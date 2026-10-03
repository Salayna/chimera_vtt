part of 'pack.dart';

/// What a sheet field holds.
enum FieldType {
  /// A whole number the player sets, within optional bounds.
  number,
  text,

  /// One of the field's [FieldDef.options].
  choice,
  checkbox,

  /// A value from its [FieldDef.formula], never set by hand.
  computed,

  /// A number the player changes in play, such as AP or HP, whose bounds
  /// are formulas: AP at most `8 - armor.penalty`.
  tracker,

  /// The character's items of one compendium [FieldDef.kind], as cards.
  /// Formulas read them with `count` and `sum`, not by the field's name.
  items,
}

/// One field of a pack's sheet. Its [name] is what formulas read, so it's a
/// formula name (`DEX`, `DEX.mod`); [label] is what people see.
final class FieldDef {
  const FieldDef(
    this.name, {
    this.type = FieldType.number,
    String? label,
    this.text = '',
    this.min,
    this.max,
    this.value,
    this.options = const [],
    this.formula,
    this.kind,
    this.was = const [],
  }) : label = label ?? name;

  final String name;
  final String label;
  final FieldType type;

  /// What it is, shown on hover.
  final String text;

  /// A number's bounds, constant; a tracker's, computed. A tracker's [min]
  /// defaults to 0.
  final Formula? min;
  final Formula? max;

  /// What a new character starts with: a number, a text, a choice or a
  /// checkbox's constant, or a tracker's formula (`HP.max`). Defaults to
  /// the least it can be, empty or off.
  final Object? value;

  /// A number field's bounds, which are constants.
  int? get least => type == FieldType.number && min != null ? SheetDef._constant(min!) : null;
  int? get most => type == FieldType.number && max != null ? SheetDef._constant(max!) : null;

  /// A choice's options.
  final List<String> options;

  /// A computed field's formula.
  final Formula? formula;

  /// An items field's compendium kind.
  final String? kind;

  /// Its former names: a character saved before the module renamed it
  /// keeps its value.
  final List<String> was;

  Json toJson() => {
        'name': name,
        if (label != name) 'label': label,
        if (type != FieldType.number) 'type': type.name,
        if (text.isNotEmpty) 'text': text,
        if (min != null) 'min': _formulaJson(min!),
        if (max != null) 'max': _formulaJson(max!),
        if (value case final v?) 'value': v is Formula ? _formulaJson(v) : v,
        if (options.isNotEmpty) 'options': options,
        if (formula != null) 'formula': formula!.text,
        if (kind != null) 'kind': kind,
        if (was.isNotEmpty) 'was': was,
      };

  factory FieldDef.fromJson(Json json) {
    final name = _text(json['name'], 'field name', 30);
    if (!Formula.isName(name)) {
      throw FormatException('"$name" can\'t be a field name: use letters, '
          'digits, _ and dots, as in DEX.mod');
    }
    final type = FieldType.values.asNameMap()[json['type'] ?? 'number'] ??
        (throw FormatException('$name: unknown field type ${json['type']}'));
    Formula? formula(Object? v, String what) => switch (v) {
          null => null,
          // A number's bounds are constants; a tracker's may be formulas.
          int() => Formula.parse('$v'),
          String() when type == FieldType.tracker => _parse(v, '$name $what'),
          _ => throw FormatException('$name: $what is a whole number'),
        };
    final options = [
      for (final o in _list(json['options'], '$name options', 50))
        _text(o, 'option', 60),
    ];
    if (type == FieldType.choice && options.isEmpty) {
      throw FormatException('$name: a choice needs options');
    }
    final value = json['value'];
    return FieldDef(
      name,
      type: type,
      label: switch (json['label']) {
        null => null,
        final l => _text(l, 'field label', 60),
      },
      text: _text(json['text'] ?? '', 'field text', 500, empty: true),
      min: formula(json['min'], 'min'),
      max: formula(json['max'], 'max'),
      value: switch (type) {
        _ when value == null => null,
        FieldType.tracker => formula(value, 'value'),
        FieldType.number when value is int => value,
        FieldType.text when value is String => _text(value, '$name value', 2000, empty: true),
        FieldType.choice when options.contains(value) => value,
        FieldType.checkbox when value is bool => value,
        _ => throw FormatException('$name: not a ${type.name} value: $value'),
      },
      options: options,
      formula: type == FieldType.computed
          ? _parse(json['formula'] ?? (throw FormatException('$name: a computed field needs a formula')),
              '$name formula')
          : null,
      kind: type == FieldType.items ? _text(json['kind'], '$name kind', 30) : null,
      was: _was(json['was'], name),
    );
  }
}

