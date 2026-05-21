# Terminal Appearance Customization Design

## Product Intent

Conductor should treat terminal appearance as a first-class professional setting, not a small
theme toggle. Users should be able to define a coherent terminal style system, apply it globally,
override it for a workspace, and make temporary or persistent overrides for a specific terminal
pane without moving terminal rendering into SwiftUI.

The design keeps GhosttyKit/libghostty as the owner of terminal semantics and drawing. SwiftUI
owns low-frequency preference state, settings controls, previews, and command entry points.

## Design Principles

* Terminal output, scrollback, cursor position, selection geometry, and cell metrics stay out of
  SwiftUI state.
* Appearance settings are low-frequency product state and may be persisted.
* Existing live terminal surfaces update through bounded Ghostty config reloads.
* New terminal surfaces resolve their appearance before `ghostty_surface_new`.
* Presets should be easy; advanced control should be available but fenced.
* Shell UI font family and terminal content font family are separate concepts.
* Per-terminal overrides must not fork the terminal runtime or recreate panes unnecessarily.

## Scope Model

Appearance resolves in this order:

1. Terminal override
2. Workspace override
3. Global default
4. Packaged default

Each override can be partial. A terminal may override only font size, while inheriting color and
cursor settings from its workspace or global profile.

### User-facing scopes

* Global: default for every workspace and terminal.
* Workspace: default for new terminals inside that workspace and live update for terminals that
  are still inheriting workspace/global appearance.
* Terminal: override for one terminal tab or pane.
* Temporary Preview: unsaved settings applied to a preview target until the user commits or
  cancels.

### Inheritance behavior

* A terminal created in a workspace inherits the workspace resolved appearance at creation time.
* If it has no terminal-level override, later workspace/global changes continue to update it.
* Once the user sets a terminal-level override, only changed override fields detach. Other fields
  still inherit.
* A “Reset to Workspace” command clears terminal overrides.
* A “Reset Workspace to Global” command clears workspace overrides.

## Data Model

Add a terminal-specific appearance model rather than extending `TerminalTheme` into every concern.

```swift
struct TerminalAppearancePreferences: Codable, Equatable {
    var global: TerminalAppearanceReference
    var userProfiles: [TerminalAppearanceProfile]
}

struct TerminalAppearanceReference: Codable, Equatable {
    var profileID: TerminalAppearanceProfileID
    var override: TerminalAppearanceOverride?
}

struct TerminalAppearanceProfile: Codable, Equatable, Identifiable {
    var id: TerminalAppearanceProfileID
    var name: String
    var source: TerminalAppearanceProfileSource
    var style: TerminalStyleSettings
}

struct TerminalAppearanceOverride: Codable, Equatable {
    var font: TerminalFontSettings?
    var colors: TerminalColorSettings?
    var cursor: TerminalCursorSettings?
    var background: TerminalBackgroundSettings?
    var advanced: TerminalAdvancedSettings?
}
```

`PersistedWindowState` owns the global appearance store. `WorkspaceState` gets an optional
`terminalAppearanceOverride`. `TerminalTabState` gets an optional `terminalAppearanceOverride`.
Unknown/missing fields decode to inheritance defaults.

Keep these structs in the app target unless ConductorCore needs to reason about them for model
checks. If workspace invariants need override validation, move the small Codable value types into
ConductorCore and keep Ghostty config rendering in the app target.

## Style Settings

### Font

Support:

* Font family chain: primary plus fallback families.
* Optional explicit bold, italic, and bold-italic families.
* Font size: current 10-22 pt range, with room to raise max after testing.
* Line/cell tuning: `adjust-cell-width` and `adjust-cell-height`.
* Optional ligature/features control via `font-feature`.
* Optional variable font axes via `font-variation`.
* Optional CJK fallback mapping via `font-codepoint-map`.

Recommended default font picker:

* “Default” maps to no `font-family` line.
* Installed monospaced fonts are discovered with CoreText.
* Favorite presets include SF Mono, Menlo, Monaco, JetBrains Mono if installed, Iosevka if
  installed, and any existing configured Ghostty family if import support discovers one.
