import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart' show SquareGrid;

import '../theme.dart';
import '../members.dart' show members;
import 'fog_mask.dart';
import 'rules.dart';
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
      ..color = setup ? CvColors.rune500.withValues(alpha: 0.85) : const Color(0x40FFFFFF)
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

/// Cells from [a] to [b], each diagonal counting one, whatever the pack.
int rulerCells(Grid grid, Point a, Point b) =>
    SquareGrid(cellSize: grid.cellSize, offset: grid.offset).steps(a, b).round();

/// Rulers being dragged, this client's and everyone else's: a line between
/// the ends, and the distance.
class RulerPainter extends CustomPainter {
  RulerPainter(this.ruler, this.others, this.scene)
      : super(repaint: Listenable.merge([ruler, others]));

  final ValueListenable<(Point, Point)?> ruler;
  final ValueListenable<List<((Point, Point), Color)>> others;

  /// For the grid, the pack's units and the regions blocking sight.
  final Scene scene;
  Grid get grid => scene.settings.grid;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (r, color) in others.value) {
      _paint(canvas, r.$1, r.$2, color);
    }
    if (ruler.value case (final from, final to)) {
      _paint(canvas, from, to, CvColors.bone100);
    }
  }

  void _paint(Canvas canvas, Point from, Point to, Color color) {
    final u = grid.cellSize / CvSizes.token; // One design pixel.
    final a = Offset(from.x, from.y), b = Offset(to.x, to.y);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(a, b, paint
        ..color = const Color(0xB3101216)
        ..strokeWidth = 6 * u)
      ..drawLine(a, b, paint
        ..color = color
        ..strokeWidth = 3 * u);
    final dot = Paint()..color = color;
    canvas
      ..drawCircle(a, 5 * u, dot)
      ..drawCircle(b, 5 * u, dot);

    final label = TextPainter(
      text: TextSpan(
          text: rulerLabel(scene, from, to),
          style: CvTypography.label.copyWith(
              fontSize: 14 * u,
              fontFamily: CvTypography.mono,
              color: CvColors.textPrimary)),
      textDirection: TextDirection.ltr,
    )..layout();
    final pill = Rect.fromCenter(
      center: b - Offset(0, 22 * u),
      width: label.width + 16 * u,
      height: label.height + 8 * u,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(8 * u)),
        Paint()..color = CvColors.surfacePanelSolid);
    label.paint(canvas, pill.center - Offset(label.width / 2, label.height / 2));
  }

  @override
  bool shouldRepaint(RulerPainter old) =>
      old.ruler != ruler || old.others != others || old.scene != scene;
}

/// A ping on the map: where, in whose colour, and a key for its ripple.
typedef MapPing = ({Point at, Color color, Key key});

/// How long a ping shows.
const pingDuration = Duration(milliseconds: 1600);

/// One ping: a ring spreading out and fading, around a dot.
class PingRipple extends StatelessWidget {
  const PingRipple({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: pingDuration,
        builder: (context, t, _) =>
            CustomPaint(painter: _RipplePainter(color, t)),
      );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.color, this.t);

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final fade = 1 - t;
    // Two rings, the second half a beat behind.
    for (final lag in [0.0, 0.35]) {
      final k = ((t - lag) / (1 - lag)).clamp(0.0, 1.0);
      if (k == 0) continue;
      canvas.drawCircle(
          c,
          r * Curves.easeOutCubic.transform(k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.06
            ..color = color.withValues(alpha: fade));
    }
    canvas.drawCircle(
        c, r * 0.12, Paint()..color = color.withValues(alpha: fade));
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t || old.color != color;
}

/// Tokens gliding to where they were dropped. Only drops are sent, so
/// everyone but the one dragging sees a token jump; this eases it over
/// instead. Driven by [tick] from the view's ticker.
class TokenGlides extends ChangeNotifier {
  static const duration = Duration(milliseconds: 300);

