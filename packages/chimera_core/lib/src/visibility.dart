import 'actor.dart';
import 'entities.dart';
import 'ids.dart';
import 'patch.dart';
import 'scene.dart';

/// [scene] without what [viewer] may not see: hidden tokens, for players.
/// Tokens under fog are kept ("trust the table").
Scene visibleTo(Scene scene, Actor viewer) => switch (viewer) {
      Gm() => scene,
      Player() => Scene(
          settings: scene.settings,
          tokens: {
            for (final t in scene.tokens.values)
              if (!t.hidden) t.id: t,
          },
          fogOps: scene.fogOps,
        ),
    };

/// The part of [batch] that [viewer] receives, given the GM's scene [before]
/// the batch. Holds: `visibleTo(before).applyPatches(patchesFor(...))` equals
/// `visibleTo(before.applyPatches(batch))`.
///
/// Assumes at most one patch per entity, as [reduce] produces.
List<Patch> patchesFor(Scene before, List<Patch> batch, Actor viewer) {
  if (viewer is Gm) return batch;
  bool known(TokenId id) => before.tokens[id]?.hidden == false;
  return [
    for (final patch in batch)
      ...switch (patch) {
        // A token that becomes hidden must disappear for the player.
        Upsert(entity: Token(hidden: true, :final id)) =>
          known(id) ? [Delete.token(id)] : const [],
        // Never sent, so nothing to delete, and the id stays secret.
        Delete(kind: EntityKind.token, :final id) when !known(TokenId(id)) =>
          const [],
        _ => [patch],
      },
  ];
}
