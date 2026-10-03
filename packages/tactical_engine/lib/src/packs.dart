import 'pack.dart';
import 'topology.dart';

/// The packs that ship with the app, by id: the id a scene's settings name.
final builtInPacks = <String, SystemPack>{
  'generic': SystemPack(
    id: 'generic',
    name: 'Generic',
    unit: 'cell',
    initiative: 'd20',
  ),
  'dnd5e': _dnd5e,
};

/// The pack for [id] among the built-in ones and [installed], or Generic
/// for an id this app doesn't know.
SystemPack packFor(String id, [Iterable<SystemPack> installed = const []]) =>
    builtInPacks[id] ??
    installed.where((p) => p.id == id).firstOrNull ??
    builtInPacks['generic']!;

// The conditions and terrain of the D&D 5e System Reference Document 5.1
// (CC-BY-4.0), summarised. Advantage is edge +1, disadvantage -1.
final _dnd5e = SystemPack(
  id: 'dnd5e',
  name: 'D&D 5e',
  diagonal: DiagonalRule.chebyshev,
  unit: 'ft',
  unitsPerStep: 5,
  initiative: 'd20',
  tags: const [
    TagDef('Blinded',
        condition: true,
        effects: [RollModifier(-1)],
        text: "Can't see. Fails checks that need sight. Its attacks have "
            'disadvantage; attacks against it have advantage.'),
    TagDef('Charmed',
        condition: true,
        text: "Can't attack the charmer. The charmer has advantage on "
            'social checks against it.'),
    TagDef('Deafened',
        condition: true, text: "Can't hear. Fails checks that need hearing."),
    TagDef('Exhaustion',
        condition: true,
        valued: true,
        text: 'Levels 1 to 6, each adding to the last: disadvantage on '
            'checks, speed halved, disadvantage on attacks and saves, '
            'hit point maximum halved, speed 0, death.'),
    TagDef('Frightened',
        condition: true,
        effects: [RollModifier(-1)],
        text: 'Disadvantage on checks and attacks while the source of fear '
            "is in sight. Can't willingly move closer to it."),
    TagDef('Grappled',
        condition: true, text: 'Speed 0. Ends if the grappler is incapacitated.'),
    TagDef('Incapacitated',
        condition: true, text: "Can't take actions or reactions."),
    TagDef('Invisible',
        condition: true,
        effects: [RollModifier(1)],
        text: 'Unseen without magic. Its attacks have advantage; attacks '
            'against it have disadvantage.'),
    TagDef('Paralyzed',
        condition: true,
        text: "Incapacitated, can't move or speak. Fails Strength and "
            'Dexterity saves. Hits from within 5 ft are critical.'),
    TagDef('Petrified',
        condition: true,
        text: 'Turned to stone: incapacitated, resistant to all damage, '
            'immune to poison and disease.'),
    TagDef('Poisoned',
        condition: true,
        effects: [RollModifier(-1)],
        text: 'Disadvantage on attacks and ability checks.'),
    TagDef('Prone',
        condition: true,
        text: 'Can only crawl. Its attacks have disadvantage. Attacks from '
            'within 5 ft have advantage, from further away disadvantage.'),
    TagDef('Restrained',
        condition: true,
        effects: [RollModifier(-1)],
        text: 'Speed 0. Its attacks and Dexterity saves have disadvantage; '
            'attacks against it have advantage.'),
    TagDef('Stunned',
        condition: true,
        text: "Incapacitated, can't move, speaks falteringly. Fails "
            'Strength and Dexterity saves.'),
    TagDef('Unconscious',
        condition: true,
        text: 'Incapacitated, prone and unaware. Fails Strength and '
            'Dexterity saves. Hits from within 5 ft are critical.'),
    TagDef('Difficult Terrain',
        effects: [MoveCost(2)], text: 'Every foot of movement costs 2.'),
    TagDef('Lightly Obscured',
        effects: [RollModifier(-1)],
        text: 'Dim light, patchy fog: disadvantage on Perception that '
            'relies on sight.'),
    TagDef('Heavily Obscured',
        effects: [BlocksSight()],
        text: 'Darkness, thick fog: sight is blocked, as if blinded.'),
    TagDef('Half Cover', text: '+2 to AC and Dexterity saves.'),
    TagDef('Three-Quarters Cover', text: '+5 to AC and Dexterity saves.'),
  ],
);
