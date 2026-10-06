import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart' show SystemPack;

import '../members.dart';
import '../theme.dart';
import '../ui/cv.dart';
import 'chrome.dart';
import 'initiative.dart';
import 'table_view.dart';

enum _Tab { party, npcs, initiative }

/// Who is at the table, in tabs at the top of the right sidebar: the party
/// with the tokens each plays, the GM's own tokens (for the [gm]), and the
/// turn order. The room code and the way out are at its foot.
class PartyPanel extends StatefulWidget {
  const PartyPanel({
    super.key,
    required this.session,
    required this.store,
    required this.controller,
    required this.send,
    required this.gm,
    required this.self,
    required this.code,
    required this.onLeave,
    this.onRemove,
    this.fullPack,
  });

  static const width = 300.0;

  final Session session;
  final SceneStore store;
  final TableController controller;
  final Outcome Function(Command) send;
  final bool gm;
  final PlayerId self;
  final String code;
  final VoidCallback onLeave;

  /// The GM removes a member.
  final void Function(PlayerId player, Member member)? onRemove;

  /// For the turn order: the scene's pack with its tokens (the GM's).
  final SystemPack Function(Scene scene)? fullPack;

  @override
  State<PartyPanel> createState() => _PartyPanelState();
}

class _PartyPanelState extends State<PartyPanel> {
  var _tab = _Tab.party;

  void _find(Token t) {
    widget.controller.centerOn(t.position);
    widget.controller.selected.value = t.id;
  }

  @override
  Widget build(BuildContext context) => CvPanel(
        width: PartyPanel.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                for (final (tab, label) in [
                  (_Tab.party, 'Party'),
                  if (widget.gm) (_Tab.npcs, 'NPCs'),
                  (_Tab.initiative, 'Initiative'),
                ])
                  _TabButton(
                      label: label,
                      selected: _tab == tab,
                      onTap: () => setState(() => _tab = tab)),
              ]),
            ),
            Container(height: 1, color: CvColors.borderSubtle),
            switch (_tab) {
              _Tab.party => _scroll(_party()),
              _Tab.npcs => _scroll(_npcs()),
              // It scrolls its own list, under its round.
              _Tab.initiative => InitiativeBar(
                  store: widget.store,
                  controller: widget.controller,
                  send: widget.send,
                  gm: widget.gm,
                  self: widget.self,
                  fullPack: widget.fullPack),
            },
            Container(height: 1, color: CvColors.borderSubtle),
            Padding(
              padding: const EdgeInsets.all(CvSpacing.s4),
              child: Row(children: [
                CvRoomCodeChip(code: widget.code),
                const Spacer(),
                CvToolButton(
                  icon: Lucide.logOut,
                  label: 'Leave',
                  danger: true,
                  tooltipSide: AxisDirection.up,
                  onPressed: widget.onLeave,
                ),
              ]),
            ),
          ],
        ),
      );

  Widget _scroll(Widget child) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(CvSpacing.s3), child: child),
      );

  /// The GM, then each member: here or away, and the tokens they play.
  Widget _party() => ValueListenableBuilder(
        valueListenable: members,
        builder: (context, all, _) => StreamBuilder(
          stream: widget.session.peers,
          initialData: widget.session.currentPeers,
          builder: (context, peers) => StreamBuilder(
            stream: widget.store.changes,
            initialData: widget.store.scene,
            builder: (context, scene) {
              final here = {for (final p in peers.requireData) p.player};
              final tokens = scene.requireData.tokens.values;
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _Row(
                  leading: CvAvatar(initials: 'GM', color: CvColors.amber500, gm: true, label: 'GM'),
                  title: 'GM',
                  sub: 'Game master',
                  subColor: CvColors.textGm,
                ),
                for (final MapEntry(key: id, value: m) in all.entries)
                  () {
                    final plays = [
                      for (final t in tokens)
                        if (t.owner == id) t.name.isEmpty ? 'Token' : t.name,
                    ];
                    final away = !here.contains(id.value);
                    return _Row(
                      leading: CvAvatar(
                        initials: m.name.substring(0, m.name.length.clamp(0, 2)).toUpperCase(),
                        color: memberColor(m.color),
                        label: m.name,
                      ),
                      title: m.name,
                      sub: away ? 'Away' : plays.isEmpty ? 'No tokens' : plays.join(', '),
                      subColor: away ? CvColors.textSecondary : memberColor(m.color),
                      trailing: widget.onRemove == null
                          ? null
                          : CvToolButton(
                              icon: Lucide.trash2,
                              label: 'Remove ${m.name}',
                              danger: true,
                              tooltipSide: AxisDirection.left,
                              onPressed: () => widget.onRemove!(id, m),
                            ),
                    );
                  }(),
                if (all.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(CvSpacing.s4),
                    child: Text('Players appear here once they join with the room code.',
                        style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
                  ),
              ]);
            },
          ),
        ),
      );

  /// The GM's own tokens, hidden ones included: where each is, to find it.
  Widget _npcs() => StreamBuilder(
        stream: widget.store.changes,
        initialData: widget.store.scene,
        builder: (context, snapshot) {
          final scene = snapshot.requireData;
          final npcs = [
            for (final t in scene.tokens.values)
              if (t.owner == null) t,
          ]..sort((a, b) => a.name.compareTo(b.name));
          if (npcs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(CvSpacing.s4),
              child: Text('Tokens nobody owns show here.',
                  style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final t in npcs)
              _Row(
                onTap: () => _find(t),
                leading: Container(
                  width: CvSizes.avatar,
                  height: CvSizes.avatar,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.hidden ? CvColors.slate700 : CvColors.slate500,
                  ),
                ),
                title: t.name.isEmpty ? 'Token' : t.name,
                sub: '${cellName(t.position, scene.settings.grid)}${t.hidden ? ' · hidden' : ''}',
                trailing: CvIcon(t.hidden ? Lucide.eyeOff : Lucide.locateFixed,
                    size: CvSizes.iconSm, color: CvColors.textSecondary),
              ),
          ]);
        },
      );
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: CvPressable(
          onTap: onTap,
          label: label,
          builder: (s) => Container(
            height: CvSizes.hit,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    width: 2,
                    color: selected ? CvColors.amber500 : const Color(0x00000000)),
              ),
            ),
            child: Text(label.toUpperCase(),
                style: CvTypography.overline.copyWith(
                    color: selected || s.hover ? CvColors.textPrimary : CvColors.textSecondary)),
          ),
        ),
      );
}

/// A person or token in a list: who, a line under it, and an action.
class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.title,
    required this.sub,
    this.subColor = CvColors.textSecondary,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String sub;
  final Color subColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget row(bool hover) => Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: hover ? CvColors.surfaceHover : null,
            borderRadius: BorderRadius.circular(CvRadii.md),
          ),
          child: Row(spacing: 12, children: [
            leading,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: CvTypography.label),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CvTypography.caption.copyWith(color: subColor)),
              ]),
            ),
            ?trailing,
          ]),
        );
    return onTap == null
        ? row(false)
        : CvPressable(onTap: onTap, label: title, builder: (s) => row(s.hover));
  }
}
