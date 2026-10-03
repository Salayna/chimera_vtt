import 'dart:convert' show jsonEncode;
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
  // Players may move and mark tokens they own, roll, chat, ping and end
  // their own turn.
  // Everything else is GM-only.
  if (actor is Player &&
      command is! MoveToken &&
      command is! SetCondition &&
      command is! RemoveCondition &&
      command is! RollDice &&
      command is! Say &&
      command is! Ping &&
      command is! EndTurn &&
      command is! SetTracker &&
      command is! UpdateCharacter &&
      command is! RemoveCharacter &&
      command is! LinkCharacter &&
      command is! UseAction) {
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
        ? Accepted([
            Delete.token(id),
            // A token that leaves the map leaves the turn order.
            if (scene.initiative case final i?
                when i.entries.any((e) => e.token == id))
              Upsert(i.without(id)),
          ])
        : const Refused(Refusal.notFound),
    RemoveFogOp(:final id) => scene.fogOps.containsKey(id)
        ? Accepted([Delete(EntityKind.fogOp, id.value)])
        : const Refused(Refusal.notFound),
    PlaceRegion(:final region) => scene.regions.containsKey(region.id)
        ? const Refused(Refusal.duplicateId)
        : _validRegion(region),
    UpdateRegion(:final region) => !scene.regions.containsKey(region.id)
        ? const Refused(Refusal.notFound)
        : _validRegion(region),
    RemoveRegion(:final id) => scene.regions.containsKey(id)
        ? Accepted([Delete(EntityKind.region, id.value)])
        : const Refused(Refusal.notFound),
    SetInitiative(:final initiative) => _initiative(scene, initiative),
    EndInitiative() => scene.initiative == null
        ? const Refused(Refusal.notFound)
        : const Accepted([Delete(EntityKind.initiative, '')]),
    EndTurn() => _endTurn(scene, actor),
    UsePack(:final id, :final data) => _usePack(scene, id, data),
    SetTracker(:final id, :final name, :final value) =>
      _own(scene, actor, id, (t) => _setTracker(t, name, value)),
    UpdateCharacter(:final character) => _updateCharacter(scene, actor, character),
    UseAction(:final action, :final dice, :final times, :final bands)
        when action.trim().isEmpty ||
            action.length > 60 ||
            (dice != null && DiceFormula.tryParse(dice) == null) ||
            times < 1 ||
            times > UseAction.maxTimes ||
            bands.length > UseAction.maxBands ||
            bands.any((b) => b.name.length > 30 || b.text.length > 500) =>
      const Refused(Refusal.invalid),
    UseAction(:final character) => _updateCharacter(scene, actor, character),
    RemoveCharacter(:final id) => switch (scene.characters[id]) {
        null => const Refused(Refusal.notFound),
        Character(:final owner) when actor is! Player || actor.id != owner =>
          const Refused(Refusal.notOwner),
        _ => Accepted([
            Delete(EntityKind.character, id.value),
            for (final t in scene.tokens.values)
              if (t.character == id) Upsert(t.withCharacter(null)),
          ]),
      },
    LinkCharacter(token: final id, :final character) => _own(scene, actor, id, (t) {
        final c = scene.characters[character];
        if (character != null && c == null) return const Refused(Refusal.notFound);
        if (actor case Player(id: final player) when c != null && c.owner != player) {
          return const Refused(Refusal.notOwner);
        }
        return Accepted([Upsert(t.withCharacter(character))]);
      }),
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
  if (!_validTags({name: value}) ||
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

/// How many trackers a token holds, and their range.
const maxTrackers = 20;
const maxTrackerValue = 99999;

Outcome? _setTracker(Token token, String name, int? value) {
  if (value == null) {
    return token.trackers.containsKey(name)
        ? Accepted([Upsert(token.withTrackers({...token.trackers}..remove(name)))])
        : const Accepted([]);
  }
  if (!_validTags({name: null}) ||
      value.abs() > maxTrackerValue ||
      (!token.trackers.containsKey(name) && token.trackers.length >= maxTrackers)) {
    return null;
  }
  if (token.trackers[name] == value) return const Accepted([]);
  return Accepted([Upsert(token.withTrackers({...token.trackers, name: value}))]);
}

/// The settings name the pack; an installed one's file rides along, and a
/// built-in one needs none.
Outcome _usePack(Scene scene, String id, Json? data) {
  if (id.isEmpty || id.length > 40) return const Refused(Refusal.invalid);
  if (data != null &&
      (data['id'] != id || jsonEncode(data).length > ScenePack.maxBytes)) {
    return const Refused(Refusal.invalid);
  }
  return Accepted([
    Upsert(scene.settings.copyWith(pack: id)),
    if (data != null)
      Upsert(ScenePack(data))
    else if (scene.packFile != null)
      const Delete(EntityKind.pack, ''),
  ]);
}

/// How much of a character the room carries: its JSON, values included.
const maxCharacterBytes = 128 * 1024;

/// Only a character's owner writes it, and only for the scene's system:
/// the GM reads characters, never changes them.
Outcome _updateCharacter(Scene scene, Actor actor, Character character) {
  if (actor case Player(:final id) when id == character.owner) {
    final had = scene.characters[character.id];
    if (had != null && had.owner != character.owner) {
      return const Refused(Refusal.notOwner);
    }
    final name = character.name.trim();
    return name.isEmpty ||
            name.length > Character.maxName ||
            character.system != scene.settings.pack ||
            character.items.length > Character.maxItems ||
            character.items.map((i) => i.id).toSet().length != character.items.length ||
            jsonEncode(character.toJson()).length > maxCharacterBytes
        ? const Refused(Refusal.invalid)
        : Accepted([Upsert(character)]);
  }
  return const Refused(Refusal.notOwner);
}

/// Bounds for tags typed by people, on regions as on tokens.
const maxTags = 20;

bool _validTags(Map<String, int?> tags) =>
    tags.length <= maxTags &&
    tags.entries.every((t) =>
        t.key.trim().isNotEmpty &&
        t.key.trim() == t.key &&
        t.key.length <= maxConditionName &&
        (t.value == null || (t.value! >= 0 && t.value! <= 99)));

Outcome _validRegion(Region region) =>
    region.from.isFinite && region.to.isFinite && _validTags(region.tags)
        ? Accepted([Upsert(region)])
        : const Refused(Refusal.invalid);

/// A turn order must list tokens on the map, each once, sorted, with the
/// current one among them.
Outcome _initiative(Scene scene, Initiative initiative) {
  final tokens = [for (final e in initiative.entries) e.token];
  final sorted = [
    for (var i = 1; i < initiative.entries.length; i++)
      initiative.entries[i - 1].value >= initiative.entries[i].value,
  ].every((ok) => ok);
  final valid = initiative.round >= 1 &&
      sorted &&
      tokens.toSet().length == tokens.length &&
      tokens.every(scene.tokens.containsKey) &&
      initiative.entries.every((e) => e.value.abs() <= 999) &&
      (initiative.current == null || tokens.contains(initiative.current));
  return valid ? Accepted([Upsert(initiative)]) : const Refused(Refusal.invalid);
}

Outcome _endTurn(Scene scene, Actor actor) {
  final initiative = scene.initiative;
  if (initiative == null) return const Refused(Refusal.notFound);
  if (actor case Player(id: final player)) {
    final current = scene.tokens[initiative.current];
    if (current == null || current.hidden || current.owner != player) {
      return const Refused(Refusal.notOwner);
    }
  }
  return Accepted([Upsert(initiative.next())]);
}
