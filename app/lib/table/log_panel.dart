import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/widgets.dart';

import '../members.dart';
import '../theme.dart';
import '../ui/cv.dart';
import 'chrome.dart';

/// What a line typed in the log sends: `/r 2d6+3` (or `/roll`) rolls,
/// and anything else is said, both for the GM alone if [secret]. Null for
/// nothing to send.
Command? commandFor(String line, {bool secret = false}) {
  final text = line.trim();
  if (text.isEmpty) return null;
  final roll = RegExp(r'^/r(?:oll)?(?:\s+(.*))?$').firstMatch(text);
  if (roll != null) return RollDice(roll[1] ?? '', secret: secret);
  return Say(text, secret: secret);
}

/// The room's journal down the left, which is also its chat: rolls,
/// messages and condition changes, newest at the bottom, with a line to type
/// in and dice to roll.
class LogPanel extends StatefulWidget {
  const LogPanel(
      {super.key, required this.session, required this.send, this.gm = false});

  final Session session;
  final Outcome Function(Command) send;

  /// Whose switch it is: the GM keeps things to themselves, a player
  /// whispers to the GM.
  final bool gm;

  static const width = 300.0;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _text = TextEditingController();
  String? _error;
  bool _open = true;
  bool _secret = false;
  bool _dice = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit(String line) {
    final command = commandFor(line, secret: _secret);
    if (command == null) return;
    final outcome = widget.send(command);
    setState(() {
      if (outcome is Refused) {
        _error = command is RollDice
            ? 'Not a roll. Try /r 2d6+3 or /r d20.'
            : 'Too long to send.';
      } else {
        _error = null;
        _text.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) => CvPanel(
        width: LogPanel.width,
        child: Column(
          mainAxisSize: _open ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
              child: Row(children: [
                const Expanded(child: CvOverline('Journal')),
                CvToolButton(
                  icon: _open ? Lucide.chevronUp : Lucide.chevronDown,
                  label: _open ? 'Hide the journal' : 'Show the journal',
                  tooltipSide: AxisDirection.right,
                  onPressed: () => setState(() => _open = !_open),
                ),
              ]),
            ),
            if (_open) ...[
              Container(height: 1, color: CvColors.borderSubtle),
              Expanded(
                child: StreamBuilder(
                  stream: widget.session.log,
                  initialData: widget.session.currentLog,
                  builder: (context, snapshot) {
                    final log = snapshot.requireData;
                    if (log.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(CvSpacing.s7),
                          child: Text(
                            'Rolls, messages and conditions show here.',
                            textAlign: TextAlign.center,
                            style: CvTypography.bodySm
                                .copyWith(color: CvColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    // Reversed, so the newest stays in view at the bottom.
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: CvSpacing.s4),
                      itemCount: log.length,
                      itemBuilder: (context, i) =>
                          _Entry(log[log.length - 1 - i]),
                    );
                  },
                ),
              ),
              Container(height: 1, color: CvColors.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(CvSpacing.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: CvSpacing.s4,
                  children: [
                    if (_dice)
                      _DicePicker(onRoll: (formula) {
                        widget.send(RollDice(formula, secret: _secret));
                        setState(() => _dice = false);
                      }),
                    CvSwitch(
                        value: _secret,
                        onChanged: (v) => setState(() => _secret = v),
                        label: Row(spacing: 8, children: [
                          const CvIcon(Lucide.eyeOff,
                              size: CvSizes.iconSm,
                              color: CvColors.textSecondary),
                          Flexible(
                            child: Text(
                                widget.gm ? 'In secret' : 'To the GM only',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Expanded(
                          child: TextKeysOnly(
                            child: CvTextInput(
                              controller: _text,
                              placeholder: _secret && !widget.gm
                                  ? 'Whisper to the GM, or /r d20'
                                  : 'Say something, or /r 2d6+3',
                              maxLength: Say.maxLength,
                              error: _error,
                              keepFocus: true,
                              onSubmitted: _submit,
                            ),
                          ),
                        ),
                        CvToolButton(
                          icon: Lucide.dices,
                          label: 'Roll dice',
                          active: _dice,
                          tooltipSide: AxisDirection.up,
                          onPressed: () => setState(() => _dice = !_dice),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

/// Dice to roll at a click: how many, which, and a modifier.
class _DicePicker extends StatefulWidget {
  const _DicePicker({required this.onRoll});

  /// With the formula, as typed after /r: `2d6+1`.
  final void Function(String formula) onRoll;

  @override
  State<_DicePicker> createState() => _DicePickerState();
}

class _DicePickerState extends State<_DicePicker> {
  static const sides = [4, 6, 8, 10, 12, 20, 100];
  int _count = 1;
  int _modifier = 0;

  String get _bonus => switch (_modifier) {
        0 => '',
        > 0 => '+$_modifier',
        _ => '$_modifier',
      };

  Widget _stepper(String label, int value, int min, int max, void Function(int) set) =>
      Expanded(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: CvColors.borderSubtle),
            borderRadius: BorderRadius.circular(CvRadii.md),
          ),
          child: Row(children: [
            CvToolButton(
              icon: Lucide.minus,
              label: 'Less: ${label.toLowerCase()}',
              tooltipSide: AxisDirection.up,
              onPressed: value > min ? () => setState(() => set(value - 1)) : null,
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(children: [
                  Text(label == 'Modifier' && value > 0 ? '+$value' : '$value',
                      style: CvTypography.label.copyWith(fontFamily: CvTypography.mono)),
                  Text(label,
                      style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
                ]),
              ),
            ),
            CvToolButton(
              icon: Lucide.plus,
              label: 'More: ${label.toLowerCase()}',
              tooltipSide: AxisDirection.up,
              onPressed: value < max ? () => setState(() => set(value + 1)) : null,
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => CvPopIn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: CvSpacing.s4,
          children: [
            for (final row in [sides.take(4), sides.skip(4)])
              Row(spacing: 6, children: [
                for (final n in row)
                  Expanded(
                    child: CvPressable(
                      label: 'd$n',
                      radius: CvRadii.md,
                      onTap: () => widget.onRoll('${_count}d$n$_bonus'),
                      builder: (s) => Container(
                        height: CvSizes.controlSm,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s.hover ? CvColors.surfaceHover : null,
                          border: Border.all(color: CvColors.borderSubtle),
                          borderRadius: BorderRadius.circular(CvRadii.md),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('d$n',
                              style: CvTypography.label.copyWith(
                                  color: n == 20 ? CvColors.rune300 : CvColors.textPrimary)),
                        ),
                      ),
                    ),
                  ),
                if (row.length < 4) const Spacer(),
              ]),
            Row(spacing: CvSpacing.s4, children: [
              _stepper('Dice', _count, 1, 10, (v) => _count = v),
              _stepper('Modifier', _modifier, -10, 20, (v) => _modifier = v),
            ]),
          ],
        ),
      );
}

class _Entry extends StatelessWidget {
  const _Entry(this.event);

  final TableEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final name = e.gm ? 'GM' : playerName(e.by);
    final color = e.gm ? CvColors.textGm : playerColor(e.by);
    final who = TextSpan(
        text: name,
        style: CvTypography.weight(CvTypography.bodySm, 600)
            .copyWith(color: color));
    final quiet = CvTypography.bodySm.copyWith(color: CvColors.textSecondary);
    final time = DateTime.fromMillisecondsSinceEpoch(e.at);
    final stamp = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    final Widget body = switch (e) {
      Roll(:final formula, :final faces, :final total, :final secret, :final blind) =>
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: CvColors.slate850,
            border: Border.all(color: CvColors.borderSubtle),
            borderRadius: BorderRadius.circular(CvRadii.md),
          ),
          child: Column(spacing: CvSpacing.s4, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  who,
                  if (secret)
                    TextSpan(text: e.gm ? ' in secret' : ' for the GM', style: quiet),
                ])),
              ),
              Text(stamp,
                  style: CvTypography.caption.copyWith(color: CvColors.textDisabled)),
            ]),
            if (blind)
              Text('The GM sees the result', style: quiet)
            else ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final face in faces.expand((f) => f))
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: CvColors.slate950,
                        border: Border.all(color: CvColors.borderStrong),
                      ),
                      child: Text('$face',
                          style: CvTypography.label
                              .copyWith(fontFamily: CvTypography.mono)),
                    ),
                ],
              ),
              Text('$total',
                  semanticsLabel: 'total $total',
                  style: CvTypography.titleLg.copyWith(
                      fontFamily: CvTypography.mono, color: CvColors.textPrimary)),
            ],
            Text(formula,
                style: CvTypography.caption.copyWith(
                    fontFamily: CvTypography.mono, color: CvColors.textSecondary)),
          ]),
        ),
      Chat(:final text, :final secret) => Text.rich(TextSpan(children: [
          who,
          if (secret)
            TextSpan(text: e.gm ? ' in secret' : ' to the GM', style: quiet),
          TextSpan(text: '  $text', style: CvTypography.bodySm),
        ])),
      ConditionChange(
        :final token,
        :final condition,
        :final value,
        :final removed,
        :final secret
      ) =>
        Text.rich(TextSpan(children: [
          who,
          TextSpan(
              text: ' ${removed ? 'removed' : 'set'} '
                  '${value == null ? condition : '$condition ($value)'}'
                  '${removed ? ' from' : ' on'} '
                  '${token.isEmpty ? 'a token' : token}'
                  // Only the GM gets these: the token is hidden.
                  '${secret ? ' (hidden)' : ''}',
              style: quiet),
        ])),
      ActionEvent(:final character, :final action, :final dice, :final banded, :final rolls) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
          Text.rich(TextSpan(children: [
            who,
            TextSpan(
                text: ' · $character used $action${dice == null ? '' : ' ($dice)'}',
                style: quiet),
          ])),
          for (final r in rolls)
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: CvSpacing.s4, children: [
              Text(_faces(dice!, r.faces),
                  style: CvTypography.caption.copyWith(
                      fontFamily: CvTypography.mono, color: CvColors.textSecondary)),
              Expanded(
                child: Text(
                    switch (r.band) {
                      null => banded ? 'Miss' : '',
                      final band => '$band${r.text.isEmpty ? '' : ': ${r.text}'}',
                    },
                    style: CvTypography.bodySm),
              ),
              Text('${r.total}',
                  semanticsLabel: 'total ${r.total}',
                  style: CvTypography.weight(CvTypography.body, 600)
                      .copyWith(fontFamily: CvTypography.mono)),
            ]),
        ]),
      PingEvent() => const SizedBox.shrink(), // Never logged.
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CvSpacing.s3),
      // A roll's card holds its own time.
      child: e is Roll
          ? body
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: CvSpacing.s4,
              children: [
                Expanded(child: body),
                Text(stamp,
                    style: CvTypography.caption.copyWith(color: CvColors.textDisabled)),
              ],
            ),
    );
  }

  /// Each die's face, constants as they are: `[4, 2] + 3`.
  static String _faces(String formula, List<List<int>> faces) {
    final terms = DiceFormula.tryParse(formula)?.terms;
    if (terms == null) return '';
    final b = StringBuffer();
    for (final (i, t) in terms.indexed) {
      if (i > 0) b.write(t.sign < 0 ? ' − ' : ' + ');
      if (i == 0 && t.sign < 0) b.write('−');
      b.write(t.sides == null ? '${t.count}' : '[${faces[i].join(', ')}]');
    }
    return b.toString();
  }
}
