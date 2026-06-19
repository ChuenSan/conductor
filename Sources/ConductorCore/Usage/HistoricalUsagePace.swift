import Foundation

public enum HistoricalUsageWindowKind: String, Codable, Sendable {
    case secondary
}

public enum HistoricalUsageRecordSource: String, Codable, Sendable {
    case live
    case backfill
}

public struct HistoricalUsageRecord: Codable, Equatable, Sendable {
    public let version: Int
    public let providerID: String
    public let windowKind: HistoricalUsageWindowKind
    public let source: HistoricalUsageRecordSource
    public let accountKey: String?
    public let sampledAt: Date
    public let usedPercent: Double
    public let resetsAt: Date
    public let windowMinutes: Int

    public init(
        version: Int = 1,
        providerID: String,
        windowKind: HistoricalUsageWindowKind,
        source: HistoricalUsageRecordSource,
        accountKey: String?,
        sampledAt: Date,
        usedPercent: Double,
        resetsAt: Date,
        windowMinutes: Int)
    {
        self.version = version
        self.providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.windowKind = windowKind
        self.source = source
        self.accountKey = accountKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sampledAt = sampledAt
        self.usedPercent = min(100, max(0, usedPercent))
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
    }
}

public struct HistoricalWeekProfile: Codable, Equatable, Sendable {
    public let resetsAt: Date
    public let windowMinutes: Int
    public let curve: [Double]

    public init(resetsAt: Date, windowMinutes: Int, curve: [Double]) {
        self.resetsAt = resetsAt
        self.windowMinutes = windowMinutes
        self.curve = curve
    }
}

public struct CodexHistoricalDataset: Codable, Equatable, Sendable {
    public static let gridPointCount = 169

    public let weeks: [HistoricalWeekProfile]

    public init(weeks: [HistoricalWeekProfile]) {
        self.weeks = weeks
    }
}