  final _from = <TokenId, (Offset, Duration)>{};
  Duration _now = Duration.zero;

  bool get active => _from.isNotEmpty;

  /// Starts [id] gliding from [from] to wherever it's stored now.
  void start(TokenId id, Offset from) => _from[id] = (from, _now);

  /// The ticker started again from zero.
  void restartClock() {
    _from.updateAll((_, g) => (g.$1, Duration.zero));
    _now = Duration.zero;
  }

  void tick(Duration now) {
    _now = now;
    _from.removeWhere((_, g) => now - g.$2 >= duration);
    notifyListeners();
  }

  /// Where [id] is drawn on its way to [to].
  Offset at(TokenId id, Offset to) {
    final glide = _from[id];
    if (glide == null) return to;
    final t = ((_now - glide.$2).inMicroseconds / duration.inMicroseconds)
        .clamp(0.0, 1.0);
    return Offset.lerp(glide.$1, to, Curves.easeOutCubic.transform(t))!;
  }
}

/// Every token. A drag repaints this layer through [drag] without
/// rebuilding any widget.
///
/// Rings follow the design system: gold for the viewer's own tokens, bone
/// for other players', dashed slate for unowned, rune cyan with a halo when
/// selected. Hidden tokens (GM only) are faded with a dashed ring. Ring
/// sizes are the design's 56 px token, scaled to the token.
class TokenPainter extends CustomPainter {
  TokenPainter({
    required this.tokens,
    required this.drag,
    required this.glides,
    required this.selected,
    required this.images,
    required this.gm,
    required this.self,
    this.imagesRevision = 0,
    // Owners' colours come from the member directory, which loads later.
  }) : super(repaint: Listenable.merge([drag, glides, selected, members]));

  final Map<TokenId, Token> tokens;
  final ValueNotifier<TokenDrag?> drag;
  final TokenGlides glides;
  final ValueNotifier<TokenId?> selected;
  final ui.Image? Function(AssetId) images;
  final bool gm;
  final PlayerId self;

  /// Changes when an image [images] returns arrives, so the layer repaints
  /// with it.
  final int imagesRevision;

  /// Laid-out labels, so a drag doesn't lay text out again every frame.
  final _labels = <TokenId, (String, double, TextPainter)>{};

  /// The name, and the trackers (but zeros) and conditions on a second
  /// line: "HP 12 · Darkness 2 · Prone". Empty for none.
  static String labelText(Token token) {
    final conditions = [
      // Zeros (a fresh threat's wounds) would only crowd the label.
      for (final MapEntry(:key, :value) in token.trackers.entries)
        if (value != 0) '$key $value',
      for (final MapEntry(:key, :value) in token.conditions.entries)
        value == null ? key : '$key $value',
    ].join(' · ');
    return [
      if (token.name.isNotEmpty) token.name,
      if (conditions.isNotEmpty) conditions,
    ].join('\n');
  }

  TextPainter _label(Token token, String text, double u) {
    if (_labels[token.id] case (final cached, final size, final painter)
        when cached == text && size == token.size) {
      return painter;
    }
    final base = CvTypography.caption.copyWith(fontSize: 12 * u, height: 1.2);
    final painter = TextPainter(
      text: TextSpan(children: [
        if (token.name.isNotEmpty)
          TextSpan(
              text: token.name,
              style: base.copyWith(
                  fontWeight: FontWeight.w600, color: CvColors.textPrimary)),
        if (text.length > token.name.length)
          TextSpan(
              text: text.substring(token.name.length),
              style: base.copyWith(
                  fontSize: 11 * u, color: CvColors.rune300)),
      ]),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: token.size * 2.5);
    _labels[token.id] = (text, token.size, painter);
    return painter;
  }

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
          : glides.at(token.id, Offset(token.position.x, token.position.y));
      final u = token.size / CvSizes.token; // One design pixel.
      final radius = token.size / 2;
      if (!visible.overlaps(
          Rect.fromCircle(center: center, radius: radius + 40 * u))) {
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
        // The middle square of the image, so a portrait isn't squashed.
        final w = image.width.toDouble(), h = image.height.toDouble();
        final side = math.min(w, h);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side),
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
        _ when isSelected => (CvColors.rune500, false),
        Token(hidden: true) => (CvColors.slate300, true),
        Token(owner: null) => (CvColors.slate400, true),
        Token(:final owner) when owner == self => (CvColors.gold500, false),
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
          ..color = CvColors.rune500
          ..strokeWidth = 2 * u;
        canvas.drawCircle(center, radius + 8 * u, stroke);
      }

