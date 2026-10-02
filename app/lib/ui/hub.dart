import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import 'cv.dart';

/// The hub, outside any room (design: ui_kits/hub): a top bar, then pages
/// of cover-led cards.

/// A hub page's content: centred, at most 1344 wide, scrolling.
class HubPage extends StatelessWidget {
  const HubPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1344),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 40, 48, 64),
              child: child,
            ),
          ),
        ),
      );
}

/// A page's title, with an optional overline above and line below.
class HubTitle extends StatelessWidget {
  const HubTitle(this.title, {super.key, this.overline, this.subtitle});

  final String title;
  final String? overline;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overline case final o?) ...[
            CvOverline(o),
            const SizedBox(height: 6),
          ],
          Text(title, style: CvTypography.display),
          if (subtitle case final s?) ...[
            const SizedBox(height: 6),
            Text(s,
                style: CvTypography.body.copyWith(color: CvColors.textSecondary)),
          ],
        ],
      );
}

/// How many columns of at least [minWidth] fit in [width], [gap] apart.
int hubColumns(double width, double minWidth, double gap, int max) =>
    ((width + gap) / (minWidth + gap)).floor().clamp(1, max);

/// A cover-led card: lifts on hover, outlined in amber when [selected].
/// [dashed] is the "new" card: a dashed outline and no fill.
class HubCard extends StatelessWidget {
  const HubCard({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
    this.selected = false,
    this.dashed = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final bool selected;
  final bool dashed;

  @override
  Widget build(BuildContext context) => CvPressable(
        onTap: onTap,
        label: label,
        toggled: selected ? true : null,
        radius: CvRadii.lg,
        pressScale: 0.99,
        builder: (s) {
          final lift = s.hover && !s.pressed;
          final border = selected
              ? CvColors.amber500
              : dashed && s.hover
                  ? CvColors.amber600
                  : s.hover || dashed
                      ? CvColors.borderStrong
                      : CvColors.borderSubtle;
          final card = AnimatedContainer(
            duration: CvMotion.fast,
            curve: CvMotion.standard,
            transform: Matrix4.translationValues(0, lift ? -2 : 0, 0),
            decoration: BoxDecoration(
              color: dashed
                  ? (s.hover ? CvColors.amberTint : const Color(0x00000000))
                  : CvColors.surfacePanelSolid,
              borderRadius: BorderRadius.circular(CvRadii.lg),
              border: dashed
                  ? null
                  : Border.all(color: border, width: selected ? 2 : 1),
              boxShadow: lift && !dashed ? CvElevation.shadow2 : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CvRadii.lg - 1),
              child: DefaultTextStyle(
                style: CvTypography.body.copyWith(
                    color: dashed && s.hover
                        ? CvColors.amber300
                        : dashed
                            ? CvColors.textSecondary
                            : CvColors.textPrimary),
                child: child,
              ),
            ),
          );
          return dashed
              ? CustomPaint(
                  foregroundPainter: _DashedBorder(border), child: card)
              : card;
        },
      );
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5), const Radius.circular(CvRadii.lg)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Stand-in cover art until real art is uploaded: map-like rooms on a warm
/// ground, tinted and laid out by [seed] so each campaign keeps its own.
class HubCover extends StatelessWidget {
  const HubCover({super.key, required this.seed, this.child});

  final String seed;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _CoverPainter(seed.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x3fffffff)),
        child: child ?? const SizedBox.expand(),
      );
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    // Warm hues only: ochre to rust to moss, like the design's covers.
    final hue = 20 + r.nextDouble() * 120;
    Color tone(double s, double l) =>
        HSLColor.fromAHSL(1, hue, s, l).toColor();
    canvas.drawRect(Offset.zero & size, Paint()..color = tone(0.22, 0.2));
    final room = Paint()..color = tone(0.28, 0.48);
    final wall = Paint()
      ..color = tone(0.25, 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    for (var i = 0; i < 7; i++) {
      final rect = Rect.fromLTWH(
        size.width * (0.04 + r.nextDouble() * 0.76),
        size.height * (0.08 + r.nextDouble() * 0.66),
        size.width * (0.1 + r.nextDouble() * 0.22),
        size.height * (0.14 + r.nextDouble() * 0.26),
      );
      canvas
        ..drawRect(rect.inflate(2), wall)
        ..drawRect(rect, room);
    }
    final grid = Paint()..color = const Color(0x29000000);
    for (var x = 0.0; x < size.width; x += 22) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 22) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), grid);
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.seed != seed;
}

/// "GM" (amber) or "Player" (teal) on a pill.
class HubRoleBadge extends StatelessWidget {
  const HubRoleBadge({super.key, this.gm = true});

  final bool gm;

  @override
  Widget build(BuildContext context) {
    final fg = gm ? CvColors.amber300 : CvColors.teal300;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: gm ? CvColors.amberTint : CvColors.tealTint,
        borderRadius: BorderRadius.circular(CvRadii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
        CvIcon(gm ? Lucide.crown : Lucide.userRound, size: 12, color: fg),
        Text(gm ? 'GM' : 'Player',
            style: CvTypography.overline.copyWith(
                height: 1, color: fg, letterSpacing: 11 * 0.04)),
      ]),
    );
  }
}

/// Opens [popover] under [anchor], right edges aligned, while [open] is
/// true. A tap outside or Escape closes it.
class HubPopover extends StatefulWidget {
  const HubPopover({
    super.key,
    required this.open,
    required this.anchor,
    required this.popover,
  });

