import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart' show TurnForm;

import '../theme.dart';
import '../ui/cv.dart';
import 'rules.dart';
import 'table_view.dart';

/// The turn order across the top: whose turn, the round, and the order.
/// The GM rolls it, steps through it and ends it; a player ends their own
/// token's turn. Clicking an entry finds its token.
class InitiativeBar extends StatelessWidget {
  const InitiativeBar({
    super.key,
    required this.store,
    required this.controller,
    required this.send,
    required this.gm,
    required this.self,
  });

  final SceneStore store;
  final TableController controller;
  final Outcome Function(Command) send;
  final bool gm;
  final PlayerId self;

  /// Everyone on the map takes a place, highest first: in their side's
  /// starting form when the pack orders turns by forms, or by rolling its
  /// initiative formula. The GM's client rolls, as the GM's session rolls
  /// all dice.
  static Initiative roll(Scene scene, math.Random random) {
    final pack = packOf(scene);
    final formula = DiceFormula.tryParse(pack.initiative ?? 'd20')!;
    int place(Token t) => pack.forms.isEmpty
        ? formula.total(formula.roll(random))
        : pack.startingForm(npc: t.owner == null)?.value ?? 0;
    final entries = Initiative.ordered([
      for (final t in scene.tokens.values) (token: t.id, value: place(t)),
    ]);
    return Initiative(
      round: 1,
      current: entries.firstOrNull?.token,
      entries: entries,
    );
  }

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: store.changes,
    initialData: store.scene,
    builder: (context, snapshot) {
      final scene = snapshot.requireData;
      final initiative = scene.initiative;
      if (initiative == null) {
        if (!gm || scene.tokens.isEmpty) return const SizedBox.shrink();
        return CvButton(
          label: packOf(scene).forms.isEmpty
              ? 'Roll initiative'
              : 'Start the fight',
          icon: Lucide.circleDashed,
          onPressed: () =>
              send(SetInitiative(roll(scene, math.Random.secure()))),
        );
      }
      final current = scene.tokens[initiative.current];
      final forms = packOf(scene).forms;

      /// The token's form, as its side reads [value].
      TurnForm? formOf(Token t, int value) => forms
          .where((f) => f.value == value && f.npc == (t.owner == null))
          .firstOrNull;

      /// The token's next form on its side, re-sorting the order.
      void cycle(Token t, int value) {
        final side = [
          for (final f in forms)
            if (f.npc == (t.owner == null)) f,
        ];
        if (side.isEmpty) return;
        final i = side.indexWhere((f) => f.value == value);
        final next = side[(i + 1) % side.length];
        send(
          SetInitiative(
            Initiative(
              round: initiative.round,
              current: initiative.current,
              entries: Initiative.ordered([
                for (final e in initiative.entries)
                  e.token == t.id ? (token: e.token, value: next.value) : e,
              ]),
            ),
          ),
        );
      }

      final mine = current != null && current.owner == self;
      return CvPanel(
        padding: const EdgeInsets.all(CvSpacing.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Round ${initiative.round}',
                style: CvTypography.label.copyWith(
                  fontFamily: CvTypography.mono,
                  color: CvColors.textSecondary,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 4,
                  children: [
                    for (final e in initiative.entries)
                      if (scene.tokens[e.token] case final token?)
                        _Entry(
                          token: token,
                          value: formOf(token, e.value)?.name ?? '${e.value}',
                          onCycle: gm && forms.isNotEmpty
                              ? () => cycle(token, e.value)
                              : null,
                          current: e.token == initiative.current,
                          onTap: () {
                            controller.centerOn(token.position);
                            controller.selected.value = token.id;
                          },
                          onRemove: gm
                              ? () => send(
                                  SetInitiative(initiative.without(token.id)),
                                )
                              : null,
                        ),
                  ],
                ),
              ),
            ),
            if (gm || mine)
              CvButton(
                label: gm ? 'Next turn' : 'End my turn',
                variant: mine
                    ? CvButtonVariant.player
                    : CvButtonVariant.primary,
                small: true,
                onPressed: () => send(const EndTurn()),
              ),
            if (gm) ...[
              if (forms.isEmpty)
                CvToolButton(
                  icon: Lucide.refreshCw,
                  label: 'Roll again',
                  tooltipSide: AxisDirection.down,
                  onPressed: () =>
                      send(SetInitiative(roll(scene, math.Random.secure()))),
                ),
              CvToolButton(
                icon: Lucide.x,
                label: 'End the fight',
                tooltipSide: AxisDirection.down,
                onPressed: () => send(const EndInitiative()),
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// One token in the order: its owner's colour, name and value. The current
/// one is lit in amber.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.token,
    required this.value,
    required this.current,
    required this.onTap,
    this.onRemove,
    this.onCycle,
  });

  final Token token;

  /// The roll, or the form's name.
  final String value;

  /// Puts the token in its side's next form.
  final VoidCallback? onCycle;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  /// The GM's remove button shows on hover, to keep the bar quiet.
  bool removable(CvStates s) => onRemove != null && s.hover;

  @override
  Widget build(BuildContext context) {
    final name = token.name.isEmpty ? 'Token' : token.name;
    return CvPressable(
      onTap: onTap,
      label: current ? '$name, $value, their turn' : '$name, $value',
      radius: CvRadii.md,
      builder: (s) => Container(
        height: CvSizes.controlSm,
        padding: EdgeInsets.only(left: 8, right: removable(s) ? 0 : 10),
        decoration: BoxDecoration(
          color: current
              ? CvColors.amberTint
              : s.hover
              ? CvColors.surfaceHover
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(CvRadii.md),
          border: Border.all(
            color: current ? CvColors.amber500 : const Color(0x00000000),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (token.owner) {
                  final owner? => playerColor(owner),
                  null => CvColors.slate500,
                },
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CvTypography.label.copyWith(
                  color: current ? CvColors.amber300 : CvColors.textPrimary,
                ),
              ),
            ),
            if (onCycle case final cycle?)
              CvPressable(
                onTap: cycle,
                label: '$name: $value, change form',
                radius: CvRadii.sm,
                builder: (s) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: s.hover ? CvColors.surfaceHover : CvColors.slate800,
                    borderRadius: BorderRadius.circular(CvRadii.sm),
                  ),
                  child: Text(
                    value,
                    style: CvTypography.caption.copyWith(
                      color: CvColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              Text(
                value,
                style: CvTypography.label.copyWith(
                  fontFamily: CvTypography.mono,
                  color: CvColors.textSecondary,
                ),
              ),
            if (onRemove case final remove? when removable(s))
              CvToolButton(
                icon: Lucide.x,
                label: 'Take $name out',
                tooltipSide: AxisDirection.down,
                onPressed: remove,
              ),
          ],
        ),
      ),
    );
  }
}
