import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:tactical_engine/tactical_engine.dart';

import 'packs.dart';
import 'sheet_view.dart';
import 'theme.dart';
import 'ui/cv.dart';
import 'ui/hub.dart';

/// A user's characters, in Postgres: only their owner writes them, and
/// the GMs of campaigns they're linked to read them. Each is played with
/// one system.
class SavedCharacters {
  SavedCharacters(this._client);

  final SupabaseClient _client;

  static const _fields = 'id, owner, system, name, sheet';

  Future<List<Character>> list() async => [
        for (final r in await _client
            .from('characters')
            .select(_fields)
            .eq('owner', _client.auth.currentUser!.id)
            .order('updated_at', ascending: false))
          Character.fromJson(r),
      ];

  /// This user's characters played with [system].
  Future<List<Character>> forSystem(String system) async =>
      [for (final c in await list()) if (c.system == system) c];

  /// The characters linked to [campaign], which its GM reads.
  Future<List<Character>> linked(String campaign) async => [
        for (final r in await _client
            .from('characters')
            .select('$_fields, campaign_characters!inner(campaign)')
            .eq('campaign_characters.campaign', campaign))
          Character.fromJson(r),
      ];

  /// Links this user's character [id] to [campaign], which must be played
  /// with its system and have them as a member.
  Future<void> link(String campaign, CharacterId id) => _client
      .rpc('link_character', params: {'campaign': campaign, 'character_id': id.value});

  Future<void> unlink(String campaign, CharacterId id) => _client
      .from('campaign_characters')
      .delete()
      .eq('campaign', campaign)
      .eq('character', id.value);

  /// A new character for [system], starting with its sheet's values.
  Future<Character> create(String name, SystemPack system) async =>
      Character.fromJson(await _client
          .from('characters')
          .insert({
            'name': name,
            'system': system.id,
            'sheet': {'values': system.sheet?.start() ?? const {}},
          })
          .select(_fields)
          .single());

