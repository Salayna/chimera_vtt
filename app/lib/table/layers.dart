import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';

import 'fog_mask.dart';

/// Grid lines. Repaints only when the grid or the map size changes.
class GridPainter extends CustomPainter {
  const GridPainter(this.settings);

  final SceneSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = settings.grid;
    final paint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1;
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
      old.settings.grid.cellSize != settings.grid.cellSize ||
      old.settings.grid.offset != settings.grid.offset ||
      old.settings.width != settings.width ||
      old.settings.height != settings.height;
}

/// The token being dragged, drawn at [position] instead of its stored one.
typedef TokenDrag = ({TokenId id, Offset position});

/// Every token. A drag repaints this layer through [drag] without
/// rebuilding any widget.
class TokenPainter extends CustomPainter {
  TokenPainter({
    required this.tokens,
    required this.drag,
    required this.images,
    required this.gm,
  }) : super(repaint: drag);

  final Map<TokenId, Token> tokens;
  final ValueNotifier<TokenDrag?> drag;
  final ui.Image? Function(AssetId) images;
  final bool gm;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = canvas.getLocalClipBounds();
    final dragged = drag.value;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint();
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;
    for (final token in tokens.values) {
      final center = dragged?.id == token.id
          ? dragged!.position
          : Offset(token.position.x, token.position.y);
      final rect = Rect.fromCenter(
          center: center, width: token.size, height: token.size);
      if (!visible.overlaps(rect)) continue;
      // Hidden tokens only ever reach the GM, who sees them faded.
      final alpha = token.hidden ? 0x80 : 0xFF;
      final image = token.image == null ? null : images(token.image!);
      if (image != null) {
        imagePaint.color = Color.fromARGB(alpha, 0, 0, 0);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          rect,
          imagePaint,
        );
      } else {
        fill.color = _ownerColor(token.owner).withAlpha(alpha);
        canvas.drawCircle(center, token.size / 2, fill);
      }
      ring.color = const Color(0xFF000000).withAlpha(alpha);
      canvas.drawCircle(center, token.size / 2, ring);
    }
  }

  @override
  bool shouldRepaint(TokenPainter old) =>
      !identical(old.tokens, tokens) || old.gm != gm;

  static Color _ownerColor(PlayerId? owner) => owner == null
      ? const Color(0xFF9E9E9E)
      : HSVColor.fromAHSV(1, (owner.value.hashCode % 360).toDouble(), 0.6, 0.9)
          .toColor();
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
    final color = Color.fromARGB(gm ? 0x99 : 0xFF, 0x10, 0x10, 0x18);
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
              ? const Color(0x66000000)
              : const Color(0x66FFFFFF));
    }
  }

  @override
  bool shouldRepaint(FogPainter old) =>
      old.revision != revision || old.gm != gm;
}
