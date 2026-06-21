@testable import ConductorApp
import ConductorCore
import XCTest

@MainActor
final class UsageMonitorAntigravitySignalTests: XCTestCase {
    func testAntigravityAutomaticSignalIgnoresLegacyLanesWithoutQuotaSummary() throws {
        let provider = try XCTUnwrap(UsageProviderCatalog.entry(for: "antigravity"))
        let snapshot = UsageSnapshot(
            primary: RateWindow(title: "Claude", usedPercent: 0),
            secondary: RateWindow(title: "Gemini Pro", usedPercent: 100),
            tertiary: RateWindow(title: "Gemini Flash", usedPercent: 40),
            extraRateWindows: [
                NamedRateWindow(
                    id: "antigravity-compact-fallback-model-a",
                    title: "Model A",
                    window: RateWindow(usedPercent: 100)),
            ])

        XCTAssertNil(UsageMonitor.signal(provider: provider, snapshot: snapshot, config: AppConfig()))
    }

    func testAntigravityAutomaticSignalRanksRenderedGeminiQuotaSummaryLanes() throws {
        let provider = try XCTUnwrap(UsageProviderCatalog.entry(for: "antigravity"))
        let snapshot = antigravityQuotaSummarySnapshot(
            geminiSessionUsed: 95,
            geminiWeeklyUsed: 20,
            otherSessionUsed: 99,
            otherWeeklyUsed: 90)

        let signal = try XCTUnwrap(UsageMonitor.signal(provider: provider, snapshot: snapshot, config: AppConfig()))

        XCTAssertEqual(signal.providerID, "antigravity")
        XCTAssertEqual(signal.windowTitle, "Gemini Session")
        XCTAssertEqual(signal.usedPercent, 95)
        XCTAssertEqual(signal.remainingPercent, 5)
        XCTAssertEqual(signal.secondaryMetric?.title, "Gemini Weekly")
        XCTAssertEqual(signal.secondaryMetric?.usedPercent, 20)
    }

    func testAntigravityAutomaticSignalFallsBackToOtherQuotaSummaryWhenGeminiIsAbsent() throws {
        let provider = try XCTUnwrap(UsageProviderCatalog.entry(for: "antigravity"))
        let snapshot = UsageSnapshot(extraRateWindows: [
            quotaSummaryWindow(id: "3p-5h", title: "Claude + GPT Session", usedPercent: 88, windowMinutes: 300),
            quotaSummaryWindow(id: "3p-weekly", title: "Claude + GPT Weekly", usedPercent: 35, windowMinutes: 10_080),
        ])

        let signal = try XCTUnwrap(UsageMonitor.signal(provider: provider, snapshot: snapshot, config: AppConfig()))

        XCTAssertEqual(signal.windowTitle, "Claude + GPT Session")
        XCTAssertEqual(signal.usedPercent, 88)
        XCTAssertEqual(signal.secondaryMetric?.title, "Claude + GPT Weekly")
    }

    func testAntigravityHeadlineExcludesOnlyWhenRenderedQuotaSummaryLanesAreExhausted() throws {
        let provider = try XCTUnwrap(UsageProviderCatalog.entry(for: "antigravity"))
        var snapshot = antigravityQuotaSummarySnapshot(
            geminiSessionUsed: 100,
            geminiWeeklyUsed: 100,
            otherSessionUsed: 50,
            otherWeeklyUsed: 50)
        var signal = try XCTUnwrap(UsageMonitor.signal(provider: provider, snapshot: snapshot, config: AppConfig()))

        XCTAssertTrue(UsageMonitor.excludeFromProviderHeadline(
            providerID: "antigravity",
            snapshot: snapshot,
            signal: signal))

        snapshot = antigravityQuotaSummarySnapshot(
            geminiSessionUsed: 100,
            geminiWeeklyUsed: 40,
            otherSessionUsed: 100,
            otherWeeklyUsed: 100)
        signal = try XCTUnwrap(UsageMonitor.signal(provider: provider, snapshot: snapshot, config: AppConfig()))

        XCTAssertFalse(UsageMonitor.excludeFromProviderHeadline(
            providerID: "antigravity",
            snapshot: snapshot,
            signal: signal))
    }

    private func antigravityQuotaSummarySnapshot(
        geminiSessionUsed: Double,
        geminiWeeklyUsed: Double,
        otherSessionUsed: Double,
        otherWeeklyUsed: Double) -> UsageSnapshot
    {
        UsageSnapshot(extraRateWindows: [
            quotaSummaryWindow(id: "gemini-5h", title: "Gemini Session", usedPercent: geminiSessionUsed, windowMinutes: 300),
            quotaSummaryWindow(id: "gemini-weekly", title: "Gemini Weekly", usedPercent: geminiWeeklyUsed, windowMinutes: 10_080),
            quotaSummaryWindow(id: "3p-5h", title: "Claude + GPT Session", usedPercent: otherSessionUsed, windowMinutes: 300),
            quotaSummaryWindow(id: "3p-weekly", title: "Claude + GPT Weekly", usedPercent: otherWeeklyUsed, windowMinutes: 10_080),
        ])
    }

    private func quotaSummaryWindow(
        id: String,
        title: String,
        usedPercent: Double,
        windowMinutes: Int) -> NamedRateWindow
    {
        NamedRateWindow(
            id: "antigravity-quota-summary-\(id)",
            title: title,
            window: RateWindow(
                title: title,
                usedPercent: usedPercent,
                windowMinutes: windowMinutes))
    }
}
