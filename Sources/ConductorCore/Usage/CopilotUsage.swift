import Foundation
import SweetCookieKit

/// GitHub Copilot 用量取数。忠实摘自 CodexBar `Copilot` provider 的浏览器 cookie 路径
/// （`CopilotBudgetWebFetcher`，用 SweetCookieKit）：
///
///   1. 从浏览器取 github.com 的登录 cookie（要求至少含一个已知会话 cookie）。
///   2. `GET https://github.com/settings/billing/budgets`（HTML）→ 解析出 `X-Fetch-Nonce`。
///   3. 带 nonce + verified-fetch 头分页拉 `GET https://github.com/settings/billing/budgets?page=&page_size=10&scope=customer`（JSON）。
///   4. 挑出 Copilot 相关预算（按 product/sku/类型选择器匹配），按 `current/budget*100` 算已用百分比。
///
/// Token 账号路径也按 CodexBar 转写：GitHub OAuth token 调
/// `api.github.com/copilot_internal/user` 作为主用量，浏览器 Cookie 预算作为 browser/source 路径。
/// 预算接口本身不返回重置时刻，CodexBar 用「下个自然月 1 号」做展示近似，这里照搬。
///
/// 注意：首次读取 Chrome cookie 会弹一次「Chrome 安全存储」钥匙串授权框；Safari 需要「完全磁盘访问」。
/// 无登录态/无授权则报错。照搬自 CodexBar，本机无登录态无法实跑验证。
public enum CopilotUsageError: LocalizedError, Sendable {
    case noSession
    case notLoggedIn
    case server(Int)
    case invalidResponse
    case noBudget
    case missingToken
    case accountMismatch(expected: String, actual: String?)
    case unsupportedSource(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noSession: L("没有找到 GitHub 登录态，请在浏览器登录 github.com（Safari 需开启完全磁盘访问）")
        case .notLoggedIn: L("GitHub 浏览器登录态已失效，请重新登录 github.com")
        case let .server(c): L("GitHub 预算接口错误（%ld）", c)
        case .invalidResponse: L("GitHub 预算接口返回异常")
        case .noBudget: L("未找到可用的 Copilot 预算用量（请在 github.com/settings/billing/budgets 设置预算）")
        case .missingToken: L("缺少 GitHub Copilot OAuth token")
        case let .accountMismatch(expected, actual):
            L("GitHub 浏览器账号不匹配：当前 %@，需要 %@", actual ?? L("未知账号"), expected)
        case let .unsupportedSource(source):
            L("Copilot 不支持 %@ 来源；请使用 auto 或 api", source)
        case let .network(m): L("网络错误：%@", m)
        }
    }
}

public enum CopilotUsageFetcher {
    public static let tokenEnvironmentKey = "COPILOT_API_TOKEN"
    public static let enterpriseHostEnvironmentKey = "COPILOT_ENTERPRISE_HOST"
    public static let budgetExtrasEnvironmentKey = "CONDUCTOR_USAGE_COPILOT_BUDGET_EXTRAS"

    public struct GitHubUserIdentity: Decodable, Equatable, Sendable {
        public let id: Int64
        public let login: String

        public init(id: Int64, login: String) {
            self.id = id
            self.login = login
        }
    }

    private struct GitHubWebIdentity: Equatable {
        let id: String?
        let login: String?

        var displayName: String? {
            if let login = CopilotUsageFetcher.clean(login) { return login }
            return CopilotUsageFetcher.clean(id)
        }
    }

    private struct BudgetPageMetadata {
        let nonce: String?
        let identity: GitHubWebIdentity?
    }

    // CodexBar 的 cookie 域：github.com / www.github.com。
    private static let cookieDomains = ["github.com", "www.github.com"]
    // CodexBar CopilotGitHubCookieImporter.sessionCookieNames：要求至少命中其一才算有登录态。
    private static let sessionCookieNames: Set<String> = [
        "user_session",
        "__Host-user_session_same_site",
        "_gh_sess",
        "logged_in",
        "dotcom_user",
    ]

    private static let budgetsURLString = "https://github.com/settings/billing/budgets"

    // CodexBar 的 Copilot 预算选择器（归一后的标识）。
    private static let copilotProductID = "copilot"
    private static let copilotPremiumRequestSKU = "copilot_premium_request"
    private static let copilotAgentPremiumRequestSKU = "copilot_agent_premium_request"
    private static let sparkPremiumRequestSKU = "spark_premium_request"
    private static let copilotBudgetSelectors: Set<String> = [
        copilotProductID,
        copilotPremiumRequestSKU,
        copilotAgentPremiumRequestSKU,
        sparkPremiumRequestSKU,
    ]

    /// Copilot primary usage is API-token based, matching CodexBar. Browser cookies are only
    /// read later for optional budget extras after a token-backed fetch succeeds.
    public static func hasSession(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil
    }

    public static func token(env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        clean(env[tokenEnvironmentKey])
    }

    public static func enterpriseHost(env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        clean(env[enterpriseHostEnvironmentKey])
    }

