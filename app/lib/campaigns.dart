import 'dart:async';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart' show Session, TableEvent;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'assets.dart';
import 'library.dart' show LibraryThumb;
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

  Future<void> rename(String id, String name) =>
      _client.from('campaigns').update({'name': name}).eq('id', id);

  /// Deletes the campaign with its scenes, members and log.
  Future<void> delete(String id) =>
      _client.from('campaigns').delete().eq('id', id);

  /// Every campaign with its size, and its live scene's map thumbnail when
  /// the map is in the library.
  Future<List<CampaignSummary>> summaries() async {
    // A scene's settings are always its first entity (Scene.entities).
    final rows = await _client
        .from('campaigns')
        .select('id, name, room_code, scenes!scenes_campaign_fkey(count), '
            'members(count), '
            'live:scenes!campaigns_live_scene_fkey(map:data->entities->0->>map)')
        .order('created_at', ascending: true);
    final maps = {
      for (final r in rows)
        if (r['live'] case {'map': final String map}) r['id'] as String: map,
    };
    final thumbs = maps.isEmpty
        ? const <String, String>{}
        : {
            for (final r in await _client
                .from('library')
                .select('asset, thumb')
                .eq('kind', 'map')
                .inFilter('asset', maps.values.toSet().toList()))
              r['asset'] as String: r['thumb'] as String,
          };
    int count(Object? embedded) => (embedded as List).first['count'] as int;
    return [
      for (final r in rows)
        (
          campaign: _row(r),
          scenes: count(r['scenes']),
          players: count(r['members']),
          thumb: switch (thumbs[maps[r['id']]]) {
            final String t => AssetId(t),
            null => null,
          },
        ),
    ];
  }

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

/// A campaign as the GM's home shows it.
typedef CampaignSummary = ({
  Campaign campaign,
  int scenes,
  int players,
  AssetId? thumb,
});

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

/// The signed-in GM's campaigns as cards: open one, start one, rename it,
/// change its code or delete it.
class CampaignsPage extends StatefulWidget {
  const CampaignsPage({
    super.key,
    required this.client,
    required this.assets,
    required this.onOpen,
  });

  final SupabaseClient client;
  final AssetStore assets;
  final void Function(Campaign campaign) onOpen;

  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  late final _campaigns = Campaigns(widget.client);
  final _name = TextEditingController();
  List<CampaignSummary>? _list;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Runs [action], then reloads the cards.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final list = await _campaigns.summaries();
      if (mounted) setState(() => _list = list);
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

  Future<bool> _confirm({
    required String title,
    required Lucide icon,
    required String body,
    required String action,
    bool danger = false,
  }) async =>
      await showCvDialog<bool>(
        context: context,
        title: title,
        icon: icon,
        tone: danger ? CvTone.danger : CvTone.neutral,
        body: Text(body),
        actions: (context) => [
          CvButton(
              label: 'Cancel',
              variant: CvButtonVariant.ghost,
              onPressed: () => Navigator.pop(context, false)),
          CvButton(
              label: action,
              variant: danger ? CvButtonVariant.danger : CvButtonVariant.primary,
              onPressed: () => Navigator.pop(context, true)),
        ],
      ) ??
      false;

  Future<void> _changeCode(Campaign c) async {
    if (await _confirm(
        title: 'Change the room code?',
        icon: Lucide.refreshCw,
        body: '${c.code} stops working. Share the new code with the players '
            'you want to keep.',
        action: 'Change code')) {
      await _run(() => _campaigns.changeCode(c.id));
    }
  }

