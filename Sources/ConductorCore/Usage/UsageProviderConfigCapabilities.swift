import Foundation

public struct UsageProviderEnvironmentPatch: Sendable {
    public var set: [String: String]
    public var unset: [String]

    public init(set: [String: String] = [:], unset: [String] = []) {
        self.set = set
        self.unset = unset
    }

    public var isEmpty: Bool {
        self.set.isEmpty && self.unset.isEmpty
    }

    public mutating func merge(_ other: UsageProviderEnvironmentPatch) {
        for name in other.unset where !unset.contains(name) {
            unset.append(name)
            set.removeValue(forKey: name)
        }
        for (name, value) in other.set {
            set[name] = value
            unset.removeAll { $0 == name }
        }
    }
}

public enum UsageProviderTokenAccountInjection: Sendable {
    case environment(keys: [String], scrub: [String])
    case cookieHeader(cookieName: String?)
}

public struct UsageProviderTokenAccountSupport: Sendable {
    public let injection: UsageProviderTokenAccountInjection
    public let requiresManualCookieSource: Bool

    public init(
        injection: UsageProviderTokenAccountInjection,
        requiresManualCookieSource: Bool)
    {
        self.injection = injection
        self.requiresManualCookieSource = requiresManualCookieSource
    }
}

public struct UsageProviderConfigEnvironmentHints: Codable, Sendable, Equatable {
    public let apiKey: [String]
    public let cookieHeader: [String]
    public let baseURL: [String]
    public let project: [String]
    public let organization: [String]
    public let sourceMode: [String]
    public let cookieSource: [String]
    public let extra: [String: [String]]

    public init(
        apiKey: [String] = [],
        cookieHeader: [String] = [],
        baseURL: [String] = [],
        project: [String] = [],
        organization: [String] = [],
        sourceMode: [String] = [],
        cookieSource: [String] = [],
        extra: [String: [String]] = [:])
    {
        self.apiKey = apiKey
        self.cookieHeader = cookieHeader
        self.baseURL = baseURL
        self.project = project
        self.organization = organization
        self.sourceMode = sourceMode
        self.cookieSource = cookieSource
        self.extra = extra
    }
}

public enum UsageProviderConfigCapabilities {
    public static let apiKeyEnvironmentNames: [String: String] = [
        "glm": "Z_AI_API_KEY",
        "minimax": "MINIMAX_CODING_API_KEY",
        "qwen": "ALIBABA_CODING_PLAN_API_KEY",
        "openrouter": "OPENROUTER_API_KEY",
        "deepseek": "DEEPSEEK_API_KEY",
        "kimi": "KIMI_CODE_API_KEY",
        "moonshot": "MOONSHOT_API_KEY",
        "groq": "GROQ_API_KEY",
        "openai": "OPENAI_ADMIN_KEY",
        "amp": "AMP_API_KEY",
        "claude": "ANTHROPIC_ADMIN_KEY",
        "azureopenai": "AZURE_OPENAI_API_KEY",
        "devin": "DEVIN_BEARER_TOKEN",
        "kilo": "KILO_API_KEY",
        "kimik2": "KIMI_K2_API_KEY",
        "ollama": "OLLAMA_API_KEY",
        "codebuff": "CODEBUFF_API_KEY",
        "synthetic": "SYNTHETIC_API_KEY",
        "elevenlabs": "ELEVENLABS_API_KEY",
        "doubao": "ARK_API_KEY",
        "crof": "CROF_API_KEY",
        "venice": "VENICE_API_KEY",
        "stepfun": "STEPFUN_TOKEN",
        "llmproxy": "LLM_PROXY_API_KEY",
        "litellm": "LITELLM_API_KEY",
        "deepgram": "DEEPGRAM_API_KEY",
        "poe": "POE_API_KEY",
        "chutes": "CHUTES_API_KEY",
        "copilot": CopilotUsageFetcher.tokenEnvironmentKey,
        "warp": "WARP_API_KEY",
    ]

