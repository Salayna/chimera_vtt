import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme.dart';
import '../ui/cv.dart';
import 'chrome.dart' show TextKeysOnly;
import 'table_view.dart';

/// One thing the palette can do: [group] heads it in the list ("Tokens",
/// "Tools"), [shortcut] is its key, if it has one.
typedef PaletteItem = ({
  String group,
  String label,
  Lucide icon,
  String? shortcut,
  VoidCallback run,
});

/// The tools and the view, for anyone at the table; the [gm] also has fog,
/// regions and snap.
List<PaletteItem> toolItems(TableController c, {bool gm = false}) => [
      (group: 'Tools', label: 'Move', icon: Lucide.mousePointer2, shortcut: 'V', run: () => c.tool = Tool.move),
      (group: 'Tools', label: 'Ruler', icon: Lucide.ruler, shortcut: 'L', run: () => c.tool = Tool.ruler),
      (group: 'Tools', label: 'Ping', icon: Lucide.radio, shortcut: 'P', run: () => c.tool = Tool.ping),
      if (gm) ...[
        (group: 'Tools', label: 'Fog', icon: Lucide.paintbrush, shortcut: 'B', run: () => c.tool = Tool.fogBrush),
        (group: 'Tools', label: 'Regions', icon: Lucide.scan, shortcut: 'A', run: () => c.tool = Tool.region),
        (group: 'View', label: 'Snap to grid', icon: Lucide.magnet, shortcut: 'S', run: () => c.snap = !c.snap),
      ],
      (group: 'View', label: 'Fit map', icon: Lucide.scan, shortcut: '0', run: c.fit),
      (group: 'View', label: 'Zoom in', icon: Lucide.zoomIn, shortcut: '+', run: () => c.zoomBy(1.25)),
      (group: 'View', label: 'Zoom out', icon: Lucide.zoomOut, shortcut: '−', run: () => c.zoomBy(1 / 1.25)),
    ];

/// The scene's tokens: picking one selects it and brings it into view.
List<PaletteItem> tokenItems(Scene scene, TableController c) => [
      for (final t in scene.tokens.values)
        (
          group: 'Tokens',
          label: t.name.isEmpty ? 'Unnamed token' : t.name,
          icon: Lucide.locateFixed,
          shortcut: null,
          run: () {
            c
              ..tool = Tool.move
              ..selected.value = t.id
              ..centerOn(t.position);
          },
        ),
    ];

/// [characters]' sheets, to open through [onOpen].
List<PaletteItem> characterItems(
        Iterable<Character> characters, ValueChanged<CharacterId> onOpen) =>
    [
      for (final c in characters)
        (
          group: 'Characters',
          label: c.name.isEmpty ? 'Unnamed character' : c.name,
          icon: Lucide.bookOpen,
          shortcut: null,
          run: () => onOpen(c.id),
        ),
    ];

/// The palette over the table, a third of the way down, on a scrim that
/// closes it.
class PaletteLayer extends StatelessWidget {
  const PaletteLayer(
      {super.key, required this.items, required this.onClose, this.onRoll});

  final List<PaletteItem> items;
  final VoidCallback onClose;
  final void Function(String dice)? onRoll;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onClose,
        child: ColoredBox(
          color: CvColors.surfaceScrim,
          child: Align(
            alignment: const Alignment(0, -0.4),
            // Taps inside don't close it.
            child: GestureDetector(
              onTap: () {},
              child: CommandPalette(
                  items: items, onClose: onClose, onRoll: onRoll),
            ),
          ),
        ),
      );
}

/// Dice as typed: "2d6+3", "d20", or a "/r" line.
final _dice = RegExp(r'^(?:/r(?:oll)?\s+)?([0-9\s+-]*d[0-9][0-9d\s+-]*)$',
    caseSensitive: false);

