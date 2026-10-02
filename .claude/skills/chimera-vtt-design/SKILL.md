---
name: chimera-vtt-design
description: Use this skill to generate well-branded interfaces and assets for Chimera VTT, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for protoyping.
user-invocable: true
---

Read the readme.md file within this skill, and explore the other available files.
If creating visual artifacts (slides, mocks, throwaway prototypes, etc), copy assets out and create static HTML files for the user to view. If working on production code, you can copy assets and read the rules here to become an expert in designing with this brand.
If the user invokes this skill without any other guidance, ask them what they want to build or design, ask some questions, and act as an expert designer who outputs HTML artifacts _or_ production code, depending on the need.

## Local notes

- Only SKILL.md and readme.md are copied here. The other files (tokens/, components/, guidelines/, assets/icons/, ui_kits/table/) live in the Claude Design project https://claude.ai/design/p/32b42cc6-7c72-43c2-a0ea-187f446c64f6. Read them with `DesignSync(get_file)` (run /design-login first).
- Production code: the tokens are already in Dart at `app/lib/theme.dart` (CvColors, CvTypography, CvSpacing, CvSizes, CvRadii, CvElevation, CvMotion). Use those, never raw hex.
- The components are Flutter widgets in `app/lib/ui/cv.dart` (CvPanel, CvToolButton, CvToolbar, CvButton, CvTextInput, CvDropdown, CvSwitch, CvSlider, CvSegmentedControl, CvToggleButton, showCvDialog, CvToasts, CvRoomCodeChip, CvAvatar…; icons are the `Lucide` enum). The table chrome (rail, fog options, token card, zoom, presence) is in `app/lib/table/chrome.dart`. No Material: the app runs on `cvApp` (WidgetsApp).
