import Foundation

/// `git status --porcelain` → `[GitChange]`。移植自 SourceGit `Commands.QueryLocalChanges`。
public enum QueryLocalChanges {
    /// 查询工作区本地变更（默认包含未跟踪文件）。
    public static func run(_ repo: GitRepository, includeUntracked: Bool = true) async throws -> [GitChange] {
        var args = ["--no-optional-locks"]
        if includeUntracked {
            args += [
                "-c", "core.untrackedCache=true",
                "-c", "status.showUntrackedFiles=all",
                "status", "-uall", "--ignore-submodules=dirty", "--porcelain",
            ]
        } else {
            args += ["status", "-uno", "--ignore-submodules=dirty", "--porcelain"]
        }
        let result = try await repo.git(args).run(allowFailure: true)
        guard result.isSuccess else { return [] }
        return self.parse(result.stdout)
    }

    /// 解析 porcelain v1 输出。每行形如 `XY <path>`（重命名为 `XY orig -> new`）。
    /// 纯函数，便于单测。
    public static func parse(_ stdout: String) -> [GitChange] {
        var changes: [GitChange] = []
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let (code, path) = self.splitCodeAndPath(line) else { continue }

            var change = GitChange()
            change.path = path
            self.applyStatusCode(code, to: &change)

            if change.index != .none || change.workTree != .none {
                changes.append(change)
            }
        }
        return changes
    }

    /// 拆出状态码与路径。等价于 SourceGit 的正则 `^(\s?[\w\?]{1,4})\s+(.+)$`：
    /// 状态码保留前导空格、去掉尾随空格（如 "M " → "M"、" M" → " M"、"MM" → "MM"）。
    static func splitCodeAndPath(_ line: String) -> (code: String, path: String)? {
        guard line.count >= 3 else { return nil }
        let chars = Array(line)
        // porcelain v1：前两列是 XY，第三列是空格分隔。
        let xy = String(chars[0..<2])
        // 去掉尾随空格但保留前导空格。
        var code = xy
        while code.hasSuffix(" ") { code.removeLast() }
        guard !code.isEmpty else { return nil }

        // 路径从第一个非空白处开始（跳过 XY 后的若干空格）。
        var idx = 2
        while idx < chars.count, chars[idx] == " " { idx += 1 }
        guard idx < chars.count else { return nil }
        let path = String(chars[idx...])
        return (code, path)
    }

    /// porcelain 状态码 → index/workTree/冲突。完整移植 SourceGit `QueryLocalChanges` 的 switch。
    static func applyStatusCode(_ code: String, to change: inout GitChange) {
        switch code {
        case " M": change.apply(index: .none, workTree: .modified)
        case " T": change.apply(index: .none, workTree: .typeChanged)
        case " A": change.apply(index: .none, workTree: .added)
        case " D": change.apply(index: .none, workTree: .deleted)
        case " R": change.apply(index: .none, workTree: .renamed)
        case " C": change.apply(index: .none, workTree: .copied)
        case "M": change.apply(index: .modified)
        case "MM": change.apply(index: .modified, workTree: .modified)
        case "MT": change.apply(index: .modified, workTree: .typeChanged)
        case "MD": change.apply(index: .modified, workTree: .deleted)
        case "T": change.apply(index: .typeChanged)
        case "TM": change.apply(index: .typeChanged, workTree: .modified)
        case "TT": change.apply(index: .typeChanged, workTree: .typeChanged)
        case "TD": change.apply(index: .typeChanged, workTree: .deleted)
        case "A": change.apply(index: .added)
        case "AM": change.apply(index: .added, workTree: .modified)
        case "AT": change.apply(index: .added, workTree: .typeChanged)
        case "AD": change.apply(index: .added, workTree: .deleted)
        case "D": change.apply(index: .deleted)
        case "R": change.apply(index: .renamed)
        case "RM": change.apply(index: .renamed, workTree: .modified)
        case "RT": change.apply(index: .renamed, workTree: .typeChanged)
        case "RD": change.apply(index: .renamed, workTree: .deleted)
        case "C": change.apply(index: .copied)
        case "CM": change.apply(index: .copied, workTree: .modified)
        case "CT": change.apply(index: .copied, workTree: .typeChanged)
        case "CD": change.apply(index: .copied, workTree: .deleted)
        case "DD":
            change.conflictReason = .bothDeleted
            change.apply(index: .none, workTree: .conflicted)
        case "AU":
            change.conflictReason = .addedByUs
            change.apply(index: .none, workTree: .conflicted)
        case "UD":
            change.conflictReason = .deletedByThem
            change.apply(index: .none, workTree: .conflicted)
        case "UA":
            change.conflictReason = .addedByThem
            change.apply(index: .none, workTree: .conflicted)
        case "DU":
            change.conflictReason = .deletedByUs
            change.apply(index: .none, workTree: .conflicted)
        case "AA":
            change.conflictReason = .bothAdded
            change.apply(index: .none, workTree: .conflicted)
        case "UU":
            change.conflictReason = .bothModified
            change.apply(index: .none, workTree: .conflicted)
        case "??": change.apply(index: .none, workTree: .untracked)
        default: break
        }
    }
}
