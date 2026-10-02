import 'dart:async';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart' show Session, TableEvent;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'room.dart' show newRoomCode;
import 'table/chrome.dart' show TextKeysOnly;
import 'theme.dart';
import 'ui/cv.dart';

/// A GM's campaign, as the lobby lists it.
typedef Campaign = ({String id, String name, String code});

/// The signed-in GM's campaigns, in Postgres behind row-level security:
/// a GM only ever sees their own.
class Campaigns {
  Campaigns(this._client);

  final SupabaseClient _client;

  static Campaign _row(Map<String, dynamic> r) =>
      (id: r['id'] as String, name: r['name'] as String, code: r['room_code'] as String);

  Future<List<Campaign>> list() async => [
        for (final r in await _client
            .from('campaigns')
            .select('id, name, room_code')
            .order('created_at', ascending: true))
          _row(r),
      ];

  Future<Campaign> create(String name) => _withNewCode((code) async => _row(
      await _client
          .from('campaigns')
          .insert({'name': name, 'room_code': code})
          .select('id, name, room_code')
          .single()));

  /// A new room code: anyone holding the old one can't join any more.
  Future<Campaign> changeCode(String id) => _withNewCode((code) async => _row(
      await _client
          .from('campaigns')
          .update({'room_code': code})
          .eq('id', id)
          .select('id, name, room_code')
          .single()));

  /// Codes are random, so one can already be taken: try another.
  static Future<T> _withNewCode<T>(Future<T> Function(String code) write) async {
    for (var attempt = 1;; attempt++) {
      try {
        return await write(newRoomCode());
      } on PostgrestException catch (e) {
        if (e.code != '23505' || attempt == 5) rethrow; // unique_violation
      }
    }
  }
}

/// A scene in a campaign's list.
typedef SceneEntry = ({String id, String name});

/// A campaign's scenes in Postgres, readable only by the campaign's GM.
/// [Scene]s are stored as the same JSON as a scene file.
class Scenes {
  Scenes(this._client, this.campaign);

  final SupabaseClient _client;
  final String campaign;

  Future<List<SceneEntry>> list() async => [
        for (final r in await _client
            .from('scenes')
            .select('id, name')
            .eq('campaign', campaign)
            .order('created_at', ascending: true))
          (id: r['id'] as String, name: r['name'] as String),
      ];

  Future<Scene> load(String id) async {
    final row =
        await _client.from('scenes').select('data').eq('id', id).single();
    return Scene.fromJson(row['data'] as Json);
  }

  Future<String> create(String name, Scene scene) async {
    final row = await _client
        .from('scenes')
        .insert({'campaign': campaign, 'name': name, 'data': scene.toJson()})
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> save(String id, Scene scene) => _client.from('scenes').update({
        'data': scene.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', id);

  Future<void> rename(String id, String name) =>
      _client.from('scenes').update({'name': name}).eq('id', id);

  Future<void> delete(String id) => _client.from('scenes').delete().eq('id', id);

  /// The scene reopening the campaign resumes, if one was set.
  Future<String?> live() async {
    final row = await _client
        .from('campaigns')
        .select('live_scene')
        .eq('id', campaign)
        .single();
    return row['live_scene'] as String?;
  }

  Future<void> setLive(String id) =>
      _client.from('campaigns').update({'live_scene': id}).eq('id', campaign);
}

/// A campaign's log in Postgres, readable only by the campaign's GM, secret
/// rolls included. Entries are events as JSON, the same as on the wire.
// ponytail: entries are never pruned; trim old ones if a campaign's log
// grows large enough to matter.
class LogEntries {
  LogEntries(this._client, this.campaign);

  final SupabaseClient _client;
  final String campaign;
  Future<void> _last = Future.value();

  /// The latest entries, oldest first. Entries this app can't read any more
  /// are skipped.
  Future<List<TableEvent>> recent() async {
    final rows = await _client
        .from('log_entries')
        .select('event')
        .eq('campaign', campaign)
        .order('id', ascending: false)
        .limit(Session.logLimit);
    return [
      for (final r in rows.reversed)
        ?_tryEvent(r['event'] as Json),
    ];
  }

  /// Stores [event] after any still being stored, so ids keep the log's
  /// order. A failure is reported to [onError] and doesn't stop later ones.
  void add(TableEvent event, {required void Function(Object) onError}) =>
      _last = _last.then((_) => _client.from('log_entries').insert({
            'campaign': campaign,
            'event': event.toJson(),
            'secret': event.secret,
          })).catchError(onError);

  static TableEvent? _tryEvent(Json json) {
    try {
      return TableEvent.fromJson(json);
    } on Object {
      return null;
    }
  }
}


/// The signed-in GM's campaigns: open one, start one, or change a code.
class CampaignList extends StatefulWidget {
  const CampaignList({super.key, required this.client, required this.onOpen});

  final SupabaseClient client;
  final void Function(Campaign campaign) onOpen;

  @override
  State<CampaignList> createState() => _CampaignListState();
}

class _CampaignListState extends State<CampaignList> {
  late final _campaigns = Campaigns(widget.client);
  final _name = TextEditingController();
  List<Campaign>? _list;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _campaigns.list();
      if (mounted) setState(() => _list = list);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name the campaign.');
      return;
    }
    await _run(() async {
      final campaign = await _campaigns.create(name);
      widget.onOpen(campaign);
    });
  }

  Future<void> _changeCode(Campaign campaign) async {
    final confirmed = await showCvDialog<bool>(
      context: context,
      title: 'Change the room code?',
      icon: Lucide.refreshCw,
      body: Text(
          '${campaign.code} stops working. Share the new code with the '
          'players you want to keep.'),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Change code',
            variant: CvButtonVariant.primary,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (!(confirmed ?? false)) return;
    await _run(() async {
      final changed = await _campaigns.changeCode(campaign.id);
      setState(() => _list = [
            for (final c in _list ?? <Campaign>[]) c.id == changed.id ? changed : c,
          ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: CvSpacing.s4,
      children: [
        if (list == null && _error == null)
          const Center(child: CvSpinner(size: 20, color: CvColors.amber500))
        else
          for (final c in list ?? <Campaign>[])
            Row(spacing: 8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CvTypography.weight(CvTypography.body, 600)),
                  Text(c.code,
                      style: CvTypography.caption.copyWith(
                          fontFamily: CvTypography.mono,
                          color: CvColors.textSecondary)),
                ]),
              ),
              CvToolButton(
                icon: Lucide.refreshCw,
                label: 'Change room code',
                tooltipSide: AxisDirection.up,
                onPressed: _busy ? null : () => _changeCode(c),
              ),
              CvButton(
                label: 'Open',
                variant: CvButtonVariant.primary,
                small: true,
                onPressed: _busy ? null : () => widget.onOpen(c),
              ),
            ]),
        CvTextInput(
          controller: _name,
          label: list?.isEmpty ?? true ? 'Your first campaign' : 'New campaign',
          placeholder: 'Curse of the Crimson Tide',
          maxLength: 80,
          error: _error,
          onSubmitted: (_) => _create(),
        ),
        CvButton(
          label: 'Create campaign',
          icon: Lucide.plus,
          block: true,
          onPressed: _busy ? null : _create,
        ),
      ],
    );
  }
}

