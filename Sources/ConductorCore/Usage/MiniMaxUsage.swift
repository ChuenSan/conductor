import Foundation
import SweetCookieKit

/// MiniMax（编码套餐）用量取数。摘自 CodexBar `MiniMax` 的 apiToken 与 web/manual-cookie 路径：
/// - `MINIMAX_CODING_API_KEY` / `MINIMAX_API_KEY` 走 `Bearer` 调 API remains 接口。
/// - `MINIMAX_COOKIE` / `MINIMAX_COOKIE_HEADER` / `CONDUCTOR_USAGE_MINIMAX_COOKIE` 走 Coding Plan remains 接口。
/// 解析 `model_remains` 的「当前周期」与「周」剩余百分比。
///
/// 注意：照搬自 CodexBar 源码，但本环境无 key 无法实跑验证，字段映射以其 Decodable 定义为准。
public enum MiniMaxUsageError: LocalizedError, Sendable {
    case missingToken
    case missingSession
    case unauthorized
    case server(Int)
    case invalidResponse
    case invalidEndpointOverride(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken: L("未找到 MiniMax 令牌，请设置 MINIMAX_CODING_API_KEY 或 MINIMAX_API_KEY")
        case .missingSession: L("没有找到 MiniMax 登录态，请设置 MINIMAX_COOKIE 或在设置中粘贴 Cookie")
        case .unauthorized: L("MiniMax 令牌无效或已过期")
        case let .server(c): L("MiniMax 接口错误（%ld）", c)
        case .invalidResponse: L("MiniMax 用量接口返回异常")
        case let .invalidEndpointOverride(key): L("MiniMax 端点覆盖 %@ 必须使用安全的 HTTPS 地址", key)
        case let .network(m): L("网络错误：%@", m)
        }
    }
}

public struct MiniMaxBillingSummary: Codable, Sendable, Equatable {
    public let todayTokens: Int
    public let last30DaysTokens: Int
    public let todayCash: Double?
    public let last30DaysCash: Double?
    public let daily: [MiniMaxBillingDay]
    public let topMethods: [MiniMaxBillingBreakdown]
    public let topModels: [MiniMaxBillingBreakdown]
    public let updatedAt: Date

    public init(
        todayTokens: Int,
        last30DaysTokens: Int,
        todayCash: Double?,
        last30DaysCash: Double?,
        daily: [MiniMaxBillingDay],
        topMethods: [MiniMaxBillingBreakdown],
        topModels: [MiniMaxBillingBreakdown],
        updatedAt: Date)
    {
        self.todayTokens = todayTokens
        self.last30DaysTokens = last30DaysTokens
        self.todayCash = todayCash
        self.last30DaysCash = last30DaysCash
        self.daily = daily
        self.topMethods = topMethods
        self.topModels = topModels
        self.updatedAt = updatedAt
    }
}

public struct MiniMaxBillingDay: Codable, Sendable, Equatable {
    public let day: String
    public let tokens: Int
    public let cash: Double?

    public init(day: String, tokens: Int, cash: Double?) {
        self.day = day
        self.tokens = tokens
        self.cash = cash
    }
}

public struct MiniMaxBillingBreakdown: Codable, Sendable, Equatable {
    public let name: String
    public let tokens: Int
    public let cash: Double?

    public init(name: String, tokens: Int, cash: Double?) {
        self.name = name
        self.tokens = tokens
        self.cash = cash
    }
}

public enum MiniMaxUsageFetcher {
    /// 候选 remains 端点：全球(.io) 先 token_plan 后 coding_plan，失败再试中国(.com)。
    private enum Region: String {
        case global
        case chinaMainland = "cn"
    }

