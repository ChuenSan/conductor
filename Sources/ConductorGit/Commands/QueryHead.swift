import Foundation

/// 当前 HEAD 概况：分支名（或 detached 的短 SHA）与相对上游的领先/落后。
public struct GitHeadInfo: Sendable, Equatable {
    public var branch: String = ""
    public var isDetached: Bool = false
    public var upstream: String = ""
    public var ahead: Int = 0
    public var behind: Int = 0

    public init() {}
}

public enum QueryHead {
    public static func run(_ repo: GitRepository) async throws -> GitHeadInfo {
        var info = GitHeadInfo()

        // 当前分支名（detached 时为空）。
        let branch = try await repo.git(["branch", "--show-current"]).run(allowFailure: true)
        let name = branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            info.isDetached = true
            let short = try await repo.git(["rev-parse", "--short", "HEAD"]).run(allowFailure: true)
            info.branch = short.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            info.branch = name
        }

        // 上游 ref（无上游则命令失败，留空）。
        let upstream = try await repo.git(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}"]).run(allowFailure: true)
        if upstream.isSuccess {
            info.upstream = upstream.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            // left-right count：左=上游独有(落后)，右=HEAD独有(领先)。
            let counts = try await repo.git(
                ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"]).run(allowFailure: true)
            if counts.isSuccess {
                let (behind, ahead) = self.parseLeftRight(counts.stdout)
                info.behind = behind
                info.ahead = ahead
            }
        }

        return info
    }

    /// 解析 `rev-list --left-right --count` 的 "<left>\t<right>" 输出 → (left, right)。纯函数。
    static func parseLeftRight(_ stdout: String) -> (left: Int, right: Int) {
        let fields = stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard fields.count == 2, let left = Int(fields[0]), let right = Int(fields[1]) else {
            return (0, 0)
        }
        return (left, right)
    }
}
