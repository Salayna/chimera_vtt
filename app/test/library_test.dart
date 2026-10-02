import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
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
  test('a library scene copy keeps everything but token owners', () {
    const a = TokenId('a');
    final scene = Scene(
      settings: const SceneSettings(
          width: 100, height: 100, grid: Grid(cellSize: 10)),
      tokens: {
        a: const Token(
            id: a,
            position: (x: 5, y: 5),
            size: 10,
            name: 'Aria',
            owner: PlayerId('p')),
      },
    );
    final copy = withoutOwners(scene).tokens[a]!;
    expect(copy.owner, isNull);
    expect(copy.name, 'Aria');
    expect(copy.position, (x: 5.0, y: 5.0));
  });

  testWidgets('thumbnails fit 256 px on their longest side, never larger',
      (tester) async {
    await tester.runAsync(() async {
      expect(await size(await thumbnail(await blank(1000, 500))), (256, 128));
      expect(await size(await thumbnail(await blank(100, 300))), (85, 256));
      expect(await size(await thumbnail(await blank(64, 32))), (64, 32));
    });
  });
}
