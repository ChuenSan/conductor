import Foundation

public struct UsagePace: Sendable, Equatable {
    public enum Stage: String, Codable, Sendable, Equatable {
        case onTrack
        case slightlyAhead
        case ahead
        case farAhead
        case slightlyBehind
        case behind
        case farBehind
    }

    public let stage: Stage
    public let deltaPercent: Double
    public let expectedUsedPercent: Double
    public let actualUsedPercent: Double
    public let etaSeconds: TimeInterval?
    public let willLastToReset: Bool
    public let runOutProbability: Double?

    public init(
        stage: Stage,
        deltaPercent: Double,
        expectedUsedPercent: Double,
        actualUsedPercent: Double,
        etaSeconds: TimeInterval?,
        willLastToReset: Bool,
        runOutProbability: Double? = nil)
    {
        self.stage = stage
        self.deltaPercent = deltaPercent
        self.expectedUsedPercent = expectedUsedPercent
        self.actualUsedPercent = actualUsedPercent
        self.etaSeconds = etaSeconds
        self.willLastToReset = willLastToReset
        self.runOutProbability = runOutProbability
    }

    public var isDeficit: Bool {
        switch stage {
        case .slightlyAhead, .ahead, .farAhead: return true
        default: return false
        }
    }

    public var isReserve: Bool {
        switch stage {
        case .slightlyBehind, .behind, .farBehind: return true
        default: return false
        }
    }

    public static func window(
        _ window: RateWindow,
        now: Date = Date(),
        defaultWindowMinutes: Int? = nil,
        minimumExpectedUsedPercent: Double = 3
    ) -> UsagePace? {
        guard let resetsAt = window.resetsAt else { return nil }
        let minutes = window.windowMinutes ?? defaultWindowMinutes
        guard let minutes, minutes > 0 else { return nil }

        let duration = TimeInterval(minutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let elapsed = clamp(duration - timeUntilReset, lower: 0, upper: duration)
        let expected = clamp((elapsed / duration) * 100, lower: 0, upper: 100)
        guard expected >= minimumExpectedUsedPercent else { return nil }

        let actual = clamp(window.usedPercent, lower: 0, upper: 100)
        let delta = actual - expected
        let stage = stage(for: delta)

        var etaSeconds: TimeInterval?
        var willLastToReset = false
        if actual >= 100 {
            etaSeconds = 0
        } else if elapsed > 0, actual > 0 {
            let rate = actual / elapsed
            let candidate = (100 - actual) / rate
            if candidate >= timeUntilReset {
                willLastToReset = true
            } else {
                etaSeconds = max(0, candidate)
            }
        } else if elapsed > 0 {
            willLastToReset = true
        }

        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset)
    }

    public static func historical(
        expectedUsedPercent: Double,
        actualUsedPercent: Double,
        etaSeconds: TimeInterval?,
        willLastToReset: Bool,
        runOutProbability: Double?)
        -> UsagePace
    {
        let expected = clamp(expectedUsedPercent, lower: 0, upper: 100)
        let actual = clamp(actualUsedPercent, lower: 0, upper: 100)
        let delta = actual - expected
        return UsagePace(
            stage: stage(for: delta),
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: runOutProbability)
    }

