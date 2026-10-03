import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../ui/cv.dart';
import 'table_view.dart';

/// Aligning the grid to a map, as Owlbear Rodeo does it: drag an anchor
/// onto a corner of the map's grid (offset), drag a second one to the
/// opposite corner of that square (size), then nudge any far corner onto
/// the map's line (refine) to take out the drift a single square leaves.

enum AlignStep { offset, size, refine }

/// Where an alignment stands: the anchor (a grid corner) and the cell size.
typedef GridAlign = ({AlignStep step, Point anchor, double size});

/// Starts aligning from [grid], anchored on its corner nearest [near].
GridAlign startAlign(Grid grid, Point near) {
  final s = grid.cellSize;
  double snap(double v, double o) => o + ((v - o) / s).round() * s;
  return (
    step: AlignStep.offset,
    anchor: (x: snap(near.x, grid.offset.x), y: snap(near.y, grid.offset.y)),
    size: s,
  );
}

/// The size step: one square from [anchor] to its opposite corner [to].
double sizeFrom(Point anchor, Point to) =>
    ((to.x - anchor.x).abs() + (to.y - anchor.y).abs()) / 2;

/// The grid corner nearest [p], in whole cells from [anchor].
(int, int) cornerNear(Point anchor, double size, Point p) =>
    (((p.x - anchor.x) / size).round(), ((p.y - anchor.y) / size).round());

/// The refine step: the cell size that puts the corner [cells] away from
/// [anchor] closest to [to], the anchor staying where it is. Null for the
/// anchor itself, which no size moves.
double? refinedSize(Point anchor, (int, int) cells, Point to) {
  final (i, j) = cells;
  if (i == 0 && j == 0) return null;
  // Least squares over both axes: (to - anchor) ≈ size × (i, j).
  return ((to.x - anchor.x) * i + (to.y - anchor.y) * j) / (i * i + j * j);
}

/// What a drag holds: the anchor, the size handle, or a grid corner.
sealed class _Grip {
  const _Grip();
}

final class _Anchor extends _Grip {
  const _Anchor();
}

final class _SizeHandle extends _Grip {
  const _SizeHandle();
}

final class _Corner extends _Grip {
  const _Corner(this.cells);

  final (int, int) cells;
}

/// The alignment over the map: its handles, a magnifier while one is
/// dragged, and the step bar. Fill the table's stack with it, above the
/// map; the map still pans and zooms wherever there's no handle.
class GridAlignLayer extends StatefulWidget {
  const GridAlignLayer({
    super.key,
    required this.controller,
    required this.onDone,
  });

  final TableController controller;

  /// Saves the aligned grid.
  final ValueChanged<Grid> onDone;

  @override
  State<GridAlignLayer> createState() => _GridAlignLayerState();
}

class _GridAlignLayerState extends State<GridAlignLayer> {
  static const _reach = 22.0; // Screen pixels a handle can be grabbed from.

  _Grip? _grip;
  Offset? _pointer; // While dragging, for the magnifier.
  Offset? _hover; // In the refine step, the corner shown under the mouse.

  TableController get _c => widget.controller;

  void _set(GridAlign a) {
    final size = a.size.clamp(Grid.minCellSize, Grid.maxCellSize);
    final clamped = (step: a.step, anchor: a.anchor, size: size);
    _c.align.value = clamped;
    _c.gridFit.value = Grid.through(clamped.anchor, size);
  }

  void _close() {
    _c.align.value = null;
    _c.gridFit.value = null;
  }

  Point _scene(Offset screen) {
    final p = MatrixUtils.transformPoint(Matrix4.inverted(_c.view.value), screen);
    return (x: p.dx, y: p.dy);
  }

  Offset _screen(Point p) => _c.toScreen(p);

