part of 'pack.dart';

/// A result a roll falls in: the highest band whose [min] it reaches, as
/// Solaris' Grazing (12+), Precise (16+) and Devastating (20+) hits, with
/// what it does.
typedef ActionBand = ({String name, int min, String text});

/// A tracker an action spends: [amount] of it, on the item when the item
/// has that tracker, on the character otherwise. A negative amount gives
/// back, as a reload: `ammo - ammo.max`.
typedef ActionCost = ({String tracker, Formula amount});

/// A button on a sheet or an item's card: it pays its [cost], rolls [dice]
/// plus [mod] [times] times, each roll in its band, and logs what happened.
/// It changes nothing on the target: its owner applies the damage.
final class ActionDef {
  const ActionDef(
    this.name, {
    this.text = '',
    this.cost = const [],
    this.dice,
    this.mod,
    this.times,
    this.bands = const [],
  });

  static const maxBands = 10;
  static const maxTimes = 10;

  final String name;
  final String text;
  final List<ActionCost> cost;

  /// Dice only, as `d20` or `2d6+1d4`; null for an action that doesn't
  /// roll.
  final String? dice;

  /// Added to each roll: `rangedMod`.
  final Formula? mod;

  /// How many rolls, each in its own band (Solaris rolls each d20 apart):
  /// 1 when null.
  final Formula? times;

  /// From lowest [ActionBand.min] up.
  final List<ActionBand> bands;

  /// The band [total] falls in, or null below them all (a miss).
  ActionBand? bandFor(int total) => bands.where((b) => total >= b.min).lastOrNull;

  /// Formulas each of a number: the costs, [mod] and [times], none rolling
  /// dice, reading [types]. Throws a [FormatException] saying what's wrong.
  void check(Map<String, FormulaType> types, Set<String> trackers) {
    void number(Formula? f, String what) {
      if (f == null) return;
      if (f.hasDice) throw FormatException('$name $what rolls dice: put them in "dice"');
      final FormulaType got;
      try {
        got = f.check(types);
      } on FormatException catch (e) {
        throw FormatException('$name $what: ${e.message}');
      }
      if (got != FormulaType.number) throw FormatException('$name $what gives a ${got.name}');
    }

    for (final c in cost) {
      if (!trackers.contains(c.tracker)) {
        throw FormatException('$name: no tracker "${c.tracker}" to pay with');
      }
      number(c.amount, 'cost');
    }
    number(mod, 'mod');
    number(times, 'times');
  }

  Json toJson() => {
        'name': name,
        if (text.isNotEmpty) 'text': text,
        if (cost.isNotEmpty)
          'cost': [
            for (final c in cost) {'tracker': c.tracker, 'amount': _formulaJson(c.amount)},
          ],
        if (dice != null) 'dice': dice,
        if (mod != null) 'mod': _formulaJson(mod!),
        if (times != null) 'times': _formulaJson(times!),
        if (bands.isNotEmpty)
          'bands': [
            for (final b in bands)
              {'name': b.name, 'min': b.min, if (b.text.isNotEmpty) 'text': b.text},
          ],
      };

  static final _dice = RegExp(r'^\d*d\d+(?:[+-](?:\d*d\d+|\d+))*$');

  factory ActionDef.fromJson(Json json) {
    final name = _text(json['name'], 'action name', 60);
    Formula? formula(Object? v, String what) => switch (v) {
          null => null,
          int() => Formula.parse('$v'),
          _ => _parse(v, '$name $what'),
        };
    final dice = switch (json['dice']) {
      null => null,
      final String d when _dice.hasMatch(d.replaceAll(' ', '')) && d.length <= 40 =>
        d.replaceAll(' ', ''),
      final d => throw FormatException('$name: "dice" is dice only, as d20 or 2d6+1: $d'),
    };
    final bands = [
      for (final b in _list(json['bands'], '$name bands', maxBands))
        (
          name: _text((b as Json)['name'], 'band name', 30),
          min: b['min'] as int,
          text: _text(b['text'] ?? '', 'band text', 500, empty: true),
        ),
    ];
    for (var i = 1; i < bands.length; i++) {
      if (bands[i].min <= bands[i - 1].min) {
        throw FormatException('$name: bands go from the lowest min up');
      }
    }
    if (bands.isNotEmpty && dice == null) {
      throw FormatException('$name: bands need dice to roll');
    }
    return ActionDef(
      name,
      text: _text(json['text'] ?? '', '$name text', 2000, empty: true),
      cost: [
        for (final c in _list(json['cost'], '$name cost', 5))
          (
            tracker: _text((c as Json)['tracker'], 'cost tracker', 30),
            amount: formula(c['amount'] ?? 1, 'cost')!,
          ),
      ],
      dice: dice,
      mod: formula(json['mod'], 'mod'),
      times: formula(json['times'], 'times'),
      bands: bands,
    );
  }
}

List<ActionDef> _actionsFromJson(Object? json) {
  final actions = [
    for (final a in _list(json, 'actions', 20)) ActionDef.fromJson(a as Json),
  ];
  if (actions.map((a) => a.name).toSet().length != actions.length) {
    throw const FormatException('Two actions share a name');
  }
  return actions;
}

List<Json> _actionsJson(List<ActionDef> actions) => [for (final a in actions) a.toJson()];

/// The trackers a sheet's actions can pay with.
Set<String> _trackers(SheetDef? sheet) => {
      for (final f in sheet?.fields ?? const <FieldDef>[])
        if (f.type == FieldType.tracker) f.name,
    };

/// Every action's formulas checked against what it reads: the sheet's for
/// the sheet's; an item's kind's and the sheet's for an item's.
void _checkActions(SheetDef? sheet, Compendium? compendium) {
  final types = sheet?.types ?? const <String, FormulaType>{};
  for (final a in sheet?.actions ?? const <ActionDef>[]) {
    a.check(types, _trackers(sheet));
  }
  for (final MapEntry(key: name, value: kind) in compendium?.kinds.entries ?? const <MapEntry<String, SheetDef>>[]) {
    final merged = {...types, ...kind.types};
    final trackers = {..._trackers(sheet), ..._trackers(kind)};
    for (final a in [
      ...kind.actions,
      for (final e in compendium!.of(name)) ...e.actions,
    ]) {
      a.check(merged, trackers);
    }
  }
}