    public static func weekly(
        window: RateWindow,
        now: Date = Date(),
        defaultWindowMinutes: Int = 10080,
        workDays: Int? = nil,
        minimumExpectedUsedPercent: Double = 3,
        calendar: Calendar = .current
    ) -> UsagePace? {
        guard let resetsAt = window.resetsAt else { return nil }
        let minutes = window.windowMinutes ?? defaultWindowMinutes
        guard minutes > 0 else { return nil }

        let duration = TimeInterval(minutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let elapsed = clamp(duration - timeUntilReset, lower: 0, upper: duration)
        let workdayProgress: WorkdayProgress? = if let workDays,
                                                   workDays >= 2,
                                                   workDays < 7,
                                                   minutes == 10080
        {
            workdayProgress(
                now: now,
                duration: duration,
                resetsAt: resetsAt,
                workDays: workDays,
                calendar: calendar)
        } else {
            nil
        }

        let expected = workdayProgress?.expectedUsedPercent
            ?? clamp((elapsed / duration) * 100, lower: 0, upper: 100)
        guard expected >= minimumExpectedUsedPercent else { return nil }

        let actual = clamp(window.usedPercent, lower: 0, upper: 100)
        if elapsed == 0, actual > 0 { return nil }
        let delta = actual - expected
        let stage = stage(for: delta)

        var etaSeconds: TimeInterval?
        var willLastToReset = false
        let paceElapsed = workdayProgress?.elapsedSeconds ?? elapsed
        if actual >= 100 {
            etaSeconds = 0
        } else if paceElapsed > 0, actual > 0 {
            let rate = actual / paceElapsed
            if rate > 0 {
                let candidate = (100 - actual) / rate
                let effectiveTimeUntilReset = workdayProgress?.remainingSeconds ?? timeUntilReset
                if candidate >= effectiveTimeUntilReset {
                    willLastToReset = true
                } else if let workDays = workdayProgress?.workDays {
                    etaSeconds = wallClockInterval(
                        from: now,
                        to: resetsAt,
                        consumingWorkSeconds: candidate,
                        workDays: workDays,
                        calendar: calendar)
                } else {
                    etaSeconds = max(0, candidate)
                }
            }
        } else if paceElapsed > 0 {
            willLastToReset = true
        }

        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            expectedUsedPercent: expected,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset)
    }

    public func summary(now: Date = Date()) -> UsagePaceSummary {
        let delta = Int(abs(deltaPercent).rounded())
        let leftLabel: String = switch stage {
        case .onTrack:
            L("节奏正常")
        case .slightlyAhead, .ahead, .farAhead:
            L("%ld%% 透支", delta)
        case .slightlyBehind, .behind, .farBehind:
            L("%ld%% 余量", delta)
        }

        let rightLabel: String? = if willLastToReset {
            L("可撑到重置")
        } else if let etaSeconds {
            etaSeconds <= 1 ? L("即将用尽") : L("%@ 后用尽", Self.durationText(seconds: etaSeconds))
        } else {
            nil
        }

        let expected = L("预期已用 %ld%%", Int(expectedUsedPercent.rounded()))
        let detail = [leftLabel, rightLabel, expected]
            .compactMap { $0 }
            .joined(separator: " · ")
        return UsagePaceSummary(
            stage: stage,
            label: leftLabel,
            detail: detail,
            expectedUsedPercent: expectedUsedPercent,
            deltaPercent: deltaPercent,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: runOutProbability)
    }

    public static func summary(
        window: RateWindow,
        now: Date = Date(),
        defaultWindowMinutes: Int? = nil,
        minimumExpectedUsedPercent: Double = 3,
        weeklyProgressWorkDays: Int? = nil
    ) -> UsagePaceSummary? {
        let normalizedWorkDays = UsageConfig.normalizedWeeklyProgressWorkDays(weeklyProgressWorkDays)
        let pace: UsagePace?
        if normalizedWorkDays != nil,
           (window.windowMinutes ?? defaultWindowMinutes) == 10080
        {
            pace = self.weekly(
                window: window,
                now: now,
                defaultWindowMinutes: defaultWindowMinutes ?? 10080,
                workDays: normalizedWorkDays,
                minimumExpectedUsedPercent: minimumExpectedUsedPercent)
        } else {
            pace = self.window(
                window,
                now: now,
                defaultWindowMinutes: defaultWindowMinutes,
                minimumExpectedUsedPercent: minimumExpectedUsedPercent)
        }
        return pace?.summary(now: now)
    }

    public static func workDayMarkerPercents(workDays: Int?, windowMinutes: Int?) -> [Double] {
        guard windowMinutes == 10080,
              let workDays = UsageConfig.normalizedWeeklyProgressWorkDays(workDays),
              workDays >= 2
        else { return [] }
        return (1..<workDays).map { Double($0) * 100.0 / Double(workDays) }
    }

    private struct WorkdayProgress {
        let workDays: Int
        let totalSeconds: TimeInterval
        let elapsedSeconds: TimeInterval
        let remainingSeconds: TimeInterval

