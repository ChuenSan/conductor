import Foundation

/// Codex（ChatGPT 订阅）用量快照。取数路径与 CodexBar 相同：
/// 读 `~/.codex/auth.json`（或 `$CODEX_HOME/auth.json`）的 OAuth access token，
/// 调 `https://chatgpt.com/backend-api/wham/usage`，解析会话/周两个限流窗口。
public struct CodexUsageSnapshot: Sendable, Equatable {
    /// 实际取数来源（如 api / web / cli / local）。区别于 CLI 请求的 source mode。
    public let sourceLabel: String?
    public let planType: String?
    public let accountLabel: String?
    /// 会话窗口（primary）。
    public let session: Window?
    /// 周窗口（secondary）。
    public let weekly: Window?
    /// Codex credits / 余额。CodexBar 单独建 `CreditsSnapshot`；Conductor 用统一的 provider cost 模型承载。
    public let providerCost: ProviderCostSnapshot?
    /// Amp 等基础 provider 的专属余额明细；通过适配器带入富模型。
    public let ampUsage: AmpUsageDetails?
    /// 额外模型级窗口（例如 Codex Spark 5-hour / Weekly）。
    public let extraRateWindows: [NamedRateWindow]
    /// 手动限额重置券（CodexBar `CodexRateLimitResetCreditsSnapshot`）。
    public let codexResetCredits: CodexRateLimitResetCreditsSnapshot?

    public struct Window: Sendable, Equatable {
        /// 已用百分比 0...100。
        public let usedPercent: Int
        /// 重置时间。
        public let resetAt: Date
        /// 窗口总时长（秒）。
        public let windowSeconds: Int

        public init(usedPercent: Int, resetAt: Date, windowSeconds: Int) {
            self.usedPercent = usedPercent
            self.resetAt = resetAt
            self.windowSeconds = windowSeconds
        }

        public var remainingPercent: Int { max(0, 100 - usedPercent) }
    }

    public init(
        sourceLabel: String? = nil,
        planType: String?,
        accountLabel: String? = nil,
        session: Window?,
        weekly: Window?,
        providerCost: ProviderCostSnapshot? = nil,
        ampUsage: AmpUsageDetails? = nil,
        extraRateWindows: [NamedRateWindow] = [],
        codexResetCredits: CodexRateLimitResetCreditsSnapshot? = nil
    ) {
        self.sourceLabel = Self.normalizedSourceLabel(sourceLabel)
        self.planType = planType
        self.accountLabel = accountLabel
        self.session = session
        self.weekly = weekly
        self.providerCost = providerCost
        self.ampUsage = ampUsage?.isEmpty == true ? nil : ampUsage
        self.extraRateWindows = extraRateWindows
        self.codexResetCredits = codexResetCredits
    }

    public func withSourceLabel(_ sourceLabel: String?) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            sourceLabel: sourceLabel,
            planType: self.planType,
            accountLabel: self.accountLabel,
            session: self.session,
            weekly: self.weekly,
            providerCost: self.providerCost,
            ampUsage: self.ampUsage,
            extraRateWindows: self.extraRateWindows,
            codexResetCredits: self.codexResetCredits)
    }

    public var isEmpty: Bool {
        session == nil && weekly == nil && providerCost == nil && ampUsage == nil && extraRateWindows.isEmpty
            && codexResetCredits == nil
    }

    public var allWindows: [(title: String, window: RateWindow)] {
        var out: [(String, RateWindow)] = []
        if let session {
            out.append((L("会话"), RateWindow(
                title: L("会话"),
                usedPercent: Double(session.usedPercent),
                windowMinutes: session.windowSeconds > 0 ? session.windowSeconds / 60 : nil,
                resetsAt: session.resetAt)))
        }
        if let weekly {
            out.append((L("本周"), RateWindow(
                title: L("本周"),
                usedPercent: Double(weekly.usedPercent),
                windowMinutes: weekly.windowSeconds > 0 ? weekly.windowSeconds / 60 : nil,
                resetsAt: weekly.resetAt)))
        }
        for extra in extraRateWindows {
            out.append((extra.title, extra.window))
        }
        return out
    }

    private static func normalizedSourceLabel(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

}

public enum CodexUsageError: LocalizedError, Sendable {
    case notLoggedIn
    case unauthorized
    case refreshExpired
    case refreshRevoked
    case refreshReused
    case refreshInvalidResponse(String)
    case invalidResponse
    case server(Int)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: L("未找到 Codex 登录信息，请先运行 `codex` 登录")
        case .unauthorized: L("Codex 令牌已过期，请重新运行 `codex` 登录")
        case .refreshExpired: L("Codex 刷新令牌已过期，请重新运行 `codex` 登录")
        case .refreshRevoked: L("Codex 刷新令牌已撤销，请重新运行 `codex` 登录")
        case .refreshReused: L("Codex 刷新令牌已被重复使用，请重新运行 `codex` 登录")
        case let .refreshInvalidResponse(message): L("Codex 刷新令牌响应异常：%@", message)
        case .invalidResponse: L("Codex 用量接口返回异常")
        case let .server(code): L("Codex 接口错误（%ld）", code)
        case let .network(msg): L("网络错误：%@", msg)
        }
    }
}

public enum CodexUsageFetcher {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let rateLimitResetCreditsPath = "/wham/rate-limit-reset-credits"
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let oauthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    /// 是否存在 Codex 登录凭证（用于决定账号用量区是否展示该 provider）。
    public static func hasCredentials(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if let source = UsageProviderRuntimeConfig.sourceMode(providerID: "codex", env: env),
           ["web", "browser", "dashboard"].contains(source),
           OpenAIDashboardUsageFetcher.hasManualCookie(env: env)
        {
            return true
        }
        return FileManager.default.fileExists(atPath: authFileURL(env: env).path)
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        let source = UsageProviderRuntimeConfig.sourceMode(providerID: "codex", env: env) ?? "auto"
        switch source {
        case "web", "browser", "dashboard":
            if UsageProviderRuntimeConfig.shouldUseOpenAIWebBatterySaver(providerID: "codex", env: env) {
                let debugLog = OpenAIWebDebugLog.shared
                debugLog.reset(context: "battery-saver")
                debugLog.append("Battery Saver active; background OpenAI Web refresh will reuse cache.")
                if let cached = OpenAIDashboardUsageFetcher.cachedSnapshotForBatterySaver(env: env) {
                    debugLog.updateStatus(L("Battery Saver 已复用缓存的 OpenAI Web 快照。"))
                    debugLog.append("Battery Saver reused cached dashboard snapshot updatedAt=\(cached.updatedAt)")
                    return cached.toCodexUsageSnapshot().withSourceLabel("web")
                }
                debugLog.updateStatus(L("Battery Saver 已跳过后台 OpenAI Web 刷新；请手动刷新。"))
                debugLog.append("Battery Saver skipped OpenAI Web refresh because no reusable cache exists.")
                throw OpenAIDashboardUsageError.batterySaverSkipped
            }
            return try await OpenAIDashboardUsageFetcher.fetch(env: env, session: session)
                .toCodexUsageSnapshot()
                .withSourceLabel("web")
        case "cli":
            return try await fetchFromCLI(env: env)
        case "auto":
            do {
                return try await fetchFromCLI(env: env)
            } catch {
                return try await fetchFromHTTP(env: env, session: session)
            }
        default:
            return try await fetchFromHTTP(env: env, session: session)
        }
    }

