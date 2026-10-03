import 'package:tactical_engine/tactical_engine.dart';
import 'package:test/test.dart';

import '../tool/solaris_characters.dart';

// Invented cards in the shape of the notes' data cards: no book content.
const weapons = '''
#### Pistols - Basic

| **Test "Sparrow" Pistol** |  |  |  |  |
| --- | --- | --- | --- | --- |
| A made-up pistol. |  |  |  |  |
| Weight: 1 Units | Price: 10 MSU | Attachment Slots: 1 (Ammo) |  |  |
| Type: | Ranged | Ballistic | Pistol | One-Handed |
| Weapon Tags - Testy: Does nothing. |  |  |  |  |
| Ammo: ☐☐☐☐ | Reload: 2 AP |  |  |  |
| Attack Profiles: |  |  |  |  |
| Snap Shot | AP Cost: 2 | Ranged Attacks: 2d20 | Range: Point Blank |  |
| Grazing Hit (10+): 1 Stress <br> Precise Hit (14+): 1 Stress & 1 CvW <br> Devastating Hit (18+): 2 Stress & 2 CvW |  |  |  |  |
| Butt | AP Cost: 1 | Melee Attacks: d20 | Range: Point Blank |  |
| Grazing Hit (12+): 1 Stress |  |  |  |  |
''';

const armor = '''
| **Test Vest** |  |  |
| --- | --- | --- |
| A made-up vest. |  |  |
| Armor Grade: 3 | AP Reduction: 1 |  |
| Weight: 2 Units | Price: 10 MSU | Carrying Capacity: 4 Items |
| Immunities: None | Vulnerabilities: Psychic | Resistances: None |
| Type: Light | Mod Slots: 2 |  |
| Armor Tags - Padded: Does nothing. |  |  |
''';

const talents = '''
> [!note]
> Test Star Prerequisite: Constellation Node
> Made up.
> Effect:
> Nothing happens.

> [!note]
> **Test Knack (Field)**
> Prerequisite: INT ≧ 4
> Also made up.
> Effect:
> Still nothing.
''';

void main() {
  test('weapon cards become entries with their attack profiles as actions', () {
    final [w] = weaponsFromMarkdown(weapons);
    expect(w['name'], 'Test "Sparrow" Pistol');
    expect(w['values'], {'capacity': 4, 'reload': 2, 'heavy': 0});
    final actions = w['actions'] as List;
    expect([for (final a in actions) (a as Json)['name']], ['Snap Shot', 'Butt', 'Reload']);
    final snap = actions.first as Json;
    expect((snap['times'], snap['mod']), (2, 'rangedMod'));
    expect(snap['cost'], [
      {'tracker': 'AP', 'amount': 2},
      {'tracker': 'ammo', 'amount': 2},
    ]);
    expect([for (final b in snap['bands'] as List) (b as Json)['min']], [10, 14, 18]);
    expect((actions[1] as Json)['cost'], [{'tracker': 'AP', 'amount': 1}], reason: 'melee spends no ammo');
  });

  test('armor, talents and the Constellation make a pack that passes the checks', () {
    final [vest] = armorFromMarkdown(armor);
    expect(vest['values'], {'grade': 3, 'apReduction': 1, 'carry': 4, 'modSlots': 2});
    final found = talentsFromMarkdown(talents);
    expect([for (final t in found) (t['name'], t['constellation'])],
        [('Test Star', true), ('Test Knack (Field)', null)]);
    final pack = SystemPack.fromJson({
      'id': 'solaris-arcanum',
      'name': 'Solaris Arcanum',
      'unit': 'sector',
      'compendium': {
        'kinds': kinds,
        'entries': [
          ...weaponsFromMarkdown(weapons),
          vest,
          for (final t in found) {...t}..remove('constellation'),
        ],
      },
      'advancement': constellation(['Test Star']),
      'sheet': sheet,
    });
    // A Beta (threat level 2) armiger with END 4, WIL 3, in the vest.
    final v = SheetValues(pack.sheet!, {...pack.sheet!.start(), 'END': 4, 'WIL': 3, 'threatLevel': 2},
        items: [(kind: 'Armor', values: pack.compendium!.start(pack.compendium!.entries['Test Vest']!))]);
    expect((v['stressThreshold'], v['AP.max'], v['AG.max'], v['rangedMod']), (9, 7, 3, 5));
    expect(pack.advancement!.nodes['Test Star']!.items, ['Test Star']);
  });
}
