import 'package:chimera_core/chimera_core.dart' show PlayerId;
import 'package:flutter/widgets.dart';

import 'members.dart' show memberColor, members;

/// Design tokens from the Chimera VTT design system (Claude Design project
/// 32b42cc6, tokens/*.css). Names follow the CSS custom properties.
abstract final class CvColors {
  static const slate950 = Color(0xFF0E1014);
  static const slate900 = Color(0xFF14161B);
  static const slate850 = Color(0xFF1A1D24);
  static const slate800 = Color(0xFF22262F);
  static const slate750 = Color(0xFF292D37);
  static const slate700 = Color(0xFF2E3340);
  static const slate600 = Color(0xFF3D4352);
  static const slate500 = Color(0xFF5A6173);
  static const slate400 = Color(0xFF7C8395);
  static const slate300 = Color(0xFFA3A9B8);
  static const bone100 = Color(0xFFE8E6E1);
  static const bone50 = Color(0xFFF6F4EF);

  /// The GM and the current selection.
  static const amber300 = Color(0xFFF5C77E);
  static const amber400 = Color(0xFFF0B65C);
  static const amber500 = Color(0xFFE8A33D);
  static const amber600 = Color(0xFFC98A2B);
  static const amber900 = Color(0xFF3A2A12);
  static const amberTint = Color(0x29E8A33D);

  /// Players and ownership.
  static const teal300 = Color(0xFF86D9CE);
  static const teal400 = Color(0xFF5CC7BA);
  static const teal500 = Color(0xFF3FB6A8);
  static const teal600 = Color(0xFF2F978B);
  static const teal900 = Color(0xFF10302D);
  static const tealTint = Color(0x293FB6A8);

  /// Danger, remove, errors.
  static const ember400 = Color(0xFFF48A7A);
  static const ember500 = Color(0xFFEF6F5E);
  static const ember600 = Color(0xFFD35746);
  static const ember900 = Color(0xFF3A1914);
  static const emberTint = Color(0x29EF6F5E);

  /// Saved / connected.
  static const moss500 = Color(0xFF8CC97A);
  static const mossTint = Color(0x298CC97A);

  /// Player identity hues for avatars and token backplates; text on them is
  /// [slate950].
  static const players = [
    Color(0xFF7FB3E8),
    Color(0xFFC79BE6),
    Color(0xFFE89BB1),
    Color(0xFF9FD08A),
    Color(0xFFE8C27F),
    Color(0xFF8FD3E0),
  ];

  static const fogGm = Color(0x8C0C0E12);
  static const fogPlayer = Color(0xFF0B0C0F);
  static const fogRevealPreview = Color(0x383FB6A8);
  static const fogCoverPreview = Color(0x730C0E12);

  // Semantic aliases.
  static const bgGround = slate900;
  static const bgSunken = slate950;
  static const surfacePanel = Color(0xF016181E);
  static const surfacePanelSolid = Color(0xFF16181E);
  static const surfaceRaised = slate800;
  static const surfaceHover = Color(0x12E8E6E1);
  static const surfacePressed = Color(0x1FE8E6E1);
  static const surfaceSelected = amberTint;
  static const surfaceInput = slate950;
  static const surfaceScrim = Color(0xB808090C);
  static const borderSubtle = slate700;
  static const borderStrong = slate600;
  static const borderInput = slate600;
  static const textPrimary = bone100;
  static const textSecondary = slate300;
  static const textDisabled = slate500;
  static const textOnAccent = slate950;
  static const textGm = amber500;
  static const textPlayer = teal400;
  static const textDanger = ember500;
  static const textOk = moss500;
  static const accentGm = amber500;
  static const accentSelect = amber500;
  static const accentPlayer = teal500;
  static const accentDanger = ember500;
  static const focusRing = bone50;
  static const focusRingHalo = Color(0xE60E1014);
  static const selectionText = Color(0x59E8A33D);
}

abstract final class CvTypography {
  static const sans = 'IBM Plex Sans';
  static const mono = 'IBM Plex Mono';

