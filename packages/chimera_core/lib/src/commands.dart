import 'entities.dart';
import 'geometry.dart';
import 'ids.dart';

/// A request to change the scene. Nothing changes state except a command.
sealed class Command {
  const Command();
}

final class UpdateSettings extends Command {
  const UpdateSettings(this.settings);

  final SceneSettings settings;
}

/// Carries the whole token, id included: the GM session mints the id with
/// [newId] so the reducer stays pure.
final class PlaceToken extends Command {
  const PlaceToken(this.token);

  final Token token;
}

final class MoveToken extends Command {
  const MoveToken(this.id, this.to);

  final TokenId id;
  final Point to;
}

final class AssignOwner extends Command {
  const AssignOwner(this.id, this.owner);

  final TokenId id;
  final PlayerId? owner;
}

final class SetTokenHidden extends Command {
  const SetTokenHidden(this.id, this.hidden);

  final TokenId id;
  final bool hidden;
}

final class RemoveToken extends Command {
  const RemoveToken(this.id);

  final TokenId id;
}

/// The reducer assigns the op's order.
final class AddFogOp extends Command {
  const AddFogOp(this.id, this.mode, this.shape);

  final FogOpId id;
  final FogMode mode;
  final FogShape shape;
}
