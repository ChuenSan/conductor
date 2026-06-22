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

    func testOnboardingPagesTeachCommandDeckLoop() {
        XCTAssertEqual(
            OnboardingCatalog.pages.map(\.id),
            ["stage", "voices", "assign", "attention", "capabilities"]
        )

        XCTAssertEqual(OnboardingCatalog.pages.first?.title, "从一个项目舞台开始")
        XCTAssertEqual(OnboardingCatalog.pages.last?.title, "把能力收进能力库")
        XCTAssertTrue(OnboardingCatalog.pages.flatMap(\.beats).contains("拖到面板执行"))
        XCTAssertTrue(OnboardingCatalog.pages.flatMap(\.beats).contains("Skills / MCP / Hooks"))
    }
}
