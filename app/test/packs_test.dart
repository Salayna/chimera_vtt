import 'dart:convert';
import 'dart:io';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/pack_tokens.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:flutter/services.dart';
import 'package:chimera_vtt/packs.dart';
import 'package:chimera_vtt/table/rules.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart' show SystemPack;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

Uint8List bytes(Object json) => utf8.encode(jsonEncode(json));

void main() {
  test('pack files: modules and Atlas presets read; built-in ids are refused', () {
    final solaris = readPackFile(File('../packs/solaris-arcanum.json').readAsBytesSync());
    expect(solaris.name, 'Solaris Arcanum');
    expect(packSummary(solaris), '46 conditions · 15 region tags · 12 trackers · 4 range bands');

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

  testWidgets("a player tracks their token's numbers within the pack's bounds",
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = TokenId('t');
    const me = PlayerId('me');
    const pack = {
      'id': 'mine',
      'name': 'Mine',
      'unit': 'ft',
      'trackers': [
        {'name': 'HP'},
        {'name': 'Stress', 'max': 6},
      ],
    };
    final host = HostSession(
      LoopbackHub().connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 1000, height: 1000, grid: Grid(cellSize: 100), pack: 'mine'),
        packFile: const ScenePack(pack),
        tokens: {
          id: const Token(id: id, position: (x: 50, y: 50), size: 100, owner: me),
        },
      )),
    );
    final controller = TableController();
    addTearDown(controller.dispose);
    controller.selected.value = id;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TokenCardLayer(
        store: host.store,
        session: host,
        controller: controller,
        send: (c) => host.store.execute(const Player(me), c),
        gm: false,
      ),
    ));
    expect(find.text('Trackers'), findsOneWidget);
    // Only trackers the token has show; a menu adds the others.
    expect(find.text('Stress / 6'), findsNothing);
    Future<void> add(String name) async {
      await tester.tap(find.text('Add a tracker…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    await add('HP');
    await add('Stress');
    expect(find.text('Stress / 6'), findsOneWidget);
    expect(find.text('Add a tracker…'), findsNothing);

    await tester.enterText(find.byType(EditableText).first, '12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(host.store.scene.tokens[id]!.trackers, {'HP': 12, 'Stress': 0});

    Finder button(String label) => find.byWidgetPredicate(
        (w) => w is CvToolButton && w.label == label);
    await tester.ensureVisible(button('Stress +1'));
    for (var i = 0; i < 8; i++) {
      await tester.tap(button('Stress +1'));
      await tester.pump();
    }
    expect(host.store.scene.tokens[id]!.trackers['Stress'], 6); // Its max.
    await tester.tap(button('HP −1'));
    await tester.pump();
    expect(host.store.scene.tokens[id]!.trackers['HP'], 11);
  });

  testWidgets("a placed pack token shows the GM its card and its own maximums",
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pack = SystemPack.fromJson({
      'id': 'mine',
      'name': 'Mine',
      'unit': 'ft',
      'trackers': [{'name': 'CvW', 'text': 'Cardiovascular Wounds.'}, {'name': 'AP'}],
      'tokens': [
        {
          'name': 'Raider',
          'size': 2,
          'trackers': [{'name': 'CvW', 'max': 6}],
          'conditions': {'Synthetic': null},
          'card': [{'title': 'Attack Profiles', 'text': 'Cleave: 2d20, Point Blank'}],
        },
      ],
    });
    const id = TokenId('r');
    final raider = tokenFrom(pack.tokens['Raider']!,
        id: id, position: (x: 100, y: 100), cellSize: 100);
    expect((raider.size, raider.template), (200.0, 'Raider'));
    expect(raider.trackers, {'CvW': 0});
    expect(raider.conditions, {'Synthetic': null});
    expect(trackersFor(raider, pack).map((t) => (t.name, t.max)),
        [('CvW', 6), ('AP', null)]);

    final host = HostSession(
      LoopbackHub().connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 1000, height: 1000, grid: Grid(cellSize: 100), pack: 'mine'),
        packFile: ScenePack(pack.toJson(tokens: false)),
        tokens: {id: raider},
      )),
    );
    final controller = TableController();
    addTearDown(controller.dispose);
    controller.selected.value = id;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TokenCardLayer(
        store: host.store,
        session: host,
        controller: controller,
        send: host.execute,
        fullPack: (_) => pack,
      ),
    ));
    expect(find.text('CvW / 6'), findsOneWidget);
    expect(find.text('ATTACK PROFILES'), findsOneWidget);
    expect(find.text('Cleave: 2d20, Point Blank'), findsOneWidget);
  });
}
