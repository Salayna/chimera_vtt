import 'dart:convert';

import 'package:tactical_engine/tactical_engine.dart';
import 'package:test/test.dart';

// Test fixtures shaped like the plan's three example packs. The numbers
// illustrate the engine, they aren't the systems' official rules.
final solaris = SystemPack.fromJson(jsonDecode('''
{
  "name": "Solaris Arcanum",
  "topology": "square",
  "diagonal": "chebyshev",
  "unit": "sector",
  "bands": [
    {"name": "Point Blank", "max": 0},
    {"name": "Adjacent", "max": 1},
    {"name": "Medium", "max": 10},
    {"name": "Far"}
  ],
  "tags": [
    {"name": "Darkness", "sector": true,
     "effects": [{"type": "roll", "edge": -1, "scaled": true}]},
    {"name": "Line of Sight Breaker", "sector": true,
     "effects": [{"type": "blocksSight"}]},
    {"name": "Difficult Terrain", "sector": true,
     "effects": [{"type": "entryCheck", "check": "Traversal"}]},
    {"name": "Cramped", "sector": true,
     "effects": [{"type": "occupantLimit", "max": 1}]}
  ]
}
''') as Json);

final dnd = SystemPack(
  name: 'D&D 5e',
  diagonal: DiagonalRule.alternating,
  unit: 'ft',
  unitsPerStep: 5,
  tags: [
    const TagDef('Difficult Terrain', effects: [MoveCost(2)]),
  ],
);

final zones = SystemPack(
  name: 'Zone game',
  topology: TopologyKind.gridless,
  unit: 'zone',
);

const cell = 100.0;
Tag tag(String name, [int? value]) => (name: name, value: value);

