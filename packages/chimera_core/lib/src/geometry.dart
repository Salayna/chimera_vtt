/// A position in world coordinates (map pixels).
typedef Point = ({double x, double y});

extension PointJson on Point {
  bool get isFinite => x.isFinite && y.isFinite;

  List<double> toJson() => [x, y];
}

Point pointFromJson(Object? json) => switch (json) {
      [num x, num y] => (x: x.toDouble(), y: y.toDouble()),
      _ => throw FormatException('Not a point: $json'),
    };
