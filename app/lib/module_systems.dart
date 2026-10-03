part of 'module_editor.dart';

/// The module editor's Sheet, Compendium and Advancement tabs. They change
/// the draft's JSON in place, in the pack format, so saving checks them as
/// any file is.

typedef _Change = void Function(VoidCallback edit);

/// Writes [v] at [key] as the format wants it: a whole number as a number,
/// other text as text (a formula), nothing when empty; [text] keeps it text.
void _put(Json map, String key, String v, {bool text = false, bool number = false}) {
  final t = v.trim();
  if (t.isEmpty) {
    map.remove(key);
  } else {
    map[key] = text ? t : int.tryParse(t) ?? (number ? num.tryParse(t) : null) ?? t;
  }
}

String _show(Object? v) => v == null ? '' : '$v';

/// "Origin, Might" as a list of names.
List<String> _names(String v) => [
      for (final p in v.split(','))
        if (p.trim().isNotEmpty) p.trim(),
    ];

/// The list at [key] in [map], made if missing, to change in place.
List<Object?> _listAt(Json map, String key) => (map[key] ??= <Object?>[]) as List<Object?>;

/// A text field writing one key of [map].
class _JsonField extends StatelessWidget {
  const _JsonField(this.map, this.key_,
      {required this.change,
      this.label,
      this.placeholder,
      this.text = false,
      this.number = false,
      this.maxLength = 500});

  final Json map;
  final String key_;
  final _Change change;
  final String? label;
  final String? placeholder;
  final bool text;

  /// Takes decimals: 1.5.
  final bool number;
  final int maxLength;

  @override
  Widget build(BuildContext context) => _Field(
        label: label,
        value: _show(map[key_]),
        placeholder: placeholder,
        maxLength: maxLength,
        onChanged: (v) => change(() => _put(map, key_, v, text: text, number: number)),
      );
}

/// A comma-separated list of names at [key] of [map].
class _NamesField extends StatelessWidget {
  const _NamesField(this.map, this.key_, {required this.change, this.placeholder});

  final Json map;
  final String key_;
  final _Change change;
  final String? placeholder;

  @override
  Widget build(BuildContext context) => _Field(
        value: [for (final n in map[key_] as List? ?? const []) '$n'].join(', '),
        placeholder: placeholder,
        maxLength: 1000,
        onChanged: (v) => change(() {
          final names = _names(v);
          names.isEmpty ? map.remove(key_) : map[key_] = names;
        }),
      );
}

/// A bordered card holding one row of a list, with a way to remove it.
class _Card extends StatelessWidget {
  const _Card(
      {super.key, required this.children, required this.onRemove, this.removeLabel = 'Remove'});

  final List<Widget> children;
  final VoidCallback onRemove;
  final String removeLabel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CvColors.bgSunken,
          borderRadius: BorderRadius.circular(CvRadii.md),
          border: Border.all(color: CvColors.borderSubtle),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: children),
          ),
          CvToolButton(
            icon: Lucide.trash2,
            label: removeLabel,
            danger: true,
            tooltipSide: AxisDirection.left,
            onPressed: onRemove,
          ),
        ]),
      );
}

Widget _add(String label, VoidCallback onPressed) => Align(
      alignment: Alignment.centerLeft,
      child: CvButton(label: label, icon: Lucide.plus, small: true, onPressed: onPressed),
    );

Widget _hint(String text) =>
    Text(text, style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary));

/// Sheet fields: each one's name, label, type and what its type needs.
class _FieldsEditor extends StatelessWidget {
  const _FieldsEditor(
      {required this.fields, required this.change, this.kinds = const [], this.onRename});

  final List<Object?> fields;
  final _Change change;

  /// Told when a field is renamed, from and to.
  final void Function(Object? from, Object? to)? onRename;

