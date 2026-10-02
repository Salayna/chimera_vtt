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
