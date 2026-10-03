part of 'pack.dart';

/// One node of an advancement graph: a star of Solaris' Constellation, a
/// level of D&D's chain.
final class AdvancementNode {
  const AdvancementNode(
    this.name, {
    this.text = '',
    this.group,
    this.cost = 1,
    this.requires = const [],
    this.requiresAll = const [],
    this.condition,
    this.adds = const {},
    this.items = const [],
    this.x,
    this.y,
    this.was = const [],
  });

  final String name;

  /// Its former names, which characters who took it may still carry.
  final List<String> was;
  final String text;

  /// What it counts as: `count("Archetype")` counts taken nodes of a group
  /// as well as items of that kind.
  final String? group;

  /// Spent from the advancement's field.
  final int cost;

  /// Taken once any of these is: Solaris' adjacent stars, D&D's previous
  /// level. A node requiring none can be taken first.
  final List<String> requires;

  /// Taken once all of these are: the reward of a group of stars.
  final List<String> requiresAll;

  /// A rule it must also meet, read on the sheet: `XP >= 900`,
  /// `count("Archetype") < 3`.
  final Formula? condition;

  /// Number fields it raises (or lowers): `{"STR": 1}`.
  final Map<String, int> adds;

  /// Compendium entries it gives, as items: a talent.
  final List<String> items;

  /// Where it's drawn, in grid steps; null lays it out in a row.
  final double? x;
  final double? y;

  Json toJson() => {
        'name': name,
        if (text.isNotEmpty) 'text': text,
        if (group != null) 'group': group,
        if (cost != 1) 'cost': cost,
        if (requires.isNotEmpty) 'requires': requires,
        if (requiresAll.isNotEmpty) 'requiresAll': requiresAll,
        if (condition != null) 'condition': condition!.text,
        if (adds.isNotEmpty) 'adds': adds,
        if (items.isNotEmpty) 'items': items,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (was.isNotEmpty) 'was': was,
      };

  factory AdvancementNode.fromJson(Json json) {
    final name = _text(json['name'], 'node name', 60);
    List<String> names(String key) => [
          for (final n in _list(json[key], '$name $key', 20)) _text(n, '$name $key', 60),
        ];
    num? at(String key) => switch (json[key]) {
          null => null,
          final num v when v.isFinite && v.abs() <= 1000 => v,
          final v => throw FormatException('$name: $key is a number: $v'),
        };
    final cost = json['cost'] as int? ?? 1;
    if (cost < 0 || cost > 1000) throw FormatException('$name: a cost from 0 to 1000');
    return AdvancementNode(
      name,
      text: _text(json['text'] ?? '', '$name text', 2000, empty: true),
      group: switch (json['group']) {
        null => null,
        final g => _text(g, '$name group', 30),
      },
      cost: cost,
      requires: names('requires'),
      requiresAll: names('requiresAll'),
      condition: switch (json['condition']) {
        null => null,
        final c => _parse(c, '$name condition'),
      },
      adds: {
        for (final MapEntry(:key, :value) in (json['adds'] as Map? ?? const {}).entries)
          key as String: value as int,
      },
      items: names('items'),
      x: at('x')?.toDouble(),
      y: at('y')?.toDouble(),
      was: _was(json['was'], name),
    );
  }
}

/// A pack's graph of nodes a character takes, paying each one's cost from
/// [field]: a Constellation of stars bought with CP, or D&D's levels as a
/// chain reached with XP.
final class Advancement {
  Advancement(this.name, {required this.field, required List<AdvancementNode> nodes})
      : nodes = {for (final n in nodes) n.name: n};

  static const maxNodes = 300;

  /// What it's called on the sheet: Constellation, Levels.
  final String name;

  /// The sheet's number or tracker its costs are paid from.
  final String field;

  /// By name, in the file's order.
  final Map<String, AdvancementNode> nodes;

  /// The node [name] is now: itself, or the one it was renamed to.
  String nodeNow(String name) => nodes.containsKey(name)
      ? name
      : nodes.values.where((n) => n.was.contains(name)).firstOrNull?.name ?? name;

  /// The groups nodes count as, for `count`.
  Set<String> get groups => {for (final n in nodes.values) ?n.group};

  Json toJson() => {
        'name': name,
        'field': field,
        'nodes': [for (final n in nodes.values) n.toJson()],
      };

  factory Advancement.fromJson(Json json) {
    final nodes = [
      for (final n in _list(json['nodes'], 'nodes', maxNodes))
        AdvancementNode.fromJson(n as Json),
    ];
    final names = {for (final n in nodes) n.name};
    if (names.length != nodes.length) throw const FormatException('Two nodes share a name');
    for (final n in nodes) {
      for (final r in [...n.requires, ...n.requiresAll]) {
        if (!names.contains(r)) {
          throw FormatException('${n.name} requires "$r", which isn\'t a node of its track');
        }
      }
    }
    return Advancement(
      _text(json['name'], 'advancement name', 30),
      field: _text(json['field'], 'advancement field', 30),
      nodes: nodes,
    );
  }

  /// Its field, conditions, grants and items checked against the [sheet]
  /// and [compendium].
  void check(SheetDef? sheet, Compendium? compendium, {Set<String>? groups}) {
    final allGroups = groups ?? this.groups;
    final s = sheet ?? (throw const FormatException('An advancement needs a sheet'));
    final f = s.fields.where((f) => f.name == field).firstOrNull;
    if (f == null || (f.type != FieldType.number && f.type != FieldType.tracker)) {
      throw FormatException('$name spends "$field", which isn\'t a number on the sheet');
    }
    for (final n in nodes.values) {
      if (n.condition case final c?) {
        if (c.hasDice) throw FormatException('${n.name} condition rolls dice');
        final FormulaType got;
        try {
          got = c.check(s.types);
        } on FormatException catch (e) {
          throw FormatException('${n.name} condition: ${e.message}');
        }
        if (got != FormulaType.boolean) {
          throw FormatException('${n.name} condition gives a ${got.name}, not a boolean');
        }
        for (final (:kind, field: _) in c.items) {
          if (!s.kinds.containsKey(kind) && !allGroups.contains(kind)) {
            throw FormatException('${n.name} condition: no kind or group "$kind"');
          }
        }
      }
      for (final key in n.adds.keys) {
        final t = s.fields.where((f) => f.name == key).firstOrNull?.type;
        if (t != FieldType.number && t != FieldType.tracker) {
          throw FormatException('${n.name} adds to "$key", which isn\'t a number on the sheet');
        }
      }
      for (final e in n.items) {
        if (compendium?.entries[e] == null) throw FormatException('${n.name} gives "$e", which isn\'t an entry');
      }
    }
  }
}
