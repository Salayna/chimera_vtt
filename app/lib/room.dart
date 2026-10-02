import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'assets.dart';
import 'table/chrome.dart';
import 'table/table_view.dart';
import 'theme.dart';
import 'ui/cv.dart';

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

/// A scene as a file: indented JSON, so a save is readable and diffable.
Uint8List sceneToFile(Scene scene) => utf8.encode(
    const JsonEncoder.withIndent('  ').convert(scene.toJson()));

/// Throws [FormatException] for anything that isn't a scene this version
/// can read.
Scene sceneFromFile(Uint8List bytes) {
  try {
    return Scene.fromJson(jsonDecode(utf8.decode(bytes)) as Json);
  } on FormatException {
    rethrow;
  } on Object catch (e) {
    throw FormatException('Not a Chimera scene: $e');
  }
}

/// Pictures shared by both roles until maps and tokens come from Storage.
typedef Art = ({ui.Image map, Map<AssetId, ui.Image> tokens});

/// Open a room as the GM, or join one with a room code.
class Lobby extends StatefulWidget {
  const Lobby({super.key, required this.onEnter});

  final void Function(SavedRoom room) onEnter;

  @override
  State<Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<Lobby> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _join() {
    final code = normalizeRoomCode(_code.text);
    if (code.length != 6) {
      setState(() => _error = 'Room codes have 6 characters.');
      return;
    }
    widget.onEnter((code: code, gm: false));
  }

