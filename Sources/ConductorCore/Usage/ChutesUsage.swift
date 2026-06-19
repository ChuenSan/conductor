import Foundation

/// Chutes 用量取数。转写自 CodexBar `ChutesUsageStats`：
/// 先读 subscription usage；当 subscription payload 缺少窗口时，再读 quotas / quota_usage 补窗口。
///
/// 环境变量：`CHUTES_API_KEY`（必需）、`CHUTES_API_URL`（可选，默认 https://api.chutes.ai）。
public enum ChutesUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case invalidCredentials
    case invalidURL
    case invalidEndpointOverride(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            L("未找到 Chutes API key，请设置 CHUTES_API_KEY")
        case .invalidCredentials:
            L("Chutes API key 被拒绝，请检查设置")
        case .invalidURL:
            L("Chutes usage URL 无效")
        case let .invalidEndpointOverride(key):
            L("Chutes endpoint override %@ 必须使用 HTTPS 或裸主机名", key)
        case let .apiError(message):
            L("Chutes usage API 错误：%@", message)
        case let .parseFailed(message):
            L("Chutes usage 解析错误：%@", message)
        }
    }
}

public enum ChutesSubscriptionState: String, Sendable, Codable {
    case active
    case inactive
    case unknown
}

public struct ChutesQuotaWindow: Sendable, Equatable {
    public let label: String?
    public let used: Double?
    public let limit: Double?
    public let remaining: Double?
    public let usedPercent: Double?
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let unit: String?

    public init(
        label: String?,
        used: Double?,
        limit: Double?,
        remaining: Double?,
        usedPercent: Double?,
        windowMinutes: Int?,
        resetsAt: Date?,
        unit: String? = nil)
    {
        self.label = label
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.unit = unit
    }

    public func rateWindow(defaultWindowMinutes: Int?) -> RateWindow? {
        guard let percent = usagePercent else { return nil }
        return RateWindow(
            title: label,
            usedPercent: max(0, min(percent, 100)),
            windowMinutes: windowMinutes ?? defaultWindowMinutes,
            resetsAt: resetsAt,
            resetDescription: usageDescription)
    }

    public var usagePercent: Double? {
        if let usedPercent { return max(0, min(usedPercent, 100)) }

        var used = self.used
        var limit = self.limit
        var remaining = self.remaining

        if limit == nil, let used, let remaining { limit = used + remaining }
        if used == nil, let limit, let remaining { used = limit - remaining }
        if remaining == nil, let limit, let used { remaining = max(0, limit - used) }

        guard let used, let limit, limit > 0 else { return nil }
        return used / limit * 100
    }

    private var usageDescription: String? {
        guard let limit, limit > 0 else { return nil }
        let used: Double
        if let explicitUsed = self.used {
            used = explicitUsed
        } else if let remaining {
            used = max(0, limit - remaining)
        } else {
            return nil
        }

        let unit = self.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = unit?.isEmpty == false ? " \(unit!)" : ""
        return "\(Self.formatAmount(used))/\(Self.formatAmount(limit))\(suffix)"
    }

