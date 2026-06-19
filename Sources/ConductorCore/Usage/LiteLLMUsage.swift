import Foundation

/// LiteLLM 用量取数。转写自 CodexBar `LiteLLMUsageFetcher`：
/// 使用 LiteLLM virtual key 和 proxy base URL，先读 `/key/info`，
/// 再按 key 里的 `user_id` / `team_id` 读取 `/user/info` 或 `/team/info`。
///
/// 环境变量：`LITELLM_API_KEY`（必需）、`LITELLM_BASE_URL`（必需，允许 `/v1` 后缀）。
public enum LiteLLMUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case missingBaseURL
    case missingUserID
    case invalidURL
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            L("未找到 LiteLLM API key，请设置 LITELLM_API_KEY")
        case .missingBaseURL:
            L("未找到 LiteLLM 基础 URL，请设置 LITELLM_BASE_URL")
        case .missingUserID:
            L("LiteLLM key info 未包含 user_id 或 team_id")
        case .invalidURL:
            L("LiteLLM URL 无效")
        case let .apiError(message):
            L("LiteLLM API 错误：%@", message)
        case let .parseFailed(message):
            L("LiteLLM 解析错误：%@", message)
        }
    }
}

public enum LiteLLMUsageFetcher {
    public static let apiKeyEnvironmentKey = "LITELLM_API_KEY"
    public static let baseURLEnvironmentKey = "LITELLM_BASE_URL"

    public static func hasToken(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        token(env: env) != nil && baseURL(env: env) != nil
    }

    static func token(env: [String: String]) -> String? {
        clean(env[apiKeyEnvironmentKey])
    }

