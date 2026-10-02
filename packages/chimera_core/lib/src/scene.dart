import 'entities.dart';
import 'ids.dart';
import 'patch.dart';

/// One map and everything on it. Immutable: [applyPatches] returns a new one.
final class Scene {
  Scene({
    required this.settings,
    Map<TokenId, Token> tokens = const {},
    Map<FogOpId, FogOp> fogOps = const {},
  })  : tokens = Map.unmodifiable(tokens),
        fogOps = Map.unmodifiable(fogOps);

  /// Version of the save format, checked before any entity is parsed.
  static const format = 1;

  final SceneSettings settings;
  final Map<TokenId, Token> tokens;
  final Map<FogOpId, FogOp> fogOps;

  /// Fog ops in drawing order.
  List<FogOp> get fogInOrder =>
      fogOps.values.toList()..sort((a, b) => a.order.compareTo(b.order));

  /// Every entity in a canonical order, so equal scenes serialize identically.
  List<Entity> get entities => [
        settings,
        ...(tokens.values.toList()
          ..sort((a, b) => a.id.value.compareTo(b.id.value))),
        ...fogInOrder,
      ];

  /// The only way a scene changes, for the GM and players alike.
  ///
  /// Entities are keyed by their own id, so `tokens[k].id == k` always holds.
  /// Tables the patches don't touch are reused as is, so views can skip
  /// repainting a layer with `identical(old.fogOps, new.fogOps)`.
  Scene applyPatches(Iterable<Patch> patches) {
    var settings = this.settings;
    Map<TokenId, Token>? tokens;
    Map<FogOpId, FogOp>? fogOps;
    for (final patch in patches) {
      switch (patch) {
        case Upsert(entity: final SceneSettings s):
          settings = s;
        case Upsert(entity: final Token t):
          (tokens ??= {...this.tokens})[t.id] = t;
        case Upsert(entity: final FogOp f):
          (fogOps ??= {...this.fogOps})[f.id] = f;
        case Delete(kind: EntityKind.token, :final id):
          (tokens ??= {...this.tokens}).remove(TokenId(id));
        case Delete(kind: EntityKind.fogOp, :final id):
          (fogOps ??= {...this.fogOps}).remove(FogOpId(id));
        case Delete(kind: EntityKind.settings):
          throw ArgumentError('Scene settings cannot be deleted');
      }
    }
    return Scene._(
      settings,
      tokens == null ? this.tokens : Map.unmodifiable(tokens),
      fogOps == null ? this.fogOps : Map.unmodifiable(fogOps),
    );
  }

  Scene._(this.settings, this.tokens, this.fogOps);

  Json toJson() => {
        'format': format,
        'entities': [for (final e in entities) e.toJson()],
      };

  factory Scene.fromJson(Json json) {
    if (json['format'] != format) {
      throw FormatException('Unsupported scene format: ${json['format']}');
    }
    final entities = [
      for (final e in json['entities'] as List) Entity.fromJson(e as Json),
    ];
    final settings = entities.whereType<SceneSettings>().singleOrNull ??
        (throw const FormatException('A scene needs exactly one settings'));
    return Scene(settings: settings)
        .applyPatches([for (final e in entities) Upsert(e)]);
  }
}