    private static func formatAmount(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0001 {
            return String(Int(rounded))
        }
        var text = String(format: "%.2f", value)
        while text.contains("."), text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

public struct ChutesUsageSnapshot: Sendable, Equatable {
    public let rollingWindow: ChutesQuotaWindow?
    public let monthlyWindow: ChutesQuotaWindow?
    public let fallbackWindows: [ChutesQuotaWindow]
    public let subscriptionState: ChutesSubscriptionState
    public let planName: String?
    public let subscriptionRenewsAt: Date?
    public let updatedAt: Date

    public init(
        rollingWindow: ChutesQuotaWindow?,
        monthlyWindow: ChutesQuotaWindow?,
        fallbackWindows: [ChutesQuotaWindow] = [],
        subscriptionState: ChutesSubscriptionState,
        planName: String?,
        subscriptionRenewsAt: Date?,
        updatedAt: Date)
    {
        self.rollingWindow = rollingWindow
        self.monthlyWindow = monthlyWindow
        self.fallbackWindows = fallbackWindows
        self.subscriptionState = subscriptionState
        self.planName = planName
        self.subscriptionRenewsAt = subscriptionRenewsAt
        self.updatedAt = updatedAt
    }

    public var hasUsageData: Bool {
        rollingWindow?.rateWindow(defaultWindowMinutes: Self.rollingWindowMinutes) != nil ||
            monthlyWindow?.rateWindow(defaultWindowMinutes: Self.monthlyWindowMinutes) != nil ||
            fallbackWindows.contains { $0.rateWindow(defaultWindowMinutes: $0.windowMinutes) != nil }
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let fallbackRateWindows = fallbackWindows.compactMap {
            $0.rateWindow(defaultWindowMinutes: $0.windowMinutes)
        }
        let monthly = monthlyWindow?.rateWindow(defaultWindowMinutes: Self.monthlyWindowMinutes)
        let rolling = rollingWindow?.rateWindow(defaultWindowMinutes: Self.rollingWindowMinutes)

        let primary = rolling ?? (monthly == nil ? fallbackRateWindows.first : nil)
        let secondary: RateWindow? = if let monthly {
            monthly
        } else if rolling != nil {
            fallbackRateWindows.first
        } else if primary != nil {
            fallbackRateWindows.dropFirst().first
        } else {
            nil
        }

        let alreadyUsedIDs = Set([primary?.title, secondary?.title].compactMap { $0 })
        let extras = fallbackRateWindows
            .enumerated()
            .compactMap { index, window -> NamedRateWindow? in
                let title = window.title ?? L("额度 %ld", index + 1)
                guard !alreadyUsedIDs.contains(title) else { return nil }
                return NamedRateWindow(id: "chutes.fallback.\(index)", title: title, window: window)
            }

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            extraRateWindows: extras,
            planName: planName ?? fallbackPlanLabel(hasWindows: primary != nil || secondary != nil),
            updatedAt: updatedAt)
    }

    func preservingSubscriptionContext(from fallback: ChutesUsageSnapshot) -> ChutesUsageSnapshot {
        ChutesUsageSnapshot(
            rollingWindow: fallback.rollingWindow ?? rollingWindow,
            monthlyWindow: fallback.monthlyWindow ?? monthlyWindow,
            fallbackWindows: fallback.fallbackWindows + fallbackWindows,
            subscriptionState: fallback.subscriptionState,
            planName: fallback.planName,
            subscriptionRenewsAt: fallback.subscriptionRenewsAt,
            updatedAt: fallback.updatedAt)
    }

    private func fallbackPlanLabel(hasWindows: Bool) -> String? {
        switch subscriptionState {
        case .active:
            return nil
        case .inactive:
            return L("无有效订阅")
        case .unknown:
            return hasWindows ? nil : L("无用量数据")
        }
    }

    static let rollingWindowMinutes = 4 * 60
    static let monthlyWindowMinutes = 30 * 24 * 60
}

public enum ChutesUsageFetcher {
    public static let apiKeyEnvironmentKey = "CHUTES_API_KEY"
    public static let apiURLEnvironmentKey = "CHUTES_API_URL"
    private static let defaultBaseURL = URL(string: "https://api.chutes.ai")!
    private static let requestTimeoutSeconds: TimeInterval = 15

    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil
    }

    static func token(env: [String: String]) -> String? {
        clean(env[apiKeyEnvironmentKey])
    }

