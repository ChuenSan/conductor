import Foundation

public struct UsageCLIReport: Encodable, Sendable {
    public let provider: String
    public let name: String
    public let configured: Bool
    public let source: String
    public let fetchedAt: Date
    public let account: String?
    public let cacheAccountKey: String?
    public let status: UsageProviderStatusSnapshot?
    public let usage: UsageCLIUsage?
    public let openaiDashboard: OpenAIDashboardSnapshot?
    public let openaiCreditsHistory: UsageCLIOpenAICreditsHistory?
    public let error: UsageCLIError?
    public let repairActions: [UsageProviderRepairAction]

    public init(
        provider: String,
        name: String,
        configured: Bool,
        source: String = "auto",
        fetchedAt: Date = Date(),
        account: String? = nil,
        cacheAccountKey: String? = nil,
        status: UsageProviderStatusSnapshot? = nil,
        usage: UsageCLIUsage?,
        openaiDashboard: OpenAIDashboardSnapshot? = nil,
        openaiCreditsHistory: UsageCLIOpenAICreditsHistory? = nil,
        error: UsageCLIError?,
        repairActions: [UsageProviderRepairAction] = []
    ) {
        self.provider = provider
        self.name = name
        self.configured = configured
        self.source = source
        self.fetchedAt = fetchedAt
        self.account = account
        self.cacheAccountKey = cacheAccountKey
        self.status = status
        self.usage = usage
        self.openaiDashboard = openaiDashboard
        self.openaiCreditsHistory = openaiCreditsHistory
        self.error = error
        self.repairActions = repairActions
    }
}

public struct UsageCLIOpenAICreditsHistory: Encodable, Sendable {
    public let accountEmail: String
    public let updatedAt: Date
    public let eventCount: Int
    public let recentEvents: [UsageCLIOpenAICreditEvent]
    public let dailyBreakdown: [OpenAIDashboardDailyBreakdown]

    public init(
        history: OpenAIDashboardCreditHistory,
        maxRecentEvents: Int = 5,
        maxDays: Int = 30
    ) {
        self.accountEmail = history.accountEmail
        self.updatedAt = history.updatedAt
        self.eventCount = history.creditEvents.count
        self.recentEvents = history.creditEvents
            .prefix(maxRecentEvents)
            .map(UsageCLIOpenAICreditEvent.init(event:))
        self.dailyBreakdown = OpenAIDashboardSnapshot.makeDailyBreakdown(
            from: history.creditEvents,
            maxDays: maxDays)
    }

    public init(
        accountEmail: String,
        updatedAt: Date = Date(),
        events: [CreditEvent],
        maxRecentEvents: Int = 5,
        maxDays: Int = 30
    ) {
        self.init(
            history: OpenAIDashboardCreditHistory(
                accountEmail: accountEmail,
                creditEvents: events,
                updatedAt: updatedAt),
            maxRecentEvents: maxRecentEvents,
            maxDays: maxDays)
    }
}

public struct UsageCLIOpenAICreditEvent: Encodable, Sendable {
    public let date: Date
    public let service: String
    public let creditsUsed: Double

    public init(event: CreditEvent) {
        self.date = event.date
        self.service = event.service
        self.creditsUsed = event.creditsUsed
    }
}

public struct UsageCLIUsage: Encodable, Sendable {
    public let sourceLabel: String?
    public let planName: String?
    public let accountLabel: String?
    public let updatedAt: Date
    public let windows: [UsageCLIWindow]
    public let providerCost: UsageCLICost?
    public let ampUsage: AmpUsageDetails?
    public let claudeAdminAPIUsage: ClaudeAdminAPIUsageSnapshot?
    public let codexResetCredits: CodexRateLimitResetCreditsSnapshot?
    public let isEmpty: Bool

