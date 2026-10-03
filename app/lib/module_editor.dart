import 'package:chimera_core/chimera_core.dart' show AssetId, DiceFormula;
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart';

import 'assets.dart';
import 'library.dart' show pickImage;
import 'theme.dart';
import 'ui/cv.dart';
import 'ui/hub.dart';

/// A module being written: plain rows the editor changes in place, turned
/// into a [SystemPack] on save. What the editor doesn't show (effects,
/// range bands, turn forms, token trackers and starting tags) is carried
/// over from [base] unchanged.
// ponytail: those are edited in the module's file for now; add them here
// when GMs ask, they're already in the format.
class ModuleDraft {
  ModuleDraft([this.base])
      : name = base?.name ?? '',
        description = base?.description ?? '',
        cover = base?.cover,
        unit = base?.unit ?? 'cell',
        unitsPerStep = base?.unitsPerStep ?? 1,
        diagonal = base?.diagonal ?? DiagonalRule.chebyshev,
        initiative = base?.initiative ?? '',
        tags = [for (final t in base?.tags.values ?? const <TagDef>[]) DraftTag.of(t)],
        trackers = [
          for (final t in base?.trackers ?? const <TrackerDef>[])
            DraftTracker(t.name, t.min, t.max, t.text),
        ],
        tokens = [
          for (final t in base?.tokens.values ?? const <TokenTemplate>[]) DraftToken.of(t),
        ];

  /// The installed module being edited; null for a new one.
  final SystemPack? base;
  String name;
  String description;
  String? cover;
  String unit;
  double unitsPerStep;
  DiagonalRule diagonal;
  String initiative;
  final List<DraftTag> tags;
  final List<DraftTracker> trackers;
  final List<DraftToken> tokens;

  /// A new module's id, from its name: "Blades in the Dark" is
  /// `blades-in-the-dark`. An edited one keeps its own.
  String get id {
    if (base case final base?) return base.id;
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final short = slug.length > 40 ? slug.substring(0, 40) : slug;
    return short.isEmpty ? 'module' : short;
  }

  /// The module, checked as any installed file is. Throws a
  /// [FormatException] saying what to fix. Saving an edit bumps the version.
  SystemPack build() {
    if (name.trim().isEmpty) throw const FormatException('Name the module.');
    if (builtInPacks.containsKey(id)) {
      throw FormatException('"$id" is a built-in system: pick another name.');
    }
    // A pack keys these by name, so a twin would silently replace the first.
    for (final (what, names) in [
      ('tags', [for (final t in tags) t.name.trim()]),
      ('trackers', [for (final t in trackers) t.name.trim()]),
      ('tokens', [for (final t in tokens) t.name.trim()]),
    ]) {
      final seen = <String>{};
      for (final n in names) {
        if (!seen.add(n)) {
          throw FormatException(n.isEmpty
              ? 'Name all the $what.'
              : 'Two $what are called "$n".');
        }
      }
    }
    final pack = SystemPack(
      id: id,
      name: name.trim(),
      version: (base?.version ?? 0) + 1,
      description: description.trim(),
      cover: cover,
      topology: base?.topology ?? TopologyKind.square,
      diagonal: diagonal,
      unit: unit.trim(),
      unitsPerStep: unitsPerStep,
      bands: base?.bands ?? const [],
      initiative: initiative.trim().isEmpty ? null : initiative.trim(),
      forms: base?.forms ?? const [],
      tokens: [for (final t in tokens) t.build()],
      trackers: [
        for (final t in trackers)
          TrackerDef(t.name.trim(), min: t.min, max: t.max, text: t.text.trim()),
      ],
      tags: [for (final t in tags) t.build()],
    );
    if (pack.initiative case final f? when DiceFormula.tryParse(f) == null) {
      throw FormatException('"$f" isn\'t a dice formula: try d20 or 2d6+1.');
    }
    // The same checks as a file from anyone: names, lengths, duplicates.
    return SystemPack.fromJson(pack.toJson());
  }
}

enum TagKind { condition, region, sector }

class DraftTag {
  DraftTag(this.name, this.kind,
      {this.valued = false, this.text = '', this.color, this.effects = const []});

  factory DraftTag.of(TagDef t) => DraftTag(
        t.name,
        t.condition ? TagKind.condition : t.sector ? TagKind.sector : TagKind.region,
        valued: t.valued,
        text: t.text,
        color: t.color,
        effects: t.effects,
      );

