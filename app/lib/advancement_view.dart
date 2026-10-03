import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart';

import 'advancement.dart';
import 'theme.dart';
import 'ui/cv.dart';

/// A pack's advancement as a graph: each node where the pack puts it (or in
/// a row, a chain), lines to what it requires, taken nodes in amber and
/// those that can be taken outlined in teal. [onChanged] takes the
/// character having taken one; null shows the graph read-only.
class AdvancementView extends StatelessWidget {
  const AdvancementView({
    super.key,
    required this.pack,
    required this.character,
    this.onChanged,
  });

  final SystemPack pack;
  final Character character;
  final ValueChanged<Character>? onChanged;

  static const _step = 96.0;
  static const _node = 36.0;

  @override
  Widget build(BuildContext context) {
    final adv = pack.advancement!;
    final nodes = adv.nodes.values.toList();
    final at = {
      for (final (i, n) in nodes.indexed)
        n.name: Offset(n.x ?? i.toDouble(), n.y ?? 0),
    };
    final minX = at.values.map((o) => o.dx).reduce(math.min);
    final minY = at.values.map((o) => o.dy).reduce(math.min);
    Offset place(String name) =>
        (at[name]! - Offset(minX, minY)) * _step + const Offset(_step / 2, _node / 2 + 8);
    final width = (at.values.map((o) => o.dx).reduce(math.max) - minX + 1) * _step;
    final height = (at.values.map((o) => o.dy).reduce(math.max) - minY) * _step + _node + 48;
    final left = readSheet(pack, character).number(adv.field);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
      Text(
          nodes.any((n) => n.cost > 0)
              ? '${formatNumber(left)} ${adv.field} to spend'
              : '${formatNumber(left)} ${adv.field}',
          style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary)),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _Lines([
                  for (final n in nodes)
                    for (final r in [...n.requires, ...n.requiresAll])
                      (place(r), place(n.name), character.nodes.contains(n.name)),
                ]),
              ),
            ),
            for (final n in nodes)
              Positioned(
                left: place(n.name).dx - _step / 2,
                top: place(n.name).dy - _node / 2,
                width: _step,
                child: _Node(
                  node: n,
                  taken: character.nodes.contains(n.name),
                  why: whyNot(pack, character, n),
                  field: adv.field,
                  onTake: onChanged == null
                      ? null
                      : () => onChanged!(take(pack, character, n)),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

String formatNumber(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

class _Node extends StatelessWidget {
  const _Node({
    required this.node,
    required this.taken,
    required this.why,
    required this.field,
    required this.onTake,
  });

  final AdvancementNode node;
  final bool taken;

  /// Why it can't be taken; null when it can.
  final String? why;
  final String field;
  final VoidCallback? onTake;

  @override
  Widget build(BuildContext context) {
    final open = why == null;
    final message = [
      node.name,
      if (node.cost != 0) '${node.cost} $field',
      if (node.text.isNotEmpty) node.text,
      if (!taken && why != null) why!,
    ].join(' · ');
    return CvTooltip(
      message: message,
      side: AxisDirection.up,
      child: Column(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        CvPressable(
          onTap: open ? onTake : null,
          label: taken ? '${node.name}, taken' : open ? 'Take ${node.name}' : node.name,
          radius: CvRadii.pill,
          builder: (s) => Container(
            width: AdvancementView._node,
            height: AdvancementView._node,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: taken
                  ? CvColors.amber500
                  : open && s.hover
                      ? CvColors.tealTint
                      : CvColors.bgSunken,
              border: Border.all(
                  color: taken
                      ? CvColors.amber300
                      : open
                          ? CvColors.teal500
                          : CvColors.borderSubtle,
                  width: 2),
            ),
          ),
        ),
        Text(node.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: CvTypography.caption.copyWith(
                color: taken || open ? CvColors.textPrimary : CvColors.textSecondary)),
      ]),
    );
  }
}

class _Lines extends CustomPainter {
  _Lines(this.lines);

  /// From, to, and whether the node it leads to is taken.
  final List<(Offset, Offset, bool)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (a, b, taken) in lines) {
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = taken ? CvColors.amber500 : CvColors.borderStrong
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_Lines old) => true;
}
