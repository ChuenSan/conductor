import Foundation

/// `git fetch`。移植自 SourceGit `Commands.Fetch`。
///
/// 鉴权依赖系统凭据助手（HTTPS：osxkeychain）或 ssh-agent；缺凭据时因 `GIT_TERMINAL_PROMPT=0`
/// 会直接报错而非挂起（交互式 askpass 是后续工作）。
public enum Fetch {
    public static func remote(_ repo: GitRepository, _ remote: String, prune: Bool = false) async throws {
        var args = ["fetch", "--progress", "--verbose", "--tags"]
        if prune { args.append("--prune") }
        args.append(remote)
        _ = try await repo.git(args).run()
    }

    public static func all(_ repo: GitRepository, prune: Bool = false) async throws {
        var args = ["fetch", "--progress", "--verbose", "--all", "--tags"]
        if prune { args.append("--prune") }
        _ = try await repo.git(args).run()
    }
}

/// `git pull`。移植自 SourceGit `Commands.Pull`。
public enum Pull {
    public static func run(
        _ repo: GitRepository,
        remote: String,
        branch: String,
        rebase: Bool = false) async throws
    {
        var args = ["pull", "--verbose", "--progress"]
        if rebase { args.append("--rebase=true") }
        args += [remote, branch]
        _ = try await repo.git(args).run()
    }
}

/// `git push`。移植自 SourceGit `Commands.Push`。
public enum Push {
    /// 推送本地分支到远程。`setUpstream` 设置跟踪；`force` 用 --force-with-lease（更安全的强推）。
    public static func branch(
        _ repo: GitRepository,
        localBranch: String,
        remote: String,
        remoteBranch: String,
        setUpstream: Bool = false,
        force: Bool = false,
        withTags: Bool = false) async throws
    {
        var args = ["push", "--progress", "--verbose"]
        if withTags { args.append("--tags") }
        if setUpstream { args.append("-u") }
        if force { args.append("--force-with-lease") }
        args += [remote, "\(localBranch):\(remoteBranch)"]
        _ = try await repo.git(args).run()
    }

    /// 删除远程分支/tag。
    public static func delete(_ repo: GitRepository, remote: String, refname: String) async throws {
        _ = try await repo.git(["push", "--delete", remote, refname]).run()
    }
}
