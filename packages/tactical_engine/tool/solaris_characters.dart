/// Gives the Solaris Arcanum module its characters, from the GM's own notes
/// of the books: a sheet, a compendium of the weapons, explosives, armor,
/// items, talents and flaws (Core Rulebook chapter 5, Appendix A), the
/// classes and archetypes (chapter 4), and the Constellation. The output holds book content, so it stays out of the
/// repository. Run it on the threats tool's output:
///
///     dart run tool/solaris_characters.dart <vault>/Solaris\ Arcanum \
///         ../../packs/solaris-arcanum.local.json ../../packs/solaris-arcanum.local.json \
///         [../../packs/solaris-constellation.local.json]
///
/// The last file is the Constellation as the character sheet draws it,
/// copied by hand (the notes don't hold it); without it, each unique
/// Constellation talent is a star beside the origin.
library;

import 'dart:convert';
import 'dart:io';

import 'package:tactical_engine/tactical_engine.dart';

void main(List<String> args) {
  if (args.length != 3 && args.length != 4) {
    stderr.writeln(
        'Usage: solaris_characters.dart <notes dir> <pack.json> <out.json> [constellation.json]');
    exit(64);
  }
  String read(String path) => File('${args[0]}/$path').readAsStringSync();
  const appendix = 'Appendices/01 Appendix A Weapons, Armor, Mods, and Items';
  const chapter5 = 'Core Rulebook/06 CHAPTER 5 Adding Details to your Character';
  final entries = <String, Json>{};
  void add(Iterable<Json> found) {
    for (final e in found) {
      entries.putIfAbsent(e['name'] as String, () => e);
    }
  }

  add(weaponsFromMarkdown(read('$appendix/01 Weapons.md')));
  add(weaponsFromMarkdown(read('$appendix/02 Explosives.md'), kind: 'Explosive'));
  add(armorFromMarkdown(read('$appendix/04 Armor.md')));
  add(itemsFromMarkdown(read('$appendix/08 Items.md')));
  final talents = talentsFromMarkdown(read('$chapter5/02 Talents and Flaws.md'));
  add(talents);
  add(talentsFromMarkdown(read('$chapter5/03 Flaws.md'), kind: 'Flaw'));
  const chapter4 = 'Core Rulebook/05 CHAPTER 4 Classes and Archetypes';
  final classes = classesFromMarkdown([
    for (final f in (Directory('${args[0]}/$chapter4').listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path))))
      if (f.path.endsWith('.md')) f.readAsStringSync(),
  ]);
  add(classes.entries);

  final input = jsonDecode(File(args[1]).readAsStringSync()) as Json;
  final out = {
    ...input,
    // A new build is a new version, so rooms playing the last one take it.
    'version': (input['version'] as int? ?? 1) + 1,
    'compendium': {'kinds': kinds, 'entries': entries.values.toList()},
    'advancement': [
      threatLevels,
      archetypeTrack(classes.archetypes),
      if (args.length == 4)
        jsonDecode(File(args[3]).readAsStringSync()) as Json
      else
        constellation([
          for (final t in talents)
            if (t['constellation'] == true) t['name'] as String,
        ]),
    ],
    'sheet': sheet,
  };
  for (final e in entries.values) {
    e.remove('constellation');
  }
  // Checked like any installed pack.
  SystemPack.fromJson(out);
  File(args[2]).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  final counts = <String, int>{};
  for (final e in entries.values) {
    counts.update(e['kind'] as String, (n) => n + 1, ifAbsent: () => 1);
  }
  stdout.writeln('${counts.entries.map((e) => '${e.value} ${e.key}').join(', ')} → ${args[2]}');
}

/// The cards of a markdown table file: each table whose first cell is
/// `**Name**`, as its rows of non-empty cells.
List<(String, List<List<String>>)> _cards(String markdown) {
  final cards = <(String, List<List<String>>)>[];
  final lines = markdown.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final head = RegExp(r'^\|\s*\*\*(.+?)\*\*').firstMatch(lines[i]);
    if (head == null) continue;
    final rows = <List<String>>[];
    var j = i + 1;
    for (; j < lines.length && lines[j].startsWith('|'); j++) {
      if (lines[j].startsWith('| ---') || lines[j].startsWith('| -')) continue;
      rows.add([
        for (final c in lines[j].split('|').skip(1)) if (c.trim().isNotEmpty) c.trim(),
      ]);
    }
    cards.add((_clean(head[1]!), rows));
    i = j - 1;
  }
  return cards;
}

