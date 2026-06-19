import Foundation

public struct UsageCostCLIReport: Encodable, Sendable {
    public let daysBack: Int
    public let generatedAt: Date
    public let sourceInfo: UsageReportSourceInfo?
    public let sessionsScanned: Int
    public let grand: UsageTotals
    public let bySource: [UsageCostSourceRow]
    public let byModel: [UsageCostModelRow]
    public let byDay: [UsageCostDayRow]
    public let byMonth: [UsageCostMonthRow]
    public let bySession: [UsageCostSessionRow]
    public let byProject: [UsageCostProjectRow]

    public init(report: UsageReport) {
        self.daysBack = report.daysBack
        self.generatedAt = report.generatedAt
        self.sourceInfo = report.sourceInfo
        self.sessionsScanned = report.sessionsScanned
        self.grand = report.grand
        self.bySource = UsageSource.allCases.compactMap { source in
            guard let totals = report.bySource[source] else { return nil }
            return UsageCostSourceRow(source: source, totals: totals, sessions: report.sessionsBySource[source] ?? 0)
        }
        self.byModel = report.byModel.map(UsageCostModelRow.init(modelUsage:))
        self.byDay = report.byDay.map(UsageCostDayRow.init(day:))
        self.byMonth = report.monthSummaries.map(UsageCostMonthRow.init(month:))
        self.bySession = report.bySession.map(UsageCostSessionRow.init(session:))
        self.byProject = report.byProject.map(UsageCostProjectRow.init(project:))
    }
}

public struct UsageCostSourceRow: Encodable, Sendable {
    public let source: String
    public let name: String
    public let totals: UsageTotals
    public let sessions: Int

    public init(source: UsageSource, totals: UsageTotals, sessions: Int) {
        self.source = source.rawValue
        self.name = source.displayName
        self.totals = totals
        self.sessions = sessions
    }
}

public struct UsageCostModelRow: Encodable, Sendable {
    public let source: String
    public let name: String
    public let model: String
    public let displayLabel: String?
    public let totals: UsageTotals

    public init(modelUsage: ModelUsage) {
        self.source = modelUsage.source.rawValue
        self.name = modelUsage.source.displayName
        self.model = modelUsage.model
        self.displayLabel = ModelPricing.codexDisplayLabel(modelUsage.model)
        self.totals = modelUsage.totals
    }
}

public struct UsageCostDayRow: Encodable, Sendable {
    public let day: String
    public let totals: UsageTotals
    public let bySource: [UsageCostSourceTotalsRow]
    public let modelBreakdowns: [UsageCostModelBreakdownRow]

    public init(day: DailyUsage) {
        self.day = day.day
        self.totals = day.totals
        self.bySource = UsageSource.allCases.compactMap { source in
            guard let totals = day.bySource[source] else { return nil }
            return UsageCostSourceTotalsRow(source: source, totals: totals)
        }
        self.modelBreakdowns = day.modelBreakdowns.map(UsageCostModelBreakdownRow.init(breakdown:))
    }
}

public struct UsageCostMonthRow: Encodable, Sendable {
    public let month: String
    public let totals: UsageTotals
    public let bySource: [UsageCostSourceTotalsRow]

    public init(month: MonthlyUsage) {
        self.month = month.month
        self.totals = month.totals
        self.bySource = UsageSource.allCases.compactMap { source in
            guard let totals = month.bySource[source] else { return nil }
            return UsageCostSourceTotalsRow(source: source, totals: totals)
        }
    }
}

public struct UsageCostSessionRow: Encodable, Sendable {
    public let session: String
    public let source: String
    public let name: String
    public let project: String
    public let totals: UsageTotals
    public let lastActivity: String?
    public let models: [String]

    public init(session: SessionUsage) {
        self.session = session.session
        self.source = session.source.rawValue
        self.name = session.source.displayName
        self.project = session.project
        self.totals = session.totals
        self.lastActivity = session.lastActivity
        self.models = session.models
    }
}

public struct UsageCostModelBreakdownRow: Encodable, Sendable {
    public let source: String
    public let name: String
    public let model: String
    public let displayLabel: String?
    public let totals: UsageTotals
    public let costUSD: Double
    public let totalTokens: Int
    public let standardCostUSD: Double?
    public let priorityCostUSD: Double?
    public let standardTokens: Int?
    public let priorityTokens: Int?

