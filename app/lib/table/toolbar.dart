import 'package:chimera_core/chimera_core.dart';
import 'package:chimera_sync/chimera_sync.dart';
import 'package:flutter/material.dart';

import 'table_view.dart';

/// The GM's tools: move or paint fog, cover or reveal, add a token.
class GmToolbar extends StatefulWidget {
  const GmToolbar({super.key, required this.controller, this.onAddToken});

  final TableController controller;
  final VoidCallback? onAddToken;

  @override
  State<GmToolbar> createState() => _GmToolbarState();
}

class _GmToolbarState extends State<GmToolbar> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<Tool>(
          segments: const [
            ButtonSegment(
                value: Tool.move, icon: Icon(Icons.pan_tool), label: Text('Move')),
            ButtonSegment(
                value: Tool.fogBrush, icon: Icon(Icons.brush), label: Text('Brush')),
            ButtonSegment(
                value: Tool.fogRect,
                icon: Icon(Icons.crop_square),
                label: Text('Rect')),
          ],
          selected: {c.tool},
          onSelectionChanged: (s) => setState(() => c.tool = s.single),
        ),
        SegmentedButton<FogMode>(
          segments: const [
            ButtonSegment(value: FogMode.cover, label: Text('Cover')),
            ButtonSegment(value: FogMode.reveal, label: Text('Reveal')),
          ],
          selected: {c.fogMode},
          onSelectionChanged: (s) => setState(() => c.fogMode = s.single),
        ),
        FilterChip(
          label: const Text('Snap'),
          tooltip: 'Snap dropped tokens to the grid. Hold Alt to place freely.',
          selected: c.snap,
          onSelected: (snap) => setState(() => c.snap = snap),
        ),
        if (widget.onAddToken != null)
          FilledButton.tonalIcon(
            onPressed: widget.onAddToken,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Token'),
          ),
      ],
    );
  }
}

/// Owner, visibility and removal of the selected token, for the GM.
class TokenPanel extends StatelessWidget {
  const TokenPanel({
    super.key,
    required this.token,
    required this.players,
    required this.send,
  });

  final Token token;

  /// Connected players, to pick an owner from.
  final List<PlayerId> players;
  final Outcome Function(Command) send;

  @override
  Widget build(BuildContext context) {
    final owners = {...players, ?token.owner}.toList();
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<PlayerId?>(
          value: token.owner,
          hint: const Text('No owner'),
          items: [
            const DropdownMenuItem(value: null, child: Text('No owner')),
            for (final p in owners)
              DropdownMenuItem(value: p, child: Text('Player ${shortId(p)}')),
          ],
          onChanged: (owner) => send(AssignOwner(token.id, owner)),
        ),
        FilterChip(
          label: const Text('Hidden'),
          selected: token.hidden,
          onSelected: (hidden) => send(SetTokenHidden(token.id, hidden)),
        ),
        IconButton(
          tooltip: 'Remove token',
          onPressed: () => send(RemoveToken(token.id)),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

/// Who is connected, from presence.
class PeerList extends StatelessWidget {
  const PeerList({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: session.peers,
        initialData: session.currentPeers,
        builder: (context, snapshot) => Wrap(spacing: 6, children: [
          for (final p in snapshot.requireData)
            Chip(
              avatar: Icon(p.gm ? Icons.star : Icons.person, size: 16),
              label: Text(
                  '${p.gm ? 'GM' : 'Player ${shortId(PlayerId(p.player))}'}'
                  '${p.player == session.self.value ? ' (you)' : ''}'),
            ),
        ]),
      );
}

/// Enough of a player id to tell players apart, until players have names.
String shortId(PlayerId id) => id.value.substring(0, 4);