    private static func fetchFromHTTP(
        env: [String: String],
        session: URLSession) async throws -> CodexUsageSnapshot
    {
        var creds = try loadCredentials(env: env)
        if creds.needsRefresh {
            creds = try await refreshCredentials(creds, env: env, session: session)
        }

        do {
            return try await fetchFromHTTPOnce(credentials: creds, env: env, session: session)
        } catch CodexUsageError.unauthorized where !creds.refreshToken.isEmpty {
            let refreshed = try await refreshCredentials(creds, env: env, session: session)
            return try await fetchFromHTTPOnce(credentials: refreshed, env: env, session: session)
        }
    }

    private static func fetchFromHTTPOnce(
        credentials creds: Credentials,
        env: [String: String],
        session: URLSession) async throws -> CodexUsageSnapshot
    {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Conductor", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw CodexUsageError.invalidResponse }
            data = d
            http = h
        } catch let error as CodexUsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            throw CodexUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            do {
                let resetCredits: CodexRateLimitResetCreditsSnapshot?
                do {
                    resetCredits = try await fetchRateLimitResetCredits(
                        credentials: creds,
                        env: env,
                        session: session)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as URLError where error.code == .cancelled {
                    throw error
                } catch {
                    resetCredits = nil
                }
                return try parsedSnapshot(data, credentials: creds, resetCredits: resetCredits)
                    .withSourceLabel("oauth")
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                throw CodexUsageError.invalidResponse
            }
        case 401, 403:
            throw CodexUsageError.unauthorized
        default:
            throw CodexUsageError.server(http.statusCode)
        }
    }

    static func fetchRateLimitResetCredits(
        credentials creds: Credentials,
        env: [String: String],
        timeout: TimeInterval = 4,
        session: URLSession) async throws -> CodexRateLimitResetCreditsSnapshot
    {
        var request = URLRequest(url: rateLimitResetCreditsURL(env: env), timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Conductor", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountId = creds.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw CodexUsageError.invalidResponse }
            data = d
            http = h
        } catch let error as CodexUsageError {
            throw error
        } catch {
            throw CodexUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            return try decodeRateLimitResetCredits(data)
        case 401, 403:
            throw CodexUsageError.unauthorized
        default:
            throw CodexUsageError.server(http.statusCode)
        }
    }

    private static func rateLimitResetCreditsURL(env: [String: String]) -> URL {
        rateLimitResetCreditsURL(env: env, configContents: nil)
    }

    private static func rateLimitResetCreditsURL(env: [String: String], configContents: String?) -> URL {
        let baseURL = chatGPTBaseURL(env: env, configContents: configContents)
        let normalized = normalizedChatGPTBaseURL(baseURL)
        let full = normalized + rateLimitResetCreditsPath
        return URL(string: full) ?? URL(string: "https://chatgpt.com/backend-api\(rateLimitResetCreditsPath)")!
    }

    private static func chatGPTBaseURL(env: [String: String], configContents: String?) -> String {
        if let configContents, let parsed = parseChatGPTBaseURL(from: configContents) {
            return parsed
        }
        if let contents = loadCodexConfigContents(env: env),
           let parsed = parseChatGPTBaseURL(from: contents)
        {
            return parsed
        }
        return "https://chatgpt.com/backend-api/"
    }

    private static func normalizedChatGPTBaseURL(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { value = "https://chatgpt.com/backend-api/" }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if (value.hasPrefix("https://chatgpt.com") || value.hasPrefix("https://chat.openai.com")),
           !value.contains("/backend-api")
        {
            value += "/backend-api"
        }
        return value
    }

    private static func parseChatGPTBaseURL(from contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true).first
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key == "chatgpt_base_url" else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'"))
            {
                value = String(value.dropFirst().dropLast())
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func loadCodexConfigContents(env: [String: String]) -> String? {
        let root = codexHomeURL(env: env)
        let url = root.appendingPathComponent("config.toml")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - CLI RPC

    private static func fetchFromCLI(env: [String: String]) async throws -> CodexUsageSnapshot {
        try await CodexCLIUsageRPCSessionPool.shared.fetch(env: env).withSourceLabel("codex-cli")
    }

    fileprivate static func recoverRPCSnapshot(from error: Error) -> CodexUsageSnapshot? {
        guard let bodyData = decodeRateLimitsErrorBodyData(from: error),
              let parsed = try? parse(bodyData)
        else { return nil }
        let hasNonWindowValue = parsed.providerCost != nil
            || parsed.codexResetCredits != nil
            || !parsed.extraRateWindows.isEmpty
        guard parsed.session != nil || hasNonWindowValue else { return nil }

        let json = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
        return CodexUsageSnapshot(
            planType: parsed.planType ?? normalizedPlan(stringValue(json?["plan_type"])),
            accountLabel: normalizedPlan(stringValue(json?["email"])),
            session: parsed.session,
            weekly: parsed.session == nil ? nil : parsed.weekly,
            providerCost: parsed.providerCost,
            extraRateWindows: parsed.extraRateWindows,
            codexResetCredits: parsed.codexResetCredits)
    }

    private static func decodeRateLimitsErrorBodyData(from error: Error) -> Data? {
        guard case let CodexRPCError.requestFailed(message) = error,
              let json = extractJSONObject(after: "body=", in: message)
        else { return nil }
        return json.data(using: .utf8)
    }

    private static func extractJSONObject(after marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let suffix = text[markerRange.upperBound...]
        guard let start = suffix.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false

        for index in suffix[start...].indices {
            let character = suffix[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(suffix[start...index])
                }
            default:
                break
            }
        }
        return nil
    }

    #if DEBUG
    static func recoverRPCSnapshotFromErrorMessageForTesting(_ message: String) -> CodexUsageSnapshot? {
        recoverRPCSnapshot(from: CodexRPCError.requestFailed(message))
    }
    #endif

    static func mapRPCSnapshot(
        rateLimits: RPCRateLimitSnapshot,
        account: RPCAccountResponse? = nil
    ) -> CodexUsageSnapshot {
        let accountPlan: String? = {
            guard let account = account?.account else { return nil }
            if case let .chatgpt(_, planType) = account {
                return planType
            }
            return nil
        }()
        let accountLabel: String? = {
            guard let account = account?.account else { return nil }
            if case let .chatgpt(email, _) = account {
                return normalizedPlan(email)
            }
            return nil
        }()
        return CodexUsageSnapshot(
            planType: normalizedPlan(rateLimits.planType) ?? normalizedPlan(accountPlan),
            accountLabel: accountLabel,
            session: rpcWindow(rateLimits.primary),
            weekly: rpcWindow(rateLimits.secondary),
            providerCost: providerCost(from: rateLimits.credits))
    }

    private static func rpcWindow(_ window: RPCRateLimitWindow?) -> CodexUsageSnapshot.Window? {
        guard let window, let resetsAt = window.resetsAt else { return nil }
        return CodexUsageSnapshot.Window(
            usedPercent: max(0, min(100, Int(window.usedPercent.rounded()))),
            resetAt: Date(timeIntervalSince1970: TimeInterval(resetsAt)),
            windowSeconds: max(0, window.windowDurationMins ?? 0) * 60)
    }

    private static func normalizedPlan(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func providerCost(from credits: RPCCreditsSnapshot?) -> ProviderCostSnapshot? {
        guard let credits, !credits.unlimited else { return nil }
        guard let balance = parseCreditBalance(credits.balance) else { return nil }
        return ProviderCostSnapshot(
            used: max(0, balance),
            limit: 0,
            currencyCode: "USD",
            period: L("余额"))
    }

    struct RPCAccountResponse: Decodable, Sendable {
        let account: RPCAccountDetails?
        let requiresOpenaiAuth: Bool?
    }

    enum RPCAccountDetails: Decodable, Sendable {
        case apiKey
        case chatgpt(email: String, planType: String)

        enum CodingKeys: String, CodingKey {
            case type
            case email
            case planType
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type).lowercased()
            switch type {
            case "apikey":
                self = .apiKey
            case "chatgpt":
                self = .chatgpt(
                    email: try container.decodeIfPresent(String.self, forKey: .email) ?? "",
                    planType: try container.decodeIfPresent(String.self, forKey: .planType) ?? "")
            default:
                throw CodexUsageError.invalidResponse
            }
        }
    }

    struct RPCRateLimitsResponse: Decodable, Sendable {
        let rateLimits: RPCRateLimitSnapshot
    }

    struct RPCRateLimitSnapshot: Decodable, Sendable {
        let primary: RPCRateLimitWindow?
        let secondary: RPCRateLimitWindow?
        let credits: RPCCreditsSnapshot?
        let planType: String?
    }

    struct RPCRateLimitWindow: Decodable, Sendable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Int?
    }

    struct RPCCreditsSnapshot: Decodable, Sendable {
        let hasCredits: Bool
        let unlimited: Bool
        let balance: String?
    }

    // MARK: - 凭证

    struct Credentials {
        let accessToken: String
        let refreshToken: String
        let idToken: String?
        let accountId: String?
        let lastRefresh: Date?

        var needsRefresh: Bool {
            guard !refreshToken.isEmpty else { return false }
            guard let lastRefresh else { return true }
            let eightDays: TimeInterval = 8 * 24 * 60 * 60
            return Date().timeIntervalSince(lastRefresh) > eightDays
        }
    }

    static func authFileURL(env: [String: String]) -> URL {
        codexHomeURL(env: env).appendingPathComponent("auth.json")
    }

    private static func codexHomeURL(env: [String: String]) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let codexHome = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !codexHome.isEmpty
        {
            return URL(fileURLWithPath: codexHome)
        }
        return home.appendingPathComponent(".codex")
    }

    static func loadCredentials(env: [String: String]) throws -> Credentials {
        let url = authFileURL(env: env)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else { throw CodexUsageError.notLoggedIn }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.invalidResponse
        }

        // 纯 API key 模式
        if let apiKey = (json["OPENAI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty
        {
            return Credentials(
                accessToken: apiKey,
                refreshToken: "",
                idToken: nil,
                accountId: nil,
                lastRefresh: nil)
        }

        guard let tokens = json["tokens"] as? [String: Any] else { throw CodexUsageError.notLoggedIn }
        let access = (tokens["access_token"] as? String) ?? (tokens["accessToken"] as? String)
        guard let accessToken = access, !accessToken.isEmpty else { throw CodexUsageError.notLoggedIn }
        let refreshToken = (tokens["refresh_token"] as? String) ?? (tokens["refreshToken"] as? String) ?? ""
        let idToken = (tokens["id_token"] as? String) ?? (tokens["idToken"] as? String)
        let accountId = (tokens["account_id"] as? String) ?? (tokens["accountId"] as? String)
        return Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountId: accountId,
            lastRefresh: parseLastRefresh(json["last_refresh"]))
    }

    private static func saveCredentials(_ credentials: Credentials, env: [String: String]) throws {
        let url = authFileURL(env: env)
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            json = existing
        }

        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
        ]
        if let idToken = credentials.idToken, !idToken.isEmpty {
            tokens["id_token"] = idToken
        }
        if let accountId = credentials.accountId, !accountId.isEmpty {
            tokens["account_id"] = accountId
        }
        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func refreshCredentials(
        _ credentials: Credentials,
        env: [String: String],
        session: URLSession) async throws -> Credentials
    {
        guard !credentials.refreshToken.isEmpty else { return credentials }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": oauthClientID,
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw CodexUsageError.invalidResponse }
            data = d
            http = h
        } catch let error as CodexUsageError {
            throw error
        } catch {
            throw CodexUsageError.network(error.localizedDescription)
        }

        guard http.statusCode == 200 else {
            throw refreshFailureError(statusCode: http.statusCode, data: data)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.refreshInvalidResponse(L("响应不是有效 JSON"))
        }

        let refreshed = Credentials(
            accessToken: (json["access_token"] as? String) ?? credentials.accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? credentials.refreshToken,
            idToken: (json["id_token"] as? String) ?? credentials.idToken,
            accountId: credentials.accountId,
            lastRefresh: Date())
        try saveCredentials(refreshed, env: env)
        return refreshed
    }

    private static func refreshFailureError(statusCode: Int, data: Data) -> CodexUsageError {
        if let errorCode = refreshErrorCode(from: data)?.lowercased() {
            switch errorCode {
            case "refresh_token_expired":
                return .refreshExpired
            case "refresh_token_reused":
                return .refreshReused
            case "invalid_grant", "refresh_token_invalidated":
                return .refreshRevoked
            default:
                break
            }
        }
        if statusCode == 401 {
            return .refreshExpired
        }
        return .refreshInvalidResponse("Status \(statusCode)")
    }

    private static func refreshErrorCode(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? String
        {
            return code
        }
        if let error = json["error"] as? String {
            return error
        }
        return json["code"] as? String
    }

    private static func parsedSnapshot(
        _ data: Data,
        credentials: Credentials,
        resetCredits: CodexRateLimitResetCreditsSnapshot? = nil) throws -> CodexUsageSnapshot
    {
        let snapshot = try parse(data)
        return CodexUsageSnapshot(
            planType: snapshot.planType ?? planType(fromIDToken: credentials.idToken),
            accountLabel: accountEmail(fromIDToken: credentials.idToken),
            session: snapshot.session,
            weekly: snapshot.weekly,
            providerCost: snapshot.providerCost,
            extraRateWindows: snapshot.extraRateWindows,
            codexResetCredits: resetCredits ?? snapshot.codexResetCredits)
    }

    static func parseJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var padded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 {
            padded.append("=")
        }
        guard let data = Data(base64Encoded: padded) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func accountEmail(fromIDToken idToken: String?) -> String? {
        guard let idToken, let payload = parseJWT(idToken) else { return nil }
        let profile = payload["https://api.openai.com/profile"] as? [String: Any]
        return normalizedPlan((payload["email"] as? String) ?? (profile?["email"] as? String))
    }

    private static func planType(fromIDToken idToken: String?) -> String? {
        guard let idToken, let payload = parseJWT(idToken) else { return nil }
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        return normalizedPlan((auth?["chatgpt_plan_type"] as? String) ?? (payload["chatgpt_plan_type"] as? String))
    }

    private static func parseLastRefresh(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct RateLimitResetCreditsResponse: Decodable {
        let credits: [CodexRateLimitResetCredit]
        let availableCount: Int

        enum CodingKeys: String, CodingKey {
            case credits
            case availableCount = "available_count"
        }
    }

    static func decodeRateLimitResetCredits(
        _ data: Data,
        updatedAt: Date = Date()) throws -> CodexRateLimitResetCreditsSnapshot
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeISO8601Date)
        let payload = try decoder.decode(RateLimitResetCreditsResponse.self, from: data)
        guard payload.availableCount >= 0 else { throw CodexUsageError.invalidResponse }
        return CodexRateLimitResetCreditsSnapshot(
            credits: payload.credits,
            availableCount: payload.availableCount,
            updatedAt: updatedAt)
    }

    private static func decodeISO8601Date(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        seconds.formatOptions = [.withInternetDateTime]
        if let date = fractional.date(from: raw) ?? seconds.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO-8601 date: \(raw)")
    }

    // MARK: - 解析

    static func parse(_ data: Data) throws -> CodexUsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageError.invalidResponse
        }
        let plan = json["plan_type"] as? String
        let rate = json["rate_limit"] as? [String: Any]
        return CodexUsageSnapshot(
            planType: plan,
            session: window(from: rate?["primary_window"] as? [String: Any]),
            weekly: window(from: rate?["secondary_window"] as? [String: Any]),
            providerCost: providerCost(fromHTTP: json["credits"] as? [String: Any]),
            extraRateWindows: extraRateWindows(from: json["additional_rate_limits"]))
    }

    private static func window(from dict: [String: Any]?) -> CodexUsageSnapshot.Window? {
        guard let dict else { return nil }
        guard let used = intValue(dict["used_percent"]),
              let resetAt = intValue(dict["reset_at"])
        else { return nil }
        let windowSeconds = intValue(dict["limit_window_seconds"]) ?? 0
        return CodexUsageSnapshot.Window(
            usedPercent: max(0, min(100, used)),
            resetAt: Date(timeIntervalSince1970: TimeInterval(resetAt)),
            windowSeconds: windowSeconds)
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let d = raw as? Double { return Int(d) }
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed) else { return nil }
            return Int(value)
        }
        return nil
    }

    private static func providerCost(fromHTTP credits: [String: Any]?) -> ProviderCostSnapshot? {
        guard let credits else { return nil }
        let unlimited = boolValue(credits["unlimited"]) ?? false
        guard !unlimited else { return nil }
        let balanceRaw = stringValue(credits["balance"])
            ?? stringValue(credits["remaining"])
            ?? stringValue(credits["remaining_balance"])
            ?? stringValue(credits["remainingBalance"])
        guard let balance = parseCreditBalance(balanceRaw) else { return nil }
        return ProviderCostSnapshot(
            used: max(0, balance),
            limit: 0,
            currencyCode: "USD",
            period: L("余额"))
    }

    static func parseCreditBalance(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(normalized) { return direct }
        guard let match = normalized.range(
            of: #"-?\d+(?:\.\d+)?"#,
            options: .regularExpression)
        else { return nil }
        return Double(normalized[match])
    }

    private static func stringValue(_ raw: Any?) -> String? {
        if let string = raw as? String { return string }
        if let double = raw as? Double { return String(double) }
        if let int = raw as? Int { return String(int) }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool? {
        if let bool = raw as? Bool { return bool }
        if let number = raw as? NSNumber { return number.boolValue }
        if let string = raw as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    private static func extraRateWindows(from raw: Any?) -> [NamedRateWindow] {
        guard let entries = raw as? [Any], !entries.isEmpty else { return [] }
        var usedIDs = Set<String>()
        return entries.flatMap { rawEntry -> [NamedRateWindow] in
            guard let entry = rawEntry as? [String: Any] else { return [] }
            return namedRateWindows(from: entry, usedIDs: &usedIDs)
        }
    }

    private static func namedRateWindows(
        from entry: [String: Any],
        usedIDs: inout Set<String>) -> [NamedRateWindow]
    {
        if isSpark(entry) {
            return sparkRateWindows(from: entry, usedIDs: &usedIDs)
        }

        guard let rateLimit = entry["rate_limit"] as? [String: Any],
              let snapshot = (rateLimit["primary_window"] as? [String: Any])
                ?? (rateLimit["secondary_window"] as? [String: Any]),
              let id = windowID(for: entry),
              usedIDs.insert(id).inserted,
              let window = rateWindow(from: snapshot, title: windowTitle(for: entry))
        else { return [] }

        return [NamedRateWindow(id: id, title: windowTitle(for: entry), window: window)]
    }

    private static func sparkRateWindows(
        from entry: [String: Any],
        usedIDs: inout Set<String>) -> [NamedRateWindow]
    {
        guard let rateLimit = entry["rate_limit"] as? [String: Any] else { return [] }
        let candidates: [(snapshot: [String: Any]?, fallback: SparkWindowKind)] = [
            (rateLimit["primary_window"] as? [String: Any], .fiveHour),
            (rateLimit["secondary_window"] as? [String: Any], .weekly),
        ]

        return candidates.compactMap { candidate -> NamedRateWindow? in
            guard let snapshot = candidate.snapshot else { return nil }
            let kind = sparkWindowKind(for: snapshot, fallback: candidate.fallback)
            guard usedIDs.insert(kind.id).inserted,
                  let window = rateWindow(from: snapshot, title: kind.title)
            else { return nil }
            return NamedRateWindow(id: kind.id, title: kind.title, window: window)
        }
    }

    private enum SparkWindowKind {
        case fiveHour
        case weekly

        var id: String {
            switch self {
            case .fiveHour: "codex-spark"
            case .weekly: "codex-spark-weekly"
            }
        }

        var title: String {
            switch self {
            case .fiveHour: "Codex Spark 5-hour"
            case .weekly: "Codex Spark Weekly"
            }
        }
    }

    private static func sparkWindowKind(
        for snapshot: [String: Any],
        fallback: SparkWindowKind) -> SparkWindowKind
    {
        let minutes = max(0, intValue(snapshot["limit_window_seconds"]) ?? 0) / 60
        if minutes > 0, minutes <= 6 * 60 { return .fiveHour }
        if minutes >= 6 * 24 * 60 { return .weekly }
        return fallback
    }

    private static func rateWindow(from snapshot: [String: Any], title: String) -> RateWindow? {
        guard let used = intValue(snapshot["used_percent"]) else { return nil }
        let windowSeconds = intValue(snapshot["limit_window_seconds"]) ?? 0
        let resetAt = intValue(snapshot["reset_at"]).flatMap { raw -> Date? in
            raw > 0 ? Date(timeIntervalSince1970: TimeInterval(raw)) : nil
        }
        return RateWindow(
            title: title,
            usedPercent: Double(max(0, min(100, used))),
            windowMinutes: windowSeconds > 0 ? windowSeconds / 60 : nil,
            resetsAt: resetAt)
    }

    private static func windowID(for entry: [String: Any]) -> String? {
        guard let source = firstNonEmpty(
            stringValue(entry["metered_feature"]),
            stringValue(entry["limit_name"]))
        else { return nil }
        let slug = slug(source)
        return slug.isEmpty ? nil : "codex-\(slug)"
    }

    private static func windowTitle(for entry: [String: Any]) -> String {
        firstNonEmpty(stringValue(entry["limit_name"]), stringValue(entry["metered_feature"]))
            ?? "Codex extra limit"
    }

    private static func isSpark(_ entry: [String: Any]) -> Bool {
        [stringValue(entry["limit_name"]), stringValue(entry["metered_feature"])]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("spark") }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return nil
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
}

private enum CodexRPCError: LocalizedError, Sendable {
    case startFailed(String)
    case malformed(String)
    case requestFailed(String)
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case let .startFailed(message):
            return "Codex app-server failed to start: \(message)"
        case let .malformed(message):
            return "Codex app-server returned invalid data: \(message)"
        case let .requestFailed(message):
            return "Codex app-server request failed: \(message)"
        case let .timeout(method):
            return "Codex app-server timed out waiting for \(method)"
        }
    }
}

