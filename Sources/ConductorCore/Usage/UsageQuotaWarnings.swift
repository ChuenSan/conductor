import Foundation

/// Quota-warning windows shared by config, notification state, and tests.
public enum QuotaWarningWindow: String, Codable, CaseIterable, Hashable, Sendable {
    case session
    case weekly

    public var fallbackTitle: String {
        switch self {
        case .session: L("会话")
        case .weekly: L("本周")
        }
    }
}

public enum QuotaWarningThresholds {
    public static let defaults = [50, 20]
    public static let allowedRange = 0...99

    public static func sanitized(_ raw: [Int]?) -> [Int] {
        let cleaned = Set(
            (raw ?? defaults)
            .map { min(max($0, allowedRange.lowerBound), allowedRange.upperBound) }
        )
            .sorted(by: >)
        return cleaned.isEmpty ? defaults : cleaned
    }

    public static func active(_ raw: [Int]?) -> [Int] {
        sanitized(raw).filter { $0 > 0 }
    }
}

public struct QuotaWarningWindowConfig: Codable, Equatable, Sendable {
    public var thresholds: [Int]?
    public var enabled: Bool?

    public init(thresholds: [Int]? = nil, enabled: Bool? = nil) {
        self.thresholds = thresholds
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thresholds = try? c.decodeIfPresent([Int].self, forKey: .thresholds)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
    }

    public func validated() -> QuotaWarningWindowConfig? {
        let cleanThresholds = thresholds.map(QuotaWarningThresholds.sanitized)
        let hasThresholdOverride = cleanThresholds != nil
        guard enabled != nil || hasThresholdOverride else { return nil }
        return QuotaWarningWindowConfig(thresholds: cleanThresholds, enabled: enabled)
    }

    public var hasOverride: Bool {
        enabled != nil || thresholds != nil
    }

    public func isEnabled(global: Bool) -> Bool {
        enabled ?? (thresholds != nil ? true : global)
    }

    public func thresholds(global: [Int]) -> [Int] {
        QuotaWarningThresholds.active(thresholds ?? global)
    }
}

public struct QuotaWarningConfig: Codable, Equatable, Sendable {
    public var enabled: Bool?
    public var soundEnabled: Bool?
    public var session: QuotaWarningWindowConfig?
    public var weekly: QuotaWarningWindowConfig?

    public init(
        enabled: Bool? = nil,
        soundEnabled: Bool? = nil,
        session: QuotaWarningWindowConfig? = nil,
        weekly: QuotaWarningWindowConfig? = nil)
    {
        self.enabled = enabled
        self.soundEnabled = soundEnabled
        self.session = session
        self.weekly = weekly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        soundEnabled = try? c.decodeIfPresent(Bool.self, forKey: .soundEnabled)
        session = try? c.decodeIfPresent(QuotaWarningWindowConfig.self, forKey: .session)
        weekly = try? c.decodeIfPresent(QuotaWarningWindowConfig.self, forKey: .weekly)
    }

    public func validated() -> QuotaWarningConfig {
        QuotaWarningConfig(
            enabled: enabled,
            soundEnabled: soundEnabled,
            session: session?.validated(),
            weekly: weekly?.validated())
    }

    public var isEmpty: Bool {
        enabled == nil && soundEnabled == nil && session == nil && weekly == nil
    }

    public func windowConfig(for window: QuotaWarningWindow) -> QuotaWarningWindowConfig? {
        switch window {
        case .session: session
        case .weekly: weekly
        }
    }
}

public struct QuotaWarningResolvedPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var thresholds: [Int]
    public var soundEnabled: Bool

    public init(enabled: Bool, thresholds: [Int], soundEnabled: Bool = true) {
        self.enabled = enabled
        self.thresholds = thresholds
        self.soundEnabled = soundEnabled
    }
}

public enum QuotaWarningPolicyResolver {
    public static func resolve(
        global: QuotaWarningConfig,
        provider: QuotaWarningConfig?,
        window: QuotaWarningWindow
    ) -> QuotaWarningResolvedPolicy {
        if provider?.enabled == false {
            return QuotaWarningResolvedPolicy(enabled: false, thresholds: [], soundEnabled: false)
        }

        let globalEnabled = global.enabled ?? false
        if !globalEnabled && provider?.enabled != true {
            return QuotaWarningResolvedPolicy(enabled: false, thresholds: [], soundEnabled: false)
        }

        let globalWindow = global.windowConfig(for: window)
        let providerWindow = provider?.windowConfig(for: window)
        let baseEnabled = provider?.enabled ?? globalEnabled
        let globalWindowEnabled = globalWindow?.isEnabled(global: baseEnabled) ?? baseEnabled
        let enabled = providerWindow?.isEnabled(global: globalWindowEnabled) ?? globalWindowEnabled

        let globalThresholds = globalWindow?.thresholds(global: QuotaWarningThresholds.defaults)
            ?? QuotaWarningThresholds.active(QuotaWarningThresholds.defaults)
        let thresholds = providerWindow?.thresholds(global: globalThresholds) ?? globalThresholds
        let soundEnabled = provider?.soundEnabled ?? global.soundEnabled ?? true

        return QuotaWarningResolvedPolicy(
            enabled: enabled && !thresholds.isEmpty,
            thresholds: thresholds,
            soundEnabled: soundEnabled)
    }
}

