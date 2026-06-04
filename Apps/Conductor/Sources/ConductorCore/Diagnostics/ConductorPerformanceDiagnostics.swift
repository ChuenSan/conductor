import Foundation

public struct ConductorPerformanceBudget: Equatable, Sendable {
    public var id: String
    public var name: String
    public var targetMilliseconds: Int
    public var measurement: String

    public init(
        id: String,
        name: String,
        targetMilliseconds: Int,
        measurement: String
    ) {
        self.id = id
        self.name = name
        self.targetMilliseconds = targetMilliseconds
        self.measurement = measurement
    }
}

public struct ConductorMainThreadStallRecord: Equatable, Sendable {
    public var timestamp: Date
    public var durationMilliseconds: Int
    public var thresholdMilliseconds: Int

    public init(
        timestamp: Date,
        durationMilliseconds: Int,
        thresholdMilliseconds: Int
    ) {
        self.timestamp = timestamp
        self.durationMilliseconds = durationMilliseconds
        self.thresholdMilliseconds = thresholdMilliseconds
    }
}

public struct ConductorPerformanceBudgetSample: Equatable, Sendable {
    public var timestamp: Date
    public var budgetID: String
    public var name: String
    public var durationMilliseconds: Int
    public var targetMilliseconds: Int
    public var status: String
    public var source: String

    public init(
        timestamp: Date,
        budgetID: String,
        name: String,
        durationMilliseconds: Int,
        targetMilliseconds: Int,
        status: String,
        source: String
    ) {
        self.timestamp = timestamp
        self.budgetID = budgetID
        self.name = name
        self.durationMilliseconds = durationMilliseconds
        self.targetMilliseconds = targetMilliseconds
        self.status = status
        self.source = source
    }
}

public struct ConductorPerformanceDiagnosticsSnapshot: Equatable, Sendable {
    public var budgets: [ConductorPerformanceBudget]
    public var recentMainThreadStalls: [ConductorMainThreadStallRecord]
    public var recentBudgetSamples: [ConductorPerformanceBudgetSample]

    public init(
        budgets: [ConductorPerformanceBudget],
        recentMainThreadStalls: [ConductorMainThreadStallRecord],
        recentBudgetSamples: [ConductorPerformanceBudgetSample]
    ) {
        self.budgets = budgets
        self.recentMainThreadStalls = recentMainThreadStalls
        self.recentBudgetSamples = recentBudgetSamples
    }
}

public final class ConductorPerformanceDiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var mainThreadStalls: [ConductorMainThreadStallRecord] = []
    private var budgetSamples: [ConductorPerformanceBudgetSample] = []

    public init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    @discardableResult
    public func recordMainThreadStall(
        timestamp: Date = Date(),
        durationNanoseconds: UInt64,
        thresholdNanoseconds: UInt64
    ) -> ConductorMainThreadStallRecord {
        let record = ConductorMainThreadStallRecord(
            timestamp: timestamp,
            durationMilliseconds: Self.milliseconds(fromNanoseconds: durationNanoseconds),
            thresholdMilliseconds: Self.milliseconds(fromNanoseconds: thresholdNanoseconds)
        )

        lock.lock()
        mainThreadStalls.append(record)
        if mainThreadStalls.count > capacity {
            mainThreadStalls.removeFirst(mainThreadStalls.count - capacity)
        }
        lock.unlock()
        return record
    }

    @discardableResult
    public func recordBudgetSample(
        timestamp: Date = Date(),
        budgetID: String,
        durationNanoseconds: UInt64,
        source: String,
        budgets: [ConductorPerformanceBudget] = ConductorPerformanceDiagnostics.defaultBudgets
    ) -> ConductorPerformanceBudgetSample? {
        guard let budget = budgets.first(where: { $0.id == budgetID }) else {
            return nil
        }
        return recordBudgetSample(
            timestamp: timestamp,
            budget: budget,
            durationNanoseconds: durationNanoseconds,
            source: source
        )
    }

    @discardableResult
    public func recordBudgetSample(
        timestamp: Date = Date(),
        budget: ConductorPerformanceBudget,
        durationNanoseconds: UInt64,
        source: String
    ) -> ConductorPerformanceBudgetSample {
        let durationMilliseconds = Self.milliseconds(fromNanoseconds: durationNanoseconds)
        let sample = ConductorPerformanceBudgetSample(
            timestamp: timestamp,
            budgetID: budget.id,
            name: budget.name,
            durationMilliseconds: durationMilliseconds,
            targetMilliseconds: budget.targetMilliseconds,
            status: durationMilliseconds <= budget.targetMilliseconds ? "within_budget" : "over_budget",
            source: source
        )

        lock.lock()
        budgetSamples.append(sample)
        if budgetSamples.count > capacity {
            budgetSamples.removeFirst(budgetSamples.count - capacity)
        }
        lock.unlock()
        return sample
    }

    public func removeAll() {
        lock.lock()
        mainThreadStalls.removeAll()
        budgetSamples.removeAll()
        lock.unlock()
    }

    public func snapshot(
        budgets: [ConductorPerformanceBudget] = ConductorPerformanceDiagnostics.defaultBudgets
    ) -> ConductorPerformanceDiagnosticsSnapshot {
        lock.lock()
        let stalls = Array(mainThreadStalls.reversed())
        let samples = Array(budgetSamples.reversed())
        lock.unlock()
        return ConductorPerformanceDiagnosticsSnapshot(
            budgets: budgets,
            recentMainThreadStalls: stalls,
            recentBudgetSamples: samples
        )
    }

    private static func milliseconds(fromNanoseconds nanoseconds: UInt64) -> Int {
        let milliseconds = nanoseconds / 1_000_000
        return Int(min(milliseconds, UInt64(Int.max)))
    }
}

public enum ConductorPerformanceDiagnostics {
    public static let shared = ConductorPerformanceDiagnosticsStore()

    public static let defaultBudgets: [ConductorPerformanceBudget] = [
        ConductorPerformanceBudget(
            id: "settings.open",
            name: "Settings open",
            targetMilliseconds: 250,
            measurement: "Warm app, command to visible settings panel."
        ),
        ConductorPerformanceBudget(
            id: "command-palette.open",
            name: "Command palette open",
            targetMilliseconds: 120,
            measurement: "Keyboard shortcut to focused search field."
        ),
        ConductorPerformanceBudget(
            id: "workspace.switch",
            name: "Workspace switch",
            targetMilliseconds: 150,
            measurement: "Tab click to selected workspace content stable."
        ),
        ConductorPerformanceBudget(
            id: "terminal.tab-switch",
            name: "Terminal tab switch",
            targetMilliseconds: 80,
            measurement: "Terminal tab click to focused terminal surface."
        ),
        ConductorPerformanceBudget(
            id: "terminal.scroll-frame",
            name: "Terminal scroll frame",
            targetMilliseconds: 16,
            measurement: "Per-frame budget during continuous terminal scrolling."
        ),
        ConductorPerformanceBudget(
            id: "update.check",
            name: "Update check",
            targetMilliseconds: 1_500,
            measurement: "Manual or background update check to settled status."
        ),
        ConductorPerformanceBudget(
            id: "browser.open",
            name: "Browser tab open",
            targetMilliseconds: 500,
            measurement: "Browser tab issuing load."
        )
    ]
}
