import 'dart:math';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:test/test.dart';

const gmId = PlayerId('gm');
const alice = PlayerId('alice');
const bob = PlayerId('bob');
const players = Player(PlayerId(''));

final settings = SceneSettings(
  width: 4096,
  height: 4096,
  grid: const Grid(cellSize: 64),
);

Token token(String id, {PlayerId? owner, bool hidden = false}) => Token(
  id: TokenId(id),
  position: (x: 0, y: 0),
  size: 64,
  owner: owner,
  hidden: hidden,
);

/// A GM and two players on a manual loopback hub.
class Table {
  Table(Scene scene) {
    host = HostSession(hub.connect(), gmId, SceneStore(scene));
    clients = {
      for (final p in [alice, bob]) p: ClientSession(hub.connect(), p),
    };
  }

  final hub = LoopbackHub(manual: true);
  late HostSession host;
  late final Map<PlayerId, ClientSession> clients;

  Future<void> join() async {
    final joins = [for (final c in clients.values) c.join()];
    hub.flush();
    await Future.wait(joins);
  }

  void expectConverged() {
    final expected = visibleTo(host.store.scene, players).toJson();
    for (final c in clients.values) {
      expect(c.store.scene.toJson(), equals(expected), reason: '${c.self}');
    }
  }
}

