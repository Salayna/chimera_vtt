import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';

/// A busy, map-sized placeholder image, drawn rather than loaded so the POC
/// needs no asset files.
ui.Image generateMap(int size, {int seed = 1}) {
  final random = math.Random(seed);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final s = size.toDouble();
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, s, s),
    ui.Paint()
      ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(s, s),
          const [ui.Color(0xFF3B4A2F), ui.Color(0xFF6B5B3E)]),
  );
  final paint = ui.Paint();
  for (var i = 0; i < 3000; i++) {
    paint.color = ui.Color.fromARGB(40 + random.nextInt(80), random.nextInt(256),
        random.nextInt(256), random.nextInt(256));
    final center = ui.Offset(random.nextDouble() * s, random.nextDouble() * s);
    if (i.isEven) {
      canvas.drawCircle(center, 8 + random.nextDouble() * 60, paint);
    } else {
      canvas.drawRect(
          ui.Rect.fromCenter(
              center: center,
              width: 10 + random.nextDouble() * 120,
              height: 10 + random.nextDouble() * 120),
          paint);
    }
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size, size);
  picture.dispose();
  return image;
}

/// [count] token portraits, keyed by made-up asset ids.
Map<AssetId, ui.Image> generateTokenImages(int count, {int size = 256}) => {
      for (var i = 0; i < count; i++) AssetId('token$i'): _portrait(i, size),
    };

ui.Image _portrait(int i, int size) {
  final s = size.toDouble();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final hue = (i * 47 % 360).toDouble();
  canvas
    ..drawCircle(ui.Offset(s / 2, s / 2), s / 2,
        ui.Paint()..color = _hsv(hue, 0.5, 0.9))
    ..drawCircle(ui.Offset(s / 2, s * 0.4), s * 0.18,
        ui.Paint()..color = _hsv(hue, 0.7, 0.4))
    ..drawOval(ui.Rect.fromLTWH(s * 0.22, s * 0.6, s * 0.56, s * 0.4),
        ui.Paint()..color = _hsv(hue, 0.7, 0.4));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(size, size);
  picture.dispose();
  return image;
}

ui.Color _hsv(double hue, double saturation, double value) {
  final c = value * saturation;
  final x = c * (1 - ((hue / 60) % 2 - 1).abs());
  final m = value - c;
  final (r, g, b) = switch (hue ~/ 60) {
    0 => (c, x, 0.0),
    1 => (x, c, 0.0),
    2 => (0.0, c, x),
    3 => (0.0, x, c),
    4 => (x, 0.0, c),
    _ => (c, 0.0, x),
  };
  return ui.Color.from(alpha: 1, red: r + m, green: g + m, blue: b + m);
}

/// A random brush stroke of [points] points across a map of [size].
FogBrush randomStroke(math.Random random, double size, {int points = 10}) {
  var p = (x: random.nextDouble() * size, y: random.nextDouble() * size);
  return FogBrush([
    for (var i = 0; i < points; i++)
      p = (
        x: (p.x + random.nextDouble() * 120 - 60).clamp(0, size),
        y: (p.y + random.nextDouble() * 120 - 60).clamp(0, size),
      ),
  ], 24 + random.nextDouble() * 48);
}
