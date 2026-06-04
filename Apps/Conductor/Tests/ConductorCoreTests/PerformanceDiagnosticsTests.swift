import Foundation
import Testing
@testable import ConductorCore

@Test func performanceDiagnosticsKeepsRecentMainThreadStallsLatestFirstAndCapped() {
    let store = ConductorPerformanceDiagnosticsStore(capacity: 2)

    store.recordMainThreadStall(
        timestamp: Date(timeIntervalSince1970: 1),
        durationNanoseconds: 2_100_000_000,
        thresholdNanoseconds: 2_000_000_000
    )
    store.recordMainThreadStall(
        timestamp: Date(timeIntervalSince1970: 2),
        durationNanoseconds: 2_500_000_000,
        thresholdNanoseconds: 2_000_000_000
    )
    store.recordMainThreadStall(
        timestamp: Date(timeIntervalSince1970: 3),
        durationNanoseconds: 3_250_000_000,
        thresholdNanoseconds: 2_000_000_000
    )

    let snapshot = store.snapshot(budgets: [])

    #expect(snapshot.recentMainThreadStalls.map(\.durationMilliseconds) == [3_250, 2_500])
    #expect(snapshot.recentMainThreadStalls.map(\.thresholdMilliseconds) == [2_000, 2_000])
    #expect(snapshot.recentBudgetSamples.isEmpty)
}

@Test func performanceDiagnosticsDefaultBudgetsCoverCoreUserFeelSurfaces() {
    let budgets = ConductorPerformanceDiagnostics.defaultBudgets
    let ids = Set(budgets.map(\.id))

    #expect(ids.contains("settings.open"))
    #expect(ids.contains("command-palette.open"))
    #expect(ids.contains("workspace.switch"))
    #expect(ids.contains("terminal.tab-switch"))
    #expect(ids.contains("terminal.scroll-frame"))
    #expect(ids.contains("update.check"))
    #expect(ids.contains("browser.restore"))
    #expect(budgets.allSatisfy { $0.targetMilliseconds > 0 })
}

@Test func performanceDiagnosticsRecordsBudgetSamplesLatestFirstWithStatus() {
    let store = ConductorPerformanceDiagnosticsStore(capacity: 2)
    let budget = ConductorPerformanceBudget(
        id: "settings.open",
        name: "Settings open",
        targetMilliseconds: 250,
        measurement: "Test budget."
    )

    let unknown = store.recordBudgetSample(
        budgetID: "missing",
        durationNanoseconds: 1,
        source: "test",
        budgets: [budget]
    )
    #expect(unknown == nil)

    store.recordBudgetSample(
        timestamp: Date(timeIntervalSince1970: 1),
        budget: budget,
        durationNanoseconds: 120_000_000,
        source: "first"
    )
    store.recordBudgetSample(
        timestamp: Date(timeIntervalSince1970: 2),
        budget: budget,
        durationNanoseconds: 260_000_000,
        source: "second"
    )
    store.recordBudgetSample(
        timestamp: Date(timeIntervalSince1970: 3),
        budget: budget,
        durationNanoseconds: 80_000_000,
        source: "third"
    )

    let snapshot = store.snapshot(budgets: [budget])

    #expect(snapshot.recentBudgetSamples.map(\.durationMilliseconds) == [80, 260])
    #expect(snapshot.recentBudgetSamples.map(\.status) == ["within_budget", "over_budget"])
    #expect(snapshot.recentBudgetSamples.map(\.source) == ["third", "second"])
}
