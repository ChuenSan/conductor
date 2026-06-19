import Foundation

/// Poe 用量取数。转写自 CodexBar `PoeUsageFetcher`：
/// 使用官方 API key 读取当前点数余额，并 best-effort 拉取最近 30 天 points history。
///
/// 环境变量：`POE_API_KEY`（必需）。
public enum PoeUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case networkError(String)
    case apiError(String)
    case unauthorized
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            L("未找到 Poe API token")
        case let .networkError(message):
            L("Poe 网络错误：%@", message)
        case let .apiError(message):
            L("Poe API 错误：%@", message)
        case .unauthorized:
            L("Poe API token 无效或已过期")
        case let .parseFailed(message):
            L("解析 Poe 响应失败：%@", message)
        }
    }
}

public struct PoeUsageSnapshot: Sendable, Equatable {
    public let currentPointBalance: Double?
    public let history: PoeUsageHistorySnapshot?
    public let updatedAt: Date

    public init(currentPointBalance: Double? = nil, history: PoeUsageHistorySnapshot? = nil, updatedAt: Date = Date()) {
        self.currentPointBalance = currentPointBalance
        self.history = history
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let primary = history?.rateWindow(days: 1, title: L("今日"))
        let secondary = history?.rateWindow(days: 7, title: "7d")
        let tertiary = history?.rateWindow(days: 30, title: "30d")
        let extras = history?.topModels.prefix(3).map { item in
            NamedRateWindow(
                id: "poe.model.\(item.name)",
                title: item.name,
                window: RateWindow(
                    usedPercent: 0,
                    resetDescription: Self.summaryDescription(points: item.points, requests: item.requests)))
        } ?? []

        let providerCost = currentPointBalance.flatMap { balance -> ProviderCostSnapshot? in
            guard balance.isFinite else { return nil }
            return ProviderCostSnapshot(used: balance, limit: 0, currencyCode: "Points", period: L("余额"))
        }

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: Array(extras),
            providerCost: providerCost,
            accountLabel: balanceLabel,
            updatedAt: updatedAt)
    }

    private var balanceLabel: String? {
        guard let balance = currentPointBalance, balance.isFinite else { return nil }
        return L("余额：%@ 点", Self.compactNumber(balance))
    }

    static func summaryDescription(points: Double, requests: Int) -> String {
        L("%@ 点 · %ld 次请求", compactNumber(points), requests)
    }

    static func compactNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}

public struct PoeUsageHistorySnapshot: Codable, Equatable, Sendable {
    public struct BreakdownItem: Equatable, Sendable {
        public let name: String
        public let points: Double
        public let requests: Int
        public let costUSD: Double?
    }

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public let id: String
        public let createdAt: Date
        public let model: String
        public let usageType: String
        public let points: Double
        public let costUSD: Double?

