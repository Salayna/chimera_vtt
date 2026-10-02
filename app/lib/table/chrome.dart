import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../ui/cv.dart';
import 'table_view.dart';

/// The floating chrome around a table (layout A in the design system):
/// everything floats over the map, inset [CvSizes.insetScreen] from the
/// edges, and nothing reflows it.

/// Enough of a player id to tell players apart, until players have names.
String shortId(PlayerId id) => id.value.substring(0, 4);

/// A cell's name for readouts: column letter, row number ("C4").
String cellName(Point p, Grid grid) {
  final col = ((p.x - grid.offset.x) / grid.cellSize).floor();
  final row = ((p.y - grid.offset.y) / grid.cellSize).floor();
  var letters = '';
  for (var n = col; n >= 0; n = n ~/ 26 - 1) {
    letters = String.fromCharCode(65 + n % 26) + letters;
  }
  return '$letters${row + 1}';
}

CvAvatar avatarFor(Presence p, {double size = CvSizes.avatar}) {
  final id = PlayerId(p.player);
  return CvAvatar(
    initials: p.gm ? 'GM' : shortId(id).substring(0, 2).toUpperCase(),
    color: playerColor(id),
    gm: p.gm,
    size: size,
    label: p.gm ? 'GM' : 'Player ${shortId(id)}',
  );
}

/// The GM's tools, a rail on the left edge.
class GmRail extends StatelessWidget {
  const GmRail({
    super.key,
    required this.controller,
    this.onAddToken,
    this.onSetMap,
    this.onExport,
    this.onImport,
  });

  final TableController controller;
  final VoidCallback? onAddToken;
  final VoidCallback? onSetMap;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          Widget tool(Tool t, Lucide icon, String label, String key) =>
              CvToolButton(
                icon: icon,
                label: label,
                shortcut: key,
                active: controller.tool == t,
                onPressed: () => controller.tool = t,
              );
          return CvToolbar(children: [
            tool(Tool.move, Lucide.mousePointer2, 'Move', 'V'),
            const CvToolbarSeparator(),
            tool(Tool.fogBrush, Lucide.paintbrush, 'Fog brush', 'B'),
            tool(Tool.fogRect, Lucide.squareDashed, 'Fog rectangle', 'R'),
            const CvToolbarSeparator(),
            CvToolButton(
                icon: Lucide.circlePlus,
                label: 'Add token',
                shortcut: 'T',
                onPressed: onAddToken),
            CvToolButton(
                icon: Lucide.imageUp,
                label: 'Change map',
                shortcut: 'M',
                onPressed: onSetMap),
            CvToolButton(
                icon: Lucide.grid3x3,
                label: 'Grid',
                shortcut: 'G',
                active: controller.gridOptions,
                onPressed: () =>
                    controller.gridOptions = !controller.gridOptions),
            const CvToolbarSeparator(),
            CvToolButton(
                icon: Lucide.download,
                label: 'Export scene',
                shortcut: 'E',
                onPressed: onExport),
            CvToolButton(
                icon: Lucide.upload,
                label: 'Import scene',
                shortcut: 'I',
                onPressed: onImport),
          ]);
        },
      );
}

/// Cover or reveal, and the brush size, while a fog tool is out.
class FogOptions extends StatelessWidget {
  const FogOptions({super.key, required this.controller, required this.grid});

  final TableController controller;
  final Grid grid;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final tool = controller.tool;
          if (tool == Tool.move) return const SizedBox.shrink();
          // The brush is sized in cells across; the controller holds a radius.
          final cells = (controller.brushRadius * 2 / grid.cellSize)
              .round()
              .clamp(1, 8);
          return CvPopIn(
            child: CvPanel(
              width: 220,
              padding: const EdgeInsets.all(CvSpacing.s5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    CvOverline(
                        tool == Tool.fogBrush ? 'Fog brush' : 'Fog rectangle'),
                    const CvKbd('X'),
                  ]),
                  CvSegmentedControl<FogMode>(
                    value: controller.fogMode,
                    onChanged: (m) => controller.fogMode = m,
                    segments: const [
                      (
                        value: FogMode.cover,
                        label: 'Cover',
                        icon: Lucide.eyeOff,
                        checked: null
                      ),
                      (
                        value: FogMode.reveal,
                        label: 'Reveal',
                        icon: Lucide.eye,
                        checked: CvColors.teal300
                      ),
                    ],
                  ),
                  if (tool == Tool.fogBrush)
                    CvSlider(
                      label: 'Size',
                      value: cells,
                      min: 1,
                      max: 8,
                      format: (v) => v == 1 ? '1 cell' : '$v cells',
                      onChanged: (v) =>
                          controller.brushRadius = v * grid.cellSize / 2,
                    ),
                ],
              ),
            ),
          );
        },
      );
}

