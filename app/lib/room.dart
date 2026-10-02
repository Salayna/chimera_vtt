import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'table/table_view.dart';
import 'table/toolbar.dart';

/// The room this client is in, saved so a refresh lands back in it.
typedef SavedRoom = ({String code, bool gm});

final _prefs = SharedPreferencesAsync();

Future<SavedRoom?> loadSavedRoom() async {
  final code = await _prefs.getString('room');
  final gm = await _prefs.getBool('gm');
  return code == null || gm == null ? null : (code: code, gm: gm);
}

Future<void> saveRoom(SavedRoom? room) async {
  if (room == null) {
    await _prefs.remove('room');
    await _prefs.remove('gm');
  } else {
    await _prefs.setString('room', room.code);
    await _prefs.setBool('gm', room.gm);
  }
}

/// No 0/O, 1/I/L: codes are read aloud and typed by hand.
const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String newRoomCode() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 6; i++) _codeAlphabet[random.nextInt(_codeAlphabet.length)],
  ].join();
}

String normalizeRoomCode(String input) =>
    input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// Pictures shared by both roles until maps and tokens come from Storage.
typedef Art = ({ui.Image map, Map<AssetId, ui.Image> tokens});

class Lobby extends StatefulWidget {
  const Lobby({super.key, required this.onEnter});

  final void Function(SavedRoom room) onEnter;

  @override
  State<Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<Lobby> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join() {
    final code = normalizeRoomCode(_code.text);
    if (code.length == 6) widget.onEnter((code: code, gm: false));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Chimera VTT',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () =>
                      widget.onEnter((code: newRoomCode(), gm: true)),
                  icon: const Icon(Icons.add),
                  label: const Text('Create a room (GM)'),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _code,
                  decoration: const InputDecoration(
                      labelText: 'Room code', border: OutlineInputBorder()),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _join, child: const Text('Join')),
              ],
            ),
          ),
        ),
      );
}

/// The top bar of a room: code, who is here, a way out.
class _RoomBar extends StatelessWidget {
  const _RoomBar({required this.code, required this.onLeave, this.session});

  final String code;
  final VoidCallback onLeave;
  final Session? session;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          SelectableText('Room $code',
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
          ),
          const SizedBox(width: 12),
          if (session != null) Expanded(child: PeerList(session: session!)),
          if (session == null) const Spacer(),
          TextButton.icon(
            onPressed: onLeave,
            icon: const Icon(Icons.logout),
            label: const Text('Leave'),
          ),
        ]),
      );
}

