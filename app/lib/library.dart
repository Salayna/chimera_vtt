import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'assets.dart';

enum LibraryKind { map, token }

/// An image in the GM's library.
typedef LibraryEntry = ({String id, String name, AssetId asset, AssetId thumb});

/// The signed-in GM's library: their images, shared by all their campaigns.
/// Owner-only behind row-level security.
class Library {
  Library(this._client, this._assets);

  final SupabaseClient _client;
  final AssetStore _assets;

  /// Thumbnails' longest side, in pixels.
  static const thumbSize = 256;

  /// Files [asset] under [kind] as [name], with a thumbnail made from
  /// [image]. The same image filed again keeps its first entry.
  Future<void> add(
      LibraryKind kind, String name, AssetId asset, ui.Image image) async {
    final thumb = await _assets.upload(await thumbnail(image), 'image/png');
    await _client.from('library').upsert({
      'owner': _client.auth.currentUser!.id,
      'kind': kind.name,
      'name': name,
      'asset': asset.value,
      'thumb': thumb.value,
    }, onConflict: 'owner,kind,asset', ignoreDuplicates: true);
  }

  Future<List<LibraryEntry>> list(LibraryKind kind) async => [
        for (final r in await _client
            .from('library')
            .select('id, name, asset, thumb')
            .eq('kind', kind.name)
            .order('created_at', ascending: true))
          (
            id: r['id'] as String,
            name: r['name'] as String,
            asset: AssetId(r['asset'] as String),
            thumb: AssetId(r['thumb'] as String),
          ),
      ];
}

/// [image] scaled down to [Library.thumbSize] on its longest side, as PNG.
Future<Uint8List> thumbnail(ui.Image image) async {
  final scale = Library.thumbSize / (image.width > image.height ? image.width : image.height);
  final w = (image.width * (scale < 1 ? scale : 1)).round().clamp(1, Library.thumbSize);
  final h = (image.height * (scale < 1 ? scale : 1)).round().clamp(1, Library.thumbSize);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final thumb = await picture.toImage(w, h);
  picture.dispose();
  final png = await thumb.toByteData(format: ui.ImageByteFormat.png);
  thumb.dispose();
  return png!.buffer.asUint8List();
}