    public init(breakdown: UsageModelBreakdown) {
        self.source = breakdown.source.rawValue
        self.name = breakdown.source.displayName
        self.model = breakdown.model
        self.displayLabel = ModelPricing.codexDisplayLabel(breakdown.model)
        self.totals = breakdown.totals
        self.costUSD = breakdown.totals.costUSD
        self.totalTokens = breakdown.totals.totalTokens
        self.standardCostUSD = breakdown.standardCostUSD
        self.priorityCostUSD = breakdown.priorityCostUSD
        self.standardTokens = breakdown.standardTokens
        self.priorityTokens = breakdown.priorityTokens
    }
}

public struct UsageCostProjectRow: Encodable, Sendable {
    public let path: String
    public let totals: UsageTotals
    public let bySource: [UsageCostSourceTotalsRow]

    public init(project: ProjectUsage) {
        self.path = project.path
        self.totals = project.totals
        self.bySource = UsageSource.allCases.compactMap { source in
            guard let totals = project.bySource[source] else { return nil }
            return UsageCostSourceTotalsRow(source: source, totals: totals)
        }
    }
}

public struct UsageCostSourceTotalsRow: Encodable, Sendable {
    public let source: String
    public let name: String
    public let totals: UsageTotals

    public init(source: UsageSource, totals: UsageTotals) {
        self.source = source.rawValue
        self.name = source.displayName
        self.totals = totals
    }
}

public enum UsageCostCLIReporter {
    public static func scanAsync(
        daysBack: Int = 30,
        sources: Set<UsageSource>? = nil,
        forceRefresh: Bool = false) async -> UsageCostCLIReport
    {
        if isBedrockOnly(sources) {
            do {
                return UsageCostCLIReport(report: try await bedrockCostUsageReport(daysBack: daysBack))
            } catch {
                return UsageCostCLIReport(
                    report: emptyBedrockErrorReport(daysBack: daysBack, error: error))
            }
        }
        let report = await CostUsageFetcher().loadReportOrFallback(
            daysBack: daysBack,
            forceRefresh: forceRefresh)
        return UsageCostCLIReport(report: self.filtered(report, sources: sources))
    }

    public static func scanAsyncUnlessCancelled(
        daysBack: Int = 30,
        sources: Set<UsageSource>? = nil,
        forceRefresh: Bool = false) async throws -> UsageCostCLIReport
    {
        if isBedrockOnly(sources) {
            return UsageCostCLIReport(report: try await bedrockCostUsageReport(daysBack: daysBack))
        }
        let report = try await CostUsageFetcher().loadReportOrFallbackUnlessCancelled(
            daysBack: daysBack,
            forceRefresh: forceRefresh)
        return UsageCostCLIReport(report: self.filtered(report, sources: sources))
    }

    static func report(
        fromBedrockDaily daily: CostUsageDailyReport,
        daysBack: Int,
        generatedAt: Date = Date(),
        sourceInfo: UsageReportSourceInfo? = nil) -> UsageReport
    {
        var report = UsageReport()
        report.daysBack = CostUsageFetcher.clampedHistoryDays(daysBack)
        report.generatedAt = generatedAt
        report.sourceInfo = sourceInfo

        var modelTotals: [String: UsageTotals] = [:]
        var days: [DailyUsage] = []
        var sessions: [SessionUsage] = []

        for entry in daily.data.sorted(by: { $0.date < $1.date }) {
            let modelBreakdowns = bedrockModelBreakdowns(for: entry)
            let totals = bedrockTotals(for: entry, modelBreakdowns: modelBreakdowns)
            guard totals.totalTokens > 0 || totals.costUSD > 0 else { continue }

            report.grand += totals
            report.bySource[.bedrock, default: UsageTotals()] += totals
            report.sessionsBySource[.bedrock, default: 0] += 1

            for breakdown in modelBreakdowns {
                modelTotals[breakdown.model, default: UsageTotals()] += breakdown.totals
            }

            let models = modelBreakdowns.map(\.model).sorted()
            days.append(
                DailyUsage(
                    day: entry.date,
                    totals: totals,
                    bySource: [.bedrock: totals],
                    modelBreakdowns: modelBreakdowns))
            sessions.append(
                SessionUsage(
                    session: "bedrock:\(entry.date)",
                    source: .bedrock,
                    project: "AWS Bedrock",
                    totals: totals,
                    lastActivity: entry.date,
                    models: models))
        }

        report.sessionsScanned = sessions.count
        report.byDay = days
        report.bySession = sessions.sorted { lhs, rhs in
            if (lhs.lastActivity ?? "") != (rhs.lastActivity ?? "") {
                return (lhs.lastActivity ?? "") > (rhs.lastActivity ?? "")
            }
            return lhs.session < rhs.session
        }
        report.byModel = modelTotals.map { model, totals in
            ModelUsage(model: model, source: .bedrock, totals: totals)
        }.sorted { lhs, rhs in
            if lhs.totals.costUSD != rhs.totals.costUSD { return lhs.totals.costUSD > rhs.totals.costUSD }
            if lhs.totals.totalTokens != rhs.totals.totalTokens { return lhs.totals.totalTokens > rhs.totals.totalTokens }
            return lhs.model < rhs.model
        }
        report.byMonth = report.monthSummaries
        return report
    }

