import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, StorageException, SupabaseClient;

/// Images in Supabase Storage, named by the SHA-256 of their bytes
/// (ADR 006). A name always means the same bytes, so a downloaded image is
/// kept for the whole session and HTTP caches may keep it forever.
class AssetStore {
  AssetStore(this._client);

  static const bucket = 'assets';

  /// The types the bucket accepts, by file extension.
  static const contentTypes = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  final SupabaseClient _client;
  final _images = <AssetId, Future<ui.Image>>{};

  /// Uploads [bytes] unless an identical file is already there.
  Future<AssetId> upload(Uint8List bytes, String contentType) async {
    final id = AssetId(sha256.convert(bytes).toString());
    try {
      await _client.storage.from(bucket).uploadBinary(
            id.value,
            bytes,
            fileOptions: FileOptions(
              contentType: contentType,
              cacheControl: '31536000', // A year: the content never changes.
            ),
          );
    } on StorageException catch (e) {
      // Same name, same bytes: someone already uploaded this file.
      if (e.statusCode != '409') rethrow;
    }
    return id;
  }

  /// The file itself, for a module bundle. Not kept.
  Future<Uint8List> bytes(AssetId id) =>
      _client.storage.from(bucket).download(id.value);

  /// The decoded image, downloaded once per session.
  Future<ui.Image> image(AssetId id) =>
      _images[id] ??= _download(id).catchError((Object e, StackTrace s) {
        _images.remove(id); // Let a later call retry.
        return Future<ui.Image>.error(e, s);
      });

  /// Makes an image this client already has (it just uploaded it)
  /// available without downloading it back.
  void remember(AssetId id, ui.Image image) => _images[id] = Future.value(image);

  Future<ui.Image> _download(AssetId id) async {
    final watch = Stopwatch()..start();
    final bytes = await _client.storage.from(bucket).download(id.value);
    final downloaded = watch.elapsedMilliseconds;
    final image = await decodeImage(bytes);
    // Feeds H4 (load time); cheap enough to keep.
    debugPrint('Asset ${id.value.substring(0, 8)}: '
        '${bytes.length ~/ 1024} KB, download $downloaded ms, '
        'decode ${watch.elapsedMilliseconds - downloaded} ms');
    return image;
  }
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