/// The grid's cell size, while the GM's grid panel is open. Applies each
/// valid value as it's typed, so the GM sees the grid move over the map.
class GridOptions extends StatefulWidget {
  const GridOptions(
      {super.key,
      required this.controller,
      required this.grid,
      required this.onCellSize});

  final TableController controller;
  final Grid grid;
  final ValueChanged<double> onCellSize;

  static const minCell = 16;
  static const maxCell = 1024;

  @override
  State<GridOptions> createState() => _GridOptionsState();
}

class _GridOptionsState extends State<GridOptions> {
  late final _text = TextEditingController(text: _format(widget.grid.cellSize));
  String? _error;

  static String _format(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  @override
  void didUpdateWidget(GridOptions old) {
    super.didUpdateWidget(old);
    // Changed elsewhere (an imported scene): show it, unless it's what the
    // field already says.
    final size = widget.grid.cellSize;
    if (size != old.grid.cellSize && double.tryParse(_text.text) != size) {
      _text.text = _format(size);
      _error = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _changed(String value) {
    final size = double.tryParse(value.trim());
    final valid = size != null &&
        size >= GridOptions.minCell &&
        size <= GridOptions.maxCell;
    setState(() => _error = valid
        ? null
        : 'From ${GridOptions.minCell} to ${GridOptions.maxCell} px.');
    if (valid && size != widget.grid.cellSize) widget.onCellSize(size);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, child) => widget.controller.gridOptions
            ? CvPopIn(child: child!)
            : const SizedBox.shrink(),
        child: CvPanel(
          width: 220,
          padding: const EdgeInsets.all(CvSpacing.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 10,
            children: [
              const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [CvOverline('Grid'), CvKbd('G')]),
              // Keys typed here are text, not the table's shortcuts.
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: (_, _) => KeyEventResult.skipRemainingHandlers,
                child: CvTextInput(
                  controller: _text,
                  label: 'Cell size (px)',
                  error: _error,
                  onChanged: _changed,
                ),
              ),
              if (_error == null)
                Text('Match one square of the map image.',
                    style: CvTypography.caption
                        .copyWith(color: CvColors.textSecondary)),
            ],
          ),
        ),
      );
}

/// Snap, zoom and fit, at the bottom right. [snap] shows the snap toggle
/// (GM only).
class ZoomCluster extends StatelessWidget {
  const ZoomCluster({super.key, required this.controller, this.snap = false});

  final TableController controller;
  final bool snap;

  @override
  Widget build(BuildContext context) => CvToolbar(axis: Axis.horizontal, children: [
        if (snap) ...[
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => CvTooltip(
              message: 'Snap to grid · hold ⌥ to place freely',
              shortcut: 'S',
              side: AxisDirection.up,
              child: CvToggleButton(
                icon: Lucide.magnet,
                label: 'Snap',
                bordered: false,
                pressed: controller.snap,
                onChanged: (v) => controller.snap = v,
              ),
            ),
          ),
          const CvToolbarSeparator(),
        ],
        CvToolButton(
            icon: Lucide.zoomOut,
            label: 'Zoom out',
            shortcut: '−',
            tooltipSide: AxisDirection.up,
            onPressed: () => controller.zoomBy(1 / 1.25)),
        ValueListenableBuilder(
          valueListenable: controller.view,
          builder: (context, _, _) => CvTooltip(
            message: 'Reset zoom to 100%',
            side: AxisDirection.up,
            child: CvPressable(
              onTap: () => controller.zoomBy(1 / controller.zoom),
              label: 'Reset zoom to 100%',
              builder: (s) => Container(
                width: 56,
                height: CvSizes.hit,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.hover ? CvColors.surfaceHover : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(CvRadii.md),
                ),
                child: Text('${(controller.zoom * 100).round()}%',
                    style: CvTypography.caption.copyWith(
                        fontFamily: CvTypography.mono,
                        color: s.hover
                            ? CvColors.textPrimary
                            : CvColors.textSecondary)),
              ),
            ),
          ),
        ),
        CvToolButton(
            icon: Lucide.zoomIn,
            label: 'Zoom in',
            shortcut: '+',
            tooltipSide: AxisDirection.up,
            onPressed: () => controller.zoomBy(1.25)),
        CvToolButton(
            icon: Lucide.scan,
            label: 'Fit map',
            shortcut: '0',
            tooltipSide: AxisDirection.up,
            onPressed: controller.fit),
      ]);
}

