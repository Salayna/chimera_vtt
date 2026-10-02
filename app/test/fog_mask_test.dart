import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/demo_assets.dart';
import 'package:chimera_vtt/table/fog_mask.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = SceneSettings(
    width: 512, height: 512, grid: Grid(cellSize: 64), fogByDefault: true);

Future<Uint8List> pixels(ui.Image image) async =>
    (await image.toByteData())!.buffer.asUint8List();

void main() {
  testWidgets('drawing ops one at a time matches drawing them all at once',
      (tester) async {
    final random = math.Random(3);
    final ops = [
      for (var i = 0; i < 40; i++)
        FogOp(
          id: FogOpId('f$i'),
          order: i + 1,
          mode: i % 3 == 0 ? FogMode.cover : FogMode.reveal,
          shape: i % 5 == 0
              ? FogRect((x: random.nextDouble() * 512, y: 0),
                  (x: 512, y: random.nextDouble() * 512))
              : randomStroke(random, 512, points: 6),
        ),
    ];

    final incremental = FogMask();
    for (var i = 1; i <= ops.length; i++) {
      expect(incremental.sync(settings, ops.sublist(0, i)), isTrue);
      if (i % 7 == 0) incremental.bake(); // Bake in uneven batches.
    }
    expect(incremental.sync(settings, ops), isFalse, reason: 'no change');
    expect(incremental.pending, isNotEmpty);
    incremental.bake();
    expect(incremental.pending, isEmpty);
    final all = FogMask()..sync(settings, ops);

    await tester.runAsync(() async {
      final a = await pixels(incremental.image!);
      final b = await pixels(all.image!);
      // Repeated resampling may shift a channel by one step; anything more
      // is a real difference.
      var worst = 0;
      for (var i = 0; i < a.length; i++) {
        worst = math.max(worst, (a[i] - b[i]).abs());
      }
      expect(worst, lessThanOrEqualTo(1));
      expect(a.where((v) => v != 0), isNotEmpty, reason: 'some fog left');
    });
  });

  testWidgets('removing an op rebuilds the mask', (tester) async {
    final rect = FogOp(
        id: const FogOpId('r'),
        order: 1,
        mode: FogMode.reveal,
        shape: const FogRect((x: 0, y: 0), (x: 512, y: 512)));
    final mask = FogMask()..sync(settings, [rect]);
    expect(mask.sync(settings, []), isTrue);
    await tester.runAsync(() async {
      final a = await pixels(mask.image!);
      final alpha = [for (var i = 3; i < a.length; i += 4) a[i]];
      expect(alpha.every((v) => v == 255), isTrue, reason: 'fully fogged again');
    });
  });
}
