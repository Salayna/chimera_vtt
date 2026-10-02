import 'dart:async';

import 'package:chimera_core/chimera_core.dart';
import 'package:supabase/supabase.dart';

import 'transport.dart';

/// A room as a Supabase Realtime channel: broadcast for messages, presence
/// for who is connected.
///
/// ponytail: public channel, so knowing the room code is enough to join and
/// a client could claim any player id. Private channels with RLS are phase 7.
final class SupabaseTransport implements Transport {
  SupabaseTransport._(this._client, this._channel);

  static const _event = 'm';

  final SupabaseClient _client;
  final RealtimeChannel _channel;
  final _messages = StreamController<Json>.broadcast();
  final _presence = StreamController<List<Json>>.broadcast();

  /// Joins room [room] and completes once subscribed. Sign in first: the
  /// POC uses anonymous sign-in.
  static Future<SupabaseTransport> join(SupabaseClient client, String room) {
    final channel = client.channel(
      'room:$room',
      opts: const RealtimeChannelConfig(self: false),
    );
    final transport = SupabaseTransport._(client, channel);
    final joined = Completer<SupabaseTransport>();
    channel
        .onBroadcast(
          event: _event,
          callback: (payload) {
            // Our message is nested: the client adds its own keys at the top.
            if (payload['message'] case final Map<String, dynamic> m) {
              transport._messages.add(m);
            }
          },
        )
        .onPresenceSync((_) => transport._presence.add([
              for (final state in channel.presenceState())
                for (final p in state.presences) p.payload,
            ]))
        .subscribe((status, error) {
      if (joined.isCompleted) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          joined.complete(transport);
        case RealtimeSubscribeStatus.channelError ||
              RealtimeSubscribeStatus.timedOut ||
              RealtimeSubscribeStatus.closed:
          joined.completeError(error ?? StateError('Realtime: ${status.name}'));
      }
    });
    return joined.future;
  }

  @override
  Stream<Json> get messages => _messages.stream;

  @override
  Stream<List<Json>> get presence => _presence.stream;

  // Best effort, like the network: a failed send is a lost message, and the
  // protocol recovers through sequence numbers and heartbeats.
  @override
  Future<void> send(Json message) =>
      _channel.sendBroadcastMessage(event: _event, payload: {'message': message});

  @override
  Future<void> track(Json state) => _channel.track(state);

  @override
  Future<void> close() async {
    await _client.removeChannel(_channel);
    await _messages.close();
    await _presence.close();
  }
}
