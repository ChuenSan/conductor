import Foundation

/// 取某文件的差异来源。
public enum GitDiffSource: Sendable, Equatable {
    /// 工作区相对 index（未暂存改动）。
    case workTree
    /// index 相对 HEAD（已暂存改动）。
    case staged
    /// 未跟踪文件（整文件视为新增）。
    case untracked
}

/// `git diff` → `TextDiff`。移植自 SourceGit `Commands.Diff` 的文本路径。
public enum Diff {
    public static func file(
        _ repo: GitRepository,
        path: String,
        source: GitDiffSource) async throws -> TextDiff
    {
        let common = ["diff", "--no-color", "--no-ext-diff", "-M"]
        let args: [String]
        switch source {
        case .workTree:
            args = common + ["--", path]
        case .staged:
            args = common + ["--cached", "--", path]
        case .untracked:
            // 未跟踪文件不在 index 里，用 --no-index 和 /dev/null 比，整文件即新增。
            // 文件相同会退出 0、不同退出 1，都带输出，故 allowFailure。
            args = ["diff", "--no-color", "--no-ext-diff", "--no-index", "--", "/dev/null", path]
        }

        let result = try await repo.git(args).run(allowFailure: true)
        return TextDiff.parse(result.stdout)
    }

    /// 取某次提交相对其首个父提交的某文件差异（历史视图用）。
    public static func commitFile(
        _ repo: GitRepository,
        sha: String,
        path: String) async throws -> TextDiff
    {
        let args = ["diff", "--no-color", "--no-ext-diff", "-M", "\(sha)^!", "--", path]
        let result = try await repo.git(args).run(allowFailure: true)
        return TextDiff.parse(result.stdout)
    }
}