    public init(
        sourceLabel: String? = nil,
        planName: String?,
        accountLabel: String?,
        updatedAt: Date,
        windows: [UsageCLIWindow],
        providerCost: UsageCLICost?,
        ampUsage: AmpUsageDetails? = nil,
        claudeAdminAPIUsage: ClaudeAdminAPIUsageSnapshot? = nil,
        codexResetCredits: CodexRateLimitResetCreditsSnapshot? = nil,
        isEmpty: Bool)
    {
        self.sourceLabel = sourceLabel
        self.planName = planName
        self.accountLabel = accountLabel
        self.updatedAt = updatedAt
        self.windows = windows
        self.providerCost = providerCost
        self.ampUsage = ampUsage
        self.claudeAdminAPIUsage = claudeAdminAPIUsage
        self.codexResetCredits = codexResetCredits
        self.isEmpty = isEmpty
    }

    public init(
        snapshot: UsageSnapshot,
        displayMetadata: UsageProviderDisplayMetadata? = nil,
        weeklyProgressWorkDays: Int? = nil)
    {
        self.sourceLabel = snapshot.sourceLabel
        self.planName = snapshot.planName
        self.accountLabel = snapshot.accountLabel
        self.updatedAt = snapshot.updatedAt
        self.windows = Self.windows(
            from: snapshot,
            displayMetadata: displayMetadata,
            weeklyProgressWorkDays: weeklyProgressWorkDays)
        self.providerCost = snapshot.providerCost.map(UsageCLICost.init(cost:))
        self.ampUsage = snapshot.ampUsage
        self.claudeAdminAPIUsage = snapshot.claudeAdminAPIUsage
        self.codexResetCredits = snapshot.codexResetCredits
        self.isEmpty = snapshot.isEmpty
    }

    private static func windows(
        from snapshot: UsageSnapshot,
        displayMetadata: UsageProviderDisplayMetadata?,
        weeklyProgressWorkDays: Int?
    ) -> [UsageCLIWindow] {
        var windows: [UsageCLIWindow] = []
        if let primary = snapshot.primary {
            windows.append(UsageCLIWindow(
                title: primary.title ?? displayMetadata?.sessionLabel ?? "Session",
                window: primary,
                weeklyProgressWorkDays: weeklyProgressWorkDays))
        }
        if let secondary = snapshot.secondary {
            windows.append(UsageCLIWindow(
                title: secondary.title ?? displayMetadata?.weeklyLabel ?? "Weekly",
                window: secondary,
                weeklyProgressWorkDays: weeklyProgressWorkDays))
        }
        if let tertiary = snapshot.tertiary {
            windows.append(UsageCLIWindow(
                title: tertiary.title ?? displayMetadata?.opusLabel ?? "Other",
                window: tertiary,
                weeklyProgressWorkDays: weeklyProgressWorkDays))
        }
        for extra in snapshot.extraRateWindows {
            windows.append(UsageCLIWindow(
                title: extra.title,
                window: extra.window,
                weeklyProgressWorkDays: weeklyProgressWorkDays))
        }
        return windows
    }

    public var codexWeeklyRateWindow: RateWindow? {
        self.windows.first { window in
            window.windowMinutes == 7 * 24 * 60 && window.resetsAt != nil
        }?.rateWindow
    }

    public var usageSnapshot: UsageSnapshot {
        var remaining = self.windows
        let primary = remaining.isEmpty ? nil : remaining.removeFirst().rateWindow
        let secondary = remaining.isEmpty ? nil : remaining.removeFirst().rateWindow
        let tertiary = remaining.isEmpty ? nil : remaining.removeFirst().rateWindow
        let extras = remaining.enumerated().map { index, window in
            NamedRateWindow(
                id: "cli-extra-\(index)",
                title: window.title,
                window: window.rateWindow)
        }
        return UsageSnapshot(
            sourceLabel: self.sourceLabel,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: extras,
            providerCost: self.providerCost?.providerCostSnapshot,
            ampUsage: self.ampUsage,
            claudeAdminAPIUsage: self.claudeAdminAPIUsage,
            codexResetCredits: self.codexResetCredits,
            planName: self.planName,
            accountLabel: self.accountLabel,
            updatedAt: self.updatedAt)
    }

