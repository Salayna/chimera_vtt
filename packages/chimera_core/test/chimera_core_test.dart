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

    test('fog ops get increasing orders', () {
      final store = SceneStore(scene);
      for (final id in ['f1', 'f2']) {
        store.execute(gm, AddFogOp(FogOpId(id), FogMode.cover,
            const FogRect((x: 0, y: 0), (x: 1, y: 1))));
      }
      expect([for (final f in store.scene.fogInOrder) f.order], [1, 2]);
    });
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
      return switch (random.nextInt(5)) {
        0 => PlaceToken(token(id.value, hidden: random.nextBool())),
        1 => MoveToken(id, (x: random.nextDouble() * 4096, y: 0)),
        2 => AssignOwner(id, players[random.nextInt(2)].id),
        3 => SetTokenHidden(id, random.nextBool()),
        _ => RemoveToken(id),
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
}
