import 'package:chimera_core/chimera_core.dart' show Character, Item, newId;
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart';

import 'actions.dart';
import 'advancement.dart';
import 'advancement_view.dart';
import 'table/chrome.dart' show TextKeysOnly;
import 'theme.dart';
import 'ui/cv.dart';

/// A character's sheet as its pack lays it out: each section's fields,
/// numbers and trackers with − and +, computed fields worked out live, and
/// items as cards. [onChanged] takes the changed character; null shows the
/// sheet read-only.
class SheetView extends StatelessWidget {
  const SheetView({
    super.key,
    required this.pack,
    required this.character,
    this.onChanged,
    this.onAction,
    this.trackersOnly = false,
  });

  /// Uses an action, the sheet's or [Item]'s; null hides actions (outside a
  /// room, where nobody rolls).
  final void Function(ActionDef action, Item? item)? onAction;

  /// Its system: the sheet, and the compendium items come from.
  final SystemPack pack;

  /// Cleaned against [pack] (see `cleaned`).
  final Character character;
  final ValueChanged<Character>? onChanged;

  /// Only the trackers, in one column: a token card's.
  final bool trackersOnly;

  SheetDef get _sheet => pack.sheet!;

  void Function(Object)? _setter(String name) => switch (onChanged) {
        final changed? => (v) =>
            changed(character.copyWith(values: {...character.values, name: v})),
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final read = readSheet(pack, character);
    if (trackersOnly) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        for (final f in _sheet.fields)
          if (f.type == FieldType.tracker)
            CvTooltip(
                key: ValueKey(f.name),
                message: f.text,
                side: AxisDirection.up,
                child: _field(f, read, _setter(f.name))),
      ]);
    }
    Widget section(SheetSection s) => Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            for (final f in s.fields)
              SizedBox(
                key: ValueKey(f.name),
                width: f.type == FieldType.text || f.type == FieldType.items
                    ? double.infinity
                    : 260,
                child: f.type == FieldType.items
                    ? _items(f)
                    : CvTooltip(
                        message: f.text,
                        side: AxisDirection.up,
                        child: _field(f, read, _setter(f.name)),
                      ),
              ),
          ],
        );
    final sections = [for (final s in _sheet.sections) (title: s.title, child: section(s))];
    final rest = [
      for (final adv in pack.advancements)
        (
          title: adv.name,
          child: AdvancementView(
              pack: pack, track: adv, character: character, onChanged: onChanged),
        ),
      if (onAction != null && _sheet.actions.isNotEmpty)
        (title: 'Actions', child: _actions(_sheet.actions, null)),
    ];
    return switch (_sheet.layout) {
      SheetLayout.tabs => _Tabs([...sections, ...rest]),
      SheetLayout.columns => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 24,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              const gap = 24.0;
              final n = (constraints.maxWidth / 360).floor().clamp(1, 3);
              // Sections go round the columns in order.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: gap,
                children: [
                  for (var c = 0; c < n; c++)
                    Expanded(
                      child: _Blocks([
                        for (final (i, s) in sections.indexed)
                          if (i % n == c) s,
                      ]),
                    ),
                ],
              );
            }),
            _Blocks(rest),
          ],
        ),
      SheetLayout.list => _Blocks([...sections, ...rest]),
    };
  }

  /// A button for each of [actions], greyed out with the reason when its
  /// cost can't be paid.
  Widget _actions(List<ActionDef> actions, Item? item) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in actions)
          switch (useAction(pack, character, a, item: item)) {
            final String why => CvTooltip(
                message: why,
                side: AxisDirection.up,
                child: CvButton(label: a.name, small: true, onPressed: null)),
            _ => CvTooltip(
                message: [
                  if (a.cost.isNotEmpty)
                    a.cost.map((c) => '${c.amount} ${c.tracker}').join(', '),
                  if (a.text.isNotEmpty) a.text,
                ].join(' · '),
                side: AxisDirection.up,
                child: CvButton(
                  label: a.name,
                  small: true,
                  onPressed: () => onAction!(a, item),
                ),
              ),
          },
      ]);

  /// An items field: the character's items of its kind as cards, and the
  /// kind's entries to add.
  Widget _items(FieldDef f) {
    final kind = f.kind!;
    final def = pack.compendium!.kinds[kind]!;
    final changed = onChanged;
    void setItems(List<Item> items) => changed!(character.copyWith(items: items));
    final mine = [for (final i in character.items) if (i.kind == kind) i];
    final entries = pack.compendium!.of(kind).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Text(f.label, style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
      for (final item in mine)
        _ItemCard(
          key: ValueKey(item.id),
          item: item,
          kind: def,
          field: _field,
          onChanged: changed == null
              ? null
              : (i) => setItems([for (final o in character.items) o.id == i.id ? i : o]),
          onRemove: changed == null
              ? null
              : () => setItems([for (final o in character.items) if (o.id != item.id) o]),
          actions: onAction == null || actionsOf(item, pack).isEmpty
              ? null
              : _actions(actionsOf(item, pack), item),
        ),
      if (mine.isEmpty && changed == null)
        Text('None', style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
      if (changed != null &&
          entries.isNotEmpty &&
          character.items.length < Character.maxItems)
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
          width: 260,
          child: CvDropdown<Entry?>(
            entries: [for (final e in entries) CvMenuItem(e, e.name)],
            value: null,
            placeholder: 'Add ${f.label.toLowerCase()}…',
            onChanged: (e) {
              if (e == null) return;
              setItems([
                ...character.items,
                Item(
                  id: newId(),
                  kind: kind,
                  name: e.name,
                  values: pack.compendium!.start(e),
                  card: e.card,
                ),
              ]);
            },
          ),
          ),
        ),
    ]);
  }

  static Widget _field(FieldDef f, SheetValues read, void Function(Object)? set) =>
      switch (f.type) {
        FieldType.number => _Stepper(
            label: f.label,
            value: read.number(f.name).toInt(),
            min: f.least ?? -SheetDef.maxValue,
            max: f.most ?? SheetDef.maxValue,
            onSet: set,
          ),
        FieldType.tracker => _Stepper(
            label: f.max == null ? f.label : '${f.label} / ${read['${f.name}.max']}',
            value: read.number(f.name).toInt(),
            min: read.number('${f.name}.min').toInt(),
            max: read.number('${f.name}.max').toInt(),
            onSet: set,
          ),
        FieldType.computed => ConstrainedBox(
            constraints: const BoxConstraints(minHeight: CvSizes.hit),
            child: Row(children: [
              Expanded(child: Text(f.label, style: CvTypography.bodySm)),
              Text(formatValue(read[f.name]),
                  style: CvTypography.weight(CvTypography.body, 600)
                      .copyWith(fontFamily: CvTypography.mono)),
            ]),
          ),
        FieldType.text || FieldType.choice when set == null =>
          _Text(label: f.label, value: read[f.name] as String, onChanged: null),
        FieldType.text => _Text(label: f.label, value: read[f.name] as String, onChanged: set),
        FieldType.choice => CvDropdown<String>(
            label: f.label,
            value: read[f.name] as String,
            entries: [for (final o in f.options) CvMenuItem(o, o)],
            onChanged: set!,
          ),
        FieldType.checkbox => CvSwitch(
            label: Text(f.label),
            value: read[f.name] as bool,
            onChanged: set,
          ),
        FieldType.items => const SizedBox.shrink(),
      };
}

