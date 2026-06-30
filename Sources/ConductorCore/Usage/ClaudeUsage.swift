import Foundation
import SweetCookieKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
#if canImport(Security)
import Security
#endif

/// Claude（Claude Code 订阅）用量取数。取数路径与 CodexBar 的 OAuth 路一致：
/// 读 `~/.claude/.credentials.json`（或 Keychain `Claude Code-credentials`）里的
/// `claudeAiOauth.accessToken`，调 `https://api.anthropic.com/api/oauth/usage`，
/// 解析 5 小时会话窗口、7 天周窗口、模型专属周窗与 Daily Routines 等附加窗口，
/// 以及 `extra_usage`（额外用量月度消费 vs 上限）。
///
/// 产出富模型 `UsageSnapshot`：session→primary、weekly→secondary、模型专属周窗→tertiary，
/// Daily Routines 等→extraRateWindows，extra_usage→providerCost。
public enum ClaudeUsageError: LocalizedError, Sendable {
    case notLoggedIn
    case unauthorized
    case refreshExpired
    case refreshRevoked
    case refreshInvalidResponse(String)
    case unsupportedSource(String)
    case noAvailableSource(String)
    case adminAPIKeyMissing
    case adminAPIServer(String, Int)
    case adminAPIInvalidResponse(String, String)
    case webSessionMissing
    case webInvalidSessionKey
    case webOrganizationMissing
    case webOrganizationNotFound(String)
    case webServer(String, Int)
    case webInvalidResponse(String)
    case cliUnavailable
    case cliFailed(Int32, String)
    case cliTimedOut
    case cliParseFailed(String)
    case invalidResponse
    case server(Int)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: L("未找到 Claude 登录信息，请先运行 `claude` 登录")
        case .unauthorized: L("Claude 令牌已过期，请重新运行 `claude` 登录")
        case .refreshExpired: L("Claude 刷新令牌已过期，请重新运行 `claude` 登录")
        case .refreshRevoked: L("Claude 刷新令牌已撤销，请重新运行 `claude` 登录")
        case let .refreshInvalidResponse(message): L("Claude 刷新令牌响应异常：%@", message)
        case let .unsupportedSource(source): L("Claude 来源 %@ 尚未接入；已停止回落到 OAuth，避免返回错误来源的数据。", source)
        case let .noAvailableSource(order): L("Claude 没有可用来源（%@）", order)
        case .adminAPIKeyMissing: L("未找到 Claude Admin API key，请设置 ANTHROPIC_ADMIN_KEY")
        case let .adminAPIServer(endpoint, code): L("Claude Admin API %@ 错误（%ld）", endpoint, code)
        case let .adminAPIInvalidResponse(endpoint, message): L("Claude Admin API %@ 解析失败：%@", endpoint, message)
        case .webSessionMissing: L("未找到 Claude Web 登录态，请设置 CONDUCTOR_USAGE_CLAUDE_COOKIE 或在浏览器登录 claude.ai")
        case .webInvalidSessionKey: L("Claude Web sessionKey 无效，请更新 CONDUCTOR_USAGE_CLAUDE_COOKIE 或 CONDUCTOR_USAGE_CLAUDE_SESSION_KEY")
        case .webOrganizationMissing: L("Claude Web API 未返回可用组织")
        case let .webOrganizationNotFound(id): L("Claude Web API 未找到组织 %@", id)
        case let .webServer(endpoint, code): L("Claude Web API %@ 错误（%ld）", endpoint, code)
        case let .webInvalidResponse(endpoint): L("Claude Web API %@ 返回异常", endpoint)
        case .cliUnavailable: L("未找到 Claude CLI，请安装或设置 CLAUDE_CLI_PATH")
        case let .cliFailed(code, message): L("Claude CLI /usage 失败（%ld）：%@", code, message)
        case .cliTimedOut: L("Claude CLI /usage 超时")
        case let .cliParseFailed(message): L("Claude CLI /usage 解析失败：%@", message)
        case .invalidResponse: L("Claude 用量接口返回异常")
        case let .server(code): L("Claude 接口错误（%ld）", code)
        case let .network(msg): L("网络错误：%@", msg)
        }
    }
}

private actor ClaudeCLIUsagePTYSessionPool {
    static let shared = ClaudeCLIUsagePTYSessionPool()

    private let idleWindow: TimeInterval = 90
    private var sessions: [String: Session] = [:]
    private var starting: [String: Task<ClaudeCLIUsagePTYClient, Error>] = [:]
    private var inFlight: [String: Task<String, Error>] = [:]

    func fetch(binary: String, env: [String: String], timeout: TimeInterval) async throws -> String {
        let key = sessionKey(binary: binary, env: env)
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await self.fetchFresh(key: key, binary: binary, env: env, timeout: timeout) }
        inFlight[key] = task
        do {
            let text = try await task.value
            inFlight[key] = nil
            return text
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    func discard(binary: String, env: [String: String]) {
        discard(key: sessionKey(binary: binary, env: env))
    }

    private func fetchFresh(
        key: String,
        binary: String,
        env: [String: String],
        timeout: TimeInterval) async throws -> String
    {
        let client = try await client(for: key, binary: binary, env: env)
        do {
            let text = try await client.fetchUsage(timeout: timeout)
            if client.isRunning {
                markUsed(key: key)
            } else {
                discard(key: key)
            }
            return text
        } catch {
            discard(key: key)
            throw error
        }
    }

    private func client(for key: String, binary: String, env: [String: String]) async throws -> ClaudeCLIUsagePTYClient {
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
            try ClaudeCLIUsagePTYClient(binary: binary, env: env)
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

    private func sessionKey(binary: String, env: [String: String]) -> String {
        let names = [
            "CLAUDE_CLI_PATH",
            "CLAUDE_CONFIG_DIR",
            "HOME",
            "PATH",
            "XDG_CONFIG_HOME",
            "CLAUDE_FAKE_MARKER_FILE",
        ]
        return (["binary=\(binary)"] + names.map { "\($0)=\(env[$0] ?? "")" })
            .joined(separator: "\n")
    }

    private struct Session {
        var client: ClaudeCLIUsagePTYClient
        var lastUsedAt: Date
        var idleShutdownTask: Task<Void, Never>?
    }
}

private final class ClaudeCLIUsagePTYClient: @unchecked Sendable {
    private let process = Process()
    private let workingDirectory: URL
    private let primaryFD: Int32
    private let primaryHandle: FileHandle
    private let secondaryHandle: FileHandle
    private var processGroup: pid_t?
    private let lock = NSLock()
    private var closed = false

    init(binary: String, env: [String: String]) throws {
        self.workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-claude-cli-persistent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try Self.prepareWorkingDirectory(workingDirectory)

        var primary: Int32 = -1
        var secondary: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &win) == 0 else {
            throw ClaudeUsageError.cliFailed(-1, "openpty failed")
        }
        _ = fcntl(primary, F_SETFL, O_NONBLOCK)
        self.primaryFD = primary
        self.primaryHandle = FileHandle(fileDescriptor: primary, closeOnDealloc: true)
        self.secondaryHandle = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)

        let resolved = URL(fileURLWithPath: binary)
        if let watchdog = TTYCommandRunner.locateBundledHelper("CodexBarClaudeWatchdog") {
            process.executableURL = URL(fileURLWithPath: watchdog)
            process.arguments = ["--", binary]
        } else {
            process.executableURL = resolved
            process.arguments = []
        }
        process.currentDirectoryURL = workingDirectory
        process.environment = Self.cliEnvironment(base: env, workingDirectory: workingDirectory)
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle

        do {
            try process.run()
        } catch {
            closeHandles()
            try? FileManager.default.removeItem(at: workingDirectory)
            throw ClaudeUsageError.cliFailed(-1, error.localizedDescription)
        }

        let pid = process.processIdentifier
        if setpgid(pid, pid) == 0 {
            processGroup = pid
        }
        guard TTYCommandRunner.registerActiveProcessForAppShutdown(
            pid: pid,
            binary: resolved.lastPathComponent)
        else {
            shutdown()
            throw ClaudeUsageError.cliFailed(-1, "App shutdown in progress")
        }
        if let processGroup {
            TTYCommandRunner.updateActiveProcessGroupForAppShutdown(pid: pid, processGroup: processGroup)
        }
        usleep(250_000)
    }

    deinit {
        shutdown()
    }

    var isRunning: Bool {
        process.isRunning
    }

    func fetchUsage(timeout: TimeInterval) async throws -> String {
        try await Task.detached(priority: .utility) {
            try self.fetchUsageBlocking(timeout: timeout)
        }.value
    }

    func shutdown() {
        lock.lock()
        let alreadyClosed = closed
        closed = true
        lock.unlock()
        guard !alreadyClosed else { return }

        try? sendUnlocked("/exit\n")
        closeHandles()

        let descendants = TTYProcessTreeTerminator.descendantPIDs(of: process.processIdentifier)
        if process.isRunning {
            process.terminate()
        }
        TTYProcessTreeTerminator.terminateProcessTree(
            rootPID: process.processIdentifier,
            processGroup: processGroup,
            signal: SIGTERM,
            knownDescendants: descendants)
        let waitDeadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < waitDeadline {
            usleep(100_000)
        }
        if process.isRunning {
            TTYProcessTreeTerminator.terminateProcessTree(
                rootPID: process.processIdentifier,
                processGroup: processGroup,
                signal: SIGKILL,
                knownDescendants: descendants)
        } else {
            for pid in descendants where pid > 0 {
                kill(pid, SIGKILL)
            }
        }
        if process.isRunning == false {
            process.waitUntilExit()
        }
        TTYCommandRunner.unregisterActiveProcessForAppShutdown(pid: process.processIdentifier)
        try? FileManager.default.removeItem(at: workingDirectory)
    }

    private func fetchUsageBlocking(timeout: TimeInterval) throws -> String {
        guard process.isRunning else {
            throw ClaudeUsageError.cliFailed(-1, "Claude PTY session is not running")
        }
        lock.lock()
        defer { lock.unlock() }
        guard !closed else {
            throw ClaudeUsageError.cliFailed(-1, "Claude PTY session is closed")
        }

        _ = drainAvailable(until: Date().addingTimeInterval(0.15))
        try sendUnlocked("/usage\r")

        var buffer = Data()
        let deadline = Date().addingTimeInterval(max(1, timeout))
        var lastOutputAt = Date()
        var sawOutput = false
        while Date() < deadline {
            let chunk = readAvailable()
            if !chunk.isEmpty {
                buffer.append(chunk)
                lastOutputAt = Date()
                sawOutput = true
            }
            if sawOutput, Date().timeIntervalSince(lastOutputAt) >= 1.2 {
                break
            }
            if !process.isRunning {
                break
            }
            usleep(50_000)
        }

        let drainDeadline = Date().addingTimeInterval(0.2)
        while Date() < drainDeadline {
            let chunk = readAvailable()
            if chunk.isEmpty {
                usleep(20_000)
            } else {
                buffer.append(chunk)
            }
        }

        guard !buffer.isEmpty else {
            throw ClaudeUsageError.cliTimedOut
        }
        return String(data: buffer, encoding: .utf8) ?? ""
    }

    private func drainAvailable(until deadline: Date) -> Data {
        var data = Data()
        while Date() < deadline {
            let chunk = readAvailable()
            if chunk.isEmpty {
                usleep(20_000)
            } else {
                data.append(chunk)
            }
        }
        return data
    }

    private func readAvailable() -> Data {
        var appended = Data()
        while true {
            var tmp = [UInt8](repeating: 0, count: 8192)
            errno = 0
            let n = read(primaryFD, &tmp, tmp.count)
            if n > 0 {
                appended.append(contentsOf: tmp.prefix(Int(n)))
                continue
            }
            if n == 0 {
                return appended
            }
            let err = errno
            if err == EAGAIN || err == EWOULDBLOCK || err == EINTR || err == EIO {
                return appended
            }
            return appended
        }
    }

    private func sendUnlocked(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { return }
        try data.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress else { return }
            var offset = 0
            var retries = 0
            while offset < rawBytes.count {
                let written = write(primaryFD, baseAddress.advanced(by: offset), rawBytes.count - offset)
                if written > 0 {
                    offset += written
                    retries = 0
                    continue
                }
                if written == 0 { break }

                let err = errno
                if err == EAGAIN || err == EWOULDBLOCK || err == EINTR {
                    retries += 1
                    if retries > 200 {
                        throw ClaudeUsageError.cliFailed(-1, "write to Claude PTY would block")
                    }
                    usleep(5_000)
                    continue
                }
                throw ClaudeUsageError.cliFailed(-1, "write to Claude PTY failed: \(String(cString: strerror(err)))")
            }
        }
    }

    private func closeHandles() {
        try? primaryHandle.close()
        try? secondaryHandle.close()
    }

    private static func prepareWorkingDirectory(_ directory: URL) throws {
        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.local.json")
        let settings: [String: String] = ["disableDeepLinkRegistration": "disable"]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func cliEnvironment(base: [String: String], workingDirectory: URL) -> [String: String] {
        var environment = base
        environment["PWD"] = workingDirectory.path
        if environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        if environment["LANG"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["LANG"] = "en_US.UTF-8"
        }
        for key in environment.keys where key.hasPrefix("ANTHROPIC_") {
            environment.removeValue(forKey: key)
        }
        return TTYCommandRunner.enrichedEnvironment(baseEnv: environment)
    }
}

