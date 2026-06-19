import Foundation
import SweetCookieKit

/// Amp（Sourcegraph Amp，ampcode.com）用量取数。对齐 CodexBar 的 source planner：
/// `auto` 按 CLI -> API -> Web 回退，显式 `cli` 调 `amp usage`，显式 `api` 用 `AMP_API_KEY`，
/// 显式 `web` 用 `session` Cookie 读取 `https://ampcode.com/settings`。
///
/// 字段/端点完全照搬 CodexBar，本机无 token 无法实跑验证。
public enum AmpUsageError: LocalizedError, Sendable {
    case missingToken
    case noSessionCookie
    case cliUnavailable
    case cliFailed(String)
    case invalidToken
    case server(Int)
    case invalidResponse
    case apiError(String)
    case network(String)
    case unsupportedSource(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken: L("未找到 Amp 令牌，请设置环境变量 AMP_API_KEY")
        case .noSessionCookie: L("没有找到 Amp 登录态，请设置 Cookie 或在浏览器登录 ampcode.com")
        case .cliUnavailable: L("未找到 Amp CLI，请安装 amp 或设置 AMP_BINARY")
        case let .cliFailed(message): L("Amp CLI 失败：%@", message)
        case .invalidToken: L("Amp 令牌无效或已过期")
        case let .server(code): L("Amp 接口错误（%ld）", code)
        case .invalidResponse: L("Amp 用量接口返回异常")
        case let .apiError(m): L("Amp API 错误：%@", m)
        case let .network(m): L("网络错误：%@", m)
        case let .unsupportedSource(source): L("Amp 来源 %@ 不受支持，请使用 auto、cli、api 或 web", source)
        }
    }
}

public enum AmpUsageFetcher {
    // 照搬 CodexBar：POST 到 internal RPC，method=userDisplayBalanceInfo。
    static let usageURL = URL(string: "https://ampcode.com/api/internal?userDisplayBalanceInfo")!
    private static let settingsURL = URL(string: "https://ampcode.com/settings")!
    private static let apiTokenKey = "AMP_API_KEY"
    private static let cookieDomains = ["ampcode.com", "www.ampcode.com"]
    private static let commandTimeout: TimeInterval = 15

