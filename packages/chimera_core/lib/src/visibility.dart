import 'actor.dart';
import 'entities.dart';
import 'ids.dart';
import 'patch.dart';
import 'scene.dart';

/// [scene] without what [viewer] may not see: hidden tokens and regions,
/// and hidden tokens' places in the turn order, for players. Tokens under
/// fog are kept ("trust the table").
Scene visibleTo(Scene scene, Actor viewer) => switch (viewer) {
      Gm() => scene,
      Player() => Scene(
          settings: scene.settings,
          tokens: {
            for (final t in scene.tokens.values)
              if (!t.hidden) t.id: _forPlayers(t),
          },
          fogOps: scene.fogOps,
          regions: {
            for (final r in scene.regions.values)
              if (!r.hidden) r.id: r,
          },
          initiative: switch (scene.initiative) {
            final i? => _initiativeFor(i, scene),
            null => null,
          },
          packFile: scene.packFile,
        ),
    };

/// [token] as players see it: the GM's tokens (no owner) keep their
/// trackers to the GM, so a threat's wounds stay secret.
// ponytail: by role, as batches are shared; a player can see another
// player's token's trackers.
Token _forPlayers(Token token) =>
    token.owner == null && token.trackers.isNotEmpty ? token.withTrackers(const {}) : token;

/// [initiative] as players see it: no hidden token's entry, and no turn
/// while it's a hidden token's.
Initiative _initiativeFor(Initiative initiative, Scene scene) {
  bool shown(TokenId id) => scene.tokens[id]?.hidden == false;
  return Initiative(
    round: initiative.round,
    current: switch (initiative.current) {
      final c? when shown(c) => c,
      _ => null,
    },
    entries: [
      for (final e in initiative.entries)
        if (shown(e.token)) e,
    ],
  );
}

/// The part of [batch] that [viewer] receives, given the GM's scene [before]
/// the batch. Holds: `visibleTo(before).applyPatches(patchesFor(...))` equals
/// `visibleTo(before.applyPatches(batch))`.
///
/// Assumes at most one patch per entity, as [reduce] produces.
List<Patch> patchesFor(Scene before, List<Patch> batch, Actor viewer) {
  if (viewer is Gm) return batch;
  bool known(TokenId id) => before.tokens[id]?.hidden == false;
  bool knownRegion(RegionId id) => before.regions[id]?.hidden == false;
  final after = before.applyPatches(batch);
  // A token hidden or shown changes who the turn order lists.
  final tokensShift = batch.any((p) => switch (p) {
        Upsert(entity: Token(:final id, :final hidden)) =>
          before.tokens[id]?.hidden != hidden,
        Delete(kind: EntityKind.token) => true,
        _ => false,
      });
  final initiativeSent = batch.any((p) => switch (p) {
        Upsert(entity: Initiative()) || Delete(kind: EntityKind.initiative) => true,
        _ => false,
      });
  return [
    for (final patch in batch)
      ...switch (patch) {
        // A token that becomes hidden must disappear for the player.
        Upsert(entity: Token(hidden: true, :final id)) =>
          known(id) ? [Delete.token(id)] : const [],
        // Never sent, so nothing to delete, and the id stays secret.
        Delete(kind: EntityKind.token, :final id) when !known(TokenId(id)) =>
          const [],
        Upsert(entity: Region(hidden: true, :final id)) => knownRegion(id)
            ? [Delete(EntityKind.region, id.value)]
            : const [],
        Delete(kind: EntityKind.region, :final id)
            when !knownRegion(RegionId(id)) =>
          const [],
        Upsert(entity: final Initiative i) => [Upsert(_initiativeFor(i, after))],
        Upsert(entity: final Token t) => [Upsert(_forPlayers(t))],
        _ => [patch],
      },
    if (tokensShift && !initiativeSent && after.initiative != null)
      Upsert(_initiativeFor(after.initiative!, after)),
  ];
}
