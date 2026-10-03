# System packs

As of 2026-10-03 · Companion to [PLAN.md](PLAN.md) and the [Lexicon](LEXICON.md)

A **system pack** is a module that teaches Chimera VTT a game system: how distance is counted, its range bands, its conditions and region tags with what they do, its initiative roll and the trackers on each token, and the ready-made tokens it brings with their pictures and cards. Generic and D&D 5e are built in. Any other system is made in the app (the hub's **Systems** page, **New module**) or installed there or from the Grid panel's **System** menu: a module bundle (`.chimera`), a pack file (`.json`) or an Atlas VTT preset.

## Module bundles

A module is more than its JSON: its tokens' pictures, its cards' images and its cover come with it. A bundle is a zip:

```
module.json                 the pack, in the format below
images/<sha256>             each image the pack names, PNG, JPEG or WebP
```

An image is named by the SHA-256 of its bytes, in hex, and the pack refers to it by that name (`"image": "3f9a…"`), as every asset in the app is named (ADR 006). Installing a bundle checks it all, then uploads the images and installs the pack: at most 64 MB, 600 images of 15 MB each; every image the pack names present; each image's bytes matching its name; nothing but PNG, JPEG or WebP. Images the pack doesn't name are left out. **Export** on the Systems page writes an installed module back out as a bundle (`<id>-v<version>.chimera`).

## Making a module in the app

**New module** (or **Edit** on an installed one) opens the editor: About (name, description, cover), Rules (unit, units a cell, diagonals, initiative roll), Tags (conditions and region or sector tags, valued or not, with rules text), Trackers (name, bounds, text) and Tokens (picture, name, size, and card sections, each with text and an image). The id comes from the name for a new module and never changes after. Saving runs the same checks as a file from anyone, then installs it; saving an edit bumps the version. Effects, range bands, turn forms, and a token's own trackers and starting tags aren't in the editor yet: they're kept as they are, and edited in the file.

Installed packs belong to the GM's account and serve all their campaigns. A scene played with one carries a copy, so players and scene files get it without installing anything.

## File format

```json
{
  "format": 1,
  "id": "solaris-arcanum",
  "name": "Solaris Arcanum",
  "version": 1,
  "topology": "square",
  "diagonal": "chebyshev",
  "unit": "sector",
  "unitsPerStep": 1,
  "bands": [{"name": "Adjacent", "max": 1}, {"name": "Far"}],
  "initiative": "d20",
  "trackers": [{"name": "HP", "min": 0}, {"name": "Stress", "max": 6}],
  "tags": [
    {"name": "Prone", "condition": true, "text": "Rules text, shown on hover."},
    {"name": "Darkness", "sector": true, "valued": true,
     "effects": [{"type": "roll", "edge": -1, "scaled": true}]}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `format` | The file format, 1. The app refuses others. |
| `id` | Lowercase letters, digits and dashes, at most 40. Scenes name their pack by it, so keep it across versions. |
| `name`, `version` | Shown to the GM. Installing a pack with an id already installed replaces it. |
| `description`, `cover` | What the module is (up to 2000 characters), and its cover art (an image name). |
| `topology` | `square` (default) or `gridless`. |
| `diagonal` | On a square grid: `chebyshev` (every diagonal 1), `manhattan` (2) or `alternating` (1, 2, 1…). |
| `unit`, `unitsPerStep` | What a step (a cell) is worth: `"ft"` and `5` for D&D 5e. Units longer than two letters get an "s" in the plural. |
| `bands` | Range bands in ascending `max` (in units, inclusive). A band without `max` catches the rest. |
| `initiative` | The dice formula each token rolls, as typed in the log (`d20`, `2d6+1`). |
| `forms` | Turn order without a roll, as Solaris' Combat Forms: `name`, `value` (higher goes first), `npc` (for the GM's tokens), `default` (where a side starts) and `text`. A fight starts everyone in their side's default form, and the GM clicks a token's form in the turn order to change it. |
| `trackers` | Numbers on every token: `name`, optional `min` (default 0), `max` and `text`. Players change their own tokens'. |
| `tokens` | Ready-made tokens, such as a system's threats: `name`, `image` (its picture, an image name), `size` (cells), `form` (a form's name), `trackers` (each with its own `max` and starting `value`), `conditions` it starts with, and `card`: sections of `title`, `text` and an optional `image` the GM reads on its token card. Players never get cards: scenes carry the pack without its tokens, and the trackers of tokens nobody owns stay with the GM. |
| `sheet` | What the system's characters hold: see [Sheets](#sheets). Players make characters only for systems with one. |
| `compendium` | Entries characters hold copies of, grouped in kinds: see [Compendium](#compendium). |
| `advancement` | The nodes characters take: see [Advancement](#advancement). |
| `tags` | Conditions (`"condition": true`, set on tokens) and region tags (the rest; `"sector": true` marks sector tags). Each may be `valued`, have a `color` (`#rrggbb`), `text` and `effects`. |

Effects are the engine's building blocks (ADR 012): `{"type": "roll", "edge": -1, "scaled": true}` (advantage or disadvantage, times the tag's value when scaled), `{"type": "moveCost", "multiplier": 2}`, `{"type": "blocksSight"}`, `{"type": "occupantLimit", "max": 1}` and `{"type": "entryCheck", "check": "Traversal"}`. Anything they can't say goes in `text`.

