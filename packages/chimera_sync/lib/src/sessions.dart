import 'dart:async';
import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';

import 'events.dart';
import 'protocol.dart';
import 'transport.dart';

/// One client's live connection to a room.
sealed class Session {
  Session(this.transport, this.self, {required this.gm}) {
    _subscription = transport.messages.listen(_onJson);
    _presenceSubscription = transport.presence.listen((states) {
      // One entry per player: after a reload, the old connection lingers in
      // presence until the server notices it's gone.
      final all = [for (final s in states) ?_tryPresence(s)];
      _peers = {for (final p in all) p.player: p}.values.toList();
      _peersController.add(_peers);
    });
  }

  final Transport transport;
  final PlayerId self;
  final bool gm;
  late final StreamSubscription<Json> _subscription;
  late final StreamSubscription<List<Json>> _presenceSubscription;
  final _peersController = StreamController<List<Presence>>.broadcast();
  List<Presence> _peers = const [];
  final _eventsController = StreamController<TableEvent>.broadcast();
  List<TableEvent> _log = const [];
  final _logController = StreamController<List<TableEvent>>.broadcast();

  /// How many logged events the GM keeps and sends to someone joining.
  // ponytail: the log lives in the GM's session and goes when they reload;
  // store it with the campaign if it should outlast that.
  static const logLimit = 200;

  /// The room's log, oldest first: rolls, chat, condition changes.
  List<TableEvent> get currentLog => _log;

  /// [currentLog] on every change.
  Stream<List<TableEvent>> get log => _logController.stream;

  /// Every new event as it arrives, pings included.
  Stream<TableEvent> get events => _eventsController.stream;

  void _receive(List<TableEvent> events) {
    if (events.isEmpty) return;
    events.forEach(_eventsController.add);
    if (events.any((e) => e.logged)) {
      _setLog([..._log, ...events.where((e) => e.logged)]);
    }
  }

  void _setLog(List<TableEvent> log) {
    _log = List.unmodifiable(log.length > logLimit
        ? log.sublist(log.length - logLimit)
        : log);
    _logController.add(_log);
  }

  /// Everyone connected now, from presence, this client included once it
  /// called [setCursor].
  List<Presence> get currentPeers => _peers;

  /// [currentPeers] on every change.
  Stream<List<Presence>> get peers => _peersController.stream;

  Point? _cursor;
  Ruler? _ruler;

  Future<void> setCursor(Point? cursor) {
    _cursor = cursor;
    return _track();
  }

  /// Shows everyone the ruler this client is dragging, or none. Each call
  /// is a presence message: throttle a drag.
  Future<void> setRuler(Ruler? ruler) {
    _ruler = ruler;
    return _track();
  }

  Future<void> _track() => transport.track(presenceToJson(
      (player: self.value, gm: gm, cursor: _cursor, ruler: _ruler)));

  Future<void> close() async {
    await _subscription.cancel();
    await _presenceSubscription.cancel();
    await _peersController.close();
    await _eventsController.close();
    await _logController.close();
    await transport.close();
  }

  void _send(Message message) =>
      // Best effort: a failed send is a lost message, which the protocol
      // recovers from.
      transport.send(message.toJson()).ignore();

  void _onJson(Json json);
}

Presence? _tryPresence(Json json) {
  try {
    return presenceFromJson(json);
  } on Object {
    return null;
  }
}

/// The GM's session: the authority. It reduces every command, applies it,
/// and sends players their filtered patches.
final class HostSession extends Session {
  /// [log] is the stored log to start from, oldest first. [onLogged] gets
  /// every new logged event, secret ones included, to store it.
  HostSession(super.transport, super.self, this.store,
      {math.Random? random,
      int Function()? clock,
      List<TableEvent> log = const [],
      this.onLogged})
      : _random = random ?? math.Random.secure(),
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        super(gm: true) {
    _setLog(log);
  }

  final SceneStore store;
  final void Function(TableEvent event)? onLogged;

  /// The log players may see: everything but the GM's secret rolls.
  List<TableEvent> get _playersLog =>
      [for (final e in currentLog) if (!e.secret) e];

  /// Rolls every die at the table, the players' included.
  final math.Random _random;
  final int Function() _clock;

  /// This run of the session. See [Snapshot.epoch].
  final String epoch = newId();
  int _seq = 0;

  // Visibility depends on the role only, so every player gets the same batch
  // and one broadcast serves them all.
  // ponytail: per-player visibility (sight, a player's own hidden token)
  // needs per-player batches, sent on per-player channels.
  static const _players = Player(PlayerId(''));

  int get seq => _seq;

  /// How many of the GM's own changes [undo] can take back.
  static const historyLimit = 100;

