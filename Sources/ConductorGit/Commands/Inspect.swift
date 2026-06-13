import Foundation

/// `git blame --line-porcelain` → `GitBlame`。移植自 SourceGit `Commands.Blame`。
public enum Blame {
    public static func run(
        _ repo: GitRepository,
        path: String,
        revision: String = "HEAD") async throws -> GitBlame
    {
        let result = try await repo.git(
            ["blame", "--line-porcelain", revision, "--", path]).run(allowFailure: true)
        guard result.isSuccess else { return GitBlame() }
        if result.stdout.contains("\u{0}") {
            var b = GitBlame()
            b.isBinary = true
            return b
        }
        return self.parse(result.stdout)
    }

    /// 解析 line-porcelain：每块以 40 位 sha 行起头，含 author/author-time 元数据，
    /// 以 TAB 开头的内容行收尾。纯函数。
    public static func parse(_ stdout: String) -> GitBlame {
        var blame = GitBlame()
        var sha = ""
        var author = ""
        var time = 0
        var lineNo = 0
        // 同一提交后续行不再重复元数据，按 sha 记忆作者/时间。
        var authorBySHA: [String: String] = [:]
        var timeBySHA: [String: Int] = [:]

        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if let first = line.first, first.isHexDigit, line.count >= 40 {
                let head = line.split(separator: " ")
                if let candidate = head.first, candidate.count == 40,
                   candidate.allSatisfy(\.isHexDigit)
                {
                    sha = String(candidate)
                    author = authorBySHA[sha] ?? ""
                    time = timeBySHA[sha] ?? 0
                    continue
                }
            }
            if line.hasPrefix("author ") {
                author = String(line.dropFirst("author ".count))
                authorBySHA[sha] = author
            } else if line.hasPrefix("author-time ") {
                time = Int(line.dropFirst("author-time ".count)) ?? 0
                timeBySHA[sha] = time
            } else if line.hasPrefix("\t") {
                lineNo += 1
                blame.lines.append(GitBlameLine(
                    lineNumber: lineNo, sha: sha, author: author, time: time,
                    content: String(line.dropFirst())))
            }
        }
        return blame
    }
}

/// 单文件提交历史。复用 QueryCommits 限定路径。
public enum FileHistory {
    public static func run(_ repo: GitRepository, path: String, maxCount: Int = 200) async throws -> [GitCommit] {
        try await QueryCommits.run(repo, maxCount: maxCount, extra: ["--", path])
    }
}

/// `git update-index --assume-unchanged`。移植自 SourceGit `Commands.AssumeUnchanged`。
public enum AssumeUnchanged {
    public static func set(_ repo: GitRepository, path: String, assume: Bool) async throws {
        let flag = assume ? "--assume-unchanged" : "--no-assume-unchanged"
        _ = try await repo.git(["update-index", flag, "--", path]).run()
    }
}

/// 存为补丁。移植自 SourceGit `Commands.SaveChangesAsPatch` / `FormatPatch`。
public enum Patch {
    /// 把工作区/暂存区某些文件的改动存成 .patch 文件。
    public static func saveLocalChanges(
        _ repo: GitRepository,
        paths: [String],
        staged: Bool,
        to file: String) async throws
    {
        var args = ["diff", "--no-color", "--no-ext-diff"]
        if staged { args.append("--cached") }
        args.append("--")
        args += paths
        let result = try await repo.git(args).run()
        try result.stdout.write(toFile: file, atomically: true, encoding: .utf8)
    }

    /// 把某次提交存成 .patch 文件（format-patch 单提交）。
    public static func saveCommit(_ repo: GitRepository, sha: String, to file: String) async throws {
        let result = try await repo.git(["format-patch", "-1", "--stdout", sha]).run()
        try result.stdout.write(toFile: file, atomically: true, encoding: .utf8)
    }
}

/// 往仓库根的 .gitignore 追加规则。移植自 SourceGit `Models.GitIgnoreFile`。
public enum GitIgnore {
    public static func append(_ repo: GitRepository, pattern: String) throws {
        let url = URL(fileURLWithPath: repo.path).appendingPathComponent(".gitignore")
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
        existing += pattern + "\n"
        try existing.write(to: url, atomically: true, encoding: .utf8)
    }
}
