import Foundation
import SweetCookieKit

public struct OpenAIDashboardSnapshot: Codable, Equatable, Sendable {
    public var signedInEmail: String?
    public var codeReviewRemainingPercent: Double?
    public var codeReviewLimit: RateWindow?
    public var creditEvents: [CreditEvent]
    public var dailyBreakdown: [OpenAIDashboardDailyBreakdown]
    public var usageBreakdown: [OpenAIDashboardDailyBreakdown]
    public var creditsPurchaseURL: String?
    public var primaryLimit: RateWindow?
    public var secondaryLimit: RateWindow?
    public var extraRateWindows: [NamedRateWindow]?
    public var creditsRemaining: Double?
    public var accountPlan: String?
    public var updatedAt: Date

    public init(
        signedInEmail: String? = nil,
        codeReviewRemainingPercent: Double? = nil,
        codeReviewLimit: RateWindow? = nil,
        creditEvents: [CreditEvent] = [],
        dailyBreakdown: [OpenAIDashboardDailyBreakdown] = [],
        usageBreakdown: [OpenAIDashboardDailyBreakdown] = [],
        creditsPurchaseURL: String? = nil,
        primaryLimit: RateWindow? = nil,
        secondaryLimit: RateWindow? = nil,
        extraRateWindows: [NamedRateWindow]? = nil,
        creditsRemaining: Double? = nil,
        accountPlan: String? = nil,
        updatedAt: Date = Date())
    {
        self.signedInEmail = signedInEmail
        self.codeReviewRemainingPercent = codeReviewRemainingPercent
        self.codeReviewLimit = codeReviewLimit
        self.creditEvents = creditEvents
        self.dailyBreakdown = dailyBreakdown
        self.usageBreakdown = OpenAIDashboardDailyBreakdown.removingSkillUsageServices(from: usageBreakdown)
        self.creditsPurchaseURL = creditsPurchaseURL
        self.primaryLimit = primaryLimit
        self.secondaryLimit = secondaryLimit
        self.extraRateWindows = extraRateWindows
        self.creditsRemaining = creditsRemaining
        self.accountPlan = accountPlan
        self.updatedAt = updatedAt
    }

    public var hasReturnableData: Bool {
        codeReviewRemainingPercent != nil
            || codeReviewLimit != nil
            || !creditEvents.isEmpty
            || !dailyBreakdown.isEmpty
            || !usageBreakdown.isEmpty
            || primaryLimit != nil
            || secondaryLimit != nil
            || extraRateWindows?.isEmpty == false
            || creditsRemaining != nil
    }

    public func toCodexUsageSnapshot() -> CodexUsageSnapshot {
        let codeReviewWindow: NamedRateWindow? = {
            if var limit = codeReviewLimit {
                limit.title = limit.title ?? L("代码审查")
                return NamedRateWindow(id: "code-review", title: L("代码审查"), window: limit)
            }
            guard let remaining = codeReviewRemainingPercent else { return nil }
            return NamedRateWindow(
                id: "code-review",
                title: L("代码审查"),
                window: RateWindow(
                    title: L("代码审查"),
                    usedPercent: max(0, min(100, 100 - remaining))))
        }()

        var extras = extraRateWindows ?? []
        if let codeReviewWindow, !extras.contains(where: { $0.id == codeReviewWindow.id }) {
            extras.append(codeReviewWindow)
        }

        let providerCost = creditsRemaining.map {
            ProviderCostSnapshot(
                used: max(0, $0),
                limit: 0,
                currencyCode: "USD",
                period: L("余额"))
        }

        return CodexUsageSnapshot(
            planType: accountPlan,
            accountLabel: signedInEmail,
            session: Self.codexWindow(primaryLimit),
            weekly: Self.codexWindow(secondaryLimit),
            providerCost: providerCost,
            extraRateWindows: extras)
    }

    public static func makeDailyBreakdown(from events: [CreditEvent], maxDays: Int) -> [OpenAIDashboardDailyBreakdown] {
        guard !events.isEmpty else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"

        var totals: [String: [String: Double]] = [:]
        for event in events {
            let day = formatter.string(from: event.date)
            totals[day, default: [:]][event.service, default: 0] += event.creditsUsed
        }

        return totals.keys.sorted(by: >).prefix(maxDays).map { day in
            let services = (totals[day] ?? [:])
                .map { OpenAIDashboardServiceUsage(service: $0.key, creditsUsed: $0.value) }
                .sorted {
                    if $0.creditsUsed == $1.creditsUsed { return $0.service < $1.service }
                    return $0.creditsUsed > $1.creditsUsed
                }
            return OpenAIDashboardDailyBreakdown(
                day: day,
                services: services,
                totalCreditsUsed: services.reduce(0) { $0 + $1.creditsUsed })
        }
    }

    private static func codexWindow(_ window: RateWindow?) -> CodexUsageSnapshot.Window? {
        guard let window, let resetAt = window.resetsAt else { return nil }
        return CodexUsageSnapshot.Window(
            usedPercent: Int(max(0, min(100, window.usedPercent)).rounded()),
            resetAt: resetAt,
            windowSeconds: max(0, window.windowMinutes ?? 0) * 60)
    }
}

public struct CreditEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var service: String
    public var creditsUsed: Double

    public init(id: UUID = UUID(), date: Date, service: String, creditsUsed: Double) {
        self.id = id
        self.date = date
        self.service = service
        self.creditsUsed = creditsUsed
    }
}

public struct OpenAIDashboardDailyBreakdown: Codable, Equatable, Sendable {
    public var day: String
    public var services: [OpenAIDashboardServiceUsage]
    public var totalCreditsUsed: Double

    public init(day: String, services: [OpenAIDashboardServiceUsage], totalCreditsUsed: Double) {
        self.day = day
        self.services = services
        self.totalCreditsUsed = totalCreditsUsed
    }

    public static func isSkillUsageService(_ service: String) -> Bool {
        service.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("skillusage:")
    }

    public static func removingSkillUsageServices(
        from breakdown: [OpenAIDashboardDailyBreakdown]
    ) -> [OpenAIDashboardDailyBreakdown] {
        breakdown.compactMap { day in
            guard !day.services.isEmpty else {
                return day.totalCreditsUsed > 0 ? day : nil
            }
            let services = day.services.filter { !isSkillUsageService($0.service) }
            guard !services.isEmpty else { return nil }
            return OpenAIDashboardDailyBreakdown(
                day: day.day,
                services: services,
                totalCreditsUsed: services.reduce(0) { $0 + $1.creditsUsed })
        }
    }
}

public struct OpenAIDashboardServiceUsage: Codable, Equatable, Sendable {
    public var service: String
    public var creditsUsed: Double

    public init(service: String, creditsUsed: Double) {
        self.service = service
        self.creditsUsed = creditsUsed
    }
}

public struct OpenAIDashboardCache: Codable, Equatable, Sendable {
    public var accountEmail: String
    public var snapshot: OpenAIDashboardSnapshot

    public init(accountEmail: String, snapshot: OpenAIDashboardSnapshot) {
        self.accountEmail = accountEmail
        self.snapshot = snapshot
    }
}

public struct OpenAIDashboardCreditHistory: Codable, Equatable, Sendable {
    public var accountEmail: String
    public var creditEvents: [CreditEvent]
    public var updatedAt: Date

    public init(accountEmail: String, creditEvents: [CreditEvent], updatedAt: Date = Date()) {
        self.accountEmail = accountEmail
        self.creditEvents = creditEvents
        self.updatedAt = updatedAt
    }
}

public enum OpenAIDashboardCreditHistoryStore {
    private static let maxStoredEvents = 1_000

    public static func load(accountEmail: String, cacheRoot: URL? = nil) -> OpenAIDashboardCreditHistory? {
        let normalized = normalizedEmail(accountEmail)
        guard !normalized.isEmpty else { return nil }
        let url = historyURL(accountEmail: normalized, cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OpenAIDashboardCreditHistory.self, from: data)
    }

    @discardableResult
    public static func mergeSnapshot(
        _ snapshot: OpenAIDashboardSnapshot,
        accountEmail: String,
        cacheRoot: URL? = nil
    ) -> OpenAIDashboardSnapshot {
        let normalized = normalizedEmail(accountEmail)
        guard !normalized.isEmpty else { return snapshot }

        let existing = load(accountEmail: normalized, cacheRoot: cacheRoot)
        let mergedEvents = mergedCreditEvents(
            existing: existing?.creditEvents ?? [],
            incoming: snapshot.creditEvents)

        save(
            OpenAIDashboardCreditHistory(
                accountEmail: normalized,
                creditEvents: mergedEvents,
                updatedAt: Date()),
            cacheRoot: cacheRoot)

        var mergedSnapshot = snapshot
        mergedSnapshot.creditEvents = mergedEvents
        mergedSnapshot.dailyBreakdown = OpenAIDashboardSnapshot.makeDailyBreakdown(from: mergedEvents, maxDays: 30)
        return mergedSnapshot
    }

    @discardableResult
    public static func clearAll(cacheRoot: URL? = nil) -> [URL] {
        let dir = historyDirectory(cacheRoot: cacheRoot)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        try? FileManager.default.removeItem(at: dir)
        return [dir]
    }

    public static func historyURL(accountEmail: String, cacheRoot: URL? = nil) -> URL {
        historyDirectory(cacheRoot: cacheRoot)
            .appendingPathComponent(historyFileName(accountEmail: accountEmail), isDirectory: false)
    }

