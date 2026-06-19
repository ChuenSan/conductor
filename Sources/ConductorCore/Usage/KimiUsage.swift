import Foundation
import SweetCookieKit

/// Kimi（Moonshot Kimi 编码套餐）用量取数。摘自 CodexBar `Kimi` 的 apiToken/web 路径：
/// 用 `KIMI_CODE_API_KEY` 走 `Bearer` 调 Code API 的 `coding/v1/usages`，
/// 解析 `usage`（周配额）与 `limits[0].detail`（5 小时速率窗口）。账号级（与具体 CLI 无关）。
/// 显式 `web` 时用 `kimi-auth` JWT 调 `www.kimi.com` billing gateway；`auto` 先 API、再 Web。
///
/// 环境变量：`KIMI_CODE_API_KEY`（必需）、`KIMI_CODE_BASE_URL`（可选覆盖 base URL，默认 https://api.kimi.com）。
/// Web token 支持 `KIMI_AUTH_TOKEN` / `KIMI_MANUAL_COOKIE` / `CONDUCTOR_USAGE_KIMI_COOKIE`。
///
/// 注意：照搬自 CodexBar 源码，但本环境无 key 无法实跑验证，字段映射以其 Decodable 定义为准。
public enum KimiUsageError: LocalizedError, Sendable {
    case missingWebToken
    case missingAPIKey
    case invalidWebToken
    case invalidAPIKey
    case invalidRequest(String)
    case unsupportedSource(String)
    case server(Int)
    case invalidResponse
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingWebToken: L("未找到 Kimi Web 登录态，请设置 KIMI_AUTH_TOKEN 或粘贴 kimi-auth Cookie")
        case .missingAPIKey: L("未找到 Kimi 令牌，请设置环境变量 KIMI_CODE_API_KEY")
        case .invalidWebToken: L("Kimi Web 登录态无效或已过期")
        case .invalidAPIKey: L("Kimi 令牌无效或已过期")
        case let .invalidRequest(m): L("Kimi 请求无效：%@", m)
        case let .unsupportedSource(source): L("Kimi 来源 %@ 不受支持，请使用 auto、api 或 web", source)
        case let .server(code): L("Kimi 接口错误（%ld）", code)
        case .invalidResponse: L("Kimi 用量接口返回异常")
        case let .network(m): L("网络错误：%@", m)
        }
    }
}

public enum KimiUsageFetcher {
    private static let defaultBaseURL = URL(string: "https://api.kimi.com")!
    private static let webUsageURL =
        URL(string: "https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages")!
    private static let cookieDomains = ["www.kimi.com", "kimi.com"]

