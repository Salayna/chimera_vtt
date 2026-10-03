import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/initiative.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const alice = PlayerId('alice');

Scene table() => Scene(
      settings: const SceneSettings(width: 1000, height: 1000, grid: Grid(cellSize: 100)),
      tokens: {
        for (final t in const [
          Token(id: TokenId('a'), position: (x: 50, y: 50), size: 100, name: 'Aria', owner: alice),
          Token(id: TokenId('g'), position: (x: 250, y: 50), size: 100, name: 'Goblin'),
        ])
          t.id: t,
      },
    );

Future<void> show(WidgetTester tester, SceneStore store,
    {required bool gm, PlayerId self = const PlayerId('gm')}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TableController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(cvApp(
    title: 'test',
    home: Center(
      child: InitiativeBar(
        store: store,
        controller: controller,
        send: (c) => store.execute(gm ? const Gm() : Player(self), c),
        gm: gm,
        self: self,
      ),
    ),
  ));
}

void main() {
  test('everyone on the map rolls, highest first', () {
    final order = InitiativeBar.roll(table(), Random(1));
    expect(order.entries.map((e) => e.token.value).toSet(), {'a', 'g'});
    expect(order.entries.first.value, greaterThanOrEqualTo(order.entries.last.value));
    expect(order.current, order.entries.first.token);
    expect(order.entries.every((e) => e.value >= 1 && e.value <= 20), isTrue);
  });

  testWidgets('the GM rolls, steps through turns, and ends the fight',
      (tester) async {
    final store = SceneStore(table());
    await show(tester, store, gm: true);
    await tester.tap(find.text('Roll initiative'));
    await tester.pump();
    final first = store.scene.initiative!.current;
    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('Aria'), findsOneWidget);
    expect(find.text('Goblin'), findsOneWidget);

    await tester.tap(find.text('Next turn'));
    await tester.pump();
    expect(store.scene.initiative!.current, isNot(first));
    await tester.tap(find.text('Next turn'));
    await tester.pump();
    expect(find.text('Round 2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('End the fight'));
    await tester.pump();
    expect(store.scene.initiative, isNull);
    expect(find.text('Roll initiative'), findsOneWidget);
  });

  testWidgets("a player ends only their own token's turn", (tester) async {
    final order = Initiative(round: 1, current: const TokenId('g'), entries: [
      (token: const TokenId('g'), value: 15),
      (token: const TokenId('a'), value: 9),
    ]);
    final store = SceneStore(table().applyPatches([Upsert(order)]));
    await show(tester, store, gm: false, self: alice);
    expect(find.text('Roll initiative'), findsNothing);
    expect(find.text('End my turn'), findsNothing);

    store.apply([Upsert(order.next())]);
    await tester.pump();
    await tester.tap(find.text('End my turn'));
    await tester.pump();
    expect(store.scene.initiative!.round, 2);
    expect(find.text('End my turn'), findsNothing);
  });

  testWidgets('a forms pack starts everyone Steady, and the GM changes forms',
      (tester) async {
    final solaris = jsonDecode(File('../packs/solaris-arcanum.json').readAsStringSync())
        as Json;
    final scene = table();
    final store = SceneStore(Scene(
      settings: scene.settings.copyWith(pack: 'solaris-arcanum'),
      tokens: scene.tokens,
      packFile: ScenePack(solaris),
    ));
    await show(tester, store, gm: true);
    expect(find.text('Roll initiative'), findsNothing);
    await tester.tap(find.text('Start the fight'));
    await tester.pump();
    expect(find.text('Steady'), findsOneWidget); // Aria, a player's token.
    expect(find.text('Steady (NPC)'), findsOneWidget); // The Goblin.
    expect(find.bySemanticsLabel('Roll again'), findsNothing);
    expect(store.scene.initiative!.entries.first.token, const TokenId('a'));

    // Poise is after Steady (NPC): the Goblin goes first now.
    await tester.tap(find.text('Steady'));
    await tester.pump();
    expect(find.text('Poise'), findsOneWidget);
    expect(store.scene.initiative!.entries.map((e) => e.token.value), ['g', 'a']);
  });
}
