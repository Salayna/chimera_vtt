/// Gives the Solaris Arcanum module its characters, from the GM's own notes
/// of the books: a sheet, a compendium of the weapons, explosives, armor,
/// items, talents and flaws (Core Rulebook chapter 5, Appendix A), the
/// classes and archetypes (chapter 4), and the Constellation. The output holds book content, so it stays out of the
/// repository. Run it on the threats tool's output:
///
///     dart run tool/solaris_characters.dart <vault>/Solaris\ Arcanum \
///         ../../packs/solaris-arcanum.local.json ../../packs/solaris-arcanum.local.json
library;

import 'dart:convert';
import 'dart:io';

import 'package:tactical_engine/tactical_engine.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('Usage: solaris_characters.dart <notes dir> <pack.json> <out.json>');
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
    'advancement': constellation([
      for (final t in talents)
        if (t['constellation'] == true) t['name'] as String,
    ], classes.archetypes),
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

const _skills = [
  ('athletics', 'Athletics', 'STR'),
  ('intimidation', 'Intimidation', 'max(STR, CHA)'),
  ('evasion', 'Evasion', 'FIN'),
  ('piloting', 'Piloting', 'FIN'),
  ('sleightOfHand', 'Sleight of Hand', 'FIN'),
  ('stealth', 'Stealth', 'FIN'),
  ('traversal', 'Traversal', 'FIN'),
  ('painTolerance', 'Pain Tolerance', 'END'),
  ('arcaneResistance', 'Arcane Resistance', 'WIL'),
  ('composure', 'Composure', 'WIL'),
  ('awareness', 'Awareness', 'INT'),
  ('commonKnowledge', 'Common Knowledge', 'INT'),
  ('cyberwarfare', 'Cyberwarfare', 'INT'),
  ('engineering', 'Engineering', 'INT'),
  ('medicine', 'Medicine', 'INT'),
  ('naturalSciences', 'Natural Sciences', 'INT'),
  ('navigation', 'Navigation', 'INT'),
  ('psychAnalysis', 'Psychological Analysis', 'INT'),
  ('socialSciences', 'Social Sciences and Humanities', 'INT'),
  ('tacticalAssessment', 'Tactical Assessment', 'INT'),
  ('deception', 'Deception', 'CHA'),
  ('persuasion', 'Persuasion', 'CHA'),
];

const _wounds = [
  ('PsW', 'Psychic wounds'),
  ('ReW', 'Respiratory wounds'),
  ('NvW', 'Nervous wounds'),
  ('CvW', 'Cardiovascular wounds'),
  ('MsW.leftArm', 'Left arm (MsW)'),
  ('MsW.rightArm', 'Right arm (MsW)'),
  ('MsW.leftLeg', 'Left leg (MsW)'),
  ('MsW.rightLeg', 'Right leg (MsW)'),
];

