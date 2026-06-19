import Foundation

/// GLM / Z.ai（智谱 GLM 编码套餐）用量取数。摘自 CodexBar `Zai` provider，自足、不依赖 cookie：
/// 用 `Z_AI_API_KEY` 走 `Bearer` 调 `https://api.z.ai/api/monitor/usage/quota/limit`，
/// 解析 TOKENS_LIMIT / TIME_LIMIT 限额，并 best-effort 附加 model-usage 明细。
/// 账号级（与具体 CLI 无关）。
///
/// 环境变量：`Z_AI_API_KEY`（必需）、`Z_AI_REGION=bigmodel-cn` 或
/// `Z_AI_API_HOST` / `Z_AI_QUOTA_URL`（可选覆盖，CN 用户可指向 open.bigmodel.cn）。
public enum GLMUsageError: LocalizedError, Sendable {
    case missingToken
    case server(Int)
    case invalidResponse
    case apiError(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken: L("未找到 GLM(Z.ai) 令牌，请设置环境变量 Z_AI_API_KEY")
        case let .server(code): L("Z.ai 接口错误（%ld）", code)
        case .invalidResponse: L("Z.ai 用量接口返回异常")
        case let .apiError(m): L("Z.ai API 错误：%@", m)
        case let .network(m): L("网络错误：%@", m)
        }
    }
}

public enum GLMUsageFetcher {
    private enum Region: String {
        case global
        case bigmodelCN = "bigmodel-cn"
    }

    private static let quotaPath = "api/monitor/usage/quota/limit"
    private static let modelUsagePath = "api/monitor/usage/model-usage"
    private static let globalHost = "https://api.z.ai"
    private static let bigmodelCNHost = "https://open.bigmodel.cn"
    private static let regionEnvironmentKey = "Z_AI_REGION"