  // Each entry is the patches that take one change back (or redo it).
  final _undo = <List<Patch>>[];
  final _redo = <List<Patch>>[];
  Command? _last;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// The GM's own command. It never travels as an intent, and it is the only
  /// thing that enters undo history: players' moves don't.
  Outcome execute(Command command) {
    final before = store.scene;
    final outcome = _run(const Gm(), command);
    if (outcome case Accepted(:final patches) when patches.isNotEmpty) {
      // Typing a name sends one edit per key: keep them as one step.
      // ponytail: any run of edits to one token is one step, size included.
      final typing = command is UpdateToken &&
          _last is UpdateToken &&
          (_last! as UpdateToken).token.id == command.token.id &&
          _undo.isNotEmpty;
      if (!typing) {
        _undo.add(invert(before, patches));
        if (_undo.length > historyLimit) _undo.removeAt(0);
      }
      _redo.clear();
      _last = command;
    }
    return outcome;
  }

  /// Takes back the GM's last change. False if there is nothing to undo.
  bool undo() => _step(_undo, _redo);

  /// Puts back the last change [undo] took back.
  bool redo() => _step(_redo, _undo);

  // ponytail: undo restores whole entities, so undoing the GM's edit to a
  // token also reverts a player's move of it made since.
  bool _step(List<List<Patch>> from, List<List<Patch>> to) {
    if (from.isEmpty) return false;
    final patches = from.removeLast();
    final before = store.scene;
    to.add(invert(before, patches));
    store.apply(patches);
    _broadcast(before, patches);
    _last = null;
    return true;
  }

  /// Replaces the scene, for example a loaded save, and sends it to everyone.
  void load(Scene scene) {
    _undo.clear();
    _redo.clear();
    _last = null;
    store.replace(scene);
    // A new seq, so a stale snapshot of the old scene can't win.
    _seq++;
    _send(Snapshot(
        epoch: epoch,
        seq: _seq,
        scene: visibleTo(scene, _players),
        log: _playersLog));
  }

  /// Call periodically (every few seconds) so players notice a missed last
  /// batch, and so lost intents expire.
  void heartbeat() => _send(Heartbeat(epoch, _seq));

  Outcome _run(Actor actor, Command command,
      {PlayerId? from, String? requestId}) {
    final before = store.scene;
    final outcome = store.execute(actor, command);
    switch (outcome) {
      case Accepted(:final patches):
        final event = _eventFor(from ?? self, before, command);
        _broadcast(before, patches,
            requestId: requestId,
            events: [if (event != null && !event.secret) event]);
        _receive([?event]);
        if (event != null && event.logged) onLogged?.call(event);
      case Refused(:final reason):
        if (from != null && requestId != null) {
          _send(RefusalMessage(to: from, requestId: requestId, reason: reason));
        }
    }
    return outcome;
  }

  /// Sends players their part of [patches], applied to [before].
  void _broadcast(Scene before, List<Patch> patches,
      {String? requestId, List<TableEvent> events = const []}) {
    final visible = patchesFor(before, patches, _players);
    // An empty batch still answers an intent.
    if (visible.isNotEmpty || requestId != null || events.isNotEmpty) {
      _seq++;
      _send(PatchBatch(
          epoch: epoch,
          seq: _seq,
          patches: visible,
          requestId: requestId,
          events: events));
    }
  }

  /// What an accepted [command] by [by] tells the table. Moves and the
  /// GM's scene edits tell nothing.
  TableEvent? _eventFor(PlayerId by, Scene before, Command command) {
    final at = _clock();
    final gm = by == self;
    switch (command) {
      case RollDice(:final formula, :final secret):
        final dice = DiceFormula.tryParse(formula)!; // The reducer checked.
        final faces = dice.roll(_random);
        return Roll(by, at,
            formula: '$dice',
            faces: faces,
            total: dice.total(faces),
            gm: gm,
            secret: secret);
      case Say(:final text):
        return Chat(by, at, text.trim(), gm: gm);
      case Ping(at: final point):
        return PingEvent(by, at, point, gm: gm);
      case SetCondition(:final id, :final name) ||
            RemoveCondition(:final id, :final name):
        final token = before.tokens[id]!; // The reducer checked.
        final value = command is SetCondition ? command.value : null;
        final removed = command is RemoveCondition;
        if (!removed &&
            token.conditions.containsKey(name) &&
            token.conditions[name] == value) {
          return null; // No change.
        }
        return ConditionChange(by, at,
            token: token.name,
            condition: name,
            value: value,
            removed: removed,
            gm: gm,
            // Players don't know a hidden token exists.
            secret: token.hidden);
      default:
        return null;
    }
  }

