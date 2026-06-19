import Foundation

public struct UsageProviderCLISessionPolicy: Codable, Equatable, Sendable {
    public let kind: String
    public let persistsAcrossRequests: Bool
    public let idleWindowSeconds: TimeInterval?

    public init(
        kind: String,
        persistsAcrossRequests: Bool,
        idleWindowSeconds: TimeInterval? = nil)
    {
        self.kind = kind
        self.persistsAcrossRequests = persistsAcrossRequests
        self.idleWindowSeconds = idleWindowSeconds
    }

    public static let none = UsageProviderCLISessionPolicy(
        kind: "none",
        persistsAcrossRequests: false,
        idleWindowSeconds: nil)

    public static let oneShot = UsageProviderCLISessionPolicy(
        kind: "oneShot",
        persistsAcrossRequests: false,
        idleWindowSeconds: nil)

    public static func persistent(idleWindowSeconds: TimeInterval) -> UsageProviderCLISessionPolicy {
        UsageProviderCLISessionPolicy(
            kind: "persistent",
            persistsAcrossRequests: true,
            idleWindowSeconds: idleWindowSeconds)
    }
}

public struct UsageProviderDisplayMetadata: Codable, Equatable, Sendable {
    public let sessionLabel: String
    public let weeklyLabel: String
    public let opusLabel: String?
    public let supportsOpus: Bool
    public let supportsCredits: Bool
    public let creditsHint: String
    public let toggleTitle: String
    public let cliName: String
    public let isPrimaryProvider: Bool
    public let usesAccountFallback: Bool

    public init(
        sessionLabel: String,
        weeklyLabel: String,
        opusLabel: String? = nil,
        supportsOpus: Bool = false,
        supportsCredits: Bool = false,
        creditsHint: String = "",
        toggleTitle: String,
        cliName: String,
        isPrimaryProvider: Bool = false,
        usesAccountFallback: Bool = false)
    {
        self.sessionLabel = sessionLabel
        self.weeklyLabel = weeklyLabel
        self.opusLabel = opusLabel
        self.supportsOpus = supportsOpus
        self.supportsCredits = supportsCredits
        self.creditsHint = creditsHint
        self.toggleTitle = toggleTitle
        self.cliName = cliName
        self.isPrimaryProvider = isPrimaryProvider
        self.usesAccountFallback = usesAccountFallback
    }

    public static func fallback(providerID: String, displayName: String) -> UsageProviderDisplayMetadata {
        UsageProviderDisplayMetadata(
            sessionLabel: L("会话"),
            weeklyLabel: L("本周"),
            toggleTitle: "Show \(displayName) usage",
            cliName: providerID)
    }
}

/// Account-level usage provider descriptor shared by the app UI and conductorctl.
public struct UsageProviderEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    /// Resource name under the app target's Resources/Logos directory.
    public let logo: String
    public let fallbackSystemImage: String
    /// Whether the provider is enabled when the user has no explicit override.
    public let defaultEnabled: Bool
    /// Statuspage-compatible base URL. The fetcher reads `/api/v2/status.json` from this base.
    public let statusPageURL: String?
    /// Human-facing status URL for providers without a compatible status API.
    public let statusLinkURL: String?
    /// Provider usage/billing dashboard URL, mirroring CodexBar provider metadata.
    public let dashboardURL: String?
    /// Provider subscription or plan-management dashboard URL when separate from usage.
    public let subscriptionDashboardURL: String?
    /// Provider-specific release notes or changelog URL.
    public let changelogURL: String?
    /// Google Workspace product ID for providers backed by the Workspace incidents feed.
    public let googleWorkspaceStatusProductID: String?
    /// Whether this provider starts CLI helper processes and if they may survive a single fetch.
    public let cliSessionPolicy: UsageProviderCLISessionPolicy
    /// Command users can run to repair local CLI authentication for this provider.
    public let signInCommand: String?
    /// Cheap local credential check. Some cookie-backed providers may still read browser cookie stores.
    public let isConfigured: @Sendable () -> Bool
    /// Fetch a rich usage snapshot for this provider.
    public let fetch: @Sendable () async throws -> UsageSnapshot

    public init(
        id: String,
        name: String,
        logo: String,
        fallbackSystemImage: String,
        defaultEnabled: Bool = false,
        statusPageURL: String? = nil,
        statusLinkURL: String? = nil,
        dashboardURL: String? = nil,
        subscriptionDashboardURL: String? = nil,
        changelogURL: String? = nil,
        googleWorkspaceStatusProductID: String? = nil,
        cliSessionPolicy: UsageProviderCLISessionPolicy = .none,
        signInCommand: String? = nil,
        isConfigured: @escaping @Sendable () -> Bool,
        fetch: @escaping @Sendable () async throws -> UsageSnapshot
    ) {
        self.id = id
        self.name = name
        self.logo = logo
        self.fallbackSystemImage = fallbackSystemImage
        self.defaultEnabled = defaultEnabled
        self.statusPageURL = statusPageURL
        self.statusLinkURL = statusLinkURL
        self.dashboardURL = dashboardURL
        self.subscriptionDashboardURL = subscriptionDashboardURL
        self.changelogURL = changelogURL
        self.googleWorkspaceStatusProductID = googleWorkspaceStatusProductID
        self.cliSessionPolicy = cliSessionPolicy
        self.signInCommand = signInCommand
        self.isConfigured = isConfigured
        let defaultSourceLabel = UsageProviderCatalog.defaultSourceLabel(for: id)
        self.fetch = {
            let snapshot = try await fetch()
            guard snapshot.sourceLabel == nil, let defaultSourceLabel else { return snapshot }
            return snapshot.withSourceLabel(defaultSourceLabel)
        }
    }

    public var logoName: String { self.logo.isEmpty ? self.id : self.logo }
    public var statusURL: String? { self.statusPageURL ?? self.statusLinkURL }
    public var sourceModes: [String] { UsageProviderCatalog.sourceModes(for: self.id) }
    public var displayMetadata: UsageProviderDisplayMetadata {
        UsageProviderCatalog.displayMetadata(for: self.id, displayName: self.name)
    }

    public func isEnabled(in config: AppConfig) -> Bool {
        config.usage.providers[self.id]?.enabled ?? self.defaultEnabled
    }

    public func supportsSourceMode(_ sourceMode: String) -> Bool {
        let normalized = sourceMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return self.sourceModes.contains(normalized)
    }
}

