import Foundation

/// 暂存：`git add`。移植自 SourceGit `Commands.Add`。
public enum Stage {
    /// 暂存指定路径。
    public static func paths(_ repo: GitRepository, _ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = try await repo.git(["add", "--"] + paths).run()
    }

    /// 暂存全部改动（含未跟踪与删除）。
    public static func all(_ repo: GitRepository) async throws {
        _ = try await repo.git(["add", "-A"]).run()
    }
}

/// 取消暂存：把 index 里的条目还原成 HEAD（或初始提交前直接移出 index）。
public enum Unstage {
    public static func paths(_ repo: GitRepository, _ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        if await Self.hasCommits(repo) {
            // 有 HEAD：restore --staged 把 index 还原到 HEAD。
            _ = try await repo.git(["restore", "--staged", "--"] + paths).run()
        } else {
            // 初始提交前无 HEAD：从 index 移除（保留工作区文件）。
            _ = try await repo.git(["rm", "--cached", "-r", "--"] + paths).run(allowFailure: true)
        }
    }

    public static func all(_ repo: GitRepository) async throws {
        if await Self.hasCommits(repo) {
            _ = try await repo.git(["reset", "-q", "HEAD", "--"]).run(allowFailure: true)
        } else {
            _ = try await repo.git(["rm", "--cached", "-r", "-q", "."]).run(allowFailure: true)
        }
    }

    static func hasCommits(_ repo: GitRepository) async -> Bool {
        let r = try? await repo.git(["rev-parse", "--verify", "HEAD"]).run(allowFailure: true)
        return r?.isSuccess ?? false
    }
}

/// 丢弃工作区改动。已跟踪文件还原到 index/HEAD，未跟踪文件直接删除。
/// 移植自 SourceGit `Commands.Discard`。
public enum Discard {
    /// 丢弃指定变更（按是否未跟踪分别处理）。
    public static func changes(_ repo: GitRepository, _ changes: [GitChange]) async throws {
        let untracked = changes.filter { $0.workTree == .untracked }.map(\.path)
        let tracked = changes.filter { $0.workTree != .untracked }.map(\.path)

        if !tracked.isEmpty {
            // 还原工作区到 index（保留已暂存内容）。
            _ = try await repo.git(["checkout", "--"] + tracked).run()
        }
        if !untracked.isEmpty {
            _ = try await repo.git(["clean", "-fd", "--"] + untracked).run(allowFailure: true)
        }
    }

    /// 丢弃全部工作区改动（含未跟踪）。
    public static func all(_ repo: GitRepository) async throws {
        _ = try await repo.git(["checkout", "--", "."]).run(allowFailure: true)
        _ = try await repo.git(["clean", "-fd"]).run(allowFailure: true)
    }
}