  @override
  void _onJson(Json json) {
    final Message message;
    try {
      message = Message.fromJson(json);
    } on Object {
      return; // Malformed or another protocol version: players are untrusted.
    }
    switch (message) {
      case RequestSnapshot(:final from):
        _send(Snapshot(
            to: from,
            epoch: epoch,
            seq: _seq,
            scene: visibleTo(store.scene, _players),
            log: _playersLog));
      case Intent(:final from, :final requestId, :final command):
        final Command decoded;
        try {
          decoded = Command.fromJson(command);
        } on Object {
          _send(RefusalMessage(
              to: from, requestId: requestId, reason: Refusal.invalid));
          return;
        }
        _run(Player(from), decoded, from: from, requestId: requestId);
      case Snapshot() || PatchBatch() || Heartbeat() || RefusalMessage():
        break; // Only the host sends these.
    }
  }
}

/// A player's session. It applies what the GM sends, shows the player's own
/// commands at once, and resyncs after a gap.
final class ClientSession extends Session {
  ClientSession(super.transport, super.self) : super(gm: false);

  /// How many heartbeats an intent may wait for its answer before it counts
  /// as lost and its optimistic copy is dropped.
  static const intentLifetime = 2;

  final _joined = Completer<SceneStore>();
  SceneStore? _store;
  Scene? _confirmed;
  String? _epoch;
  int _seq = -1;
  bool _resyncing = true;
  int _beats = 0;

  /// Intents awaiting an answer, oldest first, with the beat they were sent.
  final _pending = <String, (Command, int)>{};

  /// Asks for the scene. Completes with the player's store once the first
  /// snapshot arrives, or fails with [ProtocolMismatch].
  Future<SceneStore> join() {
    _send(RequestSnapshot(self));
    return _joined.future;
  }

  /// The player's view: the GM's filtered scene plus pending own commands.
  SceneStore get store =>
      _store ?? (throw StateError('Wait for join() before using the store'));

  bool get resyncing => _resyncing;
  int get pendingCount => _pending.length;

  /// Applies [command] at once if it looks valid, and asks the GM for it.
  /// A local refusal is returned without sending anything.
  Outcome request(Command command) {
    final outcome = reduce(store.scene, Player(self), command);
    if (outcome is Accepted) {
      final requestId = newId();
      _pending[requestId] = (command, _beats);
      _send(Intent(from: self, requestId: requestId, command: command.toJson()));
      _publish();
    }
    return outcome;
  }

  @override
  void _onJson(Json json) {
    final Message message;
    try {
      message = Message.fromJson(json);
    } on ProtocolMismatch catch (e) {
      // ponytail: a mismatch after joining (the GM upgraded mid-session)
      // isn't reported; the player stops receiving updates.
      if (!_joined.isCompleted) _joined.completeError(e);
      return;
    } on Object {
      return;
    }
    switch (message) {
      case Snapshot(
              :final to,
              :final epoch,
              :final seq,
              :final scene,
              :final log
            )
          when (to == null || to == self) && (epoch != _epoch || seq >= _seq):
        _epoch = epoch;
        _seq = seq;
        _confirmed = scene;
        // Events missed during a gap come back in the log; pings are gone.
        _setLog(log);
        _resyncing = false;
        // Anything in flight is answered by a later batch or expires.
        _publish();
      case PatchBatch(
          :final epoch,
          :final seq,
          :final patches,
          :final requestId,
          :final events
        ):
        if (_resyncing) return;
        if (epoch != _epoch) return _resync(); // The GM restarted.
        if (seq <= _seq) return; // A late duplicate.
        if (seq > _seq + 1) return _resync();
        _seq = seq;
        _confirmed = _confirmed!.applyPatches(patches);
        if (requestId != null) _settle(requestId);
        _publish();
        _receive(events);
      case Heartbeat(:final epoch, :final seq):
        _beats++;
        final before = _pending.length;
        _pending.removeWhere((_, p) => _beats - p.$2 >= intentLifetime);
        if (epoch != _epoch || seq > _seq || _resyncing) {
          _resync();
        } else if (_pending.length != before) {
          _publish();
        }
      case RefusalMessage(:final to, :final requestId) when to == self:
        if (_pending.remove(requestId) != null) _publish();
      case _:
        break; // Intents from other players, others' snapshots and refusals.
    }
  }

  void _resync() {
    _resyncing = true;
    _send(RequestSnapshot(self));
  }

  /// The GM handles intents in order, so an answer to [requestId] means
  /// every older intent was answered too, or lost.
  void _settle(String requestId) {
    if (!_pending.containsKey(requestId)) return;
    final settled = _pending.keys.takeWhile((k) => k != requestId).toList()
      ..add(requestId);
    settled.forEach(_pending.remove);
  }

  void _publish() {
    var view = _confirmed!;
    for (final (command, _) in _pending.values) {
      if (reduce(view, Player(self), command) case Accepted(:final patches)) {
        view = view.applyPatches(patches);
      }
    }
    if (_store case final store?) {
      store.replace(view);
    } else {
      _joined.complete(_store = SceneStore(view));
    }
  }
}
