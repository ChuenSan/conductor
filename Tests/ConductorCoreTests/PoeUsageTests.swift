import XCTest
@testable import ConductorCore

final class PoeUsageTests: XCTestCase {
    func testParseCurrentBalance() throws {
        let data = """
        {
          "current_point_balance": "1234.5"
        }
        """.data(using: .utf8)!

        let snapshot = try PoeUsageFetcher.parseSnapshot(data)

        XCTAssertEqual(snapshot.currentPointBalance, 1234.5)
    }

    func testParseHistoryPageAndDailyBuckets() throws {
        let data = """
        {
          "data": [
            {
              "query_id": "q1",
              "created_at": "2026-06-17T10:00:00Z",
              "bot_name": "Claude-Sonnet-4",
              "usage_type": "chat",
              "cost_points": 12,
              "cost_usd": 0.04
            },
            {
              "query_id": "q2",
              "created_at": "2026-06-17T11:00:00Z",
              "bot_name": "Claude-Sonnet-4",
              "usage_type": "chat",
              "points": "8",
              "usd": "0.02"
            },
            {
              "query_id": "q3",
              "created_at": "2026-06-18T10:00:00Z",
              "bot_name": "GPT-5",
              "usage_type": "image",
              "point_cost": 30
            }
          ],
          "next_cursor": "cursor-2"
        }
        """.data(using: .utf8)!

        let parsed = try PoeUsageFetcher.parseHistoryPage(data)
        let daily = PoeUsageFetcher.buildDailyBuckets(entries: parsed.entries)
        let history = PoeUsageHistorySnapshot(entries: parsed.entries, daily: daily, updatedAt: Date())

        XCTAssertEqual(parsed.nextCursor, "cursor-2")
        XCTAssertEqual(parsed.entries.count, 3)
        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily.first?.day, "2026-06-17")
        XCTAssertEqual(daily.first?.points, 20)
        XCTAssertEqual(daily.first?.requests, 2)
        XCTAssertEqual(history.topModels.first?.name, "GPT-5")
        XCTAssertEqual(history.topModels.first?.points, 30)
    }

    func testUsageSnapshotMapping() throws {
        let entries = [
            PoeUsageHistorySnapshot.Entry(
                id: "q1",
                createdAt: ISO8601DateFormatter().date(from: "2026-06-17T10:00:00Z")!,
                model: "Claude-Sonnet-4",
                usageType: "chat",
                points: 20,
                costUSD: 0.1),
            PoeUsageHistorySnapshot.Entry(
                id: "q2",
                createdAt: ISO8601DateFormatter().date(from: "2026-06-18T10:00:00Z")!,
                model: "GPT-5",
                usageType: "chat",
                points: 30,
                costUSD: nil),
        ]
        let history = PoeUsageHistorySnapshot(
            entries: entries,
            daily: PoeUsageFetcher.buildDailyBuckets(entries: entries),
            updatedAt: Date())
        let snapshot = PoeUsageSnapshot(currentPointBalance: 1234.5, history: history).toUsageSnapshot()

        XCTAssertEqual(snapshot.providerCost?.currencyCode, "Points")
        XCTAssertEqual(snapshot.providerCost?.used, 1234.5)
        XCTAssertEqual(snapshot.providerCost?.period, L("余额"))
        XCTAssertEqual(snapshot.primary?.title, L("今日"))
        XCTAssertEqual(snapshot.secondary?.title, "7d")
        XCTAssertEqual(snapshot.tertiary?.title, "30d")
        XCTAssertEqual(snapshot.extraRateWindows.first?.title, "GPT-5")
    }
}
