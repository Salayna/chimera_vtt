import 'entities.dart';
import 'ids.dart';
import 'scene.dart';

/// One change to one entity.
sealed class Patch {
  const Patch();

  Json toJson();

  static Patch fromJson(Json json) => switch (json['op']) {
        'upsert' => Upsert(Entity.fromJson(json['entity'] as Json)),
        'delete' => Delete(EntityKind.values.byName(json['kind'] as String),
            json['id'] as String),
        final op => throw FormatException('Unknown patch op: $op'),
      };
}

/// Create or replace the whole entity.
final class Upsert extends Patch {
  const Upsert(this.entity);

  final Entity entity;

  @override
  Json toJson() => {'op': 'upsert', 'entity': entity.toJson()};
}

/// Remove an entity. Ids are erased to [String] at runtime, so the kind
/// says which table [id] belongs to.
final class Delete extends Patch {
  const Delete(this.kind, this.id);

  Delete.token(TokenId id) : this(EntityKind.token, id.value);

  final EntityKind kind;
  final String id;

  @override
  Json toJson() => {'op': 'delete', 'kind': kind.name, 'id': id};
}

/// The patches that turn `before.applyPatches(batch)` back into [before]:
/// each entity's old value, or a delete if the batch created it.
///
/// Assumes at most one patch per entity, as [reduce] produces.
List<Patch> invert(Scene before, List<Patch> batch) => [
      for (final patch in batch)
        switch (_old(before, patch)) {
          final Entity old => Upsert(old),
          null => switch (patch) {
              Upsert(:final entity) => Delete(entity.kind, _id(entity)),
              // Deleting what didn't exist: nothing to restore.
              Delete() => patch,
            },
        },
    ];

Entity? _old(Scene before, Patch patch) {
  final (kind, id) = switch (patch) {
    Upsert(:final entity) => (entity.kind, _id(entity)),
    Delete(:final kind, :final id) => (kind, id),
  };
  return switch (kind) {
    EntityKind.settings => before.settings,
    EntityKind.token => before.tokens[TokenId(id)],
    EntityKind.fogOp => before.fogOps[FogOpId(id)],
  };
}

String _id(Entity entity) => switch (entity) {
      SceneSettings() => '',
      Token(:final id) => id.value,
      FogOp(:final id) => id.value,
    };
