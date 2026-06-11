@testable import ConductorApp
import XCTest

final class SidebarPresentationStateTests: XCTestCase {
    func testToggleCollapsesAndExpandsSidebar() {
        var state = SidebarPresentationState()

        XCTAssertFalse(state.isCollapsed)

        state.toggle()
        XCTAssertTrue(state.isCollapsed)

        state.toggle()
        XCTAssertFalse(state.isCollapsed)
    }
}
