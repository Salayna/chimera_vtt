// Live check of AssetStore and the Storage policies against a running
// Supabase. Skipped unless SUPABASE_URL and SUPABASE_KEY are set:
//
//   SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_KEY=<publishable key> \
//     flutter test test/assets_test.dart
@Tags(['supabase'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_vtt/assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final url = Platform.environment['SUPABASE_URL'];
final key = Platform.environment['SUPABASE_KEY'];

Future<SupabaseClient> signIn() async {
  final client = SupabaseClient(url!, key!);
  await client.auth.signInAnonymously();
  return client;
}

/// A small PNG with a random colour, so each run uploads new bytes.
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(
      ui.Color(0xFF000000 | DateTime.now().microsecondsSinceEpoch & 0xFFFFFF),
      ui.BlendMode.src);
  final image = recorder.endRecording().toImageSync(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding blocks real HTTP; this test is about the real thing.
  HttpOverrides.global = null;

  test(
    'maps upload by hash, deduplicate, and load on another client (H4)',
    () async {
      final gm = await signIn();
      final player = await signIn();
      final bytes = await png(64, 32);

      final id = await AssetStore(gm).upload(bytes, 'image/png');
      expect(id.value, matches(RegExp(r'^[0-9a-f]{64}$')));
      // Again, as another GM with the same file would: no error, same id.
      expect((await AssetStore(gm).upload(bytes, 'image/png')).value, id.value);

      final watch = Stopwatch()..start();
      final image = await AssetStore(player).image(id);
      // ignore: avoid_print
      print('First download and decode: ${watch.elapsedMilliseconds} ms');
      expect((image.width, image.height), (64, 32));

      final bucket = gm.storage.from(AssetStore.bucket);
      // Names must be content hashes.
      await expectLater(
        bucket.uploadBinary('not-a-hash.png', bytes,
            fileOptions: const FileOptions(contentType: 'image/png')),
        throwsA(isA<StorageException>()),
      );
      // An existing file can't be replaced, even by its uploader.
      await expectLater(
        bucket.uploadBinary(id.value, await png(8, 8),
            fileOptions:
                const FileOptions(contentType: 'image/png', upsert: true)),
        throwsA(isA<StorageException>()),
      );
      // Only images.
      await expectLater(
        AssetStore(gm).upload(Uint8List.fromList([1, 2, 3]), 'text/plain'),
        throwsA(isA<StorageException>()),
      );

      await gm.dispose();
      await player.dispose();
    },
    skip: url == null || key == null ? 'SUPABASE_URL/SUPABASE_KEY not set' : false,
  );
}
