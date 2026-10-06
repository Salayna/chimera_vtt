# Chimera VTT Design System

Dark, map-first UI kit for Chimera VTT, a virtual tabletop (Flutter, macOS + web) used by a GM and players. Built from the written brief only: no codebase, Figma or logo was supplied. Tokens map 1:1 to a Dart theme (CvColors, CvTypography, CvSpacing, CvRadii, CvElevation, CvMotion). No Material.

## Index
- styles.css — entry; imports tokens/* and components/components.css
- tokens/ — colors, typography, spacing, radii, elevation, motion, fonts, base
- components/ — React reference components (classes in components.css; every state also forceable via data-state)
- guidelines/ — foundation specimen cards
- assets/icons/ — Lucide v0.460 SVGs (copied)
- ui_kits/table/ — GM + player table prototype and 12 fixed screens (see its README)
- ui_kits/hub/ — outside the table: log in / sign up, home, campaign detail, library, new campaign, invite (see its README)
- thumbnail.html — homepage tile
- SKILL.md — Agent Skill entry
- scratch/ — dev-only loader for previewing sources before the bundle compiles; safe to delete

## Components
Icon, Button, ToolButton, ToggleButton, SegmentedControl, FloatingPanel, Toolbar (+ToolbarSeparator), Popover, Token, PresenceAvatar, AvatarStack, RoomCodeChip, TextInput, Dropdown, Menu, Toggle, Slider, Progress, Dialog, Tooltip, Toast.
Intentional additions: Button (dialogs/lobby need text actions), Icon (glyph wrapper), Menu (split out of Dropdown).

## Content fundamentals
Plain, warm, table-side English. Lexicon: GM, player (never "user"), room, room code, token, owner, hidden, fog, cover, reveal, map, grid, snap, scene. Sentence case everywhere; overlines are the only uppercase. Address the reader as "you"; questions for confirmations ("Replace the scene?"); ellipsis for waiting ("Waiting for the GM to open the room…"). No emoji, no exclamation marks, no error codes in copy.

## Visual foundations
Theme: "Slate". Engraved-instrument fantasy, kept modern: crisp hairline frames, tracked small-caps titles, one flat rune-cyan accent.
- Ground #0E1217; floating panels rgba(16,20,26,.94) + 1px #3A4450 outer frame + a second hairline 4px inside (#1C232B) + 6px radius + shadow + 12px blur, so chrome reads on any map.
- Meaningful accents only: rune cyan #5FE0F0 = GM + current selection; gold #E8B04E = players + ownership; ember #EF6F5E = danger; moss #8CC97A = saved. Cyan is always flat (no glow).
- Rune diamond (8px, rotated square) marks the top centre of dialogs and of panels with .cv-marked. Overlines are 800-weight, 0.22em tracked, cyan.
- Type: Marcellus (titles, dialog headings, hub headings), Marcellus SC (wordmark, token initials), Mulish (UI), IBM Plex Mono (room codes, readouts). Scale 40/26/20/14/13/12/11.
- Controls are pills: buttons uppercase 0.1em tracked; primary = bone fill with a 1px cyan ring 3px out. Tool buttons round; active = solid cyan + ring. Rails are capsules.
- Token selection: cyan ring + four bracket arcs at 45°. Slider thumb is a diamond. Switch is an outline track with a cyan knob when on.
- Spacing 2–64; 44px minimum target; chrome inset 16px from edges; nothing pushes the map.
- Radii 4/6/6/8/pill. Focus ring: 2px bone + 2px dark halo. Hover = 7% bone wash; press = 12% + scale .96–.98.
- Motion 60/120/180/260/420ms; standard/enter/exit curves; token drops settle with a small overshoot.
- No gradients, glows, textures, emoji or illustrations.

## Iconography
Lucide (ISC), 2px stroke, round caps, 20px (16px dense). SVGs copied to assets/icons and embedded in Icon.jsx. No icon font, no emoji, no unicode glyphs except ⌥ in keycaps.

## Caveats
No logo supplied: name set in Marcellus SC via .cv-wordmark. Fonts load from Google Fonts (no local binaries). Map imagery in the kit is a flat stand-in; real maps can be uploaded in the prototype. Tokens use initials; no portrait art supplied.

## Layout decision
Direction A (floating tools) for both roles. C’s inspector is reserved as a future GM-toggled right panel for phase-4 token data (conditions, sector tags, initiative); the token card is sized to grow into it.
