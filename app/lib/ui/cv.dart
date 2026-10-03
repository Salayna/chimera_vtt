import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart' show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

/// The Chimera VTT design system's components (Claude Design project
/// 32b42cc6, components/*). No Material: every widget here draws itself
/// from the tokens in theme.dart.

/// Lucide v0.460 (ISC licence) glyphs, copied from the design project.
enum Lucide {
  bookOpen(
      '<path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>'),
  check('<path d="M20 6 9 17l-5-5"/>'),
  chevronDown('<path d="m6 9 6 6 6-6"/>'),
  chevronUp('<path d="m18 15-6-6-6 6"/>'),
  chevronRight('<path d="m9 18 6-6-6-6"/>'),
  circle('<circle cx="12" cy="12" r="10"/>'),
  circleAlert(
      '<circle cx="12" cy="12" r="10"/><line x1="12" x2="12" y1="8" y2="12"/><line x1="12" x2="12.01" y1="16" y2="16"/>'),
  circleCheck('<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>'),
  circleDashed(
      '<path d="M10.1 2.182a10 10 0 0 1 3.8 0"/><path d="M13.9 21.818a10 10 0 0 1-3.8 0"/><path d="M17.609 3.721a10 10 0 0 1 2.69 2.7"/><path d="M2.182 13.9a10 10 0 0 1 0-3.8"/><path d="M20.279 17.609a10 10 0 0 1-2.7 2.69"/><path d="M21.818 10.1a10 10 0 0 1 0 3.8"/><path d="M3.721 6.391a10 10 0 0 1 2.7-2.69"/><path d="M6.391 20.279a10 10 0 0 1-2.69-2.7"/>'),
  circlePlus(
      '<circle cx="12" cy="12" r="10"/><path d="M8 12h8"/><path d="M12 8v8"/>'),
  copy(
      '<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>'),
  crown(
      '<path d="M11.562 3.266a.5.5 0 0 1 .876 0L15.39 8.87a1 1 0 0 0 1.516.294L21.183 5.5a.5.5 0 0 1 .798.519l-2.834 10.246a1 1 0 0 1-.956.734H5.81a1 1 0 0 1-.957-.734L2.02 6.02a.5.5 0 0 1 .798-.519l4.276 3.664a1 1 0 0 0 1.516-.294z"/><path d="M5 21h14"/>'),
  download(
      '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/>'),
  ellipsis(
      '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>'),
  eraser(
      '<path d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21"/><path d="M22 21H7"/><path d="m5 11 9 9"/>'),
  eye(
      '<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/>'),
  eyeOff(
      '<path d="M10.733 5.076a10.744 10.744 0 0 1 11.205 6.575 1 1 0 0 1 0 .696 10.747 10.747 0 0 1-1.444 2.49"/><path d="M14.084 14.158a3 3 0 0 1-4.242-4.242"/><path d="M17.479 17.499a10.75 10.75 0 0 1-15.417-5.151 1 1 0 0 1 0-.696 10.75 10.75 0 0 1 4.446-5.143"/><path d="m2 2 20 20"/>'),
  fileJson(
      '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M10 12a1 1 0 0 0-1 1v1a1 1 0 0 1-1 1 1 1 0 0 1 1 1v1a1 1 0 0 0 1 1"/><path d="M14 18a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1 1 1 0 0 1-1-1v-1a1 1 0 0 0-1-1"/>'),
  grid3x3(
      '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M3 9h18"/><path d="M3 15h18"/><path d="M9 3v18"/><path d="M15 3v18"/>'),
  map(
      '<path d="M14.106 5.553a2 2 0 0 0 1.788 0l3.659-1.83A1 1 0 0 1 21 4.619v12.764a1 1 0 0 1-.553.894l-4.553 2.277a2 2 0 0 1-1.788 0l-4.212-2.106a2 2 0 0 0-1.788 0l-3.659 1.83A1 1 0 0 1 3 19.381V6.618a1 1 0 0 1 .553-.894l4.553-2.277a2 2 0 0 1 1.788 0z"/><path d="M15 5.764v15"/><path d="M9 3.236v15"/>'),
  layers(
      '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>'),
  pencil(
      '<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/><path d="m15 5 4 4"/>'),
  imageUp(
      '<path d="M10.3 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v10l-3.1-3.1a2 2 0 0 0-2.814.014L6 21"/><path d="m14 19.5 3-3 3 3"/><path d="M17 22v-5.5"/><circle cx="9" cy="9" r="2"/>'),
  info('<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'),
  locateFixed(
      '<line x1="2" x2="5" y1="12" y2="12"/><line x1="19" x2="22" y1="12" y2="12"/><line x1="12" x2="12" y1="2" y2="5"/><line x1="12" x2="12" y1="19" y2="22"/><circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="3"/>'),
  logIn(
      '<path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><polyline points="10 17 15 12 10 7"/><line x1="15" x2="3" y1="12" y2="12"/>'),
  logOut(
      '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>'),
  magnet(
      '<path d="m6 15-4-4 6.75-6.77a7.79 7.79 0 0 1 11 11L13 22l-4-4 6.39-6.36a2.14 2.14 0 0 0-3-3L6 15"/><path d="m5 8 4 4"/><path d="m12 15 4 4"/>'),
  mousePointer2(
      '<path d="M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z"/>'),
  paintbrush(
      '<path d="m14.622 17.897-10.68-2.913"/><path d="M18.376 2.622a1 1 0 1 1 3.002 3.002L17.36 9.643a.5.5 0 0 0 0 .707l.944.944a2.41 2.41 0 0 1 0 3.408l-.944.944a.5.5 0 0 1-.707 0L8.354 7.348a.5.5 0 0 1 0-.707l.944-.944a2.41 2.41 0 0 1 3.408 0l.944.944a.5.5 0 0 0 .707 0z"/><path d="M9 8c-1.804 2.71-3.97 3.46-6.583 3.948a.507.507 0 0 0-.302.819l7.32 8.883a1 1 0 0 0 1.185.204C12.735 20.405 16 16.792 16 15"/>'),
  minus('<path d="M5 12h14"/>'),
  plus('<path d="M5 12h14"/><path d="M12 5v14"/>'),
  puzzle(
      '<path d="M15.39 4.39a1 1 0 0 0 1.68-.474 2.5 2.5 0 1 1 3.014 3.015 1 1 0 0 0-.474 1.68l1.683 1.682a2.414 2.414 0 0 1 0 3.414L19.61 15.39a1 1 0 0 1-1.68-.474 2.5 2.5 0 1 0-3.014 3.015 1 1 0 0 1 .474 1.68l-1.683 1.682a2.414 2.414 0 0 1-3.414 0L8.61 19.61a1 1 0 0 0-1.68.474 2.5 2.5 0 1 1-3.014-3.015 1 1 0 0 0 .474-1.68l-1.683-1.682a2.414 2.414 0 0 1 0-3.414L4.39 8.61a1 1 0 0 1 1.68.474 2.5 2.5 0 1 0 3.014-3.015 1 1 0 0 1-.474-1.68l1.683-1.682a2.414 2.414 0 0 1 3.414 0z"/>'),
  radio(
      '<path d="M4.9 19.1C1 15.2 1 8.8 4.9 4.9"/><path d="M7.8 16.2c-2.3-2.3-2.3-6.1 0-8.5"/><circle cx="12" cy="12" r="2"/><path d="M16.2 7.8c2.3 2.3 2.3 6.1 0 8.5"/><path d="M19.1 4.9C23 8.8 23 15.1 19.1 19"/>'),
  redo2(
      '<path d="m15 14 5-5-5-5"/><path d="M20 9H9.5A5.5 5.5 0 0 0 4 14.5A5.5 5.5 0 0 0 9.5 20H13"/>'),
  refreshCw(
      '<path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/><path d="M8 16H3v5"/>'),
  ruler(
      '<path d="M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.41 2.41 0 0 1 0-3.4l2.6-2.6a2.41 2.41 0 0 1 3.4 0Z"/><path d="m14.5 12.5 2-2"/><path d="m11.5 9.5 2-2"/><path d="m8.5 6.5 2-2"/><path d="m17.5 15.5 2-2"/>'),
  search('<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>'),
  scan(
      '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/>'),
  squareDashed(
      '<path d="M5 3a2 2 0 0 0-2 2"/><path d="M19 3a2 2 0 0 1 2 2"/><path d="M21 19a2 2 0 0 1-2 2"/><path d="M5 21a2 2 0 0 1-2-2"/><path d="M9 3h1"/><path d="M9 21h1"/><path d="M14 3h1"/><path d="M14 21h1"/><path d="M3 9v1"/><path d="M21 9v1"/><path d="M3 14v1"/><path d="M21 14v1"/>'),
  trash2(
      '<path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>'),
  triangleAlert(
      '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>'),
  undo2(
      '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11"/>'),
  upload(
      '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/>'),
  userRound('<circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 0 0-16 0"/>'),
  x('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'),
  zoomIn(
      '<circle cx="11" cy="11" r="8"/><line x1="21" x2="16.65" y1="21" y2="16.65"/><line x1="11" x2="11" y1="8" y2="14"/><line x1="8" x2="14" y1="11" y2="11"/>'),
  zoomOut(
      '<circle cx="11" cy="11" r="8"/><line x1="21" x2="16.65" y1="21" y2="16.65"/><line x1="8" x2="14" y1="11" y2="11"/>');