/// Markdown out, line breaks in, quotes straightened.
String _clean(String s) => s
    .replaceAll(RegExp(r'\s*<br>\s*'), '\n')
    .replaceAll('**', '')
    .replaceAll(RegExp('[“”]'), '"')
    .replaceAll('’', "'")
    .trim();

String _short(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

int? _int(String s, RegExp pattern) => switch (pattern.firstMatch(s)) {
      final m? => int.tryParse(m[1]!),
      null => null,
    };

Json _section(String title, String text) =>
    {'title': _short(title, 80), 'text': _short(text, 4000)};

final _profile = RegExp(r'^(Ranged|Melee) Attacks: (\d*)d20');
final _tier = RegExp(r'(Grazing|Precise|Devastating) Hit \((\d+)\+\):\s*([^\n]*)');

/// Weapon (or explosive) data cards: ammo boxes, reload, whether heavy, and
/// each attack profile as an action: its AP and, if it shoots, a round per
/// die; d20 plus the ranged or melee modifier per die, banded by hit tier.
List<Json> weaponsFromMarkdown(String markdown, {String kind = 'Weapon'}) => [
      for (final (name, rows) in _cards(markdown)) _weapon(name, rows, kind),
    ];

Json _weapon(String name, List<List<String>> rows, String kind) {
  final card = <Json>[];
  final actions = <Json>[];
  var capacity = 0, reload = 0, heavy = 0;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final first = row.first;
    if (i == 0 && row.length == 1) {
      card.add(_section('Description', _clean(first)));
    } else if (first.startsWith('Weight:') || first.startsWith('Price:')) {
      card.add(_section('Details', row.map(_clean).join(' · ')));
    } else if (first == 'Type:') {
      card.add(_section('Type', row.skip(1).join(' · ')));
      if (row.contains('Heavy')) heavy = 1;
    } else if (first.startsWith('Weapon Tags') || first.startsWith('Attack Tags')) {
      final (title, text) = _split(_clean(row.join(' ')));
      card.add(_section(title, text));
    } else if (first.startsWith('Ammo:')) {
      capacity = '☐'.allMatches(first).length;
      reload = _int(row.join(' '), RegExp(r'Reload: (\d+) AP')) ?? 0;
    } else if (first.startsWith('Effect:')) {
      card.add(_section('Effect', _clean(first.substring('Effect:'.length))));
    } else if (_int(first, RegExp(r'AP Cost: (\d+)')) case final ap? when row.length == 1) {
      // An explosive's other action: "Plant Charge AP Cost: 2".
      actions.add({
        'name': _short(first.split(' AP Cost').first, 60),
        'cost': [
          {'tracker': 'AP', 'amount': ap},
        ],
      });
    } else if (row.length >= 3 && _profile.firstMatch(row[2]) != null) {
      final m = _profile.firstMatch(row[2])!;
      final dice = m[2]!.isEmpty ? 1 : int.parse(m[2]!);
      final ap = _int(row[1], RegExp(r'AP Cost: (\d+)')) ?? 0;
      final ranged = m[1] == 'Ranged';
      final tiers = i + 1 < rows.length ? _clean(rows[i + 1].join(' ')) : '';
      var actionName = _short(_clean(first), 60);
      while (actions.any((a) => a['name'] == actionName)) {
        actionName = '$actionName+';
      }
      actions.add({
        'name': actionName,
        'text': row.skip(3).map(_clean).join(' · '),
        'cost': [
          {'tracker': 'AP', 'amount': ap},
          if (ranged && capacity > 0) {'tracker': 'ammo', 'amount': dice},
        ],
        'dice': 'd20',
        'mod': ranged ? 'rangedMod' : 'meleeMod',
        'times': dice,
        'bands': [
          for (final t in _tier.allMatches(tiers))
            {'name': t[1], 'min': int.parse(t[2]!), 'text': _short(t[3]!.trim(), 500)},
        ],
      });
      i++; // The tiers row.
    }
  }
  if (capacity > 0) {
    actions.add({
      'name': 'Reload',
      'cost': [
        {'tracker': 'AP', 'amount': reload},
        {'tracker': 'ammo', 'amount': 'ammo - ammo.max'},
      ],
    });
  }
  return {
    'kind': kind,
    'name': _short(name, 60),
    'values': {'capacity': capacity, 'reload': reload, 'heavy': heavy},
    'card': card.take(10).toList(),
    'actions': actions.take(20).toList(),
  };
}

