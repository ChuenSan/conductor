import Foundation

/// `git log` → `[GitCommit]`。移植自 SourceGit `Commands.QueryCommits`。
public enum QueryCommits {
    /// 各字段用 NUL（`%x00`）分隔，避免和内容里的字符冲突。8 个字段：
    /// SHA / 父 / 装饰 / 作者(name±email) / 作者时间 / 提交者(name±email) / 提交时间 / 标题。
    static let format = "%H%x00%P%x00%D%x00%aN±%aE%x00%at%x00%cN±%cE%x00%ct%x00%s"

    /// 查询提交历史。`maxCount` 限制条数；`extra` 可追加 ref/路径等参数。
    public static func run(
        _ repo: GitRepository,
        maxCount: Int = 1000,
        extra: [String] = []) async throws -> [GitCommit]
    {
        var args = [
            "log", "--no-show-signature", "--decorate=full",
            "--format=\(self.format)", "-\(maxCount)",
        ]
        args += extra
        let result = try await repo.git(args).run(allowFailure: true)
        guard result.isSuccess else { return [] }
        return self.parse(result.stdout)
    }

    /// 解析 log 输出。每行一条提交，8 个 NUL 分隔字段。纯函数，便于单测。
    public static func parse(_ stdout: String) -> [GitCommit] {
        var commits: [GitCommit] = []
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.components(separatedBy: "\u{0}")
            guard parts.count == 8 else { continue }

            var commit = GitCommit()
            commit.sha = parts[0]
            commit.parseParents(parts[1])
            commit.parseDecorators(parts[2])
            commit.author = GitUser.parse(parts[3])
            commit.authorTime = Int(parts[4]) ?? 0
            commit.committer = GitUser.parse(parts[5])
            commit.committerTime = Int(parts[6]) ?? 0
            commit.subject = parts[7]
            commits.append(commit)
        }
        return commits
    }
}