  /// The compendium's kinds, for items fields; none for a kind's own.
  final List<String> kinds;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final f in fields.cast<Json>())
            _Card(
              key: ObjectKey(f),
              removeLabel: 'Remove ${f['name'] ?? 'field'}',
              onRemove: () => change(() => fields.remove(f)),
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  SizedBox(
                    width: 150,
                    child: _Field(
                      value: _show(f['name']),
                      placeholder: 'Name: DEX.mod',
                      maxLength: 30,
                      onChanged: (v) => change(() {
                        final from = f['name'];
                        _put(f, 'name', v, text: true);
                        onRename?.call(from, f['name']);
                      }),
                    ),
                  ),
                  SizedBox(
                      width: 170,
                      child: _JsonField(f, 'label',
                          change: change, placeholder: 'Label: Dexterity', text: true, maxLength: 60)),
                  SizedBox(
                    width: 140,
                    child: CvDropdown<String>(
                      value: f['type'] as String? ?? 'number',
                      onChanged: (t) => change(() {
                        t == 'number' ? f.remove('type') : f['type'] = t;
                        if (t == 'items' && kinds.isNotEmpty) f['kind'] ??= kinds.first;
                      }),
                      entries: [
                        for (final t in FieldType.values)
                          if (t != FieldType.items || kinds.isNotEmpty) CvMenuItem(t.name, t.name),
                      ],
                    ),
                  ),
                  Expanded(
                      child: _JsonField(f, 'text',
                          change: change, placeholder: 'What it is, on hover', text: true)),
                ]),
                ..._typed(f),
              ],
            ),
          _add('Add a field', () => change(() => fields.add(<String, Object?>{'name': ''}))),
        ],
      );

  List<Widget> _typed(Json f) => switch (f['type'] as String? ?? 'number') {
        'number' => [
            Row(spacing: 8, children: [
              for (final (key, hint) in [('min', 'Min'), ('max', 'Max'), ('value', 'Start')])
                SizedBox(width: 110, child: _JsonField(f, key, change: change, placeholder: hint)),
            ]),
          ],
        'choice' => [
            _NamesField(f, 'options', change: change, placeholder: 'Options: Fighter, Wizard'),
          ],
        'computed' => [
            _JsonField(f, 'formula',
                change: change, placeholder: 'Formula: floor((DEX - 10) / 2)', text: true),
          ],
        'tracker' => [
            Row(spacing: 8, children: [
              SizedBox(width: 110, child: _JsonField(f, 'min', change: change, placeholder: 'Min: 0')),
              Expanded(
                  child: _JsonField(f, 'max', change: change, placeholder: 'Max: 8 - armor')),
              Expanded(
                  child: _JsonField(f, 'value', change: change, placeholder: 'Start: AP.max')),
            ]),
          ],
        'items' => [
            SizedBox(
              width: 220,
              child: CvDropdown<String>(
                label: 'Kind',
                value: f['kind'] as String? ?? kinds.first,
                onChanged: (k) => change(() => f['kind'] = k),
                entries: [for (final k in kinds) CvMenuItem(k, k)],
              ),
            ),
          ],
        _ => const [],
      };
}

/// Actions: each one's costs, dice, modifier, rolls and outcome bands.
class _ActionsEditor extends StatelessWidget {
  const _ActionsEditor({required this.actions, required this.change});