private protocol CodexRPCTransport: Sendable {
    var stdoutLines: AsyncStream<Data> { get }
    var isRunning: Bool { get }

    func send(_ data: Data) throws
    func shutdown()
    func diagnostics() -> String
}

#if DEBUG
extension CodexUsageFetcher {
    struct CodexRPCFakeLifecycleResultForTesting: Sendable {
        let recordedMessages: [String]
        let accountLabel: String?
        let planType: String?
        let sessionUsedPercent: Int?
        let weeklyUsedPercent: Int?
        let shutdownCount: Int
        let isRunningAfterSuccess: Bool
    }

    struct CodexRPCFakeFailureResultForTesting: Sendable {
        let message: String
        let shutdownCount: Int
        let isRunning: Bool
    }

    static func codexRPCErrorDescriptionForTesting(kind: String, message: String) -> String? {
        let error: CodexRPCError
        switch kind {
        case "startFailed":
            error = .startFailed(message)
        case "malformed":
            error = .malformed(message)
        case "requestFailed":
            error = .requestFailed(message)
        case "timeout":
            error = .timeout(message)
        default:
            return nil
        }
        return error.errorDescription
    }

    static func codexRPCSessionKeyForTesting(env: [String: String]) -> String {
        CodexCLIUsageRPCSessionPool.sessionKey(for: env)
    }

