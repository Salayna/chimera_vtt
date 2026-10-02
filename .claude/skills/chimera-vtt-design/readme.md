# Chimera VTT Design System

Dark, map-first UI kit for Chimera VTT, a virtual tabletop (Flutter, macOS + web) used by a GM and players. Built from the written brief only: no codebase, Figma or logo was supplied. Tokens map 1:1 to a Dart theme (CvColors, CvTypography, CvSpacing, CvRadii, CvElevation, CvMotion). No Material.

## Index
- styles.css — entry; imports tokens/* and components/components.css
- tokens/ — colors, typography, spacing, radii, elevation, motion, fonts, base
- components/ — React reference components (classes in components.css; every state also forceable via data-state)
- guidelines/ — foundation specimen cards
- assets/icons/ — Lucide v0.460 SVGs (copied)
- ui_kits/table/ — GM + player table prototype and 12 fixed screens (see its README)
- thumbnail.html — homepage tile
- SKILL.md — Agent Skill entry
- scratch/ — dev-only loader for previewing sources before the bundle compiles; safe to delete

## Components
Icon, Button, ToolButton, ToggleButton, SegmentedControl, FloatingPanel, Toolbar (+ToolbarSeparator), Popover, Token, PresenceAvatar, AvatarStack, RoomCodeChip, TextInput, Dropdown, Menu, Toggle, Slider, Progress, Dialog, Tooltip, Toast.
Intentional additions: Button (dialogs/lobby need text actions), Icon (glyph wrapper), Menu (split out of Dropdown).

## Content fundamentals
Plain, warm, table-side English. Lexicon: GM, player (never "user"), room, room code, token, owner, hidden, fog, cover, reveal, map, grid, snap, scene. Sentence case everywhere; overlines are the only uppercase. Address the reader as "you"; questions for confirmations ("Replace the scene?"); ellipsis for waiting ("Waiting for the GM to open the room…"). No emoji, no exclamation marks, no error codes in copy.

## Visual foundations
- Ground slate #14161B; floating panels rgba(22,24,30,.94) + 1px #2E3340 + 14px radius + shadow-1 + 12px backdrop blur, so chrome reads on bright and dark maps.
- Meaningful accents only: amber #E8A33D = GM + current selection; teal #3FB6A8 = players + ownership; ember #EF6F5E = danger; moss #8CC97A = saved.
- IBM Plex Sans (UI), IBM Plex Mono (room codes, readouts). Scale 40/24/18/14/13/12/11.
- Spacing 2–64; 44px minimum target; chrome inset 16px from edges; nothing pushes the map.
- Radii 4/6/10/14/20/pill. Focus ring: 2px bone + 2px dark halo. Hover = 7% bone wash; press = 12% + scale .96–.98; selected = amber tint + amber inset line.
- Motion 60/120/180/260/420ms; standard/enter/exit curves; token drops settle with a small overshoot.
- No gradients, glows, emoji or illustrations; flat colour only.

## Iconography
Lucide (ISC), 2px stroke, round caps, 20px (16px dense). SVGs copied to assets/icons and embedded in Icon.jsx. No icon font, no emoji, no unicode glyphs except ⌥ in keycaps.

## Caveats
No logo supplied: name set in type. Fonts load from Google Fonts (no local binaries). Map imagery in the kit is a flat stand-in; real maps can be uploaded in the prototype. Tokens use initials; no portrait art supplied.

## Layout decision
Direction A (floating tools) for both roles. C’s inspector is reserved as a future GM-toggled right panel for phase-4 token data (conditions, sector tags, initiative); the token card is sized to grow into it.
