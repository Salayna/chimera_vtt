import 'dart:async';

import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart' show Session, TableEvent;
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart' show builtInPacks;
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'assets.dart';
import 'members.dart' show Member, memberColor;
import 'packs.dart' show InstalledPacks;
import 'room.dart' show newRoomCode;
import 'table/chrome.dart' show TextKeysOnly;
import 'theme.dart';
import 'ui/cv.dart';
import 'ui/hub.dart';

/// A GM's campaign, as the lobby lists it.
typedef Campaign = ({String id, String name, String code, String system});

/// The signed-in GM's campaigns, in Postgres behind row-level security:
/// a GM only ever sees their own.
class Campaigns {
  Campaigns(this._client);

  final SupabaseClient _client;

  static const _fields = 'id, name, room_code, system';

  static Campaign _row(Map<String, dynamic> r) => (
        id: r['id'] as String,
        name: r['name'] as String,
        code: r['room_code'] as String,
        system: r['system'] as String,
      );

  Future<List<Campaign>> list() async => [
        for (final r in await _client
            .from('campaigns')
            .select(_fields)
            .order('created_at', ascending: true))
          _row(r),
      ];

  /// A new campaign played with [system], a pack id.
  Future<Campaign> create(String name, {String system = 'generic'}) =>
      _withNewCode((code) async => _row(await _client
          .from('campaigns')
          .insert({'name': name, 'room_code': code, 'system': system})
          .select(_fields)
          .single()));

  /// The system [id] is played with, by pack id.
  Future<String> system(String id) async => (await _client
      .from('campaigns')
      .select('system')
      .eq('id', id)
      .single())['system'] as String;

  /// Every scene of the campaign then plays with [system]; the room puts
  /// each on it as it opens.
  Future<void> setSystem(String id, String system) =>
      _client.from('campaigns').update({'system': system}).eq('id', id);