  @override
  Widget build(BuildContext context) {
    Widget card({
      required Lucide icon,
      required CvTone tone,
      required String title,
      required String subtitle,
      required List<Widget> children,
    }) =>
        CvPanel(
          width: 360,
          padding: const EdgeInsets.all(CvSpacing.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: CvSpacing.s6,
            children: [
              Row(spacing: 10, children: [
                CvIconBadge(icon, tone: tone),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: CvTypography.title),
                  Text(subtitle,
                      style: CvTypography.bodySm
                          .copyWith(color: CvColors.textSecondary)),
                ]),
              ]),
              ...children,
            ],
          ),
        );

    return Stack(children: [
      const Positioned(left: 28, top: 24, child: CvWordmark()),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CvSpacing.s6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Gather at the table',
                textAlign: TextAlign.center, style: CvTypography.display),
            const SizedBox(height: CvSpacing.s4),
            Text('Open a room as the GM, or join one with a room code.',
                textAlign: TextAlign.center,
                style: CvTypography.body.copyWith(
                    fontSize: 16, height: 1.5, color: CvColors.textSecondary)),
            const SizedBox(height: CvSpacing.s10),
            _SideBySide(
              children: [
                card(
                  icon: Lucide.crown,
                  tone: CvTone.gm,
                  title: 'Open a room',
                  subtitle: "You'll be the GM.",
                  children: [
                    Text(
                        'You get a 6-character room code to share with your '
                        'players.',
                        style: CvTypography.body
                            .copyWith(color: CvColors.textSecondary)),
                    CvButton(
                      label: 'Create room',
                      icon: Lucide.plus,
                      variant: CvButtonVariant.primary,
                      block: true,
                      onPressed: () =>
                          widget.onEnter((code: newRoomCode(), gm: true)),
                    ),
                  ],
                ),
                card(
                  icon: Lucide.logIn,
                  tone: CvTone.player,
                  title: 'Join a room',
                  subtitle: 'As a player.',
                  children: [
                    CvTextInput(
                      controller: _code,
                      label: 'Room code',
                      placeholder: 'K7Q2XM',
                      code: true,
                      maxLength: 6,
                      error: _error,
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _join(),
                    ),
                    ListenableBuilder(
                      listenable: _code,
                      builder: (context, _) => CvButton(
                        label: 'Join',
                        icon: Lucide.logIn,
                        variant: CvButtonVariant.player,
                        block: true,
                        onPressed: _code.text.isEmpty ? null : _join,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// Equal-height cards in a row when they fit, stacked when they don't.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width >= 780
      ? IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: CvSpacing.s6,
            children: children,
          ),
        )
      : Column(spacing: CvSpacing.s6, children: children);
}

/// A full-screen state on the empty ground: waiting, opening, failed.
/// Shows a spinner in [spinner]'s colour, or [icon] when there is none.
class StatusScreen extends StatelessWidget {
  const StatusScreen({
    super.key,
    required this.title,
    this.message,
    this.spinner,
    this.icon,
    this.tone = CvTone.neutral,
    this.actions = const [],
    this.code,
    this.onLeave,
  });

  final String title;
  final String? message;
  final Color? spinner;
  final Lucide? icon;
  final CvTone tone;
  final List<Widget> actions;

  /// The room, for the chip at the top left.
  final String? code;
  final VoidCallback? onLeave;

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Positioned.fill(child: GroundGrid()),
        Center(
          child: CvPopIn(
            duration: CvMotion.slow,
            child: CvPanel(
              width: 420,
              padding: const EdgeInsets.all(CvSpacing.s8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: spinner != null
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  if (spinner case final color?) ...[
                    CvSpinner(size: 28, color: color),
                    const SizedBox(height: 14),
                  ] else if (icon case final icon?) ...[
                    CvIconBadge(icon, tone: tone),
                    const SizedBox(height: CvSpacing.s6),
                  ],
                  Text(title,
                      style: CvTypography.title,
                      textAlign: spinner != null ? TextAlign.center : null),
                  if (message case final message?) ...[
                    const SizedBox(height: 6),
                    Text(message,
                        textAlign: spinner != null ? TextAlign.center : null,
                        style: CvTypography.body
                            .copyWith(color: CvColors.textSecondary)),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: CvSpacing.s7),
                    Row(spacing: CvSpacing.s4, children: actions),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (code case final code?)
          Positioned(
              left: CvSizes.insetScreen,
              top: CvSizes.insetScreen,
              child: CvRoomCodeChip(code: code)),
        if (onLeave case final onLeave?)
          Positioned(
              right: CvSizes.insetScreen,
              top: CvSizes.insetScreen,
              child: PresenceBar(onLeave: onLeave)),
      ]);
}

/// The GM's room: hosts the session and saves the scene as it changes, so
/// a refresh resumes where it left off.
class GmRoom extends StatefulWidget {
  const GmRoom({
    super.key,
    required this.client,
    required this.assets,
    required this.me,
    required this.code,
    required this.art,
    required this.onLeave,
  });

  final SupabaseClient client;
  final AssetStore assets;
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
  final _toasts = CvToasts();
  final _saved = ValueNotifier(true);
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
        _saved.value = false;
        _saveTimer?.cancel();
        _saveTimer = Timer(saveAfter, () async {
          await _save(scene);
          _saved.value = true;
        });
      });
      if (mounted) setState(() => _host = host);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
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
    final id = TokenId(newId());
    final grid = scene.settings.grid;
    host.execute(PlaceToken(Token(
      id: id,
      position: grid.freeSpot(
          _controller.snap ? grid.snap(center, size) : center,
          size,
          scene.tokens.values),
      size: size,
      image: AssetId('token${scene.tokens.length % widget.art.tokens.length}'),
    )));
    _controller
      ..tool = Tool.move
      ..selected.value = id;
  }

  void _removeToken(TokenId id) {
    _host!.execute(RemoveToken(id));
    _controller.selected.value = null;
    _toasts.show('Token removed');
  }

  String? _uploading;

  /// Picks an image and uploads it, then hands it to [use]. [what] names
  /// it in the toasts ("Map", "Token image").
  Future<void> _uploadImage(
      String what, void Function(AssetId id, ui.Image image) use) async {
    if (_uploading != null) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final type = AssetStore.contentTypes[file.extension?.toLowerCase()];
      if (type == null) {
        _toasts.show('Use a PNG, JPEG or WebP image.', tone: CvTone.danger);
        return;
      }
      setState(() => _uploading = file.name);
      final bytes = await file.readAsBytes();
      final image = await decodeImage(bytes);
      final id = await widget.assets.upload(bytes, type);
      widget.assets.remember(id, image);
      use(id, image);
      _toasts.show('$what uploaded', tone: CvTone.ok);
    } on Object catch (e) {
      _toasts.show('$what failed to upload: $e', tone: CvTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// Makes an uploaded image the scene's map.
  Future<void> _setMap() => _uploadImage('Map', (id, image) {
        final old = _host!.store.scene.settings;
        _host!.execute(UpdateSettings(old.copyWith(
          map: id,
          width: image.width.toDouble(),
          height: image.height.toDouble(),
        )));
      });

  /// Gives a token an uploaded image.
  Future<void> _setTokenImage(TokenId token) =>
      _uploadImage('Token image', (id, _) {
        // The token may have changed (or gone) during the upload.
        final current = _host!.store.scene.tokens[token];
        if (current != null) _host!.execute(UpdateToken(current.copyWith(image: id)));
      });

  void _setCellSize(double size) {
    final host = _host!;
    final old = host.store.scene.settings;
    host.execute(UpdateSettings(
        old.copyWith(grid: Grid(cellSize: size, offset: old.grid.offset))));
  }

  void _setGridVisible(bool visible) {
    final host = _host!;
    host.execute(UpdateSettings(
        host.store.scene.settings.copyWith(gridVisible: visible)));
  }

  Future<void> _export() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'chimera-${widget.code}-${now.year}${two(now.month)}'
        '${two(now.day)}-${two(now.hour)}${two(now.minute)}.json';
    try {
      final saved = await FilePicker.saveFile(
        fileName: name,
        bytes: sceneToFile(_host!.store.scene),
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      // The web downloads without a path; elsewhere null is a cancel.
      if (saved != null || kIsWeb) {
        _toasts.show('Scene exported as $name', tone: CvTone.ok);
      }
    } on Object catch (e) {
      _toasts.show('Export failed: $e', tone: CvTone.danger);
    }
  }

  /// Replaces the scene with one from a file, after confirming: the current
  /// scene is gone unless it was exported.
  Future<void> _import() async {
    try {
      final file = await FilePicker.pickFile(
          type: FileType.custom, allowedExtensions: const ['json']);
      if (file == null) return;
      final scene = sceneFromFile(await file.readAsBytes());
      if (!mounted) return;
      final confirmed = await showCvDialog<bool>(
        context: context,
        title: 'Replace the scene?',
        icon: Lucide.fileJson,
        tone: CvTone.danger,
        body: Text.rich(TextSpan(children: [
          const TextSpan(text: 'Importing '),
          TextSpan(
              text: file.name,
              style: const TextStyle(
                  color: CvColors.textPrimary, fontWeight: FontWeight.w500)),
          const TextSpan(
              text: ' replaces the map, tokens and fog for everyone at the '
                  'table. Export first if you want to keep this scene.'),
        ])),
        actions: (context) => [
          CvButton(
              label: 'Cancel',
              variant: CvButtonVariant.ghost,
              onPressed: () => Navigator.pop(context, false)),
          CvButton(
              label: 'Replace scene',
              variant: CvButtonVariant.danger,
              onPressed: () => Navigator.pop(context, true)),
        ],
      );
      if (confirmed ?? false) {
        _host!.load(scene);
        _controller.selected.value = null;
        _toasts.show('Scene replaced for everyone', tone: CvTone.gm);
      }
    } on FormatException catch (e) {
      _toasts.show(e.message, tone: CvTone.danger);
    } on Object catch (e) {
      _toasts.show('Import failed: $e', tone: CvTone.danger);
    }
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
    _toasts.dispose();
    _saved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = _host;
    if (host == null) {
      return _error == null
          ? StatusScreen(
              title: 'Opening the room…',
              spinner: CvColors.amber500,
              code: widget.code,
              onLeave: widget.onLeave)
          : StatusScreen(
              title: 'Could not open the room.',
              message: _error,
              icon: Lucide.triangleAlert,
              tone: CvTone.danger,
              code: widget.code,
              onLeave: widget.onLeave,
              actions: [
                CvButton(
                    label: 'Try again',
                    icon: Lucide.refreshCw,
                    onPressed: _start),
              ],
            );
    }
    const pad = CvSizes.insetScreen;
    return TableShortcuts(
      controller: _controller,
      gm: true,
      onAddToken: _addToken,
      onSetMap: _setMap,
      onExport: _export,
      onImport: _import,
      onRemove: _removeToken,
      child: Stack(children: [
        Positioned.fill(
          child: TableView(
            store: host.store,
            controller: _controller,
            gm: true,
            self: widget.me,
            send: host.execute,
            map: widget.art.map,
            loadAsset: widget.assets.image,
            images: (id) => widget.art.tokens[id],
          ),
        ),
        Positioned.fill(
          child: TokenCardLayer(
            store: host.store,
            session: host,
            controller: _controller,
            send: host.execute,
            onRemove: _removeToken,
            onSetImage: _uploading == null ? _setTokenImage : null,
          ),
        ),
        Positioned(
          left: pad,
          top: pad,
          child: Row(spacing: CvSpacing.s4, children: [
            CvRoomCodeChip(code: widget.code),
            SaveStatus(saved: _saved),
          ]),
        ),
        Positioned(
          right: pad,
          top: pad,
          child: PresenceBar(session: host, onLeave: widget.onLeave),
        ),
        Positioned(
          left: pad,
          top: 0,
          bottom: 0,
          child: Center(
            child: GmRail(
              controller: _controller,
              onAddToken: _addToken,
              onSetMap: _uploading == null ? _setMap : null,
              onExport: _export,
              onImport: _import,
            ),
          ),
        ),
        Positioned(
          left: pad + CvSizes.rail + CvSpacing.s4,
          top: 0,
          bottom: 0,
          child: Center(
            child: StreamBuilder(
              stream: host.store.changes,
              initialData: host.store.scene,
              builder: (context, snap) {
                final settings = snap.requireData.settings;
                final grid = settings.grid;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: CvSpacing.s4,
                  children: [
                    GridOptions(
                        controller: _controller,
                        grid: grid,
                        visible: settings.gridVisible,
                        onCellSize: _setCellSize,
                        onVisible: _setGridVisible),
                    FogOptions(controller: _controller, grid: grid),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          right: pad,
          bottom: pad,
          child: ZoomCluster(controller: _controller, snap: true),
        ),
        if (_uploading case final name?)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0x8008090C),
              child: Center(
                child: CvPopIn(
                  duration: CvMotion.slow,
                  child: CvPanel(
                    width: 400,
                    padding: const EdgeInsets.all(CvSpacing.s8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: CvSpacing.s5,
                      children: [
                        CvProgressBar(
                            label: 'Uploading $name', color: CvColors.amber500),
                        Text('Players see it when the upload finishes.',
                            style: CvTypography.caption
                                .copyWith(color: CvColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: pad,
          child: Center(child: CvToastStack(toasts: _toasts)),
        ),
      ]),
    );
  }
}

/// A player's room: joins, waits for the GM if needed, then shows the table.
class PlayerRoom extends StatefulWidget {
  const PlayerRoom({
    super.key,
    required this.client,
    required this.assets,
    required this.me,
    required this.code,
    required this.art,
    required this.onLeave,
  });

  final SupabaseClient client;
  final AssetStore assets;
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
  bool _mismatch = false;

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
      if (mounted) setState(() => _mismatch = true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
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
    final leave = CvButton(
        label: 'Leave room',
        variant: CvButtonVariant.ghost,
        onPressed: widget.onLeave);
    if (_mismatch) {
      return StatusScreen(
        title: "This app and the GM's are different versions.",
        message: 'Update Chimera VTT, then rejoin with the same room code.',
        icon: Lucide.triangleAlert,
        tone: CvTone.gm,
        actions: [leave],
      );
    }
    if (_error case final error?) {
      return StatusScreen(
        title: 'Could not join the room.',
        message: error,
        icon: Lucide.triangleAlert,
        tone: CvTone.danger,
        code: widget.code,
        actions: [
          CvButton(label: 'Try again', icon: Lucide.refreshCw, onPressed: _start),
          leave,
        ],
      );
    }
    if (session == null || store == null) {
      return StatusScreen(
        title: session == null
            ? 'Joining…'
            : 'Waiting for the GM to open the room…',
        message: session == null
            ? null
            : "You're in. The table appears as soon as the GM arrives.",
        spinner: CvColors.teal500,
        code: widget.code,
        onLeave: widget.onLeave,
      );
    }
    const pad = CvSizes.insetScreen;
    return TableShortcuts(
      controller: _controller,
      child: Stack(children: [
        Positioned.fill(
          child: TableView(
            store: store,
            controller: _controller,
            gm: false,
            self: widget.me,
            send: session.request,
            map: widget.art.map,
            loadAsset: widget.assets.image,
            images: (id) => widget.art.tokens[id],
          ),
        ),
        Positioned(
          left: pad,
          top: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: CvSpacing.s4,
            children: [
              CvRoomCodeChip(code: widget.code),
              YourTokens(store: store, self: widget.me, controller: _controller),
            ],
          ),
        ),
        Positioned(
          right: pad,
          top: pad,
          child: PresenceBar(session: session, onLeave: widget.onLeave),
        ),
        Positioned(
          right: pad,
          bottom: pad,
          child: ZoomCluster(controller: _controller),
        ),
      ]),
    );
  }
}