    public static let apiKeyAliases: [String: [String]] = [
        "minimax": ["MINIMAX_API_KEY"],
        "qwen": ["ALIBABA_QWEN_API_KEY", "DASHSCOPE_API_KEY"],
        "deepseek": ["DEEPSEEK_KEY"],
        "moonshot": ["MOONSHOT_KEY"],
        "openai": ["OPENAI_API_KEY"],
        "claude": ["ANTHROPIC_ADMIN_API_KEY"],
        "devin": ["DEVIN_AUTHORIZATION"],
        "kimik2": ["KIMI_API_KEY", "KIMI_KEY"],
        "elevenlabs": ["XI_API_KEY"],
        "doubao": ["VOLCENGINE_API_KEY", "DOUBAO_API_KEY"],
        "crof": ["CROFAI_API_KEY"],
        "venice": ["VENICE_KEY"],
        "warp": ["WARP_TOKEN"],
        "ollama": ["OLLAMA_KEY"],
    ]

    public static let baseURLEnvironmentNames: [String: String] = [
        "glm": "Z_AI_API_HOST",
        "minimax": "MINIMAX_HOST",
        "qwen": "ALIBABA_CODING_PLAN_HOST",
        "alibabatokenplan": "ALIBABA_TOKEN_PLAN_HOST",
        "openrouter": "OPENROUTER_API_URL",
        "kimi": "KIMI_CODE_BASE_URL",
        "mimo": "MIMO_API_URL",
        "groq": "GROQ_API_URL",
        "codebuff": "CODEBUFF_API_URL",
        "azureopenai": "AZURE_OPENAI_ENDPOINT",
        "llmproxy": "LLM_PROXY_BASE_URL",
        "litellm": "LITELLM_BASE_URL",
        "chutes": "CHUTES_API_URL",
        "deepgram": "DEEPGRAM_API_URL",
        "elevenlabs": "ELEVENLABS_API_URL",
        "bedrock": "CODEXBAR_BEDROCK_API_URL",
        "claude": "CONDUCTOR_USAGE_CLAUDE_WEB_API_BASE_URL",
    ]

    public static let projectEnvironmentNames: [String: [String]] = [
        "azureopenai": ["AZURE_OPENAI_DEPLOYMENT_NAME"],
        "deepgram": ["DEEPGRAM_PROJECT_ID"],
        "vertexai": ["GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT", "CLOUDSDK_CORE_PROJECT"],
        "opencode": ["CODEXBAR_OPENCODE_WORKSPACE_ID"],
        "opencodego": ["CODEXBAR_OPENCODEGO_WORKSPACE_ID"],
        "openai": ["OPENAI_PROJECT_ID"],
    ]

    public static let organizationEnvironmentNames: [String: [String]] = [
        "devin": ["DEVIN_ORGANIZATION", "DEVIN_ORG"],
        "openai": ["OPENAI_ORG_ID", "OPENAI_ORGANIZATION"],
        "claude": ["CONDUCTOR_USAGE_CLAUDE_ORGANIZATION_ID", "CLAUDE_ORGANIZATION_ID", "ANTHROPIC_ORGANIZATION_ID"],
    ]

    public static let cookieHeaderEnvironmentNames: [String: [String]] = [
        "alibabatokenplan": ["ALIBABA_TOKEN_PLAN_COOKIE"],
        "amp": ["AMP_COOKIE"],
        "commandcode": ["COMMANDCODE_SESSION_TOKEN", "COMMANDCODE_COOKIE", "COMMANDCODE_TOKEN"],
        "kimi": ["KIMI_MANUAL_COOKIE", "KIMI_AUTH_TOKEN"],
        "qwen": ["ALIBABA_CODING_PLAN_COOKIE"],
        "perplexity": ["PERPLEXITY_SESSION_TOKEN", "perplexity_session_token", "PERPLEXITY_COOKIE"],
        "manus": [
            "MANUS_SESSION_TOKEN",
            "manus_session_token",
            "MANUS_SESSION_ID",
            "manus_session_id",
            "MANUS_COOKIE",
            "manus_cookie",
        ],
        "minimax": ["MINIMAX_COOKIE", "MINIMAX_COOKIE_HEADER"],
        "claude": ["CONDUCTOR_USAGE_CLAUDE_COOKIE"],
    ]

