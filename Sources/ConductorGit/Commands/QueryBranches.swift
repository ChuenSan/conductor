import Foundation

/// `git branch -l --all --format=...` → `[GitBranch]`。移植自 SourceGit `Commands.QueryBranches`。
public enum QueryBranches {
    /// 7 个 NUL 分隔字段：refname / 提交时间 / objectname / HEAD标记 / upstream / trackshort / worktreepath。
    static let format =
        "%(refname)%00%(committerdate:unix)%00%(objectname)%00%(HEAD)%00%(upstream)%00%(upstream:trackshort)%00%(worktreepath)"

    public static func run(_ repo: GitRepository) async throws -> [GitBranch] {
        let args = ["branch", "-l", "--all", "--format=\(self.format)"]
        let result = try await repo.git(args).run(allowFailure: true)
        guard result.isSuccess else { return [] }
        var branches = self.parse(result.stdout)

        // 标记上游已消失的本地分支（upstream 指向的远程分支不在列表里）。
        let remoteFullNames = Set(branches.filter { !$0.isLocal }.map(\.fullName))
        for idx in branches.indices where branches[idx].isLocal && !branches[idx].upstream.isEmpty {
            branches[idx].isUpstreamGone = !remoteFullNames.contains(branches[idx].upstream)
        }
        return branches
    }

    /// 解析 for-each-ref 风格输出。纯函数，便于单测。
    public static func parse(_ stdout: String) -> [GitBranch] {
        var branches: [GitBranch] = []
        for rawLine in stdout.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            if let branch = self.parseLine(String(rawLine)) {
                branches.append(branch)
            }
        }
        return branches
    }

    static func parseLine(_ line: String) -> GitBranch? {
        let parts = line.components(separatedBy: "\u{0}")
        guard parts.count == 7 else { return nil }

        let refName = parts[0]
        if refName.hasSuffix("/HEAD") { return nil }

        var branch = GitBranch()
        branch.isDetachedHead =
            refName.hasPrefix("(HEAD detached at") || refName.hasPrefix("(HEAD detached from")

        if refName.hasPrefix("refs/heads/") {
            branch.name = String(refName.dropFirst("refs/heads/".count))
            branch.isLocal = true
        } else if refName.hasPrefix("refs/remotes/") {
            let name = String(refName.dropFirst("refs/remotes/".count))
            let nameParts = name.split(separator: "/", maxSplits: 1).map(String.init)
            guard nameParts.count == 2 else { return nil }
            branch.remote = nameParts[0]
            branch.name = nameParts[1]
            branch.isLocal = false
        } else {
            branch.name = refName
            branch.isLocal = true
        }

        branch.fullName = refName
        branch.committerDate = Int(parts[1]) ?? 0
        branch.head = parts[2]
        branch.isCurrent = parts[3] == "*"
        branch.upstream = parts[4]
        branch.worktreePath = parts[6]
        return branch
    }
}