    /// 是否配置了 Kimi 令牌或手动 Web 登录态；不能读取浏览器 Cookie，避免配置探测触发钥匙串。
    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil || webAuthTokenOverride(env: env) != nil
    }

    static func token(env: [String: String]) -> String? {
        // 对应 CodexBar KimiSettingsReader.apiKeyEnvironmentKeys。
        for key in ["KIMI_CODE_API_KEY"] {
            if let v = clean(env[key]) { return v }
        }
        return nil
    }

    static func clean(_ raw: String?) -> String? {
        guard var v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        v = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    static func webAuthTokenOverride(env: [String: String]) -> String? {
        let candidates = [
            UsageProviderRuntimeConfig.manualCookieHeader(providerID: "kimi", env: env),
            env["KIMI_MANUAL_COOKIE"],
            env["KIMI_AUTH_TOKEN"],
            env["kimi_auth_token"],
        ]
        for raw in candidates {
            if let token = authToken(from: raw) { return token }
        }
        return nil
    }

    private static func authToken(from raw: String?) -> String? {
        guard let raw = clean(raw) else { return nil }
        if raw.hasPrefix("eyJ"), raw.split(separator: ".").count == 3 { return raw }
        for pair in CookieHeaderNormalizer.pairs(from: raw) where pair.name.lowercased() == "kimi-auth" {
            return pair.value.isEmpty ? nil : pair.value
        }
        let pattern = #"(?i)kimi-auth[:=]\s*([A-Za-z0-9._\-+=/]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: raw)
        else {
            return nil
        }
        let token = String(raw[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// Code API base URL（可被 `KIMI_CODE_BASE_URL` 覆盖，须为 https）。
    static func baseURL(env: [String: String]) -> URL {
        guard let raw = clean(env["KIMI_CODE_BASE_URL"]) else { return defaultBaseURL }
        guard let scheme = URL(string: raw)?.scheme?.lowercased(), scheme == "https",
              let url = URL(string: raw)
        else { return defaultBaseURL }
        return url
    }

    /// 拼接 `coding/v1/usages` 端点（与 CodexBar KimiUsageFetcher.codeAPIUsageEndpoint 一致）。
    static func usageEndpoint(baseURL: URL) -> URL {
        let normalizedPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath == "coding/v1" || normalizedPath.hasSuffix("/coding/v1") {
            return baseURL.appendingPathComponent("usages")
        }
        if normalizedPath == "coding" || normalizedPath.hasSuffix("/coding") {
            return baseURL
                .appendingPathComponent("v1")
                .appendingPathComponent("usages")
        }
        return baseURL
            .appendingPathComponent("coding")
            .appendingPathComponent("v1")
            .appendingPathComponent("usages")
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        let source = UsageProviderRuntimeConfig.sourceMode(providerID: "kimi", env: env) ?? "auto"
        switch source {
        case "api":
            return try await fetchAPI(env: env, session: session)
        case "web":
            return try await fetchWeb(env: env, session: session)
        case "auto":
            guard token(env: env) != nil else {
                return try await fetchWeb(env: env, session: session)
            }
            do {
                return try await fetchAPI(env: env, session: session)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return try await fetchWeb(env: env, session: session)
            }
        default:
            throw KimiUsageError.unsupportedSource(source)
        }
    }

    private static func fetchAPI(
        env: [String: String],
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        guard let apiKey = token(env: env) else { throw KimiUsageError.missingAPIKey }

        var request = URLRequest(url: usageEndpoint(baseURL: baseURL(env: env)))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw KimiUsageError.invalidResponse }
            data = d
            http = h
        } catch let e as KimiUsageError {
            throw e
        } catch {
            throw KimiUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            return try parse(data).withSourceLabel("api")
        case 400:
            throw KimiUsageError.invalidRequest("Bad request")
        case 401:
            throw KimiUsageError.invalidAPIKey
        default:
            throw KimiUsageError.server(http.statusCode)
        }
    }

    private static func fetchWeb(
        env: [String: String],
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        guard let authToken = webAuthToken(env: env) else { throw KimiUsageError.missingWebToken }
        let sessionInfo = decodeSessionInfo(from: authToken)

        var request = URLRequest(url: webUsageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("kimi-auth=\(authToken)", forHTTPHeaderField: "Cookie")
        request.setValue("https://www.kimi.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.kimi.com/code/console", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue("en-US", forHTTPHeaderField: "x-language")
        request.setValue("web", forHTTPHeaderField: "x-msh-platform")
        request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "r-timezone")
        if let deviceId = sessionInfo?.deviceId {
            request.setValue(deviceId, forHTTPHeaderField: "x-msh-device-id")
        }
        if let sessionId = sessionInfo?.sessionId {
            request.setValue(sessionId, forHTTPHeaderField: "x-msh-session-id")
        }
        if let trafficId = sessionInfo?.trafficId {
            request.setValue(trafficId, forHTTPHeaderField: "x-traffic-id")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["scope": ["FEATURE_CODING"]])

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw KimiUsageError.invalidResponse }
            data = d
            http = h
        } catch let e as KimiUsageError {
            throw e
        } catch {
            throw KimiUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            return try parseWeb(data).withSourceLabel("web")
        case 400:
            throw KimiUsageError.invalidRequest("Bad request")
        case 401, 403:
            throw KimiUsageError.invalidWebToken
        default:
            throw KimiUsageError.server(http.statusCode)
        }
    }

    private static func webAuthToken(env: [String: String]) -> String? {
        if let override = webAuthTokenOverride(env: env) { return override }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "kimi", env: env) else {
            return nil
        }
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        for browser in Browser.defaultImportOrder {
            guard let cookies = try? client.cookies(matching: query, in: browser), !cookies.isEmpty else { continue }
            if let token = cookies.first(where: { $0.name == "kimi-auth" })?.value,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return token
            }
        }
        return nil
    }

    // MARK: - 解析

    private struct Response: Decodable {
        let usage: Detail
        let limits: [RateLimit]?
    }

    private struct RateLimit: Decodable {
        let detail: Detail
    }

    private struct WebResponse: Decodable {
        let usages: [WebUsage]
    }

    private struct WebUsage: Decodable {
        let scope: String
        let detail: Detail
        let limits: [RateLimit]?
    }

    private struct SessionInfo {
        let deviceId: String?
        let sessionId: String?
        let trafficId: String?
    }

    /// 对应 CodexBar KimiUsageDetail：字段可能是 String / Int / Double，统一取成字符串数值。
    private struct Detail: Decodable {
        let limit: String
        let used: String?
        let remaining: String?
        let resetTime: String?

        private enum CodingKeys: String, CodingKey {
            case limit
            case used
            case remaining
            case resetTime
            case resetAt
            case resetTimeSnake = "reset_time"
            case resetAtSnake = "reset_at"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let limit = Self.stringValue(in: c, forKey: .limit) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.limit,
                    DecodingError.Context(codingPath: c.codingPath, debugDescription: "Kimi usage limit is missing"))
            }
            self.limit = limit
            used = Self.stringValue(in: c, forKey: .used)
            remaining = Self.stringValue(in: c, forKey: .remaining)
            resetTime =
                Self.stringValue(in: c, forKey: .resetTime) ??
                Self.stringValue(in: c, forKey: .resetAt) ??
                Self.stringValue(in: c, forKey: .resetTimeSnake) ??
                Self.stringValue(in: c, forKey: .resetAtSnake)
        }

        private static func stringValue(
            in container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys) -> String?
        {
            if let value = try? container.decode(String.self, forKey: key) { return value }
            if let value = try? container.decode(Int64.self, forKey: key) { return String(value) }
            if let value = try? container.decode(Double.self, forKey: key) {
                if value.rounded(.towardZero) == value,
                   value >= Double(Int64.min), value <= Double(Int64.max)
                {
                    return String(Int64(value))
                }
                return String(value)
            }
            return nil
        }
    }

    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: dateString)
    }

    /// 把一条 Kimi 用量明细拆出 (已用, 上限)，请求计数；used 缺失时用 limit-remaining 兜底。
    private static func usedAndLimit(_ d: Detail) -> (used: Int, limit: Int) {
        let limit = Int(d.limit) ?? 0
        let remaining = Int(d.remaining ?? "")
        let used = Int(d.used ?? "") ?? {
            guard let remaining else { return 0 }
            return max(0, limit - remaining)
        }()
        return (used, limit)
    }

    /// 把一条明细折算成富 `RateWindow`：百分比 + 重置时刻 + “已用/上限 次请求”描述。
    private static func window(_ d: Detail?, title: String, windowMinutes: Int?) -> RateWindow? {
        guard let d else { return nil }
        let (used, limit) = usedAndLimit(d)
        let pct = limit > 0 ? Double(used) / Double(limit) * 100 : 0
        return RateWindow(
            title: title,
            usedPercent: pct,
            windowMinutes: windowMinutes,
            resetsAt: parseDate(d.resetTime),
            resetDescription: L("%ld/%ld 次请求", used, limit))
    }

    static func parse(_ data: Data) throws -> UsageSnapshot {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw KimiUsageError.invalidResponse
        }

        // 映射同 CodexBar KimiUsageSnapshot.toUsageSnapshot：
        // usage（周配额，无固定窗口）→ primary；limits[0].detail（5 小时速率窗）→ secondary。
        let primary = window(response.usage, title: L("周配额"), windowMinutes: nil)
        let secondary = window(
            response.limits?.first?.detail,
            title: L("5 小时窗口"),
            windowMinutes: 300) // 300 分钟 = 5 小时

        guard primary != nil || secondary != nil else { throw KimiUsageError.invalidResponse }

        // Kimi Code API 仅返回滑动窗百分比/请求计数，无余额或 credits/美元金额
        //（CodexBar KimiProviderDescriptor 亦标注 supportsCredits=false），故 providerCost 留 nil。
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil)
    }

    static func parseWeb(_ data: Data) throws -> UsageSnapshot {
        let response: WebResponse
        do {
            response = try JSONDecoder().decode(WebResponse.self, from: data)
        } catch {
            throw KimiUsageError.invalidResponse
        }
        guard let codingUsage = response.usages.first(where: { $0.scope == "FEATURE_CODING" }) else {
            throw KimiUsageError.invalidResponse
        }
        let primary = window(codingUsage.detail, title: L("周配额"), windowMinutes: nil)
        let secondary = window(
            codingUsage.limits?.first?.detail,
            title: L("5 小时窗口"),
            windowMinutes: 300)
        guard primary != nil || secondary != nil else { throw KimiUsageError.invalidResponse }
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil)
    }

    private static func decodeSessionInfo(from jwt: String) -> SessionInfo? {
        let parts = jwt.split(separator: ".", maxSplits: 2)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload += "="
        }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return SessionInfo(
            deviceId: json["device_id"] as? String,
            sessionId: json["ssid"] as? String,
            trafficId: json["sub"] as? String)
    }
}
