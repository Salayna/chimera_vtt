/// Builds the Solaris Arcanum module with its threats, from the GM's own
/// notes of the books: the threat data cards (GM Guide chapter 4, Appendix
/// B) become the pack's tokens. The output is for the GM to install; it
/// holds book content, so it stays out of the repository.
///
///     dart run tool/solaris_threats.dart <vault>/Solaris\ Arcanum \
///         ../../packs/solaris-arcanum.json ../../packs/solaris-arcanum.local.json
library;

import 'dart:convert';
import 'dart:io';

import 'package:tactical_engine/tactical_engine.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('Usage: solaris_threats.dart <notes dir> <pack.json> <out.json>');
    exit(64);
  }
  final pack = SystemPack.fromJson(
      jsonDecode(File(args[1]).readAsStringSync()) as Json);
  final notes = Directory(args[0])
      .listSync(recursive: true)
      .whereType<File>()
      // Only the threat databases: equipment chapters use cards too.
      .where((f) =>
          f.path.endsWith('.md') &&
          f.path.contains('Threat Database') &&
          !f.path.contains('Loot'))
      .toList()
    // The GM Guide's database first: it holds every threat.
    ..sort((a, b) => _rank(a.path).compareTo(_rank(b.path)));
  final tokens = <String, TokenTemplate>{};
  for (final file in notes) {
    for (final t in threatsFromMarkdown(file.readAsStringSync(),
        conditions: {for (final c in pack.conditions) c.name})) {
      tokens.putIfAbsent(t.name, () => t);
    }
  }
  final out = pack.toJson()..['tokens'] = [for (final t in tokens.values) t.toJson()];
  // Checked like any installed pack.
  SystemPack.fromJson(out);
  File(args[2]).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('${tokens.length} threats → ${args[2]}');
}

int _rank(String path) => path.contains('GM Guide') ? 0 : 1;

/// The per-round slots a card counts with boxes; other boxed cells are
/// trackers.
const _slots = {
  'Movement',
  'Dodge',
  'Fight Back',
  'Attack Profiles',
  'Unique Actions',
  'Unique Action',
  'Unique Reactions',
  'Unique Reaction',
  'Unique Abilities',
};

/// The threat data cards in [markdown]. A card starts at a `| Name:` row
/// and runs to the next card or heading. Book tags named in [conditions]
/// become the token's starting conditions.
List<TokenTemplate> threatsFromMarkdown(String markdown, {Set<String> conditions = const {}}) {
  final lines = markdown.split('\n');
  final cards = <TokenTemplate>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('| Name:')) continue;
    var j = i + 1;
    while (j < lines.length && !lines[j].startsWith('| Name:') && !lines[j].startsWith('#')) {
      j++;
    }
    final card = _card(lines.sublist(i, j), conditions);
    if (card != null) cards.add(card);
    i = j - 1;
  }
  return cards;
}

