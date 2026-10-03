/// The type of a [Formula]'s value, or of a name it reads.
enum FormulaType { number, boolean, text }

/// A formula in a pack: a one-line expression computing a value from a
/// character, such as `END + WIL + threatLevel`, `floor((DEX - 10) / 2)` or
/// `d20 + DEX.mod`. It's text in the pack, read when the pack is installed and
/// interpreted by the app, never compiled into it. No loops, variables or side
/// effects, so every formula finishes, and its only randomness is dice, rolled
/// by the caller.
///
/// Values are numbers (`num`), booleans and text (for comparing choices, as
/// in `class == "Fighter"`). Names, dotted or not (`DEX.mod`), are whatever
/// the caller defines. Dividing by zero gives 0, so a formula never fails at
/// the table.
// ponytail: count and sum over a character's items come with items (brick 4).
final class Formula {
  Formula._(this.text, this._root, this.names, this.hasDice);

  static const maxLength = 500;
  static const maxDepth = 32;
  static const maxDice = 100;
  static const maxSides = 1000;
  static const maxNumber = 1000000;

  /// Function names with their least and most arguments.
  static const functions = {
    'min': (2, 10),
    'max': (2, 10),
    'floor': (1, 1),
    'ceil': (1, 1),
    'round': (1, 1),
    'abs': (1, 1),
    'has': (1, 1),
  };

  static const _keywords = {
    'and',
    'or',
    'not',
    'if',
    'then',
    'else',
    'true',
    'false',
  };

  static final _name = RegExp(r'^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$');
  static final _dice = RegExp(r'^\d*d\d+$');

  /// Whether a formula reads [name] as a name: not a keyword, a function
  /// or dice (`d6`), so a sheet can refuse fields formulas can't reach.
  static bool isName(String name) =>
      _name.hasMatch(name) &&
      !_dice.hasMatch(name) &&
      !_keywords.contains(name) &&
      !functions.containsKey(name);

  static final _token = RegExp(
    r'\s*(?:'
    r'(\d*d\d+)(?![\w.])|' // 1: dice
    r'(\d+(?:\.\d+)?)|' // 2: number
    r'"([^"]*)"|' // 3: text
    r'([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)|' // 4: name or keyword
    r'(==|!=|<=|>=|[-+*/<>(),])' // 5: symbol
    r')',
  );

  final String text;
  final _Node _root;

  /// Every name the formula reads, so a sheet can check that computed fields
  /// don't depend on themselves.
  final Set<String> names;

  /// Whether it rolls dice. A computed field's formula must not.
  final bool hasDice;

  /// Throws a [FormatException] pointing at the problem unless [text] is a
  /// whole, valid formula within the limits.
  factory Formula.parse(String text) {
    if (text.length > maxLength) {
      throw FormatException('A formula is at most $maxLength characters', text);
    }
    final tokens = <_Token>[];
    var at = 0;
    while (at < text.length) {
      final m = _token.matchAsPrefix(text, at);
      if (m == null || m.end == at) {
        if (text.substring(at).trim().isEmpty) break;
        throw FormatException(
          'Unexpected character',
          text,
          at + _lead(text, at),
        );
      }
      final start = at + _lead(text, at);
      at = m.end;
      if (m[1] != null) {
        tokens.add((kind: _Kind.dice, text: m[1]!, at: start));
      } else if (m[2] != null) {
        tokens.add((kind: _Kind.number, text: m[2]!, at: start));
      } else if (m[3] != null) {
        tokens.add((kind: _Kind.text, text: m[3]!, at: start));
      } else if (m[4] != null) {
        final kind = _keywords.contains(m[4]) ? _Kind.keyword : _Kind.name;
        tokens.add((kind: kind, text: m[4]!, at: start));
      } else {
        tokens.add((kind: _Kind.symbol, text: m[5]!, at: start));
      }
    }
    final parser = _Parser(text, tokens);
    final root = parser.expression();
    if (parser.peek != null) parser.fail('Unexpected "${parser.peek!.text}"');
    return Formula._(text, root, parser.names, parser.hasDice);
  }