void main() {
  test('every message survives JSON', () {
    final scene = Scene(
      settings: settings,
      tokens: {const TokenId('a'): token('a')},
    );
    final messages = <Message>[
      const RequestSnapshot(alice),
      Snapshot(to: alice, epoch: 'e', seq: 3, scene: scene),
      Snapshot(epoch: 'e', seq: 4, scene: scene),
      PatchBatch(
        epoch: 'e',
        seq: 5,
        patches: [Upsert(token('a')), Delete.token(const TokenId('b'))],
        requestId: 'r1',
      ),
      const Heartbeat('e', 5),
      Intent(
        from: bob,
        requestId: 'r2',
        command: const MoveToken(TokenId('a'), (x: 1, y: 2)).toJson(),
      ),
      const RefusalMessage(to: bob, requestId: 'r2', reason: Refusal.notOwner),
    ];
    for (final m in messages) {
      expect(Message.fromJson(m.toJson()).toJson(), equals(m.toJson()));
    }
  });

  test(
    'presence lists each player once, even with a stale connection',
    () async {
      final hub = LoopbackHub();
      final session = ClientSession(hub.connect(), alice);
      final stale = ClientSession(hub.connect(), alice); // before a reload
      final gm = HostSession(
        hub.connect(),
        gmId,
        SceneStore(Scene(settings: settings)),
      );
      await stale.setCursor(null);
      await session.setCursor(null);
      await gm.setCursor(null);
      expect(session.currentPeers.map((p) => p.player), ['alice', 'gm']);
    },
  );

  test('joining fails on another protocol version', () async {
    final hub = LoopbackHub();
    final fake = hub.connect();
    final client = ClientSession(hub.connect(), alice);
    fake.messages.listen((_) => fake.send({'p': protocolVersion + 1}));
    await expectLater(client.join(), throwsA(isA<ProtocolMismatch>()));
  });

  test('a player sees their move at once, and the GM sees it too', () async {
    final table = Table(
      Scene(
        settings: settings,
        tokens: {const TokenId('t'): token('t', owner: alice)},
      ),
    );
    await table.join();
    final player = table.clients[alice]!;

    expect(
      player.request(const MoveToken(TokenId('t'), (x: 5, y: 5))),
      isA<Accepted>(),
    );
    expect(player.store.scene.tokens[const TokenId('t')]!.position, (
      x: 5,
      y: 5,
    ));
    expect(player.pendingCount, 1);

    table.hub.flush();
    expect(table.host.store.scene.tokens[const TokenId('t')]!.position, (
      x: 5,
      y: 5,
    ));
    expect(player.pendingCount, 0);
    table.expectConverged();
  });

  test("a move the GM refuses snaps back", () async {
    final table = Table(
      Scene(
        settings: settings,
        tokens: {const TokenId('t'): token('t', owner: alice)},
      ),
    );
    await table.join();
    final player = table.clients[alice]!;

    // The GM gives the token away before alice's move reaches them.
    table.host.execute(const AssignOwner(TokenId('t'), bob));
    expect(
      player.request(const MoveToken(TokenId('t'), (x: 9, y: 9))),
      isA<Accepted>(),
    );
    table.hub.flush();

    expect(player.pendingCount, 0);
    expect(player.store.scene.tokens[const TokenId('t')]!.position, (
      x: 0,
      y: 0,
    ));
    table.expectConverged();
  });

  test('a player refuses what the GM would refuse, without sending', () async {
    final table = Table(
      Scene(
        settings: settings,
        tokens: {const TokenId('t'): token('t', owner: bob)},
      ),
    );
    await table.join();
    final outcome = table.clients[alice]!.request(
      const MoveToken(TokenId('t'), (x: 1, y: 1)),
    );
    expect(outcome, isA<Refused>());
    expect(table.hub.idle, isTrue);
  });

  test('players follow a GM who reloads and starts counting again', () async {
    final table = Table(
      Scene(
        settings: settings,
        tokens: {const TokenId('t'): token('t', owner: alice)},
      ),
    );
    await table.join();
    for (var i = 0; i < 5; i++) {
      table.host.execute(MoveToken(const TokenId('t'), (x: i * 10.0, y: 0)));
    }
    table.hub.flush();

    // The GM's tab reloads: a new session with seq back at 0, resuming from
    // an autosave that missed the last moves.
    await table.host.close();
    table.host = HostSession(
      table.hub.connect(),
      gmId,
      SceneStore(
        Scene(
          settings: settings,
          tokens: {const TokenId('t'): token('t', owner: alice)},
        ),
      ),
    );
    table.host.execute(const MoveToken(TokenId('t'), (x: 7, y: 7)));
    table.host.heartbeat();
    table.hub.flush();
    table.expectConverged();
    expect(
      table.clients[alice]!.store.scene.tokens[const TokenId('t')]!.position,
      (x: 7, y: 7),
    );
  });

  test('the GM undoes and redoes their own changes, and players follow',
      () async {
    final table = Table(
      Scene(
        settings: settings,
        tokens: {const TokenId('t'): token('t', owner: alice)},
      ),
    );
    await table.join();
    final host = table.host;
    final start = host.store.scene.toJson();
    host.execute(PlaceToken(token('new')));
    host.execute(const SetTokenHidden(TokenId('t'), true));
    host.execute(const AddFogOp(
        FogOpId('f'), FogMode.cover, FogRect((x: 0, y: 0), (x: 1, y: 1))));
    // Typing a name is one step, however many keys.
    host.execute(UpdateToken(token('new').copyWith(name: 'O')));
    host.execute(UpdateToken(token('new').copyWith(name: 'Ok')));
    final end = host.store.scene.toJson();

    for (var i = 0; i < 4; i++) {
      expect(host.undo(), isTrue);
    }
    expect(host.undo(), isFalse);
    expect(host.store.scene.toJson(), equals(start));
    table.hub.flush();
    table.expectConverged();

    while (host.redo()) {}
    expect(host.store.scene.toJson(), equals(end));
    table.hub.flush();
    table.expectConverged();

    // A player's move is theirs: undo skips it and takes back the GM's last.
    host.undo();
    host.execute(const SetTokenHidden(TokenId('t'), false));
    table.hub.flush();
    table.clients[alice]!.request(const MoveToken(TokenId('t'), (x: 9, y: 9)));
    table.hub.flush();
    expect(host.canRedo, isFalse); // A new change clears redo.
    host.undo();
    table.hub.flush();
    expect(host.store.scene.tokens[const TokenId('t')]!.hidden, isTrue);
    table.expectConverged();
  });

  test('loading a scene reaches every player', () async {
    final table = Table(Scene(settings: settings));
    await table.join();
    table.host.load(
      Scene(settings: settings, tokens: {const TokenId('new'): token('new')}),
    );
    table.hub.flush();
    table.expectConverged();
  });

  // Hypothesis H3: two scripted players and the GM send 1,000 random
  // commands over a transport that loses 5% of messages and shuffles the
  // rest. Once the network calms down, everyone shows the GM's state.
  test('H3: players converge despite loss and reordering', () async {
    final random = Random(7);
    final ids = [for (var i = 0; i < 6; i++) TokenId('t$i')];
    final table = Table(
      Scene(
        settings: settings,
        tokens: {
          for (final id in ids)
            id: token(id.value, owner: random.nextBool() ? alice : bob),
        },
      ),
    );
    await table.join();

    Point somewhere() => (
      x: random.nextInt(4096).toDouble(),
      y: random.nextInt(4096).toDouble(),
    );

    var accepted = 0;
    for (var i = 0; i < 1000; i++) {
      final id = ids[random.nextInt(ids.length)];
      if (random.nextInt(3) == 0) {
        table.host.execute(switch (random.nextInt(5)) {
          0 => PlaceToken(token(id.value, hidden: random.nextBool())),
          1 => AssignOwner(id, random.nextBool() ? alice : bob),
          2 => SetTokenHidden(id, random.nextBool()),
          3 => RemoveToken(id),
          _ => MoveToken(id, somewhere()),
        });
      } else {
        final player = table.clients[random.nextBool() ? alice : bob]!;
        // Mostly their own tokens, as they see them; sometimes anything.
        final own = [
          for (final t in player.store.scene.tokens.values)
            if (t.owner == player.self) t.id,
        ];
        final target = own.isEmpty || random.nextInt(4) == 0
            ? id
            : own[random.nextInt(own.length)];
        if (player.request(MoveToken(target, somewhere())) is Accepted) {
          accepted++;
        }
      }
      if (i % 10 == 0) table.host.heartbeat();
      table.hub.flush(random: random, dropRate: 0.05);
    }
    expect(accepted, greaterThan(100));

    // Calm network: heartbeats reveal gaps and expire lost intents.
    for (var i = 0; i < ClientSession.intentLifetime + 1; i++) {
      table.host.heartbeat();
      table.hub.flush();
    }
    for (final c in table.clients.values) {
      expect(c.resyncing, isFalse);
      expect(c.pendingCount, 0);
    }
    table.expectConverged();
  });
}
