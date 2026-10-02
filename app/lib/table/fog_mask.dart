import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';

/// The fog as one image, so a frame costs one draw however many ops exist
/// (ADR 007). Opaque pixels are fogged.
///
/// New ops wait in [pending], drawn as vectors over the mask, until [bake]
/// draws them in: turning a picture into an image costs about 35 ms on
/// CanvasKit (0.4 ms on skwasm), too much to pay per stroke. Anything other
/// than new ops (an op removed or changed, another map size) rebuilds the
/// mask from every op at once.
final class FogMask {
  /// The longest side of the mask in pixels. Fog edges are soft, so a mask
  /// smaller than the map saves memory without visible loss.
  static const maxSide = 2048;

  /// Pending ops bake on their own past this count.
  static const maxPending = 32;

  ui.Image? _image;
  List<FogOp> _ops = const [];
  List<FogOp> _pending = [];
  SceneSettings? _settings;

  ui.Image? get image => _image;

  /// Ops not yet in [image], in drawing order.
  List<FogOp> get pending => _pending;

  /// Brings the mask up to date with [ops], given in drawing order. Returns
  /// whether it changed.
  bool sync(SceneSettings settings, List<FogOp> ops) {
    final sameSize = _settings != null &&
        _settings!.width == settings.width &&
        _settings!.height == settings.height &&
        _settings!.fogByDefault == settings.fogByDefault;
    if (sameSize && _isPrefix(_ops, ops)) {
      if (ops.length == _ops.length) return false;
      _pending = [..._pending, ...ops.sublist(_ops.length)];
      _ops = ops;
      if (_pending.length >= maxPending) bake();
    } else {
      _settings = settings;
      _ops = ops;
      _pending = [];
      _redraw(ops, from: null);
    }
    return true;
  }

  /// Draws [pending] into [image]. Call when fog painting pauses.
  void bake() {
    if (_pending.isEmpty) return;
    _redraw(_pending, from: _image);
    _pending = [];
  }

  void dispose() {
    _image?.dispose();
    _image = null;
  }

  void _redraw(List<FogOp> ops, {ui.Image? from}) {
    final settings = _settings!;
    final scale = maxSide / math.max(settings.width, settings.height);
    final width = (settings.width * math.min(scale, 1)).ceil();
    final height = (settings.height * math.min(scale, 1)).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(width / settings.width, height / settings.height);
    final bounds = ui.Rect.fromLTWH(0, 0, settings.width, settings.height);
    if (from != null) {
      canvas.drawImageRect(
        from,
        ui.Rect.fromLTWH(0, 0, from.width.toDouble(), from.height.toDouble()),
        bounds,
        ui.Paint(),
      );
    } else if (settings.fogByDefault) {
      canvas.drawRect(bounds, ui.Paint());
    }
    for (final op in ops) {
      paintFogShape(canvas, op.shape, op.mode);
    }
    final picture = recorder.endRecording();
    final next = picture.toImageSync(width, height);
    picture.dispose();
    _image?.dispose();
    _image = next;
  }

  static bool _isPrefix(List<FogOp> a, List<FogOp> b) {
    if (a.length > b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

/// Draws one fog shape: cover paints, reveal clears.
void paintFogShape(ui.Canvas canvas, FogShape shape, FogMode mode,
    {ui.Color color = const ui.Color(0xFF000000)}) {
  final paint = ui.Paint()
    ..color = color
    ..blendMode = mode == FogMode.cover ? ui.BlendMode.srcOver : ui.BlendMode.clear;
  switch (shape) {
    case FogRect(:final from, :final to):
      canvas.drawRect(
          ui.Rect.fromPoints(ui.Offset(from.x, from.y), ui.Offset(to.x, to.y)),
          paint);
    case FogBrush(:final points, :final radius) when points.length == 1:
      canvas.drawCircle(ui.Offset(points.first.x, points.first.y), radius, paint);
    case FogBrush(:final points, :final radius):
      final path = ui.Path()..moveTo(points.first.x, points.first.y);
      for (final p in points.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      canvas.drawPath(
        path,
        paint
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = radius * 2
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round,
      );
  }
}