/// "Weapon Tags - Unreliable: …" as its title and text.
(String, String) _split(String s) {
  final dash = s.indexOf(' - ');
  final colon = s.indexOf(':');
  if (dash > 0 && dash < 20) return (s.substring(0, dash), s.substring(dash + 3));
  if (colon > 0 && colon < 20) return (s.substring(0, colon), s.substring(colon + 1).trim());
  return ('Tags', s);
}

/// Armor data cards: grade, AP reduction, carrying capacity, mod slots.
List<Json> armorFromMarkdown(String markdown) => [
      for (final (name, rows) in _cards(markdown))
        () {
          final all = rows.map((r) => r.join(' | ')).join('\n');
          int n(String label) => _int(all, RegExp('$label: (\\d+)')) ?? 0;
          return {
            'kind': 'Armor',
            'name': _short(name, 60),
            'values': {
              'grade': n('Armor Grade'),
              'apReduction': n('AP Reduction'),
              'carry': n('Carrying Capacity'),
              'modSlots': n('Mod Slots'),
            },
            'card': [
              for (final (i, r) in rows.indexed)
                if (i == 0 && r.length == 1)
                  _section('Description', _clean(r.first))
                else if (r.first.startsWith('Immunities'))
                  _section('Protection', r.map(_clean).join(' · '))
                else if (r.first.startsWith('Armor Tags') || r.first.startsWith('Unique'))
                  _section(_split(_clean(r.join(' '))).$1, _split(_clean(r.join(' '))).$2)
                else if (r.first.startsWith('Type'))
                  _section('Type', r.map(_clean).join(' · ')),
            ].take(10).toList(),
          };
        }(),
    ];

/// Item cards: a Use action costing their AP, and their effect.
List<Json> itemsFromMarkdown(String markdown) => [
      for (final (name, rows) in _cards(markdown))
        () {
          final all = rows.map((r) => r.join(' | ')).join('\n');
          final ap = _int(all, RegExp(r'AP Cost: (\d+)'));
          return {
            'kind': 'Item',
            'name': _short(name, 60),
            'card': [
              for (final (i, r) in rows.indexed)
                if (i == 0 && r.length == 1)
                  _section('Description', _clean(r.first))
                else if (r.first.startsWith('Effect'))
                  _section('Effect', _clean(r.first.substring('Effect:'.length)))
                else if (r.first.startsWith('Price'))
                  _section('Details', r.map(_clean).join(' · ')),
            ].take(10).toList(),
            if (ap != null)
              'actions': [
                {
                  'name': 'Use',
                  'cost': [
                    {'tracker': 'AP', 'amount': ap},
                  ],
                },
              ],
          };
        }(),
    ];

/// Talent (or flaw) callouts: `> **Name**` then its prerequisite and
/// effect, or a unique Constellation talent's `> Name Prerequisite: …`.
/// Those marked `constellation` are the Constellation's.
List<Json> talentsFromMarkdown(String markdown, {String kind = 'Talent'}) {
  final talents = <Json>[];
  final blocks = markdown.split(RegExp(r'\n(?=> \[!note\])'));
  for (final block in blocks) {
    final lines = [
      for (final l in block.split('\n'))
        if (l.startsWith('>') && !l.contains('[!note]')) l.substring(1).trim(),
    ];
    if (lines.isEmpty) continue;
    final String name;
    final String prerequisite;
    var body = lines;
    if (lines.first.startsWith('**')) {
      name = _clean(lines.first);
      prerequisite = lines.length > 1 && lines[1].startsWith('Prerequisite:')
          ? lines[1].substring('Prerequisite:'.length).trim()
          : '';
      body = lines.skip(prerequisite.isEmpty ? 1 : 2).toList();
    } else if (lines.first.contains(' Prerequisite: ')) {
      final [n, p] = lines.first.split(' Prerequisite: ');
      name = n.trim();
      prerequisite = p.trim();
      body = lines.skip(1).toList();
    } else {
      continue;
    }
    final text = _clean(body.join('\n'));
    final effect = text.indexOf('Effect:');
    talents.add({
      'kind': kind,
      'name': _short(name, 60),
      'card': [
        if (prerequisite.isNotEmpty) _section('Prerequisite', prerequisite),
        if (effect > 0) _section('Description', text.substring(0, effect).trim()),
        _section('Effect', effect >= 0 ? text.substring(effect + 'Effect:'.length).trim() : text),
      ],
      if (prerequisite.contains('Constellation Node')) 'constellation': true,
    });
  }
  return talents;
}