    static func clean(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func apiURL(env: [String: String]) -> URL {
        if let raw = clean(env[apiURLEnvironmentKey]), let override = normalizedHTTPSURL(from: raw) {
            return override
        }
        return defaultBaseURL
    }

    static func validateEndpointOverride(env: [String: String]) throws {
        guard let raw = clean(env[apiURLEnvironmentKey]) else { return }
        guard normalizedHTTPSURL(from: raw) == nil else { return }
        throw ChutesUsageError.invalidEndpointOverride(apiURLEnvironmentKey)
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        guard let apiKey = token(env: env) else { throw ChutesUsageError.missingCredentials }
        return try await fetchUsage(apiKey: apiKey, environment: env, session: session).toUsageSnapshot()
    }

    static func fetchUsage(
        apiKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        now: Date = Date()) async throws -> ChutesUsageSnapshot
    {
        guard let token = clean(apiKey) else { throw ChutesUsageError.missingCredentials }
        try validateEndpointOverride(env: environment)

        let baseURL = apiURL(env: environment)
        let subscription = try await fetchSnapshot(
            pathComponents: ["users", "me", "subscription_usage"],
            apiKey: token,
            baseURL: baseURL,
            session: session,
            now: now)

        guard subscription.rollingWindow == nil || subscription.monthlyWindow == nil else {
            return subscription
        }

        do {
            let quotas = try await fetchQuotaSnapshot(apiKey: token, baseURL: baseURL, session: session, now: now)
            return quotas.hasUsageData ? quotas.preservingSubscriptionContext(from: subscription) : subscription
        } catch ChutesUsageError.invalidCredentials {
            throw ChutesUsageError.invalidCredentials
        } catch {
            return subscription
        }
    }

    private static func fetchSnapshot(
        pathComponents: [String],
        apiKey: String,
        baseURL: URL,
        session: URLSession,
        now: Date) async throws -> ChutesUsageSnapshot
    {
        let data = try await fetchData(pathComponents: pathComponents, apiKey: apiKey, baseURL: baseURL, session: session)
        do {
            return try ChutesUsageParser.parse(data: data, now: now)
        } catch let error as ChutesUsageError {
            throw error
        } catch {
            throw ChutesUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func fetchQuotaSnapshot(
        apiKey: String,
        baseURL: URL,
        session: URLSession,
        now: Date) async throws -> ChutesUsageSnapshot
    {
        let data = try await fetchData(pathComponents: ["users", "me", "quotas"], apiKey: apiKey, baseURL: baseURL, session: session)
        let fallback = try ChutesUsageParser.parse(data: data, now: now)
        let definitions = try quotaDefinitions(from: data)
        guard !definitions.isEmpty else { return fallback }

        var enrichedDefinitions: [[String: Any]] = []
        for definition in definitions {
            guard let identifier = quotaIdentifier(from: definition) else {
                enrichedDefinitions.append(definition)
                continue
            }
            do {
                let usageData = try await fetchData(
                    pathComponents: ["users", "me", "quota_usage", identifier],
                    apiKey: apiKey,
                    baseURL: baseURL,
                    session: session)
                guard let usage = try responseDictionary(from: usageData) else {
                    enrichedDefinitions.append(definition)
                    continue
                }
                enrichedDefinitions.append(definition.merging(usage) { _, usageValue in usageValue })
            } catch ChutesUsageError.invalidCredentials {
                throw ChutesUsageError.invalidCredentials
            } catch {
                enrichedDefinitions.append(definition)
            }
        }

        let enrichedData = try JSONSerialization.data(withJSONObject: ["quotas": enrichedDefinitions], options: [])
        let enriched = try ChutesUsageParser.parse(data: enrichedData, now: now)
        return enriched.hasUsageData ? enriched : fallback
    }

    private static func fetchData(
        pathComponents: [String],
        apiKey: String,
        baseURL: URL,
        session: URLSession) async throws -> Data
    {
        let url = pathComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard url.scheme?.lowercased() == "https" else { throw ChutesUsageError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = requestTimeoutSeconds

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ChutesUsageError.apiError("Non-HTTP response") }
            data = responseData
            http = response
        } catch let error as ChutesUsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ChutesUsageError.apiError(error.localizedDescription)
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ChutesUsageError.invalidCredentials
            }
            throw ChutesUsageError.apiError("HTTP \(http.statusCode): \(responseSummary(data))")
        }
        return data
    }

