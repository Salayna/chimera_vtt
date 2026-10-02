import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'fog_mask.dart';
import 'table_view.dart' show TableController;

/// Grid lines. Repaints when the grid or the map size changes, and for the
/// GM's [controller]: brighter while the grid panel is open, and following
/// the grid being fitted.
class GridPainter extends CustomPainter {
  GridPainter(this.settings, [this.controller])
      : super(repaint: controller == null
            ? null
            : Listenable.merge([controller, controller.gridFit]));

  final SceneSettings settings;
  final TableController? controller;

  @override
  void paint(Canvas canvas, Size size) {
    final fitting = controller?.gridFit.value;
    final grid = fitting != null && fitting.valid ? fitting : settings.grid;
    final setup = controller?.gridOptions ?? false;
    // Hidden lines still show while the GM sets the grid up.
    if (!settings.gridVisible && !setup) return;
    final paint = Paint()
      ..color = setup ? CvColors.amber500.withValues(alpha: 0.85) : const Color(0x40FFFFFF)
      ..strokeWidth = setup ? 2 : 1;
    final lines = <Offset>[];
    for (var x = grid.offset.x % grid.cellSize; x <= settings.width; x += grid.cellSize) {
      lines
        ..add(Offset(x, 0))
        ..add(Offset(x, settings.height));
    }
    for (var y = grid.offset.y % grid.cellSize; y <= settings.height; y += grid.cellSize) {
      lines
        ..add(Offset(0, y))
        ..add(Offset(settings.width, y));
    }
    // One draw call for every line.
    canvas.drawPoints(ui.PointMode.lines, lines, paint);
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.controller != controller ||
      old.settings.gridVisible != settings.gridVisible ||
      old.settings.grid.cellSize != settings.grid.cellSize ||
      old.settings.grid.offset != settings.grid.offset ||
      old.settings.width != settings.width ||
      old.settings.height != settings.height;
}

/// The token being dragged, drawn at [position] instead of its stored one.
typedef TokenDrag = ({TokenId id, Offset position});

/// Every token. A drag repaints this layer through [drag] without
/// rebuilding any widget.
///
/// Rings follow the design system: teal for the viewer's own tokens, bone
/// for other players', dashed slate for unowned, amber with a halo when
/// selected. Hidden tokens (GM only) are faded with a dashed ring. Ring
/// sizes are the design's 56 px token, scaled to the token.
class TokenPainter extends CustomPainter {
  TokenPainter({
    required this.tokens,
    required this.drag,
    required this.selected,
    required this.images,
    required this.gm,
    required this.self,
  }) : super(repaint: Listenable.merge([drag, selected]));

  final Map<TokenId, Token> tokens;
  final ValueNotifier<TokenDrag?> drag;
  final ValueNotifier<TokenId?> selected;
  final ui.Image? Function(AssetId) images;
  final bool gm;
  final PlayerId self;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = canvas.getLocalClipBounds();
    final dragged = drag.value;
    final stroke = Paint()..style = PaintingStyle.stroke;
    final fill = Paint();
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    for (final token in tokens.values) {
      final isDragged = dragged?.id == token.id;
      final center = isDragged
          ? dragged!.position
          : Offset(token.position.x, token.position.y);
      final u = token.size / CvSizes.token; // One design pixel.
      final radius = token.size / 2;
      if (!visible.overlaps(
          Rect.fromCircle(center: center, radius: radius + 12 * u))) {
        continue;
      }
      final isSelected = selected.value == token.id;
      if (isDragged) {
        // ponytail: only the dragged token casts a shadow; a blur per
        // token per frame costs too much on a full map.
        canvas.drawCircle(
            center + Offset(0, 8 * u),
            radius,
            Paint()
              ..color = const Color(0x66000000)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * u));
      }

      // Face.
      final faceAlpha = token.hidden ? 0x73 : 0xFF;
      final rect = Rect.fromCircle(center: center, radius: radius);
      final image = token.image == null ? null : images(token.image!);
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      if (image != null) {
        imagePaint.color = Color.fromARGB(faceAlpha, 0, 0, 0);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          imagePaint,
        );
      } else {
        fill.color = (token.owner == null
                ? CvColors.slate300
                : playerColor(token.owner!))
            .withAlpha(faceAlpha);
        canvas.drawCircle(center, radius, fill);
      }
      canvas.restore();