/// One item: its name, its kind's fields (its trackers changed by the
/// owner, the rest read), its card, and taking it off.
class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.kind,
    required this.field,
    required this.onChanged,
    required this.onRemove,
    this.actions,
  });

  /// Its action buttons.
  final Widget? actions;

  final Item item;
  final SheetDef kind;
  final Widget Function(FieldDef, SheetValues, void Function(Object)?) field;
  final ValueChanged<Item>? onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final read = SheetValues(kind, item.values);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CvColors.bgSunken,
        borderRadius: BorderRadius.circular(CvRadii.md),
        border: Border.all(color: CvColors.borderSubtle),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(children: [
          Expanded(
              child: Text(item.name, style: CvTypography.weight(CvTypography.body, 600))),
          if (onRemove case final remove?)
            CvToolButton(
              icon: Lucide.trash2,
              label: 'Remove ${item.name}',
              danger: true,
              tooltipSide: AxisDirection.left,
              onPressed: remove,
            ),
        ]),
        Wrap(spacing: 16, runSpacing: 6, children: [
          for (final f in kind.fields)
            SizedBox(
              key: ValueKey(f.name),
              width: 240,
              child: field(
                f,
                read,
                f.type == FieldType.tracker && onChanged != null
                    ? (v) => onChanged!(item.withValues({...item.values, f.name: v}))
                    : null,
              ),
            ),
        ]),
        ?actions,
        for (final c in item.card) ...[
          CvOverline(c.title),
          if (c.text.isNotEmpty) Text(c.text, style: CvTypography.bodySm),
        ],
      ]),
    );
  }
}

