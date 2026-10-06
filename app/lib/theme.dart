import 'package:chimera_core/chimera_core.dart' show PlayerId;
import 'package:flutter/widgets.dart';

import 'members.dart' show memberColor, members;

/// Design tokens from the Chimera VTT design system (Claude Design project
/// 32b42cc6, tokens/*.css). Names follow the CSS custom properties.
abstract final class CvColors {
  // Slate: ground, surfaces, borders. Cool, near-black.
  static const slate950 = Color(0xFF0B0E12);
  static const slate900 = Color(0xFF0E1217);
  static const slate850 = Color(0xFF131820);
  static const slate800 = Color(0xFF1A2029);
  static const slate750 = Color(0xFF20272F);
  static const slate700 = Color(0xFF29313B);
  static const slate600 = Color(0xFF3A4450);
  static const slate500 = Color(0xFF58626F);
  static const slate400 = Color(0xFF7C8592);
  static const slate300 = Color(0xFF9AA3AD);
  static const bone100 = Color(0xFFECE8DD);
  static const bone50 = Color(0xFFF6F3EA);

  /// Rune cyan: the GM and the current selection. Flat, never glowing.
  static const rune300 = Color(0xFFA6EFF8);
  static const rune400 = Color(0xFF80E7F4);
  static const rune500 = Color(0xFF5FE0F0);
  static const rune600 = Color(0xFF36BFD1);
  static const rune900 = Color(0xFF0E2E34);
  static const runeTint = Color(0x245FE0F0);

  /// Gold: players and ownership.
  static const gold300 = Color(0xFFF3D394);
  static const gold400 = Color(0xFFEEC26C);
  static const gold500 = Color(0xFFE8B04E);
  static const gold600 = Color(0xFFC99335);
  static const gold900 = Color(0xFF3A2B12);
  static const goldTint = Color(0x29E8B04E);

  /// Ember: danger, remove, errors.
  static const ember400 = Color(0xFFF48A7A);
  static const ember500 = Color(0xFFEF6F5E);
  static const ember600 = Color(0xFFD35746);
  static const ember900 = Color(0xFF3A1914);
  static const emberTint = Color(0x29EF6F5E);

  /// Moss: saved / connected.
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
    Color(0xFFF0A878),
  ];

  static const fogGm = Color(0x8C0C0E12);
  static const fogPlayer = Color(0xFF0B0C0F);
  static const fogRevealPreview = Color(0x2E5FE0F0);
  static const fogCoverPreview = Color(0x730C0E12);

  // Semantic aliases.
  static const bgGround = slate900;
  static const bgSunken = slate950;
  static const surfacePanel = Color(0xF010141A);
  static const surfacePanelSolid = Color(0xFF10141A);
  static const surfaceRaised = slate800;
  static const surfaceHover = Color(0x12ECE8DD);
  static const surfacePressed = Color(0x1FECE8DD);
  static const surfaceSelected = runeTint;
  static const surfaceInput = slate950;
  static const surfaceScrim = Color(0xB808090C);
  static const borderSubtle = slate700;

  /// The outer hairline of framed panels, and the inner one 4 px in.
  static const borderFrame = slate600;
  static const borderFrameInner = Color(0xFF1C232B);
  static const borderStrong = slate600;
  static const borderInput = slate600;
  static const textPrimary = bone100;
  static const textSecondary = slate300;
  static const textDisabled = slate500;
  static const textOnAccent = slate950;
  static const textGm = rune500;
  static const textPlayer = gold400;
  static const textDanger = ember500;
  static const textOk = moss500;
  static const accentGm = rune500;
  static const accentSelect = rune500;
  static const accentPlayer = gold500;
  static const accentDanger = ember500;
  static const focusRing = bone50;
  static const focusRingHalo = Color(0xE60E1014);
  static const selectionText = Color(0x4D5FE0F0);
}

abstract final class CvTypography {
  static const sans = 'Mulish';

  /// Titles and headings.
  static const display = 'Marcellus';

  /// The wordmark and small engraved labels.
  static const displayCaps = 'Marcellus SC';
  static const mono = 'IBM Plex Mono';

  static TextStyle _s(double size, double lh,
          {int w = 400, double tracking = 0, String family = sans}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: lh / size,
        fontWeight: FontWeight.values[w ~/ 100 - 1],
        // Mulish is a variable font: the weight axis does the work.
        fontVariations: [FontVariation.weight(w.toDouble())],
        letterSpacing: tracking * size,
        color: CvColors.textPrimary,
      );

  // Titles are set in Marcellus, which has one weight.
  static final displayLg = _s(40, 48, family: display);
  static final titleLg = _s(26, 32, family: display);
  static final title = _s(20, 26, family: display);
  static final body = _s(14, 20);
  static final bodySm = _s(13, 18);
  static final label = _s(13, 16, w: 500);
  static final caption = _s(12, 16);

  /// Engraved section labels: shown in capitals, heavy, tracked, rune-lit.
  static final overline = _s(11, 14, w: 800, tracking: 0.22)
      .copyWith(color: CvColors.rune400);
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
  static const sm = 4.0;
  static const md = 6.0;

  /// Panels: crisp frames, not soft cards.
  static const lg = 6.0;

  /// Dialogs.
  static const xl = 8.0;
  static const pill = 999.0;

  static const borderWidth = 1.0;
  static const borderWidthStrong = 2.0;
  static const focusWidth = 2.0;

  /// Token ownership / selection ring.
  static const ringToken = 3.0;

  /// The gap between a framed panel's outer and inner hairlines.
  static const frameInset = 4.0;

  /// The rune diamond on framed panels.
  static const markerSize = 8.0;
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