TokenTemplate? _card(List<String> lines, Set<String> conditions) {
  // Tables (runs of `|` lines) and notes (runs of `>` lines), in order.
  final blocks = <List<String>>[];
  String? kind;
  for (final line in lines) {
    final k = line.startsWith('|') ? '|' : line.startsWith('>') ? '>' : null;
    if (k == null) {
      kind = null;
      continue;
    }
    if (k != kind) blocks.add([]);
    kind = k;
    blocks.last.add(line);
  }
  String? name, level, form;
  final slots = <String>[];
  final trackers = <TokenTracker>[];
  final notes = <String>[];
  final sections = <CardSection>[];
  final tags = <String>[];

  // A boxed cell: a slot, a tracker, or a note on one ("Immune").
  void boxed(String cell) {
    final m = RegExp(r'^(.+?):\s*(.*)$').firstMatch(cell);
    if (m == null) return;
    final key = _clean(m[1]!);
    final rest = m[2]!;
    final boxes = '☐'.allMatches(rest).length;
    final note = rest.replaceAll('☐', '').replaceAll(RegExp(r'[()]'), '').trim();
    if (key.isEmpty) return;
    if (boxes == 0) {
      if (note.isNotEmpty && note != '-') notes.add('$key $note');
      return;
    }
    if (_slots.contains(key)) {
      slots.add('$key $boxes');
    } else if (trackers.length < 20 && !trackers.any((t) => t.name == key)) {
      trackers.add((name: key.length > 30 ? key.substring(0, 30) : key, max: boxes, value: 0));
      if (note.isNotEmpty) notes.add('$key $note');
    }
  }

  for (final (b, block) in blocks.indexed) {
    if (block.first.startsWith('>')) {
      final text = [
        for (final l in block)
          if (l.replaceFirst(RegExp(r'^>\s?'), '').trim() case final t
              when t.isNotEmpty && !t.startsWith('[!'))
            t,
      ].join('\n');
      if (text.isEmpty) continue;
      final title = RegExp(r'^([^:\n]{1,60}):').firstMatch(text)?[1] ?? 'Note';
      sections.add((title: title, text: text));
      continue;
    }
    final rows = [
      for (final l in block)
        if (_cells(l) case final cells when !cells.every((c) => RegExp(r'^:?-*:?$').hasMatch(c)))
          cells,
    ];
    if (rows.isEmpty) continue;
    final head = rows.first;
    if (b == 0) {
      // The name table: name, Threat Level, Combat Form, and slots.
      for (final cell in rows.expand((r) => r)) {
        final m = RegExp(r'^(Name|Threat Level|Combat Form):\s*(.*)$').firstMatch(cell);
        switch (m?[1]) {
          case 'Name':
            name = m![2]!.trim();
          case 'Threat Level':
            level = m![2]!.trim();
          case 'Combat Form':
            form = m![2]!.trim();
          default:
            if (cell.contains('☐')) boxed(cell);
        }
      }
      continue;
    }
    if (head.first.startsWith('Damage Trackers')) {
      for (final cell in rows.skip(1).expand((r) => r)) {
        boxed(cell);
      }
      continue;
    }
    if (head.first.startsWith('Tags')) {
      tags.addAll(head.skip(1).where((c) => c.isNotEmpty));
      continue;
    }
    // Any other table: a section per titled column, text from the rows
    // below; boxed cells in it count as slots or trackers too.
    for (var c = 0; c < head.length; c++) {
      final title = head[c];
      if (title.isEmpty) continue;
      if (title.contains('☐')) boxed(title);
      final count = '☐'.allMatches(title).length;
      final clean = _clean(title.replaceAll('☐', '').replaceFirst(RegExp(r':\s*$'), ''));
      // Columns until the next titled one belong to this section.
      var end = c + 1;
      while (end < head.length && head[end].isEmpty) {
        end++;
      }
      final cells = [
        for (final row in rows.skip(1))
          for (var k = c; k < end && k < row.length; k++)
            if (row[k].isNotEmpty) row[k],
      ];
      // A one-line boxed cell ("Ammo: ☐☐☐") is a counter, not text.
      bool counter(String cell) => cell.contains('☐') && !cell.contains('\n');
      cells.where(counter).forEach(boxed);
      final text = cells.where((cell) => !counter(cell)).join('\n');
      // Slot counts without text are already in the profile.
      if (text.isEmpty) continue;
      final full = count > 0 ? '$clean ($count)' : clean;
      // A long header (a trait's whole rule) keeps a short title and leads
      // the text instead.
      final long = full.length > 80;
      final body = long ? '$full\n$text' : text;
      sections.add((
        title: long ? '${full.substring(0, 77)}…' : full,
        text: body.length > 4000 ? '${body.substring(0, 3999)}…' : body,
      ));
    }
  }
  final cardName = name;
  if (cardName == null || cardName.isEmpty) return null;
  final profile = [
    if (level != null) 'Threat Level $level',
    if (form != null) 'Combat Form $form',
    if (slots.isNotEmpty) 'Per round: ${slots.join(' · ')}',
    if (notes.isNotEmpty) notes.join(' · '),
  ].join('\n');
  return TokenTemplate(
    cardName.length > 60 ? cardName.substring(0, 60) : cardName,
    // "Rush / Poise" acts in both: the turn order holds one, the first.
    form: switch (form?.split('/').first.trim()) {
      'Pre-Rush' => 'Pre-Rush',
      final String f when f.isNotEmpty => '$f (NPC)',
      _ => null,
    },
    trackers: trackers,
    conditions: {for (final t in tags) if (conditions.contains(t)) t: null},
    card: [
      if (profile.isNotEmpty) (title: 'Profile', text: profile),
      ...sections.take(28),
      if (tags.isNotEmpty) (title: 'Tags', text: tags.join(' · ')),
    ],
  );
}

/// A table row's cells: split on unescaped pipes, `<br>` as new lines.
List<String> _cells(String row) {
  final parts = row.trim().split(RegExp(r'(?<!\\)\|'));
  return [
    for (final p in parts.sublist(1, parts.length - 1))
      p
          .replaceAll(r'\|', '|')
          .replaceAll(RegExp(r'\s*<br>\s*'), '\n')
          .replaceAll('**', '')
          .trim(),
  ];
}

/// A label without its emoji and decoration: "MsW 🦴" → "MsW".
String _clean(String label) =>
    label.replaceAll(RegExp(r'[^\p{L}\p{N} ()/&\-]', unicode: true), '').replaceAll(RegExp(r'\s+'), ' ').trim();
