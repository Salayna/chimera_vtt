import 'pack.dart';
import 'topology.dart';

/// A system preset from Atlas VTT (its settings' `userPresets` entries) as
/// a pack. Atlas conditions become conditions, or region tags when marked
/// `sector`; its grid defaults set the unit, diagonals and range bands.
/// Atlas widgets (scene clocks and counters) have no equivalent and are
/// left out. Throws a [FormatException] for a preset it can't read.
SystemPack packFromAtlasPreset(Json preset) {
  final rules = preset['rules'];
  final grid = rules is Json ? rules['gridDefaults'] : null;
  if (rules is! Json || grid is! Json) {
    throw const FormatException('Not an Atlas preset: no rules.gridDefaults');
  }
  final abstract = grid['measurementMode'] == 'abstract';
  final distance = (grid['unitDistance'] as num? ?? 1).toDouble();
  // In abstract mode Atlas counts squares; in metric mode, units.
  final perStep = abstract ? 1.0 : distance;
  return SystemPack.fromJson({
    'id': _id(preset['id'] as String? ?? preset['name'] as String? ?? 'atlas'),
    'name': preset['name'],
    'diagonal': switch (grid['diagonalRule']) {
      'alternating' => DiagonalRule.alternating.name,
      _ => DiagonalRule.chebyshev.name, // equidistant; euclidean has no grid rule.
    },
    'unit': abstract
        ? 'square'
        : switch (grid['unitType']) {
            'feet' => 'ft',
            'meters' => 'm',
            'yards' => 'yd',
            _ => 'unit',
          },
    'unitsPerStep': perStep,
    'bands': [
      for (final b in grid['abstractRangeBands'] as List? ?? const [])
        {'name': (b as Json)['name'], 'max': (b['maxSquares'] as num) * perStep},
      // Atlas reports anything past the last band by distance; a pack names it.
      if ((grid['abstractRangeBands'] as List? ?? const []).isNotEmpty)
        {'name': 'Beyond'},
    ],
    'tags': [
      for (final c in rules['conditions'] as List? ?? const [])
        {
          'name': (c as Json)['name'],
          if (c['sector'] == true) 'sector': true else 'condition': true,
          if (c['valued'] == true) 'valued': true,
          if (c['color'] case final String color) 'color': color,
        },
    ],
  });
}

/// A pack id from an Atlas id or name: "Solaris Arcanum" → solaris-arcanum.
String _id(String from) {
  final id = from
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return id.isEmpty ? 'atlas' : (id.length > 40 ? id.substring(0, 40) : id);
}
