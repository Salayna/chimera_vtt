import 'dart:math' as math;

import 'actor.dart';
import 'commands.dart';
import 'dice.dart';
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
  // Players may move and mark tokens they own, roll, chat and ping.
  // Everything else is GM-only.
  if (actor is Player &&
      command is! MoveToken &&
      command is! SetCondition &&
      command is! RemoveCondition &&
      command is! RollDice &&
      command is! Say &&
      command is! Ping) {
    return const Refused(Refusal.gmOnly);
  }
  return switch (command) {
    UpdateSettings(:final settings) => _settings(scene, settings),
    PlaceToken(:final token) => scene.tokens.containsKey(token.id)
        ? const Refused(Refusal.duplicateId)
        : Accepted([Upsert(token)]),
    UpdateToken(:final token) => !scene.tokens.containsKey(token.id)
        ? const Refused(Refusal.notFound)
        : !token.position.isFinite || !(token.size > 0 && token.size.isFinite)
            ? const Refused(Refusal.invalid)
            : Accepted([Upsert(token)]),
    // Player input crosses a trust boundary, and NaN would break every
    // client.
    MoveToken(:final id, :final to) => _own(scene, actor, id,
        (t) => to.isFinite ? Accepted([Upsert(t.moveTo(to))]) : null),
    SetCondition(:final id, :final name, :final value) =>
      _own(scene, actor, id, (t) => _setCondition(t, name, value)),
    RemoveCondition(:final id, :final name) => _own(
        scene,
        actor,
        id,
        (t) => t.conditions.containsKey(name)
            ? Accepted([
                Upsert(t.withConditions({...t.conditions}..remove(name))),
              ])
            : const Refused(Refusal.notFound)),
    RollDice(:final secret) when secret && actor is Player =>
      const Refused(Refusal.gmOnly),
    RollDice(:final formula) => DiceFormula.tryParse(formula) == null
        ? const Refused(Refusal.invalid)
        : const Accepted([]),
    Say(:final text) =>
      text.trim().isEmpty || text.length > Say.maxLength
          ? const Refused(Refusal.invalid)
          : const Accepted([]),
    Ping(:final at) =>
      at.isFinite ? const Accepted([]) : const Refused(Refusal.invalid),
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

/// A new cell size rescales every token with it, so a 2×2 token stays 2×2.
Outcome _settings(Scene scene, SceneSettings settings) {
  final from = scene.settings.grid.cellSize;
  final to = settings.grid.cellSize;
  if (!(to > 0 && to.isFinite)) return const Refused(Refusal.invalid);
  return Accepted([
    Upsert(settings),
    if (to != from)
      for (final t in scene.tokens.values)
        Upsert(t.copyWith(size: t.size * to / from)),
  ]);
}

/// Edits a token [actor] may change: any for the GM, their own for a
/// player. A null from [edit] means invalid input.
Outcome _own(
    Scene scene, Actor actor, TokenId id, Outcome? Function(Token) edit) {
  final token = scene.tokens[id];
  // A hidden token doesn't exist for players: answer notFound, leak nothing.
  if (token == null || (actor is Player && token.hidden)) {
    return const Refused(Refusal.notFound);
  }
  if (actor case Player(id: final player) when token.owner != player) {
    return const Refused(Refusal.notOwner);
  }
  return edit(token) ?? const Refused(Refusal.invalid);
}

/// Condition names are typed by people and shown to everyone: bounded.
const maxConditionName = 30;
const maxConditions = 20;

Outcome? _setCondition(Token token, String name, int? value) {
  final had = token.conditions.containsKey(name);
  if (name.trim().isEmpty ||
      name.trim() != name ||
      name.length > maxConditionName ||
      (value != null && (value < 0 || value > 99)) ||
      (!had && token.conditions.length >= maxConditions)) {
    return null;
  }
  if (had && token.conditions[name] == value) return const Accepted([]);
  return Accepted([
    Upsert(token.withConditions({...token.conditions, name: value})),
  ]);
}

Outcome _editToken(Scene scene, TokenId id, Token Function(Token) edit) {
  final token = scene.tokens[id];
  return token == null
      ? const Refused(Refusal.notFound)
      : Accepted([Upsert(edit(token))]);
}
