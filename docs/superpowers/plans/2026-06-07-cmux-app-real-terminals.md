# cmux App（真终端 + 工作区/Tab/分屏 UI）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在已验证的 CmuxCore（模型+持久化）和 libghostty spike 之上，做出一个可启动的单窗口 macOS app：左侧工作区栏 + 顶部 Tab + tab 内自由分屏，每个分屏叶子是一个**真 libghostty 终端**，支持新建/分屏/关闭/切换焦点，并把布局结构持久化。

**Architecture:** 分两段。**Phase A**：把"命令→状态变化+副作用"的纯逻辑下沉进 CmuxCore（reducer 模式：`apply(command, store) -> (newStore, [SessionEffect])`），并提供一个泛型 `SessionRegistry`（PaneID→TerminalSurface），全部用 `FakeSurface` 走 TDD。**Phase B**：新建 `CmuxApp` 可执行目标，把 spike 一般化为 `GhosttySurface`（含运行时 action 路由 + host NSView），用 SwiftUI 外壳 + 桥接 AppKit（`NSSplitView`、`NSViewRepresentable`）渲染 CmuxCore 的 `SplitNode` 树，命令经 Phase A 的 reducer 驱动。Phase B 是集成层，**靠 `swift build` + 运行 + 肉眼验证**，并大量复用 Conductor 的 `Apps/Conductor/Sources/Conductor/Terminal/` 已验证代码。

**Tech Stack:** Swift 6 / SwiftPM；CmuxCore（纯 Swift，XCTest）；SwiftUI + AppKit 桥接；预编译 GhosttyKit（libghostty C API，已 vendored）。

**关键参照（用户自有、已验证的同款实现，可大量复用）：**
- `/Users/uchihasasuke/Desktop/conductor/Apps/Conductor/Sources/Conductor/Terminal/GhosttyAppRuntime.swift`（运行时 + action_cb 路由）
- `.../Terminal/TerminalSurface.swift`（surface 创建/几何/键鼠/text）
- `.../Terminal/TerminalHostView.swift`（NSView 宿主、CAMetalLayer、事件）
- `.../Terminal/TerminalSurfaceRepresentable.swift`（NSViewRepresentable 桥）
- 已落地的 spike：`Sources/CmuxSpike/`（最小可用的运行时 + host view，Phase B 的起点）

**范围/非目标（v1）：** 做：工作区栏（列出/切换/新建）、顶部 Tab、自由分屏、真终端、命令、布局持久化、合理默认键位、基础自绘样式。**不做**（推迟）：web tab、文件管理、AI agent 集成、通知中心、控制 socket、主题系统、scrollback 恢复、多窗口。

---

## File Structure

```
Sources/CmuxCore/                      (Phase A 新增/修改 — 纯 Swift)
  TerminalSurface.swift                # 精简协议（去掉 write/resize）   [修改]
  SessionEffect.swift                  # 命令产生的副作用类型             [新增]
  WorkspaceCommand.swift               # 命令 + reducer: apply -> (store, effects) [新增]
  SessionRegistry.swift                # 泛型 PaneID→TerminalSurface，执行 effects [新增]
Tests/CmuxCoreTests/
  FakeSurface.swift                    # 适配精简协议                      [修改]
  TerminalSurfaceTests.swift           # 适配精简协议                      [修改]
  WorkspaceCommandTests.swift          # reducer 单测                      [新增]
  SessionRegistryTests.swift           # registry 单测（用 FakeSurface）   [新增]

Sources/CmuxApp/                       (Phase B 新增 — 可执行目标)
  main.swift                           # AppKit 入口 + 主窗口
  AppCoordinator.swift                 # 持有 WorkspaceStore，跑 reducer，驱动持久化
  Terminal/
    GhosttyRuntime.swift               # 运行时 + action_cb 路由（改自 spike）
    GhosttySurface.swift               # conforms TerminalSurface；持有 surface + host view
    TerminalHostView.swift             # NSView：CAMetalLayer + 键鼠转发（改自 spike）
  UI/
    RootView.swift                     # SwiftUI：sidebar | (tabbar + split)
    SidebarView.swift                  # 工作区列表（自绘）
    TabBarView.swift                   # 顶部 tab（自绘）
    SplitContainerView.swift           # 递归 NSSplitView 桥（按 SplitNode）
    TerminalPaneView.swift             # NSViewRepresentable 包 host view
  Support/
    AppStyle.swift                     # 自绘配色/尺寸常量
```

> 备注：Phase B 完成后，旧的 `Sources/CmuxSpike/` 在最后一个任务中删除（它已完成证明使命）。

---

# Phase A — CmuxCore 纯逻辑（TDD，全代码）

## Task 1: 精简 TerminalSurface 协议

**理由：** 原协议的 `write(_:Data)` / `resize(cols:rows:)` 是在了解 libghostty 之前的猜测。libghostty 的输入走 NSEvent→`ghostty_surface_key`、尺寸走像素，二者都不属于这个 lifecycle 协议。按 YAGNI 去掉，保留引擎无关的生命周期子集。

