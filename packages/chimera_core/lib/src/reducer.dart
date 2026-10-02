import 'dart:math' as math;

import 'actor.dart';
import 'commands.dart';
import 'entities.dart';
import 'geometry.dart';
import 'ids.dart';
import 'patch.dart';
import 'scene.dart';

/// Why the reducer rejected a command.
enum Refusal { notFound, notOwner, gmOnly, invalid, duplicateId }

/// What [reduce] returns: patches to apply, or a refusal.
sealed class Outcome {
  const Outcome();
}

final class Accepted extends Outcome {
  const Accepted(this.patches);

  /// At most one patch per entity.
  final List<Patch> patches;
}

final class Refused extends Outcome {
  const Refused(this.reason);

  final Refusal reason;
}

/// Checks [command] against [scene] and returns the patches it produces.
/// Pure: it changes no state itself.
Outcome reduce(Scene scene, Actor actor, Command command) {
  // Players may only move tokens they own. Everything else is GM-only.
  if (actor is Player && command is! MoveToken) {
    return const Refused(Refusal.gmOnly);
  }
  return switch (command) {
    UpdateSettings(:final settings) => Accepted([Upsert(settings)]),
    PlaceToken(:final token) => scene.tokens.containsKey(token.id)
        ? const Refused(Refusal.duplicateId)
        : Accepted([Upsert(token)]),
    MoveToken(:final id, :final to) => _move(scene, actor, id, to),
    AssignOwner(:final id, :final owner) =>
      _editToken(scene, id, (t) => t.withOwner(owner)),
    SetTokenHidden(:final id, :final hidden) =>
      _editToken(scene, id, (t) => t.withHidden(hidden)),
    RemoveToken(:final id) => scene.tokens.containsKey(id)
        ? Accepted([Delete.token(id)])
        : const Refused(Refusal.notFound),
    AddFogOp(:final id, :final mode, :final shape) => scene.fogOps
            .containsKey(id)
        ? const Refused(Refusal.duplicateId)
        : Accepted([
            Upsert(FogOp(
              id: id,
              order: scene.fogOps.values.map((f) => f.order).fold(0, math.max) +
                  1,
              mode: mode,
              shape: shape,
            )),
          ]),
  };
}

Outcome _move(Scene scene, Actor actor, TokenId id, Point to) {
  final token = scene.tokens[id];
  // A hidden token doesn't exist for players: answer notFound, leak nothing.
  if (token == null || (actor is Player && token.hidden)) {
    return const Refused(Refusal.notFound);
  }
  if (actor case Player(id: final player) when token.owner != player) {
    return const Refused(Refusal.notOwner);
  }
  // Player input crosses a trust boundary, and NaN would break every client.
  if (!to.isFinite) return const Refused(Refusal.invalid);
  return Accepted([Upsert(token.moveTo(to))]);
}

Outcome _editToken(Scene scene, TokenId id, Token Function(Token) edit) {
  final token = scene.tokens[id];
  return token == null
      ? const Refused(Refusal.notFound)
      : Accepted([Upsert(edit(token))]);
}
