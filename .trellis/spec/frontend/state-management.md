# State Management

> How state is managed in this project.

---

## Overview

State is split by frequency and ownership. SwiftUI state may represent user-visible product metadata. Ghostty/AppKit runtime state owns terminal output, scrollback, selection, focus mechanics, and rendering invalidation.

The main rule: terminal output must not drive SwiftUI diffing.

---

## State Categories

Use these categories:

- Product state: workspaces, selected workspace, split tree, sidebar visibility, settings, command palette state.
- Display metadata: title, cwd, git branch, listening ports, agent status, unread count, latest notification summary.
- Runtime state: Ghostty surface pointer, PTY output, scrollback, cursor, selection, Metal layer, WebKit instances.
- Background derived state: git probes, port scans, hook parsing, transcript summaries, health/performance counters.

Only product state and compact display metadata should be observable by SwiftUI.

---

## When to Use Global State

Promote state only when multiple independent UI regions need the same compact value. A sidebar row does not need the terminal transcript; it needs a small display model.

Global state should be segmented by workspace and surface ID so one terminal update does not invalidate the entire app shell.

Persisted product state should be debounced. Split dragging, tab reordering, focus changes,
and theme changes may update observable workspace state rapidly; they must not synchronously
write to disk on every intermediate frame. Flush the latest snapshot during app termination.

---

## Server State

This project may have local automation, browser, or future cloud features, but terminal runtime remains local-first. Treat external data as snapshots that update UI at controlled boundaries.

For runtime metadata extraction:

- Parse output and hooks off the main thread when possible.
- Coalesce frequent events into snapshots.
- Publish snapshots at a bounded cadence, normally 10-30 Hz for visible UI.
- Prefer explicit terminal escape sequences or hooks over scanning complete scrollback.
- Agent hook bridges should pass only compact structured events into the app, such as
  terminal ID, agent name, lifecycle action, cwd, title, and a short body. Do not pipe full
  transcripts or raw conversation history through SwiftUI-observed state. For local CLI
  hooks, use the terminal's injected stable ID and deliver a small notification event to the
  running app, then let `ConductorWindowModel` resolve current workspace/pane ownership.

---

## Common Mistakes

Forbidden patterns:

- Storing complete agent conversations in observable UI state.
- Publishing on every stdout chunk.
- Updating global app state on every cursor movement or terminal redraw.
- Scanning full scrollback to compute sidebar metadata.
- Making SwiftUI view identity depend on runtime counters, transcript length, or output hashes.

## Scenario: Persisted Appearance Preferences

### 1. Scope / Trigger

- Trigger: Shell appearance preferences such as theme, density, chrome clarity, font scale,
  terminal font size, and reduced motion are added to the user-facing settings surface.
- Scope: These preferences are low-frequency product state. They may affect SwiftUI chrome
  dimensions, material tint, strokes, and motion policy, but they must not alter terminal
  transcript, scrollback, cursor, or Ghostty runtime identity.

### 2. Signatures

- `struct AppearancePreferences: Codable, Equatable`
- `enum AppearanceDensity: String, CaseIterable, Codable, Identifiable`
- `enum ChromeClarity: String, CaseIterable, Codable, Identifiable`
- `enum AppearanceFontScale: String, CaseIterable, Codable, Identifiable`
- `AppearancePreferences.terminalFontSize: CGFloat`
- `ConductorWindowModel.appearance: AppearancePreferences`
- `ConductorWindowModel.setTerminalFontSize(_:)`
- `TerminalSurface.applyTerminalFontSize(_:)`
- `GhosttyAppRuntime.makeConfig(theme:terminalFontSize:)`
- `WorkspacePersistence.save(workspaces:selectedWorkspaceID:theme:appearance:)`
- `TerminalTheme.shellPanelBackground`, `shellPanelStrong`, `shellStroke`,
  `shellSelectedFill`, `shellHoverFill`, `shellControlFill`, `shellControlRaisedFill`,
  `settingsPanelBase`, `settingsPanelWash`, `settingsControlFill`, `settingsStroke`,
  `floatingPanelBase`, `floatingPanelWash`, `floatingControlFill`,
  `floatingControlStrongFill`, `floatingStroke`, and `terminalOuterStroke`
- `EnvironmentValues.conductorTheme: TerminalTheme`

### 3. Contracts

- `AppearancePreferences` must have explicit defaults so older `window-state.json` files
  decode safely when they do not contain an `appearance` field.
- Packaged first-run defaults are `TerminalTheme.graphite`, English language, and a
  15pt terminal font size. Existing persisted user settings must not be overwritten.
- `ConductorWindowModel.appearance` is the only published source of truth for shell
  appearance preferences.
- Persistence writes the current appearance snapshot alongside workspace structure and theme.
- `TerminalTheme` is the whole-shell preset source of truth. It owns terminal colors plus
  low-frequency SwiftUI chrome colors for sidebar/settings panels, selection, hover,
  strokes, controls, window backdrop, accent, and terminal pane outline.
- Root shell must inject the selected `TerminalTheme` through `\.conductorTheme` so leaf
  shell components can update together without receiving theme parameters manually.
- Shell chrome containers that avoid observing the full window model must receive low-frequency
  visual state such as `TerminalTheme` and `AppearancePreferences` as explicit value inputs.
  They may keep the model reference for commands, but must not rely on an unobserved model
  reference for current theme/density/clarity values, toolbar command enablement, or panel
  active states.
