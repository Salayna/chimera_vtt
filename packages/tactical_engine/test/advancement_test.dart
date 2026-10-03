import 'package:tactical_engine/tactical_engine.dart';
import 'package:test/test.dart';

Json pack(List<Json> nodes, {List<Json> fields = const []}) => {
      'id': 'x',
      'name': 'X',
      'unit': 'ft',
      'compendium': {
        'kinds': [
          {'name': 'Talent', 'fields': <Json>[]},
        ],
        'entries': [
          {'kind': 'Talent', 'name': 'Favored Weapon'},
        ],
      },
      'advancement': {'name': 'Constellation', 'field': 'CP', 'nodes': nodes},
      'sheet': {
        'sections': [
          {
            'title': 'S',
            'fields': [
              {'name': 'CP'},
              {'name': 'STR', 'max': 10},
              ...fields,
            ],
          },
        ],
      },
    };

String? error(Json json) {
  try {
    SystemPack.fromJson(json);
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}

void main() {
  test('a constellation round-trips; node groups count like items', () {
    final p = SystemPack.fromJson(pack([
      {'name': 'Origin', 'cost': 0, 'x': 0, 'y': 0},
      {'name': 'Duelist', 'group': 'Archetype', 'requires': ['Origin'], 'condition': 'archetypes < 3'},
      {'name': 'Might', 'requires': ['Origin'], 'adds': {'STR': 1}, 'x': 1, 'y': 1},
      {'name': 'Favored', 'requiresAll': ['Duelist', 'Might'], 'items': ['Favored Weapon']},
    ], fields: [
      {'name': 'archetypes', 'type': 'computed', 'formula': 'count("Archetype")'},
    ]));
    expect(SystemPack.fromJson(p.toJson()).toJson(), p.toJson());
    expect(p.advancements.single.groups, {'Archetype'});
    final v = SheetValues(p.sheet!, const {}, groups: ['Archetype', 'Archetype']);
    expect(v['archetypes'], 2);
  });

  test('a bad advancement is refused with the reason', () {
    expect(error(pack([{'name': 'A', 'requires': ['B']}])), contains('requires "B"'));
    expect(error(pack([{'name': 'A'}, {'name': 'A'}])), contains('Two nodes'));
    expect(error(pack([{'name': 'A', 'condition': 'CP + 1'}])), contains('not a boolean'));
    expect(error(pack([{'name': 'A', 'condition': 'count("Class") < 1'}])), contains('no kind or group "Class"'));
    expect(error(pack([{'name': 'A', 'adds': {'notes': 1}}], fields: [{'name': 'notes', 'type': 'text'}])),
        contains("isn't a number"));
    expect(error(pack([{'name': 'A', 'items': ['Nothing']}])), contains("isn't an entry"));
    expect(error(pack([{'name': 'A', 'cost': -1}])), contains('cost'));
    expect(error({...pack(const []), 'advancement': {'name': 'L', 'field': 'XP', 'nodes': <Json>[]}}),
        contains('spends "XP"'));
  });

  test('a module may have several tracks; node names are unique across them', () {
    Json track(String name, List<Json> nodes) => {'name': name, 'field': 'CP', 'nodes': nodes};
    final two = SystemPack.fromJson({
      ...pack(const []),
      'advancement': [
        track('Threat Level', [
          {'name': 'Alpha 1', 'cost': 0, 'adds': {'CP': 1}},
        ]),
        track('Archetypes', [
          {'name': 'Duelist 1', 'group': 'Archetype'},
        ]),
      ],
    });
    expect([for (final a in two.advancements) a.name], ['Threat Level', 'Archetypes']);
    expect(two.trackOf('Duelist 1')!.name, 'Archetypes');
    expect(SystemPack.fromJson(two.toJson()).advancements.length, 2);
    expect(
        error({
          ...pack(const []),
          'advancement': [
            track('A', [{'name': 'X'}]),
            track('B', [{'name': 'X'}]),
          ],
        }),
        contains('Two nodes are called "X"'));
  });
}
