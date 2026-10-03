import 'dart:async';
import 'dart:math' as math;

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueListenable, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:tactical_engine/tactical_engine.dart'
    show SystemPack, TagDef, TrackerDef, builtInPacks;

import '../members.dart';
import '../theme.dart';
import '../ui/cv.dart';
import 'pack_tokens.dart';
import 'rules.dart';
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
  final name = playerName(id);
  return CvAvatar(
    initials: p.gm
        ? 'GM'
        : (members.value[id] == null ? shortId(id) : name)
            .substring(0, math.min(2, name.length))
            .toUpperCase(),
    color: playerColor(id),
    gm: p.gm,
    size: size,
    label: p.gm ? 'GM' : name,
  );
}

/// Shows [session]'s pings on [controller]'s map, in the pinger's colour.
StreamSubscription<TableEvent> showPings(
        Session session, TableController controller) =>
    session.events.listen((e) {
      if (e case PingEvent(:final point, :final by, :final gm)) {
        controller.ping(point, gm ? CvColors.amber500 : playerColor(by));
      }
    });

/// Shares [controller]'s ruler through [session]'s presence while it's
/// dragged, and shows everyone else's. Call the result to stop.
VoidCallback shareRulers(
    Session session, TableController controller) {
  // Each update is a presence message (H6): at most one per [every], and
  // the last position always goes out.
  const every = Duration(milliseconds: 100);
  Timer? pending;
  var last = DateTime.fromMillisecondsSinceEpoch(0);
  void send() {
    pending = null;
    last = DateTime.now();
    session.setRuler(controller.ruler.value).ignore();
  }

  void changed() {
    final wait = every - DateTime.now().difference(last);
    if (controller.ruler.value == null || wait <= Duration.zero) {
      pending?.cancel();
      send();
    } else {
      pending ??= Timer(wait, send);
    }
  }

  controller.ruler.addListener(changed);
  final others = session.peers.listen((peers) {
    controller.otherRulers.value = [
      for (final p in peers)
        if (p.ruler case final r? when p.player != session.self.value)
          (r, p.gm ? CvColors.amber500 : playerColor(PlayerId(p.player))),
    ];
  });
  return () {
    others.cancel();
    pending?.cancel();
    controller.ruler.removeListener(changed);
  };
}

/// The undo key's modifier, as the GM's platform writes it.
String get _mod => defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl ';

/// The GM's tools, a rail on the left edge.
class GmRail extends StatelessWidget {
  const GmRail({
    super.key,
    required this.controller,
    this.onAddToken,
    this.onSetMap,
    this.onUndo,
    this.onRedo,
    this.onScenes,
    this.scenesOpen = false,
    this.onMembers,
    this.membersOpen = false,
    this.mapsOpen = false,
    this.tokensOpen = false,
  });

  final TableController controller;
  final VoidCallback? onScenes;
  final bool scenesOpen;
  final VoidCallback? onMembers;
  final bool membersOpen;
  final bool mapsOpen;
  final bool tokensOpen;
  final VoidCallback? onAddToken;
  final VoidCallback? onSetMap;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

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
            if (onScenes != null) ...[
              CvToolButton(
                  icon: Lucide.layers,
                  label: 'Scenes',
                  active: scenesOpen,
                  onPressed: onScenes),
              if (onMembers != null)
                CvToolButton(
                    icon: Lucide.userRound,
                    label: 'Players',
                    active: membersOpen,
                    onPressed: onMembers),
              const CvToolbarSeparator(),
            ],
            CvToolButton(
                icon: Lucide.undo2,
                label: 'Undo',
                shortcut: '${_mod}Z',
                onPressed: onUndo),
            CvToolButton(
                icon: Lucide.redo2,
                label: 'Redo',
                shortcut: '$_mod⇧Z',
                onPressed: onRedo),
            const CvToolbarSeparator(),
            tool(Tool.move, Lucide.mousePointer2, 'Move', 'V'),
            tool(Tool.ruler, Lucide.ruler, 'Ruler', 'L'),
            tool(Tool.ping, Lucide.radio, 'Ping', 'P'),
            const CvToolbarSeparator(),
            // One button for both fog tools; the fog panel switches shape.
            CvToolButton(
              icon: Lucide.paintbrush,
              label: 'Fog',
              shortcut: 'B',
              active: controller.tool == Tool.fogBrush ||
                  controller.tool == Tool.fogRect ||
                  controller.tool == Tool.fogErase,
              onPressed: () => controller.tool = Tool.fogBrush,
            ),
            tool(Tool.region, Lucide.scan, 'Regions', 'A'),
            const CvToolbarSeparator(),
            CvToolButton(
                icon: Lucide.circlePlus,
                label: 'Add token',
                shortcut: 'T',
                active: tokensOpen,
                onPressed: onAddToken),
            CvToolButton(
                icon: Lucide.imageUp,
                label: 'Change map',
                shortcut: 'M',
                active: mapsOpen,
                onPressed: onSetMap),
            CvToolButton(
                icon: Lucide.grid3x3,
                label: 'Grid',
                shortcut: 'G',
                active: controller.gridOptions,
                onPressed: controller.toggleGridOptions),
          ]);
        },
      );
}