        var expectedUsedPercent: Double {
            clamp((elapsedSeconds / totalSeconds) * 100, lower: 0, upper: 100)
        }
    }

    private static func workdayProgress(
        now: Date,
        duration: TimeInterval,
        resetsAt: Date,
        workDays: Int,
        calendar: Calendar
    ) -> WorkdayProgress? {
        let windowStart = resetsAt.addingTimeInterval(-duration)
        var totalWorkSeconds: TimeInterval = 0
        var elapsedWorkSeconds: TimeInterval = 0
        var remainingWorkSeconds: TimeInterval = 0

        var cursor = windowStart
        while cursor < resetsAt {
            guard let startOfNextDay = nextDayBoundary(after: cursor, calendar: calendar),
                  startOfNextDay > cursor
            else { return nil }

            let sliceEnd = min(startOfNextDay, resetsAt)
            if isWorkday(cursor, calendar: calendar, workDays: workDays) {
                let sliceDuration = sliceEnd.timeIntervalSince(cursor)
                totalWorkSeconds += sliceDuration
                if now > cursor {
                    elapsedWorkSeconds += min(now, sliceEnd).timeIntervalSince(cursor)
                }
                if now < sliceEnd {
                    remainingWorkSeconds += sliceEnd.timeIntervalSince(max(now, cursor))
                }
            }
            cursor = sliceEnd
        }

        guard totalWorkSeconds > 0 else { return nil }
        return WorkdayProgress(
            workDays: workDays,
            totalSeconds: totalWorkSeconds,
            elapsedSeconds: elapsedWorkSeconds,
            remainingSeconds: remainingWorkSeconds)
    }

    private static func wallClockInterval(
        from now: Date,
        to resetsAt: Date,
        consumingWorkSeconds requiredWorkSeconds: TimeInterval,
        workDays: Int,
        calendar: Calendar
    ) -> TimeInterval? {
        guard requiredWorkSeconds > 0 else { return 0 }

        var remaining = requiredWorkSeconds
        var cursor = now
        while cursor < resetsAt {
            guard let startOfNextDay = nextDayBoundary(after: cursor, calendar: calendar),
                  startOfNextDay > cursor
            else { return nil }

            let sliceEnd = min(startOfNextDay, resetsAt)
            if isWorkday(cursor, calendar: calendar, workDays: workDays) {
                let available = sliceEnd.timeIntervalSince(cursor)
                if remaining <= available {
                    return cursor.addingTimeInterval(remaining).timeIntervalSince(now)
                }
                remaining -= available
            }
            cursor = sliceEnd
        }
        return nil
    }

    private static func nextDayBoundary(after date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))
    }

    private static func isWorkday(_ date: Date, calendar: Calendar, workDays: Int) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        return isoWeekday <= workDays
    }

    private static func stage(for delta: Double) -> Stage {
        let absDelta = abs(delta)
        if absDelta <= 2 { return .onTrack }
        if absDelta <= 6 { return delta >= 0 ? .slightlyAhead : .slightlyBehind }
        if absDelta <= 12 { return delta >= 0 ? .ahead : .behind }
        return delta >= 0 ? .farAhead : .farBehind
    }

    private static func durationText(seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        if minutes < 1 { return L("不到 1 分钟") }
        if minutes < 60 { return L("%ld 分钟", minutes) }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if hours < 24 {
            return remMinutes > 0 ? L("%1$ld 小时 %2$ld 分钟", hours, remMinutes) : L("%ld 小时", hours)
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? L("%1$ld 天 %2$ld 小时", days, remHours) : L("%ld 天", days)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}

public struct UsagePaceSummary: Codable, Sendable, Equatable {
    public let stage: UsagePace.Stage
    public let label: String
    public let detail: String
    public let expectedUsedPercent: Double
    public let deltaPercent: Double
    public let etaSeconds: TimeInterval?
    public let willLastToReset: Bool
    public let runOutProbability: Double?

    public var isDeficit: Bool {
        switch stage {
        case .slightlyAhead, .ahead, .farAhead: return true
        default: return false
        }
    }

    public var isReserve: Bool {
        switch stage {
        case .slightlyBehind, .behind, .farBehind: return true
        default: return false
        }
    }
}