/// Classes and archetypes from chapter 4's files, in order: a class's
/// core abilities (`Bastion core`), and each archetype level's abilities
/// (`Duelist, Level 1`, its gear and starting talent with it), and which
/// archetypes each class has, with how many levels the notes give each. A group's file without levels (The Psions)
/// goes on the first level of the archetypes after it.
({List<Json> entries, Map<String, Map<String, int>> archetypes}) classesFromMarkdown(
    List<String> files) {
  final entries = <Json>[];
  final archetypes = <String, Map<String, int>>{};
  Json? current;
  var group = <Json>[];
  for (final md in files) {
    final title = RegExp(r'^## (.+)$', multiLine: true).firstMatch(md)?[1]?.trim() ?? '';
    final className = _classes[title];
    if (className != null) {
      current = {'kind': 'Class', 'name': '$className core', 'card': _sections(md)};
      entries.add(current);
      archetypes[className] = {};
      group = [];
    } else if (title.contains('Core Abilit') && current != null) {
      (current['card'] as List).addAll(_sections(md));
    } else if (!md.contains('### Level 1')) {
      group = _sections(md);
    } else if (current != null) {
      final name = title.replaceFirst(RegExp(r'^The '), '');
      final levels = md.split(RegExp(r'^#{3,4} Level (?=\d)', multiLine: true));
      archetypes[_classes.entries.firstWhere((e) => '${e.value} core' == current!['name']).value]![name] =
          levels.length - 1;
      final preamble = levels.first;
      final gear = preamble.indexOf('Recommended Gear');
      for (final level in levels.skip(1)) {
        final n = level.substring(0, 1);
        entries.add({
          'kind': 'Archetype',
          'name': _short('$name, Level $n', 60),
          'card': [
            if (n == '1') ...[
              if (gear >= 0)
                _section('Recommended gear',
                    _clean(preamble.substring(preamble.indexOf('\n', gear)).replaceAll(RegExp(r'\n+'), '\n'))),
              ...group,
            ],
            ..._sections(level.substring(1)),
          ].take(10).toList(),
        });
      }
    }
  }
  for (final c in entries.where((e) => e['kind'] == 'Class')) {
    c['card'] = (c['card'] as List).take(10).toList();
  }
  return (entries: entries, archetypes: archetypes);
}

const _classes = {
  'Aethers': 'Aether',
  'Bastions': 'Bastion',
  'Specters': 'Specter',
  'Synths': 'Synth',
  'Vitalists': 'Vitalist',
};

/// A file's `####` abilities as card sections; text before the first, if
/// any, as one titled by what it starts with. Callouts lose their marks.
List<Json> _sections(String md) {
  final body = md
      .split('\n')
      .where((l) => !l.startsWith('Up:') && !l.startsWith('## ') && !l.startsWith('### ') && !l.contains('[!note]'))
      .map((l) => l.startsWith('>') ? l.substring(1).trim() : l)
      .join('\n');
  final parts = body.split(RegExp(r'^#### ', multiLine: true));
  final head = parts.first.trim();
  return [
    // Before the abilities: a level's "Gain a Weapon Art" and its choices.
    if (head.isNotEmpty && RegExp(r'^(Gain|Choose)', multiLine: true).hasMatch(head))
      _section(head.split('\n').first.replaceAll(':', '').trim(), _clean(head.split('\n').skip(1).join('\n'))),
    for (final p in parts.skip(1))
      _section(p.split('\n').first.replaceAll(RegExp(r':\s*$'), '').trim(),
          _clean(p.split('\n').skip(1).join('\n').replaceAll(RegExp(r'\n{2,}'), '\n'))),
  ];
}

