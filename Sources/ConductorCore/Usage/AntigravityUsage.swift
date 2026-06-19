import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Antigravity（Google「Antigravity」IDE / Gemini Code Assist 套餐）用量取数。
///
/// 转写自 CodexBar 的 Antigravity provider：优先支持 `agy` CLI / 本地 HTTPS API，
/// 同时保留 `AntigravityOAuthFetchStrategy` → `AntigravityRemoteUsageFetcher`
/// 这一条**纯 HTTP / 本地凭证**路径。OAuth 取数流程：
///   1. 从本地凭证文件 `~/.codexbar/antigravity/oauth_creds.json`（或环境变量
///      `ANTIGRAVITY_OAUTH_CREDENTIALS_JSON` 注入的 JSON）读 Google OAuth 凭证；
///   2. 令牌将过期则用 `refresh_token` 走 `https://oauth2.googleapis.com/token` 刷新
///      （client_id/secret 优先取凭证内置，其次环境变量，再次从已安装的 Antigravity.app
///      二进制里发现）；
///   3. `Bearer` 调 `https://cloudcode-pa.googleapis.com` 的
///      `v1internal:loadCodeAssist` / `:onboardUser` / `:fetchAvailableModels`
///      / `:retrieveUserQuota`，得到各模型 `remainingFraction`（剩余额度分数）。
///
/// 额度→快照映射：`usedPercent = round((1 - remainingFraction) * 100)`。Antigravity
/// 没有「会话窗口 / 周窗口」概念，按各模型族各自的配额配重置时间。这里照 CodexBar 的
/// 取代表：Claude 族当 session（primary），Gemini Pro 族当 weekly（secondary）；
/// 若拿不到对应族则回退到剩余最少的可用模型。无重置时间则回落 now+30 天。
///
/// 凭证来源说明：`oauth_creds.json` 是 **CodexBar 自己的 OAuth 登录产物**，由 CodexBar 的
/// 登录流程写入，并非 Antigravity IDE 原生写的文件。conductor 没有内置这套登录 UI，
/// 因此只有先在 CodexBar 里登录过、或手动经环境变量注入凭证，本 provider 才会被视作「已配置」。
/// CLI 路径会启动 `agy` 或连接显式提供的本地端口，调用 CodexBar 同款
/// `RetrieveUserQuotaSummary` / `GetUserStatus` / `GetCommandModelConfigs` 本地接口。
public enum AntigravityUsageError: LocalizedError, Sendable {
    case unsupportedSource(String)
    case cliUnavailable
    case cliFailed(String)
    case cliTimedOut
    case accountMismatch(expected: String?, found: String?)
    case notLoggedIn
    case unauthorized
    case missingOAuthClient
    case server(Int)
    case invalidResponse
    case network(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSource(source):
            return L("Antigravity 来源 %@ 不受支持，请使用 auto、cli 或 oauth", source)
        case .cliUnavailable:
            return L("未找到 Antigravity CLI，请安装 agy 或设置 ANTIGRAVITY_CLI_PATH")
        case let .cliFailed(message):
            return L("Antigravity CLI 本地接口失败：%@", message)
        case .cliTimedOut:
            return L("Antigravity CLI 本地接口超时")
        case let .accountMismatch(expected, found):
            return L(
                "Antigravity 本地会话账号不匹配（期望 %@，实际 %@）",
                expected ?? "unknown",
                found ?? "unknown")
        case .notLoggedIn:
            return L("未找到 Antigravity 登录信息，请先在 CodexBar 中用 Google 账号登录 Antigravity")
        case .unauthorized:
            return L("Antigravity 令牌已过期，请重新登录")
        case .missingOAuthClient:
            return L("未找到 Antigravity OAuth 客户端，请安装 Antigravity.app 或设置 ANTIGRAVITY_OAUTH_CLIENT_ID / ANTIGRAVITY_OAUTH_CLIENT_SECRET")
        case let .server(code):
            return L("Antigravity 接口错误（%ld）", code)
        case .invalidResponse:
            return L("Antigravity 用量接口返回异常")
        case let .network(msg):
            return L("网络错误：%@", msg)
        }
    }
}

private final class AntigravityLocalhostSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challengeResult(challenge)
    }

    private func challengeResult(
        _ challenge: URLAuthenticationChallenge
    ) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        #if os(Linux)
        return (.performDefaultHandling, nil)
        #else
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              ["127.0.0.1", "localhost"].contains(protectionSpace.host.lowercased()),
              let trust = protectionSpace.serverTrust
        else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
        #endif
    }
}

private actor AntigravityCLIHTTPSessionPool {
    static let shared = AntigravityCLIHTTPSessionPool()

    private let idleWindow: TimeInterval = 90
    private var sessions: [String: Session] = [:]
    private var starting: [String: Task<AntigravityCLIHTTPClient, Error>] = [:]
    private var inFlight: [String: Task<UsageSnapshot, Error>] = [:]

    func fetch(binary: String, env: [String: String], timeout: TimeInterval) async throws -> UsageSnapshot {
        let key = sessionKey(binary: binary, env: env)
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await self.fetchFresh(key: key, binary: binary, env: env, timeout: timeout) }
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

    private func fetchFresh(
        key: String,
        binary: String,
        env: [String: String],
        timeout: TimeInterval) async throws -> UsageSnapshot
    {
        let client = try await client(for: key, binary: binary, env: env)
        let deadline = Date().addingTimeInterval(timeout)
        do {
            let snapshot = try await AntigravityUsageFetcher.waitForLocalSnapshot(
                pid: client.pid,
                deadline: deadline,
                drainOutput: { client.drainOutput() })
            if client.isRunning {
                markUsed(key: key)
            } else {
                discard(key: key)
            }
            return snapshot
        } catch {
            discard(key: key)
            throw error
        }
    }

    private func client(for key: String, binary: String, env: [String: String]) async throws -> AntigravityCLIHTTPClient {
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

        let task = Task { try AntigravityCLIHTTPClient(binary: binary, env: env) }
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
            "ANTIGRAVITY_CLI_PATH",
            "HOME",
            "PATH",
            "XDG_CONFIG_HOME",
            "ANTIGRAVITY_CONFIG_HOME",
            "CONDUCTOR_USAGE_ANTIGRAVITY_FAKE_MARKER_FILE",
        ]
        return (["binary=\(binary)"] + names.map { "\($0)=\(env[$0] ?? "")" })
            .joined(separator: "\n")
    }

    private struct Session {
        var client: AntigravityCLIHTTPClient
        var lastUsedAt: Date
        var idleShutdownTask: Task<Void, Never>?
    }
}

private final class AntigravityCLIHTTPClient: @unchecked Sendable {
    private let process = Process()
    private let primaryFD: Int32
    private let primaryHandle: FileHandle
    private let secondaryHandle: FileHandle
    private var processGroup: pid_t?
    private let lock = NSLock()
    private var closed = false

    init(binary: String, env: [String: String]) throws {
        var primary: Int32 = -1
        var secondary: Int32 = -1
        var win = winsize(ws_row: 50, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primary, &secondary, nil, nil, &win) == 0 else {
            throw AntigravityUsageError.cliFailed("openpty failed")
        }
        _ = fcntl(primary, F_SETFL, O_NONBLOCK)
        self.primaryFD = primary
        self.primaryHandle = FileHandle(fileDescriptor: primary, closeOnDealloc: true)
        self.secondaryHandle = FileHandle(fileDescriptor: secondary, closeOnDealloc: true)

        let resolved = URL(fileURLWithPath: binary)
        process.executableURL = resolved
        process.arguments = []
        process.currentDirectoryURL = URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory(), isDirectory: true)
        process.environment = TTYCommandRunner.enrichedEnvironment(
            baseEnv: env,
            home: env["HOME"] ?? NSHomeDirectory())
        process.standardInput = secondaryHandle
        process.standardOutput = secondaryHandle
        process.standardError = secondaryHandle

        do {
            try process.run()
        } catch {
            closeHandles()
            throw AntigravityUsageError.cliFailed(error.localizedDescription)
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
            throw AntigravityUsageError.cliFailed("App shutdown in progress")
        }
        if let processGroup {
            TTYCommandRunner.updateActiveProcessGroupForAppShutdown(pid: pid, processGroup: processGroup)
        }
        usleep(250_000)
    }

    deinit {
        shutdown()
    }

    var pid: Int32 {
        process.processIdentifier
    }

    var isRunning: Bool {
        process.isRunning
    }

    func drainOutput() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return "" }
        let data = readAvailable()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func shutdown() {
        lock.lock()
        let alreadyClosed = closed
        closed = true
        lock.unlock()
        guard !alreadyClosed else { return }

        sendExit()
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
        let waitDeadline = Date().addingTimeInterval(1.5)
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
    }

    private func sendExit() {
        guard let data = "/exit\n".data(using: .utf8) else { return }
        data.withUnsafeBytes { rawBytes in
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
                    if retries > 40 { return }
                    usleep(5_000)
                    continue
                }
                return
            }
        }
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

    private func closeHandles() {
        try? primaryHandle.close()
        try? secondaryHandle.close()
    }
}

public enum AntigravityUsageFetcher {
    // MARK: - 端点（照搬 AntigravityRemoteUsageFetcher）

