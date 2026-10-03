import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<int>> pump(WidgetTester tester, {required double top}) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <int>[];
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Stack(children: [
        Positioned(
          left: 16,
          top: top,
          width: 240,
          child: CvDropdown<int>(
            entries: [for (var i = 0; i < 40; i++) CvMenuItem(i, 'Item $i')],
            value: 0,
            onChanged: picked.add,
          ),
        ),
      ]),
    ));
    await tester.tap(find.text('Item 0'));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('a long menu stays on screen and scrolls to its last item',
      (tester) async {
    final picked = await pump(tester, top: 40);
    final menu = tester.getRect(find.byType(CvMenu<int>));
    expect(menu.top, greaterThanOrEqualTo(0));
    expect(menu.bottom, lessThanOrEqualTo(600));

    await tester.scrollUntilVisible(find.text('Item 39'), 200,
        scrollable: find.descendant(
            of: find.byType(CvMenu<int>), matching: find.byType(Scrollable)));
    await tester.tap(find.text('Item 39'));
    expect(picked, [39]);
  });

  testWidgets('near the bottom, the menu opens upwards', (tester) async {
    await pump(tester, top: 500);
    final field = tester.getRect(find.byType(CvPressable).first);
    final menu = tester.getRect(find.byType(CvMenu<int>));
    expect(menu.bottom, lessThanOrEqualTo(field.top));
    expect(menu.top, greaterThanOrEqualTo(0));
  });

  testWidgets('it opens on the current item, and the arrows pick',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <int>[];
    final outer = FocusNode();
    addTearDown(outer.dispose);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Focus(
        focusNode: outer,
        autofocus: true,
        child: Stack(children: [
          Positioned(
            left: 16,
            top: 40,
            width: 240,
            child: CvDropdown<int>(
              entries: [for (var i = 0; i < 40; i++) CvMenuItem(i, 'Item $i')],
              value: 30,
              onChanged: picked.add,
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('Item 30'));
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.byType(CvMenu<int>));
    final current = tester.getRect(find.text('Item 30').last);
    expect(current.top, greaterThanOrEqualTo(menu.top));
    expect(current.bottom, lessThanOrEqualTo(menu.bottom));

    for (var i = 0; i < 9; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    final last = tester.getRect(find.text('Item 39'));
    expect(last.bottom, lessThanOrEqualTo(menu.bottom));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, [39]);
    expect(find.byType(CvMenu<int>), findsNothing);
    expect(outer.hasPrimaryFocus, isTrue);
  });
}
