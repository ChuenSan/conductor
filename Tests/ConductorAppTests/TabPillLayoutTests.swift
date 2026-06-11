@testable import ConductorApp
import XCTest

final class TabPillLayoutTests: XCTestCase {
    func testLongTabTitlesHaveAStableWidthLimit() {
        XCTAssertLessThanOrEqual(TabPillLayout.maxTitleWidth, 130)
        XCTAssertGreaterThanOrEqual(TabPillLayout.maxTitleWidth, 96)
    }

    func testGroupTabTitlesKeepReadableMinimumWidth() {
        XCTAssertGreaterThanOrEqual(TabPillLayout.minGroupTitleWidth, 64)
        XCTAssertLessThan(TabPillLayout.minGroupTitleWidth, TabPillLayout.maxTitleWidth)
    }

    func testSinglePaneTabTitlesKeepReadableMinimumWidth() {
        XCTAssertGreaterThanOrEqual(TabPillLayout.minTitleWidth, 56)
        XCTAssertLessThan(TabPillLayout.minTitleWidth, TabPillLayout.maxTitleWidth)
    }
}
