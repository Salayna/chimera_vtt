import 'package:tactical_engine/tactical_engine.dart';
import 'package:test/test.dart';

// A D&D-like sheet and Solaris-like trackers, with illustrative numbers.
final json = {
  'sections': [
    {
      'title': 'Abilities',
      'fields': [
        {'name': 'DEX', 'label': 'Dexterity', 'min': 1, 'max': 20, 'value': 10},
        {'name': 'DEX.mod', 'type': 'computed', 'formula': 'floor((DEX - 10) / 2)'},
        {'name': 'class', 'type': 'choice', 'options': ['Fighter', 'Wizard']},
        {'name': 'level', 'min': 1, 'max': 20},
        {'name': 'veteran', 'type': 'computed', 'formula': 'level >= 5'},
      ],
    },
    {
      'title': 'Combat',
      'fields': [
        {'name': 'armor', 'min': 0, 'max': 4},
        {'name': 'AP', 'type': 'tracker', 'max': '8 - armor', 'value': 'AP.max'},
        {'name': 'Stress', 'type': 'tracker', 'max': 'END + 2'},
        {'name': 'END', 'value': 3},
        {'name': 'notes', 'type': 'text'},
        {'name': 'inspired', 'type': 'checkbox'},
      ],
    },
  ],
};

String? error(Object? sheet) {
  try {
    SheetDef.fromJson({
      'sections': [
        {'title': 'S', 'fields': sheet},
      ],
    });
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

void main() {
  final sheet = SheetDef.fromJson(json);

  test('a new character starts each field at its start', () {
    expect(sheet.start(), {
      'DEX': 10,
      'class': 'Fighter',
      'level': 1,
      'armor': 0,
      'AP': 8,
      'Stress': 0,
      'END': 3,
      'notes': '',
      'inspired': false,
    });
  });

  test('formulas read stored values, computed fields and tracker bounds', () {
    final v = SheetValues(sheet, {...sheet.start(), 'DEX': 15, 'armor': 2, 'level': 5});
    expect(v['DEX.mod'], 2);
    expect(v['veteran'], true);
    expect(v['AP.max'], 6);
    expect(v['AP'], 6, reason: 'kept within its bound');
    expect(v['Stress.max'], 5);
    expect(v['notes'], '');
    expect(() => v['STR'], throwsArgumentError);
    expect(sheet.types['veteran'], FormulaType.boolean);
    expect(sheet.types['AP.max'], FormulaType.number);
  });

  test('values from a player are cleaned', () {
    expect(
      sheet.clean({
        'DEX': 99,
        'class': 'Bard',
        'level': '3',
        'AP': 5,
        'notes': 'x' * 3000,
        'stranger': 1,
        'DEX.mod': 9,
      }),
      {'DEX': 20, 'AP': 5, 'notes': 'x' * 2000},
    );
  });

  test('it round-trips through a pack file', () {
    final pack = SystemPack.fromJson({'id': 'x', 'name': 'X', 'unit': 'ft', 'sheet': json});
    final again = SystemPack.fromJson(pack.toJson());
    expect(again.sheet!.toJson(), pack.sheet!.toJson());
    expect(again.sheet!.fields.first.label, 'Dexterity');
  });

  test('a bad sheet is refused with the reason', () {
    expect(error([{'name': 'my field'}]), contains("can't be a field name"));
    expect(error([{'name': 'd6'}]), contains("can't be a field name"));
    expect(error([{'name': 'a'}, {'name': 'a'}]), contains('Two fields'));
    expect(error([{'name': 'AP', 'type': 'tracker'}, {'name': 'AP.max'}]), contains('Two fields'));
    expect(error([{'name': 'a', 'type': 'computed', 'formula': 'b + 1'}]), contains('Unknown name "b"'));
    expect(error([{'name': 'a', 'type': 'computed', 'formula': 'd20'}]), contains('rolls dice'));
    expect(
        error([
          {'name': 'a', 'type': 'computed', 'formula': 'b'},
          {'name': 'b', 'type': 'computed', 'formula': 'a'},
        ]),
        contains('depends on itself'));
    expect(error([{'name': 'AP', 'type': 'tracker', 'max': 'AP + 1'}]), contains('depends on itself'));
    expect(error([{'name': 'a', 'type': 'computed', 'formula': '1 +'}]), contains('a formula: '));
    expect(error([{'name': 'a', 'max': '3'}]), contains('whole number'));
    expect(error([{'name': 'a', 'type': 'choice'}]), contains('needs options'));
    expect(error([{'name': 'a', 'type': 'checkbox', 'value': 1}]), contains('not a checkbox value'));
    expect(error([{'name': 'a', 'type': 'tracker', 'max': '"x"'}]), contains('gives a text'));
    expect(error([{'name': 'a', 'type': 'spell'}]), contains('unknown field type'));
    expect(SheetDef.fromJson({...json, 'layout': 'tabs'}).toJson()['layout'], 'tabs');
    expect(() => SheetDef.fromJson({...json, 'layout': 'grid'}), throwsFormatException);
    expect(error([for (var i = 0; i < 201; i++) {'name': 'f$i'}]), contains('at most 200'));
  });

  test('the built-in D&D 5e pack has a sheet', () {
    final dnd = builtInPacks['dnd5e']!.sheet!;
    final v = SheetValues(dnd, {...dnd.start(), 'DEX': 14, 'level': 5, 'maxHP': 38});
    expect((v['DEX.mod'], v['proficiency'], v['HP'], v['HP.max']), (2, 3, 8, 38));
  });

  group('compendium and items', () {
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
          },
          {
            'name': 'Armor',
            'fields': [
              {'name': 'grade'},
              {'name': 'apReduction'},
            ],
          },
        ],
        'entries': [
          {
            'kind': 'Weapon',
            'name': 'P9 Pistol',
            'values': {'capacity': 5},
            'card': [{'title': 'Precision Shot', 'text': '2 AP, 1d20'}],
          },
          {'kind': 'Armor', 'name': 'Vulture', 'values': {'grade': 2, 'apReduction': 1}},
        ],
      },
      'sheet': {
        'sections': [
          {
            'title': 'Combat',
            'fields': [
              {'name': 'AP', 'type': 'tracker', 'max': '8 - sum("Armor", "apReduction")'},
              {'name': 'guns', 'type': 'computed', 'formula': 'count("Weapon")'},
              {'name': 'weapons', 'type': 'items', 'kind': 'Weapon'},
            ],
          },
        ],
      },
    });
    final compendium = pack.compendium!;

    test('an item starts as a copy of its entry, its trackers full', () {
      expect(compendium.start(compendium.entries['P9 Pistol']!), {'capacity': 5, 'ammo': 5});
      expect(compendium.of('Armor').single.name, 'Vulture');
      expect(SystemPack.fromJson(pack.toJson()).compendium!.toJson(), compendium.toJson());
    });

    test('formulas count items and sum their fields', () {
      final items = [
        (kind: 'Armor', values: compendium.start(compendium.entries['Vulture']!)),
        (kind: 'Weapon', values: {'capacity': 5, 'ammo': 2}),
        (kind: 'Weapon', values: {'capacity': 6, 'ammo': 6}),
      ];
      final v = SheetValues(pack.sheet!, const {}, items: items);
      expect((v['AP.max'], v['guns']), (7, 2));
      expect(pack.sheet!.types.containsKey('weapons'), isFalse);
    });

    test('a bad compendium or a sheet reading it wrong is refused', () {
      String? error(Json compendium, [List<Json> fields = const []]) {
        try {
          SystemPack.fromJson({
            'id': 'x',
            'name': 'X',
            'unit': 'ft',
            'compendium': compendium,
            'sheet': {
              'sections': [{'title': 'S', 'fields': fields}],
            },
          });
          return null;
        } on FormatException catch (e) {
          return e.message;
        }
      }

      final kinds = [
        {'name': 'Armor', 'fields': [{'name': 'grade'}, {'name': 'note', 'type': 'text'}]},
      ];
      expect(error({'kinds': kinds, 'entries': [{'kind': 'Gun', 'name': 'G'}]}), contains('no kind "Gun"'));
      expect(error({'kinds': kinds, 'entries': [{'kind': 'Armor', 'name': 'A', 'values': {'grade': 'x'}}]}),
          contains('not a value for "grade"'));
      expect(error({'kinds': kinds, 'entries': [{'kind': 'Armor', 'name': 'A', 'values': {'speed': 1}}]}),
          contains('not a value for "speed"'));
      expect(error({'kinds': [...kinds, ...kinds]}), contains('Two kinds'));
      expect(error({'kinds': kinds}, [{'name': 'a', 'type': 'computed', 'formula': 'count("Gun")'}]),
          contains('no compendium kind "Gun"'));
      expect(error({'kinds': kinds}, [{'name': 'a', 'type': 'computed', 'formula': 'sum("Armor", "note")'}]),
          contains('has no number "note"'));
      expect(error({'kinds': kinds}, [{'name': 'a', 'type': 'items', 'kind': 'Gun'}]),
          contains('no compendium kind "Gun"'));
      expect(error({'kinds': kinds}, [
        {'name': 'a', 'type': 'items', 'kind': 'Armor'},
        {'name': 'b', 'type': 'computed', 'formula': 'a'},
      ]), contains('list of items'));
      expect(
          error({
            'kinds': [
              {'name': 'Armor', 'fields': [{'name': 'n', 'type': 'computed', 'formula': 'count("Armor")'}]},
            ],
          }),
          contains('no compendium kind'),
          reason: 'kinds read their own fields, not items');
    });
  });
}
