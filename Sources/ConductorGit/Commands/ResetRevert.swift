import Foundation

/// reset 模式。移植自 SourceGit `Models.ResetMode`。
public enum GitResetMode: String, Sendable, CaseIterable {
    case soft
    case mixed
    case hard

    public var flag: String { "--\(self.rawValue)" }
}

/// `git reset`。移植自 SourceGit `Commands.Reset`。
public enum Reset {
    /// 把当前分支重置到某提交（soft 保留改动并暂存 / mixed 保留改动不暂存 / hard 丢弃）。
    public static func toCommit(_ repo: GitRepository, revision: String, mode: GitResetMode) async throws {
        _ = try await repo.git(["reset", mode.flag, revision]).run()
    }

    /// 把某文件在 index 里重置到某提交的版本（不动工作区）。
    public static func file(_ repo: GitRepository, path: String, to revision: String) async throws {
        _ = try await repo.git(["reset", revision, "--", path]).run()
    }
}

/// `git revert`。移植自 SourceGit `Commands.Revert`。
public enum Revert {
    /// 回滚某提交。`autoCommit` 为 false 时只改工作区不自动提交（--no-commit）。
    public static func commit(_ repo: GitRepository, _ sha: String, autoCommit: Bool = true) async throws {
        var args = ["revert", sha]
        if !autoCommit { args.append("--no-commit") }
        _ = try await repo.git(args).run()
    }
}