  String name;
  TagKind kind;
  bool valued;
  String text;
  final String? color;
  final List<Effect> effects;

  TagDef build() => TagDef(name.trim(),
      condition: kind == TagKind.condition,
      sector: kind == TagKind.sector,
      valued: valued,
      color: color,
      effects: effects,
      text: text.trim());
}

class DraftTracker {
  DraftTracker(this.name, [this.min = 0, this.max, this.text = '']);

  String name;
  int min;
  int? max;
  String text;
}

class DraftSection {
  DraftSection(this.title, [this.text = '', this.image]);

  String title;
  String text;
  String? image;
}

class DraftToken {
  DraftToken(this.name,
      {this.image,
      this.size = 1,
      List<DraftSection>? card,
      this.form,
      this.trackers = const [],
      this.conditions = const {}})
      : card = card ?? [];

  factory DraftToken.of(TokenTemplate t) => DraftToken(t.name,
      image: t.image,
      size: t.size,
      card: [for (final c in t.card) DraftSection(c.title, c.text, c.image)],
      form: t.form,
      trackers: t.trackers,
      conditions: t.conditions);

  String name;
  String? image;
  int size;
  final List<DraftSection> card;
  final String? form;
  final List<TokenTracker> trackers;
  final Map<String, int?> conditions;

  TokenTemplate build() => TokenTemplate(name.trim(),
      image: image,
      size: size,
      form: form,
      trackers: trackers,
      conditions: conditions,
      card: [
        for (final c in card)
          (title: c.title.trim(), text: c.text.trim(), image: c.image),
      ]);
}

enum _Section { about, rules, tags, trackers, tokens }

/// Writing a module in the app (design: the hub's pages): what it is, its
/// rules, its conditions and region tags, its trackers, and its ready-made
/// tokens with their pictures and cards. Saving installs it.
class ModuleEditor extends StatefulWidget {
  const ModuleEditor({
    super.key,
    required this.assets,
    required this.onSave,
    required this.onClose,
    this.module,
  });

  /// The installed module to edit; null for a new one.
  final SystemPack? module;
  final AssetStore assets;

  /// Installs the module. A throw is shown and the editor stays open.
  final Future<void> Function(SystemPack pack) onSave;
  final VoidCallback onClose;

  @override
  State<ModuleEditor> createState() => _ModuleEditorState();
}

class _ModuleEditorState extends State<ModuleEditor> {
  late final _draft = ModuleDraft(widget.module);
  var _section = _Section.about;
  DraftToken? _token;
  String? _error;
  bool _saving = false;

  void _change(VoidCallback edit) => setState(() {
        edit();
        _error = null;
      });