- Density can change toolbar, workspace tab, pane tab, and sidebar chrome dimensions.
- Chrome clarity can change material tint and stroke emphasis.
- Font scale can change SwiftUI shell text and icon labels in toolbar, sidebar, settings,
  workspace tabs, and pane tabs.
- Terminal font size is a dedicated low-frequency product preference. It is persisted in
  `AppearancePreferences`, clamped to the supported range, applied to existing
  `TerminalSurface` instances through Ghostty config updates, and passed to new surface
  creation through `ghostty_surface_config_s.font_size`.
- Terminal font size must not store measured terminal font metrics, scroll offsets, or
  transcript-derived values in SwiftUI state.
- Reduced motion can disable or shorten shell chrome animations, but must not change model
  semantics.

### 4. Validation & Error Matrix

- Missing `appearance` in persisted state -> load `AppearancePreferences()` defaults.
- Unknown enum raw value in persisted state -> persisted state may fail to decode and should
  fall back to a fresh valid workspace state rather than crashing.
- Invalid workspace plus valid appearance -> reject the invalid workspace; do not resurrect
  unsafe layout data just to keep appearance settings.
- Appearance change while terminals are streaming output -> only shell chrome invalidates;
  terminal output remains outside SwiftUI state.
- Theme change while terminals are streaming output -> Ghostty config/terminal host color
  updates may occur, but SwiftUI observes only the compact `TerminalTheme` value and theme
  derived chrome colors.
- Theme change from Settings -> same result as theme change from the sidebar/menu route:
  `ConductorWindowModel.theme` mutates, root `\.conductorTheme` updates, the open Settings
  panel restyles immediately, selected theme UI state moves to the new value, sidebar rows and
  workspace tabs restyle without requiring a workspace/tab switch, live terminal surfaces
  receive appearance updates, and persistence records the new theme.
- Terminal font size change while terminals are streaming output -> Ghostty receives a
  bounded config update per live surface; terminal transcript, scrollback, cursor, and
  measured cell metrics remain owned by Ghostty/AppKit.

### 5. Good/Base/Bad Cases

- Good: Switching density changes tab rail heights while the same Ghostty host views remain
  alive.
- Good: Switching theme changes window backdrop, sidebar/settings chrome, command surfaces,
  terminal chrome, accent, and Ghostty color config as one preset.
- Good: Theme selection rows in Settings and the sidebar theme menu use the same model
  mutation behavior, so both immediately update the shell and terminal surfaces.
- Good: Equatable workspace/sidebar/tab content that reads appearance environment includes a
  theme/font-scale identity in equality, so global appearance changes are not delayed until
  selection state changes.
- Good: Reduced motion disables panel and tab-scroll animation through a transaction.
- Base: A user upgrades from a state file that only contains `theme`; appearance defaults to
  standard density, balanced clarity, and normal motion.
- Bad: Storing measured scroll offsets, terminal font metrics, or transcript-derived values in
  `AppearancePreferences`.
- Bad: Treating `AppearanceFontScale` as a Ghostty terminal font-size control. Shell font
  scale and terminal font size are separate preferences.
- Bad: Applying opacity, scale, or identity transitions to `TerminalSurfaceRepresentable` when
  appearance changes.
- Bad: Wrapping a Settings panel in an equality/cache optimization that skips environment
  updates after `ConductorWindowModel.theme` or `appearance` changes.
- Bad: A sidebar row or workspace tab reads `\.conductorTheme` inside an `.equatable()` leaf
  but equality ignores the theme, causing the chrome to update only after switching
  workspace/tab selection.
- Bad: A sidebar or toolbar container is not an `@ObservedObject`, reads `model.theme` for
  drawing, and only refreshes when `WorkspaceChromeSnapshot` changes.
- Bad: Toolbar buttons read `model.workspace.isZoomed` or panel visibility directly from an
  unobserved model reference, so active/disabled state changes wait for an unrelated tab or
  workspace chrome update.
- Bad: Hard-coding fixed white/black opacity fills for selected sidebar/settings rows when a
  `TerminalTheme` shell color exists.
- Bad: Deleting or replacing the selected workspace, assigning `workspace` to a successor,
  and letting `workspace.didSet` sync the old selected workspace back into `workspaces`.
  Controlled list mutations must use a guarded assignment path so close/reset operations do
  not resurrect the item the user just removed.

### 6. Tests Required

- `swift build`
- `ConductorModelCheck`
- Full Conductor gate: `./Scripts/check-conductor.sh`
- Manual smoke: switch density and clarity while multiple panes are visible; terminal surfaces
  should keep focus and content.
- Manual smoke: switch themes from Settings and from the sidebar/menu route while Settings is
  open; assert the selected row, panel chrome, main window, terminal chrome/background, and
  persisted theme all update.
- Manual smoke: enable reduced motion, open and close Appearance Center / Command Center /
  Workspace Overview; shell transitions should quiet down without blocking controls.

### 7. Wrong vs Correct

#### Wrong

```swift
@Published var terminalFontMetricsByPane: [PaneID: TerminalFontMetrics]
```

#### Correct

```swift
@Published var appearance = AppearancePreferences()
```

#### Wrong

```swift
.background(ConductorDesign.selectedFill)
```

#### Correct

```swift
@Environment(\.conductorTheme) private var theme

.background(theme.shellSelectedFill)
```

#### Wrong

```swift
TerminalSurfaceRepresentable(...)
    .scaleEffect(appearance.density == .compact ? 0.98 : 1)
```

#### Correct

```swift
.frame(height: model.appearance.density.paneTabRailHeight)
```