  const Lucide(this.body);
  final String body;
}

/// A Lucide glyph in the ambient text colour, like CSS currentColor.
class CvIcon extends StatelessWidget {
  const CvIcon(this.icon, {super.key, this.size = CvSizes.icon, this.color});

  final Lucide icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'fill="none" stroke="#000" stroke-width="2" stroke-linecap="round" '
        'stroke-linejoin="round">${icon.body}</svg>',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
            color ??
                DefaultTextStyle.of(context).style.color ??
                CvColors.textPrimary,
            BlendMode.srcIn),
      );
}

/// What an accent means: GM, player, danger, saved. Icon colour and tint.
enum CvTone {
  neutral(CvColors.textPrimary, CvColors.slate800),
  ok(CvColors.moss500, CvColors.mossTint),
  gm(CvColors.amber500, CvColors.amberTint),
  player(CvColors.teal400, CvColors.tealTint),
  danger(CvColors.ember500, CvColors.emberTint);

  const CvTone(this.color, this.tint);
  final Color color;
  final Color tint;
}

typedef CvStates = ({bool hover, bool pressed, bool focus, bool disabled});

/// Hover, press, keyboard focus and activation for every control here.
/// Disabled when [onTap] is null. Keyboard focus draws the design's ring:
/// 2 px bone outside a 2 px dark halo.
class CvPressable extends StatefulWidget {
  const CvPressable({
    super.key,
    required this.onTap,
    required this.builder,
    this.radius = CvRadii.md,
    this.pressScale = 0.96,
    this.label,
    this.toggled,
  });

  final VoidCallback? onTap;
  final Widget Function(CvStates states) builder;
  final double radius;
  final double pressScale;
  final String? label;
  final bool? toggled;

  @override
  State<CvPressable> createState() => _CvPressableState();
}

class _CvPressableState extends State<CvPressable> {
  bool _hover = false;
  bool _pressed = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final states = (
      hover: _hover && !disabled,
      pressed: _pressed && !disabled,
      focus: _focus,
      disabled: disabled,
    );
    Widget child = AnimatedScale(
      scale: states.pressed ? widget.pressScale : 1,
      duration: CvMotion.instant,
      curve: CvMotion.standard,
      child: widget.builder(states),
    );
    if (_focus) child = _FocusRing(radius: widget.radius, child: child);
    return Semantics(
      button: true,
      enabled: !disabled,
      toggled: widget.toggled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: !disabled,
        mouseCursor:
            disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: child,
        ),
      ),
    );
  }
}

class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.radius, required this.child});

  final double radius;
  final Widget child;

  Widget _ring(double inset, Color color) => Positioned(
        left: -inset,
        top: -inset,
        right: -inset,
        bottom: -inset,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius + inset),
              border: Border.all(color: color, width: CvRadii.focusWidth),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          _ring(2, CvColors.focusRingHalo),
          _ring(4, CvColors.focusRing),
        ],
      );
}