/// The compendium's kinds.
const kinds = [
  {
    'name': 'Weapon',
    'fields': [
      {'name': 'capacity', 'label': 'Ammo boxes'},
      {'name': 'ammo', 'label': 'Ammo', 'type': 'tracker', 'max': 'capacity', 'value': 'ammo.max'},
      {'name': 'reload', 'label': 'Reload (AP)'},
      {'name': 'heavy', 'label': 'Heavy (1 or 0)', 'min': 0, 'max': 1},
    ],
  },
  {
    'name': 'Explosive',
    'fields': [
      {'name': 'capacity', 'label': 'Ammo boxes'},
      {'name': 'ammo', 'label': 'Ammo', 'type': 'tracker', 'max': 'capacity', 'value': 'ammo.max'},
      {'name': 'reload', 'label': 'Reload (AP)'},
      {'name': 'heavy', 'label': 'Heavy (1 or 0)', 'min': 0, 'max': 1},
    ],
  },
  {
    'name': 'Armor',
    'fields': [
      {'name': 'grade', 'label': 'Armor Grade'},
      {'name': 'apReduction', 'label': 'AP reduction'},
      {'name': 'carry', 'label': 'Carrying capacity'},
      {'name': 'modSlots', 'label': 'Mod slots'},
    ],
  },
  {'name': 'Item', 'fields': <Json>[]},
  {'name': 'Class', 'fields': <Json>[]},
  {'name': 'Archetype', 'fields': <Json>[]},
  {'name': 'Talent', 'fields': <Json>[]},
  {'name': 'Flaw', 'fields': <Json>[]},
];

const _stats = [
  ('STR', 'Strength'),
  ('FIN', 'Finesse'),
  ('END', 'Endurance'),
  ('WIL', 'Willpower'),
  ('INT', 'Intellect'),
  ('CHA', 'Charisma'),
];

/// Each core stat's skills, as the character sheet lists them.
const _skills = {
  'STR': [('athletics', 'Athletics'), ('intimidationSTR', 'Intimidation')],
  'FIN': [
    ('evasion', 'Evasion'),
    ('stealth', 'Stealth'),
    ('traversal', 'Traversal'),
    ('piloting', 'Piloting'),
    ('sleightOfHand', 'Sleight of Hand'),
  ],
  'END': [('interfacing', 'Human-Machine Interfacing'), ('painTolerance', 'Pain Tolerance')],
  'WIL': [
    ('arcaneResistance', 'Arcane Resistance'),
    ('psionicStudies', 'Psionic Studies'),
    ('composure', 'Composure'),
  ],
  'CHA': [
    ('deception', 'Deception'),
    ('intimidationCHA', 'Intimidation'),
    ('theurgy', 'Esoterism (Theurgy)'),
    ('etiquette', 'Etiquette'),
    ('persuasion', 'Persuasion'),
  ],
  'INT': [
    ('awareness', 'Awareness'),
    ('cyberwarfare', 'Cyberwarfare'),
    ('ritualMagic', 'Esoterism (Ritual Magic)'),
    ('naturalSciences', 'Natural Sciences'),
    ('psychAnalysis', 'Psychological Analysis'),
    ('tacticalAssessment', 'Tactical Assessment'),
    ('commonKnowledge', 'Common Knowledge'),
    ('engineering', 'Engineering'),
    ('medicine', 'Medicine'),
    ('navigation', 'Navigation'),
    ('socialSciences', 'Social Sciences and Humanities'),
  ],
};

const _wounds = [
  ('PsW', 'Psychic', 'Shaken (1), Shaken (2), Delirious, Mental Collapse'),
  ('ReW', 'Respiratory', 'Shallow Breathing, Shallow Breathing (2), Lungs Collapsed, Suffocating'),
  ('NvW', 'Nervous', 'Disrupted, System Shock, Paralyzed, Nerves Collapse'),
  ('CvW', 'Cardiovascular', 'Bleeding (2), Bleeding (4), Bleeding (10), Cardiac Rupture'),
  ('MsW.leftArm', 'Left arm', 'Crippled (1), Crippled (2), Broken, Torn Out'),
  ('MsW.rightArm', 'Right arm', 'Crippled (1), Crippled (2), Broken, Torn Out'),
  ('MsW.leftLeg', 'Left leg', 'Crippled (1), Crippled (2), Broken, Torn Out'),
  ('MsW.rightLeg', 'Right leg', 'Crippled (1), Crippled (2), Broken, Torn Out'),
];

