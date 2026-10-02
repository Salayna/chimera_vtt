import 'entities.dart';
import 'ids.dart';

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
