# Performance-First Aggressive Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Conductor performance-first across the whole app: no eager rendering of large user-controlled content, stable terminal hot paths, modular coordinators, focused UI files, and polished controls.

**Architecture:** Keep `ConductorWindowModel` as the compatibility facade while extracting app coordinators, compact snapshots, rendering budgets, feature folders, and shared controls. The refactor proceeds in small commits; each commit must build, and cross-layer commits must pass the full gate.

**Tech Stack:** Swift 6, SwiftUI, AppKit, GhosttyKit, SwiftPM, `ConductorModelCheck`, `./Scripts/check-conductor.sh`.

---

## Important Target Boundary

`ConductorModelCheck` depends on `ConductorCore`, not the `Conductor` executable target. Only `ConductorCore` types are tested there. App/UI/Terminal coordinator work is verified with `swift build`, existing automation in `check-conductor.sh`, and manual smoke passes.

---

## File Structure

Create these files and folders during the refactor:

```text
Apps/Conductor/Sources/ConductorCore/Shared/RenderBudget.swift
Apps/Conductor/Sources/Conductor/Shared/RenderCounter.swift
Apps/Conductor/Sources/Conductor/App/Coordinators/
Apps/Conductor/Sources/Conductor/UI/Controls/
Apps/Conductor/Sources/Conductor/UI/Shell/
Apps/Conductor/Sources/Conductor/UI/Sidebar/
Apps/Conductor/Sources/Conductor/UI/Toolbar/
Apps/Conductor/Sources/Conductor/UI/WorkspaceTabs/
Apps/Conductor/Sources/Conductor/UI/Settings/
Apps/Conductor/Sources/Conductor/UI/CommandPalette/
Apps/Conductor/Sources/Conductor/UI/WorkspaceOverview/
Apps/Conductor/Sources/Conductor/UI/FileManager/
Apps/Conductor/Sources/Conductor/UI/Notifications/
```

Legacy files remain as compatibility shells until call sites are migrated:

```text
Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift
Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift
```

---

## Task 1: Add Render Budgets, Counters, And Control State

**Files:**
- Create: `Apps/Conductor/Sources/ConductorCore/Shared/RenderBudget.swift`
- Create: `Apps/Conductor/Sources/Conductor/Shared/RenderCounter.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Controls/ConductorControlState.swift`
- Modify: `Apps/Conductor/Sources/ConductorModelCheck/main.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

- [ ] **Step 1: Add a failing core check**

In `Apps/Conductor/Sources/ConductorModelCheck/main.swift`, add:

```swift
func checkRenderBudgetDefaults() {
    require(RenderBudget.smallListLimit == 100, "small render budget should be capped")
    require(RenderBudget.mediumListLimit == 250, "medium render budget should be capped")
    require(RenderBudget.largeListPreviewLimit == 1_000, "large preview budget should be bounded")
    require(RenderBudget.visibleRowWindow(defaultVisibleCount: 40, overscan: 12) == 64, "visible row window should include overscan")
}
```

Call it with the other checks:

```swift
checkRenderBudgetDefaults()
```

- [ ] **Step 2: Verify the check fails**

Run:

```bash
cd Apps/Conductor
swift run ConductorModelCheck
```

Expected: FAIL because `RenderBudget` does not exist in `ConductorCore`.

- [ ] **Step 3: Add `RenderBudget` to ConductorCore**

Create `Apps/Conductor/Sources/ConductorCore/Shared/RenderBudget.swift`:

```swift
import Foundation

public enum RenderBudget {
    public static let smallListLimit = 100
    public static let mediumListLimit = 250
    public static let largeListPreviewLimit = 1_000
    public static let defaultVisibleRows = 40
    public static let defaultOverscanRows = 12

    public static func visibleRowWindow(
        defaultVisibleCount: Int = defaultVisibleRows,
        overscan: Int = defaultOverscanRows
    ) -> Int {
        max(1, defaultVisibleCount + overscan * 2)
    }
}
```

- [ ] **Step 4: Add app-level render counters**

Create `Apps/Conductor/Sources/Conductor/Shared/RenderCounter.swift`:

```swift
import Foundation