    static func codexRPCFakeLifecycleForTesting() async throws -> CodexRPCFakeLifecycleResultForTesting {
        let transport = CodexRPCFakeTransportForTesting(diagnosticsText: "fake stderr stays attached")
        transport.onMessage = { id, method, transport in
            switch method {
            case "initialize":
                transport.yield(["method": "server/ready", "params": [:]])
                transport.yield(["id": 999, "result": [:]])
                if let id {
                    transport.yield(["id": id, "result": [:]])
                }
            case "account/rateLimits/read":
                if let id {
                    transport.yield([
                        "id": id,
                        "result": [
                            "rateLimits": [
                                "primary": [
                                    "usedPercent": 42.0,
                                    "windowDurationMins": 300,
                                    "resetsAt": 1_781_234_567,
                                ],
                                "secondary": [
                                    "usedPercent": 11.0,
                                    "windowDurationMins": 10_080,
                                    "resetsAt": 1_781_999_999,
                                ],
                                "credits": [
                                    "hasCredits": true,
                                    "unlimited": false,
                                    "balance": "7.25",
                                ],
                                "planType": "pro",
                            ],
                        ],
                    ])
                }
            case "account/read":
                if let id {
                    transport.yield([
                        "id": id,
                        "result": [
                            "account": [
                                "type": "chatgpt",
                                "email": "dev@example.com",
                                "planType": "team",
                            ],
                            "requiresOpenaiAuth": false,
                        ],
                    ])
                }
            default:
                break
            }
        }

        let client = CodexCLIUsageRPCClient(
            transport: transport,
            initializeTimeout: 0.5,
            requestTimeout: 0.5)
        try await client.initialize()
        let limits = try await client.fetchRateLimits().rateLimits
        let account = try await client.fetchAccount()
        let snapshot = mapRPCSnapshot(rateLimits: limits, account: account)
        let isRunningAfterSuccess = client.isRunning
        client.shutdown()

        return CodexRPCFakeLifecycleResultForTesting(
            recordedMessages: transport.recordedMessages(),
            accountLabel: snapshot.accountLabel,
            planType: snapshot.planType,
            sessionUsedPercent: snapshot.session?.usedPercent,
            weeklyUsedPercent: snapshot.weekly?.usedPercent,
            shutdownCount: transport.shutdownCount(),
            isRunningAfterSuccess: isRunningAfterSuccess)
    }