    public func applyingCodexHistoricalPace(
        dataset: CodexHistoricalDataset?,
        now: Date? = nil)
        -> UsageCLIUsage
    {
        guard dataset != nil else { return self }
        let referenceNow = now ?? self.updatedAt
        let updatedWindows = self.windows.map {
            $0.applyingCodexHistoricalPace(dataset: dataset, now: referenceNow)
        }
        return UsageCLIUsage(
            sourceLabel: self.sourceLabel,
            planName: self.planName,
            accountLabel: self.accountLabel,
            updatedAt: self.updatedAt,
            windows: updatedWindows,
            providerCost: self.providerCost,
            ampUsage: self.ampUsage,
            claudeAdminAPIUsage: self.claudeAdminAPIUsage,
            codexResetCredits: self.codexResetCredits,
            isEmpty: self.isEmpty)
    }
}

public struct UsageCLIWindow: Encodable, Sendable {
    public let title: String
    public let usedPercent: Double
    public let remainingPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let resetDescription: String?
    public let pace: UsagePaceSummary?

    public init(title: String, window: RateWindow, weeklyProgressWorkDays: Int? = nil) {
        self.init(
            title: title,
            window: window,
            pace: UsagePace.summary(
                window: window,
                weeklyProgressWorkDays: weeklyProgressWorkDays))
    }

    private init(title: String, window: RateWindow, pace: UsagePaceSummary?) {
        self.title = title
        self.usedPercent = window.usedPercent
        self.remainingPercent = window.remainingPercent
        self.windowMinutes = window.windowMinutes
        self.resetsAt = window.resetsAt
        self.resetDescription = window.resetDescription
        self.pace = pace
    }

    public var rateWindow: RateWindow {
        RateWindow(
            title: self.title,
            usedPercent: self.usedPercent,
            windowMinutes: self.windowMinutes,
            resetsAt: self.resetsAt,
            resetDescription: self.resetDescription)
    }

    public func applyingCodexHistoricalPace(
        dataset: CodexHistoricalDataset?,
        now: Date)
        -> UsageCLIWindow
    {
        let window = self.rateWindow
        guard let historical = CodexHistoricalPaceEvaluator.evaluate(
            window: window,
            now: now,
            dataset: dataset),
            historical.expectedUsedPercent >= 3
        else {
            return self
        }
        return UsageCLIWindow(
            title: self.title,
            window: window,
            pace: historical.summary(now: now))
    }
}

public struct UsageCLICost: Encodable, Sendable {
    public let used: Double
    public let limit: Double
    public let currencyCode: String
    public let period: String?
    public let resetsAt: Date?
    public let usedPercent: Double?

    public init(cost: ProviderCostSnapshot) {
        self.used = cost.used
        self.limit = cost.limit
        self.currencyCode = cost.currencyCode
        self.period = cost.period
        self.resetsAt = cost.resetsAt
        self.usedPercent = cost.hasLimit ? cost.usedPercent : nil
    }

    public var providerCostSnapshot: ProviderCostSnapshot {
        ProviderCostSnapshot(
            used: self.used,
            limit: self.limit,
            currencyCode: self.currencyCode,
            period: self.period,
            resetsAt: self.resetsAt)
    }
}

public struct UsageCLIError: Encodable, Sendable {
    public let message: String

    public init(_ error: Error) {
        let nsError = error as NSError
        if !nsError.localizedDescription.isEmpty {
            self.message = nsError.localizedDescription
        } else {
            self.message = String(describing: error)
        }
    }
}

