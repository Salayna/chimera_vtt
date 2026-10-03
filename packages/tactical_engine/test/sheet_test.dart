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
    expect(error([for (var i = 0; i < 201; i++) {'name': 'f$i'}]), contains('at most 200'));
  });

  test('the built-in D&D 5e pack has a sheet', () {
    final dnd = builtInPacks['dnd5e']!.sheet!;
    final v = SheetValues(dnd, {...dnd.start(), 'DEX': 14, 'level': 5, 'maxHP': 38});
    expect((v['DEX.mod'], v['proficiency'], v['HP'], v['HP.max']), (2, 3, 8, 38));
  });
}