public actor HistoricalUsageHistoryStore {
    private static let schemaVersion = 1
    private static let writeInterval: TimeInterval = 30 * 60
    private static let writeDeltaThreshold: Double = 1
    private static let retentionDays: TimeInterval = 56 * 24 * 60 * 60
    private static let minimumWeekSamples = 6
    private static let boundaryCoverageWindow: TimeInterval = 24 * 60 * 60
    private static let backfillWindowCapWeeks = 8
    private static let backfillCalibrationMinimumUsedPercent = 1.0
    private static let backfillCalibrationMinimumCredits = 0.001
    private static let backfillSampleFractions: [Double] = (0...14).map { Double($0) / 14.0 }
    private static let coverageTolerance: TimeInterval = 16 * 60 * 60
    private static let resetBucketSeconds: TimeInterval = 5 * 60

    private let fileURL: URL
    private var records: [HistoricalUsageRecord] = []
    private var loaded = false

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public func loadCodexDataset(accountKey: String?) -> CodexHistoricalDataset? {
        self.ensureLoaded()
        return self.buildCodexDataset(accountKey: normalizedAccountKey(accountKey))
    }

    public func recordCodexWeekly(
        window: RateWindow,
        sampledAt: Date = Date(),
        accountKey: String?)
        -> CodexHistoricalDataset?
    {
        let normalizedKey = normalizedAccountKey(accountKey)
        guard let rawResetsAt = window.resetsAt,
              let windowMinutes = window.windowMinutes,
              windowMinutes > 0
        else {
            return self.loadCodexDataset(accountKey: normalizedKey)
        }

        self.ensureLoaded()
        let resetsAt = Self.normalizeReset(rawResetsAt)
        let sample = HistoricalUsageRecord(
            version: Self.schemaVersion,
            providerID: "codex",
            windowKind: .secondary,
            source: .live,
            accountKey: normalizedKey,
            sampledAt: sampledAt,
            usedPercent: window.usedPercent,
            resetsAt: resetsAt,
            windowMinutes: windowMinutes)

        guard self.shouldAccept(sample) else {
            return self.buildCodexDataset(accountKey: normalizedKey)
        }

        self.records.append(sample)
        self.normalizeRecords(now: sampledAt)
        self.persist()
        return self.buildCodexDataset(accountKey: normalizedKey)
    }

    public func backfillCodexWeeklyFromUsageBreakdown(
        _ breakdown: [OpenAIDashboardDailyBreakdown],
        referenceWindow: RateWindow,
        now: Date = Date(),
        accountKey: String?)
        -> CodexHistoricalDataset?
    {
        let normalizedKey = normalizedAccountKey(accountKey)
        self.ensureLoaded()
        let existingDataset = self.buildCodexDataset(accountKey: normalizedKey)

        guard let rawResetsAt = referenceWindow.resetsAt,
              let windowMinutes = referenceWindow.windowMinutes,
              windowMinutes > 0
        else {
            return existingDataset
        }

        let resetsAt = Self.normalizeReset(rawResetsAt)
        let duration = TimeInterval(windowMinutes) * 60
        guard duration > 0 else { return existingDataset }

        let windowStart = resetsAt.addingTimeInterval(-duration)
        let calibrationEnd = Self.clampDate(now, lower: windowStart, upper: resetsAt)
        let dayUsages = Self.parseDayUsages(
            from: OpenAIDashboardDailyBreakdown.removingSkillUsageServices(from: breakdown),
            asOf: calibrationEnd,
            fillingFrom: windowStart)
        guard let coverageStart = dayUsages.first?.start,
              let coverageEnd = dayUsages.last?.end
        else {
            return existingDataset
        }
        guard coverageStart <= windowStart.addingTimeInterval(Self.coverageTolerance) else {
            return existingDataset
        }
        guard coverageEnd >= calibrationEnd.addingTimeInterval(-Self.coverageTolerance) else {
            return existingDataset
        }

        let currentUsedPercent = Self.clamp(referenceWindow.usedPercent, lower: 0, upper: 100)
        guard currentUsedPercent >= Self.backfillCalibrationMinimumUsedPercent else { return existingDataset }

        let currentCredits = Self.creditsUsed(from: dayUsages, between: windowStart, and: calibrationEnd)
        guard currentCredits > Self.backfillCalibrationMinimumCredits else { return existingDataset }

        let estimatedCreditsAtLimit = currentCredits / (currentUsedPercent / 100)
        guard estimatedCreditsAtLimit.isFinite,
              estimatedCreditsAtLimit > Self.backfillCalibrationMinimumCredits
        else {
            return existingDataset
        }

        struct RecordKey: Hashable {
            let resetsAt: Date
            let sampledAt: Date
            let windowMinutes: Int
            let accountKey: String?
        }

        var synthesized: [HistoricalUsageRecord] = []
        synthesized.reserveCapacity(Self.backfillWindowCapWeeks * Self.backfillSampleFractions.count)

        for weeksBack in 1...Self.backfillWindowCapWeeks {
            let reset = Self.normalizeReset(resetsAt.addingTimeInterval(-duration * Double(weeksBack)))
            let start = reset.addingTimeInterval(-duration)
            guard start >= coverageStart.addingTimeInterval(-Self.coverageTolerance),
                  reset <= coverageEnd.addingTimeInterval(Self.coverageTolerance)
            else {
                continue
            }

            let existingForWeek = self.records.filter {
                $0.providerID == "codex" &&
                    $0.windowKind == .secondary &&
                    $0.windowMinutes == windowMinutes &&
                    $0.accountKey == normalizedKey &&
                    $0.resetsAt == reset
            }
            if Self.isCompleteWeek(samples: existingForWeek, windowStart: start, resetsAt: reset) {
                continue
            }

            var existingRecordKeys = Set(existingForWeek.map {
                RecordKey(
                    resetsAt: $0.resetsAt,
                    sampledAt: $0.sampledAt,
                    windowMinutes: $0.windowMinutes,
                    accountKey: $0.accountKey)
            })

            let weekCredits = Self.creditsUsed(from: dayUsages, between: start, and: reset)
            guard weekCredits > Self.backfillCalibrationMinimumCredits else { continue }

            for fraction in Self.backfillSampleFractions {
                let sampledAt = start.addingTimeInterval(duration * fraction)
                let recordKey = RecordKey(
                    resetsAt: reset,
                    sampledAt: sampledAt,
                    windowMinutes: windowMinutes,
                    accountKey: normalizedKey)
                guard !existingRecordKeys.contains(recordKey) else { continue }
                let cumulativeCredits = Self.creditsUsed(from: dayUsages, between: start, and: sampledAt)
                let usedPercent = Self.clamp(
                    (cumulativeCredits / estimatedCreditsAtLimit) * 100,
                    lower: 0,
                    upper: 100)
                synthesized.append(HistoricalUsageRecord(
                    version: Self.schemaVersion,
                    providerID: "codex",
                    windowKind: .secondary,
                    source: .backfill,
                    accountKey: normalizedKey,
                    sampledAt: sampledAt,
                    usedPercent: usedPercent,
                    resetsAt: reset,
                    windowMinutes: windowMinutes))
                existingRecordKeys.insert(recordKey)
            }
        }

        guard !synthesized.isEmpty else { return existingDataset }
        self.records.append(contentsOf: synthesized)
        self.normalizeRecords(now: now)
        self.persist()
        return self.buildCodexDataset(accountKey: normalizedKey)
    }

    public nonisolated static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return root
            .appendingPathComponent("conductor", isDirectory: true)
            .appendingPathComponent("codex-historical-usage.jsonl")
    }

    private func shouldAccept(_ sample: HistoricalUsageRecord) -> Bool {
        guard let prior = self.records.last(where: {
            $0.providerID == sample.providerID &&
                $0.windowKind == sample.windowKind &&
                $0.accountKey == sample.accountKey &&
                $0.windowMinutes == sample.windowMinutes
        }) else {
            return true
        }

        if prior.resetsAt != sample.resetsAt { return true }
        if sample.sampledAt.timeIntervalSince(prior.sampledAt) >= Self.writeInterval { return true }
        if abs(sample.usedPercent - prior.usedPercent) >= Self.writeDeltaThreshold { return true }
        return false
    }

    private func ensureLoaded() {
        guard !self.loaded else { return }
        self.loaded = true
        self.records = self.readRecordsFromDisk()
        self.normalizeRecords(now: Date())
    }

    private func readRecordsFromDisk() -> [HistoricalUsageRecord] {
        guard let data = try? Data(contentsOf: self.fileURL),
              !data.isEmpty,
              let text = String(data: data, encoding: .utf8)
        else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var decoded: [HistoricalUsageRecord] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? decoder.decode(HistoricalUsageRecord.self, from: lineData)
            else {
                continue
            }
            decoded.append(HistoricalUsageRecord(
                version: record.version,
                providerID: record.providerID,
                windowKind: record.windowKind,
                source: record.source,
                accountKey: normalizedAccountKey(record.accountKey),
                sampledAt: record.sampledAt,
                usedPercent: record.usedPercent,
                resetsAt: Self.normalizeReset(record.resetsAt),
                windowMinutes: record.windowMinutes))
        }
        return decoded
    }

    private func normalizeRecords(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retentionDays)
        self.records.removeAll { $0.sampledAt < cutoff }
        self.records.sort { lhs, rhs in
            if lhs.sampledAt != rhs.sampledAt { return lhs.sampledAt < rhs.sampledAt }
            if lhs.resetsAt != rhs.resetsAt { return lhs.resetsAt < rhs.resetsAt }
            return lhs.usedPercent < rhs.usedPercent
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let lines = self.records.compactMap { record -> String? in
            guard let data = try? encoder.encode(record) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let payload = (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
        do {
            try FileManager.default.createDirectory(
                at: self.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try payload.write(to: self.fileURL, options: [.atomic])
        } catch {
        }
    }

    private func buildCodexDataset(accountKey: String?) -> CodexHistoricalDataset? {
        let scoped = self.records.filter { record in
            Self.isCodexSecondaryRecord(record) && record.accountKey == accountKey
        }
        return Self.buildDataset(from: scoped)
    }

    private static func buildDataset(from scoped: [HistoricalUsageRecord]) -> CodexHistoricalDataset? {
        struct WeekKey: Hashable {
            let resetsAt: Date
            let windowMinutes: Int
        }

        guard !scoped.isEmpty else { return nil }
        let grouped = Dictionary(grouping: scoped) {
            WeekKey(resetsAt: $0.resetsAt, windowMinutes: $0.windowMinutes)
        }

        var weeks: [HistoricalWeekProfile] = []
        for (key, samples) in grouped {
            let duration = TimeInterval(key.windowMinutes) * 60
            guard duration > 0 else { continue }
            let windowStart = key.resetsAt.addingTimeInterval(-duration)
            guard Self.isCompleteWeek(samples: samples, windowStart: windowStart, resetsAt: key.resetsAt),
                  let curve = Self.reconstructWeekCurve(
                      samples: samples,
                      windowStart: windowStart,
                      windowDuration: duration,
                      gridPointCount: CodexHistoricalDataset.gridPointCount)
            else {
                continue
            }
            weeks.append(HistoricalWeekProfile(
                resetsAt: key.resetsAt,
                windowMinutes: key.windowMinutes,
                curve: curve))
        }

        weeks.sort { $0.resetsAt < $1.resetsAt }
        guard !weeks.isEmpty else { return nil }
        return CodexHistoricalDataset(weeks: weeks)
    }

    private static func isCodexSecondaryRecord(_ record: HistoricalUsageRecord) -> Bool {
        record.providerID == "codex" &&
            record.windowKind == .secondary &&
            record.windowMinutes > 0
    }

    private static func reconstructWeekCurve(
        samples: [HistoricalUsageRecord],
        windowStart: Date,
        windowDuration: TimeInterval,
        gridPointCount: Int)
        -> [Double]?
    {
        guard gridPointCount >= 2 else { return nil }
        var points = samples.map { sample -> (u: Double, value: Double) in
            let offset = sample.sampledAt.timeIntervalSince(windowStart)
            return (
                u: Self.clamp(offset / windowDuration, lower: 0, upper: 1),
                value: Self.clamp(sample.usedPercent, lower: 0, upper: 100))
        }
        points.sort {
            if $0.u == $1.u { return $0.value < $1.value }
            return $0.u < $1.u
        }
        guard !points.isEmpty else { return nil }

        var monotonePoints: [(u: Double, value: Double)] = []
        var runningMax = 0.0
        for point in points {
            runningMax = max(runningMax, point.value)
            monotonePoints.append((u: point.u, value: runningMax))
        }

        let endValue = monotonePoints.last?.value ?? 0
        monotonePoints.append((u: 0, value: 0))
        monotonePoints.append((u: 1, value: endValue))
        monotonePoints.sort {
            if $0.u == $1.u { return $0.value < $1.value }
            return $0.u < $1.u
        }

        runningMax = 0
        for index in monotonePoints.indices {
            runningMax = max(runningMax, monotonePoints[index].value)
            monotonePoints[index].value = runningMax
        }

        var curve = Array(repeating: 0.0, count: gridPointCount)
        let first = monotonePoints[0]
        let last = monotonePoints[monotonePoints.count - 1]
        var upperIndex = 1
        let denominator = Double(gridPointCount - 1)

        for index in 0..<gridPointCount {
            let u = Double(index) / denominator
            if u <= first.u {
                curve[index] = first.value
                continue
            }
            if u >= last.u {
                curve[index] = last.value
                continue
            }
            while upperIndex < monotonePoints.count, monotonePoints[upperIndex].u < u {
                upperIndex += 1
            }
            let hi = monotonePoints[min(upperIndex, monotonePoints.count - 1)]
            let lo = monotonePoints[max(0, upperIndex - 1)]
            if hi.u <= lo.u {
                curve[index] = max(lo.value, hi.value)
                continue
            }
            let ratio = Self.clamp((u - lo.u) / (hi.u - lo.u), lower: 0, upper: 1)
            curve[index] = lo.value + ((hi.value - lo.value) * ratio)
        }

        var curveMax = 0.0
        for index in curve.indices {
            curve[index] = Self.clamp(curve[index], lower: 0, upper: 100)
            curveMax = max(curveMax, curve[index])
            curve[index] = curveMax
        }
        return curve
    }

    private static func isCompleteWeek(
        samples: [HistoricalUsageRecord],
        windowStart: Date,
        resetsAt: Date)
        -> Bool
    {
        guard samples.count >= Self.minimumWeekSamples else { return false }
        let startBoundary = windowStart.addingTimeInterval(Self.boundaryCoverageWindow)
        let endBoundary = resetsAt.addingTimeInterval(-Self.boundaryCoverageWindow)
        let hasStartCoverage = samples.contains {
            $0.sampledAt >= windowStart && $0.sampledAt <= startBoundary
        }
        let hasEndCoverage = samples.contains {
            $0.sampledAt >= endBoundary && $0.sampledAt <= resetsAt
        }
        return hasStartCoverage && hasEndCoverage
    }

    private struct DayUsage {
        let start: Date
        let end: Date
        let creditsUsed: Double
    }

    private static func parseDayUsages(
        from breakdown: [OpenAIDashboardDailyBreakdown],
        asOf: Date,
        fillingFrom expectedCoverageStart: Date? = nil)
        -> [DayUsage]
    {
        var creditsByStart: [Date: Double] = [:]
        for day in breakdown {
            guard let dayStart = Self.dayStart(for: day.day) else { continue }
            creditsByStart[dayStart, default: 0] += max(0, day.totalCreditsUsed)
        }

        let calendar = Self.gregorianCalendar()
        let dayUsages = creditsByStart.compactMap { dayStart, credits -> DayUsage? in
            guard let nominalEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                return nil
            }
            let effectiveEnd: Date = if dayStart <= asOf, asOf < nominalEnd {
                asOf
            } else {
                nominalEnd
            }
            guard effectiveEnd > dayStart else { return nil }
            return DayUsage(start: dayStart, end: effectiveEnd, creditsUsed: credits)
        }
        .sorted { $0.start < $1.start }
        return Self.fillMissingZeroUsageDays(
            in: dayUsages,
            through: asOf,
            fillingFrom: expectedCoverageStart)
    }

    private static func fillMissingZeroUsageDays(
        in dayUsages: [DayUsage],
        through asOf: Date,
        fillingFrom expectedCoverageStart: Date? = nil)
        -> [DayUsage]
    {
        guard let firstStart = dayUsages.first?.start else { return [] }
        let calendar = Self.gregorianCalendar()
        let fillStart = expectedCoverageStart.map { min(firstStart, calendar.startOfDay(for: $0)) } ?? firstStart
        let finalDayStart = calendar.startOfDay(for: asOf)
        guard fillStart <= finalDayStart else { return dayUsages }

        let creditsByStart = Dictionary(uniqueKeysWithValues: dayUsages.map { ($0.start, $0.creditsUsed) })
        var filled: [DayUsage] = []
        var cursor = fillStart
        while cursor <= finalDayStart {
            guard let nominalEnd = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let effectiveEnd: Date = if cursor <= asOf, asOf < nominalEnd {
                asOf
            } else {
                nominalEnd
            }
            guard effectiveEnd > cursor else { break }
            filled.append(DayUsage(
                start: cursor,
                end: effectiveEnd,
                creditsUsed: creditsByStart[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return filled
    }

    private static func creditsUsed(from dayUsages: [DayUsage], between start: Date, and end: Date) -> Double {
        guard end > start else { return 0 }
        var total = 0.0
        for day in dayUsages {
            if day.end <= start { continue }
            if day.start >= end { break }
            let overlapStart = max(day.start, start)
            let overlapEnd = min(day.end, end)
            guard overlapEnd > overlapStart else { continue }
            let dayDuration = day.end.timeIntervalSince(day.start)
            guard dayDuration > 0 else { continue }
            total += day.creditsUsed * (overlapEnd.timeIntervalSince(overlapStart) / dayDuration)
        }
        return max(0, total)
    }

    private static func dayStart(for key: String) -> Date? {
        let components = key.split(separator: "-", omittingEmptySubsequences: true)
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2])
        else {
            return nil
        }
        let calendar = Self.gregorianCalendar()
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        return dateComponents.date
    }

    private static func normalizeReset(_ value: Date) -> Date {
        let rounded = (value.timeIntervalSinceReferenceDate / Self.resetBucketSeconds).rounded()
            * Self.resetBucketSeconds
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    private static func clampDate(_ value: Date, lower: Date, upper: Date) -> Date {
        min(upper, max(lower, value))
    }

    private static func gregorianCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

public enum CodexHistoricalPaceEvaluator {
    private static let minimumCompleteWeeksForHistorical = 3
    private static let minimumWeeksForRisk = 5
    private static let recencyTauWeeks: Double = 3
    private static let epsilon: Double = 1e-9
    private static let resetBucketSeconds: TimeInterval = 5 * 60

    public static func evaluate(
        window: RateWindow,
        now: Date = Date(),
        dataset: CodexHistoricalDataset?)
        -> UsagePace?
    {
        guard let dataset,
              let resetsAt = window.resetsAt
        else {
            return nil
        }
        let minutes = window.windowMinutes ?? 10080
        guard minutes > 0 else { return nil }

        let duration = TimeInterval(minutes) * 60
        guard duration > 0 else { return nil }
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let normalizedResetsAt = Self.normalizeReset(resetsAt)
        let elapsed = Self.clamp(duration - timeUntilReset, lower: 0, upper: duration)
        let actual = Self.clamp(window.usedPercent, lower: 0, upper: 100)
        if elapsed == 0, actual > 0 { return nil }

        let uNow = Self.clamp(elapsed / duration, lower: 0, upper: 1)
        let scopedWeeks = dataset.weeks.filter {
            $0.windowMinutes == minutes && $0.resetsAt < normalizedResetsAt
        }
        guard scopedWeeks.count >= Self.minimumCompleteWeeksForHistorical else { return nil }

        let weightedWeeks = scopedWeeks.map { week in
            let ageWeeks = Self.clamp(
                normalizedResetsAt.timeIntervalSince(week.resetsAt) / duration,
                lower: 0,
                upper: Double.greatestFiniteMagnitude)
            return (week: week, weight: exp(-ageWeeks / Self.recencyTauWeeks))
        }
        let totalWeight = weightedWeeks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > Self.epsilon else { return nil }

        let totalWeightSquared = weightedWeeks.reduce(0.0) { $0 + ($1.weight * $1.weight) }
        let nEff = totalWeightSquared > Self.epsilon ? (totalWeight * totalWeight) / totalWeightSquared : 0
        let lambda = Self.clamp((nEff - 2) / 6, lower: 0, upper: 1)

        let gridCount = CodexHistoricalDataset.gridPointCount
        let denominator = Double(gridCount - 1)
        var expectedCurve = Array(repeating: 0.0, count: gridCount)
        for index in 0..<gridCount {
            let u = Double(index) / denominator
            let values = weightedWeeks.map { $0.week.curve[index] }
            let weights = weightedWeeks.map(\.weight)
            let historicalMedian = Self.weightedMedian(values: values, weights: weights)
            let linearBaseline = 100 * u
            expectedCurve[index] = Self.clamp(
                (lambda * historicalMedian) + ((1 - lambda) * linearBaseline),
                lower: 0,
                upper: linearBaseline)
        }

        var runningExpected = 0.0
        for index in expectedCurve.indices {
            runningExpected = max(runningExpected, expectedCurve[index])
            expectedCurve[index] = runningExpected
        }

        let expectedNow = Self.interpolate(curve: expectedCurve, at: uNow)
        var weightedRunOutMass = 0.0
        var crossingCandidates: [(etaSeconds: TimeInterval, weight: Double)] = []

        for weighted in weightedWeeks {
            var extendedCurve = weighted.week.curve
            if let capIndex = extendedCurve.firstIndex(where: { $0 >= 100 - Self.epsilon }),
               capIndex > 0,
               capIndex < extendedCurve.count - 1
            {
                let uCap = Double(capIndex) / Double(gridCount - 1)
                let valCap = extendedCurve[capIndex]
                let slope = valCap / uCap
                for index in capIndex..<extendedCurve.count {
                    let u = Double(index) / Double(gridCount - 1)
                    extendedCurve[index] = slope * u
                }
            }

            let weight = weighted.weight
            let weekNow = Self.interpolate(curve: extendedCurve, at: uNow)
            let shift = actual - weekNow
            let shiftedEnd = (extendedCurve.last ?? 0) + shift
            if shiftedEnd >= 100 - Self.epsilon {
                weightedRunOutMass += weight
                if let crossingU = Self.firstCrossing(
                    after: uNow,
                    curve: extendedCurve,
                    shift: shift,
                    actualAtNow: actual)
                {
                    crossingCandidates.append((
                        etaSeconds: max(0, (crossingU - uNow) * duration),
                        weight: weight))
                }
            }
        }

        let smoothedProbability = Self.clamp(
            (weightedRunOutMass + 0.5) / (totalWeight + 1),
            lower: 0,
            upper: 1)
        var runOutProbability: Double? = scopedWeeks.count >= Self.minimumWeeksForRisk ? smoothedProbability : nil
        var willLastToReset = smoothedProbability < 0.5
        var etaSeconds: TimeInterval?

        if actual >= 100 {
            willLastToReset = false
            etaSeconds = 0
            runOutProbability = 1
        } else if !willLastToReset {
            let values = crossingCandidates.map(\.etaSeconds)
            let weights = crossingCandidates.map(\.weight)
            if values.isEmpty {
                willLastToReset = true
            } else {
                etaSeconds = max(0, Self.weightedMedian(values: values, weights: weights))
            }
        }

        return UsagePace.historical(
            expectedUsedPercent: expectedNow,
            actualUsedPercent: actual,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset,
            runOutProbability: runOutProbability)
    }

    private static func firstCrossing(
        after uNow: Double,
        curve: [Double],
        shift: Double,
        actualAtNow: Double)
        -> Double?
    {
        guard curve.count >= 2 else { return nil }
        let denominator = Double(curve.count - 1)
        var previousU = uNow
        var previousValue = actualAtNow
        let startIndex = min(curve.count - 1, max(1, Int(floor(uNow * denominator)) + 1))

        for index in startIndex..<curve.count {
            let u = Double(index) / denominator
            if u <= uNow + Self.epsilon { continue }
            let value = Self.clamp(curve[index] + shift, lower: 0, upper: 100)
            if previousValue < 100 - Self.epsilon,
               value >= 100 - Self.epsilon
            {
                let delta = value - previousValue
                if abs(delta) <= Self.epsilon { return u }
                let ratio = Self.clamp((100 - previousValue) / delta, lower: 0, upper: 1)
                return Self.clamp(previousU + ratio * (u - previousU), lower: uNow, upper: 1)
            }
            previousU = u
            previousValue = value
        }
        return nil
    }

    private static func interpolate(curve: [Double], at u: Double) -> Double {
        guard !curve.isEmpty else { return 0 }
        if curve.count == 1 { return curve[0] }
        let clipped = Self.clamp(u, lower: 0, upper: 1)
        let scaled = clipped * Double(curve.count - 1)
        let lower = Int(floor(scaled))
        let upper = min(curve.count - 1, lower + 1)
        if lower == upper { return curve[lower] }
        let ratio = scaled - Double(lower)
        return curve[lower] + ((curve[upper] - curve[lower]) * ratio)
    }

    private static func weightedMedian(values: [Double], weights: [Double]) -> Double {
        guard values.count == weights.count, !values.isEmpty else { return 0 }
        let pairs = zip(values, weights)
            .map { (value: $0, weight: max(0, $1)) }
            .sorted { $0.value < $1.value }
        let totalWeight = pairs.reduce(0.0) { $0 + $1.weight }
        if totalWeight <= Self.epsilon {
            let sortedValues = values.sorted()
            return sortedValues[sortedValues.count / 2]
        }

        let threshold = totalWeight / 2
        var cumulative = 0.0
        for pair in pairs {
            cumulative += pair.weight
            if cumulative >= threshold {
                return pair.value
            }
        }
        return pairs.last?.value ?? 0
    }

    private static func normalizeReset(_ value: Date) -> Date {
        let rounded = (value.timeIntervalSinceReferenceDate / Self.resetBucketSeconds).rounded()
            * Self.resetBucketSeconds
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }
}

private func normalizedAccountKey(_ raw: String?) -> String? {
    raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
