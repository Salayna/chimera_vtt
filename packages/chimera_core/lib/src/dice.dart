import 'dart:math' as math;

/// One term of a [DiceFormula]: [count] dice of [sides], or a constant when
/// [sides] is null. [sign] is 1 or -1.
typedef DiceTerm = ({int sign, int count, int? sides});

/// A dice formula such as `2d6+3`, `d20` or `1d8+1d4-1`: dice and constants
/// added or subtracted.
// ponytail: no keep-highest (2d20kh1) or exploding dice; add them to the
// grammar when a system pack needs them.
final class DiceFormula {
  DiceFormula._(this.terms);

  static const maxTerms = 10;
  static const maxDice = 100;
  static const maxSides = 1000;
  static const maxConstant = 10000;

  static final _term = RegExp(r'\s*([+-])?\s*(?:(\d*)d(\d+)|(\d+))\s*');

  final List<DiceTerm> terms;

  /// Null unless [text] is a whole, valid formula within the limits.
  /// Players type it, so everything is bounded.
  static DiceFormula? tryParse(String text) {
    final s = text.toLowerCase();
    if (s.isEmpty || s.length > 100) return null;
    final terms = <DiceTerm>[];
    var at = 0;
    for (final m in _term.allMatches(s)) {
      // Terms must follow each other, and only the first may skip its sign.
      if (m.start != at || (terms.isNotEmpty && m[1] == null)) return null;
      at = m.end;
      final sign = m[1] == '-' ? -1 : 1;
      if (m[4] case final constant?) {
        final n = int.parse(constant);
        if (n > maxConstant) return null;
        terms.add((sign: sign, count: n, sides: null));
      } else {
        final count = m[2]!.isEmpty ? 1 : int.parse(m[2]!);
        final sides = int.parse(m[3]!);
        if (count < 1 || count > maxDice || sides < 2 || sides > maxSides) {
          return null;
        }
        terms.add((sign: sign, count: count, sides: sides));
      }
    }
    if (at != s.length || terms.isEmpty || terms.length > maxTerms) return null;
    if (terms.every((t) => t.sides == null)) return null; // No dice: not a roll.
    return DiceFormula._(terms);
  }

  /// The formula written the canonical way: `2d6 + 3`.
  @override
  String toString() {
    final b = StringBuffer();
    for (final (i, t) in terms.indexed) {
      if (i > 0) b.write(t.sign < 0 ? ' - ' : ' + ');
      if (i == 0 && t.sign < 0) b.write('-');
      b.write(t.sides == null ? '${t.count}' : '${t.count}d${t.sides}');
    }
    return b.toString();
  }

  /// Rolls every die: one list of faces per term, empty for constants.
  List<List<int>> roll(math.Random random) => [
        for (final t in terms)
          if (t.sides case final sides?)
            [for (var i = 0; i < t.count; i++) random.nextInt(sides) + 1]
          else
            const [],
      ];

  /// The total of [faces], as [roll] returned them.
  int total(List<List<int>> faces) {
    var sum = 0;
    for (final (i, t) in terms.indexed) {
      final value =
          t.sides == null ? t.count : faces[i].fold(0, (a, b) => a + b);
      sum += t.sign * value;
    }
    return sum;
  }
}