  final List<Object?> actions;
  final _Change change;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final a in actions.cast<Json>())
            _Card(
              key: ObjectKey(a),
              removeLabel: 'Remove ${a['name'] ?? 'action'}',
              onRemove: () => change(() => actions.remove(a)),
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  SizedBox(
                      width: 180,
                      child: _JsonField(a, 'name',
                          change: change, placeholder: 'Name: Quick Shot', text: true, maxLength: 60)),
                  Expanded(
                      child: _JsonField(a, 'text',
                          change: change, placeholder: 'What it does', text: true, maxLength: 2000)),
                ]),
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  SizedBox(
                      width: 120,
                      child: _JsonField(a, 'dice',
                          change: change, placeholder: 'Dice: d20', text: true, maxLength: 40)),
                  Expanded(
                      child: _JsonField(a, 'mod', change: change, placeholder: '+ Mod: FIN + TL')),
                  SizedBox(
                      width: 140,
                      child: _JsonField(a, 'times', change: change, placeholder: 'Times: 1')),
                ]),
                for (final c in _listAt(a, 'cost').cast<Json>())
                  Row(key: ObjectKey(c), spacing: 8, children: [
                    const SizedBox(width: 60, child: Text('Costs')),
                    SizedBox(
                        width: 100,
                        child: _JsonField(c, 'amount', change: change, placeholder: 'Amount: 1')),
                    Expanded(
                        child: _JsonField(c, 'tracker',
                            change: change, placeholder: 'Tracker: AP', text: true, maxLength: 30)),
                    CvToolButton(
                      icon: Lucide.x,
                      label: 'Remove this cost',
                      tooltipSide: AxisDirection.left,
                      onPressed: () => change(() => (a['cost'] as List).remove(c)),
                    ),
                  ]),
                for (final b in _listAt(a, 'bands').cast<Json>())
                  Row(key: ObjectKey(b), spacing: 8, children: [
                    const SizedBox(width: 60, child: Text('Band')),
                    SizedBox(
                        width: 140,
                        child: _JsonField(b, 'name',
                            change: change, placeholder: 'Grazing', text: true, maxLength: 30)),
                    SizedBox(
                        width: 90, child: _JsonField(b, 'min', change: change, placeholder: 'From: 12')),
                    Expanded(
                        child: _JsonField(b, 'text', change: change, placeholder: '1 Stress', text: true)),
                    CvToolButton(
                      icon: Lucide.x,
                      label: 'Remove this band',
                      tooltipSide: AxisDirection.left,
                      onPressed: () => change(() => (a['bands'] as List).remove(b)),
                    ),
                  ]),
                Row(spacing: 8, children: [
                  CvButton(
                      label: 'Add a cost',
                      icon: Lucide.plus,
                      small: true,
                      variant: CvButtonVariant.ghost,
                      onPressed: () =>
                          change(() => _listAt(a, 'cost').add(<String, Object?>{'tracker': ''}))),
                  CvButton(
                      label: 'Add a band',
                      icon: Lucide.plus,
                      small: true,
                      variant: CvButtonVariant.ghost,
                      onPressed: () => change(() => _listAt(a, 'bands').add(<String, Object?>{'name': ''}))),
                ]),
              ],
            ),
          _add('Add an action', () => change(() => actions.add(<String, Object?>{'name': ''}))),
        ],
      );
}

/// The Sheet tab: sections of fields, and the character's actions.
class _SheetTab extends StatelessWidget {
  const _SheetTab({required this.draft, required this.change});

  final ModuleDraft draft;
  final _Change change;

  @override
  Widget build(BuildContext context) {
    final sheet = draft.sheet;
    if (sheet == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
        _hint('Players make characters only for a system with a sheet.'),
        CvButton(
          label: 'Give characters a sheet',
          icon: Lucide.plus,
          onPressed: () => change(() => draft.sheet = {
                'sections': [
                  {'title': 'Abilities', 'fields': <Object?>[]},
                ],
              }),
        ),
      ]);
    }
    final kinds = [
      for (final k in draft.compendium?['kinds'] as List? ?? const []) '${(k as Json)['name']}',
    ];
    final sections = _listAt(sheet, 'sections');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      _hint('Fields formulas read by name (DEX, DEX.mod); numbers, texts, choices, '
          'checkboxes, computed fields, trackers and items. Formulas: + - * /, '
          'min, max, floor, ceil, round, abs, if … then … else, count("Kind"), '
          'sum("Kind", "field").'),
      SizedBox(
        width: 260,
        child: CvDropdown<String>(
          label: 'Layout',
          value: sheet['layout'] as String? ?? 'list',
          onChanged: (l) => change(() => l == 'list' ? sheet.remove('layout') : sheet['layout'] = l),
          entries: const [
            CvMenuItem('list', 'Sections in one list'),
            CvMenuItem('columns', 'Sections in columns'),
            CvMenuItem('tabs', 'A tab for each section'),
          ],
        ),
      ),
      for (final s in sections.cast<Json>())
        Column(key: ObjectKey(s), crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Row(spacing: 8, children: [
            SizedBox(
                width: 260,
                child: _JsonField(s, 'title',
                    change: change, placeholder: 'Section: Abilities', text: true, maxLength: 60)),
            const Spacer(),
            CvButton(
              label: 'Remove section',
              icon: Lucide.trash2,
              variant: CvButtonVariant.dangerGhost,
              small: true,
              onPressed: () => change(() => sections.remove(s)),
            ),
          ]),
          _FieldsEditor(fields: _listAt(s, 'fields'), change: change, kinds: kinds),
        ]),
      _add('Add a section',
          () => change(() => sections.add(<String, Object?>{'title': '', 'fields': <Object?>[]}))),
      const CvOverline('Actions'),
      _hint("The character's own buttons: Dodge, Parry."),
      _ActionsEditor(actions: _listAt(sheet, 'actions'), change: change),
      Align(
        alignment: Alignment.centerLeft,
        child: CvButton(
          label: 'Remove the sheet',
          icon: Lucide.trash2,
          variant: CvButtonVariant.dangerGhost,
          small: true,
          onPressed: () => change(() => draft.sheet = null),
        ),
      ),
    ]);
  }
}