    public static let extraEnvironmentNames: [String: [String: [String]]] = [
        "azureopenai": [
            "apiVersion": ["AZURE_OPENAI_API_VERSION"],
        ],
        "bedrock": [
            "awsAccessKeyID": ["AWS_ACCESS_KEY_ID"],
            "awsSecretAccessKey": ["AWS_SECRET_ACCESS_KEY"],
            "awsSessionToken": ["AWS_SESSION_TOKEN"],
            "awsRegion": ["AWS_REGION", "AWS_DEFAULT_REGION"],
            "awsBudget": ["CODEXBAR_BEDROCK_BUDGET"],
        ],
        "glm": [
            "region": ["Z_AI_REGION"],
            "quotaURL": ["Z_AI_QUOTA_URL"],
        ],
        "minimax": [
            "region": ["MINIMAX_REGION"],
            "remainsURL": ["MINIMAX_REMAINS_URL"],
            "codingPlanURL": ["MINIMAX_CODING_PLAN_URL"],
            "billingHistoryURL": ["MINIMAX_BILLING_HISTORY_URL"],
            "requireProviderEndpointOverrides": ["MINIMAX_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"],
        ],
        "moonshot": [
            "region": ["MOONSHOT_REGION"],
        ],
        "qwen": [
            "region": ["ALIBABA_CODING_PLAN_REGION", "QWEN_REGION"],
            "quotaURL": ["ALIBABA_CODING_PLAN_QUOTA_URL"],
            "requireProviderEndpointOverrides": ["ALIBABA_CODING_PLAN_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"],
        ],
        "alibabatokenplan": [
            "quotaURL": ["ALIBABA_TOKEN_PLAN_QUOTA_URL"],
        ],
        "openrouter": [
            "httpReferer": ["OPENROUTER_HTTP_REFERER"],
            "clientTitle": ["OPENROUTER_X_TITLE"],
        ],
        "stepfun": [
            "username": ["STEPFUN_USERNAME"],
            "password": ["STEPFUN_PASSWORD"],
        ],
        "antigravity": [
            "oauthCredentialsJSON": ["ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"],
            "oauthClientID": ["ANTIGRAVITY_OAUTH_CLIENT_ID"],
            "oauthClientSecret": ["ANTIGRAVITY_OAUTH_CLIENT_SECRET"],
        ],
        "copilot": [
            "enterpriseHost": [CopilotUsageFetcher.enterpriseHostEnvironmentKey],
        ],
        "claude": [
            "sessionKey": ["CONDUCTOR_USAGE_CLAUDE_SESSION_KEY", "CLAUDE_SESSION_KEY"],
            "oauthToken": ["CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN", "CLAUDE_OAUTH_ACCESS_TOKEN"],
            "subscriptionType": ["CONDUCTOR_USAGE_CLAUDE_SUBSCRIPTION_TYPE"],
        ],
    ]