    static func codexRPCFakeTimeoutForTesting() async -> CodexRPCFakeFailureResultForTesting {
        let transport = CodexRPCFakeTransportForTesting(diagnosticsText: "no reply from fake app-server")
        let client = CodexCLIUsageRPCClient(
            transport: transport,
            initializeTimeout: 0.05,
            requestTimeout: 0.05)
        do {
            try await client.initialize()
            return CodexRPCFakeFailureResultForTesting(
                message: "unexpected success",
                shutdownCount: transport.shutdownCount(),
                isRunning: client.isRunning)
        } catch {
            return CodexRPCFakeFailureResultForTesting(
                message: error.localizedDescription,
                shutdownCount: transport.shutdownCount(),
                isRunning: client.isRunning)
        }
    }

    static func codexRPCFakeStdoutClosedForTesting() async -> CodexRPCFakeFailureResultForTesting {
        let transport = CodexRPCFakeTransportForTesting(diagnosticsText: "server closed pipe")
        transport.onMessage = { _, method, transport in
            if method == "initialize" {
                transport.closeStdout()
            }
        }
        let client = CodexCLIUsageRPCClient(
            transport: transport,
            initializeTimeout: 0.5,
            requestTimeout: 0.5)
        do {
            try await client.initialize()
            return CodexRPCFakeFailureResultForTesting(
                message: "unexpected success",
                shutdownCount: transport.shutdownCount(),
                isRunning: client.isRunning)
        } catch {
            client.shutdown()
            return CodexRPCFakeFailureResultForTesting(
                message: error.localizedDescription,
                shutdownCount: transport.shutdownCount(),
                isRunning: client.isRunning)
        }
    }
}
#endif

