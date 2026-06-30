import Foundation
import SweetCookieKit

/// Qwen / 通义（Alibaba 百炼编码套餐）用量取数。摘自 CodexBar `Alibaba CodingPlan` 的 apiKey 路径，
/// 自足、不依赖 cookie：用 `ALIBABA_CODING_PLAN_API_KEY`（或 `ALIBABA_QWEN_API_KEY` / `DASHSCOPE_API_KEY`）
/// POST 百炼网关 `queryCodingPlanInstanceInfoV2`，从返回里取 5 小时 / 周 配额。
///
/// 解析采用递归深搜定位含配额字段的对象（并展开内嵌 JSON 字符串），避开 CodexBar 的 instance 选择逻辑。
/// 照搬字段名自 CodexBar，本机无 key 无法实跑验证。
public enum QwenUsageError: LocalizedError, Sendable {
    case missingToken
    case missingCookie
    case invalidCookie
    case unauthorized
    case server(Int)
    case invalidResponse
    case invalidEndpointOverride(String)
    case network(String)
    case unsupportedSource(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken: L("未找到通义/Qwen 令牌，请设置 ALIBABA_CODING_PLAN_API_KEY")
        case .missingCookie: L("未找到 Alibaba Coding Plan 登录态，请设置 ALIBABA_CODING_PLAN_COOKIE 或在浏览器登录")
        case .invalidCookie: L("Alibaba Coding Plan Cookie 无效，请重新粘贴完整 Cookie header")
        case .unauthorized: L("通义令牌无效，或该区域不支持 API key 模式")
        case let .server(c): L("通义接口错误（%ld）", c)
        case .invalidResponse: L("通义用量接口返回异常")
        case let .invalidEndpointOverride(key): L("Alibaba Coding Plan 端点覆盖 %@ 必须使用安全的 HTTPS 地址", key)
        case let .network(m): L("网络错误：%@", m)
        case let .unsupportedSource(source): L("Alibaba Coding Plan 来源 %@ 不受支持，请使用 auto、api 或 web", source)
        }
    }
}

public enum QwenUsageFetcher {
    private struct Region {
        let id: String
        let gateway: String
        let commodity: String
        let regionId: String
        let referer: String

        var consoleRPCBase: String {
            id == "cn" ? "https://bailian-cs.console.aliyun.com" : "https://bailian-singapore-cs.alibabacloud.com"
        }

        var consoleRPCAction: String {
            id == "cn" ? "BroadScopeAspnGateway" : "IntlBroadScopeAspnGateway"
        }

        var consoleDomain: String {
            id == "cn" ? "bailian.console.aliyun.com" : "modelstudio.console.alibabacloud.com"
        }

        var consoleSite: String {
            id == "cn" ? "BAILIAN_ALIYUN" : "MODELSTUDIO_ALIBABACLOUD"
        }

        var consoleReferer: String {
            id == "cn"
                ? "https://bailian.console.aliyun.com/cn-beijing/?tab=model"
                : "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan"
        }
    }

