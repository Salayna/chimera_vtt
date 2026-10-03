import 'package:chimera_core/chimera_core.dart';
import 'package:tactical_engine/tactical_engine.dart';

/// The actions an item has: its kind's, then its entry's (found by name, so
/// they follow the module).
List<ActionDef> actionsOf(Item item, SystemPack pack) => [
      ...?pack.compendium?.kinds[item.kind]?.actions,
      ...?pack.compendium?.entries[item.name]?.actions,
    ];

/// [action] used by [c] (from [item] when it's an item's), as the command
/// that pays its cost and asks the GM to roll it; or, as a [String], why it
/// can't be used: a cost it can't pay.
Object useAction(SystemPack pack, Character c, ActionDef action, {Item? item}) {
  final sheet = pack.sheet!;
  final read = SheetValues(sheet, c.values,
      items: [for (final i in c.items) (kind: i.kind, values: i.values)]);
  final kind = item == null ? null : pack.compendium?.kinds[item.kind];
  final itemRead = kind == null ? null : SheetValues(kind, item!.values);
  // An item's names first: its ammo, then the character's AP.
  Object lookup(String n) =>
      itemRead != null && kind!.types.containsKey(n) ? itemRead[n] : read[n];
  num number(Formula? f, num otherwise) =>
      f == null ? otherwise : read.run(f, lookup) as num;

  var values = {...c.values};
  var itemValues = {...?item?.values};
  for (final cost in action.cost) {
    final onItem = kind != null && kind.types.containsKey(cost.tracker);
    final from = onItem ? itemRead! : read;
    final now = from.number(cost.tracker);
    final next = now - number(cost.amount, 0).round();
    final min = from.number('${cost.tracker}.min'), max = from.number('${cost.tracker}.max');
    if (next < min) return 'Not enough ${cost.tracker}';
    final paid = next > max ? max : next;
    if (onItem) {
      itemValues[cost.tracker] = paid.toInt();
    } else {
      values[cost.tracker] = paid.toInt();
    }
  }
  final mod = number(action.mod, 0).round();
  final times = number(action.times, 1).round().clamp(1, ActionDef.maxTimes);
  return UseAction(
    c.copyWith(
      values: values,
      items: [
        for (final i in c.items) i.id == item?.id ? i.withValues(itemValues) : i,
      ],
    ),
    action: action.name,
    dice: switch (action.dice) {
      null => null,
      final d when mod == 0 => d,
      final d => '$d${mod > 0 ? '+' : ''}$mod',
    },
    times: times,
    bands: action.bands,
  );
}