    /// 是否配置了 GLM 令牌（用于在工具面板里把 GLM 视作「可用」）。
    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil
    }

    static func token(env: [String: String]) -> String? {
        clean(env["Z_AI_API_KEY"])
    }

    static func clean(_ raw: String?) -> String? {
        guard var v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v.isEmpty ? nil : v
    }

    static func region(env: [String: String]) -> String {
        let raw = clean(env[regionEnvironmentKey])?.lowercased()
        return raw == Region.bigmodelCN.rawValue ? Region.bigmodelCN.rawValue : Region.global.rawValue
    }

    static func quotaURL(env: [String: String]) -> URL {
        if let raw = clean(env["Z_AI_QUOTA_URL"]) {
            if let u = URL(string: raw), u.scheme != nil { return u }
            if let u = URL(string: "https://\(raw)") { return u }
        }
        let host = clean(env["Z_AI_API_HOST"]).map { $0.contains("://") ? $0 : "https://\($0)" } ?? defaultHost(env: env)
        return URL(string: host)!.appendingPathComponent(quotaPath)
    }

    static func modelUsageURL(env: [String: String]) -> URL {
        let host = clean(env["Z_AI_API_HOST"]).map { $0.contains("://") ? $0 : "https://\($0)" } ?? defaultHost(env: env)
        if let url = URL(string: host), url.scheme != nil {
            if url.path.isEmpty || url.path == "/" {
                return url.appendingPathComponent(modelUsagePath)
            }
            return url
        }
        return URL(string: "https://\(host)")!.appendingPathComponent(modelUsagePath)
    }

    private static func defaultHost(env: [String: String]) -> String {
        switch region(env: env) {
        case Region.bigmodelCN.rawValue:
            return bigmodelCNHost
        default:
            return globalHost
        }
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        guard let apiKey = token(env: env) else { throw GLMUsageError.missingToken }

        var request = URLRequest(url: quotaURL(env: env))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw GLMUsageError.invalidResponse }
            data = d
            http = h
        } catch let e as GLMUsageError {
            throw e
        } catch {
            throw GLMUsageError.network(error.localizedDescription)
        }
        guard http.statusCode == 200 else { throw GLMUsageError.server(http.statusCode) }
        var snapshot = try parse(data)
        do {
            let modelUsage = try await fetchModelUsage(apiKey: apiKey, env: env, session: session)
            snapshot = addingExtraWindows(modelUsageExtraWindows(from: modelUsage), to: snapshot)
        } catch {
            // CodexBar treats model-usage as optional; quota data is still useful when this endpoint fails.
        }
        return snapshot
    }

    static func fetchModelUsage(
        apiKey: String,
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> ModelUsageData
    {
        let now = Date()
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
        let end = now

        func timestamp(_ date: Date, endOfHour: Bool) -> String {
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            return String(
                format: "%04d-%02d-%02d %02d:%02d:%02d",
                components.year ?? 1970,
                components.month ?? 1,
                components.day ?? 1,
                components.hour ?? 0,
                endOfHour ? 59 : 0,
                endOfHour ? 59 : 0)
        }

        guard var components = URLComponents(url: modelUsageURL(env: env), resolvingAgainstBaseURL: false) else {
            throw GLMUsageError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "startTime", value: timestamp(start, endOfHour: false)),
            URLQueryItem(name: "endTime", value: timestamp(end, endOfHour: true)),
        ]
        guard let url = components.url else { throw GLMUsageError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw GLMUsageError.invalidResponse }
            data = d
            http = h
        } catch let e as GLMUsageError {
            throw e
        } catch {
            throw GLMUsageError.network(error.localizedDescription)
        }
        guard http.statusCode == 200 else { throw GLMUsageError.server(http.statusCode) }
        guard !data.isEmpty else { return ModelUsageData(xTime: [], modelDataList: []) }
        return try parseModelUsage(data)
    }

    // MARK: - 解析

    private struct Response: Decodable {
        let code: Int
        let success: Bool
        let msg: String?
        let data: Payload?
    }

    private struct Payload: Decodable {
        let limits: [LimitRaw]?
        let planName: String?
        enum CodingKeys: String, CodingKey {
            case limits, planName, plan
            case planType = "plan_type"
            case packageName
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            limits = try c.decodeIfPresent([LimitRaw].self, forKey: .limits) ?? []
            let candidates = [
                try? c.decodeIfPresent(String.self, forKey: .planName),
                try? c.decodeIfPresent(String.self, forKey: .plan),
                try? c.decodeIfPresent(String.self, forKey: .planType),
                try? c.decodeIfPresent(String.self, forKey: .packageName),
            ].compactMap { $0 }.compactMap { $0 }
            planName = candidates.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    private struct LimitRaw: Decodable {
        let type: String
        let unit: Int
        let number: Int
        let usage: Int?
        let currentValue: Int?
        let remaining: Int?
        let percentage: Int
        let usageDetails: [UsageDetail]?
        let nextResetTime: Int?
    }

    private struct UsageDetail: Decodable {
        let modelCode: String
        let usage: Int
    }

    /// 一条限额的「已用百分比」「窗口秒数」「重置时刻」。
    private struct Limit {
        let isToken: Bool
        let usedPercent: Int
        let windowSeconds: Int?
        let resetAt: Date?
        let usage: Int?
        let usageDetails: [UsageDetail]
    }

    private static func makeLimit(_ raw: LimitRaw) -> Limit? {
        let isToken = raw.type == "TOKENS_LIMIT"
        let isTime = raw.type == "TIME_LIMIT"
        guard isToken || isTime else { return nil }

        // 优先用 usage/remaining/currentValue 精算，缺字段则回退 percentage（避免误判 100%）。
        var used: Double?
        if let limit = raw.usage, limit > 0 {
            var usedRaw: Int?
            if let remaining = raw.remaining {
                let fromRemaining = limit - remaining
                usedRaw = raw.currentValue.map { max(fromRemaining, $0) } ?? fromRemaining
            } else if let cv = raw.currentValue {
                usedRaw = cv
            }
            if let usedRaw {
                let u = max(0, min(limit, usedRaw))
                used = Double(u) / Double(limit) * 100
            }
        }
        let pct = used ?? Double(raw.percentage)
        let clamped = max(0, min(100, Int(pct.rounded())))

        let windowSeconds: Int? = raw.number > 0 ? {
            switch raw.unit {
            case 5: return raw.number * 60          // minutes
            case 3: return raw.number * 3600        // hours
            case 1: return raw.number * 86400       // days
            case 6: return raw.number * 7 * 86400   // weeks
            default: return nil
            }
        }() : nil
        let reset = raw.nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
        return Limit(
            isToken: isToken,
            usedPercent: clamped,
            windowSeconds: windowSeconds,
            resetAt: reset,
            usage: raw.usage,
            usageDetails: raw.usageDetails ?? [])
    }

    static func parse(_ data: Data) throws -> CodexUsageSnapshot {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.success, response.code == 200 else {
            throw GLMUsageError.apiError(response.msg ?? "unknown")
        }
        guard let payload = response.data else { throw GLMUsageError.invalidResponse }

        let limits = (payload.limits ?? []).compactMap(makeLimit)
        let tokenLimits = limits.filter(\.isToken).sorted { ($0.windowSeconds ?? .max) < ($1.windowSeconds ?? .max) }
        let timeLimit = limits.first { !$0.isToken }

        // session = 最短 TOKENS_LIMIT（如 5 小时）；weekly = 最长 TOKENS_LIMIT 或 TIME_LIMIT（月）。
        let sessionLimit = tokenLimits.first
        let weeklyLimit = (tokenLimits.count >= 2 ? tokenLimits.last : nil) ?? timeLimit

        func window(_ l: Limit?) -> CodexUsageSnapshot.Window? {
            guard let l else { return nil }
            let secs = l.windowSeconds ?? 0
            return CodexUsageSnapshot.Window(
                usedPercent: l.usedPercent,
                resetAt: l.resetAt ?? Date().addingTimeInterval(TimeInterval(secs > 0 ? secs : 86400)),
                windowSeconds: secs)
        }

        let session = window(sessionLimit)
        let weekly = window(weeklyLimit)
        guard session != nil || weekly != nil else { throw GLMUsageError.invalidResponse }
        return CodexUsageSnapshot(
            planType: payload.planName,
            session: session,
            weekly: weekly,
            extraRateWindows: mcpDetailWindows(from: timeLimit))
    }

    struct ModelUsageData: Sendable, Equatable {
        let xTime: [String]
        let modelDataList: [ModelDataItem]
    }

    struct ModelDataItem: Sendable, Equatable {
        let modelName: String?
        let tokensUsage: [Int?]
    }

    private struct ModelUsageResponse: Decodable {
        let code: Int
        let success: Bool
        let msg: String?
        let data: ModelUsagePayload?

        var isSuccess: Bool {
            success && code == 200
        }
    }

    private struct ModelUsagePayload: Decodable {
        let xTime: [String]?
        let modelDataList: [ModelDataItemRaw]?

        enum CodingKeys: String, CodingKey {
            case xTime = "x_time"
            case modelDataList
        }
    }

    private struct ModelDataItemRaw: Decodable {
        let modelName: String?
        let tokensUsage: [Int?]?
    }

    static func parseModelUsage(_ data: Data) throws -> ModelUsageData {
        let response = try JSONDecoder().decode(ModelUsageResponse.self, from: data)
        guard response.isSuccess else {
            throw GLMUsageError.apiError(response.msg ?? "unknown")
        }
        guard let payload = response.data else {
            return ModelUsageData(xTime: [], modelDataList: [])
        }
        return ModelUsageData(
            xTime: payload.xTime ?? [],
            modelDataList: (payload.modelDataList ?? []).map {
                ModelDataItem(modelName: $0.modelName, tokensUsage: $0.tokensUsage ?? [])
            })
    }

    static func hourlyBars(from modelUsage: ModelUsageData, now: Date = Date()) -> [(label: String, model: String, tokens: Int)] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .hour, value: -24, to: now) ?? now
        return modelUsage.xTime.enumerated().flatMap { index, timeString -> [(label: String, model: String, tokens: Int)] in
            guard let date = parseHourDate(timeString), date >= cutoff else { return [] }
            let label = hourLabel(date)
            return modelUsage.modelDataList.compactMap { item in
                guard index < item.tokensUsage.count,
                      let tokens = item.tokensUsage[index],
                      tokens > 0
                else { return nil }
                return (label: label, model: item.modelName ?? "Unknown", tokens: tokens)
            }
        }
    }

    private static func parseHourDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)
    }

    private static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func modelUsageExtraWindows(from modelUsage: ModelUsageData) -> [NamedRateWindow] {
        let totals = modelUsage.modelDataList.compactMap { item -> (model: String, tokens: Int)? in
            let tokens = item.tokensUsage.compactMap(\.self).reduce(0, +)
            guard tokens > 0 else { return nil }
            return (item.modelName ?? "Unknown", tokens)
        }
        let totalTokens = totals.reduce(0) { $0 + $1.tokens }
        guard totalTokens > 0 else { return [] }
        return totals
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens { return lhs.model < rhs.model }
                return lhs.tokens > rhs.tokens
            }
            .prefix(5)
            .map { entry in
                NamedRateWindow(
                    id: "zai.model.\(slug(entry.model))",
                    title: "\(entry.model) · 24h",
                    window: RateWindow(
                        usedPercent: Double(entry.tokens) / Double(totalTokens) * 100,
                        windowMinutes: 24 * 60,
                        resetDescription: "Last 24h"))
            }
    }

    private static func mcpDetailWindows(from timeLimit: Limit?) -> [NamedRateWindow] {
        guard let timeLimit,
              !timeLimit.usageDetails.isEmpty
        else { return [] }
        let totalUsage = max(1, timeLimit.usage ?? timeLimit.usageDetails.reduce(0) { $0 + max(0, $1.usage) })
        return timeLimit.usageDetails
            .filter { $0.usage > 0 }
            .sorted { lhs, rhs in
                if lhs.usage == rhs.usage { return lhs.modelCode < rhs.modelCode }
                return lhs.usage > rhs.usage
            }
            .prefix(5)
            .map { detail in
                NamedRateWindow(
                    id: "zai.mcp.\(slug(detail.modelCode))",
                    title: "MCP · \(detail.modelCode)",
                    window: RateWindow(
                        usedPercent: Double(detail.usage) / Double(totalUsage) * 100,
                        windowMinutes: nil,
                        resetDescription: "MCP"))
            }
    }

    private static func addingExtraWindows(_ windows: [NamedRateWindow], to snapshot: CodexUsageSnapshot) -> CodexUsageSnapshot {
        guard !windows.isEmpty else { return snapshot }
        var ids = Set(snapshot.extraRateWindows.map(\.id))
        let merged = snapshot.extraRateWindows + windows.filter { ids.insert($0.id).inserted }
        return CodexUsageSnapshot(
            sourceLabel: snapshot.sourceLabel,
            planType: snapshot.planType,
            accountLabel: snapshot.accountLabel,
            session: snapshot.session,
            weekly: snapshot.weekly,
            providerCost: snapshot.providerCost,
            ampUsage: snapshot.ampUsage,
            extraRateWindows: merged,
            codexResetCredits: snapshot.codexResetCredits)
    }

    private static func slug(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "unknown" : collapsed
    }
}