enum RenderCounter {
    private static var counts: [String: Int] = [:]

    static func increment(_ name: String) {
        counts[name, default: 0] += 1
        ConductorDiagnostics.record(
            "render-counter",
            fields: [
                "name": name,
                "count": counts[name, default: 0]
            ]
        )
    }

    static func value(_ name: String) -> Int {
        counts[name, default: 0]
    }

    static func reset() {
        counts.removeAll(keepingCapacity: true)
    }
}
```

- [ ] **Step 5: Add shared control state**

Create `Apps/Conductor/Sources/Conductor/UI/Controls/ConductorControlState.swift`:

```swift
import Foundation

struct ConductorControlState: Equatable, Identifiable, Sendable {
    let id: String
    let title: String?
    let systemImage: String
    let isEnabled: Bool
    let isActive: Bool
    let tooltip: String
    let accessibilityLabel: String

    init(
        id: String,
        title: String? = nil,
        systemImage: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        tooltip: String,
        accessibilityLabel: String
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
    }
}
```

- [ ] **Step 6: Instrument existing hot snapshot points**

Add these counter calls without changing behavior:

```swift
RenderCounter.increment("workspace-chrome-snapshot")
RenderCounter.increment("toolbar-chrome-snapshot")
RenderCounter.increment("file-manager-display-snapshot")
RenderCounter.increment("metadata-publish")
```

Locations:

- start of `WorkspaceChromeSnapshot` creation in `ConductorRootView.swift`;
- start of `ToolbarChromeSnapshot` creation in `ConductorRootView.swift`;
- start of `FileManagerDisplaySnapshotBuilder.build` in `FileManagerPanel.swift`;
- immediately before `metadataByTerminalID` assignment in `ConductorWindowModel.scheduleMetadataPublish()`.

- [ ] **Step 7: Verify**

Run:

```bash
cd Apps/Conductor
swift build
swift run ConductorModelCheck
```

Expected: both commands pass.

- [ ] **Step 8: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Shared/RenderBudget.swift \
  Apps/Conductor/Sources/Conductor/Shared/RenderCounter.swift \
  Apps/Conductor/Sources/Conductor/UI/Controls/ConductorControlState.swift \
  Apps/Conductor/Sources/ConductorModelCheck/main.swift \
  Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift \
  Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift \
  Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "perf: add render budgets and counters"
```

---

## Task 2: Extract Low-Risk Coordinators Behind `ConductorWindowModel`

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/App/Coordinators/PanelCoordinator.swift`
- Create: `Apps/Conductor/Sources/Conductor/App/Coordinators/AppearanceCoordinator.swift`
- Create: `Apps/Conductor/Sources/Conductor/App/Coordinators/FileWorkspaceCoordinator.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

- [ ] **Step 1: Add `PanelCoordinator`**

Create `PanelCoordinator.swift`:

```swift
import Foundation

struct PanelCoordinator: Equatable, Sendable {
    var commandPaletteVisible = false
    var settingsVisible = false
    var workspaceOverviewVisible = false
    var terminalSearchVisible = false

    mutating func toggleCommandPalette() {
        commandPaletteVisible.toggle()
        if commandPaletteVisible {
            settingsVisible = false
            workspaceOverviewVisible = false
            terminalSearchVisible = false
        }
    }

    mutating func toggleSettings() {
        settingsVisible.toggle()
        if settingsVisible {
            commandPaletteVisible = false
            workspaceOverviewVisible = false
            terminalSearchVisible = false
        }
    }

    mutating func toggleWorkspaceOverview() {
        workspaceOverviewVisible.toggle()
        if workspaceOverviewVisible {
            commandPaletteVisible = false
            settingsVisible = false
            terminalSearchVisible = false
        }
    }

    mutating func closeTransientPanels() {
        commandPaletteVisible = false
        settingsVisible = false
        workspaceOverviewVisible = false
        terminalSearchVisible = false
    }

    @discardableResult
    mutating func dismissVisibleShellPanel() -> Bool {
        guard commandPaletteVisible || settingsVisible || workspaceOverviewVisible || terminalSearchVisible else {
            return false
        }
        closeTransientPanels()
        return true
    }
}
```

