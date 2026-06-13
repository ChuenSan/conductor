import Foundation
@testable import ConductorGit

/// 测试用的一次性临时 git 仓库。`init()` 里 `git init` 并配好 user，便于提交。
/// `deinit` 删目录。所有命令同步跑（测试里方便）。
final class TempGitRepo {
    let url: URL
    var path: String { self.url.path }

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-git-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base

        try self.git(["init", "-b", "main"])
        try self.git(["config", "user.email", "test@conductor.local"])
        try self.git(["config", "user.name", "Conductor Test"])
        try self.git(["config", "commit.gpgsign", "false"])
    }

    deinit {
        try? FileManager.default.removeItem(at: self.url)
    }

    /// 同步跑一条 git 命令（测试辅助），非 0 退出码抛错。
    @discardableResult
    func git(_ args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: GitExecutable.resolve() ?? "/usr/bin/git")
        proc.arguments = args
        proc.currentDirectoryURL = self.url
        proc.environment = GitExecutable.environment()
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(domain: "TempGitRepo", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: String(decoding: errData, as: UTF8.self),
            ])
        }
        return String(decoding: outData, as: UTF8.self)
    }

    /// 写文件（相对仓库根）。
    func write(_ relativePath: String, _ contents: String) throws {
        let fileURL = self.url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// 暂存全部并提交，返回 commit SHA。
    @discardableResult
    func commitAll(_ message: String) throws -> String {
        try self.git(["add", "-A"])
        try self.git(["commit", "-m", message])
        return try self.git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
