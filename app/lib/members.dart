import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'theme.dart';
import 'ui/cv.dart';

/// A campaign member as the table shows them.
typedef Member = ({String name, int color});

/// The members of the campaign this client is in, by player id: names and
/// colours for avatars, token rings and owner menus.
// ponytail: one global for the one room a client is in at a time. Pass it
// down instead if a client ever shows two campaigns at once.
final members = ValueNotifier<Map<PlayerId, Member>>({});

Color memberColor(int color) => CvColors.players[color % CvColors.players.length];

/// A member's name, or a stand-in from their id.
String playerName(PlayerId id) =>
    members.value[id]?.name ?? 'Player ${id.value.substring(0, 4)}';

/// Enters the campaign with [code] as a member, or updates the name and
/// colour this player already has there. Null when no campaign has the code.
Future<String?> joinCampaign(
        SupabaseClient client, String code, String name, int color) async =>
    await client.rpc('join_campaign',
        params: {'code': code, 'name': name, 'color': color}) as String?;

/// Fills [members] with [campaign]'s members. Row-level security lets the
/// GM and the campaign's members read them.
Future<void> loadMembers(SupabaseClient client, String campaign) async {
  final rows = await client
      .from('members')
      .select('user_id, name, color')
      .eq('campaign', campaign)
      .order('joined_at', ascending: true);
  members.value = {
    for (final r in rows)
      PlayerId(r['user_id'] as String):
          (name: r['name'] as String, color: r['color'] as int),
  };
}

Future<void> removeMember(
        SupabaseClient client, String campaign, PlayerId player) =>
    client
        .from('members')
        .delete()
        .eq('campaign', campaign)
        .eq('user_id', player.value);

/// Swatches for picking a player colour.
class ColorPicker extends StatelessWidget {
  const ColorPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(spacing: 8, children: [
        for (var i = 0; i < CvColors.players.length; i++)
          CvPressable(
            onTap: () => onChanged(i),
            label: 'Colour ${i + 1}',
            toggled: i == value,
            builder: (s) => Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: memberColor(i),
                shape: BoxShape.circle,
                border: Border.all(
                    color: i == value
                        ? CvColors.bone100
                        : s.hover
                            ? CvColors.slate400
                            : const Color(0x00000000),
                    width: 2),
              ),
            ),
          ),
      ]);
}
