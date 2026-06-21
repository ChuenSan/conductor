# Command Deck Phase One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize Conductor's first-level product structure around the command deck model without changing terminal rendering or agent execution behavior.

**Architecture:** Add a small command deck presentation model that assigns visible commands and surfaces to stable layers: global, workspace, pane, agent, capability, and task. Reuse the existing Tools panel as the first Capability Library shell, tighten top toolbar and pane/workspace/menu ownership, and update onboarding/task copy to teach the new model.

**Tech Stack:** Swift, SwiftUI, AppKit, XCTest, Swift Package Manager, existing ConductorApp UI/presentation patterns.

---

## File Structure

- Create `Sources/ConductorApp/UI/CommandDeckModel.swift`
  - Owns `CommandDeckLayer`, command ID scope lookup, and presentation labels used by command palette/tests.
- Modify `Sources/ConductorApp/Commands/CommandRegistry.swift`
  - Adds `scope` to `AppCommand` with a default derived from command ID.
- Modify `Sources/ConductorApp/AppCoordinator.swift`
  - Registers explicit scopes for ambiguous commands and exposes command palette labels.
- Create `Tests/ConductorAppTests/CommandDeckScopeTests.swift`
  - Guards layer classification for major commands.
- Create `Sources/ConductorApp/UI/CapabilityLibraryPresentation.swift`
  - Owns capability library naming, section order, and mapping to existing `ToolsTab`.
- Modify `Sources/ConductorApp/UI/ToolsPanelView.swift`
  - Renames the right-side Tools panel shell to Capability Library while keeping existing modules.
- Modify `Sources/ConductorApp/UI/TabBarView.swift`
  - Keeps the top toolbar global-only and routes the tools button to Capability Library copy.
- Modify `Sources/ConductorApp/main.swift`
  - Updates app menu labels to the new command deck language.
- Create `Tests/ConductorAppTests/CapabilityLibraryPresentationTests.swift`
  - Guards section order and user-facing labels.
- Modify `Sources/ConductorApp/UI/PaneContainerView.swift`
  - Adds layer metadata to `PaneContextAction` and keeps pane header actions pane-local.
- Modify `Sources/ConductorApp/UI/SidebarView.swift`
  - Keeps workspace menu actions workspace/agent scoped and avoids capability/global leakage.
- Create `Tests/ConductorAppTests/CommandDeckMenuLayerTests.swift`
  - Guards pane and workspace menu layer rules.
- Modify `Sources/ConductorApp/UI/TaskCardsPanel.swift`
  - Reframes task cards as assignable work without changing drag/drop behavior.
- Create `Tests/ConductorAppTests/TaskCardCommandDeckCopyTests.swift`
  - Guards task card title/help copy and assignment language.
- Modify `Sources/ConductorApp/UI/OnboardingPresentationState.swift`
  - Updates onboarding pages to teach the command deck loop.
- Modify `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`
  - Adds English translations for new Chinese copy.
- Modify `Tests/ConductorAppTests/OnboardingPresentationStateTests.swift`
  - Adds model tests for page IDs and command deck vocabulary.

## Task 1: Command Deck Layer Model

**Files:**
- Create: `Sources/ConductorApp/UI/CommandDeckModel.swift`
- Modify: `Sources/ConductorApp/Commands/CommandRegistry.swift`
- Modify: `Sources/ConductorApp/AppCoordinator.swift`
- Test: `Tests/ConductorAppTests/CommandDeckScopeTests.swift`

- [ ] **Step 1: Write the failing command scope tests**

Create `Tests/ConductorAppTests/CommandDeckScopeTests.swift`:

```swift
@testable import ConductorApp
import XCTest

final class CommandDeckScopeTests: XCTestCase {
    func testMajorCommandIDsResolveToCommandDeckLayers() {
        let expectations: [String: CommandDeckLayer] = [
            "openSettings": .global,
            "commandPalette": .global,
            "shortcutCheatSheet": .global,
            "newTab": .workspace,
            "nextTab": .workspace,
            "prevTab": .workspace,
            "splitRight": .pane,
            "splitDown": .pane,
            "closePane": .pane,
            "toggleZoom": .pane,
            "findInTerminal": .pane,
            "taskCards": .task,
            "openSnippets": .capability,
            "coCreate": .capability,
            "queuePrompt": .agent,
            "missionControl": .agent,
        ]

        for (commandID, layer) in expectations {
            XCTAssertEqual(CommandDeckCommandScope.scope(forCommandID: commandID), layer, commandID)
        }
    }

    func testSelectTabCommandsAreWorkspaceScoped() {
        for index in 1...9 {
            XCTAssertEqual(CommandDeckCommandScope.scope(forCommandID: "selectTab\(index)"), .workspace)
        }
    }

    func testAppCommandDefaultsScopeFromID() {
        let command = AppCommand(id: "splitRight", title: "Split", defaultKeybinding: nil) {}

        XCTAssertEqual(command.scope, .pane)
    }

    func testCommandDeckLayerHasStableLocalizedTitles() {
        XCTAssertEqual(CommandDeckLayer.global.title, "全局")
        XCTAssertEqual(CommandDeckLayer.workspace.title, "工作区")
        XCTAssertEqual(CommandDeckLayer.pane.title, "面板")
        XCTAssertEqual(CommandDeckLayer.agent.title, "Agent")
        XCTAssertEqual(CommandDeckLayer.capability.title, "能力")
        XCTAssertEqual(CommandDeckLayer.task.title, "任务")
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
swift test --filter CommandDeckScopeTests
```

