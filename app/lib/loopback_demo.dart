import 'dart:async';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/material.dart';

import 'demo_assets.dart';
import 'table/table_view.dart';
import 'table/toolbar.dart';

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
    return MaterialApp(
      title: 'Chimera VTT',
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: Row(children: [
          Expanded(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: GmToolbar(controller: _gm),
              ),
              Expanded(
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
            ]),
          ),
          const VerticalDivider(width: 4),
          Expanded(
            child: Column(children: [
              const SizedBox(
                  height: 48, child: Center(child: Text('Player: alice'))),
              Expanded(
                child: player == null
                    ? const Center(child: CircularProgressIndicator())
                    : TableView(
                        store: player,
                        controller: _playerView,
                        gm: false,
                        self: alice,
                        send: _player.request,
                        map: _map,
                        images: (id) => _images[id],
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
