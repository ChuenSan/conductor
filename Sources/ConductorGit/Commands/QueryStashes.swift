import Foundation

/// `git stash list` → `[GitStash]`。
public enum QueryStashes {
    /// 4 个 NUL 分隔字段：refname(stash@{n}) / SHA / 提交时间 / 描述。
    static let format = "%gd%x00%H%x00%ct%x00%gs"

    public static func run(_ repo: GitRepository) async throws -> [GitStash] {
        let result = try await repo.git(["stash", "list", "--format=\(self.format)"]).run(allowFailure: true)
        guard result.isSuccess else { return [] }
        return self.parse(result.stdout)
    }

    /// 解析 stash list 输出。纯函数。
    public static func parse(_ stdout: String) -> [GitStash] {
        var stashes: [GitStash] = []
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.components(separatedBy: "\u{0}")
            guard parts.count == 4 else { continue }
            stashes.append(GitStash(
                name: parts[0],
                sha: parts[1],
                time: Int(parts[2]) ?? 0,
                message: parts[3]))
        }
        return stashes
    }
}
