import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/characters.dart';
import 'package:chimera_vtt/sheet_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart';

void main() {
  final dnd = builtInPacks['dnd5e']!;

  test('a character read from the table is cleaned against its sheet', () {
    final c = Character.fromJson({
      'id': 'c',
      'owner': 'me',
      'system': 'dnd5e',
      'name': 'Ayla',
      'sheet': {
        'values': {'DEX': 99, 'class': 'Rogue', 'hacked': true, 'level': [1]},
      },
    });
    expect(cleaned(c, dnd).values, {'DEX': 30, 'class': 'Rogue'});
    expect(cleaned(c.copyWith(values: {'class': 'Pilot'}), dnd).values, isEmpty);
    expect(cleaned(c, null).values, c.values, reason: 'kept until installed');
    expect(Character.fromJson(c.toJson()).values, c.values);
  });

  testWidgets('the sheet works its formulas out as values change', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var values = dnd.sheet!.start();
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: SheetView(
            sheet: dnd.sheet!,
            values: values,
            onSet: (name, value) => setState(() => values = {...values, name: value}),
          ),
        ),
      ),
    ));
    expect(find.text('Hit points / 8'), findsOneWidget);
    Finder button(String label) =>
        find.byWidgetPredicate((w) => w is CvToolButton && w.label == label);
    for (var i = 0; i < 4; i++) {
      await tester.tap(button('Dexterity +1'));
      await tester.pump();
    }
    expect(values['DEX'], 14);
    // Dexterity modifier, worked out from DEX.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('DEX.mod')), matching: find.text('2')),
        findsOneWidget);
    await tester.tap(button('Hit points / 8 +1'));
    await tester.pump();
    expect(values['HP'], 8, reason: 'kept at its max');
    await tester.tap(button('Hit point maximum +1'));
    await tester.pump();
    expect(find.text('Hit points / 9'), findsOneWidget);
  });
}