  static int _lead(String s, int at) {
    var i = at;
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
    return i - at;
  }

  /// The type of the formula's value, given the type of every name it may
  /// read. Throws a [FormatException] for an unknown name or mixed types.
  FormulaType check(Map<String, FormulaType> types) => _root.type(this, types);

  /// The formula's value: a `num`, `bool` or `String`. [value] gives each
  /// name's value, of the type [check] was given; [has] says whether the
  /// character has a tag (false when omitted); [die] rolls one die of the
  /// given sides, and is needed only when [hasDice].
  Object eval(
    Object Function(String name) value, {
    bool Function(String tag)? has,
    int Function(int sides)? die,
  }) => _root.eval((value: value, has: has ?? (_) => false, die: die));

  @override
  String toString() => text;
}

enum _Kind { dice, number, text, name, keyword, symbol }

typedef _Token = ({_Kind kind, String text, int at});

typedef _Env = ({
  Object Function(String) value,
  bool Function(String) has,
  int Function(int)? die,
});

/// Recursive descent, lowest precedence first: if, or, and, not, comparison,
/// + and -, * and /, unary minus, then atoms.
final class _Parser {
  _Parser(this.source, this.tokens);

  final String source;
  final List<_Token> tokens;
  final names = <String>{};
  var hasDice = false;
  var _i = 0;
  var _depth = 0;

  _Token? get peek => _i < tokens.length ? tokens[_i] : null;

  Never fail(String message, [int? at]) =>
      throw FormatException(message, source, at ?? peek?.at ?? source.length);

  /// Whether the next token is the symbol or keyword [text], not a text
  /// literal that reads the same.
  bool _is(String text) {
    final t = peek;
    return t != null &&
        t.text == text &&
        (t.kind == _Kind.symbol || t.kind == _Kind.keyword);
  }

  bool _accept(String text) {
    if (!_is(text)) return false;
    _i++;
    return true;
  }

  void _expect(String text) {
    if (!_accept(text)) {
      fail(
        peek == null
            ? 'Expected "$text"'
            : 'Expected "$text", found "${peek!.text}"',
      );
    }
  }

  _Node expression() {
    if (++_depth > Formula.maxDepth) fail('Formula nested too deeply');
    try {
      final at = peek?.at ?? source.length;
      if (_accept('if')) {
        final condition = expression();
        _expect('then');
        final then = expression();
        _expect('else');
        return _If(at, condition, then, expression());
      }
      return _or();
    } finally {
      _depth--;
    }
  }

  _Node _or() {
    var left = _and();
    while (_is('or')) {
      final at = peek!.at;
      _i++;
      left = _Binary(at, 'or', left, _and());
    }
    return left;
  }

  _Node _and() {
    var left = _not();
    while (_is('and')) {
      final at = peek!.at;
      _i++;
      left = _Binary(at, 'and', left, _not());
    }
    return left;
  }

  _Node _not() {
    final at = peek?.at ?? source.length;
    if (_accept('not')) return _Unary(at, 'not', _nested(_not));
    return _comparison();
  }

  static const _comparisons = {'==', '!=', '<', '<=', '>', '>='};

  _Node _comparison() {
    final left = _sum();
    final t = peek;
    if (t == null || t.kind != _Kind.symbol || !_comparisons.contains(t.text)) {
      return left;
    }
    _i++;
    final node = _Binary(t.at, t.text, left, _sum());
    final next = peek;
    if (next != null &&
        next.kind == _Kind.symbol &&
        _comparisons.contains(next.text)) {
      fail('Comparisons don\'t chain: use "and"');
    }
    return node;
  }

  _Node _sum() {
    var left = _product();
    for (var t = _take('+', '-'); t != null; t = _take('+', '-')) {
      left = _Binary(t.at, t.text, left, _product());
    }
    return left;
  }