        public init(id: String, createdAt: Date, model: String, usageType: String, points: Double, costUSD: Double?) {
            self.id = id
            self.createdAt = createdAt
            self.model = model
            self.usageType = usageType
            self.points = points
            self.costUSD = costUSD
        }
    }

    public struct DailyBucket: Codable, Equatable, Sendable, Identifiable {
        public let day: String
        public let points: Double
        public let requests: Int
        public let costUSD: Double?

        public init(day: String, points: Double, requests: Int, costUSD: Double?) {
            self.day = day
            self.points = points
            self.requests = requests
            self.costUSD = costUSD
        }

        public var id: String { day }
    }

    public struct Summary: Equatable, Sendable {
        public let points: Double
        public let requests: Int
        public let costUSD: Double?
    }

    public let entries: [Entry]
    public let daily: [DailyBucket]
    public let updatedAt: Date

    public init(entries: [Entry], daily: [DailyBucket], updatedAt: Date) {
        self.entries = entries.sorted { $0.createdAt < $1.createdAt }
        self.daily = daily.sorted { $0.day < $1.day }
        self.updatedAt = updatedAt
    }

    public var latestDay: Summary { summary(days: 1) }
    public var last7Days: Summary { summary(days: 7) }
    public var last30Days: Summary { summary(days: 30) }

    public func summary(days: Int) -> Summary {
        let selected = daily.suffix(max(1, days))
        let points = selected.reduce(0) { $0 + $1.points }
        let requests = selected.reduce(0) { $0 + $1.requests }
        let costValues = selected.compactMap(\.costUSD)
        let cost = costValues.isEmpty ? nil : costValues.reduce(0, +)
        return Summary(points: points, requests: requests, costUSD: cost)
    }

    public func rateWindow(days: Int, title: String) -> RateWindow? {
        let summary = summary(days: days)
        guard summary.points > 0 || summary.requests > 0 else { return nil }
        return RateWindow(
            title: title,
            usedPercent: 0,
            resetDescription: PoeUsageSnapshot.summaryDescription(points: summary.points, requests: summary.requests))
    }

    public var topModels: [BreakdownItem] {
        breakdown(groupedBy: \.model, fallback: "unknown")
    }

    public var topUsageTypes: [BreakdownItem] {
        breakdown(groupedBy: \.usageType, fallback: "unknown")
    }

    public func recentEntries(limit: Int = 3) -> [Entry] {
        Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(max(1, limit)))
    }

    private func breakdown(groupedBy keyPath: KeyPath<Entry, String>, fallback: String) -> [BreakdownItem] {
        struct Acc {
            var points: Double = 0
            var requests: Int = 0
            var costUSD: Double = 0
            var hasCost = false
        }

        var grouped: [String: Acc] = [:]
        for entry in entries {
            let raw = entry[keyPath: keyPath].trimmingCharacters(in: .whitespacesAndNewlines)
            let key = raw.isEmpty ? fallback : raw
            var row = grouped[key] ?? Acc()
            row.points += max(0, entry.points)
            row.requests += 1
            if let cost = entry.costUSD {
                row.costUSD += max(0, cost)
                row.hasCost = true
            }
            grouped[key] = row
        }

        return grouped.map { key, value in
            BreakdownItem(
                name: key,
                points: value.points,
                requests: value.requests,
                costUSD: value.hasCost ? value.costUSD : nil)
        }
        .sorted {
            if $0.points == $1.points { return $0.name < $1.name }
            return $0.points > $1.points
        }
    }
}