    public static func filtered(_ report: UsageReport, sources: Set<UsageSource>?) -> UsageReport {
        guard let sources, !sources.isEmpty else { return report }
        var out = UsageReport()
        out.daysBack = report.daysBack
        out.generatedAt = report.generatedAt
        out.sourceInfo = report.sourceInfo

        for source in sources {
            if let totals = report.bySource[source] {
                out.bySource[source] = totals
                out.grand += totals
            }
            if let sessions = report.sessionsBySource[source] {
                out.sessionsBySource[source] = sessions
            }
        }
        out.sessionsScanned = out.sessionsBySource.values.reduce(0, +)
        out.byModel = report.byModel.filter { sources.contains($0.source) }
        out.byDay = report.byDay.compactMap { day in
            let bySource = day.bySource.filter { sources.contains($0.key) }
            let totals = bySource.values.reduce(UsageTotals(), +)
            guard totals.totalTokens > 0 || totals.costUSD > 0 else { return nil }
            return DailyUsage(
                day: day.day,
                totals: totals,
                bySource: bySource,
                modelBreakdowns: day.modelBreakdowns.filter { sources.contains($0.source) })
        }
        out.byMonth = report.monthSummaries.compactMap { month in
            let bySource = month.bySource.filter { sources.contains($0.key) }
            let totals = bySource.values.reduce(UsageTotals(), +)
            guard totals.totalTokens > 0 || totals.costUSD > 0 else { return nil }
            return MonthlyUsage(month: month.month, totals: totals, bySource: bySource)
        }
        out.bySession = report.bySession.filter { sources.contains($0.source) }
        out.byProject = report.byProject.compactMap { project in
            let bySource = project.bySource.filter { sources.contains($0.key) }
            let totals = bySource.values.reduce(UsageTotals(), +)
            guard totals.totalTokens > 0 || totals.costUSD > 0 else { return nil }
            return ProjectUsage(path: project.path, totals: totals, bySource: bySource)
        }.sorted { $0.totals.costUSD > $1.totals.costUSD }
        return out
    }

    private static func isBedrockOnly(_ sources: Set<UsageSource>?) -> Bool {
        sources == Set([UsageSource.bedrock])
    }

    private static func bedrockCostUsageReport(daysBack: Int, now: Date = Date()) async throws -> UsageReport {
        let days = CostUsageFetcher.clampedHistoryDays(daysBack)
        let since = Calendar.current.date(byAdding: .day, value: -(days - 1), to: now) ?? now
        let daily = try await BedrockUsageFetcher.fetchDailyReport(since: since, until: now)
        return report(
            fromBedrockDaily: daily,
            daysBack: days,
            generatedAt: now,
            sourceInfo: UsageReportSourceInfo(source: .directScan, loadedAt: now, reason: "bedrock cost explorer"))
    }

    private static func emptyBedrockErrorReport(daysBack: Int, error: Error) -> UsageReport {
        var report = UsageReport()
        report.daysBack = CostUsageFetcher.clampedHistoryDays(daysBack)
        report.generatedAt = Date()
        report.sourceInfo = UsageReportSourceInfo(
            source: .fallbackScan,
            reason: "bedrock cost explorer failed: \(error)")
        return report
    }