    static func baseURL(env: [String: String]) -> URL? {
        guard let raw = clean(env[baseURLEnvironmentKey]) else { return nil }
        return URL(string: raw)
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

    public static func fetch(
        env: [String: String] = ProcessInfo.processInfo.environment,
        session: URLSession = .shared) async throws -> UsageSnapshot
    {
        guard let apiKey = token(env: env) else { throw LiteLLMUsageError.missingCredentials }
        guard let base = baseURL(env: env) else { throw LiteLLMUsageError.missingBaseURL }

        let updatedAt = Date()
        let keyInfo = try await fetchKeyInfo(apiKey: apiKey, baseURL: base, session: session)
        if keyInfo.userID != nil {
            return try await fetchUserInfo(apiKey: apiKey, baseURL: base, keyInfo: keyInfo, session: session, updatedAt: updatedAt)
                .toUsageSnapshot()
        }
        if keyInfo.teamID != nil {
            return try await fetchTeamInfo(apiKey: apiKey, baseURL: base, keyInfo: keyInfo, session: session, updatedAt: updatedAt)
                .toUsageSnapshot()
        }
        throw LiteLLMUsageError.missingUserID
    }

    // MARK: - Network

    private static func fetchKeyInfo(apiKey: String, baseURL: URL, session: URLSession) async throws -> KeyInfoSnapshot {
        let data = try await requestJSON(url: keyInfoURL(baseURL: baseURL), apiKey: apiKey, session: session)
        return try parseKeyInfo(data)
    }

    private static func fetchUserInfo(
        apiKey: String,
        baseURL: URL,
        keyInfo: KeyInfoSnapshot,
        session: URLSession,
        updatedAt: Date) async throws -> LiteLLMUsageSnapshot
    {
        guard let userID = keyInfo.userID else {
            throw LiteLLMUsageError.parseFailed("/user/info requested without a user_id")
        }
        let data = try await requestJSON(
            url: userInfoURL(baseURL: baseURL, userID: userID),
            apiKey: apiKey,
            session: session)
        return try parseUserInfo(data, keyInfo: keyInfo, updatedAt: updatedAt)
    }

    private static func fetchTeamInfo(
        apiKey: String,
        baseURL: URL,
        keyInfo: KeyInfoSnapshot,
        session: URLSession,
        updatedAt: Date) async throws -> LiteLLMUsageSnapshot
    {
        guard let teamID = keyInfo.teamID else {
            throw LiteLLMUsageError.parseFailed("/team/info requested without a team_id")
        }
        let data = try await requestJSON(
            url: teamInfoURL(baseURL: baseURL, teamID: teamID),
            apiKey: apiKey,
            session: session)
        return try parseTeamInfo(data, keyInfo: keyInfo, updatedAt: updatedAt)
    }

    private static func requestJSON(url: URL, apiKey: String, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw LiteLLMUsageError.invalidURL }
            data = responseData
            http = response
        } catch let error as LiteLLMUsageError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LiteLLMUsageError.apiError(error.localizedDescription)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw LiteLLMUsageError.apiError("HTTP \(http.statusCode): \(responseSummary(data))")
        }
        return data
    }

    static func keyInfoURL(baseURL: URL) -> URL {
        managementBaseURL(baseURL)
            .appendingPathComponent("key")
            .appendingPathComponent("info")
    }

    static func userInfoURL(baseURL: URL, userID: String) -> URL {
        appending(to: managementBaseURL(baseURL), pathComponents: ["user", "info"], queryItems: [
            URLQueryItem(name: "user_id", value: userID),
        ])
    }

    static func teamInfoURL(baseURL: URL, teamID: String) -> URL {
        appending(to: managementBaseURL(baseURL), pathComponents: ["team", "info"], queryItems: [
            URLQueryItem(name: "team_id", value: teamID),
        ])
    }

    static func managementBaseURL(_ baseURL: URL) -> URL {
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.split(separator: "/").last == "v1" else { return baseURL }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let parts = path.split(separator: "/").dropLast()
        components?.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        return components?.url ?? baseURL
    }

    private static func appending(to baseURL: URL, pathComponents: [String], queryItems: [URLQueryItem]) -> URL {
        let url = pathComponents.reduce(baseURL) { partial, component in
            partial.appendingPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = queryItems
        return components.url ?? url
    }

    // MARK: - Parse

    static func parseKeyInfo(_ data: Data) throws -> KeyInfoSnapshot {
        do {
            let decoded = try JSONDecoder().decode(KeyInfoResponse.self, from: data)
            let userID = nonEmpty(decoded.info.userID)
            let teamID = nonEmpty(decoded.info.teamID)
            guard userID != nil || teamID != nil else {
                throw LiteLLMUsageError.missingUserID
            }
            return KeyInfoSnapshot(
                userID: userID,
                teamID: teamID,
                keyName: decoded.info.keyName,
                spendUSD: decoded.info.spend ?? 0,
                expiresAt: parseDate(decoded.info.expires))
        } catch let error as LiteLLMUsageError {
            throw error
        } catch {
            throw LiteLLMUsageError.parseFailed(error.localizedDescription)
        }
    }

    static func parseUserInfo(
        _ data: Data,
        keyInfo: KeyInfoSnapshot,
        updatedAt: Date) throws -> LiteLLMUsageSnapshot
    {
        do {
            let decoded = try JSONDecoder().decode(UserInfoResponse.self, from: data)
            guard let expectedUserID = keyInfo.userID else {
                throw LiteLLMUsageError.parseFailed("/user/info requested without a user_id")
            }
            if let responseUserID = decoded.userInfo.userID ?? decoded.userID,
               responseUserID != expectedUserID
            {
                throw LiteLLMUsageError.parseFailed("user_id did not match /key/info")
            }

            let accountEmail = firstNonEmpty(
                decoded.userInfo.userEmail,
                decoded.userInfo.userAlias,
                decoded.userInfo.metadata?.preferredUsername)
            let team = preferredTeam(from: decoded.teams, keyTeamID: keyInfo.teamID)

            return LiteLLMUsageSnapshot(
                userID: expectedUserID,
                accountEmail: accountEmail,
                personalSpendUSD: decoded.userInfo.spend ?? 0,
                personalBudgetUSD: decoded.userInfo.maxBudget,
                personalResetAt: parseDate(decoded.userInfo.budgetResetAt),
                teamUsage: team.map {
                    LiteLLMUsageSnapshot.TeamUsage(
                        id: $0.teamID,
                        alias: $0.teamAlias,
                        spendUSD: $0.spend ?? 0,
                        budgetUSD: $0.maxBudget,
                        resetAt: parseDate($0.budgetResetAt),
                        budgetDuration: $0.budgetDuration)
                },
                keyName: keyInfo.keyName,
                keyExpiresAt: keyInfo.expiresAt,
                updatedAt: updatedAt)
        } catch let error as LiteLLMUsageError {
            throw error
        } catch {
            throw LiteLLMUsageError.parseFailed(error.localizedDescription)
        }
    }

    static func parseTeamInfo(
        _ data: Data,
        keyInfo: KeyInfoSnapshot,
        updatedAt: Date) throws -> LiteLLMUsageSnapshot
    {
        do {
            let decoded = try JSONDecoder().decode(TeamInfoResponse.self, from: data)
            guard let expectedTeamID = keyInfo.teamID else {
                throw LiteLLMUsageError.parseFailed("/team/info requested without a team_id")
            }
            if let responseTeamID = firstNonEmpty(decoded.teamInfo.teamID, decoded.teamID),
               responseTeamID != expectedTeamID
            {
                throw LiteLLMUsageError.parseFailed("team_id did not match /key/info")
            }

            let team = decoded.teamInfo
            return LiteLLMUsageSnapshot(
                userID: nil,
                accountEmail: nil,
                personalSpendUSD: 0,
                personalBudgetUSD: nil,
                personalResetAt: nil,
                teamUsage: LiteLLMUsageSnapshot.TeamUsage(
                    id: expectedTeamID,
                    alias: team.teamAlias,
                    spendUSD: team.spend ?? 0,
                    budgetUSD: team.maxBudget,
                    resetAt: parseDate(team.budgetResetAt),
                    budgetDuration: team.budgetDuration),
                keyName: keyInfo.keyName,
                keyExpiresAt: keyInfo.expiresAt,
                updatedAt: updatedAt)
        } catch let error as LiteLLMUsageError {
            throw error
        } catch {
            throw LiteLLMUsageError.parseFailed(error.localizedDescription)
        }
    }

    private static func preferredTeam(from teams: [UserInfoResponse.Team]?, keyTeamID: String?) -> UserInfoResponse.Team? {
        guard let teams, let keyTeamID else { return nil }
        return teams.first { $0.teamID == keyTeamID }
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let date = iso8601DateFormatter(fractionalSeconds: true).date(from: raw) {
            return date
        }
        return iso8601DateFormatter(fractionalSeconds: false).date(from: raw)
    }

    private static func iso8601DateFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        if fractionalSeconds {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }
        return formatter
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        firstNonEmpty(value)
    }

    private static func responseSummary(_ data: Data) -> String {
        String(bytes: data.prefix(500), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }
}

