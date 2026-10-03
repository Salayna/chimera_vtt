import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/palette.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('⌘K finds and runs, rolls dice, and gives the keys back',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    final rolls = <String>[];
    var open = false;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: StatefulBuilder(
        builder: (context, setState) => TableShortcuts(
          controller: controller,
          gm: true,
          onPalette: () => setState(() => open = true),
          child: Stack(children: [
            Positioned(
              left: 16,
              bottom: 16,
              child: ToolDock(
                  controller: controller,
                  onSearch: () => setState(() => open = true)),
            ),
            if (open)
              Positioned.fill(
                child: PaletteLayer(
                  items: toolItems(controller, gm: true),
                  onClose: () => setState(() => open = false),
                  onRoll: rolls.add,
                ),
              ),
          ]),
        ),
      ),
    ));
    await tester.pump();

    Future<void> palette() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    await palette();
    expect(find.byType(CommandPalette), findsOneWidget);

    // Typing is text, not the table's keys: "l" doesn't pick the ruler.
    await tester.enterText(find.byType(EditableText), 'reg');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(controller.tool, Tool.move);
    expect(find.text('Regions'), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.tool, Tool.region);
    expect(find.byType(CommandPalette), findsNothing);

    await palette();
    await tester.enterText(find.byType(EditableText), '/r 2d6+3');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(rolls, ['2d6+3']);

    // Arrows pick: Move is first, Ruler second.
    await palette();
    expect(find.byType(CommandPalette), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(controller.tool, Tool.ruler);

    // Escape closes, and the table has its keys again.
    await palette();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(controller.tool, Tool.ping);

    // The dock's search button opens it too.
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandPalette), findsOneWidget);
  });
}
