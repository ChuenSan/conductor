import Foundation
import SweetCookieKit

/// Augment（auggie）用量取数。摘自 CodexBar `Augment` provider:
/// 优先跑 `auggie account status`，失败后回落到浏览器 cookie 路径：
/// 从浏览器里取 augmentcode.com 的登录 cookie → `GET app.augmentcode.com/api/credits`（必需）拿额度，
/// 再 `GET /api/subscription`（可选，给套餐名/计费周期结束日）→ 算已用百分比。
///
/// Augment 在 CodexBar 里是 **cookie 类** provider（无 env token；Auth0/NextAuth/AuthJS 会话 cookie）。
/// 注意：首次读取 Chrome cookie 会弹一次「Chrome 安全存储」钥匙串授权框；Safari 需要「完全磁盘访问」。
/// 无登录态/无授权则报错。照搬自 CodexBar，本机无登录态无法实跑验证。
public enum AugmentUsageError: LocalizedError, Sendable {
    case noSession
    case unauthorized
    case server(Int)
    case invalidResponse
    case network(String)
    case unsupportedSource(String)
    case cliUnavailable
    case cliFailed(String)
    case cliNoOutput
    case cliNotAuthenticated
    case cliParseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noSession: L("没有找到 Augment 登录态，请在浏览器登录 app.augmentcode.com（Safari 需开启完全磁盘访问）")
        case .unauthorized: L("Augment 登录态已失效，请重新登录 app.augmentcode.com")
        case let .server(c): L("Augment 接口错误（%ld）", c)
        case .invalidResponse: L("Augment 用量接口返回异常")
        case let .network(m): L("网络错误：%@", m)
        case let .unsupportedSource(source): L("Augment 来源 %@ 不受支持，请使用 auto 或 cli", source)
        case .cliUnavailable: L("未找到 Augment CLI，请安装 auggie 或设置 AUGGIE_CLI_PATH")
        case let .cliFailed(message): L("Augment CLI 失败：%@", message)
        case .cliNoOutput: L("Augment CLI 没有输出")
        case .cliNotAuthenticated: L("Augment CLI 未登录，请运行 `auggie login`")
        case let .cliParseFailed(message): L("Augment CLI 输出解析失败：%@", message)
        }
    }
}

public enum AugmentUsageFetcher {
    private static let cookieDomains = ["augmentcode.com", "app.augmentcode.com"]
    /// Auth0 / NextAuth / AuthJS 会话 cookie 名（照搬自 CodexBar AugmentCookieImporter）。
    private static let sessionCookieNames: Set<String> = [
        "session", // Augment auth session (auth.augmentcode.com)
        "_session", // Legacy session cookie (app.augmentcode.com)
        "web_rpc_proxy_session", // Augment RPC proxy session
        "auth0", // Auth0 session
        "auth0.is.authenticated", // Auth0 authentication flag
        "a0.spajs.txs", // Auth0 SPA transaction state
        "__Secure-next-auth.session-token", // NextAuth secure session
        "next-auth.session-token", // NextAuth session
        "__Secure-authjs.session-token", // AuthJS secure session
        "__Host-authjs.csrf-token", // AuthJS CSRF token
        "authjs.session-token", // AuthJS session
    ]

    private static let commandTimeout: TimeInterval = 15

    /// 是否已配置 Augment 手动 Cookie 或本地 auggie。配置探测不能读取浏览器 Cookie，避免打开用量页触发钥匙串。
    public static func hasSession(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        UsageProviderRuntimeConfig.manualCookieHeader(providerID: "augment", env: env) != nil
            || resolvedAuggieBinary(env: env) != nil
    }