Expected: FAIL because `CommandDeckLayer`, `CommandDeckCommandScope`, and `AppCommand.scope` do not exist.

- [ ] **Step 3: Add the command deck layer model**

Create `Sources/ConductorApp/UI/CommandDeckModel.swift`:

```swift
import Foundation

enum CommandDeckLayer: String, CaseIterable, Equatable {
    case global
    case workspace
    case pane
    case agent
    case capability
    case task

    var title: String {
        switch self {
        case .global: return L("全局")
        case .workspace: return L("工作区")
        case .pane: return L("面板")
        case .agent: return "Agent"
        case .capability: return L("能力")
        case .task: return L("任务")
        }
    }
}

enum CommandDeckCommandScope {
    private static let explicitScopes: [String: CommandDeckLayer] = [
        "openSettings": .global,
        "commandPalette": .global,
        "shortcutCheatSheet": .global,
        "increaseFontSize": .global,
        "decreaseFontSize": .global,
        "resetFontSize": .global,

        "newTab": .workspace,
        "reopenClosedTab": .workspace,
        "nextTab": .workspace,
        "prevTab": .workspace,
        "toggleRecentTab": .workspace,
        "equalizeSplits": .workspace,

        "splitRight": .pane,
        "splitDown": .pane,
        "closePane": .pane,
        "focusPaneLeft": .pane,
        "focusPaneRight": .pane,
        "focusPaneUp": .pane,
        "focusPaneDown": .pane,
        "toggleZoom": .pane,
        "findInTerminal": .pane,
        "searchSelection": .pane,
        "findNext": .pane,
        "findPrev": .pane,

        "missionControl": .agent,
        "queuePrompt": .agent,

        "openSnippets": .capability,
        "coCreate": .capability,

        "taskCards": .task,
    ]

    static func scope(forCommandID id: String) -> CommandDeckLayer {
        if id.hasPrefix("selectTab") { return .workspace }
        return explicitScopes[id] ?? .global
    }
}
```

- [ ] **Step 4: Add `scope` to app commands**

Modify `Sources/ConductorApp/Commands/CommandRegistry.swift` so `AppCommand` becomes:

```swift
/// 一条可执行命令：稳定 id、标题、内置默认键位、命令归属层、执行体。
/// 命令面板/键位帮助/自定义键位都读这张表（高扩展）。
struct AppCommand {
    let id: String
    let title: String
    let defaultKeybinding: String?
    let scope: CommandDeckLayer
    let run: () -> Void

    init(
        id: String,
        title: String,
        defaultKeybinding: String?,
        scope: CommandDeckLayer? = nil,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.defaultKeybinding = defaultKeybinding
        self.scope = scope ?? CommandDeckCommandScope.scope(forCommandID: id)
        self.run = run
    }
}
```

- [ ] **Step 5: Make ambiguous command registrations explicit**

In `Sources/ConductorApp/AppCoordinator.swift`, update only ambiguous registrations:

```swift
AppCommand(id: "missionControl", title: L("任务总览"), defaultKeybinding: "cmd+shift+m", scope: .agent) { [weak self] in self?.openMissionControl() },
AppCommand(id: "queuePrompt", title: L("任务队列（当前面板）"), defaultKeybinding: "cmd+shift+enter", scope: .agent) { [weak self] in self?.openQueuePanel() },
AppCommand(id: "taskCards", title: L("任务卡片"), defaultKeybinding: "cmd+shift+k", scope: .task) { [weak self] in self?.openTaskCards() },
AppCommand(id: "openSnippets", title: L("命令片段库"), defaultKeybinding: nil, scope: .capability) { [weak self] in self?.openTools(.snippets) },
AppCommand(id: "coCreate", title: L("共创计划"), defaultKeybinding: nil, scope: .capability) { [weak self] in self?.openTools(.coCreate) },
```

- [ ] **Step 6: Run command scope tests**

Run:

```bash
swift test --filter CommandDeckScopeTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ConductorApp/UI/CommandDeckModel.swift Sources/ConductorApp/Commands/CommandRegistry.swift Sources/ConductorApp/AppCoordinator.swift Tests/ConductorAppTests/CommandDeckScopeTests.swift
git commit -m "Add command deck command scope model"
```

## Task 2: Capability Library Presentation Shell

**Files:**
- Create: `Sources/ConductorApp/UI/CapabilityLibraryPresentation.swift`
- Modify: `Sources/ConductorApp/UI/ToolsPanelView.swift`
- Modify: `Sources/ConductorApp/UI/TabBarView.swift`
- Modify: `Sources/ConductorApp/main.swift`
- Modify: `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`
- Test: `Tests/ConductorAppTests/CapabilityLibraryPresentationTests.swift`

- [ ] **Step 1: Write failing capability library tests**

Create `Tests/ConductorAppTests/CapabilityLibraryPresentationTests.swift`:

