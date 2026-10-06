import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:chimera_vtt/assets.dart';
import 'package:chimera_vtt/home.dart';
import 'package:chimera_vtt/members.dart';
import 'package:chimera_vtt/room.dart';
import 'package:chimera_vtt/table/chrome.dart';
import 'package:chimera_vtt/table/table_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthClientOptions, SupabaseClient;

void main() {
  test('cells are named column letter, row number', () {
    const grid = Grid(cellSize: 100);
    expect(cellName((x: 50, y: 50), grid), 'A1');
    expect(cellName((x: 250, y: 350), grid), 'C4');
    expect(cellName((x: 2650, y: 50), grid), 'AA1');
  });

  test('copies are numbered after the lowest free number', () {
    expect(nextName('Goblin 1', ['Goblin 1']), 'Goblin 2');
    expect(nextName('Goblin 1', ['Goblin 1', 'Goblin 2', 'Goblin 4']), 'Goblin 3');
    expect(nextName('Orc', ['Orc']), 'Orc');
    expect(nextName('', []), '');
  });

  testWidgets('the lobby renders and asks for 6 characters', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SavedRoom? entered;
    // Nobody signed in, and nothing to reach: the GM card asks to sign in.
    final client = SupabaseClient('http://127.0.0.1:9', 'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    await tester.pumpWidget(cvApp(
        title: 'test',
        home: Lobby(
            client: client,
            assets: AssetStore(client),
            onEnter: (room) => entered = room)));
    await tester.pump();
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.text('Create room'), findsNothing);

    await tester.enterText(find.widgetWithText(CvTextInput, 'Room code'), 'k7q');
    await tester.pump();
    await tester.tap(find.text('JOIN'));
    await tester.pump();
    expect(find.text('Room codes have 6 characters.'), findsOneWidget);
    expect(entered, isNull);
  });

  testWidgets("the GM's home switches between campaigns, library and joining",
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final client = SupabaseClient('http://127.0.0.1:9', 'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    await tester.pumpWidget(cvApp(
        title: 'test',
        home: GmHome(
            client: client,
            assets: AssetStore(client),
            email: 'gm@example.com',
            onEnter: (_) {})));
    expect(find.text('Your campaigns'), findsOneWidget);
    expect(find.textContaining('Good '), findsOneWidget);

    await tester.tap(find.text('Library').first);
    await tester.pump();
    expect(find.text('UPLOAD'), findsOneWidget);
    expect(find.text('Search maps'), findsOneWidget);
    await tester.tap(find.text('Tokens 0'));
    await tester.pump();
    expect(find.text('Search tokens'), findsOneWidget);

    await tester.tap(find.text('JOIN WITH CODE'));
    await tester.pump();
    expect(find.widgetWithText(CvTextInput, 'Room code'), findsOneWidget);
    // Let the unreachable requests fail before the test ends.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  });

  testWidgets('the GM chrome follows the controller', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TableShortcuts(
        controller: controller,
        gm: true,
        child: Stack(children: [
          Positioned(
              left: 16, bottom: 16, child: ToolDock(controller: controller, gm: true)),
          Positioned(
              left: 100,
              top: 100,
              child: FogOptions(
                  controller: controller, grid: const Grid(cellSize: 128))),
          Positioned(
              right: 16,
              bottom: 16,
              child: ZoomCluster(controller: controller, snap: true)),
        ]),
      ),
    ));
    expect(find.text('FOG'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Fog'));
    await tester.pumpAndSettle();
    expect(controller.tool, Tool.fogBrush);
    expect(find.text('FOG'), findsOneWidget);
    await tester.tap(find.text('Box'));
    await tester.pumpAndSettle();
    expect(controller.tool, Tool.fogRect);
    expect(find.text('FOG'), findsOneWidget); // Still out: the same panel.

    await tester.tap(find.text('Reveal'));
    expect(controller.fogMode, FogMode.reveal);

    await tester.tap(find.bySemanticsLabel(RegExp('^Snap to grid')));
    expect(controller.snap, isFalse);
  });

  testWidgets('the dock moves left of the zoom on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Stack(children: [
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16,
          child: BottomRow(
            dock: ToolDock(controller: controller, gm: true),
            side: ZoomCluster(controller: controller, snap: true),
          ),
        ),
      ]),
    ));
    final dock = tester.getRect(find.byType(ToolDock));
    final zoom = tester.getRect(find.byType(ZoomCluster));
    expect(dock.right, lessThanOrEqualTo(zoom.left));
    expect(dock.left, greaterThanOrEqualTo(16));
  });

  testWidgets('with no room beside it, the zoom sits on top of the dock',
      (tester) async {
    tester.view.physicalSize = const Size(440, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: Stack(children: [
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16,
          child: BottomRow(
            dock: ToolDock(controller: controller, gm: true),
            side: ZoomCluster(controller: controller, snap: true),
          ),
        ),
      ]),
    ));
    final dock = tester.getRect(find.byType(ToolDock));
    final zoom = tester.getRect(find.byType(ZoomCluster));
    expect(dock.bottom, 600 - 16);
    expect(zoom.bottom, lessThanOrEqualTo(dock.top));
  });

  testWidgets('the grid panel sets the cell size, and typing is not shortcuts',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = TableController();
    addTearDown(controller.dispose);
    final sizes = <double>[];
    final visible = <bool>[];
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TableShortcuts(
        controller: controller,
        gm: true,
        child: Stack(children: [
          Positioned(left: 16, top: 100, child: GmRail(controller: controller)),
          Positioned(
              left: 100,
              top: 100,
              child: GridOptions(
                  controller: controller,
                  grid: const Grid(cellSize: 128),
                  visible: true,
                  onCellSize: sizes.add,
                  onVisible: visible.add)),
        ]),
      ),
    ));
    expect(find.text('GRID'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Grid'));
    await tester.pumpAndSettle();
    expect(find.text('GRID'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '8');
    await tester.pump();
    expect(find.text('From 16 to 1024 px.'), findsOneWidget);
    expect(sizes, isEmpty);

    await tester.enterText(find.byType(EditableText), '70');
    await tester.pump();
    expect(sizes, [70]);

    // B would pick the fog brush; in the field it's just a key.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(controller.tool, Tool.move);

    await tester.tap(find.text('Show grid lines'));
    expect(visible, [false]);
  });

  testWidgets('the token card names the token as it is typed', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = TokenId('t');
    final host = HostSession(
      LoopbackHub().connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 1000, height: 1000, grid: Grid(cellSize: 100)),
        tokens: {id: const Token(id: id, position: (x: 50, y: 50), size: 100)},
      )),
    );
    final controller = TableController();
    addTearDown(controller.dispose);
    controller.selected.value = id;
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: TableShortcuts(
        controller: controller,
        gm: true,
        child: TokenCardLayer(
          store: host.store,
          session: host,
          controller: controller,
          send: host.execute,
          onRemove: (_) {},
          onDuplicate: (_) {},
        ),
      ),
    ));
    await tester.enterText(find.byType(EditableText).first, 'Goblin 1');
    await tester.pump();
    expect(host.store.scene.tokens[id]!.name, 'Goblin 1');
    expect(find.text('Goblin 1'), findsWidgets); // The card's title too.

    await tester.tap(find.text('2×2'));
    await tester.pump();
    expect(host.store.scene.tokens[id]!.size, 200);

    // A member who isn't connected can still be given the token.
    const aria = PlayerId('aria');
    members.value = {aria: (name: 'Aria', color: 3)};
    addTearDown(() => members.value = {});
    await tester.pump();
    await tester.tap(find.text('No owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aria').last);
    await tester.pumpAndSettle();
    expect(host.store.scene.tokens[id]!.owner, aria);

    await tester.enterText(find.byType(EditableText).last, 'Darkness 2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(host.store.scene.tokens[id]!.conditions, {'Darkness': 2});
    expect(find.text('Darkness 2'), findsOneWidget); // The chip.
    await tester.tap(find.bySemanticsLabel('Remove Darkness'));
    await tester.pump();
    expect(host.store.scene.tokens[id]!.conditions, isEmpty);
  });

  testWidgets("a player's card offers only conditions", (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const id = TokenId('t');
    const me = PlayerId('me');
    final host = HostSession(
      LoopbackHub().connect(),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 1000, height: 1000, grid: Grid(cellSize: 100)),
        tokens: {
          id: const Token(
              id: id, position: (x: 50, y: 50), size: 100, owner: me),
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
        // What the player's session checks before asking the GM.
        send: (c) => host.store.execute(const Player(me), c),
        gm: false,
      ),
    ));
    expect(find.text('Owner'), findsNothing);
    expect(find.text('REMOVE'), findsNothing);
    expect(find.byType(EditableText), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Prone');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(host.store.scene.tokens[id]!.conditions, {'Prone': null});
  });

  testWidgets('rulers are shared, at most every 100 ms, and go on release',
      (tester) async {
    final hub = LoopbackHub();
    final host = HostSession(hub.connect(), const PlayerId('gm'),
        SceneStore(Scene(settings: const SceneSettings(width: 100, height: 100,
            grid: Grid(cellSize: 10)))));
    final player = ClientSession(hub.connect(), const PlayerId('p'));
    final gmView = TableController();
    final playerView = TableController();
    addTearDown(gmView.dispose);
    addTearDown(playerView.dispose);
    final stops = [shareRulers(host, gmView), shareRulers(player, playerView)];
    addTearDown(() {
      for (final stop in stops) {
        stop();
      }
    });

    const a = (x: 5.0, y: 5.0), b = (x: 35.0, y: 5.0), c = (x: 55.0, y: 5.0);
    playerView.ruler.value = (a, b);
    await tester.pump();
    expect(gmView.otherRulers.value.single.$1, (a, b));
    expect(playerView.otherRulers.value, isEmpty); // Not your own twice.

    playerView.ruler.value = (a, c); // Too soon: held back.
    await tester.pump();
    expect(gmView.otherRulers.value.single.$1, (a, b));
    await tester.pump(const Duration(milliseconds: 150));
    expect(gmView.otherRulers.value.single.$1, (a, c));

    playerView.ruler.value = null;
    await tester.pump();
    expect(gmView.otherRulers.value, isEmpty);
  });
}