/// The Compendium tab: its kinds, and each kind's fields, actions and
/// entries.
class _CompendiumTab extends StatefulWidget {
  const _CompendiumTab({required this.draft, required this.change});

  final ModuleDraft draft;
  final _Change change;

  @override
  State<_CompendiumTab> createState() => _CompendiumTabState();
}

class _CompendiumTabState extends State<_CompendiumTab> {
  Json? _kind;

  @override
  Widget build(BuildContext context) {
    final change = widget.change;
    final compendium = widget.draft.compendium ??= {'kinds': <Object?>[], 'entries': <Object?>[]};
    final kinds = _listAt(compendium, 'kinds').cast<Json>();
    final entries = _listAt(compendium, 'entries');
    final kind = kinds.contains(_kind) ? _kind : kinds.firstOrNull;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
      SizedBox(
        width: 220,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
          for (final k in kinds)
            CvButton(
              key: ObjectKey(k),
              label: _show(k['name']).isEmpty ? 'Unnamed kind' : _show(k['name']),
              variant: k == kind ? CvButtonVariant.primary : CvButtonVariant.ghost,
              small: true,
              block: true,
              onPressed: () => setState(() => _kind = k),
            ),
          const SizedBox(height: 8),
          CvButton(
            label: 'Add a kind',
            icon: Lucide.plus,
            small: true,
            block: true,
            onPressed: () => change(() {
              final k = <String, Object?>{'name': '', 'fields': <Object?>[]};
              _listAt(compendium, 'kinds').add(k);
              _kind = k;
            }),
          ),
        ]),
      ),
      Expanded(
        child: kind == null
            ? _hint('Kinds of things characters own as items: Weapon, Armor, Talent. '
                'Each declares its fields, and its entries fill them in.')
            : Column(
                key: ObjectKey(kind),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  Row(spacing: 8, children: [
                    SizedBox(
                      width: 260,
                      child: _Field(
                        label: 'Kind',
                        value: _show(kind['name']),
                        placeholder: 'Weapon',
                        maxLength: 30,
                        onChanged: (v) => change(() {
                          // Its entries and items fields name it: rename them too.
                          final was = kind['name'];
                          kind['name'] = v.trim();
                          for (final e in entries.cast<Json>()) {
                            if (e['kind'] == was) e['kind'] = v.trim();
                          }
                          for (final s in widget.draft.sheet?['sections'] as List? ?? const []) {
                            for (final f in (s as Json)['fields'] as List? ?? const []) {
                              if ((f as Json)['kind'] == was) f['kind'] = v.trim();
                            }
                          }
                        }),
                      ),
                    ),
                    const Spacer(),
                    CvButton(
                      label: 'Remove kind',
                      icon: Lucide.trash2,
                      variant: CvButtonVariant.dangerGhost,
                      small: true,
                      onPressed: () => change(() {
                        _listAt(compendium, 'kinds').remove(kind);
                        entries.removeWhere((e) => (e as Json)['kind'] == kind['name']);
                      }),
                    ),
                  ]),
                  const CvOverline('Fields'),
                  _hint('What each entry fills in, and trackers each item keeps: ammo, '
                      'at most capacity.'),
                  _FieldsEditor(
                    fields: _listAt(kind, 'fields'),
                    change: change,
                    // Its entries' values follow the field.
                    onRename: (from, to) {
                      for (final e in entries.cast<Json>()) {
                        final values = e['values'];
                        if (e['kind'] == kind['name'] && values is Map && values.containsKey(from)) {
                          final v = values.remove(from);
                          if (to != null) values[to] = v;
                        }
                      }
                    },
                  ),
                  const CvOverline('Actions'),
                  _hint('Buttons every item of the kind has: Reload.'),
                  _ActionsEditor(actions: _listAt(kind, 'actions'), change: change),
                  const CvOverline('Entries'),
                  for (final e in entries.cast<Json>())
                    if (e['kind'] == kind['name'])
                      _Card(
                        key: ObjectKey(e),
                        removeLabel: 'Remove ${e['name'] ?? 'entry'}',
                        onRemove: () => change(() => entries.remove(e)),
                        children: [
                          SizedBox(
                              width: 300,
                              child: _JsonField(e, 'name',
                                  change: change, placeholder: 'Name: P9 Pistol', text: true, maxLength: 60)),
                          _EntryValues(entry: e, kind: kind, change: change),
                          for (final c in _listAt(e, 'card').cast<Json>())
                            Row(key: ObjectKey(c), crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                              SizedBox(
                                  width: 200,
                                  child: _JsonField(c, 'title',
                                      change: change, placeholder: 'Card section', text: true, maxLength: 80)),
                              Expanded(
                                  child: _JsonField(c, 'text',
                                      change: change, placeholder: 'Its text', text: true, maxLength: 4000)),
                              CvToolButton(
                                icon: Lucide.x,
                                label: 'Remove this section',
                                tooltipSide: AxisDirection.left,
                                onPressed: () => change(() => (e['card'] as List).remove(c)),
                              ),
                            ]),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: CvButton(
                              label: 'Add a card section',
                              icon: Lucide.plus,
                              small: true,
                              variant: CvButtonVariant.ghost,
                              onPressed: () => change(() =>
                                  _listAt(e, 'card').add(<String, Object?>{'title': '', 'text': ''})),
                            ),
                          ),
                          const CvOverline('Its actions'),
                          _ActionsEditor(actions: _listAt(e, 'actions'), change: change),
                        ],
                      ),
                  _add('Add an entry',
                      () => change(() => entries.add(<String, Object?>{'kind': kind['name'], 'name': ''}))),
                ],
              ),
      ),
    ]);
  }
}