  Future<void> _rename(Campaign c) async {
    final text = TextEditingController(text: c.name);
    final name = await showCvDialog<String>(
      context: context,
      title: 'Rename ${c.name}',
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
    if (trimmed.isEmpty || trimmed == c.name) return;
    await _run(() => _campaigns.rename(c.id, trimmed));
  }

  Future<void> _delete(Campaign c) async {
    if (await _confirm(
        title: 'Delete ${c.name}?',
        icon: Lucide.trash2,
        body: 'Its scenes, players and log go with it, for good. Your '
            'library keeps its maps, tokens and scenes.',
        action: 'Delete campaign',
        danger: true)) {
      await _run(() => _campaigns.delete(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: CvSpacing.s6,
      children: [
        Wrap(
          spacing: CvSpacing.s4,
          runSpacing: CvSpacing.s4,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            SizedBox(
              width: 320,
              child: CvTextInput(
                controller: _name,
                label: list?.isEmpty ?? true ? 'Your first campaign' : 'New campaign',
                placeholder: 'Curse of the Crimson Tide',
                maxLength: 80,
                onSubmitted: (_) => _create(),
              ),
            ),
            CvButton(
              label: 'Create campaign',
              icon: Lucide.plus,
              variant: CvButtonVariant.primary,
              onPressed: _busy ? null : _create,
            ),
          ],
        ),
        if (_error case final error?)
          Text(error, style: CvTypography.bodySm.copyWith(color: CvColors.textDanger)),
        if (list == null)
          if (_error == null)
            const Center(child: CvSpinner(size: 20, color: CvColors.amber500))
          else
            const SizedBox()
        else if (list.isEmpty)
          Text('Name your first campaign to start preparing scenes.',
              style: CvTypography.body.copyWith(color: CvColors.textSecondary))
        else
          Wrap(spacing: CvSpacing.s6, runSpacing: CvSpacing.s6, children: [
            for (final s in list)
              _CampaignCard(
                summary: s,
                assets: widget.assets,
                busy: _busy,
                onOpen: () => widget.onOpen(s.campaign),
                onRename: () => _rename(s.campaign),
                onChangeCode: () => _changeCode(s.campaign),
                onDelete: () => _delete(s.campaign),
              ),
          ]),
      ],
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.summary,
    required this.assets,
    required this.busy,
    required this.onOpen,
    required this.onRename,
    required this.onChangeCode,
    required this.onDelete,
  });

  final CampaignSummary summary;
  final AssetStore assets;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onChangeCode;
  final VoidCallback onDelete;

  static String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final c = summary.campaign;
    return CvPanel(
      width: 280,
      solid: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 140,
            child: Stack(fit: StackFit.expand, children: [
              LibraryThumb(assets: assets, thumb: summary.thumb),
              if (summary.thumb == null)
                const Center(
                    child: CvIcon(Lucide.layers, color: CvColors.textDisabled)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(CvSpacing.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: CvSpacing.s2,
              children: [
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CvTypography.weight(CvTypography.body, 600)
                        .copyWith(fontSize: 16)),
                Text(
                    '${_count(summary.scenes, 'scene')} · '
                    '${_count(summary.players, 'player')}',
                    style: CvTypography.caption
                        .copyWith(color: CvColors.textSecondary)),
                const SizedBox(height: CvSpacing.s4),
                Row(spacing: 2, children: [
                  Text(c.code,
                      style: CvTypography.label.copyWith(
                          fontFamily: CvTypography.mono,
                          color: CvColors.textSecondary)),
                  const Spacer(),
                  CvToolButton(
                    icon: Lucide.pencil,
                    label: 'Rename',
                    tooltipSide: AxisDirection.up,
                    onPressed: busy ? null : onRename,
                  ),
                  CvToolButton(
                    icon: Lucide.refreshCw,
                    label: 'Change room code',
                    tooltipSide: AxisDirection.up,
                    onPressed: busy ? null : onChangeCode,
                  ),
                  CvToolButton(
                    icon: Lucide.trash2,
                    label: 'Delete campaign',
                    danger: true,
                    tooltipSide: AxisDirection.up,
                    onPressed: busy ? null : onDelete,
                  ),
                ]),
                const SizedBox(height: CvSpacing.s2),
                CvButton(
                  label: 'Open',
                  icon: Lucide.logIn,
                  variant: CvButtonVariant.primary,
                  block: true,
                  onPressed: busy ? null : onOpen,
                ),
              ],
            ),
          ),
        ],
      ),
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