- [ ] **Step 2: Add `AppearanceCoordinator`**

Create `AppearanceCoordinator.swift`:

```swift
import Foundation

struct AppearanceCoordinator: Equatable {
    private(set) var appearance: AppearancePreferences

    init(appearance: AppearancePreferences) {
        self.appearance = appearance
    }

    mutating func setTerminalFontSize(_ terminalFontSize: CGFloat) {
        let clamped = AppearancePreferences.clampedTerminalFontSize(terminalFontSize)
        appearance.terminalFontSize = (clamped * 2).rounded() / 2
    }

    mutating func setDensity(_ density: AppearanceDensity) {
        appearance.density = density
    }

    mutating func setChromeClarity(_ chromeClarity: ChromeClarity) {
        appearance.chromeClarity = chromeClarity
    }

    mutating func setFontScale(_ fontScale: AppearanceFontScale) {
        appearance.fontScale = fontScale
    }
}
```

- [ ] **Step 3: Add `FileWorkspaceCoordinator`**

Create `FileWorkspaceCoordinator.swift`:

```swift
import Foundation

struct FileWorkspaceCoordinator {
    private(set) var tabs: [ConductorWorkspaceFileTab] = []
    private(set) var dirtyTabIDs: Set<String> = []
    private(set) var externallyChangedTabIDs: Set<String> = []
    private(set) var selectedContentTabID: ConductorWorkspaceContentTabID?

    mutating func openFile(_ fileURL: URL, rootURL: URL) {
        let tab = ConductorWorkspaceFileTab(fileURL: fileURL, rootURL: rootURL)
        tabs = [tab]
        dirtyTabIDs.formIntersection([tab.id])
        externallyChangedTabIDs.formIntersection([tab.id])
        selectedContentTabID = .file(tab.id)
    }

    mutating func setDirty(_ tabID: String, isDirty: Bool) {
        if isDirty {
            dirtyTabIDs.insert(tabID)
        } else {
            dirtyTabIDs.remove(tabID)
        }
    }
}
```

- [ ] **Step 4: Wire coordinators through the facade**

In `ConductorWindowModel.swift`, add coordinator properties, initialize them from existing state, and route existing public methods through them. Keep the existing `@Published` properties as the public compatibility surface.

Mirror panel state through:

```swift
private func publishPanelState() {
    commandPaletteVisible = panelCoordinator.commandPaletteVisible
    settingsPanelVisible = panelCoordinator.settingsVisible
    workspaceOverviewVisible = panelCoordinator.workspaceOverviewVisible
    terminalSearchVisible = panelCoordinator.terminalSearchVisible
}
```

Mirror appearance state by assigning:

```swift
appearance = appearanceCoordinator.appearance
```

Mirror file workspace state by assigning:

```swift
workspaceFileTabs = fileWorkspaceCoordinator.tabs
dirtyWorkspaceFileTabIDs = fileWorkspaceCoordinator.dirtyTabIDs
externallyChangedWorkspaceFileTabIDs = fileWorkspaceCoordinator.externallyChangedTabIDs
selectedWorkspaceContentTabID = fileWorkspaceCoordinator.selectedContentTabID
```

- [ ] **Step 5: Verify**

Run:

```bash
cd Apps/Conductor
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/App/Coordinators \
  Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "refactor: extract initial window coordinators"
```

---

## Task 3: Extract Terminal Surface Coordinator

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/App/Coordinators/TerminalSurfaceCoordinator.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

- [ ] **Step 1: Create surface handlers and coordinator**

Create `TerminalSurfaceCoordinator.swift`:

