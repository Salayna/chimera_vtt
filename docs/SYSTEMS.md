# Chimera VTT — System building

As of 2026-10-03 · Proposal · Companion to [PLAN.md](PLAN.md), the [Lexicon](LEXICON.md) and [PACKS.md](PACKS.md)

The app plays D&D well, but systems differ in more than conditions and grids: Solaris Arcanum's initiative is nothing like D&D's, nor are its damage (Stress and wound types by hit tier), its character sheet, or its leveling (a skill tree, the Constellation). A module has to bring all of that, so a campaign plays like its game.

## What a module declares

Three building blocks, all data in the module file, none compiled into the app:

1. **Fields:** typed values on a sheet or an entry: number, text, choice, checkbox, or a list of compendium entries.
2. **Formulas:** level 2 of the [tiered scripting](PLAN.md#customization-tiered-scripting) (ADR 013), for values computed from others: `END + WIL + threatLevel` (the Solaris Stress threshold), `floor((DEX - 10) / 2)`. A formula is text in the module, read when it's installed; the app ships one interpreter, so making or changing a module never rebuilds the app. No loops, no side effects, dice from the GM's roller.
3. **Actions:** a cost, a roll and outcome bands, each band saying what it does, for example Solaris' `d20 + mod` → Grazing, Precise or Devastating → "2 Stress, 2 CvW".

## The pieces

| Piece | What it is | In Solaris Arcanum |
| --- | --- | --- |
| **Character sheet** | The module's `sheet`: sections of fields, computed fields, and trackers whose bounds are formulas. | AP at most 8, less armor and wounds; the Stress threshold |
| **Compendium** | The module's entries, grouped in kinds (Weapon, Armor, Talent…). Each kind declares its fields, trackers and card. Today's pack tokens become one kind, Threat. | Weapon data cards with their AP costs, hit profiles and ammo |
| **Items** | A character owns copies of entries, shown as cards, each with its own tracker values. | A rifle with 4 of 6 shots left |
| **Actions** | Buttons on a sheet or an item card that pay their cost, roll, and log the outcome band with its text. They change nothing on the target. | Lethal Shot: 3 AP, the hit tiers, the wounds dealt |
| **Advancement** | A graph of nodes: a cost in a field (CP, XP), what each requires (other nodes, or a rule such as "at most 3 archetypes") and what it grants (field changes, entries). D&D levels are a chain; Solaris draws its graph as the Constellation. | Ranks give CP, spent on the Constellation's six paths |
| **Initiative** | Done: a roll or turn forms. The roll formula will read the sheet (`d20 + DEX.mod`). | Combat Forms |

Decks of cards (draw, shuffle, hands) wait for a system that needs them.

## Characters

Decided 2026-10-03:

- **Made outside campaigns.** A signed-in user makes characters on their home, each for one system, and links one to a campaign played with that system. A home is no longer only the GM's.
- **Players own them.** The owner edits their sheet; the GM of a linked campaign reads it.
- **Players apply damage themselves.** An action logs what it dealt; the target's owner changes their trackers. Nothing is applied for them.

Storage:

| Table | Holds | Who can read and write |
| --- | --- | --- |
| `characters` | id, owner, system (a pack id), name, the sheet's JSON, updated | The owner; the GMs of linked campaigns read |
| `campaign_characters` | campaign, character | The character's owner links and unlinks; the campaign's GM reads |

In the room a character is an entity (kind `character`), sent with the snapshot as the log is, since it spans scenes. A token links to one (`Token.character`) and shows its trackers. Changes go through the GM session like any command ([principle 2](PLAN.md#principles)), and the owner's client saves its own row, so only owners ever write characters. An anonymous player's characters last as long as their session, as everything they own does; signing in keeps them.

## Bricks

1. The formula language: a parser and evaluator in `tactical_engine`, with tests. Built 2026-10-03 (`Formula`): `parse` refuses bad syntax with its position, `check` refuses unknown names and mixed types given the sheet's names, `eval` takes the names' values and a die. Dividing by zero gives 0. `count` and `sum` over items wait for brick 4.
2. Sheets in the pack format, the `characters` table, and a Characters tab on the home to make and edit them. Built 2026-10-03: a pack's `sheet` (`SheetDef`) has sections of fields (number, text, choice, checkbox, computed, tracker; [PACKS.md](PACKS.md#sheets)), checked when the pack is read: names formulas can reach, no dice, no field depending on itself. A character's values are cleaned against it whenever they're read (`SheetDef.clean`); `SheetValues` works out computed fields and tracker bounds. The built-in D&D 5e pack has a sheet. The `characters` table is owner-only until linking. Limits: the home is for signed-in users, so anonymous players make characters only with brick 3; a player plays the systems built in or installed on their own Systems page; a sheet is saved with a button, not as it's typed.
3. Linking: a character to a campaign, then to a token, and played in the room. Built 2026-10-03: a player brings one of their characters for the campaign's system from the room's Characters panel, or makes one there (anonymous players too), which links it (`link_character` checks they're a member and the system matches; `campaign_characters`). In the room it's an entity (`Scene.characters`): the GM loads the linked ones as the room opens and keeps them across scene switches, while scene saves, files and library copies leave them out. Only its owner changes it (`UpdateCharacter`, `RemoveCharacter`; the GM is refused), and the owner's client saves its row a second after a change. A token plays a character (`LinkCharacter`: the GM any, a player their own token and character); its card shows the character's trackers, and **Sheet** opens the whole sheet, read-only for everyone but the owner. Protocol 6. Limits: every player reads every character in the room; a change resends the whole character; the initiative roll doesn't read the sheet yet; characters of another system stay in the room if the GM changes the campaign's system.
4. The compendium: kinds and entries in the format, and items on the sheet as cards with their trackers. Built 2026-10-03: a pack's `compendium` has kinds (each a list of sheet fields: data such as a weapon's `capacity`, and trackers such as its `ammo`, at most `capacity`) and entries (a kind, a name, values for its fields, a card). A sheet's `items` field shows the character's items of one kind as cards, each added from the kind's entries as a copy (`Item`: its values, its trackers starting from them, its card) with its own tracker values; the owner changes the trackers, the rest is the entry's. Formulas read items with `count("Weapon")` and `sum("Armor", "apReduction")`, checked when the pack is read. Limits: pack tokens stay their own list rather than entries of a Threat kind; an item can't be made by hand, only copied from an entry; an item keeps its copy when the module changes its entry (brick 10); items show on the sheet, not on the token card; a character holds at most 100 items and 128 KB in the room. Protocol 7.
5. Actions: cost, roll and outcome bands, logged. Built 2026-10-03: actions sit on the sheet (Dodge), on an entry kind (every weapon's Reload) and on an entry (a pistol's attack profiles). Each has costs (a tracker and an amount, from the item when it has that tracker, else the character; a negative amount gives back, as a reload's `ammo - ammo.max`), `dice` with a `mod` formula, `times` rolls (Solaris bins each die apart), and outcome bands by their least result, each with what it does. In the room, the sheet panel's buttons (greyed out when a cost can't be paid) send `UseAction`: the owner's client pays the costs and works out the dice (`d20+4`) from their sheet, and the GM's session rolls each time, finds its band and logs it (`ActionEvent`); nothing changes on the target. D&D 5e's built-in compendium has SRD weapons with Attack and Damage. Protocol 8. Limits: no actions outside a room (nobody rolls there); an item's entry actions are found by its name, so a renamed entry loses them; advantage and tier shifts (cover, Weapon Master) are the players' to apply by reading the log; the log shows a band's text, not the action's.
6. Advancement: the node graph, and the Constellation view. Built 2026-10-03: a pack's `advancement` names the sheet number it spends (CP, or XP for D&D, which spends nothing) and its nodes: each with a cost, what it requires (any one of `requires`, as Solaris' adjacent stars or D&D's previous level, and all of `requiresAll`, a group's reward), a `condition` formula (`XP >= 900`), what it `adds` to number fields and the entries it gives as `items`, a `group` that `count` reads (at most 3 archetypes: `count("Archetype") < 3`), and where it's drawn (`x`, `y`, or in a row). The sheet shows the graph (`AdvancementView`): taken nodes in amber, those that can be taken outlined, the reason on hover; tapping one takes it, on the home or in the room. A character keeps its taken nodes' names. D&D 5e's levels are a chain. Protocol 9. Limits: a node can't be given back; it isn't taken through the GM, so nothing is logged; the graph's drawing is points and straight lines.
7. The module editor's tabs for sheets, the compendium, actions and advancement (JSON until then). Built 2026-10-03: the editor's Sheet tab (sections of fields, each with what its type needs, and the character's actions), Compendium tab (kinds with their fields and actions, and each kind's entries with their values, card sections and actions; renaming a kind renames what names it) and Advancement tab (what it spends, and nodes with their requirements, condition, grants and place). They write the format's own JSON, so saving checks them as a file from anyone is checked, with the same reasons. Limits: lists of names (options, requirements) are typed comma-separated; nothing is checked until Save (brick 9 previews); fields and nodes can't be reordered; card sections of entries have no image.

Book content (Solaris weapons, talents, the Constellation's nodes) is built from the GM's own notes by a tool and kept out of the repository, as the threats are.
