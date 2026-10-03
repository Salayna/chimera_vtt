import 'dart:async';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/widgets.dart';

import 'demo_assets.dart';
import 'room.dart' show StatusScreen;
import 'table/chrome.dart';
import 'table/table_view.dart';
import 'theme.dart';
import 'ui/cv.dart';

/// The GM and one player side by side, over loopback.
class LoopbackDemo extends StatefulWidget {
  const LoopbackDemo({super.key});

  @override
  State<LoopbackDemo> createState() => _LoopbackDemoState();
}

class _LoopbackDemoState extends State<LoopbackDemo> {
  static const alice = PlayerId('alice');
  final _hub = LoopbackHub();
  late final HostSession _host;
  late final ClientSession _player;
  late final Timer _heartbeat;
  late final ui.Image _map = generateMap(4096);
  late final Map<AssetId, ui.Image> _images = generateTokenImages(4);
  final _gm = TableController();
  final _playerView = TableController();
  SceneStore? _playerStore;

  @override
  void initState() {
    super.initState();
    Token token(String id, double x, double y,
            {PlayerId? owner, bool hidden = false, int image = 0}) =>
        Token(
          id: TokenId(id),
          position: (x: x, y: y),
          size: 128,
          image: AssetId('token$image'),
          owner: owner,
          hidden: hidden,
        );
    _host = HostSession(
      _hub.connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 4096, height: 4096, grid: Grid(cellSize: 128)),
        tokens: {
          for (final t in [
            token('hero', 1000, 1000, owner: alice, image: 1),
            token('ally', 1300, 1000, owner: alice, image: 2),
            token('orc', 2600, 2200),
            token('ambush', 3000, 1200, hidden: true, image: 3),
          ])
            t.id: t,
        },
      )),
    );
    _player = ClientSession(_hub.connect(), alice);
    _player.join().then((store) => setState(() => _playerStore = store));
    _heartbeat =
        Timer.periodic(const Duration(seconds: 3), (_) => _host.heartbeat());
  }

  @override
  void dispose() {
    _heartbeat.cancel();
    _gm.dispose();
    _playerView.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _playerStore;
    const pad = CvSizes.insetScreen;
    return cvApp(
      title: 'Chimera VTT',
      home: Row(children: [
        Expanded(
          child: TableShortcuts(
            controller: _gm,
            gm: true,
            child: Stack(children: [
              Positioned.fill(
                child: TableView(
                  store: _host.store,
                  controller: _gm,
                  gm: true,
                  self: _host.self,
                  send: _host.execute,
                  map: _map,
                  images: (id) => _images[id],
                ),
              ),
              Positioned.fill(
                child: TokenCardLayer(
                  store: _host.store,
                  session: _host,
                  controller: _gm,
                  send: _host.execute,
                  onRemove: (id) => _host.execute(RemoveToken(id)),
                ),
              ),
              Positioned.fill(
                left: pad,
                right: pad,
                bottom: pad,
                child: BottomRow(
                  dock: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: CvSpacing.s4,
                    children: [
                      FogOptions(
                          controller: _gm,
                          grid: _host.store.scene.settings.grid),
                      ToolDock(controller: _gm, gm: true),
                    ],
                  ),
                  side: ZoomCluster(controller: _gm, snap: true),
                ),
              ),
            ]),
          ),
        ),
        Container(width: 4, color: CvColors.borderSubtle),
        Expanded(
          child: player == null
              ? const StatusScreen(
                  title: 'Waiting for the GM to open the room…',
                  spinner: CvColors.teal500)
              : Stack(children: [
                  Positioned.fill(
                    child: TableView(
                      store: player,
                      controller: _playerView,
                      gm: false,
                      self: alice,
                      send: _player.request,
                      map: _map,
                      images: (id) => _images[id],
                    ),
                  ),
                  Positioned(
                    left: pad,
                    top: pad,
                    child: YourTokens(
                        store: player, self: alice, controller: _playerView),
                  ),
                ]),
        ),
      ]),
    );
  }
}