enum ClaudeUsageDataSource: String, CaseIterable, Sendable {
    case auto
    case api
    case web
    case browser
    case cli
    case oauth

    var sourceLabel: String {
        switch self {
        case .api: "api"
        case .browser: "web"
        default: self.rawValue
        }
    }
}

struct ClaudeSourcePlanningInput: Equatable, Sendable {
    let selectedDataSource: ClaudeUsageDataSource
    let hasAdminAPIKey: Bool
    let hasWebSession: Bool
    let hasCLI: Bool
    let hasOAuthCredentials: Bool
}

enum ClaudeSourcePlanReason: String, Equatable, Sendable {
    case explicitSourceSelection = "explicit-source-selection"
    case autoPreferredAdminAPI = "auto-preferred-admin-api"
    case autoPreferredOAuth = "auto-preferred-oauth"
    case autoFallbackCLI = "auto-fallback-cli"
    case autoFallbackWeb = "auto-fallback-web"
}

struct ClaudeFetchPlanStep: Equatable, Sendable {
    let dataSource: ClaudeUsageDataSource
    let inclusionReason: ClaudeSourcePlanReason
    let isPlausiblyAvailable: Bool
}

struct ClaudeFetchPlan: Equatable, Sendable {
    let input: ClaudeSourcePlanningInput
    let orderedSteps: [ClaudeFetchPlanStep]

    var availableSteps: [ClaudeFetchPlanStep] {
        orderedSteps.filter(\.isPlausiblyAvailable)
    }

    var executionStep: ClaudeFetchPlanStep? {
        switch input.selectedDataSource {
        case .auto:
            availableSteps.first
        case .api, .web, .browser, .cli, .oauth:
            orderedSteps.first
        }
    }

    var orderLabel: String {
        orderedSteps.map(\.dataSource.sourceLabel).joined(separator: "→")
    }
}

enum ClaudeSourcePlanner {
    static func resolve(input: ClaudeSourcePlanningInput) -> ClaudeFetchPlan {
        ClaudeFetchPlan(input: input, orderedSteps: makeSteps(input: input))
    }

    private static func makeSteps(input: ClaudeSourcePlanningInput) -> [ClaudeFetchPlanStep] {
        switch input.selectedDataSource {
        case .auto:
            var steps: [ClaudeFetchPlanStep] = []
            if input.hasAdminAPIKey {
                steps.append(step(.api, reason: .autoPreferredAdminAPI, input: input))
            }
            steps.append(step(.oauth, reason: .autoPreferredOAuth, input: input))
            steps.append(step(.cli, reason: .autoFallbackCLI, input: input))
            steps.append(step(.web, reason: .autoFallbackWeb, input: input))
            return steps
        case .api:
            return [step(.api, reason: .explicitSourceSelection, input: input)]
        case .web:
            return [step(.web, reason: .explicitSourceSelection, input: input)]
        case .browser:
            return [step(.browser, reason: .explicitSourceSelection, input: input)]
        case .cli:
            return [step(.cli, reason: .explicitSourceSelection, input: input)]
        case .oauth:
            return [step(.oauth, reason: .explicitSourceSelection, input: input)]
        }
    }

    private static func step(
        _ dataSource: ClaudeUsageDataSource,
        reason: ClaudeSourcePlanReason,
        input: ClaudeSourcePlanningInput) -> ClaudeFetchPlanStep
    {
        ClaudeFetchPlanStep(
            dataSource: dataSource,
            inclusionReason: reason,
            isPlausiblyAvailable: isPlausiblyAvailable(dataSource, input: input))
    }

    private static func isPlausiblyAvailable(
        _ dataSource: ClaudeUsageDataSource,
        input: ClaudeSourcePlanningInput) -> Bool
    {
        switch dataSource {
        case .auto:
            false
        case .api:
            input.hasAdminAPIKey
        case .web, .browser:
            input.hasWebSession
        case .cli:
            input.hasCLI
        case .oauth:
            input.hasOAuthCredentials
        }
    }
}

public struct ClaudeAdminAPIUsageSnapshot: Codable, Equatable, Sendable {
    public struct DailyBucket: Codable, Equatable, Sendable, Identifiable {
        public let day: String
        public let startTime: Date
        public let endTime: Date
        public let costUSD: Double
        public let inputTokens: Int
        public let cacheCreationInputTokens: Int
        public let cacheReadInputTokens: Int
        public let outputTokens: Int
        public let totalTokens: Int
        public let costItems: [CostBreakdown]
        public let models: [ModelBreakdown]

        public var id: String { day }
    }

    public struct CostBreakdown: Codable, Equatable, Sendable, Identifiable {
        public let name: String
        public let costUSD: Double

        public var id: String { name }
    }

    public struct ModelBreakdown: Codable, Equatable, Sendable, Identifiable {
        public let name: String
        public let inputTokens: Int
        public let cacheCreationInputTokens: Int
        public let cacheReadInputTokens: Int
        public let outputTokens: Int
        public let totalTokens: Int

        public var id: String { name }
    }

    public struct Summary: Codable, Equatable, Sendable {
        public let costUSD: Double
        public let inputTokens: Int
        public let cacheCreationInputTokens: Int
        public let cacheReadInputTokens: Int
        public let outputTokens: Int
        public let totalTokens: Int
    }

    public let daily: [DailyBucket]
    public let updatedAt: Date

    public init(daily: [DailyBucket], updatedAt: Date) {
        self.daily = daily.sorted { $0.startTime < $1.startTime }
        self.updatedAt = updatedAt
    }

    public var last30Days: Summary { summary(days: 30) }
    public var last7Days: Summary { summary(days: 7) }
    public var latestDay: Summary { summary(days: 1) }

    public func summary(days: Int) -> Summary {
        let selected = daily.suffix(max(1, days))
        return Summary(
            costUSD: selected.reduce(0) { $0 + $1.costUSD },
            inputTokens: selected.reduce(0) { $0 + $1.inputTokens },
            cacheCreationInputTokens: selected.reduce(0) { $0 + $1.cacheCreationInputTokens },
            cacheReadInputTokens: selected.reduce(0) { $0 + $1.cacheReadInputTokens },
            outputTokens: selected.reduce(0) { $0 + $1.outputTokens },
            totalTokens: selected.reduce(0) { $0 + $1.totalTokens })
    }

    public var topModels: [ModelBreakdown] {
        var totals: [String: ModelAccumulator] = [:]
        for day in daily {
            for model in day.models {
                totals[model.name, default: ModelAccumulator()].add(model)
            }
        }
        return totals
            .map { name, total in total.makeModel(name: name) }
            .sorted {
                if $0.totalTokens == $1.totalTokens { return $0.name < $1.name }
                return $0.totalTokens > $1.totalTokens
            }
    }

    public var topCostItems: [CostBreakdown] {
        var totals: [String: Double] = [:]
        for day in daily {
            for item in day.costItems {
                totals[item.name, default: 0] += item.costUSD
            }
        }
        return totals
            .map { CostBreakdown(name: $0.key, costUSD: $0.value) }
            .sorted {
                if $0.costUSD == $1.costUSD { return $0.name < $1.name }
                return $0.costUSD > $1.costUSD
            }
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let total = last30Days
        return UsageSnapshot(
            providerCost: ProviderCostSnapshot(
                used: total.costUSD,
                limit: 0,
                currencyCode: "USD",
                period: L("过去 30 天")),
            claudeAdminAPIUsage: self,
            planName: "Admin API",
            accountLabel: "Admin API",
            updatedAt: updatedAt)
    }

    private struct ModelAccumulator {
        var inputTokens = 0
        var cacheCreationInputTokens = 0
        var cacheReadInputTokens = 0
        var outputTokens = 0
        var totalTokens = 0

        mutating func add(_ model: ModelBreakdown) {
            inputTokens += model.inputTokens
            cacheCreationInputTokens += model.cacheCreationInputTokens
            cacheReadInputTokens += model.cacheReadInputTokens
            outputTokens += model.outputTokens
            totalTokens += model.totalTokens
        }

        func makeModel(name: String) -> ModelBreakdown {
            ModelBreakdown(
                name: name,
                inputTokens: inputTokens,
                cacheCreationInputTokens: cacheCreationInputTokens,
                cacheReadInputTokens: cacheReadInputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens)
        }
    }
}

