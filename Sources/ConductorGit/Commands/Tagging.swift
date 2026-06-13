import Foundation

/// `git tag` 增删推。移植自 SourceGit `Commands.Tag`。
public enum Tag {
    /// 建轻量 tag。
    public static func createLightweight(
        _ repo: GitRepository,
        name: String,
        basedOn: String = "HEAD") async throws
    {
        _ = try await repo.git(["tag", "--no-sign", name, basedOn]).run()
    }

    /// 建带信息的附注 tag（-F 临时文件传信息）。
    public static func createAnnotated(
        _ repo: GitRepository,
        name: String,
        basedOn: String = "HEAD",
        message: String) async throws
    {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-tag-\(UUID().uuidString).txt")
        try message.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        _ = try await repo.git(["tag", "-a", "--no-sign", name, basedOn, "-F", tmp.path]).run()
    }

    public static func delete(_ repo: GitRepository, name: String) async throws {
        _ = try await repo.git(["tag", "--delete", name]).run()
    }

    public static func push(_ repo: GitRepository, name: String, remote: String) async throws {
        _ = try await repo.git(["push", remote, "refs/tags/\(name)"]).run()
    }
}

/// `git for-each-ref refs/tags` → `[GitTag]`。
public enum QueryTags {
    static let format = "%(refname:short)%00%(objectname)%00%(*objectname)%00%(creatordate:unix)%00%(contents:subject)"

    public static func run(_ repo: GitRepository) async throws -> [GitTag] {
        let args = ["for-each-ref", "--sort=-creatordate", "--format=\(self.format)", "refs/tags"]
        let result = try await repo.git(args).run(allowFailure: true)
        guard result.isSuccess else { return [] }
        return self.parse(result.stdout)
    }

    /// 解析 for-each-ref 输出。annotated tag 用解引用后的提交 SHA。纯函数。
    public static func parse(_ stdout: String) -> [GitTag] {
        var tags: [GitTag] = []
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.components(separatedBy: "\u{0}")
            guard parts.count == 5 else { continue }
            // 附注 tag：第三列 *objectname 是其指向的提交；轻量 tag 该列为空，用 objectname。
            let sha = parts[2].isEmpty ? parts[1] : parts[2]
            tags.append(GitTag(
                name: parts[0],
                sha: sha,
                time: Int(parts[3]) ?? 0,
                message: parts[4]))
        }
        return tags
    }
}
