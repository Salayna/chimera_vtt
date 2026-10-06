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
  test("the GM's tokens roll; players' wait for their owners to", () {
    final order = InitiativeBar.roll(table(), Random(1));
    expect(order.entries.map((e) => e.token.value), ['g', 'a']);
    expect(order.entries.first.value, inInclusiveRange(1, 20));
    expect(order.entries.last.value, isNull);
    expect(order.current, const TokenId('g'));
    expect(order.formula, '1d20');
    expect(order.places, isEmpty);
  });

  testWidgets('a waiting token shows Roll to its owner, Waiting to others',
      (tester) async {
    final store = SceneStore(table().applyPatches([Upsert(InitiativeBar.roll(table(), Random(1)))]));
    await show(tester, store, gm: false, self: alice);
    expect(find.text('Roll'), findsOneWidget);
    await show(tester, store, gm: false, self: const PlayerId('bob'));
    expect(find.text('Waiting'), findsOneWidget);
  });

  testWidgets('the GM rolls, steps through turns, and ends the fight',
      (tester) async {
    final store = SceneStore(table());
    await show(tester, store, gm: true);
    await tester.tap(find.text('ROLL INITIATIVE'));
    await tester.pump();
    final first = store.scene.initiative!.current;
    expect(find.text('ROUND 1'), findsOneWidget);
    expect(find.text('Aria'), findsOneWidget);
    expect(find.text('Goblin'), findsOneWidget);

    await tester.tap(find.text('NEXT TURN'));
    await tester.pump();
    expect(store.scene.initiative!.current, isNot(first));
    await tester.tap(find.text('NEXT TURN'));
    await tester.pump();
    expect(find.text('ROUND 2'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('End the fight'));
    await tester.pump();
    expect(store.scene.initiative, isNull);
    expect(find.text('ROLL INITIATIVE'), findsOneWidget);
  });

  testWidgets("a player ends only their own token's turn", (tester) async {
    final order = Initiative(round: 1, current: const TokenId('g'), entries: [
      (token: const TokenId('g'), value: 15),
      (token: const TokenId('a'), value: 9),
    ]);
    final store = SceneStore(table().applyPatches([Upsert(order)]));
    await show(tester, store, gm: false, self: alice);
    expect(find.text('ROLL INITIATIVE'), findsNothing);
    expect(find.text('END MY TURN'), findsNothing);

    store.apply([Upsert(order.next())]);
    await tester.pump();
    await tester.tap(find.text('END MY TURN'));
    await tester.pump();
    expect(store.scene.initiative!.round, 2);
    expect(find.text('END MY TURN'), findsNothing);
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
    expect(find.text('ROLL INITIATIVE'), findsNothing);
    await tester.tap(find.text('START THE FIGHT'));
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

    // A player changes their own token's form, mid-turn too, not the GM's.
    await show(tester, store, gm: false, self: alice);
    await tester.tap(find.text('Poise'));
    await tester.pump();
    expect(find.text('Poise'), findsNothing);
    final npc = store.scene.initiative!;
    await tester.tap(find.text('Steady (NPC)'));
    await tester.pump();
    expect(store.scene.initiative!.toJson(), npc.toJson());
  });
}
