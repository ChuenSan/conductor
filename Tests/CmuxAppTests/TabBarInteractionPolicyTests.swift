@testable import CmuxApp
import XCTest

final class TabBarInteractionPolicyTests: XCTestCase {
    func testDisablesTabDragWhileRenaming() {
        XCTAssertFalse(TabBarInteractionPolicy.allowsTabDrag(tabCount: 2, isRenaming: true))
    }

    func testDisablesTabDragEvenWhenMultipleTabsAreNotRenaming() {
        XCTAssertFalse(TabBarInteractionPolicy.allowsTabDrag(tabCount: 1, isRenaming: false))
        XCTAssertFalse(TabBarInteractionPolicy.allowsTabDrag(tabCount: 2, isRenaming: false))
    }
}
