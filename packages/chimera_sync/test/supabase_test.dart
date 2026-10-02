// Live check of SupabaseTransport against a running Supabase (local or
// hosted). Skipped unless SUPABASE_URL and SUPABASE_KEY are set:
//
//   SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_KEY=<publishable key> \
//     dart test test/supabase_test.dart
@Tags(['supabase'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

final url = Platform.environment['SUPABASE_URL'];
final key = Platform.environment['SUPABASE_KEY'];

Future<(SupabaseClient, PlayerId)> signIn() async {
  final client = SupabaseClient(url!, key!);
  final response = await client.auth.signInAnonymously();
  return (client, PlayerId(response.user!.id));
}

void main() {
  test(
    'a GM and a player sync over Realtime (H2)',
    () async {
      final room = newId().substring(0, 8);
      final (gmClient, gmId) = await signIn();
      final (playerClient, playerId) = await signIn();
      const tokenId = TokenId('t');

      final host = HostSession(
        await SupabaseTransport.join(gmClient, room),
        gmId,
        SceneStore(Scene(
          settings: const SceneSettings(
              width: 4096, height: 4096, grid: Grid(cellSize: 64)),
          tokens: {
            tokenId: Token(
                id: tokenId, position: (x: 0, y: 0), size: 64, owner: playerId),
          },
        )),
      );
      final player =
          ClientSession(await SupabaseTransport.join(playerClient, room), playerId);
      final store = await player.join().timeout(const Duration(seconds: 10));

      // Presence: both sides show up.
      final peers = player.peers
          .firstWhere((p) => p.length == 2)
          .timeout(const Duration(seconds: 10));
      await host.setCursor((x: 1, y: 1));
      await player.setCursor(null);
      expect((await peers).map((p) => p.gm), containsAll([true, false]));

      // GM to player latency, one move at a time.
      final delays = <int>[];
      for (var i = 1; i <= 50; i++) {
        final arrived = store.changes.firstWhere(
            (s) => s.tokens[tokenId]!.position.x == i.toDouble());
        final watch = Stopwatch()..start();
        host.execute(MoveToken(tokenId, (x: i.toDouble(), y: 0)));
        await arrived.timeout(const Duration(seconds: 5));
        delays.add(watch.elapsedMicroseconds);
      }
      delays.sort();
      final p95 = delays[(delays.length * 0.95).ceil() - 1];
      // ignore: avoid_print
      print('GM to player: median ${delays[delays.length ~/ 2] / 1000} ms, '
          'p95 ${p95 / 1000} ms, max ${delays.last / 1000} ms');

      // Player intent round trip: the GM applies it.
      player.request(const MoveToken(tokenId, (x: 999, y: 999)));
      await host.store.changes
          .firstWhere((s) => s.tokens[tokenId]!.position.x == 999)
          .timeout(const Duration(seconds: 5));

      await player.close();
      await host.close();
      await gmClient.dispose();
      await playerClient.dispose();
    },
    skip: url == null || key == null ? 'SUPABASE_URL/SUPABASE_KEY not set' : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
