import Testing
@testable import ConductorCore

@Test func truncateKeepsLastLines() {
    let input = (1...10).map { "line\($0)" }.joined(separator: "\n")
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 3, maxBytes: 1_000_000)
    #expect(result == "line8\nline9\nline10")
}

@Test func truncateNeverSplitsACodepoint() {
    // 200 CJK chars, each 3 UTF-8 bytes. Cap at 90 bytes -> must land on a char boundary.
    let input = String(repeating: "中", count: 200)
    let result = TerminalScrollbackSanitizer.truncate(input, maxLines: 1_000, maxBytes: 90)
    #expect(!result.unicodeScalars.contains("\u{FFFD}"))
    #expect(result.utf8.count <= 90)
    #expect(result.allSatisfy { $0 == "中" })
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
