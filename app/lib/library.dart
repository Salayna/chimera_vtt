import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chimera_core/chimera_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'assets.dart';
import 'theme.dart';
import 'room.dart' show sceneFromFile;
import 'ui/cv.dart';
import 'ui/hub.dart';

enum LibraryKind { map, token, scene }

/// An entry in the GM's library: an image ([asset]), or a scene (no asset,
/// and a thumbnail only if its scene has a map).
typedef LibraryEntry = ({String id, String name, AssetId? asset, AssetId? thumb});

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

  /// Files a copy of [scene] as a template, with its map's thumbnail.
  Future<void> addScene(String name, Scene scene) async {
    AssetId? thumb;
    if (scene.settings.map case final map?) {
      thumb = await _assets.upload(
          await thumbnail(await _assets.image(map)), 'image/png');
    }
    await _client.from('library').insert({
      'owner': _client.auth.currentUser!.id,
      'kind': LibraryKind.scene.name,
      'name': name,
      'data': scene.toJson(),
      'thumb': thumb?.value,
    });
  }

  /// A library scene, ready to become a campaign's: token owners are
  /// members of one campaign, so the copy has none.
  Future<Scene> sceneCopy(String id) async {
    final row =
        await _client.from('library').select('data').eq('id', id).single();
    return withoutOwners(Scene.fromJson(row['data'] as Json));
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
            asset: switch (r['asset']) { final String a => AssetId(a), _ => null },
            thumb: switch (r['thumb']) { final String t => AssetId(t), _ => null },
          ),
      ];
}

/// [scene] with no token owned by anyone.
Scene withoutOwners(Scene scene) => Scene(
      settings: scene.settings,
      tokens: {for (final t in scene.tokens.values) t.id: t.withOwner(null)},
      fogOps: scene.fogOps,
    );

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

/// Asks for a new name for [entry]. Null when cancelled or unchanged.
Future<String?> askEntryName(BuildContext context, LibraryEntry entry) async {
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
  return trimmed.isEmpty || trimmed == entry.name ? null : trimmed;
}

/// Asks before [entry] leaves the library.
Future<bool> confirmEntryDelete(BuildContext context, LibraryEntry entry) async =>
    await showCvDialog<bool>(
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
    ) ??
    false;

/// An image the GM picked and uploaded, named after its file.
typedef PickedImage = ({AssetId id, ui.Image image, String name});

/// Lets the GM pick an image file and uploads it. Null when they pick none.
/// [onUploading] gets the file's name once one is picked. Throws a
/// [FormatException] for a file that isn't PNG, JPEG or WebP.
Future<PickedImage?> pickImage(AssetStore assets,
    {void Function(String file)? onUploading}) async {
  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return null;
  final type = AssetStore.contentTypes[file.extension?.toLowerCase()];
  if (type == null) {
    throw const FormatException('Use a PNG, JPEG or WebP image.');
  }
  onUploading?.call(file.name);
  final bytes = await file.readAsBytes();
  final image = await decodeImage(bytes);
  final id = await assets.upload(bytes, type);
  assets.remember(id, image);
  return (id: id, image: image, name: file.name.replaceFirst(RegExp(r'\.[^.]*$'), ''));
}

/// A library thumbnail, loaded once per session like any asset. Empty
/// ground when there is none.
class LibraryThumb extends StatelessWidget {
  const LibraryThumb({super.key, required this.assets, required this.thumb});

