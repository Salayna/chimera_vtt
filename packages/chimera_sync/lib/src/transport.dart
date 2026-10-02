import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:chimera_core/chimera_core.dart';

/// Moves JSON messages between the clients of one room. Delivery is best
/// effort: messages may be lost or reordered, and the protocol copes.
abstract interface class Transport {
  /// Messages from the other clients. Never this client's own.
  Stream<Json> get messages;

  Future<void> send(Json message);

  /// Everyone's presence state, this client's included, on every change.
  Stream<List<Json>> get presence;

  Future<void> track(Json state);

  Future<void> close();
}

/// An in-memory room for tests and solo play. Every message goes through
/// JSON text, so anything that wouldn't survive the network fails here too.
final class LoopbackHub {
  /// With [manual], messages wait until [flush]; otherwise they are
  /// delivered in a microtask, in order.
  LoopbackHub({this.manual = false});

  final bool manual;
  final _clients = <_LoopbackTransport>[];
  final _pending = <(_LoopbackTransport, String)>[];
  final _states = <_LoopbackTransport, Json>{};

  Transport connect() {
    final client = _LoopbackTransport(this);
    _clients.add(client);
    return client;
  }

  bool get idle => _pending.isEmpty;

  /// Delivers waiting messages, including any sent while delivering. With
  /// [random], the order is shuffled and [dropRate] of messages are lost.
  void flush({Random? random, double dropRate = 0}) {
    while (_pending.isNotEmpty) {
      final i = random == null ? 0 : random.nextInt(_pending.length);
      final (to, text) = _pending.removeAt(i);
      if (random != null && random.nextDouble() < dropRate) continue;
      if (!to._messages.isClosed) to._messages.add(jsonDecode(text) as Json);
    }
  }

  void _send(_LoopbackTransport from, Json message) {
    final text = jsonEncode(message);
    for (final to in _clients) {
      if (to != from) _pending.add((to, text));
    }
    if (!manual) scheduleMicrotask(flush);
  }

  void _publishPresence() {
    final states = [
      for (final s in _states.values) jsonDecode(jsonEncode(s)) as Json,
    ];
    for (final c in _clients) {
      c._presence.add(states);
    }
  }
}

final class _LoopbackTransport implements Transport {
  _LoopbackTransport(this._hub);

  final LoopbackHub _hub;
  // Synchronous, so a manual flush delivers deterministically.
  final _messages = StreamController<Json>.broadcast(sync: true);
  final _presence = StreamController<List<Json>>.broadcast(sync: true);

  @override
  Stream<Json> get messages => _messages.stream;

  @override
  Stream<List<Json>> get presence => _presence.stream;

  @override
  Future<void> send(Json message) async => _hub._send(this, message);

  @override
  Future<void> track(Json state) async {
    _hub._states[this] = state;
    _hub._publishPresence();
  }

  @override
  Future<void> close() async {
    _hub._clients.remove(this);
    if (_hub._states.remove(this) != null) _hub._publishPresence();
    await _messages.close();
    await _presence.close();
  }
}
