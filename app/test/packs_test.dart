import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/packs.dart';
import 'package:chimera_vtt/table/rules.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

Uint8List bytes(Object json) => utf8.encode(jsonEncode(json));

void main() {
  test('pack files: modules and Atlas presets read; built-in ids are refused', () {
    final solaris = readPackFile(File('../packs/solaris-arcanum.json').readAsBytesSync());
    expect(solaris.name, 'Solaris Arcanum');
    expect(packSummary(solaris), '0 conditions · 5 region tags · 4 range bands');

    final atlas = readPackFile(bytes({
      'id': 'mine',
      'name': 'Mine',
      'rules': {
        'gridDefaults': {'unitType': 'meters', 'unitDistance': 1.5, 'measurementMode': 'metric'},
        'conditions': [{'id': 'p', 'name': 'Prone', 'color': '#aabbcc'}],
      },
    }));
    expect((atlas.unit, atlas.unitsPerStep, atlas.conditions.single.name), ('m', 1.5, 'Prone'));

    expect(() => readPackFile(bytes({'id': 'dnd5e', 'name': 'x', 'unit': 'ft'})),
        throwsFormatException);
    expect(() => readPackFile(utf8.encode('not json')), throwsFormatException);
  });

  test('a scene plays with the pack it carries', () {
    final data = jsonDecode(File('../packs/solaris-arcanum.json').readAsStringSync()) as Json;
    final scene = Scene(
      settings: const SceneSettings(
          width: 1000, height: 1000, grid: Grid(cellSize: 100), pack: 'solaris-arcanum'),
      packFile: ScenePack(data),
    );
    expect(packOf(scene).name, 'Solaris Arcanum');
    expect(identical(packOf(scene), packOf(scene)), isTrue); // Parsed once.
    expect(rulerLabel(scene, (x: 50, y: 50), (x: 150, y: 50)), '1 sector · Adjacent');
    // Settings naming a pack the scene doesn't carry: Generic.
    expect(packOf(Scene(settings: scene.settings)).name, 'Generic');
  });

  testWidgets('the Systems page lists the built-in systems', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = SupabaseClient('http://127.0.0.1:9', 'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    await tester.pumpWidget(cvApp(
        title: 'test', home: SystemsPage(packs: InstalledPacks(client))));
    expect(find.text('Generic'), findsOneWidget);
    expect(find.text('D&D 5e'), findsOneWidget);
    expect(find.text('Install system'), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  });
}