void main() {
  group('Solaris: sectors on a chebyshev grid', () {
    final grid = solaris.topologyFor(cellSize: cell) as SquareGrid;
    Point at(int col, int row) => grid.centerOf((col: col, row: row));
    Region sector(int col, int row, List<Tag> tags) => Region(
        id: '$col,$row', shape: grid.shapeOf((col: col, row: row)), tags: tags);

    final engine = TacticalEngine(pack: solaris, topology: grid, regions: [
      sector(1, 0, [tag('Line of Sight Breaker')]),
      sector(3, 3, [tag('Darkness', 2), tag('Difficult Terrain')]),
      sector(5, 5, [tag('Cramped')]),
    ]);

    test('range bands count sectors', () {
      String? band(Point b) => engine.measure(at(0, 0), b).band?.name;
      expect(band(at(0, 0)), 'Point Blank');
      expect(band(at(1, 1)), 'Adjacent');
      expect(band(at(5, 3)), 'Medium');
      expect(band(at(11, 0)), 'Far');
      expect(engine.measure(at(0, 0), at(5, 3)).value, 5);
    });

    test('a breaker blocks sight through it, not past its corner or into it',
        () {
      expect(engine.canSee(at(0, 0), at(2, 0)), isFalse);
      expect(engine.canSee(at(0, 1), at(2, 1)), isTrue);
      expect(engine.canSee(at(0, 0), at(2, 2)), isTrue); // grazes its corner
      expect(engine.canSee(at(0, 1), at(2, -1)), isFalse); // through its centre
      expect(engine.canSee(at(0, 0), at(1, 0)), isTrue); // into it
    });

    test('tag effects scale with the tag value', () {
      final effects = engine.effectsAt(at(3, 3), conditions: [tag('Prone')]);
      final edges = [
        for (final (:effect, :tag) in effects)
          if (effect is RollModifier) effect.edgeFor(tag),
      ];
      expect(edges, [-2]);
      expect(engine.tagsAt(at(3, 3), conditions: [tag('Prone')]).map((t) => t.name),
          ['Darkness', 'Difficult Terrain', 'Prone']);
    });

    test('entering difficult terrain needs a Traversal check, once', () {
      expect(engine.checkMove(at(2, 3), at(3, 3)).checks, ['Traversal']);
      expect(engine.checkMove(at(3, 3), at(3, 3)).checks, isEmpty);
      expect(engine.checkMove(at(2, 3), at(3, 3)).cost, 1);
    });

    test('a full sector blocks entry', () {
      expect(engine.checkMove(at(4, 5), at(5, 5)).blocked, isFalse);
      expect(
          engine.checkMove(at(4, 5), at(5, 5), occupants: [at(5, 5)]).blocked,
          isTrue);
    });
  });

  group('D&D 5e: feet with alternating diagonals', () {
    final grid = dnd.topologyFor(cellSize: cell) as SquareGrid;
    Point at(int col, int row) => grid.centerOf((col: col, row: row));
    final engine = TacticalEngine(pack: dnd, topology: grid, regions: [
      Region(
        id: 'mud',
        shape: Polygon.rect((x: 200, y: 0), (x: 400, y: 100)),
        tags: [tag('Difficult Terrain')],
      ),
    ]);

    test('diagonals cost 5, 10, 5', () {
      expect(engine.measure(at(0, 0), at(1, 1)).value, 5);
      expect(engine.measure(at(0, 0), at(2, 2)).value, 15);
      expect(engine.measure(at(0, 0), at(3, 3)).value, 20);
      expect(engine.measure(at(0, 0), at(3, 1)).value, 15);
      expect(engine.measure(at(0, 0), at(3, 3)).band, isNull);
    });

    test('difficult terrain doubles the cost of moving in', () {
      expect(engine.checkMove(at(0, 0), at(1, 0)).cost, 5);
      expect(engine.checkMove(at(0, 0), at(2, 0)).cost, 20);
    });
  });

  group('Zone game: gridless', () {
    final engine = TacticalEngine(
      pack: zones,
      topology: zones.topologyFor(cellSize: cell),
      regions: [
        Region(
            id: 'smoke',
            shape: const Circle((x: 500, y: 0), 100),
            tags: [tag('Smoke')]),
      ],
    );

    test('distance is straight-line, in steps of one cell size', () {
      expect(engine.measure((x: 0, y: 0), (x: 300, y: 400)).value, 5);
    });

    test('regions can be any shape, and unknown tags have no effect', () {
      expect(engine.tagsAt((x: 550, y: 50)).single.name, 'Smoke');
      expect(engine.tagsAt((x: 650, y: 50)), isEmpty);
      expect(engine.effectsAt((x: 550, y: 50)), isEmpty);
      expect(engine.canSee((x: 0, y: 0), (x: 1000, y: 0)), isTrue);
    });
  });

  group('shapes', () {
    final square = Polygon.rect((x: 0, y: 0), (x: 10, y: 10));

    test('crossing the inside, grazing an edge, and running along one', () {
      expect(square.crossesInterior((x: -5, y: 5), (x: 15, y: 5)), isTrue);
      expect(square.crossesInterior((x: -5, y: 0), (x: 15, y: 0)), isFalse);
      expect(square.crossesInterior((x: -5, y: 5), (x: 5, y: -5)), isFalse);
      expect(square.crossesInterior((x: 2, y: 2), (x: 3, y: 3)), isTrue);
      expect(square.crossesInterior((x: 20, y: 20), (x: 30, y: 30)), isFalse);
    });

    test('a concave polygon', () {
      // A U shape: the gap between its arms is outside.
      final u = Polygon([
        (x: 0, y: 0), (x: 30, y: 0), (x: 30, y: 30), (x: 20, y: 30),
        (x: 20, y: 10), (x: 10, y: 10), (x: 10, y: 30), (x: 0, y: 30),
      ]);
      expect(u.contains((x: 15, y: 20)), isFalse);
      expect(u.contains((x: 5, y: 20)), isTrue);
      expect(u.crossesInterior((x: 12, y: 15), (x: 18, y: 25)), isFalse);
      expect(u.crossesInterior((x: 5, y: 20), (x: 25, y: 20)), isTrue);
    });
  });

  test('built-in packs: 5e measures feet, conditions and region tags apart', () {
    final pack = packFor('dnd5e');
    final engine = TacticalEngine(
        pack: pack, topology: pack.topologyFor(cellSize: 100));
    expect(engine.measure((x: 50, y: 50), (x: 350, y: 250)).toString(), '15.0 ft');
    expect(pack.conditions.map((t) => t.name), contains('Prone'));
    expect(pack.regionTags.map((t) => t.name), contains('Difficult Terrain'));
    expect(pack.conditions.map((t) => t.name), isNot(contains('Difficult Terrain')));
    expect(packFor('nope').name, 'Generic');
  });
}
