import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chimera_vtt/module_editor.dart';
import 'package:chimera_vtt/modules.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart';

void main() {
  // The smallest files that pass for each type.
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 9]);
  String id(Uint8List b) => sha256.convert(b).toString();

  SystemPack module() => SystemPack.fromJson({
        'id': 'mod',
        'name': 'Module',
        'unit': 'ft',
        'cover': id(png),
        'tokens': [
          {
            'name': 'Goblin',
            'image': id(jpeg),
            'card': [
              {'title': 'Art', 'text': '', 'image': id(png)},
            ],
          },
        ],
      });

  test('a bundle carries its module and every image it uses', () {
    final bytes = encodeBundle(module(), {id(png): png, id(jpeg): jpeg});
    final back = decodeBundle(bytes);
    expect(back.pack.toJson(), module().toJson());
    expect(back.images.keys.toSet(), {id(png), id(jpeg)});
    expect(back.images[id(jpeg)], jpeg);
    expect(imageType(png), 'image/png');
    expect(imageType(jpeg), 'image/jpeg');
    expect(imageType(Uint8List.fromList([1, 2, 3])), isNull);
    expect(() => encodeBundle(module(), {id(png): png}), throwsArgumentError);
  });

  test('a bundle with an altered, missing or fake image is refused', () {
    Uint8List zip(Map<String, List<int>> files) {
      final a = Archive();
      files.forEach((name, data) => a.addFile(ArchiveFile.bytes(name, data)));
      return ZipEncoder().encodeBytes(a);
    }

    final manifest = module().toJson().toString(); // Not JSON on purpose.
    expect(() => decodeBundle(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
    expect(() => decodeBundle(zip({'images/x': png})), throwsFormatException);
    expect(() => decodeBundle(zip({'module.json': manifest.codeUnits})),
        throwsFormatException);
    final good = encodeBundle(module(), {id(png): png, id(jpeg): jpeg});
    final files = {
      for (final f in ZipDecoder().decodeBytes(good).files)
        f.name: f.readBytes()!.toList(),
    };
    // Altered: the bytes no longer hash to the name.
    expect(() => decodeBundle(zip({...files, 'images/${id(png)}': [...png, 0]})),
        throwsFormatException);
    // Missing.
    expect(() => decodeBundle(zip({...files}..remove('images/${id(jpeg)}'))),
        throwsFormatException);
  });

  test('a module written in the app builds into a pack', () {
    final d = ModuleDraft()
      ..name = 'Blades in the Dark!'
      ..unit = 'zone'
      ..initiative = 'd6'
      ..cover = id(png);
    d.tags.add(DraftTag('Harm', TagKind.condition, valued: true));
    d.trackers.add(DraftTracker('Stress', 0, 9));
    d.tokens.add(DraftToken('Bluecoat', image: id(jpeg), size: 2,
        card: [DraftSection('Attacks', 'Truncheon', id(png))]));
    final pack = d.build();
    expect(pack.id, 'blades-in-the-dark');
    expect(pack.version, 1);
    expect(pack.assets, {id(png), id(jpeg)});
    expect(pack.tokens['Bluecoat']!.card.single.image, id(png));
    expect(pack.conditions.single.valued, isTrue);
    expect(pack.trackers.single.max, 9);
  });

  test('editing keeps what the editor hides, and bumps the version', () {
    final base = SystemPack.fromJson({
      'id': 'mine',
      'name': 'Mine',
      'version': 3,
      'unit': 'ft',
      'bands': [{'name': 'Near', 'max': 30}, {'name': 'Far'}],
      'forms': [{'name': 'Rush', 'value': 2}],
      'tags': [
        {'name': 'Cover', 'effects': [{'type': 'blocksSight'}]},
      ],
      'tokens': [
        {'name': 'Orc', 'trackers': [{'name': 'HP', 'max': 15, 'value': 15}]},
      ],
      'sheet': {
        'sections': [
          {'title': 'Stats', 'fields': [{'name': 'END'}]},
        ],
      },
    });
    final d = ModuleDraft(base)..name = 'Mine, renamed';
    final pack = d.build();
    expect(pack.id, 'mine'); // An edit keeps its id: scenes name it.
    expect(pack.version, 4);
    expect(pack.bands, hasLength(2));
    expect(pack.forms.single.name, 'Rush');
    expect(pack.tags['Cover']!.effects.single, isA<BlocksSight>());
    expect(pack.tokens['Orc']!.trackers.single.max, 15);
    expect(pack.sheet!.fields.single.name, 'END');
  });

  test('a draft the format refuses says why', () {
    expect(() => ModuleDraft().build(), throwsFormatException); // No name.
    expect(() => (ModuleDraft()..name = 'Generic').build(), throwsFormatException);
    expect(() => (ModuleDraft()..name = 'X'..initiative = 'lots').build(),
        throwsFormatException);
    final twins = ModuleDraft()..name = 'X';
    twins.tags.addAll([DraftTag('A', TagKind.condition), DraftTag('A', TagKind.region)]);
    expect(twins.build, throwsFormatException);
  });
}
