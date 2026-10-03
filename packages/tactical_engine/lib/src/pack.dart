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

  Json toJson();

  static Effect fromJson(Json json) => switch (json['type']) {
        'roll' => RollModifier(json['edge'] as int,
            scaled: json['scaled'] as bool? ?? false),
        'moveCost' => MoveCost((json['multiplier'] as num).toDouble()),
        'blocksSight' => const BlocksSight(),
        'occupantLimit' => OccupantLimit(json['max'] as int),
        'entryCheck' => EntryCheck(_text(json['check'], 'check', 60)),
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

  @override
  Json toJson() => {'type': 'roll', 'edge': edge, if (scaled) 'scaled': true};
}

/// Moving into the area costs [multiplier] times as much.
final class MoveCost extends Effect {
  const MoveCost(this.multiplier);

  final double multiplier;

  @override
  Json toJson() => {'type': 'moveCost', 'multiplier': multiplier};
}

/// Line of sight can't pass through the area.
final class BlocksSight extends Effect {
  const BlocksSight();

  @override
  Json toJson() => {'type': 'blocksSight'};
}

/// At most [max] occupants in the area.
final class OccupantLimit extends Effect {
  const OccupantLimit(this.max);

  final int max;

  @override
  Json toJson() => {'type': 'occupantLimit', 'max': max};
}

/// Entering the area requires a [check], for example Traversal.
final class EntryCheck extends Effect {
  const EntryCheck(this.check);

  final String check;

  @override
  Json toJson() => {'type': 'entryCheck', 'check': check};
}

/// A tag's definition in a pack.
final class TagDef {
  const TagDef(this.name,
      {this.sector = false,
      this.condition = false,
      this.valued = false,
      this.color,
      this.effects = const [],
      this.text = ''});

  final String name;

  /// Whether the tag applies to sectors.
  final bool sector;

  /// Whether it's a condition, set on tokens. Otherwise it goes on regions.
  final bool condition;

  /// Whether it takes a value, as in Darkness (2) or Exhaustion 3.
  final bool valued;

  /// A colour for it, as `#rrggbb`, or null for the default.
  final String? color;
  final List<Effect> effects;
  final String text;

  Json toJson() => {
        'name': name,
        if (sector) 'sector': true,
        if (condition) 'condition': true,
        if (valued) 'valued': true,
        if (color != null) 'color': color,
        if (effects.isNotEmpty) 'effects': [for (final e in effects) e.toJson()],
        if (text.isNotEmpty) 'text': text,
      };

  factory TagDef.fromJson(Json json) => TagDef(
        _text(json['name'], 'tag name', 30),
        sector: json['sector'] as bool? ?? false,
        condition: json['condition'] as bool? ?? false,
        valued: json['valued'] as bool? ?? false,
        color: switch (json['color']) {
          final String c when _hexColor.hasMatch(c) => c,
          null => null,
          final c => throw FormatException('Not a #rrggbb colour: $c'),
        },
        effects: [
          for (final e in _list(json['effects'], 'effects', 10))
            Effect.fromJson(e as Json),
        ],
        text: _text(json['text'] ?? '', 'tag text', 2000, empty: true),
      );
}

/// A number kept on each token, such as hit points or stress. Players may
/// change their own tokens'.
final class TrackerDef {
  const TrackerDef(this.name, {this.min = 0, this.max, this.text = ''});

  final String name;
  final int min;

  /// The highest value, or null for none (hit points vary by creature).
  final int? max;
  final String text;

  int clamp(int value) => value < min ? min : (max != null && value > max! ? max! : value);

  Json toJson() => {
        'name': name,
        if (min != 0) 'min': min,
        if (max != null) 'max': max,
        if (text.isNotEmpty) 'text': text,
      };

  factory TrackerDef.fromJson(Json json) {
    final min = json['min'] as int? ?? 0;
    final max = json['max'] as int?;
    if (max != null && max < min) throw const FormatException('A tracker max below its min');
    return TrackerDef(_text(json['name'], 'tracker name', 30),
        min: min, max: max, text: _text(json['text'] ?? '', 'tracker text', 500, empty: true));
  }
}

/// A place in the turn order a token is put in instead of rolling, as
/// Solaris' Combat Forms (Rush, Steady, Poise). Higher [value]s go first.
final class TurnForm {
  const TurnForm(this.name,
      {required this.value, this.npc = false, this.byDefault = false, this.text = ''});

  final String name;
  final int value;

  /// For the GM's tokens (no owner) rather than players'.
  final bool npc;

  /// The form a token starts a fight in, one for each side.
  final bool byDefault;
  final String text;

  Json toJson() => {
        'name': name,
        'value': value,
        if (npc) 'npc': true,
        if (byDefault) 'default': true,
        if (text.isNotEmpty) 'text': text,
      };

