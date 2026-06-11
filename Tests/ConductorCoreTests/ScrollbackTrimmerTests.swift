import XCTest
@testable import ConductorCore

final class ScrollbackTrimmerTests: XCTestCase {
    func testDropsTrailingBlankScreenRows() {
        let text = "a\nb\n\n   \n\n"
        XCTAssertEqual(ScrollbackTrimmer.trim(text), "a\nb")
    }

    func testKeepsOnlyLastMaxLines() {
        let text = (1...10).map(String.init).joined(separator: "\n")
        XCTAssertEqual(ScrollbackTrimmer.trim(text, maxLines: 3), "8\n9\n10")
    }

    func testEnforcesByteLimitKeepingNewest() {
        let text = (1...100).map { _ in String(repeating: "x", count: 50) }.joined(separator: "\n")
        let trimmed = ScrollbackTrimmer.trim(text, maxLines: 1000, maxBytes: 200)
        XCTAssertLessThanOrEqual(trimmed.utf8.count, 200)
        XCTAssertTrue(trimmed.hasSuffix(String(repeating: "x", count: 50)))
    }

    func testShortTextUnchanged() {
        XCTAssertEqual(ScrollbackTrimmer.trim("hello\nworld"), "hello\nworld")
    }
}