    public static let tokenAccountSupportByProviderID: [String: UsageProviderTokenAccountSupport] = {
        var support: [String: UsageProviderTokenAccountSupport] = [:]
        for (id, key) in apiKeyEnvironmentNames {
            support[id] = UsageProviderTokenAccountSupport(
                injection: .environment(keys: [key] + (apiKeyAliases[id] ?? []), scrub: projectEnvironmentNames[id] ?? []),
                requiresManualCookieSource: false)
        }
        support["codex"] = UsageProviderTokenAccountSupport(
            injection: .environment(keys: ["CODEX_HOME"], scrub: []),
            requiresManualCookieSource: false)
        support["claude"] = UsageProviderTokenAccountSupport(
            injection: .environment(keys: ["CLAUDE_CONFIG_DIR"], scrub: ["CONDUCTOR_CLAUDE_AVOID_KEYCHAIN"]),
            requiresManualCookieSource: false)
        support["antigravity"] = UsageProviderTokenAccountSupport(
            injection: .environment(keys: ["ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"], scrub: []),
            requiresManualCookieSource: false)
        let cookieProviders: [String: String?] = [
            "abacus": nil,
            "alibabatokenplan": nil,
            "augment": nil,
            "commandcode": nil,
            "cursor": nil,
            "factory": nil,
            "grok": nil,
            "mimo": nil,
            "minimax": nil,
            "mistral": nil,
            "ollama": nil,
            "opencode": nil,
            "opencodego": nil,
            "perplexity": nil,
            "t3chat": nil,
        ]
        for (id, cookieName) in cookieProviders {
            support[id] = UsageProviderTokenAccountSupport(
                injection: .cookieHeader(cookieName: cookieName),
                requiresManualCookieSource: true)
        }
        support["manus"] = UsageProviderTokenAccountSupport(
            injection: .cookieHeader(cookieName: "session_id"),
            requiresManualCookieSource: true)
        return support
    }()

    public static func supportsAPIKey(_ providerID: String) -> Bool {
        apiKeyEnvironmentNames[providerID] != nil
    }

    public static func supportsCookieHeader(_ providerID: String) -> Bool {
        if providerID == "codex" || providerID == "copilot" { return true }
        if cookieHeaderEnvironmentNames[providerID] != nil { return true }
        guard let support = tokenAccountSupportByProviderID[providerID] else {
            return false
        }
        if case .cookieHeader = support.injection { return true }
        return false
    }

    public static func supportsTokenAccounts(_ providerID: String) -> Bool {
        tokenAccountSupportByProviderID[providerID] != nil
    }

    public static func environmentHints(providerID: String) -> UsageProviderConfigEnvironmentHints {
        UsageProviderConfigEnvironmentHints(
            apiKey: apiKeyEnvironmentList(providerID),
            cookieHeader: cookieHeaderEnvironmentNames[providerID] ?? conductorCookieEnvironmentNames(providerID),
            baseURL: baseURLEnvironmentNames[providerID].map { [$0] } ?? [],
            project: projectEnvironmentNames[providerID] ?? [],
            organization: organizationEnvironmentNames[providerID] ?? [],
            sourceMode: conductorSourceEnvironmentNames(providerID),
            cookieSource: conductorCookieSourceEnvironmentNames(providerID),
            extra: extraEnvironmentNames[providerID] ?? [:])
    }

    public static func apiKeyEnvironmentList(_ providerID: String) -> [String] {
        var names: [String] = []
        if let primary = apiKeyEnvironmentNames[providerID] {
            names.append(primary)
        }
        names.append(contentsOf: apiKeyAliases[providerID] ?? [])
        return names
    }

    public static func environmentPatch(providerID: String, config: UsageProviderConfig) -> UsageProviderEnvironmentPatch {
        var set: [String: String] = [:]
        if let value = normalized(config.apiKey),
           let primary = apiKeyEnvironmentNames[providerID]
        {
            for name in [primary] + (apiKeyAliases[providerID] ?? []) {
                set[name] = value
            }
        }
        if let value = normalized(config.cookieHeader) {
            for name in cookieHeaderEnvironmentNames[providerID] ?? conductorCookieEnvironmentNames(providerID) {
                set[name] = value
            }
        }
        if let value = normalized(config.baseURL),
           let name = baseURLEnvironmentNames[providerID]
        {
            set[name] = value
        }
        if let value = normalized(config.projectID) {
            for name in projectEnvironmentNames[providerID] ?? [] {
                set[name] = value
            }
        }
        if let value = normalized(config.organizationID) {
            for name in organizationEnvironmentNames[providerID] ?? [] {
                set[name] = value
            }
        }
        if let value = normalized(config.sourceMode) {
            for name in conductorSourceEnvironmentNames(providerID) {
                set[name] = value
            }
        }
        if let value = normalized(config.cookieSource) {
            for name in conductorCookieSourceEnvironmentNames(providerID) {
                set[name] = value
            }
        }
        for (key, value) in config.extra {
            guard let value = normalized(value) else { continue }
            for name in extraEnvironmentNames(providerID: providerID, key: key) {
                set[name] = value
            }
        }
        if providerID == "claude",
           config.flags["avoidKeychainPrompts"] == true
        {
            set["CONDUCTOR_CLAUDE_AVOID_KEYCHAIN"] = "1"
        }
        if providerID == "copilot",
           config.flags["budgetExtras"] == true
        {
            set[CopilotUsageFetcher.budgetExtrasEnvironmentKey] = "1"
            if normalized(config.cookieSource) == nil {
                for name in conductorCookieSourceEnvironmentNames(providerID) {
                    set[name] = "auto"
                }
            }
        }
        return UsageProviderEnvironmentPatch(set: set)
    }