  Future<void> save(Character c) => _client.from('characters').update({
        'name': c.name,
        'sheet': c.sheet,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', c.id.value);

  Future<void> remove(CharacterId id) =>
      _client.from('characters').delete().eq('id', id.value);
}

/// [c] with its values cleaned against its system's sheet, and its items'
/// against their kinds, as anything read from the table is: sheets come
/// from players. Items of a kind the system lacks are kept as they are.
Character cleaned(Character c, SystemPack? system) {
  final sheet = system?.sheet;
  if (sheet == null) return c;
  final kinds = system!.compendium?.kinds ?? const {};
  return c.copyWith(
    values: sheet.clean(c.values),
    items: [
      for (final i in c.items)
        if (kinds[i.kind] case final kind?) i.withValues(kind.clean(i.values)) else i,
    ],
  );
}

/// A user's characters on their home: each made for one system, opened to
/// edit its sheet.
class CharactersPage extends StatefulWidget {
  const CharactersPage({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<CharactersPage> createState() => _CharactersPageState();
}

class _CharactersPageState extends State<CharactersPage> {
  late final _characters = SavedCharacters(widget.client);
  late final _installed = InstalledPacks(widget.client);
  List<Character>? _list;

  /// Every system this user can play, by id: built in and installed.
  Map<String, SystemPack> _systems = Map.of(builtInPacks);
  Character? _open;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  /// Runs [action], then reloads the list.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
      final (list, installed) = await (_characters.list(), _installed.list()).wait;
      if (mounted) {
        setState(() {
          _systems = {...builtInPacks, for (final p in installed) p.id: p};
          _list = [for (final c in list) cleaned(c, _systems[c.system])];
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _create() async {
    final withSheets = [for (final p in _systems.values) if (p.sheet != null) p];
    if (withSheets.isEmpty) {
      setState(() => _error = 'No system has a character sheet yet: install '
          'a module with one from the Systems page.');
      return;
    }
    final name = TextEditingController();
    var system = withSheets.first;
    final made = await showCvDialog<bool>(
      context: context,
      title: 'New character',
      icon: Lucide.plus,
      body: StatefulBuilder(
        builder: (context, setDialog) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            CvTextInput(
              controller: name,
              label: 'Name',
              placeholder: 'Ayla Venn',
              maxLength: Character.maxName,
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
            CvDropdown<SystemPack>(
              label: 'System',
              value: system,
              entries: [for (final p in withSheets) CvMenuItem(p, p.name)],
              onChanged: (p) => setDialog(() => system = p),
            ),
          ],
        ),
      ),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Create',
            variant: CvButtonVariant.primary,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    final n = name.text.trim();
    name.dispose();
    if (!(made ?? false) || n.isEmpty) return;
    await _run(() async {
      final c = await _characters.create(n, system);
      if (mounted) setState(() => _open = c);
    });
  }

  Future<void> _remove(Character c) async {
    final confirmed = await showCvDialog<bool>(
      context: context,
      title: 'Delete ${c.name}?',
      icon: Lucide.trash2,
      tone: CvTone.danger,
      body: const Text('Their sheet goes for good.'),
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
    if (confirmed ?? false) {
      setState(() => _open = null);
      await _run(() => _characters.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_open case final open?) {
      return CharacterEditor(
        key: ValueKey(open.id),
        character: open,
        system: _systems[open.system],
        onSave: _characters.save,
        onDelete: () => _remove(open),
        onClose: () {
          setState(() => _open = null);
          _run(() async {});
        },
      );
    }
    final list = _list;
    return HubPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 16, children: [
            const Expanded(
              child: HubTitle('Characters',
                  subtitle: 'Yours to play, each with one system\'s sheet.'),
            ),
            CvButton(
              label: 'New character',
              icon: Lucide.plus,
              variant: CvButtonVariant.primary,
              onPressed: list == null ? null : _create,
            ),
          ]),
          if (_error case final error?)
            Text(error, style: CvTypography.bodySm.copyWith(color: CvColors.textDanger)),
          if (list == null && _error == null)
            const Center(child: CvSpinner(size: 20, color: CvColors.amber500))
          else if (list != null && list.isEmpty)
            Text('No characters yet. Make one for a system with a sheet, '
                'D&D 5e or a module you installed.',
                style: CvTypography.body.copyWith(color: CvColors.textSecondary))
          else if (list != null)
            CvPanel(
              solid: true,
              child: Column(children: [
                for (final c in list)
                  _Row(
                    character: c,
                    system: _systems[c.system]?.name ?? '${c.system} (not installed)',
                    onOpen: () => setState(() => _open = c),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.character, required this.system, required this.onOpen});

  final Character character;
  final String system;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => CvPressable(
        onTap: onOpen,
        label: 'Open ${character.name}',
        pressScale: 1,
        builder: (s) => Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: s.hover ? CvColors.surfaceHover : null,
            border: const Border(bottom: BorderSide(color: CvColors.borderSubtle)),
          ),
          child: Row(spacing: 16, children: [
            const CvIconBadge(Lucide.userRound),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(character.name, style: CvTypography.weight(CvTypography.body, 600)),
                Text(system,
                    style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
              ]),
            ),
            const CvIcon(Lucide.chevronRight, size: CvSizes.iconSm, color: CvColors.textSecondary),
          ]),
        ),
      );
}

/// One character's sheet, edited in place; Save writes it.
class CharacterEditor extends StatefulWidget {
  const CharacterEditor({
    super.key,
    required this.character,
    required this.system,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
  });

  final Character character;

  /// Its system's pack; null when this user hasn't got it.
  final SystemPack? system;
  final Future<void> Function(Character c) onSave;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<CharacterEditor> createState() => _CharacterEditorState();
}

class _CharacterEditorState extends State<CharacterEditor> {
  late var _c = widget.character;
  late final _name = TextEditingController(text: _c.name);
  var _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name your character.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _c = _c.copyWith(name: name);
      await widget.onSave(_c);
      if (mounted) setState(() => _dirty = false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = widget.system?.sheet;
    return HubPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 28,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
            Expanded(
              child: HubTitle(_c.name,
                  overline: 'Character · ${widget.system?.name ?? _c.system}'),
            ),
            CvButton(
              label: 'Delete',
              icon: Lucide.trash2,
              variant: CvButtonVariant.dangerGhost,
              onPressed: widget.onDelete,
            ),
            CvButton(
              label: _dirty ? 'Close without saving' : 'Close',
              variant: CvButtonVariant.ghost,
              onPressed: widget.onClose,
            ),
            CvButton(
              label: _saving ? 'Saving…' : _dirty ? 'Save' : 'Saved',
              icon: Lucide.check,
              variant: CvButtonVariant.primary,
              onPressed: _saving || !_dirty ? null : _save,
            ),
          ]),
          if (_error case final error?)
            Text(error, style: CvTypography.bodySm.copyWith(color: CvColors.textDanger)),
          CvPanel(
            solid: true,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 24,
              children: [
                SizedBox(
                  width: 400,
                  child: CvTextInput(
                    controller: _name,
                    label: 'Name',
                    maxLength: Character.maxName,
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
                if (sheet == null)
                  Text(
                      'Install ${_c.system} from the Systems page to see '
                      'this sheet.',
                      style: CvTypography.body.copyWith(color: CvColors.textSecondary))
                else
                  SheetView(
                    pack: widget.system!,
                    character: _c,
                    onChanged: (c) => setState(() {
                      _c = c;
                      _dirty = true;
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