  _Node _product() {
    var left = _unary();
    for (var t = _take('*', '/'); t != null; t = _take('*', '/')) {
      left = _Binary(t.at, t.text, left, _unary());
    }
    return left;
  }

  /// The next token, consumed, when it's the symbol [a] or [b].
  _Token? _take(String a, String b) {
    final t = peek;
    if (t == null || t.kind != _Kind.symbol || (t.text != a && t.text != b)) {
      return null;
    }
    _i++;
    return t;
  }

  _Node _unary() {
    final at = peek?.at ?? source.length;
    if (_accept('-')) return _Unary(at, '-', _nested(_unary));
    return _atom();
  }

  _Node _nested(_Node Function() parse) {
    if (++_depth > Formula.maxDepth) fail('Formula nested too deeply');
    try {
      return parse();
    } finally {
      _depth--;
    }
  }

  _Node _atom() {
    final t = peek;
    if (t == null) fail('Formula ends too soon');
    _i++;
    switch (t.kind) {
      case _Kind.number:
        final n = num.parse(t.text);
        if (n > Formula.maxNumber) {
          fail('Numbers are at most ${Formula.maxNumber}', t.at);
        }
        return _Literal(t.at, n);
      case _Kind.dice:
        final [count, sides] = t.text.split('d');
        final c = count.isEmpty ? 1 : int.parse(count);
        final s = int.parse(sides);
        if (c < 1 || c > Formula.maxDice || s < 2 || s > Formula.maxSides) {
          fail(
            'Dice are 1 to ${Formula.maxDice} dice of 2 to ${Formula.maxSides} sides',
            t.at,
          );
        }
        hasDice = true;
        return _Dice(t.at, c, s);
      case _Kind.text:
        return _Literal(t.at, t.text);
      case _Kind.keyword when t.text == 'true' || t.text == 'false':
        return _Literal(t.at, t.text == 'true');
      case _Kind.name when _is('('):
        final arity = Formula.functions[t.text];
        if (arity == null) fail('Unknown function "${t.text}"', t.at);
        _i++;
        final args = <_Node>[];
        if (!_accept(')')) {
          do {
            args.add(expression());
          } while (_accept(','));
          _expect(')');
        }
        final (least, most) = arity;
        if (args.length < least || args.length > most) {
          fail(
            least == most
                ? '"${t.text}" takes $least argument${least == 1 ? '' : 's'}'
                : '"${t.text}" takes $least to $most arguments',
            t.at,
          );
        }
        return _Call(t.at, t.text, args);
      case _Kind.name:
        names.add(t.text);
        return _Name(t.at, t.text);
      case _Kind.symbol when t.text == '(':
        final inner = expression();
        _expect(')');
        return inner;
      default:
        fail('Unexpected "${t.text}"', t.at);
    }
  }
}

sealed class _Node {
  _Node(this.at);

  /// Where the node starts in the formula, for error messages.
  final int at;

  FormulaType type(Formula f, Map<String, FormulaType> types);
  Object eval(_Env env);
}

Never _typeError(Formula f, int at, String message) =>
    throw FormatException(message, f.text, at);

void _want(
  Formula f,
  _Node node,
  FormulaType want,
  Map<String, FormulaType> types,
  String what,
) {
  final got = node.type(f, types);
  if (got != want) {
    _typeError(f, node.at, '$what needs a ${want.name}, not a ${got.name}');
  }
}

final class _Literal extends _Node {
  _Literal(super.at, this.value);

  final Object value;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) =>
      switch (value) {
        num() => FormulaType.number,
        bool() => FormulaType.boolean,
        _ => FormulaType.text,
      };

  @override
  Object eval(_Env env) => value;
}

final class _Dice extends _Node {
  _Dice(super.at, this.count, this.sides);

  final int count;
  final int sides;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) =>
      FormulaType.number;

  @override
  Object eval(_Env env) {
    final die =
        env.die ?? (throw StateError('This formula rolls dice: pass a die'));
    var total = 0;
    for (var i = 0; i < count; i++) {
      total += die(sides);
    }
    return total;
  }
}