**Files:**
- Modify: `Sources/CmuxCore/TerminalSurface.swift`
- Modify: `Tests/CmuxCoreTests/FakeSurface.swift`
- Modify: `Tests/CmuxCoreTests/TerminalSurfaceTests.swift`

- [ ] **Step 1: 改协议**

把 `Sources/CmuxCore/TerminalSurface.swift` 整文件替换为：

```swift
import Foundation

/// 一个终端实例的引擎无关生命周期接口。生产实现是 GhosttySurface（app 层，封装 libghostty）；
/// 测试用 FakeSurface。输入/渲染/尺寸由具体实现在视图层处理，不属于本协议。
public protocol TerminalSurface: AnyObject {
    /// 在给定工作目录启动 shell/PTY。
    func start(cwd: URL)
    /// 使该终端获得键盘焦点。
    func focus()
    /// 关闭终端并释放底层资源。
    func close()

    /// 终端标题变化回调。
    var onTitleChange: ((String) -> Void)? { get set }
    /// 终端工作目录变化回调。
    var onCwdChange: ((URL) -> Void)? { get set }
    /// 进程退出回调，参数为退出码。
    var onExit: ((Int32) -> Void)? { get set }
}
```

- [ ] **Step 2: 改 FakeSurface（去掉 write/resize 记录）**

把 `Tests/CmuxCoreTests/FakeSurface.swift` 整文件替换为：

```swift
import Foundation
@testable import CmuxCore

/// TerminalSurface 的测试替身：记录调用，并允许测试手动触发回调。
final class FakeSurface: TerminalSurface {
    private(set) var startedCwd: URL?
    private(set) var focusCount = 0
    private(set) var closed = false

    var onTitleChange: ((String) -> Void)?
    var onCwdChange: ((URL) -> Void)?
    var onExit: ((Int32) -> Void)?

    func start(cwd: URL) { startedCwd = cwd }
    func focus() { focusCount += 1 }
    func close() { closed = true }

    func simulateTitleChange(_ title: String) { onTitleChange?(title) }
    func simulateCwdChange(_ url: URL) { onCwdChange?(url) }
    func simulateExit(_ code: Int32) { onExit?(code) }
}
```

- [ ] **Step 3: 改 TerminalSurfaceTests（去掉 write/resize 断言）**

把 `Tests/CmuxCoreTests/TerminalSurfaceTests.swift` 整文件替换为：

```swift
import XCTest
import Foundation
@testable import CmuxCore

final class TerminalSurfaceTests: XCTestCase {
    func testFakeRecordsLifecycle() {
        let surface = FakeSurface()
        surface.start(cwd: URL(fileURLWithPath: "/tmp"))
        surface.focus()
        surface.close()
        XCTAssertEqual(surface.startedCwd, URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(surface.focusCount, 1)
        XCTAssertTrue(surface.closed)
    }

    func testFakeFiresCallbacks() {
        let surface = FakeSurface()
        var title: String?
        var cwd: URL?
        var exitCode: Int32?
        surface.onTitleChange = { title = $0 }
        surface.onCwdChange = { cwd = $0 }
        surface.onExit = { exitCode = $0 }
        surface.simulateTitleChange("build running")
        surface.simulateCwdChange(URL(fileURLWithPath: "/proj"))
        surface.simulateExit(0)
        XCTAssertEqual(title, "build running")
        XCTAssertEqual(cwd, URL(fileURLWithPath: "/proj"))
        XCTAssertEqual(exitCode, 0)
    }
}
```

- [ ] **Step 4: 跑测试**

Run: `swift test --filter TerminalSurfaceTests`
Expected: PASS（2 tests）。再跑 `swift test` 确认其余仍绿（CmuxSpike 不在 test target，不受影响）。

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/TerminalSurface.swift Tests/CmuxCoreTests/FakeSurface.swift Tests/CmuxCoreTests/TerminalSurfaceTests.swift
git commit -m "refactor(core): slim TerminalSurface protocol to engine-agnostic lifecycle"
```

---

## Task 2: SessionEffect

命令 reducer 产生的副作用：应用层据此创建/关闭真 surface。

**Files:**
- Create: `Sources/CmuxCore/SessionEffect.swift`
- Test: （随 Task 3 一起测）

- [ ] **Step 1: 实现**

`Sources/CmuxCore/SessionEffect.swift`:

```swift
import Foundation

