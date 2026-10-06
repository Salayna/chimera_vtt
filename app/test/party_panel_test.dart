import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:chimera_vtt/members.dart';
import 'package:chimera_vtt/table/party_panel.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const sam = PlayerId('sam');
const kai = PlayerId('kai');

void main() {
  Future<TableController> show(WidgetTester tester, {required bool gm}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    members.value = {sam: (name: 'Sam', color: 0), kai: (name: 'Kai', color: 1)};
    addTearDown(() => members.value = {});
    final store = SceneStore(Scene(
      settings: const SceneSettings(width: 1000, height: 1000, grid: Grid(cellSize: 100)),
      tokens: {
        for (final t in const [
          Token(id: TokenId('a'), position: (x: 50, y: 50), size: 100, name: 'Aria', owner: sam),
          Token(id: TokenId('g'), position: (x: 250, y: 350), size: 100, name: 'Goblin'),
          Token(id: TokenId('w'), position: (x: 450, y: 50), size: 100, name: 'Wight', hidden: true),
        ])
          t.id: t,
      },
    ));
    final controller = TableController();
    addTearDown(controller.dispose);
    final session = ClientSession(LoopbackHub().connect(), sam);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Align(
        alignment: Alignment.topRight,
        child: PartyPanel(
          session: session,
          store: store,
          controller: controller,
          send: (c) => store.execute(gm ? const Gm() : Player(sam), c),
          gm: gm,
          self: sam,
          code: 'ABC234',
          onLeave: () {},
        ),
      ),
    ));
    return controller;
  }

  testWidgets('players see the party and the turn order; nobody here is away',
      (tester) async {
    await show(tester, gm: false);
    expect(find.text('NPCS'), findsNothing);
    expect(find.text('GM'), findsWidgets);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Away'), findsNWidgets(2)); // No presence yet.
    await tester.tap(find.text('INITIATIVE'));
    await tester.pump();
    expect(find.text('No fight yet: the GM starts one.'), findsOneWidget);
  });

  testWidgets("the GM's tokens are found from the NPCs tab", (tester) async {
    final controller = await show(tester, gm: true);
    await tester.tap(find.text('NPCS'));
    await tester.pump();
    expect(find.text('Aria'), findsNothing);
    expect(find.text('C4'), findsOneWidget);
    expect(find.text('E1 · hidden'), findsOneWidget);
    await tester.tap(find.text('Goblin'));
    expect(controller.selected.value, const TokenId('g'));
  });
}