/// Shown while a room isn't usable yet, with a retry on failure.
class _Status extends StatelessWidget {
  const _Status(this.message, {this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (onRetry == null) const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

/// The GM's room: hosts the session and saves the scene as it changes, so
/// a refresh resumes where it left off.
class GmRoom extends StatefulWidget {
  const GmRoom({
    super.key,
    required this.client,
    required this.me,
    required this.code,
    required this.art,
    required this.onLeave,
  });

  final SupabaseClient client;
  final PlayerId me;
  final String code;
  final Art art;
  final VoidCallback onLeave;

  @override
  State<GmRoom> createState() => _GmRoomState();
}

class _GmRoomState extends State<GmRoom> {
  static const heartbeatEvery = Duration(seconds: 3);
  static const saveAfter = Duration(seconds: 1);

  final _controller = TableController();
  HostSession? _host;
  String? _error;
  Timer? _heartbeat;
  Timer? _saveTimer;
  StreamSubscription<Scene>? _autosave;

  String get _saveKey => 'scene:${widget.code}';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final scene = await _loadScene();
      final transport = await SupabaseTransport.join(widget.client, widget.code);
      final host = HostSession(transport, widget.me, SceneStore(scene));
      // Tell players already waiting, or still holding a previous run's
      // scene, about this one.
      host.load(scene);
      await host.setCursor(null);
      _heartbeat = Timer.periodic(heartbeatEvery, (_) => host.heartbeat());
      _autosave = host.store.changes.listen((scene) {
        _saveTimer?.cancel();
        _saveTimer = Timer(saveAfter, () => _save(scene));
      });
      if (mounted) setState(() => _host = host);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not open the room: $e');
    }
  }

  Future<Scene> _loadScene() async {
    final saved = await _prefs.getString(_saveKey);
    if (saved != null) {
      try {
        return Scene.fromJson(jsonDecode(saved) as Json);
      } on Object {
        // A save this version can't read: start fresh rather than not at all.
      }
    }
    return Scene(
      settings: SceneSettings(
        width: widget.art.map.width.toDouble(),
        height: widget.art.map.height.toDouble(),
        grid: const Grid(cellSize: 128),
      ),
    );
  }

  // ponytail: a refresh within [saveAfter] of the last change loses it.
  // Save on page hide (web) if that bites.
  Future<void> _save(Scene scene) =>
      _prefs.setString(_saveKey, jsonEncode(scene.toJson()));

  void _addToken() {
    final host = _host!;
    final scene = host.store.scene;
    final size = scene.settings.grid.cellSize;
    final center = _controller.viewCenter;
    host.execute(PlaceToken(Token(
      id: TokenId(newId()),
      position: _controller.snap
          ? scene.settings.grid.snap(center, size)
          : center,
      size: size,
      image: AssetId('token${scene.tokens.length % widget.art.tokens.length}'),
    )));
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _saveTimer?.cancel();
    _autosave?.cancel();
    if (_host case final host?) {
      _save(host.store.scene);
      host.close();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    return Scaffold(
      body: Column(children: [
        _RoomBar(code: widget.code, onLeave: widget.onLeave, session: host),
        if (host == null)
          Expanded(
            child: _Status(_error ?? 'Opening the room…',
                onRetry: _error == null ? null : _start),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GmToolbar(controller: _controller, onAddToken: _addToken),
          ),
          _SelectedToken(host: host, controller: _controller),
          Expanded(
            child: TableView(
              store: host.store,
              controller: _controller,
              gm: true,
              self: widget.me,
              send: host.execute,
              map: widget.art.map,
              images: (id) => widget.art.tokens[id],
            ),
          ),
        ],
      ]),
    );
  }
}

/// The panel for the token the GM clicked, kept current as it changes.
class _SelectedToken extends StatelessWidget {
  const _SelectedToken({required this.host, required this.controller});

  final HostSession host;
  final TableController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: controller.selected,
        builder: (context, selected, _) => StreamBuilder(
          stream: host.store.changes,
          initialData: host.store.scene,
          builder: (context, snapshot) {
            final token = snapshot.requireData.tokens[selected];
            if (token == null) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.all(8),
              child: StreamBuilder(
                stream: host.peers,
                initialData: host.currentPeers,
                builder: (context, peers) => TokenPanel(
                  token: token,
                  players: [
                    for (final p in peers.requireData)
                      if (!p.gm) PlayerId(p.player),
                  ],
                  send: host.execute,
                ),
              ),
            );
          },
        ),
      );
}

/// A player's room: joins, waits for the GM if needed, then shows the table.
class PlayerRoom extends StatefulWidget {
  const PlayerRoom({
    super.key,
    required this.client,
    required this.me,
    required this.code,
    required this.art,
    required this.onLeave,
  });

  final SupabaseClient client;
  final PlayerId me;
  final String code;
  final Art art;
  final VoidCallback onLeave;

  @override
  State<PlayerRoom> createState() => _PlayerRoomState();
}

class _PlayerRoomState extends State<PlayerRoom> {
  final _controller = TableController();
  ClientSession? _session;
  SceneStore? _store;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final transport = await SupabaseTransport.join(widget.client, widget.code);
      final session = ClientSession(transport, widget.me);
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() => _session = session);
      await session.setCursor(null);
      // Completes when the GM answers, now or once they open the room.
      final store = await session.join();
      if (mounted) setState(() => _store = store);
    } on ProtocolMismatch {
      if (mounted) {
        setState(() => _error = 'This app and the GM\'s are different versions. '
            'Reload to update.');
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Could not join the room: $e');
    }
  }

  @override
  void dispose() {
    _session?.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final store = _store;
    return Scaffold(
      body: Column(children: [
        _RoomBar(code: widget.code, onLeave: widget.onLeave, session: session),
        Expanded(
          child: session == null || store == null
              ? _Status(
                  _error ??
                      (session == null
                          ? 'Joining…'
                          : 'Waiting for the GM to open the room…'),
                  onRetry: _error == null ? null : _start,
                )
              : TableView(
                  store: store,
                  controller: _controller,
                  gm: false,
                  self: widget.me,
                  send: session.request,
                  map: widget.art.map,
                  images: (id) => widget.art.tokens[id],
                ),
        ),
      ]),
    );
  }
}
