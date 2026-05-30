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

    /// Returns the bytes from the start of the first full line at or after the
    /// `maxBytes` cut point. Resuming on a line boundary keeps only whole lines, so
    /// the result never begins mid-codepoint or inside a partial escape sequence
    /// (a `\n` is never a UTF-8 continuation byte or part of an escape sequence).
    /// If the tail past the cut contains no newline it is a single partial line —
    /// dropped entirely, because a severed escape fragment (e.g. `5;31m` shorn of
    /// its leading `ESC[`) would replay as literal garbage.
    static func safeByteSuffix(_ text: String, maxBytes: Int) -> String {
        let bytes = Array(text.utf8)
        guard bytes.count > maxBytes else { return text }
        let cut = bytes.count - maxBytes
        guard let newline = bytes[cut...].firstIndex(of: 0x0A) else { return "" }
        let lineStart = newline + 1
        guard lineStart < bytes.count else { return "" }
        return String(decoding: bytes[lineStart...], as: UTF8.self)
    }
}