    private static func bedrockTotals(
        for entry: CostUsageDailyReport.Entry,
        modelBreakdowns: [UsageModelBreakdown]) -> UsageTotals
    {
        var totals = UsageTotals()
        totals.inputTokens = max(0, entry.inputTokens ?? 0)
        totals.outputTokens = max(0, entry.outputTokens ?? 0)
        totals.cacheCreationTokens = max(0, entry.cacheCreationTokens ?? 0)
        totals.cacheReadTokens = max(0, entry.cacheReadTokens ?? 0)
        totals.costUSD = max(0, entry.costUSD ?? modelBreakdowns.map(\.totals.costUSD).reduce(0, +))
        totals.requestCount = max(0, entry.requestCount ?? modelBreakdowns.map(\.totals.requestCount).reduce(0, +))
        return totals
    }

    private static func bedrockModelBreakdowns(for entry: CostUsageDailyReport.Entry) -> [UsageModelBreakdown] {
        let rawBreakdowns = entry.modelBreakdowns?.filter {
            $0.source == .bedrock || $0.modelName.localizedCaseInsensitiveContains("bedrock")
        } ?? []
        let breakdowns: [UsageModelBreakdown]
        if rawBreakdowns.isEmpty {
            var totals = UsageTotals()
            totals.costUSD = max(0, entry.costUSD ?? 0)
            totals.requestCount = max(0, entry.requestCount ?? 0)
            breakdowns = [UsageModelBreakdown(model: "AWS Bedrock", source: .bedrock, totals: totals)]
        } else {
            breakdowns = rawBreakdowns.map { raw in
                var totals = UsageTotals()
                totals.costUSD = max(0, raw.costUSD ?? 0)
                totals.requestCount = max(0, raw.requestCount ?? 0)
                return UsageModelBreakdown(
                    model: raw.modelName,
                    source: .bedrock,
                    totals: totals,
                    standardCostUSD: raw.standardCostUSD,
                    priorityCostUSD: raw.priorityCostUSD,
                    standardTokens: raw.standardTokens,
                    priorityTokens: raw.priorityTokens)
            }
        }
        return breakdowns
            .filter { $0.totals.totalTokens > 0 || $0.totals.costUSD > 0 }
            .sorted { lhs, rhs in
                if lhs.totals.costUSD != rhs.totals.costUSD { return lhs.totals.costUSD > rhs.totals.costUSD }
                return lhs.model < rhs.model
            }
    }
}

