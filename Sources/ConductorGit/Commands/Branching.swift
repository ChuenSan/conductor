import Foundation

/// 切换分支/提交。移植自 SourceGit `Commands.Checkout`。
public enum Checkout {
    /// 检出已有分支。
    public static func branch(_ repo: GitRepository, _ name: String) async throws {
        _ = try await repo.git(["checkout", name]).run()
    }

    /// 新建并检出分支（可指定基点）。
    public static func newBranch(
        _ repo: GitRepository,
        name: String,
        basedOn: String? = nil) async throws
    {
        var args = ["checkout", "-b", name]
        if let basedOn, !basedOn.isEmpty { args.append(basedOn) }
        _ = try await repo.git(args).run()
    }

    /// 检出某个提交（进入 detached HEAD）。
    public static func commit(_ repo: GitRepository, _ sha: String) async throws {
        _ = try await repo.git(["checkout", sha]).run()
    }

    /// 把远程分支检出为同名本地分支并跟踪。
    public static func remoteBranchAsLocal(
        _ repo: GitRepository,
        remoteBranch: GitBranch) async throws
    {
        _ = try await repo.git(["checkout", "-b", remoteBranch.name, "--track", remoteBranch.fullName.replacingOccurrences(of: "refs/remotes/", with: "")]).run()
    }
}

/// 分支增删。移植自 SourceGit `Commands.Branch`。
public enum Branch {
    /// 创建分支（不切换）。
    public static func create(
        _ repo: GitRepository,
        name: String,
        basedOn: String? = nil) async throws
    {
        var args = ["branch", name]
        if let basedOn, !basedOn.isEmpty { args.append(basedOn) }
        _ = try await repo.git(args).run()
    }

    /// 删除本地分支。`force` 用 `-D`（未合并也删）。
    public static func delete(_ repo: GitRepository, name: String, force: Bool = false) async throws {
        _ = try await repo.git(["branch", force ? "-D" : "-d", name]).run()
    }

    /// 重命名分支。
    public static func rename(_ repo: GitRepository, from: String, to: String) async throws {
        _ = try await repo.git(["branch", "-m", from, to]).run()
    }

    /// 设置/更改上游跟踪分支。`upstream` 形如 `origin/main`。
    public static func setUpstream(_ repo: GitRepository, name: String, upstream: String) async throws {
        _ = try await repo.git(["branch", "--set-upstream-to=\(upstream)", name]).run()
    }

    /// 取消上游跟踪。
    public static func unsetUpstream(_ repo: GitRepository, name: String) async throws {
        _ = try await repo.git(["branch", "--unset-upstream", name]).run()
    }
}