/// Who is at the table, and the way out, at the top right.
class PresenceBar extends StatelessWidget {
  const PresenceBar({super.key, required this.onLeave, this.session});

  final VoidCallback onLeave;
  final Session? session;

  @override
  Widget build(BuildContext context) => CvPanel(
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          if (session case final session?) ...[
            StreamBuilder(
              stream: session.peers,
              initialData: session.currentPeers,
              builder: (context, snapshot) => CvAvatarStack(avatars: [
                // The GM first, as the design lists them.
                for (final p in snapshot.requireData.where((p) => p.gm))
                  avatarFor(p),
                for (final p in snapshot.requireData.where((p) => !p.gm))
                  avatarFor(p),
              ]),
            ),
            Container(width: 1, height: 24, color: CvColors.borderSubtle),
          ],
          CvToolButton(
            icon: Lucide.logOut,
            label: 'Leave',
            inline: true,
            danger: true,
            onPressed: onLeave,
          ),
        ]),
      );
}

/// "Saved" once the GM's scene is stored, "Saving…" until then.
class SaveStatus extends StatelessWidget {
  const SaveStatus({super.key, required this.saved});

  final ValueListenable<bool> saved;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: saved,
        builder: (context, saved, _) => CvPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: CvSizes.hit - 2,
            child: Semantics(
              liveRegion: true,
              child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                saved
                    ? const CvIcon(Lucide.circleCheck,
                        size: CvSizes.iconSm, color: CvColors.moss500)
                    : const CvSpinner(size: 14),
                Text(saved ? 'Saved' : 'Saving…',
                    style: CvTypography.bodySm
                        .copyWith(color: CvColors.textSecondary)),
              ]),
            ),
          ),
        ),
      );
}

/// A player's own tokens, to find them on the map.
class YourTokens extends StatelessWidget {
  const YourTokens({
    super.key,
    required this.store,
    required this.self,
    required this.controller,
  });

