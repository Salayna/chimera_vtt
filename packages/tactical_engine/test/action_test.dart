import 'package:tactical_engine/tactical_engine.dart';
import 'package:test/test.dart';

Json pack({List<Json> sheetActions = const [], List<Json> entryActions = const []}) => {
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
          {'kind': 'Weapon', 'name': 'P9 Pistol', 'values': {'capacity': 5}, 'actions': entryActions},
        ],
      },
      'sheet': {
        'sections': [
          {
            'title': 'Combat',
            'fields': [
              {'name': 'FIN', 'value': 3},
              {'name': 'TL', 'value': 1},
              {'name': 'rangedMod', 'type': 'computed', 'formula': 'FIN + TL'},
              {'name': 'AP', 'type': 'tracker', 'max': 8, 'value': 'AP.max'},
            ],
          },
        ],
        'actions': sheetActions,
      },
    };

String? error(Json json) {
  try {
    SystemPack.fromJson(json);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

void main() {
  final quickShot = {
    'name': 'Quick Shot',
    'cost': [
      {'tracker': 'AP', 'amount': 3},
      {'tracker': 'ammo', 'amount': 2},
    ],
    'dice': 'd20',
    'mod': 'rangedMod',
    'times': 2,
    'bands': [
      {'name': 'Grazing', 'min': 16, 'text': '1 Stress'},
      {'name': 'Precise', 'min': 20, 'text': '1 Stress & 1 CvW'},
      {'name': 'Devastating', 'min': 24, 'text': '2 Stress & 2 CvW'},
    ],
  };

  test('actions on the sheet, a kind and an entry round-trip, and band rolls', () {
    final p = SystemPack.fromJson(pack(
      sheetActions: [
        {'name': 'Dodge', 'cost': [{'tracker': 'AP', 'amount': 2}], 'text': 'Remove their highest die.'},
      ],
      entryActions: [quickShot],
    ));
    expect(SystemPack.fromJson(p.toJson()).toJson(), p.toJson());
    final shot = p.compendium!.entries['P9 Pistol']!.actions.single;
    expect([for (final t in [12, 16, 19, 20, 30]) shot.bandFor(t)?.name],
        [null, 'Grazing', 'Grazing', 'Precise', 'Devastating']);
    expect(p.compendium!.kinds['Weapon']!.actions.single.name, 'Reload');
    expect(p.sheet!.actions.single.cost.single.tracker, 'AP');
  });

  test('a bad action is refused with the reason', () {
    expect(error(pack(entryActions: [{...quickShot, 'mod': 'STR'}])), contains('Unknown name "STR"'));
    expect(error(pack(entryActions: [{...quickShot, 'mod': 'd6'}])), contains('rolls dice'));
    expect(error(pack(entryActions: [{...quickShot, 'dice': 'd20 + FIN'}])), contains('dice only'));
    expect(error(pack(entryActions: [{...quickShot, 'cost': [{'tracker': 'HP'}]}])),
        contains('no tracker "HP"'));
    expect(error(pack(sheetActions: [{...quickShot, 'cost': [{'tracker': 'ammo'}]}])),
        contains('no tracker "ammo"'), reason: "the sheet's actions can't spend an item's");
    expect(error(pack(entryActions: [{...quickShot, 'bands': [{'name': 'A', 'min': 5}, {'name': 'B', 'min': 5}]}])),
        contains('lowest min up'));
    expect(error(pack(sheetActions: [{'name': 'X', 'bands': [{'name': 'A', 'min': 5}]}])),
        contains('need dice'));
    expect(error(pack(sheetActions: [{'name': 'X'}, {'name': 'X'}])), contains('Two actions'));
  });

  test("the built-in D&D 5e pack's attacks pass the checks a file would", () {
    final dnd = builtInPacks['dnd5e']!;
    expect(SystemPack.fromJson(dnd.toJson()).compendium!.entries['Rapier']!.actions.first.mod!.text,
        'max(STR.mod, DEX.mod) + proficiency');
  });
}