  final AssetStore assets;
  final AssetId? thumb;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(CvRadii.md),
        child: ColoredBox(
          color: CvColors.surfaceInput,
          child: FutureBuilder(
            future: switch (thumb) {
              final thumb? => assets.image(thumb),
              null => null,
            },
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
    final name = await askEntryName(context, entry);
    if (name != null) await _run(() => widget.library.rename(entry.id, name));
  }

  Future<void> _delete(LibraryEntry entry) async {
    if (await confirmEntryDelete(context, entry)) {
      await _run(() => widget.library.delete(entry.id));
    }
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
                                  LibraryThumb(assets: widget.assets, thumb: e.thumb),
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

/// The GM's library page (design: hub/library): maps, tokens and scenes for
/// any campaign, searchable, with a detail panel for the picked map or
/// token.
// ponytail: no "Add to campaign" or usage counts in the detail panel yet;
// maps go into a campaign from its room, and usage isn't tracked.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.library, required this.assets});

  final Library library;
  final AssetStore assets;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  var _kind = LibraryKind.map;
  Map<LibraryKind, List<LibraryEntry>>? _entries;
  String? _error;
  String? _uploading;
  String? _selected;
  final _search = TextEditingController();

  static const _empty = {
    LibraryKind.map: 'Maps you upload, here or at the table, are kept here '
        'for every campaign.',
    LibraryKind.token: 'Token images you upload, here or at the table, are '
        'kept here for every campaign.',
    LibraryKind.scene: "Save a scene from a campaign's Scenes panel, or "
        'upload a scene file, then start new scenes from it in any campaign.',
  };

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _run(() async {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Runs [change], then reloads every kind, for the counts.
  Future<void> _run(Future<void> Function() change) async {
    setState(() => _error = null);
    try {
      await change();
      final lists = await Future.wait(
          [for (final k in LibraryKind.values) widget.library.list(k)]);
      if (mounted) {
        setState(() => _entries = {
              for (final (i, k) in LibraryKind.values.indexed) k: lists[i],
            });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// An image for maps and tokens, a scene file for scenes.
  Future<void> _upload() => _run(() async {
        final kind = _kind;
        try {
          if (kind == LibraryKind.scene) {
            final file = await FilePicker.pickFile(
                type: FileType.custom, allowedExtensions: const ['json']);
            if (file == null) return;
            setState(() => _uploading = file.name);
            final scene = sceneFromFile(await file.readAsBytes());
            await widget.library.addScene(
                file.name.replaceFirst(RegExp(r'\.[^.]*$'), ''), scene);
            return;
          }
          final picked = await pickImage(widget.assets,
              onUploading: (file) => setState(() => _uploading = file));
          if (picked == null) return;
          await widget.library.add(kind,
              picked.name.isEmpty ? kind.name : picked.name, picked.id, picked.image);
        } finally {
          if (mounted) setState(() => _uploading = null);
        }
      });

  Future<void> _rename(LibraryEntry e) async {
    final name = await askEntryName(context, e);
    if (name != null) await _run(() => widget.library.rename(e.id, name));
  }

  Future<void> _delete(LibraryEntry e) async {
    if (await confirmEntryDelete(context, e)) {
      setState(() => _selected = null);
      await _run(() => widget.library.delete(e.id));
    }
  }

  static String _plural(LibraryKind k) => switch (k) {
        LibraryKind.map => 'maps',
        LibraryKind.token => 'tokens',
        LibraryKind.scene => 'scenes',
      };

  @override
  Widget build(BuildContext context) {
    final all = _entries;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final e in all?[_kind] ?? const <LibraryEntry>[])
        if (e.name.toLowerCase().contains(query)) e,
    ];
    final selected = shown.where((e) => e.id == _selected).firstOrNull;
    int count(LibraryKind k) => all?[k]?.length ?? 0;
    return HubPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 16, children: [
            const Expanded(
              child: HubTitle('Library',
                  subtitle: 'Maps, tokens and scenes you can use in any of '
                      'your campaigns.'),
            ),
            CvButton(
              label: 'Upload',
              icon: Lucide.upload,
              variant: CvButtonVariant.primary,
              onPressed: _uploading == null ? _upload : null,
            ),
          ]),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 420,
                child: CvSegmentedControl(
                  segments: [
                    (value: LibraryKind.map, label: 'Maps ${count(LibraryKind.map)}', icon: Lucide.map, checked: null),
                    (value: LibraryKind.token, label: 'Tokens ${count(LibraryKind.token)}', icon: Lucide.circle, checked: null),
                    (value: LibraryKind.scene, label: 'Scenes ${count(LibraryKind.scene)}', icon: Lucide.fileJson, checked: null),
                  ],
                  value: _kind,
                  onChanged: (k) => setState(() {
                    _kind = k;
                    _selected = null;
                  }),
                ),
              ),
              SizedBox(
                width: 300,
                child: CvTextInput(
                  controller: _search,
                  icon: Lucide.search,
                  placeholder: 'Search ${_plural(_kind)}',
                ),
              ),
            ],
          ),
          if (_uploading case final file?)
            CvPanel(
              solid: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: CvProgressBar(label: 'Uploading $file', color: CvColors.amber500),
            ),
          if (_error case final error?)
            Text(error, style: CvTypography.bodySm.copyWith(color: CvColors.textDanger)),
          if (all == null)
            if (_error == null)
              const Center(child: CvSpinner(size: 20, color: CvColors.amber500))
            else
              const SizedBox()
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                query.isEmpty
                    ? _empty[_kind]!
                    : 'Nothing in ${_plural(_kind)} matches "${_search.text.trim()}".',
                textAlign: TextAlign.center,
                style: CvTypography.body.copyWith(color: CvColors.textSecondary),
              ),
            )
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
              Expanded(
                child: _kind == LibraryKind.scene
                    ? _sceneList(shown)
                    : _grid(shown, detail: selected != null),
              ),
              if (selected != null && _kind != LibraryKind.scene)
                SizedBox(
                  width: 340,
                  child: _Detail(
                    key: ValueKey(selected.id),
                    entry: selected,
                    kind: _kind,
                    assets: widget.assets,
                    onClose: () => setState(() => _selected = null),
                    onRename: () => _rename(selected),
                    onDelete: () => _delete(selected),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  /// Maps as cover cards (4 across), tokens as round faces (7 across);
  /// fewer beside the detail panel.
  Widget _grid(List<LibraryEntry> entries, {required bool detail}) {
    final maps = _kind == LibraryKind.map;
    final gap = maps ? 16.0 : 12.0;
    return LayoutBuilder(builder: (context, constraints) {
      final columns = hubColumns(constraints.maxWidth, maps ? 200 : 110, gap,
          maps ? (detail ? 3 : 4) : (detail ? 5 : 7));
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final e in entries)
          SizedBox(
            width: width,
            child: HubCard(
              label: e.name,
              selected: e.id == _selected,
              onTap: () => setState(
                  () => _selected = e.id == _selected ? null : e.id),
              child: maps
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        height: 150,
                        child: _Image(assets: widget.assets, entry: e),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CvTypography.weight(CvTypography.body, 500)),
                      ),
                    ])
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 20, 8, 14),
                      child: Column(spacing: 10, children: [
                        SizedBox.square(
                          dimension: 64,
                          child: ClipOval(
                              child: _Image(assets: widget.assets, entry: e)),
                        ),
                        Text(e.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: CvTypography.weight(CvTypography.bodySm, 500)),
                      ]),
                    ),
            ),
          ),
      ]);
    });
  }

  /// Scenes as rows in one panel.
  Widget _sceneList(List<LibraryEntry> entries) => CvPanel(
        solid: true,
        child: Column(children: [
          for (final (i, e) in entries.indexed)
            Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: i == entries.length - 1
                    ? null
                    : const Border(bottom: BorderSide(color: CvColors.borderSubtle)),
              ),
              child: Row(spacing: 16, children: [
                SizedBox.square(
                  dimension: 40,
                  child: e.thumb == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: CvColors.slate800,
                            borderRadius: BorderRadius.circular(CvRadii.md),
                          ),
                          child: const CvIcon(Lucide.fileJson,
                              color: CvColors.textSecondary),
                        )
                      : LibraryThumb(assets: widget.assets, thumb: e.thumb),
                ),
                Expanded(
                  child: Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CvTypography.weight(CvTypography.body, 500)
                          .copyWith(fontFamily: CvTypography.mono)),
                ),
                CvButton(
                  label: 'Rename',
                  icon: Lucide.pencil,
                  variant: CvButtonVariant.ghost,
                  small: true,
                  onPressed: () => _rename(e),
                ),
                CvButton(
                  label: 'Delete',
                  icon: Lucide.trash2,
                  variant: CvButtonVariant.dangerGhost,
                  small: true,
                  onPressed: () => _delete(e),
                ),
              ]),
            ),
        ]),
      );
}

