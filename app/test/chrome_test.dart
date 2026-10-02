import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/room.dart';
import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cells are named column letter, row number', () {
    const grid = Grid(cellSize: 100);
    expect(cellName((x: 50, y: 50), grid), 'A1');
    expect(cellName((x: 250, y: 350), grid), 'C4');
    expect(cellName((x: 2650, y: 50), grid), 'AA1');
  });

  testWidgets('the lobby renders and asks for 6 characters', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SavedRoom? entered;
    await tester.pumpWidget(cvApp(
        title: 'test', home: Lobby(onEnter: (room) => entered = room)));
    await tester.enterText(find.byType(EditableText), 'k7q');
    await tester.pump();
    await tester.tap(find.text('Join'));
    await tester.pump();
    expect(find.text('Room codes have 6 characters.'), findsOneWidget);
    expect(entered, isNull);

    await tester.tap(find.text('Create room'));
    expect(entered?.gm, isTrue);
  });

  testWidgets('the GM chrome follows the controller', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TableShortcuts(
        controller: controller,
        gm: true,
        child: Stack(children: [
          Positioned(left: 16, top: 100, child: GmRail(controller: controller)),
          Positioned(
              left: 100,
              top: 100,
              child: FogOptions(
                  controller: controller, grid: const Grid(cellSize: 128))),
          Positioned(
              right: 16,
              bottom: 16,
              child: ZoomCluster(controller: controller, snap: true)),
        ]),
      ),
    ));
    expect(find.text('FOG BRUSH'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Fog brush'));
    await tester.pumpAndSettle();
    expect(controller.tool, Tool.fogBrush);
    expect(find.text('FOG BRUSH'), findsOneWidget);

    await tester.tap(find.text('Reveal'));
    expect(controller.fogMode, FogMode.reveal);

    await tester.tap(find.text('Snap'));
    expect(controller.snap, isFalse);
  });

  testWidgets('the grid panel sets the cell size, and typing is not shortcuts',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    final sizes = <double>[];
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TableShortcuts(
        controller: controller,
        gm: true,
        child: Stack(children: [
          Positioned(left: 16, top: 100, child: GmRail(controller: controller)),
          Positioned(
              left: 100,
              top: 100,
              child: GridOptions(
                  controller: controller,
                  grid: const Grid(cellSize: 128),
                  onCellSize: sizes.add)),
        ]),
      ),
    ));
    expect(find.text('GRID'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Grid'));
    await tester.pumpAndSettle();
    expect(find.text('GRID'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '8');
    await tester.pump();
    expect(find.text('From 16 to 1024 px.'), findsOneWidget);
    expect(sizes, isEmpty);

    await tester.enterText(find.byType(EditableText), '70');
    await tester.pump();
    expect(sizes, [70]);

    // B would pick the fog brush; in the field it's just a key.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(controller.tool, Tool.move);
  });
}
