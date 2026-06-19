import XCTest
@testable import ConductorCore

final class UsagePaceTests: XCTestCase {
    func testPaceDetectsDeficitAndRunOutETA() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = RateWindow(
            usedPercent: 80,
            windowMinutes: 100,
            resetsAt: now.addingTimeInterval(50 * 60))

        let pace = try XCTUnwrap(UsagePace.window(window, now: now, minimumExpectedUsedPercent: 0))

        XCTAssertEqual(pace.stage, .farAhead)
        XCTAssertEqual(Int(pace.expectedUsedPercent.rounded()), 50)
        XCTAssertEqual(Int(pace.deltaPercent.rounded()), 30)
        XCTAssertFalse(pace.willLastToReset)
        XCTAssertEqual(Int((pace.etaSeconds ?? 0).rounded()), 750)
        XCTAssertTrue(pace.summary(now: now).isDeficit)
    }

    func testPaceDetectsReserveAndLastsToReset() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let window = RateWindow(
            usedPercent: 20,
            windowMinutes: 100,
            resetsAt: now.addingTimeInterval(50 * 60))

        let pace = try XCTUnwrap(UsagePace.window(window, now: now, minimumExpectedUsedPercent: 0))

        XCTAssertEqual(pace.stage, .farBehind)
        XCTAssertEqual(Int(pace.expectedUsedPercent.rounded()), 50)
        XCTAssertEqual(Int(pace.deltaPercent.rounded()), -30)
        XCTAssertTrue(pace.willLastToReset)
        XCTAssertNil(pace.etaSeconds)
        XCTAssertTrue(pace.summary(now: now).isReserve)
    }

    func testPaceSkipsWindowsWithoutResetMetadata() {
        let window = RateWindow(usedPercent: 50)

        XCTAssertNil(UsagePace.window(window, minimumExpectedUsedPercent: 0))
    }

    func testWeeklyPaceCanUseWorkDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 6,
            day: 15,
            hour: 0))!
        let now = start.addingTimeInterval(4 * 24 * 60 * 60)
        let window = RateWindow(
            usedPercent: 50,
            windowMinutes: 7 * 24 * 60,
            resetsAt: start.addingTimeInterval(7 * 24 * 60 * 60))

        let linear = try XCTUnwrap(UsagePace.summary(
            window: window,
            now: now,
            minimumExpectedUsedPercent: 0))
        let workdays = try XCTUnwrap(UsagePace.summary(
            window: window,
            now: now,
            minimumExpectedUsedPercent: 0,
            weeklyProgressWorkDays: 5))

        XCTAssertEqual(Int(linear.expectedUsedPercent.rounded()), 57)
        XCTAssertEqual(Int(workdays.expectedUsedPercent.rounded()), 80)
        XCTAssertTrue(workdays.isReserve)
    }

    func testWorkDayMarkerPercentsMatchCodexBar() {
        XCTAssertEqual(
            UsagePace.workDayMarkerPercents(workDays: 5, windowMinutes: 10080),
            [20, 40, 60, 80])
        XCTAssertEqual(
            UsagePace.workDayMarkerPercents(workDays: 4, windowMinutes: 10080),
            [25, 50, 75])
        XCTAssertEqual(
            UsagePace.workDayMarkerPercents(workDays: nil, windowMinutes: 10080),
            [])
        XCTAssertEqual(
            UsagePace.workDayMarkerPercents(workDays: 5, windowMinutes: 300),
            [])
    }
}
