import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/characters.dart';
import 'package:chimera_vtt/module_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart';

final v1 = SystemPack.fromJson({
  'id': 'x',
  'name': 'X',
  'unit': 'ft',
  'compendium': {
    'kinds': [
      {'name': 'Gun', 'fields': [{'name': 'shots', 'type': 'tracker', 'max': 6}]},
    ],
    'entries': [
      {'kind': 'Gun', 'name': 'Old Rifle'},
    ],
  },
  'advancement': {
    'name': 'Stars',
    'field': 'CP',
    'nodes': [{'name': 'Start', 'cost': 0}],
  },
  'sheet': {
    'sections': [
      {
        'title': 'S',
        'fields': [
          {'name': 'CP'},
          {'name': 'FIN'},
          {'name': 'gone'},
        ],
      },
    ],
  },
});

final kade = Character(
  id: const CharacterId('k'),
  owner: const PlayerId('me'),
  system: 'x',
  name: 'Kade',
  values: const {'FIN': 4, 'gone': 1, 'CP': 2},
  items: [Item(id: 'i', kind: 'Gun', name: 'Old Rifle', values: const {'shots': 3})],
  nodes: const ['Start'],
);

void main() {
  test('renaming in the editor records former names, and characters follow', () {
    final d = ModuleDraft(v1);
    final fields = ((d.sheet!['sections'] as List).first as Map)['fields'] as List;
    (fields[1] as Map)['name'] = 'finesse';
    fields.removeAt(2); // "gone" goes.
    final kind = (d.compendium!['kinds'] as List).first as Map;
    kind['name'] = 'Weapon';
    ((kind['fields'] as List).first as Map)['name'] = 'ammo';
    ((d.compendium!['entries'] as List).first as Map)
      ..['name'] = 'Rifle'
      ..['kind'] = 'Weapon';
    ((d.advancements.single['nodes'] as List).first as Map)['name'] = 'Origin';
    final v2 = d.build();
    expect(v2.sheet!.fields.firstWhere((f) => f.name == 'finesse').was, ['FIN']);
    expect(v2.toJson().toString(), isNot(contains(r'$name')));

    final now = cleaned(kade, v2);
    expect(now.values, {'CP': 2, 'finesse': 4});
    final rifle = now.items.single;
    expect((rifle.kind, rifle.name), ('Weapon', 'Rifle'));
    expect(rifle.values, {'ammo': 3});
    expect(now.nodes, ['Origin']);
    // A second version keeps the first's former names.
    expect(ModuleDraft(v2).build().sheet!.fields.firstWhere((f) => f.name == 'finesse').was,
        ['FIN']);
  });

  test("an entry's value under a field's former name is read under its new one", () {
    final c = Compendium.fromJson({
      'kinds': [
        {'name': 'Armor', 'fields': [{'name': 'gradeX', 'was': ['grade']}]},
      ],
      'entries': [
        {'kind': 'Armor', 'name': 'Vulture', 'values': {'grade': 2}},
      ],
    });
    expect(c.entries['Vulture']!.values, {'gradeX': 2});
  });

  test("a former name can't be another field's name", () {
    expect(
        () => SheetDef.fromJson({
              'sections': [
                {
                  'title': 'S',
                  'fields': [
                    {'name': 'a', 'was': ['b']},
                    {'name': 'b'},
                  ],
                },
              ],
            }),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('still a field'))));
  });
}