```swift
@testable import ConductorApp
import XCTest

final class CapabilityLibraryPresentationTests: XCTestCase {
    func testCapabilityLibraryUsesStableSectionOrder() {
        XCTAssertEqual(
            CapabilityLibrarySection.allCases,
            [.overview, .cli, .skills, .mcp, .hooks, .providersAndUsage, .activity, .snippets]
        )
    }

    func testCapabilityLibraryPanelTabsMapToExistingToolsTabs() {
        XCTAssertEqual(
            CapabilityLibrarySection.panelTabs,
            [.cli, .skills, .mcp, .hooks, .providersAndUsage, .snippets]
        )
        XCTAssertEqual(CapabilityLibrarySection.providersAndUsage.toolsTab, .usage)
    }

    func testCapabilityLibraryPrimaryLabels() {
        XCTAssertEqual(CapabilityLibraryPresentation.title, "能力库")
        XCTAssertEqual(CapabilityLibraryPresentation.englishTitle, "Capability Library")
        XCTAssertEqual(CapabilityLibraryPresentation.toolbarHelp, "打开能力库")
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
swift test --filter CapabilityLibraryPresentationTests
```

Expected: FAIL because `CapabilityLibrarySection` and `CapabilityLibraryPresentation` do not exist.

- [ ] **Step 3: Add capability library presentation model**

Create `Sources/ConductorApp/UI/CapabilityLibraryPresentation.swift`:

```swift
import Foundation

enum CapabilityLibrarySection: String, CaseIterable, Identifiable {
    case overview
    case cli
    case skills
    case mcp
    case hooks
    case providersAndUsage
    case activity
    case snippets

    var id: String { rawValue }

    static let panelTabs: [CapabilityLibrarySection] = [
        .cli,
        .skills,
        .mcp,
        .hooks,
        .providersAndUsage,
        .snippets,
    ]

    var title: String {
        switch self {
        case .overview: return L("总览")
        case .cli: return "CLI"
        case .skills: return "Skills"
        case .mcp: return "MCP"
        case .hooks: return "Hooks"
        case .providersAndUsage: return L("供应商与用量")
        case .activity: return L("活动")
        case .snippets: return L("片段")
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cli: return "terminal"
        case .skills: return "wand.and.stars"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .hooks: return "link"
        case .providersAndUsage: return "chart.bar.xaxis"
        case .activity: return "waveform.path.ecg"
        case .snippets: return "text.badge.star"
        }
    }

    var toolsTab: ToolsTab? {
        switch self {
        case .cli: return .cli
        case .skills: return .skills
        case .mcp: return .mcp
        case .hooks: return .hooks
        case .providersAndUsage: return .usage
        case .snippets: return .snippets
        case .overview, .activity: return nil
        }
    }
}

enum CapabilityLibraryPresentation {
    static var title: String { L("能力库") }
    static let englishTitle = "Capability Library"
    static var toolbarHelp: String { L("打开能力库") }
    static var subtitle: String { L("管理 CLI、Skills、MCP、Hooks 和供应商能力") }
}
```

- [ ] **Step 4: Update `ToolsPanelView` header and segment labels**

In `Sources/ConductorApp/UI/ToolsPanelView.swift`, update the comment above `ToolsPanelView`:

```swift
/// 能力库右侧面板：CLI、Skills、MCP、Hooks、供应商用量与片段统一归在一个能力入口。
```

Replace `header` with:

```swift
private var header: some View {
    HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
            Text(CapabilityLibraryPresentation.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppStyle.textPrimary)
            Text(CapabilityLibraryPresentation.subtitle)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
        }
        Spacer(minLength: 8)
        IconOnlyButton(
            systemName: "xmark",
            help: L("关闭"),
            size: 28,
            symbolSize: 11,
            weight: .bold,
            action: onClose)
    }
    .padding(.horizontal, 12)
    .padding(.top, 14)
    .padding(.bottom, 7)
}
```

In `segmented`, replace `ForEach(ToolsTab.panelTabs)` with this mapping:

```swift
ForEach(CapabilityLibrarySection.panelTabs) { section in
    let tab = section.toolsTab!
    let selected = coordinator.toolsTab == tab
    Button {
        withAnimation(Motion.snappy) {
            coordinator.toolsTab = tab
        }
    } label: {
        HStack(spacing: 5) {
            Image(systemName: section.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? AppStyle.accent : AppStyle.textTertiary)
            Text(section.title)
                .font(.system(size: 11, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.elevated)
                    .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.10), radius: 3, y: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 5: Update global toolbar and menu copy**

In `Sources/ConductorApp/UI/TabBarView.swift`, update the tool button:

```swift
IconOnlyButton(
    systemName: "wand.and.stars",
    help: CapabilityLibraryPresentation.toolbarHelp,
    size: GlobalToolbarChromePolicy.buttonSize,
    symbolSize: GlobalToolbarChromePolicy.symbolSize,
    tint: coordinator.cliToolsPresentation.isPresented ? AppStyle.accent : AppStyle.textSecondary) {
        coordinator.toggleCLITools()
    }
