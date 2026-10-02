import 'dart:math' as math;

/// A position in world coordinates (map pixels). Records are structural, so
/// this is the same type as `chimera_core`'s `Point`.
typedef Point = ({double x, double y});

double distanceBetween(Point a, Point b) {
  final dx = a.x - b.x, dy = a.y - b.y;
  return math.sqrt(dx * dx + dy * dy);
}

/// The area a region covers.
sealed class Shape {
  const Shape();

  /// Whether [p] is inside or on the edge.
  bool contains(Point p);

  /// Whether the segment from [a] to [b] passes through the inside. Grazing
  /// an edge or a corner doesn't count, so a diagonal between two cells
  /// isn't blocked by the cells that share its corners.
  bool crossesInterior(Point a, Point b);
}

final class Polygon extends Shape {
  Polygon(List<Point> vertices) : vertices = List.unmodifiable(vertices) {
    if (vertices.length < 3) {
      throw ArgumentError.value(vertices, 'vertices', 'needs at least 3');
    }
  }

  /// An axis-aligned rectangle between two opposite corners.
  Polygon.rect(Point a, Point b)
      : this([a, (x: b.x, y: a.y), b, (x: a.x, y: b.y)]);

  final List<Point> vertices;

  Iterable<(Point, Point)> get _edges sync* {
    for (var i = 0; i < vertices.length; i++) {
      yield (vertices[i], vertices[(i + 1) % vertices.length]);
    }
  }

  @override
  bool contains(Point p) => _onBoundary(p) || _insideByRay(p);

  @override
  bool crossesInterior(Point a, Point b) {
    // Split the segment wherever it meets an edge. Each piece is then wholly
    // inside or wholly outside, so testing its midpoint decides it.
    final ts = [0.0, 1.0];
    for (final (p, q) in _edges) {
      final t = _segmentParam(a, b, p, q);
      if (t != null) ts.add(t);
    }
    ts.sort();
    for (var i = 0; i + 1 < ts.length; i++) {
      if (ts[i + 1] - ts[i] < _eps) continue;
      final m = (ts[i] + ts[i + 1]) / 2;
      final mid = (x: a.x + (b.x - a.x) * m, y: a.y + (b.y - a.y) * m);
      if (!_onBoundary(mid) && _insideByRay(mid)) return true;
    }
    return false;
  }

  bool _onBoundary(Point p) =>
      _edges.any((e) => _distanceToSegment(p, e.$1, e.$2) < _eps);

  // Even-odd ray casting. Undefined on the boundary, which callers rule out.
  bool _insideByRay(Point p) {
    var inside = false;
    for (final (a, b) in _edges) {
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)) {
        inside = !inside;
      }
    }
    return inside;
  }
}

final class Circle extends Shape {
  const Circle(this.center, this.radius);

  final Point center;
  final double radius;

  @override
  bool contains(Point p) => distanceBetween(center, p) <= radius;

  @override
  bool crossesInterior(Point a, Point b) =>
      _distanceToSegment(center, a, b) < radius - _eps;
}

const _eps = 1e-9;

double _distanceToSegment(Point p, Point a, Point b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared == 0) return distanceBetween(p, a);
  final t =
      (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).clamp(0.0, 1.0);
  return distanceBetween(p, (x: a.x + t * dx, y: a.y + t * dy));
}

/// Where along a→b (0 to 1) it crosses segment p→q, or null if it doesn't or
/// the two are parallel. Overlapping collinear pieces lie on the boundary,
/// and the neighbouring edges already split the segment around them.
double? _segmentParam(Point a, Point b, Point p, Point q) {
  final rx = b.x - a.x, ry = b.y - a.y;
  final sx = q.x - p.x, sy = q.y - p.y;
  final denominator = rx * sy - ry * sx;
  if (denominator.abs() < _eps) return null;
  final t = ((p.x - a.x) * sy - (p.y - a.y) * sx) / denominator;
  final u = ((p.x - a.x) * ry - (p.y - a.y) * rx) / denominator;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1 ? t : null;
}
