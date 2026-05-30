import Testing
@testable import ConductorCore

@Test func truncateKeepsLastLines() {
    let input = (1...10).map { "line\($0)" }.joined(separator: "\n")
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 3, maxBytes: 1_000_000)
    #expect(result == "line8\nline9\nline10")
}

@Test func truncateNeverSplitsACodepoint() {
    // Many short CJK lines (each "中中中" = 9 UTF-8 bytes). A byte cap that lands
    // mid-line must resume at a line boundary, so content survives and the result
    // contains only whole 3-byte chars and newlines — never a split codepoint.
    let input = Array(repeating: "中中中", count: 50).joined(separator: "\n")
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 40)
    #expect(!result.unicodeScalars.contains("\u{FFFD}"))
    #expect(result.utf8.count <= 40)
    #expect(!result.isEmpty)
    #expect(result.allSatisfy { $0 == "中" || $0 == "\n" })
}

@Test func truncateDropsPartialFirstLineAtByteBoundary() {
    // Two lines; cap below the first line's length forces a mid-first-line cut,
    // which must be resolved by dropping to the start of the next full line.
    let input = "aaaaaaaaaaERASEME\nkeptline"
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 12)
    #expect(result == "keptline")
}

@Test func truncateReturnsEmptyWhenNothingSurvivesByteCap() {
    let input = String(repeating: "x", count: 100) // single line, no newline
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 10)
    #expect(result == "")
}

@Test func normalizeAddsCarriageReturnToBareNewline() {
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings("a\nb") == "a\r\nb")
}

@Test func normalizeIsIdempotentForCRLF() {
    // "\r\n" is a single Swift Character, so it is never matched as a bare "\n".
    let crlf = "a\r\nb"
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings(crlf) == crlf)
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings(crlf) ==
            TerminalScrollbackSanitizer.normalizeLineEndings(
                TerminalScrollbackSanitizer.normalizeLineEndings(crlf)))
}

@Test func normalizeLeavesLoneCarriageReturn() {
    #expect(TerminalScrollbackSanitizer.normalizeLineEndings("a\rb") == "a\rb")
}

@Test func wrapAddsLeadingAndTrailingReset() {
    let wrapped = TerminalScrollbackSanitizer.wrapForReplay("hi")
    #expect(wrapped == "\u{1B}[0mhi\u{1B}[0m")
}

@Test func prepareComposesTruncateNormalizeAndWrap() {
    let input = "a\nb\nc"
    let result = TerminalScrollbackSanitizer.prepareForReplay(input, maxLines: 2, maxBytes: 1_000)
    // last 2 lines -> "b\nc"; CRLF -> "b\r\nc"; wrapped in resets.
    #expect(result == "\u{1B}[0mb\r\nc\u{1B}[0m")
}

@Test func prepareReturnsBareResetsForEmptyInput() {
    #expect(TerminalScrollbackSanitizer.prepareForReplay("", maxLines: 100, maxBytes: 100)
            == "\u{1B}[0m\u{1B}[0m")
}
