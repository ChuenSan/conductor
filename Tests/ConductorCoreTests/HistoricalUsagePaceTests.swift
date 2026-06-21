import XCTest
@testable import ConductorCore

final class HistoricalUsagePaceTests: XCTestCase {
    func testHistoricalPaceUsesCompleteAccountScopedWeeks() async throws {
        let store = HistoricalUsageHistoryStore(fileURL: tempURL())
        let duration = TimeInterval(7 * 24 * 60 * 60)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let accountKey = "codex-account:test"

        for week in 1...3 {
            let reset = start.addingTimeInterval(duration * Double(week))
            let windowStart = reset.addingTimeInterval(-duration)
            for fraction in [0.0, 0.18, 0.36, 0.54, 0.72, 1.0] {
                _ = await store.recordCodexWeekly(
                    window: RateWindow(
                        usedPercent: fraction * 40,
                        windowMinutes: 10080,
                        resetsAt: reset),
                    sampledAt: windowStart.addingTimeInterval(duration * fraction),
                    accountKey: accountKey)
            }
        }

        let loadedDataset = await store.loadCodexDataset(accountKey: accountKey)
        let dataset = try XCTUnwrap(loadedDataset)
        XCTAssertEqual(dataset.weeks.count, 3)

        let currentReset = start.addingTimeInterval(duration * 4)
        let now = currentReset.addingTimeInterval(-duration / 2)
        let historical = try XCTUnwrap(CodexHistoricalPaceEvaluator.evaluate(
            window: RateWindow(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: currentReset),
            now: now,
            dataset: dataset))

        XCTAssertLessThan(historical.expectedUsedPercent, 50)
        XCTAssertGreaterThan(historical.deltaPercent, 0)
    }

    func testDashboardBreakdownBackfillsEightHistoricalWeeks() async throws {
        let store = HistoricalUsageHistoryStore(fileURL: tempURL())
        let duration = TimeInterval(7 * 24 * 60 * 60)
        let currentReset = Date(timeIntervalSince1970: 1_900_000_000)
        let currentStart = currentReset.addingTimeInterval(-duration)
        let now = currentStart.addingTimeInterval(duration / 2)
        let accountKey = "codex-account:backfill"
        let coverageStart = currentReset.addingTimeInterval(-duration * 9)

        var days: [OpenAIDashboardDailyBreakdown] = []
        var cursor = dayStart(coverageStart)
        while cursor <= dayStart(now) {
            days.append(OpenAIDashboardDailyBreakdown(
                day: dayKey(cursor),
                services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 1)],
                totalCreditsUsed: 1))
            cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor)!
        }

        let backfilledDataset = await store.backfillCodexWeeklyFromUsageBreakdown(
            days,
            referenceWindow: RateWindow(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: currentReset),
            now: now,
            accountKey: accountKey)
        let dataset = try XCTUnwrap(backfilledDataset)

        XCTAssertGreaterThanOrEqual(dataset.weeks.count, 3)
        XCTAssertLessThanOrEqual(dataset.weeks.count, 8)
        XCTAssertTrue(dataset.weeks.allSatisfy { $0.curve.count == CodexHistoricalDataset.gridPointCount })

        let pace = try XCTUnwrap(CodexHistoricalPaceEvaluator.evaluate(
            window: RateWindow(
                usedPercent: 50,
                windowMinutes: 10080,
                resetsAt: currentReset),
            now: now,
            dataset: dataset))
        XCTAssertNotNil(pace)
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-historical-\(UUID().uuidString).jsonl")
    }

    private func dayStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