    private static let regionEnvironmentKey = "MINIMAX_REGION"
    private static let hostEnvironmentKey = "MINIMAX_HOST"
    private static let codingPlanURLEnvironmentKey = "MINIMAX_CODING_PLAN_URL"
    private static let remainsURLEnvironmentKey = "MINIMAX_REMAINS_URL"
    private static let billingHistoryURLEnvironmentKey = "MINIMAX_BILLING_HISTORY_URL"
    private static let requireProviderEndpointOverridesKey = "MINIMAX_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"
    private static let globalHost = "https://api.minimax.io"
    private static let chinaHost = "https://api.minimaxi.com"
    private static let webGlobalHost = "https://platform.minimax.io"
    private static let webChinaHost = "https://platform.minimaxi.com"
    private static let apiPaths = ["v1/token_plan/remains", "v1/api/openplatform/coding_plan/remains"]
    private static let codingPlanPath = "user-center/payment/coding-plan"
    private static let webRemainsPath = "v1/api/openplatform/coding_plan/remains"
    private static let billingHistoryPath = "account/amount"
    private static let billingHistoryLimit = 100
    private static let cookieDomains = [
        "platform.minimax.io",
        "openplatform.minimax.io",
        "minimax.io",
        "platform.minimaxi.com",
        "openplatform.minimaxi.com",
        "minimaxi.com",
    ]
    private static let allowedEndpointDomainSuffixes = ["minimax.io", "minimaxi.com"]

    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil
    }

    public static func hasSession(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        cookieHeader(env: env) != nil
    }

    public static func hasCredentials(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        hasToken(env: env) || hasSession(env: env)
    }

    static func token(env: [String: String]) -> String? {
        for key in ["MINIMAX_CODING_API_KEY", "MINIMAX_API_KEY"] {
            if let v = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        }
        return nil
    }

    static func cookieHeader(env: [String: String]) -> String? {
        directCookieOverride(env: env)?.cookieHeader ?? cachedCookieHeader(env: env)?.header
    }

    private static func directCookieOverride(env: [String: String]) -> MiniMaxCookieOverride? {
        for key in ["MINIMAX_COOKIE", "MINIMAX_COOKIE_HEADER"] {
            if let override = MiniMaxCookieHeader.override(from: env[key]) { return override }
        }
        return MiniMaxCookieHeader.override(
            from: UsageProviderRuntimeConfig.manualCookieHeader(providerID: "minimax", env: env))
    }

    private struct ResolvedCookieHeader {
        let header: String
        let sourceLabel: String
        let isCached: Bool
        let shouldCacheOnSuccess: Bool
        let authorizationToken: String?
        let groupID: String?
    }

    private static func cachedCookieHeader(env: [String: String]) -> ResolvedCookieHeader? {
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "minimax", env: env),
              let entry = CookieHeaderCache.load(providerID: "minimax"),
              let override = MiniMaxCookieHeader.override(from: entry.cookieHeader)
        else { return nil }
        return ResolvedCookieHeader(
            header: override.cookieHeader,
            sourceLabel: entry.sourceLabel,
            isCached: true,
            shouldCacheOnSuccess: false,
            authorizationToken: override.authorizationToken,
            groupID: override.groupID)
    }

    private static func resolvedCookieHeaders(env: [String: String]) -> [ResolvedCookieHeader] {
        if let direct = directCookieOverride(env: env) {
            return [ResolvedCookieHeader(
                header: direct.cookieHeader,
                sourceLabel: "Manual",
                isCached: false,
                shouldCacheOnSuccess: false,
                authorizationToken: direct.authorizationToken,
                groupID: direct.groupID)]
        }

        var candidates: [ResolvedCookieHeader] = []
        if let cached = cachedCookieHeader(env: env) {
            candidates.append(cached)
        }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "minimax", env: env) else {
            return candidates
        }
        candidates.append(contentsOf: browserCookieHeaders())
        return candidates
    }

    private static func browserCookieHeaders() -> [ResolvedCookieHeader] {
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        var candidates: [ResolvedCookieHeader] = []
        for browser in Browser.defaultImportOrder {
            guard BrowserCookieAccessGate.shouldAttempt(browser) else { continue }
            let cookies: [HTTPCookie]
            do {
                cookies = try BrowserCookieAccessGate.cookies(client: client, matching: query, in: browser)
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                continue
            }
            guard !cookies.isEmpty else { continue }
            let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            guard let override = MiniMaxCookieHeader.override(from: header) else { continue }
            candidates.append(ResolvedCookieHeader(
                header: override.cookieHeader,
                sourceLabel: browser.displayName,
                isCached: false,
                shouldCacheOnSuccess: true,
                authorizationToken: override.authorizationToken,
                groupID: override.groupID))
        }
        return candidates
    }

    static func region(env: [String: String]) -> String {
        let raw = clean(env[regionEnvironmentKey])?.lowercased()
        return raw == Region.chinaMainland.rawValue ? Region.chinaMainland.rawValue : Region.global.rawValue
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        switch UsageProviderRuntimeConfig.sourceMode(providerID: "minimax", env: env) {
        case "web":
            return try await fetchWeb(env: env, session: session)
        case "api":
            return try await fetchAPI(env: env, session: session)
        default:
            return try await fetchAuto(env: env, session: session)
        }
    }

    private static func fetchAuto(env: [String: String], session: URLSession) async throws -> UsageSnapshot {
        let apiKey = token(env: env)
        let canUseWeb = canUseWebSession(env: env)
        if apiKeyKind(apiKey) == .standard, canUseWeb {
            return try await fetchWeb(env: env, session: session)
        }
        if apiKey != nil {
            do {
                return try await fetchAPI(env: env, session: session)
            } catch let error as MiniMaxUsageError {
                guard canUseWeb, shouldFallbackToWeb(after: error) else { throw error }
                return try await fetchWeb(env: env, session: session)
            }
        }
        if canUseWeb {
            return try await fetchWeb(env: env, session: session)
        }
        throw MiniMaxUsageError.missingToken
    }

    private static func fetchAPI(env: [String: String], session: URLSession) async throws -> UsageSnapshot {
        guard let apiKey = token(env: env) else { throw MiniMaxUsageError.missingToken }
        var lastError: Error = MiniMaxUsageError.invalidResponse
        for url in try apiRemainsURLs(env: env) {
            do {
                return try await fetchAPIOnce(url: url, apiKey: apiKey, session: session)
            } catch let e as MiniMaxUsageError {
                lastError = e
                if case .unauthorized = e { continue } // 换下一个端点/区域
                continue
            } catch {
                lastError = MiniMaxUsageError.network(error.localizedDescription)
                continue
            }
        }
        throw lastError
    }

    private static func fetchWeb(env: [String: String], session: URLSession) async throws -> UsageSnapshot {
        let cookieCandidates = resolvedCookieHeaders(env: env)
        guard !cookieCandidates.isEmpty else { throw MiniMaxUsageError.missingSession }
        let referer = try codingPlanRefererURL(env: env)
        let tokenContext = loadTokenContext(env: env)
        var lastError: Error = MiniMaxUsageError.invalidResponse
        for cookie in cookieCandidates {
            var lastCookieError: MiniMaxUsageError?
            for url in try webRemainsURLs(env: env) {
                for attempt in credentialAttempts(for: cookie, tokenContext: tokenContext) {
                    do {
                        let snapshot = try await fetchWebOnce(
                            url: appendGroupID(attempt.groupID, to: url),
                            cookieHeader: cookie.header,
                            authorizationToken: attempt.authorizationToken,
                            referer: referer,
                            session: session)
                        let enriched = try await attachingBillingIfAvailable(
                            to: snapshot,
                            cookieHeader: cookie.header,
                            authorizationToken: attempt.authorizationToken,
                            env: env,
                            session: session)
                        if cookie.shouldCacheOnSuccess {
                            CookieHeaderCache.store(
                                providerID: "minimax",
                                cookieHeader: cookie.header,
                                sourceLabel: cookie.sourceLabel)
                        }
                        return enriched
                    } catch let e as MiniMaxUsageError {
                        lastError = e
                        lastCookieError = e
                        if attempt.authorizationToken != nil, shouldTryNextWebCredential(after: e) {
                            continue
                        }
                        if cookie.isCached, case .unauthorized = e {
                            CookieHeaderCache.clear(providerID: "minimax")
                            break
                        }
                        if shouldTryNextWebEndpoint(after: e) { break }
                        if case .unauthorized = e { break }
                        throw e
                    } catch {
                        lastError = MiniMaxUsageError.network(error.localizedDescription)
                        break
                    }
                }
            }
            if cookie.isCached, case .some(.unauthorized) = lastCookieError {
                CookieHeaderCache.clear(providerID: "minimax")
            }
        }
        throw lastError
    }

    private static func canUseWebSession(env: [String: String]) -> Bool {
        cookieHeader(env: env) != nil || UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "minimax", env: env)
    }

    private enum APIKeyKind {
        case codingPlan
        case standard
        case unknown
    }

    private static func apiKeyKind(_ raw: String?) -> APIKeyKind {
        guard let value = clean(raw) else { return .unknown }
        if value.hasPrefix("sk-cp-") { return .codingPlan }
        if value.hasPrefix("sk-api-") { return .standard }
        return .unknown
    }

    private static func shouldFallbackToWeb(after error: MiniMaxUsageError) -> Bool {
        switch error {
        case .unauthorized, .invalidResponse:
            true
        case let .server(code):
            code == 404 || code == 405
        case .missingToken, .missingSession, .invalidEndpointOverride, .network:
            false
        }
    }

    private static func shouldTryNextWebEndpoint(after error: MiniMaxUsageError) -> Bool {
        switch error {
        case .unauthorized:
            false
        case .server, .invalidResponse, .network:
            true
        case .missingToken, .missingSession, .invalidEndpointOverride:
            false
        }
    }

    private static func shouldTryNextWebCredential(after error: MiniMaxUsageError) -> Bool {
        switch error {
        case .unauthorized, .invalidResponse:
            true
        case .server, .missingToken, .missingSession, .invalidEndpointOverride, .network:
            false
        }
    }

    private struct TokenContext {
        let tokensByLabel: [String: [String]]
        let groupIDByLabel: [String: String]
    }

    private struct WebCredentialAttempt {
        let authorizationToken: String?
        let groupID: String?
    }

    private static func loadTokenContext(env: [String: String]) -> TokenContext {
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "minimax", env: env) else {
            return TokenContext(tokensByLabel: [:], groupIDByLabel: [:])
        }
        #if os(macOS)
        let tokens = MiniMaxLocalStorageImporter.importAccessTokens()
        let groupIDs = MiniMaxLocalStorageImporter.importGroupIDs()
        var tokensByLabel: [String: [String]] = [:]
        var groupIDByLabel: [String: String] = [:]
        for token in tokens {
            let label = normalizeStorageLabel(token.sourceLabel)
            tokensByLabel[label, default: []].append(token.accessToken)
            if let groupID = token.groupID, groupIDByLabel[label] == nil {
                groupIDByLabel[label] = groupID
            }
        }
        for (label, groupID) in groupIDs where groupIDByLabel[normalizeStorageLabel(label)] == nil {
            groupIDByLabel[normalizeStorageLabel(label)] = groupID
        }
        return TokenContext(tokensByLabel: tokensByLabel, groupIDByLabel: groupIDByLabel)
        #else
        return TokenContext(tokensByLabel: [:], groupIDByLabel: [:])
        #endif
    }

    private static func credentialAttempts(
        for cookie: ResolvedCookieHeader,
        tokenContext: TokenContext) -> [WebCredentialAttempt]
    {
        let label = normalizeStorageLabel(cookie.sourceLabel)
        let groupID = cookie.groupID ?? tokenContext.groupIDByLabel[label]
        let cookieToken = cookieValue(named: "HERTZ-SESSION", in: cookie.header)
        var tokenCandidates: [String] = []

        func appendToken(_ token: String?) {
            guard let token = clean(token), !tokenCandidates.contains(token) else { return }
            tokenCandidates.append(token)
        }

        appendToken(cookie.authorizationToken)
        for token in tokenContext.tokensByLabel[label] ?? [] {
            appendToken(token)
        }
        appendToken(cookieToken)

        return tokenCandidates.map { WebCredentialAttempt(authorizationToken: $0, groupID: groupID) } +
            [WebCredentialAttempt(authorizationToken: nil, groupID: groupID)]
    }

    private static func normalizeStorageLabel(_ label: String) -> String {
        for suffix in [" (Session Storage)", " (IndexedDB)"] where label.hasSuffix(suffix) {
            return String(label.dropLast(suffix.count))
        }
        return label
    }

    private static func cookieValue(named name: String, in header: String) -> String? {
        for pair in CookieHeaderNormalizer.pairs(from: header)
            where pair.name.caseInsensitiveCompare(name) == .orderedSame
        {
            return pair.value
        }
        return nil
    }

    // MARK: - Endpoint resolution

    static func apiRemainsURLs(env: [String: String]) throws -> [URL] {
        if let raw = clean(env[remainsURLEnvironmentKey]) {
            guard let override = normalizedHTTPSURL(from: raw),
                  isAllowedEndpointOverride(override, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(remainsURLEnvironmentKey)
            }
            return [override]
        }
        if let raw = clean(env[hostEnvironmentKey]) {
            let urls = apiPaths.compactMap { endpointURL(from: raw, path: $0) }
            guard !urls.isEmpty,
                  urls.allSatisfy({ isAllowedEndpointOverride($0, env: env) })
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(hostEnvironmentKey)
            }
            return deduplicated(urls)
        }
        let hosts = switch region(env: env) {
        case Region.chinaMainland.rawValue:
            [chinaHost]
        default:
            [globalHost, chinaHost]
        }
        return hosts.flatMap { host in
            apiPaths.compactMap { URL(string: "\(host)/\($0)") }
        }
    }

    static func webRemainsURLs(env: [String: String]) throws -> [URL] {
        if let raw = clean(env[remainsURLEnvironmentKey]) {
            guard let override = normalizedHTTPSURL(from: raw),
                  isAllowedEndpointOverride(override, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(remainsURLEnvironmentKey)
            }
            return [override]
        }
        if let raw = clean(env[hostEnvironmentKey]) {
            guard let url = endpointURL(from: raw, path: webRemainsPath),
                  isAllowedEndpointOverride(url, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(hostEnvironmentKey)
            }
            return [url]
        }
        let primaryHost = region(env: env) == Region.chinaMainland.rawValue ? webChinaHost : webGlobalHost
        let fallbackHost = region(env: env) == Region.chinaMainland.rawValue ? "https://www.minimaxi.com" : "https://www.minimax.io"
        return deduplicated([primaryHost, fallbackHost].compactMap { endpointURL(from: $0, path: webRemainsPath) })
    }

    static func codingPlanRefererURL(env: [String: String]) throws -> URL {
        if let raw = clean(env[codingPlanURLEnvironmentKey]) {
            guard let url = normalizedHTTPSURL(from: raw),
                  isAllowedEndpointOverride(url, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(codingPlanURLEnvironmentKey)
            }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            return components?.url ?? url
        }
        if let raw = clean(env[hostEnvironmentKey]) {
            guard let url = endpointURL(from: raw, path: codingPlanPath),
                  isAllowedEndpointOverride(url, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(hostEnvironmentKey)
            }
            return url
        }
        let host = region(env: env) == Region.chinaMainland.rawValue ? webChinaHost : webGlobalHost
        return endpointURL(from: host, path: codingPlanPath)!
    }

    static func billingHistoryURL(env: [String: String], page: Int, limit: Int = billingHistoryLimit) throws -> URL {
        if let raw = clean(env[billingHistoryURLEnvironmentKey]) {
            guard let override = normalizedHTTPSURL(from: raw),
                  isAllowedEndpointOverride(override, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(billingHistoryURLEnvironmentKey)
            }
            return billingHistoryURL(from: override, page: page, limit: limit)
        }
        if let raw = clean(env[hostEnvironmentKey]) {
            guard let url = endpointURL(from: raw, path: billingHistoryPath),
                  isAllowedEndpointOverride(url, env: env)
            else {
                throw MiniMaxUsageError.invalidEndpointOverride(hostEnvironmentKey)
            }
            return billingHistoryURL(from: url, page: page, limit: limit)
        }
        let host = region(env: env) == Region.chinaMainland.rawValue ? webChinaHost : webGlobalHost
        return billingHistoryURL(from: endpointURL(from: host, path: billingHistoryPath)!, page: page, limit: limit)
    }

    private static func billingHistoryURL(from url: URL, page: Int, limit: Int) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems?.filter {
            $0.name != "page" && $0.name != "limit" && $0.name != "aggregate"
        } ?? []
        items.append(URLQueryItem(name: "page", value: "\(page)"))
        items.append(URLQueryItem(name: "limit", value: "\(limit)"))
        items.append(URLQueryItem(name: "aggregate", value: "false"))
        components.queryItems = items
        return components.url ?? url
    }

    private static func appendGroupID(_ groupID: String?, to url: URL) -> URL {
        guard let groupID = clean(groupID),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "GroupId", value: groupID))
        components.queryItems = items
        return components.url ?? url
    }

    private static func endpointURL(from rawHost: String, path: String) -> URL? {
        guard let base = normalizedHTTPSURL(from: rawHost),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path = "/" + path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func isAllowedEndpointOverride(_ url: URL, env: [String: String]) -> Bool {
        guard endpointOverridesRequireProviderHost(env: env) else { return true }
        guard let host = url.host?.lowercased() else { return false }
        return allowedEndpointDomainSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
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
              host.rangeOfCharacter(from: .controlCharacters) == nil,
              hostHasNoEncodedDelimiters(in: url.absoluteString, decodedHost: host)
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

    private static func hostHasNoEncodedDelimiters(in urlString: String, decodedHost: String) -> Bool {
        let delimiters = CharacterSet(charactersIn: "/\\?#@:")
        guard decodedHost.rangeOfCharacter(from: delimiters) == nil else { return false }
        guard let encodedHost = encodedHost(from: urlString)?.lowercased() else { return false }
        let encodedDelimiters = ["%2f", "%5c", "%3f", "%23", "%40", "%3a"]
        return !encodedDelimiters.contains { encodedHost.contains($0) }
    }

    private static func encodedHost(from urlString: String) -> String? {
        guard let schemeRange = urlString.range(of: "://") else { return nil }
        let start = schemeRange.upperBound
        let end = urlString[start...].firstIndex { ["/", "?", "#"].contains($0) } ?? urlString.endIndex
        var authority = String(urlString[start..<end])
        if let at = authority.lastIndex(of: "@") {
            authority = String(authority[authority.index(after: at)...])
        }
        if authority.hasPrefix("["),
           let close = authority.firstIndex(of: "]")
        {
            return String(authority[authority.index(after: authority.startIndex)..<close])
        }
        if let colon = authority.lastIndex(of: ":") {
            let suffix = authority[authority.index(after: colon)...]
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                authority = String(authority[..<colon])
            }
        }
        return authority.isEmpty ? nil : authority
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let key = url.absoluteString
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(url)
        }
        return result
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

    private static func fetchAPIOnce(url: URL, apiKey: String, session: URLSession) async throws -> UsageSnapshot {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Conductor", forHTTPHeaderField: "MM-API-Source")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MiniMaxUsageError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MiniMaxUsageError.unauthorized }
        guard http.statusCode == 200 else { throw MiniMaxUsageError.server(http.statusCode) }
        return try parse(data).withSourceLabel("api")
    }

    private static func fetchWebOnce(
        url: URL,
        cookieHeader: String,
        authorizationToken: String?,
        referer: URL,
        session: URLSession) async throws -> UsageSnapshot
    {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "user-agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        request.setValue(originURL(from: url).absoluteString, forHTTPHeaderField: "origin")
        request.setValue(referer.absoluteString, forHTTPHeaderField: "referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MiniMaxUsageError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MiniMaxUsageError.unauthorized }
        guard http.statusCode == 200 else { throw MiniMaxUsageError.server(http.statusCode) }
        if let body = String(data: data, encoding: .utf8),
           body.lowercased().contains("login") || body.contains("登录")
        {
            throw MiniMaxUsageError.unauthorized
        }
        return try parse(data).withSourceLabel("web")
    }

    private static func attachingBillingIfAvailable(
        to snapshot: UsageSnapshot,
        cookieHeader: String,
        authorizationToken: String?,
        env: [String: String],
        session: URLSession) async throws -> UsageSnapshot
    {
        do {
            let billing = try await fetchBillingSummary(
                cookieHeader: cookieHeader,
                authorizationToken: authorizationToken,
                env: env,
                session: session)
            return snapshot.withMiniMaxBillingSummary(billing)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            return snapshot
        }
    }

    private static func fetchBillingSummary(
        cookieHeader: String,
        authorizationToken: String?,
        env: [String: String],
        session: URLSession) async throws -> MiniMaxBillingSummary
    {
        var records: [MiniMaxBillingRecord] = []
        var totalCount: Int?
        var page = 1

        while true {
            let url = try billingHistoryURL(env: env, page: page, limit: billingHistoryLimit)
            let payload = try await fetchBillingHistoryPage(
                url: url,
                cookieHeader: cookieHeader,
                authorizationToken: authorizationToken,
                session: session)

            if let status = payload.baseResp?.statusCode, status != 0 {
                if status == 1004 {
                    throw MiniMaxUsageError.unauthorized
                }
                throw MiniMaxUsageError.server(status)
            }
            totalCount = payload.totalCount ?? totalCount
            guard !payload.chargeRecords.isEmpty else { break }
            records.append(contentsOf: payload.chargeRecords)
            if containsBillingRecordBefore30DayWindow(payload.chargeRecords) { break }
            if let totalCount, records.count >= totalCount { break }
            page += 1
        }

        return aggregateBillingRecords(records)
    }

    private static func fetchBillingHistoryPage(
        url: URL,
        cookieHeader: String,
        authorizationToken: String?,
        session: URLSession) async throws -> MiniMaxBillingHistoryPayload
    {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        if let authorizationToken {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "x-requested-with")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "user-agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        let origin = originURL(from: url)
        request.setValue(origin.absoluteString, forHTTPHeaderField: "origin")
        request.setValue(origin.appendingPathComponent("account").absoluteString, forHTTPHeaderField: "referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MiniMaxUsageError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw MiniMaxUsageError.unauthorized }
        guard http.statusCode == 200 else { throw MiniMaxUsageError.server(http.statusCode) }
        return try JSONDecoder().decode(MiniMaxBillingHistoryPayload.self, from: data)
    }

    private static func originURL(from url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        return components.url ?? URL(string: "https://platform.minimax.io")!
    }

    // MARK: - 解析

    private struct Payload: Decodable {
        let baseResp: BaseResp?
        let data: PlanData?
        enum CodingKeys: String, CodingKey { case baseResp = "base_resp", data }
    }

    private struct PlanData: Decodable {
        let baseResp: BaseResp?
        let planName: String?
        let subscribeTitle: String?
        let modelRemains: [ModelRemains]?
        /// 积分/点数余额，对应 CodexBar 的 pointsBalance（多键兜底）。
        let pointsBalance: Double?
        enum CodingKeys: String, CodingKey {
            case baseResp = "base_resp"
            case planName = "plan_name"
            case subscribeTitle = "current_subscribe_title"
            case modelRemains = "model_remains"
            case pointsBalance = "points_balance"
            case pointBalance = "point_balance"
            case creditsBalance = "credits_balance"
            case creditBalance = "credit_balance"
            case balance
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.baseResp = try c.decodeIfPresent(BaseResp.self, forKey: .baseResp)
            self.planName = try c.decodeIfPresent(String.self, forKey: .planName)
            self.subscribeTitle = try c.decodeIfPresent(String.self, forKey: .subscribeTitle)
            self.modelRemains = try c.decodeIfPresent([ModelRemains].self, forKey: .modelRemains)
            self.pointsBalance = PlanData.decodeDouble(c, forKeys: [
                .pointsBalance, .pointBalance, .creditsBalance, .creditBalance, .balance,
            ])
        }

        /// 数值可能以 Double / Int / Int64 / String 形式出现，逐键、逐类型兜底。
        private static func decodeDouble(
            _ container: KeyedDecodingContainer<CodingKeys>,
            forKeys keys: [CodingKeys]) -> Double?
        {
            for key in keys {
                if let v = try? container.decodeIfPresent(Double.self, forKey: key) { return v }
                if let v = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(v) }
                if let v = try? container.decodeIfPresent(Int64.self, forKey: key) { return Double(v) }
                if let v = try? container.decodeIfPresent(String.self, forKey: key),
                   let d = Double(v.trimmingCharacters(in: .whitespacesAndNewlines)) { return d }
            }
            return nil
        }
    }

    private struct BaseResp: Decodable {
        let statusCode: Int?
        let statusMsg: String?
        enum CodingKeys: String, CodingKey { case statusCode = "status_code", statusMsg = "status_msg" }
    }

    private struct ModelRemains: Decodable {
        let intervalRemainingPercent: Double?
        let endTime: Int?
        let remainsTime: Int?
        let weeklyRemainingPercent: Double?
        let weeklyEndTime: Int?
        let weeklyRemainsTime: Int?
        enum CodingKeys: String, CodingKey {
            case intervalRemainingPercent = "current_interval_remaining_percent"
            case endTime = "end_time"
            case remainsTime = "remains_time"
            case weeklyRemainingPercent = "current_weekly_remaining_percent"
            case weeklyEndTime = "weekly_end_time"
            case weeklyRemainsTime = "weekly_remains_time"
        }
    }

    private struct MiniMaxBillingHistoryPayload: Decodable {
        let baseResp: BaseResp?
        let chargeRecords: [MiniMaxBillingRecord]
        let totalCount: Int?

        enum CodingKeys: String, CodingKey {
            case baseResp = "base_resp"
            case chargeRecords = "charge_records"
            case totalCount = "total_cnt"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.baseResp = try c.decodeIfPresent(BaseResp.self, forKey: .baseResp)
            self.chargeRecords = try c.decodeIfPresent([MiniMaxBillingRecord].self, forKey: .chargeRecords) ?? []
            self.totalCount = MiniMaxUsageFetcher.decodeInt(c, forKey: .totalCount)
        }
    }

    private struct MiniMaxBillingRecord: Decodable {
        let consumeToken: Int?
        let consumeInputToken: Int?
        let consumeOutputToken: Int?
        let consumeCash: Double?
        let consumeCashAfterVoucher: Double?
        let createdAt: Int?
        let ymd: String?
        let consumeTime: String?
        let method: String?
        let model: String?
        let result: String?
        let status: String?

        enum CodingKeys: String, CodingKey {
            case consumeToken = "consume_token"
            case consumeInputToken = "consume_input_token"
            case consumeOutputToken = "consume_output_token"
            case consumeCash = "consume_cash"
            case consumeCashAfterVoucher = "consume_cash_after_voucher"
            case createdAt = "created_at"
            case ymd
            case consumeTime = "consume_time"
            case method
            case model
            case result
            case status
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.consumeToken = MiniMaxUsageFetcher.decodeInt(c, forKey: .consumeToken)
            self.consumeInputToken = MiniMaxUsageFetcher.decodeInt(c, forKey: .consumeInputToken)
            self.consumeOutputToken = MiniMaxUsageFetcher.decodeInt(c, forKey: .consumeOutputToken)
            self.consumeCash = MiniMaxUsageFetcher.decodeDouble(c, forKey: .consumeCash)
            self.consumeCashAfterVoucher = MiniMaxUsageFetcher.decodeDouble(c, forKey: .consumeCashAfterVoucher)
            self.createdAt = MiniMaxUsageFetcher.decodeInt(c, forKey: .createdAt)
            self.ymd = try c.decodeIfPresent(String.self, forKey: .ymd)
            self.consumeTime = try c.decodeIfPresent(String.self, forKey: .consumeTime)
            self.method = try c.decodeIfPresent(String.self, forKey: .method)
            self.model = try c.decodeIfPresent(String.self, forKey: .model)
            self.result = MiniMaxUsageFetcher.decodeScalarString(c, forKey: .result)
            self.status = MiniMaxUsageFetcher.decodeScalarString(c, forKey: .status)
        }

        var recordResult: String? {
            if let result = MiniMaxUsageFetcher.clean(result) { return result }
            if let status = MiniMaxUsageFetcher.clean(status) { return status }
            return nil
        }

        var tokenCount: Int {
            if let consumeToken, consumeToken > 0 { return consumeToken }
            return max(0, (consumeInputToken ?? 0) + (consumeOutputToken ?? 0))
        }

        var cashValue: Double? {
            consumeCashAfterVoucher ?? consumeCash
        }
    }

    static func parseBillingHistory(
        _ data: Data,
        now: Date = Date(),
        calendar: Calendar = .current) throws -> MiniMaxBillingSummary
    {
        let payload = try JSONDecoder().decode(MiniMaxBillingHistoryPayload.self, from: data)
        if let status = payload.baseResp?.statusCode, status != 0 {
            if status == 1004 {
                throw MiniMaxUsageError.unauthorized
            }
            throw MiniMaxUsageError.server(status)
        }
        return aggregateBillingRecords(payload.chargeRecords, now: now, calendar: calendar)
    }

    private static func aggregateBillingRecords(
        _ records: [MiniMaxBillingRecord],
        now: Date = Date(),
        calendar inputCalendar: Calendar = .current) -> MiniMaxBillingSummary
    {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone

        let startOfToday = calendar.startOfDay(for: now)
        let startOf30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        var daily: [String: (date: Date, tokens: Int, cash: Double, hasCash: Bool)] = [:]
        var methodTotals: [String: (tokens: Int, cash: Double, hasCash: Bool)] = [:]
        var modelTotals: [String: (tokens: Int, cash: Double, hasCash: Bool)] = [:]

        for record in records {
            if let result = record.recordResult,
               result.caseInsensitiveCompare("SUCCESS") != .orderedSame
            {
                continue
            }
            guard let date = billingRecordDate(record, calendar: calendar),
                  date >= startOf30Days,
                  date <= now
            else {
                continue
            }

            let day = dayString(date, calendar: calendar)
            let tokens = record.tokenCount
            let cash = record.cashValue
            var bucket = daily[day] ?? (calendar.startOfDay(for: date), 0, 0, false)
            bucket.tokens += tokens
            if let cash {
                bucket.cash += cash
                bucket.hasCash = true
            }
            daily[day] = bucket
            addBillingBreakdown(record.method, tokens: tokens, cash: cash, totals: &methodTotals)
            addBillingBreakdown(record.model, tokens: tokens, cash: cash, totals: &modelTotals)
        }

        let sortedDays = daily
            .sorted { $0.value.date < $1.value.date }
            .map { key, value in
                MiniMaxBillingDay(
                    day: key,
                    tokens: value.tokens,
                    cash: value.hasCash ? value.cash : nil)
            }
        let today = daily[dayString(now, calendar: calendar)]
        let last30CashValues = sortedDays.compactMap(\.cash)
        let last30Cash = last30CashValues.isEmpty ? nil : last30CashValues.reduce(0, +)

        return MiniMaxBillingSummary(
            todayTokens: today?.tokens ?? 0,
            last30DaysTokens: sortedDays.reduce(0) { $0 + $1.tokens },
            todayCash: (today?.hasCash == true) ? today?.cash : nil,
            last30DaysCash: last30Cash,
            daily: sortedDays,
            topMethods: billingBreakdowns(from: methodTotals),
            topModels: billingBreakdowns(from: modelTotals),
            updatedAt: now)
    }

    private static func addBillingBreakdown(
        _ rawName: String?,
        tokens: Int,
        cash: Double?,
        totals: inout [String: (tokens: Int, cash: Double, hasCash: Bool)])
    {
        guard let name = clean(rawName) else { return }
        var total = totals[name] ?? (0, 0, false)
        total.tokens += tokens
        if let cash {
            total.cash += cash
            total.hasCash = true
        }
        totals[name] = total
    }

    private static func billingBreakdowns(
        from totals: [String: (tokens: Int, cash: Double, hasCash: Bool)])
        -> [MiniMaxBillingBreakdown]
    {
        totals
            .map { name, value in
                MiniMaxBillingBreakdown(
                    name: name,
                    tokens: value.tokens,
                    cash: value.hasCash ? value.cash : nil)
            }
            .sorted {
                if $0.tokens == $1.tokens {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.tokens > $1.tokens
            }
            .prefix(3)
            .map(\.self)
    }

    private static func containsBillingRecordBefore30DayWindow(
        _ records: [MiniMaxBillingRecord],
        now: Date = Date(),
        calendar inputCalendar: Calendar = .current) -> Bool
    {
        var calendar = inputCalendar
        calendar.timeZone = inputCalendar.timeZone
        let startOfToday = calendar.startOfDay(for: now)
        let startOf30Days = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
        return records.contains { record in
            guard let date = billingRecordDate(record, calendar: calendar) else { return false }
            return date < startOf30Days
        }
    }

    private static func billingRecordDate(_ record: MiniMaxBillingRecord, calendar: Calendar) -> Date? {
        if let createdAt = record.createdAt {
            let seconds = createdAt > 1_000_000_000_000 ? Double(createdAt) / 1000 : Double(createdAt)
            return Date(timeIntervalSince1970: seconds)
        }
        if let ymd = record.ymd {
            return parseDateOnly(ymd, calendar: calendar)
        }
        if let consumeTime = record.consumeTime {
            return parseDate(consumeTime, formats: [
                "yyyy-MM-dd HH:mm:ss",
                "yyyy/MM/dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            ])
        }
        return nil
    }

    private static func parseDateOnly(_ text: String, calendar: Calendar) -> Date? {
        guard let value = clean(text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd", "yyyyMMdd", "yyyy/MM/dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    private static func parseDate(_ text: String, formats: [String]) -> Date? {
        guard let value = clean(text) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func decodeInt<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key),
           let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return Int(double)
        }
        return nil
    }

    private static func decodeDouble<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K) -> Double?
    {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) { return Double(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key),
           let double = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return double
        }
        return nil
    }

    private static func decodeScalarString<K: CodingKey>(
        _ container: KeyedDecodingContainer<K>,
        forKey key: K) -> String?
    {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    static func parse(_ data: Data) throws -> UsageSnapshot {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let base = payload.data?.baseResp ?? payload.baseResp
        if let status = base?.statusCode, status != 0 {
            let msg = (base?.statusMsg ?? "").lowercased()
            if status == 1004 || msg.contains("login") || msg.contains("log in") || msg.contains("cookie") {
                throw MiniMaxUsageError.unauthorized
            }
            throw MiniMaxUsageError.server(status)
        }
        guard let models = payload.data?.modelRemains, !models.isEmpty else {
            throw MiniMaxUsageError.invalidResponse
        }

        // 取「当前周期剩余最低」的车道作为会话窗，并用它的周窗。
        let lane = models.min { ($0.intervalRemainingPercent ?? 100) < ($1.intervalRemainingPercent ?? 100) }
            ?? models[0]

        func used(_ remainingPercent: Double?) -> Double? {
            guard let r = remainingPercent else { return nil }
            return max(0, min(100, 100 - r))
        }
        func resetAt(end: Int?, remains: Int?, fallbackSeconds: Int) -> Date {
            if let end, end > 0 { return dateFromUnix(end) }
            if let remains, remains > 0 { return Date().addingTimeInterval(TimeInterval(remains)) }
            return Date().addingTimeInterval(TimeInterval(fallbackSeconds))
        }

        // session → primary、weekly → secondary。
        var primary: RateWindow?
        if let u = used(lane.intervalRemainingPercent) {
            primary = RateWindow(
                title: L("会话"),
                usedPercent: u,
                windowMinutes: 5 * 60,
                resetsAt: resetAt(end: lane.endTime, remains: lane.remainsTime, fallbackSeconds: 5 * 3600))
        }
        var secondary: RateWindow?
        if let u = used(lane.weeklyRemainingPercent) {
            secondary = RateWindow(
                title: L("本周"),
                usedPercent: u,
                windowMinutes: 7 * 24 * 60,
                resetsAt: resetAt(end: lane.weeklyEndTime, remains: lane.weeklyRemainsTime, fallbackSeconds: 7 * 24 * 3600))
        }
        guard primary != nil || secondary != nil else { throw MiniMaxUsageError.invalidResponse }

        // MiniMax 是积分/points 余额，无上限 → providerCost。对应 CodexBar pointsBalanceSnapshot()。
        var providerCost: ProviderCostSnapshot?
        if let balance = payload.data?.pointsBalance, balance >= 0 {
            providerCost = ProviderCostSnapshot(
                used: balance,
                limit: 0,
                currencyCode: "Points",
                period: "MiniMax points balance")
        }

        let plan = payload.data?.subscribeTitle ?? payload.data?.planName
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            providerCost: providerCost,
            planName: plan)
    }

    /// 时间戳可能是秒或毫秒。
    private static func dateFromUnix(_ value: Int) -> Date {
        let secs = value > 1_000_000_000_000 ? Double(value) / 1000 : Double(value)
        return Date(timeIntervalSince1970: secs)
    }
}

private extension UsageSnapshot {
    func withMiniMaxBillingSummary(_ billing: MiniMaxBillingSummary) -> UsageSnapshot {
        var extras = extraRateWindows
        let totalTokens = billing.last30DaysTokens
        let totalCash = billing.last30DaysCash

        func percent(tokens: Int, cash: Double?) -> Double {
            if totalTokens > 0 {
                return max(0, min(100, Double(tokens) / Double(totalTokens) * 100))
            }
            if let cash, let totalCash, totalCash > 0 {
                return max(0, min(100, cash / totalCash * 100))
            }
            return (tokens > 0 || cash != nil) ? 100 : 0
        }

        func appendSummary(id: String, title: String, tokens: Int, cash: Double?) {
            guard tokens > 0 || cash != nil else { return }
            extras.append(NamedRateWindow(
                id: id,
                title: Self.billingTitle(title, tokens: tokens, cash: cash),
                window: RateWindow(
                    title: title,
                    usedPercent: percent(tokens: tokens, cash: cash),
                    windowMinutes: nil,
                    resetsAt: nil)))
        }

        appendSummary(
            id: "minimax.billing.today",
            title: L("今日"),
            tokens: billing.todayTokens,
            cash: billing.todayCash)
        appendSummary(
            id: "minimax.billing.30d",
            title: L("过去 30 天"),
            tokens: billing.last30DaysTokens,
            cash: billing.last30DaysCash)

        for item in billing.topModels {
            let title = L("模型：%@", item.name)
            appendSummary(
                id: "minimax.billing.model.\(Self.stableID(item.name))",
                title: title,
                tokens: item.tokens,
                cash: item.cash)
        }
        for item in billing.topMethods {
            let title = L("方法：%@", item.name)
            appendSummary(
                id: "minimax.billing.method.\(Self.stableID(item.name))",
                title: title,
                tokens: item.tokens,
                cash: item.cash)
        }

        return UsageSnapshot(
            sourceLabel: sourceLabel,
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: extras,
            providerCost: providerCost,
            claudeAdminAPIUsage: claudeAdminAPIUsage,
            codexResetCredits: codexResetCredits,
            planName: planName,
            accountLabel: accountLabel,
            updatedAt: updatedAt)
    }

    static func billingTitle(_ title: String, tokens: Int, cash: Double?) -> String {
        var parts = [title, L("%@ Token", Self.compactNumber(Double(tokens)))]
        if let cash {
            parts.append(Self.cashText(cash))
        }
        return parts.joined(separator: " · ")
    }

    static func compactNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = value >= 1000 ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }

    static func cashText(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func stableID(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let id = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return id.isEmpty ? "unknown" : id
    }
}
