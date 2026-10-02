import 'dart:async';

import 'package:chimera_core/chimera_core.dart';

import 'protocol.dart';
import 'transport.dart';

/// One client's live connection to a room.
sealed class Session {
  Session(this.transport, this.self, {required this.gm}) {
    _subscription = transport.messages.listen(_onJson);
  }

  final Transport transport;
  final PlayerId self;
  final bool gm;
  late final StreamSubscription<Json> _subscription;

  /// Everyone connected, from Realtime presence.
  Stream<List<Presence>> get peers =>
      transport.presence.map((states) => [
            for (final s in states) ?_tryPresence(s),
          ]);

  Future<void> setCursor(Point? cursor) => transport
      .track(presenceToJson((player: self.value, gm: gm, cursor: cursor)));

  Future<void> close() async {
    await _subscription.cancel();
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
  HostSession(super.transport, super.self, this.store) : super(gm: true);

  final SceneStore store;
  int _seq = 0;

  // Visibility depends on the role only, so every player gets the same batch
  // and one broadcast serves them all.
  // ponytail: per-player visibility (sight, a player's own hidden token)
  // needs per-player batches, sent on per-player channels.
  static const _players = Player(PlayerId(''));

  int get seq => _seq;

  /// The GM's own command. It never travels as an intent.
  Outcome execute(Command command) => _run(const Gm(), command);

  /// Replaces the scene, for example a loaded save, and sends it to everyone.
  void load(Scene scene) {
    store.replace(scene);
    // A new seq, so a stale snapshot of the old scene can't win.
    _seq++;
    _send(Snapshot(seq: _seq, scene: visibleTo(scene, _players)));
  }

  /// Call periodically (every few seconds) so players notice a missed last
  /// batch, and so lost intents expire.
  void heartbeat() => _send(Heartbeat(_seq));

  Outcome _run(Actor actor, Command command,
      {PlayerId? from, String? requestId}) {
    final before = store.scene;
    final outcome = store.execute(actor, command);
    switch (outcome) {
      case Accepted(:final patches):
        final visible = patchesFor(before, patches, _players);
        // An empty batch still answers an intent.
        if (visible.isNotEmpty || requestId != null) {
          _seq++;
          _send(PatchBatch(seq: _seq, patches: visible, requestId: requestId));
        }
      case Refused(:final reason):
        if (from != null && requestId != null) {
          _send(RefusalMessage(to: from, requestId: requestId, reason: reason));
        }
    }
    return outcome;
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
            to: from, seq: _seq, scene: visibleTo(store.scene, _players)));
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
      case Snapshot(:final to, :final seq, :final scene)
          when (to == null || to == self) && seq >= _seq:
        _seq = seq;
        _confirmed = scene;
        _resyncing = false;
        // Anything in flight is answered by a later batch or expires.
        _publish();
      case PatchBatch(:final seq, :final patches, :final requestId):
        if (_resyncing || seq <= _seq) return; // Waiting, or a late duplicate.
        if (seq > _seq + 1) return _resync();
        _seq = seq;
        _confirmed = _confirmed!.applyPatches(patches);
        if (requestId != null) _settle(requestId);
        _publish();
      case Heartbeat(:final seq):
        _beats++;
        final before = _pending.length;
        _pending.removeWhere((_, p) => _beats - p.$2 >= intentLifetime);
        if (seq > _seq || _resyncing) {
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