    private static func save(_ history: OpenAIDashboardCreditHistory, cacheRoot: URL? = nil) {
        let url = historyURL(accountEmail: history.accountEmail, cacheRoot: cacheRoot)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(history) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func mergedCreditEvents(existing: [CreditEvent], incoming: [CreditEvent]) -> [CreditEvent] {
        var seen: Set<String> = []
        return (incoming + existing)
            .sorted {
                if $0.date == $1.date {
                    if $0.service == $1.service { return $0.creditsUsed > $1.creditsUsed }
                    return $0.service < $1.service
                }
                return $0.date > $1.date
            }
            .filter { event in
                seen.insert(stableEventKey(event)).inserted
            }
            .prefix(maxStoredEvents)
            .map { $0 }
    }

    private static func stableEventKey(_ event: CreditEvent) -> String {
        let timestamp = Int(event.date.timeIntervalSince1970.rounded())
        let service = event.service.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(timestamp)|\(service)|\(String(format: "%.6f", event.creditsUsed))"
    }

    private static func historyDirectory(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? OpenAIDashboardCacheStore.defaultCacheRoot()
        return root
            .appendingPathComponent("openai-dashboard", isDirectory: true)
            .appendingPathComponent("credit-history", isDirectory: true)
    }

    private static func historyFileName(accountEmail: String) -> String {
        let normalized = normalizedEmail(accountEmail)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-")
        let safe = normalized.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        return "\(safe)-\(fnv1a64Hex(normalized)).json"
    }

    private static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func fnv1a64Hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

public enum OpenAIDashboardCacheStore {
    public static func load(cacheRoot: URL? = nil) -> OpenAIDashboardCache? {
        let url = cacheURL(cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OpenAIDashboardCache.self, from: data)
    }

    public static func save(_ cache: OpenAIDashboardCache, cacheRoot: URL? = nil) {
        let snapshot = OpenAIDashboardCreditHistoryStore.mergeSnapshot(
            cache.snapshot,
            accountEmail: cache.accountEmail,
            cacheRoot: cacheRoot)
        let mergedCache = OpenAIDashboardCache(accountEmail: cache.accountEmail, snapshot: snapshot)
        let url = cacheURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(mergedCache) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    public static func clear(cacheRoot: URL? = nil) {
        try? FileManager.default.removeItem(at: cacheURL(cacheRoot: cacheRoot))
    }

    public static func reusableSnapshotForCLI(
        reportAccount: String?,
        usageAccountLabel: String?,
        sourceLabel: String,
        env: [String: String] = ProcessInfo.processInfo.environment,
        cacheRoot: URL? = nil
    ) -> OpenAIDashboardSnapshot? {
        guard let cache = load(cacheRoot: cacheRoot) else { return nil }
        let trustedUsageEmail = CodexIdentityResolver.firstEmail(in: usageAccountLabel)
            ?? CodexIdentityResolver.firstEmail(in: reportAccount)
        let input = CodexDashboardAuthorityContext.makeCachedDashboardInput(
            dashboard: cache.snapshot,
            cachedAccountEmail: cache.accountEmail,
            trustedUsageEmail: trustedUsageEmail,
            sourceLabel: sourceLabel,
            env: env)
        let decision = CodexDashboardAuthority.evaluate(input)
        if decision.allowedEffects.contains(.cachedDashboardReuse) {
            return OpenAIDashboardCreditHistoryStore.mergeSnapshot(
                cache.snapshot,
                accountEmail: cache.accountEmail,
                cacheRoot: cacheRoot)
        }
        if decision.cleanup.contains(.dashboardCache) {
            clear(cacheRoot: cacheRoot)
        }
        return nil
    }

    public static func cacheURL(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? defaultCacheRoot()
        return root
            .appendingPathComponent("openai-dashboard", isDirectory: true)
            .appendingPathComponent("codex-dashboard.json", isDirectory: false)
    }

    public static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Conductor", isDirectory: true)
    }

}

public struct OpenAIDashboardFoundAccount: Equatable, Sendable {
    public let sourceLabel: String
    public let email: String

    public init(sourceLabel: String, email: String) {
        self.sourceLabel = sourceLabel
        self.email = email
    }
}

public struct OpenAIDashboardCookieImportFailure: Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case noCookiesFound
        case browserAccessDenied
        case helperTimedOut
        case noMatchingAccount
        case manualCookieHeaderInvalid
        case missingVerifiedEmail
    }

    public let reason: Reason
    public let details: String?
    public let foundAccounts: [OpenAIDashboardFoundAccount]

    public init(
        reason: Reason,
        details: String? = nil,
        foundAccounts: [OpenAIDashboardFoundAccount] = []
    ) {
        self.reason = reason
        self.details = details
        self.foundAccounts = foundAccounts
    }

    var errorDescription: String {
        switch reason {
        case .noCookiesFound:
            return L("未在浏览器中找到可用的 OpenAI web session Cookie。")
        case .browserAccessDenied:
            if let details, !details.isEmpty {
                return L("浏览器 Cookie 读取被拒绝：%@", details)
            }
            return L("浏览器 Cookie 读取被拒绝。")
        case .helperTimedOut:
            if let details, !details.isEmpty {
                return L("浏览器 Cookie helper 超时：%@", details)
            }
            return L("浏览器 Cookie helper 超时。")
        case .noMatchingAccount:
            let found = foundAccounts
                .sorted { lhs, rhs in
                    if lhs.sourceLabel == rhs.sourceLabel { return lhs.email < rhs.email }
                    return lhs.sourceLabel < rhs.sourceLabel
                }
                .map { "\($0.sourceLabel)=\($0.email)" }
                .joined(separator: ", ")
            if found.isEmpty {
                return L("浏览器中没有匹配当前 Codex 账号的 OpenAI web session。")
            }
            return L("OpenAI web session 与当前 Codex 账号不匹配（找到：%@）。", found)
        case .manualCookieHeaderInvalid:
            return L("手动 Cookie header 缺少有效的 OpenAI session cookie。")
        case .missingVerifiedEmail:
            if let details, !details.isEmpty {
                return L("OpenAI web session 无法验证账号邮箱：%@", details)
            }
            return L("OpenAI web session 无法验证账号邮箱。")
        }
    }

    var diagnosticCategory: String {
        switch reason {
        case .noMatchingAccount:
            return "configuration"
        case .browserAccessDenied, .helperTimedOut, .manualCookieHeaderInvalid, .missingVerifiedEmail, .noCookiesFound:
            return "auth"
        }
    }
}

public enum OpenAIDashboardUsageError: LocalizedError, Sendable {
    case noSession
    case cookieImportFailed(OpenAIDashboardCookieImportFailure)
    case batterySaverSkipped
    case unauthorized
    case invalidResponse
    case noDashboardData(String)
    case policyRejected(CodexDashboardAuthorityDecision)
    case server(Int)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noSession: L("OpenAI dashboard 需要 ChatGPT Cookie。请粘贴 Cookie 或允许浏览器读取。")
        case let .cookieImportFailed(failure): failure.errorDescription
        case .batterySaverSkipped: L("OpenAI Web Battery Saver 已跳过后台 dashboard 刷新；请手动刷新以更新 Web 数据。")
        case .unauthorized: L("OpenAI dashboard 登录态已过期，请重新登录 ChatGPT。")
        case .invalidResponse: L("OpenAI dashboard 返回异常")
        case let .noDashboardData(sample): L("OpenAI dashboard 未返回可用用量数据：%@", String(sample.prefix(160)))
        case let .policyRejected(decision): decision.policyErrorDescription
        case let .server(code): L("OpenAI dashboard 接口错误（%ld）", code)
        case let .network(message): L("OpenAI dashboard 网络错误：%@", message)
        }
    }

    public func diagnosticCategory(authConfigured: Bool) -> String {
        switch self {
        case .noSession, .unauthorized:
            return "auth"
        case let .cookieImportFailed(failure):
            return failure.diagnosticCategory
        case .batterySaverSkipped:
            return "configuration"
        case .invalidResponse:
            return "parse"
        case let .noDashboardData(sample):
            return Self.sampleLooksLikeCloudflare(sample) ? "network" : "parse"
        case let .policyRejected(decision):
            return decision.diagnosticCategory(authConfigured: authConfigured)
        case .server:
            return "api"
        case .network:
            return "network"
        }
    }

    private static func sampleLooksLikeCloudflare(_ sample: String) -> Bool {
        let lower = sample.lowercased()
        return lower.contains("cloudflare") ||
            lower.contains("captcha") ||
            lower.contains("challenge") ||
            lower.contains("turnstile") ||
            lower.contains("cf-ray") ||
            lower.contains("验证码")
    }
}

public enum OpenAIDashboardParser {
    public static func parseSignedInEmailFromClientBootstrap(html: String) -> String? {
        guard let data = clientBootstrapJSONData(fromHTML: html),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        return findFirstEmail(in: json)
    }

