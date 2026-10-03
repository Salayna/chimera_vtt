import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'assets.dart';
import 'campaigns.dart';
import 'library.dart';
import 'packs.dart';
import 'room.dart';
import 'theme.dart';
import 'ui/hub.dart';

/// A signed-in GM's home, outside any room: their campaigns and their
/// library under the hub's top bar, and joining someone else's room as a
/// player from the bar.
class GmHome extends StatefulWidget {
  const GmHome({
    super.key,
    required this.client,
    required this.assets,
    required this.email,
    required this.onEnter,
    this.code,
  });

  final SupabaseClient client;
  final AssetStore assets;
  final String? email;
  final void Function(SavedRoom room) onEnter;

  /// From a join link: opens the join popover, with the code filled in.
  final String? code;

  @override
  State<GmHome> createState() => _GmHomeState();
}

class _GmHomeState extends State<GmHome> {
  var _tab = HubTab.campaigns;
  late final _library = Library(widget.client, widget.assets);
  late final _joinOpen = ValueNotifier((widget.code ?? '').isNotEmpty);

  @override
  void dispose() {
    _joinOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: CvColors.bgGround,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          HubTopBar(
            tab: _tab,
            onTab: (t) => setState(() => _tab = t),
            joinOpen: _joinOpen,
            join: JoinRoomForm(
                client: widget.client,
                onEnter: widget.onEnter,
                code: widget.code),
            email: widget.email,
            onSignOut: widget.client.auth.signOut,
          ),
          Expanded(
            child: switch (_tab) {
              HubTab.campaigns => CampaignsPage(
                  client: widget.client,
                  assets: widget.assets,
                  onOpen: (c) =>
                      widget.onEnter((code: c.code, gm: true, campaign: c.id)),
                  onJoin: () => _joinOpen.value = true,
                ),
              HubTab.library =>
                LibraryPage(library: _library, assets: widget.assets),
              HubTab.systems =>
                SystemsPage(packs: InstalledPacks(widget.client)),
            },
          ),
        ]),
      );
}
