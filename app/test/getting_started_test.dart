import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/getting_started.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = TokenId('t');
  final empty = Scene(
      settings: const SceneSettings(
          width: 1024, height: 1024, grid: Grid(cellSize: 128)));

  Future<(SceneStore, List<List<String>>)> pump(WidgetTester tester,
      {List<String> remembered = const []}) async {
    final store = SceneStore(empty);
    final saved = <List<String>>[];
    var maps = 0;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Align(
        alignment: Alignment.bottomLeft,
        child: GettingStarted(
          store: store,
          code: 'ABC234',
          load: () async => remembered,
          save: saved.add,
          onMap: () => maps++,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (store, saved);
  }

  testWidgets('steps tick themselves, and stay ticked', (tester) async {
    final (store, saved) = await pump(tester);
    expect(find.text('GETTING STARTED · 0/4'), findsOneWidget);
    expect(find.text('Send them the room code ABC234, at the foot of the party panel.'), findsOneWidget);

    store.execute(const Gm(),
        const PlaceToken(Token(id: id, position: (x: 64, y: 64), size: 128)));
    await tester.pumpAndSettle();
    expect(find.text('GETTING STARTED · 1/4'), findsOneWidget);
    expect(saved.last, contains('token'));

    // Removing the token doesn't undo the step.
    store.execute(const Gm(), const RemoveToken(id));
    await tester.pumpAndSettle();
    expect(find.text('GETTING STARTED · 1/4'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GETTING STARTED'), findsNothing);
    expect(saved.last, containsAll(['token', 'closed']));
  });

  testWidgets('closed, or all done, it stays away', (tester) async {
    await pump(tester, remembered: ['closed']);
    expect(find.textContaining('GETTING STARTED'), findsNothing);
    await pump(tester, remembered: startSteps);
    expect(find.textContaining('GETTING STARTED'), findsNothing);
  });
}
