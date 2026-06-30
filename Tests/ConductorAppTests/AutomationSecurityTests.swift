@testable import ConductorApp
import XCTest

final class AutomationSecurityTests: XCTestCase {
    func testExternalResumeRequestsCannotMarkCommandsTrusted() {
        let trust = AutomationService.externalSurfaceResumeTrust(
            requestedAutoResume: true,
            requestedTrusted: true)

        XCTAssertFalse(trust.autoResume)
        XCTAssertFalse(trust.trusted)
    }
}