Object _formulaJson(Formula f) => int.tryParse(f.text) ?? f.text;

Formula _parse(Object? text, String what) {
  if (text is! String) throw FormatException('$what: a formula is text');
  try {
    return Formula.parse(text);
  } on FormatException catch (e) {
    throw FormatException('$what: ${e.message}');
  }
}

/// A titled group of fields on a sheet: Attributes, Combat, Notes.
typedef SheetSection = ({String title, List<FieldDef> fields});

/// What a pack says a character holds: sections of fields, computed fields
/// and trackers. A character's sheet is its values, by field name.
final class SheetDef {
  /// [kinds] are the compendium's, by name: what items fields hold and
  /// `count` and `sum` read.
  SheetDef(this.sections,
      {this.kinds = const {}, this.groups = const {}, this.actions = const []}) {
    final seen = <String>{};
    for (final f in fields) {
      for (final n in [
        f.name,
        if (f.type == FieldType.tracker) ...['${f.name}.min', '${f.name}.max'],
      ]) {
        if (!seen.add(n)) throw FormatException('Two fields are called "$n"');
      }
    }
    for (final f in fields) {
      for (final w in f.was) {
        if (seen.contains(w)) throw FormatException('${f.name} was "$w", which is still a field');
      }
    }
    for (final f in fields) {
      if (f.type == FieldType.items) {
        if (!kinds.containsKey(f.kind)) {
          throw FormatException('${f.name}: no compendium kind "${f.kind}"');
        }
      } else {
        _typeOf(f.name, {});
      }
    }
  }

  static const maxFields = 200;

  final Map<String, SheetDef> kinds;

  /// The advancement's node groups, which `count` reads too.
  final Set<String> groups;

  final List<SheetSection> sections;

  /// Its buttons: the character's, or every item's of a kind.
  final List<ActionDef> actions;

  Iterable<FieldDef> get fields => sections.expand((s) => s.fields);

  late final Map<String, FieldDef> _byName = {for (final f in fields) f.name: f};

  /// Every name a formula can read on this sheet, with its type: each field,
  /// and each tracker's `.min` and `.max`.
  late final Map<String, FormulaType> types = {
    for (final f in fields)
      if (f.type != FieldType.items) ...{
      f.name: _typeOf(f.name, {}),
      if (f.type == FieldType.tracker) ...{
        '${f.name}.min': FormulaType.number,
        '${f.name}.max': FormulaType.number,
      },
    },
  };

  final _types = <String, FormulaType>{};

  /// A name's type, checking the formulas it depends on. [path] holds the
  /// names being checked, to refuse a field that depends on itself.
  FormulaType _typeOf(String name, Set<String> path) {
    if (_types[name] case final t?) return t;
    final (field, part) = _split(name);
    if (field == null) throw FormatException('Unknown name "$name"');
    if (!path.add(name)) throw FormatException('"$name" depends on itself');
    try {
      FormulaType? check(Formula? f, String what, [FormulaType? want]) {
        if (f == null) return null;
        if (f.hasDice) throw FormatException('$what rolls dice: a sheet can\'t');
        for (final (:kind, :field) in f.items) {
          final k = kinds[kind];
          if (k == null && (field != null || !groups.contains(kind))) {
            throw FormatException('$what: no compendium kind "$kind"');
          }
          if (field != null && k!.types[field] != FormulaType.number) {
            throw FormatException('$what: "$kind" has no number "$field"');
          }
        }
        final reads = {
          for (final n in f.names)
            if (_split(n).$1 != null) n: _typeOf(n, path),
        };
        final FormulaType got;
        try {
          got = f.check(reads);
        } on FormatException catch (e) {
          throw FormatException('$what: ${e.message}');
        }
        if (want != null && got != want) {
          throw FormatException('$what gives a ${got.name}, not a ${want.name}');
        }
        return got;
      }

      const number = FormulaType.number;
      final type = switch (field.type) {
        FieldType.computed => check(field.formula, field.name)!,
        FieldType.tracker when part == 'min' =>
          check(field.min, '${field.name} min', number) ?? number,
        FieldType.tracker when part == 'max' =>
          check(field.max, '${field.name} max', number) ?? number,
        FieldType.tracker => _trackerType(field, path, check),
        FieldType.number => number,
        FieldType.checkbox => FormulaType.boolean,
        FieldType.text || FieldType.choice => FormulaType.text,
        FieldType.items => throw FormatException(
            '"$name" is a list of items: read it with count or sum'),
      };
      return _types[name] = type;
    } finally {
      path.remove(name);
    }
  }

