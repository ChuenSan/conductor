import Foundation

/// 提交。移植自 SourceGit `Commands.Commit`：把提交信息写临时文件再 `--file=` 传入，
/// 避免命令行里处理多行/引号/特殊字符。
public enum Commit {
    public static func run(
        _ repo: GitRepository,
        message: String,
        amend: Bool = false,
        resetAuthor: Bool = false,
        signOff: Bool = false,
        noVerify: Bool = false) async throws
    {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-commit-\(UUID().uuidString).txt")
        try message.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var args = ["commit", "--file=\(tmp.path)"]
        if signOff { args.append("--signoff") }
        if noVerify { args.append("--no-verify") }
        if amend {
            args.append("--amend")
            if resetAuthor { args.append("--reset-author") }
        }

        _ = try await repo.git(args).run()
    }
}
