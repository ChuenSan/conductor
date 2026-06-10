import XCTest
@testable import CmuxCore

final class AgentSessionPreviewTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, _ content: String) throws -> String {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    func testClaudePreviewExtractsUserAndAssistant() throws {
        let lines = """
        {"type":"user","message":{"role":"user","content":"帮我修个 bug"}}
        {"type":"assistant","message":{"content":[{"type":"thinking","thinking":"hmm"},{"type":"text","text":"好的，我看一下"}]}}
        {"type":"assistant","message":{"content":[{"type":"text","text":"已修复"}]}}
        {"type":"user","message":{"content":"<command-name>/clear</command-name>"}}
        """
        let path = try write("claude.jsonl", lines)

        let messages = AgentSessionPreview.load(agent: "claude", filePath: path)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].text, "帮我修个 bug")
        XCTAssertEqual(messages[1].role, .assistant)
        // 连续 assistant 合并
        XCTAssertEqual(messages[1].text, "好的，我看一下 已修复")
    }

    func testClaudeSkipsSidechainAndToolResults() throws {
        let lines = """
        {"type":"user","isSidechain":true,"message":{"content":"内部子任务"}}
        {"type":"user","message":{"content":[{"type":"tool_result","content":"raw"}]}}
        {"type":"user","message":{"content":"真正的问题"}}
        """
        let path = try write("claude2.jsonl", lines)

        let messages = AgentSessionPreview.load(agent: "claude", filePath: path)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].text, "真正的问题")
    }

    func testCodexPreviewExtractsEventMessages() throws {
        let lines = """
        {"type":"session_meta","payload":{"id":"x","cwd":"/tmp"}}
        {"type":"event_msg","payload":{"type":"user_message","message":"继续实现"}}
        {"type":"event_msg","payload":{"type":"agent_message","message":"收到，开始干活"}}
        {"type":"response_item","payload":{"type":"message","role":"developer","content":[]}}
        """
        let path = try write("codex.jsonl", lines)

        let messages = AgentSessionPreview.load(agent: "codex", filePath: path)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].text, "继续实现")
        XCTAssertEqual(messages[1].role, .assistant)
    }

    func testLimitKeepsLatestMessages() throws {
        var lines: [String] = []
        for n in 1...10 {
            lines.append(#"{"type":"event_msg","payload":{"type":"user_message","message":"问题\#(n)"}}"#)
            lines.append(#"{"type":"event_msg","payload":{"type":"agent_message","message":"回答\#(n)"}}"#)
        }
        let path = try write("codex-long.jsonl", lines.joined(separator: "\n"))

        let messages = AgentSessionPreview.load(agent: "codex", filePath: path, limit: 4)
        XCTAssertEqual(messages.count, 4)
        XCTAssertEqual(messages.last?.text, "回答10")
        XCTAssertEqual(messages.first?.text, "问题9")
    }

    func testLongMessageTruncated() throws {
        let long = String(repeating: "长", count: 500)
        let line = #"{"type":"event_msg","payload":{"type":"user_message","message":"\#(long)"}}"#
        let path = try write("codex-trunc.jsonl", line)

        let messages = AgentSessionPreview.load(agent: "codex", filePath: path)
        XCTAssertEqual(messages.count, 1)
        XCTAssertLessThanOrEqual(messages[0].text.count, AgentSessionPreview.maxMessageChars)
        XCTAssertTrue(messages[0].text.hasSuffix("…"))
    }

    func testMissingFileReturnsEmpty() {
        XCTAssertTrue(AgentSessionPreview.load(agent: "claude", filePath: "/no/such/file").isEmpty)
    }

    func testLoadFullReturnsAllMessagesWithoutTruncation() throws {
        var lines: [String] = []
        for n in 1...25 {
            lines.append(#"{"type":"event_msg","payload":{"type":"user_message","message":"问题\#(n)"}}"#)
            lines.append(#"{"type":"event_msg","payload":{"type":"agent_message","message":"回答\#(n)"}}"#)
        }
        let path = try write("codex-full.jsonl", lines.joined(separator: "\n"))

        let messages = AgentSessionPreview.loadFull(agent: "codex", filePath: path)
        XCTAssertEqual(messages.count, 50)
        XCTAssertEqual(messages.first?.text, "问题1")
        XCTAssertEqual(messages.last?.text, "回答25")
        XCTAssertFalse(messages[0].text.hasSuffix("…"))
    }
}