  static TextStyle _s(double size, double lh,
          {int w = 400, double tracking = 0, String family = sans}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: lh / size,
        fontWeight: FontWeight.values[w ~/ 100 - 1],
        // Plex Sans is a variable font: the weight axis does the work.
        fontVariations: [FontVariation.weight(w.toDouble())],
        letterSpacing: tracking * size,
        color: CvColors.textPrimary,
      );

  static final display = _s(40, 48, w: 600, tracking: -0.01);
  static final titleLg = _s(24, 32, w: 600);
  static final title = _s(18, 24, w: 600);
  static final body = _s(14, 20);
  static final bodySm = _s(13, 18);
  static final label = _s(13, 16, w: 500);
  static final caption = _s(12, 16);
  static final overline = _s(11, 14, w: 600, tracking: 0.08)
      .copyWith(color: CvColors.textSecondary);
  static final code = _s(15, 20, w: 500, tracking: 0.14, family: mono);
  static final codeLg = _s(28, 36, w: 500, tracking: 0.14, family: mono);

  /// A [style] at another weight, keeping the variable axis in step.
  static TextStyle weight(TextStyle style, int w) => style.copyWith(
      fontWeight: FontWeight.values[w ~/ 100 - 1],
      fontVariations: [FontVariation.weight(w.toDouble())]);
}

abstract final class CvSpacing {
  static const s1 = 2.0;
  static const s2 = 4.0;
  static const s3 = 6.0;
  static const s4 = 8.0;
  static const s5 = 12.0;
  static const s6 = 16.0;
  static const s7 = 20.0;
  static const s8 = 24.0;
  static const s9 = 32.0;
  static const s10 = 40.0;
  static const s11 = 48.0;
  static const s12 = 64.0;
}

abstract final class CvSizes {
  static const hit = 44.0;
  static const control = 44.0;
  static const controlSm = 36.0;
  static const icon = 20.0;
  static const iconSm = 16.0;
  static const token = 56.0;
  static const avatar = 32.0;
  static const rail = 60.0;

  /// Floating chrome distance from the viewport edge.
  static const insetScreen = 16.0;

  /// Gap between a token and its floating card.
  static const gapFloat = 12.0;
}

abstract final class CvRadii {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 10.0;

  /// Panels.
  static const lg = 14.0;

  /// Dialogs.
  static const xl = 20.0;
  static const pill = 999.0;

  static const borderWidth = 1.0;
  static const borderWidthStrong = 2.0;
  static const focusWidth = 2.0;

  /// Token ownership / selection ring.
  static const ringToken = 3.0;
}

abstract final class CvElevation {
  static const _a35 = Color(0x59000000);
  static const shadow1 = [
    BoxShadow(color: _a35, offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4), blurRadius: 14),
  ];
  static const shadow2 = [
    BoxShadow(color: _a35, offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 10), blurRadius: 28),
  ];
  static const shadow3 = [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 8),
    BoxShadow(color: Color(0x8C000000), offset: Offset(0, 24), blurRadius: 56),
  ];
  static const shadowToken = [
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: _a35, offset: Offset(0, 2), blurRadius: 6),
  ];
  static const shadowTokenLift = [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 6), blurRadius: 10),
    BoxShadow(color: _a35, offset: Offset(0, 14), blurRadius: 24),
  ];
  static const blurPanel = 12.0;
}

abstract final class CvMotion {
  static const instant = Duration(milliseconds: 60);
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const pan = Duration(milliseconds: 420);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const enter = Cubic(0.05, 0.7, 0.1, 1);
  static const exit = Cubic(0.3, 0, 1, 1);

  /// Token snap-drop: a small overshoot.
  static const settle = Cubic(0.34, 1.4, 0.64, 1);
}

/// A player's identity hue, the same on their avatar and their tokens: the
/// colour they picked as a member, else one hashed from their id.
// String.hashCode differs between the VM and the web, so hash by hand: the
// GM on macOS and a player in a browser must agree.
Color playerColor(PlayerId player) => switch (members.value[player]) {
      (name: _, :final color) => memberColor(color),
      null => CvColors.players[player.value.codeUnits
              .fold(0, (h, c) => (h * 31 + c) & 0x3fffffff) %
          CvColors.players.length],
    };