extension LiteLLMUsageFetcher {
    struct KeyInfoSnapshot: Sendable, Equatable {
        let userID: String?
        let teamID: String?
        let keyName: String?
        let spendUSD: Double
        let expiresAt: Date?
    }

    struct LiteLLMUsageSnapshot: Sendable, Equatable {
        let userID: String?
        let accountEmail: String?
        let personalSpendUSD: Double
        let personalBudgetUSD: Double?
        let personalResetAt: Date?
        let teamUsage: TeamUsage?
        let keyName: String?
        let keyExpiresAt: Date?
        let updatedAt: Date

        struct TeamUsage: Sendable, Equatable {
            let id: String
            let alias: String?
            let spendUSD: Double
            let budgetUSD: Double?
            let resetAt: Date?
            let budgetDuration: String?
        }

        func toUsageSnapshot() -> UsageSnapshot {
            let primary = Self.rateWindow(
                title: L("个人预算"),
                spend: personalSpendUSD,
                budget: personalBudgetUSD,
                resetAt: personalResetAt,
                description: Self.budgetDescription(spend: personalSpendUSD, budget: personalBudgetUSD))

            let secondary = teamUsage.flatMap { team in
                Self.rateWindow(
                    title: L("团队预算"),
                    spend: team.spendUSD,
                    budget: team.budgetUSD,
                    resetAt: team.resetAt,
                    description: Self.teamDescription(team))
            }

            let account = [accountEmail?.nilIfEmpty, teamUsage?.alias?.nilIfEmpty]
                .compactMap { $0 }
                .joined(separator: " · ")

            return UsageSnapshot(
                primary: primary,
                secondary: secondary,
                providerCost: providerCostSnapshot(),
                planName: keyName?.nilIfEmpty,
                accountLabel: account.isEmpty ? userID : account,
                updatedAt: updatedAt)
        }

