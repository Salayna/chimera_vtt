import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = TokenId('t');

  /// An 800x600 view of a 1024 px map, fitted: scale 600/1024, 100 px
  /// margin left and right. The token starts in the middle of cell (1, 1).
  Future<SceneStore> pump(WidgetTester tester, {required bool snap}) async {
    final store = SceneStore(Scene(
      settings: const SceneSettings(
          width: 1024, height: 1024, grid: Grid(cellSize: 128)),
      tokens: {
        id: const Token(id: id, position: (x: 192, y: 192), size: 128),
      },
    ));
    final controller = TableController()..snap = snap;
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableView(
        store: store,
        controller: controller,
        gm: true,
        self: const PlayerId('gm'),
        send: (command) => store.execute(const Gm(), command),
      ),
    ));
    return store;
  }

  const scale = 600 / 1024;
  const tokenOnScreen = Offset(100 + 192 * scale, 192 * scale);

  testWidgets('a dropped token snaps to the nearest cell', (tester) async {
    final store = await pump(tester, snap: true);
    // 100 px on screen is about 171 map px: from x=192 to about 363,
    // which is nearest the cell centred on x=320.
    await tester.dragFrom(tokenOnScreen, const Offset(100, 0));
    await tester.pump();
    expect(store.scene.tokens[id]!.position, (x: 320.0, y: 192.0));
  });

  testWidgets('with snapping off, it stays where it was dropped',
      (tester) async {
    final store = await pump(tester, snap: false);
    await tester.dragFrom(tokenOnScreen, const Offset(100, 0));
    await tester.pump();
    final position = store.scene.tokens[id]!.position;
    expect(position.x, closeTo(192 + 100 / scale, 1));
    expect(position.y, closeTo(192, 1));
  });
}