/// An entry's values for its kind's fields, trackers and computed fields
/// aside (items start trackers themselves).
class _EntryValues extends StatelessWidget {
  const _EntryValues({required this.entry, required this.kind, required this.change});

  final Json entry;
  final Json kind;
  final _Change change;

  @override
  Widget build(BuildContext context) {
    final values = (entry['values'] ??= <String, Object?>{}) as Json;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in _listAt(kind, 'fields').cast<Json>())
        if (const {null, 'number', 'text', 'choice', 'checkbox'}.contains(f['type']) &&
            _show(f['name']).isNotEmpty)
          SizedBox(
            width: 180,
            child: f['type'] == 'checkbox'
                ? CvSwitch(
                    label: Text(_show(f['label'] ?? f['name'])),
                    value: values[f['name']] == true,
                    onChanged: (v) => change(() => values[f['name'] as String] = v),
                  )
                : _JsonField(values, f['name'] as String,
                    change: change,
                    label: _show(f['label'] ?? f['name']),
                    text: f['type'] == 'text' || f['type'] == 'choice'),
          ),
    ]);
  }
}

/// The Advancement tab: its tracks (a Threat Level chain, a Constellation),
/// each with what it spends and its nodes.
class _AdvancementTab extends StatefulWidget {
  const _AdvancementTab({required this.draft, required this.change});

  final ModuleDraft draft;
  final _Change change;

  @override
  State<_AdvancementTab> createState() => _AdvancementTabState();
}

class _AdvancementTabState extends State<_AdvancementTab> {
  Json? _track;

