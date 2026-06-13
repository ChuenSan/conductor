import Foundation

/// stash 操作。移植自 SourceGit `Commands.Stash`。
public enum Stash {
    /// 暂存当前改动。`includeUntracked` 连未跟踪文件一起 stash。
    public static func push(
        _ repo: GitRepository,
        message: String? = nil,
        includeUntracked: Bool = false) async throws
    {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message, !message.isEmpty {
            args.append("-m")
            args.append(message)
        }
        _ = try await repo.git(args).run()
    }

    /// 应用并移除某条 stash（默认最近一条）。
    public static func pop(_ repo: GitRepository, _ name: String? = nil) async throws {
        var args = ["stash", "pop"]
        if let name, !name.isEmpty { args.append(name) }
        _ = try await repo.git(args).run()
    }

    /// 应用但保留某条 stash。
    public static func apply(_ repo: GitRepository, _ name: String? = nil) async throws {
        var args = ["stash", "apply"]
        if let name, !name.isEmpty { args.append(name) }
        _ = try await repo.git(args).run()
    }

    /// 删除某条 stash。
    public static func drop(_ repo: GitRepository, _ name: String) async throws {
        _ = try await repo.git(["stash", "drop", name]).run()
    }

    /// 清空全部 stash。
    public static func clear(_ repo: GitRepository) async throws {
        _ = try await repo.git(["stash", "clear"]).run()
    }

    /// 基于某条 stash 新建分支并应用（git stash branch）。
    public static func toBranch(_ repo: GitRepository, name: String, branch: String) async throws {
        _ = try await repo.git(["stash", "branch", branch, name]).run()
    }
}