  Future<void> _save() async {
    final SystemPack pack;
    try {
      pack = _draft.build();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(pack);
      widget.onClose();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Uploads a picked image; null when none is picked.
  Future<String?> _pickImage() async {
    try {
      return (await pickImage(widget.assets))?.id.value;
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return HubPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
            Expanded(
              child: HubTitle(
                d.base == null ? 'New module' : 'Edit ${d.base!.name}',
                overline: 'Module · ${d.id}',
                subtitle: 'A game system with its rules, and the tokens and '
                    'cards it brings. Saving installs it; Export shares it '
                    'with its images.',
              ),
            ),
            CvButton(
              label: 'Cancel',
              variant: CvButtonVariant.ghost,
              onPressed: widget.onClose,
            ),
            CvButton(
              label: _saving ? 'Saving…' : 'Save module',
              icon: Lucide.check,
              variant: CvButtonVariant.primary,
              onPressed: _saving ? null : _save,
            ),
          ]),
          if (_error case final error?)
            Text(error, style: CvTypography.bodySm.copyWith(color: CvColors.textDanger)),
          SizedBox(
            width: 640,
            child: CvSegmentedControl(
              segments: [
                (value: _Section.about, label: 'About', icon: Lucide.info, checked: null),
                (value: _Section.rules, label: 'Rules', icon: Lucide.ruler, checked: null),
                (value: _Section.tags, label: 'Tags ${d.tags.length}', icon: Lucide.scan, checked: null),
                (value: _Section.trackers, label: 'Trackers ${d.trackers.length}', icon: Lucide.circleDashed, checked: null),
                (value: _Section.tokens, label: 'Tokens ${d.tokens.length}', icon: Lucide.circle, checked: null),
              ],
              value: _section,
              onChanged: (s) => setState(() => _section = s),
            ),
          ),
          CvPanel(
            solid: true,
            padding: const EdgeInsets.all(24),
            child: switch (_section) {
              _Section.about => _about(),
              _Section.rules => _rules(),
              _Section.tags => _tags(),
              _Section.trackers => _trackers(),
              _Section.tokens => _tokens(),
            },
          ),
        ],
      ),
    );
  }

  Widget _about() {
    final d = _draft;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
          _Field(
            label: 'Name',
            value: d.name,
            placeholder: 'Blades in the Dark',
            maxLength: 60,
            onChanged: (v) => _change(() => d.name = v),
          ),
          _Field(
            label: 'Description',
            value: d.description,
            placeholder: 'What it is, and what it brings.',
            maxLength: 2000,
            multiline: true,
            onChanged: (v) => _change(() => d.description = v),
          ),
        ]),
      ),
      SizedBox(
        width: 280,
        child: _ImagePick(
          label: 'Cover',
          image: d.cover,
          assets: widget.assets,
          height: 160,
          onPick: () async {
            final id = await _pickImage();
            if (id != null) _change(() => d.cover = id);
          },
          onClear: () => _change(() => d.cover = null),
        ),
      ),
    ]);
  }

  Widget _rules() {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Row(spacing: 16, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _Field(
            label: 'Unit',
            value: d.unit,
            placeholder: 'ft, sector, zone',
            maxLength: 20,
            onChanged: (v) => _change(() => d.unit = v),
          ),
        ),
        Expanded(
          child: _Field(
            label: 'Units a cell',
            value: _number(d.unitsPerStep),
            placeholder: '5',
            maxLength: 8,
            onChanged: (v) {
              final n = double.tryParse(v);
              if (n != null && n > 0) _change(() => d.unitsPerStep = n);
            },
          ),
        ),
        Expanded(
          child: _Field(
            label: 'Initiative roll',
            value: d.initiative,
            placeholder: 'd20 (empty for none)',
            maxLength: 100,
            onChanged: (v) => _change(() => d.initiative = v),
          ),
        ),
      ]),
      Text('Diagonals',
          style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
      SizedBox(
        width: 480,
        child: CvSegmentedControl(
          segments: const [
            (value: DiagonalRule.chebyshev, label: 'Count 1', icon: null, checked: null),
            (value: DiagonalRule.alternating, label: '1, 2, 1…', icon: null, checked: null),
            (value: DiagonalRule.manhattan, label: 'Count 2', icon: null, checked: null),
          ],
          value: d.diagonal,
          onChanged: (r) => _change(() => d.diagonal = r),
        ),
      ),
      if (d.base case final base? when base.bands.isNotEmpty || base.forms.isNotEmpty)
        Text(
            'Its ${[
              if (base.bands.isNotEmpty) '${base.bands.length} range bands',
              if (base.forms.isNotEmpty) '${base.forms.length} turn forms',
            ].join(' and ')} are kept as they are; edit them in the module\'s file.',
            style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
    ]);
  }

  Widget _tags() {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Text('Conditions go on tokens; region tags on sectors and zones.',
          style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
      for (final t in d.tags)
        Row(key: ObjectKey(t), crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          SizedBox(
            width: 200,
            child: _Field(
              value: t.name,
              placeholder: 'Prone',
              maxLength: 30,
              onChanged: (v) => _change(() => t.name = v),
            ),
          ),
          SizedBox(
            width: 170,
            child: CvDropdown<TagKind>(
              value: t.kind,
              onChanged: (k) => _change(() => t.kind = k),
              entries: const [
                CvMenuItem(TagKind.condition, 'Condition'),
                CvMenuItem(TagKind.region, 'Region tag'),
                CvMenuItem(TagKind.sector, 'Sector tag'),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: CvSwitch(
              value: t.valued,
              onChanged: (v) => _change(() => t.valued = v),
              label: const Text('Has a value'),
            ),
          ),
          Expanded(
            child: _Field(
              value: t.text,
              placeholder: 'Rules text, shown on hover',
              maxLength: 2000,
              onChanged: (v) => _change(() => t.text = v),
            ),
          ),
          CvToolButton(
            icon: Lucide.trash2,
            label: 'Remove ${t.name}',
            danger: true,
            tooltipSide: AxisDirection.left,
            onPressed: () => _change(() => d.tags.remove(t)),
          ),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: CvButton(
          label: 'Add a tag',
          icon: Lucide.plus,
          small: true,
          onPressed: () => _change(() => d.tags.add(DraftTag('', TagKind.condition))),
        ),
      ),
    ]);
  }

  Widget _trackers() {
    final d = _draft;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Text('Numbers kept on every token: HP, Stress, Ammo.',
          style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
      for (final t in d.trackers)
        Row(key: ObjectKey(t), crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          SizedBox(
            width: 200,
            child: _Field(
              value: t.name,
              placeholder: 'HP',
              maxLength: 30,
              onChanged: (v) => _change(() => t.name = v),
            ),
          ),
          SizedBox(
            width: 100,
            child: _Field(
              value: '${t.min}',
              placeholder: 'Min',
              maxLength: 6,
              onChanged: (v) {
                if (int.tryParse(v) case final n?) _change(() => t.min = n);
              },
            ),
          ),
          SizedBox(
            width: 100,
            child: _Field(
              value: t.max == null ? '' : '${t.max}',
              placeholder: 'Max',
              maxLength: 6,
              onChanged: (v) => _change(() => t.max = int.tryParse(v)),
            ),
          ),
          Expanded(
            child: _Field(
              value: t.text,
              placeholder: 'What it counts',
              maxLength: 500,
              onChanged: (v) => _change(() => t.text = v),
            ),
          ),
          CvToolButton(
            icon: Lucide.trash2,
            label: 'Remove ${t.name}',
            danger: true,
            tooltipSide: AxisDirection.left,
            onPressed: () => _change(() => d.trackers.remove(t)),
          ),
        ]),
      Align(
        alignment: Alignment.centerLeft,
        child: CvButton(
          label: 'Add a tracker',
          icon: Lucide.plus,
          small: true,
          onPressed: () => _change(() => d.trackers.add(DraftTracker(''))),
        ),
      ),
    ]);
  }

  Widget _tokens() {
    final d = _draft;
    final token = d.tokens.contains(_token) ? _token : d.tokens.firstOrNull;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
      SizedBox(
        width: 260,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
          for (final t in d.tokens)
            CvPressable(
              onTap: () => setState(() => _token = t),
              label: t.name.isEmpty ? 'Unnamed token' : t.name,
              toggled: t == token,
              radius: CvRadii.sm,
              pressScale: 1,
              builder: (s) => Container(
                height: CvSizes.hit,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: t == token
                      ? CvColors.amberTint
                      : s.hover
                          ? CvColors.surfaceHover
                          : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(CvRadii.sm),
                ),
                child: Row(spacing: 10, children: [
                  SizedBox.square(
                    dimension: 28,
                    child: ClipOval(
                      child: _Picture(assets: widget.assets, image: t.image),
                    ),
                  ),
                  Expanded(
                    child: Text(t.name.isEmpty ? 'Unnamed token' : t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CvTypography.label.copyWith(
                            color: t == token ? CvColors.amber300 : null)),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          CvButton(
            label: 'Add a token',
            icon: Lucide.plus,
            small: true,
            block: true,
            onPressed: () => _change(() {
              final t = DraftToken('');
              d.tokens.add(t);
              _token = t;
            }),
          ),
        ]),
      ),
      Expanded(
        child: token == null
            ? Text('Ready-made tokens the GM places from a room: threats, '
                'allies, objects. Each can have a picture and a card.',
                style: CvTypography.body.copyWith(color: CvColors.textSecondary))
            : _TokenForm(
                key: ObjectKey(token),
                token: token,
                assets: widget.assets,
                change: _change,
                pickImage: _pickImage,
                onRemove: () => _change(() => d.tokens.remove(token)),
              ),
      ),
    ]);
  }
}

