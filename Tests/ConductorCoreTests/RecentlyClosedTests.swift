import XCTest
@testable import ConductorCore

final class RecentlyClosedTests: XCTestCase {
    private func paneRecord(_ n: Int) -> ClosedRecord {
        .pane(workspaceID: WorkspaceID("w1"), tabID: TabID("t1"),
              pane: PaneID("p\(n)"), cwd: "/tmp/\(n)", axis: .vertical, session: nil)
    }

    func testPopReturnsLastPushedFirst() {
        var stack = RecentlyClosedStack()
        stack.push(paneRecord(1))
        stack.push(paneRecord(2))
        XCTAssertEqual(stack.pop(), paneRecord(2))
        XCTAssertEqual(stack.pop(), paneRecord(1))
        XCTAssertNil(stack.pop())
        XCTAssertTrue(stack.isEmpty)
    }

    func testCapacityDropsOldestRecords() {
        var stack = RecentlyClosedStack(capacity: 3)
        for n in 1...5 { stack.push(paneRecord(n)) }
        XCTAssertEqual(stack.count, 3)
        XCTAssertEqual(stack.pop(), paneRecord(5))
        XCTAssertEqual(stack.pop(), paneRecord(4))
        XCTAssertEqual(stack.pop(), paneRecord(3))   // 1、2 已被挤掉
        XCTAssertNil(stack.pop())
    }

    func testTabRecordKeepsTreeAndCwds() {
        let tab = Tab(
            id: TabID("t1"), title: "zsh",
            rootSplit: .split(
                id: SplitID("s1"), axis: .horizontal, ratio: 0.5,
                first: .leaf(PaneID("p1")), second: .leaf(PaneID("p2"))),
            activePane: PaneID("p2"))
        var stack = RecentlyClosedStack()
        let session = AgentSessionRef(agent: "claude", sessionID: "abc-123")
        stack.push(.tab(workspaceID: WorkspaceID("w1"), tab: tab,
                        paneCwds: ["p1": "/a"], paneSessions: ["p1": session]))
        guard case let .tab(wsID, restored, cwds, sessions)? = stack.pop() else {
            return XCTFail("应为 tab 记录")
        }
        XCTAssertEqual(wsID, WorkspaceID("w1"))
        XCTAssertEqual(restored, tab)
        XCTAssertEqual(cwds, ["p1": "/a"])
        XCTAssertEqual(sessions, ["p1": session])
    }

    func testPaneRecordKeepsSession() {
        var stack = RecentlyClosedStack()
        let session = AgentSessionRef(agent: "codex", sessionID: "xyz")
        stack.push(.pane(workspaceID: WorkspaceID("w1"), tabID: TabID("t1"),
                         pane: PaneID("p1"), cwd: "/a", axis: .horizontal, session: session))
        guard case let .pane(_, _, _, _, _, restored)? = stack.pop() else {
            return XCTFail("应为 pane 记录")
        }
        XCTAssertEqual(restored, session)
    }
}
