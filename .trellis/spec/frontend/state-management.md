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

- Trigger: Shell appearance preferences such as theme, density, chrome clarity, reduced
  motion, and future font scale are added to the user-facing settings surface.
- Scope: These preferences are low-frequency product state. They may affect SwiftUI chrome
  dimensions, material tint, strokes, and motion policy, but they must not alter terminal
  transcript, scrollback, cursor, or Ghostty runtime identity.

### 2. Signatures

- `struct AppearancePreferences: Codable, Equatable`
- `enum AppearanceDensity: String, CaseIterable, Codable, Identifiable`
- `enum ChromeClarity: String, CaseIterable, Codable, Identifiable`
- `ConductorWindowModel.appearance: AppearancePreferences`
- `WorkspacePersistence.save(workspaces:selectedWorkspaceID:theme:appearance:)`

### 3. Contracts

- `AppearancePreferences` must have explicit defaults so older `window-state.json` files
  decode safely when they do not contain an `appearance` field.
- `ConductorWindowModel.appearance` is the only published source of truth for shell
  appearance preferences.
- Persistence writes the current appearance snapshot alongside workspace structure and theme.
- Density can change toolbar, workspace tab, pane tab, and sidebar chrome dimensions.
- Chrome clarity can change material tint and stroke emphasis.
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

### 5. Good/Base/Bad Cases

- Good: Switching density changes tab rail heights while the same Ghostty host views remain
  alive.
- Good: Reduced motion disables panel and tab-scroll animation through a transaction.
- Base: A user upgrades from a state file that only contains `theme`; appearance defaults to
  standard density, balanced clarity, and normal motion.
- Bad: Storing measured scroll offsets, terminal font metrics, or transcript-derived values in
  `AppearancePreferences`.
- Bad: Applying opacity, scale, or identity transitions to `TerminalSurfaceRepresentable` when
  appearance changes.

### 6. Tests Required

- `swift build`
- `ConductorModelCheck`
- Full Conductor gate: `./Scripts/check-conductor.sh`
- Manual smoke: switch density and clarity while multiple panes are visible; terminal surfaces
  should keep focus and content.
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
TerminalSurfaceRepresentable(...)
    .scaleEffect(appearance.density == .compact ? 0.98 : 1)
```

#### Correct

```swift
.frame(height: model.appearance.density.paneTabRailHeight)
```
