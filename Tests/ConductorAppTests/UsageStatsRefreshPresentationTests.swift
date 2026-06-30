import XCTest
@testable import ConductorApp

final class UsageStatsRefreshPresentationTests: XCTestCase {
    func testLoadingRefreshHidesExistingReport() {
        XCTAssertTrue(UsageStatsRefreshPresentation.showsLoadingSurface(isLoading: true, hasReport: true))
        XCTAssertFalse(UsageStatsRefreshPresentation.showsReport(isLoading: true, hasReport: true))
    }

    func testLoadedReportIsShownOnlyAfterLoadingFinishes() {
        XCTAssertFalse(UsageStatsRefreshPresentation.showsLoadingSurface(isLoading: false, hasReport: true))
        XCTAssertTrue(UsageStatsRefreshPresentation.showsReport(isLoading: false, hasReport: true))
        XCTAssertFalse(UsageStatsRefreshPresentation.showsReport(isLoading: false, hasReport: false))
    }

    func testReportRevealAnimationHasVisibleDuration() {
        XCTAssertGreaterThan(UsageStatsRefreshPresentation.revealAnimationDuration, 0.2)
    }

    func testLoadingSkeletonUsesRestrainedDensityAndOpacity() {
        XCTAssertLessThanOrEqual(UsageStatsRefreshPresentation.loadingSkeletonMetricTileCount, 3)
        XCTAssertLessThanOrEqual(UsageStatsRefreshPresentation.loadingSkeletonChartBarCount, 12)
        XCTAssertLessThanOrEqual(UsageStatsRefreshPresentation.skeletonFillOpacity(isPulsing: true), 0.36)
        XCTAssertLessThan(
            UsageStatsRefreshPresentation.skeletonFillOpacity(isPulsing: false),
            UsageStatsRefreshPresentation.skeletonFillOpacity(isPulsing: true))
    }

    func testDailyChartAnimationIsNoticeablyVisible() {
        XCTAssertGreaterThanOrEqual(UsageStatsRefreshPresentation.barRevealAnimationDuration, 0.85)
        XCTAssertGreaterThan(
            UsageStatsRefreshPresentation.barRevealAnimationDuration,
            UsageStatsRefreshPresentation.revealAnimationDuration)
        XCTAssertEqual(UsageStatsRefreshPresentation.chartBarStaggerDelay(dayIndex: 0, dayCount: 30), 0)
        XCTAssertGreaterThan(UsageStatsRefreshPresentation.chartBarStaggerDelay(dayIndex: 12, dayCount: 30), 0)
    }
}
