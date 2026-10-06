import 'dart:convert';
import 'dart:typed_data';

import 'package:chimera_core/chimera_core.dart' show AssetId;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:tactical_engine/tactical_engine.dart';

import 'assets.dart';
import 'module_editor.dart';
import 'modules.dart';
import 'theme.dart';
import 'ui/cv.dart';
import 'ui/hub.dart';

/// The system packs a GM has installed, in Postgres, owner-only. Built-in
/// packs aren't stored.
class InstalledPacks {
  InstalledPacks(this._client);

  final SupabaseClient _client;

  /// Every installed pack this app can read; others are skipped.
  Future<List<SystemPack>> list() async => [
        for (final r in await _client
            .from('packs')
            .select('data')
            .order('installed_at', ascending: true))
          ?_tryPack(r['data'] as Json),
      ];

  /// Installs [pack], replacing one with the same id.
  Future<void> install(SystemPack pack) => _client.from('packs').upsert({
        'owner': _client.auth.currentUser!.id,
        'id': pack.id,
        'name': pack.name,
        'version': pack.version,
        'data': pack.toJson(),
      }, onConflict: 'owner,id');

  Future<void> remove(String id) => _client.from('packs').delete().eq('id', id);

  static SystemPack? _tryPack(Json json) {
    try {
      return SystemPack.fromJson(json);
    } on FormatException {
      return null;
    }
  }
}

/// A pack from a file's [bytes]: a pack module, or an Atlas VTT preset.
/// Throws a [FormatException] saying what's wrong.
SystemPack readPackFile(Uint8List bytes) {
  final Object? json;
  try {
    json = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    throw const FormatException('This file isn\'t JSON.');
  }
  if (json is! Json) throw const FormatException('A pack file holds one object.');
  final pack = json.containsKey('rules') ? packFromAtlasPreset(json) : SystemPack.fromJson(json);
  if (builtInPacks.containsKey(pack.id)) {
    throw FormatException('"${pack.id}" is a built-in system; give the pack another id.');
  }
  return pack;
}

/// Lets the GM pick a module: a bundle (`.chimera`, whose images are
/// uploaded here), a pack file or an Atlas preset. Null when they pick none.
/// Installing is the caller's.
Future<SystemPack?> pickModule(AssetStore assets) async {
  final file = await FilePicker.pickFile(
      type: FileType.custom, allowedExtensions: const ['json', bundleExtension]);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (file.extension?.toLowerCase() != bundleExtension) return readPackFile(bytes);
  final bundle = decodeBundle(bytes);
  if (builtInPacks.containsKey(bundle.pack.id)) {
    throw FormatException(
        '"${bundle.pack.id}" is a built-in system; give the module another id.');
  }
  for (final data in bundle.images.values) {
    // decodeBundle checked each is an image named by its hash.
    await assets.upload(data, imageType(data)!);
  }
  return bundle.pack;
}

/// Saves [pack] as a bundle with its images, `<id>-v<version>.chimera`.
/// False when the GM cancels.
Future<bool> exportModule(SystemPack pack, AssetStore assets) async {
  final images = {
    for (final id in pack.assets) id: await assets.bytes(AssetId(id)),
  };
  final name = '${pack.id}-v${pack.version}.$bundleExtension';
  final saved = await FilePicker.saveFile(
    fileName: name,
    bytes: encodeBundle(pack, images),
    mimeType: 'application/zip',
    type: FileType.custom,
    allowedExtensions: const [bundleExtension],
  );
  // The web downloads without a path; elsewhere null is a cancel.
  return saved != null || kIsWeb;
}

/// What a pack holds, in a line: "12 conditions · 5 region tags · 2 trackers".
String packSummary(SystemPack pack) {
  String n(int count, String one) => '$count $one${count == 1 ? '' : 's'}';
  return [
    n(pack.conditions.length, 'condition'),
    n(pack.regionTags.length, 'region tag'),
    if (pack.trackers.isNotEmpty) n(pack.trackers.length, 'tracker'),
    if (pack.bands.isNotEmpty) n(pack.bands.length, 'range band'),
    if (pack.tokens.isNotEmpty) n(pack.tokens.length, 'token'),
  ].join(' · ');
}

/// The GM's systems on their hub: the built-in ones, the installed ones,
/// and installing more from a pack file or an Atlas preset.
class SystemsPage extends StatefulWidget {
  const SystemsPage({super.key, required this.packs, required this.assets});

  final InstalledPacks packs;
  final AssetStore assets;

  @override
  State<SystemsPage> createState() => _SystemsPageState();
}

class _SystemsPageState extends State<SystemsPage> {
  List<SystemPack>? _installed;
  String? _error;
  String? _notice;

  /// The module open in the editor: a new one is a pack-less draft.
  ({SystemPack? module})? _editing;