public enum UsageCLIReporter {
    public static func fetchUnlessCancelled(
        entries: [UsageProviderEntry],
        source: String = "auto",
        weeklyProgressWorkDays: Int? = nil,
        statusesByProvider: [String: UsageProviderStatusSnapshot] = [:]
    ) async throws -> [UsageCLIReport] {
        var reports: [UsageCLIReport] = []
        for entry in entries {
            try Task.checkCancellation()
            let configured = entry.isConfigured()
            do {
                let snapshot = try await entry.fetch()
                try Task.checkCancellation()
                reports.append(UsageCLIReport(
                    provider: entry.id,
                    name: entry.name,
                    configured: configured,
                    source: Self.reportSource(requested: source, snapshot: snapshot),
                    status: statusesByProvider[entry.id],
                    usage: UsageCLIUsage(
                        snapshot: snapshot,
                        displayMetadata: entry.displayMetadata,
                        weeklyProgressWorkDays: weeklyProgressWorkDays),
                    openaiCreditsHistory: Self.openAICreditsHistory(
                        providerID: entry.id,
                        usageAccountLabel: snapshot.accountLabel),
                    error: nil))
            } catch {
                try UsageProviderCancellation.rethrowIfCancelled(error)
                let repairActions = UsageProviderRepairActions.actions(
                    providerID: entry.id,
                    providerName: entry.name,
                    configured: configured,
                    error: error,
                    source: source,
                    hasStatusPage: entry.statusURL != nil,
                    statusURL: entry.statusURL)
                reports.append(UsageCLIReport(
                    provider: entry.id,
                    name: entry.name,
                    configured: configured,
                    source: source,
                    status: statusesByProvider[entry.id],
                    usage: nil,
                    error: UsageCLIError(error),
                    repairActions: repairActions))
            }
        }
        return reports
    }

    public static func fetch(
        entries: [UsageProviderEntry],
        source: String = "auto",
        weeklyProgressWorkDays: Int? = nil,
        statusesByProvider: [String: UsageProviderStatusSnapshot] = [:]
    ) async -> [UsageCLIReport] {
        var reports: [UsageCLIReport] = []
        for entry in entries {
            let configured = entry.isConfigured()
            do {
                let snapshot = try await entry.fetch()
                reports.append(UsageCLIReport(
                    provider: entry.id,
                    name: entry.name,
                    configured: configured,
                    source: Self.reportSource(requested: source, snapshot: snapshot),
                    status: statusesByProvider[entry.id],
                    usage: UsageCLIUsage(
                        snapshot: snapshot,
                        displayMetadata: entry.displayMetadata,
                        weeklyProgressWorkDays: weeklyProgressWorkDays),
                    openaiCreditsHistory: Self.openAICreditsHistory(
                        providerID: entry.id,
                        usageAccountLabel: snapshot.accountLabel),
                    error: nil))
            } catch {
                let repairActions = UsageProviderRepairActions.actions(
                    providerID: entry.id,
                    providerName: entry.name,
                    configured: configured,
                    error: error,
                    source: source,
                    hasStatusPage: entry.statusURL != nil,
                    statusURL: entry.statusURL)
                reports.append(UsageCLIReport(
                    provider: entry.id,
                    name: entry.name,
                    configured: configured,
                    source: source,
                    status: statusesByProvider[entry.id],
                    usage: nil,
                    error: UsageCLIError(error),
                    repairActions: repairActions))
            }
        }
        return reports
    }

    private static func reportSource(requested: String, snapshot: UsageSnapshot) -> String {
        snapshot.sourceLabel ?? requested
    }

    public static func openAICreditsHistory(
        providerID: String,
        reportAccount: String? = nil,
        usageAccountLabel: String? = nil,
        dashboard: OpenAIDashboardSnapshot? = nil
    ) -> UsageCLIOpenAICreditsHistory? {
        guard providerID == "codex" else { return nil }
        guard let email = openAICreditsHistoryEmail(
            reportAccount: reportAccount,
            usageAccountLabel: usageAccountLabel,
            dashboard: dashboard)
        else {
            return nil
        }
        if let history = OpenAIDashboardCreditHistoryStore.load(accountEmail: email),
           !history.creditEvents.isEmpty
        {
            return UsageCLIOpenAICreditsHistory(history: history)
        }
        if let dashboard, !dashboard.creditEvents.isEmpty {
            return UsageCLIOpenAICreditsHistory(
                accountEmail: email,
                updatedAt: dashboard.updatedAt,
                events: dashboard.creditEvents)
        }
        return nil
    }

    private static func openAICreditsHistoryEmail(
        reportAccount: String?,
        usageAccountLabel: String?,
        dashboard: OpenAIDashboardSnapshot?
    ) -> String? {
        CodexIdentityResolver.firstEmail(in: dashboard?.signedInEmail)
            ?? CodexIdentityResolver.firstEmail(in: usageAccountLabel)
            ?? CodexIdentityResolver.firstEmail(in: reportAccount)
    }
}