/// One token: name, picture, size, and its card's sections.
class _TokenForm extends StatelessWidget {
  const _TokenForm({
    super.key,
    required this.token,
    required this.assets,
    required this.change,
    required this.pickImage,
    required this.onRemove,
  });

  final DraftToken token;
  final AssetStore assets;
  final void Function(VoidCallback edit) change;
  final Future<String?> Function() pickImage;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = token;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
        SizedBox(
          width: 160,
          child: _ImagePick(
            label: 'Picture',
            image: t.image,
            assets: assets,
            height: 160,
            round: true,
            onPick: () async {
              final id = await pickImage();
              if (id != null) change(() => t.image = id);
            },
            onClear: () => change(() => t.image = null),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            _Field(
              label: 'Name',
              value: t.name,
              placeholder: 'Goblin archer',
              maxLength: 60,
              onChanged: (v) => change(() => t.name = v),
            ),
            Text('Size',
                style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
            CvSegmentedControl<int>(
              value: t.size,
              onChanged: (n) => change(() => t.size = n),
              segments: [
                for (var n = 1; n <= 4; n++)
                  (value: n, label: '$n×$n', icon: null, checked: null),
              ],
            ),
            if (t.trackers.isNotEmpty || t.conditions.isNotEmpty)
              Text(
                  'Its own trackers and starting tags are kept as they are.',
                  style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
          ]),
        ),
      ]),
      const CvOverline('Card'),
      for (final c in t.card)
        Container(
          key: ObjectKey(c),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CvColors.bgSunken,
            borderRadius: BorderRadius.circular(CvRadii.md),
            border: Border.all(color: CvColors.borderSubtle),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                _Field(
                  value: c.title,
                  placeholder: 'Section title: Attacks, Traits',
                  maxLength: 80,
                  onChanged: (v) => change(() => c.title = v),
                ),
                _Field(
                  value: c.text,
                  placeholder: 'What the GM reads',
                  maxLength: 4000,
                  multiline: true,
                  onChanged: (v) => change(() => c.text = v),
                ),
              ]),
            ),
            SizedBox(
              width: 160,
              child: _ImagePick(
                label: 'Image',
                image: c.image,
                assets: assets,
                height: 100,
                onPick: () async {
                  final id = await pickImage();
                  if (id != null) change(() => c.image = id);
                },
                onClear: () => change(() => c.image = null),
              ),
            ),
            CvToolButton(
              icon: Lucide.trash2,
              label: 'Remove this section',
              danger: true,
              tooltipSide: AxisDirection.left,
              onPressed: () => change(() => t.card.remove(c)),
            ),
          ]),
        ),
      Row(children: [
        CvButton(
          label: 'Add a card section',
          icon: Lucide.plus,
          small: true,
          onPressed: () => change(() => t.card.add(DraftSection(''))),
        ),
        const Spacer(),
        CvButton(
          label: 'Remove token',
          icon: Lucide.trash2,
          variant: CvButtonVariant.dangerGhost,
          small: true,
          onPressed: onRemove,
        ),
      ]),
    ]);
  }
}

