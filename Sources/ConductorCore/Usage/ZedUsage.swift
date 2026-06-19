import Foundation
#if os(macOS)
import Darwin
#endif
#if canImport(Security)
import Security
#endif
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Zed 用量取数。转写自 CodexBar `ZedStatusProbe`：
/// 读取 `~/.config/zed/settings.json` 中的 `credentials_url` / `server_url`，
/// 从 macOS Keychain 读取 Zed 凭证，再请求 `https://cloud.zed.dev/client/users/me`
/// 或可信自定义 HTTPS server 的 `/client/users/me`。
public enum ZedUsageError: LocalizedError, Sendable, Equatable {
    case notSupported
    case notSignedIn
    case keychainUnavailable
    case invalidServerURL(String)
    case untrustedServerConfiguration
    case network(String)
    case server(Int)
    case unauthorized
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notSupported:
            L("Zed 仅支持 macOS 本地登录态")
        case .notSignedIn:
            L("未登录 Zed，请先在 Zed 编辑器中使用 GitHub 登录")
        case .keychainUnavailable:
            L("无法从钥匙串读取 Zed 凭证，请重新登录 Zed 或检查钥匙串权限")
        case let .invalidServerURL(value):
            L("Zed server URL 无效：%@", value)
        case .untrustedServerConfiguration:
            L("Zed 自定义 server 必须使用 HTTPS，且凭证 URL 必须与 server URL 一致")
        case let .network(message):
            L("Zed 云端 API 请求失败：%@", message)
        case let .server(code):
            L("Zed 云端 API 返回 HTTP %ld", code)
        case .unauthorized:
            L("Zed 凭证无效或已过期，请重新登录 Zed")
        case let .parseFailed(message):
            L("解析 Zed 账号响应失败：%@", message)
        }
    }
}

public enum ZedUsageFetcher {
    static let defaultKeychainServiceURL = "https://zed.dev"
    static let defaultCloudAPIURL = URL(string: "https://cloud.zed.dev/client/users/me")!

    public static func hasCredentials(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        #if canImport(Security)
        let serviceURL = (loadSettings(env: env)?.keychainServiceURL).flatMap(nonEmpty)
            ?? defaultKeychainServiceURL
        return keychainItemExists(serviceURL: serviceURL)
        #else
        return false
        #endif
    }

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        #if canImport(Security)
        let settings = loadSettings(env: env)
        let serviceURL = settings?.keychainServiceURL ?? defaultKeychainServiceURL
        let apiURL: URL
        if let settings {
            guard let configuredURL = settings.cloudAPIURL else {
                let serverURL = settings.serverURL ?? ""
                guard URL(string: serverURL)?.scheme?.lowercased() == "https" else {
                    throw ZedUsageError.invalidServerURL(serverURL)
                }
                throw ZedUsageError.untrustedServerConfiguration
            }
            apiURL = configuredURL
        } else {
            apiURL = defaultCloudAPIURL
        }