    public static func parseAuthStatusFromClientBootstrap(html: String) -> String? {
        guard let data = clientBootstrapJSONData(fromHTML: html),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["authStatus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parsePlanFromHTML(html: String) -> String? {
        for data in [clientBootstrapJSONData(fromHTML: html), nextDataJSONData(fromHTML: html)].compactMap(\.self) {
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let plan = findPlan(in: json)
            else { continue }
            return plan
        }
        return nil
    }

    public static func parseCodeReviewRemainingPercent(bodyText: String) -> Double? {
        let cleaned = bodyText.replacingOccurrences(of: "\r", with: "\n")
        let patterns = [
            #"Code\s*review[^0-9%]*([0-9]{1,3})%\s*remaining"#,
            #"Core\s*review[^0-9%]*([0-9]{1,3})%\s*remaining"#,
        ]
        for pattern in patterns {
            if let value = TextParsing.firstNumber(pattern: pattern, text: cleaned) {
                return min(100, max(0, value))
            }
        }
        return nil
    }

    public static func parseCreditsRemaining(bodyText: String) -> Double? {
        let cleaned = bodyText.replacingOccurrences(of: "\r", with: "\n")
        let patterns = [
            #"credits\s*remaining[^0-9]*([0-9][0-9.,]*)"#,
            #"remaining\s*credits[^0-9]*([0-9][0-9.,]*)"#,
            #"credit\s*balance[^0-9]*([0-9][0-9.,]*)"#,
        ]
        for pattern in patterns {
            if let value = TextParsing.firstNumber(pattern: pattern, text: cleaned) { return value }
        }
        return nil
    }

    public static func parseRateLimits(
        bodyText: String,
        now: Date = Date()
    ) -> (primary: RateWindow?, secondary: RateWindow?) {
        let lines = bodyText
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (
            parseRateWindow(lines: lines, match: isFiveHourLimitLine, windowMinutes: 5 * 60, now: now),
            parseRateWindow(lines: lines, match: isWeeklyLimitLine, windowMinutes: 7 * 24 * 60, now: now))
    }

    public static func parseCodeReviewLimit(bodyText: String, now: Date = Date()) -> RateWindow? {
        let lines = bodyText
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var window = parseRateWindow(lines: lines, match: isCodeReviewLimitLine, windowMinutes: nil, now: now)
        window?.title = L("代码审查")
        return window
    }

    public static func parseCreditEvents(rows: [[String]]) -> [CreditEvent] {
        return rows.compactMap { row in
            guard row.count >= 3,
                  let date = parseCreditDate(row[0])
            else { return nil }
            return CreditEvent(
                date: date,
                service: row[1].trimmingCharacters(in: .whitespacesAndNewlines),
                creditsUsed: parseCreditsUsed(row[2]))
        }
        .sorted { $0.date > $1.date }
    }

    public static func parseCreditEvents(fromHTML html: String) -> [CreditEvent] {
        parseCreditEvents(rows: parseCreditRows(fromHTML: html))
    }

    public static func parseCreditRows(fromHTML html: String) -> [[String]] {
        let focusedHTML = htmlAfterCreditsHistoryHeading(html) ?? html
        let focusedRows = tableRows(fromHTML: focusedHTML)
        if !focusedRows.isEmpty { return focusedRows }
        return tableRows(fromHTML: html)
    }

    public static func parseUsageBreakdownJSON(_ raw: String) -> [OpenAIDashboardDailyBreakdown] {
        let trimmed = decodeHTMLEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let decoded = decodeUsageBreakdownArray(from: trimmed) {
            return OpenAIDashboardDailyBreakdown.removingSkillUsageServices(from: decoded)
        }

        if let stringLiteral = decodeJSONStringLiteral(trimmed),
           let decoded = decodeUsageBreakdownArray(from: stringLiteral)
        {
            return OpenAIDashboardDailyBreakdown.removingSkillUsageServices(from: decoded)
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data)
        {
            for candidate in usageBreakdownCandidates(in: object) {
                let parsed = parseUsageBreakdownJSON(candidate)
                if !parsed.isEmpty { return parsed }
            }
        }

        return []
    }

    public static func parseUsageBreakdown(fromHTML html: String) -> [OpenAIDashboardDailyBreakdown] {
        let markers = [
            "__codexbarUsageBreakdownJSON",
            "usageBreakdownJSON",
            "usageBreakdown",
        ]
        for raw in extractedJSONValues(afterMarkers: markers, in: html) {
            let parsed = parseUsageBreakdownJSON(raw)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    public static func bodyText(fromHTML html: String) -> String {
        let stripped = html
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "\n", options: .regularExpression)
        return decodeHTMLEntities(stripped)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func findFirstEmail(inJSONData data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return findFirstEmail(in: json)
    }

    private struct UsageBreakdownDayPayload: Decodable {
        var day: String
        var services: [UsageBreakdownServicePayload]
        var totalCreditsUsed: Double?

        private enum CodingKeys: String, CodingKey {
            case day
            case services
            case totalCreditsUsed
        }

        func model() -> OpenAIDashboardDailyBreakdown? {
            let normalizedDay = day.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedDay.isEmpty else { return nil }
            let serviceModels = services
                .map(\.model)
                .filter { !$0.service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .filter { $0.creditsUsed > 0 }
                .sorted {
                    if $0.creditsUsed == $1.creditsUsed { return $0.service < $1.service }
                    return $0.creditsUsed > $1.creditsUsed
                }
            let total = totalCreditsUsed ?? serviceModels.reduce(0) { $0 + $1.creditsUsed }
            guard total > 0 || !serviceModels.isEmpty else { return nil }
            return OpenAIDashboardDailyBreakdown(
                day: normalizedDay,
                services: serviceModels,
                totalCreditsUsed: total)
        }
    }

    private struct UsageBreakdownServicePayload: Decodable {
        var model: OpenAIDashboardServiceUsage

        private enum CodingKeys: String, CodingKey {
            case service
            case creditsUsed
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let service = (try? container.decode(String.self, forKey: .service)) ?? ""
            let creditsUsed =
                (try? container.decode(Double.self, forKey: .creditsUsed))
                ?? (try? container.decode(Int.self, forKey: .creditsUsed)).map(Double.init)
                ?? (try? container.decode(String.self, forKey: .creditsUsed)).map(parseCreditsUsed)
                ?? 0
            self.model = OpenAIDashboardServiceUsage(service: service, creditsUsed: creditsUsed)
        }
    }

    private static func decodeUsageBreakdownArray(from raw: String) -> [OpenAIDashboardDailyBreakdown]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([OpenAIDashboardDailyBreakdown].self, from: data) {
            return decoded
        }
        if let payload = try? decoder.decode([UsageBreakdownDayPayload].self, from: data) {
            let decoded = payload.compactMap { $0.model() }
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }

    private static func usageBreakdownCandidates(in object: Any) -> [String] {
        var candidates: [String] = []
        var queue: [Any] = [object]
        var seen = 0
        while !queue.isEmpty, seen < 6000 {
            let current = queue.removeFirst()
            seen += 1
            if let array = current as? [Any] {
                if looksLikeUsageBreakdownArray(array),
                   let string = jsonString(from: array)
                {
                    candidates.append(string)
                }
                queue.append(contentsOf: array)
                continue
            }
            guard let dict = current as? [String: Any] else { continue }
            for (key, value) in dict {
                let normalizedKey = key.replacingOccurrences(of: "_", with: "").lowercased()
                if normalizedKey == "usagebreakdownjson" || normalizedKey == "usagebreakdown" {
                    if let string = value as? String {
                        candidates.append(string)
                    } else if let string = jsonString(from: value) {
                        candidates.append(string)
                    }
                }
                if value is [String: Any] || value is [Any] {
                    queue.append(value)
                }
            }
        }
        return candidates
    }

    private static func looksLikeUsageBreakdownArray(_ array: [Any]) -> Bool {
        guard let first = array.first as? [String: Any] else { return false }
        return first["day"] != nil && first["services"] != nil
    }

    private static func jsonString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    private static func extractedJSONValues(afterMarkers markers: [String], in text: String) -> [String] {
        var values: [String] = []
        for marker in markers {
            var searchRange = text.startIndex..<text.endIndex
            while let markerRange = text.range(of: marker, options: [.caseInsensitive], range: searchRange) {
                let suffix = text[markerRange.upperBound...]
                if let separator = suffix.firstIndex(where: { $0 == ":" || $0 == "=" }) {
                    let afterSeparator = suffix[suffix.index(after: separator)...]
                    if let value = extractJSONValue(from: afterSeparator) {
                        values.append(value)
                    }
                }
                searchRange = markerRange.upperBound..<text.endIndex
            }
        }

        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private static func extractJSONValue(from text: Substring) -> String? {
        var start = text.startIndex
        while start < text.endIndex, isSkippableJSONPrefix(text[start]) {
            start = text.index(after: start)
        }
        guard start < text.endIndex else { return nil }
        let first = text[start]
        if first == "\"" || first == "'" {
            return extractQuotedValue(from: text[start...], delimiter: first)
        }
        if first == "[" || first == "{" {
            return extractBalancedValue(from: text[start...], opening: first)
        }
        return nil
    }

    private static func isSkippableJSONPrefix(_ character: Character) -> Bool {
        character == " "
            || character == "\n"
            || character == "\r"
            || character == "\t"
            || character == ";"
            || character == "("
    }

    private static func extractQuotedValue(from text: Substring, delimiter: Character) -> String? {
        var escaped = false
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == delimiter {
                return String(text[text.startIndex...index])
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func extractBalancedValue(from text: Substring, opening: Character) -> String? {
        let closing: Character = opening == "[" ? "]" : "}"
        var depth = 0
        var stringDelimiter: Character?
        var escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let delimiter = stringDelimiter {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == delimiter {
                    stringDelimiter = nil
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" || character == "'" {
                stringDelimiter = character
            } else if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return String(text[text.startIndex...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func decodeJSONStringLiteral(_ literal: String) -> String? {
        let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last else { return nil }
        if first == "\"", let data = trimmed.data(using: .utf8) {
            return try? JSONDecoder().decode(String.self, from: data)
        }
        guard first == "'", last == "'" else { return nil }
        var output = ""
        var escaped = false
        for character in trimmed.dropFirst().dropLast() {
            if escaped {
                switch character {
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                case "\\": output.append("\\")
                case "\"": output.append("\"")
                case "'": output.append("'")
                default: output.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                output.append(character)
            }
        }
        return output
    }

    private static func htmlAfterCreditsHistoryHeading(_ html: String) -> String? {
        guard let range = html.range(
            of: #"(?is)<h[1-3]\b[^>]*>.*?credits\s+usage\s+history.*?</h[1-3]>"#,
            options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return String(html[range.lowerBound...].prefix(120_000))
    }

    private static func tableRows(fromHTML html: String) -> [[String]] {
        regexCaptures(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr>"#, text: html).compactMap { rowHTML in
            let cells = regexCaptures(pattern: #"(?is)<t[dh]\b[^>]*>(.*?)</t[dh]>"#, text: rowHTML)
                .map(textFromHTMLFragment)
                .filter { !$0.isEmpty }
            guard looksLikeCreditsEventRow(cells) else { return nil }
            return cells
        }
    }

    private static func looksLikeCreditsEventRow(_ cells: [String]) -> Bool {
        guard cells.count >= 3 else { return false }
        return parseCreditDate(cells[0]) != nil
            && cells[2].range(of: #"\d"#, options: .regularExpression) != nil
    }

    private static func regexCaptures(pattern: String, text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let capture = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[capture])
        }
    }

    private static func textFromHTMLFragment(_ html: String) -> String {
        let stripped = html
            .replacingOccurrences(of: #"(?is)<script\b[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style\b[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
        return collapseWhitespace(decodeHTMLEntities(stripped))
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&#xA0;", with: " ")
            .replacingOccurrences(of: "&#8239;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")

        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#) else {
            return decoded
        }
        let range = NSRange(decoded.startIndex..<decoded.endIndex, in: decoded)
        for match in regex.matches(in: decoded, options: [], range: range).reversed() {
            guard match.numberOfRanges >= 2,
                  let fullRange = Range(match.range(at: 0), in: decoded),
                  let entityRange = Range(match.range(at: 1), in: decoded)
            else { continue }
            let raw = String(decoded[entityRange])
            let scalarValue: UInt32?
            if raw.lowercased().hasPrefix("x") {
                scalarValue = UInt32(raw.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(raw, radix: 10)
            }
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            decoded.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return decoded
    }

    private static func parseCreditDate(_ raw: String) -> Date? {
        let cleaned = collapseWhitespace(decodeHTMLEntities(raw))
        guard !cleaned.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.isLenient = false
        for format in [
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "yyyy-MM-dd",
            "M/d/yyyy",
            "M/d/yy",
            "MM/dd/yyyy",
            "MM/dd/yy",
            "M-d-yyyy",
            "M.d.yyyy",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }

    private static func parseRateWindow(
        lines: [String],
        match: (String) -> Bool,
        windowMinutes: Int?,
        now: Date
    ) -> RateWindow? {
        for index in lines.indices where match(lines[index]) {
            let windowLines = Array(lines[index...min(lines.count - 1, index + 5)])
            var percentValue: Double?
            var isRemaining = true
            for line in windowLines {
                if let percent = parsePercent(from: line) {
                    percentValue = percent.value
                    isRemaining = percent.isRemaining
                    break
                }
            }
            guard let percentValue else { continue }
            let used = isRemaining ? 100 - percentValue : percentValue
            let resetLine = windowLines.first { $0.localizedCaseInsensitiveContains("reset") }
            let resetsAt = resetLine.flatMap { parseResetDate(from: $0, now: now) }
            return RateWindow(
                usedPercent: max(0, min(100, used)),
                windowMinutes: windowMinutes,
                resetsAt: resetsAt,
                resetDescription: resetLine?.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func parsePercent(from line: String) -> (value: Double, isRemaining: Bool)? {
        guard let percent = TextParsing.firstNumber(pattern: #"([0-9]{1,3})\s*%"#, text: line) else { return nil }
        let lower = line.lowercased()
        if lower.contains("used") || lower.contains("spent") || lower.contains("consumed") {
            return (percent, false)
        }
        return (percent, true)
    }

    private static func isFiveHourLimitLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("5h")
            || lower.range(of: #"\b5\s*h\b"#, options: .regularExpression) != nil
            || lower.contains("5-hour")
            || lower.contains("5 hour")
    }

    private static func isWeeklyLimitLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("weekly")
            || lower.contains("7-day")
            || lower.contains("7 day")
            || lower.contains("7d")
            || lower.range(of: #"\b7\s*d\b"#, options: .regularExpression) != nil
    }

    private static func isCodeReviewLimitLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return (lower.contains("code review") || lower.contains("core review"))
            && !lower.contains("github code review")
    }

    private static func parseResetDate(from line: String, now: Date) -> Date? {
        var raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: #"(?i)^resets?:?\s*"#, with: "", options: .regularExpression)
        raw = raw.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: " on ", with: " ", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let calendar = Calendar(identifier: .gregorian)
        let monthDayFormatter = DateFormatter()
        monthDayFormatter.locale = Locale(identifier: "en_US_POSIX")
        monthDayFormatter.timeZone = TimeZone.current
        monthDayFormatter.dateFormat = "MMM d"

        var candidate = raw
        let lower = candidate.lowercased()
        var usedRelativeDay = false
        if lower.contains("today") {
            usedRelativeDay = true
            candidate = candidate.replacingOccurrences(
                of: "today",
                with: monthDayFormatter.string(from: now),
                options: .caseInsensitive)
        } else if lower.contains("tomorrow"),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
        {
            usedRelativeDay = true
            candidate = candidate.replacingOccurrences(
                of: "tomorrow",
                with: monthDayFormatter.string(from: tomorrow),
                options: .caseInsensitive)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.defaultDate = now
        for format in ["MMM d h:mma", "MMM d, h:mma", "MMM d h:mm a", "MMM d, h:mm a", "MMM d HH:mm",
                       "MMM d, HH:mm", "MMM d", "M/d h:mma", "M/d h:mm a", "M/d/yyyy h:mm a",
                       "M/d/yy h:mm a", "M/d", "yyyy-MM-dd HH:mm", "yyyy-MM-dd h:mm a", "yyyy-MM-dd"]
        {
            formatter.dateFormat = format
            guard let date = formatter.date(from: candidate) else { continue }
            if usedRelativeDay, date < now,
               let bumped = calendar.date(byAdding: lower.contains("today") ? .day : .day,
                                          value: lower.contains("today") ? 1 : 7,
                                          to: date)
            {
                return bumped
            }
            return date
        }
        return nil
    }

    private static func parseCreditsUsed(_ text: String) -> Double {
        guard let range = text.range(of: #"([0-9][0-9.,\s\u{00A0}\u{202F}]*)"#, options: .regularExpression) else {
            return 0
        }
        let token = text[range]
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
        let hasComma = token.contains(",")
        let hasDot = token.contains(".")
        if hasComma, hasDot { return Double(token.replacingOccurrences(of: ",", with: "")) ?? 0 }
        if hasComma {
            if token.range(of: #"^\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil {
                return Double(token.replacingOccurrences(of: ",", with: "")) ?? 0
            }
            return Double(token.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        if hasDot, token.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil {
            return Double(token.replacingOccurrences(of: ".", with: "")) ?? 0
        }
        return Double(token) ?? 0
    }

    private static func clientBootstrapJSONData(fromHTML html: String) -> Data? {
        scriptJSONData(fromHTML: html, idNeedle: #"id="client-bootstrap""#)
    }

    private static func nextDataJSONData(fromHTML html: String) -> Data? {
        scriptJSONData(fromHTML: html, idNeedle: #"id="__NEXT_DATA__""#)
    }

    private static func scriptJSONData(fromHTML html: String, idNeedle: String) -> Data? {
        let data = Data(html.utf8)
        guard let idRange = data.range(of: Data(idNeedle.utf8)),
              let openTagEnd = data[idRange.upperBound...].firstIndex(of: UInt8(ascii: ">"))
        else { return nil }
        let contentStart = data.index(after: openTagEnd)
        guard let closeRange = data.range(of: Data("</script>".utf8), in: contentStart..<data.endIndex) else {
            return nil
        }
        let raw = data[contentStart..<closeRange.lowerBound]
        let trimmed = trimASCIIWhitespace(Data(raw))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimASCIIWhitespace(_ data: Data) -> Data {
        var start = data.startIndex
        var end = data.endIndex
        while start < end, data[start].isASCIIWhitespace { start = data.index(after: start) }
        while end > start {
            let prev = data.index(before: end)
            guard data[prev].isASCIIWhitespace else { break }
            end = prev
        }
        return data.subdata(in: start..<end)
    }

    private static func findFirstEmail(in json: Any) -> String? {
        var queue: [Any] = [json]
        var seen = 0
        while !queue.isEmpty, seen < 4000 {
            let current = queue.removeFirst()
            seen += 1
            if let string = current as? String, string.contains("@") {
                return string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let dict = current as? [String: Any] {
                for (key, value) in dict {
                    if key.lowercased() == "email",
                       let string = value as? String,
                       string.contains("@")
                    {
                        return string.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    queue.append(value)
                }
            } else if let array = current as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return nil
    }

    private static func findPlan(in json: Any) -> String? {
        var queue: [Any] = [json]
        var seen = 0
        while !queue.isEmpty, seen < 6000 {
            let current = queue.removeFirst()
            seen += 1
            if let dict = current as? [String: Any] {
                for (key, value) in dict {
                    if let plan = planCandidate(forKey: key, value: value) { return plan }
                    queue.append(value)
                }
            } else if let array = current as? [Any] {
                queue.append(contentsOf: array)
            }
        }
        return nil
    }

    private static func planCandidate(forKey key: String, value: Any) -> String? {
        let lower = key.lowercased()
        guard lower.contains("plan") || lower.contains("tier") || lower.contains("subscription") else { return nil }
        if let string = value as? String { return normalizePlan(string) }
        if let dict = value as? [String: Any] {
            for key in ["name", "displayName", "tier"] {
                if let value = dict[key] as? String, let plan = normalizePlan(value) { return plan }
            }
        }
        return nil
    }

    private static func normalizePlan(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        let lower = trimmed.lowercased()
        guard lower != "none", lower != "unknown", lower != "free_trial_ended" else { return nil }
        return trimmed
    }
}

enum OpenAIDashboardCookieCandidateEvaluation: Equatable {
    case accepted(signedInEmail: String?)
    case rejectedNoSession
    case rejectedMissingVerifiedEmail(expected: String)
    case rejectedWrongEmail(expected: String, actual: String)
}

public enum OpenAIDashboardUsageFetcher {
    private static let usageAPIURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let usagePageURL = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")!
    private static let dashboardAcceptLanguage = "en-US,en;q=0.9"
    private static let cookieDomains = ["chatgpt.com", "openai.com"]

    public static func hasManualCookie(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        UsageProviderRuntimeConfig.manualCookieHeader(providerID: "codex", env: env) != nil
    }

    public static func cachedSnapshotForBatterySaver(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> OpenAIDashboardSnapshot? {
        OpenAIDashboardCacheStore.reusableSnapshotForCLI(
            reportAccount: nil,
            usageAccountLabel: authBackedAccountEmail(env: env),
            sourceLabel: "openai-web-battery-saver",
            env: env)
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) async throws -> OpenAIDashboardSnapshot {
        let debugLog = OpenAIWebDebugLog.shared
        debugLog.reset(context: "fetch")
        debugLog.updateStatus(L("正在准备 OpenAI Web 刷新…"))
        let logger = debugLog.logger()
        let source = UsageProviderRuntimeConfig.sourceMode(providerID: "codex", env: env) ?? "auto"
        let cookieSource = UsageProviderRuntimeConfig.cookieSource(providerID: "codex", env: env) ?? "auto"
        logger("source=\(source) cookieSource=\(cookieSource) webTimeout=\(webKitTimeout(env: env))")

        let resolved = try await resolvedCookieHeader(
            env: env,
            preferCached: true,
            session: session,
            logger: logger)
        logger("resolved cookies from \(resolved.sourceLabel), cached=\(resolved.loadedFromCache), snapshots=\(resolved.cookieSnapshots.count)")
        do {
            let snapshot = try await fetch(
                cookieHeader: resolved.cookieHeader,
                cookieSnapshots: resolved.cookieSnapshots,
                env: env,
                session: session,
                replaceWebKitCookies: !resolved.loadedFromCache,
                logger: logger)
            storeCookieHeaderIfNeeded(resolved)
            debugLog.updateStatus(L("OpenAI Web 快照已更新。"))
            logger("snapshot ready: hasData=\(snapshot.hasReturnableData), email=\(snapshot.signedInEmail ?? "unknown"), events=\(snapshot.creditEvents.count), usageBreakdown=\(snapshot.usageBreakdown.count)")
            return snapshot
        } catch {
            guard resolved.loadedFromCache,
                  shouldRetryWithFreshBrowserCookie(after: error)
            else {
                debugLog.updateStatus(L("OpenAI Web 刷新失败：%@", error.localizedDescription))
                logger("fetch failed: \(error.localizedDescription)")
                throw error
            }
            logger("cached cookies failed; retrying with fresh browser cookies: \(error.localizedDescription)")
            CookieHeaderCache.clear(providerID: "codex", scope: resolved.cacheScope)
            let fresh = try await resolvedCookieHeader(
                env: env,
                preferCached: false,
                session: session,
                logger: logger)
            logger("resolved fresh cookies from \(fresh.sourceLabel), snapshots=\(fresh.cookieSnapshots.count)")
            let snapshot = try await fetch(
                cookieHeader: fresh.cookieHeader,
                cookieSnapshots: fresh.cookieSnapshots,
                env: env,
                session: session,
                replaceWebKitCookies: true,
                logger: logger)
            storeCookieHeaderIfNeeded(fresh)
            debugLog.updateStatus(L("OpenAI Web 快照已更新。"))
            logger("snapshot ready after retry: hasData=\(snapshot.hasReturnableData), email=\(snapshot.signedInEmail ?? "unknown"), events=\(snapshot.creditEvents.count), usageBreakdown=\(snapshot.usageBreakdown.count)")
            return snapshot
        }
    }

    private static func fetch(
        cookieHeader: String,
        cookieSnapshots: [OpenAIDashboardCookieSnapshot],
        env: [String: String],
        session: URLSession,
        replaceWebKitCookies: Bool,
        logger: (@Sendable (String) -> Void)?
    ) async throws -> OpenAIDashboardSnapshot {
        let expectedEmail = authBackedAccountEmail(env: env)
        logger?("expected account email=\(expectedEmail ?? "unresolved")")

        async let apiSnapshotTask = fetchUsageAPI(
            cookieHeader: cookieHeader,
            session: session,
            timeout: webRequestTimeout(env: env, defaultValue: 10),
            logger: logger)
        async let emailTask = fetchSignedInEmail(
            cookieHeader: cookieHeader,
            session: session,
            timeout: webRequestTimeout(env: env, defaultValue: 5),
            logger: logger)
        async let htmlTask = fetchUsageHTML(
            cookieHeader: cookieHeader,
            session: session,
            timeout: webRequestTimeout(env: env, defaultValue: 15),
            logger: logger)

        let apiSnapshot = try? await apiSnapshotTask
        let signedInEmail = try? await emailTask
        let html = try? await htmlTask
        let htmlBody = html.map(OpenAIDashboardParser.bodyText(fromHTML:)) ?? ""
        let parsedRateLimits = OpenAIDashboardParser.parseRateLimits(bodyText: htmlBody)
        let codeReviewLimit = OpenAIDashboardParser.parseCodeReviewLimit(bodyText: htmlBody)
        let codeReviewRemaining = OpenAIDashboardParser.parseCodeReviewRemainingPercent(bodyText: htmlBody)
        let htmlCreditsRemaining = OpenAIDashboardParser.parseCreditsRemaining(bodyText: htmlBody)
        let htmlEmail = html.flatMap(OpenAIDashboardParser.parseSignedInEmailFromClientBootstrap)
        let htmlPlan = html.flatMap(OpenAIDashboardParser.parsePlanFromHTML)
        let creditEvents = html.map(OpenAIDashboardParser.parseCreditEvents(fromHTML:)) ?? []
        let dailyBreakdown = OpenAIDashboardSnapshot.makeDailyBreakdown(from: creditEvents, maxDays: 30)
        let usageBreakdown = html.map(OpenAIDashboardParser.parseUsageBreakdown(fromHTML:)) ?? []
        let usageSnapshot = apiSnapshot.map(UsageSnapshot.init(codexSnapshot:))

        let baseSnapshot = OpenAIDashboardSnapshot(
            signedInEmail: firstNonEmpty(signedInEmail, htmlEmail, apiSnapshot?.accountLabel),
            codeReviewRemainingPercent: codeReviewRemaining,
            codeReviewLimit: codeReviewLimit,
            creditEvents: creditEvents,
            dailyBreakdown: dailyBreakdown,
            usageBreakdown: usageBreakdown,
            creditsPurchaseURL: creditsPurchaseURL(fromHTML: html),
            primaryLimit: usageSnapshot?.primary ?? parsedRateLimits.primary,
            secondaryLimit: usageSnapshot?.secondary ?? parsedRateLimits.secondary,
            extraRateWindows: apiSnapshot?.extraRateWindows.isEmpty == false ? apiSnapshot?.extraRateWindows : nil,
            creditsRemaining: apiSnapshot?.providerCost?.used ?? htmlCreditsRemaining,
            accountPlan: firstNonEmpty(htmlPlan, apiSnapshot?.planType),
            updatedAt: Date())

        let snapshot: OpenAIDashboardSnapshot
        var webKitNoDataSample: String?
        #if os(macOS) && canImport(WebKit)
        do {
            let webKitAccountEmail = firstNonEmpty(
                expectedEmail,
                signedInEmail,
                htmlEmail,
                apiSnapshot?.accountLabel)
            let hydrated = try await OpenAIDashboardWebKitUsageFetcher.fetch(
                cookieHeader: cookieHeader,
                cookieSnapshots: cookieSnapshots,
                accountEmail: webKitAccountEmail,
                timeout: webKitTimeout(env: env),
                debugDumpHTML: webDebugDumpHTML(env: env),
                replaceExistingCookies: replaceWebKitCookies,
                logger: logger)
            logger?("webkit hydrated: email=\(hydrated.signedInEmail ?? "unknown"), events=\(hydrated.creditEvents.count), usageBreakdown=\(hydrated.usageBreakdown.count)")
            snapshot = merge(base: baseSnapshot, hydrated: hydrated)
        } catch let error as OpenAIDashboardUsageError {
            if case let .noDashboardData(sample) = error {
                webKitNoDataSample = sample
            }
            logger?("webkit fallback: \(error.localizedDescription)")
            snapshot = baseSnapshot
        } catch {
            try UsageProviderCancellation.rethrowIfCancelled(error)
            logger?("webkit fallback: \(error.localizedDescription)")
            snapshot = baseSnapshot
        }
        #else
        snapshot = baseSnapshot
        #endif

        guard snapshot.hasReturnableData else {
            throw OpenAIDashboardUsageError.noDashboardData(firstNonEmpty(webKitNoDataSample, htmlBody) ?? "")
        }
        try validateDashboardOwnership(snapshot: snapshot, expectedEmail: expectedEmail, env: env)
        if let email = snapshot.signedInEmail {
            OpenAIDashboardCacheStore.save(OpenAIDashboardCache(accountEmail: email, snapshot: snapshot))
        }
        return snapshot
    }

    static func cookieHeader(env: [String: String]) -> String? {
        staticCookieHeader(env: env, preferCached: true)?.cookieHeader
    }

    static func cookieHeaderCandidates(env: [String: String]) -> [String] {
        staticCookieHeader(env: env, preferCached: true).map { [$0.cookieHeader] } ?? []
    }

    private struct ResolvedCookieHeader {
        let cookieHeader: String
        let cookieSnapshots: [OpenAIDashboardCookieSnapshot]
        let sourceLabel: String
        let cacheScope: CookieHeaderCache.Scope?
        let loadedFromCache: Bool
        let shouldStore: Bool
    }

    private static func resolvedCookieHeader(
        env: [String: String],
        preferCached: Bool,
        session: URLSession,
        selectionDeadline existingSelectionDeadline: Date? = nil,
        logger: (@Sendable (String) -> Void)?
    ) async throws -> ResolvedCookieHeader {
        let expectedEmail = authBackedAccountEmail(env: env)
        let validationTimeout = webRequestTimeout(env: env, defaultValue: 5)
        let selectionDeadline = existingSelectionDeadline
            ?? Date().addingTimeInterval(cookieSelectionBudget(perRequestTimeout: validationTimeout))
        var diagnostics = CookieSelectionDiagnostics()
        OpenAIWebDebugLog.shared.updateStatus(L("正在选择 OpenAI Cookie…"))
        logger?("cookie selection preferCached=\(preferCached), expectedEmail=\(expectedEmail ?? "unresolved"), timeout=\(validationTimeout)")

        func remainingSelectionTimeout(
            label: String,
            cappedAt localLimit: TimeInterval? = nil
        ) throws -> TimeInterval {
            do {
                return try remainingCookieSelectionTimeout(
                    until: selectionDeadline,
                    cappedAt: localLimit)
            } catch let error as URLError where error.code == .timedOut {
                diagnostics.helperTimedOutBrowsers.append(label)
                logger?("cookie selection timed out while processing \(label)")
                throw OpenAIDashboardUsageError.cookieImportFailed(diagnostics.failure())
            }
        }

        if let manual = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "codex", env: env) {
            OpenAIWebDebugLog.shared.updateStatus(L("正在验证手动 OpenAI Cookie…"))
            logger?("evaluating manual cookie header")
            let evaluationTimeout = try remainingSelectionTimeout(
                label: "manual",
                cappedAt: validationTimeout)
            let evaluation = await evaluateCookieCandidate(
                cookieHeader: manual,
                expectedEmail: expectedEmail,
                sourceLabel: "manual",
                session: session,
                timeout: evaluationTimeout,
                logger: logger)
            logger?("manual cookie evaluation: \(cookieEvaluationDescription(evaluation))")
            guard candidateAccepted(
                evaluation,
                sourceLabel: "manual",
                diagnostics: &diagnostics)
            else {
                OpenAIWebDebugLog.shared.updateStatus(L("手动 OpenAI Cookie 无效。"))
                throw OpenAIDashboardUsageError.cookieImportFailed(diagnostics.manualFailure())
            }
            OpenAIWebDebugLog.shared.updateStatus(L("正在使用手动 OpenAI Cookie。"))
            return ResolvedCookieHeader(
                cookieHeader: manual,
                cookieSnapshots: [],
                sourceLabel: "manual",
                cacheScope: nil,
                loadedFromCache: false,
                shouldStore: false)
        }

        let scope = cookieCacheScope(env: env)
        if preferCached,
           let cached = CookieHeaderCache.load(providerID: "codex", scope: scope)
        {
            OpenAIWebDebugLog.shared.updateStatus(L("正在验证缓存的 OpenAI Cookie…"))
            logger?("evaluating cached cookie header from \(cached.sourceLabel)")
            let evaluationTimeout = try remainingSelectionTimeout(
                label: cached.sourceLabel,
                cappedAt: validationTimeout)
            let evaluation = await evaluateCookieCandidate(
                cookieHeader: cached.cookieHeader,
                expectedEmail: expectedEmail,
                sourceLabel: cached.sourceLabel,
                session: session,
                timeout: evaluationTimeout,
                logger: logger)
            logger?("cached cookie evaluation: \(cookieEvaluationDescription(evaluation))")
            guard candidateAccepted(
                evaluation,
                sourceLabel: cached.sourceLabel,
                diagnostics: &diagnostics)
            else {
                CookieHeaderCache.clear(providerID: "codex", scope: scope)
                logger?("cached cookie rejected; cleared cache")
                OpenAIWebDebugLog.shared.updateStatus(L("缓存的 OpenAI Cookie 无效，正在重新导入…"))
                return try await resolvedCookieHeader(
                    env: env,
                    preferCached: false,
                    session: session,
                    selectionDeadline: selectionDeadline,
                    logger: logger)
            }
            OpenAIWebDebugLog.shared.updateStatus(L("正在使用缓存的 OpenAI Cookie。"))
            return ResolvedCookieHeader(
                cookieHeader: cached.cookieHeader,
                cookieSnapshots: [],
                sourceLabel: cached.sourceLabel,
                cacheScope: scope,
                loadedFromCache: true,
                shouldStore: false)
        }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "codex", env: env) else {
            OpenAIWebDebugLog.shared.updateStatus(L("OpenAI Cookie 读取未启用。"))
            throw OpenAIDashboardUsageError.cookieImportFailed(.init(
                reason: .noCookiesFound,
                details: L("当前配置未启用浏览器 Cookie 读取，也没有可用的手动 Cookie header。")))
        }
        let client = BrowserCookieClient()
        guard BrowserCookieAccessGate.cookieStoreAccessDecision(
            homeDirectories: client.configuration.homeDirectories,
            environment: env) == .allowed
        else {
            OpenAIWebDebugLog.shared.updateStatus(L("浏览器 Cookie 读取被当前进程抑制。"))
            throw OpenAIDashboardUsageError.cookieImportFailed(.init(
                reason: .browserAccessDenied,
                details: L("当前进程已抑制默认浏览器 Cookie 目录读取。")))
        }
        let query = BrowserCookieQuery(domains: cookieDomains)
        let detection = BrowserDetection()
        let browserCandidates = Browser.defaultImportOrder.cookieImportCandidates(using: detection)
        logger?("browser cookie candidates: \(browserCandidates.map(\.displayName).joined(separator: ", "))")
        for browser in browserCandidates {
            _ = try remainingSelectionTimeout(label: browser.displayName)
            OpenAIWebDebugLog.shared.updateStatus(L("正在读取 %@ 的 OpenAI Cookie…", browser.displayName))
            logger?("checking browser \(browser.displayName)")
            if browser.usesKeychainForCookieDecryption {
                let helperTimeout = try remainingSelectionTimeout(
                    label: browser.displayName,
                    cappedAt: max(1, validationTimeout))
                logger?("starting helper for \(browser.displayName), timeout=\(helperTimeout)")
                let helperResult = BrowserCookieHelperClient.cookieHeaderCandidates(
                    browser: browser,
                    domains: cookieDomains,
                    timeout: helperTimeout,
                    env: env)
                if helperResult.timedOut {
                    BrowserCookieAccessGate.recordDenied(for: browser)
                    diagnostics.helperTimedOutBrowsers.append(browser.displayName)
                    logger?("helper timed out for \(browser.displayName)")
                    OpenAIWebDebugLog.shared.updateStatus(L("%@ Cookie helper 超时。", browser.displayName))
                    throw OpenAIDashboardUsageError.cookieImportFailed(diagnostics.failure())
                }
                logger?("helper returned \(helperResult.candidates.count) candidate(s) for \(browser.displayName)")
                for candidate in helperResult.candidates {
                    diagnostics.foundAnyCookies = true
                    let evaluationTimeout = try remainingSelectionTimeout(
                        label: candidate.sourceLabel,
                        cappedAt: validationTimeout)
                    let evaluation = await evaluateCookieCandidate(
                        cookieHeader: candidate.cookieHeader,
                        expectedEmail: expectedEmail,
                        sourceLabel: candidate.sourceLabel,
                        session: session,
                        timeout: evaluationTimeout,
                        logger: logger)
                    logger?("\(candidate.sourceLabel) evaluation: \(cookieEvaluationDescription(evaluation))")
                    guard candidateAccepted(
                        evaluation,
                        sourceLabel: candidate.sourceLabel,
                        diagnostics: &diagnostics)
                    else {
                        continue
                    }
                    OpenAIWebDebugLog.shared.updateStatus(L("正在使用 %@。", candidate.sourceLabel))
                    return ResolvedCookieHeader(
                        cookieHeader: candidate.cookieHeader,
                        cookieSnapshots: candidate.cookies,
                        sourceLabel: candidate.sourceLabel,
                        cacheScope: scope,
                        loadedFromCache: false,
                        shouldStore: true)
                }
                continue
            }

            let sources: [BrowserCookieStoreRecords]
            do {
                sources = try await runBoundedCookieLoad(deadline: selectionDeadline) {
                    try client.records(matching: query, in: browser)
                }
                _ = try remainingSelectionTimeout(label: browser.displayName)
            } catch let error as OpenAIDashboardUsageError {
                throw error
            } catch let error as URLError where error.code == .timedOut {
                diagnostics.helperTimedOutBrowsers.append(browser.displayName)
                logger?("cookie load timed out for \(browser.displayName)")
                OpenAIWebDebugLog.shared.updateStatus(L("%@ Cookie 读取超时。", browser.displayName))
                throw OpenAIDashboardUsageError.cookieImportFailed(diagnostics.failure())
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                if let hint = (error as? BrowserCookieError)?.accessDeniedHint {
                    diagnostics.accessDeniedHints.append(hint)
                }
                OpenAIWebDebugLog.shared.updateStatus(L("读取 %@ Cookie 失败。", browser.displayName))
                logger?("failed to read \(browser.displayName): \(error.localizedDescription)")
                continue
            }
            logger?("read \(sources.count) cookie source(s) from \(browser.displayName)")
            for source in sources {
                diagnostics.foundAnyCookies = true
                let cookies = source.cookies(origin: query.origin)
                guard let normalized = cookieHeader(from: cookies) else {
                    logger?("\(source.label) skipped: no OpenAI cookie header after normalization")
                    continue
                }
                let evaluationTimeout = try remainingSelectionTimeout(
                    label: source.label,
                    cappedAt: validationTimeout)
                let evaluation = await evaluateCookieCandidate(
                    cookieHeader: normalized,
                    expectedEmail: expectedEmail,
                    sourceLabel: source.label,
                    session: session,
                    timeout: evaluationTimeout,
                    logger: logger)
                logger?("\(source.label) evaluation: \(cookieEvaluationDescription(evaluation))")
                guard candidateAccepted(
                    evaluation,
                    sourceLabel: source.label,
                    diagnostics: &diagnostics)
                else {
                    continue
                }
                OpenAIWebDebugLog.shared.updateStatus(L("正在使用 %@。", source.label))
                return ResolvedCookieHeader(
                    cookieHeader: normalized,
                    cookieSnapshots: OpenAIDashboardCookieSnapshot.snapshots(from: cookies),
                    sourceLabel: source.label,
                    cacheScope: scope,
                    loadedFromCache: false,
                    shouldStore: true)
            }
        }
        logger?("cookie selection failed: \(diagnostics.failure().errorDescription)")
        OpenAIWebDebugLog.shared.updateStatus(L("OpenAI Cookie 导入失败。"))
        throw OpenAIDashboardUsageError.cookieImportFailed(diagnostics.failure())
    }

    private static func cookieSelectionBudget(perRequestTimeout: TimeInterval) -> TimeInterval {
        min(20, max(3, perRequestTimeout * 4))
    }

    private nonisolated static let cookieDeadlineQueue = DispatchQueue(
        label: "com.conductor.openai-cookie-deadline",
        qos: .userInitiated)
    private nonisolated static let cookieCacheQueue = DispatchQueue(
        label: "com.conductor.openai-cookie-cache",
        qos: .userInitiated)

    private final class CookieLoadCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var didFinish = false

        func finish(_ action: () -> Void) {
            lock.lock()
            guard !didFinish else {
                lock.unlock()
                return
            }
            didFinish = true
            lock.unlock()
            action()
        }
    }

    static func remainingCookieSelectionTimeout(
        until deadline: Date?,
        cappedAt localLimit: TimeInterval? = nil,
        now: Date = Date()
    ) throws -> TimeInterval {
        guard let deadline else {
            return localLimit.map(sanitizedCookieTimeout) ?? .greatestFiniteMagnitude
        }
        let remaining = deadline.timeIntervalSince(now)
        guard remaining > 0 else { throw URLError(.timedOut) }
        guard let localLimit else { return remaining }
        return min(sanitizedCookieTimeout(localLimit), remaining)
    }

    static func runBoundedCookieLoad<T: Sendable>(
        deadline: Date?,
        timeoutObserver: (@Sendable () -> Void)? = nil,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        guard let deadline else {
            return try await withCheckedThrowingContinuation { continuation in
                cookieCacheQueue.async {
                    continuation.resume(with: Result(catching: operation))
                }
            }
        }
        let timeout = try remainingCookieSelectionTimeout(until: deadline)
        let completion = CookieLoadCompletion()
        return try await withCheckedThrowingContinuation { continuation in
            cookieCacheQueue.async {
                let result = Result(catching: operation)
                completion.finish {
                    continuation.resume(with: result)
                }
            }
            cookieDeadlineQueue.asyncAfter(deadline: .now() + timeout) {
                completion.finish {
                    timeoutObserver?()
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }

    private static func sanitizedCookieTimeout(_ timeout: TimeInterval) -> TimeInterval {
        guard timeout.isFinite, timeout > 0 else { return 0 }
        return min(timeout, 86_400)
    }

    private static func staticCookieHeader(
        env: [String: String],
        preferCached: Bool
    ) -> ResolvedCookieHeader? {
        if let manual = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "codex", env: env) {
            return ResolvedCookieHeader(
                cookieHeader: manual,
                cookieSnapshots: [],
                sourceLabel: "manual",
                cacheScope: nil,
                loadedFromCache: false,
                shouldStore: false)
        }

        let scope = cookieCacheScope(env: env)
        if preferCached,
           let cached = CookieHeaderCache.load(providerID: "codex", scope: scope)
        {
            return ResolvedCookieHeader(
                cookieHeader: cached.cookieHeader,
                cookieSnapshots: [],
                sourceLabel: cached.sourceLabel,
                cacheScope: scope,
                loadedFromCache: true,
                shouldStore: false)
        }
        return nil
    }

    private struct CookieSelectionDiagnostics {
        var foundAccounts: [OpenAIDashboardFoundAccount] = []
        var foundAnyCookies = false
        var foundUnknownEmail = false
        var accessDeniedHints: [String] = []
        var helperTimedOutBrowsers: [String] = []

        func failure() -> OpenAIDashboardCookieImportFailure {
            let accounts = deduplicatedAccounts()
            if !accounts.isEmpty {
                return .init(reason: .noMatchingAccount, foundAccounts: accounts)
            }
            if !helperTimedOutBrowsers.isEmpty {
                return .init(
                    reason: .helperTimedOut,
                    details: sortedUnique(helperTimedOutBrowsers).joined(separator: ", "))
            }
            if !accessDeniedHints.isEmpty {
                return .init(
                    reason: .browserAccessDenied,
                    details: sortedUnique(accessDeniedHints).joined(separator: " / "))
            }
            if foundUnknownEmail {
                return .init(reason: .missingVerifiedEmail)
            }
            return .init(
                reason: .noCookiesFound,
                details: foundAnyCookies ? L("找到了 Cookie 记录，但没有有效的 OpenAI session cookie。") : nil)
        }

        func manualFailure() -> OpenAIDashboardCookieImportFailure {
            let accounts = deduplicatedAccounts()
            if !accounts.isEmpty {
                return .init(reason: .noMatchingAccount, foundAccounts: accounts)
            }
            if foundUnknownEmail {
                return .init(reason: .missingVerifiedEmail)
            }
            return .init(reason: .manualCookieHeaderInvalid)
        }

        private func deduplicatedAccounts() -> [OpenAIDashboardFoundAccount] {
            var seen = Set<String>()
            var result: [OpenAIDashboardFoundAccount] = []
            for account in foundAccounts {
                let key = "\(account.sourceLabel.lowercased())\u{0}\(account.email.lowercased())"
                guard seen.insert(key).inserted else { continue }
                result.append(account)
            }
            return result
        }

        private func sortedUnique(_ values: [String]) -> [String] {
            Array(Set(values.filter { !$0.isEmpty })).sorted()
        }
    }

    private static func candidateAccepted(
        _ evaluation: OpenAIDashboardCookieCandidateEvaluation,
        sourceLabel: String,
        diagnostics: inout CookieSelectionDiagnostics
    ) -> Bool {
        switch evaluation {
        case .accepted:
            return true
        case .rejectedNoSession:
            return false
        case .rejectedMissingVerifiedEmail:
            diagnostics.foundUnknownEmail = true
            return false
        case let .rejectedWrongEmail(_, actual):
            diagnostics.foundAccounts.append(.init(sourceLabel: sourceLabel, email: actual))
            return false
        }
    }

    private static func shouldAcceptCookieHeader(
        _ cookieHeader: String,
        expectedEmail: String?,
        sourceLabel: String,
        session: URLSession,
        timeout: TimeInterval
    ) async -> Bool {
        switch await evaluateCookieCandidate(
            cookieHeader: cookieHeader,
            expectedEmail: expectedEmail,
            sourceLabel: sourceLabel,
            session: session,
            timeout: timeout,
            logger: nil)
        {
        case .accepted:
            return true
        case .rejectedNoSession, .rejectedMissingVerifiedEmail, .rejectedWrongEmail:
            return false
        }
    }

    static func evaluateCookieCandidate(
        cookieHeader: String,
        expectedEmail: String?,
        sourceLabel: String,
        session: URLSession,
        timeout: TimeInterval,
        logger: (@Sendable (String) -> Void)? = nil
    ) async -> OpenAIDashboardCookieCandidateEvaluation {
        let signedInEmail = try? await fetchSignedInEmail(
            cookieHeader: cookieHeader,
            session: session,
            timeout: timeout,
            logger: logger)
        let normalizedSignedInEmail = normalizedEmail(signedInEmail)
        let normalizedExpectedEmail = normalizedEmail(expectedEmail)

        if let normalizedExpectedEmail {
            guard let normalizedSignedInEmail else {
                if hasOpenAISessionCookie(cookieHeader) {
                    logger?("\(sourceLabel) has session cookie but email could not be verified")
                    return .rejectedMissingVerifiedEmail(expected: normalizedExpectedEmail)
                }
                return .rejectedNoSession
            }
            if normalizedSignedInEmail == normalizedExpectedEmail {
                return .accepted(signedInEmail: normalizedSignedInEmail)
            }
            return .rejectedWrongEmail(expected: normalizedExpectedEmail, actual: normalizedSignedInEmail)
        }

        if let normalizedSignedInEmail {
            return .accepted(signedInEmail: normalizedSignedInEmail)
        }
        return hasOpenAISessionCookie(cookieHeader) ? .accepted(signedInEmail: nil) : .rejectedNoSession
    }

    private static func cookieEvaluationDescription(
        _ evaluation: OpenAIDashboardCookieCandidateEvaluation
    ) -> String {
        switch evaluation {
        case let .accepted(signedInEmail):
            return "accepted email=\(signedInEmail ?? "unknown")"
        case .rejectedNoSession:
            return "rejected no session"
        case let .rejectedMissingVerifiedEmail(expected):
            return "rejected missing verified email expected=\(expected)"
        case let .rejectedWrongEmail(expected, actual):
            return "rejected wrong email expected=\(expected) actual=\(actual)"
        }
    }

    private static func cookieHeader(from cookies: [HTTPCookie]) -> String? {
        let header = cookies
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        guard let normalized = CookieHeaderNormalizer.normalize(header), !normalized.isEmpty else {
            return nil
        }
        return normalized
    }

    private static func hasOpenAISessionCookie(_ cookieHeader: String) -> Bool {
        CookieHeaderNormalizer.pairs(from: cookieHeader).contains { pair in
            let name = pair.name.lowercased()
            return name.contains("session-token") ||
                name.contains("authjs") ||
                name.contains("next-auth") ||
                name == "_account"
        }
    }

    private static func storeCookieHeaderIfNeeded(_ resolved: ResolvedCookieHeader) {
        guard resolved.shouldStore else { return }
        OpenAIWebDebugLog.shared.append("stored cookie cache from \(resolved.sourceLabel)")
        CookieHeaderCache.store(
            providerID: "codex",
            scope: resolved.cacheScope,
            cookieHeader: resolved.cookieHeader,
            sourceLabel: resolved.sourceLabel)
    }

    static func shouldRetryWithFreshBrowserCookie(after error: Error) -> Bool {
        if case OpenAIDashboardUsageError.noDashboardData(_) = error {
            return true
        }
        if case OpenAIDashboardUsageError.unauthorized = error {
            return true
        }
        if case let OpenAIDashboardUsageError.policyRejected(decision) = error {
            switch decision.reason {
            case .wrongEmail, .missingDashboardSignedInEmail:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func cookieCacheScope(env: [String: String]) -> CookieHeaderCache.Scope? {
        let auth = CodexDashboardAuthorityContext.authBackedAccount(env: env)
        switch auth.identity {
        case let .providerAccount(id):
            return CookieHeaderCache.Scope("provider-account:\(id)")
        case let .emailOnly(email):
            return CookieHeaderCache.Scope("email:\(email)")
        case .unresolved:
            let rawHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CookieHeaderCache.Scope(rawHome.map { "codex-home:\($0)" })
        }
    }

    private static func fetchUsageAPI(
        cookieHeader: String,
        session: URLSession,
        timeout: TimeInterval,
        logger: (@Sendable (String) -> Void)? = nil
    ) async throws -> CodexUsageSnapshot {
        var request = URLRequest(url: usageAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(dashboardAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("Conductor", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger?("usage API network error: \(error.localizedDescription)")
            throw OpenAIDashboardUsageError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logger?("usage API status=\(status), bytes=\(data.count)")
        switch status {
        case 200...299:
            return try CodexUsageFetcher.parse(data)
        case 401, 403:
            throw OpenAIDashboardUsageError.unauthorized
        default:
            throw OpenAIDashboardUsageError.server(status)
        }
    }

    private static func fetchUsageHTML(
        cookieHeader: String,
        session: URLSession,
        timeout: TimeInterval,
        logger: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        var request = URLRequest(url: usagePageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(dashboardAcceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("Conductor", forHTTPHeaderField: "User-Agent")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger?("dashboard HTML network error: \(error.localizedDescription)")
            throw OpenAIDashboardUsageError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        logger?("dashboard HTML status=\(status), bytes=\(data.count)")
        switch status {
        case 200...299:
            return String(data: data, encoding: .utf8) ?? ""
        case 401, 403:
            throw OpenAIDashboardUsageError.unauthorized
        default:
            throw OpenAIDashboardUsageError.server(status)
        }
    }

    private static func fetchSignedInEmail(
        cookieHeader: String,
        session: URLSession,
        timeout: TimeInterval,
        logger: (@Sendable (String) -> Void)? = nil
    ) async throws -> String? {
        for url in [
            URL(string: "https://chatgpt.com/backend-api/me"),
            URL(string: "https://chatgpt.com/api/auth/session"),
        ].compactMap(\.self) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(dashboardAcceptLanguage, forHTTPHeaderField: "Accept-Language")
            request.setValue("Conductor", forHTTPHeaderField: "User-Agent")
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                logger?("identity API \(url.path) network error: \(error.localizedDescription)")
                continue
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger?("identity API \(url.path) status=\(status), bytes=\(data.count)")
            guard (200...299).contains(status),
                  let email = OpenAIDashboardParser.findFirstEmail(inJSONData: data)
            else { continue }
            return email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func creditsPurchaseURL(fromHTML html: String?) -> String? {
        guard let html,
              let range = html.range(
                  of: #"https://chatgpt\.com/[^\"]*(?:credits|billing|purchase)[^\"]*"#,
                  options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return String(html[range])
    }

    private static func firstNonEmpty(_ candidates: String?...) -> String? {
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed?.isEmpty == false { return trimmed }
        }
        return nil
    }

    private static func merge(
        base: OpenAIDashboardSnapshot,
        hydrated: OpenAIDashboardSnapshot
    ) -> OpenAIDashboardSnapshot {
        OpenAIDashboardSnapshot(
            signedInEmail: firstNonEmpty(base.signedInEmail, hydrated.signedInEmail),
            codeReviewRemainingPercent: hydrated.codeReviewRemainingPercent ?? base.codeReviewRemainingPercent,
            codeReviewLimit: hydrated.codeReviewLimit ?? base.codeReviewLimit,
            creditEvents: hydrated.creditEvents.isEmpty ? base.creditEvents : hydrated.creditEvents,
            dailyBreakdown: hydrated.dailyBreakdown.isEmpty ? base.dailyBreakdown : hydrated.dailyBreakdown,
            usageBreakdown: hydrated.usageBreakdown.isEmpty ? base.usageBreakdown : hydrated.usageBreakdown,
            creditsPurchaseURL: firstNonEmpty(hydrated.creditsPurchaseURL, base.creditsPurchaseURL),
            primaryLimit: base.primaryLimit ?? hydrated.primaryLimit,
            secondaryLimit: base.secondaryLimit ?? hydrated.secondaryLimit,
            extraRateWindows: mergedExtraRateWindows(base: base.extraRateWindows, hydrated: hydrated.extraRateWindows),
            creditsRemaining: base.creditsRemaining ?? hydrated.creditsRemaining,
            accountPlan: firstNonEmpty(base.accountPlan, hydrated.accountPlan),
            updatedAt: max(base.updatedAt, hydrated.updatedAt))
    }

    static func mergedExtraRateWindows(
        base: [NamedRateWindow]?,
        hydrated: [NamedRateWindow]?
    ) -> [NamedRateWindow]? {
        var merged: [NamedRateWindow] = []
        var seen = Set<String>()
        for window in (base ?? []) + (hydrated ?? []) {
            guard seen.insert(window.id).inserted else { continue }
            merged.append(window)
        }
        return merged.isEmpty ? nil : merged
    }

    private static func webKitTimeout(env: [String: String]) -> TimeInterval {
        UsageProviderRuntimeConfig.webTimeout(providerID: "codex", defaultValue: 35, env: env)
    }

    private static func webRequestTimeout(env: [String: String], defaultValue: TimeInterval) -> TimeInterval {
        UsageProviderRuntimeConfig.webTimeout(providerID: "codex", defaultValue: defaultValue, env: env)
    }

    private static func webDebugDumpHTML(env: [String: String]) -> Bool {
        UsageProviderRuntimeConfig.webDebugDumpHTML(providerID: "codex", env: env)
    }

    static func validateDashboardOwnership(
        snapshot: OpenAIDashboardSnapshot,
        expectedEmail: String?,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let input = CodexDashboardAuthorityContext.makeLiveWebInput(
            dashboard: snapshot,
            env: env,
            routingTargetEmail: expectedEmail)
        let decision = CodexDashboardAuthority.evaluate(input)
        if decision.disposition == .attach { return }

        if decision.disposition == .displayOnly {
            throw CodexDashboardPolicyError.displayOnly(decision)
        }
        throw OpenAIDashboardUsageError.policyRejected(decision)
    }

    private static func authBackedAccountEmail(env: [String: String]) -> String? {
        guard let credentials = try? CodexUsageFetcher.loadCredentials(env: env),
              let idToken = credentials.idToken,
              let payload = CodexUsageFetcher.parseJWT(idToken)
        else { return nil }
        let profile = payload["https://api.openai.com/profile"] as? [String: Any]
        return normalizedEmail((payload["email"] as? String) ?? (profile?["email"] as? String))
    }

    private static func normalizedEmail(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let trimmed, trimmed.contains("@"), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool {
        self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09
    }
}
