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
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;
import 'package:tactical_engine/tactical_engine.dart'
    show SystemPack, TokenTemplate, builtInPacks;

import 'account.dart';
import 'assets.dart';
import 'campaigns.dart';
import 'characters.dart';
import 'home.dart';
import 'library.dart';
import 'members.dart';
import 'packs.dart';
import 'table/chrome.dart';
import 'table/grid_align.dart';
import 'table/initiative.dart';
import 'table/log_panel.dart';
import 'table/pack_tokens.dart';
import 'table/room_characters.dart';
import 'table/rules.dart';
import 'table/table_view.dart';
import 'theme.dart';
import 'ui/cv.dart';

/// The room this client is in, saved so a refresh lands back in it. A GM's
/// room is a campaign's.
typedef SavedRoom = ({String code, bool gm, String? campaign});

final _prefs = SharedPreferencesAsync();

Future<SavedRoom?> loadSavedRoom() async {
  final code = await _prefs.getString('room');
  final gm = await _prefs.getBool('gm');
  final campaign = await _prefs.getString('campaign');
  if (code == null || gm == null) return null;
  // A GM room from before campaigns: back to the lobby.
  if (gm && campaign == null) return null;
  return (code: code, gm: gm, campaign: campaign);
}

Future<void> saveRoom(SavedRoom? room) async {
  if (room == null) {
    await _prefs.remove('room');
    await _prefs.remove('gm');
    await _prefs.remove('campaign');
  } else {
    await _prefs.setString('room', room.code);
    await _prefs.setBool('gm', room.gm);
    if (room.campaign case final id?) {
      await _prefs.setString('campaign', id);
    } else {
      await _prefs.remove('campaign');
    }
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
/// Without the players' characters, which their owners keep.
Uint8List sceneToFile(Scene scene) => utf8.encode(
    const JsonEncoder.withIndent('  ').convert(scene.withCharacters(const {}).toJson()));

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

/// Open a room as the GM (signed in), or join one with a room code.
class Lobby extends StatelessWidget {
  const Lobby({
    super.key,
    required this.client,
    required this.assets,
    required this.onEnter,
    this.code,
  });

  final SupabaseClient client;
  final AssetStore assets;
  final void Function(SavedRoom room) onEnter;

  /// From a join link: fills in the room code.
  final String? code;

  @override
  Widget build(BuildContext context) => GmAccount(
        client: client,
        builder: (context, gm) => gm == null
            ? _SignedOut(client: client, onEnter: onEnter, code: code)
            : GmHome(
                client: client,
                assets: assets,
                email: gm.email,
                onEnter: onEnter,
                code: code,
              ),
      );
}

/// Nobody signed in: sign in to run a campaign, or join one as a player.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.client, required this.onEnter, this.code});

  final SupabaseClient client;
  final void Function(SavedRoom room) onEnter;
  final String? code;

  @override
  Widget build(BuildContext context) {
    Widget card({
      required Lucide icon,
      required CvTone tone,
      required String title,
      required String subtitle,
      required Widget child,
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
              child,
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
            Text('Run a campaign as the GM, or join one with a room code.',
                textAlign: TextAlign.center,
                style: CvTypography.body.copyWith(
                    fontSize: 16, height: 1.5, color: CvColors.textSecondary)),
            const SizedBox(height: CvSpacing.s10),
            _SideBySide(
              children: [
                card(
                  icon: Lucide.crown,
                  tone: CvTone.gm,
                  title: 'Run a campaign',
                  subtitle: "You'll be the GM.",
                  child: GmSignIn(client: client),
                ),
                card(
                  icon: Lucide.logIn,
                  tone: CvTone.player,
                  title: 'Join a room',
                  subtitle: 'As a player.',
                  child: JoinRoomForm(client: client, onEnter: onEnter, code: code),
                ),
              ],
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// A room code, a name and a colour: enters a campaign's room as a player.
class JoinRoomForm extends StatefulWidget {
  const JoinRoomForm(
      {super.key, required this.client, required this.onEnter, this.code});

  final SupabaseClient client;
  final void Function(SavedRoom room) onEnter;
  final String? code;

  @override
  State<JoinRoomForm> createState() => _JoinRoomFormState();
}

class _JoinRoomFormState extends State<JoinRoomForm> {
  late final _code = TextEditingController(text: widget.code);
  final _name = TextEditingController();
  var _color = 0;
  String? _error;
  String? _nameError;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    // The name and colour this player used last time.
    _prefs.getString('playerName').then((name) {
      if (name != null && mounted && _name.text.isEmpty) _name.text = name;
    });
    _prefs.getInt('playerColor').then((color) {
      if (color != null && mounted) setState(() => _color = color);
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = normalizeRoomCode(_code.text);
    if (code.length != 6) {
      setState(() => _error = 'Room codes have 6 characters.');
      return;
    }
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Tell the table who you are.');
      return;
    }
    setState(() => _joining = true);
    try {
      final campaign = await joinCampaign(widget.client, code, name, _color);
      if (campaign == null) {
        if (mounted) setState(() => _error = 'No campaign has this room code.');
        return;
      }
      await _prefs.setString('playerName', name);
      await _prefs.setInt('playerColor', _color);
      widget.onEnter((code: code, gm: false, campaign: campaign));
    } on PostgrestException catch (e) {
      // unique_violation: another player at this table has the name.
      if (mounted) {
        setState(() => e.code == '23505'
            ? _nameError = 'Someone at this table already goes by $name.'
            : _error = e.message);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: CvSpacing.s6,
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
          CvTextInput(
            controller: _name,
            label: 'Your name',
            placeholder: 'Aria',
            maxLength: 40,
            error: _nameError,
            onChanged: (_) => setState(() => _nameError = null),
            onSubmitted: (_) => _join(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text('Your colour',
                  style: CvTypography.label
                      .copyWith(color: CvColors.textSecondary)),
              ColorPicker(
                  value: _color, onChanged: (c) => setState(() => _color = c)),
            ],
          ),
          ListenableBuilder(
            listenable: _code,
            builder: (context, _) => CvButton(
              label: 'Join',
              icon: Lucide.logIn,
              variant: CvButtonVariant.player,
              block: true,
              onPressed: _code.text.isEmpty || _joining ? null : _join,
            ),
          ),
        ],
      );
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

/// The GM's room: hosts a campaign's session and saves its live scene to
/// Postgres as it changes, so a refresh resumes where it left off.
class GmRoom extends StatefulWidget {
  const GmRoom({
    super.key,
    required this.client,
    required this.assets,
    required this.me,
    required this.code,
    required this.campaign,
    required this.art,
    required this.onLeave,
  });

  final SupabaseClient client;
  final AssetStore assets;
  final PlayerId me;
  final String code;

  /// The campaign's id: its scenes are this room's.
  final String campaign;
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

  late final _scenes = Scenes(widget.client, widget.campaign);
  late final _characters = SavedCharacters(widget.client);

  /// The character whose sheet is open.
  CharacterId? _sheet;

  /// The live scene, which autosave writes to.
  String? _sceneId;
  List<SceneEntry> _sceneList = [];
  bool _scenesOpen = false;
  bool _membersOpen = false;
  StreamSubscription<Set<String>>? _peers;
  StreamSubscription<TableEvent>? _pings;
  VoidCallback? _stopRulers;

  /// The save waiting for [saveAfter] to pass, already bound to its scene.
  Future<void> Function()? _pendingSave;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onGridOptions);
    _start();
  }

  /// Opening a panel by the rail closes the others: one at a time.
  void _closePanels() {
    _scenesOpen = false;
    _membersOpen = false;
    _libraryOpen = null;
    _tokenImageFor = null;
    if (_controller.gridOptions) _controller.toggleGridOptions();
  }

  /// The grid panel opens from the controller (its key, G), so it closes the
  /// others as it opens.
  bool _gridWasOpen = false;
  void _onGridOptions() {
    final open = _controller.gridOptions;
    if (open && !_gridWasOpen) {
      setState(() {
        _scenesOpen = false;
        _membersOpen = false;
        _libraryOpen = null;
        _tokenImageFor = null;
      });
    }
    _gridWasOpen = open;
  }

  /// The system the campaign is played with, by pack id. Every scene is
  /// put on it as it opens.
  String _system = SceneSettings.defaultPack;

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      await _loadPacks();
      _system = await Campaigns(widget.client).system(widget.campaign);
      final scene = _onSystem(await _loadScene())
          .withCharacters(await _linkedCharacters());
      final log = LogEntries(widget.client, widget.campaign);
      final stored = await log.recent();
      final transport = await SupabaseTransport.join(widget.client, widget.code);
      final host = HostSession(
        transport,
        widget.me,
        SceneStore(scene),
        log: stored,
        onLogged: (e) => log.add(e,
            onError: (Object error) {
              if (mounted) {
                _toasts.show('A log entry failed to save: $error',
                    tone: CvTone.danger);
              }
            }),
      );
      // Tell players already waiting, or still holding a previous run's
      // scene, about this one.
      host.load(scene);
      await host.setCursor(null);
      _heartbeat = Timer.periodic(heartbeatEvery, (_) => host.heartbeat());
      _autosave = host.store.changes.listen((scene) {
        // Bound now: a switch before the timer fires mustn't send this
        // scene's changes to the next one.
        final id = _sceneId!;
        _saved.value = false;
        _saveTimer?.cancel();
        _pendingSave = () => _scenes.save(id, scene);
        _saveTimer = Timer(saveAfter, _flushSave);
      });
      // Someone new at the table may be a new member: reload the names.
      _peers = host.peers.map(peerIds).distinct(sameIds).listen((_) => _loadMembers());
      _pings = showPings(host, _controller);
      _stopRulers = shareRulers(host, _controller);
      await _loadMembers();
      if (mounted) setState(() => _host = host);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The players' characters linked to the campaign, as their owners last
  /// saved them. They span scenes, so the room keeps them from then on.
  Future<Map<CharacterId, Character>> _linkedCharacters() async {
    try {
      return {
        for (final c in await _characters.linked(widget.campaign))
          if (c.system == _system) c.id: c,
      };
    } on Object catch (e) {
      _toasts.show('Characters failed to load: $e', tone: CvTone.danger);
      return const {};
    }
  }

  Future<void> _loadMembers() async {
    try {
      await loadMembers(widget.client, widget.campaign);
    } on Object catch (e) {
      if (mounted) _toasts.show('Players failed to load: $e', tone: CvTone.danger);
    }
  }

  // ponytail: a removed player still connected stays until they leave;
  // changing the room code is what keeps them out.
  Future<void> _removeMember(PlayerId player, Member member) async {
    final confirmed = await showCvDialog<bool>(
      context: context,
      title: 'Remove ${member.name}?',
      icon: Lucide.userRound,
      tone: CvTone.danger,
      body: const Text('They leave the players list, and their tokens lose '
          'their owner. With the room code they can join again: change the '
          'code from the lobby to keep them out.'),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Remove',
            variant: CvButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (!(confirmed ?? false)) return;
    try {
      await removeMember(widget.client, widget.campaign, player);
      final host = _host!;
      for (final t in host.store.scene.tokens.values) {
        if (t.owner == player) host.execute(AssignOwner(t.id, null));
      }
      await _loadMembers();
    } on Object catch (e) {
      _toasts.show('${member.name} failed to remove: $e', tone: CvTone.danger);
    }
  }

  /// The live scene: the one set as live, else the first, else a new one.
  Future<Scene> _loadScene() async {
    var list = await _scenes.list();
    var id = await _scenes.live();
    if (!list.any((s) => s.id == id)) id = list.firstOrNull?.id;
    final Scene scene;
    if (id == null) {
      scene = _blankScene();
      id = await _scenes.create('Scene 1', scene);
      list = [(id: id, name: 'Scene 1')];
    } else {
      scene = await _scenes.load(id);
    }
    await _scenes.setLive(id);
    _sceneId = id;
    _sceneList = list;
    return scene;
  }

  Scene _blankScene() => Scene(
        settings: SceneSettings(
          width: widget.art.map.width.toDouble(),
          height: widget.art.map.height.toDouble(),
          grid: const Grid(cellSize: 128),
        ),
      );

  // ponytail: a refresh within [saveAfter] of the last change loses it.
  // Save on page hide (web) if that bites.
  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    final save = _pendingSave;
    _pendingSave = null;
    if (save == null) return;
    try {
      await save();
      if (mounted) _saved.value = _pendingSave == null;
    } on Object catch (e) {
      if (mounted) {
        _toasts.show('The scene failed to save: $e', tone: CvTone.danger);
      }
    }
  }

  /// Makes [id] the live scene: saves this one, then shows that one to
  /// everyone at the table.
  Future<void> _switchScene(String id, {Scene? scene}) async {
    if (id == _sceneId) return;
    try {
      await _flushSave();
      final next = _onSystem(scene ?? await _scenes.load(id))
          .withCharacters(_host!.store.scene.characters);
      _sceneId = id;
      _host!.load(next);
      _controller.selected.value = null;
      await _scenes.setLive(id);
      if (mounted) setState(() {});
    } on Object catch (e) {
      _toasts.show('The scene failed to open: $e', tone: CvTone.danger);
    }
  }

  /// A new scene: blank, or [from] a library scene's copy, named after it.
  Future<void> _newScene({LibraryEntry? from}) async {
    final names = {for (final s in _sceneList) s.name};
    String unique(String stem) {
      // A blank scene counts on from the list; a copy from its own name.
      var n = from == null ? _sceneList.length + 1 : 2;
      while (names.contains('$stem $n')) {
        n++;
      }
      return '$stem $n';
    }

    final name = switch (from?.name) {
      final n? when !names.contains(n) => n,
      final n => unique(n ?? 'Scene'),
    };
    try {
      final scene =
          from == null ? _blankScene() : await _library.sceneCopy(from.id);
      final id = await _scenes.create(name, scene);
      setState(() => _sceneList = [..._sceneList, (id: id, name: name)]);
      await _switchScene(id, scene: scene);
    } on Object catch (e) {
      _toasts.show('The scene failed to create: $e', tone: CvTone.danger);
    }
  }

  Future<void> _saveSceneToLibrary() async {
    final name = _sceneList.where((s) => s.id == _sceneId).firstOrNull?.name;
    try {
      await _library.addScene(name ?? 'Scene', _host!.store.scene);
      setState(() => _libraryRevision++);
      _toasts.show('${name ?? 'Scene'} saved to your library', tone: CvTone.ok);
    } on Object catch (e) {
      _toasts.show('The scene failed to save to the library: $e',
          tone: CvTone.danger);
    }
  }

  Future<void> _renameScene(String name) async {
    final id = _sceneId;
    if (id == null || name.isEmpty) return;
    setState(() => _sceneList = [
          for (final s in _sceneList) s.id == id ? (id: id, name: name) : s,
        ]);
    try {
      await _scenes.rename(id, name);
    } on Object catch (e) {
      _toasts.show('The scene failed to rename: $e', tone: CvTone.danger);
    }
  }

  Future<void> _deleteScene(SceneEntry scene) async {
    final confirmed = await showCvDialog<bool>(
      context: context,
      title: 'Delete ${scene.name}?',
      icon: Lucide.trash2,
      tone: CvTone.danger,
      body: const Text('Its map, tokens and fog are gone for good. '
          'Export it first if you might want it back.'),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Delete scene',
            variant: CvButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (!(confirmed ?? false)) return;
    try {
      await _scenes.delete(scene.id);
      setState(() =>
          _sceneList = [for (final s in _sceneList) if (s.id != scene.id) s]);
    } on Object catch (e) {
      _toasts.show('The scene failed to delete: $e', tone: CvTone.danger);
    }
  }

  /// The scene's pack with its tokens: the GM's installed copy, since a
  /// scene carries its pack without them.
  SystemPack _fullPack(Scene scene) {
    final pack = packOf(scene);
    return _packs.where((p) => p.id == pack.id).firstOrNull ?? pack;
  }

  /// Places one of the pack's tokens, ready to run, like [_addToken].
  void _placeTemplate(TokenTemplate template) {
    final host = _host!;
    final scene = host.store.scene;
    final grid = scene.settings.grid;
    final size = template.size * grid.cellSize;
    final center = _controller.viewCenter;
    final id = TokenId(newId());
    host.execute(PlaceToken(tokenFrom(
      template,
      id: id,
      position: grid.freeSpot(
          _controller.snap ? grid.snap(center, size) : center, size, scene.tokens.values),
      cellSize: grid.cellSize,
      image: switch (template.image) {
        final image? => AssetId(image),
        null => AssetId('token${scene.tokens.length % widget.art.tokens.length}'),
      },
    )));
    _controller
      ..tool = Tool.move
      ..selected.value = id;
  }

  /// Places a token in the nearest free cell to the middle of the view:
  /// with [image] from the library, or one of the stand-in portraits.
  void _addToken({AssetId? image}) {
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
      image: image ??
          AssetId('token${scene.tokens.length % widget.art.tokens.length}'),
    )));
    _controller
      ..tool = Tool.move
      ..selected.value = id;
  }

  /// Copies a token into the nearest free cell, numbered, and selects it.
  void _duplicateToken(TokenId id) {
    final host = _host!;
    final scene = host.store.scene;
    final token = scene.tokens[id];
    if (token == null) return;
    final copy = token.copyWith(
      id: TokenId(newId()),
      position: scene.settings.grid
          .freeSpot(token.position, token.size, scene.tokens.values),
      name: nextName(token.name, [for (final t in scene.tokens.values) t.name]),
    );
    host.execute(PlaceToken(copy));
    _controller.selected.value = copy.id;
  }

  void _removeToken(TokenId id) {
    _host!.execute(RemoveToken(id));
    _controller.selected.value = null;
    _toasts.show('Token removed');
  }

  /// What the GM is waiting for ("Uploading tavern.jpg"), shown over the
  /// table; null when nothing is.
  String? _uploading;

  /// The library panel open beside the rail, if any.
  LibraryKind? _libraryOpen;

  /// Bumped when an upload lands in the library, so an open panel reloads.
  int _libraryRevision = 0;

  /// The token the token library is choosing an image for, if any; else
  /// picking places a new token.
  TokenId? _tokenImageFor;

  void _toggleLibrary(LibraryKind kind) => setState(() {
        final open = _libraryOpen != kind;
        // The scene library opens from the scenes panel, beside it.
        final scenes = _scenesOpen && kind == LibraryKind.scene;
        _closePanels();
        _scenesOpen = scenes;
        if (open) _libraryOpen = kind;
      });

  void _closeLibrary() => setState(() {
        _libraryOpen = null;
        _tokenImageFor = null;
      });

  /// The token strip shows the pack's tokens rather than the images.
  bool _stripPack = false;

  /// The token library, a strip above the dock. It stays open while the GM
  /// places tokens, so they see each land; giving one token an image closes
  /// it. Placing new tokens, it can show the pack's tokens instead.
  Widget _tokenStrip(HostSession host) {
    final pack = _tokenImageFor == null ? _fullPack(host.store.scene) : null;
    final toggle = pack == null || pack.tokens.isEmpty
        ? null
        : SizedBox(
            width: 240,
            child: CvSegmentedControl<bool>(
              value: _stripPack,
              onChanged: (v) => setState(() => _stripPack = v),
              segments: [
                (value: false, label: 'Images', icon: Lucide.imageUp, checked: null),
                (value: true, label: pack.name, icon: Lucide.bookOpen, checked: null),
              ],
            ),
          );
    // Beside the log if it fits there, else across the table.
    final across = MediaQuery.sizeOf(context).width - 2 * CvSizes.insetScreen;
    final beside = across - LogPanel.width - CvSpacing.s4;
    return SizedBox(
      width: min(720, beside >= 560 ? beside : across),
      child: toggle != null && _stripPack
          ? PackTokensPanel(
              pack: pack!,
              strip: true,
              leading: toggle,
              onClose: _closeLibrary,
              onPick: _placeTemplate,
            )
          : LibraryPanel(
          library: _library,
          assets: widget.assets,
          kind: LibraryKind.token,
          strip: true,
          title: switch (host.store.scene.tokens[_tokenImageFor]) {
            null => 'Tokens',
            final t =>
              t.name.isEmpty ? 'Image for the token' : 'Image for ${t.name}',
          },
          hint: 'Token images you upload are kept here, for every campaign.',
          revision: _libraryRevision,
          onClose: _closeLibrary,
          onPick: (e) => _useTokenImage(e.asset!),
          footer: [
            ?toggle,
            if (_tokenImageFor == null)
              CvButton(
                label: 'Blank token',
                icon: Lucide.circlePlus,
                variant: CvButtonVariant.ghost,
                small: true,
                onPressed: _addToken,
              ),
            CvButton(
              label: 'Upload',
              icon: Lucide.imageUp,
              small: true,
              onPressed: _uploading == null ? _uploadTokenImage : null,
            ),
          ],
        ),
    );
  }

  /// The [kind] library's panels, for the pop-up.
  List<Widget> _libraryPopup(LibraryKind kind, HostSession host) => switch (kind) {
        LibraryKind.map => [
            LibraryPanel(
              library: _library,
              assets: widget.assets,
              kind: LibraryKind.map,
              title: 'Maps',
              hint: 'Maps you upload are kept here, for every campaign.',
              revision: _libraryRevision,
              onClose: _closeLibrary,
              onPick: (e) {
                _closeLibrary();
                _useMap(e);
              },
              footer: [
                CvButton(
                  label: 'Upload new map',
                  icon: Lucide.imageUp,
                  small: true,
                  block: true,
                  onPressed: _uploading == null
                      ? () => _setMap().then((_) => _closeLibrary())
                      : null,
                ),
              ],
            ),
          ],
        LibraryKind.token => const [],
        LibraryKind.scene => [
            LibraryPanel(
              library: _library,
              assets: widget.assets,
              kind: LibraryKind.scene,
              title: 'Library scenes',
              hint: 'Save a scene to your library to start new scenes from '
                  'it, in any campaign.',
              revision: _libraryRevision,
              onClose: _closeLibrary,
              onPick: (e) {
                _closeLibrary();
                _newScene(from: e);
              },
            ),
          ],
      };

  late final _library = Library(widget.client, widget.assets);

  /// Picks an image and uploads it, files it in the GM's library under
  /// [kind], then hands it to [use]. [what] names it in the toasts ("Map",
  /// "Token image").
  Future<void> _uploadImage(String what, LibraryKind kind,
      void Function(AssetId id, ui.Image image) use) async {
    if (_uploading != null) return;
    try {
      final picked = await pickImage(widget.assets,
          onUploading: (file) => setState(() => _uploading = 'Uploading $file'));
      if (picked == null) return;
      use(picked.id, picked.image);
      _toasts.show('$what uploaded', tone: CvTone.ok);
      // The library is a convenience: a failure there doesn't undo the upload.
      final name = picked.name.isEmpty ? what : picked.name;
      _library.add(kind, name, picked.id, picked.image).then((_) {
        if (mounted) setState(() => _libraryRevision++);
      }, onError: (Object e) => debugPrint('$what not added to the library: $e'));
    } on FormatException catch (e) {
      _toasts.show(e.message, tone: CvTone.danger);
    } on Object catch (e) {
      _toasts.show('$what failed to upload: $e', tone: CvTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// Makes an uploaded image the scene's map.
  Future<void> _setMap() => _uploadImage('Map', LibraryKind.map, (id, image) {
        final old = _host!.store.scene.settings;
        _host!.execute(UpdateSettings(old.copyWith(
          map: id,
          width: image.width.toDouble(),
          height: image.height.toDouble(),
        )));
      });

  /// Makes a library map the scene's map, at its own size.
  Future<void> _useMap(LibraryEntry entry) async {
    if (_uploading != null) return;
    setState(() => _uploading = 'Opening ${entry.name}');
    try {
      // Maps and tokens always have an asset (the library's shape check).
      final image = await widget.assets.image(entry.asset!);
      final old = _host!.store.scene.settings;
      _host!.execute(UpdateSettings(old.copyWith(
        map: entry.asset!,
        width: image.width.toDouble(),
        height: image.height.toDouble(),
      )));
    } on Object catch (e) {
      _toasts.show('${entry.name} failed to open: $e', tone: CvTone.danger);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  /// Gives a token an uploaded image.
  /// Opens the token library: to place tokens, or, [forToken], to give
  /// that one token an image.
  void _openTokens({TokenId? forToken}) => setState(() {
        final close = forToken == null && _libraryOpen == LibraryKind.token;
        _closePanels();
        if (!close) {
          _libraryOpen = LibraryKind.token;
          _tokenImageFor = forToken;
        }
      });

  /// A token image from the library or an upload: the token the library was
  /// opened for gets it, or a new token is placed with it.
  void _useTokenImage(AssetId image) {
    final host = _host!;
    // The token may have changed (or gone) since the library opened.
    if (host.store.scene.tokens[_tokenImageFor] case final token?) {
      host.execute(UpdateToken(token.copyWith(image: image)));
      setState(() {
        _tokenImageFor = null;
        _libraryOpen = null;
      });
    } else {
      _addToken(image: image);
    }
  }

  Future<void> _uploadTokenImage() => _uploadImage(
      'Token image', LibraryKind.token, (id, _) => _useTokenImage(id));

  void _setCellSize(double size) {
    final host = _host!;
    final old = host.store.scene.settings;
    host.execute(UpdateSettings(
        old.copyWith(grid: Grid(cellSize: size, offset: old.grid.offset))));
  }

  /// One fog op over the whole map: a clean slate, covered or revealed,
  /// that undo takes back like any other.
  void _fillFog(FogMode mode) {
    final host = _host!;
    final s = host.store.scene.settings;
    host.execute(AddFogOp(
        FogOpId(newId()), mode, FogRect((x: 0, y: 0), (x: s.width, y: s.height))));
    // Revealing everything leaves only covering to do, and the reverse.
    _controller.fogMode =
        mode == FogMode.cover ? FogMode.reveal : FogMode.cover;
  }

  late final _installedPacks = InstalledPacks(widget.client);

  /// The GM's installed systems, for the System menu.
  List<SystemPack> _packs = const [];

  Future<void> _loadPacks() async {
    try {
      final packs = await _installedPacks.list();
      if (mounted) setState(() => _packs = packs);
    } on Object catch (e) {
      if (mounted) _toasts.show('Systems failed to load: $e', tone: CvTone.danger);
    }
  }

  /// The systems the menu offers beyond the built-in ones: installed ones,
  /// and the one the scene carries if this GM hasn't installed it.
  List<SystemPack> _packChoices(Scene scene) {
    final carried = packOf(scene);
    return [
      ..._packs,
      if (!builtInPacks.containsKey(carried.id) &&
          !_packs.any((p) => p.id == carried.id))
        carried,
    ];
  }

  /// Applied before the table sees the scene, so it isn't an undo step.
  Scene _onSystem(Scene scene) => sceneOnSystem(scene, _system, _packs);

  /// Plays the campaign, and so this scene and every other, with [id]; an
  /// installed system's file goes with the scene.
  Future<void> _setPack(String id) async {
    final host = _host!;
    final pack = builtInPacks.containsKey(id)
        ? null
        : _packChoices(host.store.scene).where((p) => p.id == id).firstOrNull;
    host.execute(UsePack(id, data: pack?.toJson(tokens: false)));
    _system = id;
    try {
      await Campaigns(widget.client).setSystem(widget.campaign, id);
    } on Object catch (e) {
      _toasts.show('The campaign\'s system failed to save: $e', tone: CvTone.danger);
    }
  }

  Future<void> _installPack() async {
    try {
      final pack = await pickModule(widget.assets);
      if (pack == null) return;
      await _installedPacks.install(pack);
      await _loadPacks();
      await _setPack(pack.id);
      _toasts.show('${pack.name} installed', tone: CvTone.ok);
    } on FormatException catch (e) {
      _toasts.show(e.message, tone: CvTone.danger);
    } on Object catch (e) {
      _toasts.show('The system failed to install: $e', tone: CvTone.danger);
    }
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
        _host!.load(scene.withCharacters(_host!.store.scene.characters));
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
    _autosave?.cancel();
    _peers?.cancel();
    _pings?.cancel();
    _stopRulers?.call();
    members.value = {};
    _flushSave();
    _host?.close();
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
      onAddToken: _openTokens,
      onSetMap: () => _toggleLibrary(LibraryKind.map),
      onExport: _export,
      onImport: _import,
      onRemove: _removeToken,
      onDuplicate: _duplicateToken,
      onUndo: host.undo,
      onRedo: host.redo,
      onEscape: _libraryOpen == null ? null : _closeLibrary,
      grid: () => host.store.scene.settings.grid,
      child: Stack(children: [
        Positioned.fill(
          child: TableView(
            store: host.store,
            controller: _controller,
            gm: true,
            self: widget.me,
            send: host.execute,
            onPing: (at) => host.execute(Ping(at)),
            map: widget.art.map,
            loadAsset: widget.assets.image,
            images: (id) => widget.art.tokens[id],
          ),
        ),
        // Under the token card and the log, which it would otherwise hide.
        if (_sheet case final id?)
          Positioned(
            left: 0,
            right: 0,
            top: pad + CvSizes.hit + CvSpacing.s4,
            child: Center(
              child: SheetPanel(
                store: host.store,
                id: id,
                self: widget.me,
                send: host.execute,
                onClose: () => setState(() => _sheet = null),
              ),
            ),
          ),
        Positioned.fill(
          child: TokenCardLayer(
            store: host.store,
            session: host,
            controller: _controller,
            send: host.execute,
            onRemove: _removeToken,
            onDuplicate: _duplicateToken,
            onSetImage: (id) => _openTokens(forToken: id),
            fullPack: _fullPack,
            loadImage: widget.assets.image,
            self: widget.me,
            onOpenSheet: (id) => setState(() => _sheet = id),
          ),
        ),
        Positioned.fill(
          child: GridAlignLayer(
            controller: _controller,
            onDone: (grid) => host.execute(UpdateSettings(
                host.store.scene.settings.copyWith(grid: grid))),
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
          left: 0,
          right: 0,
          top: pad,
          child: Center(
            child: InitiativeBar(
                store: host.store,
                controller: _controller,
                send: host.execute,
                gm: true,
                self: widget.me,
                fullPack: _fullPack),
          ),
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
              onSetMap: () => _toggleLibrary(LibraryKind.map),
              mapsOpen: _libraryOpen == LibraryKind.map,
              scenesOpen: _scenesOpen,
              onScenes: () => setState(() {
                final open = !_scenesOpen;
                _closePanels();
                _scenesOpen = open;
              }),
              membersOpen: _membersOpen,
              onMembers: () => setState(() {
                final open = !_membersOpen;
                _closePanels();
                _membersOpen = open;
              }),
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
                    if (_membersOpen) MembersPanel(onRemove: _removeMember),
                    if (_scenesOpen)
                      ScenesPanel(
                        scenes: _sceneList,
                        live: _sceneId,
                        onSwitch: _switchScene,
                        onNew: _newScene,
                        onRename: _renameScene,
                        onDelete: _deleteScene,
                        onSaveToLibrary: _saveSceneToLibrary,
                        onExport: _export,
                        onImport: _import,
                        onFromLibrary: () => _toggleLibrary(LibraryKind.scene),
                        fromLibraryOpen: _libraryOpen == LibraryKind.scene,
                      ),
                    GridOptions(
                        controller: _controller,
                        grid: grid,
                        visible: settings.gridVisible,
                        onCellSize: _setCellSize,
                        onVisible: _setGridVisible,
                        pack: settings.pack,
                        packs: _packChoices(snap.requireData),
                        onPack: _setPack,
                        onInstallPack: _installPack),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          left: pad,
          right: pad,
          top: pad + CvSizes.hit + CvSpacing.s4,
          bottom: pad,
          child: BottomRow(
            // The options of the tool in hand, just above it.
            dock: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: CvSpacing.s4,
              children: [
                StreamBuilder(
                  stream: host.store.changes,
                  initialData: host.store.scene,
                  builder: (context, snap) => FogOptions(
                      controller: _controller,
                      grid: snap.requireData.settings.grid,
                      onFill: _fillFog),
                ),
                RegionOptions(
                    controller: _controller,
                    store: host.store,
                    send: host.execute),
                if (_libraryOpen == LibraryKind.token) _tokenStrip(host),
                ToolDock(
                    controller: _controller,
                    gm: true,
                    onUndo: host.undo,
                    onRedo: host.redo,
                    onAddToken: _openTokens,
                    tokensOpen: _libraryOpen == LibraryKind.token),
              ],
            ),
            side: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: CvSpacing.s4,
              children: [
                LogPanel(session: host, send: host.execute, gm: true),
                ZoomCluster(controller: _controller, snap: true),
              ],
            ),
          ),
        ),
        // Maps and scenes pop up over the table: picking closes them.
        if (_libraryOpen case final kind? when kind != LibraryKind.token)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeLibrary,
              child: ColoredBox(
                color: CvColors.surfaceScrim,
                child: Center(
                  // Taps inside don't close it.
                  child: GestureDetector(
                    onTap: () {},
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: CvSpacing.s4,
                      children: _libraryPopup(kind, host),
                    ),
                  ),
                ),
              ),
            ),
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
                        CvProgressBar(label: name, color: CvColors.amber500),
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
    required this.campaign,
    required this.art,
    required this.onLeave,
  });

  final SupabaseClient client;
  final AssetStore assets;
  final PlayerId me;
  final String code;

  /// The campaign joined, for its members' names; null for a room saved
  /// before campaigns.
  final String? campaign;
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
  StreamSubscription<Set<String>>? _peers;
  StreamSubscription<TableEvent>? _pings;
  VoidCallback? _stopRulers;
  VoidCallback? _stopSaving;
  late final _characters = SavedCharacters(widget.client);

  /// The character whose sheet is open.
  CharacterId? _sheet;

  Future<void> _loadMembers() async {
    if (widget.campaign case final campaign?) {
      // Names are a nicety: the table works without them.
      await loadMembers(widget.client, campaign).catchError((Object e) {
        debugPrint('Players failed to load: $e');
      });
    }
  }

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
      _peers = session.peers.map(peerIds).distinct(sameIds).listen((_) => _loadMembers());
      _pings = showPings(session, _controller);
      _stopRulers = shareRulers(session, _controller);
      await _loadMembers();
      await session.setCursor(null);
      // Completes when the GM answers, now or once they open the room.
      final store = await session.join();
      _stopSaving = saveOwnCharacters(store, widget.me, _characters,
          onError: (e) => debugPrint('A character failed to save: $e'));
      if (mounted) setState(() => _store = store);
    } on ProtocolMismatch {
      if (mounted) setState(() => _mismatch = true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _peers?.cancel();
    _pings?.cancel();
    _stopRulers?.call();
    _stopSaving?.call();
    members.value = {};
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
            onPing: (at) => session.request(Ping(at)),
            map: widget.art.map,
            loadAsset: widget.assets.image,
            images: (id) => widget.art.tokens[id],
          ),
        ),
        // Under the token card and the log, which it would otherwise hide.
        if (_sheet case final id?)
          Positioned(
            left: 0,
            right: 0,
            top: pad + CvSizes.hit + CvSpacing.s4,
            child: Center(
              child: SheetPanel(
                store: store,
                id: id,
                self: widget.me,
                send: session.request,
                onClose: () => setState(() => _sheet = null),
              ),
            ),
          ),
        Positioned.fill(
          child: TokenCardLayer(
            store: store,
            session: session,
            controller: _controller,
            send: session.request,
            gm: false,
            self: widget.me,
            onOpenSheet: (id) => setState(() => _sheet = id),
          ),
        ),
        Positioned(
          left: pad,
          top: pad,
          child: CvRoomCodeChip(code: widget.code),
        ),

        Positioned(
          left: pad,
          top: pad + CvSizes.hit + CvSpacing.s4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: CvSpacing.s4,
            children: [
              YourTokens(store: store, self: widget.me, controller: _controller),
              if (widget.campaign case final campaign?)
                CharactersPanel(
                  store: store,
                  self: widget.me,
                  campaign: campaign,
                  characters: _characters,
                  send: session.request,
                  onOpen: (id) => setState(() => _sheet = id),
                ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: pad,
          child: Center(
            child: InitiativeBar(
                store: store,
                controller: _controller,
                send: session.request,
                gm: false,
                self: widget.me),
          ),
        ),
        Positioned(
          right: pad,
          top: pad,
          child: PresenceBar(session: session, onLeave: widget.onLeave),
        ),
        Positioned(
          left: pad,
          right: pad,
          top: pad + CvSizes.hit + CvSpacing.s4,
          bottom: pad,
          child: BottomRow(
            dock: ToolDock(controller: _controller),
            side: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: CvSpacing.s4,
              children: [
                LogPanel(session: session, send: session.request),
                ZoomCluster(controller: _controller),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// [scene] played with [system], a pack id: as it was if it already is
/// with the installed version, or if the system is neither built in nor
/// among [installed] (it then keeps its own). An installed system's file
/// goes with the scene, so a module's new version reaches it as it opens.
Scene sceneOnSystem(Scene scene, String system, List<SystemPack> installed) {
  final pack = installed.where((p) => p.id == system).firstOrNull;
  if (scene.settings.pack == system &&
      (pack == null || scene.packFile?.data['version'] == pack.version)) {
    return scene;
  }
  if (!builtInPacks.containsKey(system) && pack == null) return scene;
  return switch (reduce(
      scene, const Gm(), UsePack(system, data: pack?.toJson(tokens: false)))) {
    Accepted(:final patches) => scene.applyPatches(patches),
    Refused() => scene,
  };
}

/// Who is connected, without their cursors: a change here, not a cursor
/// move, means someone arrived or left.
Set<String> peerIds(List<Presence> peers) => {for (final p in peers) p.player};

bool sameIds(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// The name for a copy: "Goblin 1" becomes the lowest free "Goblin N", and
/// a name without a number stays as it is.
String nextName(String name, Iterable<String> taken) {
  final match = RegExp(r'^(.*?)(\d+)$').firstMatch(name);
  if (match == null) return name;
  final stem = match[1]!;
  final used = taken.toSet();
  var n = int.parse(match[2]!) + 1;
  while (used.contains('$stem$n')) {
    n++;
  }
  return '$stem$n';
}