      // Name and conditions, on a dark pill under the ring.
      final text = labelText(token);
      if (text.isNotEmpty) {
        final label = _label(token, text, u);
        final pill = Rect.fromCenter(
          center: center +
              Offset(0, ringRadius + ringWidth / 2 + 4 * u + label.height / 2 + 2 * u),
          width: label.width + 12 * u,
          height: label.height + 4 * u,
        );
        fill.color = Color.fromARGB(token.hidden ? 0x73 : 0xD9, 0x10, 0x12, 0x16);
        canvas.drawRRect(
            RRect.fromRectAndRadius(pill, Radius.circular(10 * u)), fill);
        label.paint(canvas, pill.center - Offset(label.width / 2, label.height / 2));
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
      !identical(old.tokens, tokens) ||
      old.imagesRevision != imagesRevision ||
      old.gm != gm ||
      old.self != self;
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
    this.cursor,
    this.brush,
    this.erasing,
    this.ops = const {},
    this.naiveOps,
    Listenable? naiveRepaint,
  }) : super(repaint: Listenable.merge([preview, cursor, erasing, naiveRepaint]));

  /// The op an erase click would take away, shown in red; looked up in
  /// [ops].
  final ValueListenable<FogOpId?>? erasing;
  final Map<FogOpId, FogOp> ops;

  /// The brush outline under the pointer, at [brush]'s size, in its mode's
  /// colour: what a press would paint.
  final ValueListenable<Point?>? cursor;
  final ({double radius, FogMode mode})? brush;

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
    if ((cursor?.value, brush) case (final at?, final b?)) {
      final reveal = b.mode == FogMode.reveal;
      canvas.drawCircle(
          Offset(at.x, at.y),
          b.radius,
          Paint()
            ..color = reveal ? CvColors.fogRevealPreview : CvColors.fogCoverPreview);
      canvas.drawCircle(
          Offset(at.x, at.y),
          b.radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = b.radius / 24
            ..color = reveal ? CvColors.gold300 : CvColors.bone100);
    }
    if (ops[erasing?.value] case final op?) {
      paintFogShape(canvas, op.shape, FogMode.cover, color: CvColors.emberTint);
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
      old.revision != revision ||
      old.gm != gm ||
      old.brush != brush ||
      !identical(old.ops, ops);
}