```

In `Sources/ConductorApp/main.swift`, add a capability item to the app menu before task cards:

```swift
let capabilityItem = ClosureMenuItem(CapabilityLibraryPresentation.title, systemImage: "wand.and.stars") { [weak self] in
    self?.coordinator?.openTools(.cli)
}
appMenu.addItem(capabilityItem)
```

- [ ] **Step 6: Add English translations**

Append these keys to `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`:

```text
"能力库" = "Capability Library";
"打开能力库" = "Open Capability Library";
"管理 CLI、Skills、MCP、Hooks 和供应商能力" = "Manage CLI, Skills, MCP, Hooks, and provider capabilities";
"供应商与用量" = "Providers & Usage";
"活动" = "Activity";
```

- [ ] **Step 7: Run capability tests and i18n audit**

Run:

```bash
swift test --filter CapabilityLibraryPresentationTests
python3 Scripts/audit-i18n.py --strict --limit 200
```

Expected: both commands exit 0.

- [ ] **Step 8: Commit**

```bash
git add Sources/ConductorApp/UI/CapabilityLibraryPresentation.swift Sources/ConductorApp/UI/ToolsPanelView.swift Sources/ConductorApp/UI/TabBarView.swift Sources/ConductorApp/main.swift Sources/ConductorApp/Resources/en.lproj/Localizable.strings Tests/ConductorAppTests/CapabilityLibraryPresentationTests.swift
git commit -m "Introduce capability library presentation"
```

## Task 3: Global Toolbar And Pane Chrome Boundaries

**Files:**
- Modify: `Sources/ConductorApp/UI/TabBarView.swift`
- Modify: `Sources/ConductorApp/UI/PaneContainerView.swift`
- Test: `Tests/ConductorAppTests/ToolbarChromePolicyTests.swift`
- Test: `Tests/ConductorAppTests/PaneHeaderActionPresentationTests.swift`

- [ ] **Step 1: Extend toolbar boundary tests**

Modify `Tests/ConductorAppTests/ToolbarChromePolicyTests.swift` so it contains:

```swift
@testable import ConductorApp
import XCTest

final class ToolbarChromePolicyTests: XCTestCase {
    func testGlobalToolbarGroupsActionsByIntent() {
        XCTAssertEqual(
            GlobalToolbarActionPresentation.groups,
            [
                [.update],
                [.appearance],
                [.capability, .tasks],
                [.settings],
            ])
    }

    func testGlobalToolbarContainsOnlyGlobalOrTaskCapabilityEntrypoints() {
        let allowedLayers = GlobalToolbarActionPresentation.actions.map(\.deckLayer)

        XCTAssertEqual(allowedLayers, [.global, .global, .capability, .task, .global])
    }

    func testPaneHeaderControlsStayQuietUntilActiveOrHovered() {
        XCTAssertLessThan(PaneHeaderChromePolicy.controlOpacity(isActive: false, isHovering: false), 0.35)
        XCTAssertGreaterThan(PaneHeaderChromePolicy.controlOpacity(isActive: true, isHovering: false), 0.60)
        XCTAssertGreaterThan(PaneHeaderChromePolicy.controlOpacity(isActive: false, isHovering: true), 0.85)
        XCTAssertLessThanOrEqual(PaneHeaderChromePolicy.activeHeaderTintOpacity, 0.055)
    }
}
```

- [ ] **Step 2: Run the failing toolbar test**

Run:

```bash
swift test --filter ToolbarChromePolicyTests
```

Expected: FAIL until `GlobalToolbarAction.capability`, `GlobalToolbarAction.deckLayer`, and `GlobalToolbarActionPresentation.actions` exist.

- [ ] **Step 3: Update global toolbar presentation model**

In `Sources/ConductorApp/UI/TabBarView.swift`, replace `GlobalToolbarAction` and `GlobalToolbarActionPresentation` definitions with:

```swift
enum GlobalToolbarAction: Equatable {
    case update
    case appearance
    case capability
    case tasks
    case settings

    var deckLayer: CommandDeckLayer {
        switch self {
        case .update, .appearance, .settings: return .global
        case .capability: return .capability
        case .tasks: return .task
        }
    }
}

enum GlobalToolbarActionPresentation {
    static let groups: [[GlobalToolbarAction]] = [
        [.update],
        [.appearance],
        [.capability, .tasks],
        [.settings],
    ]

    static var actions: [GlobalToolbarAction] {
        groups.flatMap { $0 }
    }
}
```

- [ ] **Step 4: Keep pane header actions pane-local**

Modify `Sources/ConductorApp/UI/PaneContainerView.swift` by adding this computed property to `PaneContextAction`:

```swift
var deckLayer: CommandDeckLayer {
    switch self {
    case .copy, .paste, .selectAll, .clear,
         .splitRight, .splitDown, .zoom,
         .copyCwd, .openInFinder,
         .exportText, .commandLog, .close:
        return .pane
    }
}
```

Extend `Tests/ConductorAppTests/PaneHeaderActionPresentationTests.swift`:

```swift
func testPaneHeaderActionsArePaneScoped() {
    let actions = PaneHeaderActionPresentation.primaryActions + PaneHeaderActionPresentation.moreActions

    XCTAssertFalse(actions.isEmpty)
    XCTAssertTrue(actions.allSatisfy { $0.deckLayer == .pane })
}
```

- [ ] **Step 5: Run chrome and pane tests**

Run:

```bash
swift test --filter ToolbarChromePolicyTests
swift test --filter PaneHeaderActionPresentationTests
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/ConductorApp/UI/TabBarView.swift Sources/ConductorApp/UI/PaneContainerView.swift Tests/ConductorAppTests/ToolbarChromePolicyTests.swift Tests/ConductorAppTests/PaneHeaderActionPresentationTests.swift
git commit -m "Lock command deck toolbar and pane boundaries"
```

## Task 4: Workspace And Menu Layer Audit

**Files:**
- Modify: `Sources/ConductorApp/UI/SidebarView.swift`
- Modify: `Sources/ConductorApp/UI/PaneContainerView.swift`
- Test: `Tests/ConductorAppTests/CommandDeckMenuLayerTests.swift`

- [ ] **Step 1: Write layer audit tests**

Create `Tests/ConductorAppTests/CommandDeckMenuLayerTests.swift`:

```swift
@testable import ConductorApp
import XCTest