  /// A new room code: anyone holding the old one can't join any more.
  Future<Campaign> changeCode(String id) => _withNewCode((code) async => _row(
      await _client
          .from('campaigns')
          .update({'room_code': code})
          .eq('id', id)
          .select(_fields)
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
        .select('$_fields, scenes!scenes_campaign_fkey(count), '
            'members(name, color), '
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
          players: [
            for (final m in r['members'] as List)
              (name: m['name'] as String, color: m['color'] as int),
          ],
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
  List<Member> players,
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

/// The signed-in GM's home page (design: hub/home): a greeting, then their
/// campaigns as cover cards. Open one, start one, rename it, change its code
/// or delete it.
// ponytail: no "next session" hero or Running/Playing filter: sessions
// aren't scheduled yet, and a GM's own campaigns are the only ones listed.
class CampaignsPage extends StatefulWidget {
  const CampaignsPage({
    super.key,
    required this.client,
    required this.assets,
    required this.onOpen,
    required this.onJoin,
  });

  final SupabaseClient client;
  final AssetStore assets;
  final void Function(Campaign campaign) onOpen;

  /// Opens the top bar's join popover.
  final VoidCallback onJoin;

  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  late final _campaigns = Campaigns(widget.client);
  late final _installed = InstalledPacks(widget.client);
  List<CampaignSummary>? _list;

  /// The systems a campaign can be played with, by pack id: the built-in
  /// ones, then the GM's installed ones.
  Map<String, String> _systems = {
    for (final p in builtInPacks.values) p.id: p.name,
  };
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  /// Runs [action], then reloads the cards.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final (list, installed) =
          await (_campaigns.summaries(), _installed.list()).wait;
      if (mounted) {
        setState(() {
          _list = list;
          _systems = {
            for (final p in builtInPacks.values) p.id: p.name,
            for (final p in installed) p.id: p.name,
          };
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for a name: [title] for a new campaign, or renaming [current].
  Future<String?> _askName(String title, {String current = ''}) async {
    final text = TextEditingController(text: current);
    final name = await showCvDialog<String>(
      context: context,
      title: title,
      icon: current.isEmpty ? Lucide.plus : Lucide.pencil,
      body: CvTextInput(
        controller: text,
        label: 'Name',
        placeholder: 'Curse of the Crimson Tide',
        maxLength: 80,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context)),
        CvButton(
            label: current.isEmpty ? 'Create campaign' : 'Rename',
            variant: CvButtonVariant.primary,
            onPressed: () => Navigator.pop(context, text.text)),
      ],
    );
    // Not disposed: the dialog still shows it while it animates away.
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty || trimmed == current ? null : trimmed;
  }

  /// A system's name, or its id when it's no longer installed.
  String _systemName(String id) => _systems[id] ?? id;

  /// The systems to choose from, with [current] even if it's gone.
  List<CvMenuEntry<String>> _systemEntries(String current) => [
        for (final MapEntry(key: id, value: name) in _systems.entries)
          CvMenuItem(id, name),
        if (!_systems.containsKey(current)) CvMenuItem(current, current),
      ];

  Future<void> _create() async {
    final text = TextEditingController();
    var system = 'generic';
    final created = await showCvDialog<bool>(
      context: context,
      title: 'New campaign',
      icon: Lucide.plus,
      body: StatefulBuilder(
        builder: (context, setDialog) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            CvTextInput(
              controller: text,
              label: 'Name',
              placeholder: 'Curse of the Crimson Tide',
              maxLength: 80,
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
            CvDropdown<String>(
              label: 'System',
              value: system,
              entries: _systemEntries(system),
              onChanged: (v) => setDialog(() => system = v),
            ),
            Text('Every scene in the campaign plays with it. Install more '
                'systems from the Systems page.',
                style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
          ],
        ),
      ),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Create campaign',
            variant: CvButtonVariant.primary,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    // Not disposed: the dialog still shows it while it animates away.
    final name = text.text.trim();
    if (!(created ?? false) || name.isEmpty) return;
    await _run(() async =>
        widget.onOpen(await _campaigns.create(name, system: system)));
  }

  Future<void> _changeSystem(Campaign c) async {
    var system = c.system;
    final changed = await showCvDialog<bool>(
      context: context,
      title: 'System for ${c.name}',
      icon: Lucide.puzzle,
      body: StatefulBuilder(
        builder: (context, setDialog) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            CvDropdown<String>(
              label: 'System',
              value: system,
              entries: _systemEntries(system),
              onChanged: (v) => setDialog(() => system = v),
            ),
            Text('Each scene switches to it as it opens. Conditions and '
                'trackers the old system set stay on tokens.',
                style: CvTypography.caption.copyWith(color: CvColors.textSecondary)),
          ],
        ),
      ),
      actions: (context) => [
        CvButton(
            label: 'Cancel',
            variant: CvButtonVariant.ghost,
            onPressed: () => Navigator.pop(context, false)),
        CvButton(
            label: 'Change system',
            variant: CvButtonVariant.primary,
            onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if ((changed ?? false) && system != c.system) {
      await _run(() => _campaigns.setSystem(c.id, system));
    }
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

  Future<void> _act(Campaign c, _CardAction action) async {
    switch (action) {
      case _CardAction.system:
        await _changeSystem(c);
      case _CardAction.rename:
        final name = await _askName('Rename ${c.name}', current: c.name);
        if (name != null) await _run(() => _campaigns.rename(c.id, name));
      case _CardAction.changeCode:
        if (await _confirm(
            title: 'Change the room code?',
            icon: Lucide.refreshCw,
            body: '${c.code} stops working. Share the new code with the '
                'players you want to keep.',
            action: 'Change code')) {
          await _run(() => _campaigns.changeCode(c.id));
        }
      case _CardAction.delete:
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
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list != null && list.isEmpty) return _empty();
    return HubPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 40,
        children: [
          HubTitle(_greeting(DateTime.now()), overline: _date(DateTime.now())),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 20,
            children: [
              Text('Your campaigns',
                  style: CvTypography.title.copyWith(fontSize: 20, height: 28 / 20)),
              if (_error case final error?)
                Text(error,
                    style: CvTypography.bodySm.copyWith(color: CvColors.textDanger)),
              if (list == null)
                if (_error == null)
                  const Center(child: CvSpinner(size: 20, color: CvColors.amber500))
                else
                  const SizedBox()
              else
                LayoutBuilder(builder: (context, constraints) {
                  const gap = 20.0;
                  final columns = hubColumns(constraints.maxWidth, 280, gap, 3);
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(spacing: gap, runSpacing: gap, children: [
                    for (final s in list)
                      SizedBox(
                        width: width,
                        height: _CampaignCard.height,
                        child: _CampaignCard(
                          summary: s,
                          system: _systemName(s.campaign.system),
                          assets: widget.assets,
                          onOpen: _busy ? null : () => widget.onOpen(s.campaign),
                          onAction: (a) => _act(s.campaign, a),
                        ),
                      ),
                    SizedBox(
                      width: width,
                      height: _CampaignCard.height,
                      child: HubCard(
                        dashed: true,
                        label: 'New campaign',
                        onTap: _busy ? null : _create,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 10,
                          children: [
                            Builder(
                              builder: (context) => CvIcon(Lucide.plus,
                                  size: 24,
                                  color: DefaultTextStyle.of(context).style.color),
                            ),
                            const Text('New campaign',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ]);
                }),
            ],
          ),
        ],
      ),
    );
  }

  /// No campaign yet: start one, or join a friend's table.
  Widget _empty() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: SizedBox(
            width: 520,
            child: Column(spacing: 16, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(CvRadii.lg),
                child: const SizedBox(
                    height: 200, child: HubCover(seed: 'No campaigns yet')),
              ),
              Text('No campaigns yet',
                  style: CvTypography.titleLg.copyWith(fontSize: 28, height: 36 / 28)),
              Text(
                "Start one as the GM, or join a friend's table with the room "
                'code they send you.',
                textAlign: TextAlign.center,
                style: CvTypography.body.copyWith(color: CvColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
                CvButton(
                  label: 'New campaign',
                  icon: Lucide.plus,
                  variant: CvButtonVariant.primary,
                  onPressed: _busy ? null : _create,
                ),
                CvButton(
                  label: 'Join with code',
                  icon: Lucide.logIn,
                  onPressed: widget.onJoin,
                ),
              ]),
            ]),
          ),
        ),
      );
}

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];

/// "Friday 3 October".
String _date(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _greeting(DateTime d) => switch (d.hour) {
      < 5 || >= 18 => 'Good evening',
      < 12 => 'Good morning',
      _ => 'Good afternoon',
    };

enum _CardAction { rename, system, changeCode, delete }

/// A campaign as a cover card: its live map (or stand-in art), its name,
/// scenes and room code, its players' faces, and a menu of changes.
class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.summary,
    required this.system,
    required this.assets,
    required this.onOpen,
    required this.onAction,
  });

  static const height = 312.0;

  final CampaignSummary summary;

  /// The name of the system it's played with.
  final String system;
  final AssetStore assets;
  final VoidCallback? onOpen;
  final ValueChanged<_CardAction> onAction;

  static String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final c = summary.campaign;
    final players = summary.players;
    return HubCard(
      label: 'Open ${c.name}',
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 172,
            child: Stack(fit: StackFit.expand, children: [
              if (summary.thumb case final thumb?)
                _Thumb(assets: assets, thumb: thumb, seed: c.id)
              else
                HubCover(seed: c.id),
              const Positioned(left: 12, top: 12, child: HubRoleBadge()),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 6,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CvTypography.title),
                  ),
                  Row(spacing: 6, children: [
                    const CvIcon(Lucide.layers,
                        size: 14, color: CvColors.amber500),
                    Text(_count(summary.scenes, 'scene'),
                        style: CvTypography.bodySm),
                    Text('·',
                        style: CvTypography.bodySm
                            .copyWith(color: CvColors.textSecondary)),
                    Text(c.code,
                        style: CvTypography.bodySm.copyWith(
                            fontFamily: CvTypography.mono,
                            color: CvColors.textSecondary)),
                  ]),
                  Row(spacing: 6, children: [
                    const CvIcon(Lucide.puzzle,
                        size: 14, color: CvColors.textSecondary),
                    Flexible(
                      child: Text(system,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CvTypography.bodySm
                              .copyWith(color: CvColors.textSecondary)),
                    ),
                  ]),
                  const Spacer(),
                  Row(children: [
                    if (players.isEmpty)
                      Text('No players yet',
                          style: CvTypography.caption
                              .copyWith(color: CvColors.textSecondary))
                    else
                      CvAvatarStack(
                          caption: players.length == 1 ? 'player' : 'players',
                          avatars: [
                        for (final p in players)
                          CvAvatar(
                            initials: p.name
                                .substring(0, p.name.length < 2 ? p.name.length : 2)
                                .toUpperCase(),
                            color: memberColor(p.color),
                            size: 26,
                            label: p.name,
                          ),
                      ]),
                    const Spacer(),
                    _CardMenu(name: c.name, onAction: onAction),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A campaign's live-map thumbnail, over its stand-in art while it loads.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.assets, required this.thumb, required this.seed});

  final AssetStore assets;
  final AssetId thumb;
  final String seed;

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: assets.image(thumb),
        builder: (context, snapshot) => snapshot.data == null
            ? HubCover(seed: seed)
            : RawImage(image: snapshot.data, fit: BoxFit.cover),
      );
}

/// The ⋯ on a campaign card: rename, change the code, delete.
class _CardMenu extends StatefulWidget {
  const _CardMenu({required this.name, required this.onAction});

  final String name;
  final ValueChanged<_CardAction> onAction;

  @override
  State<_CardMenu> createState() => _CardMenuState();
}

class _CardMenuState extends State<_CardMenu> {
  final _open = ValueNotifier(false);

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HubPopover(
        open: _open,
        anchor: CvToolButton(
          icon: Lucide.ellipsis,
          label: 'More for ${widget.name}',
          tooltipSide: AxisDirection.up,
          onPressed: () => _open.value = !_open.value,
        ),
        popover: CvMenu<_CardAction>(
          entries: const [
            CvMenuItem(_CardAction.rename, 'Rename',
                leading: CvIcon(Lucide.pencil,
                    size: CvSizes.iconSm, color: CvColors.textSecondary)),
            CvMenuItem(_CardAction.system, 'Change system',
                leading: CvIcon(Lucide.puzzle,
                    size: CvSizes.iconSm, color: CvColors.textSecondary)),
            CvMenuItem(_CardAction.changeCode, 'Change room code',
                leading: CvIcon(Lucide.refreshCw,
                    size: CvSizes.iconSm, color: CvColors.textSecondary)),
            CvMenuDivider(),
            CvMenuItem(_CardAction.delete, 'Delete campaign',
                leading: CvIcon(Lucide.trash2,
                    size: CvSizes.iconSm, color: CvColors.textDanger)),
          ],
          onSelected: (a) {
            _open.value = false;
            widget.onAction(a);
          },
        ),
      );
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
    this.onExport,
    this.onImport,
    this.onFromLibrary,
    this.fromLibraryOpen = false,
  });

  final List<SceneEntry> scenes;
  final VoidCallback? onSaveToLibrary;

  /// The live scene to a file, or a file into the live scene (E and I).
  final VoidCallback? onExport;
  final VoidCallback? onImport;
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
            if (onExport != null || onImport != null)
              Row(spacing: 6, children: [
                Expanded(
                  child: CvButton(
                    label: 'Export',
                    icon: Lucide.download,
                    variant: CvButtonVariant.ghost,
                    small: true,
                    block: true,
                    onPressed: onExport,
                  ),
                ),
                Expanded(
                  child: CvButton(
                    label: 'Import',
                    icon: Lucide.upload,
                    variant: CvButtonVariant.ghost,
                    small: true,
                    block: true,
                    onPressed: onImport,
                  ),
                ),
              ]),
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