    public static func environmentPatch(
        providerID: String,
        account: UsageProviderTokenAccount) -> UsageProviderEnvironmentPatch
    {
        let token = account.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return UsageProviderEnvironmentPatch() }
        if providerID == "claude",
           let patch = claudeEnvironmentPatch(token: token, organizationID: account.organizationID)
        {
            return patch
        }

        guard let support = tokenAccountSupportByProviderID[providerID] else { return UsageProviderEnvironmentPatch() }

        switch support.injection {
        case let .environment(keys, scrub):
            return UsageProviderEnvironmentPatch(
                set: Dictionary(uniqueKeysWithValues: keys.map { ($0, token) }),
                unset: scrub)
        case let .cookieHeader(cookieName):
            var set: [String: String] = [:]
            let header = normalizedCookieHeader(token, cookieName: cookieName)
            for name in cookieHeaderEnvironmentNames[providerID] ?? conductorCookieEnvironmentNames(providerID) {
                set[name] = header
            }
            if support.requiresManualCookieSource {
                for name in conductorCookieSourceEnvironmentNames(providerID) {
                    set[name] = "manual"
                }
            }
            return UsageProviderEnvironmentPatch(set: set)
        }
    }

    private enum ClaudeTokenAccountRoute {
        case adminAPIKey(String)
        case oauthAccessToken(String)
        case webCookie(String)
        case configDirectory(String)
    }

    private static func claudeEnvironmentPatch(
        token: String,
        organizationID: String?) -> UsageProviderEnvironmentPatch?
    {
        guard let route = claudeTokenAccountRoute(token) else { return nil }
        var set: [String: String] = [:]
        var unset = [
            "CLAUDE_CONFIG_DIR",
            "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN",
            "ANTHROPIC_ADMIN_KEY",
            "ANTHROPIC_ADMIN_API_KEY",
            "CONDUCTOR_USAGE_CLAUDE_COOKIE",
            "CONDUCTOR_USAGE_CLAUDE_COOKIE_SOURCE",
            "CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN",
            "CLAUDE_OAUTH_ACCESS_TOKEN",
            "CONDUCTOR_USAGE_CLAUDE_SESSION_KEY",
            "CLAUDE_SESSION_KEY",
        ]

        switch route {
        case let .adminAPIKey(key):
            for name in apiKeyEnvironmentList("claude") {
                set[name] = key
            }
            for name in conductorSourceEnvironmentNames("claude") {
                set[name] = "api"
            }
        case let .oauthAccessToken(token):
            set["CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN"] = token
            set["CLAUDE_OAUTH_ACCESS_TOKEN"] = token
            for name in conductorSourceEnvironmentNames("claude") {
                set[name] = "oauth"
            }
        case let .webCookie(header):
            for name in cookieHeaderEnvironmentNames["claude"] ?? conductorCookieEnvironmentNames("claude") {
                set[name] = header
            }
            for name in conductorCookieSourceEnvironmentNames("claude") {
                set[name] = "manual"
            }
            for name in conductorSourceEnvironmentNames("claude") {
                set[name] = "web"
            }
            if let org = normalized(organizationID) {
                for name in organizationEnvironmentNames["claude"] ?? [] {
                    set[name] = org
                }
            }
        case let .configDirectory(path):
            set["CLAUDE_CONFIG_DIR"] = path
            unset.removeAll { $0 == "CLAUDE_CONFIG_DIR" }
            if let org = normalized(organizationID) {
                for name in organizationEnvironmentNames["claude"] ?? [] {
                    set[name] = org
                }
            }
        }

        for key in set.keys {
            unset.removeAll { $0 == key }
        }
        return UsageProviderEnvironmentPatch(set: set, unset: unset)
    }

    private static func claudeTokenAccountRoute(_ raw: String) -> ClaudeTokenAccountRoute? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        if let key = normalizedClaudeAdminAPIKey(token) {
            return .adminAPIKey(key)
        }
        if let token = normalizedClaudeOAuthToken(token) {
            return .oauthAccessToken(token)
        }
        if looksLikeClaudeConfigDirectory(token) {
            return .configDirectory(expandedUserPath(token))
        }
        if let header = normalizedClaudeWebCookie(token) {
            return .webCookie(header)
        }
        return nil
    }

    private static func normalizedClaudeAdminAPIKey(_ raw: String) -> String? {
        guard let token = normalizedBearerToken(raw),
              token.lowercased().hasPrefix("sk-ant-admin")
        else { return nil }
        return token
    }

    private static func normalizedClaudeOAuthToken(_ raw: String) -> String? {
        guard let token = normalizedBearerToken(raw),
              token.lowercased().hasPrefix("sk-ant-oat")
        else { return nil }
        return token
    }

    private static func normalizedBearerToken(_ raw: String) -> String? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              !token.contains("="),
              !token.lowercased().contains("cookie:")
        else { return nil }
        if token.lowercased().hasPrefix("bearer ") {
            token = token.dropFirst("bearer ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token.isEmpty ? nil : token
    }

    private static func normalizedClaudeWebCookie(_ raw: String) -> String? {
        guard let header = CookieHeaderNormalizer.normalize(raw), !header.isEmpty else { return nil }
        if header.contains("=") { return header }
        return "sessionKey=\(header)"
    }

    private static func looksLikeClaudeConfigDirectory(_ raw: String) -> Bool {
        let path = expandedUserPath(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !path.isEmpty else { return false }
        return path.hasPrefix("/")
            || path.hasPrefix("./")
            || path.hasPrefix("../")
            || path.contains("/")
            || path.contains("\\")
            || FileManager.default.fileExists(atPath: path)
    }

    private static func expandedUserPath(_ raw: String) -> String {
        (raw as NSString).expandingTildeInPath
    }

    public static func conductorCookieEnvironmentNames(_ providerID: String) -> [String] {
        ["CONDUCTOR_USAGE_\(envSafe(providerID))_COOKIE"]
    }

    public static func conductorSourceEnvironmentNames(_ providerID: String) -> [String] {
        ["CONDUCTOR_USAGE_\(envSafe(providerID))_SOURCE"]
    }

    public static func conductorCookieSourceEnvironmentNames(_ providerID: String) -> [String] {
        ["CONDUCTOR_USAGE_\(envSafe(providerID))_COOKIE_SOURCE"]
    }

    public static func extraEnvironmentNames(providerID: String, key: String) -> [String] {
        extraEnvironmentNames[providerID]?[key] ?? ["CONDUCTOR_USAGE_\(envSafe(providerID))_\(envSafe(key))"]
    }

    public static func envSafe(_ raw: String) -> String {
        raw.uppercased().map { ch in
            ch.isLetter || ch.isNumber ? String(ch) : "_"
        }.joined()
    }

    private static func normalizedCookieHeader(_ raw: String, cookieName: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cookieName else { return trimmed }
        let lower = trimmed.lowercased()
        if lower.contains("cookie:") || trimmed.contains("=") {
            return trimmed
        }
        return "\(cookieName)=\(trimmed)"
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
