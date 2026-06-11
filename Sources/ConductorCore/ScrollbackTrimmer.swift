import Foundation

/// 终端内容快照的截尾：只保留末尾 N 行 / M 字节，并收掉屏幕底部的成片空行。
/// 纯函数，便于单测；落盘/回放由 app 层负责。
public enum ScrollbackTrimmer {
    public static let defaultMaxLines = 2000
    public static let defaultMaxBytes = 262_144   // 256 KB

    public static func trim(
        _ text: String,
        maxLines: Int = defaultMaxLines,
        maxBytes: Int = defaultMaxBytes
    ) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        // 屏幕底部（提示符以下）是成片空行：全部收掉，回放时不顶出一大段空白。
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        var result = lines.joined(separator: "\n")
        // 字节上限：超了就从头按行丢，直到装下（保留最新内容）。
        while result.utf8.count > maxBytes, !lines.isEmpty {
            let overshoot = result.utf8.count - maxBytes
            var dropped = 0
            var cut = 0
            for (index, line) in lines.enumerated() {
                dropped += line.utf8.count + 1
                if dropped >= overshoot { cut = index + 1; break }
            }
            lines.removeFirst(max(cut, 1))
            result = lines.joined(separator: "\n")
        }
        return result
    }
}