      // Ring, centred on the face's edge plus half its width.
      final ringWidth = CvRadii.ringToken * u;
      final ringRadius = radius + ringWidth / 2;
      final (ringColor, dashed) = switch (token) {
        _ when isSelected => (CvColors.amber500, false),
        Token(hidden: true) => (CvColors.slate300, true),
        Token(owner: null) => (CvColors.slate400, true),
        Token(:final owner) when owner == self => (CvColors.teal500, false),
        _ => (CvColors.bone100, false),
      };
      stroke
        ..color = ringColor
        ..strokeWidth = ringWidth;
      if (dashed) {
        _dashedCircle(canvas, center, ringRadius, stroke, dash: 6 * u);
      } else {
        canvas.drawCircle(center, ringRadius, stroke);
      }
      if (isSelected) {
        stroke
          ..color = CvColors.amber500
          ..strokeWidth = 2 * u;
        canvas.drawCircle(center, radius + 8 * u, stroke);
      }
    }
  }

  static void _dashedCircle(Canvas canvas, Offset center, double radius,
      Paint paint, {required double dash}) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final count = math.max(4, (2 * math.pi * radius / (dash * 2)).floor());
    final step = 2 * math.pi / count;
    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, i * step, step / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(TokenPainter old) =>
      !identical(old.tokens, tokens) || old.gm != gm || old.self != self;
}

/// The fog stroke being painted, before it becomes a fog op.
typedef FogPreview = ({FogShape shape, FogMode mode});

/// The fog: one image draw, plus the stroke in progress for the GM.
class FogPainter extends CustomPainter {
  FogPainter({
    required this.mask,
    required this.revision,
    required this.preview,
    required this.gm,
    this.naiveOps,
    Listenable? naiveRepaint,
  }) : super(repaint: Listenable.merge([preview, naiveRepaint]));

  /// Benchmark baseline only (`--dart-define=NAIVE_FOG=true`): replays every
  /// op in a saveLayer, repainting whenever [naiveRepaint] fires, as a single
  /// all-in-one painter would.
  static const naive = bool.fromEnvironment('NAIVE_FOG');
  final List<FogOp>? naiveOps;

  final FogMask mask;

  /// Bumped by the owner whenever [mask] changes.
  final int revision;
  final ValueNotifier<FogPreview?> preview;
  final bool gm;

  @override
  void paint(Canvas canvas, Size size) {
    final image = mask.image;
    // Players see opaque fog; the GM sees through it.
    final color = gm ? CvColors.fogGm : CvColors.fogPlayer;
    if (naiveOps case final ops?) {
      canvas.saveLayer(Offset.zero & size, Paint()..color = color);
      for (final op in ops) {
        paintFogShape(canvas, op.shape, op.mode);
      }
      canvas.restore();
    } else if (image != null) {
      final tint = ColorFilter.mode(color, BlendMode.srcIn);
      final pending = mask.pending;
      // Pending reveals must cut into the mask, so mask and pending ops are
      // composed in one layer first. Without pending ops, a plain draw.
      if (pending.isNotEmpty) {
        canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = tint);
      }
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()
          ..colorFilter = pending.isEmpty ? tint : null
          ..filterQuality = FilterQuality.medium,
      );
      if (pending.isNotEmpty) {
        for (final op in pending) {
          paintFogShape(canvas, op.shape, op.mode);
        }
        canvas.restore();
      }
    }
    if (preview.value case (:final shape, :final mode)) {
      // Always drawn as paint: a reveal preview must not clear the mask.
      paintFogShape(canvas, shape, FogMode.cover,
          color: mode == FogMode.cover
              ? CvColors.fogCoverPreview
              : CvColors.fogRevealPreview);
    }
  }

  @override
  bool shouldRepaint(FogPainter old) =>
      old.revision != revision || old.gm != gm;
}