* Missing imported fonts stay visible as unavailable entries with a warning and fallback path.

### Colors

Support:

* 16 ANSI colors.
* Foreground and background.
* Cursor color and cursor text color.
* Selection foreground/background.
* Optional bold color behavior.
* Import/export as Ghostty-compatible theme fragments.

`TerminalTheme` should remain the packaged shell-plus-terminal preset catalog. User-created
terminal-only color profiles should not be forced to define full shell chrome colors. A packaged
`TerminalTheme` can be converted into a `TerminalColorSettings` profile.

### Cursor

Support:

* Cursor style: block, bar, underline where Ghostty accepts those values.
* Blink behavior: system/default, on, off.
* Opacity, if we expose it after visual validation.

### Background

Support cautiously:

* Background opacity.
* Background opacity cells behavior.
* Background blur only if it does not fight the AppKit host layer and shell materials.
* Background image options only behind an “Advanced” disclosure. This needs careful validation
  with split resizing and performance.

The host view layer background and Ghostty renderer background must remain synchronized. If
opacity/blur is enabled, define one owner for translucency rather than stacking SwiftUI glass,
AppKit layer opacity, and Ghostty background opacity.

### Advanced

Support a fenced Ghostty config fragment only after the allowlist exists. The allowlist should be
limited to appearance keys. Reject command, shell, working-directory, keybind, clipboard, and
runtime lifecycle keys.

The advanced editor should validate by loading the fragment into a temporary
`ghostty_config_t`, finalizing it, and surfacing parse diagnostics before applying to live
surfaces.

## Ghostty Config Builder

Introduce a dedicated builder:

```swift
struct TerminalGhosttyConfigBuilder {
    func makeConfig(
        resolvedAppearance: ResolvedTerminalAppearance,
        workingDirectory: String?
    ) -> ghostty_config_t?
}
```

Responsibilities:

* Emit Conductor-owned hard requirements first:
  * `macos-background-from-layer = true`
  * `macos-titlebar-proxy-icon = hidden`
  * `shell-integration = none`
* Emit resolved font settings.
* Emit resolved color/theme settings.
* Emit cursor and background settings.
* Emit validated advanced appearance fragment last, except for protected keys.
* Finalize the config and keep ownership rules explicit.

`GhosttyAppRuntime.makeConfig` can delegate to this builder. `TerminalSurface` should store the
last `ResolvedTerminalAppearance` it applied, not just theme and font size.

## Runtime Application Flow

### New surface

1. `ConductorWindowModel.surface(for:)` resolves appearance for the tab.
2. `TerminalSurface.init` stores the resolved appearance.
3. `TerminalSurface.attachIfPossible()` starts Ghostty if needed and creates
   `ghostty_surface_config_s`.
4. `font_size` in the surface config mirrors the resolved font size for initial creation.
5. Immediately after creation, call `applyAppearance(resolvedAppearance)` so colors and advanced
   settings are aligned.

### Existing surface update

1. Settings mutate low-frequency appearance state.
2. `ConductorWindowModel` computes affected terminal IDs:
   * Global change: all terminals without detached field overrides.
   * Workspace change: terminals in that workspace without detached field overrides.
   * Terminal change: only that terminal.
3. Each affected `TerminalSurface` receives a resolved appearance.
4. `TerminalSurface` compares it with the applied appearance.
5. If changed, build a new Ghostty config, call `ghostty_surface_update_config`, refresh once,
   and update the applied snapshot.

Coalesce slider changes with a short debounce so dragging font size or opacity does not create
excessive config reloads.

## Settings UI

Use the existing Settings panel, but promote terminal appearance into a dedicated section:

* Interface
* Terminal Appearance
* Profiles
* Commands

### Terminal Appearance section

Top bar:

* Scope segmented control: Global, Current Workspace, Selected Terminal.
* Inheritance indicator: “Inherits Global”, “Overrides Font”, “Overrides Colors”.
* Reset button for the current scope.

