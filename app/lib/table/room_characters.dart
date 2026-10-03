import 'dart:async';
import 'dart:convert';

import 'package:chimera_core/chimera_core.dart';
import 'package:flutter/widgets.dart';
import 'package:tactical_engine/tactical_engine.dart';

import '../characters.dart';
import '../sheet_view.dart';
import '../theme.dart';
import '../ui/cv.dart';
import 'rules.dart';

/// A player's characters in the room: bring one of theirs made for the
/// campaign's system, make one here, open a sheet, or take one out.
class CharactersPanel extends StatefulWidget {
  const CharactersPanel({
    super.key,
    required this.store,
    required this.self,
    required this.campaign,
    required this.characters,
    required this.send,
    required this.onOpen,
  });

  final SceneStore store;
  final PlayerId self;
  final String campaign;
  final SavedCharacters characters;
  final Outcome Function(Command) send;
  final ValueChanged<CharacterId> onOpen;

  @override
  State<CharactersPanel> createState() => _CharactersPanelState();
}

class _CharactersPanelState extends State<CharactersPanel> {
  /// This player's characters for the scene's system, from their home.
  List<Character>? _mine;
  String? _system;
  String? _error;
  bool _busy = false;

  Future<void> _load(String system) async {
    _system = system;
    try {
      final mine = await widget.characters.forSystem(system);
      if (mounted) setState(() => _mine = mine);
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

  /// Links [c] to the campaign and brings it to the table.
  Future<void> _bring(Character c, SystemPack pack) => _run(() async {
        await widget.characters.link(widget.campaign, c.id);
        widget.send(UpdateCharacter(cleaned(c, pack)));
        widget.onOpen(c.id);
      });

  Future<void> _create(SystemPack pack) async {
    final name = TextEditingController();
    final made = await showCvDialog<bool>(
      context: context,
      title: 'New character',
      icon: Lucide.plus,
      body: CvTextInput(
        controller: name,
        label: 'Name',
        placeholder: 'Ayla Venn',
        maxLength: Character.maxName,
        onSubmitted: (_) => Navigator.pop(context, true),
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
      final c = await widget.characters.create(n, pack);
      _mine = [...?_mine, c];
      await widget.characters.link(widget.campaign, c.id);
      widget.send(UpdateCharacter(cleaned(c, pack)));
      widget.onOpen(c.id);
    });
  }

  Future<void> _remove(Character c) => _run(() async {
        await widget.characters.unlink(widget.campaign, c.id);
        widget.send(RemoveCharacter(c.id));
      });

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: widget.store.changes,
        initialData: widget.store.scene,
        builder: (context, snapshot) {
          final scene = snapshot.requireData;
          final pack = packOf(scene);
          if (pack.sheet == null) return const SizedBox.shrink();
          if (_system != pack.id) _load(pack.id);
          final here = [
            for (final c in scene.characters.values)
              if (c.owner == widget.self) c,
          ];
          final offered = [
            for (final c in _mine ?? const <Character>[])
              if (!scene.characters.containsKey(c.id)) c,
          ];
          return CvPanel(
            width: 220,
            padding: const EdgeInsets.all(CvSpacing.s3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 4,
              children: [
                const Padding(
                  padding: EdgeInsets.all(CvSpacing.s3),
                  child: CvOverline('Your characters'),
                ),
                for (final c in here)
                  Row(children: [
                    Expanded(
                      child: CvButton(
                        label: c.name,
                        icon: Lucide.userRound,
                        variant: CvButtonVariant.ghost,
                        small: true,
                        onPressed: () => widget.onOpen(c.id),
                      ),
                    ),
                    CvToolButton(
                      icon: Lucide.x,
                      label: 'Take ${c.name} out of the campaign',
                      tooltipSide: AxisDirection.right,
                      onPressed: _busy ? null : () => _remove(c),
                    ),
                  ]),
                if (offered.isNotEmpty)
                  CvDropdown<Character?>(
                    entries: [for (final c in offered) CvMenuItem(c, c.name)],
                    value: null,
                    placeholder: 'Bring a character…',
                    onChanged: (c) {
                      if (c != null && !_busy) _bring(c, pack);
                    },
                  ),
                CvButton(
                  label: 'New character',
                  icon: Lucide.plus,
                  small: true,
                  block: true,
                  onPressed: _busy ? null : () => _create(pack),
                ),
                if (_error case final error?)
                  Text(error,
                      style: CvTypography.caption.copyWith(color: CvColors.textDanger)),
              ],
            ),
          );
        },
      );
}

/// A character's whole sheet, floating over the table. Its owner changes
/// it; everyone else reads it.
class SheetPanel extends StatelessWidget {
  const SheetPanel({
    super.key,
    required this.store,
    required this.id,
    required this.self,
    required this.send,
    required this.onClose,
  });

  final SceneStore store;
  final CharacterId id;

  /// Who's looking: the owner edits.
  final PlayerId self;
  final Outcome Function(Command) send;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => StreamBuilder(
        stream: store.changes,
        initialData: store.scene,
        builder: (context, snapshot) {
          final scene = snapshot.requireData;
          final c = scene.characters[id];
          final sheet = packOf(scene).sheet;
          if (c == null || sheet == null) return const SizedBox.shrink();
          return CvPanel(
            width: 600,
            solid: true,
            padding: EdgeInsets.zero,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height - 160),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                    child: Row(children: [
                      Expanded(child: Text(c.name, style: CvTypography.title)),
                      CvToolButton(
                        icon: Lucide.x,
                        label: 'Close',
                        tooltipSide: AxisDirection.left,
                        onPressed: onClose,
                      ),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: SheetView(
                        sheet: sheet,
                        values: sheet.clean(c.values),
                        onSet: c.owner == self
                            ? (name, value) => send(UpdateCharacter(
                                c.copyWith(values: {...c.values, name: value})))
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

/// Saves the characters [self] owns whenever they change in [store], a
/// second after the last change: only owners write their characters. One
/// newly in the room came from its row, so it isn't saved again. Returns
/// what stops it.
VoidCallback saveOwnCharacters(
    SceneStore store, PlayerId self, SavedCharacters characters,
    {void Function(Object error)? onError}) {
  // By content: a snapshot rebuilds every entity.
  String key(Character c) => jsonEncode(c.toJson());
  final saved = <CharacterId, String>{};
  bool record(Scene scene) {
    var changed = false;
    for (final c in scene.characters.values) {
      if (c.owner != self) continue;
      final k = saved.putIfAbsent(c.id, () => key(c));
      changed |= k != key(c);
    }
    return changed;
  }

  record(store.scene);
  Timer? timer;
  Future<void> flush() async {
    for (final c in store.scene.characters.values) {
      if (c.owner != self || saved[c.id] == key(c)) continue;
      try {
        await characters.save(c);
        saved[c.id] = key(c);
      } on Object catch (e) {
        onError?.call(e);
      }
    }
  }

  final subscription = store.changes.listen((scene) {
    if (!record(scene)) return;
    timer?.cancel();
    timer = Timer(const Duration(seconds: 1), flush);
  });
  return () {
    subscription.cancel();
    timer?.cancel();
    record(store.scene);
    flush();
  };
}
