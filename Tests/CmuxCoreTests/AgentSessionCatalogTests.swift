import XCTest
@testable import CmuxCore

final class AgentSessionCatalogTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-catalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testTrimTitleCollapsesWhitespaceAndTruncates() {
        let long = String(repeating: "a", count: 90)
        XCTAssertEqual(AgentSessionCatalog.trimTitle("  hello\nworld  "), "hello world")
        XCTAssertTrue(AgentSessionCatalog.trimTitle(long).hasSuffix("…"))
    }

    func testReadClaudeMetaExtractsTitleAndCwd() throws {
        let dir = tempDir.appendingPathComponent("-tmp-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sess-1.jsonl")
        let lines = """
        {"type":"queue-operation","operation":"enqueue","content":"修复滚动条"}
        {"cwd":"/tmp/proj","type":"attachment"}
        """
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let meta = AgentSessionCatalog.readClaudeMeta(file)
        XCTAssertEqual(meta.title, "修复滚动条")
        XCTAssertEqual(meta.cwd, "/tmp/proj")
    }

    func testReadCodexMetaExtractsFields() throws {
        let day = tempDir.appendingPathComponent("2026/06/10", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout.jsonl")
        let lines = """
        {"type":"session_meta","payload":{"id":"abc-123","cwd":"/tmp/proj"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"继续实现"}}
        """
        try lines.write(to: file, atomically: true, encoding: .utf8)

        let meta = AgentSessionCatalog.readCodexMeta(file)
        XCTAssertEqual(meta?.id, "abc-123")
        XCTAssertEqual(meta?.cwd, "/tmp/proj")
        XCTAssertEqual(meta?.title, "继续实现")
    }

    func testScanClaudeReturnsRecords() throws {
        let root = tempDir.appendingPathComponent("claude", isDirectory: true)
        let dir = root.appendingPathComponent("-tmp-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sess-a.jsonl")
        try "{\"type\":\"queue-operation\",\"operation\":\"enqueue\",\"content\":\"hi\"}\n"
            .write(to: file, atomically: true, encoding: .utf8)

        let records = AgentSessionCatalog.scanClaude(limit: 10, projectsRoot: root)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].agent, "claude")
        XCTAssertEqual(records[0].sessionID, "sess-a")
        XCTAssertEqual(records[0].title, "hi")
    }

    func testBelongsToWorkspaceAndDirectory() {
        let record = AgentSessionRecord(
            agent: "codex", sessionID: "x", cwd: "/tmp/proj/src",
            title: "t", modifiedAt: Date())
        XCTAssertTrue(record.belongsToWorkspace("/tmp/proj"))
        XCTAssertTrue(record.belongsToDirectory("/tmp/proj/src"))
        XCTAssertFalse(record.belongsToDirectory("/elsewhere"))
    }

    func testUtilityCommandTitleDetection() {
        XCTAssertTrue(AgentSessionCatalog.isUtilityCommandTitle("/usage"))
        XCTAssertTrue(AgentSessionCatalog.isUtilityCommandTitle("  /status  "))
        XCTAssertTrue(AgentSessionCatalog.isUtilityCommandTitle(
            "<command-name>/usage</command-name> <command-message>usage</command-message> <command-args></command-args>"))
        XCTAssertFalse(AgentSessionCatalog.isUtilityCommandTitle("/review 这个 PR"))
        XCTAssertFalse(AgentSessionCatalog.isUtilityCommandTitle(
            "<command-name>/review</command-name> <command-args>fix bug</command-args>"))
        XCTAssertFalse(AgentSessionCatalog.isUtilityCommandTitle("修复滚动条"))
        XCTAssertFalse(AgentSessionCatalog.isUtilityCommandTitle("/"))
    }

    func testScanClaudeSkipsUtilityCommandSessions() throws {
        let root = tempDir.appendingPathComponent("claude", isDirectory: true)
        let dir = root.appendingPathComponent("-tmp-proj", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{\"type\":\"user\",\"message\":{\"content\":\"/usage\"},\"cwd\":\"/tmp/proj\"}\n"
            .write(to: dir.appendingPathComponent("usage-1.jsonl"), atomically: true, encoding: .utf8)
        try "{\"type\":\"user\",\"message\":{\"content\":\"真实对话\"},\"cwd\":\"/tmp/proj\"}\n"
            .write(to: dir.appendingPathComponent("real-1.jsonl"), atomically: true, encoding: .utf8)

        let records = AgentSessionCatalog.scanClaude(limit: 10, projectsRoot: root)
        XCTAssertEqual(records.map(\.sessionID), ["real-1"])
    }

    func testInferCwdFromSlug() {
        XCTAssertEqual(
            AgentSessionCatalog.inferCwdFromSlug("-Users-me-Desktop-c"),
            "/Users/me/Desktop/c")
    }
}
