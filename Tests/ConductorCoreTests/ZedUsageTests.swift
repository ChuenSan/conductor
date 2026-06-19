import XCTest
@testable import ConductorCore

final class ZedUsageTests: XCTestCase {
    func testParseLimitedPredictionsAndBillingCycle() throws {
        let data = """
        {
          "user": { "id": 42, "github_login": "octocat", "name": "Octo Cat" },
          "plan": {
            "plan_v3": "zed_pro",
            "subscription_period": {
              "started_at": "2026-06-01T00:00:00Z",
              "ended_at": "2026-07-01T00:00:00Z"
            },
            "usage": {
              "edit_predictions": { "used": 25, "limit": 100 }
            },
            "has_overdue_invoices": false
          }
        }
        """.data(using: .utf8)!

        let now = ISO8601DateFormatter().date(from: "2026-06-16T00:00:00Z")!
        let snapshot = try ZedUsageFetcher.parseSnapshot(data, updatedAt: now, now: now)

        XCTAssertEqual(snapshot.planName, "Zed Pro")
        XCTAssertEqual(snapshot.accountLabel, "octocat · Octo Cat")
        XCTAssertEqual(snapshot.primary?.title, L("Edit predictions"))
        XCTAssertEqual(snapshot.primary?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.primary?.resetDescription, L("%1$ld / %2$ld predictions", 25, 100))
        XCTAssertEqual(snapshot.secondary?.title, L("Billing cycle"))
        XCTAssertEqual(snapshot.secondary?.usedPercent ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(snapshot.extraRateWindows.count, 0)
    }

    func testParseObjectLimitAndOverdueInvoice() throws {
        let data = """
        {
          "user": { "id": 7, "github_login": "dev", "name": null },
          "plan": {
            "plan_v3": "zed_business",
            "subscription_period": null,
            "usage": {
              "edit_predictions": { "used": 120, "limit": { "limited": 100 } }
            },
            "has_overdue_invoices": true
          }
        }
        """.data(using: .utf8)!

        let snapshot = try ZedUsageFetcher.parseSnapshot(data)

        XCTAssertEqual(snapshot.planName, "Zed Business")
        XCTAssertEqual(snapshot.accountLabel, "dev")
        XCTAssertEqual(snapshot.primary?.usedPercent ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(snapshot.primary?.resetDescription, L("%1$ld / %2$ld predictions", 100, 100))
        XCTAssertEqual(snapshot.extraRateWindows.first?.id, "zed.overdue-invoices")
        XCTAssertEqual(snapshot.extraRateWindows.first?.window.resetDescription, L("Overdue invoices"))
    }

    func testParseUnlimitedLimit() throws {
        let data = """
        {
          "user": { "id": 8, "github_login": "student", "name": "" },
          "plan": {
            "plan_v3": "zed_student",
            "subscription_period": null,
            "usage": {
              "edit_predictions": { "used": 999, "limit": "unlimited" }
            },
            "has_overdue_invoices": false
          }
        }
        """.data(using: .utf8)!

        let snapshot = try ZedUsageFetcher.parseSnapshot(data)

        XCTAssertEqual(snapshot.planName, "Zed Student")
        XCTAssertEqual(snapshot.accountLabel, "student")
        XCTAssertEqual(snapshot.primary?.usedPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.primary?.resetDescription, L("Unlimited"))
    }
}