  final ValueNotifier<bool> open;
  final Widget anchor;
  final Widget popover;

  @override
  State<HubPopover> createState() => _HubPopoverState();
}

class _HubPopoverState extends State<HubPopover> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    widget.open.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.open.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    widget.open.value ? _portal.show() : _portal.hide();
  }

  void _close() => widget.open.value = false;

  @override
  Widget build(BuildContext context) => TapRegion(
        groupId: this,
        onTapOutside: (_) => _close(),
        child: CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
          child: CompositedTransformTarget(
            link: _link,
            child: OverlayPortal(
              controller: _portal,
              overlayChildBuilder: (context) => Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomRight,
                  followerAnchor: Alignment.topRight,
                  offset: const Offset(0, 10),
                  child: TapRegion(
                    groupId: this,
                    child: CvPopIn(child: widget.popover),
                  ),
                ),
              ),
              child: widget.anchor,
            ),
          ),
        ),
      );
}

/// One of the top bar's tabs: underlined in amber when [current].
class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.icon,
    required this.label,
    required this.current,
    required this.onTap,
  });

  final Lucide icon;
  final String label;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => CvPressable(
        onTap: onTap,
        label: label,
        toggled: current,
        pressScale: 1,
        builder: (s) {
          final fg = current || s.hover
              ? CvColors.textPrimary
              : CvColors.textSecondary;
          return Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: current ? CvColors.amber500 : const Color(0x00000000),
                    width: 2),
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
              CvIcon(icon, size: 18, color: fg),
              Text(label,
                  style: CvTypography.weight(CvTypography.body, 500)
                      .copyWith(color: fg, height: 1)),
            ]),
          );
        },
      );
}

/// The hub's pages, as the top bar names them.
enum HubTab { campaigns, library }

/// The hub's top bar: wordmark, page tabs, joining with a code, account.
class HubTopBar extends StatefulWidget {
  const HubTopBar({
    super.key,
    required this.tab,
    required this.onTab,
    required this.joinOpen,
    required this.join,
    required this.email,
    required this.onSignOut,
  });

  final HubTab tab;
  final ValueChanged<HubTab> onTab;

  /// Whether the join popover is open, so a page can open it too.
  final ValueNotifier<bool> joinOpen;

  /// The join form, in the popover.
  final Widget join;
  final String? email;
  final VoidCallback onSignOut;

  @override
  State<HubTopBar> createState() => _HubTopBarState();
}

class _HubTopBarState extends State<HubTopBar> {
  final _account = ValueNotifier(false);

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HubTopBar(:tab, :onTab, :joinOpen, :join, :email, :onSignOut) = widget;
    final account = _account;
    final name = email ?? 'GM';
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Color(0xF514161B),
        border: Border(bottom: BorderSide(color: CvColors.borderSubtle)),
      ),
      child: Row(spacing: 28, children: [
        CvPressable(
          onTap: () => onTab(HubTab.campaigns),
          label: 'Chimera VTT home',
          pressScale: 1,
          builder: (_) => const CvWordmark(),
        ),
        Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
          _NavTab(
            icon: Lucide.bookOpen,
            label: 'Campaigns',
            current: tab == HubTab.campaigns,
            onTap: () => onTab(HubTab.campaigns),
          ),
          _NavTab(
            icon: Lucide.layers,
            label: 'Library',
            current: tab == HubTab.library,
            onTap: () => onTab(HubTab.library),
          ),
        ]),
        const Spacer(),
        Row(mainAxisSize: MainAxisSize.min, spacing: 12, children: [
          HubPopover(
            open: joinOpen,
            anchor: CvButton(
              label: 'Join with code',
              icon: Lucide.logIn,
              onPressed: () => joinOpen.value = !joinOpen.value,
            ),
            popover: CvPanel(
              width: 320,
              solid: true,
              raised: true,
              padding: const EdgeInsets.all(CvSpacing.s6),
              child: join,
            ),
          ),
          HubPopover(
            open: account,
            anchor: CvPressable(
              onTap: () => account.value = !account.value,
              label: 'Account',
              builder: (s) => Container(
                height: CvSizes.hit,
                padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
                decoration: BoxDecoration(
                  color: s.hover ? CvColors.surfaceHover : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(CvRadii.pill),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
                  CvAvatar(
                    initials: name.substring(0, math.min(2, name.length)).toUpperCase(),
                    color: CvColors.amber500,
                    gm: true,
                    label: name,
                  ),
                  const CvIcon(Lucide.chevronDown,
                      size: CvSizes.iconSm, color: CvColors.textSecondary),
                ]),
              ),
            ),
            popover: CvMenu<HubTab?>(
              width: 240,
              entries: [
                CvMenuHeading(name),
                const CvMenuItem(HubTab.library, 'Library',
                    leading: CvIcon(Lucide.layers,
                        size: CvSizes.iconSm, color: CvColors.textSecondary)),
                const CvMenuDivider(),
                const CvMenuItem(null, 'Log out',
                    leading: CvIcon(Lucide.logOut,
                        size: CvSizes.iconSm, color: CvColors.textSecondary)),
              ],
              onSelected: (choice) {
                account.value = false;
                choice == null ? onSignOut() : onTab(choice);
              },
            ),
          ),
        ]),
      ]),
    );
  }
}