final class CommandDeckMenuLayerTests: XCTestCase {
    func testWorkspaceContextActionsStayWorkspaceOrAgentScoped() {
        XCTAssertEqual(
            WorkspaceContextActionPresentation.staticActions.map(\.deckLayer),
            [.workspace, .workspace, .workspace, .workspace, .workspace, .workspace]
        )
        XCTAssertEqual(WorkspaceContextActionPresentation.agentLaunchLayer, .agent)
    }

    func testWorkspaceContextActionsDoNotContainGlobalOrCapabilityActions() {
        let forbidden: Set<CommandDeckLayer> = [.global, .capability]

        XCTAssertTrue(WorkspaceContextActionPresentation.staticActions.allSatisfy { !forbidden.contains($0.deckLayer) })
    }

    func testPaneMoreMenuContainsOnlyPaneScopedActions() {
        XCTAssertTrue(PaneHeaderActionPresentation.moreActions.allSatisfy { $0.deckLayer == .pane })
    }
}
```

- [ ] **Step 2: Run the failing menu tests**

Run:

```bash
swift test --filter CommandDeckMenuLayerTests
```

Expected: FAIL because `WorkspaceContextActionPresentation` does not exist.

- [ ] **Step 3: Add workspace context presentation model**

In `Sources/ConductorApp/UI/SidebarView.swift`, add these types near `WorkspaceReorderDragPolicy`:

```swift
enum WorkspaceContextAction: Equatable {
    case rename
    case revealInFinder
    case copyPath
    case reauthorizeDirectory
    case saveLayout
    case removeWorkspace

    var deckLayer: CommandDeckLayer {
        switch self {
        case .rename, .revealInFinder, .copyPath, .reauthorizeDirectory, .saveLayout, .removeWorkspace:
            return .workspace
        }
    }
}

enum WorkspaceContextActionPresentation {
    static let staticActions: [WorkspaceContextAction] = [
        .rename,
        .revealInFinder,
        .copyPath,
        .reauthorizeDirectory,
        .saveLayout,
        .removeWorkspace,
    ]

    static let agentLaunchLayer: CommandDeckLayer = .agent
}
```

- [ ] **Step 4: Add comments that explain context menu ownership**

In `Sources/ConductorApp/UI/SidebarView.swift`, add this comment immediately above the workspace row `.contextMenu`:

```swift
// 工作区菜单只放工作区动作与工作区范围内的 Agent 启动动作；
// 全局设置和能力库入口必须留在顶栏/命令面板，避免每一层都长出自己的工具箱。
```

In `Sources/ConductorApp/UI/PaneContainerView.swift`, add this comment immediately above `private func buildContextMenu()`:

```swift
// Pane 菜单只放当前面板的文本、布局、路径、会话和 Agent 协作动作。
// 全局设置、能力库配置、工作区管理不进入这里。
```

- [ ] **Step 5: Run menu tests**

Run:

```bash
swift test --filter CommandDeckMenuLayerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ConductorApp/UI/SidebarView.swift Sources/ConductorApp/UI/PaneContainerView.swift Tests/ConductorAppTests/CommandDeckMenuLayerTests.swift
git commit -m "Audit command deck menu layers"
```

## Task 5: Task Cards As Assignable Work

**Files:**
- Modify: `Sources/ConductorApp/UI/TaskCardsPanel.swift`
- Modify: `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`
- Test: `Tests/ConductorAppTests/TaskCardCommandDeckCopyTests.swift`

- [ ] **Step 1: Write failing task card copy tests**

Create `Tests/ConductorAppTests/TaskCardCommandDeckCopyTests.swift`:

```swift
@testable import ConductorApp
import XCTest

final class TaskCardCommandDeckCopyTests: XCTestCase {
    func testTaskCardPanelCopyFramesCardsAsAssignableWork() {
        XCTAssertEqual(TaskCardCommandDeckCopy.title, "任务卡片")
        XCTAssertEqual(TaskCardCommandDeckCopy.subtitle, "拖到某个面板，交给 Shell 或 Agent 执行")
        XCTAssertEqual(TaskCardCommandDeckCopy.emptyTitle, "还没有可指派的任务")
    }