public enum ClaudeUsageFetcher {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let adminCostReportURL = URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!
    private static let adminMessagesUsageURL = URL(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
    private static let oauthClientID = "https://claude.ai/oauth/claude-code-client-metadata"
    private static let betaHeader = "oauth-2025-04-20"
    private static let adminAnthropicVersion = "2023-06-01"
    private static let fallbackVersion = "2.1.0"
    private static let webDefaultAPIBaseURL = URL(string: "https://claude.ai/api")!
    private static let webCookieDomains = ["claude.ai"]
    private static let webSessionCookieName = "sessionKey"
    private static let sessionWindowSeconds = 5 * 60 * 60
    private static let weeklyWindowSeconds = 7 * 24 * 60 * 60
    private static let refreshSafetyWindow: TimeInterval = 5 * 60
    private static let adminMaxDailyBuckets = 31
    private static let cliAutoProbeTimeout: TimeInterval = 12
    private static let cliProbeTimeout: TimeInterval = 24
    private static let cliRetryProbeTimeout: TimeInterval = 60

    /// 是否存在 Claude 登录凭证（文件或 Keychain）。Keychain 只查条目存在、不取密钥数据，不弹授权框。
    public static func hasCredentials(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if oauthAccessToken(env: env) != nil { return true }
        if FileManager.default.fileExists(atPath: credentialsFileURL(env: env).path) { return true }
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        userAgentVersion: String? = nil,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        let plan = ClaudeSourcePlanner.resolve(input: planningInput(env: env))
        guard let step = plan.executionStep else {
            throw ClaudeUsageError.noAvailableSource(plan.orderLabel)
        }

        switch step.dataSource {
        case .oauth:
            return try await fetchOAuth(
                env: env,
                userAgentVersion: userAgentVersion,
                session: session)
        case .api:
            return try await fetchAdminAPI(env: env, session: session)
        case .cli:
            return try await fetchDirectCLIUsage(
                env: env,
                timeout: step.inclusionReason == .autoFallbackCLI ? cliAutoProbeTimeout : cliProbeTimeout,
                retryTimeout: cliRetryProbeTimeout)
        case .web, .browser:
            return try await fetchWebUsage(env: env, session: session)
        case .auto:
            throw ClaudeUsageError.noAvailableSource(plan.orderLabel)
        }
    }

    private static func fetchOAuth(
        env: [String: String],
        userAgentVersion: String?,
        session: URLSession) async throws -> UsageSnapshot
    {
        var creds = try loadCredentials(env: env)
        if creds.needsRefresh {
            creds = try await refreshCredentials(creds, env: env, session: session)
        }

        do {
            return try await fetchOnce(
                credentials: creds,
                userAgentVersion: userAgentVersion,
                session: session)
                .withSourceLabel("oauth")
        } catch ClaudeUsageError.unauthorized where creds.canRefresh {
            let refreshed = try await refreshCredentials(creds, env: env, session: session)
            return try await fetchOnce(
                credentials: refreshed,
                userAgentVersion: userAgentVersion,
                session: session)
                .withSourceLabel("oauth")
        }
    }

    static func fetchAdminAPI(
        env: [String: String],
        session: URLSession,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        guard let apiKey = adminAPIKey(env: env) else {
            throw ClaudeUsageError.adminAPIKeyMissing
        }
        return try await fetchAdminAPIUsage(
            apiKey: apiKey,
            session: session,
            now: now)
            .toUsageSnapshot()
            .withSourceLabel("api")
    }

    static func fetchWebUsage(
        env: [String: String],
        session: URLSession,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        let debugLog = ClaudeWebDebugLog.shared
        debugLog.reset(context: "fetch")
        debugLog.updateStatus(L("正在准备 Claude Web 刷新…"))
        let baseURL = webAPIBaseURL(env: env)
        debugLog.append("baseURL=\(baseURL.absoluteString)")
        var resolvedSession = try webSession(env: env, allowCached: true)
        do {
            let snapshot = try await fetchWebUsage(
                baseURL: baseURL,
                webSession: resolvedSession,
                organizationID: webOrganizationID(env: env),
                session: session,
                now: now)
            debugLog.updateStatus(L("Claude Web 快照已更新。"))
            return snapshot.withSourceLabel("web")
        } catch ClaudeUsageError.webSessionMissing where resolvedSession.isCached {
            debugLog.append("cached Claude session was rejected; clearing cookie cache and retrying with fresh browser cookies")
            debugLog.updateStatus(L("缓存的 Claude Cookie 无效，正在重新导入…"))
            CookieHeaderCache.clear(providerID: "claude")
            resolvedSession = try webSession(env: env, allowCached: false)
            do {
                let snapshot = try await fetchWebUsage(
                    baseURL: baseURL,
                    webSession: resolvedSession,
                    organizationID: webOrganizationID(env: env),
                    session: session,
                    now: now)
                debugLog.updateStatus(L("Claude Web 快照已更新。"))
                return snapshot.withSourceLabel("web")
            } catch {
                debugLog.append("Claude Web retry failed: \(error.localizedDescription)")
                debugLog.updateStatus(L("Claude Web 刷新失败：%@", error.localizedDescription))
                throw error
            }
        } catch {
            debugLog.append("Claude Web fetch failed: \(error.localizedDescription)")
            debugLog.updateStatus(L("Claude Web 刷新失败：%@", error.localizedDescription))
            throw error
        }
    }

    private static func fetchWebUsage(
        baseURL: URL,
        webSession: ClaudeWebSession,
        organizationID: String?,
        session: URLSession,
        now: Date) async throws -> UsageSnapshot
    {
        let debugLog = ClaudeWebDebugLog.shared
        debugLog.updateStatus(L("正在读取 Claude 组织…"))
        let organization = try await fetchWebOrganization(
            baseURL: baseURL,
            sessionKey: webSession.sessionKey,
            targetOrganizationID: organizationID,
            session: session)
        debugLog.append("selected Claude organization id=\(organization.id) name=\(organization.name ?? "unknown")")
        debugLog.updateStatus(L("正在读取 Claude Web 用量…"))
        var snapshot = try await fetchWebUsageSnapshot(
            baseURL: baseURL,
            organizationID: organization.id,
            sessionKey: webSession.sessionKey,
            session: session,
            now: now)
        if snapshot.providerCost == nil,
           let cost = await fetchWebOverageSpendLimit(
               baseURL: baseURL,
               organizationID: organization.id,
               sessionKey: webSession.sessionKey,
               session: session)
        {
            debugLog.append("attached Claude Web overage spend limit")
            snapshot.providerCost = cost
        }
        debugLog.updateStatus(L("正在读取 Claude Web 账号…"))
        let account = await fetchWebAccountInfo(
            baseURL: baseURL,
            organizationID: organization.id,
            sessionKey: webSession.sessionKey,
            session: session)
        snapshot.planName = account?.loginMethod
        snapshot.accountLabel = accountLabel(email: account?.email, organization: organization.name)
        snapshot.updatedAt = now
        if let cacheHeader = webSession.cacheHeader {
            debugLog.append("stored Claude cookie cache from \(webSession.sourceLabel)")
            CookieHeaderCache.store(
                providerID: "claude",
                cookieHeader: cacheHeader,
                sourceLabel: webSession.sourceLabel)
        }
        return snapshot
    }

    static func fetchAdminAPIUsage(
        apiKey: String,
        costURL: URL = adminCostReportURL,
        messagesURL: URL = adminMessagesUsageURL,
        session: URLSession = .shared,
        now: Date = Date()) async throws -> ClaudeAdminAPIUsageSnapshot
    {
        let trimmed = cleanedAdminAPIKey(apiKey) ?? ""
        guard !trimmed.isEmpty else {
            throw ClaudeUsageError.adminAPIKeyMissing
        }

        let calendar = adminUTCCalendar
        let range = adminDailyRange(now: now, calendar: calendar)
        let costData = try await fetchAdminAPIData(
            url: adminURL(
                baseURL: costURL,
                range: range,
                queryItems: [URLQueryItem(name: "group_by[]", value: "description")]),
            apiKey: trimmed,
            endpoint: "cost_report",
            session: session)
        let messagesData = try await fetchAdminAPIData(
            url: adminURL(
                baseURL: messagesURL,
                range: range,
                queryItems: [URLQueryItem(name: "group_by[]", value: "model")]),
            apiKey: trimmed,
            endpoint: "messages",
            session: session)
        return try parseAdminAPISnapshot(
            costs: costData,
            messages: messagesData,
            now: now,
            calendar: calendar)
    }

    static func parseAdminAPISnapshot(
        costs: Data,
        messages: Data,
        now: Date,
        calendar: Calendar = adminUTCCalendar) throws -> ClaudeAdminAPIUsageSnapshot
    {
        let costs = try decodeAdminCosts(costs)
        let messages = try decodeAdminMessages(messages)
        return makeAdminAPISnapshot(costs: costs, messages: messages, now: now, calendar: calendar)
    }

    private static func fetchAdminAPIData(
        url: URL,
        apiKey: String,
        endpoint: String,
        session: URLSession) async throws -> Data
    {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(adminAnthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Conductor/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
            data = d
            http = h
        } catch let error as ClaudeUsageError {
            throw error
        } catch {
            throw ClaudeUsageError.network(error.localizedDescription)
        }

        guard http.statusCode == 200 else {
            throw ClaudeUsageError.adminAPIServer(endpoint, http.statusCode)
        }
        return data
    }

    private static func decodeAdminCosts(_ data: Data) throws -> AdminCostReportResponse {
        do {
            return try JSONDecoder().decode(AdminCostReportResponse.self, from: data)
        } catch {
            throw ClaudeUsageError.adminAPIInvalidResponse("cost_report", error.localizedDescription)
        }
    }

    private static func decodeAdminMessages(_ data: Data) throws -> AdminMessagesUsageResponse {
        do {
            return try JSONDecoder().decode(AdminMessagesUsageResponse.self, from: data)
        } catch {
            throw ClaudeUsageError.adminAPIInvalidResponse("messages", error.localizedDescription)
        }
    }

    private static func makeAdminAPISnapshot(
        costs: AdminCostReportResponse,
        messages: AdminMessagesUsageResponse,
        now: Date,
        calendar: Calendar) -> ClaudeAdminAPIUsageSnapshot
    {
        var accumulators: [String: AdminDailyAccumulator] = [:]

        for bucket in costs.data {
            var accumulator = accumulators[bucket.startingAt] ?? AdminDailyAccumulator(
                startingAt: bucket.startingAt,
                endingAt: bucket.endingAt)
            for result in bucket.results {
                let value = usdFromAnthropicLowestUnitAmount(result.amount)
                accumulator.costUSD += value
                let item = displayName(result.description ?? result.costType, fallback: "Claude API")
                accumulator.costItems[item, default: 0] += value
            }
            accumulators[bucket.startingAt] = accumulator
        }

        for bucket in messages.data {
            var accumulator = accumulators[bucket.startingAt] ?? AdminDailyAccumulator(
                startingAt: bucket.startingAt,
                endingAt: bucket.endingAt)
            for result in bucket.results {
                let input = result.uncachedInputTokens ?? 0
                let cacheCreation = result.cacheCreation?.totalInputTokens ?? 0
                let cacheRead = result.cacheReadInputTokens ?? 0
                let output = result.outputTokens ?? 0
                let total = input + cacheCreation + cacheRead + output
                accumulator.inputTokens += input
                accumulator.cacheCreationInputTokens += cacheCreation
                accumulator.cacheReadInputTokens += cacheRead
                accumulator.outputTokens += output
                accumulator.totalTokens += total
                let modelName = displayName(result.model, fallback: "Claude API")
                accumulator.models[modelName, default: AdminModelAccumulator()].add(
                    inputTokens: input,
                    cacheCreationInputTokens: cacheCreation,
                    cacheReadInputTokens: cacheRead,
                    outputTokens: output,
                    totalTokens: total)
            }
            accumulators[bucket.startingAt] = accumulator
        }

        let daily = accumulators.values
            .compactMap { $0.makeBucket(calendar: calendar) }
            .filter { $0.startTime <= now }
            .sorted { $0.startTime < $1.startTime }
        return ClaudeAdminAPIUsageSnapshot(daily: daily, updatedAt: now)
    }

    static func fetchDirectCLIUsage(
        env: [String: String],
        timeout: TimeInterval = cliProbeTimeout,
        retryTimeout: TimeInterval? = cliRetryProbeTimeout) async throws -> UsageSnapshot
    {
        guard let binary = resolvedCLIBinary(env: env) else {
            throw ClaudeUsageError.cliUnavailable
        }
        do {
            return try await fetchDirectCLIUsageOnce(binary: binary, env: env, timeout: timeout)
                .withSourceLabel("cli")
        } catch {
            if error is CancellationError { throw error }
            let initialError = error
            if let retryTimeout, shouldRetryCLIProbe(after: initialError) {
                do {
                    return try await fetchDirectCLIUsageOnce(
                        binary: binary,
                        env: env,
                        timeout: retryTimeout)
                        .withSourceLabel("cli")
                } catch {
                    if error is CancellationError { throw error }
                    if shouldAttemptCLIPTYFallback(after: error) {
                        return try await fetchDirectCLITTYUsageOnce(
                            binary: binary,
                            env: env,
                            timeout: retryTimeout)
                            .withSourceLabel("cli")
                    }
                    throw error
                }
            }
            if shouldAttemptCLIPTYFallback(after: initialError) {
                do {
                    return try await fetchDirectCLITTYUsageOnce(
                        binary: binary,
                        env: env,
                        timeout: retryTimeout ?? timeout)
                        .withSourceLabel("cli")
                } catch {
                    if error is CancellationError { throw error }
                    guard let retryTimeout, shouldRetryCLIProbe(after: error) else { throw error }
                    return try await fetchDirectCLITTYUsageOnce(
                        binary: binary,
                        env: env,
                        timeout: retryTimeout)
                        .withSourceLabel("cli")
                }
            }
            throw initialError
        }
    }

    static func discardDirectCLITTYSessionForTesting(env: [String: String]) async {
        guard let binary = resolvedCLIBinary(env: env) else { return }
        await ClaudeCLIUsagePTYSessionPool.shared.discard(binary: binary, env: env)
    }

    private static func fetchDirectCLIUsageOnce(
        binary: String,
        env: [String: String],
        timeout: TimeInterval) async throws -> UsageSnapshot
    {
        let output = try await runDirectCLIUsage(binary: binary, env: env, timeout: timeout)
        do {
            return try parseCLIUsageOutput(output)
        } catch let error as ClaudeUsageError {
            if case .cliParseFailed = error, outputLooksLikeLoadingUsage(output) {
                throw ClaudeUsageError.cliParseFailed("still loading usage")
            }
            throw error
        }
    }

    private static func fetchDirectCLITTYUsageOnce(
        binary: String,
        env: [String: String],
        timeout: TimeInterval) async throws -> UsageSnapshot
    {
        let output: String
        do {
            output = try await ClaudeCLIUsagePTYSessionPool.shared.fetch(
                binary: binary,
                env: env,
                timeout: timeout)
        } catch {
            output = try await runDirectCLITTYUsage(binary: binary, env: env, timeout: timeout)
        }
        do {
            return try parseCLIUsageOutput(output)
        } catch let error as ClaudeUsageError {
            await ClaudeCLIUsagePTYSessionPool.shared.discard(binary: binary, env: env)
            if case .cliParseFailed = error, outputLooksLikeLoadingUsage(output) {
                throw ClaudeUsageError.cliParseFailed("still loading usage")
            }
            throw error
        }
    }

    static func parseCLIUsageOutput(_ output: String, now: Date = Date()) throws -> UsageSnapshot {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeUsageError.cliParseFailed(L("输出为空")) }
        if let json = try? parseCLIUsageJSON(trimmed, now: now) {
            return json
        }
        return try parseCLIUsageText(trimmed, now: now)
    }