  @override
  Widget build(BuildContext context) {
    final change = widget.change;
    final tracks = widget.draft.advancements;
    final adv = tracks.contains(_track) ? _track : tracks.firstOrNull;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
      SizedBox(
        width: 220,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
          for (final t in tracks)
            CvButton(
              key: ObjectKey(t),
              label: _show(t['name']).isEmpty ? 'Unnamed track' : _show(t['name']),
              variant: t == adv ? CvButtonVariant.primary : CvButtonVariant.ghost,
              small: true,
              block: true,
              onPressed: () => setState(() => _track = t),
            ),
          const SizedBox(height: 8),
          CvButton(
            label: 'Add a track',
            icon: Lucide.plus,
            small: true,
            block: true,
            onPressed: () => change(() {
              final t = <String, Object?>{'name': '', 'field': '', 'nodes': <Object?>[]};
              tracks.add(t);
              _track = t;
            }),
          ),
        ]),
      ),
      Expanded(
        child: adv == null
            ? _hint('Tracks of nodes characters take with a sheet number: a '
                'Constellation bought with CP, levels reached with XP.')
            : _trackForm(adv, change, () => change(() => tracks.remove(adv))),
      ),
    ]);
  }

  Widget _trackForm(Json adv, _Change change, VoidCallback onRemove) {
    final nodes = _listAt(adv, 'nodes');
    return Column(key: ObjectKey(adv), crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        SizedBox(
            width: 260,
            child: _JsonField(adv, 'name',
                change: change, label: 'Name', placeholder: 'Constellation', text: true, maxLength: 30)),
        SizedBox(
            width: 260,
            child: _JsonField(adv, 'field',
                change: change, label: 'Spends', placeholder: 'A sheet number: CP', text: true, maxLength: 30)),
        const Spacer(),
        CvButton(
          label: 'Remove the track',
          icon: Lucide.trash2,
          variant: CvButtonVariant.dangerGhost,
          small: true,
          onPressed: onRemove,
        ),
      ]),
      _hint('A node is taken once any node it requires is, and all it requires '
          'all of, its condition holds and its cost is paid. Its group counts '
          'with count("Group"), across tracks.'),
      for (final n in nodes.cast<Json>())
        _Card(
          key: ObjectKey(n),
          removeLabel: 'Remove ${n['name'] ?? 'node'}',
          onRemove: () => change(() => nodes.remove(n)),
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              SizedBox(
                  width: 180,
                  child: _JsonField(n, 'name', change: change, placeholder: 'Name', text: true, maxLength: 60)),
              SizedBox(
                  width: 130,
                  child: _JsonField(n, 'group', change: change, placeholder: 'Group', text: true, maxLength: 30)),
              SizedBox(width: 90, child: _JsonField(n, 'cost', change: change, placeholder: 'Cost: 1')),
              SizedBox(width: 70, child: _JsonField(n, 'x', change: change, placeholder: 'x')),
              SizedBox(width: 70, child: _JsonField(n, 'y', change: change, placeholder: 'y')),
              Expanded(
                  child: _JsonField(n, 'text', change: change, placeholder: 'What it grants', text: true)),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Expanded(child: _NamesField(n, 'requires', change: change, placeholder: 'Requires one of')),
              Expanded(child: _NamesField(n, 'requiresAll', change: change, placeholder: 'Requires all of')),
              Expanded(
                  child: _JsonField(n, 'condition',
                      change: change, placeholder: 'Condition: XP >= 900', text: true)),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Expanded(
                child: _Field(
                  value: [
                    for (final MapEntry(:key, :value) in (n['adds'] as Map? ?? const {}).entries)
                      '$key ${value is int && value >= 0 ? '+' : ''}$value',
                  ].join(', '),
                  placeholder: 'Adds: STR +1, AP +1',
                  maxLength: 500,
                  onChanged: (v) => change(() {
                    final adds = {
                      for (final part in _names(v))
                        if (RegExp(r'^(\S+)\s+([+-]?\d+)$').firstMatch(part) case final m?)
                          m[1]!: int.parse(m[2]!.replaceFirst('+', '')),
                    };
                    adds.isEmpty ? n.remove('adds') : n['adds'] = adds;
                  }),
                ),
              ),
              Expanded(child: _NamesField(n, 'items', change: change, placeholder: 'Gives entries')),
            ]),
          ],
        ),
      _add('Add a node', () => change(() => nodes.add(<String, Object?>{'name': ''}))),
    ]);
  }
}

/// A tag's effects: the engine's building blocks, each with what it needs.
class _EffectsEditor extends StatelessWidget {
  const _EffectsEditor({required this.effects, required this.change});

  final List<Json> effects;
  final _Change change;

  static const _types = {
    'roll': 'Advantage or disadvantage',
    'moveCost': 'Moving costs more',
    'blocksSight': 'Blocks sight',
    'occupantLimit': 'Holds at most',
    'entryCheck': 'Entering needs a check',
  };

