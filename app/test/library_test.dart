import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_vtt/library.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> blank(int w, int h) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF336699));
  return recorder.endRecording().toImage(w, h);
}

Future<(int, int)> size(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  return (image.width, image.height);
}

void main() {
  testWidgets('thumbnails fit 256 px on their longest side, never larger',
      (tester) async {
    await tester.runAsync(() async {
      expect(await size(await thumbnail(await blank(1000, 500))), (256, 128));
      expect(await size(await thumbnail(await blank(100, 300))), (85, 256));
      expect(await size(await thumbnail(await blank(64, 32))), (64, 32));
    });
  });
}
