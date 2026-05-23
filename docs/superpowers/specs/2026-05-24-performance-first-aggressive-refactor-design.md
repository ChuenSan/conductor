# Performance-First Aggressive Refactor Design

## Goal

Refactor Conductor into a performance-first native macOS terminal workspace where no feature relies on large SwiftUI render batches, terminal hot paths stay isolated from app chrome, and every visible control has clear state, behavior, and styling.

This is not a cosmetic file split. Structural changes are only justified when they reduce invalidation scope, isolate expensive work, prevent accidental bulk rendering, or make future performance regressions harder to introduce.

## Current Diagnosis

The core terminal architecture is fundamentally sound: live terminal output stays inside GhosttyKit/AppKit surfaces, while SwiftUI owns compact product state. The main reliability risk is not the terminal renderer; it is the shell around it growing into broad observable objects and very large SwiftUI files.

The most important pressure points are:

- `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`: one model coordinates workspace state, terminal surfaces, panels, notifications, settings, file tabs, font downloads, drag state, menus, and command routing.
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`: root shell, settings, command palette, workspace overview, sidebar, toolbar, workspace tabs, and many reusable controls live in one very large file.
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`: file services, store, display snapshots, file operations, previews, AppKit bridges, and UI controls live together.
- Repeated UI surfaces still have opportunities to render or compute more than the user can see, especially file trees, settings rows, document/file previews, notifications, workspace/tab chrome, and panels.

## Hard Rules

These rules apply to the whole project.

1. SwiftUI `body` must not perform large filtering, sorting, recursive tree expansion, filesystem checks, parsing, preview generation, or repeated model scans.
2. Views must not render content that is not visible, expanded, selected, or within a bounded viewport/window.
3. Repeated content must use one of: lazy SwiftUI containers for small bounded lists, pagination/windowing for medium lists, AppKit-backed tables/text views for large lists, or a cached compact snapshot.
4. Leaf views must not observe the entire window model. They receive compact immutable snapshots and use coordinator references only for commands.
5. Terminal surfaces must keep stable AppKit identity across tab changes, split changes, panel toggles, theme changes, and workspace switches.
6. Split resize, terminal focus, tab selection, workspace switching, and Ghostty input must not depend on panel state, file-manager state, document-preview state, or settings state.
7. Animations must not wrap live terminal surfaces or large repeated content. They may animate lightweight chrome only.
8. Every command button must expose a clear enabled state, active state where relevant, tooltip or accessible label, and shared visual treatment.

## Target Architecture

### State And Coordination

`ConductorWindowModel` becomes a thin composition root. It remains the SwiftUI-observed entry point during migration, but its responsibilities are moved into focused coordinators:

- `WorkspaceCoordinator`: workspace list, selected workspace, split/tree operations, tab moves, workspace activation, and workspace persistence snapshots.
- `TerminalSurfaceCoordinator`: `TerminalSurface` lifecycle, focus reconciliation, surface creation, surface closing, appearance application, and navigation refreshes.
- `PanelCoordinator`: command palette, settings, workspace overview, terminal search, file manager panel request, and mutually exclusive panel behavior.
- `NotificationCoordinator`: terminal notifications, unread state, notification panel state, notification navigation, and compact notification metadata.
- `FileWorkspaceCoordinator`: workspace file tabs, dirty state, save tokens, external-change flags, file-tab selection, and local file URL routing.
- `AppearanceCoordinator`: theme, density, language, font scale, terminal font size, renderer preferences, font imports/downloads, and persistence-ready appearance snapshots.

The migration may keep `ConductorWindowModel` as the public facade so existing views and command handlers can move incrementally. Internally, direct fields should shrink over time until the facade mostly delegates and publishes compact snapshots.

### Snapshot Boundaries

Each UI region receives a dedicated snapshot:

