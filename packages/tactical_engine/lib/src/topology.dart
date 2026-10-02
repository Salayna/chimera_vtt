import 'geometry.dart';

typedef Cell = ({int col, int row});

/// How a square grid counts a diagonal step.
enum DiagonalRule {
  /// Every diagonal costs 1: the 8 surrounding cells are adjacent.
  chebyshev,

  /// Diagonals cost 2: only the 4 orthogonal cells are adjacent.
  manhattan,

  /// Diagonals alternate 1, 2, 1, 2 (D&D's 5-10-5 variant).
  alternating,
}

/// How space is divided.
sealed class Topology {
  const Topology();

  /// The distance from [a] to [b] in steps: cells on a grid, or world units
  /// divided by [Gridless.stepSize].
  double steps(Point a, Point b);
}

final class SquareGrid extends Topology {
  const SquareGrid({
    required this.cellSize,
    this.offset = (x: 0, y: 0),
    this.diagonal = DiagonalRule.chebyshev,
  });

  final double cellSize;
  final Point offset;
  final DiagonalRule diagonal;

  Cell cellAt(Point p) => (
        col: ((p.x - offset.x) / cellSize).floor(),
        row: ((p.y - offset.y) / cellSize).floor(),
      );

  Point centerOf(Cell c) => (
        x: offset.x + (c.col + 0.5) * cellSize,
        y: offset.y + (c.row + 0.5) * cellSize,
      );

  /// The cell as a shape, for regions that are whole cells (Solaris sectors).
  Polygon shapeOf(Cell c) {
    final x = offset.x + c.col * cellSize, y = offset.y + c.row * cellSize;
    return Polygon.rect((x: x, y: y), (x: x + cellSize, y: y + cellSize));
  }

  int cellDistance(Cell a, Cell b) {
    final dx = (a.col - b.col).abs(), dy = (a.row - b.row).abs();
    final (long, short) = dx > dy ? (dx, dy) : (dy, dx);
    return switch (diagonal) {
      DiagonalRule.chebyshev => long,
      DiagonalRule.manhattan => dx + dy,
      DiagonalRule.alternating => long + short ~/ 2,
    };
  }

  @override
  double steps(Point a, Point b) =>
      cellDistance(cellAt(a), cellAt(b)).toDouble();
}

/// No grid: straight-line distance. Also covers precise movement.
final class Gridless extends Topology {
  const Gridless({required this.stepSize});

  /// World units per step, usually the scene's cell size.
  final double stepSize;

  @override
  double steps(Point a, Point b) => distanceBetween(a, b) / stepSize;
}