/// The character sheet, as the Solaris Arcanum sheet lays it out: who the
/// character is, core abilities and skills, combat, loadout, talents and
/// story, with the Threat Level, archetypes and Constellation as tabs of
/// their own.
final sheet = {
  'layout': 'tabs',
  'sections': [
    {
      'title': 'Character',
      'fields': [
        {'name': 'class', 'label': 'Starting class', 'type': 'choice', 'options': ['Aether', 'Bastion', 'Specter', 'Synth', 'Vitalist']},
        {'name': 'threatLevel', 'label': 'Threat Level (Alpha 1 to Delta 4)', 'min': 1, 'max': 4, 'value': 1},
        {'name': 'rank', 'label': 'Rank', 'min': 0, 'max': 6},
        {'name': 'CP', 'label': 'CP', 'min': 0},
        {'name': 'archetypePicks', 'label': 'Archetype levels to take', 'min': 0, 'text': 'Given by the Threat Level rewards and the Constellation.'},
        {'name': 'classPicks', 'label': 'Classes beyond the first', 'min': 0, 'text': 'Given by the Beta and Delta rewards.'},
        {'name': 'background', 'label': 'Background', 'type': 'text'},
        {'name': 'classes', 'label': 'Classes', 'type': 'items', 'kind': 'Class'},
        {'name': 'archetypes', 'label': 'Archetypes', 'type': 'items', 'kind': 'Archetype'},
      ],
    },
    {
      'title': 'Core abilities',
      'fields': [
        for (final (stat, label) in _stats) ...[
          {'name': stat, 'label': label, 'min': 0, 'max': 10, 'value': 3},
          for (final (name, skill) in _skills[stat]!) ...[
            {'name': '$name.bonus', 'label': '$skill bonus', 'min': -10, 'max': 20},
            {'name': name, 'label': skill, 'type': 'computed', 'formula': '$stat + $name.bonus'},
          ],
        ],
        {'name': 'masteries', 'label': 'Masteries', 'type': 'text'},
      ],
    },
    {
      'title': 'Combat',
      'fields': [
        {'name': 'arcaneStat', 'label': 'Arcane stat', 'type': 'choice', 'options': ['WIL', 'INT', 'CHA']},
        {'name': 'meleeMod', 'label': 'Melee', 'type': 'computed', 'formula': 'STR + threatLevel + meleeBonus'},
        {'name': 'rangedMod', 'label': 'Ranged', 'type': 'computed', 'formula': 'FIN + threatLevel + rangedBonus'},
        {
          'name': 'arcaneMod',
          'label': 'Arcane',
          'type': 'computed',
          'formula': 'threatLevel + castingBonus + (if arcaneStat == "WIL" then WIL else if arcaneStat == "INT" then INT else CHA)',
        },
        {'name': 'physical', 'label': 'Physical Prowess', 'type': 'computed', 'formula': 'ceil((STR + FIN + END) / 3)'},
        {'name': 'mental', 'label': 'Mental Prowess', 'type': 'computed', 'formula': 'ceil((INT + WIL + CHA) / 3)'},
        {'name': 'form', 'label': 'Combat Form', 'type': 'choice', 'options': ['Steady', 'Poise', 'Rush'], 'text': 'Poise +2 AP, Rush -2 AP.'},
        {
          'name': 'AP',
          'type': 'tracker',
          'max': '8 + apBonus - sum("Armor", "apReduction") - sum("Weapon", "heavy") - min(ReW, 2) '
              '- (if ReW >= 3 then 2 else 0) + (if form == "Poise" then 2 else if form == "Rush" then -2 else 0)',
          'value': 'AP.max',
        },
        {'name': 'stressThreshold', 'label': 'Stress Threshold', 'type': 'computed', 'formula': 'max(5, END + WIL + threatLevel) + stressBonus'},
        {'name': 'Stress', 'type': 'tracker', 'max': 'stressThreshold'},
        {'name': 'AG', 'label': 'Armor Grade', 'type': 'tracker', 'max': 'sum("Armor", "grade") + agBonus', 'value': 'AG.max'},
        {'name': 'tempAG', 'label': 'Temporary Armor', 'type': 'tracker', 'max': 10},
        for (final (name, label, stages) in _wounds) {'name': name, 'label': label, 'type': 'tracker', 'max': 4, 'text': stages},
        {'name': 'overloaded', 'label': 'Overloaded', 'type': 'checkbox'},
        {'name': 'profile', 'label': 'Psyche profile', 'type': 'text'},
        {'name': 'defenses', 'label': 'Immunities, resistances, vulnerabilities, tags', 'type': 'text'},
        // What the Constellation raised, kept apart from the stats.
        for (final (name, label) in [
          ('meleeBonus', 'Melee from the Constellation'),
          ('rangedBonus', 'Ranged from the Constellation'),
          ('castingBonus', 'Casting from the Constellation'),
          ('stressBonus', 'Stress from the Constellation'),
          ('agBonus', 'Armor Grade from the Constellation'),
          ('apBonus', 'AP from the Constellation'),
          ('overloadBonus', 'Overload checks from the Constellation'),
        ])
          {'name': name, 'label': label, 'min': 0, 'max': 20},
      ],
    },
    {
      'title': 'Loadout',
      'fields': [
        {'name': 'maxCarry', 'label': 'Max carry capacity', 'type': 'computed', 'formula': 'sum("Armor", "carry")'},
        {'name': 'weapons', 'label': 'Weapons', 'type': 'items', 'kind': 'Weapon'},
        {'name': 'explosives', 'label': 'Explosives', 'type': 'items', 'kind': 'Explosive'},
        {'name': 'armor', 'label': 'Armor', 'type': 'items', 'kind': 'Armor'},
        {'name': 'items', 'label': 'Items', 'type': 'items', 'kind': 'Item'},
        {'name': 'wielding', 'label': 'Wielding', 'type': 'text'},
        {'name': 'quickAccess', 'label': 'Quick access', 'type': 'text'},
        {'name': 'backpack', 'label': 'Backpack', 'type': 'text'},
      ],
    },
    {
      'title': 'Talents & flaws',
      'fields': [
        {'name': 'talents', 'label': 'Talents', 'type': 'items', 'kind': 'Talent'},
        {'name': 'flaws', 'label': 'Flaws', 'type': 'items', 'kind': 'Flaw'},
      ],
    },
    {
      'title': 'Story',
      'fields': [
        for (final (name, label) in [
          ('looks', 'Physical looks'),
          ('contracts', 'Contract history'),
          ('coatOfArms', 'Coat of arms'),
          ('details', 'Character details (affiliations, personal history, etc.)'),
          ('equipment', 'Equipment list'),
          ('otherDetails', 'Other details (proxies, spells & vector microorganisms)'),
        ])
          {'name': name, 'label': label, 'type': 'text'},
      ],
    },
  ],
  'actions': [
    {'name': 'Move', 'cost': [{'tracker': 'AP', 'amount': 1}], 'text': 'One Sector.'},
    {'name': 'Enter Stealth', 'cost': [{'tracker': 'AP', 'amount': 1}]},
    {'name': 'Command Proxies', 'cost': [{'tracker': 'AP', 'amount': 2}]},
    {'name': 'Dodge', 'cost': [{'tracker': 'AP', 'amount': 2}], 'text': "Reaction: removes the attacker's highest die."},
    {'name': 'Fight Back', 'cost': [{'tracker': 'AP', 'amount': 1}], 'text': "Reaction: plus the weapon profile's AP."},
    {'name': 'Parry', 'cost': [{'tracker': 'AP', 'amount': 2}], 'dice': 'd20', 'mod': 'meleeMod', 'text': 'Reaction: blocks the attack if higher.'},
    {'name': 'Overload check', 'dice': 'd20', 'mod': 'WIL + overloadBonus'},
  ],
};

