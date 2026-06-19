import Foundation
import XCTest
@testable import ConductorCore

final class UsageProviderStatusTests: XCTestCase {
    func testCancellationHelperRecognizesURLSessionCancellation() throws {
        XCTAssertTrue(UsageProviderCancellation.isCancelled(URLError(.cancelled)))

        do {
            try UsageProviderCancellation.rethrowIfCancelled(URLError(.cancelled))
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: URLSession cancellation is normalized to Swift cancellation.
        }
    }

    func testCancellationHelperRecognizesWrappedCancellationMessages() throws {
        XCTAssertTrue(UsageProviderCancellation.isCancelled(NSError(
            domain: "provider",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "CancellationError()"])))
        XCTAssertTrue(UsageProviderCancellation.isCancelled(NSError(
            domain: "provider",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "request cancelled while waiting for response"])))
        XCTAssertFalse(UsageProviderCancellation.isCancelled(NSError(
            domain: "provider",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "request failed with status 500"])))

        do {
            try UsageProviderCancellation.rethrowIfCancelled(NSError(
                domain: "provider",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "cancelled"]))
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: provider-wrapped cancellation is normalized before reporting.
        }
    }

    func testUsageCLIReporterUnlessCancelledPropagatesCancellation() async throws {
        let entry = UsageProviderEntry(
            id: "demo",
            name: "Demo",
            logo: "demo",
            fallbackSystemImage: "circle",
            isConfigured: { true },
            fetch: {
                throw CancellationError()
            })

        do {
            _ = try await UsageCLIReporter.fetchUnlessCancelled(entries: [entry])
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: serve cancellation must not be converted into a provider error row.
        }
    }

    func testUsageCLIReporterUnlessCancelledPropagatesURLSessionCancellation() async throws {
        let entry = UsageProviderEntry(
            id: "demo",
            name: "Demo",
            logo: "demo",
            fallbackSystemImage: "circle",
            isConfigured: { true },
            fetch: {
                throw URLError(.cancelled)
            })

        do {
            _ = try await UsageCLIReporter.fetchUnlessCancelled(entries: [entry])
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: URLSession cancellation must not become a provider error row.
        }
    }

    func testStatusReporterUnlessCancelledPropagatesTaskCancellation() async throws {
        let entry = UsageProviderEntry(
            id: "demo",
            name: "Demo",
            logo: "demo",
            fallbackSystemImage: "circle",
            isConfigured: { true },
            fetch: { UsageSnapshot() })

        let task = Task<[UsageProviderStatusSnapshot], Error> {
            await Task.yield()
            return try await UsageProviderStatusReporter.fetchUnlessCancelled(entries: [entry])
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation is a control-flow signal, not a status snapshot.
        }
    }

    func testParseStatusPagePayload() throws {
        let entry = UsageProviderEntry(
            id: "codex",
            name: "Codex",
            logo: "codex",
            fallbackSystemImage: "chevron.left.forwardslash.chevron.right",
            statusPageURL: "https://status.openai.com/",
            isConfigured: { true },
            fetch: { UsageSnapshot() })
        let payload = """
        {
          "page": { "updated_at": "2026-06-18T10:15:30.000Z" },
          "status": {
            "indicator": "minor",
            "description": "Partial outage"
          }
        }
        """

        let snapshot = try UsageProviderStatusFetcher.parseStatusPage(data: Data(payload.utf8), entry: entry)

        XCTAssertEqual(snapshot.provider, "codex")
        XCTAssertEqual(snapshot.indicator, .minor)
        XCTAssertEqual(snapshot.description, "Partial outage")
        XCTAssertEqual(snapshot.statusPageURL, "https://status.openai.com/")
        XCTAssertNotNil(snapshot.updatedAt)
    }

    func testUnknownIndicatorFallsBackToUnknown() throws {
        let entry = UsageProviderEntry(
            id: "demo",
            name: "Demo",
            logo: "demo",
            fallbackSystemImage: "circle",
            statusPageURL: "https://status.example.com",
            isConfigured: { true },
            fetch: { UsageSnapshot() })
        let payload = """
        {
          "status": {
            "indicator": "surprise",
            "description": "Unexpected feed value"
          }
        }
        """

        let snapshot = try UsageProviderStatusFetcher.parseStatusPage(data: Data(payload.utf8), entry: entry)

        XCTAssertEqual(snapshot.indicator, .unknown)
        XCTAssertEqual(snapshot.description, "Unexpected feed value")
    }

    func testParseGoogleWorkspaceStatusPayload() throws {
        let entry = UsageProviderEntry(
            id: "gemini",
            name: "Gemini",
            logo: "gemini",
            fallbackSystemImage: "diamond",
            statusLinkURL: "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
            googleWorkspaceStatusProductID: "npdyhgECDJ6tB66MxXyo",
            isConfigured: { true },
            fetch: { UsageSnapshot() })
        let payload = """
        [
          {
            "begin": "2026-06-18T08:00:00Z",
            "modified": "2026-06-18T08:30:00Z",
            "status_impact": "SERVICE_DISRUPTION",
            "severity": "medium",
            "currently_affected_products": [
              { "title": "Gemini", "id": "npdyhgECDJ6tB66MxXyo" }
            ],
            "most_recent_update": {
              "when": "2026-06-18T08:45:00Z",
              "status": "SERVICE_DISRUPTION",
              "text": "**Summary**\\n- [Gemini requests](https://example.com) may fail."
            }
          }
        ]
        """

        let snapshot = try UsageProviderStatusFetcher.parseGoogleWorkspaceStatus(
            data: Data(payload.utf8),
            entry: entry,
            productID: "npdyhgECDJ6tB66MxXyo")

        XCTAssertEqual(snapshot.provider, "gemini")
        XCTAssertEqual(snapshot.indicator, .major)
        XCTAssertEqual(snapshot.description, "Gemini requests may fail.")
        XCTAssertEqual(snapshot.source, "google-workspace")
        XCTAssertNotNil(snapshot.updatedAt)
    }

    func testUsageCLIReportIncludesStatusInJSONAndText() throws {
        let status = UsageProviderStatusSnapshot(
            provider: "codex",
            name: "Codex",
            indicator: .minor,
            description: "Partial outage",
            statusPageURL: "https://status.openai.com/",
            source: "statuspage")
        let report = UsageCLIReport(
            provider: "codex",
            name: "Codex",
            configured: false,
            source: "auto",
            status: status,
            usage: nil,
            error: UsageCLIError(CodexUsageError.notLoggedIn))

        let data = try JSONEncoder().encode(report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedStatus = try XCTUnwrap(object["status"] as? [String: Any])

        XCTAssertEqual(encodedStatus["provider"] as? String, "codex")
        XCTAssertEqual(encodedStatus["indicator"] as? String, "minor")
        XCTAssertEqual(encodedStatus["description"] as? String, "Partial outage")

        let text = UsageCLITextRenderer.render([report])
        XCTAssertTrue(text.contains("status:"))
        XCTAssertTrue(text.contains("Partial outage"))
        XCTAssertTrue(text.contains("error:"))
    }

    func testUsageCLITextRendererCanHideCodexCreditsOnly() {
        let codex = UsageCLIReport(
            provider: "codex",
            name: "Codex",
            configured: true,
            usage: UsageCLIUsage(snapshot: UsageSnapshot(
                providerCost: ProviderCostSnapshot(
                    used: 12.5,
                    limit: 0,
                    currencyCode: "USD",
                    period: "Balance"))),
            error: nil)
        let openAI = UsageCLIReport(
            provider: "openai",
            name: "OpenAI",
            configured: true,
            usage: UsageCLIUsage(snapshot: UsageSnapshot(
                providerCost: ProviderCostSnapshot(
                    used: 3,
                    limit: 10,
                    currencyCode: "USD",
                    period: "Monthly"))),
            error: nil)

        let defaultText = UsageCLITextRenderer.render([codex, openAI])
        let hiddenText = UsageCLITextRenderer.render([codex, openAI], includeCredits: false)

        XCTAssertEqual(defaultText.components(separatedBy: "  cost:").count - 1, 2)
        XCTAssertEqual(hiddenText.components(separatedBy: "  cost:").count - 1, 1)
        XCTAssertFalse(hiddenText.contains("Codex (codex)\n  configured: yes\n  source: auto\n  cost:"))
        XCTAssertTrue(hiddenText.contains("OpenAI (openai)"))
        XCTAssertTrue(hiddenText.contains("  cost:"))
    }

    func testUsageCLITextRendererCanHidePersonalInfoInTextOutput() {
        let report = UsageCLIReport(
            provider: "codex",
            name: "Codex",
            configured: true,
            source: "web",
            usage: UsageCLIUsage(snapshot: UsageSnapshot(accountLabel: "dev@example.com")),
            openaiDashboard: OpenAIDashboardSnapshot(signedInEmail: "team@example.org"),
            error: nil)

        let text = UsageCLITextRenderer.render([report], hidePersonalInfo: true)

        XCTAssertTrue(text.contains("account: Hidden"))
        XCTAssertTrue(text.contains("Web session: Hidden"))
        XCTAssertFalse(text.contains("dev@example.com"))
        XCTAssertFalse(text.contains("team@example.org"))
    }

    func testUsageCLIReportIncludesOpenAICreditsHistoryInJSONAndText() throws {
        let events = [
            CreditEvent(
                date: Date(timeIntervalSince1970: 1_780_272_000),
                service: "CLI",
                creditsUsed: 12),
            CreditEvent(
                date: Date(timeIntervalSince1970: 1_780_185_600),
                service: "Code Review",
                creditsUsed: 2.5),
        ]
        let history = UsageCLIOpenAICreditsHistory(
            accountEmail: "dev@example.com",
            updatedAt: Date(timeIntervalSince1970: 1_780_300_800),
            events: events)
        let report = UsageCLIReport(
            provider: "codex",
            name: "Codex",
            configured: true,
            source: "auto",
            usage: UsageCLIUsage(snapshot: UsageSnapshot(accountLabel: "dev@example.com")),
            openaiCreditsHistory: history,
            error: nil)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let encodedHistory = try XCTUnwrap(object["openaiCreditsHistory"] as? [String: Any])

        XCTAssertEqual(encodedHistory["accountEmail"] as? String, "dev@example.com")
        XCTAssertEqual(encodedHistory["eventCount"] as? Int, 2)
        XCTAssertEqual((encodedHistory["recentEvents"] as? [Any])?.count, 2)
        XCTAssertEqual((encodedHistory["dailyBreakdown"] as? [Any])?.count, 2)

        let text = UsageCLITextRenderer.render([report])
        XCTAssertTrue(text.contains("Credits history: 2 stored events"))
        XCTAssertTrue(text.contains("latest 2026-06-01"))
        XCTAssertTrue(text.contains("latest day: 2026-06-01"))
        XCTAssertFalse(UsageCLITextRenderer.render([report], includeCredits: false).contains("Credits history:"))
    }

    func testUsageCLITextRendererShowsOpenAIWebDashboardForWebSource() {
        let event = CreditEvent(
            date: Date(timeIntervalSince1970: 1_780_272_000),
            service: "CLI",
            creditsUsed: 12)
        let dashboard = OpenAIDashboardSnapshot(
            signedInEmail: "dev@example.com",
            codeReviewRemainingPercent: 42.4,
            codeReviewLimit: RateWindow(
                usedPercent: 57.6,
                resetsAt: Date(timeIntervalSince1970: 1_780_300_800)),
            creditEvents: [event])
        let report = UsageCLIReport(
            provider: "codex",
            name: "Codex",
            configured: true,
            source: "web",
            usage: UsageCLIUsage(snapshot: UsageSnapshot()),
            openaiDashboard: dashboard,
            error: nil)

        let text = UsageCLITextRenderer.render([report])

        XCTAssertTrue(text.contains("Web session: dev@example.com"))
        XCTAssertTrue(text.contains("Code review: 42% remaining"))
        XCTAssertTrue(text.contains("Web history: 1 events"))
        XCTAssertTrue(text.contains("latest 2026-06-01"))
    }

    func testUsageCLITextRendererDoesNotShowCachedDashboardForOAuthText() {
        let report = UsageCLIReport(
            provider: "codex",
            name: "Codex",
            configured: true,
            source: "oauth",
            usage: UsageCLIUsage(snapshot: UsageSnapshot()),
            openaiDashboard: OpenAIDashboardSnapshot(signedInEmail: "dev@example.com"),
            error: nil)

        let text = UsageCLITextRenderer.render([report])

        XCTAssertFalse(text.contains("Web session: dev@example.com"))
        XCTAssertFalse(text.contains("Web history:"))
    }
}