        guard let credentials = try loadCredentials(serviceURL: serviceURL) else {
            throw ZedUsageError.notSignedIn
        }
        let response = try await fetchAuthenticatedUser(credentials: credentials, apiURL: apiURL, session: session)
        return response.toUsageSnapshot(updatedAt: Date()).withSourceLabel("local")
        #else
        _ = env
        _ = session
        throw ZedUsageError.notSupported
        #endif
    }

    // MARK: - Settings

    struct ClientSettings: Sendable, Equatable {
        let credentialsURL: String?
        let serverURL: String?

        var keychainServiceURL: String {
            if let value = Self.trimmed(credentialsURL) { return value }
            if let value = Self.trimmed(serverURL) { return value }
            return defaultKeychainServiceURL
        }

        var cloudAPIURL: URL? {
            let server = Self.trimmed(serverURL) ?? defaultKeychainServiceURL
            let trustedZedServer = server == "https://zed.dev" || server == "https://staging.zed.dev"
            if !trustedZedServer,
               let credentials = Self.trimmed(credentialsURL),
               credentials != server
            {
                return nil
            }

            let cloudBase = switch server {
            case "https://zed.dev", "https://staging.zed.dev":
                "https://cloud.zed.dev"
            default:
                server
            }
            guard let baseURL = URL(string: cloudBase),
                  baseURL.scheme?.lowercased() == "https",
                  baseURL.host != nil
            else {
                return nil
            }
            return baseURL.appendingPathComponent("client/users/me")
        }

        private static func trimmed(_ raw: String?) -> String? {
            let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
    }

    static func settingsURL(env: [String: String]) -> URL {
        if let override = nonEmpty(env["ZED_SETTINGS_PATH"]) {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/zed/settings.json")
    }

    static func loadSettings(env: [String: String] = ProcessInfo.processInfo.environment) -> ClientSettings? {
        struct Payload: Decodable {
            let credentialsURL: String?
            let serverURL: String?

            enum CodingKeys: String, CodingKey {
                case credentialsURL = "credentials_url"
                case serverURL = "server_url"
            }
        }
        guard let data = try? Data(contentsOf: settingsURL(env: env)),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return ClientSettings(credentialsURL: payload.credentialsURL, serverURL: payload.serverURL)
    }

    // MARK: - Credentials

    struct Credentials: Sendable, Equatable {
        let userID: String
        let accessToken: String

        var authorizationHeader: String { "\(userID) \(accessToken)" }
    }

    #if canImport(Security)
    static func keychainItemExists(serviceURL: String) -> Bool {
        keychainItemExists(kind: .internetPassword, serviceURL: serviceURL)
            || keychainItemExists(kind: .genericPassword, serviceURL: serviceURL)
    }

    private enum KeychainKind {
        case internetPassword
        case genericPassword
    }

    private static let keychainUIFailPolicy = resolveKeychainUIFailPolicy()

    private static func keychainItemExists(kind: KeychainKind, serviceURL: String) -> Bool {
        var query = baseKeychainQuery(kind: kind, serviceURL: serviceURL)
        applyNoUI(to: &query)
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func loadCredentials(serviceURL: String) throws -> Credentials? {
        if let credentials = try loadCredentials(kind: .internetPassword, serviceURL: serviceURL) {
            return credentials
        }
        return try loadCredentials(kind: .genericPassword, serviceURL: serviceURL)
    }

    private static func loadCredentials(kind: KeychainKind, serviceURL: String) throws -> Credentials? {
        var query = baseKeychainQuery(kind: kind, serviceURL: serviceURL)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        applyNoUI(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecNoAccessForItem:
            throw ZedUsageError.keychainUnavailable
        default:
            throw ZedUsageError.keychainUnavailable
        }

        guard let item = result as? [String: Any],
              let account = nonEmpty(item[kSecAttrAccount as String] as? String),
              let tokenData = item[kSecValueData as String] as? Data,
              let accessToken = nonEmpty(String(data: tokenData, encoding: .utf8))
        else {
            return nil
        }
        return Credentials(userID: account, accessToken: accessToken)
    }

    private static func baseKeychainQuery(kind: KeychainKind, serviceURL: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        switch kind {
        case .internetPassword:
            query[kSecClass as String] = kSecClassInternetPassword
            query[kSecAttrServer as String] = serviceURL
        case .genericPassword:
            query[kSecClass as String] = kSecClassGenericPassword
            query[kSecAttrService as String] = serviceURL
        }
        return query
    }

    private static func applyNoUI(to query: inout [String: Any]) {
        #if canImport(LocalAuthentication)
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        #endif
        query[kSecUseAuthenticationUI as String] = keychainUIFailPolicy as CFString
    }

    private static func resolveKeychainUIFailPolicy() -> String {
        #if os(macOS)
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
        #else
        return "u_AuthUIF"
        #endif
    }
    #endif

    // MARK: - Network / Parse

    private static func fetchAuthenticatedUser(
        credentials: Credentials,
        apiURL: URL,
        session: URLSession) async throws -> AuthenticatedUserResponse
    {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(credentials.authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw ZedUsageError.parseFailed("no HTTP response") }
            data = responseData
            http = response
        } catch let error as ZedUsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ZedUsageError.network(error.localizedDescription)
        }

        switch http.statusCode {
        case 200:
            return try parseResponse(data)
        case 401, 403:
            throw ZedUsageError.unauthorized
        default:
            throw ZedUsageError.server(http.statusCode)
        }
    }

    static func parseSnapshot(_ data: Data, updatedAt: Date = Date(), now: Date = Date()) throws -> UsageSnapshot {
        try parseResponse(data).toUsageSnapshot(updatedAt: updatedAt, now: now)
            .withSourceLabel("local")
    }

    static func parseResponse(_ data: Data) throws -> AuthenticatedUserResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseISO8601Date(value) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(value)")
        }
        do {
            return try decoder.decode(AuthenticatedUserResponse.self, from: data)
        } catch {
            throw ZedUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    static func nonEmpty(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

extension ZedUsageFetcher {
    struct AuthenticatedUserResponse: Decodable, Equatable, Sendable {
        let user: AuthenticatedUser
        let plan: PlanInfo
    }

    struct AuthenticatedUser: Decodable, Equatable, Sendable {
        let id: Int
        let githubLogin: String
        let name: String?

        enum CodingKeys: String, CodingKey {
            case id
            case githubLogin = "github_login"
            case name
        }
    }

    struct PlanInfo: Decodable, Equatable, Sendable {
        let planV3: String
        let subscriptionPeriod: SubscriptionPeriod?
        let usage: CurrentUsage
        let hasOverdueInvoices: Bool

        enum CodingKeys: String, CodingKey {
            case planV3 = "plan_v3"
            case subscriptionPeriod = "subscription_period"
            case usage
            case hasOverdueInvoices = "has_overdue_invoices"
        }
    }

    struct SubscriptionPeriod: Decodable, Equatable, Sendable {
        let startedAt: Date
        let endedAt: Date

        enum CodingKeys: String, CodingKey {
            case startedAt = "started_at"
            case endedAt = "ended_at"
        }
    }

    struct CurrentUsage: Decodable, Equatable, Sendable {
        let editPredictions: UsageData

        enum CodingKeys: String, CodingKey {
            case editPredictions = "edit_predictions"
        }
    }

    struct UsageData: Decodable, Equatable, Sendable {
        let used: Int
        let limit: UsageLimit
    }

    enum UsageLimit: Decodable, Equatable, Sendable {
        case limited(Int)
        case unlimited

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer() {
                if let string = try? single.decode(String.self), string == "unlimited" {
                    self = .unlimited
                    return
                }
                if let value = try? single.decode(Int.self) {
                    self = .limited(value)
                    return
                }
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try container.decodeIfPresent(Int.self, forKey: .limited) {
                self = .limited(value)
                return
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized Zed usage limit"))
        }

        private enum CodingKeys: String, CodingKey {
            case limited
        }
    }
}

private extension ZedUsageFetcher.AuthenticatedUserResponse {
    func toUsageSnapshot(updatedAt: Date, now: Date = Date()) -> UsageSnapshot {
        let primary = Self.makeEditPredictionsWindow(
            used: plan.usage.editPredictions.used,
            limit: plan.usage.editPredictions.limit)
        let secondary = plan.subscriptionPeriod.map { period in
            RateWindow(
                title: L("账单周期"),
                usedPercent: Self.billingCycleUsedPercent(
                    startedAt: period.startedAt,
                    endedAt: period.endedAt,
                    now: now),
                resetsAt: period.endedAt,
                resetDescription: Self.formatResetDescription(period.endedAt, now: now))
        }

        var extras: [NamedRateWindow] = []
        if plan.hasOverdueInvoices {
            extras.append(NamedRateWindow(
                id: "zed.overdue-invoices",
                title: L("账单"),
                window: RateWindow(
                    title: L("账单"),
                    usedPercent: 100,
                    resetDescription: L("逾期账单"))))
        }

        let account = [user.githubLogin.nilIfEmpty, user.name?.nilIfEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")

        return UsageSnapshot(
            sourceLabel: "local",
            primary: primary,
            secondary: secondary,
            extraRateWindows: extras,
            planName: Self.displayPlanName(plan.planV3),
            accountLabel: account.isEmpty ? nil : account,
            updatedAt: updatedAt)
    }

    static func makeEditPredictionsWindow(
        used: Int,
        limit: ZedUsageFetcher.UsageLimit) -> RateWindow?
    {
        switch limit {
        case .unlimited:
            return RateWindow(
                title: L("编辑预测"),
                usedPercent: 0,
                resetDescription: L("无限制"))
        case let .limited(total):
            guard total > 0 else { return nil }
            let clampedUsed = max(0, min(total, used))
            return RateWindow(
                title: L("编辑预测"),
                usedPercent: Double(clampedUsed) / Double(total) * 100,
                resetDescription: L("%1$ld / %2$ld 次预测", clampedUsed, total))
        }
    }

    static func displayPlanName(_ rawPlan: String) -> String {
        switch rawPlan.lowercased() {
        case "zed_free": "Zed Free"
        case "zed_pro": "Zed Pro"
        case "zed_pro_trial": "Zed Pro Trial"
        case "zed_student": "Zed Student"
        case "zed_business": "Zed Business"
        default:
            rawPlan
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { word in
                    word.prefix(1).uppercased() + word.dropFirst().lowercased()
                }
                .joined(separator: " ")
        }
    }

    static func billingCycleUsedPercent(startedAt: Date, endedAt: Date, now: Date) -> Double {
        let total = endedAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 0 }
        return max(0, min(100, now.timeIntervalSince(startedAt) / total * 100))
    }

    static func formatResetDescription(_ date: Date, now: Date) -> String? {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return L("周期已结束") }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return L("%1$ld 天 %2$ld 小时后结束", days, remainingHours)
        } else if hours > 0 {
            return L("%1$ld 小时 %2$ld 分钟后结束", hours, minutes)
        } else {
            return L("%ld 分钟后结束", minutes)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