  /// A tracker's value is kept within its bounds, and may start at one, so
  /// it depends on both.
  FormulaType _trackerType(FieldDef field, Set<String> path,
      FormulaType? Function(Formula?, String, [FormulaType?]) check) {
    _typeOf('${field.name}.min', path);
    _typeOf('${field.name}.max', path);
    check(field.value as Formula?, '${field.name} value', FormulaType.number);
    return FormulaType.number;
  }

  /// The field [name] belongs to, and `min` or `max` for a tracker's bound.
  (FieldDef?, String?) _split(String name) {
    if (_byName[name] case final f?) return (f, null);
    final dot = name.lastIndexOf('.');
    if (dot < 0) return (null, null);
    final f = _byName[name.substring(0, dot)];
    final part = name.substring(dot + 1);
    return f?.type == FieldType.tracker && (part == 'min' || part == 'max')
        ? (f, part)
        : (null, null);
  }

  /// A new character's values: each field's start, after [given] (an
  /// item's entry's values, which its trackers may start from).
  Map<String, Object> start([Map<String, Object> given = const {}]) {
    final read = SheetValues(this, given);
    return {
      for (final f in fields)
        if (f.type != FieldType.computed && f.type != FieldType.items)
          f.name: given[f.name] ??
              (f.type == FieldType.tracker ? read._start(f) : _default(f)),
    };
  }

  Object _default(FieldDef f) => switch (f.type) {
        FieldType.number => f.value ?? (f.min == null ? 0 : _constant(f.min!)),
        FieldType.text => f.value ?? '',
        FieldType.choice => f.value ?? f.options.first,
        FieldType.checkbox => f.value ?? false,
        FieldType.computed || FieldType.tracker || FieldType.items => 0,
      };

  /// [values] kept to what this sheet holds: unknown and mistyped values
  /// dropped, numbers within their bounds, texts within 2000 characters.
  /// Sheets come from players, so everything read is cleaned first.
  Map<String, Object> clean(Map<String, Object?> values) => {
        for (final f in fields)
          if (values[f.name] ?? f.was.map((w) => values[w]).nonNulls.firstOrNull case final v?)
            f.name: ?_clean(f, v),
      };

  Object? _clean(FieldDef f, Object v) => switch (f.type) {
        FieldType.number when v is int => _clamp(v, f.min, f.max),
        FieldType.tracker when v is int => v.clamp(-maxValue, maxValue),
        FieldType.text when v is String => v.length > 2000 ? v.substring(0, 2000) : v,
        FieldType.choice when f.options.contains(v) => v,
        FieldType.checkbox when v is bool => v,
        _ => null,
      };

  static const maxValue = 999999;

  static int _constant(Formula f) => f.eval((_) => 0) as int;

  static int _clamp(int v, Formula? min, Formula? max) {
    if (min != null && v < _constant(min)) return _constant(min);
    if (max != null && v > _constant(max)) return _constant(max);
    return v;
  }

  Json toJson() => {
        'sections': [
          for (final s in sections)
            {
              'title': s.title,
              'fields': [for (final f in s.fields) f.toJson()],
            },
        ],
        if (actions.isNotEmpty) 'actions': _actionsJson(actions),
      };

