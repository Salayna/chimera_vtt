import 'package:tactical_engine/tactical_engine.dart';
import 'package:test/test.dart';

// A Solaris-like and a D&D-like character, with illustrative numbers.
const values = <String, Object>{
  'END': 3,
  'WIL': 2,
  'threatLevel': 2,
  'DEX': 15,
  'DEX.mod': 2,
  'armor.penalty': 1,
  'AP': 8,
  'Rush': true,
  'class': 'Fighter',
  'level': 5,
};

final types = {
  for (final MapEntry(:key, :value) in values.entries)
    key: switch (value) {
      num() => FormulaType.number,
      bool() => FormulaType.boolean,
      _ => FormulaType.text,
    },
};

Object run(String text, {int Function(int)? die}) {
  final f = Formula.parse(text);
  f.check(types);
  return f.eval(
    (n) => values[n]!,
    has: (t) => t == 'Marked for Death',
    die: die,
  );
}

String? parseError(String text) {
  try {
    Formula.parse(text);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

String? checkError(String text) {
  try {
    Formula.parse(text).check(types);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

void main() {
  test('the examples from the plan', () {
    expect(run('END + WIL + threatLevel'), 7);
    expect(run('8 - armor.penalty'), 7);
    expect(run('floor((DEX - 10) / 2)'), 2);
    expect(run('has("Marked for Death")'), true);
    expect(run('has("Prone")'), false);
    expect(run('level >= 5 and class == "Fighter"'), true);
    expect(run('if Rush then AP - 2 else AP'), 6);
  });

  test('precedence, unary minus, and whole results', () {
    expect(run('2 + 3 * 4'), 14);
    expect(run('(2 + 3) * 4'), 20);
    expect(run('-DEX.mod + 1'), -1);
    expect(run('7 / 2'), 3.5);
    expect(run('4 / 2'), isA<int>());
    expect(run('5 / 0'), 0);
    expect(run('not Rush or level > 3'), true);
    expect(run('max(1, DEX.mod, 3) + min(4, 2)'), 5);
    expect(run('round(2.5) + ceil(0.1) + abs(-3)'), 7);
  });

  test('dice are rolled by the caller', () {
    final rolled = <int>[];
    int die(int sides) {
      rolled.add(sides);
      return sides; // Every die shows its highest face.
    }

    expect(run('d20 + DEX.mod', die: die), 22);
    expect(run('2d6 + max(1, 2)', die: die), 14);
    expect(rolled, [20, 6, 6]);
    expect(Formula.parse('2d6').hasDice, true);
    expect(Formula.parse('DEX.mod').hasDice, false);
    expect(() => run('d20'), throwsStateError);
  });

  test('names it reads, dotted or not', () {
    expect(Formula.parse('d20 + DEX.mod + armor.penalty * level').names, {
      'DEX.mod',
      'armor.penalty',
      'level',
    });
    expect(Formula.parse('has("d20")').names, isEmpty);
  });

  test('a text literal is never an operator', () {
    expect(run('class == "or"'), false);
    expect(run('class != "("'), true);
  });

  test('bad syntax is refused with where it is', () {
    expect(parseError('1 +'), 'Formula ends too soon');
    expect(parseError('1 2'), 'Unexpected "2"');
    expect(parseError('(1'), 'Expected ")"');
    expect(parseError('1 # 2'), 'Unexpected character');
    expect(parseError('if Rush then 1'), 'Expected "else"');
    expect(parseError('1 < 2 < 3'), contains('chain'));
    expect(parseError('sqrt(4)'), 'Unknown function "sqrt"');
    expect(parseError('floor(1, 2)'), '"floor" takes 1 argument');
    expect(parseError('101d6'), contains('Dice are'));
    expect(parseError('d1'), contains('Dice are'));
    expect(parseError('2000000'), contains('at most'));
    expect(parseError('1+' * 300), contains('at most'));
    expect(parseError('${'(' * 40}1${')' * 40}'), 'Formula nested too deeply');
    expect(parseError('${'-' * 40}1'), 'Formula nested too deeply');
    try {
      Formula.parse('END + * 2');
    } on FormatException catch (e) {
      expect(e.offset, 6);
    }
  });

  test('wrong names and mixed types are refused', () {
    expect(checkError('STR + 1'), 'Unknown name "STR"');
    expect(checkError('class + 1'), '"+" needs a number, not a text');
    expect(checkError('level and Rush'), '"and" needs a boolean, not a number');
    expect(checkError('class == 1'), "Can't compare a text with a number");
    expect(
      checkError('if level then 1 else 2'),
      '"if" needs a boolean, not a number',
    );
    expect(
      checkError('if Rush then 1 else "x"'),
      contains('"then" gives a number'),
    );
    expect(checkError('has(level)'), '"has" needs a text, not a number');
    expect(Formula.parse('level > 3').check(types), FormulaType.boolean);
  });

  test('count and sum read items by their kind', () {
    final f = Formula.parse('8 - sum("Armor", "apReduction") - count("Heavy")');
    expect(f.items, {(kind: 'Armor', field: 'apReduction'), (kind: 'Heavy', field: null)});
    expect(f.check(types), FormulaType.number);
    num items(String kind, String? field) => switch ((kind, field)) {
          ('Armor', 'apReduction') => 2,
          ('Heavy', null) => 1,
          _ => 0,
        };
    expect(f.eval((n) => values[n]!, items: items), 5);
    expect(f.eval((n) => values[n]!), 8, reason: 'no items given: none');
    expect(parseError('count(class)'), contains('names in quotes'));
    expect(parseError('sum("Armor")'), '"sum" takes 2 arguments');
  });
}
