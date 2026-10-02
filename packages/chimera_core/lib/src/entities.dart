import 'geometry.dart';
import 'ids.dart';

typedef Json = Map<String, Object?>;

/// A piece of scene state with its own identity: the unit of sync,
/// visibility, permission and persistence.
///
/// Subclasses must live in this library because the class is sealed.
sealed class Entity {
  const Entity();

  /// Schema version, written as `v`. Bump it and migrate in [fromJson] when
  /// an entity's JSON shape changes.
  static const version = 1;

  EntityKind get kind;

  Json _fields();

  Json toJson() => {'kind': kind.name, 'v': version, ..._fields()};

  static Entity fromJson(Json json) {
    if (json['v'] != version) {
      throw FormatException('Unsupported entity version: ${json['v']}');
    }
    return switch (EntityKind.values.byName(json['kind'] as String)) {
      EntityKind.settings => SceneSettings._fromJson(json),
      EntityKind.token => Token._fromJson(json),
      EntityKind.fogOp => FogOp._fromJson(json),
      EntityKind.region => Region._fromJson(json),
      EntityKind.initiative => Initiative._fromJson(json),
    };
  }
}

/// Cell size and offset used to snap and measure. A field, not an entity.
final class Grid {
  const Grid({required this.cellSize, this.offset = (x: 0, y: 0)});

  final double cellSize;
  final Point offset;

  static const minCellSize = 16.0;
  static const maxCellSize = 1024.0;

  /// The grid with one cell over the box from [a] to [b]: the box's mean
  /// side, in whole pixels, with lines through its top-left corner.
  // ponytail: one cell drawn by hand is off by a pixel or so, which adds up
  // across a big map. Fit over several cells if that shows.
  factory Grid.fitted(Point a, Point b) {
    final size = (((a.x - b.x).abs() + (a.y - b.y).abs()) / 2).roundToDouble();
    if (size == 0) return const Grid(cellSize: 0);
    double origin(double u, double v) => (u < v ? u : v).round() % size;
    return Grid(cellSize: size, offset: (x: origin(a.x, b.x), y: origin(a.y, b.y)));
  }

  bool get valid => cellSize >= minCellSize && cellSize <= maxCellSize;

  /// The spot nearest [near], a whole number of cells away, where a token of
  /// [size] overlaps none of [tokens]. Tokens touching edge to edge is fine.
  // ponytail: may land off the map near its edge; clamp if that bites.
  Point freeSpot(Point near, double size, Iterable<Token> tokens) {
    bool free(Point p) => tokens.every((t) {
          final dx = t.position.x - p.x, dy = t.position.y - p.y;
          final reach = (size + t.size) / 2 - 0.5;
          return dx * dx + dy * dy >= reach * reach;
        });
    for (var ring = 0; ring <= 32; ring++) {
      for (var i = -ring; i <= ring; i++) {
        for (var j = -ring; j <= ring; j++) {
          if (i.abs() != ring && j.abs() != ring) continue; // Inside the ring.
          final p = (x: near.x + i * cellSize, y: near.y + j * cellSize);
          if (free(p)) return p;
        }
      }
    }
    return near; // A full map: stack after all.
  }

  /// Where a token of [size] centred at [center] snaps to: its edges onto
  /// the nearest grid lines, so a 2-cell token covers exactly 4 cells. A
  /// token smaller than a cell snaps to the middle of the cell it's in.
  Point snap(Point center, double size) {
    double axis(double c, double origin) {
      if (size < cellSize) {
        return origin + (((c - origin) / cellSize).floor() + 0.5) * cellSize;
      }
      final edge = ((c - size / 2 - origin) / cellSize).round() * cellSize;
      return origin + edge + size / 2;
    }

    return (x: axis(center.x, offset.x), y: axis(center.y, offset.y));
  }

  Json toJson() => {'cellSize': cellSize, 'offset': offset.toJson()};

  factory Grid.fromJson(Json json) => Grid(
        cellSize: (json['cellSize'] as num).toDouble(),
        offset: pointFromJson(json['offset']),
      );
}

/// The single-instance entity holding the map, its size, the grid and the
/// default fog. It has no id: its kind identifies it.
final class SceneSettings extends Entity {
  const SceneSettings({
    this.map,
    required this.width,
    required this.height,
    required this.grid,
    this.gridVisible = true,
    this.fogByDefault = false,
    this.pack = defaultPack,
  });

  /// The system pack scenes use unless the GM picks another.
  static const defaultPack = 'generic';

  final AssetId? map;
  final double width;
  final double height;
  final Grid grid;

  /// Whether the grid lines are drawn. Off for a map with its own grid
  /// printed on it; snapping still uses [grid].
  final bool gridVisible;

  /// Whether the whole map starts covered, so fog ops reveal it.
  final bool fogByDefault;

  /// The id of the system pack the scene is played with: its units, range
  /// bands, conditions and tags. Core doesn't read packs; the app does.
  final String pack;