  factory SheetDef.fromJson(Json json,
      {Map<String, SheetDef> kinds = const {}, Set<String> groups = const {}}) {
    final sections = [
      for (final s in _list(json['sections'], 'sheet sections', 20))
        (
          title: _text((s as Json)['title'], 'section title', 60),
          fields: [
            for (final f in _list(s['fields'], 'section fields', maxFields))
              FieldDef.fromJson(f as Json),
          ],
        ),
    ];
    if (sections.fold(0, (n, s) => n + s.fields.length) > maxFields) {
      throw const FormatException('A sheet has at most $maxFields fields');
    }
    return SheetDef(sections,
        kinds: kinds, groups: groups, actions: _actionsFromJson(json['actions']));
  }
}

/// A character's sheet read through its [sheet]: what formulas see. Stored
/// values first, each field's start otherwise; computed fields and tracker
/// bounds are worked out when read, trackers kept within their bounds.
final class SheetValues {
  SheetValues(this.sheet, this.stored,
      {this.has, this.items = const [], this.groups = const []});

  final SheetDef sheet;
  final Map<String, Object> stored;

  /// The character's items: each one's kind and values, for `count` and
  /// `sum`.
  final List<({String kind, Map<String, Object> values})> items;

  /// The group of each taken advancement node, which `count` counts too.
  final List<String> groups;

  /// Whether the character has a condition, for `has(…)`.
  final bool Function(String tag)? has;

  final _cache = <String, Object>{};

  /// The value of a formula name on the sheet. Throws an [ArgumentError]
  /// for a name the sheet doesn't have.
  Object operator [](String name) {
    if (_cache[name] case final v?) return v;
    final (field, part) = sheet._split(name);
    if (field == null) throw ArgumentError.value(name, 'name', 'Not on the sheet');
    final Object value;
    if (field.type == FieldType.computed) {
      value = _run(field.formula!);
    } else if (part == 'min') {
      value = field.min == null ? 0 : _whole(_run(field.min!) as num);
    } else if (part == 'max') {
      value = field.max == null ? SheetDef.maxValue : _whole(_run(field.max!) as num);
    } else if (field.type == FieldType.tracker) {
      final v = stored[name] as int? ?? _start(field);
      final min = number('$name.min'), max = number('$name.max');
      value = v > max ? max : (v < min ? min : v);
    } else {
      value = stored[name] ?? sheet._default(field);
    }
    return _cache[name] = value;
  }

  Object _run(Formula f) => run(f);

  /// [f]'s value on this sheet: its names read through [value] when given
  /// (an item's action reads the item first), [this] otherwise.
  Object run(Formula f, [Object Function(String name)? value]) {
    final v = f.eval(value ?? (n) => this[n], has: has, items: _items);
    return v is double && !v.isFinite ? 0 : v;
  }

  num _items(String kind, String? field) {
    final of = items.where((i) => i.kind == kind);
    if (field == null) return of.length + groups.where((g) => g == kind).length;
    final def = sheet.kinds[kind];
    if (def == null) return 0;
    return of.fold<num>(0, (sum, i) => sum + SheetValues(def, i.values).number(field));
  }

  /// A tracker's value on a new character.
  int _start(FieldDef tracker) => switch (tracker.value) {
        final Formula f => _whole(_run(f) as num),
        _ => number('${tracker.name}.min') as int,
      };

  num number(String name) => this[name] as num;

  static int _whole(num n) => n.round().clamp(-SheetDef.maxValue, SheetDef.maxValue);
}

/// One thing in a compendium, such as a weapon or a talent: values for its
/// kind's fields, and a card. A character's item is a copy of one.
final class Entry {
  const Entry(this.kind, this.name,
      {this.values = const {},
      this.card = const [],
      this.actions = const [],
      this.was = const []});

  final String kind;
  final String name;
  final Map<String, Object> values;
  final List<CardSection> card;

  /// Its own buttons, beside its kind's: a weapon's attack profiles.
  final List<ActionDef> actions;

  /// Its former names, which items copied from it may still carry.
  final List<String> was;