  final SceneStore store;
  final PlayerId self;
  final TableController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: store.changes,
        initialData: store.scene,
        builder: (context, snapshot) {
          final scene = snapshot.requireData;
          final mine = [
            for (final t in scene.tokens.values)
              if (t.owner == self) t,
          ];
          if (mine.isEmpty) return const SizedBox.shrink();
          return CvPanel(
            width: 220,
            padding: const EdgeInsets.all(CvSpacing.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(CvSpacing.s3),
                  child: CvOverline('Your tokens'),
                ),
                // ponytail: no "Under fog" state yet; it needs a lookup in
                // the fog mask.
                for (final t in mine)
                  CvPressable(
                    onTap: () => controller.centerOn(t.position),
                    label: 'Find token at ${cellName(t.position, scene.settings.grid)}',
                    radius: CvRadii.sm,
                    pressScale: 1,
                    builder: (s) => Container(
                      height: CvSizes.hit,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: s.hover
                            ? CvColors.surfaceHover
                            : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(CvRadii.sm),
                      ),
                      child: Row(spacing: 10, children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: playerColor(self),
                            boxShadow: const [
                              BoxShadow(color: CvColors.teal500, spreadRadius: 2)
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                              'Token at ${cellName(t.position, scene.settings.grid)}'),
                        ),
                        const CvIcon(Lucide.locateFixed,
                            size: CvSizes.iconSm, color: CvColors.textSecondary),
                      ]),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

/// The selected token's card, floating beside it: owner, hidden, remove.
/// Fill the table's stack with it; it follows the token as the view moves.
class TokenCardLayer extends StatelessWidget {
  const TokenCardLayer({
    super.key,
    required this.store,
    required this.session,
    required this.controller,
    required this.send,
    required this.onRemove,
  });

  final SceneStore store;
  final Session session;
  final TableController controller;
  final Outcome Function(Command) send;
  final void Function(TokenId) onRemove;

  static const width = 280.0;

  /// For keeping the card on screen; near enough to its real height.
  static const height = 248.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(
            [controller, controller.selected, controller.view, controller.drag]),
        builder: (context, _) => StreamBuilder(
          stream: store.changes,
          initialData: store.scene,
          builder: (context, snapshot) {
            final scene = snapshot.requireData;
            final token = scene.tokens[controller.selected.value];
            if (token == null || controller.tool != Tool.move) {
              return const SizedBox.shrink();
            }
            return LayoutBuilder(builder: (context, constraints) {
              final view = constraints.biggest;
              const pad = CvSizes.insetScreen;
              final drag = controller.drag.value;
              final at = controller.toScreen(drag?.id == token.id
                  ? (x: drag!.position.dx, y: drag.position.dy)
                  : token.position);
              final r = token.size / 2 * controller.zoom + 6;
              var left = at.dx + r + 22;
              final onRight = left + width <= view.width - pad;
              if (!onRight) left = at.dx - r - 22 - width;
              final top = math.max(pad + CvSizes.hit + 12,
                  math.min(view.height - pad - 60 - height, at.dy - 36));
              final arrow = (at.dy - top).clamp(22.0, height - 22);
              return Stack(children: [
                Positioned(
                  left: left,
                  top: top,
                  child: _TokenCard(
                    key: ValueKey(token.id),
                    token: token,
                    grid: scene.settings.grid,
                    session: session,
                    send: send,
                    onRemove: () => onRemove(token.id),
                    onClose: () => controller.selected.value = null,
                    arrowOnLeft: onRight,
                    arrowTop: arrow,
                    menuAbove: top > view.height / 2,
                  ),
                ),
              ]);
            });
          },
        ),
      );
}

class _TokenCard extends StatelessWidget {
  const _TokenCard({
    super.key,
    required this.token,
    required this.grid,
    required this.session,
    required this.send,
    required this.onRemove,
    required this.onClose,
    required this.arrowOnLeft,
    required this.arrowTop,
    required this.menuAbove,
  });

  final Token token;
  final Grid grid;
  final Session session;
  final Outcome Function(Command) send;
  final VoidCallback onRemove;
  final VoidCallback onClose;
  final bool arrowOnLeft;
  final double arrowTop;
  final bool menuAbove;