  /// The handle under [screen], if any. [hover] reaches the nearest corner
  /// within half a cell, to show it; a press takes it only close up, so the
  /// map still pans and zooms everywhere else.
  _Grip? _gripAt(Offset screen, {bool hover = false}) {
    final a = _c.align.value;
    if (a == null) return null;
    bool near(Point p) => (_screen(p) - screen).distance <= _reach;
    if (near(a.anchor)) return const _Anchor();
    if (a.step == AlignStep.size &&
        near((x: a.anchor.x + a.size, y: a.anchor.y + a.size))) {
      return const _SizeHandle();
    }
    if (a.step == AlignStep.refine) {
      // Every corner is a handle, shown as the mouse nears it, as on
      // Owlbear Rodeo.
      final cells = cornerNear(a.anchor, a.size, _scene(screen));
      final corner = (x: a.anchor.x + cells.$1 * a.size, y: a.anchor.y + cells.$2 * a.size);
      final reach = hover ? math.max(_reach, a.size * _c.zoom / 2) : _reach;
      if (cells != (0, 0) && (_screen(corner) - screen).distance <= reach) {
        return _Corner(cells);
      }
    }
    return null;
  }

  void _drag(Offset screen) {
    final a = _c.align.value!;
    final p = _scene(screen);
    setState(() => _pointer = screen);
    switch (_grip) {
      case _Anchor():
        _set((step: a.step, anchor: p, size: a.size));
      case _SizeHandle():
        _set((step: a.step, anchor: a.anchor, size: sizeFrom(a.anchor, p)));
      case _Corner(:final cells):
        if (refinedSize(a.anchor, cells, p) case final size? when size > 0) {
          _set((step: a.step, anchor: a.anchor, size: size));
        }
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_c.align, _c.view]),
        builder: (context, _) {
          final a = _c.align.value;
          if (a == null) return const SizedBox.shrink();
          return Stack(children: [
            Positioned.fill(
              child: MouseRegion(
                opaque: false,
                onHover: (e) {
                  if (a.step == AlignStep.refine) setState(() => _hover = e.localPosition);
                },
                onExit: (_) => setState(() => _hover = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onPanStart: (d) => setState(() {
                    _grip = _gripAt(d.localPosition);
                    _pointer = d.localPosition;
                  }),
                  onPanUpdate: (d) => _drag(d.localPosition),
                  onPanEnd: (_) => setState(() {
                    _grip = null;
                    _pointer = null;
                  }),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _HandlesPainter(
                      align: a,
                      toScreen: _screen,
                      hover: switch (_hover) {
                        final h? when a.step == AlignStep.refine =>
                          switch (_gripAt(h, hover: true)) {
                            _Corner(:final cells) => cells,
                            _ => null,
                          },
                        _ => null,
                      },
                      grabbed: _grip,
                      grabbable: (p) => _grip != null || _gripAt(p) != null,
                    ),
                  ),
                ),
              ),
            ),
            if (_pointer case final p?) _magnifier(p),
            Positioned(
              left: 0,
              right: 0,
              top: CvSizes.insetScreen + CvSizes.hit + CvSpacing.s5,
              child: Center(child: _bar(a)),
            ),
          ]);
        },
      );

  /// A lifted round lens over the dragged point, as on Owlbear Rodeo: the
  /// finger or cursor doesn't hide what's being aligned.
  Widget _magnifier(Offset at) {
    const size = 132.0, lift = 96.0;
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - lift - size / 2,
      child: IgnorePointer(
        child: RawMagnifier(
          size: const Size.square(size),
          magnificationScale: 3,
          focalPointOffset: const Offset(0, lift),
          decoration: const MagnifierDecoration(
            shape: CircleBorder(side: BorderSide(color: CvColors.amber500, width: 2)),
            shadows: CvElevation.shadow2,
          ),
          child: const CustomPaint(painter: _Crosshair()),
        ),
      ),
    );
  }

  Widget _bar(GridAlign a) {
    const hints = {
      AlignStep.offset: 'Drag the anchor onto a corner of a square on the map.',
      AlignStep.size: 'Drag the second anchor to the opposite corner of that square.',
      AlignStep.refine: 'Far from the anchor, drag any grid corner onto the map\'s line.',
    };
    final last = a.step == AlignStep.refine;
    return CvPanel(
      raised: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 16, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
            for (final s in AlignStep.values)
              Text('${s.index + 1}  ${switch (s) {
                AlignStep.offset => 'Offset',
                AlignStep.size => 'Size',
                AlignStep.refine => 'Refine',
              }}',
                  style: CvTypography.weight(CvTypography.label, 600).copyWith(
                      color: s == a.step
                          ? CvColors.amber400
                          : s.index < a.step.index
                              ? CvColors.textPrimary
                              : CvColors.textDisabled)),
          ]),
          // A fixed width: the buttons stay put from step to step.
          SizedBox(
            width: 380,
            child: Text(hints[a.step]!,
                style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
          ),
        ]),
        CvButton(
            label: 'Back',
            variant: CvButtonVariant.ghost,
            small: true,
            onPressed: a.step == AlignStep.offset ? null : () => _set((
              step: AlignStep.values[a.step.index - 1],
              anchor: a.anchor,
              size: a.size,
            )),
          ),
        CvButton(
          label: 'Cancel',
          variant: CvButtonVariant.ghost,
          small: true,
          onPressed: _close,
        ),
        CvButton(
          label: last ? 'Done' : 'Next',
          icon: last ? Lucide.check : null,
          variant: CvButtonVariant.primary,
          small: true,
          onPressed: () {
            if (last) {
              widget.onDone(Grid.through(a.anchor, a.size));
              _close();
            } else {
              _set((step: AlignStep.values[a.step.index + 1], anchor: a.anchor, size: a.size));
            }
          },
        ),
      ]),
    );
  }
}

