import 'entities.dart' show Json;
import 'ids.dart';

/// A player's character, made on their home for one system and owned by
/// them. Its sheet is its values by field name; what they mean is the
/// system pack's, which core doesn't read: the app cleans them against the
/// pack's sheet.
final class Character {
  Character({
    required this.id,
    required this.owner,
    required this.system,
    required this.name,
    Map<String, Object> values = const {},
  }) : values = Map.unmodifiable(values);

  static const maxName = 60;

  final CharacterId id;
  final PlayerId owner;

  /// The id of the system pack it's played with.
  final String system;
  final String name;

  /// Its sheet: numbers, texts and booleans by field name.
  final Map<String, Object> values;

  Character copyWith({String? name, Map<String, Object>? values}) => Character(
        id: id,
        owner: owner,
        system: system,
        name: name ?? this.name,
        values: values ?? this.values,
      );

  /// The sheet, as the `characters` table's `sheet` column holds it.
  Json get sheet => {'values': values};

  Json toJson() => {
        'id': id.value,
        'owner': owner.value,
        'system': system,
        'name': name,
        'sheet': sheet,
      };

  /// Throws on malformed input; the values' meaning isn't checked here.
  factory Character.fromJson(Json json) => Character(
        id: CharacterId(json['id'] as String),
        owner: PlayerId(json['owner'] as String),
        system: json['system'] as String,
        name: json['name'] as String,
        values: {
          for (final MapEntry(:key, :value)
              in ((json['sheet'] as Map?)?['values'] as Map? ?? const {}).entries)
            if (value is num || value is bool || value is String) key as String: value as Object,
        },
      );
}