/// The Threat Level's ranks in order, each giving its CP (Alpha 1, Beta 2,
/// Gamma 3, Delta 10), the first of each level raising the Threat Level,
/// and each level's first rank its reward: archetype levels to take, or a
/// new class with its archetype.
final threatLevels = {
  'name': 'Threat Level',
  'field': 'CP',
  'nodes': [
    for (final (t, (level, ranks, cp)) in const [
      ('Alpha', 6, 1),
      ('Beta', 6, 2),
      ('Gamma', 4, 3),
      ('Delta', 2, 10),
    ].indexed) ...[
      for (var r = 1; r <= ranks; r++)
        {
          'name': '$level $r',
          'cost': 0,
          if (t > 0 || r > 1) 'requires': [r == 1 ? '${const ['Alpha', 'Beta', 'Gamma'][t - 1]} ${const [6, 6, 4][t - 1]}' : '$level ${r - 1}'],
          'adds': {
            'CP': cp,
            // Rank 1 of a new level: the level goes up, the rank starts again.
            'rank': r > 1 ? 1 : (t == 0 ? 1 : 1 - const [6, 6, 4][t - 1]),
            if (r == 1 && t > 0) 'threatLevel': 1,
          },
          'x': r - 1,
          'y': t * 2,
          'text': '+$cp CP',
        },
      for (final (i, (reward, adds)) in switch (level) {
        'Alpha' => [('An archetype in your starting class at Level 1', {'archetypePicks': 1})],
        'Beta' => [
            ('Archetype Level +1', {'archetypePicks': 1}),
            ('A New Class and Archetype at Level 1', {'classPicks': 1, 'archetypePicks': 1}),
          ],
        'Gamma' => [('Level +1 to any of your Archetypes', {'archetypePicks': 1})],
        _ => [
            ('A new Archetype within one of your classes at Level 2', {'archetypePicks': 2}),
            ('A New Class and Archetype at Level 1', {'classPicks': 1, 'archetypePicks': 1}),
          ],
      }.indexed)
        {
          'name': '$level: $reward',
          'cost': 0,
          'group': '$level reward',
          'requires': ['$level 1'],
          'condition': 'count("$level reward") < 1',
          'adds': adds,
          'x': i * 3,
          'y': t * 2 + 1,
          'text': 'At Threat Level $level Rank 1.',
        },
    ],
  ],
};