- `ShellChromeSnapshot`: selected workspace, sidebar state, active panels, command enablement, theme identity, appearance identity.
- `WorkspaceChromeSnapshot`: workspace rows, workspace file tabs, selected IDs, unread counts, drag/drop state, tab counts, pane counts.
- `ToolbarChromeSnapshot`: split, zoom, panel, file-manager, notification, and command states for every toolbar button.
- `TerminalStageSnapshot`: visible split root, focused pane, zoom state, pane chrome snapshots, and surface lookup tokens.
- `SettingsSnapshot`: only values displayed by the current settings section and its visible rows.
- `FileManagerDisplaySnapshot`: visible file rows only, current selection summary, operation state, preview header state, and bounded child row windows.
- `NotificationDisplaySnapshot`: visible notification rows only, unread totals, selected/jump target state.

Snapshots are value types, `Equatable` where useful, and created outside view bodies. A view that draws repeated rows should not ask the model for individual row values during rendering.

## Rendering Policy

### Small Lists

Small lists are lists with a hard project-owned cap, usually below 100 items. Examples: toolbar buttons, command groups, known theme presets, known terminal font presets. They may use SwiftUI `ForEach` directly if all row models are precomputed.

### Medium Lists

Medium lists are user-controlled collections that can grow but are still expected to be manageable. Examples: workspace tabs, notification summaries, settings rows, command palette results. They must use lazy containers or explicit visible windows. Search/filter work happens in stores or snapshot builders, not row bodies.

### Large Lists

Large lists include directories, file search results, long previews, tables, CSV/TSV rows, JSON trees, logs, command output files, and any user data that can grow without a product-owned cap. These must use AppKit-backed views or explicit virtualization/windowing. SwiftUI should render only the container, controls, and compact metadata.

### Previews

Text, source, log, table, key-value, structured data, document, and image previews must render through a selected preview host. Only the selected file preview is loaded. Large previews must use AppKit/WebKit/native hosts with bounded input and cancellation. No preview may force the file tree or terminal stage to re-render.

## UI Module Layout

The target file organization under `Apps/Conductor/Sources/Conductor/UI/` is:

```text
UI/
  Shell/
    ShellRootView.swift
    ShellChromeSnapshot.swift
    ShellPanelHost.swift
  Sidebar/
    ConductorSidebar.swift
    SidebarRows.swift
    SidebarControls.swift
  Toolbar/
    ConductorToolbar.swift
    ToolbarChromeSnapshot.swift
    ToolbarButtons.swift
  WorkspaceTabs/
    WorkspaceTabStrip.swift
    WorkspaceTabModels.swift
    WorkspaceTabButtons.swift
  Settings/
    SettingsPanel.swift
    SettingsSnapshot.swift
    SettingsSections.swift
    SettingsControls.swift
    TerminalSettingsViews.swift
    AppearanceSettingsViews.swift
  CommandPalette/
    CommandPaletteView.swift
    CommandPaletteModels.swift
    CommandPaletteFiltering.swift
  WorkspaceOverview/
    WorkspaceOverviewPanel.swift
    WorkspaceOverviewModels.swift
  Notifications/
    NotificationPanelView.swift
    NotificationDisplaySnapshot.swift
  FileManager/
    FileManagerPanel.swift
    FileManagerStore.swift
    FileManagerService.swift
    FileManagerDisplaySnapshot.swift
    FileManagerListView.swift
    FileManagerControls.swift
    FileManagerOperations.swift
    FilePreviewHost.swift
    FilePreviewModels.swift
    FilePreviewAppKitHosts.swift
  Controls/
    ConductorButton.swift
    ConductorIconButton.swift
    ConductorSegmentedControl.swift
    ConductorMenuButton.swift
    ConductorToggleRow.swift
```

Existing files can remain as compatibility shells during migration, but new implementation should move toward these boundaries.

## Button And Control Quality

Every button must be represented by a compact model:

```swift
struct ConductorControlState: Equatable, Sendable {
    var id: String
    var title: String?
    var systemImage: String
    var isEnabled: Bool
    var isActive: Bool
    var tooltip: String
    var accessibilityLabel: String
}
```

Toolbar, sidebar rail, tab close, panel close, command, settings, file-manager, and notification actions should use shared controls unless a native AppKit bridge is required. A control is incomplete if it lacks disabled styling, hover/pressed styling, accessibility text, keyboard relationship where applicable, and a single command route.