    /// 跨默认浏览器顺序取 github.com 的 cookie，拼成 Cookie 头；要求至少含一个已知会话 cookie。
    static func cookieHeader(env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        cookieHeaderCandidates(env: env).first
    }

    private static func cookieHeaderCandidates(env: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        if let manual = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "copilot", env: env) {
            return [manual]
        }
        let cookieSource = UsageProviderRuntimeConfig.cookieSource(providerID: "copilot", env: env)
        let budgetExtrasMayReadBrowser = budgetExtrasEnabled(env: env)
            && cookieSource != "manual"
            && cookieSource != "off"
        guard budgetExtrasMayReadBrowser
            || UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "copilot", env: env)
        else {
            return []
        }
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        var headers: [String] = []
        var seen = Set<String>()
        for browser in Browser.defaultImportOrder {
            guard let cookies = try? client.cookies(matching: query, in: browser), !cookies.isEmpty else { continue }
            guard cookies.contains(where: { sessionCookieNames.contains($0.name) }) else { continue }
            let header = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            if seen.insert(header).inserted {
                headers.append(header)
            }
        }
        return headers
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        let source = UsageProviderRuntimeConfig.sourceMode(providerID: "copilot", env: env) ?? "auto"
        switch source {
        case "api", "auto":
            guard let token = token(env: env) else { throw CopilotUsageError.missingToken }
            let snapshot = try await fetchTokenUsage(
                token: token,
                enterpriseHost: enterpriseHost(env: env),
                session: session)
            return await withBudgetExtrasIfEnabled(
                snapshot.withSourceLabel("api"),
                token: token,
                env: env,
                session: session)
        default:
            throw CopilotUsageError.unsupportedSource(source)
        }
    }

    public static func fetchBudgetUsage(session: URLSession = .shared) async throws -> CodexUsageSnapshot {
        let allBudgets = try await fetchBudgetList(session: session)
        return try makeSnapshot(from: allBudgets, now: Date())
    }

    private static func fetchBudgetList(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared,
        expectedGitHubAccountIdentifier: String? = nil) async throws -> [Budget]
    {
        let headers = cookieHeaderCandidates(env: env)
        guard !headers.isEmpty else { throw CopilotUsageError.noSession }

        var lastRetryableError: CopilotUsageError?
        for header in headers {
            do {
                return try await fetchBudgetList(
                    cookieHeader: header,
                    session: session,
                    expectedGitHubAccountIdentifier: expectedGitHubAccountIdentifier)
            } catch let error as CopilotUsageError {
                switch error {
                case .notLoggedIn, .accountMismatch:
                    lastRetryableError = error
                    continue
                default:
                    throw error
                }
            }
        }
        if let lastRetryableError { throw lastRetryableError }
        throw CopilotUsageError.noSession
    }

    private static func fetchBudgetList(
        cookieHeader header: String,
        session: URLSession,
        expectedGitHubAccountIdentifier: String?) async throws -> [Budget]
    {
        // 1) 先抓预算页 HTML，解析出 fetch nonce（CodexBar：拿不到 nonce 也尽力继续）。
        let nonce = try await fetchNonce(
            cookieHeader: header,
            expectedGitHubAccountIdentifier: expectedGitHubAccountIdentifier,
            session: session)

        // 2) 分页拉预算 JSON。
        var allBudgets: [Budget] = []
        var page = 1
        let maxPages = 20
        var shouldContinue = true
        while shouldContinue, page <= maxPages {
            let response = try await fetchBudgetPage(
                cookieHeader: header,
                nonce: nonce,
                page: page,
                session: session)
            allBudgets.append(contentsOf: response.budgets)
            shouldContinue = response.hasNextPage == true
            page += 1
        }

        return allBudgets
    }

    public static func fetchTokenUsage(
        token: String,
        enterpriseHost: String? = nil,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        guard let url = usageURL(enterpriseHost: enterpriseHost) else { throw CopilotUsageError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        addCopilotHeaders(to: &request)

        let (data, http) = try await perform(request, session: session)
        switch http.statusCode {
        case 200:
            let usage = try JSONDecoder().decode(CopilotUsageResponse.self, from: data)
            return makeTokenSnapshot(from: usage)
        case 401, 403:
            throw CopilotUsageError.notLoggedIn
        default:
            throw CopilotUsageError.server(http.statusCode)
        }
    }

    public static func fetchGitHubIdentity(
        token: String,
        session: URLSession = .shared) async throws -> GitHubUserIdentity
    {
        guard let url = URL(string: "https://api.github.com/user") else { throw CopilotUsageError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, http) = try await perform(request, session: session)
        switch http.statusCode {
        case 200:
            return try JSONDecoder().decode(GitHubUserIdentity.self, from: data)
        case 401, 403:
            throw CopilotUsageError.notLoggedIn
        default:
            throw CopilotUsageError.server(http.statusCode)
        }
    }

    public static func apiHost(enterpriseHost: String?) -> String {
        let host = CopilotDeviceFlow.normalizedHost(enterpriseHost)
        if host == CopilotDeviceFlow.defaultHost { return "api.github.com" }
        if host.hasPrefix("api.") { return host }
        return "api.\(host)"
    }

    public static func usageURL(enterpriseHost: String?) -> URL? {
        URL(string: "https://\(apiHost(enterpriseHost: enterpriseHost))/copilot_internal/user")
    }

    public static func normalizedGitHubAccountIdentifier(for identity: GitHubUserIdentity) -> String {
        "github:user:\(identity.id)"
    }

    // MARK: - 网络

    private static func fetchNonce(
        cookieHeader: String,
        expectedGitHubAccountIdentifier: String?,
        session: URLSession) async throws -> String?
    {
        if let expectedGitHubAccountIdentifier {
            let metadata = try await fetchBudgetPageMetadata(cookieHeader: cookieHeader, session: session)
            try verifyExpectedGitHubAccount(metadata.identity, expected: expectedGitHubAccountIdentifier)
            return metadata.nonce
        }
        do {
            return try await fetchBudgetPageMetadata(cookieHeader: cookieHeader, session: session).nonce
        } catch {
            // GitHub accepts some budget requests without a nonce. Keep the metadata
            // page best-effort unless an expected account must be verified.
            return nil
        }
    }

    private static func fetchBudgetPageMetadata(cookieHeader: String, session: URLSession) async throws -> BudgetPageMetadata {
        guard let url = URL(string: budgetsURLString) else { throw CopilotUsageError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("Conductor", forHTTPHeaderField: "User-Agent")

        let (data, http) = try await perform(request, session: session)
        switch http.statusCode {
        case 200:
            guard let html = String(data: data, encoding: .utf8) else { throw CopilotUsageError.invalidResponse }
            return BudgetPageMetadata(
                nonce: extractFetchNonce(from: html),
                identity: extractGitHubWebIdentity(from: html))
        case 401, 403:
            throw CopilotUsageError.notLoggedIn
        default:
            throw CopilotUsageError.server(http.statusCode)
        }
    }

    private static func fetchBudgetPage(
        cookieHeader: String,
        nonce: String?,
        page: Int,
        session: URLSession) async throws -> BudgetResponse
    {
        guard var components = URLComponents(string: budgetsURLString) else {
            throw CopilotUsageError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "10"),
            URLQueryItem(name: "scope", value: "customer"),
        ]
        guard let url = components.url else { throw CopilotUsageError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(budgetsURLString, forHTTPHeaderField: "Referer")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("true", forHTTPHeaderField: "GitHub-Verified-Fetch")
        request.setValue("Conductor", forHTTPHeaderField: "User-Agent")
        if let nonce, !nonce.isEmpty {
            request.setValue(nonce, forHTTPHeaderField: "X-Fetch-Nonce")
        }

        let (data, http) = try await perform(request, session: session)
        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(BudgetResponse.self, from: data)
            } catch {
                throw CopilotUsageError.invalidResponse
            }
        case 401, 403:
            throw CopilotUsageError.notLoggedIn
        default:
            throw CopilotUsageError.server(http.statusCode)
        }
    }

    private static func perform(
        _ request: URLRequest,
        session: URLSession) async throws -> (Data, HTTPURLResponse)
    {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CopilotUsageError.invalidResponse }
            return (data, http)
        } catch let e as CopilotUsageError {
            throw e
        } catch {
            throw CopilotUsageError.network(error.localizedDescription)
        }
    }

    private static func addCopilotHeaders(to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
    }

    private static func makeTokenSnapshot(from usage: CopilotUsageResponse) -> UsageSnapshot {
        let resetsAt = parseQuotaResetDate(usage.quotaResetDate)
        let premium = makeTokenRateWindow(
            from: usage.quotaSnapshots.premiumInteractions,
            title: L("高级请求"),
            resetsAt: resetsAt)
        let chat = makeTokenRateWindow(
            from: usage.quotaSnapshots.chat,
            title: L("聊天"),
            resetsAt: resetsAt)

        if let premium {
            return UsageSnapshot(
                primary: premium,
                secondary: chat,
                planName: usage.copilotPlan.capitalized,
                updatedAt: Date())
        }
        return UsageSnapshot(
            primary: nil,
            secondary: chat,
            planName: usage.copilotPlan.capitalized,
            updatedAt: Date())
    }

    private static func withBudgetExtrasIfEnabled(
        _ snapshot: UsageSnapshot,
        token: String,
        env: [String: String],
        session: URLSession) async -> UsageSnapshot
    {
        guard budgetExtrasEnabled(env: env) else { return snapshot }
        do {
            let identity = try await fetchGitHubIdentity(token: token, session: session)
            let expectedIdentifier = normalizedGitHubAccountIdentifier(for: identity)
            let budgets = try await fetchBudgetList(
                env: env,
                session: session,
                expectedGitHubAccountIdentifier: expectedIdentifier)
            let extraRateWindows = budgetExtraWindows(from: budgets, now: Date())
            guard !extraRateWindows.isEmpty else { return snapshot }
            var next = snapshot
            next.extraRateWindows = extraRateWindows
            return next
        } catch {
            return snapshot
        }
    }

    private static func makeTokenRateWindow(
        from snapshot: CopilotUsageResponse.QuotaSnapshot?,
        title: String,
        resetsAt: Date?) -> RateWindow?
    {
        guard let snapshot, !snapshot.isPlaceholder, snapshot.hasPercentRemaining else { return nil }
        return RateWindow(
            title: title,
            usedPercent: snapshot.usedPercent,
            resetsAt: snapshot.unlimited ? nil : resetsAt,
            resetDescription: snapshot.overQuotaUsedPercent.map { String(format: "%.0f%% used", $0) })
    }

    static func parseQuotaResetDate(_ value: String?) -> Date? {
        guard let raw = clean(value) else { return nil }
        let fractionalISO = ISO8601DateFormatter()
        fractionalISO.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalISO.date(from: raw) {
            return date
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    // MARK: - nonce 解析（照搬 CodexBar 的多模式正则）

    static func extractFetchNonce(from html: String) -> String? {
        let patterns = [
            #"x-fetch-nonce"\s+content="([^"]+)""#,
            #"X-Fetch-Nonce"\s*:\s*"([^"]+)""#,
            #"fetchNonce"\s*:\s*"([^"]+)""#,
            #"data-fetch-nonce="([^"]+)""#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, range: range),
                  let nonceRange = Range(match.range(at: 1), in: html)
            else { continue }
            return String(html[nonceRange])
        }
        return nil
    }

    private static func extractGitHubWebIdentity(from html: String) -> GitHubWebIdentity? {
        let id = extractMetaContent(
            named: [
                "octolytics-actor-id",
                "analytics-user-id",
                "user-id",
            ],
            from: html)
        let login = extractMetaContent(
            named: [
                "user-login",
                "octolytics-actor-login",
                "analytics-user-login",
            ],
            from: html)
        let identity = GitHubWebIdentity(id: id, login: login)
        return identity.id == nil && identity.login == nil ? nil : identity
    }

    private static let metaTagRegex = try? NSRegularExpression(
        pattern: #"<meta\b[^>]*>"#,
        options: [.caseInsensitive])

    private static let metaAttributeRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(['"])(.*?)\2"#,
        options: [.caseInsensitive])

    private static func extractMetaContent(named names: [String], from html: String) -> String? {
        guard let metaTagRegex, let metaAttributeRegex else { return nil }
        let expectedNames = Set(names.map { $0.lowercased() })
        var contentByName: [String: String] = [:]
        let htmlRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for tagMatch in metaTagRegex.matches(in: html, range: htmlRange) {
            guard let tagRange = Range(tagMatch.range, in: html) else { continue }
            let tag = String(html[tagRange])
            let tagNSRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
            var attributes: [String: String] = [:]
            for attributeMatch in metaAttributeRegex.matches(in: tag, range: tagNSRange) {
                guard let keyRange = Range(attributeMatch.range(at: 1), in: tag),
                      let valueRange = Range(attributeMatch.range(at: 3), in: tag)
                else { continue }
                attributes[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
            }
            guard let name = attributes["name"]?.lowercased(),
                  expectedNames.contains(name),
                  contentByName[name] == nil,
                  let content = attributes["content"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty
            else { continue }
            contentByName[name] = content
        }
        for name in names {
            if let content = contentByName[name.lowercased()] {
                return content
            }
        }
        return nil
    }

    private static func verifyExpectedGitHubAccount(
        _ actual: GitHubWebIdentity?,
        expected expectedIdentifier: String) throws
    {
        guard let actual else {
            throw CopilotUsageError.accountMismatch(expected: expectedIdentifier, actual: nil)
        }
        guard webIdentity(actual, matches: expectedIdentifier) else {
            throw CopilotUsageError.accountMismatch(expected: expectedIdentifier, actual: actual.displayName)
        }
    }

    private static func webIdentity(_ identity: GitHubWebIdentity, matches expectedIdentifier: String) -> Bool {
        guard let expected = normalizedExpectedAccountIdentifier(expectedIdentifier) else { return false }
        if let expectedID = githubUserID(from: expected) {
            return identity.id == expectedID
        }
        return identity.login?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == expected
    }

    private static func normalizedExpectedAccountIdentifier(_ identifier: String?) -> String? {
        guard let identifier = clean(identifier)?.lowercased() else { return nil }
        return identifier
    }

    private static func githubUserID(from identifier: String) -> String? {
        let prefix = "github:user:"
        guard identifier.hasPrefix(prefix) else { return nil }
        let suffix = String(identifier.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : suffix
    }

    // MARK: - 预算 → 快照

    static func makeSnapshot(from budgets: [Budget], now: Date) throws -> CodexUsageSnapshot {
        let resetDate = approximateNextMonthResetDate(now: now)
        let windowSeconds = resetDate.map { max(1, Int($0.timeIntervalSince(now))) } ?? 30 * 24 * 3600

        let windows: [CodexUsageSnapshot.Window] = budgets.compactMap { budget in
            let selectors = normalizedSelectors(for: budget)
            guard isCopilotBudget(budget, selectors: selectors) else { return nil }
            // CodexBar：usedPercent = current/budget*100，封顶 999；这里再夹到 0...100 以适配 Int 窗口。
            let raw = budget.budgetAmount > 0
                ? min(999, max(0, budget.currentAmount / budget.budgetAmount * 100))
                : 0
            let used = Int(max(0, min(100, raw)).rounded())
            return CodexUsageSnapshot.Window(
                usedPercent: used,
                resetAt: resetDate ?? now.addingTimeInterval(TimeInterval(windowSeconds)),
                windowSeconds: windowSeconds)
        }

        guard !windows.isEmpty else { throw CopilotUsageError.noBudget }
        // 主预算 → session（会话位 / "Premium"），次预算 → weekly（"Chat"）。
        return CodexUsageSnapshot(
            planType: "Copilot",
            session: windows.first,
            weekly: windows.count > 1 ? windows[1] : nil)
    }

    static func budgetExtraWindows(from budgets: [Budget], now: Date) -> [NamedRateWindow] {
        var usedIDs = Set<String>()
        let resetDate = approximateNextMonthResetDate(now: now)
        return budgets.compactMap { budget in
            let selectors = normalizedSelectors(for: budget)
            guard isCopilotBudget(budget, selectors: selectors) else { return nil }
            let id = uniqueWindowID(for: budget, selectors: selectors, usedIDs: &usedIDs)
            let usedPercent = budget.budgetAmount > 0
                ? min(999, max(0, budget.currentAmount / budget.budgetAmount * 100))
                : 0
            return NamedRateWindow(
                id: id,
                title: windowTitle(for: budget, selectors: selectors),
                window: RateWindow(
                    usedPercent: usedPercent,
                    resetsAt: resetDate))
        }
    }

    private static func isCopilotBudget(_ budget: Budget, selectors: Set<String>) -> Bool {
        guard budget.budgetAmount > 0 else { return false }
        return !selectors.isDisjoint(with: copilotBudgetSelectors)
    }

    private static func normalizedSelectors(for budget: Budget) -> Set<String> {
        let values = budget.budgetProductSkus + [
            budget.budgetType,
            budget.budgetEntityName,
            budget.name,
        ].compactMap(\.self)
        return Set(values.compactMap(normalizedBillingIdentifier))
    }

    private static func windowTitle(for budget: Budget, selectors: Set<String>) -> String {
        let budgetType: String
        if selectors == [copilotProductID] {
            budgetType = "Copilot"
        } else if selectors.contains(copilotAgentPremiumRequestSKU) {
            budgetType = "Copilot Agent Premium Requests"
        } else if selectors.contains(sparkPremiumRequestSKU) {
            budgetType = "Spark Premium Requests"
        } else if selectors.contains(copilotPremiumRequestSKU) {
            budgetType = "All Premium Request SKUs"
        } else if let name = clean(budget.name) {
            budgetType = name
        } else {
            budgetType = "Copilot Premium Requests"
        }
        return "Budget - \(budgetType)"
    }

    private static func uniqueWindowID(
        for budget: Budget,
        selectors: Set<String>,
        usedIDs: inout Set<String>) -> String
    {
        let source = budget.id ?? budget.budgetProductSkus.joined(separator: "-")
        let sourceTitle = source.isEmpty ? windowTitle(for: budget, selectors: selectors) : source
        let slug = slug(sourceTitle)
        let base = slug.isEmpty ? "copilot-budget" : "copilot-budget-\(slug)"
        var candidate = base
        var suffix = 2
        while !usedIDs.insert(candidate).inserted {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    // CodexBar 的归一逻辑：把各种 sku/名称归到固定的 Copilot 标识。
    static func normalizedBillingIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let slug = slug(value)
        guard !slug.isEmpty else { return nil }
        let underscored = slug.replacingOccurrences(of: "-", with: "_")
        if underscored == copilotProductID {
            return copilotProductID
        }
        if underscored == "premium_request" || underscored == "premium_requests" {
            return copilotPremiumRequestSKU
        }
        if underscored == "coding_agent_premium_request" || underscored == "coding_agent_premium_requests" {
            return copilotAgentPremiumRequestSKU
        }
        if underscored.contains("spark"), underscored.contains("premium"), underscored.contains("request") {
            return sparkPremiumRequestSKU
        }
        if underscored.contains("cloud") || underscored.contains("coding"),
           underscored.contains("agent"),
           underscored.contains("premium"),
           underscored.contains("request")
        {
            return copilotAgentPremiumRequestSKU
        }
        if underscored.contains("bundled"), underscored.contains("premium"), underscored.contains("request") {
            return copilotPremiumRequestSKU
        }
        if underscored.contains("copilot"),
           underscored.contains("agent"),
           underscored.contains("premium"),
           underscored.contains("request")
        {
            return copilotAgentPremiumRequestSKU
        }
        if underscored.contains("copilot"), underscored.contains("premium"), underscored.contains("request") {
            return copilotPremiumRequestSKU
        }
        return underscored
    }

    private static func approximateNextMonthResetDate(now: Date) -> Date? {
        // GitHub 预算接口不返回重置时刻；CodexBar 用本地下个自然月 1 号做展示近似。
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month], from: now)
        guard let monthStart = calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: 1))
        else {
            return nil
        }
        return calendar.date(byAdding: .month, value: 1, to: monthStart)
    }

    private static func slug(_ value: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func clean(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func budgetExtrasEnabled(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let value = clean(env[budgetExtrasEnvironmentKey])?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(value)
    }

    // MARK: - OAuth token quota decoding

    struct CopilotUsageResponse: Decodable {
        private struct AnyCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int?

            init?(stringValue: String) {
                self.stringValue = stringValue
                self.intValue = nil
            }

            init?(intValue: Int) {
                self.stringValue = String(intValue)
                self.intValue = intValue
            }
        }

        struct QuotaSnapshot: Decodable {
            let entitlement: Double
            let remaining: Double
            let percentRemaining: Double
            let quotaID: String
            let hasPercentRemaining: Bool
            let unlimited: Bool
            private let entitlementWasDecoded: Bool
            private let remainingWasDecoded: Bool

            var usedPercent: Double { max(0, 100 - percentRemaining) }
            var overQuotaUsedPercent: Double? { usedPercent > 100 ? usedPercent : nil }
            var isPlaceholder: Bool {
                if unlimited { return false }
                if entitlement == 0, remaining == 0, percentRemaining == 0, !hasPercentRemaining {
                    return true
                }
                return entitlementWasDecoded && remainingWasDecoded && entitlement == 0 && remaining == 0
            }

            private enum CodingKeys: String, CodingKey {
                case entitlement
                case remaining
                case percentRemaining = "percent_remaining"
                case quotaID = "quota_id"
                case unlimited
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let decodedEntitlement = Self.decodeNumberIfPresent(container: container, key: .entitlement)
                let decodedRemaining = Self.decodeNumberIfPresent(container: container, key: .remaining)
                entitlement = decodedEntitlement ?? 0
                remaining = decodedRemaining ?? 0
                entitlementWasDecoded = decodedEntitlement != nil
                remainingWasDecoded = decodedRemaining != nil
                unlimited = try container.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
                quotaID = try container.decodeIfPresent(String.self, forKey: .quotaID) ?? ""
                let decodedPercent = Self.decodeNumberIfPresent(container: container, key: .percentRemaining)
                if unlimited {
                    percentRemaining = 100
                    hasPercentRemaining = true
                } else if let decodedPercent {
                    percentRemaining = decodedPercent
                    hasPercentRemaining = true
                } else if let decodedEntitlement, decodedEntitlement > 0, let decodedRemaining {
                    percentRemaining = (decodedRemaining / decodedEntitlement) * 100
                    hasPercentRemaining = true
                } else {
                    percentRemaining = 0
                    hasPercentRemaining = false
                }
            }

            private static func decodeNumberIfPresent(
                container: KeyedDecodingContainer<CodingKeys>,
                key: CodingKeys) -> Double?
            {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                    return value
                }
                if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                    return Double(value)
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                    return Double(value)
                }
                return nil
            }
        }

        struct QuotaCounts: Decodable {
            let chat: Double?
            let completions: Double?

            private enum CodingKeys: String, CodingKey {
                case chat
                case completions
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                chat = Self.decodeNumberIfPresent(container: container, key: .chat)
                completions = Self.decodeNumberIfPresent(container: container, key: .completions)
            }

            private static func decodeNumberIfPresent(
                container: KeyedDecodingContainer<CodingKeys>,
                key: CodingKeys) -> Double?
            {
                if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                    return value
                }
                if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                    return Double(value)
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: key) {
                    return Double(value)
                }
                return nil
            }
        }

        struct QuotaSnapshots: Decodable {
            let premiumInteractions: QuotaSnapshot?
            let chat: QuotaSnapshot?

            private enum CodingKeys: String, CodingKey {
                case premiumInteractions = "premium_interactions"
                case chat
            }

            init(premiumInteractions: QuotaSnapshot?, chat: QuotaSnapshot?) {
                self.premiumInteractions = premiumInteractions
                self.chat = chat
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                var premium = try container.decodeIfPresent(QuotaSnapshot.self, forKey: .premiumInteractions)
                var chat = try container.decodeIfPresent(QuotaSnapshot.self, forKey: .chat)
                if premium?.isPlaceholder == true { premium = nil }
                if chat?.isPlaceholder == true { chat = nil }

                if premium == nil || chat == nil {
                    let dynamic = try decoder.container(keyedBy: AnyCodingKey.self)
                    var fallbackPremium: QuotaSnapshot?
                    var fallbackChat: QuotaSnapshot?
                    var firstUsable: QuotaSnapshot?

                    for key in dynamic.allKeys {
                        guard let decoded = try? dynamic.decodeIfPresent(QuotaSnapshot.self, forKey: key),
                              !decoded.isPlaceholder
                        else { continue }
                        if firstUsable == nil { firstUsable = decoded }
                        let name = key.stringValue.lowercased()
                        if fallbackChat == nil, name.contains("chat") {
                            fallbackChat = decoded
                            continue
                        }
                        if fallbackPremium == nil,
                           name.contains("premium") || name.contains("completion") || name.contains("code")
                        {
                            fallbackPremium = decoded
                        }
                    }

                    premium = premium ?? fallbackPremium
                    chat = chat ?? fallbackChat
                    if premium == nil, chat == nil {
                        chat = firstUsable
                    }
                }

                self.premiumInteractions = premium
                self.chat = chat
            }
        }

        let quotaSnapshots: QuotaSnapshots
        let copilotPlan: String
        let tokenBasedBilling: Bool
        let quotaResetDate: String?

        private enum CodingKeys: String, CodingKey {
            case quotaSnapshots = "quota_snapshots"
            case copilotPlan = "copilot_plan"
            case tokenBasedBilling = "token_based_billing"
            case quotaResetDate = "quota_reset_date"
            case monthlyQuotas = "monthly_quotas"
            case limitedUserQuotas = "limited_user_quotas"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let directSnapshots = try container.decodeIfPresent(QuotaSnapshots.self, forKey: .quotaSnapshots)
            let monthlyQuotas = try container.decodeIfPresent(QuotaCounts.self, forKey: .monthlyQuotas)
            let limitedUserQuotas = try container.decodeIfPresent(QuotaCounts.self, forKey: .limitedUserQuotas)
            let derivedSnapshots = Self.makeQuotaSnapshots(monthly: monthlyQuotas, limited: limitedUserQuotas)
            let premium = Self.usableQuotaSnapshot(from: directSnapshots?.premiumInteractions)
                ?? Self.usableQuotaSnapshot(from: derivedSnapshots?.premiumInteractions)
            let chat = Self.usableQuotaSnapshot(from: directSnapshots?.chat)
                ?? Self.usableQuotaSnapshot(from: derivedSnapshots?.chat)
            if premium != nil || chat != nil {
                quotaSnapshots = QuotaSnapshots(premiumInteractions: premium, chat: chat)
            } else {
                quotaSnapshots = directSnapshots ?? QuotaSnapshots(premiumInteractions: nil, chat: nil)
            }
            copilotPlan = try container.decodeIfPresent(String.self, forKey: .copilotPlan) ?? "unknown"
            tokenBasedBilling = try container.decodeIfPresent(Bool.self, forKey: .tokenBasedBilling) ?? false
            quotaResetDate = try container.decodeIfPresent(String.self, forKey: .quotaResetDate)
        }

        private static func makeQuotaSnapshots(monthly: QuotaCounts?, limited: QuotaCounts?) -> QuotaSnapshots? {
            let premium = makeQuotaSnapshot(
                monthly: monthly?.completions,
                limited: limited?.completions)
            let chat = makeQuotaSnapshot(monthly: monthly?.chat, limited: limited?.chat)
            guard premium != nil || chat != nil else { return nil }
            return QuotaSnapshots(premiumInteractions: premium, chat: chat)
        }

        private static func makeQuotaSnapshot(monthly: Double?, limited: Double?) -> QuotaSnapshot? {
            guard let monthly, let limited, monthly > 0 else { return nil }
            let remaining = max(0, limited)
            let percentRemaining = max(0, min(100, (remaining / monthly) * 100))
            let json = [
                "entitlement": monthly,
                "remaining": remaining,
                "percent_remaining": percentRemaining,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
            return try? JSONDecoder().decode(QuotaSnapshot.self, from: data)
        }

        private static func usableQuotaSnapshot(from snapshot: QuotaSnapshot?) -> QuotaSnapshot? {
            guard let snapshot, !snapshot.isPlaceholder, snapshot.hasPercentRemaining else { return nil }
            return snapshot
        }
    }

    // MARK: - 预算解码（照搬 CodexBar 的宽松解码：多套蛇形/驼峰键名 + payload 包裹 + 数字/字符串/对象金额）

    struct BudgetResponse: Decodable {
        let budgets: [Budget]
        let hasNextPage: Bool?

        private enum CodingKeys: String, CodingKey {
            case budgets
            case payload
            case hasNextPage
            case hasNextPageSnake = "has_next_page"
        }

        init(budgets: [Budget], hasNextPage: Bool? = nil) {
            self.budgets = budgets
            self.hasNextPage = hasNextPage
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let payload = try container.decodeIfPresent(BudgetResponse.self, forKey: .payload) {
                self = payload
                return
            }
            self.budgets = try container.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
            self.hasNextPage = try container.decodeIfPresent(Bool.self, forKey: .hasNextPage)
                ?? container.decodeIfPresent(Bool.self, forKey: .hasNextPageSnake)
        }
    }

    struct Budget: Decodable, Equatable {
        let id: String?
        let name: String?
        let budgetType: String?
        let budgetProductSkus: [String]
        let budgetScope: String?
        let budgetEntityName: String?
        let budgetAmount: Double
        let currentAmount: Double

        init(
            id: String? = nil,
            name: String? = nil,
            budgetType: String? = nil,
            budgetProductSkus: [String] = [],
            budgetScope: String? = nil,
            budgetEntityName: String? = nil,
            budgetAmount: Double,
            currentAmount: Double = 0)
        {
            self.id = id
            self.name = name
            self.budgetType = budgetType
            self.budgetProductSkus = budgetProductSkus
            self.budgetScope = budgetScope
            self.budgetEntityName = budgetEntityName
            self.budgetAmount = budgetAmount
            self.currentAmount = currentAmount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            self.id = Self.decodeString(container: container, keys: ["id", "uuid", "budget_id", "budgetId"])
            self.name = Self.decodeString(container: container, keys: ["name", "display_name", "displayName", "title"])
            self.budgetType = Self.decodeString(
                container: container,
                keys: ["budget_type", "budgetType", "type", "pricing_target_type", "pricingTargetType"])
            self.budgetProductSkus = Self.decodeStringArray(
                container: container,
                keys: [
                    "budget_product_skus",
                    "budgetProductSkus",
                    "budget_product_sku",
                    "budgetProductSku",
                    "product_skus",
                    "productSkus",
                    "skus",
                    "sku",
                    "product",
                    "product_name",
                    "productName",
                    "pricing_target_id",
                    "pricingTargetId",
                ])
            self.budgetScope = Self.decodeString(container: container, keys: ["budget_scope", "budgetScope", "scope"])
            self.budgetEntityName = Self.decodeString(
                container: container,
                keys: [
                    "budget_entity_name",
                    "budgetEntityName",
                    "entity_name",
                    "entityName",
                    "target_name",
                    "targetName",
                ])
            self.budgetAmount = Self.decodeDouble(
                container: container,
                keys: [
                    "budget_amount",
                    "budgetAmount",
                    "target_amount",
                    "targetAmount",
                    "spending_limit",
                    "spendingLimit",
                    "limit",
                    "amount",
                    "max",
                ]) ?? 0
            self.currentAmount = Self.decodeDouble(
                container: container,
                keys: [
                    "current_usage",
                    "currentUsage",
                    "current_amount",
                    "currentAmount",
                    "usage_amount",
                    "usageAmount",
                    "usage",
                    "spent",
                    "amount_used",
                    "amountUsed",
                ]) ?? 0
        }

        private static func decodeString(
            container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]) -> String?
        {
            for key in keys {
                guard let codingKey = DynamicCodingKey(key) else { continue }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey), !value.isEmpty {
                    return value
                }
                if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                    return String(value)
                }
            }
            return nil
        }

        private static func decodeStringArray(
            container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]) -> [String]
        {
            for key in keys {
                guard let codingKey = DynamicCodingKey(key) else { continue }
                if let values = try? container.decodeIfPresent([String].self, forKey: codingKey), !values.isEmpty {
                    return values
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey), !value.isEmpty {
                    return [value]
                }
                if let values = try? container.decodeIfPresent([ProductSKU].self, forKey: codingKey),
                   !values.isEmpty
                {
                    return values.flatMap(\.selectors)
                }
            }
            return []
        }

        private static func decodeDouble(
            container: KeyedDecodingContainer<DynamicCodingKey>,
            keys: [String]) -> Double?
        {
            for key in keys {
                guard let codingKey = DynamicCodingKey(key) else { continue }
                if let value = try? container.decodeIfPresent(Double.self, forKey: codingKey) {
                    return value
                }
                if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                    return Double(value)
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey),
                   let parsed = Self.parseAmount(value)
                {
                    return parsed
                }
                if let value = try? container.decodeIfPresent(AmountValue.self, forKey: codingKey) {
                    return value.amount
                }
            }
            return nil
        }

        fileprivate static func parseAmount(_ value: String) -> Double? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let isNegative = trimmed.first == "-"
            guard !trimmed.dropFirst(isNegative ? 1 : 0).contains("-") else { return nil }
            let unsigned = trimmed.filter { $0.isNumber || $0 == "." }
            guard !unsigned.isEmpty else { return nil }
            return Double(isNegative ? "-\(unsigned)" : unsigned)
        }
    }

    private struct ProductSKU: Decodable, Equatable {
        let selectors: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            self.selectors = [
                "sku",
                "name",
                "display_name",
                "displayName",
                "product",
                "product_name",
                "productName",
            ].compactMap { key in
                guard let codingKey = DynamicCodingKey(key) else { return nil }
                return try? container.decodeIfPresent(String.self, forKey: codingKey)
            }
        }
    }

    private struct AmountValue: Decodable {
        let amount: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            self.amount = [
                "amount",
                "value",
                "total",
                "cents",
                "formatted",
            ].lazy.compactMap { key -> Double? in
                guard let codingKey = DynamicCodingKey(key) else { return nil }
                if let value = try? container.decodeIfPresent(Double.self, forKey: codingKey) {
                    return key == "cents" ? value / 100 : value
                }
                if let value = try? container.decodeIfPresent(Int.self, forKey: codingKey) {
                    return key == "cents" ? Double(value) / 100 : Double(value)
                }
                if let value = try? container.decodeIfPresent(String.self, forKey: codingKey) {
                    return Budget.parseAmount(value)
                }
                return nil
            }.first
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(_ stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }
}
