@testable import ConductorApp
import XCTest

final class SettingsPresentationStateTests: XCTestCase {
    func testOpenAndCloseSettingsPanel() {
        var state = SettingsPresentationState()

        XCTAssertFalse(state.isPresented)

        state.open()
        XCTAssertTrue(state.isPresented)

        state.close()
        XCTAssertFalse(state.isPresented)
    }
}
