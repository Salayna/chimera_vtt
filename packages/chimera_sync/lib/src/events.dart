import 'package:chimera_core/chimera_core.dart';

/// Something that happened at the table, made by the GM session from an
/// accepted command and sent to everyone. Logged events form the room's log,
/// its chat; token moves never become events.
sealed class TableEvent {
  const TableEvent(this.by, this.at, {this.gm = false, this.secret = false});

  /// Who did it: a player, or the GM's own id.
  final PlayerId by;

  /// [by] is the GM. Players don't otherwise know the GM's id.
  final bool gm;

  /// For the GM's eyes only: never sent to players.
  final bool secret;

  /// The GM's clock, in milliseconds since the Unix epoch.
  final int at;

  /// Whether it stays in the log, rather than only showing for a moment.
  bool get logged => true;

  Json _fields();
  String get _type;

  Json toJson() =>
      {
        'type': _type,
        'by': by.value,
        'at': at,
        if (gm) 'gm': true,
        if (secret) 'secret': true,
        ..._fields(),
      };

  static TableEvent fromJson(Json json) {
    final by = PlayerId(json['by'] as String);
    final at = json['at'] as int;
    final gm = json['gm'] as bool? ?? false;
    final secret = json['secret'] as bool? ?? false;
    return switch (json['type']) {
      'roll' => Roll(
          by,
          at,
          formula: json['formula'] as String,
          faces: [
            for (final term in json['faces'] as List)
              [for (final f in term as List) f as int],
          ],
          total: json['total'] as int,
          gm: gm,
          secret: secret,
        ),
      'chat' => Chat(by, at, json['text'] as String, gm: gm, secret: secret),
      'condition' => ConditionChange(
          by,
          at,
          token: json['token'] as String,
          condition: json['condition'] as String,
          value: json['value'] as int?,
          removed: json['removed'] as bool,
          gm: gm,
          secret: secret,
        ),
      'ping' => PingEvent(by, at, pointFromJson(json['point']), gm: gm),
      'action' => ActionEvent(
          by,
          at,
          character: json['character'] as String,
          action: json['action'] as String,
          dice: json['dice'] as String?,
          banded: json['banded'] as bool? ?? false,
          rolls: [
            for (final r in json['rolls'] as List? ?? const [])
              (
                faces: [
                  for (final term in (r as Json)['faces'] as List)
                    [for (final f in term as List) f as int],
                ],
                total: r['total'] as int,
                band: r['band'] as String?,
                text: r['text'] as String? ?? '',
              ),
          ],
          gm: gm,
        ),
      final type => throw FormatException('Unknown event: $type'),
    };
  }
}

/// A dice roll. [faces] holds each term's dice, empty for constants.
final class Roll extends TableEvent {
  const Roll(super.by, super.at,
      {required this.formula,
      required this.faces,
      required this.total,
      super.gm,
      super.secret});

  final String formula;
  final List<List<int>> faces;
  final int total;

  /// A player's own copy of their roll for the GM, without its result.
  bool get blind => faces.isEmpty;

  @override
  String get _type => 'roll';

  @override
  Json _fields() => {'formula': formula, 'faces': faces, 'total': total};
}

final class Chat extends TableEvent {
  const Chat(super.by, super.at, this.text, {super.gm, super.secret});

  final String text;

  @override
  String get _type => 'chat';

  @override
  Json _fields() => {'text': text};
}

/// A condition set on, changed on, or removed from a token. [token] is the
/// token's name at the time, or empty. Secret when the token is hidden.
final class ConditionChange extends TableEvent {
  const ConditionChange(super.by, super.at,
      {required this.token,
      required this.condition,
      required this.value,
      required this.removed,
      super.gm,
      super.secret});

  final String token;
  final String condition;
  final int? value;
  final bool removed;

  @override
  String get _type => 'condition';

  @override
  Json _fields() => {
        'token': token,
        'condition': condition,
        if (value != null) 'value': value,
        'removed': removed,
      };
}

/// A ping on the map: shown for a moment, never logged.
final class PingEvent extends TableEvent {
  const PingEvent(super.by, super.at, this.point, {super.gm});

  final Point point;

  @override
  bool get logged => false;

  @override
  String get _type => 'ping';

  @override
  Json _fields() => {'point': point.toJson()};
}

/// One roll of an action: each die's faces by term, the total, and the band
/// it fell in with what that does (null below every band).
typedef ActionRoll = ({List<List<int>> faces, int total, String? band, String text});

/// A character's action: what was used, by whom, and each roll in its band.
/// It changed nothing on the target; its owner applies what it says.
final class ActionEvent extends TableEvent {
  const ActionEvent(super.by, super.at,
      {required this.character,
      required this.action,
      this.dice,
      this.banded = false,
      this.rolls = const [],
      super.gm});

  /// The character's name at the time.
  final String character;
  final String action;
  final String? dice;

  /// Whether the action has bands, so a roll in none is a miss.
  final bool banded;
  final List<ActionRoll> rolls;

  @override
  String get _type => 'action';

  @override
  Json _fields() => {
        'character': character,
        'action': action,
        if (dice != null) 'dice': dice,
        if (banded) 'banded': true,
        if (rolls.isNotEmpty)
          'rolls': [
            for (final r in rolls)
              {
                'faces': r.faces,
                'total': r.total,
                if (r.band != null) 'band': r.band,
                if (r.text.isNotEmpty) 'text': r.text,
              },
          ],
      };
}