    private static let defaultBaseURL = "https://cloudcode-pa.googleapis.com"
    private static let defaultTokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private static let baseURLEnvironmentKey = "CONDUCTOR_USAGE_ANTIGRAVITY_BASE_URL"
    private static let tokenURLEnvironmentKey = "CONDUCTOR_USAGE_ANTIGRAVITY_TOKEN_URL"
    public static let tokenAccountUpdatePathEnvironmentKey =
        "CONDUCTOR_USAGE_ANTIGRAVITY_TOKEN_ACCOUNT_UPDATE_PATH"
    private static let userAgent = "antigravity"
    private static let refreshSafetyWindow: TimeInterval = 60
    private static let timeout: TimeInterval = 30
    private static let localTimeout: TimeInterval = 5
    private static let environmentCredentialsKey = "ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"

    // MARK: - 可用性判断

    /// 是否存在 Antigravity 凭证（本地 oauth_creds.json 或环境变量注入）。
    /// 仅做便宜的本地存在性 / 解码检查，不发网络。
    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        loadStoredCredentials(env: env) != nil
            || localPortsOverride(env: env) != nil
            || resolvedAgyBinary(env: env) != nil
            || hasLocalLanguageServer()
    }

    // MARK: - 取数

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        switch UsageProviderRuntimeConfig.sourceMode(providerID: "antigravity", env: env) ?? "auto" {
        case "auto":
            var localError: Error?
            do {
                return try await fetchSelectedAccountValidatedCLI(env: env)
            } catch {
                localError = error
            }
            if loadStoredCredentials(env: env) != nil {
                return try await fetchOAuth(env: env, session: session)
            }
            throw localError ?? AntigravityUsageError.notLoggedIn
        case "cli":
            return try await fetchSelectedAccountValidatedCLI(env: env)
        case "oauth":
            return try await fetchOAuth(env: env, session: session)
        case "web", "api":
            throw AntigravityUsageError.unsupportedSource(
                UsageProviderRuntimeConfig.sourceMode(providerID: "antigravity", env: env) ?? "auto")
        case let source:
            throw AntigravityUsageError.unsupportedSource(source)
        }
    }

    private static func fetchOAuth(env: [String: String], session: URLSession) async throws -> UsageSnapshot {
        guard var credentials = loadStoredCredentials(env: env) else {
            throw AntigravityUsageError.notLoggedIn
        }
        guard var accessToken = credentials.accessToken?.trimmedNonEmpty else {
            throw AntigravityUsageError.notLoggedIn
        }

        // 1. 必要时刷新令牌。
        if shouldRefresh(expiryDate: credentials.expiryDate, now: Date()) {
            guard let refreshToken = credentials.refreshToken?.trimmedNonEmpty else {
                throw AntigravityUsageError.notLoggedIn
            }
            let refreshed = try await refreshAccessToken(
                credentials: credentials,
                refreshToken: refreshToken,
                env: env,
                session: session)
            accessToken = refreshed.accessToken
            credentials = refreshed.credentials
        }

        // 2. loadCodeAssist 拿计划 / projectID。
        let claims = extractClaims(from: credentials)
        let codeAssist = try await loadCodeAssist(accessToken: accessToken, env: env, session: session)
        let projectID = try await resolveProjectID(
            accessToken: accessToken,
            storedProjectID: credentials.projectID?.trimmedNonEmpty,
            initialResponse: codeAssist,
            env: env,
            session: session)

        // 3. 取各模型额度。
        let quotas = try await fetchModelQuotas(
            accessToken: accessToken,
            projectID: projectID,
            env: env,
            session: session)

        let plan = resolvePlan(response: codeAssist, claims: claims)
        var snapshot = makeSnapshot(quotas: quotas, planType: plan)
        snapshot.accountLabel = claims.email
        return snapshot.withSourceLabel("oauth")
    }

    // MARK: - CLI / 本地 HTTPS API

    private static let localGetUserStatusPath =
        "/exa.language_server_pb.LanguageServerService/GetUserStatus"
    private static let localCommandModelConfigPath =
        "/exa.language_server_pb.LanguageServerService/GetCommandModelConfigs"
    private static let localQuotaSummaryPath =
        "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"

    private struct LocalEndpoint {
        let scheme: String
        let port: Int
        let csrfToken: String?
        let requiresCSRFToken: Bool
    }

    private static func fetchSelectedAccountValidatedCLI(env: [String: String]) async throws -> UsageSnapshot {
        let snapshot = try await fetchCLI(env: env)
        try validateSelectedLocalAccount(snapshot, env: env)
        return snapshot
    }

    private static func validateSelectedLocalAccount(_ snapshot: UsageSnapshot, env: [String: String]) throws {
        guard let expected = selectedAccountEmail(env: env)
        else {
            return
        }
        let found = snapshot.accountLabel?.trimmedNonEmpty
        guard let found, found.caseInsensitiveCompare(expected) == .orderedSame else {
            throw AntigravityUsageError.accountMismatch(expected: expected, found: found)
        }
    }

    private static func selectedAccountEmail(env: [String: String]) -> String? {
        guard env[environmentCredentialsKey]?.trimmedNonEmpty != nil,
              let credentials = loadStoredCredentials(env: env)
        else {
            return nil
        }
        return extractClaims(from: credentials).email
    }

    private static func fetchCLI(env: [String: String]) async throws -> UsageSnapshot {
        let matchingAccountEmail = selectedAccountEmail(env: env)
        if let ports = localPortsOverride(env: env) {
            return try await fetchLocalSnapshot(
                ports: ports,
                deadline: Date().addingTimeInterval(localTimeout),
                matchingAccountEmail: matchingAccountEmail)
                .withSourceLabel("cli")
        }

        let deadline = Date().addingTimeInterval(localTimeout)
        var lastError: Error?
        do {
            return try await fetchLocalProcesses(
                scope: .appOnly,
                deadline: deadline,
                matchingAccountEmail: matchingAccountEmail)
        } catch {
            lastError = error
        }

        if let binary = resolvedAgyBinary(env: env) {
            do {
                if shouldUseWarmCLISession(env: env) {
                    return try await AntigravityCLIHTTPSessionPool.shared.fetch(
                        binary: binary,
                        env: env,
                        timeout: localTimeout)
                        .withSourceLabel("cli")
                }
                return try await fetchOneShotCLI(binary: binary, env: env)
                    .withSourceLabel("cli")
            } catch {
                lastError = error
            }
        } else {
            lastError = lastError ?? AntigravityUsageError.cliUnavailable
        }

        do {
            return try await fetchLocalProcesses(
                scope: .ideOnly,
                deadline: Date().addingTimeInterval(localTimeout),
                matchingAccountEmail: matchingAccountEmail)
        } catch {
            lastError = error
        }

        throw lastError ?? AntigravityUsageError.cliUnavailable
    }

    private static func shouldUseWarmCLISession(env: [String: String]) -> Bool {
        if let value = env["CONDUCTOR_USAGE_ANTIGRAVITY_WARM_SESSION"]?.trimmedNonEmpty {
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        if let value = env["CONDUCTOR_USAGE_ANTIGRAVITY_DISABLE_WARM_SESSION"]?.trimmedNonEmpty,
           ["1", "true", "yes", "on"].contains(value.lowercased())
        {
            return false
        }
        let executableName = URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent
        if executableName == "ConductorApp" { return true }
        return CommandLine.arguments.dropFirst().contains("serve")
    }

    private static func fetchOneShotCLI(binary: String, env: [String: String]) async throws -> UsageSnapshot {
        let process = try launchAgy(binary: binary, env: env)
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(localTimeout)
        do {
            return try await waitForLocalSnapshot(pid: process.processIdentifier, deadline: deadline)
        } catch {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
            let output = processOutput(process)
            if localOutputLooksAuthenticationRequired(output) {
                throw AntigravityUsageError.cliFailed("Antigravity CLI is signed out. Run agy in a terminal to sign in.")
            }
            throw error
        }
    }

    static func waitForLocalSnapshot(
        pid: Int32,
        deadline: Date,
        drainOutput: (() -> String)? = nil) async throws -> UsageSnapshot
    {
        var lastError: Error?
        while Date() < deadline {
            if let output = drainOutput?(), localOutputLooksAuthenticationRequired(output) {
                throw AntigravityUsageError.cliFailed("Antigravity CLI is signed out. Run agy in a terminal to sign in.")
            }
            do {
                let ports = try listeningPorts(pid: pid, timeout: min(0.75, max(0.2, deadline.timeIntervalSinceNow)))
                if !ports.isEmpty {
                    do {
                        let snapshot = try await fetchLocalSnapshot(ports: ports, deadline: deadline)
                        return snapshot
                    } catch {
                        lastError = error
                    }
                }
            } catch {
                lastError = error
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        if let output = drainOutput?(), localOutputLooksAuthenticationRequired(output) {
            throw AntigravityUsageError.cliFailed("Antigravity CLI is signed out. Run agy in a terminal to sign in.")
        }
        if let lastError { throw lastError }
        throw AntigravityUsageError.cliTimedOut
    }

    private static func resolvedAgyBinary(env: [String: String]) -> String? {
        BinaryLocator.resolveAntigravityBinary(
            env: env,
            loginPATH: LoginShellPathCache.shared.currentOrCapture(),
            home: env["HOME"] ?? NSHomeDirectory())
    }

    private static func localPortsOverride(env: [String: String]) -> [Int]? {
        let raw = env["CONDUCTOR_USAGE_ANTIGRAVITY_LOCAL_PORTS"] ?? env["ANTIGRAVITY_LOCAL_PORTS"]
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let ports = raw
            .split { $0 == "," || $0 == " " || $0 == ";" || $0 == ":" }
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 && $0 < 65_536 }
        return ports.isEmpty ? nil : Array(Set(ports)).sorted()
    }

    private static func launchAgy(binary: String, env: [String: String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = []
        var commandEnv = env
        commandEnv["PATH"] = PathBuilder.effectivePATH(
            purposes: [.tty, .nodeTooling],
            env: env,
            loginPATH: LoginShellPathCache.shared.currentOrCapture(),
            home: env["HOME"] ?? NSHomeDirectory())
        commandEnv["TERM"] = commandEnv["TERM"]?.trimmedNonEmpty ?? "xterm-256color"
        process.environment = commandEnv
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AntigravityUsageError.cliFailed(error.localizedDescription)
        }
        return process
    }

    private static func processOutput(_ process: Process) -> String {
        let stdout = (process.standardOutput as? Pipe)?
            .fileHandleForReading
            .readDataToEndOfFile()
        let stderr = (process.standardError as? Pipe)?
            .fileHandleForReading
            .readDataToEndOfFile()
        return [stdout, stderr]
            .compactMap { data -> String? in
                guard let data, !data.isEmpty else { return nil }
                return String(data: data, encoding: .utf8)
            }
            .joined(separator: "\n")
    }

    private static func localOutputLooksAuthenticationRequired(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("select login method")
            || lower.contains("select a login method")
            || lower.contains("choose login method")
            || lower.contains("authentication required")
    }

    private enum LocalProcessScope {
        case appOnly
        case ideOnly
    }

    private enum LocalProcessKind {
        case app
        case ide
        case cli

        var sourceLabel: String {
            switch self {
            case .app: "app"
            case .ide: "ide"
            case .cli: "cli"
            }
        }
    }

    private struct LocalProcessInfo {
        let pid: Int32
        let kind: LocalProcessKind
        let extensionPort: Int?
        let extensionServerCSRFToken: String?
        let csrfToken: String
    }

    private static func hasLocalLanguageServer() -> Bool {
        (try? detectLocalProcessInfos(scope: .appOnly).isEmpty == false) == true
            || (try? detectLocalProcessInfos(scope: .ideOnly).isEmpty == false) == true
    }

    private static func fetchLocalProcesses(
        scope: LocalProcessScope,
        deadline: Date,
        matchingAccountEmail: String?) async throws -> UsageSnapshot
    {
        let processInfos = try detectLocalProcessInfos(scope: scope)
        var snapshots: [UsageSnapshot] = []
        var lastError: Error?
        for processInfo in processInfos {
            do {
                let ports = try listeningPorts(
                    pid: processInfo.pid,
                    timeout: min(0.75, max(0.2, deadline.timeIntervalSinceNow)))
                let endpoints = localProcessEndpoints(processInfo: processInfo, listeningPorts: ports)
                let snapshot = try await fetchLocalSnapshot(endpoints: endpoints, deadline: deadline)
                    .withSourceLabel(processInfo.kind.sourceLabel)
                snapshots.append(snapshot)
            } catch {
                lastError = error
            }
        }
        if let bestSnapshot = preferredLocalSnapshot(snapshots, matchingAccountEmail: matchingAccountEmail) {
            return bestSnapshot
        }
        throw lastError ?? AntigravityUsageError.cliFailed("Antigravity language server not detected")
    }

    private static func preferredLocalSnapshot(
        _ snapshots: [UsageSnapshot],
        matchingAccountEmail expectedAccountEmail: String?) -> UsageSnapshot?
    {
        let candidates: [UsageSnapshot]
        if let expected = expectedAccountEmail?.trimmedNonEmpty {
            let matches = snapshots.filter { snapshot in
                guard let found = snapshot.accountLabel?.trimmedNonEmpty else { return false }
                return found.caseInsensitiveCompare(expected) == .orderedSame
            }
            candidates = matches.isEmpty ? snapshots : matches
        } else {
            candidates = snapshots
        }

        return candidates.max { lhs, rhs in
            localSnapshotScore(lhs) < localSnapshotScore(rhs)
        }
    }

    private static func localSnapshotScore(_ snapshot: UsageSnapshot) -> Int {
        var score = 0
        if snapshot.primary != nil { score += 100 }
        if snapshot.secondary != nil { score += 80 }
        score += snapshot.extraRateWindows.count * 20
        if snapshot.accountLabel?.trimmedNonEmpty != nil { score += 2 }
        if snapshot.planName?.trimmedNonEmpty != nil { score += 1 }
        return score
    }

    private static func detectLocalProcessInfos(scope: LocalProcessScope) throws -> [LocalProcessInfo] {
        let result = runLocalCommand(
            binary: "/bin/ps",
            arguments: ["-ax", "-o", "pid=,command="],
            timeout: 1.5)
        guard result.status == 0 else {
            throw AntigravityUsageError.cliFailed(
                result.stderr.trimmedNonEmpty ?? result.stdout.trimmedNonEmpty ?? "ps exited \(result.status)")
        }
        return try localProcessInfos(fromProcessListOutput: result.stdout, scope: scope)
    }

    private static func localProcessInfos(
        fromProcessListOutput output: String,
        scope: LocalProcessScope) throws -> [LocalProcessInfo]
    {
        var results: [LocalProcessInfo] = []
        var sawTokenlessLanguageServer = false
        for line in output.split(separator: "\n") {
            guard let match = matchProcessLine(String(line)),
                  let kind = antigravityProcessKind(match.command),
                  localProcessKind(kind, matches: scope)
            else {
                continue
            }
            guard let token = resolvedCSRFToken(forKind: kind, command: match.command) else {
                sawTokenlessLanguageServer = true
                continue
            }
            results.append(LocalProcessInfo(
                pid: Int32(match.pid),
                kind: kind,
                extensionPort: extractPort("--extension_server_port", from: match.command),
                extensionServerCSRFToken: extractFlag("--extension_server_csrf_token", from: match.command),
                csrfToken: token))
        }
        if !results.isEmpty { return results }
        if sawTokenlessLanguageServer {
            throw AntigravityUsageError.cliFailed("Antigravity CSRF token not found. Restart Antigravity and retry.")
        }
        throw AntigravityUsageError.cliFailed("Antigravity language server not detected")
    }

    private struct ProcessLineMatch {
        let pid: Int
        let command: String
    }

    private static func matchProcessLine(_ line: String) -> ProcessLineMatch? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
        return ProcessLineMatch(pid: pid, command: String(parts[1]))
    }

    private static func localProcessKind(_ kind: LocalProcessKind, matches scope: LocalProcessScope) -> Bool {
        switch scope {
        case .appOnly:
            kind == .app
        case .ideOnly:
            kind == .ide
        }
    }

    private static func antigravityProcessKind(_ command: String) -> LocalProcessKind? {
        let lower = command.lowercased()
        if isLanguageServerCommandLine(lower), isAntigravityCommandLine(lower) {
            return isAntigravityIDECommandLine(lower) ? .ide : .app
        }
        if isAntigravityCLICommandLine(lower) {
            return .cli
        }
        return nil
    }

    private static func resolvedCSRFToken(forKind kind: LocalProcessKind, command: String) -> String? {
        if let token = extractFlag("--csrf_token", from: command) {
            return token
        }
        switch kind {
        case .app, .ide:
            return nil
        case .cli:
            return ""
        }
    }

    private static func isLanguageServerCommandLine(_ lowerCommand: String) -> Bool {
        let pattern = #"(^|[/\\])language(?:_|-)server(?:[_-][a-z0-9]+)*(?:\.exe)?(\s|$)"#
        return lowerCommand.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isAntigravityCLICommandLine(_ lowerCommand: String) -> Bool {
        let cliPathPattern = #"(^|[/\\])(antigravity-cli|antigravity_cli)([\s/\\]|$)"#
        if lowerCommand.range(of: cliPathPattern, options: .regularExpression) != nil {
            return true
        }
        let agyPattern = #"(^|[/\\])agy(\s|$)"#
        return lowerCommand.range(of: agyPattern, options: .regularExpression) != nil
    }

    private static func isAntigravityCommandLine(_ command: String) -> Bool {
        if command.contains("--app_data_dir") && command.contains("antigravity") { return true }
        if command.contains("antigravity.app/") || command.contains("antigravity.app\\") { return true }
        if command.contains("antigravity ide.app/") || command.contains("antigravity ide.app\\") { return true }
        if command.contains("/antigravity/") || command.contains("\\antigravity\\") { return true }
        return false
    }

    private static func isAntigravityIDECommandLine(_ lowerCommand: String) -> Bool {
        [
            "antigravity ide.app/",
            "antigravity ide.app\\",
            "--app_data_dir antigravity-ide",
            "--app_data_dir=antigravity-ide",
            "/extensions/antigravity/bin/language_server",
            "\\extensions\\antigravity\\bin\\language_server",
        ].contains { lowerCommand.contains($0) }
    }

    private static func extractFlag(_ flag: String, from command: String) -> String? {
        let pattern = "\(NSRegularExpression.escapedPattern(for: flag))[=\\s]+([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, options: [], range: range),
              let tokenRange = Range(match.range(at: 1), in: command)
        else {
            return nil
        }
        return String(command[tokenRange])
    }

    private static func extractPort(_ flag: String, from command: String) -> Int? {
        guard let raw = extractFlag(flag, from: command) else { return nil }
        return Int(raw)
    }

    private static func listeningPorts(pid: Int32, timeout: TimeInterval) throws -> [Int] {
        let lsof = ["/usr/sbin/lsof", "/usr/bin/lsof"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let lsof else { throw AntigravityUsageError.cliFailed("lsof not available") }

        let result = runLocalCommand(
            binary: lsof,
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)],
            timeout: timeout)
        if result.status == 1, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        guard result.status == 0 else {
            throw AntigravityUsageError.cliFailed(
                result.stderr.trimmedNonEmpty ?? result.stdout.trimmedNonEmpty ?? "lsof exited \(result.status)")
        }

        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(result.stdout.startIndex..<result.stdout.endIndex, in: result.stdout)
        var ports = Set<Int>()
        regex.enumerateMatches(in: result.stdout, options: [], range: range) { match, _, _ in
            guard let match,
                  let range = Range(match.range(at: 1), in: result.stdout),
                  let value = Int(result.stdout[range])
            else { return }
            ports.insert(value)
        }
        return ports.sorted()
    }

    private struct LocalCommandResult {
        let stdout: String
        let stderr: String
        let status: Int32
    }

    private static func runLocalCommand(binary: String, arguments: [String], timeout: TimeInterval) -> LocalCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdoutFD = Int32(stdout.fileHandleForReading.fileDescriptor)
        let stderrFD = Int32(stderr.fileHandleForReading.fileDescriptor)
        _ = fcntl(stdoutFD, F_SETFL, O_NONBLOCK)
        _ = fcntl(stderrFD, F_SETFL, O_NONBLOCK)
        do {
            try process.run()
        } catch {
            return LocalCommandResult(stdout: "", stderr: error.localizedDescription, status: -1)
        }
        var stdoutData = Data()
        var stderrData = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            stdoutData.append(readAvailable(fd: stdoutFD))
            stderrData.append(readAvailable(fd: stderrFD))
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                stdoutData.append(readAvailable(fd: stdoutFD))
                stderrData.append(readAvailable(fd: stderrFD))
                return LocalCommandResult(stdout: "", stderr: "timed out", status: -1)
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        stdoutData.append(readAvailable(fd: stdoutFD))
        stderrData.append(readAvailable(fd: stderrFD))
        let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        return LocalCommandResult(stdout: stdoutText, stderr: stderrText, status: process.terminationStatus)
    }

    private static func readAvailable(fd: Int32) -> Data {
        var data = Data()
        while true {
            var buffer = [UInt8](repeating: 0, count: 8192)
            errno = 0
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(Int(count)))
                continue
            }
            if count == 0 {
                return data
            }
            let err = errno
            if err == EAGAIN || err == EWOULDBLOCK || err == EINTR || err == EIO {
                return data
            }
            return data
        }
    }

    private static func fetchLocalSnapshot(
        ports: [Int],
        deadline: Date?,
        matchingAccountEmail: String? = nil) async throws -> UsageSnapshot
    {
        var snapshots: [UsageSnapshot] = []
        var lastError: Error?
        for port in ports {
            do {
                snapshots.append(try await fetchLocalSnapshot(
                    endpoints: localEndpoints(ports: [port]),
                    deadline: deadline))
            } catch {
                lastError = error
            }
        }
        if let snapshot = preferredLocalSnapshot(snapshots, matchingAccountEmail: matchingAccountEmail) {
            return snapshot
        }
        throw lastError ?? AntigravityUsageError.cliFailed("local API returned no response")
    }

    private static func fetchLocalSnapshot(endpoints: [LocalEndpoint], deadline: Date?) async throws -> UsageSnapshot {
        do {
            var snapshot = try await requestLocalQuotaSummary(endpoints: endpoints, deadline: deadline)
            if let identity = try? await requestLocalUserStatus(endpoints: endpoints, deadline: deadline) {
                snapshot.accountLabel = identity.accountLabel ?? snapshot.accountLabel
                snapshot.planName = snapshot.planName ?? identity.planName
            }
            return snapshot
        } catch {
            if let snapshot = try? await requestLocalUserStatus(endpoints: endpoints, deadline: deadline) {
                return snapshot
            }
            return try await requestLocalCommandModels(endpoints: endpoints, deadline: deadline)
        }
    }

    private static func localEndpoints(ports: [Int]) -> [LocalEndpoint] {
        #if os(Linux)
        let schemes = ["https", "http"]
        #else
        let schemes = ["https"]
        #endif
        return ports.flatMap { port in
            schemes.map { LocalEndpoint(scheme: $0, port: port, csrfToken: nil, requiresCSRFToken: false) }
        }
    }

    private static func localProcessEndpoints(
        processInfo: LocalProcessInfo,
        listeningPorts: [Int]) -> [LocalEndpoint]
    {
        var endpoints: [LocalEndpoint] = []
        for endpoint in languageServerEndpoints(
            listeningPorts: listeningPorts,
            csrfToken: processInfo.csrfToken)
        {
            appendUniqueEndpoint(endpoint, to: &endpoints)
        }
        for endpoint in extensionServerEndpoints(
            extensionPort: processInfo.extensionPort,
            languageServerCSRFToken: processInfo.csrfToken,
            extensionServerCSRFToken: processInfo.extensionServerCSRFToken)
        {
            appendUniqueEndpoint(endpoint, to: &endpoints)
        }
        return endpoints
    }

    private static func languageServerEndpoints(listeningPorts: [Int], csrfToken: String) -> [LocalEndpoint] {
        #if os(Linux)
        let schemes = ["https", "http"]
        #else
        let schemes = ["https"]
        #endif
        return listeningPorts.flatMap { port in
            schemes.map {
                LocalEndpoint(scheme: $0, port: port, csrfToken: csrfToken, requiresCSRFToken: true)
            }
        }
    }

    private static func extensionServerEndpoints(
        extensionPort: Int?,
        languageServerCSRFToken: String,
        extensionServerCSRFToken: String?) -> [LocalEndpoint]
    {
        guard let extensionPort else { return [] }
        var endpoints: [LocalEndpoint] = []
        if let extensionServerCSRFToken {
            endpoints.append(LocalEndpoint(
                scheme: "http",
                port: extensionPort,
                csrfToken: extensionServerCSRFToken,
                requiresCSRFToken: true))
        }
        if extensionServerCSRFToken != languageServerCSRFToken {
            endpoints.append(LocalEndpoint(
                scheme: "http",
                port: extensionPort,
                csrfToken: languageServerCSRFToken,
                requiresCSRFToken: true))
        }
        return endpoints
    }

    private static func appendUniqueEndpoint(_ endpoint: LocalEndpoint, to endpoints: inout [LocalEndpoint]) {
        guard !endpoints.contains(where: {
            $0.scheme == endpoint.scheme &&
                $0.port == endpoint.port &&
                $0.csrfToken == endpoint.csrfToken &&
                $0.requiresCSRFToken == endpoint.requiresCSRFToken
        }) else {
            return
        }
        endpoints.append(endpoint)
    }

    private static func requestLocalQuotaSummary(
        endpoints: [LocalEndpoint],
        deadline: Date?) async throws -> UsageSnapshot
    {
        try await requestLocalParsed(
            endpoints: endpoints,
            path: localQuotaSummaryPath,
            body: ["forceRefresh": true],
            deadline: deadline,
            parse: parseLocalQuotaSummary)
    }

    private static func requestLocalUserStatus(
        endpoints: [LocalEndpoint],
        deadline: Date?) async throws -> UsageSnapshot
    {
        try await requestLocalParsed(
            endpoints: endpoints,
            path: localGetUserStatusPath,
            body: localDefaultRequestBody(),
            deadline: deadline,
            parse: parseLocalUserStatus)
    }

    private static func requestLocalCommandModels(
        endpoints: [LocalEndpoint],
        deadline: Date?) async throws -> UsageSnapshot
    {
        try await requestLocalParsed(
            endpoints: endpoints,
            path: localCommandModelConfigPath,
            body: localDefaultRequestBody(),
            deadline: deadline,
            parse: parseLocalCommandModels)
    }

    private static func requestLocalParsed<T>(
        endpoints: [LocalEndpoint],
        path: String,
        body: [String: Any],
        deadline: Date?,
        parse: (Data) throws -> T) async throws -> T
    {
        var lastError: Error?
        for endpoint in endpoints {
            do {
                let data = try await sendLocalRequest(endpoint: endpoint, path: path, body: body, deadline: deadline)
                return try parse(data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? AntigravityUsageError.cliFailed("local API returned no response")
    }

    private static func sendLocalRequest(
        endpoint: LocalEndpoint,
        path: String,
        body: [String: Any],
        deadline: Date?) async throws -> Data
    {
        guard let url = URL(string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)\(path)") else {
            throw AntigravityUsageError.invalidResponse
        }
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = max(0.2, min(localTimeout, deadline?.timeIntervalSinceNow ?? localTimeout))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(bodyData.count), forHTTPHeaderField: "Content-Length")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if endpoint.requiresCSRFToken, let csrfToken = endpoint.csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = request.timeoutInterval
        config.timeoutIntervalForResource = request.timeoutInterval
        #if !os(Linux)
        config.waitsForConnectivity = false
        #endif
        let delegate = AntigravityLocalhostSessionDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AntigravityUsageError.invalidResponse }
            guard http.statusCode == 200 else {
                throw AntigravityUsageError.cliFailed("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            }
            return data
        } catch let error as AntigravityUsageError {
            throw error
        } catch {
            throw AntigravityUsageError.cliFailed(error.localizedDescription)
        }
    }

    private static func localDefaultRequestBody() -> [String: Any] {
        [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en",
            ],
        ]
    }

    // MARK: - 凭证加载

    static func credentialsFileURL(env: [String: String]) -> URL {
        let home = env["HOME"]?.trimmedNonEmpty.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".codexbar", isDirectory: true)
            .appendingPathComponent("antigravity", isDirectory: true)
            .appendingPathComponent("oauth_creds.json")
    }

    static func loadStoredCredentials(env: [String: String]) -> Credentials? {
        // 优先环境变量注入的 JSON（选定账号场景），否则读本地文件。
        if let raw = env[environmentCredentialsKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let data = raw.data(using: .utf8),
           let creds = try? JSONDecoder().decode(Credentials.self, from: data)
        {
            return creds
        }
        let url = credentialsFileURL(env: env)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let creds = try? JSONDecoder().decode(Credentials.self, from: data)
        else { return nil }
        return creds
    }

    private static func saveStoredCredentials(_ credentials: Credentials, env: [String: String]) throws {
        let url = credentialsFileURL(env: env)
        try writeCredentials(credentials, to: url, securePermissions: true)
    }

    private static func writeCredentials(
        _ credentials: Credentials,
        to url: URL,
        securePermissions: Bool) throws
    {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(credentials)
        try data.write(to: url, options: [.atomic])
        if securePermissions {
            #if os(macOS) || os(Linux)
            try? FileManager.default.setAttributes([
                .posixPermissions: NSNumber(value: Int16(0o600)),
            ], ofItemAtPath: url.path)
            #endif
        }
    }

    private static func shouldPersistSharedCredentials(env: [String: String]) -> Bool {
        env[environmentCredentialsKey]?.trimmedNonEmpty == nil
    }

    private static func tokenAccountUpdateURL(env: [String: String]) -> URL? {
        env[tokenAccountUpdatePathEnvironmentKey]?.trimmedNonEmpty.map {
            URL(fileURLWithPath: $0)
        }
    }

    private static func tokenURL(env: [String: String]) -> URL {
        if let raw = env[tokenURLEnvironmentKey]?.trimmedNonEmpty,
           let url = URL(string: raw)
        {
            return url
        }
        return defaultTokenURL
    }

    private static func endpoint(_ path: String, env: [String: String]) -> String {
        let base = env[baseURLEnvironmentKey]?.trimmedNonEmpty ?? defaultBaseURL
        return base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
    }

    private static func shouldRefresh(expiryDate: Date?, now: Date) -> Bool {
        guard let expiryDate else { return false }
        return expiryDate.timeIntervalSince(now) <= refreshSafetyWindow
    }

    // MARK: - 令牌刷新

    private struct RefreshResult {
        let accessToken: String
        let credentials: Credentials
    }

    private static func refreshAccessToken(
        credentials: Credentials,
        refreshToken: String,
        env: [String: String],
        session: URLSession) async throws -> RefreshResult
    {
        let client = try resolveOAuthClient(from: credentials, env: env)

        var request = URLRequest(url: tokenURL(env: env))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ])

        let (data, http) = try await perform(request, session: session)
        guard http.statusCode == 200 else { throw AntigravityUsageError.unauthorized }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String
        else { throw AntigravityUsageError.invalidResponse }

        var updated = credentials
        updated.accessToken = accessToken
        if let expiresIn = json["expires_in"] as? Double {
            updated.expiryDateMilliseconds = (Date().timeIntervalSince1970 + expiresIn) * 1000
        } else if let expiresIn = json["expires_in"] as? Int {
            updated.expiryDateMilliseconds = (Date().timeIntervalSince1970 + Double(expiresIn)) * 1000
        }
        if let idToken = json["id_token"] as? String { updated.idToken = idToken }
        if let updateURL = tokenAccountUpdateURL(env: env) {
            try? writeCredentials(updated, to: updateURL, securePermissions: false)
        } else if shouldPersistSharedCredentials(env: env) {
            try? saveStoredCredentials(updated, env: env)
        }
        return RefreshResult(accessToken: accessToken, credentials: updated)
    }

    private struct OAuthClient {
        let clientID: String
        let clientSecret: String
    }

    private static func resolveOAuthClient(from credentials: Credentials, env: [String: String]) throws -> OAuthClient {
        // 1. 凭证内置。
        if let id = credentials.clientID?.trimmedNonEmpty,
           let secret = credentials.clientSecret?.trimmedNonEmpty
        {
            return OAuthClient(clientID: id, clientSecret: secret)
        }
        // 2. 环境变量。
        if let id = env["ANTIGRAVITY_OAUTH_CLIENT_ID"]?.trimmedNonEmpty,
           let secret = env["ANTIGRAVITY_OAUTH_CLIENT_SECRET"]?.trimmedNonEmpty
        {
            return OAuthClient(clientID: id, clientSecret: secret)
        }
        // 3. 从已安装的 Antigravity.app 二进制里发现。
        if let discovered = discoverClientFromInstalledApp() {
            return discovered
        }
        throw AntigravityUsageError.missingOAuthClient
    }

    private static func formBody(_ values: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.query?.data(using: .utf8)
    }

    // MARK: - Cloud Code 调用

    private static func loadCodeAssist(
        accessToken: String,
        env: [String: String],
        session: URLSession) async throws -> CodeAssistResponse
    {
        let body: [String: Any] = [
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI",
            ],
        ]
        return try await sendRequest(
            endpoint: endpoint("/v1internal:loadCodeAssist", env: env),
            accessToken: accessToken,
            body: body,
            session: session)
    }

    private static func resolveProjectID(
        accessToken: String,
        storedProjectID: String?,
        initialResponse: CodeAssistResponse,
        env: [String: String],
        session: URLSession) async throws -> String?
    {
        if let storedProjectID { return storedProjectID }
        if let projectID = initialResponse.projectID { return projectID }
        guard let tierID = pickOnboardTier(from: initialResponse) else { return nil }

        let onboardBody: [String: Any] = [
            "tierId": tierID,
            "metadata": [
                "ideType": "ANTIGRAVITY",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI",
            ],
        ]
        if let onboard: OnboardResponse = try? await sendRequest(
            endpoint: endpoint("/v1internal:onboardUser", env: env),
            accessToken: accessToken,
            body: onboardBody,
            session: session),
            let projectID = onboard.projectID
        {
            return projectID
        }
        // onboard 异步：轮询 loadCodeAssist 至多 5 次等 projectID 落地。
        for _ in 0 ..< 5 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let refreshed = try await loadCodeAssist(accessToken: accessToken, env: env, session: session)
            if let projectID = refreshed.projectID { return projectID }
        }
        return nil
    }

    private static func fetchModelQuotas(
        accessToken: String,
        projectID: String?,
        env: [String: String],
        session: URLSession) async throws -> [ModelQuota]
    {
        do {
            let response: FetchAvailableModelsResponse = try await sendRequest(
                endpoint: endpoint("/v1internal:fetchAvailableModels", env: env),
                accessToken: accessToken,
                body: projectBody(projectID),
                session: session)
            let quotas = parseModelQuotas(response)
            // 全部满额时再用 retrieveUserQuota 校验真实消耗（与 CodexBar 一致）。
            if shouldVerify(quotas),
               let verified = try? await fetchQuotaBuckets(
                   accessToken: accessToken,
                   projectID: projectID,
                   env: env,
                   session: session),
               hasConsumed(verified)
            {
                return mergeVerified(modelQuotas: quotas, verified: verified)
            }
            return quotas
        } catch let error as AntigravityUsageError {
            // fetchAvailableModels 被拒（403）时回退 retrieveUserQuota。
            guard case .server(403) = error else { throw error }
            return (try? await fetchQuotaBuckets(
                accessToken: accessToken,
                projectID: projectID,
                env: env,
                session: session)) ?? []
        }
    }

    private static func fetchQuotaBuckets(
        accessToken: String,
        projectID: String?,
        env: [String: String],
        session: URLSession) async throws -> [ModelQuota]?
    {
        do {
            let response: RetrieveUserQuotaResponse = try await sendRequest(
                endpoint: endpoint("/v1internal:retrieveUserQuota", env: env),
                accessToken: accessToken,
                body: projectBody(projectID),
                session: session)
            return parseQuotaBuckets(response)
        } catch let error as AntigravityUsageError {
            guard case .server(403) = error else { throw error }
            return nil
        }
    }

    private static func projectBody(_ projectID: String?) -> [String: Any] {
        if let projectID = projectID?.trimmedNonEmpty { ["project": projectID] } else { [:] }
    }

    private static func sendRequest<Response: Decodable>(
        endpoint: String,
        accessToken: String,
        body: [String: Any],
        session: URLSession) async throws -> Response
    {
        guard let url = URL(string: endpoint) else { throw AntigravityUsageError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, http) = try await perform(request, session: session)
        switch http.statusCode {
        case 200 ... 299:
            do { return try JSONDecoder().decode(Response.self, from: data) }
            catch { throw AntigravityUsageError.invalidResponse }
        case 401:
            throw AntigravityUsageError.unauthorized
        default:
            throw AntigravityUsageError.server(http.statusCode)
        }
    }

    private static func perform(_ request: URLRequest, session: URLSession) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AntigravityUsageError.invalidResponse }
            return (data, http)
        } catch let error as AntigravityUsageError {
            throw error
        } catch {
            throw AntigravityUsageError.network(error.localizedDescription)
        }
    }

    // MARK: - 解析额度

    /// 一个模型的额度（剩余分数 + 重置时间）。
    struct ModelQuota {
        let label: String
        let modelID: String
        let remainingFraction: Double?
        let resetTime: Date?

        /// 剩余百分比 0...100（无数据按 0）。
        var remainingPercent: Double {
            guard let remainingFraction else { return 0 }
            return max(0, min(100, remainingFraction * 100))
        }
    }

    private static func parseModelQuotas(_ response: FetchAvailableModelsResponse) -> [ModelQuota] {
        let models = response.models ?? [:]
        return models.compactMap { modelID, model in
            guard let quotaInfo = model.quotaInfo else { return nil }
            let label = model.displayName?.trimmedNonEmpty ?? model.label?.trimmedNonEmpty ?? modelID
            return ModelQuota(
                label: label,
                modelID: modelID,
                remainingFraction: quotaInfo.remainingFraction,
                resetTime: quotaInfo.resetTime.flatMap(parseResetTime))
        }
    }

    private static func parseQuotaBuckets(_ response: RetrieveUserQuotaResponse) -> [ModelQuota] {
        guard let buckets = response.buckets, !buckets.isEmpty else { return [] }
        var map: [String: (fraction: Double?, resetTime: String?)] = [:]
        for bucket in buckets {
            guard let modelID = bucket.modelId?.trimmedNonEmpty else { continue }
            let next = (bucket.remainingFraction, bucket.resetTime)
            if let existing = map[modelID] {
                let existingValue = existing.fraction ?? .greatestFiniteMagnitude
                let nextValue = next.0 ?? .greatestFiniteMagnitude
                if nextValue < existingValue { map[modelID] = next }
            } else {
                map[modelID] = next
            }
        }
        return map.keys.sorted().compactMap { modelID in
            guard let info = map[modelID] else { return nil }
            return ModelQuota(
                label: modelID,
                modelID: modelID,
                remainingFraction: info.fraction,
                resetTime: info.resetTime.flatMap(parseResetTime))
        }
    }

    private static func shouldVerify(_ quotas: [ModelQuota]) -> Bool {
        guard !quotas.isEmpty else { return false }
        return quotas.allSatisfy { ($0.remainingFraction ?? -1) >= 0.999 }
    }

    private static func hasConsumed(_ quotas: [ModelQuota]) -> Bool {
        quotas.contains { ($0.remainingFraction ?? 1.0) < 0.999 }
    }

    private static func mergeVerified(modelQuotas: [ModelQuota], verified: [ModelQuota]) -> [ModelQuota] {
        var verifiedByID = Dictionary(uniqueKeysWithValues: verified.map { (quotaKey($0), $0) })
        var merged = modelQuotas.map { quota -> ModelQuota in
            guard let v = verifiedByID.removeValue(forKey: quotaKey(quota)) else { return quota }
            return ModelQuota(
                label: quota.label,
                modelID: quota.modelID,
                remainingFraction: v.remainingFraction ?? quota.remainingFraction,
                resetTime: v.resetTime ?? quota.resetTime)
        }
        merged.append(contentsOf: verifiedByID.values
            .filter { $0.remainingFraction != nil }
            .sorted { $0.modelID.localizedCaseInsensitiveCompare($1.modelID) == .orderedAscending })
        return merged
    }

    private static func quotaKey(_ quota: ModelQuota) -> String {
        quota.modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func parseResetTime(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    // MARK: - 模型族 → 快照映射

    private enum Family { case claude, geminiPro, geminiFlash, unknown }

    private static func family(of quota: ModelQuota) -> Family {
        let text = (quota.modelID + " " + quota.label).lowercased()
        if text.contains("claude") { return .claude }
        if text.contains("gemini"), text.contains("pro") { return .geminiPro }
        if text.contains("gemini"), text.contains("flash") { return .geminiFlash }
        return .unknown
    }

    private static func isSummaryCandidate(_ quota: ModelQuota) -> Bool {
        let text = (quota.modelID + " " + quota.label).lowercased()
        let isLite = text.contains("lite")
        let isAutocomplete = text.contains("autocomplete") || quota.modelID.lowercased().hasPrefix("tab_")
        let isImage = text.contains("image")
        return family(of: quota) != .unknown && !isLite && !isAutocomplete && !isImage
    }

    /// 在某一族里取代表配额：优先有 remainingFraction 的，再取剩余最少的。
    private static func representative(for family: Family, in quotas: [ModelQuota]) -> ModelQuota? {
        let candidates = quotas.filter { self.family(of: $0) == family }
        guard !candidates.isEmpty else { return nil }
        return candidates.min { lhs, rhs in
            let lhsHas = lhs.remainingFraction != nil
            let rhsHas = rhs.remainingFraction != nil
            if lhsHas != rhsHas { return lhsHas && !rhsHas }
            if lhs.remainingPercent != rhs.remainingPercent { return lhs.remainingPercent < rhs.remainingPercent }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private static func makeSnapshot(quotas: [ModelQuota], planType: String?) -> UsageSnapshot {
        let summaryModels = quotas.filter { isSummaryCandidate($0) && $0.remainingFraction != nil }
        let claude = representative(for: .claude, in: summaryModels)
        let geminiPro = representative(for: .geminiPro, in: summaryModels)
        let geminiFlash = representative(for: .geminiFlash, in: summaryModels)

        // primary = Claude 族（无则回退到剩余最少的可用模型）；secondary = Gemini Pro 族；
        // tertiary = Gemini Flash 族（照搬 CodexBar 的 `tertiary: tertiary`）。
        let primaryQuota = claude ?? geminiPro ?? geminiFlash ?? summaryModels.min {
            $0.remainingPercent < $1.remainingPercent
        }
        let secondaryQuota: ModelQuota? = (claude != nil) ? geminiPro : nil
        let tertiaryQuota: ModelQuota? = geminiFlash

        // extraRateWindows：把全部 summary 模型按剩余%（再按标签）排序后逐条建命名窗，
        // 照搬 CodexBar 的 `extraRateWindows: extraWindows`（id=modelID、title=label、
        // window=该模型的 RateWindow）。空则不带额外窗。
        let extraWindows = summaryModels
            .sorted { lhs, rhs in
                if lhs.remainingPercent != rhs.remainingPercent {
                    return lhs.remainingPercent < rhs.remainingPercent
                }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            .map { quota in
                NamedRateWindow(id: quota.modelID, title: quota.label, window: rateWindow(for: quota))
            }

        return UsageSnapshot(
            primary: primaryQuota.map(rateWindow(for:)),
            secondary: secondaryQuota.map(rateWindow(for:)),
            tertiary: tertiaryQuota.map(rateWindow(for:)),
            extraRateWindows: extraWindows,
            planName: planType)
    }

    // MARK: - 本地响应解析

    private static func parseLocalQuotaSummary(_ data: Data) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(LocalQuotaSummaryResponse.self, from: data)
        if let invalid = invalidLocalCode(response.code) { throw AntigravityUsageError.cliFailed(invalid) }
        let payload = response.response ?? response.summary ?? response.rootPayload
        guard let payload else { throw AntigravityUsageError.invalidResponse }

        let windows = payload.groups
            .compactMap(localQuotaSummaryGroup)
            .flatMap { group in
                group.buckets.map { bucket -> NamedRateWindow in
                    let usedPercent = bucket.remainingFraction.map { max(0, min(100, 100 - ($0 * 100))) } ?? 0
                    let title = "\(group.displayName) \(bucket.displayName)"
                    return NamedRateWindow(
                        id: "antigravity-quota-summary-\(bucket.bucketId)",
                        title: title,
                        window: RateWindow(
                            title: bucket.displayName,
                            usedPercent: usedPercent,
                            windowMinutes: localWindowMinutes(for: bucket),
                            resetsAt: bucket.resetTime,
                            resetDescription: bucket.resetDescription))
                }
            }
        guard !windows.isEmpty else { throw AntigravityUsageError.invalidResponse }

        let primary = localQuotaSummaryRepresentative(
            matching: { $0.lowercased().contains("gemini") },
            in: windows)
        let secondary = localQuotaSummaryRepresentative(
            matching: { $0.lowercased().contains("claude") || $0.lowercased().contains("gpt") },
            in: windows)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            extraRateWindows: windows)
    }

    private struct LocalQuotaSummaryGroup {
        let displayName: String
        let buckets: [LocalQuotaSummaryBucket]
    }

    private struct LocalQuotaSummaryBucket {
        let bucketId: String
        let displayName: String
        let remainingFraction: Double?
        let resetTime: Date?
        let resetDescription: String?
        let disabled: Bool
    }

    private static func localQuotaSummaryGroup(_ payload: LocalQuotaSummaryGroupPayload) -> LocalQuotaSummaryGroup? {
        let buckets = (payload.buckets ?? [])
            .compactMap(localQuotaSummaryBucket)
            .filter { !$0.disabled }
        guard !buckets.isEmpty else { return nil }
        return LocalQuotaSummaryGroup(
            displayName: payload.displayName?.trimmedNonEmpty ?? "Quota",
            buckets: buckets)
    }

    private static func localQuotaSummaryBucket(_ payload: LocalQuotaSummaryBucketPayload) -> LocalQuotaSummaryBucket? {
        guard let bucketID = payload.bucketId?.trimmedNonEmpty else { return nil }
        return LocalQuotaSummaryBucket(
            bucketId: bucketID,
            displayName: payload.displayName?.trimmedNonEmpty ?? bucketID,
            remainingFraction: payload.resolvedRemainingFraction,
            resetTime: payload.resetTime.flatMap(parseResetTime),
            resetDescription: payload.description,
            disabled: payload.disabled ?? false)
    }

    private static func localQuotaSummaryRepresentative(
        matching predicate: (String) -> Bool,
        in windows: [NamedRateWindow]) -> RateWindow?
    {
        windows
            .filter { predicate($0.title) }
            .max { lhs, rhs in
                if lhs.window.usedPercent != rhs.window.usedPercent {
                    return lhs.window.usedPercent < rhs.window.usedPercent
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedDescending
            }?
            .window
    }

    private static func localWindowMinutes(for bucket: LocalQuotaSummaryBucket) -> Int? {
        let combined = "\(bucket.bucketId) \(bucket.displayName)".lowercased()
        if combined.contains("5h") || combined.contains("5-hour") || combined.contains("five hour") {
            return 300
        }
        if combined.contains("weekly") {
            return 10_080
        }
        return nil
    }

    private static func parseLocalUserStatus(_ data: Data) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(LocalUserStatusResponse.self, from: data)
        if let invalid = invalidLocalCode(response.code) { throw AntigravityUsageError.cliFailed(invalid) }
        guard let status = response.userStatus else { throw AntigravityUsageError.invalidResponse }
        let quotas = (status.cascadeModelConfigData?.clientModelConfigs ?? [])
            .compactMap(localQuota(from:))
        let plan = status.userTier?.preferredName ?? status.planStatus?.planInfo?.preferredName
        var snapshot = makeSnapshot(quotas: quotas, planType: plan)
        snapshot.accountLabel = status.email?.trimmedNonEmpty
        return snapshot
    }

    private static func parseLocalCommandModels(_ data: Data) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(LocalCommandModelConfigResponse.self, from: data)
        if let invalid = invalidLocalCode(response.code) { throw AntigravityUsageError.cliFailed(invalid) }
        let quotas = (response.clientModelConfigs ?? []).compactMap(localQuota(from:))
        return makeSnapshot(quotas: quotas, planType: nil)
    }

    private static func localQuota(from config: LocalModelConfig) -> ModelQuota? {
        guard let quota = config.quotaInfo else { return nil }
        let modelID = config.modelOrAlias.model.trimmedNonEmpty ?? config.label
        return ModelQuota(
            label: config.label.trimmedNonEmpty ?? modelID,
            modelID: modelID,
            remainingFraction: quota.remainingFraction,
            resetTime: quota.resetTime.flatMap(parseResetTime))
    }

    private static func invalidLocalCode(_ code: LocalCodeValue?) -> String? {
        guard let code else { return nil }
        return code.isOK ? nil : code.rawValue
    }

    /// 单条额度 → RateWindow。Antigravity 无周期窗口，windowMinutes 记 nil；
    /// usedPercent = 100 - 剩余%；resetsAt 取重置时间（无则 now+30 天）。
    private static func rateWindow(for quota: ModelQuota) -> RateWindow {
        let used = max(0, min(100, (100 - quota.remainingPercent).rounded()))
        let reset = quota.resetTime ?? Date().addingTimeInterval(30 * 86400)
        return RateWindow(
            title: quota.label,
            usedPercent: used,
            windowMinutes: nil,
            resetsAt: reset)
    }

    // MARK: - 计划解析

    private struct TokenClaims {
        let email: String?
        let hostedDomain: String?
    }

    private static func extractClaims(from credentials: Credentials) -> TokenClaims {
        let fromToken = claimsFromIDToken(credentials.idToken)
        return TokenClaims(
            email: fromToken.email ?? credentials.email?.trimmedNonEmpty,
            hostedDomain: fromToken.hostedDomain)
    }

    private static func claimsFromIDToken(_ idToken: String?) -> TokenClaims {
        guard let idToken else { return TokenClaims(email: nil, hostedDomain: nil) }
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return TokenClaims(email: nil, hostedDomain: nil) }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 { payload += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return TokenClaims(email: nil, hostedDomain: nil) }
        return TokenClaims(
            email: (json["email"] as? String)?.trimmedNonEmpty,
            hostedDomain: (json["hd"] as? String)?.trimmedNonEmpty)
    }

    private static func resolvePlan(response: CodeAssistResponse, claims: TokenClaims) -> String? {
        if let planType = response.planInfo?.planType?.trimmedNonEmpty { return planType }
        switch (response.currentTier?.id?.trimmedNonEmpty, claims.hostedDomain) {
        case ("standard-tier", _): return "Paid"
        case ("free-tier", .some): return "Workspace"
        case ("free-tier", .none): return "Free"
        case ("legacy-tier", _): return "Legacy"
        default: return response.currentTier?.name?.trimmedNonEmpty
        }
    }

    private static func pickOnboardTier(from response: CodeAssistResponse) -> String? {
        if let defaultTier = response.allowedTiers?
            .first(where: { $0.isDefault == true && $0.id?.trimmedNonEmpty != nil })?.id?.trimmedNonEmpty
        { return defaultTier }
        if let firstTier = response.allowedTiers?.first(where: { $0.id?.trimmedNonEmpty != nil })?.id?.trimmedNonEmpty {
            return firstTier
        }
        if let paidTier = response.paidTier?.id?.trimmedNonEmpty { return paidTier }
        return response.currentTier?.id?.trimmedNonEmpty
    }

    // MARK: - 从已安装 App 二进制发现 OAuth 客户端（照搬 AntigravityOAuthConfig）

    private static func discoverClientFromInstalledApp() -> OAuthClient? {
        let fileManager = FileManager.default
        for url in candidateOAuthClientArtifactURLs(fileManager: fileManager)
            where fileManager.fileExists(atPath: url.path)
        {
            guard let data = try? Data(contentsOf: url),
                  let client = parseClient(fromArtifactData: data)
            else { continue }
            return client
        }
        return nil
    }

    private static func candidateOAuthClientArtifactURLs(fileManager: FileManager) -> [URL] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        let relativePaths = [
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_arm",
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos_x64",
            "Contents/Resources/app/extensions/antigravity/bin/language_server_macos",
            "Contents/Resources/app/out/main.js",
            "Contents/Resources/bin/language_server",
            "Contents/Resources/bin/language_server_macos",
        ]
        var bundleURLs: [URL] = []
        var seen = Set<String>()
        for root in roots {
            let candidate = root.appendingPathComponent("Antigravity.app", isDirectory: true)
            if seen.insert(candidate.standardizedFileURL.path).inserted { bundleURLs.append(candidate) }
            let appURLs = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for appURL in appURLs where appURL.pathExtension == "app" && isAntigravityAppBundle(appURL) {
                if seen.insert(appURL.standardizedFileURL.path).inserted { bundleURLs.append(appURL) }
            }
        }
        return bundleURLs.flatMap { bundle in relativePaths.map { bundle.appendingPathComponent($0) } }
    }

    private static func isAntigravityAppBundle(_ url: URL) -> Bool {
        switch Bundle(url: url)?.bundleIdentifier {
        case "com.google.antigravity", "com.google.antigravity-ide": true
        default: false
        }
    }

    private static func parseClient(fromArtifactData data: Data) -> OAuthClient? {
        if let content = String(data: data, encoding: .utf8),
           let client = parseClient(fromArtifactText: content)
        { return client }

        let clientIDs = clientIDs(in: data)
        let clientSecrets = clientSecrets(in: data)
        guard !clientIDs.isEmpty, !clientSecrets.isEmpty else { return nil }

        if clientSecrets.count == 1, clientIDs.count > 1 {
            return OAuthClient(clientID: clientIDs[clientIDs.count - 1], clientSecret: clientSecrets[0])
        }
        let secret: String = if clientSecrets.count == clientIDs.count, clientSecrets.count > 1 {
            clientSecrets[clientSecrets.count - 1]
        } else {
            clientSecrets[0]
        }
        return OAuthClient(clientID: clientIDs[0], clientSecret: secret)
    }

    private static func parseClient(fromArtifactText content: String) -> OAuthClient? {
        let marker = "vs/platform/cloudCode/common/oauthClient.js"
        let searchStart = content.range(of: marker)?.lowerBound ?? content.startIndex
        let searchEnd = content.index(searchStart, offsetBy: 4000, limitedBy: content.endIndex) ?? content.endIndex
        let haystack = String(content[searchStart ..< searchEnd])
        guard let clientID = firstMatch(
            pattern: #"[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com"#, in: haystack),
            let clientSecret = firstMatch(pattern: #"GOCSPX-[A-Za-z0-9_-]{28}"#, in: haystack)
        else { return nil }
        return OAuthClient(clientID: clientID, clientSecret: clientSecret)
    }

    private static func clientIDs(in data: Data) -> [String] {
        let suffix = Data(".apps.googleusercontent.com".utf8)
        var searchRange = data.startIndex ..< data.endIndex
        var values: [String] = []
        while let range = data.range(of: suffix, options: [], in: searchRange) {
            var start = range.lowerBound
            while start > data.startIndex {
                let previous = data.index(before: start)
                guard isOAuthByte(data[previous]) else { break }
                start = previous
            }
            if let candidate = String(data: Data(data[start ..< range.upperBound]), encoding: .ascii),
               let clientID = firstMatch(
                   pattern: #"[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com"#, in: candidate)
            { values.append(clientID) }
            searchRange = range.upperBound ..< data.endIndex
        }
        return unique(values)
    }

    private static func clientSecrets(in data: Data) -> [String] {
        let prefix = Data("GOCSPX-".utf8)
        let secretLength = 35
        var searchRange = data.startIndex ..< data.endIndex
        var values: [String] = []
        while let range = data.range(of: prefix, options: [], in: searchRange) {
            let end = range.lowerBound + secretLength
            if end <= data.endIndex {
                let candidateData = Data(data[range.lowerBound ..< end])
                if candidateData.dropFirst(prefix.count).allSatisfy(isOAuthByte),
                   let candidate = String(data: candidateData, encoding: .ascii)
                { values.append(candidate) }
            }
            searchRange = range.upperBound ..< data.endIndex
        }
        return unique(values)
    }

    private static func isOAuthByte(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122) || byte == 45 || byte == 95
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // MARK: - 凭证模型（照搬 AntigravityOAuthCredentials 的解码键，snake/camel 双兼容）

    struct Credentials: Codable {
        var accessToken: String?
        var refreshToken: String?
        var expiryDateMilliseconds: Double?
        var idToken: String?
        var email: String?
        var projectID: String?
        var clientID: String?
        var clientSecret: String?

        var expiryDate: Date? {
            guard let expiryDateMilliseconds else { return nil }
            return Date(timeIntervalSince1970: expiryDateMilliseconds / 1000)
        }

        enum CodingKeys: String, CodingKey {
            case accessTokenSnake = "access_token"
            case accessTokenCamel = "accessToken"
            case refreshTokenSnake = "refresh_token"
            case refreshTokenCamel = "refreshToken"
            case expiryDateSnake = "expiry_date"
            case expiresAtCamel = "expiresAt"
            case idTokenSnake = "id_token"
            case idTokenCamel = "idToken"
            case email
            case projectIDSnake = "project_id"
            case projectIDCamel = "projectId"
            case clientIDSnake = "client_id"
            case clientIDCamel = "clientId"
            case clientSecretSnake = "client_secret"
            case clientSecretCamel = "clientSecret"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try c.decodeIfPresent(String.self, forKey: .accessTokenSnake)
                ?? c.decodeIfPresent(String.self, forKey: .accessTokenCamel)
            refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshTokenSnake)
                ?? c.decodeIfPresent(String.self, forKey: .refreshTokenCamel)
            idToken = try c.decodeIfPresent(String.self, forKey: .idTokenSnake)
                ?? c.decodeIfPresent(String.self, forKey: .idTokenCamel)
            email = try c.decodeIfPresent(String.self, forKey: .email)
            projectID = try c.decodeIfPresent(String.self, forKey: .projectIDSnake)
                ?? c.decodeIfPresent(String.self, forKey: .projectIDCamel)
            clientID = try c.decodeIfPresent(String.self, forKey: .clientIDSnake)
                ?? c.decodeIfPresent(String.self, forKey: .clientIDCamel)
            clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecretSnake)
                ?? c.decodeIfPresent(String.self, forKey: .clientSecretCamel)
            if let ms = try c.decodeIfPresent(Double.self, forKey: .expiryDateSnake)
                ?? c.decodeIfPresent(Double.self, forKey: .expiresAtCamel)
            {
                expiryDateMilliseconds = ms
            } else if let ms = try c.decodeIfPresent(Int.self, forKey: .expiryDateSnake)
                ?? c.decodeIfPresent(Int.self, forKey: .expiresAtCamel)
            {
                expiryDateMilliseconds = Double(ms)
            } else {
                expiryDateMilliseconds = nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(accessToken, forKey: .accessTokenSnake)
            try c.encodeIfPresent(refreshToken, forKey: .refreshTokenSnake)
            try c.encodeIfPresent(expiryDateMilliseconds, forKey: .expiryDateSnake)
            try c.encodeIfPresent(idToken, forKey: .idTokenSnake)
            try c.encodeIfPresent(email, forKey: .email)
            try c.encodeIfPresent(projectID, forKey: .projectIDSnake)
            try c.encodeIfPresent(clientID, forKey: .clientIDSnake)
            try c.encodeIfPresent(clientSecret, forKey: .clientSecretSnake)
        }
    }

    // MARK: - 响应模型

    private struct LocalUserStatusResponse: Decodable {
        let code: LocalCodeValue?
        let message: String?
        let userStatus: LocalUserStatus?
    }

    private struct LocalCommandModelConfigResponse: Decodable {
        let code: LocalCodeValue?
        let message: String?
        let clientModelConfigs: [LocalModelConfig]?
    }

    private struct LocalUserStatus: Decodable {
        let email: String?
        let planStatus: LocalPlanStatus?
        let cascadeModelConfigData: LocalModelConfigData?
        let userTier: LocalUserTier?
    }

    private struct LocalUserTier: Decodable {
        let id: String?
        let name: String?
        let description: String?

        var preferredName: String? { name?.trimmedNonEmpty ?? description?.trimmedNonEmpty ?? id?.trimmedNonEmpty }
    }

    private struct LocalPlanStatus: Decodable {
        let planInfo: LocalPlanInfo?
    }

    private struct LocalPlanInfo: Decodable {
        let planName: String?
        let planDisplayName: String?
        let displayName: String?
        let productName: String?
        let planShortName: String?

        var preferredName: String? {
            [planDisplayName, displayName, productName, planName, planShortName]
                .compactMap { $0?.trimmedNonEmpty }
                .first
        }
    }

    private struct LocalModelConfigData: Decodable {
        let clientModelConfigs: [LocalModelConfig]?
    }

    private struct LocalModelConfig: Decodable {
        let label: String
        let modelOrAlias: LocalModelAlias
        let quotaInfo: LocalQuotaInfo?
    }

    private struct LocalModelAlias: Decodable {
        let model: String
    }

    private struct LocalQuotaInfo: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
    }

    private enum LocalCodeValue: Decodable {
        case int(Int)
        case string(String)

        var isOK: Bool {
            switch self {
            case let .int(value):
                return value == 0
            case let .string(value):
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "", "0", "ok", "success":
                    return true
                default:
                    return false
                }
            }
        }

        var rawValue: String {
            switch self {
            case let .int(value): String(value)
            case let .string(value): value
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else {
                self = .string((try? container.decode(String.self)) ?? "")
            }
        }
    }

    private struct LocalQuotaSummaryResponse: Decodable {
        let code: LocalCodeValue?
        let message: String?
        let response: LocalQuotaSummaryPayload?
        let summary: LocalQuotaSummaryPayload?
        let description: String?
        let groups: [LocalQuotaSummaryGroupPayload]?

        var rootPayload: LocalQuotaSummaryPayload? {
            guard let groups else { return nil }
            return LocalQuotaSummaryPayload(description: description, groups: groups)
        }
    }

    private struct LocalQuotaSummaryPayload: Decodable {
        let description: String?
        let groups: [LocalQuotaSummaryGroupPayload]

        init(description: String?, groups: [LocalQuotaSummaryGroupPayload]) {
            self.description = description
            self.groups = groups
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            groups = (try? container.decode([LocalQuotaSummaryGroupPayload].self, forKey: .groups)) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case description
            case groups
        }
    }

    private struct LocalQuotaSummaryGroupPayload: Decodable {
        let displayName: String?
        let description: String?
        let buckets: [LocalQuotaSummaryBucketPayload]?
    }

    private struct LocalQuotaSummaryBucketPayload: Decodable {
        let bucketId: String?
        let displayName: String?
        let description: String?
        let disabled: Bool?
        let remainingFraction: Double?
        let remaining: LocalQuotaSummaryRemainingPayload?
        let resetTime: String?

        var resolvedRemainingFraction: Double? {
            remainingFraction ?? remaining?.remainingFraction
        }
    }

    private struct LocalQuotaSummaryRemainingPayload: Decodable {
        let remainingFraction: Double?

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let direct = try? container.decode(Double.self)
            {
                remainingFraction = direct
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction)
                ?? container.decodeIfPresent(Double.self, forKey: .value)
        }

        enum CodingKeys: String, CodingKey {
            case remainingFraction
            case value
        }
    }

    private struct CodeAssistResponse: Decodable {
        let planInfo: PlanInfo?
        let currentTier: TierInfo?
        let paidTier: TierInfo?
        let allowedTiers: [AllowedTier]?
        let cloudaicompanionProject: ProjectReference?

        var projectID: String? {
            cloudaicompanionProject?.value?.trimmedNonEmpty
        }
    }

    private struct PlanInfo: Decodable { let planType: String? }
    private struct TierInfo: Decodable { let id: String?; let name: String? }
    private struct AllowedTier: Decodable { let id: String?; let isDefault: Bool? }

    private struct ProjectReference: Decodable {
        let value: String?
        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let stringValue = try? single.decode(String.self)
            {
                value = stringValue
                return
            }
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            value = try keyed.decodeIfPresent(String.self, forKey: .id)
                ?? keyed.decodeIfPresent(String.self, forKey: .projectID)
        }

        enum CodingKeys: String, CodingKey {
            case id
            case projectID = "projectId"
        }
    }

    private struct OnboardResponse: Decodable {
        let response: Inner?
        var projectID: String? { response?.cloudaicompanionProject?.value?.trimmedNonEmpty }
        struct Inner: Decodable { let cloudaicompanionProject: ProjectReference? }
    }

    private struct FetchAvailableModelsResponse: Decodable {
        let models: [String: RemoteModel]?
    }

    private struct RemoteModel: Decodable {
        let displayName: String?
        let label: String?
        let quotaInfo: RemoteQuotaInfo?
    }

    private struct RemoteQuotaInfo: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
    }

    private struct RetrieveUserQuotaResponse: Decodable {
        let buckets: [QuotaBucket]?
    }

    private struct QuotaBucket: Decodable {
        let modelId: String?
        let remainingFraction: Double?
        let resetTime: String?
    }
}

extension Optional where Wrapped == String {
    fileprivate var trimmedNonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