  factory TurnForm.fromJson(Json json) => TurnForm(
        _text(json['name'], 'form name', 30),
        value: json['value'] as int,
        npc: json['npc'] as bool? ?? false,
        byDefault: json['default'] as bool? ?? false,
        text: _text(json['text'] ?? '', 'form text', 500, empty: true),
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

/// A game system as data: how space works, its units, bands, tags and
/// trackers. Packs are modules: built in, or installed from a file
/// (`docs/PACKS.md`).
final class SystemPack {
  SystemPack({
    required this.id,
    required this.name,
    this.version = 1,
    this.topology = TopologyKind.square,
    this.diagonal = DiagonalRule.chebyshev,
    required this.unit,
    this.unitsPerStep = 1,
    this.bands = const [],
    this.initiative,
    this.forms = const [],
    this.trackers = const [],
    List<TagDef> tags = const [],
  }) : tags = {for (final t in tags) t.name: t};

  /// The version of the pack file format this app reads.
  static const format = 1;

  /// Ids are lowercase letters, digits and dashes, as `solaris-arcanum`.
  static final idPattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,39}$');

  /// Stable across versions: scenes name their pack by it.
  final String id;
  final String name;

  /// The pack's own version, bumped by its author.
  final int version;
  final TopologyKind topology;
  final DiagonalRule diagonal;

  /// What distances are reported in: 'ft', 'sector', 'zone'…
  final String unit;

  /// Units per topology step: 5 ft per cell for D&D 5e.
  final double unitsPerStep;

  /// In ascending order of [RangeBand.max].
  final List<RangeBand> bands;

  /// The dice formula each side rolls for initiative, for example `d20`.
  /// Null when the pack has no initiative roll.
  final String? initiative;

  /// Turn order by form instead of a roll, when not empty.
  final List<TurnForm> forms;

  /// The form a token starts a fight in: the default for its side, or the
  /// side's first.
  TurnForm? startingForm({required bool npc}) {
    final side = forms.where((f) => f.npc == npc);
    return side.where((f) => f.byDefault).firstOrNull ?? side.firstOrNull;
  }
  final List<TrackerDef> trackers;
  final Map<String, TagDef> tags;

  /// The tags set on tokens.
  Iterable<TagDef> get conditions => tags.values.where((t) => t.condition);

  /// The tags set on regions.
  Iterable<TagDef> get regionTags => tags.values.where((t) => !t.condition);

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

  /// The pack as a module file.
  Json toJson() => {
        'format': format,
        'id': id,
        'name': name,
        'version': version,
        'topology': topology.name,
        'diagonal': diagonal.name,
        'unit': unit,
        'unitsPerStep': unitsPerStep,
        if (bands.isNotEmpty)
          'bands': [
            for (final b in bands) {'name': b.name, if (b.max != null) 'max': b.max},
          ],
        if (initiative != null) 'initiative': initiative,
        if (forms.isNotEmpty) 'forms': [for (final f in forms) f.toJson()],
        if (trackers.isNotEmpty) 'trackers': [for (final t in trackers) t.toJson()],
        'tags': [for (final t in tags.values) t.toJson()],
      };

  /// Reads a module file. Packs come from anyone, so every field is checked
  /// and bounded; a bad file throws a [FormatException] saying why.
  factory SystemPack.fromJson(Json json) {
    if ((json['format'] ?? format) != format) {
      throw FormatException('Unsupported pack format: ${json['format']}');
    }
    final id = json['id'];
    if (id is! String || !idPattern.hasMatch(id)) {
      throw FormatException('A pack id is lowercase letters, digits and dashes: $id');
    }
    try {
      final unitsPerStep = (json['unitsPerStep'] as num? ?? 1).toDouble();
      if (!(unitsPerStep > 0 && unitsPerStep.isFinite)) {
        throw const FormatException('unitsPerStep must be above 0');
      }
      final tags = [
        for (final t in _list(json['tags'], 'tags', 200)) TagDef.fromJson(t as Json),
      ];
      if (tags.map((t) => t.name).toSet().length != tags.length) {
        throw const FormatException('Two tags share a name');
      }
      return SystemPack(
        id: id,
        name: _text(json['name'], 'name', 60),
        version: json['version'] as int? ?? 1,
        topology: TopologyKind.values
            .byName(json['topology'] as String? ?? TopologyKind.square.name),
        diagonal: DiagonalRule.values
            .byName(json['diagonal'] as String? ?? DiagonalRule.chebyshev.name),
        unit: _text(json['unit'], 'unit', 20),
        unitsPerStep: unitsPerStep,
        bands: [
          for (final b in _list(json['bands'], 'bands', 20))
            RangeBand(_text((b as Json)['name'], 'band name', 30),
                (b['max'] as num?)?.toDouble()),
        ],
        initiative: switch (json['initiative']) {
          final String formula => _text(formula, 'initiative', 100),
          _ => null,
        },
        forms: [
          for (final f in _list(json['forms'], 'forms', 20)) TurnForm.fromJson(f as Json),
        ],
        trackers: [
          for (final t in _list(json['trackers'], 'trackers', 20))
            TrackerDef.fromJson(t as Json),
        ],
        tags: tags,
      );
    } on FormatException {
      rethrow;
    } on Object catch (e) {
      // Wrong types (a number where a name goes, and the like).
      throw FormatException('Not a valid pack: $e');
    }
  }
}

final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

String _text(Object? value, String what, int max, {bool empty = false}) {
  if (value is! String || (!empty && value.trim().isEmpty) || value.length > max) {
    throw FormatException('$what: text of 1 to $max characters');
  }
  return value;
}

List<Object?> _list(Object? value, String what, int max) {
  if (value == null) return const [];
  if (value is! List || value.length > max) {
    throw FormatException('$what: a list of at most $max');
  }
  return value;
}