    private static func parseCLIUsageJSON(_ output: String, now: Date) throws -> UsageSnapshot {
        guard let data = output.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ClaudeUsageError.cliParseFailed(String(output.prefix(160))) }

        if let ok = object["ok"] as? Bool, !ok {
            let hint = stringValue(object["hint"]) ?? stringValue(object["pane_preview"]) ?? String(output.prefix(160))
            throw ClaudeUsageError.cliParseFailed(hint)
        }

        func firstWindowDict(_ keys: [String]) -> [String: Any]? {
            for key in keys {
                if let dict = object[key] as? [String: Any] { return dict }
            }
            return nil
        }

        func makeWindow(_ dict: [String: Any]?, title: String, windowMinutes: Int) -> RateWindow? {
            guard let dict else { return nil }
            let pct = doubleValue(dict["pct_used"]) ?? doubleValue(dict["used_percent"]) ?? 0
            let resetText = stringValue(dict["resets"]) ?? stringValue(dict["reset"])
            return RateWindow(
                title: title,
                usedPercent: pct,
                windowMinutes: windowMinutes,
                resetsAt: parseCLIReset(text: resetText, now: now),
                resetDescription: resetText)
        }

        guard let session = makeWindow(
            firstWindowDict(["session_5h", "five_hour", "session"]),
            title: L("会话"),
            windowMinutes: sessionWindowSeconds / 60)
        else {
            throw ClaudeUsageError.cliParseFailed(L("缺少会话用量"))
        }

        let weekly = makeWindow(
            firstWindowDict(["week_all_models", "week_all", "seven_day"]),
            title: L("本周"),
            windowMinutes: weeklyWindowSeconds / 60)
        let modelSpecific = makeWindow(
            firstWindowDict(["week_sonnet", "week_sonnet_only", "week_opus"]),
            title: object["week_opus"] == nil ? L("Sonnet 周") : L("Opus 周"),
            windowMinutes: weeklyWindowSeconds / 60)

