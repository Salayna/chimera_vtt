import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:chimera_vtt/characters.dart';
import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/room_characters.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const me = PlayerId('me');
const tokenId = TokenId('t');
final ayla = Character(
    id: const CharacterId('ayla'),
    owner: me,
    system: 'dnd5e',
    name: 'Ayla',
    values: const {'maxHP': 12, 'HP': 10});

/// Records saves instead of writing rows.
class _Saves implements SavedCharacters {
  final saved = <Character>[];

  @override
  Future<void> save(Character c) async => saved.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets("a token plays its owner's character: its trackers, theirs to change",
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final host = HostSession(
      LoopbackHub().connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 1000, height: 1000, grid: Grid(cellSize: 100), pack: 'dnd5e'),
        tokens: {
          tokenId: const Token(id: tokenId, position: (x: 50, y: 50), size: 100, owner: me),
        },
        characters: {ayla.id: ayla},
      )),
    );
    final controller = TableController();
    addTearDown(controller.dispose);
    controller.selected.value = tokenId;
    CharacterId? opened;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TokenCardLayer(
        store: host.store,
        session: host,
        controller: controller,
        send: (c) => host.store.execute(const Player(me), c),
        gm: false,
        self: me,
        onOpenSheet: (id) => opened = id,
      ),
    ));
    // The owner links their token to their character.
    await tester.tap(find.text('No character'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayla').last);
    await tester.pumpAndSettle();
    expect(host.store.scene.tokens[tokenId]!.character, ayla.id);

    expect(find.text('Hit points / 12'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is CvToolButton && w.label == 'Hit points / 12 +1'));
    await tester.pump();
    expect(host.store.scene.characters[ayla.id]!.values['HP'], 11);
    await tester.tap(find.text('SHEET'));
    expect(opened, ayla.id);
  });

  test('owners save their characters when they change, not when they arrive',
      () async {
    final store = SceneStore(Scene(
        settings: const SceneSettings(
            width: 100, height: 100, grid: Grid(cellSize: 10), pack: 'dnd5e')));
    final saves = _Saves();
    final stop = saveOwnCharacters(store, me, saves);
    final theirs = Character(
        id: const CharacterId('b'), owner: const PlayerId('bob'), system: 'dnd5e', name: 'B');
    store.apply([Upsert(ayla), Upsert(theirs)]);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(saves.saved, isEmpty);
    store.apply([Upsert(ayla.copyWith(values: {'HP': 3})), Upsert(theirs.copyWith(name: 'C'))]);
    await Future<void>.delayed(Duration.zero);
    // A snapshot rebuilds entities with the same content: nothing to save.
    store.replace(Scene.fromJson(store.scene.toJson()));
    stop(); // Flushes what's waiting.
    await Future<void>.delayed(Duration.zero);
    expect([for (final c in saves.saved) c.values['HP']], [3]);
  });
}