  SceneSettings copyWith({
    AssetId? map,
    double? width,
    double? height,
    Grid? grid,
    bool? gridVisible,
    String? pack,
  }) =>
      SceneSettings(
        map: map ?? this.map,
        width: width ?? this.width,
        height: height ?? this.height,
        grid: grid ?? this.grid,
        gridVisible: gridVisible ?? this.gridVisible,
        fogByDefault: fogByDefault,
        pack: pack ?? this.pack,
      );

  @override
  EntityKind get kind => EntityKind.settings;

  @override
  Json _fields() => {
        if (map != null) 'map': map!.value,
        'width': width,
        'height': height,
        'grid': grid.toJson(),
        'gridVisible': gridVisible,
        'fogByDefault': fogByDefault,
        if (pack != defaultPack) 'pack': pack,
      };

  factory SceneSettings._fromJson(Json json) => SceneSettings(
        map: json['map'] == null ? null : AssetId(json['map'] as String),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        grid: Grid.fromJson(json['grid'] as Json),
        // Absent in scenes saved before it existed.
        gridVisible: json['gridVisible'] as bool? ?? true,
        fogByDefault: json['fogByDefault'] as bool,
        pack: json['pack'] as String? ?? defaultPack,
      );
}

/// A creature or object on the map.
final class Token extends Entity {
  const Token({
    required this.id,
    required this.position,
    required this.size,
    this.image,
    this.owner,
    this.hidden = false,
    this.name = '',
    this.conditions = const {},
  });

  final TokenId id;

  /// Centre of the token.
  final Point position;

  /// Width and height in world units (map pixels), like [position].
  final double size;
  final AssetId? image;

  /// The one player allowed to move this token, if any.
  final PlayerId? owner;

  /// GM-only: a hidden token is never sent to players.
  final bool hidden;

  /// Shown under the token. Empty for none.
  final String name;

  /// Conditions by name, each with an optional value: Poisoned, Darkness (2).
  /// Saving to Postgres (jsonb) may reorder them.
  final Map<String, int?> conditions;

  @override
  EntityKind get kind => EntityKind.token;

  Token moveTo(Point to) => Token(
      id: id,
      position: to,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden,
      name: name,
      conditions: conditions);

  Token withOwner(PlayerId? owner) => Token(
      id: id,
      position: position,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden,
      name: name,
      conditions: conditions);

  Token withHidden(bool hidden) => Token(
      id: id,
      position: position,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden,
      name: name,
      conditions: conditions);

  /// The owner can't be cleared here: use [withOwner].
  Token copyWith(
          {TokenId? id,
          Point? position,
          double? size,
          AssetId? image,
          String? name}) =>
      Token(
          id: id ?? this.id,
          position: position ?? this.position,
          size: size ?? this.size,
          image: image ?? this.image,
          owner: owner,
          hidden: hidden,
          name: name ?? this.name,
          conditions: conditions);

  Token withConditions(Map<String, int?> conditions) => Token(
      id: id,
      position: position,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden,
      name: name,
      conditions: Map.unmodifiable(conditions));

  @override
  Json _fields() => {
        'id': id.value,
        'position': position.toJson(),
        'size': size,
        if (image != null) 'image': image!.value,
        if (owner != null) 'owner': owner!.value,
        'hidden': hidden,
        if (name.isNotEmpty) 'name': name,
        if (conditions.isNotEmpty) 'conditions': conditions,
      };

  factory Token._fromJson(Json json) => Token(
        id: TokenId(json['id'] as String),
        position: pointFromJson(json['position']),
        size: (json['size'] as num).toDouble(),
        image: json['image'] == null ? null : AssetId(json['image'] as String),
        owner: json['owner'] == null ? null : PlayerId(json['owner'] as String),
        hidden: json['hidden'] as bool,
        name: json['name'] as String? ?? '',
        conditions: _tagsFromJson(json['conditions']),
      );
}

enum FogMode { cover, reveal }

/// The area a fog op covers or reveals.
sealed class FogShape {
  const FogShape();

  Json toJson();

  static FogShape fromJson(Json json) => switch (json['type']) {
        'rect' => FogRect(pointFromJson(json['from']), pointFromJson(json['to'])),
        'brush' => FogBrush(
            [for (final p in json['points'] as List) pointFromJson(p)],
            (json['radius'] as num).toDouble(),
          ),
        final type => throw FormatException('Unknown fog shape: $type'),
      };
}

/// A rectangle between two opposite corners.
final class FogRect extends FogShape {
  const FogRect(this.from, this.to);

  final Point from;
  final Point to;

  @override
  Json toJson() => {'type': 'rect', 'from': from.toJson(), 'to': to.toJson()};
}

/// A stroke: a polyline swept by a circle of [radius].
final class FogBrush extends FogShape {
  const FogBrush(this.points, this.radius);

  final List<Point> points;
  final double radius;

  @override
  Json toJson() => {
        'type': 'brush',
        'points': [for (final p in points) p.toJson()],
        'radius': radius,
      };
}

