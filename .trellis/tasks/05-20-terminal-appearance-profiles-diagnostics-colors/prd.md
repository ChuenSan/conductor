# terminal appearance profiles diagnostics and colors

## Goal

Add the next complete layer of terminal appearance settings: reusable appearance profiles,
font diagnostics that explain why a selected font does or does not take effect, and a compact
terminal color editor for Ghostty-backed terminal colors. The work should make terminal style
customization feel trustworthy and professional without moving terminal rendering or scrollback
into SwiftUI.

## What I already know

* The user approved continuing after the recommendation to build profiles, font diagnostics,
  and a color editor.
* Current settings already include terminal font presets, installed monospace font selection,
  imported font files, terminal font size, cursor style, and background opacity.
* Terminal rendering is owned by GhosttyKit/libghostty; SwiftUI owns low-frequency settings
  state and controls only.
* `TerminalAppearancePreferences`, resolver, and Ghostty config text builder already exist.
* `ConductorWindowModel` already refreshes existing terminal surfaces when terminal appearance
  preferences change.
* `AppearancePreferences` already persists terminal appearance and imported terminal fonts.

## Assumptions

* This task should extend the existing `终端外观` settings pane rather than adding a separate
  landing page or decorative panel.
* Profiles are global in this slice; workspace and per-terminal scoped overrides remain model
  support rather than full UI.
* The color editor should start with high-impact colors: foreground, background, cursor, cursor
  text, selection background, selection foreground, and ANSI 16-color swatches.
* Font diagnostics should be visible enough to explain fallback, but not require Ghostty
  transcript or renderer internals.

## Open Questions

* None blocking for the current slice. Use the recommended implementation path.

## Requirements

* Add a profile area to terminal appearance settings with packaged profile choices and a way to
  save the current appearance as a user profile.
* Add profile lifecycle management for custom profiles: rename, duplicate, update, delete,
  import JSON, export JSON, and clear current overrides.
* Allow switching profiles without losing explicit current overrides unless the user chooses a
  profile action that replaces the global style.
* Add font diagnostics that show selected font family, macOS availability, imported font status,
  and the Ghostty config font line that will be emitted.
* Add a color editor that can update terminal foreground/background, cursor, selection, and ANSI
  palette entries through the existing terminal appearance model.
* Keep all settings as low-frequency persisted product state.
* Refresh existing Ghostty surfaces through the existing config update path.
* Do not store terminal transcript, scrollback, cursor movement, or per-cell data in SwiftUI
  observable state.

## Acceptance Criteria

* [ ] `终端外观` settings includes a profile section.
* [ ] Users can switch between at least several packaged terminal appearance profiles.
* [ ] Users can save the current terminal appearance as a custom profile.
* [ ] Users can manage custom profiles through rename, duplicate, update, delete, import, and
  export actions.
* [ ] Users can see whether the current appearance is exactly the profile or has overrides.
* [ ] Font diagnostics explain when a selected font is unavailable or imported.
* [ ] Color controls update Ghostty config text for foreground/background/cursor/selection.
* [ ] ANSI palette swatches are editable through compact native controls.
* [ ] Existing live terminal surfaces refresh after profile or color changes.
* [ ] Existing font import and installed font selection still work.
* [ ] `swift build`, `ConductorModelCheck`, and `git diff --check` pass.

## Definition of Done

* Tests/checks added or updated where model behavior changes.
* Build and model check pass with the Homebrew Swift toolchain.
* UI follows existing settings panel patterns and macOS-native controls.
* No high-frequency terminal data enters SwiftUI state.

## Out of Scope

* Full per-workspace and per-terminal appearance override UI.
* Arbitrary theme import/export formats beyond the current Ghostty-compatible model.
* Measuring Ghostty's final runtime fallback font from renderer internals.
* Replacing GhosttyKit/libghostty rendering.

## Technical Notes

* Relevant code:
  * `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
  * `Apps/Conductor/Sources/Conductor/Shared/AppearancePreferences.swift`
  * `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalAppearanceModel.swift`
  * `Apps/Conductor/Sources/Conductor/Terminal/TerminalGhosttyConfigBuilder.swift`
  * `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`
* Relevant specs:
  * `.trellis/spec/guides/high-performance-terminal-roadmap.md`
  * `.trellis/spec/frontend/component-guidelines.md`
  * `.trellis/spec/frontend/state-management.md`
  * `.trellis/spec/backend/ghosttykit-integration.md`