public enum UsageProviderCatalogError: Error, LocalizedError, CustomStringConvertible, Sendable {
    case unknownProvider(String, known: [String])

    public var errorDescription: String? { self.description }

    public var description: String {
        switch self {
        case let .unknownProvider(provider, known):
            return "Unknown provider '\(provider)'. Known providers: \((known + ["both", "all"]).joined(separator: ", "))"
        }
    }
}

public enum UsageProviderCatalog {
    public static let primaryProviderIDs: [String] = ["codex", "claude"]

    public static let providerAliases: [String: String] = [
        "alibaba": "qwen",
        "azure-openai": "azureopenai",
        "claude-code": "claude",
        "claudecode": "claude",
        "github-copilot": "copilot",
        "open-code": "opencode",
        "open-code-go": "opencodego",
        "zai": "glm",
    ]

    public static let providerSourceModes: [String: [String]] = [
        "abacus": ["auto", "web"],
        "alibabatokenplan": ["auto", "web"],
        "amp": ["auto", "api", "web", "cli"],
        "antigravity": ["auto", "cli", "oauth"],
        "augment": ["auto", "cli"],
        "azureopenai": ["auto", "api"],
        "bedrock": ["auto", "api"],
        "chutes": ["auto", "api"],
        "claude": ["auto", "api", "web", "cli", "oauth"],
        "codebuff": ["auto", "api"],
        "codex": ["auto", "web", "cli", "oauth"],
        "commandcode": ["auto", "web"],
        "copilot": ["auto", "api"],
        "crof": ["auto", "api"],
        "cursor": ["auto", "cli"],
        "deepgram": ["auto", "api"],
        "deepseek": ["auto", "api"],
        "devin": ["auto", "web"],
        "doubao": ["auto", "api"],
        "elevenlabs": ["auto", "api"],
        "factory": ["auto", "cli"],
        "gemini": ["auto", "api"],
        "glm": ["auto", "api"],
        "grok": ["auto", "cli", "web"],
        "groq": ["auto", "api"],
        "jetbrains": ["auto", "cli"],
        "kilo": ["auto", "api", "cli"],
        "kimi": ["auto", "api", "web"],
        "kimik2": ["auto", "api"],
        "kiro": ["auto", "cli"],
        "litellm": ["auto", "api"],
        "llmproxy": ["auto", "api"],
        "manus": ["auto", "web"],
        "mimo": ["auto", "web"],
        "minimax": ["auto", "web", "api"],
        "mistral": ["auto", "web"],
        "moonshot": ["auto", "api"],
        "ollama": ["auto", "web", "api"],
        "openai": ["auto", "api"],
        "opencode": ["auto", "web"],
        "opencodego": ["auto", "web"],
        "openrouter": ["auto", "api"],
        "perplexity": ["auto", "web"],
        "poe": ["auto", "api"],
        "qwen": ["auto", "web", "api"],
        "stepfun": ["auto", "web"],
        "synthetic": ["auto", "api"],
        "t3chat": ["auto", "web"],
        "venice": ["auto", "api"],
        "vertexai": ["auto", "oauth"],
        "warp": ["auto", "api"],
        "windsurf": ["auto", "web", "cli"],
        "zed": ["auto", "api"],
    ]