/// An entry's image, filling its box: its thumbnail, or stand-in art.
class _Image extends StatelessWidget {
  const _Image({required this.assets, required this.entry});

  final AssetStore assets;
  final LibraryEntry entry;

  @override
  Widget build(BuildContext context) => switch (entry.thumb) {
        final thumb? => FutureBuilder(
            future: assets.image(thumb),
            builder: (context, snapshot) => snapshot.data == null
                ? const ColoredBox(color: CvColors.surfaceInput)
                : RawImage(image: snapshot.data, fit: BoxFit.cover),
          ),
        null => HubCover(seed: entry.id),
      };
}

/// The picked map or token: a large preview, its name, rename and delete.
class _Detail extends StatelessWidget {
  const _Detail({
    super.key,
    required this.entry,
    required this.kind,
    required this.assets,
    required this.onClose,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryEntry entry;
  final LibraryKind kind;
  final AssetStore assets;
  final VoidCallback onClose;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => CvPopIn(
        child: CvPanel(
          solid: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (kind == LibraryKind.map)
              SizedBox(height: 190, child: _Image(assets: assets, entry: entry))
            else
              Container(
                height: 160,
                color: CvColors.bgSunken,
                alignment: Alignment.center,
                child: SizedBox.square(
                  dimension: 96,
                  child: ClipOval(child: _Image(assets: assets, entry: entry)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(entry.name,
                            style: CvTypography.weight(CvTypography.body, 600)
                                .copyWith(fontSize: 16, height: 22 / 16)),
                        Text(kind == LibraryKind.map ? 'Map' : 'Token',
                            style: CvTypography.caption
                                .copyWith(color: CvColors.textSecondary)),
                      ]),
                    ),
                    CvToolButton(
                      icon: Lucide.x,
                      label: 'Close',
                      tooltipSide: AxisDirection.left,
                      onPressed: onClose,
                    ),
                  ]),
                  Text(
                    kind == LibraryKind.map
                        ? 'Use it from a room: Change map, on the GM\'s rail.'
                        : 'Use it from a room: Add token, on the GM\'s rail.',
                    style: CvTypography.bodySm.copyWith(color: CvColors.textSecondary),
                  ),
                  Container(
                    padding: const EdgeInsets.only(top: 12),
                    decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: CvColors.borderSubtle))),
                    child: Row(spacing: 4, children: [
                      CvButton(
                        label: 'Rename',
                        icon: Lucide.pencil,
                        variant: CvButtonVariant.ghost,
                        small: true,
                        onPressed: onRename,
                      ),
                      CvButton(
                        label: 'Delete',
                        icon: Lucide.trash2,
                        variant: CvButtonVariant.dangerGhost,
                        small: true,
                        onPressed: onDelete,
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}
