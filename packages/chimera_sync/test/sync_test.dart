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
    const events = <TableEvent>[
      Roll(alice, 1, formula: '2d6 + 1', faces: [[3, 4], []], total: 8),
      Roll(gmId, 1, formula: '1d20', faces: [[7]], total: 7, gm: true,
          secret: true),
      Chat(bob, 2, 'Hi'),
      ConditionChange(alice, 3,
          token: 'Goblin', condition: 'Darkness', value: 2, removed: false),
      ConditionChange(gmId, 3,
          token: 'Ghost', condition: 'Prone', value: null, removed: true,
          gm: true, secret: true),
      PingEvent(gmId, 4, (x: 1.5, y: 2), gm: true),
    ];
    final messages = <Message>[
      const RequestSnapshot(alice),
      Snapshot(to: alice, epoch: 'e', seq: 3, scene: scene, log: events),
      Snapshot(epoch: 'e', seq: 4, scene: scene),
      PatchBatch(
        epoch: 'e',
        seq: 5,
        patches: [Upsert(token('a')), Delete.token(const TokenId('b'))],
        requestId: 'r1',
        events: events,
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

  test('rolls, chat and conditions reach everyone\'s log; moves don\'t',
      () async {
    final table = Table(
      Scene(
        settings: settings,
        tokens: {
          const TokenId('t'): token('t', owner: alice).copyWith(name: 'Ayla'),
          const TokenId('h'): token('h', hidden: true),
        },
      ),
    );
    await table.join();
    final pings = <TableEvent>[];
    table.clients[bob]!.events
        .where((e) => e is PingEvent)
        .listen(pings.add);
    final alices = table.clients[alice]!;
    alices.request(const MoveToken(TokenId('t'), (x: 64, y: 64)));
    alices.request(const RollDice('2d6+3'));
    alices.request(const Say('  Hello  '));
    alices.request(const SetCondition(TokenId('t'), 'Darkness', 2));
    alices.request(const Ping((x: 5, y: 5)));
    table.hub.flush();
    table.host.execute(const SetCondition(TokenId('h'), 'Secret'));
    table.host.execute(const RemoveCondition(TokenId('t'), 'Darkness'));
    table.hub.flush();
    await Future<void>.delayed(Duration.zero); // Stream deliveries.

    // The hidden token's condition is logged for the GM alone.
    final secret = table.host.currentLog.where((e) => e.secret).toList();
    expect(secret.single,
        isA<ConditionChange>().having((c) => c.condition, 'condition', 'Secret'));
    final log = [for (final e in table.host.currentLog) if (!e.secret) e];
    expect(log.map((e) => e.runtimeType),
        [Roll, Chat, ConditionChange, ConditionChange]);
    final roll = log[0] as Roll;
    expect(roll.by, alice);
    expect(roll.formula, '2d6 + 3');
    expect(roll.faces.first, hasLength(2));
    expect(roll.total, roll.faces.first.reduce((a, b) => a + b) + 3);
    expect((log[1] as Chat).text, 'Hello');
    expect((log[2] as ConditionChange).token, 'Ayla');
    expect((log[3] as ConditionChange).removed, isTrue);
    expect([for (final e in log) e.gm], [false, false, false, true]);
    expect(pings, hasLength(1));
    for (final c in table.clients.values) {
      expect([for (final e in c.currentLog) e.toJson()],
          [for (final e in log) e.toJson()], reason: '${c.self}');
    }

    // Someone who joins late gets the log with the scene.
    final carol = ClientSession(table.hub.connect(), const PlayerId('carol'));
    final joined = carol.join();
    table.hub.flush();
    await joined;
    expect(carol.currentLog, hasLength(log.length));
    table.expectConverged();
  });

  test('a ruler travels in presence, and goes when cleared', () async {
    final hub = LoopbackHub(manual: true);
    final host = HostSession(
        hub.connect(), gmId, SceneStore(Scene(settings: settings)));
    final player = ClientSession(hub.connect(), alice);
    await player.setCursor(null);
    await player.setRuler(((x: 1, y: 2), (x: 3, y: 4)));
    hub.flush();
    await Future<void>.delayed(Duration.zero);
    Presence alices() =>
        host.currentPeers.singleWhere((p) => p.player == alice.value);
    expect(alices().ruler, ((x: 1.0, y: 2.0), (x: 3.0, y: 4.0)));
    await player.setRuler(null);
    hub.flush();
    await Future<void>.delayed(Duration.zero);
    expect(alices().ruler, isNull);
  });

  test('the stored log carries over; secret rolls stay with the GM',
      () async {
    final stored = <TableEvent>[];
    final hub = LoopbackHub(manual: true);
    final host = HostSession(
      hub.connect(),
      gmId,
      SceneStore(Scene(settings: settings)),
      log: const [Chat(alice, 1, 'From last session')],
      onLogged: stored.add,
    );
    final player = ClientSession(hub.connect(), alice);
    final joined = player.join();
    hub.flush();
    await joined;
    expect(player.currentLog.map((e) => e.toJson()),
        [const Chat(alice, 1, 'From last session').toJson()]);

    host.execute(const RollDice('d20', secret: true));
    host.execute(const RollDice('d6'));
    host.execute(const Ping((x: 0, y: 0)));
    hub.flush();
    await Future<void>.delayed(Duration.zero);
    expect([for (final e in host.currentLog) e.secret], [false, true, false]);
    expect([for (final e in player.currentLog) e.secret], [false, false]);
    expect([for (final e in stored) (e as Roll).secret], [true, false]);

    // Nor does a snapshot carry it.
    final late = ClientSession(hub.connect(), bob);
    final lateJoined = late.join();
    hub.flush();
    await lateJoined;
    expect(late.currentLog.where((e) => e.secret), isEmpty);
    expect(late.currentLog, hasLength(2));
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
