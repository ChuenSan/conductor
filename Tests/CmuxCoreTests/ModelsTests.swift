import XCTest
@testable import CmuxCore

final class ModelsTests: XCTestCase {
    func testSingleTabHasOneLeaf() {
        let tab = Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1"))
        XCTAssertEqual(tab.rootSplit, .leaf(PaneID("p1")))
        XCTAssertEqual(tab.activePane, PaneID("p1"))
    }

    func testSingleTabIsNotGroup() {
        let tab = Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1"))
        XCTAssertFalse(tab.isGroup)
        XCTAssertEqual(tab.paneCount, 1)
    }

    func testSplitTabIsGroup() {
        let split = SplitNode.split(id: SplitID("s1"), axis: .vertical, ratio: 0.5,
                                    first: .leaf(PaneID("p1")), second: .leaf(PaneID("p2")))
        let tab = Tab(id: TabID("t1"), title: "zsh", rootSplit: split, activePane: PaneID("p1"))
        XCTAssertTrue(tab.isGroup)
        XCTAssertEqual(tab.paneCount, 2)
    }

    func testWorkspaceAddTabSetsActive() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1")))
        XCTAssertEqual(ws.tabs.count, 1)
        XCTAssertEqual(ws.activeTab, TabID("t1"))
    }

    func testWorkspaceCloseActiveTabFallsBackToPrevious() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.addTab(Tab.single(id: TabID("t2"), title: "b", pane: PaneID("p2")))
        // active 现在是 t2；关掉 t2 应回退到 t1
        ws.closeTab(TabID("t2"))
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t1")])
        XCTAssertEqual(ws.activeTab, TabID("t1"))
    }

    func testWorkspaceCloseLastTabClearsActive() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.closeTab(TabID("t1"))
        XCTAssertTrue(ws.tabs.isEmpty)
        XCTAssertNil(ws.activeTab)
    }

    func testStoreUpsertAndActive() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [], activeTab: nil)
        store.upsert(ws)
        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w1"))
        // 再次 upsert 同 id 应替换而非新增
        var updated = ws
        updated.name = "renamed"
        store.upsert(updated)
        XCTAssertEqual(store.workspaces.count, 1)
        XCTAssertEqual(store.workspaces.first?.name, "renamed")
    }

    func testStoreRemoveWorkspaceUpdatesActive() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        store.upsert(Workspace(id: WorkspaceID("w1"), name: "a", path: "/a", tabs: [], activeTab: nil))
        store.upsert(Workspace(id: WorkspaceID("w2"), name: "b", path: "/b", tabs: [], activeTab: nil))
        store.remove(WorkspaceID("w2"))   // active 当前是 w2
        XCTAssertEqual(store.workspaces.map(\.id), [WorkspaceID("w1")])
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w1"))
    }

    func testCloseUnknownTabIsNoOp() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj", tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.addTab(Tab.single(id: TabID("t2"), title: "b", pane: PaneID("p2")))
        ws.closeTab(TabID("zzz"))
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t1"), TabID("t2")])
        XCTAssertEqual(ws.activeTab, TabID("t2"))
    }

    func testCloseNonActiveTabKeepsActive() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj", tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.addTab(Tab.single(id: TabID("t2"), title: "b", pane: PaneID("p2")))
        // active 是 t2；关掉非 active 的 t1
        ws.closeTab(TabID("t1"))
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t2")])
        XCTAssertEqual(ws.activeTab, TabID("t2"))
    }

    func testCloseFirstActiveTabWithThreeFallsToNewFirst() {
        var ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj", tabs: [], activeTab: nil)
        ws.addTab(Tab.single(id: TabID("t1"), title: "a", pane: PaneID("p1")))
        ws.addTab(Tab.single(id: TabID("t2"), title: "b", pane: PaneID("p2")))
        ws.addTab(Tab.single(id: TabID("t3"), title: "c", pane: PaneID("p3")))
        ws.activeTab = TabID("t1")   // 把焦点设到第一个
        ws.closeTab(TabID("t1"))
        XCTAssertEqual(ws.tabs.map(\.id), [TabID("t2"), TabID("t3")])
        XCTAssertEqual(ws.activeTab, TabID("t2"))
    }

    func testRemoveUnknownWorkspaceIsNoOp() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        store.upsert(Workspace(id: WorkspaceID("w1"), name: "a", path: "/a", tabs: [], activeTab: nil))
        store.upsert(Workspace(id: WorkspaceID("w2"), name: "b", path: "/b", tabs: [], activeTab: nil))
        store.remove(WorkspaceID("zzz"))
        XCTAssertEqual(store.workspaces.map(\.id), [WorkspaceID("w1"), WorkspaceID("w2")])
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w2"))
    }

    func testRemoveNonActiveWorkspaceKeepsActive() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        store.upsert(Workspace(id: WorkspaceID("w1"), name: "a", path: "/a", tabs: [], activeTab: nil))
        store.upsert(Workspace(id: WorkspaceID("w2"), name: "b", path: "/b", tabs: [], activeTab: nil))
        store.remove(WorkspaceID("w1"))   // active 是 w2
        XCTAssertEqual(store.workspaces.map(\.id), [WorkspaceID("w2")])
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w2"))
    }

    func testUpsertExistingPreservesActive() {
        var store = WorkspaceStore(workspaces: [], activeWorkspace: nil)
        store.upsert(Workspace(id: WorkspaceID("w1"), name: "a", path: "/a", tabs: [], activeTab: nil))
        store.upsert(Workspace(id: WorkspaceID("w2"), name: "b", path: "/b", tabs: [], activeTab: nil))
        // active 现在是 w2；更新已存在的 w1 不应改变 active
        let updated = Workspace(id: WorkspaceID("w1"), name: "renamed", path: "/a", tabs: [], activeTab: nil)
        store.upsert(updated)
        XCTAssertEqual(store.workspaces.count, 2)
        XCTAssertEqual(store.activeWorkspace, WorkspaceID("w2"))
    }
}
