import XCTest
@testable import ConductorCore

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
        let effects = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1"), cwd: nil)
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
        _ = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1"), cwd: nil).apply(to: &store)
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

    func testCloseTabClosesAllItsPanesAndFocusesFallback() {
        var store = baseStore()
        // t1 分屏成 p1|p2；再开 t2（p3）。active 现在是 t2。
        _ = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1"), cwd: nil).apply(to: &store)
        _ = WorkspaceCommand.newTab(newTabID: TabID("t2"), newPaneID: PaneID("p3")).apply(to: &store)
        // 关掉非 active 的 t1（含 p1、p2 两个 pane）
        let effects = WorkspaceCommand.closeTab(TabID("t1")).apply(to: &store)
        XCTAssertEqual(store.workspaces[0].tabs.map(\.id), [TabID("t2")])
        XCTAssertEqual(store.workspaces[0].activeTab, TabID("t2"))
        XCTAssertEqual(effects, [
            .closeSurface(pane: PaneID("p1")),
            .closeSurface(pane: PaneID("p2")),
            .focusSurface(pane: PaneID("p3")),
        ])
    }

    func testCloseActiveTabFallsBackAndFocuses() {
        var store = baseStore()
        _ = WorkspaceCommand.newTab(newTabID: TabID("t2"), newPaneID: PaneID("p2")).apply(to: &store)
        // active 是 t2；关掉 active 的 t2 → 回退 t1
        let effects = WorkspaceCommand.closeTab(TabID("t2")).apply(to: &store)
        XCTAssertEqual(store.workspaces[0].tabs.map(\.id), [TabID("t1")])
        XCTAssertEqual(store.workspaces[0].activeTab, TabID("t1"))
        XCTAssertEqual(effects, [
            .closeSurface(pane: PaneID("p2")),
            .focusSurface(pane: PaneID("p1")),
        ])
    }

    func testMoveTabReorders() {
        var store = baseStore()
        _ = WorkspaceCommand.newTab(newTabID: TabID("t2"), newPaneID: PaneID("p2")).apply(to: &store)
        _ = WorkspaceCommand.newTab(newTabID: TabID("t3"), newPaneID: PaneID("p3")).apply(to: &store)
        // [t1, t2, t3] → 把 t3 移到最前
        let effects = WorkspaceCommand.moveTab(id: TabID("t3"), toIndex: 0).apply(to: &store)
        XCTAssertEqual(store.workspaces[0].tabs.map(\.id), [TabID("t3"), TabID("t1"), TabID("t2")])
        XCTAssertTrue(effects.isEmpty)
        // active 不变
        XCTAssertEqual(store.workspaces[0].activeTab, TabID("t3"))
    }

    func testFocusPaneEmitsFocusEffect() {
        var store = baseStore()
        _ = WorkspaceCommand.split(axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1"), cwd: nil).apply(to: &store)
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

    // MARK: - 分屏继承 cwd

    func testSplitWithExplicitCwdUsesIt() {
        var store = baseStore()
        let effects = WorkspaceCommand.split(
            axis: .vertical, newPaneID: PaneID("p2"), splitID: SplitID("s1"), cwd: "/proj/src"
        ).apply(to: &store)
        XCTAssertEqual(effects.first, .createSurface(pane: PaneID("p2"), cwd: "/proj/src"))
    }

    // MARK: - 误关恢复

    private func closedTab() -> Tab {
        Tab(
            id: TabID("t9"), title: "zsh",
            rootSplit: .split(
                id: SplitID("s9"), axis: .horizontal, ratio: 0.5,
                first: .leaf(PaneID("p8")), second: .leaf(PaneID("p9"))),
            activePane: PaneID("p9"))
    }

    func testRestoreTabIntoOriginalWorkspaceWithPaneCwds() {
        var store = baseStore()
        let effects = WorkspaceCommand.restoreTab(
            tab: closedTab(), workspaceID: WorkspaceID("w1"),
            paneCwds: ["p8": "/proj/a"]
        ).apply(to: &store)
        let ws = store.workspaces[0]
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t1"), TabID("t9")])
        XCTAssertEqual(ws.activeTab, TabID("t9"))
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w1"))
        XCTAssertEqual(effects, [
            .createSurface(pane: PaneID("p8"), cwd: "/proj/a"),
            .createSurface(pane: PaneID("p9"), cwd: "/proj"),   // 没记录 cwd 回退工作区根
            .focusSurface(pane: PaneID("p9")),
        ])
    }

    func testRestoreTabFallsBackToActiveWorkspaceWhenOriginalGone() {
        var store = baseStore()
        let effects = WorkspaceCommand.restoreTab(
            tab: closedTab(), workspaceID: nil, paneCwds: [:]
        ).apply(to: &store)
        XCTAssertEqual(store.workspaces[0].tabs.map(\.id), [TabID("t1"), TabID("t9")])
        XCTAssertEqual(effects.count, 3)
    }

    func testRestoreTabRefusesPaneIDCollision() {
        var store = baseStore()
        // p1 已存在于现有树里 → 拒绝恢复，不动 store
        let tab = Tab.single(id: TabID("t9"), title: "zsh", pane: PaneID("p1"))
        let before = store
        let effects = WorkspaceCommand.restoreTab(tab: tab, workspaceID: nil, paneCwds: [:])
            .apply(to: &store)
        XCTAssertEqual(store, before)
        XCTAssertTrue(effects.isEmpty)
    }

    func testRestorePaneSplitsBackWithAxisAndCwd() {
        var store = baseStore()
        let effects = WorkspaceCommand.restorePane(
            pane: PaneID("p2"), tabID: TabID("t1"), workspaceID: WorkspaceID("w1"),
            cwd: "/proj/b", axis: .horizontal, splitID: SplitID("s2")
        ).apply(to: &store)
        let tab = store.workspaces[0].tabs[0]
        XCTAssertEqual(tab.rootSplit.leaves(), [PaneID("p1"), PaneID("p2")])
        if case let .split(_, axis, _, _, _) = tab.rootSplit {
            XCTAssertEqual(axis, .horizontal)
        } else {
            XCTFail("应恢复成分屏")
        }
        XCTAssertEqual(tab.activePane, PaneID("p2"))
        XCTAssertEqual(effects, [
            .createSurface(pane: PaneID("p2"), cwd: "/proj/b"),
            .focusSurface(pane: PaneID("p2")),
        ])
    }

    func testRestorePaneRequiresTabAlive() {
        var store = baseStore()
        let before = store
        let effects = WorkspaceCommand.restorePane(
            pane: PaneID("p2"), tabID: TabID("gone"), workspaceID: WorkspaceID("w1"),
            cwd: nil, axis: .vertical, splitID: SplitID("s2")
        ).apply(to: &store)
        XCTAssertEqual(store, before)
        XCTAssertTrue(effects.isEmpty)
    }
}
