import XCTest
@testable import CmuxCore

final class StateStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func sampleState() -> PersistedState {
        let ws = Workspace(id: WorkspaceID("w1"), name: "proj", path: "/tmp/proj",
                           tabs: [Tab.single(id: TabID("t1"), title: "zsh", pane: PaneID("p1"))],
                           activeTab: TabID("t1"))
        return PersistedState(store: WorkspaceStore(workspaces: [ws], activeWorkspace: WorkspaceID("w1")))
    }

    func testSaveThenLoadRoundTrips() throws {
        let url = dir.appendingPathComponent("state.json")
        let store = StateStore(fileURL: url)
        let state = sampleState()
        try store.save(state)

        let result = store.load()
        XCTAssertEqual(result.outcome, .loaded)
        XCTAssertEqual(result.state, state)
    }

    func testLoadMissingFileReturnsFresh() {
        let url = dir.appendingPathComponent("does-not-exist.json")
        let store = StateStore(fileURL: url)
        let result = store.load()
        XCTAssertEqual(result.outcome, .fresh)
        XCTAssertTrue(result.state.store.workspaces.isEmpty)
    }

    func testLoadCorruptFileRecoversAndBacksUp() throws {
        let url = dir.appendingPathComponent("state.json")
        try Data("not json {{{".utf8).write(to: url)
        let store = StateStore(fileURL: url)

        let result = store.load()
        XCTAssertEqual(result.outcome, .recovered)
        XCTAssertTrue(result.state.store.workspaces.isEmpty)

        // 坏文件应被备份（目录里出现一个 .corrupt-* 文件）
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.contains("corrupt") },
                      "expected a backup of the corrupt file, got \(files)")
    }

    func testLoadIncompatibleVersionRecovers() throws {
        let url = dir.appendingPathComponent("state.json")
        // 构造一个版本号远高于当前的合法 JSON
        let future = """
        {"version": 9999, "store": {"workspaces": [], "activeWorkspace": null}}
        """
        try Data(future.utf8).write(to: url)
        let store = StateStore(fileURL: url)

        let result = store.load()
        XCTAssertEqual(result.outcome, .recovered)
    }
}
