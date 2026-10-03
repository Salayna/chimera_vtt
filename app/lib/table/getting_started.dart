import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';

import '../members.dart';
import '../theme.dart';
import '../ui/cv.dart';

/// A first table's steps, by id: done once the room shows them, and
/// remembered once done, so ending initiative doesn't undo one.
const startSteps = ['map', 'token', 'player', 'initiative'];

/// The steps [scene] and its [players] count have done.
Set<String> stepsDone(Scene scene, int players) => {
      if (scene.settings.map != null) 'map',
      if (scene.tokens.isNotEmpty) 'token',
      if (players > 0) 'player',
      if (scene.initiative != null) 'initiative',
    };

/// The GM's checklist for a first table, in a corner: drop a map, place a
/// token, invite a player, roll initiative. Each step ticks itself; it goes
/// once all are done, or the GM closes it. [load] and [save] keep what's
/// done (and "closed") for the campaign.
class GettingStarted extends StatefulWidget {
  const GettingStarted({
    super.key,
    required this.store,
    required this.code,
    required this.load,
    required this.save,
    this.onMap,
    this.onToken,
    this.onInvite,
  });

  final SceneStore store;

  /// The room code, for inviting.
  final String code;
  final Future<List<String>> Function() load;
  final void Function(List<String> done) save;
  final VoidCallback? onMap;
  final VoidCallback? onToken;
  final VoidCallback? onInvite;

  @override
  State<GettingStarted> createState() => _GettingStartedState();
}

class _GettingStartedState extends State<GettingStarted> {
  /// Null until loaded: nothing shows before then.
  Set<String>? _done;

  @override
  void initState() {
    super.initState();
    widget.load().then((done) {
      if (mounted) setState(() => _done = done.toSet());
    }, onError: (Object e) {
      // A nicety: without its memory it starts again.
      if (mounted) setState(() => _done = {});
    });
  }

  /// Remembers [now] as done, after this frame: it's found while building.
  void _remember(Set<String> now) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _done = {...?_done, ...now});
        widget.save(_done!.toList());
      });

  void _close() {
    setState(() => _done = {...?_done, 'closed'});
    widget.save(_done!.toList());
  }

  @override
  Widget build(BuildContext context) {
    final remembered = _done;
    if (remembered == null || remembered.contains('closed')) {
      return const SizedBox.shrink();
    }
    return StreamBuilder(
      stream: widget.store.changes,
      initialData: widget.store.scene,
      builder: (context, snap) => ValueListenableBuilder(
        valueListenable: members,
        builder: (context, all, _) {
          final now = stepsDone(snap.requireData, all.length);
          if (!remembered.containsAll(now)) _remember(now);
          final done = {...remembered, ...now};
          final count = startSteps.where(done.contains).length;
          if (count == startSteps.length) return const SizedBox.shrink();
          return CvPopIn(
            child: CvPanel(
              width: 260,
              padding: const EdgeInsets.all(CvSpacing.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 2,
                children: [
                  Row(children: [
                    Expanded(
                      child: CvOverline(
                          'Getting started · $count/${startSteps.length}'),
                    ),
                    CvToolButton(
                      icon: Lucide.x,
                      label: 'Close',
                      tooltipSide: AxisDirection.up,
                      onPressed: _close,
                    ),
                  ]),
                  for (final (id, label, hint, onTap) in [
                    ('map', 'Drop a map', 'From your library, or upload one.',
                        widget.onMap),
                    ('token', 'Place a token', 'Its image, or one of the '
                        "system's.", widget.onToken),
                    ('player', 'Invite a player',
                        'Send them the room code ${widget.code}.',
                        widget.onInvite),
                    ('initiative', 'Roll initiative',
                        'From the bar at the top, once tokens are out.', null),
                  ])
                    _step(label, hint, done: done.contains(id), onTap: onTap),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _step(String label, String hint,
          {required bool done, VoidCallback? onTap}) =>
      CvPressable(
        onTap: done ? null : onTap,
        label: label,
        radius: CvRadii.sm,
        pressScale: 1,
        builder: (s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: s.hover && !done && onTap != null
                ? CvColors.surfaceHover
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(CvRadii.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              CvIcon(done ? Lucide.circleCheck : Lucide.circle,
                  size: CvSizes.iconSm,
                  color: done ? CvColors.amber500 : CvColors.textSecondary),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(label,
                        style: CvTypography.label.copyWith(
                            color: done ? CvColors.textSecondary : null,
                            decoration:
                                done ? TextDecoration.lineThrough : null)),
                    if (!done)
                      Text(hint,
                          style: CvTypography.caption
                              .copyWith(color: CvColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}