Command execution stays centralized through `ConductorShellCommand` and coordinator/facade methods. A button should not patch model internals directly.

## Performance Instrumentation

The refactor must add lightweight observability around high-risk paths:

- snapshot rebuild counts for shell, workspace chrome, settings, file manager, notifications;
- surface create/attach/close counts;
- panel open/close timing;
- file-manager directory scan timing and visible row counts;
- preview load timing and input sizes;
- split resize event counts and surface geometry update counts.

Instrumentation must never log terminal transcript text, file content, secrets, or raw command output.

## Migration Strategy

### Phase 1: Guardrails And Measurement

Create project-level rendering rules in code form where possible. Add debug counters/signposts around snapshot creation, panel opening, file-manager rows, preview loads, and terminal surface lifecycle. Establish baseline checks with `swift build`, `swift run ConductorModelCheck`, and `./Scripts/check-conductor.sh`.

### Phase 2: Coordinator Extraction

Extract coordinators behind the existing `ConductorWindowModel` facade. Start with low-risk domains:

1. `PanelCoordinator`
2. `NotificationCoordinator`
3. `AppearanceCoordinator`
4. `FileWorkspaceCoordinator`
5. `TerminalSurfaceCoordinator`
6. `WorkspaceCoordinator`

Each extraction must preserve public behavior and keep the full gate green.

### Phase 3: Shell Snapshot And UI Split

Move root shell, sidebar, toolbar, workspace tabs, command palette, settings, and overview into feature folders. Replace direct model observation in leaves with compact snapshots. Keep root observation coarse but intentional.

### Phase 4: File Manager And Preview Rewrite

Split file manager service/store/UI/preview hosts. Enforce visible-row rendering and selected-preview-only loading. Large files and large tables must use AppKit-backed or virtualized hosts. Directory expansion must be incremental and cancellable.

### Phase 5: Settings And Controls Polish

Rebuild settings as section-scoped panels that only render the selected section. Replace custom one-off buttons with shared control components. Audit every button for state, tooltip, accessibility, visual consistency, and command routing.

### Phase 6: Whole-App Regression And Cleanup

Run full gate repeatedly, then perform manual smoke passes for big directory browsing, settings switching, split resizing under terminal output, workspace switching, notifications, file preview, theme changes, and reduced motion. Remove compatibility shims only when callers have migrated.

## Testing Strategy

Automated checks:

- `cd Apps/Conductor && swift build`
- `cd Apps/Conductor && swift run ConductorModelCheck`
- `cd Apps/Conductor && ./Scripts/check-conductor.sh`

Additional model checks should cover:

- coordinator/facade behavior parity for workspace, panels, notifications, file tabs, and appearance;
- snapshot builders producing bounded rows;
- file-manager display snapshot limiting visible output;
- settings snapshot exposing only current-section display values;
- terminal surface count stability during panel toggles, tab selection, workspace switching, and split resize.

Manual checks:

- Open a large directory and confirm only visible rows are rendered.
- Open large text/table/structured files and confirm preview uses bounded/AppKit-backed rendering.
- Toggle Settings sections rapidly and confirm terminal focus/split geometry stay stable.
- Resize splits while terminal output is active.
- Switch workspaces and tabs while notification and file panels are open.
- Verify every toolbar/sidebar/panel button has enabled/disabled/active/hover states and a useful tooltip or accessibility label.

## Non-Goals

This refactor does not replace GhosttyKit, rewrite terminal rendering, change terminal transcript ownership, redesign the entire product visually from scratch, or introduce a separate state-management framework. It improves the existing native architecture by enforcing performance boundaries and modular ownership.

## Acceptance Criteria

The refactor is successful when:

- no large user-controlled collection is rendered eagerly in SwiftUI;
- `ConductorWindowModel` no longer owns every domain directly;
- major UI files are split by responsibility;
- terminal surfaces remain stable through all shell interactions;
- panel toggles and file previews do not trigger terminal-stage churn;
- large file/directory paths are lazy, virtualized, bounded, or AppKit-backed;
- full Conductor gate passes;
- controls are visually consistent, accessible, and stateful.