```swift
import ConductorCore
import Foundation

@MainActor
struct TerminalSurfaceHandlers {
    let install: (TerminalSurface) -> Void
}

@MainActor
final class TerminalSurfaceCoordinator {
    private var surfaces: [TerminalID: TerminalSurface] = [:]
    private var pendingNavigationRefreshTerminalIDs = Set<TerminalID>()

    var runtimeSurfaceCount: Int {
        surfaces.count
    }

    func hasSurface(for terminalID: TerminalID) -> Bool {
        surfaces[terminalID] != nil
    }

    func surface(
        for tab: TerminalTabState,
        theme: TerminalTheme,
        terminalFontSize: CGFloat,
        handlers: TerminalSurfaceHandlers
    ) -> TerminalSurface {
        if let surface = surfaces[tab.id] {
            return surface
        }
        let surface = TerminalSurface(
            id: tab.id,
            theme: theme,
            terminalFontSize: terminalFontSize,
            workingDirectory: tab.workingDirectory
        )
        handlers.install(surface)
        surfaces[tab.id] = surface
        return surface
    }

    func existingSurface(for terminalID: TerminalID) -> TerminalSurface? {
        surfaces[terminalID]
    }

    func closeSurfaces(for terminalIDs: [TerminalID]) {
        for terminalID in terminalIDs {
            surfaces.removeValue(forKey: terminalID)?.close()
            pendingNavigationRefreshTerminalIDs.remove(terminalID)
        }
    }

    func closeAllSurfaces() {
        surfaces.values.forEach { $0.close() }
        surfaces.removeAll()
        pendingNavigationRefreshTerminalIDs.removeAll()
    }

    func applyAppearance(theme: TerminalTheme, terminalFontSize: CGFloat) {
        surfaces.values.forEach {
            $0.applyAppearance(theme: theme, terminalFontSize: terminalFontSize)
        }
    }

    func setFocusedTerminal(_ focusedTerminalID: TerminalID?) {
        for (terminalID, surface) in surfaces {
            surface.setFocused(terminalID == focusedTerminalID)
        }
    }

    func markPendingNavigationRefresh(_ terminalID: TerminalID) -> Bool {
        pendingNavigationRefreshTerminalIDs.insert(terminalID).inserted
    }

    func clearPendingNavigationRefresh(_ terminalID: TerminalID) {
        pendingNavigationRefreshTerminalIDs.remove(terminalID)
    }
}
```

- [ ] **Step 2: Replace raw surface storage**

In `ConductorWindowModel.swift`, replace the raw `surfaces` dictionary and pending navigation set with:

```swift
private let surfaceCoordinator = TerminalSurfaceCoordinator()
```

Route `surface(for:)`, `runtimeSurfaceCount`, `runtimeHasSurface(for:)`, `closeSurfaces(for:)`, `closeAllSurfaces()`, appearance application, and focus reconciliation through the coordinator.

- [ ] **Step 3: Run full gate**

Run:

```bash
cd Apps/Conductor
./Scripts/check-conductor.sh
```

Expected: PASS with `Conductor checks passed`.

- [ ] **Step 4: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/App/Coordinators/TerminalSurfaceCoordinator.swift \
  Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "refactor: isolate terminal surface coordination"
```

---

## Task 4: Split Shell Chrome Modules

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/UI/Shell/ShellChromeSnapshot.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Sidebar/ConductorSidebar.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Toolbar/ConductorToolbar.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/WorkspaceTabs/WorkspaceTabStrip.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`

- [ ] **Step 1: Create shell snapshot**

Create `ShellChromeSnapshot.swift`:

```swift
import ConductorCore
import Foundation

struct ShellChromeSnapshot: Equatable, Sendable {
    let selectedWorkspaceID: WorkspaceID
    let selectedTerminalCount: Int
    let commandPaletteVisible: Bool
    let settingsPanelVisible: Bool
    let workspaceOverviewVisible: Bool
    let notificationPanelVisible: Bool

    init(model: ConductorWindowModel) {
        RenderCounter.increment("shell-chrome-snapshot")
        self.selectedWorkspaceID = model.workspace.id
        self.selectedTerminalCount = model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
        self.commandPaletteVisible = model.commandPaletteVisible
        self.settingsPanelVisible = model.settingsPanelVisible
        self.workspaceOverviewVisible = model.workspaceOverviewVisible
        self.notificationPanelVisible = model.notificationPanelVisible
    }
}
```

- [ ] **Step 2: Move root shell body**

Create `ShellRootView.swift` and move the existing root-level `body` from `ConductorRootView` into `ShellRootView`. Keep `ConductorRootView` as:

```swift
import SwiftUI

struct ConductorRootView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        ShellRootView(model: model)
    }
}
```