        private static func rateWindow(
            title: String,
            spend: Double,
            budget: Double?,
            resetAt: Date?,
            description: String?) -> RateWindow?
        {
            guard let budget, budget > 0 else { return nil }
            return RateWindow(
                title: title,
                usedPercent: min(100, max(0, (spend / budget) * 100)),
                resetsAt: resetAt,
                resetDescription: description)
        }

        private static func budgetDescription(spend: Double, budget: Double?) -> String? {
            guard let budget, budget > 0 else { return usdString(spend) }
            return "\(usdString(spend)) / \(usdString(budget))"
        }

        private static func teamDescription(_ team: TeamUsage) -> String? {
            let label = team.alias.map { L("团队 %@", $0) } ?? L("团队")
            guard let budget = team.budgetUSD, budget > 0 else {
                return "\(label): \(usdString(team.spendUSD))"
            }
            return "\(label): \(usdString(team.spendUSD)) / \(usdString(budget))"
        }

        private func providerCostSnapshot() -> ProviderCostSnapshot? {
            let spend: Double
            let budget: Double?
            let period: String
            let resetsAt: Date?

            if userID == nil, let team = teamUsage {
                spend = team.spendUSD
                budget = team.budgetUSD
                period = (team.budgetUSD ?? 0) > 0 ? L("团队预算") : L("团队消费")
                resetsAt = team.resetAt
            } else {
                spend = personalSpendUSD
                budget = personalBudgetUSD
                period = (personalBudgetUSD ?? 0) > 0 ? L("个人预算") : L("个人消费")
                resetsAt = personalResetAt
            }

            guard spend > 0 || (budget ?? 0) > 0 else { return nil }
            return ProviderCostSnapshot(
                used: spend,
                limit: max(0, budget ?? 0),
                currencyCode: "USD",
                period: period,
                resetsAt: resetsAt)
        }

        private static func usdString(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
        }
    }

    private struct KeyInfoResponse: Decodable {
        struct Info: Decodable {
            let keyName: String?
            let spend: Double?
            let expires: String?
            let userID: String?
            let teamID: String?

            private enum CodingKeys: String, CodingKey {
                case keyName = "key_name"
                case spend
                case expires
                case userID = "user_id"
                case teamID = "team_id"
            }
        }

        let info: Info
    }

    struct UserInfoResponse: Decodable {
        struct UserInfo: Decodable {
            struct Metadata: Decodable {
                let preferredUsername: String?

                private enum CodingKeys: String, CodingKey {
                    case preferredUsername = "preferred_username"
                }
            }

            let userID: String?
            let userAlias: String?
            let maxBudget: Double?
            let spend: Double?
            let userEmail: String?
            let budgetResetAt: String?
            let metadata: Metadata?

            private enum CodingKeys: String, CodingKey {
                case userID = "user_id"
                case userAlias = "user_alias"
                case maxBudget = "max_budget"
                case spend
                case userEmail = "user_email"
                case budgetResetAt = "budget_reset_at"
                case metadata
            }
        }

        struct Team: Decodable {
            let teamAlias: String?
            let teamID: String
            let maxBudget: Double?
            let spend: Double?
            let budgetResetAt: String?
            let budgetDuration: String?

            private enum CodingKeys: String, CodingKey {
                case teamAlias = "team_alias"
                case teamID = "team_id"
                case maxBudget = "max_budget"
                case spend
                case budgetResetAt = "budget_reset_at"
                case budgetDuration = "budget_duration"
            }
        }

        let userID: String?
        let userInfo: UserInfo
        let teams: [Team]?

        private enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case userInfo = "user_info"
            case teams
        }
    }

    private struct TeamInfoResponse: Decodable {
        struct TeamInfo: Decodable {
            let teamAlias: String?
            let teamID: String?
            let maxBudget: Double?
            let spend: Double?
            let budgetResetAt: String?
            let budgetDuration: String?

            private enum CodingKeys: String, CodingKey {
                case teamAlias = "team_alias"
                case teamID = "team_id"
                case maxBudget = "max_budget"
                case spend
                case budgetResetAt = "budget_reset_at"
                case budgetDuration = "budget_duration"
            }
        }

        let teamID: String?
        let teamInfo: TeamInfo

        private enum CodingKeys: String, CodingKey {
            case teamID = "team_id"
            case teamInfo = "team_info"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
