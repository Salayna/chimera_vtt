import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'demo_assets.dart';
import 'table/fog_mask.dart';
import 'table/table_view.dart';

/// H1 and H5 in one run: a 4096 px map, 50 image tokens and 500 fog strokes,
/// shown to the GM and a player side by side, while the GM drags a token,
/// the views pan, and a new fog stroke lands twice a second.
///
/// Run in profile mode: flutter run --profile --dart-define=BENCH=true
/// Prints one line starting with `BENCH ` when done.
class BenchApp extends StatefulWidget {
  const BenchApp({super.key});

  static const mapSize = 4096.0;
  static const tokens = 50;
  static const fogStrokes = 500;
  static const warmUp = Duration(seconds: 2);
  static const measure = Duration(seconds: 10);

  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp>
    with SingleTickerProviderStateMixin {
  final _random = math.Random(42);
  final _hub = LoopbackHub();
  late final HostSession _host;
  late final ClientSession _player;
  SceneStore? _playerStore;
  final _gm = TableController();
  final _playerView = TableController();
  late final ui.Image _map;
  late final Map<AssetId, ui.Image> _images;
  late final Ticker _ticker;
  final Map<String, Object> _report = {};

  final _intervals = <int>[];
  final _build = <int>[];
  final _raster = <int>[];
  Duration? _lastTick;
  Duration _lastSend = Duration.zero;
  int _sends = 0;
  bool _measuring = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _map = generateMap(BenchApp.mapSize.toInt());
    _images = generateTokenImages(8);
    final tokens = {
      for (var i = 0; i < BenchApp.tokens; i++)
        TokenId('t$i'): Token(
          id: TokenId('t$i'),
          position: (
            x: _random.nextDouble() * BenchApp.mapSize,
            y: _random.nextDouble() * BenchApp.mapSize
          ),
          size: 64,
          image: AssetId('token${i % 8}'),
          owner: i.isEven ? const PlayerId('alice') : null,
        ),
    };
    _host = HostSession(
      _hub.connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: BenchApp.mapSize,
            height: BenchApp.mapSize,
            grid: Grid(cellSize: 64)),
        tokens: tokens,
      )),
    );
    for (var i = 0; i < BenchApp.fogStrokes; i++) {
      _host.execute(AddFogOp(FogOpId('f$i'), FogMode.cover,
          randomStroke(_random, BenchApp.mapSize)));
    }
    _report.addAll(_bakeTimes(_host.store.scene));
    _player = ClientSession(_hub.connect(), const PlayerId('alice'));
    _player.join().then((store) => setState(() => _playerStore = store));
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _ticker = createTicker(_tick)..start();
  }

  /// One-off costs of the fog mask, outside the frame loop.
  static Map<String, Object> _bakeTimes(Scene scene) {
    final mask = FogMask();
    final ops = scene.fogInOrder;
    final watch = Stopwatch()..start();
    mask.sync(scene.settings, ops.sublist(0, ops.length - 1));
    final full = watch.elapsedMicroseconds;
    watch.reset();
    mask
      ..sync(scene.settings, ops)
      ..bake();
    final one = watch.elapsedMicroseconds;
    mask.dispose();
    return {
      'fogFullBakeMs': full / 1000,
      'fogOneOpBakeMs': one / 1000,
    };
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (!_measuring) return;
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds);
      _raster.add(t.rasterDuration.inMicroseconds);
    }
  }

  void _tick(Duration elapsed) {
    if (_lastTick != null && _measuring) {
      _intervals.add((elapsed - _lastTick!).inMicroseconds);
    }
    _lastTick = elapsed;
    _measuring = elapsed > BenchApp.warmUp;
    if (elapsed > BenchApp.warmUp + BenchApp.measure) return _finish();

    // The GM drags token 1 in a circle, sending moves at 15 per second.
    final t = elapsed.inMicroseconds / 1e6;
    final position = Offset(2048 + 800 * math.cos(t), 2048 + 800 * math.sin(t));
    _gm.drag.value = (id: const TokenId('t1'), position: position);
    if (elapsed - _lastSend >= const Duration(milliseconds: 66)) {
      _lastSend = elapsed;
      _host.execute(
          MoveToken(const TokenId('t1'), (x: position.dx, y: position.dy)));
      // Every 8th send (about twice a second) adds a fog stroke.
      if (++_sends % 8 == 0) {
        _host.execute(AddFogOp(FogOpId(newId()), FogMode.cover,
            randomStroke(_random, BenchApp.mapSize)));
      }
    }
    // Both views pan back and forth.
    final pan = Matrix4.translationValues(math.sin(t * 2) * 1.5, 0, 0);
    _gm.view.value = pan.clone()..multiply(_gm.view.value);
    _playerView.view.value = pan..multiply(_playerView.view.value);
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    double pct(List<int> xs, double p) {
      if (xs.isEmpty) return 0;
      final sorted = [...xs]..sort();
      return sorted[((sorted.length - 1) * p).round()] / 1000;
    }

    final meanInterval =
        _intervals.reduce((a, b) => a + b) / _intervals.length;
    _report.addAll({
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'mode': kProfileMode ? 'profile' : kReleaseMode ? 'release' : 'debug',
      'frames': _intervals.length,
      'fps': (1e6 / meanInterval).toStringAsFixed(1),
      'intervalMs': [pct(_intervals, .5), pct(_intervals, .9), pct(_intervals, .99)],
      // Over 1.5 frames: really dropped, not vsync jitter.
      'droppedFramesPct':
          (100 * _intervals.where((i) => i > 25000).length / _intervals.length)
              .toStringAsFixed(1),
      'buildMs': [pct(_build, .5), pct(_build, .9), pct(_build, .99)],
      'rasterMs': [pct(_raster, .5), pct(_raster, .9), pct(_raster, .99)],
      'fogOps': _host.store.scene.fogOps.length,
    });
    debugPrint('BENCH ${jsonEncode(_report)}');
    // Profile web builds don't forward prints; the page title is readable
    // from Chrome's debugging endpoint.
    SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(label: 'BENCH ${jsonEncode(_report)}'));
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _gm.dispose();
    _playerView.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _playerStore;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [
        Expanded(child: _view(_host.store, _gm, gm: true, self: _host.self)),
        const SizedBox(width: 4),
        Expanded(
          child: player == null
              ? const SizedBox()
              : _view(player, _playerView, gm: false, self: _player.self),
        ),
      ]),
    );
  }

  Widget _view(SceneStore store, TableController controller,
          {required bool gm, required PlayerId self}) =>
      TableView(
        store: store,
        controller: controller,
        gm: gm,
        self: self,
        send: gm ? _host.execute : _player.request,
        map: _map,
        images: (id) => _images[id],
      );
}