typedef _Block = ({String title, Widget child});

/// Titled blocks of a sheet, one under another.
class _Blocks extends StatelessWidget {
  const _Blocks(this.blocks);

  final List<_Block> blocks;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 24,
        children: [
          for (final b in blocks)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [CvOverline(b.title), b.child],
            ),
        ],
      );
}

/// Titled blocks of a sheet, one tab each.
class _Tabs extends StatefulWidget {
  const _Tabs(this.blocks);

  final List<_Block> blocks;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) {
    final blocks = widget.blocks;
    if (blocks.isEmpty) return const SizedBox.shrink();
    final tab = _tab.clamp(0, blocks.length - 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      CvSegmentedControl<int>(
        value: tab,
        onChanged: (t) => setState(() => _tab = t),
        segments: [
          for (final (i, b) in blocks.indexed) (value: i, label: b.title, icon: null, checked: null),
        ],
      ),
      KeyedSubtree(key: ValueKey(tab), child: blocks[tab].child),
    ]);
  }
}

/// A formula's value as a sheet shows it: "+2" is "2", 3.5 stays, true is
/// "Yes".
String formatValue(Object value) => switch (value) {
  true => 'Yes',
  false => 'No',
  final double d when d == d.roundToDouble() => '${d.round()}',
  final double d => d.toStringAsFixed(1),
  _ => '$value',
};

/// A number with − and +, or typed, kept within [min] and [max].
class _Stepper extends StatefulWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onSet,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onSet;

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  late final _text = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(_Stepper old) {
    super.didUpdateWidget(old);
    if (int.tryParse(_text.text) != widget.value) {
      _text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _set(int v) {
    final clamped = v.clamp(widget.min, widget.max);
    _text.text = '$clamped';
    if (clamped != widget.value) widget.onSet!(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final editable = w.onSet != null;
    return Row(
      spacing: 4,
      children: [
        Expanded(
          child: Text(
            w.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CvTypography.bodySm,
          ),
        ),
        if (editable)
          CvToolButton(
            icon: Lucide.minus,
            label: '${w.label} −1',
            tooltipSide: AxisDirection.up,
            onPressed: w.value > w.min ? () => _set(w.value - 1) : null,
          ),
        SizedBox(
          width: 64,
          child: editable
              ? TextKeysOnly(
                  child: CvTextInput(
                    controller: _text,
                    maxLength: 6,
                    onSubmitted: (v) => _set(int.tryParse(v.trim()) ?? w.value),
                  ),
                )
              : Text(
                  '${w.value}',
                  textAlign: TextAlign.end,
                  style: CvTypography.weight(
                    CvTypography.body,
                    600,
                  ).copyWith(fontFamily: CvTypography.mono),
                ),
        ),
        if (editable)
          CvToolButton(
            icon: Lucide.plus,
            label: '${w.label} +1',
            tooltipSide: AxisDirection.up,
            onPressed: w.value < w.max ? () => _set(w.value + 1) : null,
          ),
      ],
    );
  }
}

/// A text field owning its controller, reporting every change.
class _Text extends StatefulWidget {
  const _Text({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  State<_Text> createState() => _TextState();
}

class _TextState extends State<_Text> {
  late final _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_Text old) {
    super.didUpdateWidget(old);
    if (_text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.onChanged == null
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 4,
          children: [
            Text(
              widget.label,
              style: CvTypography.label.copyWith(color: CvColors.textSecondary),
            ),
            Text(
              widget.value.isEmpty ? '–' : widget.value,
              style: CvTypography.body,
            ),
          ],
        )
      : TextKeysOnly(
          child: CvTextInput(
            controller: _text,
            label: widget.label,
            maxLength: 2000,
            multiline: true,
            onChanged: widget.onChanged,
          ),
        );
}