public enum PoeUsageFetcher {
    public static let apiKeyEnvironmentKey = "POE_API_KEY"
    private static let usageURL = URL(string: "https://api.poe.com/usage/current_balance")!
    private static let historyURL = URL(string: "https://api.poe.com/usage/points_history")!
    private static let timeoutSeconds: TimeInterval = 15

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

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        guard let apiKey = token(env: env) else { throw PoeUsageError.missingCredentials }
        return try await fetchUsage(apiKey: apiKey, session: session).toUsageSnapshot()
    }

    static func fetchUsage(apiKey: String, session: URLSession = .shared) async throws -> PoeUsageSnapshot {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PoeUsageError.missingCredentials }

        let balanceData = try await perform(url: usageURL, apiKey: trimmed, session: session)
        let balance = try parseSnapshot(balanceData).currentPointBalance

        let history: PoeUsageHistorySnapshot?
        do {
            history = try await fetchHistory(apiKey: trimmed, session: session)
        } catch {
            history = nil
        }
        return PoeUsageSnapshot(currentPointBalance: balance, history: history, updatedAt: Date())
    }

    static func parseSnapshot(_ data: Data) throws -> PoeUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PoeUsageError.parseFailed("Invalid JSON")
        }
        return PoeUsageSnapshot(currentPointBalance: double(from: root["current_point_balance"]), updatedAt: Date())
    }

    static func parseHistoryPage(_ data: Data) throws -> (entries: [PoeUsageHistorySnapshot.Entry], nextCursor: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PoeUsageError.parseFailed("Invalid history JSON")
        }

        let rawEntries: [[String: Any]] = if let rows = root["data"] as? [[String: Any]] {
            rows
        } else if let rows = root["items"] as? [[String: Any]] {
            rows
        } else if let rows = root["results"] as? [[String: Any]] {
            rows
        } else {
            []
        }

        let entries = rawEntries.compactMap { row -> PoeUsageHistorySnapshot.Entry? in
            guard let createdAt = date(fromHistoryValue: row["creation_time"] ?? row["timestamp"] ?? row["created_at"]) else {
                return nil
            }
            let model = (row["bot_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let usageType = (row["usage_type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            let points = double(from: row["cost_points"])
                ?? double(from: row["points"])
                ?? double(from: row["point_cost"])
                ?? 0
            let costUSD = double(from: row["cost_usd"] ?? row["usd"])
            let id = (row["query_id"] as? String)
                ?? (row["message_id"] as? String)
                ?? (row["id"] as? String)
                ?? "\(createdAt.timeIntervalSince1970)-\(model)"
            return PoeUsageHistorySnapshot.Entry(
                id: id,
                createdAt: createdAt,
                model: model.isEmpty ? "unknown" : model,
                usageType: usageType.isEmpty ? "unknown" : usageType,
                points: max(0, points),
                costUSD: costUSD)
        }

        let nextCursor = (root["next_cursor"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let nextCursor, !nextCursor.isEmpty {
            return (entries, nextCursor)
        }
        if let hasMore = root["has_more"] as? Bool, hasMore {
            let fallbackCursor = (rawEntries.last?["query_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let fallbackCursor, !fallbackCursor.isEmpty {
                return (entries, fallbackCursor)
            }
        }
        return (entries, nil)
    }

    static func buildDailyBuckets(entries: [PoeUsageHistorySnapshot.Entry]) -> [PoeUsageHistorySnapshot.DailyBucket] {
        var acc: [String: (points: Double, requests: Int, costUSD: Double)] = [:]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        for entry in entries {
            let key = formatter.string(from: entry.createdAt)
            var row = acc[key] ?? (points: 0, requests: 0, costUSD: 0)
            row.points += max(0, entry.points)
            row.requests += 1
            row.costUSD += max(0, entry.costUSD ?? 0)
            acc[key] = row
        }
        return acc.keys.sorted().map { day in
            let row = acc[day] ?? (0, 0, 0)
            return PoeUsageHistorySnapshot.DailyBucket(
                day: day,
                points: row.points,
                requests: row.requests,
                costUSD: row.costUSD > 0 ? row.costUSD : nil)
        }
    }

    private static func fetchHistory(apiKey: String, session: URLSession) async throws -> PoeUsageHistorySnapshot? {
        var cursor: String?
        var entries: [PoeUsageHistorySnapshot.Entry] = []
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        var page = 0

        while page < 5 {
            page += 1
            var components = URLComponents(url: historyURL, resolvingAgainstBaseURL: false)
            var query = [URLQueryItem(name: "limit", value: "100")]
            if let cursor, !cursor.isEmpty {
                query.append(URLQueryItem(name: "starting_after", value: cursor))
            }
            components?.queryItems = query
            guard let url = components?.url else {
                throw PoeUsageError.parseFailed("Invalid points_history URL")
            }

            let data = try await perform(url: url, apiKey: apiKey, session: session)
            let parsed = try parseHistoryPage(data)
            entries.append(contentsOf: parsed.entries)
            cursor = parsed.nextCursor

            if parsed.entries.last?.createdAt ?? .distantPast < cutoff { break }
            if cursor == nil { break }
        }

        guard !entries.isEmpty else { return nil }
        let filtered = entries.filter { $0.createdAt >= cutoff }
        guard !filtered.isEmpty else { return nil }
        return PoeUsageHistorySnapshot(
            entries: filtered,
            daily: buildDailyBuckets(entries: filtered),
            updatedAt: Date())
    }

    private static func perform(url: URL, apiKey: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw PoeUsageError.networkError("Non-HTTP response") }
            data = responseData
            http = response
        } catch let error as PoeUsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PoeUsageError.networkError(error.localizedDescription)
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw PoeUsageError.unauthorized
            }
            throw PoeUsageError.apiError("HTTP \(http.statusCode)")
        }
        return data
    }

    private static func date(fromHistoryValue value: Any?) -> Date? {
        switch value {
        case let number as NSNumber:
            return date(fromNumericTimestamp: number.doubleValue)
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let numeric = Double(trimmed) {
                return date(fromNumericTimestamp: numeric)
            }
            return ISO8601DateFormatter().date(from: trimmed)
        default:
            return nil
        }
    }

    private static func date(fromNumericTimestamp raw: Double) -> Date? {
        guard raw.isFinite, raw > 0 else { return nil }
        if raw > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: raw / 1_000_000)
        }
        return Date(timeIntervalSince1970: raw)
    }

    private static func double(from value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            let raw = number.doubleValue
            return raw.isFinite ? raw : nil
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let raw = Double(trimmed), raw.isFinite else { return nil }
            return raw
        default:
            return nil
        }
    }
}
