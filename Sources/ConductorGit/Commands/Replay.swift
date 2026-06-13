import Foundation

/// `git cherry-pick`。移植自 SourceGit `Commands.CherryPick`。
public enum CherryPick {
    /// 把若干提交摘到当前分支。`noCommit` 只应用不提交；`appendSource` 在信息里追加来源(-x)。
    public static func run(
        _ repo: GitRepository,
        commits: [String],
        noCommit: Bool = false,
        appendSource: Bool = false) async throws
    {
        guard !commits.isEmpty else { return }
        var args = ["cherry-pick"]
        if noCommit { args.append("-n") }
        if appendSource { args.append("-x") }
        // 多个提交挑选时按父链顺序应用；保持调用方给的顺序。
        args += commits
        _ = try await repo.git(args).run()
    }
}

/// `git merge`。移植自 SourceGit `Commands.Merge`。
public enum Merge {
    /// 把某分支/提交合并进当前分支。
    public static func run(
        _ repo: GitRepository,
        source: String,
        edit: Bool = false,
        fastForward: GitMergeFastForward = .default) async throws
    {
        var args = ["merge", "--progress"]
        args.append(edit ? "--edit" : "--no-edit")
        if let flag = fastForward.flag { args.append(flag) }
        args.append(source)
        _ = try await repo.git(args).run()
    }
}

/// merge 的快进策略。
public enum GitMergeFastForward: Sendable {
    /// 默认（能快进就快进）。
    case `default`
    /// 总是建合并提交（--no-ff）。
    case noFastForward
    /// 仅当能快进时（--ff-only），否则失败。
    case ffOnly

    var flag: String? {
        switch self {
        case .default: nil
        case .noFastForward: "--no-ff"
        case .ffOnly: "--ff-only"
        }
    }
}

/// `git rebase`。移植自 SourceGit `Commands.Rebase`。
public enum Rebase {
    /// 把当前分支变基到 `basedOn`（分支名/提交/上游）。
    public static func onto(
        _ repo: GitRepository,
        basedOn: String,
        autoStash: Bool = true) async throws
    {
        var args = ["rebase"]
        if autoStash { args.append("--autostash") }
        args.append(basedOn)
        _ = try await repo.git(args).run()
    }

    /// 中止进行中的变基。
    public static func abort(_ repo: GitRepository) async throws {
        _ = try await repo.git(["rebase", "--abort"]).run()
    }

    /// 解决冲突后继续变基。
    public static func `continue`(_ repo: GitRepository) async throws {
        _ = try await repo.git(["rebase", "--continue"]).run()
    }
}
