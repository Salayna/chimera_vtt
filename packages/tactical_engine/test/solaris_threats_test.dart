import 'package:test/test.dart';

import '../tool/solaris_threats.dart';

// A made-up card in the notes' format, not one from the books.
const card = r'''
#### Test Raider

Some lore that isn't part of the card.

| Name: Test Raider | Threat Level: Beta | Combat Form: Rush |
| --- | --- | --- |
| Movement: ☐☐☐ | Dodge: ☐ | Fight Back: - |

| Attack Profiles: ☐☐ |  |
| --- | --- |
| Pipe Swing \| Melee Attacks: 2d20 \| Range: Point Blank <br> Grazing Hit (10+): 1 Stress | Scrap Gun \| Ranged Attacks: 1d20 \| Range: Adjacent <br> Precise Hit (14+): 1 CvW |
| Ammo: ☐☐☐ |  |

| Unique Actions: ☐ | Unique Reactions: ☐ |
| --- | --- |
| Holler: allies move a sector. | Duck: ignore one Grazing Hit. |

| Damage Trackers: |  |  |
| --- | --- | --- |
| MsW 🦴: ☐☐☐☐ (Vulnerable) | CvW 💘: ☐☐☐☐☐ | PsW 🧠: Immune |
| Armor Grade 🛡: ☐☐ | Stress ✩: ☐☐☐☐☐☐ |  |

> [!note]
> Overload Profile - Rattled: loses a Movement slot.

| Tags: | Organic | Synthetic | Physical Prowess: +3 |
| --- | --- | --- | --- |

#### Next heading
''';

void main() {
  test('a threat card becomes a pack token', () {
    final threats = threatsFromMarkdown(card, conditions: {'Synthetic'});
    expect(threats, hasLength(1));
    final t = threats.single;
    expect(t.name, 'Test Raider');
    expect(t.form, 'Rush (NPC)');
    expect(t.trackers.map((t) => (t.name, t.max)), [
      ('Ammo', 3),
      ('MsW', 4),
      ('CvW', 5),
      ('Armor Grade', 2),
      ('Stress', 6),
    ]);
    expect(t.conditions, {'Synthetic': null});
    final sections = {for (final s in t.card) s.title: s.text};
    expect(sections['Profile'], contains('Threat Level Beta'));
    expect(sections['Profile'], contains('Movement 3 · Dodge 1'));
    expect(sections['Profile'], contains('PsW Immune'));
    expect(sections['Profile'], contains('MsW Vulnerable'));
    expect(sections['Attack Profiles (2)'], contains('Pipe Swing | Melee Attacks: 2d20'));
    expect(sections['Attack Profiles (2)'], contains('\n'));
    expect(sections['Attack Profiles (2)'], isNot(contains('Ammo')));
    expect(sections['Unique Reactions (1)'], 'Duck: ignore one Grazing Hit.');
    expect(sections['Overload Profile - Rattled'], contains('loses a Movement slot'));
    expect(sections['Tags'], 'Organic · Synthetic · Physical Prowess: +3');
  });
}
