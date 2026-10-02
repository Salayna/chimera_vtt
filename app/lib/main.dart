import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assets.dart';
import 'bench.dart';
import 'demo_assets.dart';
import 'loopback_demo.dart';
import 'room.dart';
import 'theme.dart';
import 'ui/cv.dart';

/// Defaults point at the local stack from `supabase start`; its publishable
/// key is the CLI's well-known local one, not a secret. Pass both with
/// --dart-define for a hosted project.
const _supabaseUrl =
    String.fromEnvironment('SUPABASE_URL', defaultValue: 'http://127.0.0.1:54321');
const _supabaseKey = String.fromEnvironment('SUPABASE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH');

Future<void> main() async {
  // Offline modes: the render benchmark, and GM and player side by side.
  if (const bool.fromEnvironment('BENCH')) return runApp(const BenchApp());
  if (const bool.fromEnvironment('LOOPBACK')) return runApp(const LoopbackDemo());

  WidgetsFlutterBinding.ensureInitialized();
  // For browser automation: exposes widgets to the DOM as accessibility nodes.
  if (const bool.fromEnvironment('SEMANTICS')) {
    SemanticsBinding.instance.ensureSemantics();
  }
  // The session persists (local storage on web), so a refresh keeps the
  // same anonymous player.
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  runApp(const ChimeraApp());
}

class ChimeraApp extends StatefulWidget {
  const ChimeraApp({super.key});

  @override
  State<ChimeraApp> createState() => _ChimeraAppState();
}

class _ChimeraAppState extends State<ChimeraApp> {
  final _client = Supabase.instance.client;
  late final _assets = AssetStore(_client);
  PlayerId? _me;
  SavedRoom? _room;
  Art? _art;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      final auth = _client.auth;
      if (auth.currentSession == null) await auth.signInAnonymously();
      var room = await loadSavedRoom();
      // A join link: ?room=CODE.
      if (room == null) {
        final code = normalizeRoomCode(Uri.base.queryParameters['room'] ?? '');
        if (code.length == 6) {
          room = (code: code, gm: false);
          await saveRoom(room);
        }
      }
      setState(() {
        _me = PlayerId(auth.currentUser!.id);
        _room = room;
        _art = (map: generateMap(4096), tokens: generateTokenImages(4));
      });
    } on Object catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _enter(SavedRoom room) {
    saveRoom(room);
    setState(() => _room = room);
  }

  void _leave() {
    saveRoom(null);
    setState(() => _room = null);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final art = _art;
    final room = _room;
    return cvApp(
      title: 'Chimera VTT',
      home: switch ((me, art, room)) {
        (final me?, final art?, final room?) when room.gm => GmRoom(
            key: ValueKey(room),
            client: _client,
            assets: _assets,
            me: me,
            code: room.code,
            art: art,
            onLeave: _leave,
          ),
        (final me?, final art?, final room?) => PlayerRoom(
            key: ValueKey(room),
            client: _client,
            assets: _assets,
            me: me,
            code: room.code,
            art: art,
            onLeave: _leave,
          ),
        (_?, _?, null) => Lobby(onEnter: _enter),
        _ when _error != null => StatusScreen(
            title: 'Could not sign in.',
            message: _error,
            icon: Lucide.triangleAlert,
            tone: CvTone.danger,
            actions: [
              CvButton(
                  label: 'Try again', icon: Lucide.refreshCw, onPressed: _boot),
            ],
          ),
        _ => const StatusScreen(title: 'Signing in…', spinner: CvColors.bone100),
      },
    );
  }
}