final class _Name extends _Node {
  _Name(super.at, this.name);

  final String name;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) =>
      types[name] ?? _typeError(f, at, 'Unknown name "$name"');

  @override
  Object eval(_Env env) => env.value(name);
}

final class _Unary extends _Node {
  _Unary(super.at, this.op, this.operand);

  final String op;
  final _Node operand;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) {
    final want = op == 'not' ? FormulaType.boolean : FormulaType.number;
    _want(f, operand, want, types, '"$op"');
    return want;
  }

  @override
  Object eval(_Env env) =>
      op == 'not' ? !(operand.eval(env) as bool) : -(operand.eval(env) as num);
}

final class _Binary extends _Node {
  _Binary(super.at, this.op, this.left, this.right);

  final String op;
  final _Node left;
  final _Node right;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) {
    switch (op) {
      case 'and' || 'or':
        _want(f, left, FormulaType.boolean, types, '"$op"');
        _want(f, right, FormulaType.boolean, types, '"$op"');
        return FormulaType.boolean;
      case '==' || '!=':
        final l = left.type(f, types);
        final r = right.type(f, types);
        if (l != r) {
          _typeError(f, at, 'Can\'t compare a ${l.name} with a ${r.name}');
        }
        return FormulaType.boolean;
      default:
        _want(f, left, FormulaType.number, types, '"$op"');
        _want(f, right, FormulaType.number, types, '"$op"');
        return const {'<', '<=', '>', '>='}.contains(op)
            ? FormulaType.boolean
            : FormulaType.number;
    }
  }

  @override
  Object eval(_Env env) {
    switch (op) {
      case 'and':
        return (left.eval(env) as bool) && (right.eval(env) as bool);
      case 'or':
        return (left.eval(env) as bool) || (right.eval(env) as bool);
      case '==':
        return left.eval(env) == right.eval(env);
      case '!=':
        return left.eval(env) != right.eval(env);
    }
    final a = left.eval(env) as num;
    final b = right.eval(env) as num;
    return switch (op) {
      '+' => a + b,
      '-' => a - b,
      '*' => a * b,
      '/' => b == 0 ? 0 : _whole(a / b),
      '<' => a < b,
      '<=' => a <= b,
      '>' => a > b,
      _ => a >= b,
    };
  }
}

/// 4 / 2 is 2, not 2.0.
num _whole(double d) => d == d.truncateToDouble() ? d.toInt() : d;

final class _If extends _Node {
  _If(super.at, this.condition, this.then, this.otherwise);

  final _Node condition;
  final _Node then;
  final _Node otherwise;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) {
    _want(f, condition, FormulaType.boolean, types, '"if"');
    final a = then.type(f, types);
    final b = otherwise.type(f, types);
    if (a != b) {
      _typeError(f, at, '"then" gives a ${a.name} but "else" a ${b.name}');
    }
    return a;
  }

  @override
  Object eval(_Env env) =>
      (condition.eval(env) as bool) ? then.eval(env) : otherwise.eval(env);
}

final class _Call extends _Node {
  _Call(super.at, this.function, this.args);

  final String function;
  final List<_Node> args;

  @override
  FormulaType type(Formula f, Map<String, FormulaType> types) {
    if (function == 'has') {
      _want(f, args.single, FormulaType.text, types, '"has"');
      return FormulaType.boolean;
    }
    for (final a in args) {
      _want(f, a, FormulaType.number, types, '"$function"');
    }
    return FormulaType.number;
  }

  @override
  Object eval(_Env env) {
    if (function == 'has') return env.has(args.single.eval(env) as String);
    final values = [for (final a in args) a.eval(env) as num];
    return switch (function) {
      'min' => values.reduce((a, b) => a < b ? a : b),
      'max' => values.reduce((a, b) => a > b ? a : b),
      'floor' => values.single.floor(),
      'ceil' => values.single.ceil(),
      'round' => values.single.round(),
      _ => values.single.abs(),
    };
  }
}
