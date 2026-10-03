import 'entities.dart';
import 'geometry.dart';
import 'ids.dart';

/// A request to change the scene. Nothing changes state except a command.
sealed class Command {
  const Command();

  Json toJson();

  /// Throws on malformed input. Commands arrive from players, so callers
  /// must treat a throw as an invalid command.
  static Command fromJson(Json json) => switch (json['type']) {
        'updateSettings' =>
          UpdateSettings(Entity.fromJson(json['settings'] as Json) as SceneSettings),
        'placeToken' => PlaceToken(Entity.fromJson(json['token'] as Json) as Token),
        'updateToken' =>
          UpdateToken(Entity.fromJson(json['token'] as Json) as Token),
        'moveToken' =>
          MoveToken(TokenId(json['id'] as String), pointFromJson(json['to'])),
        'assignOwner' => AssignOwner(TokenId(json['id'] as String),
            json['owner'] == null ? null : PlayerId(json['owner'] as String)),
        'setTokenHidden' =>
          SetTokenHidden(TokenId(json['id'] as String), json['hidden'] as bool),
        'removeToken' => RemoveToken(TokenId(json['id'] as String)),
        'addFogOp' => AddFogOp(
            FogOpId(json['id'] as String),
            FogMode.values.byName(json['mode'] as String),
            FogShape.fromJson(json['shape'] as Json),
          ),
        'removeFogOp' => RemoveFogOp(FogOpId(json['id'] as String)),
        'setCondition' => SetCondition(TokenId(json['id'] as String),
            json['name'] as String, json['value'] as int?),
        'removeCondition' => RemoveCondition(
            TokenId(json['id'] as String), json['name'] as String),
        'rollDice' => RollDice(json['formula'] as String,
            secret: json['secret'] as bool? ?? false),
        'say' => Say(json['text'] as String),
        'ping' => Ping(pointFromJson(json['at'])),
        'placeRegion' =>
          PlaceRegion(Entity.fromJson(json['region'] as Json) as Region),
        'updateRegion' =>
          UpdateRegion(Entity.fromJson(json['region'] as Json) as Region),
        'removeRegion' => RemoveRegion(RegionId(json['id'] as String)),
        'setInitiative' => SetInitiative(
            Entity.fromJson(json['initiative'] as Json) as Initiative),
        'endInitiative' => const EndInitiative(),
        'endTurn' => const EndTurn(),
        final type => throw FormatException('Unknown command: $type'),
      };
}

final class UpdateSettings extends Command {
  const UpdateSettings(this.settings);

  final SceneSettings settings;

  @override
  Json toJson() => {'type': 'updateSettings', 'settings': settings.toJson()};
}

/// Carries the whole token, id included: the GM session mints the id with
/// [newId] so the reducer stays pure.
final class PlaceToken extends Command {
  const PlaceToken(this.token);

  final Token token;

  @override
  Json toJson() => {'type': 'placeToken', 'token': token.toJson()};
}

/// Replaces a token's fields (GM only): image, name, size and the rest.
final class UpdateToken extends Command {
  const UpdateToken(this.token);

  final Token token;

  @override
  Json toJson() => {'type': 'updateToken', 'token': token.toJson()};
}

final class MoveToken extends Command {
  const MoveToken(this.id, this.to);

  final TokenId id;
  final Point to;

  @override
  Json toJson() => {'type': 'moveToken', 'id': id.value, 'to': to.toJson()};
}

final class AssignOwner extends Command {
  const AssignOwner(this.id, this.owner);

  final TokenId id;
  final PlayerId? owner;

  @override
  Json toJson() => {
        'type': 'assignOwner',
        'id': id.value,
        if (owner != null) 'owner': owner!.value,
      };
}

final class SetTokenHidden extends Command {
  const SetTokenHidden(this.id, this.hidden);

  final TokenId id;
  final bool hidden;

  @override
  Json toJson() => {'type': 'setTokenHidden', 'id': id.value, 'hidden': hidden};
}

final class RemoveToken extends Command {
  const RemoveToken(this.id);

  final TokenId id;

  @override
  Json toJson() => {'type': 'removeToken', 'id': id.value};
}

/// The reducer assigns the op's order.
final class AddFogOp extends Command {
  const AddFogOp(this.id, this.mode, this.shape);

  final FogOpId id;
  final FogMode mode;
  final FogShape shape;

  @override
  Json toJson() => {
        'type': 'addFogOp',
        'id': id.value,
        'mode': mode.name,
        'shape': shape.toJson(),
      };
}

/// Takes one fog op away, as if it had never been drawn.
final class RemoveFogOp extends Command {
  const RemoveFogOp(this.id);

  final FogOpId id;

  @override
  Json toJson() => {'type': 'removeFogOp', 'id': id.value};
}

/// Adds a condition to a token, or changes its value. Players may, on their
/// own tokens.
final class SetCondition extends Command {
  const SetCondition(this.id, this.name, [this.value]);

  final TokenId id;
  final String name;
  final int? value;

  @override
  Json toJson() => {
        'type': 'setCondition',
        'id': id.value,
        'name': name,
        if (value != null) 'value': value,
      };
}

final class RemoveCondition extends Command {
  const RemoveCondition(this.id, this.name);

  final TokenId id;
  final String name;

  @override
  Json toJson() => {'type': 'removeCondition', 'id': id.value, 'name': name};
}

/// Carries the whole region, id included, minted like a token's.
final class PlaceRegion extends Command {
  const PlaceRegion(this.region);

  final Region region;

  @override
  Json toJson() => {'type': 'placeRegion', 'region': region.toJson()};
}

/// Replaces a region: its tags, area or hidden flag.
final class UpdateRegion extends Command {
  const UpdateRegion(this.region);

  final Region region;

  @override
  Json toJson() => {'type': 'updateRegion', 'region': region.toJson()};
}

final class RemoveRegion extends Command {
  const RemoveRegion(this.id);

  final RegionId id;

  @override
  Json toJson() => {'type': 'removeRegion', 'id': id.value};
}

/// Starts or changes the turn order: who is in it, their values, the round
/// and whose turn it is. The GM's session rolls the values.
final class SetInitiative extends Command {
  const SetInitiative(this.initiative);

  final Initiative initiative;

  @override
  Json toJson() => {'type': 'setInitiative', 'initiative': initiative.toJson()};
}

/// Ends the fight: the turn order goes.
final class EndInitiative extends Command {
  const EndInitiative();

  @override
  Json toJson() => {'type': 'endInitiative'};
}

/// Passes the turn to the next in the order. Players may, on their own
/// token's turn.
final class EndTurn extends Command {
  const EndTurn();

  @override
  Json toJson() => {'type': 'endTurn'};
}

/// The following commands change nothing in the scene: the GM session turns
/// them into events for the log (and, for a ping, the map).

/// The GM rolls, so players can't pick their results.
final class RollDice extends Command {
  const RollDice(this.formula, {this.secret = false});

  /// Checked with [DiceFormula.tryParse].
  final String formula;

  /// GM only: the roll is logged for the GM alone.
  final bool secret;

  @override
  Json toJson() => {
        'type': 'rollDice',
        'formula': formula,
        if (secret) 'secret': true,
      };
}

/// A chat message.
final class Say extends Command {
  const Say(this.text);

  static const maxLength = 500;

  final String text;

  @override
  Json toJson() => {'type': 'say', 'text': text};
}

/// Draws everyone's eye to a point on the map for a moment.
final class Ping extends Command {
  const Ping(this.at);

  final Point at;

  @override
  Json toJson() => {'type': 'ping', 'at': at.toJson()};
}