/// A text field that owns its controller and reports every change.
class _Field extends StatefulWidget {
  const _Field({
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.maxLength,
    this.multiline = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? placeholder;
  final int? maxLength;
  final bool multiline;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CvTextInput(
        controller: _text,
        label: widget.label,
        placeholder: widget.placeholder,
        maxLength: widget.maxLength,
        multiline: widget.multiline,
        onChanged: widget.onChanged,
      );
}

/// An image slot: the picture, or an empty dashed box to pick one.
class _ImagePick extends StatelessWidget {
  const _ImagePick({
    required this.label,
    required this.image,
    required this.assets,
    required this.onPick,
    required this.onClear,
    this.height = 140,
    this.round = false,
  });

  final String label;
  final String? image;
  final AssetStore assets;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final double height;
  final bool round;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label,
              style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
          SizedBox(
            height: height,
            child: HubCard(
              dashed: image == null,
              label: image == null ? 'Pick ${label.toLowerCase()}' : 'Change ${label.toLowerCase()}',
              onTap: onPick,
              child: image == null
                  ? const Center(child: CvIcon(Lucide.imageUp, size: 24))
                  : round
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: ClipOval(child: _Picture(assets: assets, image: image)),
                        )
                      : _Picture(assets: assets, image: image),
            ),
          ),
          if (image != null)
            Align(
              alignment: Alignment.centerLeft,
              child: CvButton(
                label: 'Remove',
                variant: CvButtonVariant.ghost,
                small: true,
                onPressed: onClear,
              ),
            ),
        ],
      );
}

/// An asset image filling its box; sunken ground while it loads or if none.
class _Picture extends StatelessWidget {
  const _Picture({required this.assets, required this.image});

  final AssetStore assets;
  final String? image;

  @override
  Widget build(BuildContext context) => switch (image) {
        null => const ColoredBox(color: CvColors.slate800),
        final id => FutureBuilder(
            future: assets.image(AssetId(id)),
            builder: (context, snapshot) => snapshot.data == null
                ? const ColoredBox(color: CvColors.slate800)
                : RawImage(image: snapshot.data, fit: BoxFit.cover),
          ),
      };
}

/// "5", "2.5".
String _number(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