    public static let providerDisplayMetadata: [String: UsageProviderDisplayMetadata] = [
        "codex": UsageProviderDisplayMetadata(sessionLabel: "Session", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Credits unavailable; keep Codex running to refresh.", toggleTitle: "Show Codex usage", cliName: "codex", isPrimaryProvider: true, usesAccountFallback: true),
        "claude": UsageProviderDisplayMetadata(sessionLabel: "Session", weeklyLabel: "Weekly", opusLabel: "Sonnet", supportsOpus: true, supportsCredits: false, creditsHint: "", toggleTitle: "Show Claude Code usage", cliName: "claude", isPrimaryProvider: true, usesAccountFallback: false),
        "gemini": UsageProviderDisplayMetadata(sessionLabel: "Pro", weeklyLabel: "Flash", opusLabel: "Flash Lite", supportsOpus: true, supportsCredits: false, creditsHint: "", toggleTitle: "Show Gemini usage", cliName: "gemini", isPrimaryProvider: false, usesAccountFallback: false),
        "glm": UsageProviderDisplayMetadata(sessionLabel: "Tokens", weeklyLabel: "MCP", opusLabel: "5-hour", supportsOpus: true, supportsCredits: false, creditsHint: "", toggleTitle: "Show z.ai usage", cliName: "zai", isPrimaryProvider: false, usesAccountFallback: false),
        "minimax": UsageProviderDisplayMetadata(sessionLabel: "Prompts", weeklyLabel: "Window", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show MiniMax usage", cliName: "minimax", isPrimaryProvider: false, usesAccountFallback: false),
        "qwen": UsageProviderDisplayMetadata(sessionLabel: "5-hour", weeklyLabel: "Weekly", opusLabel: "Monthly", supportsOpus: true, supportsCredits: false, creditsHint: "", toggleTitle: "Show Alibaba usage", cliName: "alibaba-coding-plan", isPrimaryProvider: false, usesAccountFallback: false),
        "cursor": UsageProviderDisplayMetadata(sessionLabel: "Total", weeklyLabel: "Auto", opusLabel: "API", supportsOpus: true, supportsCredits: true, creditsHint: "On-demand usage beyond included plan limits.", toggleTitle: "Show Cursor usage", cliName: "cursor", isPrimaryProvider: false, usesAccountFallback: false),
        "grok": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "On-demand", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Grok usage", cliName: "grok", isPrimaryProvider: false, usesAccountFallback: false),
        "copilot": UsageProviderDisplayMetadata(sessionLabel: "Premium", weeklyLabel: "Chat", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Copilot usage", cliName: "copilot", isPrimaryProvider: false, usesAccountFallback: false),
        "openrouter": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Usage", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Credit balance from OpenRouter API", toggleTitle: "Show OpenRouter usage", cliName: "openrouter", isPrimaryProvider: false, usesAccountFallback: false),
        "deepseek": UsageProviderDisplayMetadata(sessionLabel: "Balance", weeklyLabel: "Balance", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show DeepSeek usage", cliName: "deepseek", isPrimaryProvider: false, usesAccountFallback: false),
        "kimi": UsageProviderDisplayMetadata(sessionLabel: "Weekly", weeklyLabel: "Rate Limit", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Kimi usage", cliName: "kimi", isPrimaryProvider: false, usesAccountFallback: false),
        "mistral": UsageProviderDisplayMetadata(sessionLabel: "Monthly", weeklyLabel: "", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Mistral usage", cliName: "mistral", isPrimaryProvider: false, usesAccountFallback: false),
        "moonshot": UsageProviderDisplayMetadata(sessionLabel: "Balance", weeklyLabel: "Balance", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Moonshot / Kimi API balance", cliName: "moonshot", isPrimaryProvider: false, usesAccountFallback: false),
        "groq": UsageProviderDisplayMetadata(sessionLabel: "Requests", weeklyLabel: "Tokens", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Groq usage", cliName: "groqcloud", isPrimaryProvider: false, usesAccountFallback: false),
        "opencode": UsageProviderDisplayMetadata(sessionLabel: "5-hour", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show OpenCode usage", cliName: "opencode", isPrimaryProvider: false, usesAccountFallback: false),
        "ollama": UsageProviderDisplayMetadata(sessionLabel: "Session", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Ollama usage", cliName: "ollama", isPrimaryProvider: false, usesAccountFallback: false),
        "openai": UsageProviderDisplayMetadata(sessionLabel: "Spend", weeklyLabel: "Requests", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show OpenAI usage", cliName: "openai", isPrimaryProvider: false, usesAccountFallback: false),
        "perplexity": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Bonus credits", opusLabel: "Purchased", supportsOpus: true, supportsCredits: false, creditsHint: "", toggleTitle: "Show Perplexity usage", cliName: "perplexity", isPrimaryProvider: false, usesAccountFallback: false),
        "warp": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Add-on credits", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Warp usage", cliName: "warp", isPrimaryProvider: false, usesAccountFallback: false),
        "augment": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Usage", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Augment Code credits for AI-powered coding assistance.", toggleTitle: "Show Augment usage", cliName: "augment", isPrimaryProvider: false, usesAccountFallback: false),
        "amp": UsageProviderDisplayMetadata(sessionLabel: "Amp Free", weeklyLabel: "Balance", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Individual and workspace credit balances from Amp.", toggleTitle: "Show Amp usage", cliName: "amp", isPrimaryProvider: false, usesAccountFallback: false),
        "antigravity": UsageProviderDisplayMetadata(sessionLabel: "Gemini Models", weeklyLabel: "Claude and GPT", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Antigravity usage (experimental)", cliName: "antigravity", isPrimaryProvider: false, usesAccountFallback: false),
        "vertexai": UsageProviderDisplayMetadata(sessionLabel: "Requests", weeklyLabel: "Tokens", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Vertex AI usage", cliName: "vertexai", isPrimaryProvider: false, usesAccountFallback: false),
        "windsurf": UsageProviderDisplayMetadata(sessionLabel: "Daily", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Windsurf usage", cliName: "windsurf", isPrimaryProvider: false, usesAccountFallback: false),
        "zed": UsageProviderDisplayMetadata(sessionLabel: "Edit predictions", weeklyLabel: "Billing cycle", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Zed usage", cliName: "zed", isPrimaryProvider: false, usesAccountFallback: false),
        "azureopenai": UsageProviderDisplayMetadata(sessionLabel: "Status", weeklyLabel: "Deployment", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Azure OpenAI status", cliName: "azure-openai", isPrimaryProvider: false, usesAccountFallback: false),
        "factory": UsageProviderDisplayMetadata(sessionLabel: "Standard", weeklyLabel: "Premium", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Droid usage", cliName: "factory", isPrimaryProvider: false, usesAccountFallback: false),
        "devin": UsageProviderDisplayMetadata(sessionLabel: "Daily", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Devin usage", cliName: "devin", isPrimaryProvider: false, usesAccountFallback: false),
        "manus": UsageProviderDisplayMetadata(sessionLabel: "Monthly credits", weeklyLabel: "Daily refresh", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Manus usage", cliName: "manus", isPrimaryProvider: false, usesAccountFallback: false),
        "kilo": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Kilo Pass", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Kilo usage", cliName: "kilo", isPrimaryProvider: false, usesAccountFallback: false),
        "kiro": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Bonus", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Kiro usage", cliName: "kiro", isPrimaryProvider: false, usesAccountFallback: false),
        "jetbrains": UsageProviderDisplayMetadata(sessionLabel: "Current", weeklyLabel: "Refill", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show JetBrains AI usage", cliName: "jetbrains", isPrimaryProvider: false, usesAccountFallback: false),
        "kimik2": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Credits", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show unofficial Kimi K2 usage", cliName: "kimik2", isPrimaryProvider: false, usesAccountFallback: false),
        "t3chat": UsageProviderDisplayMetadata(sessionLabel: "Base", weeklyLabel: "Overage", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show T3 Chat usage", cliName: "t3chat", isPrimaryProvider: false, usesAccountFallback: false),
        "codebuff": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Credit balance from the Codebuff API", toggleTitle: "Show Codebuff usage", cliName: "codebuff", isPrimaryProvider: false, usesAccountFallback: false),
        "opencodego": UsageProviderDisplayMetadata(sessionLabel: "5-hour", weeklyLabel: "Weekly", opusLabel: "Monthly", supportsOpus: true, supportsCredits: false, creditsHint: "", toggleTitle: "Show OpenCode Go usage", cliName: "opencodego", isPrimaryProvider: false, usesAccountFallback: false),
        "alibabatokenplan": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Usage", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Alibaba Token Plan usage", cliName: "alibaba-token-plan", isPrimaryProvider: false, usesAccountFallback: false),
        "synthetic": UsageProviderDisplayMetadata(sessionLabel: "Five-hour quota", weeklyLabel: "Weekly tokens", opusLabel: "Search hourly", supportsOpus: true, supportsCredits: false, creditsHint: "Weekly token quota regenerates continuously.", toggleTitle: "Show Synthetic usage", cliName: "synthetic", isPrimaryProvider: false, usesAccountFallback: false),
        "elevenlabs": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Voices", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show ElevenLabs usage", cliName: "elevenlabs", isPrimaryProvider: false, usesAccountFallback: false),
        "mimo": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Window", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Token plan credits usage.", toggleTitle: "Show Xiaomi MiMo token plan & balance", cliName: "mimo", isPrimaryProvider: false, usesAccountFallback: false),
        "doubao": UsageProviderDisplayMetadata(sessionLabel: "Requests", weeklyLabel: "Rate limit", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Doubao usage", cliName: "doubao", isPrimaryProvider: false, usesAccountFallback: false),
        "abacus": UsageProviderDisplayMetadata(sessionLabel: "Credits", weeklyLabel: "Weekly", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Abacus AI usage", cliName: "abacusai", isPrimaryProvider: false, usesAccountFallback: false),
        "crof": UsageProviderDisplayMetadata(sessionLabel: "Requests", weeklyLabel: "Credits", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "Credit balance from the Crof usage API", toggleTitle: "Show Crof usage", cliName: "crof", isPrimaryProvider: false, usesAccountFallback: false),
        "venice": UsageProviderDisplayMetadata(sessionLabel: "Balance", weeklyLabel: "Balance", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Venice usage", cliName: "venice", isPrimaryProvider: false, usesAccountFallback: false),
        "commandcode": UsageProviderDisplayMetadata(sessionLabel: "Monthly credits", weeklyLabel: "Monthly", opusLabel: nil, supportsOpus: false, supportsCredits: true, creditsHint: "Monthly USD credits from Command Code billing.", toggleTitle: "Show Command Code usage", cliName: "commandcode", isPrimaryProvider: false, usesAccountFallback: false),
        "stepfun": UsageProviderDisplayMetadata(sessionLabel: "5h Window", weeklyLabel: "Weekly Window", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show StepFun usage", cliName: "stepfun", isPrimaryProvider: false, usesAccountFallback: false),
        "bedrock": UsageProviderDisplayMetadata(sessionLabel: "Budget", weeklyLabel: "Cost", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show AWS Bedrock usage", cliName: "bedrock", isPrimaryProvider: false, usesAccountFallback: false),
        "llmproxy": UsageProviderDisplayMetadata(sessionLabel: "Quota", weeklyLabel: "Requests", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show LLM Proxy usage", cliName: "llmproxy", isPrimaryProvider: false, usesAccountFallback: false),
        "litellm": UsageProviderDisplayMetadata(sessionLabel: "Personal budget", weeklyLabel: "Team budget", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "Reads spend and budget from LiteLLM key, user, and team info endpoints.", toggleTitle: "Show LiteLLM usage", cliName: "litellm", isPrimaryProvider: false, usesAccountFallback: false),
        "deepgram": UsageProviderDisplayMetadata(sessionLabel: "Requests", weeklyLabel: "Usage", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "Usage summary from Deepgram API", toggleTitle: "Show Deepgram usage", cliName: "deepgram", isPrimaryProvider: false, usesAccountFallback: false),
        "poe": UsageProviderDisplayMetadata(sessionLabel: "Points", weeklyLabel: "Points", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "", toggleTitle: "Show Poe usage", cliName: "poe", isPrimaryProvider: false, usesAccountFallback: false),
        "chutes": UsageProviderDisplayMetadata(sessionLabel: "4-hour quota", weeklyLabel: "Monthly quota", opusLabel: nil, supportsOpus: false, supportsCredits: false, creditsHint: "Subscription usage from the Chutes API.", toggleTitle: "Show Chutes usage", cliName: "chutes", isPrimaryProvider: false, usesAccountFallback: false),
    ]

    public static func canonicalProviderID(_ raw: String) -> String {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return self.providerAliases[id] ?? id
    }

    public static func sourceModes(for providerID: String) -> [String] {
        self.providerSourceModes[self.canonicalProviderID(providerID)] ?? ["auto"]
    }

    public static func defaultSourceLabel(for providerID: String) -> String? {
        let modes = self.sourceModes(for: providerID).filter { $0 != "auto" }
        return modes.count == 1 ? modes[0] : nil
    }

    public static func displayMetadata(for providerID: String, displayName: String) -> UsageProviderDisplayMetadata {
        let canonical = self.canonicalProviderID(providerID)
        return self.providerDisplayMetadata[canonical]
            ?? UsageProviderDisplayMetadata.fallback(providerID: canonical, displayName: displayName)
    }

    public static let all: [UsageProviderEntry] = [
        UsageProviderEntry(
            id: "codex", name: "Codex", logo: "codex",
            fallbackSystemImage: "chevron.left.forwardslash.chevron.right",
            defaultEnabled: true,
            statusPageURL: "https://status.openai.com/",
            dashboardURL: "https://chatgpt.com/codex/settings/usage",
            changelogURL: "https://github.com/openai/codex/releases",
            cliSessionPolicy: .persistent(idleWindowSeconds: 90),
            signInCommand: "codex login --device-auth",
            isConfigured: { CodexUsageFetcher.hasCredentials() },
            fetch: { UsageSnapshot(codexSnapshot: try await CodexUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "claude", name: "Claude", logo: "claude",
            fallbackSystemImage: "sparkles",
            statusPageURL: "https://status.claude.com/",
            dashboardURL: "https://console.anthropic.com/settings/billing",
            subscriptionDashboardURL: "https://claude.ai/settings/usage",
            changelogURL: "https://github.com/anthropics/claude-code/releases",
            cliSessionPolicy: .persistent(idleWindowSeconds: 90),
            signInCommand: "claude /login",
            isConfigured: { ClaudeUsageFetcher.hasCredentials() },
            fetch: { try await ClaudeUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "gemini", name: "Gemini", logo: "gemini",
            fallbackSystemImage: "diamond",
            statusLinkURL: "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
            dashboardURL: "https://gemini.google.com",
            changelogURL: "https://github.com/google-gemini/gemini-cli/releases",
            googleWorkspaceStatusProductID: "npdyhgECDJ6tB66MxXyo",
            signInCommand: "gemini auth",
            isConfigured: { GeminiUsageFetcher.hasCredentials() },
            fetch: { UsageSnapshot(codexSnapshot: try await GeminiUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "glm", name: "z.ai", logo: "glm",
            fallbackSystemImage: "g.square",
            dashboardURL: "https://z.ai/manage-apikey/coding-plan/personal/my-plan",
            isConfigured: { GLMUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await GLMUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "minimax", name: "MiniMax", logo: "minimax",
            fallbackSystemImage: "m.square",
            dashboardURL: "https://platform.minimax.io/user-center/payment/coding-plan?cycle_type=3",
            isConfigured: { MiniMaxUsageFetcher.hasCredentials() },
            fetch: { try await MiniMaxUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "qwen", name: "Alibaba", logo: "qwen",
            fallbackSystemImage: "q.square",
            statusLinkURL: "https://status.aliyun.com",
            dashboardURL: "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan",
            signInCommand: "qwen login",
            isConfigured: { QwenUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await QwenUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "cursor", name: "Cursor", logo: "cursor",
            fallbackSystemImage: "cursorarrow.rays",
            statusPageURL: "https://status.cursor.com",
            dashboardURL: "https://cursor.com/dashboard?tab=usage",
            isConfigured: { CursorUsageFetcher.hasSession() },
            fetch: { try await CursorUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "grok", name: "Grok", logo: "grok", fallbackSystemImage: "bolt.fill",
            statusLinkURL: "https://status.x.ai",
            dashboardURL: "https://grok.com/?_s=usage",
            changelogURL: "https://x.ai/news",
            isConfigured: { GrokUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await GrokUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "copilot", name: "Copilot", logo: "copilot", fallbackSystemImage: "command",
            statusPageURL: "https://www.githubstatus.com/",
            dashboardURL: "https://github.com/settings/copilot",
            isConfigured: { CopilotUsageFetcher.hasSession() },
            fetch: { try await CopilotUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "openrouter", name: "OpenRouter", logo: "openrouter", fallbackSystemImage: "arrow.triangle.swap",
            statusLinkURL: "https://status.openrouter.ai",
            dashboardURL: "https://openrouter.ai/settings/credits",
            isConfigured: { OpenRouterUsageFetcher.hasToken() },
            fetch: { try await OpenRouterUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "deepseek", name: "DeepSeek", logo: "deepseek", fallbackSystemImage: "water.waves",
            statusLinkURL: "https://status.deepseek.com",
            dashboardURL: "https://platform.deepseek.com/usage",
            isConfigured: { DeepSeekUsageFetcher.hasToken() },
            fetch: { try await DeepSeekUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "kimi", name: "Kimi", logo: "kimi", fallbackSystemImage: "k.square",
            dashboardURL: "https://www.kimi.com/code/console",
            isConfigured: { KimiUsageFetcher.hasToken() },
            fetch: { try await KimiUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "mistral", name: "Mistral", logo: "mistral", fallbackSystemImage: "wind",
            statusLinkURL: "https://status.mistral.ai",
            dashboardURL: "https://admin.mistral.ai/organization/usage",
            isConfigured: { MistralUsageFetcher.hasSession() },
            fetch: { try await MistralUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "moonshot", name: "Moonshot / Kimi API", logo: "moonshot", fallbackSystemImage: "moon.stars",
            dashboardURL: "https://platform.moonshot.ai/console/account",
            isConfigured: { MoonshotUsageFetcher.hasToken() },
            fetch: { try await MoonshotUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "groq", name: "Groq", logo: "groq", fallbackSystemImage: "cpu",
            statusLinkURL: "https://status.groq.com",
            dashboardURL: "https://console.groq.com/dashboard/metrics",
            isConfigured: { GroqUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await GroqUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "opencode", name: "OpenCode", logo: "opencode", fallbackSystemImage: "curlybraces",
            dashboardURL: "https://opencode.ai",
            isConfigured: { OpenCodeUsageFetcher.hasSession() },
            fetch: { try await OpenCodeUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "ollama", name: "Ollama", logo: "ollama", fallbackSystemImage: "shippingbox",
            dashboardURL: "https://ollama.com/settings",
            isConfigured: { OllamaUsageFetcher.hasSession() },
            fetch: { try await OllamaUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "openai", name: "OpenAI", logo: "openai", fallbackSystemImage: "brain",
            statusPageURL: "https://status.openai.com",
            dashboardURL: "https://platform.openai.com/usage",
            isConfigured: { OpenAIUsageFetcher.hasToken() },
            fetch: { try await OpenAIUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "perplexity", name: "Perplexity", logo: "perplexity", fallbackSystemImage: "magnifyingglass",
            statusLinkURL: "https://status.perplexity.com/",
            dashboardURL: "https://www.perplexity.ai/account/usage",
            isConfigured: { PerplexityUsageFetcher.hasSession() },
            fetch: { try await PerplexityUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "warp", name: "Warp", logo: "warp", fallbackSystemImage: "terminal",
            dashboardURL: "https://docs.warp.dev/reference/cli/api-keys",
            isConfigured: { WarpUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await WarpUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "augment", name: "Augment", logo: "augment", fallbackSystemImage: "puzzlepiece.extension",
            dashboardURL: "https://app.augmentcode.com/account/subscription",
            signInCommand: "auggie login",
            isConfigured: { AugmentUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await AugmentUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "amp", name: "Amp", logo: "amp", fallbackSystemImage: "bolt.horizontal.circle",
            dashboardURL: "https://ampcode.com/settings#billing",
            isConfigured: { AmpUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await AmpUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "antigravity", name: "Antigravity", logo: "antigravity", fallbackSystemImage: "arrow.up",
            statusLinkURL: "https://www.google.com/appsstatus/dashboard/products/npdyhgECDJ6tB66MxXyo/history",
            googleWorkspaceStatusProductID: "npdyhgECDJ6tB66MxXyo",
            isConfigured: { AntigravityUsageFetcher.hasToken() },
            fetch: { try await AntigravityUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "vertexai", name: "Vertex AI", logo: "vertexai", fallbackSystemImage: "triangle",
            statusLinkURL: "https://status.cloud.google.com",
            dashboardURL: "https://console.cloud.google.com/vertex-ai",
            isConfigured: { VertexAIUsageFetcher.hasCredentials() },
            fetch: { UsageSnapshot(codexSnapshot: try await VertexAIUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "windsurf", name: "Windsurf", logo: "windsurf", fallbackSystemImage: "wind.snow",
            dashboardURL: "https://windsurf.com/subscription/usage",
            isConfigured: { WindsurfUsageFetcher.hasCredentials() || WindsurfUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await WindsurfUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "zed", name: "Zed", logo: "zed", fallbackSystemImage: "z.square",
            isConfigured: { ZedUsageFetcher.hasCredentials() },
            fetch: { try await ZedUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "azureopenai", name: "Azure OpenAI", logo: "azureopenai", fallbackSystemImage: "a.square",
            statusLinkURL: "https://azure.status.microsoft/en-us/status",
            dashboardURL: "https://ai.azure.com",
            isConfigured: { AzureOpenAIUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await AzureOpenAIUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "factory", name: "Droid", logo: "factory", fallbackSystemImage: "gearshape.2",
            statusPageURL: "https://status.factory.ai",
            dashboardURL: "https://app.factory.ai/settings/billing",
            isConfigured: { FactoryUsageFetcher.hasSession() },
            fetch: { try await FactoryUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "devin", name: "Devin", logo: "devin", fallbackSystemImage: "hammer",
            dashboardURL: "https://app.devin.ai",
            subscriptionDashboardURL: "https://app.devin.ai/settings/usage",
            isConfigured: { DevinUsageFetcher.hasToken() || DevinUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await DevinUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "manus", name: "Manus", logo: "manus", fallbackSystemImage: "hand.raised",
            dashboardURL: "https://manus.im",
            isConfigured: { ManusUsageFetcher.hasToken() || ManusUsageFetcher.hasSession() },
            fetch: { try await ManusUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "kilo", name: "Kilo", logo: "kilo", fallbackSystemImage: "k.circle",
            dashboardURL: "https://app.kilo.ai/usage",
            cliSessionPolicy: .oneShot,
            isConfigured: { KiloUsageFetcher.hasToken() },
            fetch: { try await KiloUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "kiro", name: "Kiro", logo: "kiro", fallbackSystemImage: "k.square.fill",
            statusLinkURL: "https://health.aws.amazon.com/health/status",
            dashboardURL: "https://app.kiro.dev/account/usage",
            isConfigured: { KiroUsageFetcher.hasCredentials() },
            fetch: { try await KiroUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "jetbrains", name: "JetBrains AI", logo: "jetbrains", fallbackSystemImage: "j.square",
            isConfigured: { JetBrainsUsageFetcher.hasCredentials() },
            fetch: { UsageSnapshot(codexSnapshot: try await JetBrainsUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "kimik2", name: "Kimi K2 (unofficial)", logo: "kimik2", fallbackSystemImage: "k.circle.fill",
            isConfigured: { KimiK2UsageFetcher.hasToken() },
            fetch: { try await KimiK2UsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "t3chat", name: "T3 Chat", logo: "t3chat", fallbackSystemImage: "t.square",
            dashboardURL: "https://t3.chat/settings/customization",
            subscriptionDashboardURL: "https://t3.chat/settings/subscription",
            isConfigured: { T3ChatUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await T3ChatUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "codebuff", name: "Codebuff", logo: "codebuff", fallbackSystemImage: "hammer",
            dashboardURL: "https://www.codebuff.com/usage",
            isConfigured: { CodebuffUsageFetcher.hasToken() },
            fetch: { try await CodebuffUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "opencodego", name: "OpenCode Go", logo: "opencodego",
            fallbackSystemImage: "chevron.left.forwardslash.chevron.right",
            dashboardURL: "https://opencode.ai",
            isConfigured: { OpenCodeGoUsageFetcher.hasSession() },
            fetch: { try await OpenCodeGoUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "alibabatokenplan", name: "Alibaba Token Plan", logo: "alibabatokenplan",
            fallbackSystemImage: "a.circle",
            statusLinkURL: "https://status.aliyun.com",
            dashboardURL: "https://bailian.console.aliyun.com/cn-beijing?tab=plan#/efm/subscription/token-plan",
            isConfigured: { AlibabaTokenPlanUsageFetcher.hasToken() || AlibabaTokenPlanUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await AlibabaTokenPlanUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "synthetic", name: "Synthetic", logo: "synthetic", fallbackSystemImage: "s.circle",
            isConfigured: { SyntheticUsageFetcher.hasToken() },
            fetch: { try await SyntheticUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "elevenlabs", name: "ElevenLabs", logo: "elevenlabs", fallbackSystemImage: "waveform",
            statusLinkURL: "https://status.elevenlabs.io",
            dashboardURL: "https://elevenlabs.io/app/developers/usage",
            subscriptionDashboardURL: "https://elevenlabs.io/app/subscription",
            isConfigured: { ElevenLabsUsageFetcher.hasToken() },
            fetch: { try await ElevenLabsUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "mimo", name: "Xiaomi MiMo", logo: "mimo", fallbackSystemImage: "m.circle",
            dashboardURL: "https://platform.xiaomimimo.com/#/console/balance",
            isConfigured: { MiMoUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await MiMoUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "doubao", name: "Doubao", logo: "doubao", fallbackSystemImage: "d.circle",
            dashboardURL: "https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&advancedActiveKey=subscribe",
            isConfigured: { DoubaoUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await DoubaoUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "abacus", name: "Abacus AI", logo: "abacus", fallbackSystemImage: "function",
            dashboardURL: "https://apps.abacus.ai/chatllm/admin/compute-points-usage",
            isConfigured: { AbacusUsageFetcher.hasSession() },
            fetch: { UsageSnapshot(codexSnapshot: try await AbacusUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "crof", name: "Crof", logo: "crof", fallbackSystemImage: "c.circle",
            dashboardURL: "https://crof.ai/dashboard",
            isConfigured: { CrofUsageFetcher.hasToken() },
            fetch: { try await CrofUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "venice", name: "Venice", logo: "venice", fallbackSystemImage: "v.circle",
            dashboardURL: "https://venice.ai/settings/api",
            isConfigured: { VeniceUsageFetcher.hasToken() },
            fetch: { try await VeniceUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "commandcode", name: "Command Code", logo: "commandcode", fallbackSystemImage: "command.circle",
            dashboardURL: "https://commandcode.ai/studio",
            subscriptionDashboardURL: "https://commandcode.ai/sixhobbits/settings/billing",
            isConfigured: { CommandCodeUsageFetcher.hasToken() || CommandCodeUsageFetcher.hasSession() },
            fetch: { try await CommandCodeUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "stepfun", name: "StepFun", logo: "stepfun", fallbackSystemImage: "s.square",
            dashboardURL: "https://platform.stepfun.com/plan-usage",
            isConfigured: { StepFunUsageFetcher.hasToken() },
            fetch: { UsageSnapshot(codexSnapshot: try await StepFunUsageFetcher.fetch()) }),
        UsageProviderEntry(
            id: "bedrock", name: "AWS Bedrock", logo: "bedrock", fallbackSystemImage: "cloud",
            statusLinkURL: "https://health.aws.amazon.com/health/status",
            dashboardURL: "https://console.aws.amazon.com/bedrock",
            isConfigured: { BedrockUsageFetcher.hasCredentials() },
            fetch: { try await BedrockUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "llmproxy", name: "LLM Proxy", logo: "llmproxy", fallbackSystemImage: "network",
            isConfigured: { LLMProxyUsageFetcher.hasToken() },
            fetch: { try await LLMProxyUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "litellm", name: "LiteLLM", logo: "litellm", fallbackSystemImage: "l.square",
            isConfigured: { LiteLLMUsageFetcher.hasToken() },
            fetch: { try await LiteLLMUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "deepgram", name: "Deepgram", logo: "deepgram", fallbackSystemImage: "waveform.circle",
            statusLinkURL: "https://status.deepgram.com",
            dashboardURL: "https://console.deepgram.com/project/",
            isConfigured: { DeepgramUsageFetcher.hasToken() },
            fetch: { try await DeepgramUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "poe", name: "Poe", logo: "poe", fallbackSystemImage: "p.circle",
            dashboardURL: "https://poe.com/api/keys",
            isConfigured: { PoeUsageFetcher.hasToken() },
            fetch: { try await PoeUsageFetcher.fetch() }),
        UsageProviderEntry(
            id: "chutes", name: "Chutes", logo: "chutes", fallbackSystemImage: "c.circle",
            dashboardURL: "https://chutes.ai",
            isConfigured: { ChutesUsageFetcher.hasToken() },
            fetch: { try await ChutesUsageFetcher.fetch() }),
    ]

    public static func entry(for id: String) -> UsageProviderEntry? {
        let canonical = self.canonicalProviderID(id)
        return self.all.first { $0.id == canonical }
    }

    public static func configured() -> [UsageProviderEntry] {
        self.all.filter { $0.isConfigured() }
    }

    public static func orderedEntries(config: AppConfig) -> [UsageProviderEntry] {
        let order = config.usage.effectiveProviderOrder(knownProviderIDs: self.all.map(\.id))
        let entriesByID = Dictionary(uniqueKeysWithValues: self.all.map { ($0.id, $0) })
        return order.compactMap { entriesByID[$0] }
    }

    public static func entries(for selection: String?) throws -> [UsageProviderEntry] {
        let normalized = selection?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else {
            return try self.entries(for: "both")
        }
        if normalized == "all" { return self.all }
        if normalized == "both" {
            let primary = self.primaryProviderIDs.compactMap { id in self.all.first { $0.id == id } }
            return primary.isEmpty ? Array(self.all.prefix(2)) : primary
        }

        let ids = normalized
            .split(separator: ",")
            .map { self.canonicalProviderID(String($0)) }
            .filter { !$0.isEmpty }
        var entries: [UsageProviderEntry] = []
        for id in ids {
            guard let entry = self.all.first(where: { $0.id == id }) else {
                throw UsageProviderCatalogError.unknownProvider(id, known: self.all.map(\.id))
            }
            entries.append(entry)
        }
        return entries
    }

    public static func entries(for selection: String?, config: AppConfig) throws -> [UsageProviderEntry] {
        let ordered = self.orderedEntries(config: config)
        let normalized = selection?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty else {
            return ordered.filter { $0.isEnabled(in: config) }
        }
        if normalized == "all" { return ordered }
        if normalized == "both" {
            return ordered.filter { self.primaryProviderIDs.contains($0.id) }
        }
        return try self.entries(for: selection)
    }
}