/// Fades and rises in, like the design's cv-pop-in.
class CvPopIn extends StatelessWidget {
  const CvPopIn({super.key, required this.child, this.duration = CvMotion.base});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: CvMotion.enter,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
          ),
        ),
        child: child,
      );
}

/// Floating chrome: translucent slate, hairline border, soft shadow and a
/// backdrop blur, so it reads over bright and dark maps alike. [solid] for
/// popovers, menus and dialogs.
class CvPanel extends StatelessWidget {
  const CvPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = CvRadii.lg,
    this.raised = false,
    this.solid = false,
    this.width,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool raised;
  final bool solid;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: raised ? CvElevation.shadow2 : CvElevation.shadow1,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          enabled: !solid,
          filter: ImageFilter.blur(
              sigmaX: CvElevation.blurPanel, sigmaY: CvElevation.blurPanel),
          child: Container(
            width: width,
            padding: padding,
            decoration: BoxDecoration(
              color: solid ? CvColors.surfacePanelSolid : CvColors.surfacePanel,
              borderRadius: shape,
              border: Border.all(color: CvColors.borderSubtle),
            ),
            child: DefaultTextStyle(style: CvTypography.body, child: child),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase heading, the only uppercase text in the system.
class CvOverline extends StatelessWidget {
  const CvOverline(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: CvTypography.overline);
}

/// A keycap: "Esc", "Del", "X".
class CvKbd extends StatelessWidget {
  const CvKbd(this.keys, {super.key});

  final String keys;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CvColors.slate800,
          borderRadius: BorderRadius.circular(CvRadii.xs),
          border: Border.all(color: CvColors.slate600),
        ),
        child: Text(keys,
            style: CvTypography.caption.copyWith(
                fontFamily: CvTypography.mono,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w500,
                color: CvColors.textSecondary)),
      );
}

/// "Chimera VTT", set in type: there is no logo.
class CvWordmark extends StatelessWidget {
  const CvWordmark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(text: 'Chimera ', children: const [
          TextSpan(text: 'VTT', style: TextStyle(color: CvColors.amber500)),
        ]),
        style: CvTypography.weight(CvTypography.body, 700)
            .copyWith(fontSize: size, height: 1, letterSpacing: -0.02 * size),
      );
}

// ---------- Tooltip ----------

/// Shows [message] (and a keycap for [shortcut]) beside [child] on hover.
class CvTooltip extends StatefulWidget {
  const CvTooltip({
    super.key,
    required this.message,
    required this.child,
    this.shortcut,
    this.side = AxisDirection.right,
  });

  final String message;
  final String? shortcut;
  final AxisDirection side;
  final Widget child;

  @override
  State<CvTooltip> createState() => _CvTooltipState();
}

class _CvTooltipState extends State<CvTooltip> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final (target, follower, offset) = switch (widget.side) {
      AxisDirection.right =>
        (Alignment.centerRight, Alignment.centerLeft, const Offset(10, 0)),
      AxisDirection.left =>
        (Alignment.centerLeft, Alignment.centerRight, const Offset(-10, 0)),
      AxisDirection.up =>
        (Alignment.topCenter, Alignment.bottomCenter, const Offset(0, -10)),
      AxisDirection.down =>
        (Alignment.bottomCenter, Alignment.topCenter, const Offset(0, 10)),
    };
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: target,
            followerAnchor: follower,
            offset: offset,
            child: IgnorePointer(
              child: CvPopIn(
                duration: CvMotion.fast,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: CvColors.slate950,
                    borderRadius: BorderRadius.circular(CvRadii.sm),
                    border: Border.all(color: CvColors.slate700),
                    boxShadow: CvElevation.shadow1,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                    Text(widget.message,
                        style: CvTypography.weight(CvTypography.caption, 500)),
                    if (widget.shortcut case final keys?) CvKbd(keys),
                  ]),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _portal.show(),
          onExit: (_) => _portal.hide(),
          child: widget.child,
        ),
      ),
    );
  }
}

// ---------- Buttons ----------

/// An icon button for toolbars and rails, with a tooltip. [active] marks the
/// current tool (amber). [inline] shows the label beside the icon instead.
class CvToolButton extends StatelessWidget {
  const CvToolButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.active = false,
    this.danger = false,
    this.inline = false,
    this.shortcut,
    this.tooltipSide = AxisDirection.right,
  });

  final Lucide icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;
  final bool inline;
  final String? shortcut;
  final AxisDirection tooltipSide;

  @override
  Widget build(BuildContext context) {
    final button = CvPressable(
      onTap: onPressed,
      label: label,
      toggled: active ? true : null,
      builder: (s) {
        var bg = const Color(0x00000000);
        var fg = CvColors.textSecondary;
        if (s.disabled) {
          fg = CvColors.textDisabled;
        } else if (active) {
          bg = s.hover ? const Color(0x3DE8A33D) : CvColors.amberTint;
          fg = s.hover ? CvColors.amber300 : CvColors.amber400;
        } else if (s.pressed) {
          bg = CvColors.surfacePressed;
          fg = CvColors.textPrimary;
        } else if (s.hover) {
          bg = danger ? CvColors.emberTint : CvColors.surfaceHover;
          fg = danger ? CvColors.ember400 : CvColors.textPrimary;
        }
        return AnimatedContainer(
          duration: CvMotion.fast,
          curve: CvMotion.standard,
          width: inline ? null : CvSizes.hit,
          height: CvSizes.hit,
          padding: inline ? const EdgeInsets.symmetric(horizontal: 12) : null,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(CvRadii.md),
            border: Border.all(
                color: active && !s.disabled
                    ? const Color(0x73E8A33D)
                    : const Color(0x00000000)),
          ),
          child: DefaultTextStyle(
            style: CvTypography.label.copyWith(color: fg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [CvIcon(icon), if (inline) Text(label)],
            ),
          ),
        );
      },
    );
    return inline || onPressed == null
        ? button
        : CvTooltip(
            message: label, shortcut: shortcut, side: tooltipSide, child: button);
  }
}