  @override
  Widget build(BuildContext context) {
    const border = BorderSide(color: CvColors.borderSubtle);
    final card = Container(
      width: TokenCardLayer.width,
      decoration: BoxDecoration(
        color: CvColors.surfacePanelSolid,
        borderRadius: BorderRadius.circular(CvRadii.lg),
        border: Border.all(color: CvColors.borderSubtle),
        boxShadow: CvElevation.shadow2,
      ),
      child: DefaultTextStyle(
        style: CvTypography.body,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: const BoxDecoration(border: Border(bottom: border)),
              child: Row(spacing: 10, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Token',
                          style: CvTypography.weight(CvTypography.body, 600)),
                      Text(cellName(token.position, grid),
                          style: CvTypography.caption.copyWith(
                              fontFamily: CvTypography.mono,
                              fontWeight: FontWeight.w500,
                              color: CvColors.textSecondary)),
                    ],
                  ),
                ),
                CvToolButton(
                  icon: Lucide.x,
                  label: 'Close',
                  shortcut: 'Esc',
                  tooltipSide: AxisDirection.up,
                  onPressed: onClose,
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  StreamBuilder(
                    stream: session.peers,
                    initialData: session.currentPeers,
                    builder: (context, snapshot) {
                      final players = [
                        for (final p in snapshot.requireData)
                          if (!p.gm) PlayerId(p.player),
                      ];
                      final owners = {...players, ?token.owner};
                      return CvDropdown<PlayerId?>(
                        label: 'Owner',
                        value: token.owner,
                        above: menuAbove,
                        onChanged: (owner) => send(AssignOwner(token.id, owner)),
                        entries: [
                          const CvMenuItem(null, 'No owner',
                              leading: CvIcon(Lucide.circleDashed,
                                  size: CvSizes.iconSm,
                                  color: CvColors.textSecondary)),
                          if (owners.isNotEmpty) ...[
                            const CvMenuDivider(),
                            const CvMenuHeading('Connected players'),
                          ],
                          for (final p in owners)
                            CvMenuItem(p, 'Player ${shortId(p)}',
                                leading: avatarFor(
                                    (player: p.value, gm: false, cursor: null),
                                    size: 24)),
                        ],
                      );
                    },
                  ),
                  CvSwitch(
                    value: token.hidden,
                    onChanged: (hidden) =>
                        send(SetTokenHidden(token.id, hidden)),
                    label: const Row(spacing: 8, children: [
                      CvIcon(Lucide.eyeOff,
                          size: CvSizes.iconSm, color: CvColors.textSecondary),
                      Text('Hidden from players'),
                    ]),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(border: Border(top: border)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CvButton(
                    label: 'Remove token',
                    icon: Lucide.trash2,
                    variant: CvButtonVariant.dangerGhost,
                    small: true,
                    onPressed: onRemove,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: CvKbd('Del'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // The arrow: a rotated square showing two borders, pointing at the token.
    final arrow = Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: CvColors.surfacePanelSolid,
          border: arrowOnLeft
              ? const Border(left: border, bottom: border)
              : const Border(right: border, top: border),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Token at ${cellName(token.position, grid)}',
      child: CvPopIn(
        child: Stack(clipBehavior: Clip.none, children: [
          card,
          Positioned(
            left: arrowOnLeft ? -6 : null,
            right: arrowOnLeft ? null : -6,
            top: arrowTop - 6,
            child: arrow,
          ),
        ]),
      ),
    );
  }
}

/// The table's single-key shortcuts. GM: V B R tools, T add token, M map, G grid,
/// E export, I import, X cover/reveal, S snap, Del remove. Everyone:
/// + − 0 zoom, Esc deselect.
class TableShortcuts extends StatelessWidget {
  const TableShortcuts({
    super.key,
    required this.controller,
    required this.child,
    this.gm = false,
    this.onAddToken,
    this.onSetMap,
    this.onExport,
    this.onImport,
    this.onRemove,
  });

  final TableController controller;
  final Widget child;
  final bool gm;
  final VoidCallback? onAddToken;
  final VoidCallback? onSetMap;
  final VoidCallback? onExport;
  final VoidCallback? onImport;
  final void Function(TokenId)? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    void remove() {
      if (c.selected.value case final id?) onRemove?.call(id);
    }

    return CallbackShortcuts(
      bindings: {
        const CharacterActivator('+'): () => c.zoomBy(1.25),
        const CharacterActivator('='): () => c.zoomBy(1.25),
        const CharacterActivator('-'): () => c.zoomBy(1 / 1.25),
        const CharacterActivator('0'): c.fit,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          c.selected.value = null;
          c.tool = Tool.move;
        },
        if (gm) ...{
          const CharacterActivator('v'): () => c.tool = Tool.move,
          const CharacterActivator('b'): () => c.tool = Tool.fogBrush,
          const CharacterActivator('r'): () => c.tool = Tool.fogRect,
          const CharacterActivator('x'): () => c.fogMode =
              c.fogMode == FogMode.cover ? FogMode.reveal : FogMode.cover,
          const CharacterActivator('s'): () => c.snap = !c.snap,
          const CharacterActivator('t'): () => onAddToken?.call(),
          const CharacterActivator('m'): () => onSetMap?.call(),
          const CharacterActivator('g'): () => c.gridOptions = !c.gridOptions,
          const CharacterActivator('e'): () => onExport?.call(),
          const CharacterActivator('i'): () => onImport?.call(),
          const SingleActivator(LogicalKeyboardKey.delete): remove,
          const SingleActivator(LogicalKeyboardKey.backspace): remove,
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// The table's empty ground: sunken slate with a faint 56 px grid.
class GroundGrid extends StatelessWidget {
  const GroundGrid({super.key});

  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: CvColors.bgSunken,
        child: CustomPaint(painter: _GroundPainter(), size: Size.infinite),
      );
}

class _GroundPainter extends CustomPainter {
  const _GroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0AE8E6E1);
    for (var x = 0.0; x < size.width; x += CvSizes.token) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += CvSizes.token) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(_GroundPainter old) => false;
}
