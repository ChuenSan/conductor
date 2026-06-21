@testable import ConductorApp
import XCTest

final class OnboardingPresentationStateTests: XCTestCase {
    func testOpenCloseAndPageNavigationClampToAvailablePages() {
        var state = OnboardingPresentationState(pageCount: 3)

        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.pageIndex, 0)
        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.isLastPage)

        state.open()
        XCTAssertTrue(state.isPresented)
        XCTAssertEqual(state.pageIndex, 0)

        state.previous()
        XCTAssertEqual(state.pageIndex, 0)

        state.next()
        XCTAssertEqual(state.pageIndex, 1)
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.isLastPage)

        state.selectPage(8)
        XCTAssertEqual(state.pageIndex, 2)
        XCTAssertTrue(state.isLastPage)

        state.next()
        XCTAssertEqual(state.pageIndex, 2)

        state.close()
        XCTAssertFalse(state.isPresented)
        XCTAssertEqual(state.pageIndex, 0)
    }

    func testLaunchPolicyPresentsUntilCurrentVersionIsMarkedSeen() {
        let suiteName = "OnboardingPresentationStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        var policy = OnboardingLaunchPolicy(currentVersion: "intro-v1")

        XCTAssertTrue(policy.shouldPresent(using: defaults))

        policy.markSeen(using: defaults)
        XCTAssertFalse(policy.shouldPresent(using: defaults))

        policy = OnboardingLaunchPolicy(currentVersion: "intro-v2")
        XCTAssertTrue(policy.shouldPresent(using: defaults))
    }
}
