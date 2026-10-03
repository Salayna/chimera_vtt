import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/widgets.dart';

import '../members.dart';
import '../theme.dart';
import '../ui/cv.dart';
import 'chrome.dart';

/// What a line typed in the log sends: `/r 2d6+3` (or `/roll`) rolls,
/// in secret if [secret], and anything else is said. Null for nothing to
/// send.
Command? commandFor(String line, {bool secret = false}) {
  final text = line.trim();
  if (text.isEmpty) return null;
  final roll = RegExp(r'^/r(?:oll)?(?:\s+(.*))?$').firstMatch(text);
  if (roll != null) return RollDice(roll[1] ?? '', secret: secret);
  return Say(text);
}

/// The room's log, which is also its chat: rolls, messages and condition
/// changes, newest at the bottom, with dice buttons and a line to type in.
class LogPanel extends StatefulWidget {
  const LogPanel(
      {super.key, required this.session, required this.send, this.gm = false});

  final Session session;
  final Outcome Function(Command) send;

  /// The GM may roll in secret.
  final bool gm;

  static const width = 320.0;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _text = TextEditingController();
  String? _error;
  bool _open = true;
  bool _secret = false;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
              child: Row(children: [
                const Expanded(child: CvOverline('Log')),
                CvToolButton(
                  icon: _open ? Lucide.chevronDown : Lucide.chevronUp,
                  label: _open ? 'Hide the log' : 'Show the log',
                  tooltipSide: AxisDirection.left,
                  onPressed: () => setState(() => _open = !_open),
                ),
              ]),
            ),
            if (_open) ...[
              Container(height: 1, color: CvColors.borderSubtle),
              SizedBox(
                height: 240,
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
                          horizontal: 14, vertical: CvSpacing.s4),
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
                    Row(children: [
                      for (final sides in [4, 6, 8, 10, 12, 20])
                        Expanded(
                          child: CvButton(
                            label: 'd$sides',
                            small: true,
                            variant: CvButtonVariant.ghost,
                            onPressed: () => widget
                                .send(RollDice('d$sides', secret: _secret)),
                          ),
                        ),
                    ]),
                    if (widget.gm)
                      CvSwitch(
                        value: _secret,
                        onChanged: (v) => setState(() => _secret = v),
                        label: const Row(spacing: 8, children: [
                          CvIcon(Lucide.eyeOff,
                              size: CvSizes.iconSm,
                              color: CvColors.textSecondary),
                          Flexible(
                            child: Text('Roll in secret',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ]),
                      ),
                    TextKeysOnly(
                      child: CvTextInput(
                        controller: _text,
                        placeholder: 'Say something, or /r 2d6+3',
                        maxLength: Say.maxLength,
                        error: _error,
                        keepFocus: true,
                        onSubmitted: _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      Roll(:final formula, :final faces, :final total, :final secret) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: CvSpacing.s5,
          children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                who,
                TextSpan(
                    text: ' rolled $formula${secret ? ' in secret' : ''}\n',
                    style: quiet),
                TextSpan(
                    text: _faces(formula, faces),
                    style: CvTypography.caption.copyWith(
                        fontFamily: CvTypography.mono,
                        color: CvColors.textSecondary)),
              ])),
            ),
            Text('$total',
                semanticsLabel: 'total $total',
                style: CvTypography.title.copyWith(
                    fontFamily: CvTypography.mono, color: CvColors.textPrimary)),
          ],
        ),
      Chat(:final text) => Text.rich(TextSpan(children: [
          who,
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
      child: Row(
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