  static Json _start(String type) => switch (type) {
        'roll' => {'type': type, 'edge': -1},
        'moveCost' => {'type': type, 'multiplier': 2},
        'occupantLimit' => {'type': type, 'max': 1},
        'entryCheck' => {'type': type, 'check': 'Traversal'},
        _ => {'type': type},
      };

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        for (final (i, e) in effects.indexed)
          Row(key: ObjectKey(e), spacing: 8, children: [
            SizedBox(
              width: 230,
              child: CvDropdown<String>(
                value: e['type'] as String,
                onChanged: (t) => change(() => effects[i] = _start(t)),
                entries: [for (final MapEntry(:key, :value) in _types.entries) CvMenuItem(key, value)],
              ),
            ),
            ...switch (e['type']) {
              'roll' => [
                  SizedBox(
                      width: 140,
                      child: _JsonField(e, 'edge', change: change, placeholder: 'Edge: -1')),
                  SizedBox(
                    width: 220,
                    child: CvSwitch(
                      value: e['scaled'] == true,
                      onChanged: (v) => change(() => v ? e['scaled'] = true : e.remove('scaled')),
                      label: const Text("Times the tag's value"),
                    ),
                  ),
                ],
              'moveCost' => [
                  SizedBox(
                      width: 160,
                      child: _JsonField(e, 'multiplier',
                          change: change, placeholder: 'Times: 2', number: true)),
                ],
              'occupantLimit' => [
                  SizedBox(width: 140, child: _JsonField(e, 'max', change: change, placeholder: 'Max: 1')),
                ],
              'entryCheck' => [
                  SizedBox(
                      width: 200,
                      child: _JsonField(e, 'check',
                          change: change, placeholder: 'Traversal', text: true, maxLength: 60)),
                ],
              _ => const <Widget>[],
            },
            const Spacer(),
            CvToolButton(
              icon: Lucide.x,
              label: 'Remove this effect',
              tooltipSide: AxisDirection.left,
              onPressed: () => change(() => effects.removeAt(i)),
            ),
          ]),
        Align(
          alignment: Alignment.centerLeft,
          child: CvButton(
            label: 'Add an effect',
            icon: Lucide.plus,
            small: true,
            variant: CvButtonVariant.ghost,
            onPressed: () => change(() => effects.add(_start('roll'))),
          ),
        ),
      ]);
}

/// The Try it tab: the module's sheet on a sample character, as players will
/// see it, its formulas worked out as values change and its actions rolled
/// here, since no GM is there to roll them.
class _PreviewTab extends StatefulWidget {
  const _PreviewTab({required this.pack, required this.problem});

  /// The module as it stands; null while something's wrong with it.
  final SystemPack? pack;
  final String? problem;

  @override
  State<_PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<_PreviewTab> {
  final _random = math.Random();
  Character? _sample;
  final _rolls = <String>[];

  /// The sample, kept across edits and cleaned against the module as it
  /// is now.
  Character _character(SystemPack pack) => cleaned(
      _sample ??= Character(
        id: const CharacterId('preview'),
        owner: const PlayerId('me'),
        system: pack.id,
        name: 'Sample',
        values: pack.sheet!.start(),
      ),
      pack);

  void _use(SystemPack pack, ActionDef action, Item? item) {
    final use = useAction(pack, _character(pack), action, item: item);
    if (use is! UseAction) return;
    final dice = use.dice == null ? null : DiceFormula.tryParse(use.dice!);
    setState(() {
      _sample = use.character;
      _rolls.insert(0, [
        '${action.name}${use.dice == null ? '' : ' (${use.dice})'}',
        if (dice != null)
          for (var i = 0; i < use.times; i++)
            () {
              final faces = dice.roll(_random);
              final total = dice.total(faces);
              final band = action.bandFor(total);
              return '$total${band == null ? action.bands.isEmpty ? '' : ' miss' : ' ${band.name}: ${band.text}'}';
            }(),
      ].join(' · '));
      if (_rolls.length > 8) _rolls.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.pack;
    if (pack == null) {
      return Text(widget.problem ?? '',
          style: CvTypography.body.copyWith(color: CvColors.textDanger));
    }
    if (pack.sheet == null) return _hint('Give characters a sheet to try it.');
    final c = _character(pack);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Row(children: [
        Expanded(
            child: _hint('A sample character: change values, add items, take nodes '
                'and use actions, rolled here.')),
        CvButton(
          label: 'Start again',
          icon: Lucide.refreshCw,
          small: true,
          variant: CvButtonVariant.ghost,
          onPressed: () => setState(() {
            _sample = null;
            _rolls.clear();
          }),
        ),
      ]),
      for (final r in _rolls)
        Text(r, style: CvTypography.bodySm.copyWith(fontFamily: CvTypography.mono)),
      SheetView(
        pack: pack,
        character: c,
        onChanged: (changed) => setState(() => _sample = changed),
        onAction: (action, item) => _use(pack, action, item),
      ),
    ]);
  }
}
