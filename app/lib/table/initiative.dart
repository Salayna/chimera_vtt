import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';

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

  /// Everyone on the map rolls the pack's initiative formula, highest
  /// first. The GM's client rolls, as the GM's session rolls all dice.
  static Initiative roll(Scene scene, math.Random random) {
    final formula = DiceFormula.tryParse(packOf(scene).initiative ?? 'd20')!;
    final entries = Initiative.ordered([
      for (final t in scene.tokens.values)
        (token: t.id, value: formula.total(formula.roll(random))),
    ]);
    return Initiative(round: 1, current: entries.firstOrNull?.token, entries: entries);
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
              label: 'Roll initiative',
              icon: Lucide.circleDashed,
              onPressed: () =>
                  send(SetInitiative(roll(scene, math.Random.secure()))),
            );
          }
          final current = scene.tokens[initiative.current];
          final mine = current != null && current.owner == self;
          return CvPanel(
            padding: const EdgeInsets.all(CvSpacing.s3),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('Round ${initiative.round}',
                    style: CvTypography.label.copyWith(
                        fontFamily: CvTypography.mono,
                        color: CvColors.textSecondary)),
              ),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(spacing: 4, children: [
                    for (final e in initiative.entries)
                      if (scene.tokens[e.token] case final token?)
                        _Entry(
                          token: token,
                          value: e.value,
                          current: e.token == initiative.current,
                          onTap: () {
                            controller.centerOn(token.position);
                            controller.selected.value = token.id;
                          },
                          onRemove: gm
                              ? () => send(SetInitiative(initiative.without(token.id)))
                              : null,
                        ),
                  ]),
                ),
              ),
              if (gm || mine)
                CvButton(
                  label: gm ? 'Next turn' : 'End my turn',
                  variant: mine ? CvButtonVariant.player : CvButtonVariant.primary,
                  small: true,
                  onPressed: () => send(const EndTurn()),
                ),
              if (gm) ...[
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
            ]),
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
  });

  final Token token;
  final int value;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final name = token.name.isEmpty ? 'Token' : token.name;
    return CvPressable(
      onTap: onTap,
      label: current ? '$name, $value, their turn' : '$name, $value',
      radius: CvRadii.md,
      builder: (s) => Container(
        height: CvSizes.controlSm,
        padding: EdgeInsets.only(left: 8, right: onRemove == null ? 10 : 0),
        decoration: BoxDecoration(
          color: current
              ? CvColors.amberTint
              : s.hover
                  ? CvColors.surfaceHover
                  : const Color(0x00000000),
          borderRadius: BorderRadius.circular(CvRadii.md),
          border: Border.all(
              color: current ? CvColors.amber500 : const Color(0x00000000)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
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
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CvTypography.label.copyWith(
                    color: current ? CvColors.amber300 : CvColors.textPrimary)),
          ),
          Text('$value',
              style: CvTypography.label.copyWith(
                  fontFamily: CvTypography.mono, color: CvColors.textSecondary)),
          if (onRemove case final remove?)
            CvToolButton(
              icon: Lucide.x,
              label: 'Take $name out',
              tooltipSide: AxisDirection.down,
              onPressed: remove,
            ),
        ]),
      ),
    );
  }
}
