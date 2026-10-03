import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:tactical_engine/tactical_engine.dart' show SystemPack;

/// A module bundle: a zip (`.chimera`) holding the pack as `module.json`
/// and every image it uses as `images/<sha256>`. More than a pack file: a
/// module's tokens, cards and cover come with it.
typedef ModuleBundle = ({SystemPack pack, Map<String, Uint8List> images});

const bundleExtension = 'chimera';

/// Bundles come from anyone: bounded before anything is unpacked.
const maxBundleBytes = 64 << 20;
const maxImageBytes = 15 << 20;
const maxImages = 600;

/// The content type of an image the asset store takes, from its first
/// bytes; null for anything else.
String? imageType(Uint8List b) {
  bool starts(List<int> sig, [int at = 0]) =>
      b.length >= at + sig.length &&
      [for (var i = 0; i < sig.length; i++) b[at + i] == sig[i]].every((x) => x);
  if (starts(const [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) {
    return 'image/webp';
  }
  return null;
}

/// [pack] and its [images] (by asset id) as a bundle. Throws an
/// [ArgumentError] if an image the pack uses is missing.
Uint8List encodeBundle(SystemPack pack, Map<String, Uint8List> images) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('module.json',
        const JsonEncoder.withIndent('  ').convert(pack.toJson())));
  for (final id in pack.assets) {
    final bytes = images[id] ?? (throw ArgumentError('Missing image $id'));
    // Already compressed: storing them saves time for nothing lost.
    archive.addFile(ArchiveFile.noCompress('images/$id', bytes.length, bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}

/// Reads a bundle. Throws a [FormatException] saying what's wrong: not a
/// zip, no module, a bad pack, an image missing, altered or not an image.
// ponytail: sizes are checked as declared and as unpacked, but a lying
// header still unpacks once; stream the entries if bundles get hostile.
ModuleBundle decodeBundle(Uint8List bytes) {
  if (bytes.length > maxBundleBytes) {
    throw const FormatException('A module bundle holds up to 64 MB.');
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const FormatException('This file isn\'t a module bundle (a zip).');
  }
  final files = [for (final f in archive.files) if (f.isFile) f];
  if (files.length > maxImages + 1) {
    throw const FormatException('A module bundle holds up to 600 images.');
  }
  Uint8List read(ArchiveFile f, int max) {
    if (f.size > max) throw FormatException('${f.name} is too large.');
    final data = f.readBytes() ?? Uint8List(0);
    if (data.length > max) throw FormatException('${f.name} is too large.');
    return data;
  }

  final manifest = files.where((f) => f.name == 'module.json').firstOrNull ??
      (throw const FormatException('The bundle has no module.json.'));
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(read(manifest, 8 << 20)));
  } on FormatException {
    throw const FormatException('module.json isn\'t JSON.');
  }
  if (json is! Map<String, dynamic>) {
    throw const FormatException('module.json holds one object.');
  }
  final pack = SystemPack.fromJson(json);
  final images = <String, Uint8List>{};
  for (final f in files) {
    if (!f.name.startsWith('images/')) continue;
    final id = f.name.substring('images/'.length);
    if (!pack.assets.contains(id)) continue; // Unused: left out.
    final data = read(f, maxImageBytes);
    if (sha256.convert(data).toString() != id) {
      throw FormatException('Image $id doesn\'t match its name.');
    }
    if (imageType(data) == null) {
      throw FormatException('Image $id isn\'t a PNG, JPEG or WebP.');
    }
    images[id] = data;
  }
  final missing = pack.assets.difference(images.keys.toSet());
  if (missing.isNotEmpty) {
    throw FormatException('The bundle lacks ${missing.length} of its images.');
  }
  return (pack: pack, images: images);
}
