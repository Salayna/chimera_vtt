import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'assets.dart';
import 'theme.dart';
import 'ui/cv.dart';

enum LibraryKind { map, token }

/// An image in the GM's library.
typedef LibraryEntry = ({String id, String name, AssetId asset, AssetId thumb});

/// The signed-in GM's library: their images, shared by all their campaigns.
/// Owner-only behind row-level security.
class Library {
  Library(this._client, this._assets);

  final SupabaseClient _client;
  final AssetStore _assets;

  /// Thumbnails' longest side, in pixels.
  static const thumbSize = 256;

  /// Files [asset] under [kind] as [name], with a thumbnail made from
  /// [image]. The same image filed again keeps its first entry.
  Future<void> add(
      LibraryKind kind, String name, AssetId asset, ui.Image image) async {
    final thumb = await _assets.upload(await thumbnail(image), 'image/png');
    await _client.from('library').upsert({
      'owner': _client.auth.currentUser!.id,
      'kind': kind.name,
      'name': name,
      'asset': asset.value,
      'thumb': thumb.value,
    }, onConflict: 'owner,kind,asset', ignoreDuplicates: true);
  }

  Future<void> rename(String id, String name) =>
      _client.from('library').update({'name': name}).eq('id', id);

  /// Drops the entry. The image stays in Storage: scenes may still use it.
  Future<void> delete(String id) =>
      _client.from('library').delete().eq('id', id);

  Future<List<LibraryEntry>> list(LibraryKind kind) async => [
        for (final r in await _client
            .from('library')
            .select('id, name, asset, thumb')
            .eq('kind', kind.name)
            .order('created_at', ascending: true))
          (
            id: r['id'] as String,
            name: r['name'] as String,
            asset: AssetId(r['asset'] as String),
            thumb: AssetId(r['thumb'] as String),
          ),
      ];
}

/// [image] scaled down to [Library.thumbSize] on its longest side, as PNG.
Future<Uint8List> thumbnail(ui.Image image) async {
  final scale = Library.thumbSize / (image.width > image.height ? image.width : image.height);
  final w = (image.width * (scale < 1 ? scale : 1)).round().clamp(1, Library.thumbSize);
  final h = (image.height * (scale < 1 ? scale : 1)).round().clamp(1, Library.thumbSize);
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final thumb = await picture.toImage(w, h);
  picture.dispose();
  final png = await thumb.toByteData(format: ui.ImageByteFormat.png);
  thumb.dispose();
  return png!.buffer.asUint8List();
}

/// A library thumbnail, loaded once per session like any asset.
class LibraryThumb extends StatelessWidget {
  const LibraryThumb({super.key, required this.assets, required this.entry});

  final AssetStore assets;
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(CvRadii.md),
        child: ColoredBox(
          color: CvColors.surfaceInput,
          child: FutureBuilder(
            future: assets.image(entry.thumb),
            builder: (context, snapshot) => snapshot.data == null
                ? const SizedBox.expand()
                : RawImage(image: snapshot.data, fit: BoxFit.cover),
          ),
        ),
      );
}

/// One kind of the GM's library beside the rail: pick an entry, or add a
/// new one. Reloads when [revision] changes.
class LibraryPanel extends StatefulWidget {
  const LibraryPanel({
    super.key,
    required this.library,
    required this.assets,
    required this.kind,
    required this.title,
    required this.hint,
    required this.onPick,
    this.footer = const [],
    this.revision = 0,
  });

  final Library library;
  final AssetStore assets;
  final LibraryKind kind;
  final String title;
  final String hint;
  final void Function(LibraryEntry entry) onPick;

  /// Buttons under the entries: upload, and the like.
  final List<Widget> footer;
  final int revision;

  @override
  State<LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<LibraryPanel> {
  List<LibraryEntry>? _entries;
  String? _error;

  /// Editing: tapping renames, and each entry has a delete button.
  bool _editing = false;

  Future<void> _rename(LibraryEntry entry) async {
    final text = TextEditingController(text: entry.name);
    final name = await showCvDialog<String>(
      context: context,
      title: 'Rename ${entry.name}',
      icon: Lucide.pencil,
      body: CvTextInput(
        controller: text,
        label: 'Name',
        maxLength: 80,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context)),
        CvButton(
            label: 'Rename',
            variant: CvButtonVariant.primary,
            onPressed: () => Navigator.pop(context, text.text)),
      ],
    );
    // Not disposed: the dialog still shows it while it animates away.
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == entry.name) return;
    await _run(() => widget.library.rename(entry.id, trimmed));
  }

  Future<void> _delete(LibraryEntry entry) async {
    final confirmed = await showCvDialog<bool>(
      context: context,
      title: 'Delete ${entry.name}?',
      icon: Lucide.trash2,
      tone: CvTone.danger,
      body: const Text('It leaves your library. Scenes already using it '
          'keep it.'),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Delete',
            variant: CvButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (confirmed ?? false) await _run(() => widget.library.delete(entry.id));
  }

  Future<void> _run(Future<void> Function() change) async {
    try {
      await change();
      await _load();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LibraryPanel old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || old.kind != widget.kind) _load();
  }

  Future<void> _load() async {
    try {
      final entries = await widget.library.list(widget.kind);
      if (mounted) setState(() => _entries = entries);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return CvPopIn(
      child: CvPanel(
        width: 300,
        padding: const EdgeInsets.all(CvSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(children: [
              Expanded(child: CvOverline(widget.title)),
              if (entries?.isNotEmpty ?? false)
                CvToolButton(
                  icon: _editing ? Lucide.check : Lucide.pencil,
                  label: _editing ? 'Done' : 'Rename or delete',
                  active: _editing,
                  tooltipSide: AxisDirection.up,
                  onPressed: () => setState(() => _editing = !_editing),
                ),
            ]),
            if (_error case final error?)
              Text(error,
                  style: CvTypography.caption.copyWith(color: CvColors.ember400))
            else if (entries == null)
              const Center(child: CvSpinner(size: 20, color: CvColors.amber500))
            else if (entries.isEmpty)
              Text(widget.hint,
                  style: CvTypography.caption
                      .copyWith(color: CvColors.textSecondary))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in entries)
                      CvPressable(
                        onTap: () => _editing ? _rename(e) : widget.onPick(e),
                        label: _editing ? 'Rename ${e.name}' : e.name,
                        builder: (s) => SizedBox(
                          width: 80,
                          child: Column(spacing: 4, children: [
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: DecoratedBox(
                                position: DecorationPosition.foreground,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(CvRadii.md),
                                  border: Border.all(
                                      color: s.hover
                                          ? CvColors.amber500
                                          : CvColors.borderSubtle),
                                ),
                                child: Stack(fit: StackFit.expand, children: [
                                  LibraryThumb(assets: widget.assets, entry: e),
                                  if (_editing)
                                    Positioned(
                                      right: 2,
                                      top: 2,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: CvColors.surfacePanelSolid,
                                          borderRadius:
                                              BorderRadius.circular(CvRadii.md),
                                        ),
                                        child: CvToolButton(
                                          icon: Lucide.trash2,
                                          label: 'Delete ${e.name}',
                                          danger: true,
                                          tooltipSide: AxisDirection.up,
                                          onPressed: () => _delete(e),
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                            ),
                            Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CvTypography.caption),
                          ]),
                        ),
                      ),
                  ]),
                ),
              ),
            ...widget.footer,
          ],
        ),
      ),
    );
  }
}