/// One fog operation. Fog is every op applied by ascending [order].
final class FogOp extends Entity {
  const FogOp({
    required this.id,
    required this.order,
    required this.mode,
    required this.shape,
  });

  final FogOpId id;

  /// Drawing order, assigned by the reducer.
  final int order;
  final FogMode mode;
  final FogShape shape;

  @override
  EntityKind get kind => EntityKind.fogOp;

  @override
  Json _fields() => {
        'id': id.value,
        'order': order,
        'mode': mode.name,
        'shape': shape.toJson(),
      };

  factory FogOp._fromJson(Json json) => FogOp(
        id: FogOpId(json['id'] as String),
        order: json['order'] as int,
        mode: FogMode.values.byName(json['mode'] as String),
        shape: FogShape.fromJson(json['shape'] as Json),
      );
}

Map<String, int?> _tagsFromJson(Object? json) => Map.unmodifiable({
      for (final MapEntry(:key, :value) in (json as Map? ?? const {}).entries)
        key as String: value as int?,
    });

/// An area that carries tags: a sector, a zone, a spell's area. A rectangle
/// between two opposite corners, usually on grid lines.
// ponytail: rectangles only; freeform zones need a polygon shape here.
final class Region extends Entity {
  const Region({
    required this.id,
    required this.from,
    required this.to,
    this.tags = const {},
    this.hidden = false,
  });

  final RegionId id;
  final Point from;
  final Point to;

  /// Tags by name, each with an optional value: Heavy Cover, Darkness (2).
  final Map<String, int?> tags;

  /// GM-only, like a hidden token: never sent to players.
  final bool hidden;

  Region copyWith({Point? from, Point? to, Map<String, int?>? tags, bool? hidden}) =>
      Region(
        id: id,
        from: from ?? this.from,
        to: to ?? this.to,
        tags: tags == null ? this.tags : Map.unmodifiable(tags),
        hidden: hidden ?? this.hidden,
      );

  @override
  EntityKind get kind => EntityKind.region;

  @override
  Json _fields() => {
        'id': id.value,
        'from': from.toJson(),
        'to': to.toJson(),
        if (tags.isNotEmpty) 'tags': tags,
        'hidden': hidden,
      };

  factory Region._fromJson(Json json) => Region(
        id: RegionId(json['id'] as String),
        from: pointFromJson(json['from']),
        to: pointFromJson(json['to']),
        tags: _tagsFromJson(json['tags']),
        hidden: json['hidden'] as bool? ?? false,
      );
}

/// One token's place in the turn order.
typedef InitiativeEntry = ({TokenId token, int value});

/// The turn order while a fight is on: a single-instance entity, absent
/// when there is none. [entries] go from highest to lowest value.
final class Initiative extends Entity {
  Initiative({required this.round, this.current, required List<InitiativeEntry> entries})
      : entries = List.unmodifiable(entries);

  /// Starts at 1.
  final int round;

  /// Whose turn it is, or null before the first turn.
  final TokenId? current;
  final List<InitiativeEntry> entries;

  /// [entries] ordered from highest to lowest value, ties in their order.
  static List<InitiativeEntry> ordered(Iterable<InitiativeEntry> entries) =>
      [...entries]..sort((a, b) => b.value.compareTo(a.value));

  /// The next turn: the entry after [current], or the first of a new round
  /// after the last.
  Initiative next() {
    if (entries.isEmpty) return this;
    final i = entries.indexWhere((e) => e.token == current);
    if (current == null || i == -1) {
      return Initiative(round: round, current: entries.first.token, entries: entries);
    }
    return i + 1 < entries.length
        ? Initiative(round: round, current: entries[i + 1].token, entries: entries)
        : Initiative(round: round + 1, current: entries.first.token, entries: entries);
  }

  /// Without [token], whose turn passes to the next entry if it was theirs.
  Initiative without(TokenId token) {
    final rest = [for (final e in entries) if (e.token != token) e];
    if (current != token) {
      return Initiative(round: round, current: current, entries: rest);
    }
    final i = entries.indexWhere((e) => e.token == token);
    final after = [...entries.skip(i + 1), ...entries.take(i)]
        .where((e) => e.token != token)
        .firstOrNull;
    return Initiative(round: round, current: after?.token, entries: rest);
  }

  @override
  EntityKind get kind => EntityKind.initiative;

  @override
  Json _fields() => {
        'round': round,
        if (current != null) 'current': current!.value,
        'entries': [
          for (final e in entries) {'token': e.token.value, 'value': e.value},
        ],
      };

  factory Initiative._fromJson(Json json) => Initiative(
        round: json['round'] as int,
        current: json['current'] == null ? null : TokenId(json['current'] as String),
        entries: [
          for (final e in json['entries'] as List)
            (
              token: TokenId((e as Json)['token'] as String),
              value: e['value'] as int,
            ),
        ],
      );
}