/// A vertical rail or horizontal bar of tool buttons in a floating panel.
/// A row of [itemCount] items that scrolls sideways, [height] tall. A mouse
/// wheel only scrolls up and down, so here it scrolls sideways too.
class CvSideways extends StatefulWidget {
  const CvSideways({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<CvSideways> createState() => _CvSidewaysState();
}

class _CvSidewaysState extends State<CvSideways> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final delta = event.scrollDelta;
    if (delta.dx != 0) return;
    final p = _scroll.position;
    _scroll.jumpTo(
        (p.pixels + delta.dy).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: Listener(
          onPointerSignal: _wheel,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: widget.itemBuilder,
          ),
        ),
      );
}

/// [CvToolbarSeparator]s become hairlines across it.
class CvToolbar extends StatelessWidget {
  const CvToolbar({super.key, required this.children, this.axis = Axis.vertical});

  final List<Widget> children;
  final Axis axis;

  @override
  Widget build(BuildContext context) => CvPanel(
        padding: const EdgeInsets.all(CvSpacing.s3),
        child: Flex(
          direction: axis,
          mainAxisSize: MainAxisSize.min,
          spacing: CvSpacing.s2,
          children: [
            for (final child in children)
              if (child is CvToolbarSeparator)
                axis == Axis.vertical
                    ? Container(
                        width: CvSizes.hit - 8,
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: CvColors.borderSubtle)
                    : Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: CvColors.borderSubtle)
              else
                child,
          ],
        ),
      );
}

class CvToolbarSeparator extends StatelessWidget {
  const CvToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// An on/off button that says which it is: "Snap · On".
class CvToggleButton extends StatelessWidget {
  const CvToggleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.pressed,
    required this.onChanged,
    this.bordered = true,
  });

  final Lucide icon;
  final String label;
  final bool pressed;
  final ValueChanged<bool>? onChanged;
  final bool bordered;

  @override
  Widget build(BuildContext context) => CvPressable(
        onTap: onChanged == null ? null : () => onChanged!(!pressed),
        label: label,
        toggled: pressed,
        pressScale: 0.97,
        builder: (s) {
          var bg = const Color(0x00000000);
          var fg = CvColors.textSecondary;
          var border = CvColors.borderStrong;
          if (s.disabled) {
            fg = CvColors.textDisabled;
            border = CvColors.borderSubtle;
          } else if (pressed) {
            bg = CvColors.amberTint;
            fg = CvColors.amber300;
            border = const Color(0x8CE8A33D);
          } else if (s.hover || s.pressed) {
            bg = s.pressed ? CvColors.surfacePressed : CvColors.surfaceHover;
            fg = CvColors.textPrimary;
            border = CvColors.slate500;
          }
          return AnimatedContainer(
            duration: CvMotion.fast,
            height: CvSizes.hit,
            padding: const EdgeInsets.only(left: 12, right: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(CvRadii.md),
              border: Border.all(
                  color: bordered ? border : const Color(0x00000000)),
            ),
            child: DefaultTextStyle(
              style: CvTypography.label.copyWith(color: fg, height: 1),
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                CvIcon(icon, size: 18),
                Text(label),
                Text(pressed ? 'ON' : 'OFF',
                    style: CvTypography.overline.copyWith(
                        height: 1,
                        color: pressed
                            ? CvColors.amber400
                            : CvColors.textDisabled)),
              ]),
            ),
          );
        },
      );
}

typedef CvSegment<T> = ({T value, String label, Lucide? icon, Color? checked});