- [ ] **Step 3: Move sidebar declarations**

Move `ConductorSidebar`, sidebar row models, sidebar row views, sidebar rail controls, and sidebar helper shapes from `ConductorRootView.swift` into `Sidebar/ConductorSidebar.swift`. Preserve existing type names and initializers.

- [ ] **Step 4: Move toolbar declarations**

Move `ConductorToolbar`, toolbar snapshots, toolbar groups, and toolbar button rows from `ConductorRootView.swift` into `Toolbar/ConductorToolbar.swift`. Preserve existing type names and initializers.

- [ ] **Step 5: Move workspace tab declarations**

Move `WorkspaceTabStrip`, workspace top tabs, file top tabs, tab glyphs, tab metrics, and tab display models from `ConductorRootView.swift` into `WorkspaceTabs/WorkspaceTabStrip.swift`. Preserve existing type names and initializers.

- [ ] **Step 6: Verify**

Run:

```bash
cd Apps/Conductor
swift build
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Shell \
  Apps/Conductor/Sources/Conductor/UI/Sidebar \
  Apps/Conductor/Sources/Conductor/UI/Toolbar \
  Apps/Conductor/Sources/Conductor/UI/WorkspaceTabs \
  Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift
git commit -m "refactor: split shell chrome modules"
```

---

## Task 5: Split Settings And Render One Section At A Time

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsSnapshot.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsPanel.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsSections.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsControls.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`

- [ ] **Step 1: Create settings snapshot**

Create `SettingsSnapshot.swift`:

```swift
import Foundation

enum SettingsSectionID: String, CaseIterable, Identifiable, Sendable {
    case overview
    case interface
    case terminal
    case keyboard
    case notifications
    case agents

    var id: String { rawValue }
}

struct SettingsSnapshot: Equatable {
    let selectedSection: SettingsSectionID
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let agentStatuses: [AgentHookProvider: AgentCLIStatus]

    init(
        selectedSection: SettingsSectionID,
        theme: TerminalTheme,
        appearance: AppearancePreferences,
        agentStatuses: [AgentHookProvider: AgentCLIStatus]
    ) {
        RenderCounter.increment("settings-snapshot")
        self.selectedSection = selectedSection
        self.theme = theme
        self.appearance = appearance
        self.agentStatuses = agentStatuses
    }
}
```

- [ ] **Step 2: Move settings types**

Move settings panel, section enums, setting rows, theme rows, Ghostty settings rows, agent rows, and settings controls from `ConductorRootView.swift` into the `UI/Settings/` folder.

- [ ] **Step 3: Render only selected settings section**

In `SettingsPanel.swift`, implement selected-section rendering with:

```swift
@ViewBuilder
private var selectedSectionBody: some View {
    switch snapshot.selectedSection {
    case .overview:
        SettingsOverviewSection(model: model, snapshot: snapshot)
    case .interface:
        InterfaceSettingsSection(model: model, snapshot: snapshot)
    case .terminal:
        TerminalSettingsSectionView(model: model, snapshot: snapshot)
    case .keyboard:
        KeyboardSettingsSection(model: model, snapshot: snapshot)
    case .notifications:
        NotificationSettingsSection(model: model, snapshot: snapshot)
    case .agents:
        AgentSettingsSection(model: model, snapshot: snapshot)
    }
}
```

The inactive sections must not be instantiated in the view tree.

- [ ] **Step 4: Verify**

Run:

```bash
cd Apps/Conductor
swift build
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Settings \
  Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift
git commit -m "perf: scope settings rendering by section"
```

---

## Task 6: Split File Manager And Enforce Visible Windows

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerService.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerStore.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerDisplaySnapshot.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerListView.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/FileManager/FilePreviewHost.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/FileManager/FilePreviewAppKitHosts.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

- [ ] **Step 1: Move service and data types**

Move `FileManagerItem`, visible row types, file operation result types, pasteboard helpers, and `FileManagerService` from `FileManagerPanel.swift` into `FileManagerService.swift`. Preserve type names so call sites keep compiling.

- [ ] **Step 2: Create visible-window snapshot API**

Create `FileManagerDisplaySnapshot.swift`:

```swift
import Foundation

