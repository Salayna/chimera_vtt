import 'dart:async';

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/semantics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account.dart';
import 'assets.dart';
import 'bench.dart';
import 'demo_assets.dart';
import 'loopback_demo.dart';
import 'room.dart';
import 'theme.dart';
import 'ui/cv.dart';

/// From --dart-define-from-file: config/local.json for the `supabase start`
/// stack, or a file per hosted project.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_KEY');

Future<void> main() async {
  // Offline modes: the render benchmark, and GM and player side by side.
  if (const bool.fromEnvironment('BENCH')) return runApp(const BenchApp());
  if (const bool.fromEnvironment('LOOPBACK')) return runApp(const LoopbackDemo());

  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    throw StateError('No Supabase config: run with '
        '--dart-define-from-file=config/local.json');
  }
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
  StreamSubscription<AuthState>? _auth;

  @override
  void initState() {
    super.initState();
    _boot();
    // A GM signing in or out changes who this client is. Signed out, it
    // goes back to being an anonymous player.
    _auth = _client.auth.onAuthStateChange.listen((state) async {
      final user = _client.auth.currentUser;
      if (user == null) {
        await _client.auth.signInAnonymously();
        return;
      }
      if (mounted && _me?.value != user.id) {
        setState(() => _me = PlayerId(user.id));
      }
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    super.dispose();
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
          room = (code: code, gm: false, campaign: null);
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
        (final me?, final art?, final room?)
            when room.gm && signedInGm(_client) != null =>
          GmRoom(
            key: ValueKey(room),
            client: _client,
            assets: _assets,
            me: me,
            code: room.code,
            campaign: room.campaign!,
            art: art,
            onLeave: _leave,
          ),
        (final me?, final art?, final room?) when !room.gm => PlayerRoom(
            key: ValueKey(room),
            client: _client,
            assets: _assets,
            me: me,
            code: room.code,
            art: art,
            onLeave: _leave,
          ),
        // No room, or a GM room without a signed-in GM.
        (_?, _?, _) => Lobby(client: _client, onEnter: _enter),
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
