import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart';

void main() {
  final pack = SystemPack.fromJson({
    'id': 'x',
    'name': 'X',
    'unit': 'sector',
    'compendium': {
      'kinds': [
        {
          'name': 'Weapon',
          'fields': [
            {'name': 'capacity'},
            {'name': 'ammo', 'type': 'tracker', 'max': 'capacity', 'value': 'ammo.max'},
          ],
          'actions': [
            {
              'name': 'Reload',
              'cost': [
                {'tracker': 'AP', 'amount': 2},
                {'tracker': 'ammo', 'amount': 'ammo - ammo.max'},
              ],
            },
          ],
        },
      ],
      'entries': [
        {
          'kind': 'Weapon',
          'name': 'P9 Pistol',
          'values': {'capacity': 5},
          'actions': [
            {
              'name': 'Quick Shot',
              'cost': [
                {'tracker': 'AP', 'amount': 3},
                {'tracker': 'ammo', 'amount': 'times'},
              ],
              'dice': 'd20',
              'mod': 'FIN + TL',
              'times': 2,
              'bands': [
                {'name': 'Grazing', 'min': 16, 'text': '1 Stress'},
              ],
            },
          ],
        },
      ],
    },
    'sheet': {
      'sections': [
        {
          'title': 'S',
          'fields': [
            {'name': 'FIN', 'value': 3},
            {'name': 'TL', 'value': 1},
            {'name': 'times', 'value': 2},
            {'name': 'AP', 'type': 'tracker', 'max': 8, 'value': 'AP.max'},
          ],
        },
      ],
    },
  });
  final pistol = Item(id: 'p', kind: 'Weapon', name: 'P9 Pistol', values: const {'capacity': 5, 'ammo': 3});
  final kade = Character(
      id: const CharacterId('k'),
      owner: const PlayerId('me'),
      system: 'x',
      name: 'Kade',
      values: pack.sheet!.start(),
      items: [pistol]);

  test("an item's action pays from the item and the character, and rolls", () {
    final [reload, shot] = actionsOf(pistol, pack);
    final use = useAction(pack, kade, shot, item: pistol) as UseAction;
    expect((use.dice, use.times, use.bands.single.name), ('d20+4', 2, 'Grazing'));
    expect(use.character.values['AP'], 5);
    expect(use.character.items.single.values['ammo'], 1);

    // One shot left: not enough for two.
    final low = use.character;
    expect(useAction(pack, low, shot, item: low.items.single), 'Not enough ammo');
    // A reload gives back what's missing, never above the max.
    final reloaded = useAction(pack, low, reload, item: low.items.single) as UseAction;
    expect(reloaded.character.items.single.values['ammo'], 5);
    expect(reloaded.dice, isNull);
  });

  test('a D&D 5e attack adds the better ability and proficiency', () {
    final dnd = builtInPacks['dnd5e']!;
    final dagger = Item(id: 'd', kind: 'Weapon', name: 'Dagger');
    final c = Character(
        id: const CharacterId('a'),
        owner: const PlayerId('me'),
        system: 'dnd5e',
        name: 'Ayla',
        values: {...dnd.sheet!.start(), 'DEX': 16, 'level': 5},
        items: [dagger]);
    final [attack, damage] = actionsOf(dagger, dnd);
    expect((useAction(dnd, c, attack, item: dagger) as UseAction).dice, 'd20+6');
    expect((useAction(dnd, c, damage, item: dagger) as UseAction).dice, '1d4+3');
  });
}
