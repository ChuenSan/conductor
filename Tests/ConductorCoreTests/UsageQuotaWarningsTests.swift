import Foundation
import XCTest
@testable import ConductorCore

final class UsageQuotaWarningsTests: XCTestCase {
    func testThresholdsAreSanitizedDescendingAndActiveFiltersZero() {
        XCTAssertEqual(
            QuotaWarningThresholds.sanitized([20, 50, 20, 120, -4, 0]),
            [99, 50, 20, 0])
        XCTAssertEqual(
            QuotaWarningThresholds.active([20, 0, 50]),
            [50, 20])
    }

    func testCrossedThresholdUsesTightestThresholdWhenDroppingAcrossMultiple() {
        let threshold = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: 60,
            currentRemaining: 18,
            thresholds: [50, 20],
            alreadyFired: [])

        XCTAssertEqual(threshold, 20)
        XCTAssertEqual(
            QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
                threshold: 20,
                thresholds: [50, 20]),
            [50, 20])
    }

    func testEvaluatorClearsFiredThresholdsWhenRemainingRecovers() {
        let policy = QuotaWarningResolvedPolicy(enabled: true, thresholds: [50, 20])
        let first = UsageQuotaWarningEvaluator.evaluate(
            providerID: "codex",
            providerName: "Codex",
            snapshot: UsageSnapshot(primary: RateWindow(usedPercent: 82)),
            window: .session,
            policy: policy,
            previous: QuotaWarningState(lastRemaining: 60))

        XCTAssertEqual(first.event?.threshold, 20)
        XCTAssertEqual(first.state?.firedThresholds, Set([50, 20]))

        let recovered = UsageQuotaWarningEvaluator.evaluate(
            providerID: "codex",
            providerName: "Codex",
            snapshot: UsageSnapshot(primary: RateWindow(usedPercent: 30)),
            window: .session,
            policy: policy,
            previous: first.state)

        XCTAssertNil(recovered.event)
        XCTAssertEqual(recovered.state?.firedThresholds, Set<Int>())
    }

    func testProviderCanOverrideGlobalDisabledPolicy() {
        let policy = QuotaWarningPolicyResolver.resolve(
            global: QuotaWarningConfig(enabled: false),
            provider: QuotaWarningConfig(
                enabled: true,
                session: QuotaWarningWindowConfig(thresholds: [25, 10])),
            window: .session)

        XCTAssertTrue(policy.enabled)
        XCTAssertEqual(policy.thresholds, [25, 10])
    }
}