private actor CodexCLIUsageRPCSessionPool {
    static let shared = CodexCLIUsageRPCSessionPool()
    private static let sessionKeyEnvironmentKeys = [
        "CONDUCTOR_CODEX_BINARY",
        "CODEX_BINARY",
        "CODEX_HOME",
        "HOME",
        "PATH",
        "XDG_CONFIG_HOME",
    ]

    private let idleWindow: TimeInterval = 90
    private var sessions: [String: Session] = [:]
    private var starting: [String: Task<CodexCLIUsageRPCClient, Error>] = [:]
    private var inFlight: [String: Task<CodexUsageSnapshot, Error>] = [:]

    func fetch(env: [String: String]) async throws -> CodexUsageSnapshot {
        let key = sessionKey(env: env)
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await self.fetchFresh(key: key, env: env) }
        inFlight[key] = task
        do {
            let snapshot = try await task.value
            inFlight[key] = nil
            return snapshot
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    private func fetchFresh(key: String, env: [String: String]) async throws -> CodexUsageSnapshot {
        let client = try await client(for: key, env: env)
        do {
            let limits = try await client.fetchRateLimits().rateLimits
            let account = try? await client.fetchAccount()
            let snapshot = CodexUsageFetcher.mapRPCSnapshot(rateLimits: limits, account: account)
            if client.isRunning {
                markUsed(key: key)
            } else {
                discard(key: key)
            }
            return snapshot
        } catch {
            discard(key: key)
            if let recovered = CodexUsageFetcher.recoverRPCSnapshot(from: error) {
                return recovered
            }
            throw error
        }
    }

    private func client(for key: String, env: [String: String]) async throws -> CodexCLIUsageRPCClient {
        if var session = sessions[key] {
            if session.client.isRunning {
                session.idleShutdownTask?.cancel()
                session.idleShutdownTask = nil
                sessions[key] = session
                return session.client
            }
            session.idleShutdownTask?.cancel()
            sessions[key] = nil
        }

        if let task = starting[key] {
            return try await task.value
        }

        let task = Task {
            let client = try CodexCLIUsageRPCClient(env: env)
            do {
                try await client.initialize()
                return client
            } catch {
                client.shutdown()
                throw error
            }
        }
        starting[key] = task
        do {
            let client = try await task.value
            starting[key] = nil
            sessions[key] = Session(client: client, lastUsedAt: Date(), idleShutdownTask: nil)
            return client
        } catch {
            starting[key] = nil
            throw error
        }
    }

    private func markUsed(key: String) {
        guard var session = sessions[key] else { return }
        session.lastUsedAt = Date()
        session.idleShutdownTask?.cancel()
        let idleWindow = self.idleWindow
        session.idleShutdownTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(idleWindow * 1_000_000_000))
            await self?.shutdownIfIdle(key: key, idleWindow: idleWindow)
        }
        sessions[key] = session
    }

    private func shutdownIfIdle(key: String, idleWindow: TimeInterval) {
        guard let session = sessions[key],
              Date().timeIntervalSince(session.lastUsedAt) >= idleWindow
        else {
            return
        }
        session.idleShutdownTask?.cancel()
        session.client.shutdown()
        sessions[key] = nil
    }

    private func discard(key: String) {
        if let task = starting[key] {
            task.cancel()
            starting[key] = nil
        }
        guard let session = sessions[key] else { return }
        session.idleShutdownTask?.cancel()
        session.client.shutdown()
        sessions[key] = nil
    }

    private func sessionKey(env: [String: String]) -> String {
        Self.sessionKey(for: env)
    }

    fileprivate static func sessionKey(for env: [String: String]) -> String {
        sessionKeyEnvironmentKeys
            .map { "\($0)=\(env[$0] ?? "")" }
            .joined(separator: "\n")
    }

    private struct Session {
        var client: CodexCLIUsageRPCClient
        var lastUsedAt: Date
        var idleShutdownTask: Task<Void, Never>?
    }
}

