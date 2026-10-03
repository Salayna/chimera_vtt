import 'dart:convert';
import 'dart:math';

import 'package:chimera_core/chimera_core.dart';
import 'package:test/test.dart';

const gm = Gm();
const alice = Player(PlayerId('alice'));
const bob = Player(PlayerId('bob'));

final settings = SceneSettings(
  map: const AssetId('abc123'),
  width: 4096,
  height: 4096,
  grid: const Grid(cellSize: 64),
);

Token token(String id, {PlayerId? owner, bool hidden = false}) => Token(
      id: TokenId(id),
      position: (x: 10, y: 20),
      size: 64,
      owner: owner,
      hidden: hidden,
    );

final r = Region(
    id: const RegionId('r'),
    from: (x: 0, y: 0),
    to: (x: 64, y: 64),
    tags: const {'Heavy Cover': null});

Scene sceneWith(List<Token> tokens) =>
    Scene(settings: settings, tokens: {for (final t in tokens) t.id: t});

void main() {
  test('a scene survives a JSON round trip', () {
    final scene = sceneWith([token('a', owner: alice.id), token('b', hidden: true)])
        .applyPatches([
      Upsert(FogOp(
        id: const FogOpId('f1'),
        order: 1,
        mode: FogMode.cover,
        shape: const FogRect((x: 0, y: 0), (x: 100, y: 100)),
      )),
      Upsert(FogOp(
        id: const FogOpId('f2'),
        order: 2,
        mode: FogMode.reveal,
        shape: const FogBrush([(x: 1, y: 2), (x: 3.5, y: 4)], 8),
      )),
    ]);
    final decoded = jsonDecode(jsonEncode(scene.toJson())) as Json;
    expect(Scene.fromJson(decoded).toJson(), equals(scene.toJson()));
  });

  test('settings saved before gridVisible show the grid', () {
    final json = const SceneSettings(
            width: 100, height: 100, grid: Grid(cellSize: 10), gridVisible: false)
        .toJson()
      ..remove('gridVisible');
    expect((Entity.fromJson(json) as SceneSettings).gridVisible, isTrue);
  });

  test('patches leave the tables they do not touch untouched', () {
    final scene = sceneWith([token('a')]);
    final moved = scene.applyPatches([Upsert(token('a'))]);
    expect(identical(moved.fogOps, scene.fogOps), isTrue);
    expect(identical(moved.tokens, scene.tokens), isFalse);
    expect(() => (moved.tokens as Map)[const TokenId('x')] = token('x'),
        throwsUnsupportedError);
  });

  test('tokens snap to the grid by their edges, small ones to cell centres', () {
    const grid = Grid(cellSize: 100, offset: (x: 10, y: 0));
    expect(grid.snap((x: 160, y: 40), 100), (x: 160.0, y: 50.0)); // 1 cell
    expect(grid.snap((x: 105, y: 40), 100), (x: 60.0, y: 50.0)); // left half
    expect(grid.snap((x: 212, y: 190), 200), (x: 210.0, y: 200.0)); // 2x2
    expect(grid.snap((x: 290, y: 180), 300), (x: 260.0, y: 150.0)); // 3x3
    expect(grid.snap((x: 105, y: 199), 50), (x: 60.0, y: 150.0)); // small
    expect(grid.snap((x: -40, y: -60), 100), (x: -40.0, y: -50.0)); // off map
  });

  test('a grid through a point has lines crossing there', () {
    final grid = Grid.through((x: 215, y: 148), 70);
    expect(grid.offset, (x: 5.0, y: 8.0)); // 215 % 70, 148 % 70
    expect(grid.cellSize, 70);
  });

  test('a free spot is the nearest cell no token overlaps', () {
    const grid = Grid(cellSize: 100);
    Token at(double x, double y, [double size = 100]) =>
        Token(id: TokenId('$x,$y'), position: (x: x, y: y), size: size);
    const near = (x: 150.0, y: 150.0);
    expect(grid.freeSpot(near, 100, []), near);
    // Taken: the next ring, starting top-left.
    expect(grid.freeSpot(near, 100, [at(150, 150)]), (x: 50.0, y: 50.0));
    // A 2×2 token around it blocks the whole first ring.
    final big = at(200, 200, 200);
    final spot = grid.freeSpot(near, 100, [big]);
    expect(((spot.x - 200).abs() >= 150 || (spot.y - 200).abs() >= 150), isTrue);
  });

  group('reduce', () {
    final scene = sceneWith([
      token('mine', owner: alice.id),
      token('theirs', owner: bob.id),
      token('secret', owner: alice.id, hidden: true),
    ]);

    Refusal? refusal(Actor actor, Command command) =>
        switch (reduce(scene, actor, command)) {
          Refused(:final reason) => reason,
          Accepted() => null,
        };

    test('players move only tokens they own and can see', () {
      expect(refusal(alice, const MoveToken(TokenId('mine'), (x: 5, y: 5))), isNull);
      expect(refusal(alice, const MoveToken(TokenId('theirs'), (x: 5, y: 5))),
          Refusal.notOwner);
      expect(refusal(alice, const MoveToken(TokenId('secret'), (x: 5, y: 5))),
          Refusal.notFound);
      expect(refusal(alice, const MoveToken(TokenId('mine'), (x: double.nan, y: 0))),
          Refusal.invalid);
      expect(refusal(gm, const MoveToken(TokenId('theirs'), (x: 5, y: 5))), isNull);
    });

    test('everything else is GM-only', () {
      expect(refusal(alice, const RemoveToken(TokenId('mine'))), Refusal.gmOnly);
      expect(refusal(gm, PlaceToken(token('mine'))), Refusal.duplicateId);
      expect(refusal(gm, const RemoveToken(TokenId('nope'))), Refusal.notFound);
    });

    test('the GM updates a token whole; bad sizes are refused', () {
      final mine = scene.tokens[const TokenId('mine')]!;
      final pictured =
          mine.copyWith(image: const AssetId('face'), name: 'Goblin 1');
      expect(refusal(gm, UpdateToken(pictured)), isNull);
      expect(Command.fromJson(UpdateToken(pictured).toJson()).toJson(),
          UpdateToken(pictured).toJson());
      expect(reduce(scene, gm, UpdateToken(pictured)),
          isA<Accepted>().having((a) => a.patches.single, 'patch',
              isA<Upsert>().having((u) => u.entity, 'entity', pictured)));
      expect(refusal(alice, UpdateToken(pictured)), Refusal.gmOnly);
      expect(refusal(gm, UpdateToken(token('nope'))), Refusal.notFound);
      expect(refusal(gm, UpdateToken(mine.copyWith(size: 0))), Refusal.invalid);
      expect(refusal(gm, UpdateToken(mine.copyWith(size: double.infinity))),
          Refusal.invalid);
    });

    test('a new cell size rescales tokens; a zero one is refused', () {
      final store = SceneStore(scene); // Tokens are 64, one cell.
      store.execute(gm, UpdateSettings(settings.copyWith(grid: const Grid(cellSize: 100))));
      expect({for (final t in store.scene.tokens.values) t.size}, {100});
      expect(refusal(gm, UpdateSettings(settings.copyWith(grid: const Grid(cellSize: 0)))),
          Refusal.invalid);
    });

    test('players mark their own tokens with conditions', () {
      final store = SceneStore(scene);
      expect(store.execute(alice, const SetCondition(TokenId('mine'), 'Poisoned')),
          isA<Accepted>());
      store.execute(alice, const SetCondition(TokenId('mine'), 'Darkness', 2));
      store.execute(gm, const SetCondition(TokenId('mine'), 'Poisoned', 1));
      final mine = store.scene.tokens[const TokenId('mine')]!;
      expect(mine.conditions, {'Poisoned': 1, 'Darkness': 2});
      final decoded =
          Entity.fromJson(jsonDecode(jsonEncode(mine.toJson())) as Json);
      expect((decoded as Token).conditions, mine.conditions);
      store.execute(alice, const RemoveCondition(TokenId('mine'), 'Poisoned'));
      expect(store.scene.tokens[const TokenId('mine')]!.conditions,
          {'Darkness': 2});

      expect(refusal(alice, const SetCondition(TokenId('theirs'), 'Prone')),
          Refusal.notOwner);
      expect(refusal(alice, const SetCondition(TokenId('secret'), 'Prone')),
          Refusal.notFound);
      expect(refusal(alice, const RemoveCondition(TokenId('mine'), 'Prone')),
          Refusal.notFound);
      for (final bad in [
        const SetCondition(TokenId('mine'), ''),
        const SetCondition(TokenId('mine'), ' Prone'),
        SetCondition(const TokenId('mine'), 'x' * 31),
        const SetCondition(TokenId('mine'), 'Prone', -1),
        const SetCondition(TokenId('mine'), 'Prone', 100),
      ]) {
        expect(refusal(alice, bad), Refusal.invalid, reason: '${bad.toJson()}');
        expect(Command.fromJson(bad.toJson()).toJson(), bad.toJson());
      }
    });

    test('anyone rolls, chats and pings; bad input is refused', () {
      for (final ok in [
        const RollDice('2d6+3'),
        const Say('Hello'),
        const Ping((x: 1, y: 2)),
      ]) {
        expect(refusal(alice, ok), isNull);
        expect(reduce(scene, alice, ok),
            isA<Accepted>().having((a) => a.patches, 'patches', isEmpty));
        expect(Command.fromJson(ok.toJson()).toJson(), ok.toJson());
      }
      expect(refusal(alice, const RollDice('2d')), Refusal.invalid);
      expect(refusal(alice, const RollDice('d20', secret: true)),
          Refusal.gmOnly);
      expect(refusal(gm, const RollDice('d20', secret: true)), isNull);
      expect(Command.fromJson(const RollDice('d4', secret: true).toJson())
          .toJson(), const RollDice('d4', secret: true).toJson());
      expect(refusal(alice, const Say('  ')), Refusal.invalid);
      expect(refusal(alice, Say('x' * 501)), Refusal.invalid);
      expect(refusal(alice, const Ping((x: double.nan, y: 0))), Refusal.invalid);
    });

    test('fog ops get increasing orders', () {
      final store = SceneStore(scene);
      for (final id in ['f1', 'f2']) {
        store.execute(gm, AddFogOp(FogOpId(id), FogMode.cover,
            const FogRect((x: 0, y: 0), (x: 1, y: 1))));
      }
      expect([for (final f in store.scene.fogInOrder) f.order], [1, 2]);
    });
  });

  test('dice formulas parse within limits, and roll within their faces', () {
    String? canon(String s) => DiceFormula.tryParse(s)?.toString();
    expect(canon('2d6+3'), '2d6 + 3');
    expect(canon('D20'), '1d20');
    expect(canon(' 1d8 + 1d4 - 1 '), '1d8 + 1d4 - 1');
    expect(canon('-1+d4'), '-1 + 1d4');
    for (final bad in [
      '', '3', 'd', '2d', 'd1', '0d6', '101d6', '1d1001', '2d6+', '2d6 3',
      '2d6*2', '1+2+3+4+5+6+7+8+9+10+1d4', 'abc', '1d6+20000',
    ]) {
      expect(DiceFormula.tryParse(bad), isNull, reason: bad);
    }
    final formula = DiceFormula.tryParse('3d6-2')!;
    final random = Random(1);
    for (var i = 0; i < 200; i++) {
      final faces = formula.roll(random);
      expect(faces.first, hasLength(3));
      expect(faces.first.every((f) => f >= 1 && f <= 6), isTrue);
      expect(formula.total(faces), faces.first.reduce((a, b) => a + b) - 2);
    }
  });

  // The core half of hypothesis H3: a player who applies only their filtered
  // patches ends up with exactly the GM's scene filtered for them.
  test('filtered patches converge with the filtered scene', () {
    final random = Random(42);
    final players = [alice, bob];
    final ids = [for (var i = 0; i < 6; i++) TokenId('t$i')];
    var gmScene = Scene(settings: settings);
    final views = {for (final p in players) p: visibleTo(gmScene, p)};

    Command randomCommand() {
      final id = ids[random.nextInt(ids.length)];
      final region = RegionId('r${random.nextInt(3)}');
      return switch (random.nextInt(12)) {
        0 => PlaceToken(token(id.value, hidden: random.nextBool())),
        1 => MoveToken(id, (x: random.nextDouble() * 4096, y: 0)),
        2 => AssignOwner(id, players[random.nextInt(2)].id),
        3 => SetTokenHidden(id, random.nextBool()),
        4 => RemoveToken(id),
        5 => PlaceRegion(Region(
            id: region,
            from: (x: 0, y: 0),
            to: (x: 64, y: 64),
            hidden: random.nextBool())),
        6 => UpdateRegion(Region(
            id: region,
            from: (x: 0, y: 0),
            to: (x: 128, y: 64),
            tags: const {'Darkness': 2},
            hidden: random.nextBool())),
        7 => RemoveRegion(region),
        8 => SetInitiative(Initiative(
            round: 1,
            current: gmScene.tokens.keys.firstOrNull,
            entries: Initiative.ordered([
              for (final t in gmScene.tokens.keys)
                (token: t, value: random.nextInt(20)),
            ]))),
        9 => random.nextBool() ? const EndTurn() : const EndInitiative(),
        10 => SetTracker(id, 'HP', random.nextBool() ? random.nextInt(30) : null),
        _ => random.nextBool()
            ? const UsePack('dnd5e')
            : const UsePack('mine', data: {'id': 'mine', 'name': 'Mine'}),
      };
    }

    var accepted = 0;
    for (var i = 0; i < 2000; i++) {
      final actor = random.nextInt(3) == 0 ? players[random.nextInt(2)] : gm;
      if (reduce(gmScene, actor, randomCommand()) case Accepted(:final patches)) {
        accepted++;
        for (final p in players) {
          views[p] = views[p]!.applyPatches(patchesFor(gmScene, patches, p));
        }
        gmScene = gmScene.applyPatches(patches);
        for (final p in players) {
          expect(views[p]!.toJson(), equals(visibleTo(gmScene, p).toJson()));
        }
      }
    }
    expect(accepted, greaterThan(500));
  });

  group('regions', () {
    test('the GM places, updates and removes them; players may not', () {
      final scene = sceneWith([]);
      final placed = reduce(scene, gm, PlaceRegion(r));
      expect(placed, isA<Accepted>());
      final withRegion = scene.applyPatches((placed as Accepted).patches);
      expect(reduce(withRegion, gm, PlaceRegion(r)), isA<Refused>());
      expect(reduce(withRegion, alice, RemoveRegion(r.id)), isA<Refused>());
      expect(
          reduce(withRegion, gm, UpdateRegion(r.copyWith(tags: {'': 1}))),
          isA<Refused>());
      final removed = reduce(withRegion, gm, RemoveRegion(r.id)) as Accepted;
      expect(withRegion.applyPatches(removed.patches).regions, isEmpty);
    });

    test('a hidden region never reaches players', () {
      final scene = sceneWith([]).applyPatches([Upsert(r.copyWith(hidden: true))]);
      expect(visibleTo(scene, alice).regions, isEmpty);
      expect(visibleTo(scene, gm).regions, hasLength(1));
    });
  });

  group('initiative', () {
    Initiative order(String? current, {int round = 1}) => Initiative(
          round: round,
          current: current == null ? null : TokenId(current),
          entries: Initiative.ordered([
            (token: const TokenId('a'), value: 12),
            (token: const TokenId('b'), value: 18),
            (token: const TokenId('c'), value: 5),
          ]),
        );

    test('turns go from highest to lowest, then a new round', () {
      var i = order(null);
      final seen = <String>[];
      for (var n = 0; n < 4; n++) {
        i = i.next();
        seen.add('${i.round}:${i.current!.value}');
      }
      expect(seen, ['1:b', '1:a', '1:c', '2:b']);
    });

    test('players end only their own turn', () {
      final scene = sceneWith([token('a', owner: alice.id), token('b'), token('c')])
          .applyPatches([Upsert(order('a'))]);
      expect(reduce(scene, bob, const EndTurn()), isA<Refused>());
      final ended = reduce(scene, alice, const EndTurn()) as Accepted;
      expect((ended.patches.single as Upsert).entity, isA<Initiative>());
      expect(scene.applyPatches(ended.patches).initiative!.current, const TokenId('c'));
    });

    test('a removed token leaves the order, passing its turn on', () {
      final scene = sceneWith([token('a'), token('b'), token('c')])
          .applyPatches([Upsert(order('a'))]);
      final after = scene.applyPatches(
          (reduce(scene, gm, const RemoveToken(TokenId('a'))) as Accepted).patches);
      expect(after.initiative!.entries.map((e) => e.token.value), ['b', 'c']);
      expect(after.initiative!.current, const TokenId('c'));
    });

    test('orders listing missing tokens or out of order are refused', () {
      final scene = sceneWith([token('a'), token('b')]);
      expect(reduce(scene, gm, SetInitiative(order(null))), isA<Refused>());
      final unsorted = Initiative(round: 1, entries: [
        (token: const TokenId('a'), value: 1),
        (token: const TokenId('b'), value: 9),
      ]);
      expect(reduce(scene, gm, SetInitiative(unsorted)), isA<Refused>());
    });

    test('players never see a hidden token in the order, nor its turn', () {
      final scene = sceneWith([token('a'), token('b', hidden: true), token('c')])
          .applyPatches([Upsert(order('b'))]);
      final seen = visibleTo(scene, alice).initiative!;
      expect(seen.entries.map((e) => e.token.value), ['a', 'c']);
      expect(seen.current, isNull);
    });

    test('regions, the order and the pack survive a JSON round trip', () {
      final scene = Scene(
        settings: settings.copyWith(pack: 'dnd5e'),
        tokens: {for (final t in [token('a'), token('b'), token('c')]) t.id: t},
        regions: {r.id: r},
        initiative: order('b', round: 3),
      );
      final decoded = jsonDecode(jsonEncode(scene.toJson())) as Json;
      expect(Scene.fromJson(decoded).toJson(), equals(scene.toJson()));
      expect(Scene.fromJson(decoded).settings.pack, 'dnd5e');
    });
  });

  test('the GM erases a fog op; players may not; a shape knows what it covers', () {
    final scene = sceneWith([]).applyPatches([
      Upsert(FogOp(
          id: const FogOpId('f'),
          order: 1,
          mode: FogMode.reveal,
          shape: const FogBrush([(x: 0, y: 0), (x: 100, y: 0)], 10))),
    ]);
    expect(reduce(scene, alice, const RemoveFogOp(FogOpId('f'))), isA<Refused>());
    final erased = reduce(scene, gm, const RemoveFogOp(FogOpId('f'))) as Accepted;
    expect(scene.applyPatches(erased.patches).fogOps, isEmpty);
    expect(reduce(scene, gm, const RemoveFogOp(FogOpId('nope'))), isA<Refused>());

    const brush = FogBrush([(x: 0, y: 0), (x: 100, y: 0)], 10);
    expect(brush.contains((x: 50, y: 9)), isTrue);
    expect(brush.contains((x: 50, y: 11)), isFalse);
    expect(const FogBrush([(x: 5, y: 5)], 3).contains((x: 7, y: 5)), isTrue);
    expect(const FogRect((x: 10, y: 10), (x: 0, y: 0)).contains((x: 5, y: 5)), isTrue);
  });

  group('packs and trackers', () {
    const mine = {'id': 'mine', 'name': 'Mine', 'unit': 'ft'};

    test('an installed pack rides with the scene; a built-in one drops it', () {
      var scene = sceneWith([]);
      expect(reduce(scene, alice, const UsePack('mine', data: mine)), isA<Refused>());
      expect(reduce(scene, gm, const UsePack('other', data: mine)), isA<Refused>());
      scene = scene.applyPatches(
          (reduce(scene, gm, const UsePack('mine', data: mine)) as Accepted).patches);
      expect(scene.settings.pack, 'mine');
      expect(visibleTo(scene, alice).packFile!.id, 'mine');
      final decoded = Scene.fromJson(jsonDecode(jsonEncode(scene.toJson())) as Json);
      expect(decoded.packFile!.data, mine);
      scene = scene.applyPatches(
          (reduce(scene, gm, const UsePack('dnd5e')) as Accepted).patches);
      expect((scene.settings.pack, scene.packFile), ('dnd5e', null));
    });

    test('players track their own tokens; values are bounded', () {
      final scene = sceneWith([token('a', owner: alice.id), token('b')]);
      final set = reduce(scene, alice, const SetTracker(TokenId('a'), 'HP', 12));
      final after = scene.applyPatches((set as Accepted).patches);
      expect(after.tokens[const TokenId('a')]!.trackers, {'HP': 12});
      expect(reduce(scene, alice, const SetTracker(TokenId('b'), 'HP', 3)),
          isA<Refused>());
      expect(reduce(scene, gm, const SetTracker(TokenId('b'), 'HP', 1000000)),
          isA<Refused>());
      final cleared = reduce(after, alice, const SetTracker(TokenId('a'), 'HP', null));
      expect(after.applyPatches((cleared as Accepted).patches)
          .tokens[const TokenId('a')]!.trackers, isEmpty);
      final moved = after.tokens[const TokenId('a')]!.moveTo((x: 1, y: 1));
      expect(moved.trackers, {'HP': 12});
    });
  });

  test("the GM's tokens keep their trackers from players; templates round-trip", () {
    final scene = sceneWith([
      token('pc', owner: alice.id).withTrackers({'HP': 9}),
      Token(
          id: const TokenId('npc'),
          position: (x: 0, y: 0),
          size: 64,
          template: 'Raider',
          trackers: const {'CvW': 2}),
    ]);
    final seen = visibleTo(scene, bob);
    expect(seen.tokens[const TokenId('pc')]!.trackers, {'HP': 9});
    expect(seen.tokens[const TokenId('npc')]!.trackers, isEmpty);
    expect(seen.tokens[const TokenId('npc')]!.template, 'Raider');
    final hit = reduce(scene, gm, const SetTracker(TokenId('npc'), 'CvW', 3)) as Accepted;
    final sent = patchesFor(scene, hit.patches, bob).single as Upsert;
    expect((sent.entity as Token).trackers, isEmpty);
    final decoded = Scene.fromJson(jsonDecode(jsonEncode(scene.toJson())) as Json);
    expect(decoded.tokens[const TokenId('npc')]!.template, 'Raider');
    expect(decoded.tokens[const TokenId('npc')]!.moveTo((x: 1, y: 1)).template, 'Raider');
  });

  test('only owners write their characters; tokens play them', () {
    final ayla = Character(
        id: const CharacterId('ayla'),
        owner: alice.id,
        system: 'generic',
        name: 'Ayla',
        values: const {'HP': 8});
    final scene = sceneWith([token('a', owner: alice.id), token('b', owner: bob.id)]);
    Scene run(Scene s, Actor actor, Command c) =>
        s.applyPatches((reduce(s, actor, c) as Accepted).patches);
    Refusal? why(Scene s, Actor actor, Command c) => switch (reduce(s, actor, c)) {
          Refused(:final reason) => reason,
          Accepted() => null,
        };

    final inRoom = run(scene, alice, UpdateCharacter(ayla));
    expect(inRoom.characters[ayla.id]!.values, {'HP': 8});
    expect(why(scene, bob, UpdateCharacter(ayla)), Refusal.notOwner);
    expect(why(scene, gm, UpdateCharacter(ayla)), Refusal.notOwner);
    // Bob can't take Ayla over by sending her as his.
    final stolen = Character(id: ayla.id, owner: bob.id, system: 'generic', name: 'Mine');
    expect(why(inRoom, bob, UpdateCharacter(stolen)), Refusal.notOwner);
    expect(why(scene, alice, UpdateCharacter(ayla.copyWith(name: ' '))), Refusal.invalid);
    final other = Character(id: ayla.id, owner: alice.id, system: 'dnd5e', name: 'Ayla');
    expect(why(scene, alice, UpdateCharacter(other)), Refusal.invalid);

    const link = LinkCharacter(TokenId('a'), CharacterId('ayla'));
    final linked = run(inRoom, alice, link);
    expect(linked.tokens[const TokenId('a')]!.character, ayla.id);
    expect(why(inRoom, bob, const LinkCharacter(TokenId('b'), CharacterId('ayla'))),
        Refusal.notOwner);
    expect(why(inRoom, alice, const LinkCharacter(TokenId('b'), CharacterId('ayla'))),
        Refusal.notOwner);
    expect(reduce(inRoom, gm, const LinkCharacter(TokenId('b'), CharacterId('ayla'))),
        isA<Accepted>());

    // Characters ride along with the scene's JSON and players' copies.
    final decoded = Scene.fromJson(jsonDecode(jsonEncode(linked.toJson())) as Json);
    expect(decoded.characters[ayla.id]!.name, 'Ayla');
    expect(decoded.tokens[const TokenId('a')]!.moveTo((x: 0, y: 0)).character, ayla.id);
    expect(visibleTo(linked, bob).characters.keys, [ayla.id]);
    expect(linked.withCharacters(const {}).characters, isEmpty);

    expect(why(linked, bob, RemoveCharacter(ayla.id)), Refusal.notOwner);
    final gone = run(linked, alice, RemoveCharacter(ayla.id));
    expect(gone.characters, isEmpty);
    expect(gone.tokens[const TokenId('a')]!.character, isNull);
  });
}
