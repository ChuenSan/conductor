@testable import ConductorApp
import XCTest

final class ToolbarChromePolicyTests: XCTestCase {
    func testGlobalToolbarGroupsActionsByIntent() {
        XCTAssertEqual(
            GlobalToolbarActionPresentation.groups,
            [
                [.update],
                [.appearance],
                [.automation, .tasks],
                [.settings],
            ])
    }

    func testPaneHeaderControlsStayQuietUntilActiveOrHovered() {
        XCTAssertLessThan(PaneHeaderChromePolicy.controlOpacity(isActive: false, isHovering: false), 0.35)
        XCTAssertGreaterThan(PaneHeaderChromePolicy.controlOpacity(isActive: true, isHovering: false), 0.60)
        XCTAssertGreaterThan(PaneHeaderChromePolicy.controlOpacity(isActive: false, isHovering: true), 0.85)
        XCTAssertLessThanOrEqual(PaneHeaderChromePolicy.activeHeaderTintOpacity, 0.055)
    }
}