  Json toJson() => {
        'kind': kind,
        'name': name,
        if (values.isNotEmpty) 'values': values,
        if (card.isNotEmpty) 'card': _cardJson(card),
        if (actions.isNotEmpty) 'actions': _actionsJson(actions),
        if (was.isNotEmpty) 'was': was,
      };
}

/// A pack's entries, grouped in kinds. Each kind declares its fields like a
/// sheet's: data (a weapon's AP cost) and trackers (its ammo, at most its
/// `capacity`). Kinds can't read items.
final class Compendium {
  Compendium(this.kinds, List<Entry> entries, {this.kindsWere = const {}})
      : entries = {for (final e in entries) e.name: e};

  /// Each kind's former names, by kind.
  final Map<String, List<String>> kindsWere;

  /// The kind or entry an item names now: its own, or the one it was
  /// renamed to.
  String kindNow(String kind) => kinds.containsKey(kind)
      ? kind
      : kindsWere.entries.where((e) => e.value.contains(kind)).firstOrNull?.key ?? kind;

  String entryNow(String name) => entries.containsKey(name)
      ? name
      : entries.values.where((e) => e.was.contains(name)).firstOrNull?.name ?? name;

  static const maxKinds = 20;
  static const maxEntries = 1000;

  /// Each kind's fields, by its name.
  final Map<String, SheetDef> kinds;

  /// By name.
  final Map<String, Entry> entries;

  Iterable<Entry> of(String kind) => entries.values.where((e) => e.kind == kind);

  /// The values of a new item copied from [entry]: its own, and its kind's
  /// starts for the rest (a rifle's ammo full).
  Map<String, Object> start(Entry entry) => kinds[entry.kind]!.start(entry.values);

  Json toJson() => {
        'kinds': [
          for (final MapEntry(key: name, value: sheet) in kinds.entries)
            {
              'name': name,
              'fields': [for (final f in sheet.fields) f.toJson()],
              if (sheet.actions.isNotEmpty) 'actions': _actionsJson(sheet.actions),
              if (kindsWere[name] case final was? when was.isNotEmpty) 'was': was,
            },
        ],
        'entries': [for (final e in entries.values) e.toJson()],
      };

  factory Compendium.fromJson(Json json) {
    final kinds = <String, SheetDef>{};
    final kindsWere = <String, List<String>>{};
    for (final k in _list(json['kinds'], 'compendium kinds', maxKinds)) {
      final name = _text((k as Json)['name'], 'kind name', 30);
      kindsWere[name] = _was(k['was'], name);
      if (kinds.containsKey(name)) throw FormatException('Two kinds are called "$name"');
      kinds[name] = SheetDef.fromJson({
        'sections': [
          {'title': name, 'fields': k['fields'] ?? const []},
        ],
        'actions': k['actions'],
      });
    }
    final entries = <Entry>[];
    final names = <String>{};
    for (final e in _list(json['entries'], 'compendium entries', maxEntries)) {
      final name = _text((e as Json)['name'], 'entry name', 60);
      if (!names.add(name)) throw FormatException('Two entries are called "$name"');
      final kind = _text(e['kind'], '$name kind', 30);
      final sheet = kinds[kind] ?? (throw FormatException('$name: no kind "$kind"'));
      final values = <String, Object>{
        for (final MapEntry(:key, :value) in (e['values'] as Map? ?? const {}).entries)
          key as String: value as Object,
      };
      final clean = sheet.clean(values);
      for (final MapEntry(:key, :value) in values.entries) {
        // A value may still be under a field's former name.
        final field = sheet.fields.where((f) => f.name == key || f.was.contains(key)).firstOrNull;
        if (field == null || clean[field.name] != value) {
          throw FormatException('$name: not a value for "$key"');
        }
      }
      entries.add(Entry(kind, name,
          values: clean,
          card: _cardFromJson(e['card'], 10),
          actions: _actionsFromJson(e['actions']),
          was: _was(e['was'], name)));
    }
    return Compendium(kinds, entries, kindsWere: kindsWere);
  }
}

/// Former names: up to 5, each a name it no longer has.
List<String> _was(Object? json, String name) => [
      for (final w in _list(json, '$name was', 5))
        if (_text(w, '$name was', 60) != name) w as String,
    ];
