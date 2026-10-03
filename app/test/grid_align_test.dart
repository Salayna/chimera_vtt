import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/grid_align.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the steps: an anchor, one square, then a far corner', () {
    final a = startAlign(const Grid(cellSize: 100, offset: (x: 0, y: 0)), (x: 240, y: 260));
    expect(a.anchor, (x: 200.0, y: 300.0)); // The grid's nearest corner.
    expect(sizeFrom((x: 0, y: 0), (x: 68, y: 72)), 70); // Not quite square: the mean.
    expect(cornerNear((x: 10, y: 10), 100, (x: 320, y: 190)), (3, 2));
    // Three cells right and two down landed 30 and 20 px further out:
    // 10 px a cell more.
    expect(refinedSize((x: 0, y: 0), (3, 2), (x: 330, y: 220)), 110);
    expect(refinedSize((x: 0, y: 0), (0, 0), (x: 5, y: 5)), isNull);
  });

  testWidgets('dragging through offset, size and refine saves the grid',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = TableController(); // Identity view: screen is scene.
    addTearDown(c.dispose);
    final saved = <Grid>[];
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Stack(children: [
        Positioned.fill(child: GridAlignLayer(controller: c, onDone: saved.add)),
      ]),
    ));
    c.align.value = startAlign(const Grid(cellSize: 100), (x: 240, y: 260));
    await tester.pump();

    // Offset: the anchor onto the map's corner.
    await tester.dragFrom(const Offset(200, 300), const Offset(10, 5));
    await tester.pump();
    expect(c.align.value!.anchor, (x: 210.0, y: 305.0));
    expect(c.gridFit.value!.toJson(), Grid.through((x: 210, y: 305), 100).toJson());

    // Size: the second anchor to the square's opposite corner.
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.dragFrom(const Offset(310, 405), const Offset(20, 20));
    await tester.pump();
    expect(c.align.value!.size, 120);

    // Refine: the corner 3 right, 2 down lands 30 and 20 px further.
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.dragFrom(const Offset(570, 545), const Offset(30, 20));
    await tester.pump();
    expect(c.align.value!.size, 130);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(saved.single.cellSize, 130);
    expect(saved.single.offset, (x: 80.0, y: 45.0)); // 210 % 130, 305 % 130
    expect(c.align.value, isNull);
    expect(c.gridFit.value, isNull);
  });

  testWidgets('over the map, a handle drag moves the handle, not the map',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SceneStore(Scene(
        settings: const SceneSettings(
            width: 1024, height: 1024, grid: Grid(cellSize: 128))));
    final c = TableController();
    addTearDown(c.dispose);
    // Stacked as in the GM's room.
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Stack(children: [
        Positioned.fill(
          child: TableView(
            store: store,
            controller: c,
            gm: true,
            self: const PlayerId('gm'),
            send: (command) => store.execute(const Gm(), command),
          ),
        ),
        Positioned.fill(child: GridAlignLayer(controller: c, onDone: (_) {})),
      ]),
    ));
    await tester.pump();
    c.align.value = startAlign(store.scene.settings.grid, c.viewCenter);
    await tester.pump();
    final view = c.view.value.clone();
    final anchor = c.align.value!.anchor;

    await tester.dragFrom(c.toScreen(anchor), const Offset(30, 0));
    await tester.pump();
    expect(c.view.value, view); // The map stayed put.
    expect(c.align.value!.anchor.x, closeTo(anchor.x + 30 / c.zoom, 0.5));

    // Away from any handle, the map still pans.
    await tester.dragFrom(const Offset(150, 150), const Offset(40, 0));
    await tester.pump();
    expect(c.view.value, isNot(view));
  });
}