struct FileManagerDisplaySnapshot: Equatable {
    let rows: [FileManagerVisibleRow]
    let totalRowCount: Int
    let visibleRange: Range<Int>

    static func visibleWindow(
        items: [FileManagerItem],
        startIndex: Int,
        visibleCount: Int,
        overscan: Int
    ) -> FileManagerDisplaySnapshot {
        let lower = max(0, startIndex - overscan)
        let upper = min(items.count, startIndex + max(1, visibleCount) + overscan)
        let range = lower..<upper
        let rows = range.map { index in
            FileManagerVisibleRow(item: items[index], depth: 0, index: index)
        }
        return FileManagerDisplaySnapshot(
            rows: rows,
            totalRowCount: items.count,
            visibleRange: range
        )
    }
}
```

If the existing `FileManagerVisibleRow` initializer differs, add an initializer with `item`, `depth`, and `index` labels instead of changing call sites throughout the panel.

- [ ] **Step 3: Move store**

Move `FileManagerPanelStore` into `FileManagerStore.swift`. The store owns `displaySnapshot` as stored state. Rebuild `displaySnapshot` only when directory contents, search query, sort mode, kind filter, expansion state, or visible row window changes.

- [ ] **Step 4: Move list view**

Move the file list, rows, and row controls into `FileManagerListView.swift`. The list reads only `store.displaySnapshot.rows`; it does not recursively expand directories in `body`.

- [ ] **Step 5: Move preview hosts**

Move text/table/key-value/structured AppKit preview hosts into `FilePreviewAppKitHosts.swift`. `FilePreviewHost.swift` switches only on the selected preview state:

```swift
@ViewBuilder
func filePreviewBody(state: FilePreviewState) -> some View {
    switch state {
    case .empty:
        EmptyView()
    case .text(let document):
        FileManagerSourcePreview(document: document)
    case .table(let document):
        FileManagerTablePreview(document: document)
    case .keyValue(let document):
        FileManagerKeyValuePreview(document: document)
    case .structured(let document):
        FileManagerStructuredPreview(document: document)
    }
}
```

- [ ] **Step 6: Run full gate**

Run:

```bash
cd Apps/Conductor
./Scripts/check-conductor.sh
```

Expected: PASS with `Conductor checks passed`.

- [ ] **Step 7: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/FileManager \
  Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift
git commit -m "perf: virtualize file manager rendering"
```

---

## Task 7: Standardize Buttons And Control Quality

**Files:**
- Create: `Apps/Conductor/Sources/Conductor/UI/Controls/ConductorIconButton.swift`
- Create: `Apps/Conductor/Sources/Conductor/UI/Controls/ConductorCommandButton.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/Toolbar/ConductorToolbar.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/Sidebar/ConductorSidebar.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/Settings/SettingsControls.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerListView.swift`

- [ ] **Step 1: Create shared icon button**

Create `ConductorIconButton.swift`:

```swift
import SwiftUI

struct ConductorIconButton: View {
    let state: ConductorControlState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
        .help(state.tooltip)
        .accessibilityLabel(state.accessibilityLabel)
        .foregroundStyle(foreground)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var foreground: Color {
        if !state.isEnabled { return .secondary.opacity(0.45) }
        if state.isActive { return .accentColor }
        return .primary
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(state.isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.001))
    }
}
```

- [ ] **Step 2: Create shared command button**

Create `ConductorCommandButton.swift`:

```swift
import SwiftUI

struct ConductorCommandButton: View {
    let state: ConductorControlState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                if let title = state.title {
                    Text(title)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: state.systemImage)
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(minHeight: 28)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
        .disabled(!state.isEnabled)
        .help(state.tooltip)
        .accessibilityLabel(state.accessibilityLabel)
        .foregroundStyle(state.isEnabled ? Color.primary : Color.secondary.opacity(0.45))
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(state.isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
        }
    }
}
```

- [ ] **Step 3: Replace toolbar controls**

Convert toolbar controls to `ConductorControlState` plus `ConductorIconButton` or `ConductorCommandButton`. Each toolbar control must provide `isEnabled`, `isActive`, `tooltip`, and `accessibilityLabel`.

