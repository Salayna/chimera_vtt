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
  compendium: _dnd5eWeapons,
  advancement: _dnd5eLevels,
  sheet: _dnd5eSheet,
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

/// A simple D&D 5e character: abilities and their modifiers, level and
/// proficiency, hit points and armor class.
final _dnd5eSheet = SheetDef.fromJson(kinds: _dnd5eWeapons.kinds, {
  'sections': [
    {
      'title': 'Abilities',
      'fields': [
        for (final (a, label) in [
          ('STR', 'Strength'),
          ('DEX', 'Dexterity'),
          ('CON', 'Constitution'),
          ('INT', 'Intelligence'),
          ('WIS', 'Wisdom'),
          ('CHA', 'Charisma'),
        ]) ...[
          {'name': a, 'label': label, 'min': 1, 'max': 30, 'value': 10},
          {
            'name': '$a.mod',
            'label': '$label modifier',
            'type': 'computed',
            'formula': 'floor(($a - 10) / 2)',
          },
        ],
      ],
    },
    {
      'title': 'Character',
      'fields': [
        {
          'name': 'class',
          'label': 'Class',
          'type': 'choice',
          'options': [
            'Barbarian', 'Bard', 'Cleric', 'Druid', 'Fighter', 'Monk', //
            'Paladin', 'Ranger', 'Rogue', 'Sorcerer', 'Warlock', 'Wizard',
          ],
        },
        {'name': 'level', 'label': 'Level', 'min': 1, 'max': 20},
        {'name': 'XP', 'label': 'Experience points', 'min': 0, 'max': 355000},
        {
          'name': 'proficiency',
          'label': 'Proficiency bonus',
          'type': 'computed',
          'formula': 'ceil(level / 4) + 1',
        },
      ],
    },
    {
      'title': 'Combat',
      'fields': [
        {'name': 'AC', 'label': 'Armor class', 'min': 0, 'max': 30, 'value': 10},
        {'name': 'speed', 'label': 'Speed', 'min': 0, 'max': 120, 'value': 30},
        {'name': 'maxHP', 'label': 'Hit point maximum', 'min': 1, 'max': 999, 'value': 8},
        {
          'name': 'HP',
          'label': 'Hit points',
          'type': 'tracker',
          'max': 'maxHP',
          'value': 'HP.max',
        },
      ],
    },
    {
      'title': 'Attacks',
      'fields': [
        {'name': 'weapons', 'label': 'Weapons', 'type': 'items', 'kind': 'Weapon'},
      ],
    },
    {
      'title': 'Notes',
      'fields': [
        {'name': 'notes', 'label': 'Notes', 'type': 'text'},
      ],
    },
  ],
});

/// Some of the SRD's weapons, each with an attack and a damage roll, the
/// character proficient. Finesse weapons use the better of STR and DEX.
final _dnd5eWeapons = Compendium.fromJson({
  'kinds': [
    {'name': 'Weapon', 'fields': <Object>[]},
  ],
  'entries': [
    for (final (name, damage, kind, properties) in [
      ('Club', '1d4 bludgeoning', 'STR', 'Light'),
      ('Dagger', '1d4 piercing', 'finesse', 'Finesse, light, thrown (20/60)'),
      ('Handaxe', '1d6 slashing', 'STR', 'Light, thrown (20/60)'),
      ('Mace', '1d6 bludgeoning', 'STR', ''),
      ('Quarterstaff', '1d6 bludgeoning', 'STR', 'Versatile (1d8)'),
      ('Shortsword', '1d6 piercing', 'finesse', 'Finesse, light'),
      ('Rapier', '1d8 piercing', 'finesse', 'Finesse'),
      ('Longsword', '1d8 slashing', 'STR', 'Versatile (1d10)'),
      ('Warhammer', '1d8 bludgeoning', 'STR', 'Versatile (1d10)'),
      ('Greataxe', '1d12 slashing', 'STR', 'Heavy, two-handed'),
      ('Greatsword', '2d6 slashing', 'STR', 'Heavy, two-handed'),
      ('Shortbow', '1d6 piercing', 'DEX', 'Ammunition (80/320), two-handed'),
      ('Longbow', '1d8 piercing', 'DEX', 'Ammunition (150/600), heavy, two-handed'),
      ('Light crossbow', '1d8 piercing', 'DEX', 'Ammunition (80/320), loading, two-handed'),
    ])
      {
        'kind': 'Weapon',
        'name': name,
        if (properties.isNotEmpty)
          'card': [
            {'title': 'Properties', 'text': properties},
          ],
        'actions': [
          {
            'name': 'Attack',
            'dice': 'd20',
            'mod': '${_abilityMod(kind)} + proficiency',
            'text': 'Against the target\'s AC.',
          },
          {
            'name': 'Damage',
            'dice': damage.split(' ').first,
            'mod': _abilityMod(kind),
            'text': damage.split(' ').last,
          },
        ],
      },
  ],
});

String _abilityMod(String kind) =>
    kind == 'finesse' ? 'max(STR.mod, DEX.mod)' : '$kind.mod';

/// Levels as a chain: each needs the one before and the SRD's experience
/// for it, and raises the level by one. Experience isn't spent.
final _dnd5eLevels = Advancement.fromJson({
  'name': 'Levels',
  'field': 'XP',
  'nodes': [
    for (final (i, xp) in const [
      300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, //
      100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000,
    ].indexed)
      {
        'name': 'Level ${i + 2}',
        'cost': 0,
        if (i > 0) 'requires': ['Level ${i + 1}'],
        'condition': 'XP >= $xp',
        'adds': {'level': 1},
        'text': '$xp XP',
      },
  ],
});