/// The character sheet: the core stats and what follows from them, AP and
/// Stress, armor and wounds, skills, gear and story.
final sheet = {
  'layout': 'tabs',
  'sections': [
    {
      'title': 'Core',
      'fields': [
        for (final (name, label) in _stats) {'name': name, 'label': label, 'min': 0, 'max': 10, 'value': 3},
        {'name': 'class', 'label': 'Class', 'type': 'choice', 'options': ['Aether', 'Bastion', 'Specter', 'Synth', 'Vitalist']},
        {'name': 'threatLevel', 'label': 'Threat Level (Alpha 1 to Delta 4)', 'min': 1, 'max': 4, 'value': 1},
        {'name': 'rank', 'label': 'Rank', 'min': 1, 'value': 1},
        {'name': 'CP', 'label': 'CP', 'min': 0, 'value': 1},
        {'name': 'arcaneStat', 'label': 'Arcane stat', 'type': 'choice', 'options': ['WIL', 'INT', 'CHA']},
        {'name': 'rangedMod', 'label': 'Ranged modifier', 'type': 'computed', 'formula': 'FIN + threatLevel'},
        {'name': 'meleeMod', 'label': 'Melee modifier', 'type': 'computed', 'formula': 'STR + threatLevel'},
        {
          'name': 'arcaneMod',
          'label': 'Arcane modifier',
          'type': 'computed',
          'formula': 'threatLevel + (if arcaneStat == "WIL" then WIL else if arcaneStat == "INT" then INT else CHA)',
        },
        {'name': 'physical', 'label': 'Physical Prowess', 'type': 'computed', 'formula': 'ceil((STR + FIN + END) / 3)'},
        {'name': 'mental', 'label': 'Mental Prowess', 'type': 'computed', 'formula': 'ceil((INT + WIL + CHA) / 3)'},
      ],
    },
    {
      'title': 'Combat',
      'fields': [
        {'name': 'form', 'label': 'Combat Form', 'type': 'choice', 'options': ['Steady', 'Rush', 'Poise']},
        {
          'name': 'AP',
          'type': 'tracker',
          'max': '8 - sum("Armor", "apReduction") - sum("Weapon", "heavy") - 2 * min(ReW, 2) '
              '- (if ReW >= 3 then 4 else 0) + (if form == "Poise" then 2 else if form == "Rush" then -2 else 0)',
          'value': 'AP.max',
        },
        {'name': 'stressThreshold', 'label': 'Stress Threshold', 'type': 'computed', 'formula': 'max(5, END + WIL + threatLevel)'},
        {'name': 'Stress', 'type': 'tracker', 'max': 'stressThreshold'},
        {'name': 'AG', 'label': 'Armor Grade', 'type': 'tracker', 'max': 'sum("Armor", "grade")', 'value': 'AG.max'},
        {'name': 'tempAG', 'label': 'Temporary Armor Grade', 'type': 'tracker', 'max': 10},
        for (final (name, label) in _wounds) {'name': name, 'label': label, 'type': 'tracker', 'max': 4},
      ],
    },
    {
      'title': 'Skills',
      'fields': [
        for (final (name, label, stat) in _skills) ...[
          {'name': '$name.bonus', 'label': '$label bonus', 'min': -10, 'max': 20},
          {'name': name, 'label': label, 'type': 'computed', 'formula': '$stat + $name.bonus'},
        ],
      ],
    },
    {
      'title': 'Gear',
      'fields': [
        {'name': 'weapons', 'label': 'Weapons', 'type': 'items', 'kind': 'Weapon'},
        {'name': 'explosives', 'label': 'Explosives', 'type': 'items', 'kind': 'Explosive'},
        {'name': 'armor', 'label': 'Armor', 'type': 'items', 'kind': 'Armor'},
        {'name': 'items', 'label': 'Items', 'type': 'items', 'kind': 'Item'},
      ],
    },
    {
      'title': 'Story',
      'fields': [
        {'name': 'talents', 'label': 'Talents', 'type': 'items', 'kind': 'Talent'},
        {'name': 'flaws', 'label': 'Flaws', 'type': 'items', 'kind': 'Flaw'},
        {'name': 'classAbilities', 'label': 'Class', 'type': 'items', 'kind': 'Class'},
        {'name': 'archetypes', 'label': 'Archetypes', 'type': 'items', 'kind': 'Archetype'},
        {'name': 'background', 'label': 'Background', 'type': 'text'},
        {'name': 'profile', 'label': 'Psychological Profile', 'type': 'text'},
        {'name': 'notes', 'label': 'Notes', 'type': 'text'},
      ],
    },
  ],
  'actions': [
    {'name': 'Dodge', 'cost': [{'tracker': 'AP', 'amount': 2}], 'text': "Removes the attacker's highest die."},
    {'name': 'Parry', 'cost': [{'tracker': 'AP', 'amount': 2}], 'dice': 'd20', 'mod': 'meleeMod'},
    {'name': 'Move', 'cost': [{'tracker': 'AP', 'amount': 1}], 'text': 'One Sector.'},
    {'name': 'Overload check', 'dice': 'd20', 'mod': 'WIL'},
  ],
};

/// The Constellation, as far as the notes give it: its origin and its
/// unique talents, each a star giving its talent for 1 CP. The book draws
/// where each star sits and which touch; the notes don't have it, so every
/// star starts beside the origin, for the GM to place in the editor.
///
/// Below them, one under another, each class's archetypes: the class's own node, free and
/// open to that class alone, giving its core abilities; from it each
/// archetype's first level, at most 3 archetypes, then its next levels in
/// order, each an Individual Constellation Star's 5 CP and giving that
/// level's abilities. (Levels the Threat Level rewards give free: add the
/// CP first.)
Json constellation(List<String> talents, [Map<String, Map<String, int>> archetypes = const {}]) => {
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
        for (final (c, MapEntry(key: className, value: types)) in archetypes.entries.indexed) ...[
          {
            'name': className,
            'cost': 0,
            'condition': 'class == "$className"',
            'items': ['$className core'],
            'x': 0,
            'y': 5 + c * 6,
            'text': 'The $className class and its core abilities.',
          },
          for (final (a, MapEntry(key: type, value: levels)) in types.entries.indexed)
            for (var level = 1; level <= levels; level++)
              {
                'name': '$type $level',
                'group': level == 1 ? 'Archetype' : null,
                'cost': 5,
                'requires': [level == 1 ? className : '$type ${level - 1}'],
                if (level == 1) 'condition': 'count("Archetype") < 3',
                'items': ['$type, Level $level'],
                'x': a - (types.length - 1) / 2,
                'y': 5 + c * 6 + level,
                'text': level == 1 ? 'The $type archetype.' : '$type level $level.',
              }..removeWhere((_, v) => v == null),
        ],
      ],
    };