private final class CodexCLIUsageRPCClient: @unchecked Sendable {
    private let transport: any CodexRPCTransport
    private var nextID = 1
    private let initializeTimeout: TimeInterval
    private let requestTimeout: TimeInterval

    private struct SendableJSONMessage: @unchecked Sendable {
        let value: [String: Any]
    }

    init(env: [String: String]) throws {
        self.transport = try CodexRPCProcessTransport(env: env)
        self.initializeTimeout = 8
        self.requestTimeout = 3
    }

    fileprivate init(
        transport: any CodexRPCTransport,
        initializeTimeout: TimeInterval = 8,
        requestTimeout: TimeInterval = 3)
    {
        self.transport = transport
        self.initializeTimeout = initializeTimeout
        self.requestTimeout = requestTimeout
    }

    deinit {
        shutdown()
    }

    var isRunning: Bool {
        transport.isRunning
    }

    func initialize() async throws {
        _ = try await request(
            method: "initialize",
            params: ["clientInfo": ["name": "conductor", "version": "0.1.0"]],
            timeout: initializeTimeout)
        try sendNotification(method: "initialized")
    }

    func fetchAccount() async throws -> CodexUsageFetcher.RPCAccountResponse {
        let message = try await request(method: "account/read")
        return try decodeResult(from: message)
    }

    func fetchRateLimits() async throws -> CodexUsageFetcher.RPCRateLimitsResponse {
        let message = try await request(method: "account/rateLimits/read")
        return try decodeResult(from: message)
    }

    func shutdown() {
        transport.shutdown()
    }

    private func request(
        method: String,
        params: [String: Any]? = nil,
        timeout: TimeInterval? = nil) async throws -> [String: Any]
    {
        let id = nextID
        nextID += 1
        try sendRequest(id: id, method: method, params: params)
        let wrapped = try await withTaskCancellationHandler {
            try await withTimeout(seconds: timeout ?? requestTimeout, method: method) {
                while true {
                    let message = try await self.readNextMessage()
                    if message["id"] == nil {
                        continue
                    }
                    guard self.jsonID(message["id"]) == id else { continue }
                    if let error = message["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "\(error)"
                        throw CodexRPCError.requestFailed(self.withDiagnostics(message))
                    }
                    return SendableJSONMessage(value: message)
                }
            }
        } onCancel: {
            self.shutdown()
        }
        return wrapped.value
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        method: String,
        body: @escaping @Sendable () async throws -> T) async throws -> T
    {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await body()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0.1, seconds) * 1_000_000_000))
                throw CodexRPCError.timeout(self.withDiagnostics(method))
            }
            do {
                let result = try await group.next()
                group.cancelAll()
                guard let result else { throw CodexRPCError.timeout(withDiagnostics(method)) }
                return result
            } catch {
                group.cancelAll()
                if case .timeout = error as? CodexRPCError {
                    self.shutdown()
                }
                throw error
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]? = nil) throws {
        try sendPayload(["method": method, "params": params ?? [:]])
    }

    private func sendRequest(id: Int, method: String, params: [String: Any]?) throws {
        try sendPayload(["id": id, "method": method, "params": params ?? [:]])
    }

    private func sendPayload(_ payload: [String: Any]) throws {
        guard transport.isRunning else {
            throw CodexRPCError.malformed(withDiagnostics("process exited before request"))
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        var line = data
        line.append(0x0A)
        try transport.send(line)
    }

    private func readNextMessage() async throws -> [String: Any] {
        for await line in transport.stdoutLines {
            guard !line.isEmpty else { continue }
            if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                return object
            }
        }
        throw CodexRPCError.malformed(withDiagnostics("stdout closed"))
    }

    private func decodeResult<T: Decodable>(from message: [String: Any]) throws -> T {
        guard let result = message["result"] else {
            throw CodexRPCError.malformed(withDiagnostics("missing result"))
        }
        let data = try JSONSerialization.data(withJSONObject: result)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CodexRPCError.malformed(withDiagnostics("failed to decode \(T.self): \(error.localizedDescription)"))
        }
    }

    private func jsonID(_ raw: Any?) -> Int? {
        if let int = raw as? Int { return int }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }

    private func withDiagnostics(_ message: String) -> String {
        let stderr = transport.diagnostics()
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(12)
            .joined(separator: " | ")
        guard !stderr.isEmpty else { return message }
        return "\(message) stderr: \(stderr)"
    }
}

