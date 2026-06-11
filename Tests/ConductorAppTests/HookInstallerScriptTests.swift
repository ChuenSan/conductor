import XCTest
@testable import ConductorApp

/// 验证生成的 conductor-notify 脚本：跑一遍能写出可被 conductor 解析的合法 JSON，且带上 CONDUCTOR_PANE_ID。
final class HookInstallerScriptTests: XCTestCase {
    func testGeneratedScriptEmitsValidJSON() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("conductor-hook-test-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // 写脚本
        let scriptURL = tmp.appendingPathComponent("conductor-notify")
        try HookInstaller.scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // 用一个隔离的 HOME 跑脚本（脚本写到 $HOME/Library/Application Support/conductor/hooks-inbox）
        let fakeHome = tmp.appendingPathComponent("home")
        try fm.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptURL.path]
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = fakeHome.path
        env["CONDUCTOR_PANE_ID"] = "p-test-123"
        process.environment = env
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        // 检查收件箱里生成了合法 JSON
        let inbox = fakeHome
            .appendingPathComponent("Library/Application Support/conductor/hooks-inbox")
        let files = try fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1, "应恰好生成一个 JSON 文件")

        let data = try Data(contentsOf: files[0])
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["paneId"] as? String, "p-test-123")
        XCTAssertFalse((obj?["title"] as? String ?? "").isEmpty)
    }
}
