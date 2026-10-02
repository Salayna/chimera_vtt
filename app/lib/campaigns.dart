import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'room.dart' show newRoomCode;
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
            .order('created_at'))
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
