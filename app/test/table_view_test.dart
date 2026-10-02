import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/layers.dart';
import 'package:chimera_vtt/table/rules.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const id = TokenId('t');

  /// An 800x600 view of a 1024 px map, fitted: scale 600/1024, 100 px
  /// margin left and right. The token starts in the middle of cell (1, 1).
  Future<SceneStore> pump(WidgetTester tester, {required bool snap}) async {
    final store = SceneStore(Scene(
      settings: const SceneSettings(
          width: 1024, height: 1024, grid: Grid(cellSize: 128)),
      tokens: {
        id: const Token(id: id, position: (x: 192, y: 192), size: 128),
      },
    ));
    final controller = TableController()..snap = snap;
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableView(
        store: store,
        controller: controller,
        gm: true,
        self: const PlayerId('gm'),
        send: (command) => store.execute(const Gm(), command),
      ),
    ));
    return store;
  }

  const scale = 600 / 1024;
  const tokenOnScreen = Offset(100 + 192 * scale, 192 * scale);

  testWidgets('a dropped token snaps to the nearest cell', (tester) async {
    final store = await pump(tester, snap: true);
    // 100 px on screen is about 171 map px: from x=192 to about 363,
    // which is nearest the cell centred on x=320.
    await tester.dragFrom(tokenOnScreen, const Offset(100, 0));
    await tester.pump();
    expect(store.scene.tokens[id]!.position, (x: 320.0, y: 192.0));
    // Whoever drags sees their token land at once; only others see it glide.
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('with snapping off, it stays where it was dropped',
      (tester) async {
    final store = await pump(tester, snap: false);
    await tester.dragFrom(tokenOnScreen, const Offset(100, 0));
    await tester.pump();
    final position = store.scene.tokens[id]!.position;
    expect(position.x, closeTo(192 + 100 / scale, 1));
    expect(position.y, closeTo(192, 1));
  });

  test('the ruler speaks the pack: cells, feet, and blocked sight', () {
    final settings = const SceneSettings(width: 1000, height: 1000, grid: Grid(cellSize: 100));
    final generic = Scene(settings: settings);
    expect(rulerLabel(generic, (x: 50, y: 50), (x: 350, y: 250)), '3 cells');
    expect(rulerLabel(generic, (x: 50, y: 50), (x: 150, y: 50)), '1 cell');
    final dnd = Scene(
      settings: settings.copyWith(pack: 'dnd5e'),
      regions: {
        const RegionId('smoke'): const Region(
            id: RegionId('smoke'),
            from: (x: 200, y: 0),
            to: (x: 300, y: 300),
            tags: {'Heavily Obscured': null}),
      },
    );
    expect(rulerLabel(dnd, (x: 50, y: 50), (x: 50, y: 250)), '10 ft');
    expect(rulerLabel(dnd, (x: 50, y: 50), (x: 450, y: 50)), '20 ft · no sight');
  });

  test('the ruler counts cells, a diagonal as one', () {
    const grid = Grid(cellSize: 100);
    expect(rulerCells(grid, (x: 50, y: 50), (x: 50, y: 50)), 0);
    expect(rulerCells(grid, (x: 50, y: 50), (x: 350, y: 50)), 3);
    expect(rulerCells(grid, (x: 50, y: 50), (x: 350, y: 250)), 3);
  });

  testWidgets("a player's ruler snaps to cell centres and goes on release",
      (tester) async {
    final store = SceneStore(Scene(
        settings: const SceneSettings(
            width: 1024, height: 1024, grid: Grid(cellSize: 128))));
    final controller = TableController()..tool = Tool.ruler;
    addTearDown(controller.dispose);
    final pinged = <Point>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableView(
        store: store,
        controller: controller,
        gm: false,
        self: const PlayerId('p'),
        send: (command) => store.execute(const Player(PlayerId('p')), command),
        onPing: pinged.add,
      ),
    ));
    await tester.pump();
    // Scale 600/1024 with a 100 px margin: cell (1, 1) is around (212, 112).
    final gesture = await tester.startGesture(const Offset(205, 105));
    await gesture.moveTo(const Offset(100 + 600 * 4.4 / 8, 600 * 1.3 / 8));
    await tester.pump();
    final (from, to) = controller.ruler.value!;
    expect(from, (x: 192.0, y: 192.0));
    expect(to, (x: 576.0, y: 192.0));
    expect(rulerCells(store.scene.settings.grid, from, to), 3);
    await gesture.up();
    await tester.pump();
    expect(controller.ruler.value, isNull);
    expect(store.scene.tokens, isEmpty); // Measuring changes nothing.

    controller.tool = Tool.ping;
    await tester.tapAt(const Offset(400, 300));
    expect(pinged, hasLength(1));
  });

  testWidgets('a double-click pings where it lands; a single one does not',
      (tester) async {
    final store = SceneStore(Scene(
        settings: const SceneSettings(
            width: 1024, height: 1024, grid: Grid(cellSize: 128))));
    final controller = TableController();
    addTearDown(controller.dispose);
    final pinged = <Point>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableView(
        store: store,
        controller: controller,
        gm: false,
        self: const PlayerId('p'),
        send: (command) => store.execute(const Gm(), command),
        onPing: pinged.add,
      ),
    ));
    await tester.pump();
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(pinged, isEmpty);
    await tester.tapAt(const Offset(400, 300));
    await tester.tapAt(const Offset(400, 300));
    expect(pinged, hasLength(1));
    // The middle of the fitted view is the middle of the map.
    expect(pinged.single.x, closeTo(512, 1));
    expect(pinged.single.y, closeTo(512, 1));
  });

  testWidgets('pressing the map gives the table back its shortcuts',
      (tester) async {
    final store = SceneStore(Scene(
        settings: const SceneSettings(
            width: 1024, height: 1024, grid: Grid(cellSize: 128))));
    final controller = TableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableShortcuts(
        controller: controller,
        gm: true,
        child: TableView(
          store: store,
          controller: controller,
          gm: true,
          self: const PlayerId('gm'),
          send: (command) => store.execute(const Gm(), command),
        ),
      ),
    ));
    // What a closed card's focused field leaves on the web: no focus at all.
    FocusManager.instance.primaryFocus?.unfocus(
        disposition: UnfocusDisposition.previouslyFocusedChild);
    FocusManager.instance.rootScope.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(controller.gridOptions, isFalse);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    expect(controller.gridOptions, isTrue);
  });

  testWidgets('a drag sends one move: the drop', (tester) async {
    final store = SceneStore(Scene(
      settings: const SceneSettings(
          width: 1024, height: 1024, grid: Grid(cellSize: 128)),
      tokens: {id: const Token(id: id, position: (x: 192, y: 192), size: 128)},
    ));
    final controller = TableController();
    addTearDown(controller.dispose);
    final sent = <Command>[];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableView(
        store: store,
        controller: controller,
        gm: true,
        self: const PlayerId('gm'),
        send: (command) {
          sent.add(command);
          return store.execute(const Gm(), command);
        },
      ),
    ));
    await tester.pump();
    final gesture = await tester.startGesture(tokenOnScreen);
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(5, 0));
      // Real time, longer than the old 66 ms send throttle.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 70)));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));
    expect(sent.single, isA<MoveToken>());
  });

  testWidgets('the region tool marks whole cells, and a click picks one',
      (tester) async {
    final store = SceneStore(Scene(
      settings: const SceneSettings(
          width: 1024, height: 1024, grid: Grid(cellSize: 128)),
    ));
    final controller = TableController()..tool = Tool.region;
    addTearDown(controller.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TableView(
        store: store,
        controller: controller,
        gm: true,
        self: const PlayerId('gm'),
        send: (command) => store.execute(const Gm(), command),
      ),
    ));
    await tester.pumpAndSettle();
    final gesture =
        await tester.startGesture(controller.toScreen((x: 140, y: 140)));
    await gesture.moveTo(controller.toScreen((x: 220, y: 180)));
    await gesture.moveTo(controller.toScreen((x: 300, y: 200)));
    await gesture.up();
    await tester.pump();
    final region = store.scene.regions.values.single;
    expect((region.from, region.to), ((x: 128.0, y: 128.0), (x: 384.0, y: 256.0)));
    expect(controller.selectedRegion.value, region.id);

    controller.selectedRegion.value = null;
    await tester.tapAt(controller.toScreen((x: 200, y: 200)));
    await tester.pump();
    expect(controller.selectedRegion.value, region.id);
    await tester.tapAt(controller.toScreen((x: 600, y: 600)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.selectedRegion.value, isNull);
  });

  test('a glide eases from where the token was to where it is', () {
    final glides = TokenGlides();
    addTearDown(glides.dispose);
    glides.start(id, Offset.zero);
    const to = Offset(100, 0);
    glides.tick(TokenGlides.duration ~/ 2);
    final mid = glides.at(id, to).dx;
    expect(mid, greaterThan(50)); // Ease-out: past halfway at half time.
    expect(mid, lessThan(100));
    glides.tick(TokenGlides.duration);
    expect(glides.active, isFalse);
    expect(glides.at(id, to), to);
  });
}