    /// 是否配置了 Amp 令牌或手动 Cookie；不读取浏览器 Cookie，避免配置探测触发钥匙串。
    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil || manualCookieHeader(env: env) != nil
    }

    static func token(env: [String: String]) -> String? {
        clean(env[apiTokenKey])
    }

    static func clean(_ raw: String?) -> String? {
        guard var v = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        if (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        v = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        let source = UsageProviderRuntimeConfig.sourceMode(providerID: "amp", env: env) ?? "auto"
        switch source {
        case "cli":
            return try await fetchCLI(env: env, now: Date())
        case "api":
            return try await fetchAPI(env: env, session: session)
        case "web":
            return try await fetchWeb(env: env, session: session)
        case "auto":
            do {
                return try await fetchCLI(env: env, now: Date())
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if token(env: env) != nil {
                    do {
                        return try await fetchAPI(env: env, session: session)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return try await fetchWeb(env: env, session: session)
                    }
                }
                return try await fetchWeb(env: env, session: session)
            }
        default:
            throw AmpUsageError.unsupportedSource(source)
        }
    }

    private static func fetchAPI(
        env: [String: String],
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        guard let apiToken = token(env: env) else { throw AmpUsageError.missingToken }

        var request = URLRequest(url: usageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "method": "userDisplayBalanceInfo",
            "params": [:],
        ])
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw AmpUsageError.invalidResponse }
            data = d
            http = h
        } catch let e as AmpUsageError {
            throw e
        } catch {
            throw AmpUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            return try parse(data, now: Date()).withSourceLabel("api")
        case 401, 403:
            throw AmpUsageError.invalidToken
        default:
            throw AmpUsageError.server(http.statusCode)
        }
    }

    private static func fetchWeb(
        env: [String: String],
        session: URLSession = .shared) async throws -> CodexUsageSnapshot
    {
        let header = try cookieHeader(env: env)
        var request = URLRequest(url: settingsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(header, forHTTPHeaderField: "Cookie")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "user-agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "accept-language")
        request.setValue("https://ampcode.com", forHTTPHeaderField: "origin")
        request.setValue(settingsURL.absoluteString, forHTTPHeaderField: "referer")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw AmpUsageError.invalidResponse }
            data = d
            http = h
        } catch let e as AmpUsageError {
            throw e
        } catch {
            throw AmpUsageError.network(error.localizedDescription)
        }
        if http.statusCode == 401 || http.statusCode == 403 { throw AmpUsageError.invalidToken }
        guard http.statusCode == 200 else { throw AmpUsageError.server(http.statusCode) }
        return try parse(html: String(data: data, encoding: .utf8) ?? "", now: Date())
            .withSourceLabel("web")
    }

    private static func fetchCLI(env: [String: String], now: Date) async throws -> CodexUsageSnapshot {
        guard let binary = resolvedAmpBinary(env: env) else { throw AmpUsageError.cliUnavailable }
        var commandEnv = env
        commandEnv["NO_COLOR"] = "1"
        if commandEnv["PATH"] == nil {
            commandEnv["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        let output = try runCommand(binary: binary, arguments: ["usage"], environment: commandEnv, timeout: commandTimeout)
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AmpUsageError.cliFailed("empty output")
        }
        return try parse(displayText: output, now: now).withSourceLabel("cli")
    }

    // MARK: - 解析

    private struct UsageAPIResponse: Decodable {
        let ok: Bool
        let result: Result?
        let error: APIError?

        struct Result: Decodable {
            let displayText: String
        }

        struct APIError: Decodable {
            let code: String?
            let message: String?
        }
    }

    static func parse(_ data: Data, now: Date = Date()) throws -> CodexUsageSnapshot {
        let response: UsageAPIResponse
        do {
            response = try JSONDecoder().decode(UsageAPIResponse.self, from: data)
        } catch {
            throw AmpUsageError.invalidResponse
        }
        guard response.ok else {
            if response.error?.code == "auth-required" { throw AmpUsageError.invalidToken }
            throw AmpUsageError.apiError(response.error?.message ?? "unknown")
        }
        guard let displayText = response.result?.displayText, !displayText.isEmpty else {
            throw AmpUsageError.invalidResponse
        }
        return try parse(displayText: displayText, now: now)
    }

    static func parse(html: String, now: Date = Date()) throws -> CodexUsageSnapshot {
        guard let usage = parseFreeTierUsage(html) else {
            if looksSignedOut(html) { throw AmpUsageError.invalidToken }
            throw AmpUsageError.invalidResponse
        }
        let quota = max(0, usage.quota)
        let used = max(0, usage.used)
        let percent = quota > 0 ? min(100, used / quota * 100) : 0
        let windowSeconds = (usage.windowHours.map { $0 > 0 ? Int(($0 * 3600).rounded()) : 0 }) ?? 0
        let resetAt: Date = {
            guard quota > 0, usage.hourlyReplenishment > 0 else {
                return now.addingTimeInterval(TimeInterval(windowSeconds > 0 ? windowSeconds : 86400))
            }
            return now.addingTimeInterval(max(0, used / usage.hourlyReplenishment * 3600))
        }()
        let window = CodexUsageSnapshot.Window(
            usedPercent: max(0, min(100, Int(percent.rounded()))),
            resetAt: resetAt,
            windowSeconds: windowSeconds)
        return CodexUsageSnapshot(planType: nil, session: window, weekly: nil)
    }

    /// Amp Free 一档的额度/剩余/回补（金额单位 $）。
    private struct FreeTierUsage {
        let quota: Double
        let used: Double
        let hourlyReplenishment: Double
        let windowHours: Double?
    }

    static func parse(displayText: String, now: Date = Date()) throws -> CodexUsageSnapshot {
        let text = stripANSICodes(displayText)

        // 形如：`Signed in as alice@example.com (Acme)`，仅用于校验是否登录。
        let identityPattern = #"(?im)^\s*Signed in as\s+([^\s(]+)(?:\s+\(([^\r\n)]+)\))?\s*$"#
        let identity = captures(in: text, pattern: identityPattern)
        if identity == nil, looksSignedOut(text) {
            throw AmpUsageError.invalidToken
        }

        let amountPattern = #"([0-9][0-9,]*(?:\.[0-9]+)?)"#
        // 形如：`Amp Free: $4.20 / $10.00 remaining (replenishes +$0.50 / hour)`
        let freePattern = #"(?im)^\s*Amp Free:\s*\$?"# + amountPattern +
            #"\s*/\s*\$?"# + amountPattern +
            #"\s+remaining(?:\s*\(replenishes\s*\+\$?"# + amountPattern + #"\s*/\s*hour\))?"#

        let freeUsage: FreeTierUsage? = {
            guard let free = captures(in: text, pattern: freePattern),
                  let remaining = number(from: free[0]),
                  let quota = number(from: free[1])
            else { return nil }
            let hourlyReplenishment = number(from: free[2]) ?? 0
            let windowHours = hourlyReplenishment > 0
                ? max(1, (quota / hourlyReplenishment).rounded())
                : nil
            return FreeTierUsage(
                quota: quota,
                used: max(0, quota - remaining),
                hourlyReplenishment: hourlyReplenishment,
                windowHours: windowHours)
        }()

        // `Individual credits: $123.45 remaining`
        let creditsPattern = #"(?im)^\s*Individual credits:\s*\$?"# + amountPattern + #"\s+remaining"#
        let individualCredits = captures(in: text, pattern: creditsPattern)?.first.flatMap(number(from:))

        // `Workspace Acme: $67.89 remaining`（可多条）
        let workspacePattern = #"(?im)^\s*Workspace\s+(.+?):\s*\$?"# + amountPattern + #"\s+remaining"#
        let workspaceBalances: [AmpWorkspaceBalance] = allCaptures(in: text, pattern: workspacePattern).compactMap { caps in
            guard caps.count == 2, nonEmpty(caps[0]) != nil else { return nil }
            guard let remaining = number(from: caps[1]) else { return nil }
            return AmpWorkspaceBalance(name: caps[0], remaining: remaining)
        }

        guard freeUsage != nil || individualCredits != nil || !workspaceBalances.isEmpty else {
            throw AmpUsageError.invalidResponse
        }

        // 计划名：照搬 CodexBar 的 sessionLabel/weeklyLabel 含义 —— 主窗是 Amp Free。
        let planType = identity?.first.flatMap(nonEmpty)

        // session 窗 = Amp Free 一档。映射同 CodexBar `toUsageSnapshot`：
        //   usedPercent = used/quota*100；windowSeconds = windowHours*3600；
        //   resetAt = now + used/hourlyReplenishment*3600（回补到满所需时间）。
        if let free = freeUsage {
            let quota = max(0, free.quota)
            let used = max(0, free.used)
            let percent = quota > 0 ? min(100, used / quota * 100) : 0
            let windowSeconds = (free.windowHours.map { $0 > 0 ? Int(($0 * 3600).rounded()) : 0 }) ?? 0
            let resetAt: Date = {
                guard quota > 0, free.hourlyReplenishment > 0 else {
                    return now.addingTimeInterval(TimeInterval(windowSeconds > 0 ? windowSeconds : 86400))
                }
                return now.addingTimeInterval(max(0, used / free.hourlyReplenishment * 3600))
            }()
            let window = CodexUsageSnapshot.Window(
                usedPercent: max(0, min(100, Int(percent.rounded()))),
                resetAt: resetAt,
                windowSeconds: windowSeconds)
            return CodexUsageSnapshot(
                planType: planType,
                session: window,
                weekly: nil,
                ampUsage: AmpUsageDetails(
                    individualCredits: individualCredits,
                    workspaceBalances: workspaceBalances))
        }

        // 无 Amp Free 一档（纯余额账户）：没有用量周期 → session 占位，reset = now + 30 天，weekly = nil。
        // 余额本身是「剩余额度」而非「已用百分比」，无总额无法换算用量，故标记 0%（仅表示「已配置/可用」）。
        let window = CodexUsageSnapshot.Window(
            usedPercent: 0,
            resetAt: now.addingTimeInterval(30 * 24 * 3600),
            windowSeconds: 30 * 24 * 3600)
        return CodexUsageSnapshot(
            planType: planType,
            session: window,
            weekly: nil,
            ampUsage: AmpUsageDetails(
                individualCredits: individualCredits,
                workspaceBalances: workspaceBalances))
    }

    // MARK: - 文本工具（照搬 CodexBar AmpUsageParser）

    private static func stripANSICodes(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\u{001B}\\[[0-9;]*[A-Za-z]") else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
    }

    private static func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return captures(in: text, match: match)
    }

    private static func allCaptures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).map { captures(in: text, match: $0) }
    }

    private static func captures(in text: String, match: NSTextCheckingResult) -> [String] {
        (1..<match.numberOfRanges).map { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let range = Range(captureRange, in: text)
            else { return "" }
            return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func number(from text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ""))
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func looksSignedOut(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("sign in") || lower.contains("log in") || lower.contains("login") { return true }
        if lower.contains("/login") || lower.contains("ampcode.com/login") { return true }
        return false
    }

    private static func parseFreeTierUsage(_ html: String) -> FreeTierUsage? {
        for token in ["freeTierUsage", "getFreeTierUsage"] {
            if let object = extractObject(named: token, in: html),
               let usage = parseFreeTierUsageObject(object)
            {
                return usage
            }
        }
        return nil
    }

    private static func parseFreeTierUsageObject(_ object: String) -> FreeTierUsage? {
        guard let quota = number(for: "quota", in: object),
              let used = number(for: "used", in: object),
              let hourly = number(for: "hourlyReplenishment", in: object)
        else {
            return nil
        }
        return FreeTierUsage(
            quota: quota,
            used: used,
            hourlyReplenishment: hourly,
            windowHours: number(for: "windowHours", in: object))
    }

    private static func extractObject(named token: String, in text: String) -> String? {
        guard let tokenRange = text.range(of: token),
              let braceIndex = text[tokenRange.upperBound...].firstIndex(of: "{")
        else {
            return nil
        }
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = braceIndex
        while index < text.endIndex {
            let char = text[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == "{" {
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[braceIndex...index])
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func number(for key: String, in text: String) -> Double? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: key))\\b\\s*:\\s*([0-9]+(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return Double(text[valueRange])
    }

    private static func manualCookieHeader(env: [String: String]) -> String? {
        let raw = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "amp", env: env) ?? env["AMP_COOKIE"]
        guard let header = CookieHeaderNormalizer.normalize(raw),
              CookieHeaderNormalizer.pairs(from: header).contains(where: { $0.name == "session" })
        else {
            return nil
        }
        return header
    }

    private static func cookieHeader(env: [String: String]) throws -> String {
        if let manual = manualCookieHeader(env: env) {
            return manual
        }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "amp", env: env) else {
            throw AmpUsageError.noSessionCookie
        }
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: cookieDomains)
        for browser in Browser.defaultImportOrder {
            guard let cookies = try? client.cookies(matching: query, in: browser), !cookies.isEmpty else { continue }
            let sessionCookies = cookies.filter { $0.name == "session" && !$0.value.isEmpty }
            guard !sessionCookies.isEmpty else { continue }
            return sessionCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
        throw AmpUsageError.noSessionCookie
    }

    private static func resolvedAmpBinary(env: [String: String]) -> String? {
        for key in ["AMP_BINARY", "CONDUCTOR_AMP_BINARY"] {
            if let value = clean(env[key]), FileManager.default.isExecutableFile(atPath: value) {
                return value
            }
        }
        let path = env["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for dir in path.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("amp").path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
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
            throw AmpUsageError.cliFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw AmpUsageError.cliFailed("timed out")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw AmpUsageError.cliFailed(nonEmpty(stderrText) ?? nonEmpty(stdoutText) ?? "exit \(process.terminationStatus)")
        }
        return nonEmpty(stdoutText) ?? stderrText
    }
}
