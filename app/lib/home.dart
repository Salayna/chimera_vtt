import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'assets.dart';
import 'campaigns.dart';
import 'library.dart';
import 'room.dart';
import 'theme.dart';
import 'ui/cv.dart';

enum _Page { campaigns, library, join }

/// A signed-in GM's home, outside any room: their campaigns, their library,
/// and joining someone else's room as a player.
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

  /// From a join link: opens on joining, with the code filled in.
  final String? code;

  @override
  State<GmHome> createState() => _GmHomeState();
}

class _GmHomeState extends State<GmHome> {
  late var _page = (widget.code ?? '').isEmpty ? _Page.campaigns : _Page.join;
  late final _library = Library(widget.client, widget.assets);

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (_page) {
      _Page.campaigns => (
          'Your campaigns',
          'Open one to run its room. Players join with its room code.'
        ),
      _Page.library => (
          'Your library',
          'Maps, token images and scenes, shared by all your campaigns.'
        ),
      _Page.join => ('Join a room', "Sit at someone else's table as a player."),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: CvSpacing.s8, vertical: CvSpacing.s5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: CvColors.borderSubtle)),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: CvSpacing.s6,
          runSpacing: CvSpacing.s4,
          children: [
            const CvWordmark(),
            SizedBox(
              width: 420,
              child: CvSegmentedControl(
                segments: const [
                  (
                    value: _Page.campaigns,
                    label: 'Campaigns',
                    icon: Lucide.crown,
                    checked: CvColors.textGm
                  ),
                  (
                    value: _Page.library,
                    label: 'Library',
                    icon: Lucide.layers,
                    checked: null
                  ),
                  (
                    value: _Page.join,
                    label: 'Join a room',
                    icon: Lucide.logIn,
                    checked: CvColors.textPlayer
                  ),
                ],
                value: _page,
                onChanged: (p) => setState(() => _page = p),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, spacing: CvSpacing.s4, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(widget.email ?? 'GM',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CvTypography.caption
                        .copyWith(color: CvColors.textSecondary)),
              ),
              CvButton(
                label: 'Sign out',
                icon: Lucide.logOut,
                variant: CvButtonVariant.ghost,
                small: true,
                onPressed: widget.client.auth.signOut,
              ),
            ]),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CvSpacing.s8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: CvTypography.display),
                  const SizedBox(height: CvSpacing.s3),
                  Text(subtitle,
                      style: CvTypography.body.copyWith(
                          fontSize: 16, color: CvColors.textSecondary)),
                  const SizedBox(height: CvSpacing.s8),
                  switch (_page) {
                    _Page.campaigns => CampaignsPage(
                        client: widget.client,
                        assets: widget.assets,
                        onOpen: (c) => widget.onEnter(
                            (code: c.code, gm: true, campaign: c.id)),
                      ),
                    _Page.library =>
                      LibraryPage(library: _library, assets: widget.assets),
                    _Page.join => Align(
                        alignment: Alignment.topLeft,
                        child: CvPanel(
                          width: 360,
                          padding: const EdgeInsets.all(CvSpacing.s8),
                          child: JoinRoomForm(
                              client: widget.client,
                              onEnter: widget.onEnter,
                              code: widget.code),
                        ),
                      ),
                  },
                ],
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
