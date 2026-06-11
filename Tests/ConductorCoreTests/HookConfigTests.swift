import XCTest
@testable import ConductorCore

final class HookConfigTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-hookcfg-\(UUID().uuidString).json")
    }

    func testAddReadRemovePreservesOtherKeys() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        // 预置一个含敏感键 + 已有 hook 的配置
        let initial = """
        {"env":{"SECRET":"keep-me"},"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"existing","timeout":5}]}]}}
        """
        try initial.write(to: url, atomically: true, encoding: .utf8)

        let doc = HookConfigDocument(url: url, source: .claude)
        XCTAssertEqual(doc.entries().count, 1)

        try doc.addCommand(event: "Stop", command: "echo hi #conductor:test", timeout: 5000)
        let entries = doc.entries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { $0.command == "echo hi #conductor:test" && $0.managedByConductor })
        XCTAssertTrue(entries.contains { $0.command == "existing" && !$0.managedByConductor })

        // 敏感键保留
        let reloaded = doc.load()
        XCTAssertEqual((reloaded["env"] as? [String: Any])?["SECRET"] as? String, "keep-me")

        // 重复添加不增加
        try doc.addCommand(event: "Stop", command: "echo hi #conductor:test")
        XCTAssertEqual(doc.entries().count, 2)

        // 按哨兵移除，只移我们的
        let removed = try doc.removeCommands(containing: "#conductor:test")
        XCTAssertEqual(removed, 1)
        let after = doc.entries()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.command, "existing")
        XCTAssertEqual((doc.load()["env"] as? [String: Any])?["SECRET"] as? String, "keep-me")
    }

    func testAddToFreshFile() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = HookConfigDocument(url: url, source: .codex)
        try doc.addCommand(event: "Stop", command: "do-thing #conductor:x")
        XCTAssertEqual(doc.entries().count, 1)
        XCTAssertEqual(doc.entries().first?.event, "Stop")
    }
}
