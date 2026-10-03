import 'package:chimera_vtt/assets.dart';
import 'package:chimera_vtt/module_editor.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthClientOptions, SupabaseClient;
import 'package:tactical_engine/tactical_engine.dart';

void main() {
  test("a draft's sheet, compendium and advancement are checked as a file's", () {
    final d = ModuleDraft()..name = 'Mine';
    d.sheet = {
      'sections': [
        {
          'title': 'S',
          'fields': [
            {'name': 'CP'},
            {'name': 'AP', 'type': 'tracker', 'max': '8 - sum("Armor", "apReduction")'},
          ],
        },
      ],
    };
    d.compendium = {
      'kinds': [
        {'name': 'Armor', 'fields': [{'name': 'apReduction'}]},
      ],
      'entries': [
        {'kind': 'Armor', 'name': 'Vulture', 'values': {'apReduction': 1}},
      ],
    };
    d.advancement = {
      'name': 'Constellation',
      'field': 'CP',
      'nodes': [{'name': 'Origin', 'cost': 0}],
    };
    final pack = d.build();
    expect(pack.sheet!.fields.last.max!.text, '8 - sum("Armor", "apReduction")');
    expect(pack.compendium!.entries['Vulture']!.values, {'apReduction': 1});
    // An edit starts from the installed module's own.
    expect(ModuleDraft(pack).build().advancement!.nodes.keys, ['Origin']);
    d.advancement!['field'] = 'XP';
    expect(() => d.build(), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('spends "XP"'))));
  });

  test("bands, forms, effects and a token's own trackers and conditions are edited", () {
    final d = ModuleDraft()..name = 'Mine';
    d.bands.addAll([
      {'name': 'Adjacent', 'max': 1.5},
      {'name': 'Far'},
    ]);
    d.forms.addAll([
      {'name': 'Rush', 'value': 3},
      {'name': 'Steady', 'value': 2, 'default': true},
    ]);
    d.tags.add(DraftTag('Darkness', TagKind.sector, valued: true, effects: [
      {'type': 'roll', 'edge': -1, 'scaled': true},
      {'type': 'entryCheck', 'check': 'Traversal'},
    ]));
    d.tokens.add(DraftToken('Raider', form: 'Rush', trackers: [
      {'name': 'CvW', 'max': 6, 'value': 0},
    ], conditions: [
      {'name': 'Synthetic'},
      {'name': 'Armored', 'value': 2},
    ]));
    final pack = d.build();
    expect([for (final b in pack.bands) (b.name, b.max)], [('Adjacent', 1.5), ('Far', null)]);
    expect(pack.startingForm(npc: false)!.name, 'Steady');
    expect(pack.tags['Darkness']!.effects.first, isA<RollModifier>().having((r) => r.scaled, 'scaled', true));
    final raider = pack.tokens['Raider']!;
    expect((raider.form, raider.trackers.single.max), ('Rush', 6));
    expect(raider.conditions, {'Synthetic': null, 'Armored': 2});
    // And they survive being edited again.
    expect(ModuleDraft(pack).build().toJson()..remove('version'), pack.toJson()..remove('version'));
  });

  testWidgets('the Sheet and Compendium tabs write the module', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = SupabaseClient('http://127.0.0.1:9', 'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    SystemPack? saved;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: ModuleEditor(
        assets: AssetStore(client),
        onSave: (p) async => saved = p,
        onClose: () {},
      ),
    ));
    await tester.enterText(find.byType(EditableText).first, 'Gear');
    await tester.tap(find.text('Compendium'));
    await tester.pump();
    await tester.tap(find.text('Add a kind'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).first, 'Weapon');
    await tester.pump();
    await tester.tap(find.text('Add an entry'));
    await tester.pump();
    await tester.enterText(find.byType(EditableText).last, 'P9 Pistol');
    await tester.tap(find.text('Sheet'));
    await tester.pump();
    await tester.tap(find.text('Give characters a sheet'));
    await tester.pump();
    await tester.tap(find.text('Add a field'));
    await tester.pump();
    // Name, label, then the number's min.
    await tester.enterText(find.byType(EditableText).at(1), 'STR');
    await tester.enterText(find.byType(EditableText).at(4), '1');
    await tester.tap(find.text('Save module'));
    await tester.pumpAndSettle();
    expect(saved!.sheet!.fields.single.least, 1);
    expect(saved!.compendium!.entries['P9 Pistol']!.kind, 'Weapon');
  });
}
