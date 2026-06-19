import XCTest
@testable import ConductorCore

final class ChutesUsageTests: XCTestCase {
    func testParseSubscriptionUsageWindows() throws {
        let data = """
        {
          "active": true,
          "plan_name": "Pro",
          "renews_at": "2026-07-01T00:00:00Z",
          "rolling": {
            "used": 25,
            "limit": 100,
            "reset_at": "2026-06-18T04:00:00Z"
          },
          "monthly": {
            "used": 400,
            "limit": 1000,
            "period_end": "2026-07-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!
        let now = ISO8601DateFormatter().date(from: "2026-06-18T00:00:00Z")!

        let snapshot = try ChutesUsageParser.parse(data: data, now: now)
        let usage = snapshot.toUsageSnapshot()

        XCTAssertEqual(snapshot.subscriptionState, .active)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(usage.planName, "Pro")
        XCTAssertEqual(usage.primary?.title, L("4 小时额度"))
        XCTAssertEqual(usage.primary?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(usage.primary?.windowMinutes, 240)
        XCTAssertEqual(usage.secondary?.title, L("月度额度"))
        XCTAssertEqual(usage.secondary?.usedPercent ?? -1, 40, accuracy: 0.001)
    }

    func testParseFallbackQuotas() throws {
        let data = """
        {
          "quotas": [
            {
              "name": "rolling 4h",
              "remaining_percent": 0.25,
              "window_hours": 4
            },
            {
              "name": "monthly subscription",
              "used": 40,
              "remaining": 60,
              "window": "1 month"
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try ChutesUsageParser.parse(data: data)
        let usage = snapshot.toUsageSnapshot()

        XCTAssertEqual(usage.primary?.title, "rolling 4h")
        XCTAssertEqual(usage.primary?.usedPercent ?? -1, 75, accuracy: 0.001)
        XCTAssertEqual(usage.secondary?.title, "monthly subscription")
        XCTAssertEqual(usage.secondary?.usedPercent ?? -1, 40, accuracy: 0.001)
    }

    func testEndpointOverrideValidation() throws {
        XCTAssertEqual(
            ChutesUsageFetcher.apiURL(env: ["CHUTES_API_URL": "chutes.internal"]).absoluteString,
            "https://chutes.internal")
        XCTAssertEqual(
            ChutesUsageFetcher.apiURL(env: ["CHUTES_API_URL": "https://api.example.com/root"]).absoluteString,
            "https://api.example.com/root")
        XCTAssertThrowsError(try ChutesUsageFetcher.validateEndpointOverride(env: ["CHUTES_API_URL": "http://api.example.com"]))
    }
}
