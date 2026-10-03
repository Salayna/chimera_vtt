import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_vtt/advancement.dart';
import 'package:chimera_vtt/advancement_view.dart';
import 'package:chimera_vtt/ui/cv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tactical_engine/tactical_engine.dart';

final pack = SystemPack.fromJson({
  'id': 'x',
  'name': 'X',
  'unit': 'ft',
  'compendium': {
    'kinds': [
      {'name': 'Talent', 'fields': const []},
    ],
    'entries': [
      {'kind': 'Talent', 'name': 'Favored Weapon', 'card': [{'title': 'Effect', 'text': '+1 Stress'}]},
    ],
  },
  'advancement': {
    'name': 'Constellation',
    'field': 'CP',
    'nodes': [
      {'name': 'Origin', 'cost': 0},
      {'name': 'Duelist', 'group': 'Archetype', 'requires': ['Origin'], 'condition': 'count("Archetype") < 1'},
      {'name': 'Sniper', 'group': 'Archetype', 'requires': ['Origin'], 'condition': 'count("Archetype") < 1'},
      {'name': 'Might', 'requires': ['Origin'], 'adds': {'STR': 1}},
      {'name': 'Favored', 'requiresAll': ['Duelist', 'Might'], 'items': ['Favored Weapon']},
    ],
  },
  'sheet': {
    'sections': [
      {
        'title': 'S',
        'fields': [
          {'name': 'CP', 'value': 3},
          {'name': 'STR', 'value': 10, 'max': 10},
        ],
      },
    ],
  },
});

Character fresh() => Character(
    id: const CharacterId('c'),
    owner: const PlayerId('me'),
    system: 'x',
    name: 'Kade',
    values: pack.sheet!.start());

void main() {
  test('nodes are taken along the graph, paid with CP, granting what they give', () {
    final n = pack.advancement!.nodes;
    var c = fresh();
    expect(whyNot(pack, c, n['Duelist']!), 'Needs Origin');
    c = take(pack, c, n['Origin']!);
    expect(c.values['CP'], 3, reason: 'Origin costs nothing');
    c = take(pack, c, n['Duelist']!);
    expect(whyNot(pack, c, n['Sniper']!), contains('count("Archetype") < 1'));
    expect(whyNot(pack, c, n['Favored']!), 'Needs Might');
    c = take(pack, c, n['Might']!);
    expect(c.values['STR'], 10, reason: 'kept within its max');
    c = take(pack, c, n['Favored']!);
    expect(c.items.single.name, 'Favored Weapon');
    expect(c.values['CP'], 0);
    expect(c.nodes, ['Origin', 'Duelist', 'Might', 'Favored']);
    expect(whyNot(pack, c, n['Favored']!), 'Taken');
  });

  test("D&D 5e's levels are a chain reached with XP", () {
    final dnd = builtInPacks['dnd5e']!;
    var c = Character(
        id: const CharacterId('a'),
        owner: const PlayerId('me'),
        system: 'dnd5e',
        name: 'Ayla',
        values: {...dnd.sheet!.start(), 'XP': 1000});
    final levels = dnd.advancement!.nodes;
    expect(whyNot(dnd, c, levels['Level 3']!), 'Needs Level 2');
    c = take(dnd, c, levels['Level 2']!);
    c = take(dnd, c, levels['Level 3']!);
    expect((c.values['level'], c.values['XP']), (3, 1000));
    expect(whyNot(dnd, c, levels['Level 4']!), 'Needs XP >= 2700');
  });

  testWidgets('a node that can be taken is taken with a tap', (tester) async {
    var c = fresh();
    await tester.pumpWidget(cvApp(
      title: 'test',
      home: StatefulBuilder(
        builder: (context, setState) => AdvancementView(
          pack: pack,
          character: c,
          onChanged: (changed) => setState(() => c = changed),
        ),
      ),
    ));
    Finder node(String label) =>
        find.byWidgetPredicate((w) => w is CvPressable && w.label == label);
    expect(find.text('3 CP to spend'), findsOneWidget);
    await tester.tap(node('Take Origin'));
    await tester.pump();
    await tester.tap(node('Take Might'));
    await tester.pump();
    expect(c.nodes, ['Origin', 'Might']);
    expect(find.text('2 CP to spend'), findsOneWidget);
    expect(node('Take Favored'), findsNothing);
  });
}