    private static let intl = Region(
        id: "intl",
        gateway: "https://modelstudio.console.alibabacloud.com",
        commodity: "sfm_codingplan_public_intl",
        regionId: "ap-southeast-1",
        referer: "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan")
    private static let cn = Region(
        id: "cn",
        gateway: "https://bailian.console.aliyun.com",
        commodity: "sfm_codingplan_public_cn",
        regionId: "cn-beijing",
        referer: "https://bailian.console.aliyun.com/cn-beijing/?tab=model#/efm/coding_plan")
    private static let hostEnvironmentKey = "ALIBABA_CODING_PLAN_HOST"
    private static let quotaURLEnvironmentKey = "ALIBABA_CODING_PLAN_QUOTA_URL"
    private static let requireProviderEndpointOverridesKey = "ALIBABA_CODING_PLAN_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"
    private static let regionEnvironmentKeys = ["ALIBABA_CODING_PLAN_REGION", "QWEN_REGION"]
    private static let cookieEnvironmentKey = "ALIBABA_CODING_PLAN_COOKIE"
    private static let cookieDomains = [
        "bailian-singapore-cs.alibabacloud.com",
        "bailian-cs.console.aliyun.com",
        "bailian-beijing-cs.aliyuncs.com",
        "modelstudio.console.alibabacloud.com",
        "bailian.console.aliyun.com",
        "free.aliyun.com",
        "account.aliyun.com",
        "signin.aliyun.com",
        "passport.alibabacloud.com",
        "console.alibabacloud.com",
        "console.aliyun.com",
        "alibabacloud.com",
        "aliyun.com",
    ]
    private static let allowedEndpointHosts: Set<String> = [
        "modelstudio.console.alibabacloud.com",
        "bailian.console.aliyun.com",
        "bailian-singapore-cs.alibabacloud.com",
        "bailian-cs.console.aliyun.com",
        "bailian-beijing-cs.aliyuncs.com",
    ]

    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil || manualCookieHeader(env: env) != nil
    }

    static func token(env: [String: String]) -> String? {
        for key in ["ALIBABA_CODING_PLAN_API_KEY", "ALIBABA_QWEN_API_KEY", "DASHSCOPE_API_KEY"] {
            if let v = clean(env[key]) { return v }
        }
        return nil
    }

    static func region(env: [String: String]) -> String {
        for key in regionEnvironmentKeys {
            let raw = clean(env[key])?.lowercased()
            if raw == cn.id { return cn.id }
            if raw == intl.id { return intl.id }
        }
        return intl.id
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        let source = UsageProviderRuntimeConfig.sourceMode(providerID: "qwen", env: env) ?? "auto"
        switch source {
        case "api":
            return try await fetchAPI(env: env, session: session)
        case "web":
            return try await fetchWeb(env: env, session: session)
        case "auto":
            if UsageProviderRuntimeConfig.cookieSource(providerID: "qwen", env: env) == "off" {
                return try await fetchAPI(env: env, session: session)
            }
            do {
                return try await fetchWeb(env: env, session: session)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard token(env: env) != nil else { throw error }
                return try await fetchAPI(env: env, session: session)
            }
        default:
            throw QwenUsageError.unsupportedSource(source)
        }
    }

    private static func fetchAPI(
        env: [String: String],
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        guard let apiKey = token(env: env) else { throw QwenUsageError.missingToken }
        // CodexBar defaults to International and can retry China mainland.
        // An explicit China mainland region stays on that gateway.
        let candidates = region(env: env) == cn.id ? [cn] : [intl, cn]
        var lastError: Error = QwenUsageError.invalidResponse
        for region in candidates {
            do {
                return try await fetchOnce(region: region, env: env, apiKey: apiKey, session: session)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func fetchWeb(
        env: [String: String],
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        let header = try cookieHeader(env: env)
        let candidates = region(env: env) == cn.id ? [cn] : [intl, cn]
        var lastError: Error = QwenUsageError.invalidResponse
        for region in candidates {
            do {
                return try await fetchWebOnce(region: region, env: env, cookieHeader: header, session: session)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    private static func fetchOnce(region: Region, env: [String: String], apiKey: String, session: URLSession) async throws
        -> CodexUsageSnapshot
    {
        let url = try quotaURL(region: region, env: env)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        let body: [String: Any] = ["queryCodingPlanInstanceInfoRequest": ["commodityCode": region.commodity]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiKey, forHTTPHeaderField: "X-DashScope-API-Key")
        request.setValue(region.gateway, forHTTPHeaderField: "Origin")
        request.setValue(region.referer, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QwenUsageError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw QwenUsageError.unauthorized }
        guard http.statusCode == 200 else { throw QwenUsageError.server(http.statusCode) }
        return try parse(data).withSourceLabel("api")
    }

    private static func fetchWebOnce(
        region: Region,
        env: [String: String],
        cookieHeader: String,
        session: URLSession) async throws -> CodexUsageSnapshot
    {
        let secToken = try await resolveSECToken(cookieHeader: cookieHeader, region: region, env: env, session: session)
        let url = try consoleQuotaURL(region: region, env: env)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = consoleRequestBody(region: region, secToken: secToken, cookieHeader: cookieHeader)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let csrf = cookieValue("login_aliyunid_csrf", in: cookieHeader) ?? cookieValue("csrf", in: cookieHeader) {
            request.setValue(csrf, forHTTPHeaderField: "x-xsrf-token")
            request.setValue(csrf, forHTTPHeaderField: "x-csrf-token")
        }
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")
        request.setValue(region.gateway, forHTTPHeaderField: "Origin")
        request.setValue(region.consoleReferer, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QwenUsageError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw QwenUsageError.unauthorized }
        guard http.statusCode == 200 else { throw QwenUsageError.server(http.statusCode) }
        return try parse(data).withSourceLabel("web")
    }

    // MARK: - Endpoint resolution

    static func quotaURL(region: String, env: [String: String]) throws -> URL {
        try quotaURL(region: region == cn.id ? cn : intl, env: env)
    }

    private static func quotaURL(region: Region, env: [String: String]) throws -> URL {
        if let raw = clean(env[quotaURLEnvironmentKey]) {
            guard let override = normalizedHTTPSURL(from: raw),
                  isAllowedEndpoint(override, env: env)
            else {
                throw QwenUsageError.invalidEndpointOverride(quotaURLEnvironmentKey)
            }
            return override
        }
        if let raw = clean(env[hostEnvironmentKey]) {
            guard let override = quotaURL(from: raw, region: region),
                  isAllowedEndpoint(override, env: env)
            else {
                throw QwenUsageError.invalidEndpointOverride(hostEnvironmentKey)
            }
            return override
        }
        return defaultQuotaURL(region: region)
    }

    private static func defaultQuotaURL(region: Region) -> URL {
        quotaURL(from: region.gateway, region: region)!
    }

    private static func consoleQuotaURL(region: Region, env: [String: String]) throws -> URL {
        if let raw = clean(env[quotaURLEnvironmentKey]) {
            guard let override = normalizedHTTPSURL(from: raw),
                  isAllowedEndpoint(override, env: env)
            else {
                throw QwenUsageError.invalidEndpointOverride(quotaURLEnvironmentKey)
            }
            return override
        }
        if let raw = clean(env[hostEnvironmentKey]) {
            guard let override = consoleQuotaURL(from: raw, region: region),
                  isAllowedEndpoint(override, env: env)
            else {
                throw QwenUsageError.invalidEndpointOverride(hostEnvironmentKey)
            }
            return override
        }
        return consoleQuotaURL(from: region.consoleRPCBase, region: region)!
    }

    private static func quotaURL(from rawHost: String, region: Region) -> URL? {
        guard let base = normalizedHTTPSURL(from: rawHost) else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/data/api.json"
        components?.queryItems = [
            URLQueryItem(name: "action", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "product", value: "broadscope-bailian"),
            URLQueryItem(name: "api", value: "queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "currentRegionId", value: region.regionId),
        ]
        return components?.url
    }

    private static func consoleQuotaURL(from rawHost: String, region: Region) -> URL? {
        guard let base = normalizedHTTPSURL(from: rawHost) else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/data/api.json"
        components?.queryItems = [
            URLQueryItem(name: "action", value: region.consoleRPCAction),
            URLQueryItem(name: "product", value: "sfm_bailian"),
            URLQueryItem(name: "api", value: "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2"),
            URLQueryItem(name: "_v", value: "undefined"),
        ]
        return components?.url
    }

    private static func isAllowedEndpoint(_ url: URL, env: [String: String]) -> Bool {
        guard endpointOverridesRequireProviderHost(env: env) else { return true }
        guard let host = url.host?.lowercased() else { return false }
        return allowedEndpointHosts.contains(host)
    }

    private static func endpointOverridesRequireProviderHost(env: [String: String]) -> Bool {
        switch clean(env[requireProviderEndpointOverridesKey])?.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return true
        }
    }

    /// Accepts `https://host[/path]` or a bare host, rejects non-HTTPS, user info and encoded host tricks.
    static func normalizedHTTPSURL(from raw: String) -> URL? {
        let url = hasExplicitURLScheme(raw) ? URL(string: raw) : URL(string: "https://\(raw)")
        guard let url else { return nil }
        guard url.scheme?.lowercased() == "https" else { return nil }
        guard url.user == nil, url.password == nil else { return nil }
        guard let host = url.host?.lowercased(),
              !host.isEmpty,
              !host.contains("%"),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              host.rangeOfCharacter(from: .controlCharacters) == nil
        else { return nil }
        return url
    }

    private static func hasExplicitURLScheme(_ raw: String) -> Bool {
        guard let colonIndex = raw.firstIndex(of: ":") else { return false }
        if raw[colonIndex...].hasPrefix("://") { return true }
        if let authorityEnd = raw.firstIndex(where: { ["/", "?", "#"].contains($0) }),
           colonIndex > authorityEnd
        {
            return false
        }
        let afterColon = raw.index(after: colonIndex)
        guard afterColon < raw.endIndex else { return true }
        let portEnd = raw[afterColon...].firstIndex { Set<Character>(["/", "?", "#"]).contains($0) } ?? raw.endIndex
        let suffix = raw[afterColon..<portEnd]
        if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) { return false }
        let scheme = raw[..<colonIndex]
        guard let first = scheme.first, first.isLetter else { return false }
        return scheme.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || ["+", "-", "."].contains($0) }
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

    // MARK: - Web cookie/session path

    private static func manualCookieHeader(env: [String: String]) -> String? {
        CookieHeaderNormalizer.normalize(env[cookieEnvironmentKey])
            ?? UsageProviderRuntimeConfig.manualCookieHeader(providerID: "qwen", env: env)
    }

    private static func cookieHeader(env: [String: String]) throws -> String {
        if let manual = manualCookieHeader(env: env) {
            return manual
        }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "qwen", env: env) else {
            throw QwenUsageError.missingCookie
        }
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        for browser in Browser.defaultImportOrder {
            guard let cookies = try? BrowserCookieAccessGate.cookies(client: client, matching: query, in: browser), !cookies.isEmpty else { continue }
            guard isAuthenticatedSession(cookies: cookies) else { continue }
            return normalizedCookieHeader(cookies)
        }
        throw QwenUsageError.missingCookie
    }

    private static func isAuthenticatedSession(cookies: [HTTPCookie]) -> Bool {
        let names = Set(cookies.map(\.name))
        let hasTicket = names.contains("login_aliyunid_ticket")
        let hasAccount =
            names.contains("login_aliyunid_pk") ||
            names.contains("login_current_pk") ||
            names.contains("login_aliyunid")
        return hasTicket && hasAccount
    }

    private static func normalizedCookieHeader(_ cookies: [HTTPCookie]) -> String {
        var byName: [String: HTTPCookie] = [:]
        for cookie in cookies {
            if let expiry = cookie.expiresDate, expiry < Date() { continue }
            guard !cookie.value.isEmpty else { continue }
            if let existing = byName[cookie.name] {
                let existingExpiry = existing.expiresDate ?? .distantPast
                let candidateExpiry = cookie.expiresDate ?? .distantPast
                if candidateExpiry >= existingExpiry {
                    byName[cookie.name] = cookie
                }
            } else {
                byName[cookie.name] = cookie
            }
        }
        return byName.keys.sorted().compactMap { name in
            guard let cookie = byName[name] else { return nil }
            return "\(cookie.name)=\(cookie.value)"
        }.joined(separator: "; ")
    }

    private static func resolveSECToken(
        cookieHeader: String,
        region: Region,
        env: [String: String],
        session: URLSession) async throws -> String
    {
        if let token = try? await fetchSECTokenFromDashboard(
            cookieHeader: cookieHeader,
            region: region,
            env: env,
            session: session)
        {
            return token
        }
        if let token = try? await fetchSECTokenFromUserInfo(
            cookieHeader: cookieHeader,
            region: region,
            env: env,
            session: session)
        {
            return token
        }
        if let token = cookieValue("sec_token", in: cookieHeader) {
            return token
        }
        throw QwenUsageError.unauthorized
    }

    private static func fetchSECTokenFromDashboard(
        cookieHeader: String,
        region: Region,
        env: [String: String],
        session: URLSession) async throws -> String?
    {
        let url = dashboardURL(region: region, env: env)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let html = String(data: data, encoding: .utf8) ?? ""
        return extractSECToken(fromHTML: html)
    }

    private static func fetchSECTokenFromUserInfo(
        cookieHeader: String,
        region: Region,
        env: [String: String],
        session: URLSession) async throws -> String?
    {
        let base = gatewayBaseURL(region: region, env: env)
        let url = base.appendingPathComponent("tool/user/info.json")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(
            base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/",
            forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        let object = try JSONSerialization.jsonObject(with: data)
        return findDeepString(["secToken", "sec_token"], in: expand(object))
    }

    private static func dashboardURL(region: Region, env: [String: String]) -> URL {
        guard let raw = clean(env[hostEnvironmentKey]),
              let base = normalizedHTTPSURL(from: raw),
              isAllowedEndpoint(base, env: env),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let defaultComponents = URLComponents(string: region.referer)
        else {
            return URL(string: region.referer)!
        }
        components.path = defaultComponents.path
        components.percentEncodedQuery = defaultComponents.percentEncodedQuery
        components.fragment = defaultComponents.fragment
        return components.url ?? URL(string: region.referer)!
    }

    private static func gatewayBaseURL(region: Region, env: [String: String]) -> URL {
        guard let raw = clean(env[hostEnvironmentKey]),
              let base = normalizedHTTPSURL(from: raw),
              isAllowedEndpoint(base, env: env),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            return URL(string: region.gateway)!
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url ?? URL(string: region.gateway)!
    }

    private static func consoleRequestBody(region: Region, secToken: String, cookieHeader: String) -> Data {
        let traceID = UUID().uuidString.lowercased()
        var cornerstoneParam: [String: Any] = [
            "feTraceId": traceID,
            "feURL": region.referer,
            "protocol": "V2",
            "console": "ONE_CONSOLE",
            "productCode": "p_efm",
            "domain": region.consoleDomain,
            "consoleSite": region.consoleSite,
            "userNickName": "",
            "userPrincipalName": "",
            "xsp_lang": "en-US",
        ]
        if let anonymousID = cookieValue("cna", in: cookieHeader) {
            cornerstoneParam["X-Anonymous-Id"] = anonymousID
        }
        let paramsObject: [String: Any] = [
            "Api": "zeldaEasy.broadscope-bailian.codingPlan.queryCodingPlanInstanceInfoV2",
            "V": "1.0",
            "Data": [
                "queryCodingPlanInstanceInfoRequest": [
                    "commodityCode": region.commodity,
                    "onlyLatestOne": true,
                ],
                "cornerstoneParam": cornerstoneParam,
            ],
        ]
        let paramsData = (try? JSONSerialization.data(withJSONObject: paramsObject)) ?? Data("{}".utf8)
        let paramsString = String(data: paramsData, encoding: .utf8) ?? "{}"
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "params", value: paramsString),
            URLQueryItem(name: "region", value: region.regionId),
            URLQueryItem(name: "sec_token", value: secToken),
        ]
        return Data((components.percentEncodedQuery ?? "").utf8)
    }

    private static func extractSECToken(fromHTML html: String) -> String? {
        let patterns = [
            #"SEC_TOKEN\s*:\s*\"([^\"]+)\""#,
            #"SEC_TOKEN\s*:\s*'([^']+)'"#,
            #"secToken\s*:\s*\"([^\"]+)\""#,
            #"sec_token\s*:\s*\"([^\"]+)\""#,
            #"sec_token\s*:\s*'([^']+)'"#,
            #"\"SEC_TOKEN\"\s*:\s*\"([^\"]+)\""#,
            #"\"sec_token\"\s*:\s*\"([^\"]+)\""#,
        ]
        for pattern in patterns {
            if let token = firstCapture(in: html, pattern: pattern) { return token }
        }
        return nil
    }

    private static func cookieValue(_ name: String, in cookieHeader: String) -> String? {
        for pair in CookieHeaderNormalizer.pairs(from: cookieHeader) where pair.name == name {
            return pair.value.isEmpty ? nil : pair.value
        }
        return nil
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = String(text[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - 解析（递归深搜 + 展开内嵌 JSON）

    static func parse(_ data: Data) throws -> CodexUsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { throw QwenUsageError.invalidResponse }

        // 登录态/区域不支持判定。
        if let dict = root as? [String: Any] {
            let msg = (firstString(["message", "msg", "statusMessage"], dict) ?? "").lowercased()
            let code = (firstString(["code", "status"], dict) ?? "").lowercased()
            if msg.contains("login") || msg.contains("log in") || code.contains("login") || code.contains("unauth") {
                throw QwenUsageError.unauthorized
            }
        }

        guard let quota = findQuotaDict(in: root) else { throw QwenUsageError.invalidResponse }

        func window(used usedKeys: [String], total totalKeys: [String], refresh refreshKeys: [String], fallbackSeconds: Int)
            -> CodexUsageSnapshot.Window?
        {
            guard let total = anyInt(totalKeys, quota), total > 0 else { return nil }
            let used = anyInt(usedKeys, quota) ?? 0
            let pct = max(0, min(100, Int((Double(used) / Double(total) * 100).rounded())))
            let reset = anyDate(refreshKeys, quota) ?? Date().addingTimeInterval(TimeInterval(fallbackSeconds))
            return CodexUsageSnapshot.Window(usedPercent: pct, resetAt: reset, windowSeconds: fallbackSeconds)
        }

        let session = window(
            used: ["per5HourUsedQuota", "perFiveHourUsedQuota"],
            total: ["per5HourTotalQuota", "perFiveHourTotalQuota"],
            refresh: ["per5HourQuotaNextRefreshTime", "perFiveHourQuotaNextRefreshTime"],
            fallbackSeconds: 5 * 3600)
        let weekly = window(
            used: ["perWeekUsedQuota"], total: ["perWeekTotalQuota"],
            refresh: ["perWeekQuotaNextRefreshTime"], fallbackSeconds: 7 * 24 * 3600)
            ?? window(
                used: ["perBillMonthUsedQuota", "perMonthUsedQuota"],
                total: ["perBillMonthTotalQuota", "perMonthTotalQuota"],
                refresh: ["perBillMonthQuotaNextRefreshTime", "perMonthQuotaNextRefreshTime"],
                fallbackSeconds: 30 * 24 * 3600)

        guard session != nil || weekly != nil else { throw QwenUsageError.invalidResponse }
        let plan = firstString(["planName", "plan_name", "packageName", "package_name"], quota)
        return CodexUsageSnapshot(planType: plan, session: session, weekly: weekly)
    }

    /// 递归找到第一个含 5 小时配额字段的对象；遇到能解析成 JSON 的字符串值会展开后继续找。
    private static func findQuotaDict(in any: Any) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            if dict["per5HourTotalQuota"] != nil || dict["perFiveHourTotalQuota"] != nil
                || dict["perWeekTotalQuota"] != nil
            {
                return dict
            }
            for value in dict.values {
                if let found = findQuotaDict(in: expand(value)) { return found }
            }
        } else if let array = any as? [Any] {
            for value in array {
                if let found = findQuotaDict(in: expand(value)) { return found }
            }
        }
        return nil
    }

    /// 内嵌 JSON 字符串 → 解析成对象；否则原样返回。
    private static func expand(_ value: Any) -> Any {
        guard let s = value as? String,
              let first = s.trimmingCharacters(in: .whitespaces).first,
              first == "{" || first == "[",
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
        else { return value }
        return obj
    }

    private static func anyInt(_ keys: [String], _ dict: [String: Any]) -> Int? {
        for k in keys {
            if let i = dict[k] as? Int { return i }
            if let d = dict[k] as? Double { return Int(d) }
            if let s = dict[k] as? String, let i = Int(s) ?? Double(s).map({ Int($0) }) { return i }
        }
        return nil
    }

    private static func firstString(_ keys: [String], _ dict: [String: Any]) -> String? {
        for k in keys {
            if let s = dict[k] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func findDeepString(_ keys: [String], in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let direct = firstString(keys, dict) { return direct }
            for nested in dict.values {
                if let found = findDeepString(keys, in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findDeepString(keys, in: nested) { return found }
            }
        }
        return nil
    }

    /// 刷新时间：可能是 epoch（秒/毫秒）或 ISO8601 字符串。
    private static func anyDate(_ keys: [String], _ dict: [String: Any]) -> Date? {
        for k in keys {
            if let ms = dict[k] as? Int { return epochDate(Double(ms)) }
            if let ms = dict[k] as? Double { return epochDate(ms) }
            if let s = dict[k] as? String {
                if let v = Double(s) { return epochDate(v) }
                let f = ISO8601DateFormatter()
                if let d = f.date(from: s) { return d }
            }
        }
        return nil
    }

    private static func epochDate(_ value: Double) -> Date {
        Date(timeIntervalSince1970: value > 1_000_000_000_000 ? value / 1000 : value)
    }
}
