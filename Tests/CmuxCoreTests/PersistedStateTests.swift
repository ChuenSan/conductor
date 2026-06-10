import XCTest
@testable import CmuxCore

final class PersistedStateTests: XCTestCase {
    private func sampleStore() -> WorkspaceStore {
        let tab = Tab(
            id: TabID("t1"), title: "zsh",
            rootSplit: .split(
                id: SplitID("s1"), axis: .vertical, ratio: 0.6,
                first: .leaf(PaneID("p1")),
                second: .leaf(PaneID("p2"))
            ),
            activePane: PaneID("p1")
        )
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [tab], activeTab: TabID("t1"))
        return WorkspaceStore(workspaces: [ws], activeWorkspace: WorkspaceID("w1"))
    }

    func testDefaultVersionIsCurrent() {
        let state = PersistedState(store: sampleStore())
        XCTAssertEqual(state.version, PersistedState.currentVersion)
    }

    func testRoundTripPreservesFullTree() throws {
        let original = PersistedState(
            store: sampleStore(),
            paneCwds: ["p1": "/tmp/proj/src", "p2": "/tmp/proj"],
            paneSessions: ["p1": AgentSessionRef(agent: "claude", sessionID: "abc-123")])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// v1 文件没有 paneCwds / paneSessions 字段：必须正常解码（按空处理），不能进坏文件恢复流程。
    func testDecodingV1FileWithoutPaneCwds() throws {
        let v1 = PersistedState(version: 1, store: sampleStore())
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(v1)) as! [String: Any]
        json.removeValue(forKey: "paneCwds")
        json.removeValue(forKey: "paneSessions")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.store, v1.store)
        XCTAssertTrue(decoded.paneCwds.isEmpty)
        XCTAssertTrue(decoded.paneSessions.isEmpty)
    }
}