public enum UsageCostCLITextRenderer {
    public static func render(_ report: UsageCostCLIReport) -> String {
        var lines: [String] = []
        lines.append("Local Cost Usage")
        lines.append("  days: \(report.daysBack)")
        if let sourceInfo = report.sourceInfo {
            lines.append("  source: \(self.source(sourceInfo))")
        }
        lines.append("  sessions: \(report.sessionsScanned)")
        lines.append("  total: \(self.money(report.grand.costUSD)) · \(self.tokens(report.grand.totalTokens)) tokens · \(self.requests(report.grand.requestCount)) requests")

        if !report.bySource.isEmpty {
            lines.append("")
            lines.append("By provider")
            for source in report.bySource {
                lines.append("  \(source.name): \(self.money(source.totals.costUSD)) · \(self.tokens(source.totals.totalTokens)) tokens · \(self.requests(source.totals.requestCount)) requests · \(source.sessions) sessions")
            }
        }

        if !report.byModel.isEmpty {
            lines.append("")
            lines.append("Top models")
            for model in report.byModel.prefix(8) {
                lines.append("  \(model.name) / \(model.model): \(self.modelCostDetail(model: model))")
            }
        }

        if !report.byDay.isEmpty {
            lines.append("")
            lines.append("Recent days")
            for day in report.byDay.suffix(10) {
                lines.append("  \(day.day): \(self.money(day.totals.costUSD)) · \(self.tokens(day.totals.totalTokens)) tokens · \(self.requests(day.totals.requestCount)) requests")
                for model in day.modelBreakdowns.prefix(3) {
                    lines.append("    \(model.name) / \(model.model): \(self.modelCostDetail(model: model))")
                }
            }
        }

        if !report.byMonth.isEmpty {
            lines.append("")
            lines.append("Recent months")
            for month in report.byMonth.suffix(12) {
                lines.append("  \(month.month): \(self.money(month.totals.costUSD)) · \(self.tokens(month.totals.totalTokens)) tokens · \(self.requests(month.totals.requestCount)) requests")
            }
        }

        if !report.bySession.isEmpty {
            lines.append("")
            lines.append("Recent sessions")
            for session in report.bySession.prefix(10) {
                let project = session.project.isEmpty ? "(unknown)" : session.project
                let activity = session.lastActivity.map { " · last \($0)" } ?? ""
                lines.append("  \(session.name) / \(session.session): \(self.money(session.totals.costUSD)) · \(self.tokens(session.totals.totalTokens)) tokens · \(self.requests(session.totals.requestCount)) requests · \(project)\(activity)")
            }
        }

        if !report.byProject.isEmpty {
            lines.append("")
            lines.append("Top projects")
            for project in report.byProject.prefix(10) {
                let path = project.path.isEmpty ? "(unknown)" : project.path
                lines.append("  \(path): \(self.money(project.totals.costUSD)) · \(self.tokens(project.totals.totalTokens)) tokens · \(self.requests(project.totals.requestCount)) requests")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static func tokens(_ value: Int) -> String {
        let n = Double(value)
        if n >= 1_000_000_000 { return String(format: "%.2fB", n / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.2fM", n / 1_000_000) }
        if n >= 1_000 { return String(format: "%.2fK", n / 1_000) }
        return "\(value)"
    }

    private static func requests(_ value: Int) -> String {
        self.tokens(value)
    }

    private static func modelCostDetail(model: UsageCostModelRow) -> String {
        self.modelCostDetail(
            model: model.model,
            displayLabel: model.displayLabel,
            costUSD: model.totals.costUSD,
            totalTokens: model.totals.totalTokens,
            requestCount: model.totals.requestCount,
            modeSplit: nil)
    }

    private static func modelCostDetail(model: UsageCostModelBreakdownRow) -> String {
        self.modelCostDetail(
            model: model.model,
            displayLabel: model.displayLabel,
            costUSD: model.costUSD,
            totalTokens: model.totalTokens,
            requestCount: model.totals.requestCount,
            modeSplit: self.modeSplit(model))
    }

    private static func modelCostDetail(
        model _: String,
        displayLabel: String?,
        costUSD: Double,
        totalTokens: Int,
        requestCount: Int,
        modeSplit: String?) -> String
    {
        var parts: [String] = []
        if let displayLabel, !displayLabel.isEmpty {
            parts.append(displayLabel)
        } else {
            parts.append(self.money(costUSD))
        }
        parts.append("\(self.tokens(totalTokens)) tokens")
        parts.append("\(self.requests(requestCount)) requests")
        if let modeSplit, !modeSplit.isEmpty {
            parts.append(modeSplit)
        }
        return parts.joined(separator: " · ")
    }

    private static func modeSplit(_ model: UsageCostModelBreakdownRow) -> String? {
        var parts: [String] = []
        if let standardCostUSD = model.standardCostUSD {
            parts.append(self.modeSplitPart(label: "Std", costUSD: standardCostUSD, tokens: model.standardTokens))
        }
        if let priorityCostUSD = model.priorityCostUSD {
            parts.append(self.modeSplitPart(label: "Fast", costUSD: priorityCostUSD, tokens: model.priorityTokens))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }

    private static func modeSplitPart(label: String, costUSD: Double, tokens: Int?) -> String {
        if let tokens {
            return "\(label) \(self.money(costUSD)) \(self.tokens(tokens)) tokens"
        }
        return "\(label) \(self.money(costUSD))"
    }

    private static func source(_ info: UsageReportSourceInfo) -> String {
        var parts = [info.source.label]
        if let age = info.cacheAgeSeconds {
            parts.append("age \(self.duration(age))")
        }
        if let reason = info.reason, !reason.isEmpty {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value >= 86_400 { return "\(value / 86_400)d" }
        if value >= 3_600 { return "\(value / 3_600)h" }
        if value >= 60 { return "\(value / 60)m" }
        return "\(value)s"
    }
}