/// The campaign's scenes, beside the GM's rail: the live one is what the
/// table sees. Pick another to show it, name the live one, add or delete.
class ScenesPanel extends StatelessWidget {
  const ScenesPanel({
    super.key,
    required this.scenes,
    required this.live,
    required this.onSwitch,
    required this.onNew,
    required this.onRename,
    required this.onDelete,
    this.onSaveToLibrary,
    this.onFromLibrary,
    this.fromLibraryOpen = false,
  });

  final List<SceneEntry> scenes;
  final VoidCallback? onSaveToLibrary;
  final VoidCallback? onFromLibrary;
  final bool fromLibraryOpen;
  final String? live;
  final void Function(String id) onSwitch;
  final VoidCallback onNew;
  final ValueChanged<String> onRename;
  final void Function(SceneEntry scene) onDelete;

  @override
  Widget build(BuildContext context) {
    final current = scenes.where((s) => s.id == live).firstOrNull;
    return CvPopIn(
      child: CvPanel(
        width: 260,
        padding: const EdgeInsets.all(CvSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            const CvOverline('Scenes'),
            for (final s in scenes)
              CvPressable(
                onTap: s.id == live ? null : () => onSwitch(s.id),
                label: s.id == live ? '${s.name}, live' : 'Show ${s.name}',
                builder: (state) => Container(
                  height: CvSizes.hit,
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: s.id == live
                        ? CvColors.amberTint
                        : state.hover
                            ? CvColors.surfaceHover
                            : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(CvRadii.md),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CvTypography.label.copyWith(
                              color: s.id == live
                                  ? CvColors.amber300
                                  : CvColors.textPrimary)),
                    ),
                    if (s.id == live)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text('Live',
                            style: CvTypography.caption
                                .copyWith(color: CvColors.amber400)),
                      )
                    else
                      CvToolButton(
                        icon: Lucide.trash2,
                        label: 'Delete ${s.name}',
                        danger: true,
                        tooltipSide: AxisDirection.up,
                        onPressed: () => onDelete(s),
                      ),
                  ]),
                ),
              ),
            if (current != null)
              _SceneNameField(
                  key: ValueKey(current.id), name: current.name, onRename: onRename),
            CvButton(
              label: 'New scene',
              icon: Lucide.plus,
              small: true,
              block: true,
              onPressed: onNew,
            ),
            if (onFromLibrary != null)
              CvButton(
                label: fromLibraryOpen ? 'Close library' : 'New from library',
                icon: Lucide.layers,
                variant: CvButtonVariant.ghost,
                small: true,
                block: true,
                onPressed: onFromLibrary,
              ),
            if (onSaveToLibrary != null)
              CvButton(
                label: 'Save to library',
                icon: Lucide.download,
                variant: CvButtonVariant.ghost,
                small: true,
                block: true,
                onPressed: onSaveToLibrary,
              ),
          ],
        ),
      ),
    );
  }
}

/// The live scene's name, saved half a second after typing stops.
// ponytail: closing the panel within that half second drops the last edit.
class _SceneNameField extends StatefulWidget {
  const _SceneNameField({super.key, required this.name, required this.onRename});

  final String name;
  final ValueChanged<String> onRename;

  @override
  State<_SceneNameField> createState() => _SceneNameFieldState();
}

class _SceneNameFieldState extends State<_SceneNameField> {
  late final _text = TextEditingController(text: widget.name);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextKeysOnly(
        child: CvTextInput(
          controller: _text,
          label: 'Name',
          maxLength: 80,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 500),
                () => widget.onRename(v.trim()));
          },
        ),
      );
}