/// ⌘K: one box to find a token, run an action or roll dice. [items] are
/// what it searches; typed dice become a roll, through [onRoll].
class CommandPalette extends StatefulWidget {
  const CommandPalette({
    super.key,
    required this.items,
    required this.onClose,
    this.onRoll,
  });

  final List<PaletteItem> items;
  final VoidCallback onClose;
  final void Function(String dice)? onRoll;

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _selected = GlobalKey();
  int _at = 0;

  /// What had the keys before: the table, which gets them back on close.
  final _before = FocusManager.instance.primaryFocus;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() => _at = 0));
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    final before = _before;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (before?.context != null) before!.requestFocus();
    });
    super.dispose();
  }

  List<PaletteItem> get _shown {
    final q = _query.text.trim().toLowerCase();
    final roll = widget.onRoll;
    final dice = roll == null ? null : _dice.firstMatch(q)?[1]?.trim();
    return [
      if (dice != null)
        (group: 'Dice', label: 'Roll $dice', icon: Lucide.circleDashed, shortcut: null, run: () => roll!(dice)),
      for (final i in widget.items)
        if (i.label.toLowerCase().contains(q) || i.group.toLowerCase().contains(q)) i,
    ];
  }

  void _run(PaletteItem item) {
    widget.onClose();
    item.run();
  }

  void _move(int by, int count) {
    if (count == 0) return;
    setState(() => _at = (_at + by) % count);
    // Keep the picked row in view; wrapping round jumps to the far end,
    // where the row may not be built yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (_at == 0) return _scroll.jumpTo(0);
      if (_at == count - 1) {
        return _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
      if (_selected.currentContext case final row?) {
        Scrollable.ensureVisible(row,
            alignmentPolicy: by > 0
                ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final at = shown.isEmpty ? 0 : _at.clamp(0, shown.length - 1);
    return CvPopIn(
      child: CvPanel(
        width: 560,
        raised: true,
        padding: const EdgeInsets.all(CvSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: CvSpacing.s4,
          children: [
            TextKeysOnly(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _move(1, shown.length),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _move(-1, shown.length),
                  const SingleActivator(LogicalKeyboardKey.escape):
                      widget.onClose,
                },
                child: CvTextInput(
                  controller: _query,
                  icon: Lucide.search,
                  autofocus: true,
                  keepFocus: true,
                  placeholder: 'Find a token, run an action, roll 2d6…',
                  onSubmitted: (_) {
                    if (shown.isNotEmpty) _run(shown[at]);
                  },
                ),
              ),
            ),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(CvSpacing.s5),
                child: Text('Nothing matches "${_query.text.trim()}".',
                    textAlign: TextAlign.center,
                    style: CvTypography.bodySm
                        .copyWith(color: CvColors.textSecondary)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _row(
                    shown[i],
                    key: i == at ? _selected : null,
                    selected: i == at,
                    // A group's name heads its first row.
                    heading: i == 0 || shown[i - 1].group != shown[i].group,
                  ),
                ),
              ),
            Text('↑↓ to move · ↵ to run · esc to close',
                textAlign: TextAlign.center,
                style:
                    CvTypography.caption.copyWith(color: CvColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _row(PaletteItem item,
          {Key? key, required bool selected, required bool heading}) =>
      Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (heading)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: CvOverline(item.group),
            ),
          CvPressable(
            onTap: () => _run(item),
            label: item.label,
            radius: CvRadii.sm,
            pressScale: 1,
            builder: (s) => Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: selected || s.hover
                    ? CvColors.surfaceHover
                    : const Color(0x00000000),
                borderRadius: BorderRadius.circular(CvRadii.sm),
              ),
              child: Row(spacing: 10, children: [
                CvIcon(item.icon,
                    color: selected ? CvColors.rune500 : CvColors.textSecondary),
                Expanded(
                  child: Text(item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CvTypography.label),
                ),
                if (item.shortcut case final keys?) CvKbd(keys),
              ]),
            ),
          ),
        ],
      );
}