Tabs:

* Presets: packaged themes and user profiles.
* Font: family picker, fallback chain, size slider, cell width/height steppers, feature toggles.
* Colors: swatches for foreground/background, ANSI 0-15, cursor, selection.
* Cursor: style, blink, color link/unlink.
* Background: opacity and optional image controls.
* Advanced: validated appearance-only Ghostty config fragment.

Preview:

* Use a synthetic terminal sample, not live scrollback.
* Show normal text, bold, italic, ANSI color rows, selection, cursor, and CJK sample text.
* The preview can be SwiftUI because it is static product UI, not terminal output.
* For final confidence, an optional live preview can apply to the selected terminal only after
  user interaction, with a Cancel/Revert affordance.

### Profiles section

* Duplicate packaged theme into editable user profile.
* Rename, duplicate, delete user profiles.
* Import Ghostty theme fragment.
* Export profile as Conductor JSON and Ghostty theme fragment.
* Mark a profile as default global/workspace.

## Commands And Menus

Expose primary commands in menus and command palette:

* Open Terminal Appearance Settings: `Cmd-,` opens settings, terminal section selected.
* Increase Terminal Font Size.
* Decrease Terminal Font Size.
* Reset Terminal Font Size.
* Cycle Terminal Profile.
* Reset Selected Terminal Appearance.
* Reset Workspace Terminal Appearance.
* Duplicate Current Appearance as Profile.

Do not override standard copy/paste/editing shortcuts. Respect Ghostty-owned terminal keybindings
when the terminal is first responder unless the command is clearly app-level.

## Persistence And Migration

Persistence rules:

* Existing `appearance.terminalFontSize` migrates into global terminal font settings.
* Existing `theme` remains the shell theme and initial terminal color source.
* New global terminal appearance fields decode with packaged defaults.
* Workspace and terminal overrides decode as nil by default.
* Unknown user profile IDs fall back to packaged default while preserving the unresolved ID in
  diagnostics if possible.

Storage locations:

* Global profile store in `PersistedWindowState`.
* Workspace override in `WorkspaceState`.
* Terminal override in `TerminalTabState`.

## Import And Export

Import:

* Ghostty theme fragment for colors.
* Conductor profile JSON for complete settings.
* Raw Ghostty config import should extract only appearance allowlist keys.

Export:

* Ghostty theme fragment for color-only sharing.
* Conductor profile JSON for full fidelity.

Do not import command, shell, keybind, working-directory, or automation settings through this
appearance surface.

## Error Handling

* Invalid color: reject before saving.
* Missing font: keep profile, mark font unavailable, fall back to default at render time.
* Invalid advanced config: keep editor text, do not apply, show compact error.
* Ghostty config allocation/finalization failure: keep previous applied appearance and log.
* Live update failure: leave the surface on its previous applied snapshot.

## Testing

Model tests:

* Appearance inheritance resolution.
* Partial override merging.
* Migration from `appearance.terminalFontSize`.
* Unknown profile fallback.
* Reset workspace/terminal overrides.

Config builder tests:

* Font family emits repeatable `font-family` lines.
* Color settings emit expected Ghostty lines.
* Protected keys are rejected from advanced fragments.
* Invalid fragments do not produce an applied config.

App/model checks:

* `ConductorModelCheck`
* `swift build`
* `./Scripts/check-conductor.sh`

Manual smoke:

* Change global profile while multiple panes stream output.
* Override one workspace and verify another workspace is unchanged.
* Override one terminal and verify global changes do not detach unrelated fields.
* Drag split dividers after font and background changes.
* Import/export a Ghostty theme fragment.
* Test CJK sample rendering with fallback fonts.

## Phasing

This is the full design, but implementation should still land in coherent slices:

1. Core model, resolver, config builder, tests.
2. Global settings UI with full font/color/cursor controls.
3. Workspace and terminal override UI.
4. Profiles, import/export, and advanced fragment validation.
5. Background image/blur if validation shows it behaves well with the host layer.

Each slice should keep the data model forward-compatible with the full design.