class _HandlesPainter extends CustomPainter {
  _HandlesPainter({
    required this.align,
    required this.toScreen,
    required this.hover,
    required this.grabbed,
    required this.grabbable,
  });

  final GridAlign align;
  final Offset Function(Point) toScreen;
  final (int, int)? hover;
  final _Grip? grabbed;

  /// Whether a press at a point takes a handle; elsewhere the map below
  /// gets it, to pan and zoom.
  final bool Function(Offset) grabbable;

  @override
  bool? hitTest(Offset position) => grabbable(position);

  @override
  void paint(Canvas canvas, Size size) {
    final a = align;
    final anchor = toScreen(a.anchor);
    // The square being sized, filled so the eye can match it to the map's.
    if (a.step != AlignStep.offset) {
      final far = toScreen((x: a.anchor.x + a.size, y: a.anchor.y + a.size));
      final square = Rect.fromPoints(anchor, far);
      canvas
        ..drawRect(square, Paint()..color = CvColors.amber500.withValues(alpha: 0.16))
        ..drawRect(
            square,
            Paint()
              ..color = CvColors.amber400
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
    }
    _handle(canvas, anchor, filled: true);
    if (a.step == AlignStep.size) {
      _handle(canvas, toScreen((x: a.anchor.x + a.size, y: a.anchor.y + a.size)),
          filled: false);
    }
    final corner = switch (grabbed) {
      _Corner(:final cells) => cells,
      _ => hover,
    };
    if (corner case (final i, final j) when a.step == AlignStep.refine) {
      _handle(canvas,
          toScreen((x: a.anchor.x + i * a.size, y: a.anchor.y + j * a.size)),
          filled: false);
    }
  }

  static void _handle(Canvas canvas, Offset at, {required bool filled}) {
    canvas
      ..drawCircle(at, 11, Paint()..color = const Color(0x99101216))
      ..drawCircle(
          at,
          8,
          Paint()
            ..color = CvColors.amber500
            ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
            ..strokeWidth = 2.5)
      ..drawCircle(at, 2, Paint()..color = filled ? const Color(0xFF101216) : CvColors.amber500);
  }

  @override
  // Rebuilt with the view, which moves every handle.
  bool shouldRepaint(_HandlesPainter old) => true;
}

/// The magnifier's crosshair: a thin cross with a gap at the centre.
class _Crosshair extends CustomPainter {
  const _Crosshair();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..color = CvColors.amber400
      ..strokeWidth = 1.5;
    final r = math.min(size.width, size.height) / 2;
    for (final d in [const Offset(1, 0), const Offset(0, 1)]) {
      canvas
        ..drawLine(c + d * 6, c + d * (r - 8), paint)
        ..drawLine(c - d * 6, c - d * (r - 8), paint);
    }
  }

  @override
  bool shouldRepaint(_Crosshair old) => false;
}