    static func quotaDefinitions(from data: Data) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        if let array = object as? [Any] { return array.compactMap { $0 as? [String: Any] } }
        guard let dictionary = object as? [String: Any] else { return [] }
        if let quotas = dictionary["quotas"] as? [Any] { return quotas.compactMap { $0 as? [String: Any] } }
        if let data = dictionary["data"] as? [Any] { return data.compactMap { $0 as? [String: Any] } }
        if let data = dictionary["data"] as? [String: Any], let quotas = data["quotas"] as? [Any] {
            return quotas.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    static func quotaIdentifier(from definition: [String: Any]) -> String? {
        for key in ["chute_id", "chuteId", "id"] {
            if let value = definition[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = definition[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func responseDictionary(from data: Data) throws -> [String: Any]? {
        guard let dictionary = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return dictionary["data"] as? [String: Any]
            ?? dictionary["result"] as? [String: Any]
            ?? dictionary
    }

    private static func responseSummary(_ data: Data) -> String {
        String(bytes: data.prefix(240), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    /// 接受 `https://host[/path]` 或裸主机名（补全为 https），拒绝非 HTTPS。
    private static func normalizedHTTPSURL(from raw: String) -> URL? {
        if let url = URL(string: raw), let scheme = url.scheme?.lowercased() {
            return scheme == "https" ? url : nil
        }
        return URL(string: "https://\(raw)")
    }
}

private final class ChutesISO8601FormatterBox: @unchecked Sendable {
    let lock = NSLock()
    let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum ChutesTimestampParser {
    static let box = ChutesISO8601FormatterBox()

    static func parse(_ value: Any?) -> Date? {
        switch value {
        case let date as Date:
            date
        case let number as NSNumber:
            date(fromEpochValue: number.doubleValue)
        case let text as String:
            parseString(text)
        default:
            nil
        }
    }

    private static func parseString(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let number = Double(text) { return date(fromEpochValue: number) }

        box.lock.lock()
        defer { box.lock.unlock() }
        return box.withFractional.date(from: text) ?? box.plain.date(from: text)
    }

    private static func date(fromEpochValue value: Double) -> Date? {
        guard value.isFinite, value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

enum ChutesUsageParser {
    static func parse(data: Data, now: Date = Date()) throws -> ChutesUsageSnapshot {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return parse(object: object, now: now)
    }

    private static func parse(object: Any, now: Date) -> ChutesUsageSnapshot {
        let root: [String: Any] = {
            if let dict = object as? [String: Any] { return dict }
            if let array = object as? [Any] { return ["quotas": array] }
            return [:]
        }()
        let dataRoot = dictionaryValue(value(in: root, keys: ["data", "result"])) ?? root
        let subscription = subscriptionPayload(root: root, dataRoot: dataRoot)

        let explicitRolling = firstDictionary(in: root, dataRoot: dataRoot, keys: rollingPayloadKeys)
            .flatMap { parseQuota($0, defaultLabel: L("4 小时额度"), defaultWindowMinutes: ChutesUsageSnapshot.rollingWindowMinutes) }
        let explicitMonthly = firstDictionary(in: root, dataRoot: dataRoot, keys: monthlyPayloadKeys)
            .flatMap { parseQuota($0, defaultLabel: L("月度额度"), defaultWindowMinutes: ChutesUsageSnapshot.monthlyWindowMinutes) }

        let quotaWindows = fallbackQuotaObjects(from: root, dataRoot: dataRoot).compactMap {
            parseQuota($0, defaultLabel: nil, defaultWindowMinutes: nil)
        }
        let classifiedRolling = explicitRolling ?? quotaWindows.first { kind(for: $0) == .rolling }
        let classifiedMonthly = explicitMonthly ?? quotaWindows.first { kind(for: $0) == .monthly }
        let fallbackWindows = quotaWindows.filter { window in
            Optional.some(window) != classifiedRolling && Optional.some(window) != classifiedMonthly
        }

        return ChutesUsageSnapshot(
            rollingWindow: classifiedRolling,
            monthlyWindow: classifiedMonthly,
            fallbackWindows: fallbackWindows,
            subscriptionState: subscriptionState(root: root, dataRoot: dataRoot, subscription: subscription),
            planName: planName(root: root, dataRoot: dataRoot, subscription: subscription),
            subscriptionRenewsAt: subscriptionRenewsAt(root: root, dataRoot: dataRoot, subscription: subscription),
            updatedAt: now)
    }

    private enum WindowKind {
        case rolling
        case monthly
    }

    private static func parseQuota(
        _ payload: [String: Any],
        defaultLabel: String?,
        defaultWindowMinutes: Int?) -> ChutesQuotaWindow?
    {
        let label = firstString(in: payload, keys: labelKeys) ?? defaultLabel
        let limit = firstDouble(in: payload, keys: limitKeys)
        let used = firstDouble(in: payload, keys: usedKeys)
        let remaining = firstDouble(in: payload, keys: remainingKeys)
        var usedPercent = normalizedPercent(firstDouble(in: payload, keys: percentUsedKeys))
        if usedPercent == nil,
           let remainingPercent = normalizedPercent(firstDouble(in: payload, keys: percentRemainingKeys))
        {
            usedPercent = 100 - remainingPercent
        }
        let window = windowMinutes(from: payload) ?? defaultWindowMinutes
        let resetsAt = firstDate(in: payload, keys: resetKeys)
        let unit = firstString(in: payload, keys: unitKeys) ?? "credits"

        let quota = ChutesQuotaWindow(
            label: label,
            used: used,
            limit: limit,
            remaining: remaining,
            usedPercent: usedPercent,
            windowMinutes: window,
            resetsAt: resetsAt,
            unit: unit)
        return quota.usagePercent == nil ? nil : quota
    }

    private static func subscriptionPayload(root: [String: Any], dataRoot: [String: Any]) -> [String: Any]? {
        firstDictionary(in: root, dataRoot: dataRoot, keys: [
            "subscription", "subscription_usage", "subscriptionUsage", "current_subscription", "currentSubscription", "plan",
        ])
    }

    private static func subscriptionState(
        root: [String: Any],
        dataRoot: [String: Any],
        subscription: [String: Any]?) -> ChutesSubscriptionState
    {
        if let active = firstBool(in: root, keys: activeKeys)
            ?? firstBool(in: dataRoot, keys: activeKeys)
            ?? subscription.flatMap({ firstBool(in: $0, keys: activeKeys) })
        {
            return active ? .active : .inactive
        }

        let status = firstString(in: root, keys: statusKeys)
            ?? firstString(in: dataRoot, keys: statusKeys)
            ?? subscription.flatMap { firstString(in: $0, keys: statusKeys) }
        let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let normalizedStatus, !normalizedStatus.isEmpty else { return .unknown }
        if normalizedStatus.contains("active") && !normalizedStatus.contains("inactive") { return .active }
        if normalizedStatus.contains("free") ||
            normalizedStatus.contains("inactive") ||
            normalizedStatus.contains("cancel") ||
            normalizedStatus.contains("none") ||
            normalizedStatus.contains("expired")
        {
            return .inactive
        }
        return .unknown
    }

    private static func planName(root: [String: Any], dataRoot: [String: Any], subscription: [String: Any]?) -> String? {
        firstString(in: root, keys: planKeys)
            ?? firstString(in: dataRoot, keys: planKeys)
            ?? subscription.flatMap { firstString(in: $0, keys: planKeys) }
    }

    private static func subscriptionRenewsAt(root: [String: Any], dataRoot: [String: Any], subscription: [String: Any]?) -> Date? {
        firstDate(in: root, keys: resetKeys)
            ?? firstDate(in: dataRoot, keys: resetKeys)
            ?? subscription.flatMap { firstDate(in: $0, keys: resetKeys) }
    }

    private static func firstDictionary(in root: [String: Any], dataRoot: [String: Any], keys: [String]) -> [String: Any]? {
        dictionaryValue(value(in: root, keys: keys)) ?? dictionaryValue(value(in: dataRoot, keys: keys))
    }

    private static func fallbackQuotaObjects(from root: [String: Any], dataRoot: [String: Any]) -> [[String: Any]] {
        let candidates: [Any?] = [
            value(in: root, keys: quotaContainerKeys),
            value(in: dataRoot, keys: quotaContainerKeys),
            dataRoot,
            root,
        ]
        var results: [[String: Any]] = []
        for candidate in candidates {
            results.append(contentsOf: extractQuotaObjects(from: candidate))
        }
        return deduplicated(results)
    }

    private static func extractQuotaObjects(from candidate: Any?) -> [[String: Any]] {
        if let array = candidate as? [Any] {
            return array.flatMap { extractQuotaObjects(from: $0) }
        }
        guard let dict = dictionaryValue(candidate) else { return [] }
        var results: [[String: Any]] = isQuotaPayload(dict) ? [dict] : []
        for value in dict.values {
            results.append(contentsOf: extractQuotaObjects(from: value))
        }
        return results
    }

    private static func deduplicated(_ objects: [[String: Any]]) -> [[String: Any]] {
        var seen: Set<Data> = []
        var unique: [[String: Any]] = []
        for object in objects {
            guard let key = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
                unique.append(object)
                continue
            }
            guard seen.insert(key).inserted else { continue }
            unique.append(object)
        }
        return unique
    }

    private static func isQuotaPayload(_ payload: [String: Any]) -> Bool {
        firstDouble(in: payload, keys: limitKeys) != nil ||
            firstDouble(in: payload, keys: usedKeys) != nil ||
            firstDouble(in: payload, keys: remainingKeys) != nil ||
            firstDouble(in: payload, keys: percentUsedKeys) != nil ||
            firstDouble(in: payload, keys: percentRemainingKeys) != nil
    }

    private static func kind(for window: ChutesQuotaWindow) -> WindowKind? {
        let label = [window.label, window.unit].compactMap { $0?.lowercased() }.joined(separator: " ")
        if label.contains("rolling") ||
            label.contains("4h") ||
            label.contains("4 h") ||
            label.contains("4-hour") ||
            label.contains("four hour") ||
            label.contains("four-hour") ||
            window.windowMinutes == ChutesUsageSnapshot.rollingWindowMinutes
        {
            return .rolling
        }
        if label.contains("month") ||
            label.contains("billing") ||
            label.contains("subscription") ||
            (window.windowMinutes ?? 0) >= 28 * 24 * 60
        {
            return .monthly
        }
        return nil
    }

    private static func windowMinutes(from payload: [String: Any]) -> Int? {
        if let minutes = firstDouble(in: payload, keys: windowMinuteKeys) { return Int(minutes.rounded()) }
        if let hours = firstDouble(in: payload, keys: windowHourKeys) { return Int((hours * 60).rounded()) }
        if let days = firstDouble(in: payload, keys: windowDayKeys) { return Int((days * 24 * 60).rounded()) }
        if let seconds = firstDouble(in: payload, keys: windowSecondKeys) { return Int((seconds / 60).rounded()) }
        if let text = firstString(in: payload, keys: windowStringKeys) { return windowMinutes(fromText: text) }
        return nil
    }

    static func windowMinutes(fromText raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        let compact = text.replacingOccurrences(of: " ", with: "")
        let scanner = Scanner(string: compact)
        guard let value = scanner.scanDouble(), value > 0 else { return nil }
        let suffix = String(compact[scanner.currentIndex...])
        if suffix.hasPrefix("min") || suffix == "m" { return Int(value.rounded()) }
        if suffix.hasPrefix("hour") || suffix.hasPrefix("hr") || suffix == "h" { return Int((value * 60).rounded()) }
        if suffix.hasPrefix("day") || suffix == "d" { return Int((value * 24 * 60).rounded()) }
        if suffix.hasPrefix("month") || suffix == "mo" { return Int((value * 30 * 24 * 60).rounded()) }
        return nil
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        guard let value = value(in: dict, keys: keys) else { return nil }
        if let string = value as? String {
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func firstBool(in dict: [String: Any], keys: [String]) -> Bool? {
        guard let value = value(in: dict, keys: keys) else { return nil }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes", "active":
                return true
            case "false", "0", "no", "inactive", "none":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private static func firstDouble(in dict: [String: Any], keys: [String]) -> Double? {
        doubleValue(value(in: dict, keys: keys))
    }

    private static func firstDate(in dict: [String: Any], keys: [String]) -> Date? {
        ChutesTimestampParser.parse(value(in: dict, keys: keys))
    }

    private static func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        let percent = abs(value) < 1 ? value * 100 : value
        return max(0, min(percent, 100))
    }

    private static func value(in dict: [String: Any], keys: [String]) -> Any? {
        for key in keys {
            let normalized = normalizedKey(key)
            for (candidateKey, value) in dict where normalizedKey(candidateKey) == normalized {
                return value
            }
        }
        return nil
    }

    private static func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double:
            double.isFinite ? double : nil
        case let int as Int:
            Double(int)
        case let number as NSNumber:
            number.doubleValue.isFinite ? number.doubleValue : nil
        case let string as String:
            doubleValue(from: string)
        default:
            nil
        }
    }

    private static func doubleValue(from raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard !text.isEmpty, let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func normalizedKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let rollingPayloadKeys = ["rolling", "rolling_window", "rollingWindow", "rolling_4h", "rolling4h", "four_hour", "fourHour", "four_hour_usage", "fourHourUsage", "window_4h", "window4h"]
    private static let monthlyPayloadKeys = ["monthly", "monthly_usage", "monthlyUsage", "subscription", "subscription_usage", "subscriptionUsage", "billing_period", "billingPeriod"]
    private static let quotaContainerKeys = ["quotas", "quota", "quota_usage", "quotaUsage", "limits", "usage", "entries", "subscription_usage", "subscriptionUsage"]
    private static let labelKeys = ["label", "name", "title", "type", "quota_type", "quotaType", "period", "window", "window_name", "windowName", "chute_id", "chuteId"]
    private static let limitKeys = ["limit", "cap", "max", "maximum", "quota", "quota_limit", "quotaLimit", "monthly_cap", "monthlyCap", "monthly_limit", "monthlyLimit", "request_limit", "requestLimit", "token_limit", "tokenLimit", "hard_limit", "hardLimit", "total"]
    private static let usedKeys = ["used", "usage", "used_amount", "usedAmount", "consumed", "consumed_amount", "consumedAmount", "current", "current_usage", "currentUsage", "requests", "request_count", "requestCount", "tokens", "token_usage", "tokenUsage", "monthly_usage", "monthlyUsage"]
    private static let remainingKeys = ["remaining", "available", "balance", "left", "remaining_amount", "remainingAmount", "available_amount", "availableAmount"]
    private static let percentUsedKeys = ["percent_used", "percentUsed", "usage_percent", "usagePercent", "used_percent", "usedPercent", "utilization", "utilization_percent", "utilizationPercent"]
    private static let percentRemainingKeys = ["percent_remaining", "percentRemaining", "remaining_percent", "remainingPercent"]
    private static let resetKeys = ["reset_at", "resetAt", "resets_at", "resetsAt", "reset_time", "resetTime", "next_reset_at", "nextResetAt", "renews_at", "renewsAt", "renewal_at", "renewalAt", "period_end", "periodEnd", "current_period_end", "currentPeriodEnd", "expires_at", "expiresAt", "window_end", "windowEnd", "end_time", "endTime"]
    private static let unitKeys = ["unit", "units", "currency", "quota_unit", "quotaUnit"]
    private static let activeKeys = ["active", "is_active", "isActive", "subscription_active", "subscriptionActive", "has_subscription", "hasSubscription"]
    private static let statusKeys = ["status", "state", "subscription_status", "subscriptionStatus"]
    private static let planKeys = ["plan_name", "planName", "plan", "tier", "subscription_plan", "subscriptionPlan", "subscription_tier", "subscriptionTier"]
    private static let windowMinuteKeys = ["window_minutes", "windowMinutes", "period_minutes", "periodMinutes", "duration_minutes", "durationMinutes"]
    private static let windowHourKeys = ["window_hours", "windowHours", "period_hours", "periodHours", "duration_hours", "durationHours"]
    private static let windowDayKeys = ["window_days", "windowDays", "period_days", "periodDays", "duration_days", "durationDays"]
    private static let windowSecondKeys = ["window_seconds", "windowSeconds", "period_seconds", "periodSeconds", "duration_seconds", "durationSeconds"]
    private static let windowStringKeys = ["window", "period", "interval", "duration"]
}
