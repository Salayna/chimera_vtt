// H6: does a session fit Supabase's Realtime message quota? Plays a scripted
// one-hour session over the loopback and counts what Supabase would bill.
//
// Billing (supabase.com/docs/guides/platform/manage-your-usage/realtime-messages):
// a broadcast is 1 message sent plus 1 per client that receives it. Clients
// don't receive their own (`self: false`), so each send is billed once per
// client in the room. Presence isn't counted here: cursors aren't sent yet.
import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:test/test.dart';

/// Counts what goes out, then hands it on.
final class Counting implements Transport {
  Counting(this._inner);

  final Transport _inner;
  static var sends = 0;

  @override
  Stream<Json> get messages => _inner.messages;
  @override
  Future<void> send(Json message) {
    sends++;
    return _inner.send(message);
  }

  @override
  Stream<List<Json>> get presence => _inner.presence;
  @override
  Future<void> track(Json state) => _inner.track(state);
  @override
  Future<void> close() => _inner.close();
}

// The session: the GM and four players, one hour.
const playerCount = 4;
const minutes = 60;
const heartbeatSeconds = 3; // GmRoom.heartbeatEvery
// Only a drag's drop is sent (TableView), so each move is one update.
const updatesPerMove = 1;
const playerMovesPerMinute = 2; // Each player.
const gmMovesPerMinute = 1;
const fogStrokesPerHour = 100;

void main() {
  test('H6: one hour of play, counted as Supabase bills it', () async {
    Counting.sends = 0;
    final hub = LoopbackHub(manual: true);
    final ids = [for (var i = 0; i < playerCount; i++) PlayerId('p$i')];
    final host = HostSession(
      Counting(hub.connect()),
      const PlayerId('gm'),
      SceneStore(Scene(
        settings: const SceneSettings(
            width: 4096, height: 4096, grid: Grid(cellSize: 64)),
        tokens: {
          const TokenId('gm'):
              const Token(id: TokenId('gm'), position: (x: 0, y: 0), size: 64),
          for (final p in ids)
            TokenId(p.value): Token(
                id: TokenId(p.value), position: (x: 0, y: 0), size: 64, owner: p),
        },
      )),
    );
    final players = [for (final p in ids) ClientSession(Counting(hub.connect()), p)];
    final joins = [for (final c in players) c.join()];
    hub.flush();
    await Future.wait(joins);

    const updates = updatesPerMove;
    var x = 0.0;
    for (var minute = 0; minute < minutes; minute++) {
      for (var s = 0; s < 60; s += heartbeatSeconds) {
        host.heartbeat();
      }
      for (final c in players) {
        for (var m = 0; m < playerMovesPerMinute; m++) {
          for (var u = 0; u < updates; u++) {
            c.request(MoveToken(TokenId(c.self.value), (x: x++, y: 0)));
            hub.flush();
          }
        }
      }
      for (var m = 0; m < gmMovesPerMinute * updates; m++) {
        host.execute(MoveToken(const TokenId('gm'), (x: x++, y: 0)));
      }
      hub.flush();
    }
    for (var i = 0; i < fogStrokesPerHour; i++) {
      host.execute(AddFogOp(FogOpId('f$i'), FogMode.cover,
          const FogRect((x: 0, y: 0), (x: 64, y: 64))));
    }
    hub.flush();

    final clients = playerCount + 1;
    final billed = Counting.sends * clients;
    // ignore: avoid_print
    print('H6: ${Counting.sends} sends, $billed billed messages per hour '
        '(GM + $playerCount players). Hours per month within 2M (Free): '
        '${(2e6 / billed).toStringAsFixed(1)}; within 5M (Pro): '
        '${(5e6 / billed).toStringAsFixed(1)}.');
    expect(billed, greaterThan(0));
  });
}