/// A player's tools, a rail on the left edge: move, ruler, ping.
class PlayerRail extends StatelessWidget {
  const PlayerRail({super.key, required this.controller});

  final TableController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => CvToolbar(children: [
          for (final (t, icon, label, key) in const [
            (Tool.move, Lucide.mousePointer2, 'Move', 'V'),
            (Tool.ruler, Lucide.ruler, 'Ruler', 'L'),
            (Tool.ping, Lucide.radio, 'Ping', 'P'),
          ])
            CvToolButton(
              icon: icon,
              label: label,
              shortcut: key,
              active: controller.tool == t,
              onPressed: () => controller.tool = t,
            ),
        ]),
      );
}

/// While the region tool is out: how to draw one, or the selected region's
/// tags, whether players see it, and deleting it.
class RegionOptions extends StatelessWidget {
  const RegionOptions(
      {super.key,
      required this.controller,
      required this.store,
      required this.send});

  final TableController controller;
  final SceneStore store;
  final Outcome Function(Command) send;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.selectedRegion]),
        builder: (context, _) => controller.tool != Tool.region
            ? const SizedBox.shrink()
            : StreamBuilder(
                stream: store.changes,
                initialData: store.scene,
                builder: (context, snapshot) {
                  final scene = snapshot.requireData;
                  final region = scene.regions[controller.selectedRegion.value];
                  final pack = packOf(scene);
                  return CvPopIn(
                    child: CvPanel(
                      width: 260,
                      padding: const EdgeInsets.all(CvSpacing.s5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 10,
                        children: [
                          const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [CvOverline('Region'), CvKbd('A')]),
                          if (region == null)
                            Text(
                                'Drag over the map to mark a region, cell by '
                                'cell (Alt for exact). Click one to give it '
                                'tags such as cover or difficult terrain.',
                                style: CvTypography.caption
                                    .copyWith(color: CvColors.textSecondary))
                          else ...[
                            _TagEditor(
                              key: ValueKey(region.id),
                              title: 'Tags',
                              tags: region.tags,
                              pack: pack,
                              offered: pack.regionTags,
                              placeholder: 'Add: Heavy Cover, Darkness 2…',
                              onSet: (name, value) => send(UpdateRegion(
                                  region.copyWith(
                                      tags: {...region.tags, name: value}))),
                              onRemove: (name) => send(UpdateRegion(
                                  region.copyWith(
                                      tags: {...region.tags}..remove(name)))),
                            ),
                            CvSwitch(
                              value: region.hidden,
                              onChanged: (hidden) => send(
                                  UpdateRegion(region.copyWith(hidden: hidden))),
                              label: const Text('Hidden from players'),
                            ),
                            CvButton(
                              label: 'Delete region',
                              icon: Lucide.trash2,
                              variant: CvButtonVariant.dangerGhost,
                              small: true,
                              block: true,
                              onPressed: () {
                                send(RemoveRegion(region.id));
                                controller.selectedRegion.value = null;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      );
}

/// Cover or reveal, and the brush size, while a fog tool is out.
class FogOptions extends StatelessWidget {
  const FogOptions(
      {super.key, required this.controller, required this.grid, this.onFill});

  final TableController controller;
  final Grid grid;

  /// Covers or reveals the whole map at once.
  final void Function(FogMode mode)? onFill;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final tool = controller.tool;
          if (tool != Tool.fogBrush &&
              tool != Tool.fogRect &&
              tool != Tool.fogErase) {
            return const SizedBox.shrink();
          }
          final cells = controller.brushCells(grid.cellSize);
          return CvPopIn(
            child: CvPanel(
              width: 248,
              padding: const EdgeInsets.all(CvSpacing.s5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [CvOverline('Fog'), CvKbd('X')]),
                  CvSegmentedControl<Tool>(
                    value: tool,
                    onChanged: (t) => controller.tool = t,
                    segments: const [
                      (
                        value: Tool.fogBrush,
                        label: 'Brush',
                        icon: Lucide.paintbrush,
                        checked: null
                      ),
                      (
                        value: Tool.fogRect,
                        label: 'Box',
                        icon: Lucide.squareDashed,
                        checked: null
                      ),
                      (
                        value: Tool.fogErase,
                        label: 'Erase',
                        icon: Lucide.eraser,
                        checked: CvColors.ember400
                      ),
                    ],
                  ),
                  if (tool != Tool.fogErase)
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
                          controller.setBrushCells(v, grid.cellSize),
                    ),
                  Text(
                      switch (tool) {
                        Tool.fogBrush => 'Paint over the map. Hold Shift to '
                            'do the opposite; [ and ] change the size.',
                        Tool.fogRect => 'Drag over whole cells (Alt for '
                            'exact). Hold Shift to do the opposite.',
                        _ => 'Click fog you drew to take it away, the '
                            'latest first. Undo puts it back.',
                      },
                      style: CvTypography.caption
                          .copyWith(color: CvColors.textSecondary)),
                  if (onFill case final fill?)
                    Row(spacing: 6, children: [
                      Expanded(
                        child: CvButton(
                          label: 'Hide all',
                          icon: Lucide.eyeOff,
                          small: true,
                          block: true,
                          onPressed: () => fill(FogMode.cover),
                        ),
                      ),
                      Expanded(
                        child: CvButton(
                          label: 'Reveal all',
                          icon: Lucide.eye,
                          small: true,
                          block: true,
                          onPressed: () => fill(FogMode.reveal),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          );
        },
      );
}

/// Keys typed in [child] (a text field) stay text: the table's single-key
/// shortcuts above it don't see them.
class TextKeysOnly extends StatelessWidget {
  const TextKeysOnly({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, _) => KeyEventResult.skipRemainingHandlers,
        child: child,
      );
}

/// The grid's cell size, while the GM's grid panel is open. Applies each
/// valid value as it's typed, so the GM sees the grid move over the map.
/// Fit draws one cell over the map instead ([Tool.gridFit]).
class GridOptions extends StatefulWidget {
  const GridOptions(
      {super.key,
      required this.controller,
      required this.grid,
      required this.visible,
      required this.onCellSize,
      required this.onVisible,
      this.pack = SceneSettings.defaultPack,
      this.packs = const [],
      this.onPack,
      this.onInstallPack});

  final TableController controller;
  final Grid grid;
  final bool visible;
  final ValueChanged<double> onCellSize;
  final ValueChanged<bool> onVisible;

  /// The scene's system pack, picked here among [packs] (beyond the
  /// built-in ones) when [onPack] is given.
  final String pack;
  final List<SystemPack> packs;
  final ValueChanged<String>? onPack;

  /// Installs a system from a file.
  final VoidCallback? onInstallPack;

  /// The menu value that installs instead of picking: not a valid pack id.
  static const _install = '+install';

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
    final valid = size != null && Grid(cellSize: size).valid;
    setState(() => _error = valid
        ? null
        : 'From ${Grid.minCellSize.round()} to ${Grid.maxCellSize.round()} px.');
    if (valid && size != widget.grid.cellSize) widget.onCellSize(size);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) => widget.controller.gridOptions
            ? CvPopIn(child: _panel())
            : const SizedBox.shrink(),
      );

  Widget _panel() {
    final c = widget.controller;
    final fitting = c.tool == Tool.gridFit;
    return CvPanel(
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
              TextKeysOnly(
                child: CvTextInput(
                  controller: _text,
                  label: 'Cell size (px)',
                  error: _error,
                  onChanged: _changed,
                ),
              ),
              if (_error == null)
                Text(
                    fitting
                        ? 'Drag a box over one square of the map. Zoom in first to be exact.'
                        : 'Match one square of the map image, or fit it on the map.',
                    style: CvTypography.caption
                        .copyWith(color: CvColors.textSecondary)),
              CvSwitch(
                label: const Text('Show grid lines'),
                value: widget.visible,
                onChanged: widget.onVisible,
              ),
              if (widget.onPack case final onPack?)
                CvDropdown<String>(
                  label: 'System',
                  entries: [
                    for (final MapEntry(key: id, value: pack) in builtInPacks.entries)
                      CvMenuItem(id, pack.name),
                    if (widget.packs.isNotEmpty) ...[
                      const CvMenuDivider<String>(),
                      for (final pack in widget.packs) CvMenuItem(pack.id, pack.name),
                    ],
                    if (widget.onInstallPack != null) ...[
                      const CvMenuDivider<String>(),
                      const CvMenuItem(GridOptions._install, 'Install from file…'),
                    ],
                  ],
                  value: widget.pack,
                  onChanged: (id) => id == GridOptions._install
                      ? widget.onInstallPack?.call()
                      : onPack(id),
                ),
              CvButton(
                label: fitting ? 'Cancel fit' : 'Fit on map',
                icon: fitting ? Lucide.x : Lucide.squareDashed,
                small: true,
                block: true,
                variant: fitting ? CvButtonVariant.ghost : CvButtonVariant.secondary,
                onPressed: () => c.tool = fitting ? Tool.move : Tool.gridFit,
              ),
            ],
          ),
        );
  }
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

/// The selected token's card, floating beside it: conditions and, for the
/// GM, owner, hidden, remove. Fill the table's stack with it; it follows the
/// token as the view moves.
class TokenCardLayer extends StatelessWidget {
  const TokenCardLayer({
    super.key,
    required this.store,
    required this.session,
    required this.controller,
    required this.send,
    this.gm = true,
    this.onRemove,
    this.onDuplicate,
    this.onSetImage,
    this.fullPack,
  });

  final SceneStore store;
  final Session session;
  final TableController controller;
  final Outcome Function(Command) send;

  /// The scene's pack with its tokens' cards, which only the GM has
  /// installed; the scene's own copy otherwise.
  final SystemPack Function(Scene scene)? fullPack;

  /// A player's card shows only what they may change: conditions.
  final bool gm;
  final void Function(TokenId)? onRemove;
  final void Function(TokenId)? onDuplicate;

  /// Picks and uploads a new image for the token; null while one uploads.
  final void Function(TokenId)? onSetImage;

  static const width = 280.0;

  /// For keeping the card on screen; near enough to its real height.
  static const height = 520.0;

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
                    maxHeight: view.height - pad - top,
                    token: token,
                    scene: scene,
                    pack: fullPack?.call(scene) ?? packOf(scene),
                    snap: controller.snap,
                    session: session,
                    send: send,
                    gm: gm,
                    onRemove: onRemove == null
                        ? null
                        : () => onRemove!(token.id),
                    onDuplicate: onDuplicate == null
                        ? null
                        : () => onDuplicate!(token.id),
                    onSetImage: onSetImage == null
                        ? null
                        : () => onSetImage!(token.id),
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
    required this.maxHeight,
    required this.pack,
    required this.token,
    required this.scene,
    required this.snap,
    required this.session,
    required this.send,
    required this.gm,
    required this.onRemove,
    required this.onDuplicate,
    required this.onSetImage,
    required this.onClose,
    required this.arrowOnLeft,
    required this.arrowTop,
    required this.menuAbove,
  });

  final Token token;

  /// The room left below the card's top: its middle scrolls past it.
  final double maxHeight;

  /// The rules: trackers, conditions, and the token's card if it came from
  /// one of the pack's tokens.
  final SystemPack pack;

  /// For the grid, and the rules in force where the token stands.
  final Scene scene;
  Grid get grid => scene.settings.grid;

  /// Resizing snaps the token too, like a drop.
  final bool snap;
  final Session session;
  final Outcome Function(Command) send;
  final bool gm;
  final VoidCallback? onRemove;
  final VoidCallback? onDuplicate;
  final VoidCallback? onSetImage;
  final VoidCallback onClose;
  final bool arrowOnLeft;
  final double arrowTop;
  final bool menuAbove;

  @override
  Widget build(BuildContext context) {
    const border = BorderSide(color: CvColors.borderSubtle);
    final card = Container(
      width: TokenCardLayer.width,
      constraints: BoxConstraints(maxHeight: maxHeight),
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
                      Text(token.name.isEmpty ? 'Token' : token.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CvTypography.weight(CvTypography.body, 600)),
                      Text(
                          [
                            cellName(token.position, grid),
                            for (final t in engineFor(scene).tagsAt(token.position))
                              t.value == null ? t.name : '${t.name} ${t.value}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
            Flexible(
              child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  if (gm) ...[
                    _NameField(
                      name: token.name,
                      onChanged: (name) =>
                          send(UpdateToken(token.copyWith(name: name))),
                    ),
                    Text('Size',
                        style: CvTypography.label
                            .copyWith(color: CvColors.textSecondary)),
                    CvSegmentedControl<int>(
                      value: (token.size / grid.cellSize).round(),
                      onChanged: (cells) {
                        final size = cells * grid.cellSize;
                        send(UpdateToken(token.copyWith(
                            size: size,
                            position:
                                snap ? grid.snap(token.position, size) : null)));
                      },
                      segments: [
                        for (var n = 1; n <= 4; n++)
                          (value: n, label: '$n×$n', icon: null, checked: null),
                      ],
                    ),
                    StreamBuilder(
                      stream: session.peers,
                      initialData: session.currentPeers,
                      builder: (context, snapshot) => ValueListenableBuilder(
                        valueListenable: members,
                        builder: (context, all, _) {
                          // Every member, connected or not, so tokens can be
                          // handed out before a session; and anyone connected
                          // who isn't a member yet.
                          final owners = {
                            ...all.keys,
                            for (final p in snapshot.requireData)
                              if (!p.gm) PlayerId(p.player),
                            ?token.owner,
                          };
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
                                const CvMenuHeading('Players'),
                              ],
                              for (final p in owners)
                                CvMenuItem(p, playerName(p),
                                    leading: avatarFor(
                                        (player: p.value, gm: false, cursor: null, ruler: null),
                                        size: 24)),
                            ],
                          );
                        },
                      ),
                    ),
                    CvButton(
                      label: 'Change image',
                      icon: Lucide.imageUp,
                      small: true,
                      block: true,
                      onPressed: onSetImage,
                    ),
                    CvSwitch(
                      value: token.hidden,
                      onChanged: (hidden) =>
                          send(SetTokenHidden(token.id, hidden)),
                      label: const Row(spacing: 8, children: [
                        CvIcon(Lucide.eyeOff,
                            size: CvSizes.iconSm, color: CvColors.textSecondary),
                        Flexible(
                          child: Text('Hidden from players',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ),
                  ],
                  if (trackersFor(token, pack) case final trackers
                      when trackers.isNotEmpty)
                    _Trackers(
                      key: ValueKey(token.id),
                      token: token,
                      trackers: trackers,
                      send: send,
                    ),
                  _TagEditor(
                    title: 'Conditions',
                    tags: token.conditions,
                    pack: pack,
                    offered: pack.conditions,
                    onSet: (name, value) =>
                        send(SetCondition(token.id, name, value)),
                    onRemove: (name) => send(RemoveCondition(token.id, name)),
                  ),
                  if (gm)
                    if (pack.tokens[token.template]?.card case final card?
                        when card.isNotEmpty)
                      TokenCardSections(sections: card),
                ],
              ),
              ),
            ),
            if (gm)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(border: Border(top: border)),
                // Wraps rather than overflows with large text.
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    CvButton(
                      label: 'Duplicate',
                      icon: Lucide.copy,
                      variant: CvButtonVariant.ghost,
                      small: true,
                      onPressed: onDuplicate,
                    ),
                    CvButton(
                      label: 'Remove',
                      icon: Lucide.trash2,
                      variant: CvButtonVariant.dangerGhost,
                      small: true,
                      onPressed: onRemove,
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

/// The table's single-key shortcuts. Everyone: V L P tools (move, ruler,
/// ping). GM: B R tools, T add token, D duplicate, M map, G grid,
/// E export, I import, X cover/reveal, S snap, Del remove, Cmd/Ctrl+Z undo,
/// Cmd/Ctrl+Shift+Z redo. Everyone:
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
    this.onDuplicate,
    this.onUndo,
    this.onRedo,
    this.grid,
  });

  final TableController controller;
  final Widget child;
  final bool gm;

  /// The scene's grid, which the brush size keys count in.
  final Grid Function()? grid;
  final VoidCallback? onAddToken;
  final VoidCallback? onSetMap;
  final VoidCallback? onExport;
  final VoidCallback? onImport;
  final void Function(TokenId)? onRemove;
  final void Function(TokenId)? onDuplicate;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    double cellSize() => grid?.call().cellSize ?? 128;
    void undo() => onUndo?.call();
    void redo() => onRedo?.call();
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
        const CharacterActivator('v'): () => c.tool = Tool.move,
        const CharacterActivator('l'): () => c.tool = Tool.ruler,
        const CharacterActivator('p'): () => c.tool = Tool.ping,
        if (gm) ...{
          const CharacterActivator('b'): () => c.tool = Tool.fogBrush,
          const CharacterActivator('r'): () => c.tool = Tool.fogRect,
          const CharacterActivator('['): () => c.setBrushCells(
              c.brushCells(cellSize()) - 1, cellSize()),
          const CharacterActivator(']'): () => c.setBrushCells(
              c.brushCells(cellSize()) + 1, cellSize()),
          const CharacterActivator('a'): () => c.tool = Tool.region,
          const CharacterActivator('x'): () => c.fogMode =
              c.fogMode == FogMode.cover ? FogMode.reveal : FogMode.cover,
          const CharacterActivator('s'): () => c.snap = !c.snap,
          const CharacterActivator('t'): () => onAddToken?.call(),
          const CharacterActivator('d'): () {
            if (c.selected.value case final id?) onDuplicate?.call(id);
          },
          const CharacterActivator('m'): () => onSetMap?.call(),
          const CharacterActivator('g'): c.toggleGridOptions,
          const CharacterActivator('e'): () => onExport?.call(),
          const CharacterActivator('i'): () => onImport?.call(),
          const SingleActivator(LogicalKeyboardKey.delete): remove,
          const SingleActivator(LogicalKeyboardKey.backspace): remove,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
              redo,
          const SingleActivator(LogicalKeyboardKey.keyZ,
              control: true, shift: true): redo,
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

/// The token's name, applied as it's typed.
class _NameField extends StatefulWidget {
  const _NameField({required this.name, required this.onChanged});

  final String name;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _text = TextEditingController(text: widget.name);

  @override
  void didUpdateWidget(_NameField old) {
    super.didUpdateWidget(old);
    if (widget.name != _text.text) _text.text = widget.name;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextKeysOnly(
        child: CvTextInput(
          controller: _text,
          label: 'Name',
          placeholder: 'Goblin 1',
          maxLength: 40,
          onChanged: widget.onChanged,
        ),
      );
}

/// The pack's trackers a token has: − and + step one, or type a value,
/// kept within each tracker's bounds; an empty field takes it off. A menu
/// adds the others, so a pack with many trackers keeps the card short.
class _Trackers extends StatefulWidget {
  const _Trackers(
      {super.key, required this.token, required this.trackers, required this.send});

  final Token token;
  final List<TrackerDef> trackers;
  final Outcome Function(Command) send;

  @override
  State<_Trackers> createState() => _TrackersState();
}

class _TrackersState extends State<_Trackers> {
  final _fields = <String, TextEditingController>{};

  TextEditingController _field(String name) => _fields[name] ??=
      TextEditingController(text: '${widget.token.trackers[name] ?? ''}');

  @override
  void didUpdateWidget(_Trackers old) {
    super.didUpdateWidget(old);
    // Changed elsewhere (another client, the buttons): show it.
    for (final MapEntry(key: name, value: field) in _fields.entries) {
      final text = '${widget.token.trackers[name] ?? ''}';
      if (field.text != text && int.tryParse(field.text) != widget.token.trackers[name]) {
        field.text = text;
      }
    }
  }

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _set(TrackerDef def, int? value) {
    final clamped = value == null ? null : def.clamp(value);
    _field(def.name).text = '${clamped ?? ''}';
    widget.send(SetTracker(widget.token.id, def.name, clamped));
  }

  @override
  Widget build(BuildContext context) {
    final trackers = widget.token.trackers;
    final shown = [for (final d in widget.trackers) if (trackers.containsKey(d.name)) d];
    final offered = [for (final d in widget.trackers) if (!trackers.containsKey(d.name)) d];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text('Trackers',
            style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
        for (final def in shown)
          CvTooltip(
            message: def.text,
            side: AxisDirection.up,
            child: Row(spacing: 4, children: [
              Expanded(
                child: Text(def.max == null ? def.name : '${def.name} / ${def.max}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CvTypography.bodySm),
              ),
              CvToolButton(
                icon: Lucide.minus,
                label: '${def.name} −1',
                tooltipSide: AxisDirection.up,
                onPressed: () => _set(def, (trackers[def.name] ?? def.min) - 1),
              ),
              SizedBox(
                width: 72,
                child: TextKeysOnly(
                  child: CvTextInput(
                    controller: _field(def.name),
                    placeholder: '–',
                    maxLength: 6,
                    onSubmitted: (v) => _set(def, int.tryParse(v.trim())),
                  ),
                ),
              ),
              CvToolButton(
                icon: Lucide.plus,
                label: '${def.name} +1',
                tooltipSide: AxisDirection.up,
                onPressed: () => _set(def, (trackers[def.name] ?? def.min) + 1),
              ),
            ]),
          ),
        if (offered.isNotEmpty)
          CvDropdown<String?>(
            entries: [for (final d in offered) CvMenuItem(d.name, d.name)],
            value: null,
            placeholder: 'Add a tracker…',
            onChanged: (name) {
              final def = offered.where((d) => d.name == name).firstOrNull;
              if (def != null) _set(def, def.min);
            },
          ),
      ],
    );
  }
}

/// Tags as chips, each removable and explained by the pack on hover, a
/// menu of the pack's [offered] tags, and a line to type one: "Prone", or
/// "Darkness 2" for one with a value. Token conditions and region tags.
class _TagEditor extends StatefulWidget {
  const _TagEditor({
    super.key,
    required this.title,
    required this.tags,
    required this.pack,
    required this.offered,
    required this.onSet,
    required this.onRemove,
    this.placeholder = 'Add: Prone, Darkness 2…',
  });

  final String title;
  final Map<String, int?> tags;
  final SystemPack pack;
  final Iterable<TagDef> offered;
  final Outcome Function(String name, int? value) onSet;
  final void Function(String name) onRemove;
  final String placeholder;

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final _text = TextEditingController();
  bool _invalid = false;

  /// [child] with the rules [text] on hover, when there is any.
  static Widget _explained(String? text, Widget child) =>
      text == null || text.isEmpty
          ? child
          : CvTooltip(message: text, side: AxisDirection.up, child: child);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add(String line) {
    final m = RegExp(r'^(.*?)(?:\s+(\d{1,2}))?$').firstMatch(line.trim())!;
    final name = m[1]!;
    if (name.isEmpty) return;
    final value = m[2] == null ? null : int.parse(m[2]!);
    final outcome = widget.onSet(name, value);
    setState(() {
      _invalid = outcome is Refused;
      if (!_invalid) _text.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final offered = [
      for (final t in widget.offered)
        if (!widget.tags.containsKey(t.name)) t,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Text(widget.title,
            style: CvTypography.label.copyWith(color: CvColors.textSecondary)),
        if (widget.tags.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final MapEntry(key: name, :value) in widget.tags.entries)
              _explained(widget.pack.tags[name]?.text, Container(
                height: 28,
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(
                  color: CvColors.slate800,
                  borderRadius: BorderRadius.circular(CvRadii.pill),
                  border: Border.all(color: CvColors.borderStrong),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(value == null ? name : '$name $value',
                      style: CvTypography.bodySm),
                  CvPressable(
                    onTap: () => widget.onRemove(name),
                    label: 'Remove $name',
                    radius: CvRadii.pill,
                    builder: (s) => SizedBox(
                      width: 28,
                      height: 28,
                      child: CvIcon(Lucide.x,
                          size: 14,
                          color: s.hover
                              ? CvColors.textPrimary
                              : CvColors.textSecondary),
                    ),
                  ),
                ]),
              )),
          ]),
        if (offered.isNotEmpty)
          CvDropdown<String?>(
            entries: [
              for (final t in offered)
                CvMenuItem(t.name, t.valued ? '${t.name} (1)' : t.name),
            ],
            value: null,
            placeholder: 'Add from ${widget.pack.name}…',
            onChanged: (name) {
              if (name != null) {
                widget.onSet(name, widget.pack.tags[name]!.valued ? 1 : null);
              }
            },
          ),
        TextKeysOnly(
          child: CvTextInput(
            controller: _text,
            placeholder: widget.placeholder,
            maxLength: maxConditionName + 3,
            error: _invalid ? 'Up to 30 letters, and a value up to 99.' : null,
            keepFocus: true,
            onSubmitted: _add,
          ),
        ),
      ],
    );
  }
}
