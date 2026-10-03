import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart'
    show CardSection, SystemPack, TokenTemplate, TokenTracker, TrackerDef;

import '../theme.dart';
import '../ui/cv.dart';

/// The scene's pack tokens beside the rail (a Solaris module's threats):
/// search them, and pick one to place it ready to run.
class PackTokensPanel extends StatefulWidget {
  const PackTokensPanel({super.key, required this.pack, required this.onPick});

  final SystemPack pack;
  final void Function(TokenTemplate template) onPick;

  @override
  State<PackTokensPanel> createState() => _PackTokensPanelState();
}

class _PackTokensPanelState extends State<PackTokensPanel> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final t in widget.pack.tokens.values)
        if (t.name.toLowerCase().contains(query)) t,
    ];
    return CvPopIn(
      child: CvPanel(
        width: 300,
        padding: const EdgeInsets.all(CvSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            CvOverline('${widget.pack.name} tokens'),
            CvTextInput(
              controller: _search,
              icon: Lucide.search,
              placeholder: 'Search ${widget.pack.tokens.length}',
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in shown)
                      CvPressable(
                        onTap: () => widget.onPick(t),
                        label: 'Place ${t.name}',
                        radius: CvRadii.sm,
                        pressScale: 1,
                        builder: (s) => Container(
                          constraints: const BoxConstraints(minHeight: CvSizes.hit),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: s.hover ? CvColors.surfaceHover : const Color(0x00000000),
                            borderRadius: BorderRadius.circular(CvRadii.sm),
                          ),
                          child: Row(spacing: 10, children: [
                            Expanded(
                              child: Text(t.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: CvTypography.label),
                            ),
                            if (t.form case final form?)
                              Text(form,
                                  style: CvTypography.caption
                                      .copyWith(color: CvColors.textSecondary)),
                          ]),
                        ),
                      ),
                    if (shown.isEmpty)
                      Text('Nothing matches "${_search.text.trim()}".',
                          style: CvTypography.caption
                              .copyWith(color: CvColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [template] as a token at [position], in cells of [cellSize]: its name,
/// size, starting trackers and tags, and the link to its card.
Token tokenFrom(TokenTemplate template,
        {required TokenId id,
        required Point position,
        required double cellSize,
        AssetId? image}) =>
    Token(
      id: id,
      position: position,
      size: template.size * cellSize,
      image: image,
      name: template.name,
      template: template.name,
      conditions: Map.unmodifiable(template.conditions),
      trackers: Map.unmodifiable({
        for (final t in template.trackers) t.name: t.value,
      }),
    );

/// The trackers a token offers: its template's (with their own
/// maximums) first, then the pack's others.
List<TrackerDef> trackersFor(Token token, SystemPack pack) {
  final template = pack.tokens[token.template];
  final own = [
    for (final t in template?.trackers ?? const <TokenTracker>[])
      TrackerDef(t.name, max: t.max, text: pack.trackers.where((d) => d.name == t.name).firstOrNull?.text ?? ''),
  ];
  return [
    ...own,
    for (final d in pack.trackers)
      if (!own.any((t) => t.name == d.name)) d,
  ];
}

/// A pack token's card on the GM's token card: each section titled, its
/// text as written.
class TokenCardSections extends StatelessWidget {
  const TokenCardSections({super.key, required this.sections, this.loadImage});

  final List<CardSection> sections;

  /// Loads a section's image; without it, images aren't shown.
  final Future<ui.Image> Function(AssetId id)? loadImage;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          for (final s in sections)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                CvOverline(s.title),
                if ((s.image, loadImage) case (final image?, final load?))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CvRadii.md),
                    child: FutureBuilder(
                      future: load(AssetId(image)),
                      builder: (context, snapshot) => snapshot.data == null
                          ? const SizedBox(height: 120)
                          : RawImage(image: snapshot.data, fit: BoxFit.fitWidth),
                    ),
                  ),
                if (s.text.isNotEmpty) Text(s.text, style: CvTypography.bodySm),
              ],
            ),
        ],
      );
}
