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
