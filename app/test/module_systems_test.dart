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
