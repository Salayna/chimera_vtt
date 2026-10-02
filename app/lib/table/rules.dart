import 'package:chimera_core/chimera_core.dart';
import 'package:tactical_engine/tactical_engine.dart' as te;

/// The scene's system pack: Generic for one this app doesn't know.
te.SystemPack packOf(Scene scene) => te.packFor(scene.settings.pack);

/// The rules engine for [scene]: its pack, its grid's scale, its regions.
te.TacticalEngine engineFor(Scene scene) {
  final grid = scene.settings.grid;
  final pack = packOf(scene);
  return te.TacticalEngine(
    pack: pack,
    topology: pack.topologyFor(cellSize: grid.cellSize, offset: grid.offset),
    regions: [
      for (final r in scene.regions.values)
        te.Region(
          id: r.id.value,
          shape: te.Polygon.rect(r.from, r.to),
          tags: [for (final t in r.tags.entries) (name: t.key, value: t.value)],
        ),
    ],
  );
}

/// [value] in [unit], for people: "3 cells", "15 ft", "1 sector".
String formatDistance(double value, String unit) {
  final v = value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);
  // Abbreviations (ft, m) don't take a plural.
  final plural = value != 1 && unit.length > 2 ? 's' : '';
  return '$v $unit$plural';
}

/// What the ruler shows from [a] to [b]: the distance in the pack's unit,
/// its range band if the pack has bands, and whether sight is blocked.
String rulerLabel(Scene scene, Point a, Point b) {
  final engine = engineFor(scene);
  final m = engine.measure(a, b);
  return [
    formatDistance(m.value, m.unit),
    ?m.band?.name,
    if (!engine.canSee(a, b)) 'no sight',
  ].join(' · ');
}