public enum UsageCLITextRenderer {
    public static func render(
        _ reports: [UsageCLIReport],
        includeCredits: Bool = true,
        hidePersonalInfo: Bool = false
    ) -> String {
        reports.map {
            self.render(
                report: $0,
                includeCredits: includeCredits,
                hidePersonalInfo: hidePersonalInfo)
        }
        .joined(separator: "\n\n")
    }

    private static func render(
        report: UsageCLIReport,
        includeCredits: Bool,
        hidePersonalInfo: Bool
    ) -> String {
        var lines: [String] = []
        lines.append("\(report.name) (\(report.provider))")
        lines.append("  configured: \(report.configured ? "yes" : "no")")
        lines.append("  source: \(report.source)")
        if let status = report.status {
            lines.append("  status: \(status.label)\(self.statusDescriptionSuffix(status))")
        }

        if let error = report.error {
            lines.append("  error: \(error.message)")
            for action in report.repairActions {
                lines.append("  next: \(action.title) - \(action.detail)")
                if let command = action.command, !command.isEmpty {
                    lines.append("    command: \(command)")
                }
                if let url = action.url, !url.isEmpty {
                    lines.append("    url: \(url)")
                }
            }
            return lines.joined(separator: "\n")
        }

        guard let usage = report.usage else {
            lines.append("  usage: no data")
            return lines.joined(separator: "\n")
        }

        if let plan = usage.planName, !plan.isEmpty {
            lines.append("  plan: \(plan)")
        }
        if let account = report.account ?? usage.accountLabel, !account.isEmpty {
            lines.append("  account: \(redactEmails(in: account, hidePersonalInfo: hidePersonalInfo))")
        }
        if usage.windows.isEmpty, usage.providerCost == nil, usage.ampUsage == nil, usage.codexResetCredits == nil {
            lines.append("  usage: no data")
        }
        for window in usage.windows {
            lines.append("  \(window.title): \(self.percent(window.usedPercent)) used, \(self.percent(window.remainingPercent)) remaining\(self.resetSuffix(window))")
            if let pace = window.pace {
                lines.append("    pace: \(pace.detail)")
            }
        }
        if let cost = usage.providerCost, includeCredits || report.provider != "codex" {
            lines.append("  cost: \(self.money(cost.used, code: cost.currencyCode))\(self.limitSuffix(cost))\(self.periodSuffix(cost))")
        }
        if includeCredits, let ampUsage = usage.ampUsage {
            lines.append(contentsOf: self.ampUsageLines(ampUsage))
        }
        if report.provider == "codex", includeCredits, let resetCredits = usage.codexResetCredits {
            lines.append(contentsOf: self.codexResetCreditLines(resetCredits))
        }
        if report.provider == "codex", includeCredits, let history = report.openaiCreditsHistory {
            lines.append(contentsOf: self.openAICreditsHistoryLines(history))
        }
        if report.provider == "codex",
           let dashboard = report.openaiDashboard,
           self.shouldRenderOpenAIDashboardText(source: report.source)
        {
            lines.append(contentsOf: self.openAIDashboardLines(
                dashboard,
                hidePersonalInfo: hidePersonalInfo))
        }
        return lines.joined(separator: "\n")
    }

