import Foundation

/// Pure helpers that make prior-session scrollback safe to repaint into a fresh
/// terminal surface without garbling: byte- and escape-safe truncation,
/// idempotent line-ending normalization, and a full SGR reset wrap.
///
/// Capture and replay are byte streams of VT/ANSI escape sequences (from
/// libghostty's `write_screen_file:copy,vt` export), so every transform here
/// must preserve escape-sequence and UTF-8 codepoint boundaries.
public enum TerminalScrollbackSanitizer {
    /// Keeps the last `maxLines` lines and at most `maxBytes` bytes, never cutting
    /// inside a multi-byte codepoint or a line's escape sequence.
    public static func truncate(_ text: String, maxLines: Int, maxBytes: Int) -> String {
        // Line cap first: splitting on "\n" (a single 0x0A byte) is always safe.
        var lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        let lineCapped = lines.joined(separator: "\n")
        guard lineCapped.utf8.count > maxBytes else { return lineCapped }
        return safeByteSuffix(lineCapped, maxBytes: maxBytes)
    }

    /// Returns the last `maxBytes` bytes, advanced forward to (a) the next UTF-8
    /// leading byte and (b) the start of the next full line, so the suffix never
    /// begins mid-codepoint or inside a partial escape sequence.
    static func safeByteSuffix(_ text: String, maxBytes: Int) -> String {
        let bytes = Array(text.utf8)
        guard bytes.count > maxBytes else { return text }
        var start = bytes.count - maxBytes
        // (a) Skip UTF-8 continuation bytes (0b10xxxxxx).
        while start < bytes.count, (bytes[start] & 0xC0) == 0x80 {
            start += 1
        }
        // (b) Skip the (possibly partial) first line: resume after the next newline.
        // If there is no subsequent newline, the entire remaining content is a
        // partial line fragment — drop it entirely.
        guard let newline = bytes[start...].firstIndex(of: 0x0A) else { return "" }
        start = newline + 1
        guard start < bytes.count else { return "" }
        return String(decoding: bytes[start...], as: UTF8.self)
    }
}
