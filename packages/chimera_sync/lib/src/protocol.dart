import 'package:chimera_core/chimera_core.dart';

/// Bumped on any incompatible message change. Clients on another version
/// can't decode messages and report [ProtocolMismatch].
const protocolVersion = 1;

final class ProtocolMismatch implements Exception {
  const ProtocolMismatch(this.version);

  final Object? version;

  @override
  String toString() =>
      'ProtocolMismatch: got $version, this client speaks $protocolVersion';
}

/// Anything on the wire. Encoded as `{'p': version, 'type': …, …}`.
sealed class Message {
  const Message();

  String get _type;
  Json _fields();

  Json toJson() => {'p': protocolVersion, 'type': _type, ..._fields()};

  /// Throws [ProtocolMismatch] for another version and [FormatException] or
  /// [TypeError] for malformed input.
  static Message fromJson(Json json) {
    if (json['p'] != protocolVersion) throw ProtocolMismatch(json['p']);
    PlayerId player(String key) => PlayerId(json[key] as String);
    PlayerId? optionalPlayer(String key) =>
        json[key] == null ? null : player(key);
    return switch (json['type']) {
      'requestSnapshot' => RequestSnapshot(player('from')),
      'snapshot' => Snapshot(
          to: optionalPlayer('to'),
          epoch: json['epoch'] as String,
          seq: json['seq'] as int,
          scene: Scene.fromJson(json['scene'] as Json),
        ),
      'batch' => PatchBatch(
          epoch: json['epoch'] as String,
          seq: json['seq'] as int,
          patches: [
            for (final p in json['patches'] as List) Patch.fromJson(p as Json),
          ],
          requestId: json['requestId'] as String?,
        ),
      'heartbeat' => Heartbeat(json['epoch'] as String, json['seq'] as int),
      'intent' => Intent(
          from: player('from'),
          requestId: json['requestId'] as String,
          command: json['command'] as Json,
        ),
      'refusal' => RefusalMessage(
          to: player('to'),
          requestId: json['requestId'] as String,
          reason: Refusal.values.byName(json['reason'] as String),
        ),
      final type => throw FormatException('Unknown message: $type'),
    };
  }
}

/// A player asking for the whole scene: on join, after a gap, on reconnect.
final class RequestSnapshot extends Message {
  const RequestSnapshot(this.from);

  final PlayerId from;

  @override
  String get _type => 'requestSnapshot';

  @override
  Json _fields() => {'from': from.value};
}

/// The whole player-filtered scene, as of batch [seq]. [to] is null when
/// every player should take it, for example after the GM loads a scene.
final class Snapshot extends Message {
  const Snapshot(
      {this.to, required this.epoch, required this.seq, required this.scene});

  final PlayerId? to;

  /// Names one run of the GM's session. A GM who reloads starts a new
  /// epoch with [seq] back at zero, so players compare sequence numbers
  /// only within one epoch.
  final String epoch;
  final int seq;
  final Scene scene;

  @override
  String get _type => 'snapshot';

  @override
  Json _fields() => {
        if (to != null) 'to': to!.value,
        'epoch': epoch,
        'seq': seq,
        'scene': scene.toJson(),
      };
}

/// The player-filtered patches of one accepted command. [requestId] names
/// the intent it answers, so its sender can drop the optimistic copy.
final class PatchBatch extends Message {
  const PatchBatch(
      {required this.epoch,
      required this.seq,
      required this.patches,
      this.requestId});

  final String epoch;
  final int seq;
  final List<Patch> patches;
  final String? requestId;

  @override
  String get _type => 'batch';

  @override
  Json _fields() => {
        'epoch': epoch,
        'seq': seq,
        'patches': [for (final p in patches) p.toJson()],
        if (requestId != null) 'requestId': requestId,
      };
}

/// The GM's latest [seq], sent periodically so a player who missed the last
/// batch notices the gap.
final class Heartbeat extends Message {
  const Heartbeat(this.epoch, this.seq);

  final String epoch;
  final int seq;

  @override
  String get _type => 'heartbeat';

  @override
  Json _fields() => {'epoch': epoch, 'seq': seq};
}

/// A player asking for a command. [command] stays JSON until the GM decodes
/// it, so a malformed command is refused rather than dropping the message.
final class Intent extends Message {
  const Intent(
      {required this.from, required this.requestId, required this.command});

  final PlayerId from;
  final String requestId;
  final Json command;

  @override
  String get _type => 'intent';

  @override
  Json _fields() =>
      {'from': from.value, 'requestId': requestId, 'command': command};
}

/// The GM refusing intent [requestId].
final class RefusalMessage extends Message {
  const RefusalMessage(
      {required this.to, required this.requestId, required this.reason});

  final PlayerId to;
  final String requestId;
  final Refusal reason;

  @override
  String get _type => 'refusal';

  @override
  Json _fields() =>
      {'to': to.value, 'requestId': requestId, 'reason': reason.name};
}

/// Who is connected, from Realtime presence.
typedef Presence = ({String player, bool gm, Point? cursor});

Json presenceToJson(Presence p) => {
      'player': p.player,
      'gm': p.gm,
      if (p.cursor != null) 'cursor': p.cursor!.toJson(),
    };

Presence presenceFromJson(Json json) => (
      player: json['player'] as String,
      gm: json['gm'] as bool,
      cursor: json['cursor'] == null ? null : pointFromJson(json['cursor']),
    );
