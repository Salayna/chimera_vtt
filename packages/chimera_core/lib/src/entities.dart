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
    this.fogByDefault = false,
  });

  final AssetId? map;
  final double width;
  final double height;
  final Grid grid;

  /// Whether the whole map starts covered, so fog ops reveal it.
  final bool fogByDefault;

  SceneSettings withGrid(Grid grid) => SceneSettings(
      map: map, width: width, height: height, grid: grid, fogByDefault: fogByDefault);

  @override
  EntityKind get kind => EntityKind.settings;

  @override
  Json _fields() => {
        if (map != null) 'map': map!.value,
        'width': width,
        'height': height,
        'grid': grid.toJson(),
        'fogByDefault': fogByDefault,
      };

  factory SceneSettings._fromJson(Json json) => SceneSettings(
        map: json['map'] == null ? null : AssetId(json['map'] as String),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        grid: Grid.fromJson(json['grid'] as Json),
        fogByDefault: json['fogByDefault'] as bool,
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

  @override
  EntityKind get kind => EntityKind.token;

  Token moveTo(Point to) => Token(
      id: id,
      position: to,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden);

  Token withOwner(PlayerId? owner) => Token(
      id: id,
      position: position,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden);

  Token withHidden(bool hidden) => Token(
      id: id,
      position: position,
      size: size,
      image: image,
      owner: owner,
      hidden: hidden);

  @override
  Json _fields() => {
        'id': id.value,
        'position': position.toJson(),
        'size': size,
        if (image != null) 'image': image!.value,
        if (owner != null) 'owner': owner!.value,
        'hidden': hidden,
      };

  factory Token._fromJson(Json json) => Token(
        id: TokenId(json['id'] as String),
        position: pointFromJson(json['position']),
        size: (json['size'] as num).toDouble(),
        image: json['image'] == null ? null : AssetId(json['image'] as String),
        owner: json['owner'] == null ? null : PlayerId(json['owner'] as String),
        hidden: json['hidden'] as bool,
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
