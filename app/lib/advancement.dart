import 'package:chimera_core/chimera_core.dart';
import 'package:tactical_engine/tactical_engine.dart';

/// What [c]'s sheet reads, with its items and taken nodes, for `count`.
SheetValues readSheet(SystemPack pack, Character c) {
  final nodes = pack.advancement?.nodes ?? const {};
  return SheetValues(pack.sheet!, c.values,
      items: [for (final i in c.items) (kind: i.kind, values: i.values)],
      groups: [for (final n in c.nodes) ?nodes[n]?.group]);
}

/// Why [c] can't take [node], or null when they can.
String? whyNot(SystemPack pack, Character c, AdvancementNode node) {
  if (c.nodes.contains(node.name)) return 'Taken';
  if (node.requires.isNotEmpty && !node.requires.any(c.nodes.contains)) {
    return 'Needs ${node.requires.length == 1 ? '' : 'one of '}${node.requires.join(', ')}';
  }
  final missing = [for (final n in node.requiresAll) if (!c.nodes.contains(n)) n];
  if (missing.isNotEmpty) return 'Needs ${missing.join(', ')}';
  final read = readSheet(pack, c);
  if (node.condition case final f? when read.run(f) != true) return 'Needs $f';
  final field = pack.advancement!.field;
  if (read.number(field) < node.cost) return 'Needs ${node.cost} $field';
  return null;
}

/// [c] having taken [node]: its cost paid, its grants added, its entries
/// given as items. Check [whyNot] first.
Character take(SystemPack pack, Character c, AdvancementNode node) {
  final read = readSheet(pack, c);
  final field = pack.advancement!.field;
  final values = {
    ...c.values,
    field: read.number(field).toInt() - node.cost,
  };
  for (final MapEntry(:key, :value) in node.adds.entries) {
    values[key] = read.number(key).toInt() + value;
  }
  final compendium = pack.compendium;
  return c.copyWith(
    // Grants stay within their fields' bounds.
    values: {...values, ...pack.sheet!.clean(values)},
    items: [
      ...c.items,
      for (final name in node.items)
        if (compendium?.entries[name] case final e?)
          Item(
              id: newId(),
              kind: e.kind,
              name: e.name,
              values: compendium!.start(e),
              card: e.card),
    ],
    nodes: [...c.nodes, node.name],
  );
}