/// Each class's archetypes, spending archetype levels to take: the class
/// (free: your starting class, or one a reward allowed), each archetype's
/// first level from its class (at most 3 archetypes), then its next
/// levels in order. One class under another.
Json archetypeTrack(Map<String, Map<String, int>> archetypes) => {
      'name': 'Archetypes',
      'field': 'archetypePicks',
      'nodes': [
        for (final (c, MapEntry(key: className, value: types)) in archetypes.entries.indexed) ...[
          {
            'name': className,
            'cost': 0,
            'group': 'Class',
            'condition': 'class == "$className" or count("Class") <= classPicks',
            'items': ['$className core'],
            'x': 0,
            'y': c * 6,
            'text': 'Your starting class, or a new one a Threat Level reward gave.',
          },
          for (final (a, MapEntry(key: type, value: levels)) in types.entries.indexed)
            for (var level = 1; level <= levels; level++)
              {
                'name': '$type $level',
                if (level == 1) 'group': 'Archetype',
                'cost': 1,
                'requires': [level == 1 ? className : '$type ${level - 1}'],
                if (level == 1) 'condition': 'count("Archetype") < 3',
                'items': ['$type, Level $level'],
                'x': a - (types.length - 1) / 2,
                'y': c * 6 + level,
                'text': level == 1 ? 'The $type archetype.' : '$type level $level.',
              },
        ],
      ],
    };

/// A stand-in Constellation, when its copy from the character sheet isn't
/// given: each unique Constellation talent a star beside the origin, for 1
/// CP, giving its talent.
Json constellation(List<String> talents) => {
      'name': 'Constellation',
      'field': 'CP',
      'nodes': [
        {'name': 'Origin', 'cost': 0, 'x': 0, 'y': 0, 'text': 'Your class.'},
        for (final (i, t) in talents.indexed)
          {
            'name': t,
            'requires': ['Origin'],
            'items': [t],
            'x': (i % 5) - 2,
            'y': i ~/ 5 + 1,
            'text': 'Gives the talent $t.',
          },
      ],
    };