  Future<void> _export(SystemPack pack) async {
    setState(() => _notice = null);
    try {
      if (await exportModule(pack, widget.assets)) {
        setState(() => _notice = '${pack.name} exported with '
            '${pack.assets.length} image${pack.assets.length == 1 ? '' : 's'}.');
      }
    } on Object catch (e) {
      setState(() => _error = 'Export failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  Future<void> _run(Future<void> Function() change) async {
    setState(() => _error = null);
    try {
      await change();
      final installed = await widget.packs.list();
      if (mounted) setState(() => _installed = installed);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _install() => _run(() async {
        final pack = await pickModule(widget.assets);
        if (pack == null) return;
        final replaced = _installed?.any((p) => p.id == pack.id) ?? false;
        await widget.packs.install(pack);
        if (mounted) {
          setState(() => _notice = replaced
              ? '${pack.name} updated to version ${pack.version}.'
              : '${pack.name} installed. Pick it in a scene\'s Grid panel.');
        }
      });

  Future<void> _remove(SystemPack pack) async {
    final confirmed = await showCvDialog<bool>(
      context: context,
      title: 'Remove ${pack.name}?',
      icon: Lucide.trash2,
      tone: CvTone.danger,
      body: const Text('Scenes already played with it keep their copy.'),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Remove',
            variant: CvButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (confirmed ?? false) {
      setState(() => _notice = null);
      await _run(() => widget.packs.remove(pack.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing case (:final module)) {
      return ModuleEditor(
        module: module,
        assets: widget.assets,
        onSave: (pack) async {
          await widget.packs.install(pack);
          _notice = '${pack.name} saved, version ${pack.version}.';
        },
        onClose: () {
          setState(() => _editing = null);
          _run(() async {});
        },
      );
    }
    final installed = _installed;
    return HubPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 16, children: [
            const Expanded(
              child: HubTitle('Systems',
                  subtitle: 'The game systems your scenes can be played with, '
                      'and the tokens and cards they bring. Make a module, or '
                      'install one.'),
            ),
            CvButton(
              label: 'Install',
              icon: Lucide.upload,
              onPressed: _install,
            ),
            CvButton(
              label: 'New module',
              icon: Lucide.plus,
              variant: CvButtonVariant.primary,
              onPressed: () => setState(() => _editing = (module: null)),
            ),
          ]),
          if (_error case final error?)
            Text(error, style: CvTypography.bodySm.copyWith(color: CvColors.textDanger))
          else if (_notice case final notice?)
            Text(notice, style: CvTypography.bodySm.copyWith(color: CvColors.textOk)),
          CvPanel(
            solid: true,
            child: Column(children: [
              for (final pack in builtInPacks.values)
                _Row(pack: pack, badge: 'Built in'),
              if (installed == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CvSpinner(size: 20, color: CvColors.rune500),
                ),
              for (final pack in installed ?? const <SystemPack>[])
                _Row(
                  pack: pack,
                  badge: 'Version ${pack.version}',
                  onEdit: () => setState(() => _editing = (module: pack)),
                  onExport: () => _export(pack),
                  onRemove: () => _remove(pack),
                ),
            ]),
          ),
          Text(
              'A module is a game system with the tokens, cards and art it '
              'brings. Make one here, or install a module bundle (.chimera), '
              'a pack file (.json) or an Atlas preset. Scenes carry the '
              'system they use, so players need nothing installed.',
              style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.pack,
    required this.badge,
    this.onEdit,
    this.onExport,
    this.onRemove,
  });

  final SystemPack pack;
  final String badge;
  final VoidCallback? onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: CvColors.borderSubtle))),
        child: Row(spacing: 16, children: [
          const CvIconBadge(Lucide.puzzle),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pack.name, style: CvTypography.weight(CvTypography.body, 600)),
              Text(
                  '${pack.id} · ${formatUnit(pack)} · ${packSummary(pack)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
            ]),
          ),
          Text(badge,
              style: CvTypography.caption.copyWith(
                  fontFamily: CvTypography.mono, color: CvColors.textSecondary)),
          if (onEdit case final edit?)
            CvButton(
              label: 'Edit',
              icon: Lucide.pencil,
              variant: CvButtonVariant.ghost,
              small: true,
              onPressed: edit,
            ),
          if (onExport case final export?)
            CvButton(
              label: 'Export',
              icon: Lucide.download,
              variant: CvButtonVariant.ghost,
              small: true,
              onPressed: export,
            ),
          if (onRemove case final remove?)
            CvButton(
              label: 'Remove',
              icon: Lucide.trash2,
              variant: CvButtonVariant.dangerGhost,
              small: true,
              onPressed: remove,
            ),
        ]),
      );
}

/// A cell's worth in the pack: "5 ft a cell", "1 sector a cell".
String formatUnit(SystemPack pack) {
  final v = pack.unitsPerStep;
  return '${v == v.roundToDouble() ? v.round() : v} ${pack.unit} a cell';
}