    func testTaskCardsBelongToTaskLayer() {
        XCTAssertEqual(TaskCardCommandDeckCopy.deckLayer, .task)
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
swift test --filter TaskCardCommandDeckCopyTests
```

Expected: FAIL because `TaskCardCommandDeckCopy` does not exist.

- [ ] **Step 3: Add task card command deck copy model**

In `Sources/ConductorApp/UI/TaskCardsPanel.swift`, add this near the top, below `TaskRunRequest`:

```swift
enum TaskCardCommandDeckCopy {
    static let deckLayer: CommandDeckLayer = .task
    static var title: String { L("任务卡片") }
    static var subtitle: String { L("拖到某个面板，交给 Shell 或 Agent 执行") }
    static var emptyTitle: String { L("还没有可指派的任务") }
    static var emptyDetail: String { L("输入命令或提示词创建一张任务卡片，再把它拖到目标面板。") }
}
```

- [ ] **Step 4: Use the copy in the panel header**

In `TaskCardsPanelView.launcher`, replace the title area:

```swift
Image(systemName: "bolt.fill")
    .font(.system(size: 12, weight: .semibold))
    .foregroundStyle(AppStyle.accent)
VStack(alignment: .leading, spacing: 2) {
    Text(TaskCardCommandDeckCopy.title)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(AppStyle.textPrimary)
    Text(TaskCardCommandDeckCopy.subtitle)
        .font(.system(size: 10.5))
        .foregroundStyle(AppStyle.textTertiary)
        .lineLimit(1)
}
Spacer()
```

If `emptyState` currently hardcodes its text, replace the title/detail with:

```swift
Text(TaskCardCommandDeckCopy.emptyTitle)
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(AppStyle.textPrimary)
Text(TaskCardCommandDeckCopy.emptyDetail)
    .font(.system(size: 11.5))
    .foregroundStyle(AppStyle.textTertiary)
    .multilineTextAlignment(.center)
```

- [ ] **Step 5: Add English translations**

Append these keys to `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`:

```text
"拖到某个面板，交给 Shell 或 Agent 执行" = "Drag to a pane and let Shell or an Agent run it";
"还没有可指派的任务" = "No assignable tasks yet";
"输入命令或提示词创建一张任务卡片，再把它拖到目标面板。" = "Create a task card from a command or prompt, then drag it to the target pane.";
```

- [ ] **Step 6: Run task card test and i18n audit**

Run:

```bash
swift test --filter TaskCardCommandDeckCopyTests
python3 Scripts/audit-i18n.py --strict --limit 200
```

Expected: both commands exit 0.

- [ ] **Step 7: Commit**

```bash
git add Sources/ConductorApp/UI/TaskCardsPanel.swift Sources/ConductorApp/Resources/en.lproj/Localizable.strings Tests/ConductorAppTests/TaskCardCommandDeckCopyTests.swift
git commit -m "Frame task cards as assignable work"
```

## Task 6: Onboarding Teaches The Command Deck Loop

**Files:**
- Modify: `Sources/ConductorApp/UI/OnboardingPresentationState.swift`
- Modify: `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`
- Modify: `Tests/ConductorAppTests/OnboardingPresentationStateTests.swift`

- [ ] **Step 1: Add failing onboarding catalog tests**

Append this test to `Tests/ConductorAppTests/OnboardingPresentationStateTests.swift`:

```swift
func testOnboardingPagesTeachCommandDeckLoop() {
    XCTAssertEqual(
        OnboardingCatalog.pages.map(\.id),
        ["stage", "voices", "assign", "attention", "capabilities"]
    )

    XCTAssertEqual(OnboardingCatalog.pages.first?.title, "从一个项目舞台开始")
    XCTAssertEqual(OnboardingCatalog.pages.last?.title, "把能力收进能力库")
    XCTAssertTrue(OnboardingCatalog.pages.flatMap(\.beats).contains("拖到面板执行"))
    XCTAssertTrue(OnboardingCatalog.pages.flatMap(\.beats).contains("Skills / MCP / Hooks"))
}
```

- [ ] **Step 2: Run the failing onboarding test**

Run:

```bash
swift test --filter OnboardingPresentationStateTests/testOnboardingPagesTeachCommandDeckLoop
```

Expected: FAIL because current page IDs and copy still describe feature modules instead of the command deck loop.

- [ ] **Step 3: Replace onboarding pages**

In `Sources/ConductorApp/UI/OnboardingPresentationState.swift`, replace `OnboardingCatalog.pages` with:

```swift
static let pages: [OnboardingPage] = [
    OnboardingPage(
        id: "stage",
        screenshotName: "onboarding-workspace",
        screenshotFocus: .workspace,
        accent: .blue,
        eyebrow: "工作区",
        title: "从一个项目舞台开始",
        body: "每个工作区都是一个项目现场：目录、标签、分屏、最近会话和布局都围绕这个现场组织。",
        beats: ["选择项目舞台", "保留分屏现场", "恢复最近上下文"]
    ),
    OnboardingPage(
        id: "voices",
        screenshotName: "onboarding-workspace",
        screenshotFocus: .workspace,
        accent: .violet,
        eyebrow: "面板",
        title: "把每个面板当成一个声部",
        body: "面板负责具体执行：Shell、Agent、命令记录、搜索、分屏和放大都留在当前声部里。",
        beats: ["分屏组织工作", "面板本地控制", "双击放大/还原"]
    ),
    OnboardingPage(
        id: "assign",
        screenshotName: "onboarding-tools",
        screenshotFocus: .rightPanel,
        accent: .mint,
        eyebrow: "任务",
        title: "把任务甩给正确的执行者",
        body: "任务卡片是一段可复用的乐谱。拖到某个面板，就交给那个 Shell 或 Agent 执行。",
        beats: ["拖到面板执行", "变量按需填写", "当前上下文运行"]
    ),
    OnboardingPage(
        id: "attention",
        screenshotName: "onboarding-workspace",
        screenshotFocus: .workspace,
        accent: .rose,
        eyebrow: "注意力",
        title: "只看真正需要你指挥的地方",
        body: "完成、等待、审批和后台运行都会回到状态栏、工作区、标签或伙伴层，提醒你下一步该看哪里。",
        beats: ["完成未读", "活动记录", "跳回相关面板"]
    ),
    OnboardingPage(
        id: "capabilities",
        screenshotName: "onboarding-tools",
        screenshotFocus: .rightPanel,
        accent: .amber,
        eyebrow: "能力库",
        title: "把能力收进能力库",
        body: "CLI、Skills、MCP、Hooks 和供应商用量都归到能力库。这里管理能力，工作区和面板只使用能力。",
        beats: ["Skills / MCP / Hooks", "CLI 检测", "供应商与用量"]
    ),
]
```

- [ ] **Step 4: Add English translations**

Append these keys to `Sources/ConductorApp/Resources/en.lproj/Localizable.strings`:

```text
"从一个项目舞台开始" = "Start from a project stage";
"每个工作区都是一个项目现场：目录、标签、分屏、最近会话和布局都围绕这个现场组织。" = "Each workspace is a project stage: folders, tabs, splits, recent sessions, and layouts are organized around it.";
"选择项目舞台" = "Choose a project stage";
"保留分屏现场" = "Keep split layouts";
"恢复最近上下文" = "Restore recent context";
"把每个面板当成一个声部" = "Treat each pane as a voice";
"面板负责具体执行：Shell、Agent、命令记录、搜索、分屏和放大都留在当前声部里。" = "Panes handle execution: Shell, Agents, command logs, search, splits, and zoom stay with the current voice.";
"分屏组织工作" = "Organize work with splits";
"面板本地控制" = "Pane-local controls";
"双击放大/还原" = "Double-click to zoom or restore";
"把任务甩给正确的执行者" = "Assign tasks to the right performer";
"任务卡片是一段可复用的乐谱。拖到某个面板，就交给那个 Shell 或 Agent 执行。" = "A task card is a reusable score fragment. Drag it to a pane and that Shell or Agent runs it.";
"拖到面板执行" = "Drag to a pane to run";
"变量按需填写" = "Fill variables only when needed";
"当前上下文运行" = "Run in the current context";
"只看真正需要你指挥的地方" = "Watch only what needs direction";
"完成、等待、审批和后台运行都会回到状态栏、工作区、标签或伙伴层，提醒你下一步该看哪里。" = "Done, waiting, approvals, and background work return to the status bar, workspaces, tabs, or companion layer so you know where to look next.";
"完成未读" = "Unread completions";
"活动记录" = "Activity record";
"跳回相关面板" = "Jump back to the relevant pane";
"把能力收进能力库" = "Collect capabilities in the library";
"CLI、Skills、MCP、Hooks 和供应商用量都归到能力库。这里管理能力，工作区和面板只使用能力。" = "CLI, Skills, MCP, Hooks, and provider usage belong in the Capability Library. Capabilities are managed here and used by workspaces and panes.";
"CLI 检测" = "CLI detection";
```

- [ ] **Step 5: Run onboarding tests and i18n audit**

Run:

```bash
swift test --filter OnboardingPresentationStateTests
python3 Scripts/audit-i18n.py --strict --limit 200
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit**

```bash
git add Sources/ConductorApp/UI/OnboardingPresentationState.swift Sources/ConductorApp/Resources/en.lproj/Localizable.strings Tests/ConductorAppTests/OnboardingPresentationStateTests.swift
git commit -m "Teach command deck model in onboarding"
```

## Task 7: Command Palette Scope Display

**Files:**
- Modify: `Sources/ConductorApp/UI/CommandPaletteView.swift`
- Modify: `Sources/ConductorApp/AppCoordinator.swift`
- Test: `Tests/ConductorAppTests/CommandDeckScopeTests.swift`

- [ ] **Step 1: Add failing palette item scope test**

Append to `Tests/ConductorAppTests/CommandDeckScopeTests.swift`:

```swift
func testPalettePresentationIncludesCommandLayer() {
    let item = PaletteItem(
        id: "cmd:taskCards",
        icon: "command",
        title: "Task Cards",
        subtitle: "",
        layerTitle: CommandDeckLayer.task.title
    ) {}

    XCTAssertEqual(item.layerTitle, "任务")
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
swift test --filter CommandDeckScopeTests/testPalettePresentationIncludesCommandLayer
```

Expected: FAIL because `PaletteItem.layerTitle` does not exist.

- [ ] **Step 3: Extend palette item presentation**

In `Sources/ConductorApp/UI/CommandPaletteView.swift`, replace `PaletteItem` with:

```swift
/// 命令面板的一项：命令 / 标签 / 工作区。
struct PaletteItem: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let layerTitle: String?
    let run: () -> Void

    init(
        id: String,
        icon: String,
        title: String,
        subtitle: String,
        layerTitle: String? = nil,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.layerTitle = layerTitle
        self.run = run
    }
}
```

- [ ] **Step 4: Tag command palette items with their deck layer**

In `Sources/ConductorApp/AppCoordinator.swift`, update `paletteItems()` item construction.

For registered commands:

```swift
items.append(PaletteItem(
    id: "cmd:\(c.id)",
    icon: "command",
    title: c.title,
    subtitle: kb,
    layerTitle: c.scope.title,
    run: c.run))
```

For workspaces:

```swift
items.append(PaletteItem(
    id: "ws:\(id.value)",
    icon: "folder",
    title: L("工作区：%@", ws.name),
    subtitle: ws.path,
    layerTitle: CommandDeckLayer.workspace.title
) { [weak self] in self?.selectWorkspace(id) })
```

For tabs:

```swift
items.append(PaletteItem(
    id: "tab:\(tid.value)",
    icon: "macwindow",
    title: L("标签：%@", t),
    subtitle: "",
    layerTitle: CommandDeckLayer.workspace.title
) { [weak self] in self?.selectTab(tid) })
```

For snippets:

```swift
items.append(PaletteItem(
    id: "snippet:\(snippet.id)",
    icon: snippet.autoRun ? "bolt" : "text.cursor",
    title: L("片段：%@", snippet.name),
    subtitle: snippet.command,
    layerTitle: CommandDeckLayer.capability.title
) { [weak self] in self?.sendSnippet(snippet) })
```

For recent sessions:

```swift
items.append(PaletteItem(
    id: "session:\(record.id)",
    icon: "bubble.left.and.text.bubble.right",
    title: L("续聊：%@", record.title),
    subtitle: dir.map { "\(record.agent) · \($0)" } ?? record.agent,
    layerTitle: CommandDeckLayer.agent.title
) { [weak self] in self?.resumeSession(record, inPane: nil) })
```

- [ ] **Step 5: Render scope in command palette rows**

In the command palette row view, add a subtle badge after the subtitle or trailing shortcut:

```swift
if let layerTitle = item.layerTitle {
    Text(layerTitle)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppStyle.textTertiary)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(
            Capsule().fill(AppStyle.theme.isDark ? Color.white.opacity(0.045) : Color.black.opacity(0.035))
        )
}
```

- [ ] **Step 6: Run command palette tests**

Run:

```bash
swift test --filter CommandDeckScopeTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/ConductorApp/UI/CommandPaletteView.swift Sources/ConductorApp/AppCoordinator.swift Tests/ConductorAppTests/CommandDeckScopeTests.swift
git commit -m "Show command deck layers in command palette"
```

## Task 8: Verification, Packaging, And Visual Review

**Files:**
- Verify only.
- Generated bundle: `Conductor.app`

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --filter CommandDeckScopeTests
swift test --filter CapabilityLibraryPresentationTests
swift test --filter ToolbarChromePolicyTests
swift test --filter CommandDeckMenuLayerTests
swift test --filter TaskCardCommandDeckCopyTests
swift test --filter OnboardingPresentationStateTests
```

Expected: every command exits 0.

- [ ] **Step 2: Run full tests**

Run:

```bash
swift test
```

Expected: all XCTest suites pass with 0 failures.

- [ ] **Step 3: Run localization and whitespace checks**

Run:

```bash
python3 Scripts/audit-i18n.py --strict --limit 200
git diff --check
plutil -lint Sources/ConductorApp/Resources/en.lproj/Localizable.strings Sources/ConductorApp/Resources/zh-Hans.lproj/Localizable.strings
```

Expected: i18n reports 0 missing translations and both plist files lint as OK.

- [ ] **Step 4: Build the app bundle**

Run:

```bash
Scripts/make-app.sh debug
```

Expected: `/Users/claude/Desktop/conductor/Conductor.app` is rebuilt successfully.

- [ ] **Step 5: Verify signing and bundle plist**

Run:

```bash
codesign --verify --strict --verbose=2 Conductor.app
plutil -lint Conductor.app/Contents/Info.plist
```

Expected: codesign reports `valid on disk` and `satisfies its Designated Requirement`; Info.plist reports `OK`.

- [ ] **Step 6: Launch the rebuilt bundle for visual review**

Run:

```bash
open -n /Users/claude/Desktop/conductor/Conductor.app
```

Expected:
- Top toolbar shows only global/capability/task entries.
- The tools entry reads as Capability Library / 能力库.
- Capability Library header explains CLI, Skills, MCP, Hooks, and providers.
- Pane header controls remain pane-local.
- Task Cards panel explains drag-to-pane assignment.
- Onboarding pages teach the five-step command deck loop.

- [ ] **Step 7: Commit verification-only adjustments**

If visual review reveals copy spacing or translation issues, make only those corrections, rerun the focused check that covers the changed surface, then commit:

```bash
git add Sources/ConductorApp/Resources/en.lproj/Localizable.strings Sources/ConductorApp/UI
git commit -m "Polish command deck phase one copy"
```

If no corrections are needed, do not create an empty commit.