        return UsageSnapshot(
            primary: session,
            secondary: weekly,
            tertiary: modelSpecific,
            planName: stringValue(object["plan"])
                ?? stringValue(object["plan_type"])
                ?? stringValue(object["login_method"])
                ?? stringValue(object["loginMethod"]),
            accountLabel: accountLabel(
                email: stringValue(object["account_email"]),
                organization: stringValue(object["account_org"])),
            updatedAt: now)
    }

    private static func parseCLIUsageText(_ output: String, now: Date) throws -> UsageSnapshot {
        let clean = normalizedCLITerminalText(TextParsing.stripANSICodes(output))
        let lines = clean.components(separatedBy: .newlines)
        let sessionLeft = percentLeft(labelCandidates: ["Current session", "session"], lines: lines)
        let weeklyLeft = percentLeft(
            labelCandidates: ["Current week (all models)", "Current week", "week all"],
            lines: lines)
        let sonnetLeft = percentLeft(
            labelCandidates: ["Current week (Sonnet only)", "Current week (Sonnet)", "Current week (Opus)", "Sonnet", "Opus"],
            lines: lines)

        guard let sessionLeft else {
            throw ClaudeUsageError.cliParseFailed(L("缺少 Current session"))
        }

        let sessionReset = resetText(labelCandidates: ["Current session", "session"], lines: lines)
        let weeklyReset = resetText(
            labelCandidates: ["Current week (all models)", "Current week", "week all"],
            lines: lines)
        let sonnetReset = resetText(
            labelCandidates: ["Current week (Sonnet only)", "Current week (Sonnet)", "Current week (Opus)", "Sonnet", "Opus"],
            lines: lines)
        let identity = cliIdentity(from: clean)

        return UsageSnapshot(
            primary: RateWindow(
                title: L("会话"),
                usedPercent: usedPercent(fromLeft: sessionLeft),
                windowMinutes: sessionWindowSeconds / 60,
                resetsAt: parseCLIReset(text: sessionReset, now: now),
                resetDescription: sessionReset),
            secondary: weeklyLeft.map {
                RateWindow(
                    title: L("本周"),
                    usedPercent: usedPercent(fromLeft: $0),
                    windowMinutes: weeklyWindowSeconds / 60,
                    resetsAt: parseCLIReset(text: weeklyReset, now: now),
                    resetDescription: weeklyReset)
            },
            tertiary: sonnetLeft.map {
                RateWindow(
                    title: clean.range(of: "opus", options: .caseInsensitive) == nil ? L("Sonnet 周") : L("Opus 周"),
                    usedPercent: usedPercent(fromLeft: $0),
                    windowMinutes: weeklyWindowSeconds / 60,
                    resetsAt: parseCLIReset(text: sonnetReset, now: now),
                    resetDescription: sonnetReset)
            },
            planName: identity.loginMethod,
            accountLabel: accountLabel(email: identity.email, organization: identity.organization),
            updatedAt: now)
    }

    private static func runDirectCLIUsage(
        binary: String,
        env: [String: String],
        timeout: TimeInterval) async throws -> String
    {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let workingDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("conductor-claude-cli-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workingDirectory) }
            try prepareCLIWorkingDirectory(workingDirectory)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["/usage"]
            process.currentDirectoryURL = workingDirectory
            process.environment = cliEnvironment(base: env, workingDirectory: workingDirectory)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw ClaudeUsageError.cliFailed(-1, error.localizedDescription)
            }

            let deadline = Date().addingTimeInterval(max(1, timeout))
            while process.isRunning, Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(nanoseconds: 200_000_000)
                throw ClaudeUsageError.cliTimedOut
            }

            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw ClaudeUsageError.cliFailed(process.terminationStatus, stderr.isEmpty ? stdout : stderr)
            }
            return stdout.isEmpty ? stderr : stdout
        }.value
    }

    private static func runDirectCLITTYUsage(
        binary: String,
        env: [String: String],
        timeout: TimeInterval) async throws -> String
    {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let workingDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("conductor-claude-cli-pty-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workingDirectory) }
            try prepareCLIWorkingDirectory(workingDirectory)

            do {
                return try TTYCommandRunner().run(
                    binary: binary,
                    send: "/usage",
                    options: TTYCommandRunner.Options(
                        rows: 50,
                        cols: 160,
                        timeout: max(1, timeout),
                        idleTimeout: 1.2,
                        workingDirectory: workingDirectory,
                        baseEnvironment: cliEnvironment(base: env, workingDirectory: workingDirectory),
                        initialDelay: 0.25,
                        settleAfterStop: 0.2)).text
            } catch TTYCommandRunner.Error.binaryNotFound {
                throw ClaudeUsageError.cliUnavailable
            } catch TTYCommandRunner.Error.timedOut {
                throw ClaudeUsageError.cliTimedOut
            } catch {
                throw ClaudeUsageError.cliFailed(-1, error.localizedDescription)
            }
        }.value
    }

    private static func shouldAttemptCLIPTYFallback(after error: Error) -> Bool {
        if error is CancellationError { return false }
        if let cliError = error as? ClaudeUsageError {
            switch cliError {
            case .cliTimedOut, .cliParseFailed:
                return true
            case let .cliFailed(_, message):
                return messageLooksLikeTTYRequired(message) || outputLooksLikeLoadingUsage(message)
            default:
                return false
            }
        }
        return messageLooksLikeTTYRequired(error.localizedDescription)
    }

    private static func shouldRetryCLIProbe(after error: Error) -> Bool {
        let description = "\(String(describing: error)) \(error.localizedDescription)"
        if outputLooksLikeLoadingUsage(description) { return true }
        if let cliError = error as? ClaudeUsageError {
            switch cliError {
            case .cliTimedOut:
                return true
            case let .cliParseFailed(message):
                return outputLooksLikeLoadingUsage(message)
            default:
                return false
            }
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("timed out")
            || message.contains("timeout")
            || outputLooksLikeLoadingUsage(message)
    }

    private static func outputLooksLikeLoadingUsage(_ output: String) -> Bool {
        let lower = TextParsing.stripANSICodes(output).lowercased()
        return lower.contains("still loading usage")
            || lower.contains("loading usage data")
            || lower.contains("could not load usage data")
    }

    private static func messageLooksLikeTTYRequired(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("tty")
            || lower.contains("terminal")
            || lower.contains("raw mode")
            || lower.contains("not a terminal")
            || lower.contains("interactive")
    }

    private static func prepareCLIWorkingDirectory(_ directory: URL) throws {
        let claudeDirectory = directory.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        let settingsURL = claudeDirectory.appendingPathComponent("settings.local.json")
        let settings: [String: String] = ["disableDeepLinkRegistration": "disable"]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func cliEnvironment(base: [String: String], workingDirectory: URL) -> [String: String] {
        var environment = base
        environment["PWD"] = workingDirectory.path
        if environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["PATH"] = defaultExecutableSearchPath
        }
        if environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        }
        if environment["TERM"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["TERM"] = "xterm-256color"
        }
        if environment["LANG"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            environment["LANG"] = "en_US.UTF-8"
        }
        for key in environment.keys where key.hasPrefix("ANTHROPIC_") {
            environment.removeValue(forKey: key)
        }
        return environment
    }

    static func planningInput(env: [String: String]) -> ClaudeSourcePlanningInput {
        ClaudeSourcePlanningInput(
            selectedDataSource: selectedDataSource(env: env),
            hasAdminAPIKey: adminAPIKey(env: env) != nil,
            hasWebSession: hasWebSession(env: env),
            hasCLI: hasCLI(env: env),
            hasOAuthCredentials: hasCredentials(env: env))
    }

    private static func selectedDataSource(env: [String: String]) -> ClaudeUsageDataSource {
        guard let raw = UsageProviderRuntimeConfig.sourceMode(providerID: "claude", env: env),
              let source = ClaudeUsageDataSource(rawValue: raw)
        else { return .auto }
        return source
    }

    private static func adminAPIKey(env: [String: String]) -> String? {
        for key in ["ANTHROPIC_ADMIN_KEY", "ANTHROPIC_ADMIN_API_KEY"] {
            if let value = cleanedAdminAPIKey(env[key]) { return value }
        }
        return nil
    }

    private static func cleanedAdminAPIKey(_ raw: String?) -> String? {
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

    private static func resolvedCLIBinary(env: [String: String]) -> String? {
        if let override = env["CLAUDE_CLI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           FileManager.default.isExecutableFile(atPath: override)
        {
            return override
        }
        let rawPath = env["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? defaultExecutableSearchPath
        for directory in rawPath.split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent("claude").path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    private static func hasWebSession(env: [String: String]) -> Bool {
        if (try? directWebSessionKey(env: env)) != nil { return true }
        if let manual = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "claude", env: env),
           webSessionKey(fromCookieHeader: manual) != nil
        {
            return true
        }
        return cachedWebSession() != nil
    }

    private static func hasCLI(env: [String: String]) -> Bool {
        resolvedCLIBinary(env: env) != nil
    }

    private static let defaultExecutableSearchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    private static func webAPIBaseURL(env: [String: String]) -> URL {
        for key in ["CONDUCTOR_USAGE_CLAUDE_WEB_API_BASE_URL", "CONDUCTOR_CLAUDE_WEB_API_BASE_URL"] {
            guard let raw = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { continue }
            return UsageEndpointPolicy.trustedHTTPSURL(
                from: raw,
                default: webDefaultAPIBaseURL,
                allowedHosts: ["claude.ai"])
        }
        return webDefaultAPIBaseURL
    }

    private static func webOrganizationID(env: [String: String]) -> String? {
        for key in ["CONDUCTOR_USAGE_CLAUDE_ORGANIZATION_ID", "CLAUDE_ORGANIZATION_ID", "ANTHROPIC_ORGANIZATION_ID"] {
            guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func webSession(env: [String: String], allowCached: Bool) throws -> ClaudeWebSession {
        let debugLog = ClaudeWebDebugLog.shared
        debugLog.updateStatus(L("正在选择 Claude Web sessionKey…"))
        if let rawSession = try directWebSessionKey(env: env) {
            debugLog.append("selected direct Claude sessionKey")
            debugLog.updateStatus(L("正在使用直接 Claude sessionKey。"))
            return ClaudeWebSession(
                sessionKey: rawSession,
                sourceLabel: "Direct",
                cacheHeader: nil,
                isCached: false)
        }
        if let manual = UsageProviderRuntimeConfig.manualCookieHeader(providerID: "claude", env: env) {
            guard let sessionKey = webSessionKey(fromCookieHeader: manual) else {
                debugLog.append("manual Claude cookie did not contain a valid sessionKey")
                debugLog.updateStatus(L("手动 Claude Cookie 无效。"))
                throw ClaudeUsageError.webInvalidSessionKey
            }
            debugLog.append("selected manual Claude cookie")
            debugLog.updateStatus(L("正在使用手动 Claude Cookie。"))
            return ClaudeWebSession(
                sessionKey: sessionKey,
                sourceLabel: "Manual",
                cacheHeader: nil,
                isCached: false)
        }
        if allowCached, let cached = cachedWebSession() {
            debugLog.append("selected cached Claude cookie source=\(cached.sourceLabel)")
            debugLog.updateStatus(L("正在使用缓存的 Claude Cookie。"))
            return cached
        }
        guard UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "claude", env: env),
              let webSession = webSessionFromBrowser(env: env)
        else {
            debugLog.append("Claude browser cookie selection failed or is disabled")
            debugLog.updateStatus(L("Claude Cookie 导入失败。"))
            throw ClaudeUsageError.webSessionMissing
        }
        return webSession
    }

    private static func directWebSessionKey(env: [String: String]) throws -> String? {
        for key in ["CONDUCTOR_USAGE_CLAUDE_SESSION_KEY", "CLAUDE_SESSION_KEY"] {
            guard let value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            guard isValidWebSessionKey(value) else {
                ClaudeWebDebugLog.shared.append("direct Claude sessionKey from \(key) is invalid")
                ClaudeWebDebugLog.shared.updateStatus(L("Claude sessionKey 无效。"))
                throw ClaudeUsageError.webInvalidSessionKey
            }
            return value
        }
        return nil
    }

    private static func webSessionKey(fromCookieHeader header: String) -> String? {
        for pair in CookieHeaderNormalizer.pairs(from: header) where pair.name == webSessionCookieName {
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidWebSessionKey(value) { return value }
        }
        return nil
    }

    private static func cachedWebSession() -> ClaudeWebSession? {
        guard let entry = CookieHeaderCache.load(providerID: "claude"),
              let sessionKey = webSessionKey(fromCookieHeader: entry.cookieHeader)
        else { return nil }
        return ClaudeWebSession(
            sessionKey: sessionKey,
            sourceLabel: entry.sourceLabel,
            cacheHeader: nil,
            isCached: true)
    }

    private static func webSessionFromBrowser(env: [String: String]) -> ClaudeWebSession? {
        _ = env
        let debugLog = ClaudeWebDebugLog.shared
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: webCookieDomains)
        for browser in Browser.defaultImportOrder {
            guard BrowserCookieAccessGate.shouldAttempt(browser) else {
                debugLog.append("skipped \(browser.displayName) due to cookie access cooldown")
                continue
            }
            debugLog.updateStatus(L("正在读取 %@ 的 Claude Cookie…", browser.displayName))
            let cookies: [HTTPCookie]
            do {
                cookies = try BrowserCookieAccessGate.cookies(client: client, matching: query, in: browser)
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                debugLog.append("failed reading \(browser.displayName) Claude cookies: \(error.localizedDescription)")
                continue
            }
            guard !cookies.isEmpty else {
                debugLog.append("\(browser.displayName) returned no Claude cookies")
                continue
            }
            let pairs = cookies.map { (name: $0.name, value: $0.value) }
            if let sessionKey = webSessionKey(fromCookiePairs: pairs) {
                debugLog.append("selected Claude cookie from \(browser.displayName)")
                debugLog.updateStatus(L("正在使用 %@ 的 Claude Cookie。", browser.displayName))
                return ClaudeWebSession(
                    sessionKey: sessionKey,
                    sourceLabel: browser.displayName,
                    cacheHeader: "\(webSessionCookieName)=\(sessionKey)",
                    isCached: false)
            }
            debugLog.append("\(browser.displayName) Claude cookies did not include a valid sessionKey")
        }
        return nil
    }

    private static func webSessionKey(fromCookiePairs pairs: [(name: String, value: String)]) -> String? {
        for pair in pairs where pair.name == webSessionCookieName {
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidWebSessionKey(value) { return value }
        }
        return nil
    }

    private static func isValidWebSessionKey(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("sk-ant-")
    }

    private static func fetchWebOrganization(
        baseURL: URL,
        sessionKey: String,
        targetOrganizationID: String?,
        session: URLSession) async throws -> ClaudeWebOrganization
    {
        let data = try await fetchWebData(
            baseURL: baseURL,
            path: ["organizations"],
            endpoint: "organizations",
            sessionKey: sessionKey,
            session: session)
        guard let organizations = try? JSONDecoder().decode([ClaudeWebOrganizationResponse].self, from: data) else {
            throw ClaudeUsageError.webInvalidResponse("organizations")
        }
        if let targetOrganizationID = targetOrganizationID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !targetOrganizationID.isEmpty
        {
            guard let selected = organizations.first(where: { $0.uuid == targetOrganizationID }) else {
                throw ClaudeUsageError.webOrganizationNotFound(targetOrganizationID)
            }
            return selected.organization
        }
        guard let selected = organizations.first(where: \.hasChatCapability)
            ?? organizations.first(where: { !$0.isAPIOnly })
            ?? organizations.first
        else {
            throw ClaudeUsageError.webOrganizationMissing
        }
        return selected.organization
    }

    private static func fetchWebUsageSnapshot(
        baseURL: URL,
        organizationID: String,
        sessionKey: String,
        session: URLSession,
        now: Date) async throws -> UsageSnapshot
    {
        let data = try await fetchWebData(
            baseURL: baseURL,
            path: ["organizations", organizationID, "usage"],
            endpoint: "usage",
            sessionKey: sessionKey,
            session: session)
        return try parseWebUsageResponse(data, now: now)
    }

    private static func fetchWebOverageSpendLimit(
        baseURL: URL,
        organizationID: String,
        sessionKey: String,
        session: URLSession) async -> ProviderCostSnapshot?
    {
        guard let data = try? await fetchWebData(
            baseURL: baseURL,
            path: ["organizations", organizationID, "overage_spend_limit"],
            endpoint: "overage_spend_limit",
            sessionKey: sessionKey,
            session: session)
        else { return nil }
        return parseWebOverageSpendLimit(data)
    }

    private static func fetchWebAccountInfo(
        baseURL: URL,
        organizationID: String,
        sessionKey: String,
        session: URLSession) async -> ClaudeWebAccountInfo?
    {
        guard let data = try? await fetchWebData(
            baseURL: baseURL,
            path: ["account"],
            endpoint: "account",
            sessionKey: sessionKey,
            session: session)
        else { return nil }
        return parseWebAccountInfo(data, organizationID: organizationID)
    }

    private static func fetchWebData(
        baseURL: URL,
        path: [String],
        endpoint: String,
        sessionKey: String,
        session: URLSession) async throws -> Data
    {
        var url = baseURL
        for component in path {
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("\(webSessionCookieName)=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Conductor/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else {
                throw ClaudeUsageError.webInvalidResponse(endpoint)
            }
            data = d
            http = h
        } catch let error as ClaudeUsageError {
            throw error
        } catch {
            throw ClaudeUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw ClaudeUsageError.webSessionMissing
        default:
            throw ClaudeUsageError.webServer(endpoint, http.statusCode)
        }
    }

    private static func fetchOnce(
        credentials creds: Credentials,
        userAgentVersion: String?,
        session: URLSession) async throws -> UsageSnapshot
    {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        let version = userAgentVersion ?? fallbackVersion
        request.setValue("claude-code/\(version)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
            data = d
            http = h
        } catch let error as ClaudeUsageError {
            throw error
        } catch {
            throw ClaudeUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try parse(data, planType: creds.subscriptionType)
            } catch {
                throw ClaudeUsageError.invalidResponse
            }
        case 401, 403:
            throw ClaudeUsageError.unauthorized
        default:
            throw ClaudeUsageError.server(http.statusCode)
        }
    }

    // MARK: - 凭证

    struct Credentials {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let subscriptionType: String?
        let source: CredentialSource

        var canRefresh: Bool {
            let token = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !token.isEmpty
        }

        var needsRefresh: Bool {
            guard canRefresh, let expiresAt else { return false }
            return Date().addingTimeInterval(refreshSafetyWindow) >= expiresAt
        }
    }

    enum CredentialSource {
        case environment
        case file(URL)
        case keychain
    }

    static func credentialsFileURL(env: [String: String]) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let configDir = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configDir.isEmpty
        {
            return URL(fileURLWithPath: configDir).appendingPathComponent(".credentials.json")
        }
        return home.appendingPathComponent(".claude").appendingPathComponent(".credentials.json")
    }

    static func loadCredentials(env: [String: String]) throws -> Credentials {
        if let token = oauthAccessToken(env: env) {
            return Credentials(
                accessToken: token,
                refreshToken: nil,
                expiresAt: nil,
                subscriptionType: stringValue(env["CONDUCTOR_USAGE_CLAUDE_SUBSCRIPTION_TYPE"]),
                source: .environment)
        }
        // 1) 凭证文件（多数 Linux / 部分 macOS 安装）
        let fileURL = credentialsFileURL(env: env)
        if let data = try? Data(contentsOf: fileURL),
           let creds = parseCredentials(data, source: .file(fileURL))
        {
            return creds
        }
        if shouldAvoidKeychain(env: env) {
            throw ClaudeUsageError.notLoggedIn
        }
        // 2) macOS Keychain（Claude Code 默认存这里）。读取他人 keychain 项可能弹一次授权框。
        #if canImport(Security)
        if let data = keychainCredentialData(), let creds = parseCredentials(data, source: .keychain) {
            return creds
        }
        #endif
        throw ClaudeUsageError.notLoggedIn
    }

    static func shouldAvoidKeychain(env: [String: String]) -> Bool {
        let raw = env["CONDUCTOR_CLAUDE_AVOID_KEYCHAIN"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return raw == "1" || raw == "true" || raw == "yes"
    }

    /// 解析 `{ "claudeAiOauth": { "accessToken": ..., "subscriptionType": ... } }`。
    static func parseCredentials(_ data: Data, source: CredentialSource = .keychain) -> Credentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any]
        else { return nil }
        let token = (oauth["accessToken"] as? String) ?? (oauth["access_token"] as? String)
        guard let accessToken = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty
        else { return nil }
        let refreshToken = stringValue(oauth["refreshToken"]) ?? stringValue(oauth["refresh_token"])
        let expiresAt = parseCredentialExpiry(from: oauth)
        let sub = (oauth["subscriptionType"] as? String) ?? (oauth["subscription_type"] as? String)
        return Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: sub,
            source: source)
    }

    private static func refreshCredentials(
        _ credentials: Credentials,
        env: [String: String],
        session: URLSession) async throws -> Credentials
    {
        guard let refreshToken = credentials.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty
        else { return credentials }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded([
            "client_id": env["CONDUCTOR_CLAUDE_OAUTH_CLIENT_ID"] ?? oauthClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        let data: Data
        let http: HTTPURLResponse
        do {
            let (d, response) = try await session.data(for: request)
            guard let h = response as? HTTPURLResponse else { throw ClaudeUsageError.invalidResponse }
            data = d
            http = h
        } catch let error as ClaudeUsageError {
            throw error
        } catch {
            throw ClaudeUsageError.network(error.localizedDescription)
        }

        guard http.statusCode == 200 else {
            throw refreshFailureError(statusCode: http.statusCode, data: data)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.refreshInvalidResponse(L("响应不是有效 JSON"))
        }

        guard let accessToken = stringValue(json["access_token"]) ?? stringValue(json["accessToken"]) else {
            throw ClaudeUsageError.refreshInvalidResponse(L("缺少 access_token"))
        }
        let refreshed = Credentials(
            accessToken: accessToken,
            refreshToken: stringValue(json["refresh_token"]) ?? stringValue(json["refreshToken"]) ?? credentials.refreshToken,
            expiresAt: refreshExpiry(from: json),
            subscriptionType: stringValue(json["subscription_type"])
                ?? stringValue(json["subscriptionType"])
                ?? credentials.subscriptionType,
            source: credentials.source)
        try saveCredentials(refreshed)
        return refreshed
    }

    private static func saveCredentials(_ credentials: Credentials) throws {
        guard case let .file(url) = credentials.source else { return }
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            json = existing
        }

        var oauth = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
        setCredentialField(&oauth, camelKey: "accessToken", snakeKey: "access_token", value: credentials.accessToken)
        if let refreshToken = credentials.refreshToken, !refreshToken.isEmpty {
            setCredentialField(&oauth, camelKey: "refreshToken", snakeKey: "refresh_token", value: refreshToken)
        }
        if let expiresAt = credentials.expiresAt {
            setCredentialExpiry(&oauth, expiresAt: expiresAt)
        }
        if let subscriptionType = credentials.subscriptionType, !subscriptionType.isEmpty {
            setCredentialField(&oauth, camelKey: "subscriptionType", snakeKey: "subscription_type", value: subscriptionType)
        }
        json["claudeAiOauth"] = oauth

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func refreshFailureError(statusCode: Int, data: Data) -> ClaudeUsageError {
        if let errorCode = refreshErrorCode(from: data)?.lowercased() {
            switch errorCode {
            case "invalid_grant", "invalid_refresh_token", "refresh_token_invalidated":
                return .refreshRevoked
            case "expired_refresh_token", "refresh_token_expired":
                return .refreshExpired
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
           let code = stringValue(error["code"])
        {
            return code
        }
        return stringValue(json["error"]) ?? stringValue(json["error_code"])
    }

    private static func refreshExpiry(from json: [String: Any]) -> Date? {
        parseDateValue(json["expires_at"])
            ?? parseDateValue(json["expiresAt"])
            ?? parseDateValue(json["expiry"])
            ?? parseDateValue(json["expiration_time"])
            ?? expiresInDate(json["expires_in"])
    }

    private static func parseCredentialExpiry(from oauth: [String: Any]) -> Date? {
        parseDateValue(oauth["expiresAt"])
            ?? parseDateValue(oauth["expires_at"])
            ?? parseDateValue(oauth["expiry"])
            ?? parseDateValue(oauth["expiration_time"])
            ?? expiresInDate(oauth["expiresIn"])
            ?? expiresInDate(oauth["expires_in"])
    }

    private static func expiresInDate(_ raw: Any?) -> Date? {
        guard let seconds = doubleValue(raw), seconds > 0 else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private static func parseDateValue(_ raw: Any?) -> Date? {
        if let date = raw as? Date { return date }
        if let timestamp = doubleValue(raw) {
            if timestamp > 100_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1_000)
            }
            if timestamp > 1_000_000_000 {
                return Date(timeIntervalSince1970: timestamp)
            }
        }
        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let numeric = Double(trimmed) {
                return parseDateValue(numeric)
            }
            return parseISO8601(trimmed)
        }
        return nil
    }

    private static func setCredentialField(
        _ oauth: inout [String: Any],
        camelKey: String,
        snakeKey: String,
        value: String)
    {
        if oauth[snakeKey] != nil {
            oauth[snakeKey] = value
        } else {
            oauth[camelKey] = value
        }
    }

    private static func setCredentialExpiry(_ oauth: inout [String: Any], expiresAt: Date) {
        let keys = ["expiresAt", "expires_at", "expiry", "expiration_time"]
        if let existingKey = keys.first(where: { oauth[$0] != nil }) {
            if let number = doubleValue(oauth[existingKey]) {
                oauth[existingKey] = number > 100_000_000_000
                    ? expiresAt.timeIntervalSince1970 * 1_000
                    : expiresAt.timeIntervalSince1970
            } else {
                oauth[existingKey] = ISO8601DateFormatter().string(from: expiresAt)
            }
        } else {
            oauth["expiresAt"] = ISO8601DateFormatter().string(from: expiresAt)
        }
    }

    private static func formURLEncoded(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in "\(urlFormEncode(key))=\(urlFormEncode(value))" }
            .sorted()
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func oauthAccessToken(env: [String: String]) -> String? {
        for key in ["CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN", "CLAUDE_OAUTH_ACCESS_TOKEN"] {
            guard var value = env[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            if value.lowercased().hasPrefix("bearer ") {
                value = value.dropFirst("bearer ".count).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if value.lowercased().hasPrefix("sk-ant-oat") { return value }
        }
        return nil
    }

    private static func urlFormEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func stringValue(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    #if canImport(Security)
    private static func keychainCredentialData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }
    #endif

    // MARK: - 解析

    static func parseWebUsageResponse(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.webInvalidResponse("usage")
        }

        let session = webWindow(
            from: json["five_hour"] as? [String: Any],
            title: L("会话"),
            windowSeconds: sessionWindowSeconds)
            ?? RateWindow(
                title: L("会话"),
                usedPercent: 0,
                windowMinutes: sessionWindowSeconds / 60)
        let weekly = webWindow(
            from: json["seven_day"] as? [String: Any],
            title: L("本周"),
            windowSeconds: weeklyWindowSeconds)
        let modelSpecificDict = json["seven_day_sonnet"] as? [String: Any]
        let isOpus = modelSpecificDict == nil
        let modelSpecific = webWindow(
            from: modelSpecificDict ?? (json["seven_day_opus"] as? [String: Any]),
            title: isOpus ? L("Opus 周") : L("Sonnet 周"),
            windowSeconds: weeklyWindowSeconds)

        var extras: [NamedRateWindow] = []
        if let routines = firstWebUsageWindow(
            in: json,
            keys: [
                "seven_day_routines",
                "seven_day_claude_routines",
                "claude_routines",
                "routines",
                "routine",
                "seven_day_cowork",
                "cowork",
            ]),
            let window = webWindow(
                from: routines,
                title: L("Daily Routines"),
                windowSeconds: weeklyWindowSeconds)
        {
            extras.append(NamedRateWindow(id: "claude-routines", title: L("Daily Routines"), window: window))
        } else if hasAnyWebUsageKey(
            in: json,
            keys: [
                "seven_day_routines",
                "seven_day_claude_routines",
                "claude_routines",
                "routines",
                "routine",
                "seven_day_cowork",
                "cowork",
            ])
        {
            extras.append(NamedRateWindow(
                id: "claude-routines",
                title: L("Daily Routines"),
                window: RateWindow(
                    title: L("Daily Routines"),
                    usedPercent: 0,
                    windowMinutes: weeklyWindowSeconds / 60)))
        }

        return UsageSnapshot(
            primary: session,
            secondary: weekly,
            tertiary: modelSpecific,
            extraRateWindows: extras,
            providerCost: extraUsageCost(json["extra_usage"] as? [String: Any]),
            updatedAt: now)
    }

    private static func webWindow(
        from dict: [String: Any]?,
        title: String,
        windowSeconds: Int) -> RateWindow?
    {
        guard let dict, let utilization = doubleValue(dict["utilization"]) else { return nil }
        return RateWindow(
            title: title,
            usedPercent: utilization,
            windowMinutes: windowSeconds / 60,
            resetsAt: parseISO8601(dict["resets_at"] as? String))
    }

    private static func firstWebUsageWindow(in json: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let window = json[key] as? [String: Any] { return window }
        }
        return nil
    }

    private static func hasAnyWebUsageKey(in json: [String: Any], keys: [String]) -> Bool {
        keys.contains { json.keys.contains($0) }
    }

    private static func parseWebOverageSpendLimit(_ data: Data) -> ProviderCostSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["is_enabled"] as? Bool) == true
        else { return nil }
        return extraUsageCost(json)
    }

    private static func parseWebAccountInfo(_ data: Data, organizationID: String?) -> ClaudeWebAccountInfo? {
        guard let response = try? JSONDecoder().decode(ClaudeWebAccountResponse.self, from: data) else {
            return nil
        }
        let email = response.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let membership = selectedWebMembership(response.memberships, organizationID: organizationID)
        let loginMethod = claudeWebLoginMethod(
            rateLimitTier: membership?.organization.rateLimitTier,
            billingType: membership?.organization.billingType)
        return ClaudeWebAccountInfo(
            email: email?.isEmpty == false ? email : nil,
            loginMethod: loginMethod)
    }

    private static func selectedWebMembership(
        _ memberships: [ClaudeWebAccountResponse.Membership]?,
        organizationID: String?) -> ClaudeWebAccountResponse.Membership?
    {
        guard let memberships, !memberships.isEmpty else { return nil }
        if let organizationID {
            if let match = memberships.first(where: { $0.organization.uuid == organizationID }) { return match }
        }
        return memberships.first
    }

    private static func claudeWebLoginMethod(rateLimitTier: String?, billingType: String?) -> String? {
        let tier = rateLimitTier?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let billing = billingType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if tier.contains("max") { return "Claude Max" }
        if tier.contains("pro") { return "Claude Pro" }
        if tier.contains("team") { return "Claude Team" }
        if tier.contains("enterprise") { return "Claude Enterprise" }
        if tier.contains("ultra") { return "Claude Ultra" }
        if billing.contains("stripe"), tier.contains("claude") { return "Claude Pro" }
        return nil
    }

    static func parse(_ data: Data, planType: String?) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeUsageError.invalidResponse
        }

        // 取窗口字典：按 CodexBar 的多键回退顺序找第一个存在的键。
        func firstDict(_ keys: [String]) -> [String: Any]? {
            for key in keys {
                if let dict = json[key] as? [String: Any] { return dict }
            }
            return nil
        }

        // 5 小时会话窗（primary）。CodexBar 在缺 five_hour 时会回退到各 7 天窗，
        // 但 conductor 这里以 session→primary、seven_day→secondary 的位置语义为准，
        // 故 primary 仅取 five_hour。
        let session = window(
            from: json["five_hour"] as? [String: Any],
            title: L("会话"),
            windowSeconds: sessionWindowSeconds)
        // 每周全模型窗（secondary）。
        let weekly = window(
            from: json["seven_day"] as? [String: Any],
            title: L("本周"),
            windowSeconds: weeklyWindowSeconds)
        // 模型专属周窗（tertiary）：Sonnet 优先，其次 Opus。
        let modelSpecificDict = (json["seven_day_sonnet"] as? [String: Any])
        let isOpus = modelSpecificDict == nil
        let modelSpecific = window(
            from: modelSpecificDict ?? (json["seven_day_opus"] as? [String: Any]),
            title: isOpus ? L("Opus 周") : L("Sonnet 周"),
            windowSeconds: weeklyWindowSeconds)

        // 附加命名窗口（Daily Routines 等）。
        let routinesDict = firstDict([
            "seven_day_routines",
            "seven_day_claude_routines",
            "claude_routines",
            "routines",
            "routine",
            "seven_day_cowork",
            "cowork",
        ])
        var extras: [NamedRateWindow] = []
        if let routines = routinesDict, let w = window(
            from: routines,
            title: L("Daily Routines"),
            windowSeconds: weeklyWindowSeconds)
        {
            extras.append(NamedRateWindow(id: "claude-routines", title: L("Daily Routines"), window: w))
        }

        // 额外用量（extra_usage）→ providerCost（月度消费 vs 上限，单位为分，需除以 100）。
        let providerCost = extraUsageCost(json["extra_usage"] as? [String: Any])

        // 至少要有一个时间窗或消费数据才算有效，否则视为接口异常。
        guard session != nil || weekly != nil || modelSpecific != nil
            || !extras.isEmpty || providerCost != nil
        else { throw ClaudeUsageError.invalidResponse }

        return UsageSnapshot(
            primary: session,
            secondary: weekly,
            tertiary: modelSpecific,
            extraRateWindows: extras,
            providerCost: providerCost,
            planName: planType)
    }

    private static func window(
        from dict: [String: Any]?,
        title: String,
        windowSeconds: Int) -> RateWindow?
    {
        guard let dict, let utilization = doubleValue(dict["utilization"]) else { return nil }
        let resetAt = parseISO8601(dict["resets_at"] as? String)
            ?? Date().addingTimeInterval(TimeInterval(windowSeconds))
        return RateWindow(
            title: title,
            usedPercent: utilization,
            windowMinutes: windowSeconds / 60,
            resetsAt: resetAt)
    }

    /// 解析 `extra_usage`：启用且有 `used_credits` / `monthly_limit` 时，
    /// 产出月度消费快照。OAuth 接口的金额是「分」，统一除以 100 转成主单位（美元）。
    private static func extraUsageCost(_ dict: [String: Any]?) -> ProviderCostSnapshot? {
        guard let dict,
              (dict["is_enabled"] as? Bool) != false,
              let usedCents = doubleValue(dict["used_credits"]),
              let limitCents = doubleValue(dict["monthly_limit"] ?? dict["monthly_credit_limit"]),
              limitCents > 0
        else { return nil }
        let rawCurrency = (dict["currency"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = (rawCurrency?.isEmpty ?? true) ? "USD" : rawCurrency!
        return ProviderCostSnapshot(
            used: usedCents / 100.0,
            limit: limitCents / 100.0,
            currencyCode: currency,
            period: L("本月"))
    }

    static func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let i = raw as? Int { return Double(i) }
        if let s = raw as? String { return Double(s) }
        return nil
    }

    private static func displayName(_ raw: String?, fallback: String) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return fallback
        }
        return trimmed
    }

    private static func accountLabel(email: String?, organization: String?) -> String? {
        let parts = [email, organization].compactMap {
            let trimmed = $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func usedPercent(fromLeft left: Double) -> Double {
        max(0, min(100, 100 - left))
    }

    private static func percentLeft(labelCandidates: [String], lines: [String]) -> Double? {
        for candidate in labelCandidates {
            if let value = firstPercentNearLabel(candidate, lines: lines) {
                return value
            }
        }
        return nil
    }

    private static func firstPercentNearLabel(_ label: String, lines: [String]) -> Double? {
        let normalizedLabel = normalizedLabelText(label)
        for index in lines.indices {
            guard normalizedLabelText(lines[index]).contains(normalizedLabel) else { continue }
            let sliceEnd = min(lines.endIndex, index + 3)
            let text = lines[index..<sliceEnd].joined(separator: " ")
            if let left = firstPercentValue(text, leftOnly: true) ?? firstPercentValue(text, leftOnly: false) {
                return left
            }
        }
        return nil
    }

    private static func resetText(labelCandidates: [String], lines: [String]) -> String? {
        for candidate in labelCandidates {
            let normalizedLabel = normalizedLabelText(candidate)
            for index in lines.indices {
                guard normalizedLabelText(lines[index]).contains(normalizedLabel) else { continue }
                if let reset = firstResetText(lines[index]) { return reset }
                let sliceEnd = min(lines.endIndex, index + 3)
                let text = lines[index..<sliceEnd].joined(separator: "\n")
                if let reset = firstResetText(text) { return reset }
            }
        }
        return nil
    }

    private static func firstPercentValue(_ text: String, leftOnly: Bool) -> Double? {
        let pattern = leftOnly
            ? #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%\s*(?:left|remaining)"#
            : #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Double(text[valueRange])
    }

    private static func firstResetText(_ text: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"resets?\s+([^|•\n\r]+)"#,
            options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let resetRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[resetRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedLabelText(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func normalizedCLITerminalText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func cliIdentity(from text: String) -> (email: String?, organization: String?, loginMethod: String?) {
        (
            email: firstRegexCapture(#"([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})"#, in: text),
            organization: firstRegexCapture(#"(?i)(?:organization|org)\s*[:：]\s*([^\n\r]+)"#, in: text),
            loginMethod: firstRegexCapture(#"(?i)(?:login method|auth method|method)\s*[:：]\s*([^\n\r]+)"#, in: text)
        )
    }

    private static func firstRegexCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let value = text[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func parseCLIReset(text: String?, now: Date) -> Date? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let iso = parseISO8601(trimmed) { return iso }
        if let relative = parseCLIRelativeReset(trimmed, now: now) { return relative }
        if let monthDay = parseCLIMonthDayReset(trimmed, now: now) { return monthDay }
        return parseCLITimeOnlyReset(trimmed, now: now)
    }

    private static func parseCLIRelativeReset(_ text: String, now: Date) -> Date? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*(today|tomorrow)\s+at\s+(.+?)\s*$"#,
            options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 2,
              let dayRange = Range(match.range(at: 1), in: text),
              let timeRange = Range(match.range(at: 2), in: text),
              let parsedTime = parseCLITime(String(text[timeRange]))
        else { return nil }
        let dayOffset = String(text[dayRange]).lowercased() == "tomorrow" ? 1 : 0
        return alignCLIReset(
            parsedTime,
            baseDayOffset: dayOffset,
            shouldAdvancePastTimes: false,
            now: now)
    }

    private static func parseCLIMonthDayReset(_ text: String, now: Date) -> Date? {
        let formats = [
            "MMM d 'at' ha",
            "MMM d 'at' h:mma",
            "MMM d, ha",
            "MMM d, h:mma",
            "MMM d ha",
            "MMM d h:mma",
        ]
        for format in formats {
            guard let parsed = parseCLIDate(text, format: format) else { continue }
            let calendar = Calendar.current
            let parsedComponents = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: parsed)
            let nowYear = calendar.component(.year, from: now)
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            components.year = nowYear
            components.month = parsedComponents.month
            components.day = parsedComponents.day
            components.hour = parsedComponents.hour
            components.minute = parsedComponents.minute
            components.second = parsedComponents.second ?? 0
            guard var candidate = calendar.date(from: components) else { continue }
            if candidate < now.addingTimeInterval(-12 * 60 * 60),
               let nextYear = calendar.date(byAdding: .year, value: 1, to: candidate)
            {
                candidate = nextYear
            }
            return candidate
        }
        return nil
    }

    private static func parseCLITimeOnlyReset(_ text: String, now: Date) -> Date? {
        guard let parsed = parseCLITime(text) else { return nil }
        return alignCLIReset(
            parsed,
            baseDayOffset: 0,
            shouldAdvancePastTimes: true,
            now: now)
    }

    private static func parseCLITime(_ text: String) -> Date? {
        parseCLIDate(text.trimmingCharacters(in: .whitespacesAndNewlines), format: "ha")
            ?? parseCLIDate(text.trimmingCharacters(in: .whitespacesAndNewlines), format: "h:mma")
    }

    private static func parseCLIDate(_ text: String, format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = format
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func alignCLIReset(
        _ parsed: Date,
        baseDayOffset: Int,
        shouldAdvancePastTimes: Bool,
        now: Date) -> Date
    {
        let calendar = Calendar.current
        let baseDay = calendar.date(byAdding: .day, value: baseDayOffset, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)
        let components = calendar.dateComponents([.hour, .minute, .second], from: parsed)
        var candidate = calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: baseDay) ?? parsed
        if shouldAdvancePastTimes,
           candidate < now.addingTimeInterval(-60),
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: candidate)
        {
            candidate = tomorrow
        }
        return candidate
    }

    private static func usdFromAnthropicLowestUnitAmount(_ raw: String) -> Double {
        (Double(raw) ?? 0) / 100
    }

    private static func adminURL(
        baseURL: URL,
        range: AdminDateRange,
        queryItems extraItems: [URLQueryItem]) -> URL
    {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: adminRFC3339String(from: range.start)),
            URLQueryItem(name: "ending_at", value: adminRFC3339String(from: range.end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: String(adminMaxDailyBuckets)),
        ] + extraItems
        return components.url!
    }

    private static func adminDailyRange(now: Date, calendar: Calendar) -> AdminDateRange {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(adminMaxDailyBuckets - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return AdminDateRange(start: start, end: end)
    }

    private static var adminUTCCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func adminRFC3339Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func adminRFC3339String(from date: Date) -> String {
        adminRFC3339Formatter().string(from: date)
    }

    private static func adminDayKey(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct ClaudeWebOrganization {
        let id: String
        let name: String?
    }

    private struct ClaudeWebSession {
        let sessionKey: String
        let sourceLabel: String
        let cacheHeader: String?
        let isCached: Bool
    }

    private struct ClaudeWebOrganizationResponse: Decodable {
        let uuid: String
        let name: String?
        let capabilities: [String]?

        var organization: ClaudeWebOrganization {
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClaudeWebOrganization(
                id: uuid,
                name: trimmed?.isEmpty == false ? trimmed : nil)
        }

        var hasChatCapability: Bool {
            normalizedCapabilities.contains("chat")
        }

        var isAPIOnly: Bool {
            !normalizedCapabilities.isEmpty && normalizedCapabilities == ["api"]
        }

        private var normalizedCapabilities: Set<String> {
            Set((capabilities ?? []).map { $0.lowercased() })
        }
    }

    private struct ClaudeWebAccountInfo {
        let email: String?
        let loginMethod: String?
    }

    private struct ClaudeWebAccountResponse: Decodable {
        let emailAddress: String?
        let memberships: [Membership]?

        private enum CodingKeys: String, CodingKey {
            case emailAddress = "email_address"
            case memberships
        }

        struct Membership: Decodable {
            let organization: Organization

            struct Organization: Decodable {
                let uuid: String?
                let rateLimitTier: String?
                let billingType: String?

                private enum CodingKeys: String, CodingKey {
                    case uuid
                    case rateLimitTier = "rate_limit_tier"
                    case billingType = "billing_type"
                }
            }
        }
    }

    private struct AdminDateRange {
        let start: Date
        let end: Date
    }

    private struct AdminDailyAccumulator {
        let startingAt: String
        let endingAt: String
        var costUSD: Double = 0
        var inputTokens: Int = 0
        var cacheCreationInputTokens: Int = 0
        var cacheReadInputTokens: Int = 0
        var outputTokens: Int = 0
        var totalTokens: Int = 0
        var costItems: [String: Double] = [:]
        var models: [String: AdminModelAccumulator] = [:]

        func makeBucket(calendar: Calendar) -> ClaudeAdminAPIUsageSnapshot.DailyBucket? {
            guard let start = ClaudeUsageFetcher.parseISO8601(startingAt),
                  let end = ClaudeUsageFetcher.parseISO8601(endingAt)
            else { return nil }
            return ClaudeAdminAPIUsageSnapshot.DailyBucket(
                day: ClaudeUsageFetcher.adminDayKey(from: start, calendar: calendar),
                startTime: start,
                endTime: end,
                costUSD: costUSD,
                inputTokens: inputTokens,
                cacheCreationInputTokens: cacheCreationInputTokens,
                cacheReadInputTokens: cacheReadInputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens,
                costItems: costItems
                    .map { ClaudeAdminAPIUsageSnapshot.CostBreakdown(name: $0.key, costUSD: $0.value) }
                    .sorted {
                        if $0.costUSD == $1.costUSD { return $0.name < $1.name }
                        return $0.costUSD > $1.costUSD
                    },
                models: models
                    .map { name, total in total.makeModel(name: name) }
                    .sorted {
                        if $0.totalTokens == $1.totalTokens { return $0.name < $1.name }
                        return $0.totalTokens > $1.totalTokens
                    })
        }
    }

    private struct AdminModelAccumulator {
        var inputTokens = 0
        var cacheCreationInputTokens = 0
        var cacheReadInputTokens = 0
        var outputTokens = 0
        var totalTokens = 0

        mutating func add(
            inputTokens: Int,
            cacheCreationInputTokens: Int,
            cacheReadInputTokens: Int,
            outputTokens: Int,
            totalTokens: Int)
        {
            self.inputTokens += inputTokens
            self.cacheCreationInputTokens += cacheCreationInputTokens
            self.cacheReadInputTokens += cacheReadInputTokens
            self.outputTokens += outputTokens
            self.totalTokens += totalTokens
        }

        func makeModel(name: String) -> ClaudeAdminAPIUsageSnapshot.ModelBreakdown {
            ClaudeAdminAPIUsageSnapshot.ModelBreakdown(
                name: name,
                inputTokens: inputTokens,
                cacheCreationInputTokens: cacheCreationInputTokens,
                cacheReadInputTokens: cacheReadInputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens)
        }
    }

    private struct AdminCostReportResponse: Decodable {
        let data: [AdminCostBucket]

        private enum CodingKeys: String, CodingKey {
            case data
        }
    }

    private struct AdminCostBucket: Decodable {
        let startingAt: String
        let endingAt: String
        let results: [AdminCostResult]

        private enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    private struct AdminCostResult: Decodable {
        let amount: String
        let description: String?
        let costType: String?

        private enum CodingKeys: String, CodingKey {
            case amount
            case description
            case costType = "cost_type"
        }
    }

    private struct AdminMessagesUsageResponse: Decodable {
        let data: [AdminMessagesBucket]

        private enum CodingKeys: String, CodingKey {
            case data
        }
    }

    private struct AdminMessagesBucket: Decodable {
        let startingAt: String
        let endingAt: String
        let results: [AdminMessagesResult]

        private enum CodingKeys: String, CodingKey {
            case startingAt = "starting_at"
            case endingAt = "ending_at"
            case results
        }
    }

    private struct AdminMessagesResult: Decodable {
        let uncachedInputTokens: Int?
        let cacheCreation: AdminCacheCreation?
        let cacheReadInputTokens: Int?
        let outputTokens: Int?
        let model: String?

        private enum CodingKeys: String, CodingKey {
            case uncachedInputTokens = "uncached_input_tokens"
            case cacheCreation = "cache_creation"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case outputTokens = "output_tokens"
            case model
        }
    }

    private struct AdminCacheCreation: Decodable {
        let ephemeral1HInputTokens: Int?
        let ephemeral5MInputTokens: Int?

        var totalInputTokens: Int {
            (ephemeral1HInputTokens ?? 0) + (ephemeral5MInputTokens ?? 0)
        }

        private enum CodingKeys: String, CodingKey {
            case ephemeral1HInputTokens = "ephemeral_1h_input_tokens"
            case ephemeral5MInputTokens = "ephemeral_5m_input_tokens"
        }
    }
}
