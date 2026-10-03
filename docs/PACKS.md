# System packs

As of 2026-10-03 · Companion to [PLAN.md](PLAN.md) and the [Lexicon](LEXICON.md)

A **system pack** is a module that teaches Chimera VTT a game system: how distance is counted, its range bands, its conditions and region tags with what they do, its initiative roll and the trackers on each token. Generic and D&D 5e are built in. Any other system is a JSON file the GM installs from the Library's **Systems** tab or the Grid panel's **System** menu. An Atlas VTT preset can be installed the same way.

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
| `topology` | `square` (default) or `gridless`. |
| `diagonal` | On a square grid: `chebyshev` (every diagonal 1), `manhattan` (2) or `alternating` (1, 2, 1…). |
| `unit`, `unitsPerStep` | What a step (a cell) is worth: `"ft"` and `5` for D&D 5e. Units longer than two letters get an "s" in the plural. |
| `bands` | Range bands in ascending `max` (in units, inclusive). A band without `max` catches the rest. |
| `initiative` | The dice formula each token rolls, as typed in the log (`d20`, `2d6+1`). |
| `forms` | Turn order without a roll, as Solaris' Combat Forms: `name`, `value` (higher goes first), `npc` (for the GM's tokens), `default` (where a side starts) and `text`. A fight starts everyone in their side's default form, and the GM clicks a token's form in the turn order to change it. |
| `trackers` | Numbers on every token: `name`, optional `min` (default 0), `max` and `text`. Players change their own tokens'. |
| `tags` | Conditions (`"condition": true`, set on tokens) and region tags (the rest; `"sector": true` marks sector tags). Each may be `valued`, have a `color` (`#rrggbb`), `text` and `effects`. |

Effects are the engine's building blocks (ADR 012): `{"type": "roll", "edge": -1, "scaled": true}` (advantage or disadvantage, times the tag's value when scaled), `{"type": "moveCost", "multiplier": 2}`, `{"type": "blocksSight"}`, `{"type": "occupantLimit", "max": 1}` and `{"type": "entryCheck", "check": "Traversal"}`. Anything they can't say goes in `text`.

Limits: at most 200 tags, 20 trackers and 20 bands; names up to 30 characters and texts up to 2000.

## Atlas VTT presets

An entry of Atlas' `userPresets` installs as a pack: Atlas conditions become conditions, or region tags when marked `sector`; its grid defaults give the unit, diagonals and range bands (with a last "Beyond" band). Atlas widgets have no equivalent yet and are left out.

## Shipped modules

- `packs/solaris-arcanum.json`: Solaris Arcanum from the Core Rulebook and Appendix C, summarised: 20 ft sectors at 1 AP each, the four range bands, the 15 sector tags (Line of Sight Breaker blocks sight; Difficult Terrain and Zero-g ask for Traversal; Bottleneck holds one), the status, wound and archetype tags as conditions, Combat Forms for turn order, and trackers for AP, Stress, Armor Grade and each system's wounds.