    private static func redactEmails(in text: String, hidePersonalInfo: Bool) -> String {
        UsagePersonalInfoRedactor.redactEmails(in: text, isEnabled: hidePersonalInfo) ?? text
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func money(_ value: Double, code: String) -> String {
        if code.uppercased() == "USD" {
            return String(format: "$%.2f", value)
        }
        return "\(String(format: "%.2f", value)) \(code)"
    }

    private static func resetSuffix(_ window: UsageCLIWindow) -> String {
        if let resetDescription = window.resetDescription, !resetDescription.isEmpty {
            return ", resets \(resetDescription)"
        }
        if let resetsAt = window.resetsAt {
            return ", resets \(self.iso8601(resetsAt))"
        }
        return ""
    }

    private static func limitSuffix(_ cost: UsageCLICost) -> String {
        guard cost.limit > 0 else { return "" }
        let percent = cost.usedPercent.map { " (\(self.percent($0)) used)" } ?? ""
        return " / \(self.money(cost.limit, code: cost.currencyCode))\(percent)"
    }

    private static func periodSuffix(_ cost: UsageCLICost) -> String {
        var parts: [String] = []
        if let period = cost.period, !period.isEmpty {
            parts.append(period)
        }
        if let resetsAt = cost.resetsAt {
            parts.append("resets \(self.iso8601(resetsAt))")
        }
        return parts.isEmpty ? "" : " [" + parts.joined(separator: ", ") + "]"
    }

    private static func openAICreditsHistoryLines(_ history: UsageCLIOpenAICreditsHistory) -> [String] {
        var lines: [String] = []
        var summary = "\(history.eventCount) stored events"
        if let latest = history.recentEvents.first {
            summary += " (latest \(self.day(latest.date)), \(self.credits(latest.creditsUsed)))"
        }
        lines.append("  Credits history: \(summary)")
        if let day = history.dailyBreakdown.first {
            lines.append("    latest day: \(day.day) · \(self.credits(day.totalCreditsUsed))")
        }
        return lines
    }

    private static func codexResetCreditLines(_ resetCredits: CodexRateLimitResetCreditsSnapshot) -> [String] {
        var lines: [String] = []
        let value = resetCredits.availableCount == 1
            ? "1 available"
            : "\(resetCredits.availableCount) available"
        lines.append("  Limit Reset Credits: \(value)")
        if resetCredits.availableCount > 0,
           let expiresAt = resetCredits.nextExpiringAvailableCredit?.expiresAt
        {
            lines.append("    next reset credit expires \(self.iso8601(expiresAt))")
        }
        return lines
    }

    private static func ampUsageLines(_ usage: AmpUsageDetails) -> [String] {
        var lines: [String] = []
        if let individualCredits = usage.individualCredits {
            lines.append("  Individual credits: \(self.money(individualCredits, code: "USD"))")
        }
        for workspace in usage.workspaceBalances {
            lines.append("  Workspace \(workspace.name): \(self.money(workspace.remaining, code: "USD"))")
        }
        return lines
    }

    private static func credits(_ value: Double) -> String {
        let absolute = abs(value)
        if absolute >= 100 {
            return "\(String(format: "%.0f", value)) credits"
        }
        if absolute >= 1 {
            return "\(String(format: "%.2f", value)) credits"
        }
        return "\(String(format: "%.3f", value)) credits"
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func shouldRenderOpenAIDashboardText(source: String) -> Bool {
        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "web", "browser", "dashboard":
            return true
        default:
            return false
        }
    }

    private static func openAIDashboardLines(
        _ dashboard: OpenAIDashboardSnapshot,
        hidePersonalInfo: Bool
    ) -> [String] {
        var lines: [String] = []
        if let email = dashboard.signedInEmail, !email.isEmpty {
            lines.append("  Web session: \(redactEmails(in: email, hidePersonalInfo: hidePersonalInfo))")
        }
        if let remaining = dashboard.codeReviewRemainingPercent {
            let value = Int(remaining.rounded())
            if let suffix = dashboard.codeReviewLimit.flatMap(dashboardResetSuffix) {
                lines.append("  Code review: \(value)% remaining (\(suffix))")
            } else {
                lines.append("  Code review: \(value)% remaining")
            }
        }
        if let first = dashboard.creditEvents.first {
            lines.append("  Web history: \(dashboard.creditEvents.count) events (latest \(self.day(first.date)))")
        } else {
            lines.append("  Web history: none")
        }
        return lines
    }

    private static func dashboardResetSuffix(_ window: RateWindow) -> String? {
        if let resetDescription = window.resetDescription, !resetDescription.isEmpty {
            return "resets \(resetDescription)"
        }
        if let resetsAt = window.resetsAt {
            return "resets \(self.iso8601(resetsAt))"
        }
        return nil
    }

    private static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func statusDescriptionSuffix(_ status: UsageProviderStatusSnapshot) -> String {
        guard let description = status.description, !description.isEmpty else { return "" }
        return " - \(description)"
    }
}
