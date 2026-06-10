@testable import CmuxApp
import XCTest

final class QuickStartAvailabilityTests: XCTestCase {
    func testShowsEmptyIllustrationOnlyForEmptyWorkspaces() {
        XCTAssertTrue(QuickStartAvailability.showsEmptyIllustration(tabCount: 0, totalPaneCount: 0, isPanelPresented: false))
        XCTAssertFalse(QuickStartAvailability.showsEmptyIllustration(tabCount: 1, totalPaneCount: 1, isPanelPresented: false))
        XCTAssertFalse(QuickStartAvailability.showsEmptyIllustration(tabCount: 1, totalPaneCount: 2, isPanelPresented: false))
        XCTAssertFalse(QuickStartAvailability.showsEmptyIllustration(tabCount: 2, totalPaneCount: 2, isPanelPresented: false))
        XCTAssertFalse(QuickStartAvailability.showsEmptyIllustration(tabCount: nil, totalPaneCount: nil, isPanelPresented: false))
        XCTAssertFalse(QuickStartAvailability.showsEmptyIllustration(tabCount: 0, totalPaneCount: 0, isPanelPresented: true))
    }
}
