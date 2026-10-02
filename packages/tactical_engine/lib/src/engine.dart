import 'dart:math' as math;

import 'geometry.dart';
import 'pack.dart';
import 'topology.dart';

/// An area that carries tags: a sector, a zone, a spell area.
final class Region {
  const Region({required this.id, required this.shape, this.tags = const []});

  final String id;
  final Shape shape;
  final List<Tag> tags;
}

final class Measurement {
  const Measurement(this.value, this.unit, this.band);

  final double value;
  final String unit;

  /// Null when the pack defines no bands.
  final RangeBand? band;

  @override
  String toString() => '$value $unit${band == null ? '' : ' (${band!.name})'}';
}

/// An effect in force, with the tag it comes from.
typedef ActiveEffect = ({Effect effect, Tag tag});

/// What a move costs and what stands in its way.
typedef MoveCheck = ({
  /// In pack units: AP for Solaris, feet for D&D 5e.
  double cost,

  /// Checks required by the regions entered, for example Traversal.
  List<String> checks,

  /// Whether a region entered is already full.
  bool blocked,
});

/// Answers rules questions about one scene. Pure: no state, no game system,
/// no rendering. Everything system-specific comes from [pack].
final class TacticalEngine {
  const TacticalEngine({
    required this.pack,
    required this.topology,
    this.regions = const [],
  });

  final SystemPack pack;
  final Topology topology;
  final List<Region> regions;

  Measurement measure(Point a, Point b) {
    final value = topology.steps(a, b) * pack.unitsPerStep;
    return Measurement(value, pack.unit, pack.bandFor(value));
  }

  Iterable<Region> regionsAt(Point p) =>
      regions.where((r) => r.shape.contains(p));

  /// The tags in force at [p]: its regions' tags plus the entity's own
  /// [conditions].
  List<Tag> tagsAt(Point p, {List<Tag> conditions = const []}) =>
      [for (final r in regionsAt(p)) ...r.tags, ...conditions];

  List<ActiveEffect> effectsAt(Point p, {List<Tag> conditions = const []}) => [
        for (final tag in tagsAt(p, conditions: conditions))
          for (final effect in pack.effectsOf(tag)) (effect: effect, tag: tag),
      ];

  /// Whether [a] sees [b]. A sight-blocking region stops sight passing
  /// through it, but not into or out of it.
  bool canSee(Point a, Point b) => !regions.any((r) =>
      _hasEffect<BlocksSight>(r) &&
      !r.shape.contains(a) &&
      !r.shape.contains(b) &&
      r.shape.crossesInterior(a, b));

  /// [occupants] are the positions of everyone else, used for limits.
  MoveCheck checkMove(Point from, Point to,
      {Iterable<Point> occupants = const []}) {
    final entered = [
      for (final r in regionsAt(to))
        if (!r.shape.contains(from)) r,
    ];
    // ponytail: only the destination's cost counts, not the regions crossed
    // on the way. Walk the path cell by cell when a pack needs it.
    final multiplier = [
      for (final e in effectsAt(to))
        if (e.effect case MoveCost(:final multiplier)) multiplier,
    ].fold(1.0, math.max);
    return (
      cost: topology.steps(from, to) * pack.unitsPerStep * multiplier,
      checks: [
        for (final r in entered)
          for (final tag in r.tags)
            for (final effect in pack.effectsOf(tag))
              if (effect case EntryCheck(:final check)) check,
      ],
      blocked: entered.any((r) => r.tags.any((tag) => pack
          .effectsOf(tag)
          .whereType<OccupantLimit>()
          .any((limit) =>
              occupants.where(r.shape.contains).length >= limit.max))),
    );
  }

  bool _hasEffect<T extends Effect>(Region r) =>
      r.tags.any((tag) => pack.effectsOf(tag).any((e) => e is T));
}