Limits: at most 200 tags, 20 trackers, 20 bands and 500 tokens (each with up to 20 trackers and 30 card sections of up to 4000 characters); names up to 30 characters and texts up to 2000. An installed pack holds up to 4 MB.

### Sheets

A sheet is sections of fields. Each field has a `name` that formulas read (letters, digits, `_` and dots, as `DEX.mod`; not a keyword, a function or dice), an optional `label` people see and `text` shown on hover, and a `type`:

```json
"sheet": {"sections": [
  {"title": "Abilities", "fields": [
    {"name": "DEX", "label": "Dexterity", "min": 1, "max": 20, "value": 10},
    {"name": "DEX.mod", "type": "computed", "formula": "floor((DEX - 10) / 2)"},
    {"name": "class", "type": "choice", "options": ["Fighter", "Wizard"]}
  ]},
  {"title": "Combat", "fields": [
    {"name": "armor", "min": 0, "max": 4},
    {"name": "AP", "type": "tracker", "max": "8 - armor", "value": "AP.max"},
    {"name": "inspired", "type": "checkbox"},
    {"name": "notes", "type": "text"}
  ]}
]}
```

| Type | Holds |
| --- | --- |
| `number` (default) | A whole number, within optional constant `min` and `max`, starting at `value` (or `min`, or 0). |
| `text` | Up to 2000 characters, starting at `value` or empty. |
| `choice` | One of `options` (up to 50, of up to 60 characters), starting at `value` or the first. |
| `checkbox` | On or off, starting at `value` or off. |
| `computed` | The value of its `formula`, a number, boolean or text, never set by hand. |
| `tracker` | A number changed in play, kept within `min` (default 0) and `max`, which may be formulas; formulas read them as `AP.min` and `AP.max`. It starts at `value`, a formula too (`"AP.max"`), or at its min. |
| `items` | The character's items of one compendium `kind`, as cards. Formulas don't read it by name: `count("Weapon")` is how many there are, `sum("Armor", "apReduction")` adds up a number field of them. |

Formulas are those of [SYSTEMS.md](SYSTEMS.md): they read the sheet's names, never roll dice, and a field can't depend on itself. A bad sheet refuses the whole pack with the reason. Limits: 20 sections, 200 fields.

### Compendium

```json
"compendium": {
  "kinds": [
    {"name": "Weapon", "fields": [
      {"name": "capacity"},
      {"name": "ammo", "type": "tracker", "max": "capacity", "value": "ammo.max"}
    ]},
    {"name": "Armor", "fields": [{"name": "apReduction"}]}
  ],
  "entries": [
    {"kind": "Weapon", "name": "P9 Pistol", "values": {"capacity": 5},
     "card": [{"title": "Precision Shot", "text": "2 AP, 1d20, Point Blank / Adjacent"}]},
    {"kind": "Armor", "name": "Vulture Harness", "values": {"apReduction": 1}}
  ]
}
```

A kind's `fields` are sheet fields (no items, and no `count` or `sum`), and its `actions` every item of it has. An entry has a `kind`, a `name` unique in the compendium, `values` for its kind's fields, each checked against them, a `card` of sections like a token's, and its own `actions`. A character's item is a copy of an entry, its trackers starting from the entry's values. Limits: 20 kinds, 1000 entries, 10 card sections an entry.

