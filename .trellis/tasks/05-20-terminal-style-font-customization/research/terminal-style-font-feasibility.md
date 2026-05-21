# Terminal Style And Font Customization Feasibility

## Conclusion

Terminal style customization is feasible on the current GhosttyKit/libghostty surface route.
Terminal font size is already implemented as a global low-frequency appearance preference.
Terminal font family is also feasible, but it is not currently modeled separately from the
SwiftUI shell font family.

## Existing Implementation

### Terminal themes

`TerminalTheme` already owns both shell chrome colors and Ghostty terminal renderer colors.
Each theme exposes `ghosttyConfig`, which emits Ghostty-compatible config lines:

* `palette = 0..15`
* `background`
* `foreground`
* `cursor-color`
* `cursor-text`
* `selection-background`
* `selection-foreground`

`GhosttyAppRuntime.makeConfig(theme:terminalFontSize:)` loads these config lines into
`ghostty_config_load_string`, then finalizes the Ghostty config.

`TerminalSurface.applyAppearance(theme:terminalFontSize:)` calls
`ghostty_surface_update_config(surface, config)` and refreshes the surface. It also sets the
host view layer background to the theme terminal background, keeping the AppKit host and
Ghostty renderer visually aligned.

### Terminal font size

`AppearancePreferences` already has:

* `terminalFontSize`
* `defaultTerminalFontSize = 15`
* `minTerminalFontSize = 10`
* `maxTerminalFontSize = 22`
* clamping during init and decode

`AppearanceSettingsPanel` already exposes a Terminal Font Size slider.

`ConductorWindowModel.appearance.didSet` detects terminal font size changes and calls
`TerminalSurface.applyTerminalFontSize` on all live surfaces. New surfaces receive the current
font size through `ConductorWindowModel.surface(for:)`.

`TerminalSurface.attachIfPossible()` also passes the size to Ghostty via
`ghostty_surface_config_s.font_size`, so the initial surface creation and later config reloads
are both covered.

## Ghostty Feasibility Notes

Local Ghostty source confirms:

* `font-family`, `font-family-bold`, `font-family-italic`, and
  `font-family-bold-italic` are valid repeatable config keys.
* `font-size` is a valid config key.
* `Surface.updateConfig` rebuilds and sends a new font grid to the renderer during config
  reload.
* `Termio.changeConfig` updates the default palette and terminal background/foreground/cursor
  colors from config.

cmux also uses `ghostty_surface_update_config` for per-surface config reloads and has tests
around `font-family` config handling, which supports this route as an integration precedent.

## Recommended MVP

Keep customization global first:

1. Continue using `TerminalTheme` as the preset source of truth for terminal colors and shell chrome.
2. Keep terminal font size in `AppearancePreferences.terminalFontSize`.
3. Add a separate `terminalFontFamily` preference rather than reusing shell `fontFamily`.
4. Add `font-family = <name>` to `GhosttyAppRuntime.makeConfig`.
5. Extend `TerminalSurface.applyAppearance` and `ConductorWindowModel.appearance.didSet` so
   changing the terminal font family updates existing surfaces the same way terminal font size
   does.

Avoid per-pane overrides for the first pass. Global settings match the current persistence and
theme model, and keep the UI simple.

## Risks

* Font family hot updates may cause a visible renderer refresh, which is acceptable for a
  low-frequency settings action but should be manually tested while output is streaming.
* Missing fonts need a fallback strategy. Ghostty can fall back, but the UI should prefer
  known installed monospaced fonts and keep a default option.
* CJK fallback deserves care. cmux has dedicated logic around CJK fallback maps; Conductor can
  start with a conservative font picker and add codepoint maps later if needed.
* Existing shell `AppearanceFontFamily` is for SwiftUI chrome text. Reusing it for terminal
  content would mix two separate concerns.

## Validation For Implementation

* `swift build`
* `ConductorModelCheck`
* `./Scripts/check-conductor.sh`
* Manual smoke: change theme while several panes are visible.
* Manual smoke: change terminal font size and font family while a pane is streaming output.
* Manual smoke: create a new terminal after changing font settings; it should inherit the new settings.
