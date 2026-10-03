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
    expect(pack.advancements.single.nodes['Test Star']!.items, ['Test Star']);
  });

  test('classes and archetypes become entries and an archetype track', () {
    // Made-up files in the shape of chapter 4's.
    final found = classesFromMarkdown([
      '## Bastions\n\nLore.',
      '## Bastion Core Ability\n\n#### Stubborn:\n\nNever falls.',
      '## The Tester\n\n#### Tester Recommended Gear:\n\nA clipboard\n\n### Level 1\n\n'
          '#### Probe:\n\nAction - 1 AP: Pokes.\n\n### Level 2\n\nGain a Trick:\n\nOne more.\n\n'
          '#### Level 3:\n\n#### Check:\n\nChecks.',
    ]);
    expect(found.archetypes, {'Bastion': {'Tester': 3}});
    final byName = {for (final e in found.entries) e['name']: e};
    expect([for (final c in byName['Bastion core']!['card'] as List) (c as Json)['title']], ['Stubborn']);
    expect([for (final c in byName['Tester, Level 1']!['card'] as List) (c as Json)['title']],
        ['Recommended gear', 'Probe']);
    expect([for (final c in byName['Tester, Level 2']!['card'] as List) (c as Json)['title']], ['Gain a Trick']);
    expect(byName.containsKey('Tester, Level 3'), isTrue, reason: 'a level under #### still counts');

    final pack = SystemPack.fromJson({
      'id': 'solaris-arcanum',
      'name': 'Solaris Arcanum',
      'unit': 'sector',
      'compendium': {'kinds': kinds, 'entries': found.entries},
      'advancement': [threatLevels, archetypeTrack(found.archetypes), constellation(const [])],
      'sheet': sheet,
    });
    final nodes = pack.advancements[1].nodes;
    expect(nodes['Bastion']!.condition!.text, 'class == "Bastion" or count("Class") <= classPicks');
    expect(nodes['Tester 1']!.requires, ['Bastion']);
    expect((nodes['Tester 1']!.group, nodes['Tester 1']!.cost), ('Archetype', 1));
    expect(nodes['Tester 2']!.requires, ['Tester 1']);
    expect(nodes['Tester 3']!.items, ['Tester, Level 3']);
    expect(nodes.containsKey('Tester 4'), isFalse, reason: 'only the levels the notes have');
  });
}