### Actions

The sheet's `actions` are the character's; a kind's and an entry's are its items'. An item's action reads the item's fields first, then the sheet's.

```json
{"name": "Quick Shot", "text": "Point Blank / Adjacent",
 "cost": [{"tracker": "AP", "amount": 3}, {"tracker": "ammo", "amount": 2}],
 "dice": "d20", "mod": "FIN + threatLevel", "times": 2,
 "bands": [{"name": "Grazing", "min": 16, "text": "1 Stress"},
           {"name": "Precise", "min": 20, "text": "1 Stress & 1 CvW"},
           {"name": "Devastating", "min": 24, "text": "2 Stress & 2 CvW"}]}
```

| Field | Meaning |
| --- | --- |
| `cost` | Up to 5 trackers it spends, each with an `amount` (a formula, 1 by default): the item's tracker of that name if it has one, the character's otherwise. It can't be used when one would fall below its min; a negative amount gives back, up to the max (a reload: `"ammo - ammo.max"`). |
| `dice` | Dice only (`d20`, `2d6+1d4`), rolled by the GM; none for an action that only spends. |
| `mod`, `times` | Formulas: what's added to each roll, and how many rolls (1 to 10), each in its own band. |
| `bands` | Up to 10, from the lowest `min` up: a roll is in the highest band it reaches, with its `text`; below them all it misses. |

Limits: 20 actions on a sheet, a kind or an entry.

### Advancement

```json
"advancement": {"name": "Constellation", "field": "CP", "nodes": [
  {"name": "Origin", "cost": 0, "x": 0, "y": 0},
  {"name": "Duelist", "group": "Archetype", "requires": ["Origin"],
   "condition": "count(\"Archetype\") < 3", "x": 1, "y": 0},
  {"name": "Might", "requires": ["Origin"], "adds": {"STR": 1}, "x": 0, "y": 1},
  {"name": "Ultimate Combatant", "requiresAll": ["Duelist", "Might"],
   "items": ["Ultimate Combatant"], "x": 1, "y": 1}
]}
```

`field` is the sheet number or tracker costs are paid from. A node has a `name`, `text`, a `cost` (1 by default, 0 to 1000), `requires` (taken once any of these is; none for a first node), `requiresAll` (once all are), a `condition` (a boolean formula on the sheet), `adds` (to number fields, kept within their bounds), `items` (entries given as items), a `group` (`count("Archetype")` counts taken nodes of it as well as items of that kind), and `x` and `y` to draw it (in a row by default). Limits: 300 nodes, each requiring up to 20.


## Atlas VTT presets

An entry of Atlas' `userPresets` installs as a pack: Atlas conditions become conditions, or region tags when marked `sector`; its grid defaults give the unit, diagonals and range bands (with a last "Beyond" band). Atlas widgets have no equivalent yet and are left out.

## Shipped modules

- `packs/solaris-arcanum.json`: Solaris Arcanum from the Core Rulebook and Appendix C, summarised: 20 ft sectors at 1 AP each, the four range bands, the 15 sector tags (Line of Sight Breaker blocks sight; Difficult Terrain and Zero-g ask for Traversal; Bottleneck holds one), the status, wound and archetype tags as conditions, Combat Forms for turn order, and trackers for AP, Stress, Armor Grade and each system's wounds.

### Threats from your own books

The Solaris threat database is book content, so the repository's module has none. `packages/tactical_engine/tool/solaris_threats.dart` reads the threat data cards in your own notes of the books (Markdown, as in an Obsidian vault) and writes the module with them as tokens, git-ignored:

```sh
cd packages/tactical_engine
dart run tool/solaris_threats.dart "<vault>/Solaris Arcanum" \
    ../../packs/solaris-arcanum.json ../../packs/solaris-arcanum.local.json
```

Install `packs/solaris-arcanum.local.json` from the Systems page. Each card becomes a token: its Combat Form, its damage tracks and other boxed counters (Ammo, Heat, Horde Counter) as trackers with their box counts, its per-round slots, immunities and vulnerabilities in a Profile section, its attack profiles, unique actions and traits, overload profile and tags as card sections, and book tags the pack knows (Synthetic) as conditions. A card without a damage table gets no trackers.