/// 命令 reducer 产生的副作用，由应用层解释执行（创建/关闭真实终端 surface）。
public enum SessionEffect: Equatable {
    /// 为新 pane 创建一个终端，并在给定目录启动 shell。
    case createSurface(pane: PaneID, cwd: String)
    /// 关闭并释放该 pane 的终端。
    case closeSurface(pane: PaneID)
    /// 把键盘焦点给该 pane 的终端。
    case focusSurface(pane: PaneID)
}
```

- [ ] **Step 2: 提交**

```bash
git add Sources/CmuxCore/SessionEffect.swift
git commit -m "feat(core): add SessionEffect type for command reducer"
```

---

## Task 3: WorkspaceCommand reducer

**Files:**
- Create: `Sources/CmuxCore/WorkspaceCommand.swift`
- Test: `Tests/CmuxCoreTests/WorkspaceCommandTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/WorkspaceCommandTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class WorkspaceCommandTests: XCTestCase {
    // 起始：一个工作区 w1（路径 /proj），含一个 tab t1，单 pane p1。
    private func baseStore() -> WorkspaceStore {
        let tab = Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1"))
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/proj",
                           tabs: [tab], activeTab: TabID("t1"))
        return WorkspaceStore(workspaces: [ws], activeWorkspace: WorkspaceID("w1"))
    }

    func testNewTabAddsTabAndCreatesSurface() {
        var store = baseStore()
        let effects = WorkspaceCommand.newTab(newTabID: TabID("t2"), newPaneID: PaneID("p2"))
            .apply(to: &store)
        let ws = store.workspaces[0]
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t1"), TabID("t2")])
        XCTAssertEqual(ws.activeTab, TabID("t2"))
        XCTAssertEqual(effects, [
            .createSurface(pane: PaneID("p2"), cwd: "/proj"),
            .focusSurface(pane: PaneID("p2")),
        ])
    }

    func testSplitActivePaneInsertsAndCreatesSurface() {
        var store = baseStore()
        let effects = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1"))
            .apply(to: &store)
        let tab = store.workspaces[0].tabs[0]
        XCTAssertEqual(tab.rootSplit.leaves(), [PaneID("p1"), PaneID("p2")])
        XCTAssertEqual(tab.activePane, PaneID("p2"))
        XCTAssertEqual(effects, [
            .createSurface(pane: PaneID("p2"), cwd: "/proj"),
            .focusSurface(pane: PaneID("p2")),
        ])
    }

    func testClosePaneRemovesAndClosesSurface() {
        var store = baseStore()
        // 先分屏成 p1|p2，active=p2
        _ = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1")).apply(to: &store)
        let effects = WorkspaceCommand.closeActivePane.apply(to: &store)
        let tab = store.workspaces[0].tabs[0]
        XCTAssertEqual(tab.rootSplit, .leaf(PaneID("p1")))
        XCTAssertEqual(tab.activePane, PaneID("p1"))
        XCTAssertEqual(effects, [
            .closeSurface(pane: PaneID("p2")),
            .focusSurface(pane: PaneID("p1")),
        ])
    }

    func testCloseLastPaneInTabClosesTab() {
        var store = baseStore()
        let effects = WorkspaceCommand.closeActivePane.apply(to: &store)
        XCTAssertTrue(store.workspaces[0].tabs.isEmpty)
        XCTAssertEqual(effects, [.closeSurface(pane: PaneID("p1"))])
    }

    func testFocusPaneEmitsFocusEffect() {
        var store = baseStore()
        _ = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1")).apply(to: &store)
        let effects = WorkspaceCommand.focusPane(PaneID("p1")).apply(to: &store)
        XCTAssertEqual(store.workspaces[0].tabs[0].activePane, PaneID("p1"))
        XCTAssertEqual(effects, [.focusSurface(pane: PaneID("p1"))])
    }

    func testSelectTabUpdatesActiveAndFocusesItsPane() {
        var store = baseStore()
        _ = WorkspaceCommand.newTab(newTabID: TabID("t2"), newPaneID: PaneID("p2")).apply(to: &store)
        let effects = WorkspaceCommand.selectTab(TabID("t1")).apply(to: &store)
        XCTAssertEqual(store.workspaces[0].activeTab, TabID("t1"))
        XCTAssertEqual(effects, [.focusSurface(pane: PaneID("p1"))])
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter WorkspaceCommandTests`
Expected: 编译失败，`cannot find 'WorkspaceCommand' in scope`

- [ ] **Step 3: 实现 reducer**

`Sources/CmuxCore/WorkspaceCommand.swift`:

```swift
import Foundation

/// 用户/键位触发的工作区命令。`apply` 是纯函数：修改 store（in-out），返回应用层要执行的副作用。
/// 所有"会发生什么"的逻辑集中在此并可单测；应用层只负责把 SessionEffect 翻译成真实终端操作。
public enum WorkspaceCommand {
    case newTab(newTabID: TabID, newPaneID: PaneID)
    case split(axis: SplitAxis, newPaneID: PaneID, splitID: SplitID)
    case closeActivePane
    case focusPane(PaneID)
    case selectTab(TabID)

    @discardableResult
    public func apply(to store: inout WorkspaceStore) -> [SessionEffect] {
        guard let wsIndex = activeWorkspaceIndex(in: store) else { return [] }
        let cwd = store.workspaces[wsIndex].path

        switch self {
        case let .newTab(newTabID, newPaneID):
            store.workspaces[wsIndex].addTab(
                Tab.single(id: newTabID, title: "zsh", pane: newPaneID)
            )
            return [.createSurface(pane: newPaneID, cwd: cwd), .focusSurface(pane: newPaneID)]

        case let .split(axis, newPaneID, splitID):
            guard let tabIndex = activeTabIndex(in: store, wsIndex: wsIndex) else { return [] }
            let target = store.workspaces[wsIndex].tabs[tabIndex].activePane
            store.workspaces[wsIndex].tabs[tabIndex].rootSplit =
                store.workspaces[wsIndex].tabs[tabIndex].rootSplit
                    .splitting(target, with: newPaneID, axis: axis, ratio: 0.5, splitID: splitID)
            store.workspaces[wsIndex].tabs[tabIndex].activePane = newPaneID
            return [.createSurface(pane: newPaneID, cwd: cwd), .focusSurface(pane: newPaneID)]

        case .closeActivePane:
            guard let tabIndex = activeTabIndex(in: store, wsIndex: wsIndex) else { return [] }
            let closing = store.workspaces[wsIndex].tabs[tabIndex].activePane
            if let newTree = store.workspaces[wsIndex].tabs[tabIndex].rootSplit.removing(closing) {
                store.workspaces[wsIndex].tabs[tabIndex].rootSplit = newTree
                let nextFocus = newTree.leaves().first ?? closing
                store.workspaces[wsIndex].tabs[tabIndex].activePane = nextFocus
                return [.closeSurface(pane: closing), .focusSurface(pane: nextFocus)]
            } else {
                // tab 内最后一个 pane：关掉整个 tab
                let tabID = store.workspaces[wsIndex].tabs[tabIndex].id
                store.workspaces[wsIndex].closeTab(tabID)
                var effects: [SessionEffect] = [.closeSurface(pane: closing)]
                if let newActiveTab = store.workspaces[wsIndex].activeTab,
                   let t = store.workspaces[wsIndex].tabs.first(where: { $0.id == newActiveTab }) {
                    effects.append(.focusSurface(pane: t.activePane))
                }
                return effects
            }

        case let .focusPane(pane):
            guard let tabIndex = activeTabIndex(in: store, wsIndex: wsIndex),
                  store.workspaces[wsIndex].tabs[tabIndex].rootSplit.contains(pane) else { return [] }
            store.workspaces[wsIndex].tabs[tabIndex].activePane = pane
            return [.focusSurface(pane: pane)]

        case let .selectTab(tabID):
            guard store.workspaces[wsIndex].tabs.contains(where: { $0.id == tabID }) else { return [] }
            store.workspaces[wsIndex].activeTab = tabID
            if let t = store.workspaces[wsIndex].tabs.first(where: { $0.id == tabID }) {
                return [.focusSurface(pane: t.activePane)]
            }
            return []
        }
    }

    private func activeWorkspaceIndex(in store: WorkspaceStore) -> Int? {
        guard let id = store.activeWorkspace else { return nil }
        return store.workspaces.firstIndex(where: { $0.id == id })
    }

    private func activeTabIndex(in store: WorkspaceStore, wsIndex: Int) -> Int? {
        guard let id = store.workspaces[wsIndex].activeTab else { return nil }
        return store.workspaces[wsIndex].tabs.firstIndex(where: { $0.id == id })
    }
}
```

- [ ] **Step 4: 跑测试**

Run: `swift test --filter WorkspaceCommandTests`
Expected: PASS（6 tests）

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SessionEffect.swift Sources/CmuxCore/WorkspaceCommand.swift Tests/CmuxCoreTests/WorkspaceCommandTests.swift
git commit -m "feat(core): WorkspaceCommand reducer producing SessionEffects"
```

---

## Task 4: SessionRegistry（泛型 PaneID→TerminalSurface）

**Files:**
- Create: `Sources/CmuxCore/SessionRegistry.swift`
- Test: `Tests/CmuxCoreTests/SessionRegistryTests.swift`

- [ ] **Step 1: 写失败测试**

`Tests/CmuxCoreTests/SessionRegistryTests.swift`:

```swift
import XCTest
@testable import CmuxCore

final class SessionRegistryTests: XCTestCase {
    func testCreateSurfaceUsesFactoryAndStartsAtCwd() {
        var made: [PaneID: FakeSurface] = [:]
        let registry = SessionRegistry { _ in
            let s = FakeSurface(); return s
        } onPaneExited: { _ in }
        // 用一个能捕获实例的工厂
        let reg2 = SessionRegistry(factory: { pane in
            let s = FakeSurface(); made[pane] = s; return s
        }, onPaneExited: { _ in })
        reg2.apply([.createSurface(pane: PaneID("p1"), cwd: "/proj")])
        XCTAssertEqual(made[PaneID("p1")]?.startedCwd, URL(fileURLWithPath: "/proj"))
        XCTAssertNotNil(reg2.surface(for: PaneID("p1")))
        _ = registry // 避免未使用告警
    }

    func testFocusEffectFocusesSurface() {
        var made: [PaneID: FakeSurface] = [:]
        let registry = SessionRegistry(factory: { pane in
            let s = FakeSurface(); made[pane] = s; return s
        }, onPaneExited: { _ in })
        registry.apply([.createSurface(pane: PaneID("p1"), cwd: "/proj")])
        registry.apply([.focusSurface(pane: PaneID("p1"))])
        XCTAssertEqual(made[PaneID("p1")]?.focusCount, 1)
    }

    func testCloseEffectClosesAndForgets() {
        var made: [PaneID: FakeSurface] = [:]
        let registry = SessionRegistry(factory: { pane in
            let s = FakeSurface(); made[pane] = s; return s
        }, onPaneExited: { _ in })
        registry.apply([.createSurface(pane: PaneID("p1"), cwd: "/proj")])
        registry.apply([.closeSurface(pane: PaneID("p1"))])
        XCTAssertTrue(made[PaneID("p1")]?.closed ?? false)
        XCTAssertNil(registry.surface(for: PaneID("p1")))
    }

    func testSurfaceExitInvokesOnPaneExited() {
        var made: [PaneID: FakeSurface] = [:]
        var exited: [PaneID] = []
        let registry = SessionRegistry(factory: { pane in
            let s = FakeSurface(); made[pane] = s; return s
        }, onPaneExited: { exited.append($0) })
        registry.apply([.createSurface(pane: PaneID("p1"), cwd: "/proj")])
        made[PaneID("p1")]?.simulateExit(0)
        XCTAssertEqual(exited, [PaneID("p1")])
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

Run: `swift test --filter SessionRegistryTests`
Expected: 编译失败，`cannot find 'SessionRegistry' in scope`

- [ ] **Step 3: 实现**

`Sources/CmuxCore/SessionRegistry.swift`:

```swift
import Foundation

/// 持有 PaneID→TerminalSurface 的映射，并把 SessionEffect 翻译成真实生命周期调用。
/// 泛型/可注入工厂，使其在 CmuxCore 中可用 FakeSurface 单测；app 注入 GhosttySurface 工厂。
public final class SessionRegistry {
    private var surfaces: [PaneID: TerminalSurface] = [:]
    private let factory: (PaneID) -> TerminalSurface
    private let onPaneExited: (PaneID) -> Void

    public init(factory: @escaping (PaneID) -> TerminalSurface,
                onPaneExited: @escaping (PaneID) -> Void) {
        self.factory = factory
        self.onPaneExited = onPaneExited
    }

    public func surface(for pane: PaneID) -> TerminalSurface? { surfaces[pane] }

    public func apply(_ effects: [SessionEffect]) {
        for effect in effects { apply(effect) }
    }

    private func apply(_ effect: SessionEffect) {
        switch effect {
        case let .createSurface(pane, cwd):
            guard surfaces[pane] == nil else { return }
            let surface = factory(pane)
            surface.onExit = { [weak self] _ in self?.onPaneExited(pane) }
            surfaces[pane] = surface
            surface.start(cwd: URL(fileURLWithPath: cwd))
        case let .closeSurface(pane):
            surfaces[pane]?.close()
            surfaces[pane] = nil
        case let .focusSurface(pane):
            surfaces[pane]?.focus()
        }
    }
}
```

- [ ] **Step 4: 跑测试**

Run: `swift test --filter SessionRegistryTests`
Expected: PASS（4 tests）。再跑全量 `swift test` 确认 ≥ 49 + 新增全绿。

- [ ] **Step 5: 提交**

```bash
git add Sources/CmuxCore/SessionRegistry.swift Tests/CmuxCoreTests/SessionRegistryTests.swift
git commit -m "feat(core): SessionRegistry maps panes to surfaces and applies effects"
```

---

# Phase B — App 层（集成；`swift build` + 运行验证；复用 Conductor）

> Phase B 任务以**构建通过 + 运行肉眼验证**为验收。每个任务给出要创建的文件、要从 Conductor 复用/改写的具体源文件、关键适配点，以及确切的 `swift build` 命令与预期。GhosttyKit 已 vendored（`Vendor/GhosttyKit.xcframework`，若缺失先跑 `./Scripts/prepare-ghosttykit.sh`）。

## Task 5: 新建 CmuxApp 可执行目标 + 空窗口

**Files:**
- Modify: `Package.swift`（加 `CmuxApp` executableTarget，依赖 `CmuxCore` + `GhosttyKit`，linkerSettings 同 CmuxSpike）
- Create: `Sources/CmuxApp/main.swift`（AppKit 入口 + 一个空 `NSWindow`，沿用 CmuxSpike/main.swift 的 `MainActor.assumeIsolated` + AppDelegate 结构，标题 "cmux"）
- Create: `Sources/CmuxApp/UI/RootView.swift`（先放一个占位 `NSView`/空 SwiftUI `Text("cmux")`）

**适配点：** target 设 `.swiftLanguageMode(.v5)`（同 CmuxSpike，避免 C 回调并发摩擦）。

- [ ] Step 1: 在 Package.swift 的 `products` 加 `.executable(name: "CmuxApp", targets: ["CmuxApp"])`，`targets` 加 `CmuxApp`（dependencies: `["CmuxCore", "GhosttyKit"]`，swiftSettings `[.swiftLanguageMode(.v5)]`，linkerSettings 同 CmuxSpike 的 6 个：c++/AppKit/Carbon/IOSurface/Metal/QuartzCore）。
- [ ] Step 2: 写 `main.swift`（复制 `Sources/CmuxSpike/main.swift`，contentView 暂时 `NSView()`，标题改 "cmux"）。
- [ ] Step 3: `swift build --product CmuxApp`，预期 `Build complete!`（含无害 ImGui 链接告警）。
- [ ] Step 4: 运行 `.build/debug/CmuxApp`，肉眼确认弹出空窗口。Ctrl-C/关窗退出。
- [ ] Step 5: 提交 `feat(app): scaffold CmuxApp executable with empty window`。

## Task 6: GhosttyRuntime（含 action_cb 路由）

**Files:**
- Create: `Sources/CmuxApp/Terminal/GhosttyRuntime.swift`

**复用：** 以 `Sources/CmuxSpike/GhosttyRuntime.swift` 为基础，把 `action_cb` 从 `{ _, _, _ in false }` 升级为：按 `target.tag == GHOSTTY_TARGET_SURFACE` 取 `target.target.surface`，用 `ghostty_surface_userdata` 取回 `GhosttySurface`（见 Task 7），分派 `GHOSTTY_ACTION_SET_TITLE`/`GHOSTTY_ACTION_PWD`/`GHOSTTY_ACTION_SHOW_CHILD_EXITED`/`GHOSTTY_ACTION_CLOSE_TAB` 到对应回调。**直接参照** Conductor 的 `GhosttyAppRuntime.handleAction`（只保留这 4 个 case，其余 `default: return false`）。`wakeup_cb`/tick/`ensureStarted` 沿用 spike。

- [ ] Step 1: 写文件（singleton `GhosttyRuntime.shared`，`ensureStarted()` 同 spike，新增 `action_cb` 路由 title/pwd/exit）。
- [ ] Step 2: `swift build --product CmuxApp`，预期 Build complete（此任务可能引用 Task 7 的 GhosttySurface，与 Task 7 一并编译通过；若单独构建报缺 GhosttySurface，先占位再于 Task 7 接上）。
- [ ] Step 3: 提交 `feat(app): GhosttyRuntime with per-surface action routing`。

## Task 7: GhosttySurface + TerminalHostView

**Files:**
- Create: `Sources/CmuxApp/Terminal/TerminalHostView.swift`（NSView，CAMetalLayer 背衬 + 键鼠转发；改自 `Sources/CmuxSpike/SpikeTerminalView.swift`，但把"创建 surface/几何/输入"拆给 GhosttySurface，view 只转发事件给 `weak var surface: GhosttySurface?`，参照 Conductor 的 TerminalHostView 精简版）
- Create: `Sources/CmuxApp/Terminal/GhosttySurface.swift`（`final class GhosttySurface: CmuxCore.TerminalSurface`，持有 `ghostty_surface_t` + `TerminalHostView`，实现 `start(cwd:)`=创建 surface（参照 spike 的 createSurface，command `/bin/zsh`、working_directory=cwd、userdata=`Unmanaged.passRetained(self)`）、`focus()`、`close()`，并暴露 `hostView`；`onTitleChange/onCwdChange/onExit` 由 GhosttyRuntime 的 action 路由触发；静态 `fromGhosttySurface(_:)` 用 userdata 取回实例）

**关键适配点：**
- surface 的 `userdata` 设为 `Unmanaged.passRetained(self).toOpaque()`，`close()` 里 `release`；`fromGhosttySurface` 用 `ghostty_surface_userdata` + `takeUnretainedValue`（照搬 Conductor）。
- 几何/输入逻辑（content_scale/set_size/key/mouse）从 spike 的 `SpikeTerminalView` 搬到 host view，调用 `surface` 的 ghostty handle。
- `start(cwd:)` 需要 host view 已在 window 上才能建 surface（参照 Conductor 的 `attachIfPossible`：view `viewDidMoveToWindow` 时若 surface 为空则创建）。v1 简化：GhosttySurface 创建即建好 hostView，`start(cwd:)` 暂存 cwd，host view 上墙时创建 ghostty surface。

- [ ] Step 1: 写 `TerminalHostView.swift`（CAMetalLayer 背衬 + keyDown/keyUp/mouse 转发到 `surface`；`ghosttyMods`/`printableText` 等 helper 从 spike 搬来）。
- [ ] Step 2: 写 `GhosttySurface.swift`（conforms TerminalSurface；持有 hostView；create/focus/close；userdata 取回）。
- [ ] Step 3: `swift build --product CmuxApp`，预期 Build complete。
- [ ] Step 4: 临时在 `main.swift` 把窗口 contentView 设成一个 `GhosttySurface` 的 hostView 并 `start(cwd: home)`，运行确认**单个真终端可输入输出**（回归 spike 行为，但走新结构）。验证后还原 contentView（下一任务接 UI）。
- [ ] Step 5: 提交 `feat(app): GhosttySurface + TerminalHostView (real libghostty terminal)`。

## Task 8: SplitContainerView（递归 NSSplitView）+ TerminalPaneView

**Files:**
- Create: `Sources/CmuxApp/UI/TerminalPaneView.swift`（`NSViewRepresentable`/或直接 NSView 包装，把某 `PaneID` 对应 GhosttySurface 的 hostView 放进去；从 `SessionRegistry` 取 surface）
- Create: `Sources/CmuxApp/UI/SplitContainerView.swift`（输入一棵 `SplitNode` + 一个"取 pane 视图"的闭包，递归构建 `NSSplitView`：`.leaf` → pane 视图；`.split(axis,ratio,first,second)` → 一个 `NSSplitView`（`.isVertical = axis == .vertical`），按 ratio 设分隔位置，子项递归）

**适配点：** v1 用 AppKit `NSSplitView` 直接桥接（手感稳）；拖拽分隔条改 ratio 的回写留待后续（先固定 0.5/按 ratio 初始布局）。`axis == .vertical` 表示左右分（竖直分隔条）→ `NSSplitView.isVertical = true`。

- [ ] Step 1: 写 TerminalPaneView（按 PaneID 拿 hostView 塞进容器 NSView）。
- [ ] Step 2: 写 SplitContainerView（递归）。
- [ ] Step 3: `swift build --product CmuxApp`，Build complete。
- [ ] Step 4: 临时在 main.swift 用一个手搓的二叉 `SplitNode`（p1|p2）+ 两个 GhosttySurface 驱动，运行确认**左右两个真终端并排**。
- [ ] Step 5: 提交 `feat(app): recursive SplitContainerView over SplitNode with real terminals`。

## Task 9: AppCoordinator + 命令/键位

**Files:**
- Create: `Sources/CmuxApp/AppCoordinator.swift`（`@MainActor` 持有 `var store: WorkspaceStore`、`SessionRegistry`（工厂创建 GhosttySurface）、当前布局视图的刷新闭包；`run(_ command: WorkspaceCommand)`：`let effects = command.apply(to: &store); registry.apply(effects); rebuildActiveTabView()`；ID 用 `UUID().uuidString` 生成）
- Modify: `Sources/CmuxApp/main.swift`（初始化 coordinator，seed 一个工作区 w1=当前目录或 $HOME，一个 tab 一个 pane；窗口 contentView = 当前 tab 的 SplitContainerView；安装键位）

**键位（NSEvent 监听或 menu）：** `⌘T` newTab、`⌘D` split(.vertical)、`⌘⇧D` split(.horizontal)、`⌘W` closeActivePane、`⌘⌥←/→` focus 前/后一个 pane（用 `rootSplit.pane(before:/after:)`）。

- [ ] Step 1: 写 AppCoordinator（seed + run + rebuild）。
- [ ] Step 2: main.swift 接上 coordinator + 键位（用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 或 NSMenu）。
- [ ] Step 3: `swift build --product CmuxApp`，Build complete。
- [ ] Step 4: 运行：单终端起步；`⌘D` 竖分出第二个真终端、`⌘⇧D` 横分、`⌘W` 关闭并塌缩、`⌘T` 新 tab（先无 tab 栏，焦点切到新 tab 的终端即可）、`⌘⌥←/→` 切焦点。逐一肉眼验证。
- [ ] Step 5: 提交 `feat(app): AppCoordinator wires WorkspaceCommand to live split UI + keybindings`。

## Task 10: TabBarView（自绘）

**Files:**
- Create: `Sources/CmuxApp/UI/TabBarView.swift`（SwiftUI 自绘横向 tab 条：当前工作区的 tabs，点击 → `coordinator.run(.selectTab(id))`，`+` → `.newTab`；active tab 高亮）
- Modify: `Sources/CmuxApp/UI/RootView.swift`（顶部 TabBar + 下方 SplitContainer）
- Create: `Sources/CmuxApp/Support/AppStyle.swift`（配色/间距常量）

- [ ] Step 1: 写 AppStyle + TabBarView。
- [ ] Step 2: RootView 组合 tabbar + split；main.swift 用 `NSHostingView(rootView:)` 承载。
- [ ] Step 3: `swift build --product CmuxApp`，Build complete。
- [ ] Step 4: 运行：顶部出现 tab 条，能点击切换、`+` 新建，active 高亮，切 tab 时下方终端随之切换。
- [ ] Step 5: 提交 `feat(app): self-drawn top tab bar wired to commands`。

## Task 11: SidebarView（工作区，自绘）

**Files:**
- Create: `Sources/CmuxApp/UI/SidebarView.swift`（SwiftUI 自绘左侧工作区列表：列出 `store.workspaces`，点击切换 active workspace，`+` 选目录新建工作区（`NSOpenPanel` 选目录 → 新 Workspace，path=选中目录，含一个 tab 一个 pane）；active 高亮）
- Modify: `Sources/CmuxApp/AppCoordinator.swift`（加 `selectWorkspace(WorkspaceID)` 与 `addWorkspace(path:)`：用 `WorkspaceStore.upsert/activeWorkspace`，切换时 rebuild 并 focus 其 active tab 的 pane）
- Modify: `RootView.swift`（左 Sidebar | 右 (TabBar+Split)）

- [ ] Step 1: coordinator 加 selectWorkspace/addWorkspace。
- [ ] Step 2: 写 SidebarView；RootView 三栏组合。
- [ ] Step 3: `swift build --product CmuxApp`，Build complete。
- [ ] Step 4: 运行：左侧出现工作区栏；`+` 选目录新建工作区（路径绑定）；切换工作区时 tab/分屏随之切换；不同工作区的终端起在各自路径。
- [ ] Step 5: 提交 `feat(app): self-drawn workspace sidebar (path-bound workspaces)`。

## Task 12: 持久化接线（StateStore）

**Files:**
- Modify: `Sources/CmuxApp/AppCoordinator.swift`（注入 `StateStore(fileURL: ~/Library/Application Support/cmux/state.json)`；`save()`=`store` 包成 `PersistedState` 原子写，防抖 ~500ms 在每次 `run`/工作区变更后调用；启动 `restore()`：`StateStore.load()`，若 `.loaded` 用其 store 重建——对每个工作区的 active tab 的每个叶子 PaneID，发 `.createSurface(pane:cwd:)`（cwd 用 `CwdResolver.resolve(cwd: 叶子记录或工作区 path, workspacePath:)`），并 focus 各 active pane；若 `.fresh/.recovered` 则 seed 默认工作区）
- Modify: `main.swift`（`applicationWillTerminate` 调 `coordinator.save()`）

**适配点：** 只恢复"结构 + 路径"，每个叶子起**空白 shell**（已定的 B 边界）。v1 简化：恢复时只为**当前可见**（每个工作区 active tab）的叶子建 surface；切到其它 tab 时按需建（或一次性全建，量小可接受——v1 先全建可见 tab 的）。

- [ ] Step 1: coordinator 加 save（防抖）+ restore + seedDefault。
- [ ] Step 2: main.swift 启动调 restore、退出调 save。
- [ ] Step 3: `swift build --product CmuxApp`，Build complete。
- [ ] Step 4: 运行：建几个工作区/tab/分屏 → 退出 → 重开，**布局结构恢复**，各终端在原 cwd 起新 shell（进程不恢复，符合预期）。删/坏 state.json 不崩（走 fresh/recovered）。
- [ ] Step 5: 提交 `feat(app): persist & restore layout via StateStore (blank shells at cwd)`。

## Task 13: 收尾（删 spike、样式打磨、README）

**Files:**
- Delete: `Sources/CmuxSpike/`（移除目标：Package.swift 去掉 CmuxSpike product/target）
- Modify: `Sources/CmuxApp/Support/AppStyle.swift` + 各 UI（间距/配色/焦点高亮/hover 打磨一遍）
- Create: `README.md`（构建步骤：`./Scripts/prepare-ghosttykit.sh` → `swift build` → `swift run CmuxApp`）

- [ ] Step 1: 删除 CmuxSpike 目标与目录。
- [ ] Step 2: 样式打磨（active pane 焦点环、tab/侧栏 active 态、配色统一）。
- [ ] Step 3: 写 README。
- [ ] Step 4: `swift build` 全量 + `swift test`（CmuxCore 全绿）+ 运行 CmuxApp 完整冒烟（工作区/tab/分屏/持久化）。
- [ ] Step 5: 提交 `chore(app): remove spike, polish styling, add README`。

---

## Self-Review（计划作者已核对）

**1. Spec 覆盖（对 2026-06-06 设计 spec）：**
- 三级布局（工作区/Tab/分屏树）→ Task 8/9/10/11 ✓
- 每叶子 = 真 libghostty surface → Task 7/8 ✓
- SwiftUI 优先 + 桥接 AppKit（NSSplitView/NSViewRepresentable/NSWindow/第一响应者）→ Task 5/8/9/10/11 ✓
- 持久化 B（只存结构、原 cwd 起空白 shell、坏文件兜底）→ Task 12 ✓（用 CmuxCore 已有 StateStore/CwdResolver）
- 默认键位 → Task 9 ✓
- 自绘样式 → Task 10/11/13 ✓
- libghostty 隔离在桥接层、上层用协议 → Phase A 协议 + GhosttySurface 实现 ✓
- 错误处理（surface 起失败/坏 state）→ Task 7（失败不崩）/Task 12（fresh/recovered）✓
- **明确推迟**：web tab、AI agent、控制 socket、主题、scrollback、多窗口、分隔条拖拽回写 ratio（Task 8 备注）。

**2. Placeholder 扫描：** Phase A 任务含完整可编译代码 + 确切命令。Phase B 是集成层，按计划约定以"创建文件 + 复用指定 Conductor 文件 + 适配点 + swift build/运行验证"描述，给出确切目标/文件/命令与肉眼验收点，不含 vague 的 "处理边界情况" 之类。

**3. 类型一致性：** `WorkspaceCommand`（newTab/split/closeActivePane/focusPane/selectTab）、`SessionEffect`（createSurface/closeSurface/focusSurface）、`SessionRegistry(factory:onPaneExited:)`/`apply(_:)`/`surface(for:)`、精简后的 `TerminalSurface`（start/focus/close + 3 回调）、复用既有 `SplitNode.splitting/removing/leaves/contains/pane(before:after:)`、`Tab.single`、`Workspace.addTab/closeTab`、`WorkspaceStore.upsert/activeWorkspace`、`PersistedState`/`StateStore.load()`(.loaded/.fresh/.recovered)/`CwdResolver.resolve`。前后一致。

**注意：** Phase B 的"完整逐行代码"刻意不写进计划（会变成把整个 app 抄进文档）；改为"复用 Conductor 指定文件 + 适配点"。执行时若选 subagent 驱动，子代理需能读 Conductor 参照文件与本仓库 spike。这是本计划与纯 TDD 计划（计划一）的有意差异，因为 app/集成层靠构建+运行验证而非单测。