/// A label pill, as the ruler draws it, centred on [center]. [u] is one
/// design pixel in scene units.
void _pill(Canvas canvas, String text, Offset center, double u,
    {Color color = CvColors.textPrimary, bool mono = true, double? maxWidth}) {
  final label = TextPainter(
    text: TextSpan(
        text: text,
        style: CvTypography.label.copyWith(
            fontSize: (mono ? 14 : 12) * u,
            fontFamily: mono ? CvTypography.mono : null,
            color: color)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? double.infinity);
  final pill = Rect.fromCenter(
    center: center,
    width: label.width + 16 * u,
    height: label.height + 8 * u,
  );
  canvas.drawRRect(RRect.fromRectAndRadius(pill, Radius.circular(8 * u)),
      Paint()..color = CvColors.surfacePanelSolid);
  label.paint(canvas, pill.center - Offset(label.width / 2, label.height / 2));
}

/// Regions: a wash and an outline, and their tags along the top edge.
/// Players only get regions that carry tags; the GM sees every one, hidden
/// ones dimmer, and the one being drawn.
class RegionPainter extends CustomPainter {
  RegionPainter(
      {required this.scene,
      required this.draft,
      required this.selected,
      required this.gm})
      : super(repaint: Listenable.merge([draft, selected]));

  final Scene scene;
  final ValueListenable<(Point, Point)?> draft;
  final ValueListenable<RegionId?> selected;
  final bool gm;

  @override
  void paint(Canvas canvas, Size size) {
    final u = scene.settings.grid.cellSize / CvSizes.token;
    for (final r in scene.regions.values) {
      if (!gm && r.tags.isEmpty) continue;
      final rect = Rect.fromPoints(Offset(r.from.x, r.from.y), Offset(r.to.x, r.to.y));
      final picked = r.id == selected.value;
      final alpha = r.hidden ? 0.5 : 1.0;
      canvas
        ..drawRect(
            rect,
            Paint()
              ..color = (picked ? CvColors.runeTint : const Color(0x24ECE8DD))
                  .withValues(alpha: (picked ? 0.16 : 0.14) * alpha))
        ..drawRect(
            rect.deflate(u),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * u
              ..color = (picked ? CvColors.rune500 : CvColors.slate300)
                  .withValues(alpha: 0.9 * alpha));
      final tags = [
        for (final MapEntry(:key, :value) in r.tags.entries)
          value == null ? key : '$key $value',
      ];
      final text = [if (r.hidden) 'Hidden', ...tags].join(' · ');
      if (text.isNotEmpty) {
        _pill(canvas, text, Offset(rect.center.dx, rect.top + 14 * u), u,
            color: r.hidden ? CvColors.textSecondary : CvColors.textPrimary,
            mono: false,
            maxWidth: rect.width - 24 * u);
      }
    }
    if (draft.value case (final a, final b)) {
      canvas.drawRect(
          Rect.fromPoints(Offset(a.x, a.y), Offset(b.x, b.y)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * u
            ..color = CvColors.rune500);
    }
  }

  @override
  bool shouldRepaint(RegionPainter old) =>
      !identical(old.scene.regions, scene.regions) ||
      old.scene.settings != scene.settings ||
      old.gm != gm;
}

/// While this client drags a token: what the move costs in the pack's
/// unit, the checks the regions it enters ask for, and whether one is full.
class MovePainter extends CustomPainter {
  MovePainter(this.drag, this.scene, {required this.snap}) : super(repaint: drag);

  final ValueListenable<TokenDrag?> drag;
  final Scene scene;

  /// Measures to where the token will land, as the drop snaps it.
  final bool snap;

  @override
  void paint(Canvas canvas, Size size) {
    final d = drag.value;
    final token = d == null ? null : scene.tokens[d.id];
    if (d == null || token == null) return;
    final Point at = (x: d.position.dx, y: d.position.dy);
    final to = snap ? scene.settings.grid.snap(at, token.size) : at;
    if (to == token.position) return;
    final engine = engineFor(scene);
    final move = engine.checkMove(token.position, to, occupants: [
      for (final t in scene.tokens.values)
        if (t.id != token.id) t.position,
    ]);
    final text = [
      formatDistance(move.cost, engine.pack.unit),
      ...move.checks.map((c) => '$c check'),
      if (move.blocked) 'full',
    ].join(' · ');
    final u = scene.settings.grid.cellSize / CvSizes.token;
    _pill(canvas, text, Offset(to.x, to.y - token.size / 2 - 18 * u), u,
        color: move.blocked ? CvColors.ember400 : CvColors.textPrimary);
  }

  @override
  bool shouldRepaint(MovePainter old) =>
      old.scene != scene || old.snap != snap || old.drag != drag;
}