/// One choice out of a few, as a row of segments.
class CvSegmentedControl<T> extends StatelessWidget {
  const CvSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<CvSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: CvSizes.hit,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: CvColors.surfaceInput,
          borderRadius: BorderRadius.circular(CvRadii.md),
          border: Border.all(color: CvColors.borderSubtle),
        ),
        child: Row(spacing: 2, children: [
          for (final seg in segments)
            Expanded(
              child: CvPressable(
                onTap: () => onChanged(seg.value),
                label: seg.label,
                toggled: seg.value == value,
                radius: 7,
                pressScale: 1,
                builder: (s) {
                  final on = seg.value == value;
                  return AnimatedContainer(
                    duration: CvMotion.fast,
                    decoration: BoxDecoration(
                      color: on
                          ? CvColors.slate750
                          : s.pressed
                              ? CvColors.surfacePressed
                              : s.hover
                                  ? CvColors.surfaceHover
                                  : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                          color: on
                              ? CvColors.slate600
                              : const Color(0x00000000)),
                      boxShadow: on
                          ? const [
                              BoxShadow(
                                  color: Color(0x66000000),
                                  offset: Offset(0, 1),
                                  blurRadius: 2)
                            ]
                          : null,
                    ),
                    child: DefaultTextStyle(
                      style: CvTypography.label.copyWith(
                          height: 1,
                          color: on
                              ? seg.checked ?? CvColors.textPrimary
                              : s.hover
                                  ? CvColors.textPrimary
                                  : CvColors.textSecondary),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 6,
                        children: [
                          if (seg.icon case final icon?)
                            CvIcon(icon, size: CvSizes.iconSm),
                          Flexible(
                            child: Text(seg.label,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ]),
      );
}

enum CvButtonVariant { primary, player, secondary, ghost, danger, dangerGhost }

/// A text action. [CvButtonVariant.primary] is amber (the GM's colour),
/// [CvButtonVariant.player] teal.
class CvButton extends StatelessWidget {
  const CvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = CvButtonVariant.secondary,
    this.icon,
    this.small = false,
    this.block = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final CvButtonVariant variant;
  final Lucide? icon;
  final bool small;
  final bool block;

  @override
  Widget build(BuildContext context) {
    const clear = Color(0x00000000);
    // (rest, hover, pressed, text, border, hover border)
    final (rest, hover, press, fg, border, hoverBorder) = switch (variant) {
      CvButtonVariant.primary => (CvColors.amber500, CvColors.amber400,
          CvColors.amber600, CvColors.textOnAccent, clear, clear),
      CvButtonVariant.player => (CvColors.teal500, CvColors.teal400,
          CvColors.teal600, CvColors.textOnAccent, clear, clear),
      CvButtonVariant.secondary => (CvColors.slate800, CvColors.slate750,
          CvColors.slate700, CvColors.textPrimary, CvColors.borderStrong,
          CvColors.slate500),
      CvButtonVariant.ghost => (clear, CvColors.surfaceHover,
          CvColors.surfacePressed, CvColors.textPrimary, clear, clear),
      CvButtonVariant.danger => (CvColors.ember500, CvColors.ember400,
          CvColors.ember600, CvColors.textOnAccent, clear, clear),
      CvButtonVariant.dangerGhost => (clear, CvColors.emberTint,
          CvColors.emberTint, CvColors.ember500, clear, clear),
    };
    final ghostly = variant == CvButtonVariant.ghost ||
        variant == CvButtonVariant.dangerGhost;
    return CvPressable(
      onTap: onPressed,
      label: label,
      pressScale: 0.98,
      builder: (s) {
        final bg = s.disabled
            ? (ghostly ? clear : CvColors.slate800)
            : s.pressed
                ? press
                : s.hover
                    ? hover
                    : rest;
        final color = s.disabled
            ? CvColors.textDisabled
            : variant == CvButtonVariant.dangerGhost && s.hover
                ? CvColors.ember400
                : fg;
        return AnimatedContainer(
          duration: CvMotion.fast,
          curve: CvMotion.standard,
          height: small ? CvSizes.controlSm : CvSizes.control,
          width: block ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: small ? 12 : 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(CvRadii.md),
            border: Border.all(
                color: s.disabled && !ghostly
                    ? CvColors.borderSubtle
                    : s.hover
                        ? hoverBorder
                        : border),
          ),
          child: DefaultTextStyle(
            style: CvTypography.weight(
                    small ? CvTypography.label : CvTypography.body, 600)
                .copyWith(color: color, height: 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                if (icon case final icon?)
                  CvIcon(icon, size: small ? CvSizes.iconSm : 18),
                Text(label, maxLines: 1),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------- Forms ----------

/// A labelled single-line field. [code] is the room-code look: monospace,
/// uppercase, letters and digits only.
class CvTextInput extends StatefulWidget {
  const CvTextInput({
    super.key,
    required this.controller,
    this.label,
    this.placeholder,
    this.error,
    this.code = false,
    this.obscure = false,
    this.maxLength,
    this.onChanged,
    this.onSubmitted,
    this.keepFocus = false,
    this.icon,
    this.multiline = false,
  });

  /// Several lines, growing with the text: Enter starts a new line.
  final bool multiline;

  final TextEditingController controller;

  /// Shown before the text: a search glass, say.
  final Lucide? icon;

  /// Stays focused after Enter, for typing one line after another.
  final bool keepFocus;

  /// Dots instead of the text: passwords.
  final bool obscure;
  final String? label;
  final String? placeholder;
  final String? error;
  final bool code;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CvTextInput> createState() => _CvTextInputState();
}

class _CvTextInputState extends State<CvTextInput> {
  final _focus = FocusNode();
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invalid = widget.error != null;
    final focused = _focus.hasFocus;
    final style = widget.code
        ? CvTypography.code.copyWith(fontSize: 18, height: 1, letterSpacing: 18 * 0.3)
        : CvTypography.body.copyWith(height: 1.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (widget.label case final label?)
          Text(label,
              style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
        MouseRegion(
          cursor: SystemMouseCursors.text,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            // ponytail: focuses only; no click-to-place caret or drag
            // selection (that's Material's TextField). Keyboard editing works.
            onTap: _focus.requestFocus,
            child: AnimatedContainer(
              duration: CvMotion.fast,
              height: widget.multiline ? null : CvSizes.control,
              constraints: widget.multiline
                  ? const BoxConstraints(minHeight: 88)
                  : null,
              padding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: widget.multiline ? 10 : 0),
              alignment: widget.multiline ? Alignment.topLeft : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: CvColors.surfaceInput,
                borderRadius: BorderRadius.circular(CvRadii.md),
                border: Border.all(
                    color: invalid
                        ? CvColors.ember500
                        : focused
                            ? CvColors.bone100
                            : _hover
                                ? CvColors.slate500
                                : CvColors.borderInput),
                boxShadow: focused
                    ? [
                        BoxShadow(
                            color: invalid
                                ? CvColors.emberTint
                                : const Color(0x24E8E6E1),
                            spreadRadius: 3)
                      ]
                    : null,
              ),
              child: Row(spacing: 8, children: [
                if (widget.icon case final icon?)
                  CvIcon(icon, size: CvSizes.iconSm, color: CvColors.textSecondary),
                Expanded(
                    child: Stack(alignment: widget.multiline ? Alignment.topLeft : Alignment.centerLeft, children: [
                if (widget.placeholder case final placeholder?)
                  ListenableBuilder(
                    listenable: widget.controller,
                    builder: (context, _) => widget.controller.text.isEmpty
                        ? Text(placeholder,
                            style: style.copyWith(color: CvColors.slate400))
                        : const SizedBox.shrink(),
                  ),
                // Without enabled, Flutter web renders the field's semantics
                // <input> as disabled, so screen readers can't type into it.
                Semantics(
                  enabled: true,
                  child: EditableText(
                    controller: widget.controller,
                    focusNode: _focus,
                    obscureText: widget.obscure,
                    maxLines: widget.multiline ? null : 1,
                    keyboardType: widget.multiline ? TextInputType.multiline : null,
                    textInputAction:
                        widget.multiline ? TextInputAction.newline : null,
                    style: style,
                    cursorColor: CvColors.amber500,
                    backgroundCursorColor: CvColors.slate700,
                    selectionColor: CvColors.selectionText,
                    textCapitalization: widget.code
                        ? TextCapitalization.characters
                        : TextCapitalization.none,
                    inputFormatters: [
                      if (widget.code) ...[
                        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                        _UpperCase(),
                      ],
                      if (widget.maxLength case final max?)
                        LengthLimitingTextInputFormatter(max),
                    ],
                    onChanged: widget.onChanged,
                    onSubmitted: (text) {
                      widget.onSubmitted?.call(text);
                      if (!widget.keepFocus) return;
                      // On the web the browser's input closes on Enter even
                      // when Flutter keeps focus: reopen it.
                      _focus.unfocus();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _focus.requestFocus();
                      });
                    },
                    onEditingComplete: widget.keepFocus ? () {} : null,
                  ),
                ),
              ])),
              ]),
            ),
          ),
        ),
        if (widget.error case final error?)
          DefaultTextStyle(
            style: CvTypography.caption.copyWith(color: CvColors.ember500),
            child: Row(spacing: 6, children: [
              const CvIcon(Lucide.circleAlert, size: 14),
              Expanded(child: Text(error)),
            ]),
          ),
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

sealed class CvMenuEntry<T> {
  const CvMenuEntry();
}

class CvMenuItem<T> extends CvMenuEntry<T> {
  const CvMenuItem(this.value, this.label, {this.leading});

  final T value;
  final String label;
  final Widget? leading;
}

class CvMenuDivider<T> extends CvMenuEntry<T> {
  const CvMenuDivider();
}

class CvMenuHeading<T> extends CvMenuEntry<T> {
  const CvMenuHeading(this.text);

  final String text;
}

/// A labelled select: shows the current item, opens a menu of [entries].
/// [above] opens the menu upwards, for selects near the bottom.
class CvDropdown<T> extends StatefulWidget {
  const CvDropdown({
    super.key,
    required this.entries,
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder = 'Choose…',
    this.above = false,
  });

  final List<CvMenuEntry<T>> entries;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;
  final String placeholder;
  final bool above;

  @override
  State<CvDropdown<T>> createState() => _CvDropdownState<T>();
}

class _CvDropdownState<T> extends State<CvDropdown<T>> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  double _width = 220;

  void _toggle() => setState(_portal.toggle);

  void _close() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  void _choose(T value) {
    _close();
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.entries
        .whereType<CvMenuItem<T>>()
        .where((e) => e.value == widget.value)
        .firstOrNull;
    final open = _portal.isShowing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        if (widget.label case final label?)
          Text(label,
              style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
        TapRegion(
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
                    targetAnchor:
                        widget.above ? Alignment.topLeft : Alignment.bottomLeft,
                    followerAnchor:
                        widget.above ? Alignment.bottomLeft : Alignment.topLeft,
                    offset: Offset(0, widget.above ? -6 : 6),
                    child: TapRegion(
                      groupId: this,
                      child: CvPopIn(
                        child: CvMenu<T>(
                          width: math.max(_width, 220),
                          entries: widget.entries,
                          value: widget.value,
                          onSelected: _choose,
                        ),
                      ),
                    ),
                  ),
                ),
                child: LayoutBuilder(builder: (context, constraints) {
                  _width = constraints.maxWidth;
                  return CvPressable(
                    onTap: _toggle,
                    label: widget.label,
                    pressScale: 1,
                    builder: (s) => AnimatedContainer(
                      duration: CvMotion.fast,
                      height: CvSizes.control,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: CvColors.surfaceInput,
                        borderRadius: BorderRadius.circular(CvRadii.md),
                        border: Border.all(
                            color: open
                                ? CvColors.bone100
                                : s.hover
                                    ? CvColors.slate500
                                    : CvColors.borderInput),
                      ),
                      child: Row(spacing: 10, children: [
                        ?current?.leading,
                        Expanded(
                          child: Text(
                            current?.label ?? widget.placeholder,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CvTypography.body.copyWith(
                                color: current == null
                                    ? CvColors.slate400
                                    : CvColors.textPrimary),
                          ),
                        ),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: CvMotion.fast,
                          curve: CvMotion.standard,
                          child: const CvIcon(Lucide.chevronDown,
                              size: CvSizes.iconSm,
                              color: CvColors.textSecondary),
                        ),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A list of choices on a solid popover surface.
class CvMenu<T> extends StatelessWidget {
  const CvMenu({
    super.key,
    required this.entries,
    required this.onSelected,
    this.value,
    this.width = 220,
  });

  final List<CvMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final T? value;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: CvColors.surfacePanelSolid,
          borderRadius: BorderRadius.circular(CvRadii.md),
          border: Border.all(color: CvColors.borderSubtle),
          boxShadow: CvElevation.shadow2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries)
              switch (entry) {
                CvMenuDivider() => Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    color: CvColors.borderSubtle),
                CvMenuHeading(:final text) => Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    child: CvOverline(text)),
                CvMenuItem(:final value, :final label, :final leading) =>
                  CvPressable(
                    onTap: () => onSelected(value),
                    label: label,
                    radius: CvRadii.sm,
                    pressScale: 1,
                    builder: (s) => Container(
                      height: CvSizes.hit,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: s.pressed
                            ? CvColors.surfacePressed
                            : s.hover
                                ? CvColors.surfaceHover
                                : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(CvRadii.sm),
                      ),
                      child: Row(spacing: 10, children: [
                        ?leading,
                        Expanded(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: value == this.value
                                  ? CvTypography.weight(CvTypography.body, 500)
                                  : CvTypography.body),
                        ),
                      ]),
                    ),
                  ),
              },
          ],
        ),
      );
}

/// An on/off switch with its label on the left and the track on the right.
class CvSwitch extends StatelessWidget {
  const CvSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final Widget label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CvPressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        toggled: value,
        radius: CvRadii.sm,
        pressScale: 1,
        builder: (s) => ConstrainedBox(
          constraints: const BoxConstraints(minHeight: CvSizes.hit),
          child: Row(children: [
            Expanded(
              child: DefaultTextStyle(
                style: CvTypography.body.copyWith(
                    color: s.disabled
                        ? CvColors.textDisabled
                        : CvColors.textPrimary),
                child: label,
              ),
            ),
            AnimatedContainer(
              duration: CvMotion.fast,
              curve: CvMotion.standard,
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CvRadii.pill),
                color: value
                    ? (s.hover ? CvColors.amber400 : CvColors.amber500)
                    : (s.hover ? CvColors.slate600 : CvColors.slate700),
                border: value ? null : Border.all(color: CvColors.slate600),
              ),
              child: AnimatedAlign(
                duration: CvMotion.fast,
                curve: CvMotion.standard,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: s.pressed ? 22 : 18,
                  height: 18,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(CvRadii.pill),
                    color: value ? CvColors.slate950 : CvColors.slate300,
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// A whole-number slider with its label and current value above it.
class CvSlider extends StatelessWidget {
  const CvSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.format,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    final t = (value - min) / (max - min);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
          Text(format?.call(value) ?? '$value',
              style: CvTypography.caption.copyWith(
                  fontFamily: CvTypography.mono, fontWeight: FontWeight.w500)),
        ]),
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          void at(Offset local) {
            final v = (min + (local.dx / width).clamp(0.0, 1.0) * (max - min))
                .round();
            if (v != value) onChanged(v);
          }

          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => at(d.localPosition),
              onHorizontalDragUpdate: (d) => at(d.localPosition),
              child: SizedBox(
                height: CvSizes.hit,
                child: Stack(alignment: Alignment.centerLeft, clipBehavior: Clip.none, children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                        color: CvColors.slate700,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Container(
                    width: width * t,
                    height: 4,
                    decoration: BoxDecoration(
                        color: CvColors.amber500,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  Positioned(
                    left: width * t - 9,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: CvColors.bone100,
                        boxShadow: [
                          BoxShadow(color: CvColors.slate950, spreadRadius: 2),
                          BoxShadow(
                              color: Color(0x80000000),
                              offset: Offset(0, 2),
                              blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
      ],
    );
  }
}

// ---------- Feedback ----------

/// A spinning arc: slate track, coloured head.
class CvSpinner extends StatefulWidget {
  const CvSpinner({super.key, this.size = 16, this.color = CvColors.bone100});

  final double size;
  final Color color;

  @override
  State<CvSpinner> createState() => _CvSpinnerState();
}

class _CvSpinnerState extends State<CvSpinner>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))
    ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _spin,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _ArcPainter(widget.color),
        ),
      );
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = CvColors.slate700;
    canvas.drawOval(rect, paint);
    canvas.drawArc(rect, -math.pi * 3 / 4, math.pi / 2, false,
        paint..color = color);
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

/// A labelled bar for work of unknown length.
class CvProgressBar extends StatefulWidget {
  const CvProgressBar({super.key, required this.label, this.color = CvColors.bone100});

  final String label;
  final Color color;

  @override
  State<CvProgressBar> createState() => _CvProgressBarState();
}

class _CvProgressBarState extends State<CvProgressBar>
    with SingleTickerProviderStateMixin {
  late final _run = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Text(widget.label, style: CvTypography.label),
          ClipRRect(
            borderRadius: BorderRadius.circular(CvRadii.pill),
            child: Container(
              height: 6,
              color: CvColors.slate750,
              child: LayoutBuilder(
                builder: (context, constraints) => AnimatedBuilder(
                  animation: _run,
                  builder: (context, _) {
                    final w = constraints.maxWidth;
                    final t = CvMotion.standard.transform(_run.value);
                    return Transform.translate(
                      offset: Offset(-0.4 * w + t * 1.4 * w, 0),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.color,
                            borderRadius: BorderRadius.circular(CvRadii.pill),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      );
}

/// The square icon badge at the top of dialogs and cards.
class CvIconBadge extends StatelessWidget {
  const CvIconBadge(this.icon, {super.key, this.tone = CvTone.neutral});

  final Lucide icon;
  final CvTone tone;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone.tint,
          borderRadius: BorderRadius.circular(CvRadii.md),
        ),
        child: CvIcon(icon, color: tone.color),
      );
}

/// A modal dialog over a scrim: icon, title, body, actions. The actions
/// pop the route with their result.
Future<T?> showCvDialog<T>({
  required BuildContext context,
  required String title,
  required Widget body,
  required List<Widget> Function(BuildContext context) actions,
  Lucide? icon,
  CvTone tone = CvTone.neutral,
}) =>
    showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: CvColors.surfaceScrim,
      transitionDuration: CvMotion.slow,
      transitionBuilder: (context, animation, _, child) {
        final t = CvMotion.enter.transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 4 * (1 - t)),
            child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
          ),
        );
      },
      pageBuilder: (context, _, _) => Center(
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(CvSpacing.s8),
          decoration: BoxDecoration(
            color: CvColors.surfacePanelSolid,
            borderRadius: BorderRadius.circular(CvRadii.xl),
            border: Border.all(color: CvColors.borderSubtle),
            boxShadow: CvElevation.shadow3,
          ),
          child: DefaultTextStyle(
            style: CvTypography.body.copyWith(color: CvColors.textSecondary),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  CvIconBadge(icon, tone: tone),
                  const SizedBox(height: CvSpacing.s6),
                ],
                Semantics(
                    header: true,
                    child: Text(title, style: CvTypography.title)),
                const SizedBox(height: CvSpacing.s4),
                body,
                const SizedBox(height: CvSpacing.s8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  spacing: CvSpacing.s4,
                  children: actions(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );

typedef CvToastData = ({int id, String message, CvTone tone});

/// Short messages at the bottom of the table. Each leaves after a few
/// seconds; at most three show at once.
class CvToasts extends ValueNotifier<List<CvToastData>> {
  CvToasts() : super(const []);

  static const lifetime = Duration(seconds: 4);
  int _next = 0;
  final _timers = <Timer>{};

  void show(String message, {CvTone tone = CvTone.neutral}) {
    final id = _next++;
    value = [
      ...value.skip(math.max(0, value.length - 2)),
      (id: id, message: message, tone: tone),
    ];
    late final Timer timer;
    timer = Timer(lifetime, () {
      _timers.remove(timer);
      dismiss(id);
    });
    _timers.add(timer);
  }

  void dismiss(int id) => value = [
        for (final t in value)
          if (t.id != id) t,
      ];

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }
}

class CvToastStack extends StatelessWidget {
  const CvToastStack({super.key, required this.toasts});

  final CvToasts toasts;

  static const _icons = {
    CvTone.neutral: Lucide.info,
    CvTone.ok: Lucide.circleCheck,
    CvTone.gm: Lucide.crown,
    CvTone.player: Lucide.userRound,
    CvTone.danger: Lucide.triangleAlert,
  };

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: toasts,
        builder: (context, list, _) => Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            for (final t in list)
              CvPopIn(
                key: ValueKey(t.id),
                duration: CvMotion.slow,
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    constraints: const BoxConstraints(
                        maxWidth: 440, minHeight: CvSizes.hit),
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: CvColors.surfacePanelSolid,
                      borderRadius: BorderRadius.circular(CvRadii.lg),
                      border: Border.all(
                          color: t.tone == CvTone.danger
                              ? const Color(0x73EF6F5E)
                              : CvColors.borderSubtle),
                      boxShadow: CvElevation.shadow2,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
                      CvIcon(_icons[t.tone]!,
                          size: 18,
                          color: t.tone == CvTone.neutral
                              ? CvColors.textSecondary
                              : t.tone.color),
                      Flexible(
                          child: Text(t.message, style: CvTypography.body)),
                      CvPressable(
                        onTap: () => toasts.dismiss(t.id),
                        label: 'Dismiss',
                        builder: (s) => Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: s.hover
                                ? CvColors.surfaceHover
                                : const Color(0x00000000),
                            borderRadius: BorderRadius.circular(CvRadii.md),
                          ),
                          child: CvIcon(Lucide.x,
                              size: CvSizes.iconSm,
                              color: s.hover
                                  ? CvColors.textPrimary
                                  : CvColors.textSecondary),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      );
}

// ---------- Table ----------

/// The room code with a copy button, at the top left of every table.
class CvRoomCodeChip extends StatefulWidget {
  const CvRoomCodeChip({super.key, required this.code});

  final String code;

  @override
  State<CvRoomCodeChip> createState() => _CvRoomCodeChipState();
}

class _CvRoomCodeChipState extends State<CvRoomCodeChip> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.code));
    _reset?.cancel();
    setState(() => _copied = true);
    _reset = Timer(const Duration(milliseconds: 1600),
        () => setState(() => _copied = false));
  }

  @override
  Widget build(BuildContext context) => CvPanel(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: SizedBox(
          height: CvSizes.hit - 2,
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            const CvOverline('Room'),
            Semantics(
              label: 'Room code ${widget.code.split('').join(' ')}',
              excludeSemantics: true,
              child: Text(widget.code, style: CvTypography.code),
            ),
            CvPressable(
              onTap: _copy,
              label: _copied ? 'Copied' : 'Copy room code',
              radius: CvRadii.sm,
              builder: (s) => AnimatedContainer(
                duration: CvMotion.fast,
                height: 36,
                constraints: const BoxConstraints(minWidth: 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: s.pressed
                      ? CvColors.surfacePressed
                      : s.hover
                          ? CvColors.surfaceHover
                          : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(CvRadii.sm),
                ),
                child: DefaultTextStyle(
                  style: CvTypography.weight(CvTypography.caption, 500).copyWith(
                      color: _copied
                          ? CvColors.moss500
                          : s.hover
                              ? CvColors.textPrimary
                              : CvColors.textSecondary),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    spacing: 6,
                    children: [
                      CvIcon(_copied ? Lucide.check : Lucide.copy,
                          size: CvSizes.iconSm),
                      if (_copied) const Text('Copied'),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// Someone at the table: initials on their hue. The GM wears an amber ring.
class CvAvatar extends StatelessWidget {
  const CvAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.gm = false,
    this.size = CvSizes.avatar,
    this.label,
  });

  final String initials;
  final Color color;
  final bool gm;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        excludeSemantics: label != null,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: gm ? CvColors.amber500 : color,
            boxShadow: [
              if (gm) const BoxShadow(color: CvColors.amber500, spreadRadius: 4),
              const BoxShadow(
                  color: CvColors.surfacePanelSolid, spreadRadius: 2),
            ],
          ),
          child: Text(initials,
              style: CvTypography.weight(CvTypography.caption, 600).copyWith(
                  fontSize: (size * 0.38).roundToDouble(),
                  height: 1,
                  color: CvColors.slate950)),
        ),
      );
}

/// Overlapping avatars and a count: "3 at the table".
class CvAvatarStack extends StatelessWidget {
  const CvAvatarStack(
      {super.key, required this.avatars, this.max = 4, this.caption = 'at the table'});

  final List<CvAvatar> avatars;
  final int max;

  /// After the count: "4 at the table".
  final String caption;

  @override
  Widget build(BuildContext context) {
    final shown = avatars.take(max).toList();
    final more = avatars.length - shown.length;
    final items = <Widget>[
      ...shown,
      if (more > 0)
        Container(
          width: CvSizes.avatar,
          height: CvSizes.avatar,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: CvColors.slate750,
            boxShadow: [
              BoxShadow(color: CvColors.surfacePanelSolid, spreadRadius: 2)
            ],
          ),
          child: Text('+$more',
              style: CvTypography.weight(CvTypography.caption, 600)
                  .copyWith(height: 1)),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 10),
      child: SizedBox(
        height: CvSizes.hit,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Each avatar but the last gives up 6 px, so the next overlaps it.
          for (final (i, item) in items.indexed)
            Align(
              widthFactor:
                  i == items.length - 1 ? 1 : (CvSizes.avatar - 6) / CvSizes.avatar,
              alignment: Alignment.centerLeft,
              child: item,
            ),
          const SizedBox(width: 8),
          Text('${avatars.length} $caption',
              style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
        ]),
      ),
    );
  }
}

/// The app shell: no Material, the design's ground and type.
Widget cvApp({required String title, required Widget home}) => WidgetsApp(
      title: title,
      color: CvColors.amber500,
      textStyle: CvTypography.body,
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<T>(
            settings: settings,
            pageBuilder: (context, _, _) => builder(context),
          ),
      home: ColoredBox(color: CvColors.bgGround, child: home),
    );
