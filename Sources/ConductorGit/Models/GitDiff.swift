import Foundation

/// diff 里的一行。带原文件/新文件的 1-based 行号（用于 diff 视图的行号栏）。
public struct TextDiffLine: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case context
        case added
        case deleted
        /// "\ No newline at end of file" 标记行。
        case noNewline
    }

    public var kind: Kind
    /// 行内容，不含行首的 `+`/`-`/空格标记。
    public var content: String
    public var oldLine: Int?
    public var newLine: Int?
    /// 在整个 diff 里的稳定序号（供 SwiftUI 列表用）。
    public var index: Int

    public var id: Int { self.index }

    public init(kind: Kind, content: String, oldLine: Int?, newLine: Int?, index: Int) {
        self.kind = kind
        self.content = content
        self.oldLine = oldLine
        self.newLine = newLine
        self.index = index
    }
}

/// diff 的一个 hunk（`@@ ... @@` 块）。
public struct TextDiffHunk: Sendable, Equatable {
    /// `@@ -a,b +c,d @@` 整行（含尾部可选的上下文函数名）。
    public var header: String
    public var lines: [TextDiffLine]
    /// 该 hunk 的原始 patch 文本（@@ 行 + 各原始 +/-/空格 行），用于逐 hunk 暂存。
    public var patchText: String

    public init(header: String, lines: [TextDiffLine], patchText: String = "") {
        self.header = header
        self.lines = lines
        self.patchText = patchText
    }
}

/// 一个文件的文本差异。移植自 SourceGit `Models.DiffResult` 的文本部分。
public struct TextDiff: Sendable, Equatable {
    public var oldPath: String = ""
    public var newPath: String = ""
    public var hunks: [TextDiffHunk] = []
    public var isBinary: Bool = false
    /// 文件头部原始行（`diff --git` / `index` / `---` / `+++` 等），逐 hunk 暂存时拼在 hunk 前。
    public var fileHeader: [String] = []
    /// 无任何差异（git diff 输出为空）。
    public var isEmpty: Bool { self.hunks.isEmpty && !self.isBinary }

    public var addedCount: Int {
        self.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .added }.count }
    }

    public var deletedCount: Int {
        self.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deleted }.count }
    }

    public init() {}

    /// 解析 `git diff` 对单个文件的统一 diff 输出。纯函数，便于单测。
    /// 同时保留文件头与每个 hunk 的原始 patch 文本，供逐 hunk 暂存重建补丁。
    public static func parse(_ raw: String) -> TextDiff {
        var diff = TextDiff()
        var oldLine = 0
        var newLine = 0
        var index = 0
        var inHunk = false
        var hunkHeader = ""
        var hunkLines: [TextDiffLine] = []
        var rawHunkLines: [String] = []

        func flush() {
            guard inHunk else { return }
            let patch = ([hunkHeader] + rawHunkLines).joined(separator: "\n")
            diff.hunks.append(TextDiffHunk(header: hunkHeader, lines: hunkLines, patchText: patch))
            hunkLines = []
            rawHunkLines = []
            inHunk = false
        }

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.hasPrefix("diff --git") {
                flush()
                diff.fileHeader = [line]
                continue
            }
            if line.hasPrefix("Binary files") || line.hasPrefix("GIT binary patch") {
                diff.isBinary = true
                continue
            }
            if line.hasPrefix("@@") {
                flush()
                let (oldStart, newStart) = Self.parseHunkHeader(line)
                oldLine = oldStart
                newLine = newStart
                hunkHeader = line
                inHunk = true
                continue
            }
            if !inHunk {
                // 文件头部分（index / mode / --- / +++ 等），原样留存以便重建补丁。
                if line.hasPrefix("--- ") { diff.oldPath = Self.stripDiffPath(String(line.dropFirst(4))) }
                if line.hasPrefix("+++ ") { diff.newPath = Self.stripDiffPath(String(line.dropFirst(4))) }
                if !line.isEmpty { diff.fileHeader.append(line) }
                continue
            }

            // hunk 内的内容行：原始行留存 + 解析出带行号的结构化行。
            rawHunkLines.append(line)
            if line.hasPrefix("+") {
                hunkLines.append(TextDiffLine(
                    kind: .added, content: String(line.dropFirst()), oldLine: nil, newLine: newLine, index: index))
                newLine += 1; index += 1
            } else if line.hasPrefix("-") {
                hunkLines.append(TextDiffLine(
                    kind: .deleted, content: String(line.dropFirst()), oldLine: oldLine, newLine: nil, index: index))
                oldLine += 1; index += 1
            } else if line.hasPrefix("\\") {
                hunkLines.append(TextDiffLine(
                    kind: .noNewline, content: String(line.dropFirst(2)), oldLine: nil, newLine: nil, index: index))
                index += 1
            } else if line.hasPrefix(" ") || line.isEmpty {
                hunkLines.append(TextDiffLine(
                    kind: .context, content: line.isEmpty ? "" : String(line.dropFirst()),
                    oldLine: oldLine, newLine: newLine, index: index))
                oldLine += 1; newLine += 1; index += 1
            }
        }

        flush()
        return diff
    }

    /// `a/path` / `b/path` / `/dev/null` → 干净路径。
    static func stripDiffPath(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed == "/dev/null" { return "" }
        if trimmed.hasPrefix("a/") || trimmed.hasPrefix("b/") {
            return String(trimmed.dropFirst(2))
        }
        return trimmed
    }

    /// 从 `@@ -oldStart,oldCount +newStart,newCount @@` 解析起始行号。纯函数。
    static func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int) {
        // 取两个 `@@` 之间的范围段。
        guard let firstRange = header.range(of: "@@"),
              let secondRange = header.range(of: "@@", range: firstRange.upperBound..<header.endIndex)
        else { return (0, 0) }
        let spec = header[firstRange.upperBound..<secondRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        var oldStart = 0
        var newStart = 0
        for token in spec.split(separator: " ") {
            if token.hasPrefix("-") {
                oldStart = Self.firstInt(String(token.dropFirst()))
            } else if token.hasPrefix("+") {
                newStart = Self.firstInt(String(token.dropFirst()))
            }
        }
        return (oldStart, newStart)
    }

    /// "12,7" → 12；"12" → 12。
    private static func firstInt(_ s: String) -> Int {
        let head = s.split(separator: ",").first.map(String.init) ?? s
        return Int(head) ?? 0
    }
}