    /// 跨默认浏览器顺序取 augmentcode.com 的 cookie，拼成 Cookie 头；要求至少含一个已知会话 cookie。
    static func cookieHeader(env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let manual = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "augment", env: env) {
            return manual
        }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "augment", env: env) else {
            return nil
        }
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        for browser in Browser.defaultImportOrder {
            guard let cookies = try? client.cookies(matching: query, in: browser), !cookies.isEmpty else { continue }
            let hasNamed = cookies.contains { sessionCookieNames.contains($0.name) }
            // 优先返回含已知会话名的那组；否则也返回（让 API 去校验）。
            if hasNamed || browser == Browser.defaultImportOrder.last {
                return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
        }
        // 兜底：任意浏览器的 augment 域 cookie。
        for browser in Browser.defaultImportOrder {
            if let cookies = try? client.cookies(matching: query, in: browser), !cookies.isEmpty {
                return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            }
        }
        return nil
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared
    ) async throws -> CodexUsageSnapshot {
        switch UsageProviderRuntimeConfig.sourceMode(providerID: "augment", env: env) ?? "auto" {
        case "auto":
            if let binary = resolvedAuggieBinary(env: env) {
                do {
                    return try await fetchCLI(binary: binary, env: env)
                } catch {
                    // CodexBar falls back from auggie to the web cookie path when CLI auth/output fails.
                }
            }
            return try await fetchWeb(env: env, session: session)
        case "cli":
            guard let binary = resolvedAuggieBinary(env: env) else { throw AugmentUsageError.cliUnavailable }
            return try await fetchCLI(binary: binary, env: env)
        case let source:
            throw AugmentUsageError.unsupportedSource(source)
        }
    }

    private static func fetchWeb(
        env: [String: String],
        session: URLSession) async throws -> CodexUsageSnapshot
    {
        guard let header = cookieHeader(env: env) else { throw AugmentUsageError.noSession }

        // 额度（必需）。
        let credits = try await fetchCredits(cookieHeader: header, session: session)
        // 订阅（可选）：拿套餐名/计费周期结束日；失败不影响主流程。
        let subscription = try? await fetchSubscription(cookieHeader: header, session: session)

        return parse(credits: credits, subscription: subscription).withSourceLabel("web")
    }

    private static func fetchCLI(binary: String, env: [String: String]) async throws -> CodexUsageSnapshot {
        var commandEnv = env
        commandEnv["NO_COLOR"] = "1"
        commandEnv["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling],
            env: env,
            loginPATH: LoginShellPathCache.shared.currentOrCapture(),
            home: env["HOME"] ?? NSHomeDirectory())
        let output = try runCommand(
            binary: binary,
            arguments: ["account", "status"],
            environment: commandEnv,
            timeout: commandTimeout)
        return try parseCLI(output).withSourceLabel("cli")
    }

    private static func resolvedAuggieBinary(env: [String: String]) -> String? {
        BinaryLocator.resolveAuggieBinary(
            env: env,
            loginPATH: LoginShellPathCache.shared.currentOrCapture(),
            home: env["HOME"] ?? NSHomeDirectory())
    }

    // MARK: - 请求

    private static func fetchCredits(cookieHeader: String, session: URLSession) async throws -> CreditsResponse {
        let url = URL(string: "https://app.augmentcode.com/api/credits")!
        let data = try await get(url, cookieHeader: cookieHeader, session: session)
        do { return try JSONDecoder().decode(CreditsResponse.self, from: data) }
        catch { throw AugmentUsageError.invalidResponse }
    }

    private static func fetchSubscription(
        cookieHeader: String,
        session: URLSession) async throws -> SubscriptionResponse
    {
        let url = URL(string: "https://app.augmentcode.com/api/subscription")!
        let data = try await get(url, cookieHeader: cookieHeader, session: session)
        do { return try JSONDecoder().decode(SubscriptionResponse.self, from: data) }
        catch { throw AugmentUsageError.invalidResponse }
    }

    private static func get(_ url: URL, cookieHeader: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw AugmentUsageError.invalidResponse }
            data = d; http = h
        } catch let e as AugmentUsageError {
            throw e
        } catch {
            throw AugmentUsageError.network(error.localizedDescription)
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw AugmentUsageError.unauthorized }
        guard http.statusCode == 200 else { throw AugmentUsageError.server(http.statusCode) }
        return data
    }

    // MARK: - 解析

    private struct CreditsResponse: Decodable {
        let usageUnitsRemaining: Double?
        let usageUnitsConsumedThisBillingCycle: Double?
        let usageUnitsAvailable: Double?
        let usageBalanceStatus: String?

        var creditsRemaining: Double? { usageUnitsRemaining }
        var creditsUsed: Double? { usageUnitsConsumedThisBillingCycle }
        var creditsLimit: Double? {
            if let available = usageUnitsAvailable, available > 0 { return available }
            guard let remaining = usageUnitsRemaining,
                  let consumed = usageUnitsConsumedThisBillingCycle
            else { return nil }
            return remaining + consumed
        }
    }

    private struct SubscriptionResponse: Decodable {
        let planName: String?
        let billingPeriodEnd: String?
        let email: String?
        let organization: String?
    }

    private static func parse(credits: CreditsResponse, subscription: SubscriptionResponse?) -> CodexUsageSnapshot {
        let used = credits.creditsUsed
        let limit = credits.creditsLimit
        let remaining = credits.creditsRemaining

        // 已用百分比：优先 used/limit；否则 (limit-remaining)/limit。
        let percent: Double = if let used, let limit, limit > 0 {
            max(0, min(100, used / limit * 100))
        } else if let remaining, let limit, limit > 0 {
            max(0, min(100, (limit - remaining) / limit * 100))
        } else {
            0
        }

        // 计费周期结束日（ISO8601）。无则窗口 = now + 30 天。
        let end = parseISO(subscription?.billingPeriodEnd)
        let resetAt = end ?? Date().addingTimeInterval(30 * 24 * 3600)
        let windowSeconds = max(1, Int(resetAt.timeIntervalSinceNow))

        // Augment 是单一计费周期额度 → 放主窗（会话位）；无周窗。
        let window = CodexUsageSnapshot.Window(
            usedPercent: Int(percent.rounded()),
            resetAt: resetAt,
            windowSeconds: windowSeconds)
        return CodexUsageSnapshot(planType: subscription?.planName, session: window, weekly: nil)
    }

    static func parseCLI(_ output: String) throws -> CodexUsageSnapshot {
        var maxCredits: Int?
        var remaining: Int?
        var used: Int?
        var total: Int?
        var billingCycleEnd: Date?

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("credits / month") {
                if let match = trimmed.range(
                    of: #"([\d,]+)\s+credits\s*/\s*month"#,
                    options: .regularExpression)
                {
                    let number = cliNumber(String(trimmed[match]))
                    maxCredits = number
                    total = total ?? number
                }
            } else if trimmed.contains("Max Plan"),
                      trimmed.contains("credits"),
                      !trimmed.contains("remaining"),
                      let match = trimmed.range(of: #"([\d,]+)\s+credits"#, options: .regularExpression)
            {
                maxCredits = cliNumber(String(trimmed[match]))
            }

            if trimmed.contains("credits remaining"), !trimmed.contains("billing cycle") {
                if let match = trimmed.range(
                    of: #"([\d,]+)\s+credits\s+remaining"#,
                    options: .regularExpression)
                {
                    remaining = cliNumber(String(trimmed[match]))
                }
            }

            if trimmed.contains("remaining"), trimmed.contains("credits used") {
                if let match = trimmed.range(of: #"([\d,]+)\s+remaining"#, options: .regularExpression) {
                    remaining = cliNumber(String(trimmed[match]))
                }
                if let match = trimmed.range(
                    of: #"([\d,]+)\s*/\s*([\d,]+)\s+credits used"#,
                    options: .regularExpression)
                {
                    let parts = String(trimmed[match])
                        .replacingOccurrences(of: " credits used", with: "")
                        .split(separator: "/")
                    if parts.count == 2 {
                        used = cliNumber(String(parts[0]))
                        total = cliNumber(String(parts[1]))
                    }
                }
            }

            if trimmed.contains("billing cycle"), trimmed.contains("ends"),
               let match = trimmed.range(of: #"ends\s+([\d/]+)"#, options: .regularExpression)
            {
                let dateText = String(trimmed[match])
                    .replacingOccurrences(of: "ends", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let formatter = DateFormatter()
                formatter.dateFormat = "M/d/yyyy"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                billingCycleEnd = formatter.date(from: dateText)
            }
        }

        guard let finalRemaining = remaining else {
            throw AugmentUsageError.cliParseFailed("missing remaining credits")
        }
        guard let finalTotal = total ?? maxCredits else {
            throw AugmentUsageError.cliParseFailed("missing total credits")
        }
        let finalUsed = used ?? max(0, finalTotal - finalRemaining)
        let percent = finalTotal > 0 ? max(0, min(100, Double(finalUsed) / Double(finalTotal) * 100)) : 0
        let resetAt = billingCycleEnd ?? Date().addingTimeInterval(30 * 24 * 3600)
        let windowSeconds = max(1, Int(resetAt.timeIntervalSinceNow))
        let window = CodexUsageSnapshot.Window(
            usedPercent: Int(percent.rounded()),
            resetAt: resetAt,
            windowSeconds: windowSeconds)
        return CodexUsageSnapshot(
            planType: maxCredits.map { "\($0.formatted()) credits/month" },
            session: window,
            weekly: nil)
    }

    private static func parseISO(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private static func cliNumber(_ raw: String) -> Int? {
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func runCommand(
        binary: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval) throws -> String
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw AugmentUsageError.cliFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw AugmentUsageError.cliFailed("timed out")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            if stdoutText.contains("Authentication failed") || stdoutText.contains("auggie login")
                || stderrText.contains("Authentication failed") || stderrText.contains("auggie login")
            {
                throw AugmentUsageError.cliNotAuthenticated
            }
            throw AugmentUsageError.cliFailed(nonEmpty(stderrText) ?? nonEmpty(stdoutText) ?? "exit \(process.terminationStatus)")
        }
        guard let output = nonEmpty(stdoutText) else { throw AugmentUsageError.cliNoOutput }
        if output.contains("Authentication failed") || output.contains("auggie login") {
            throw AugmentUsageError.cliNotAuthenticated
        }
        return output
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