public struct QuotaWarningState: Codable, Equatable, Sendable {
    public var lastRemaining: Double?
    public var firedThresholds: Set<Int>

    public init(lastRemaining: Double? = nil, firedThresholds: Set<Int> = []) {
        self.lastRemaining = lastRemaining
        self.firedThresholds = firedThresholds
    }
}

public struct QuotaWarningEvent: Equatable, Sendable {
    public var providerID: String
    public var providerName: String
    public var window: QuotaWarningWindow
    public var windowTitle: String
    public var threshold: Int
    public var currentRemaining: Double
    public var accountLabel: String?

    public init(
        providerID: String,
        providerName: String,
        window: QuotaWarningWindow,
        windowTitle: String,
        threshold: Int,
        currentRemaining: Double,
        accountLabel: String? = nil)
    {
        self.providerID = providerID
        self.providerName = providerName
        self.window = window
        self.windowTitle = windowTitle
        self.threshold = threshold
        self.currentRemaining = currentRemaining
        self.accountLabel = accountLabel
    }
}

public enum QuotaWarningNotificationLogic {
    public static func crossedThreshold(
        previousRemaining: Double?,
        currentRemaining: Double,
        thresholds: [Int],
        alreadyFired: Set<Int>
    ) -> Int? {
        let active = QuotaWarningThresholds.active(thresholds)
        let eligible = active.filter { threshold in
            currentRemaining <= Double(threshold) && !alreadyFired.contains(threshold)
        }
        guard !eligible.isEmpty else { return nil }

        if let previousRemaining {
            let crossed = eligible.filter { previousRemaining > Double($0) }
            return crossed.min()
        }
        return eligible.min()
    }

    public static func firedThresholdsAfterWarning(threshold: Int, thresholds: [Int]) -> Set<Int> {
        Set(QuotaWarningThresholds.active(thresholds).filter { $0 >= threshold })
    }

    public static func thresholdsToClear(
        currentRemaining: Double,
        alreadyFired: Set<Int>
    ) -> Set<Int> {
        Set(alreadyFired.filter { currentRemaining > Double($0) })
    }
}

public enum UsageQuotaWarningEvaluator {
    public static func window(_ window: QuotaWarningWindow, in snapshot: UsageSnapshot) -> RateWindow? {
        switch window {
        case .session: snapshot.primary
        case .weekly: snapshot.secondary
        }
    }

    public static func evaluate(
        providerID: String,
        providerName: String,
        snapshot: UsageSnapshot,
        window: QuotaWarningWindow,
        policy: QuotaWarningResolvedPolicy,
        previous state: QuotaWarningState?
    ) -> (state: QuotaWarningState?, event: QuotaWarningEvent?) {
        guard policy.enabled, let rateWindow = Self.window(window, in: snapshot) else {
            return (nil, nil)
        }

        let currentRemaining = rateWindow.remainingPercent
        var nextState = state ?? QuotaWarningState()
        nextState.firedThresholds.subtract(
            QuotaWarningNotificationLogic.thresholdsToClear(
                currentRemaining: currentRemaining,
                alreadyFired: nextState.firedThresholds))

        let threshold = QuotaWarningNotificationLogic.crossedThreshold(
            previousRemaining: nextState.lastRemaining,
            currentRemaining: currentRemaining,
            thresholds: policy.thresholds,
            alreadyFired: nextState.firedThresholds)

        nextState.lastRemaining = currentRemaining

        guard let threshold else {
            return (nextState, nil)
        }

        nextState.firedThresholds.formUnion(
            QuotaWarningNotificationLogic.firedThresholdsAfterWarning(
                threshold: threshold,
                thresholds: policy.thresholds))

        let event = QuotaWarningEvent(
            providerID: providerID,
            providerName: providerName,
            window: window,
            windowTitle: rateWindow.title ?? window.fallbackTitle,
            threshold: threshold,
            currentRemaining: currentRemaining,
            accountLabel: Self.nonEmpty(snapshot.accountLabel))
        return (nextState, event)
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
