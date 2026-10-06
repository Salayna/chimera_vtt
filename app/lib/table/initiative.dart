import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart' show SystemPack, TurnForm;

import '../theme.dart';
import '../ui/cv.dart';
import 'rules.dart';
import 'table_view.dart';

/// The turn order, the party panel's Initiative tab: the round, the order
/// and whose turn it is.
/// The GM starts it, steps through it and ends it; a player places their own
/// token (its form, or its roll) and ends its turn. Clicking an entry finds
/// its token.
class InitiativeBar extends StatelessWidget {
  const InitiativeBar({
    super.key,
    required this.store,
    required this.controller,
    required this.send,
    required this.gm,
    required this.self,
    this.fullPack,
  });

  final SceneStore store;
  final TableController controller;
  final Outcome Function(Command) send;
  final bool gm;
  final PlayerId self;

  /// The scene's pack with its tokens, for the forms they fight in.
  final SystemPack Function(Scene scene)? fullPack;

  /// Everyone on the map takes a place, highest first: in their side's
  /// starting form when the pack orders turns by forms, or by its initiative
  /// roll. The GM's tokens are rolled here, by the GM's client; players'
  /// wait for their owners to roll, which the GM's session does.
  /// A pack token fights in its own form, from [pack] (the GM's, with its
  /// tokens). Players may then take any of their side's forms, or roll once.
  static Initiative roll(Scene scene, math.Random random, [SystemPack? pack]) {
    pack ??= packOf(scene);
    final formula = DiceFormula.tryParse(pack.initiative ?? 'd20')!;
    int? own(Token t) => switch (pack!.tokens[t.template]?.form) {
          final name? => pack.forms.where((f) => f.name == name).firstOrNull?.value,
          null => null,
        };
    int? place(Token t) => pack!.forms.isNotEmpty
        ? own(t) ?? pack.startingForm(npc: t.owner == null)?.value ?? 0
        : t.owner == null
            ? formula.total(formula.roll(random))
            : null;
    final entries = Initiative.ordered([
      for (final t in scene.tokens.values) (token: t.id, value: place(t)),
    ]);
    return Initiative(
      round: 1,
      current: entries.firstOrNull?.token,
      entries: entries,
      places: [for (final f in pack.forms) if (!f.npc) f.value],
      formula: pack.forms.isEmpty ? '$formula' : null,
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
        return Padding(
          padding: const EdgeInsets.all(CvSpacing.s5),
          child: gm && scene.tokens.isNotEmpty
              ? CvButton(
                  label: packOf(scene).forms.isEmpty
                      ? 'Roll initiative'
                      : 'Start the fight',
                  icon: Lucide.circleDashed,
                  onPressed: () =>
                      send(SetInitiative(roll(scene, math.Random.secure(), fullPack?.call(scene)))),
                )
              : Text(gm ? 'Place tokens to start a fight.' : 'No fight yet: the GM starts one.',
                  style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
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
        send(SetPlace(t.id, side[(i + 1) % side.length].value));
      }

      /// What clicking [e]'s place does, for whoever may: roll it while it
      /// waits, or change its form.
      VoidCallback? placing(Token t, InitiativeEntry e) => switch (e.value) {
            _ when !gm && t.owner != self => null,
            null when initiative.formula != null => () => send(SetPlace(t.id)),
            final value? when forms.isNotEmpty => () => cycle(t, value),
            _ => null,
          };

      final mine = current != null && current.owner == self;
      return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 2, 2),
              child: Row(children: [
                Expanded(child: CvOverline('Round ${initiative.round}')),
                if (gm) ...[
                  if (forms.isEmpty)
                    CvToolButton(
                      icon: Lucide.refreshCw,
                      label: 'Roll again',
                      tooltipSide: AxisDirection.left,
                      onPressed: () =>
                          send(SetInitiative(roll(scene, math.Random.secure(), fullPack?.call(scene)))),
                    ),
                  CvToolButton(
                    icon: Lucide.x,
                    label: 'End the fight',
                    tooltipSide: AxisDirection.left,
                    onPressed: () => send(const EndInitiative()),
                  ),
                ] else
                  const SizedBox(height: CvSizes.hit),
              ]),
            ),
            Container(height: 1, color: CvColors.borderSubtle),
            // ponytail: a fixed cap keeps the scenes below in view; size it
            // to the sidebar if fights get bigger.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(CvSpacing.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 2,
                  children: [
                    for (final e in initiative.entries)
                      if (scene.tokens[e.token] case final token?)
                        _Entry(
                          token: token,
                          value: switch (e.value) {
                            final value? => formOf(token, value)?.name ?? '$value',
                            null when placing(token, e) != null => 'Roll',
                            null => 'Waiting',
                          },
                          onPlace: placing(token, e),
                          current: e.token == initiative.current,
                          onTap: () {
                            controller.centerOn(token.position);
                            controller.selected.value = token.id;
                          },
                          onRemove: gm
                              ? () => send(SetInitiative(initiative.without(token.id)))
                              : null,
                        ),
                  ],
                ),
              ),
            ),
            if (gm || mine) ...[
              Container(height: 1, color: CvColors.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(CvSpacing.s4),
                child: CvButton(
                  label: gm ? 'Next turn' : 'End my turn',
                  variant: mine ? CvButtonVariant.player : CvButtonVariant.primary,
                  small: true,
                  onPressed: () => send(const EndTurn()),
                ),
              ),
            ],
          ],
      );
    },
  );
}

/// One token in the order: its owner's colour, name and value. The current
/// one is lit in rune cyan.
class _Entry extends StatelessWidget {
  const _Entry({
    required this.token,
    required this.value,
    required this.current,
    required this.onTap,
    this.onRemove,
    this.onPlace,
  });

  final Token token;

  /// The roll, the form's name, or Roll (Waiting, to others) before one.
  final String value;

  /// Rolls the token's place, or puts it in its side's next form.
  final VoidCallback? onPlace;
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
              ? CvColors.runeTint
              : s.hover
              ? CvColors.surfaceHover
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(CvRadii.md),
          border: Border.all(
            color: current ? CvColors.rune500 : const Color(0x00000000),
          ),
        ),
        child: Row(
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
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CvTypography.label.copyWith(
                  color: current ? CvColors.rune300 : CvColors.textPrimary,
                ),
              ),
            ),
            if (onPlace case final place?)
              CvPressable(
                onTap: place,
                label: value == 'Roll' ? '$name: roll for their place' : '$name: $value, change form',
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
