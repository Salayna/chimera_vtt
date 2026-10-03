import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = TokenId('t');

  /// An 800x600 view of a 1024 px map with one token, as [gm] or a player.
  Future<(SceneStore, TableController, List<TokenId>)> pump(
      WidgetTester tester,
      {required bool gm}) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SceneStore(Scene(
      settings: const SceneSettings(
          width: 1024, height: 1024, grid: Grid(cellSize: 128)),
      tokens: {
        id: const Token(id: id, position: (x: 192, y: 192), size: 128),
      },
    ));
    final controller = TableController();
    addTearDown(controller.dispose);
    final removed = <TokenId>[];
    Outcome send(Command c) => store.execute(const Gm(), c);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Stack(children: [
        Positioned.fill(
          child: TableView(
            store: store,
            controller: controller,
            gm: gm,
            self: const PlayerId('gm'),
            send: send,
          ),
        ),
        Positioned.fill(
          child: TokenMenuLayer(
            store: store,
            controller: controller,
            send: send,
            gm: gm,
            onRemove: gm ? removed.add : null,
            onDuplicate: gm ? (_) {} : null,
          ),
        ),
      ]),
    ));
    return (store, controller, removed);
  }

  const scale = 600 / 1024;
  const tokenOnScreen = Offset(100 + 192 * scale, 192 * scale);

  Future<void> rightClick(WidgetTester tester, Offset at) async {
    await tester.tapAt(at, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('right-clicking a token opens its menu, with its keys',
      (tester) async {
    final (store, _, removed) = await pump(tester, gm: true);
    await rightClick(tester, tokenOnScreen);
    expect(find.text('Hide from players'), findsOneWidget);
    expect(find.text('⌫'), findsOneWidget);

    await tester.tap(find.text('Hide from players'));
    await tester.pumpAndSettle();
    expect(store.scene.tokens[id]!.hidden, isTrue);
    expect(find.byType(CvMenu<Object>), findsNothing);
    expect(find.text('Show to players'), findsNothing);

    await rightClick(tester, tokenOnScreen);
    await tester.tap(find.text('Remove'));
    expect(removed, [id]);
  });

  testWidgets('the map has no menu, nor a token for a player with nothing '
      'to do on it', (tester) async {
    await pump(tester, gm: true);
    await rightClick(tester, const Offset(700, 500));
    expect(find.text('Duplicate'), findsNothing);

    await pump(tester, gm: false);
    await rightClick(tester, tokenOnScreen);
    expect(find.text('Duplicate'), findsNothing);
  });
}
