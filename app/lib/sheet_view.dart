import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart';

import 'table/chrome.dart' show TextKeysOnly;
import 'theme.dart';
import 'ui/cv.dart';

/// A character's sheet as its pack lays it out: each section's fields,
/// numbers and trackers with − and +, computed fields worked out live.
/// [onSet] changes one stored value; null shows the sheet read-only.
class SheetView extends StatelessWidget {
  const SheetView({
    super.key,
    required this.sheet,
    required this.values,
    this.onSet,
    this.trackersOnly = false,
  });

  /// Only the trackers, in one column: a token card's.
  final bool trackersOnly;

  final SheetDef sheet;

  /// The character's stored values, cleaned against [sheet].
  final Map<String, Object> values;
  final void Function(String name, Object value)? onSet;

  @override
  Widget build(BuildContext context) {
    final read = SheetValues(sheet, values);
    if (trackersOnly) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        for (final f in sheet.fields)
          if (f.type == FieldType.tracker)
            CvTooltip(
                key: ValueKey(f.name),
                message: f.text,
                side: AxisDirection.up,
                child: _field(f, read)),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        for (final s in sheet.sections)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              CvOverline(s.title),
              Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final f in s.fields)
                    SizedBox(
                      key: ValueKey(f.name),
                      width: f.type == FieldType.text ? double.infinity : 260,
                      child: CvTooltip(
                        message: f.text,
                        side: AxisDirection.up,
                        child: _field(f, read),
                      ),
                    ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _field(FieldDef f, SheetValues read) {
    final set = onSet == null ? null : (Object v) => onSet!(f.name, v);
    return switch (f.type) {
      FieldType.number => _Stepper(
        label: f.label,
        value: read.number(f.name).toInt(),
        min: f.least ?? -SheetDef.maxValue,
        max: f.most ?? SheetDef.maxValue,
        onSet: set,
      ),
      FieldType.tracker => _Stepper(
        label: f.max == null
            ? f.label
            : '${f.label} / ${read['${f.name}.max']}',
        value: read.number(f.name).toInt(),
        min: read.number('${f.name}.min').toInt(),
        max: read.number('${f.name}.max').toInt(),
        onSet: set,
      ),
      FieldType.computed => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: CvSizes.hit),
        child: Row(
          children: [
            Expanded(child: Text(f.label, style: CvTypography.bodySm)),
            Text(
              formatValue(read[f.name]),
              style: CvTypography.weight(
                CvTypography.body,
                600,
              ).copyWith(fontFamily: CvTypography.mono),
            ),
          ],
        ),
      ),
      FieldType.text => _Text(
        label: f.label,
        value: read[f.name] as String,
        onChanged: set,
      ),
      FieldType.choice when set == null => _Text(
          label: f.label, value: read[f.name] as String, onChanged: null),
      FieldType.choice => CvDropdown<String>(
        label: f.label,
        value: read[f.name] as String,
        entries: [for (final o in f.options) CvMenuItem(o, o)],
        onChanged: set ?? (_) {},
      ),
      FieldType.checkbox => CvSwitch(
        label: Text(f.label),
        value: read[f.name] as bool,
        onChanged: set,
      ),
    };
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