private final class CodexRPCProcessTransport: CodexRPCTransport, @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    let stdoutLines: AsyncStream<Data>
    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private let stderrTail = BoundedTextBuffer(maxCharacters: 4_000)
    private let lifecycle = RPCProcessLifecycle()

    private final class LineBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func appendAndDrain(_ chunk: Data) -> [Data] {
            lock.lock()
            defer { lock.unlock() }
            data.append(chunk)
            var lines: [Data] = []
            while let newline = data.firstIndex(of: 0x0A) {
                let line = Data(data[..<newline])
                data.removeSubrange(...newline)
                if !line.isEmpty { lines.append(line) }
            }
            return lines
        }
    }

    private final class BoundedTextBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private let maxCharacters: Int
        private var text = ""

        init(maxCharacters: Int) {
            self.maxCharacters = max(0, maxCharacters)
        }

        func append(_ chunk: String) {
            guard !chunk.isEmpty, maxCharacters > 0 else { return }
            lock.lock()
            text.append(chunk)
            if text.count > maxCharacters {
                text.removeFirst(text.count - maxCharacters)
            }
            lock.unlock()
        }

        func snapshot() -> String {
            lock.lock()
            let value = text
            lock.unlock()
            return value
        }
    }

    private final class RPCProcessLifecycle: @unchecked Sendable {
        private let lock = NSLock()
        private var didFinishStdout = false
        private var didStopIO = false

        func finishStdoutOnce(
            stdoutPipe: Pipe,
            stdoutContinuation: AsyncStream<Data>.Continuation)
        {
            lock.lock()
            guard !didFinishStdout else {
                lock.unlock()
                return
            }
            didFinishStdout = true
            lock.unlock()

            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stdoutContinuation.finish()
        }

        func stopIOOnce(
            stdoutPipe: Pipe,
            stderrPipe: Pipe,
            stdoutContinuation: AsyncStream<Data>.Continuation)
        {
            lock.lock()
            let shouldFinishStdout = !didFinishStdout
            didFinishStdout = true
            let shouldStopIO = !didStopIO
            didStopIO = true
            lock.unlock()

            if shouldFinishStdout {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stdoutContinuation.finish()
            }
            if shouldStopIO {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            }
        }
    }

    init(env: [String: String]) throws {
        var continuation: AsyncStream<Data>.Continuation!
        self.stdoutLines = AsyncStream<Data> { continuation = $0 }
        self.stdoutContinuation = continuation

        var resolvedEnv = env
        let loginPATH = LoginShellPathCache.shared.currentOrCapture()
        resolvedEnv["PATH"] = PathBuilder.effectivePATH(
            purposes: [.rpc, .nodeTooling],
            env: resolvedEnv,
            loginPATH: loginPATH)

        let executable = Self.resolveExecutable(env: resolvedEnv, loginPATH: loginPATH)
            ?? "codex"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = resolvedEnv
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let message = CodexCLILaunchGate.shared.backgroundSkipMessage(binary: executable) {
            throw CodexRPCError.startFailed(message)
        }

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.stderrTail.append("\n\(Self.terminationSummary(process))\n")
            Task.detached { [weak self] in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.lifecycle.finishStdoutOnce(
                    stdoutPipe: self.stdoutPipe,
                    stdoutContinuation: self.stdoutContinuation)
            }
        }

        do {
            try process.run()
        } catch {
            let message = error.localizedDescription
            let throttled = CodexCLILaunchGate.shared.recordLaunchFailure(binary: executable, message: message)
            throw CodexRPCError.startFailed(throttled ?? message)
        }

        let stdoutBuffer = LineBuffer()
        let stdoutContinuation = self.stdoutContinuation
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                self.lifecycle.finishStdoutOnce(
                    stdoutPipe: self.stdoutPipe,
                    stdoutContinuation: stdoutContinuation)
                return
            }
            for line in stdoutBuffer.appendAndDrain(chunk) {
                stdoutContinuation.yield(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: chunk, encoding: .utf8), !text.isEmpty else { return }
            self.stderrTail.append(text)
        }
    }

    deinit {
        shutdown()
    }

    var isRunning: Bool {
        process.isRunning
    }

    func shutdown() {
        lifecycle.stopIOOnce(
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            stdoutContinuation: stdoutContinuation)
        if process.isRunning {
            process.terminate()
        }
    }

    func send(_ data: Data) throws {
        stdinPipe.fileHandleForWriting.write(data)
    }

    func diagnostics() -> String {
        stderrTail.snapshot()
    }

    private static func terminationSummary(_ process: Process) -> String {
        switch process.terminationReason {
        case .exit:
            return "codex app-server exited with status \(process.terminationStatus)"
        case .uncaughtSignal:
            return "codex app-server terminated by signal \(process.terminationStatus)"
        @unknown default:
            return "codex app-server terminated with status \(process.terminationStatus)"
        }
    }

    private static func resolveExecutable(env: [String: String], loginPATH: [String]?) -> String? {
        for key in ["CONDUCTOR_CODEX_BINARY", "CODEX_BINARY"] {
            if let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        }
        return BinaryLocator.resolveCodexBinary(env: env, loginPATH: loginPATH)
            ?? TTYCommandRunner.which("codex")
    }
}

#if DEBUG
private final class CodexRPCFakeTransportForTesting: CodexRPCTransport, @unchecked Sendable {
    typealias MessageHandler = @Sendable (
        _ id: Int?,
        _ method: String,
        _ transport: CodexRPCFakeTransportForTesting) -> Void

    let stdoutLines: AsyncStream<Data>
    var onMessage: MessageHandler?

    private let stdoutContinuation: AsyncStream<Data>.Continuation
    private let lock = NSLock()
    private let diagnosticsText: String
    private var running = true
    private var shutdowns = 0
    private var messages: [String] = []

    init(diagnosticsText: String = "") {
        var continuation: AsyncStream<Data>.Continuation!
        self.stdoutLines = AsyncStream<Data> { continuation = $0 }
        self.stdoutContinuation = continuation
        self.diagnosticsText = diagnosticsText
    }

    var isRunning: Bool {
        lock.lock()
        let value = running
        lock.unlock()
        return value
    }

    func send(_ data: Data) throws {
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let method = object["method"] as? String
            else { continue }

            let id = jsonID(object["id"])
            record(id: id, method: method)
            onMessage?(id, method, self)
        }
    }

    func shutdown() {
        lock.lock()
        shutdowns += 1
        if running {
            running = false
        }
        lock.unlock()
        stdoutContinuation.finish()
    }

    func diagnostics() -> String {
        diagnosticsText
    }

    func yield(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        stdoutContinuation.yield(data)
    }

    func closeStdout() {
        lock.lock()
        running = false
        lock.unlock()
        stdoutContinuation.finish()
    }

    func recordedMessages() -> [String] {
        lock.lock()
        let value = messages
        lock.unlock()
        return value
    }

    func shutdownCount() -> Int {
        lock.lock()
        let value = shutdowns
        lock.unlock()
        return value
    }

    private func record(id: Int?, method: String) {
        lock.lock()
        if let id {
            messages.append("request:\(id):\(method)")
        } else {
            messages.append("notify:\(method)")
        }
        lock.unlock()
    }

    private func jsonID(_ raw: Any?) -> Int? {
        if let int = raw as? Int { return int }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }
}
#endif