- [ ] **Step 4: Replace sidebar, settings, and file-manager controls**

Convert sidebar rail buttons, settings panel close/action buttons, file-manager toolbar buttons, preview action buttons, and row action buttons to shared controls.

- [ ] **Step 5: Verify**

Run:

```bash
cd Apps/Conductor
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Controls \
  Apps/Conductor/Sources/Conductor/UI/Toolbar \
  Apps/Conductor/Sources/Conductor/UI/Sidebar \
  Apps/Conductor/Sources/Conductor/UI/Settings \
  Apps/Conductor/Sources/Conductor/UI/FileManager
git commit -m "ui: standardize conductor controls"
```

---

## Task 8: Whole-App Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-05-24-performance-first-aggressive-refactor.md`

- [ ] **Step 1: Run full gate**

Run:

```bash
cd Apps/Conductor
./Scripts/check-conductor.sh
```

Expected output includes:

```text
Conductor checks passed
```

- [ ] **Step 2: Confirm no Conductor process remains**

Run:

```bash
pgrep -fl '/Users/uchihasasuke/Desktop/conductor/Apps/Conductor/.build/debug/Conductor|/Users/uchihasasuke/Desktop/conductor/Apps/Conductor/.build/Conductor.app/Contents/MacOS/Conductor|\.build/debug/Conductor|\.build/Conductor.app/Contents/MacOS/Conductor' || true
```

Expected: no output.

- [ ] **Step 3: Manual performance smoke**

Run this manual pass:

```text
1. Launch Apps/Conductor/.build/Conductor.app.
2. Open File Manager on a directory with at least 2,000 entries or nested descendants.
3. Scroll top, middle, and bottom; confirm rows appear without rendering the full tree.
4. Open Settings and switch every section twice.
5. Split right, split down, and resize while a terminal command is producing output.
6. Open Notification panel, Workspace Overview, Command Palette, and File Manager while terminals remain active.
7. Inspect toolbar/sidebar/panel buttons for disabled, active, hover, tooltip, and accessible labels.
```

Expected: terminal surfaces remain stable, visible content updates only inside active panels, and panel toggles do not churn the terminal stage.

- [ ] **Step 4: Commit verification note**

After the manual pass succeeds, check this task in the plan file and run:

```bash
git add docs/superpowers/plans/2026-05-24-performance-first-aggressive-refactor.md
git commit -m "docs: record performance refactor verification"
```

### Verification Record - 2026-05-24

- `swift build --package-path Apps/Conductor --product Conductor`: passed after Task 7 follow-up.
- `swift run --package-path Apps/Conductor ConductorModelCheck`: passed.
- `./Scripts/check-conductor.sh`: build, `ConductorModelCheck`, smoke, shortcut, focus, layout, lifecycle, workspace, shell-panel, notification, long-output stress, resize-while-output stress, release bundle build, and app signing all passed. The command exited before printing `Conductor checks passed` because the existing Trellis validation step could not open `.trellis/scripts/task.py`, which is currently deleted outside this refactor.
- Process cleanup check with the documented `pgrep` command returned no Conductor process before the manual pass.
- Manual smoke launched `Apps/Conductor/.build/Conductor.app`, opened File Manager on `/tmp/conductor-large-dir` with 2,000 files, confirmed the panel rendered a bounded visible row window with `显示下一组` pagination instead of eager 2,000-row rendering, switched Settings sections while terminals remained visible, and inspected shared toolbar/sidebar/panel buttons through accessibility labels and visible layout.

---

## Self-Review

Spec coverage:

- Performance-first goal: Tasks 1, 3, 6, 8.
- Full-project ban on eager large SwiftUI rendering: Tasks 1, 4, 5, 6.
- Coordinator extraction: Tasks 2 and 3.
- UI feature-folder split: Tasks 4, 5, 6.
- Button quality: Task 7.
- Full gate and manual checks: Task 8.

Execution consistency:

- `ConductorModelCheck` is used only for `ConductorCore` render-budget coverage.
- App target work is verified by `swift build`, full gate automation, and manual smoke checks.
- Code-producing steps include concrete files, snippets, commands, and expected results.
