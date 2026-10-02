import 'geometry.dart';
import 'topology.dart';

typedef Json = Map<String, Object?>;

/// A named property on a region or entity, with an optional value:
/// `(name: 'Darkness', value: 2)` is Darkness (2).
typedef Tag = ({String name, int? value});

/// What a tag does: the data building blocks of ADR 012. Anything they can't
/// express stays in [TagDef.text] for people to read.
sealed class Effect {
  const Effect();

  static Effect fromJson(Json json) => switch (json['type']) {
        'roll' => RollModifier(json['edge'] as int,
            scaled: json['scaled'] as bool? ?? false),
        'moveCost' => MoveCost((json['multiplier'] as num).toDouble()),
        'blocksSight' => const BlocksSight(),
        'occupantLimit' => OccupantLimit(json['max'] as int),
        'entryCheck' => EntryCheck(json['check'] as String),
        final type => throw FormatException('Unknown effect: $type'),
      };
}

/// Advantage (positive [edge]) or disadvantage (negative), with a strength.
/// How edges combine is the system's business, so the engine only reports
/// them.
final class RollModifier extends Effect {
  const RollModifier(this.edge, {this.scaled = false});

  final int edge;

  /// Multiply [edge] by the tag's value, as in Darkness (X).
  final bool scaled;

  int edgeFor(Tag tag) => scaled ? edge * (tag.value ?? 1) : edge;
}

/// Moving into the area costs [multiplier] times as much.
final class MoveCost extends Effect {
  const MoveCost(this.multiplier);

  final double multiplier;
}

/// Line of sight can't pass through the area.
final class BlocksSight extends Effect {
  const BlocksSight();
}

/// At most [max] occupants in the area.
final class OccupantLimit extends Effect {
  const OccupantLimit(this.max);

  final int max;
}

/// Entering the area requires a [check], for example Traversal.
final class EntryCheck extends Effect {
  const EntryCheck(this.check);

  final String check;
}

/// A tag's definition in a pack.
final class TagDef {
  const TagDef(this.name,
      {this.sector = false, this.effects = const [], this.text = ''});

  final String name;

  /// Whether the tag applies to sectors.
  final bool sector;
  final List<Effect> effects;
  final String text;

  factory TagDef.fromJson(Json json) => TagDef(
        json['name'] as String,
        sector: json['sector'] as bool? ?? false,
        effects: [
          for (final e in json['effects'] as List? ?? const [])
            Effect.fromJson(e as Json),
        ],
        text: json['text'] as String? ?? '',
      );
}

/// A named distance bracket. [max] is inclusive, in pack units; null means
/// no limit.
final class RangeBand {
  const RangeBand(this.name, [this.max]);

  final String name;
  final double? max;
}

enum TopologyKind { square, gridless }

/// A game system as data: how space works, its units, bands and tags.
final class SystemPack {
  SystemPack({
    required this.name,
    this.topology = TopologyKind.square,
    this.diagonal = DiagonalRule.chebyshev,
    required this.unit,
    this.unitsPerStep = 1,
    this.bands = const [],
    List<TagDef> tags = const [],
  }) : tags = {for (final t in tags) t.name: t};

  final String name;
  final TopologyKind topology;
  final DiagonalRule diagonal;

  /// What distances are reported in: 'ft', 'sector', 'zone'…
  final String unit;

  /// Units per topology step: 5 ft per cell for D&D 5e.
  final double unitsPerStep;

  /// In ascending order of [RangeBand.max].
  final List<RangeBand> bands;
  final Map<String, TagDef> tags;

  /// The first band whose max covers [value], or null if the pack has none.
  RangeBand? bandFor(double value) =>
      bands.where((b) => b.max == null || value <= b.max!).firstOrNull;

  /// The effects of [tag], or none if the pack doesn't define it.
  List<Effect> effectsOf(Tag tag) => tags[tag.name]?.effects ?? const [];

  /// The pack chooses the kind of space; the scene supplies the scale.
  Topology topologyFor({required double cellSize, Point offset = (x: 0, y: 0)}) =>
      switch (topology) {
        TopologyKind.square =>
          SquareGrid(cellSize: cellSize, offset: offset, diagonal: diagonal),
        TopologyKind.gridless => Gridless(stepSize: cellSize),
      };

  factory SystemPack.fromJson(Json json) => SystemPack(
        name: json['name'] as String,
        topology: TopologyKind.values
            .byName(json['topology'] as String? ?? TopologyKind.square.name),
        diagonal: DiagonalRule.values
            .byName(json['diagonal'] as String? ?? DiagonalRule.chebyshev.name),
        unit: json['unit'] as String,
        unitsPerStep: (json['unitsPerStep'] as num? ?? 1).toDouble(),
        bands: [
          for (final b in json['bands'] as List? ?? const [])
            RangeBand((b as Json)['name'] as String,
                (b['max'] as num?)?.toDouble()),
        ],
        tags: [
          for (final t in json['tags'] as List? ?? const [])
            TagDef.fromJson(t as Json),
        ],
      );
}
