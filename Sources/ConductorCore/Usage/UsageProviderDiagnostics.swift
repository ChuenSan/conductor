import Foundation

public struct UsageProviderDiagnosticBatchExport: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let diagnostics: [UsageProviderDiagnosticExport]

    public init(
        schemaVersion: String = "1.0",
        generatedAt: Date = Date(),
        diagnostics: [UsageProviderDiagnosticExport])
    {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.diagnostics = diagnostics
    }
}

public struct UsageProviderDiagnosticExport: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let provider: String
    public let displayName: String
    /// 实际成功取数来源（如 api / web / cli / local）。
    public let source: String
    /// 请求的 source mode（如 auto / web / cli / api）。
    public let sourceMode: String
    public let configured: Bool
    public let auth: UsageProviderDiagnosticAuthSummary
    public let selectedAccount: UsageProviderDiagnosticSelectedAccount?
    public let settings: UsageProviderDiagnosticSettingsSummary
    public let usage: UsageProviderDiagnosticUsageSummary?
    public let storage: UsageProviderDiagnosticStorageSummary?
    public let fetchAttempts: [UsageProviderDiagnosticFetchAttempt]
    public let error: UsageProviderDiagnosticError?
    public let repairActions: [UsageProviderRepairAction]
    public let redaction: UsageProviderDiagnosticRedactionSummary
}

public struct UsageProviderDiagnosticAuthSummary: Codable, Sendable, Equatable {
    public let configured: Bool
    public let modes: [String]
    public let environmentKeysPresent: [String]
    public let configFieldsPresent: [String]

    public init(
        providerID: String,
        providerConfig: UsageProviderConfig?,
        environment: [String: String],
        selectedAccount: UsageProviderTokenAccount?,
        locallyConfigured: Bool)
    {
        let envKeys = Self.environmentKeysPresent(providerID: providerID, environment: environment)
        let configFields = Self.configFieldsPresent(providerConfig)
        let apiKeyNames = Self.apiKeyNames(providerID: providerID)
        let cookieNames = Self.cookieNames(providerID: providerID)
        let credentialEnvironmentKeys = Set(apiKeyNames + cookieNames)
        var modes: [String] = []

        if selectedAccount != nil {
            modes.append("tokenAccount")
        }
        if providerConfig?.tokenAccounts?.accounts.isEmpty == false {
            modes.append("configuredTokenAccounts")
        }
        if providerConfig?.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            modes.append("configApiKey")
        }
        if providerConfig?.cookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            modes.append("configCookie")
        }
        if envKeys.contains(where: { credentialEnvironmentKeys.contains($0) && apiKeyNames.contains($0) }) {
            modes.append("environmentApiKey")
        }
        if envKeys.contains(where: { credentialEnvironmentKeys.contains($0) && cookieNames.contains($0) }) {
            modes.append("environmentCookie")
        }
        if locallyConfigured, modes.isEmpty {
            modes.append("local")
        }

        self.configured = locallyConfigured || !modes.isEmpty
        self.modes = Self.uniqueSorted(modes)
        self.environmentKeysPresent = envKeys
        self.configFieldsPresent = configFields
    }

    private static func environmentKeysPresent(providerID: String, environment: [String: String]) -> [String] {
        let names = Set(Self.apiKeyNames(providerID: providerID)
            + Self.cookieNames(providerID: providerID)
            + Self.baseURLNames(providerID: providerID)
            + Self.projectNames(providerID: providerID)
            + Self.organizationNames(providerID: providerID)
            + UsageProviderConfigCapabilities.conductorSourceEnvironmentNames(providerID)
            + UsageProviderConfigCapabilities.conductorCookieSourceEnvironmentNames(providerID))
        return names
            .filter { name in
                guard let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                return !value.isEmpty
            }
            .sorted()
    }

    private static func configFieldsPresent(_ config: UsageProviderConfig?) -> [String] {
        guard let config else { return [] }
        var fields: [String] = []
        if config.enabled != nil { fields.append("enabled") }
        if config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("apiKey")
        }
        if config.sourceMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("sourceMode")
        }
        if config.cookieSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("cookieSource")
        }
        if config.cookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("cookieHeader")
        }
        if config.projectID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("projectID")
        }
        if config.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("baseURL")
        }
        if config.organizationID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            fields.append("organizationID")
        }
        if !config.flags.isEmpty { fields.append("flags") }
        if !config.extra.isEmpty { fields.append("extra") }
        if config.tokenAccounts?.accounts.isEmpty == false { fields.append("tokenAccounts") }
        if config.quotaWarnings != nil { fields.append("quotaWarnings") }
        return fields.sorted()
    }

    private static func apiKeyNames(providerID: String) -> [String] {
        var names: [String] = []
        if let primary = UsageProviderConfigCapabilities.apiKeyEnvironmentNames[providerID] {
            names.append(primary)
        }
        names.append(contentsOf: UsageProviderConfigCapabilities.apiKeyAliases[providerID] ?? [])
        return names
    }

    private static func cookieNames(providerID: String) -> [String] {
        UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames[providerID]
            ?? UsageProviderConfigCapabilities.conductorCookieEnvironmentNames(providerID)
    }

    private static func baseURLNames(providerID: String) -> [String] {
        UsageProviderConfigCapabilities.baseURLEnvironmentNames[providerID].map { [$0] } ?? []
    }

    private static func projectNames(providerID: String) -> [String] {
        UsageProviderConfigCapabilities.projectEnvironmentNames[providerID] ?? []
    }

    private static func organizationNames(providerID: String) -> [String] {
        UsageProviderConfigCapabilities.organizationEnvironmentNames[providerID] ?? []
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}

public struct UsageProviderDiagnosticSelectedAccount: Codable, Sendable, Equatable {
    public let label: String
    public let externalIdentifierPresent: Bool
    public let organizationIDPresent: Bool

    public init(account: UsageProviderTokenAccount) {
        self.label = UsageDiagnosticRedactor.redact(account.displayName)
        self.externalIdentifierPresent = account.externalIdentifier?.isEmpty == false
        self.organizationIDPresent = account.organizationID?.isEmpty == false
    }
}

public struct UsageProviderDiagnosticSettingsSummary: Codable, Sendable, Equatable {
    public let configuredExplicitly: Bool
    public let enabled: Bool?
    public let sourceModes: [String]
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
    public let supportsAPIKey: Bool
    public let supportsTokenAccounts: Bool
    public let cliSessionPolicy: UsageProviderCLISessionPolicy
    public let signInCommand: String?
    public let dashboardURL: String?
    public let subscriptionDashboardURL: String?
    public let changelogURL: String?
    public let environmentHints: UsageProviderConfigEnvironmentHints
    public let sourceMode: String?
    public let cookieSource: String?
    public let hasAPIKey: Bool
    public let hasCookieHeader: Bool
    public let baseURLHost: String?
    public let projectIDPresent: Bool
    public let organizationIDPresent: Bool
    public let enabledFlags: [String]
    public let extraKeys: [String]
    public let tokenAccounts: UsageProviderDiagnosticTokenAccountSummary?

    public init(
        providerID: String,
        config: UsageProviderConfig?,
        sourceModes: [String] = [],
        displayMetadata: UsageProviderDisplayMetadata? = nil,
        cliSessionPolicy: UsageProviderCLISessionPolicy = .none,
        signInCommand: String? = nil,
        dashboardURL: String? = nil,
        subscriptionDashboardURL: String? = nil,
        changelogURL: String? = nil)
    {
        self.configuredExplicitly = config != nil
        self.enabled = config?.enabled
        self.sourceModes = sourceModes.isEmpty ? UsageProviderCatalog.sourceModes(for: providerID) : sourceModes
        let metadata = displayMetadata
            ?? UsageProviderCatalog.displayMetadata(for: providerID, displayName: providerID)
        self.sessionLabel = metadata.sessionLabel
        self.weeklyLabel = metadata.weeklyLabel
        self.opusLabel = metadata.opusLabel
        self.supportsOpus = metadata.supportsOpus
        self.supportsCredits = metadata.supportsCredits
        self.creditsHint = metadata.creditsHint
        self.toggleTitle = metadata.toggleTitle
        self.cliName = metadata.cliName
        self.isPrimaryProvider = metadata.isPrimaryProvider
        self.usesAccountFallback = metadata.usesAccountFallback
        self.supportsAPIKey = UsageProviderConfigCapabilities.supportsAPIKey(providerID)
        self.supportsTokenAccounts = UsageProviderConfigCapabilities.supportsTokenAccounts(providerID)
        self.cliSessionPolicy = cliSessionPolicy
        self.signInCommand = signInCommand
        self.dashboardURL = dashboardURL
        self.subscriptionDashboardURL = subscriptionDashboardURL
        self.changelogURL = changelogURL
        self.environmentHints = UsageProviderConfigCapabilities.environmentHints(providerID: providerID)
        self.sourceMode = Self.nonEmpty(config?.sourceMode)
        self.cookieSource = Self.nonEmpty(config?.cookieSource)
        self.hasAPIKey = Self.nonEmpty(config?.apiKey) != nil
        self.hasCookieHeader = Self.nonEmpty(config?.cookieHeader) != nil
        self.baseURLHost = Self.baseURLHost(config?.baseURL)
        self.projectIDPresent = Self.nonEmpty(config?.projectID) != nil
        self.organizationIDPresent = Self.nonEmpty(config?.organizationID) != nil
        self.enabledFlags = (config?.flags ?? [:])
            .filter { $0.value }
            .map(\.key)
            .sorted()
        self.extraKeys = (config?.extra ?? [:])
            .filter { Self.nonEmpty($0.value) != nil }
            .map(\.key)
            .sorted()
        self.tokenAccounts = config?.tokenAccounts.map(UsageProviderDiagnosticTokenAccountSummary.init(data:))
    }

    private static func baseURLHost(_ raw: String?) -> String? {
        guard let raw = Self.nonEmpty(raw),
              let components = URLComponents(string: raw),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }
        var output = components.scheme.map { "\($0)://" } ?? ""
        output += host
        if let port = components.port {
            output += ":\(port)"
        }
        return UsageDiagnosticRedactor.redact(output)
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public struct UsageProviderDiagnosticTokenAccountSummary: Codable, Sendable, Equatable {
    public let count: Int
    public let activeIndex: Int
    public let activeLabel: String?
    public let labels: [String]
    public let externalIdentifierCount: Int
    public let organizationIDCount: Int

    public init(data: UsageProviderTokenAccountData) {
        let clamped = data.clampedActiveIndex()
        self.count = data.accounts.count
        self.activeIndex = clamped + 1
        self.activeLabel = data.accounts.indices.contains(clamped)
            ? UsageDiagnosticRedactor.redact(data.accounts[clamped].displayName)
            : nil
        self.labels = data.accounts.map { UsageDiagnosticRedactor.redact($0.displayName) }
        self.externalIdentifierCount = data.accounts.filter { $0.externalIdentifier?.isEmpty == false }.count
        self.organizationIDCount = data.accounts.filter { $0.organizationID?.isEmpty == false }.count
    }
}

public struct UsageProviderDiagnosticUsageSummary: Codable, Sendable, Equatable {
    public let sourceLabel: String?
    public let updatedAt: Date
    public let planName: String?
    public let accountLabel: String?
    public let windows: [UsageProviderDiagnosticRateWindow]
    public let extraWindowCount: Int
    public let providerCost: UsageProviderDiagnosticCostSummary?
    public let dataKeys: [String]

    public init(snapshot: UsageSnapshot) {
        var windows: [UsageProviderDiagnosticRateWindow] = []
        if let primary = snapshot.primary {
            windows.append(.init(label: primary.title ?? "primary", window: primary))
        }
        if let secondary = snapshot.secondary {
            windows.append(.init(label: secondary.title ?? "secondary", window: secondary))
        }
        if let tertiary = snapshot.tertiary {
            windows.append(.init(label: tertiary.title ?? "tertiary", window: tertiary))
        }
        for extra in snapshot.extraRateWindows {
            windows.append(.init(label: extra.title, window: extra.window))
        }

        var dataKeys: [String] = []
        if snapshot.primary != nil { dataKeys.append("primaryWindow") }
        if snapshot.secondary != nil { dataKeys.append("secondaryWindow") }
        if snapshot.tertiary != nil { dataKeys.append("tertiaryWindow") }
        if !snapshot.extraRateWindows.isEmpty { dataKeys.append("extraRateWindows") }
        if snapshot.providerCost != nil { dataKeys.append("providerCost") }
        if snapshot.claudeAdminAPIUsage != nil { dataKeys.append("claudeAdminAPIUsage") }
        if snapshot.planName?.isEmpty == false { dataKeys.append("planName") }
        if snapshot.accountLabel?.isEmpty == false { dataKeys.append("accountLabel") }

        self.sourceLabel = snapshot.sourceLabel
        self.updatedAt = snapshot.updatedAt
        self.planName = snapshot.planName.map(UsageDiagnosticRedactor.redact)
        self.accountLabel = snapshot.accountLabel.map(UsageDiagnosticRedactor.redact)
        self.windows = windows
        self.extraWindowCount = snapshot.extraRateWindows.count
        self.providerCost = snapshot.providerCost.map(UsageProviderDiagnosticCostSummary.init(cost:))
        self.dataKeys = dataKeys.sorted()
    }
}

public struct UsageProviderDiagnosticRateWindow: Codable, Sendable, Equatable {
    public let label: String
    public let usedPercent: Double
    public let remainingPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?
    public let hasResetDescription: Bool

    public init(label: String, window: RateWindow) {
        self.label = UsageDiagnosticRedactor.redact(label)
        self.usedPercent = window.usedPercent
        self.remainingPercent = window.remainingPercent
        self.windowMinutes = window.windowMinutes
        self.resetsAt = window.resetsAt
        self.hasResetDescription = window.resetDescription?.isEmpty == false
    }
}

public struct UsageProviderDiagnosticCostSummary: Codable, Sendable, Equatable {
    public let used: Double
    public let limit: Double
    public let currencyCode: String
    public let period: String?
    public let resetsAt: Date?
    public let usedPercent: Double?

    public init(cost: ProviderCostSnapshot) {
        self.used = cost.used
        self.limit = cost.limit
        self.currencyCode = UsageDiagnosticRedactor.redact(cost.currencyCode)
        self.period = cost.period.map(UsageDiagnosticRedactor.redact)
        self.resetsAt = cost.resetsAt
        self.usedPercent = cost.hasLimit ? cost.usedPercent : nil
    }
}

public struct UsageProviderDiagnosticStorageSummary: Codable, Sendable, Equatable {
    public let totalBytes: Int64
    public let byteCountText: String
    public let hasLocalData: Bool
    public let pathCount: Int
    public let missingPathCount: Int
    public let unreadablePathCount: Int
    public let componentCount: Int
    public let paths: [String]
    public let missingPaths: [String]
    public let unreadablePaths: [String]
    public let topComponents: [UsageProviderDiagnosticStorageComponent]
    public let cleanupRecommendations: [UsageProviderDiagnosticStorageRecommendation]
    public let updatedAt: Date

    public init(
        footprint: ProviderStorageFootprint,
        maxComponents: Int = 5,
        maxRecommendations: Int = 3)
    {
        self.totalBytes = footprint.totalBytes
        self.byteCountText = footprint.byteCountText
        self.hasLocalData = footprint.hasLocalData
        self.pathCount = footprint.paths.count
        self.missingPathCount = footprint.missingPaths.count
        self.unreadablePathCount = footprint.unreadablePaths.count
        self.componentCount = footprint.components.count
        self.paths = footprint.paths.map(Self.safePath)
        self.missingPaths = footprint.missingPaths.map(Self.safePath)
        self.unreadablePaths = footprint.unreadablePaths.map(Self.safePath)
        self.topComponents = footprint.components.prefix(maxComponents).map {
            UsageProviderDiagnosticStorageComponent(component: $0)
        }
        self.cleanupRecommendations = footprint.cleanupRecommendations.prefix(maxRecommendations).map {
            UsageProviderDiagnosticStorageRecommendation(recommendation: $0)
        }
        self.updatedAt = footprint.updatedAt
    }

    static func safePath(_ raw: String) -> String {
        let home = NSHomeDirectory()
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        let homeCandidates = [
            home,
            homeURL.standardizedFileURL.path,
            homeURL.resolvingSymlinksInPath().path,
        ]
        let rawCandidates = [
            raw,
            URL(fileURLWithPath: raw).standardizedFileURL.path,
            URL(fileURLWithPath: raw).resolvingSymlinksInPath().path,
        ]

        for rawCandidate in rawCandidates {
            for homeCandidate in homeCandidates where !homeCandidate.isEmpty {
                if rawCandidate == homeCandidate {
                    return UsageDiagnosticRedactor.redact("~")
                }
                let prefix = homeCandidate.hasSuffix("/") ? homeCandidate : "\(homeCandidate)/"
                if rawCandidate.hasPrefix(prefix) {
                    let suffix = rawCandidate.dropFirst(homeCandidate.count)
                    return UsageDiagnosticRedactor.redact("~" + suffix)
                }
            }
        }

        return UsageDiagnosticRedactor.redact(raw)
    }
}

public struct UsageProviderDiagnosticStorageComponent: Codable, Sendable, Equatable {
    public let name: String
    public let path: String
    public let bytes: Int64
    public let byteCountText: String

    public init(component: ProviderStorageFootprint.Component) {
        self.name = UsageDiagnosticRedactor.redact(component.name)
        self.path = UsageProviderDiagnosticStorageSummary.safePath(component.path)
        self.bytes = component.totalBytes
        self.byteCountText = ByteCountFormatter.string(fromByteCount: component.totalBytes, countStyle: .file)
    }
}

public struct UsageProviderDiagnosticStorageRecommendation: Codable, Sendable, Equatable {
    public let title: String
    public let path: String
    public let bytes: Int64
    public let byteCountText: String
    public let riskLevel: String
    public let consequence: String

    public init(recommendation: ProviderStorageRecommendation) {
        self.title = UsageDiagnosticRedactor.redact(recommendation.exportTitle)
        self.path = UsageProviderDiagnosticStorageSummary.safePath(recommendation.path)
        self.bytes = recommendation.bytes
        self.byteCountText = ByteCountFormatter.string(fromByteCount: recommendation.bytes, countStyle: .file)
        self.riskLevel = recommendation.riskLevel.rawValue
        self.consequence = UsageDiagnosticRedactor.redact(recommendation.exportConsequence)
    }
}

public struct UsageProviderDiagnosticFetchAttempt: Codable, Sendable, Equatable {
    public let kind: String
    public let wasAvailable: Bool
    public let durationMilliseconds: Int
    public let errorCategory: String?
}

public struct UsageProviderDiagnosticError: Codable, Sendable, Equatable {
    public let category: String
    public let safeDescription: String
    public let message: String

    public init(error: Error, authConfigured: Bool) {
        let category = Self.category(error: error, authConfigured: authConfigured)
        self.category = category
        self.safeDescription = Self.safeDescription(category: category)
        self.message = UsageDiagnosticRedactor.redact(Self.message(error))
    }

    static func category(error: Error, authConfigured: Bool) -> String {
        if let dashboardError = error as? OpenAIDashboardUsageError {
            return dashboardError.diagnosticCategory(authConfigured: authConfigured)
        }
        if case let CodexDashboardPolicyError.displayOnly(decision) = error {
            return decision.diagnosticCategory(authConfigured: authConfigured)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "network"
        }
        let message = Self.message(error).lowercased()
        if message.contains("cloudflare") || message.contains("captcha") ||
            message.contains("challenge") || message.contains("turnstile") ||
            message.contains("cf-ray")
        {
            return "network"
        }
        if message.contains("ssl") || message.contains("certificate") || message.contains("network") ||
            message.contains("timeout") || message.contains("connection") || message.contains("dns") ||
            message.contains("offline") || message.contains("internet")
        {
            return "network"
        }
        if message.contains("unauthorized") || message.contains("forbidden") || message.contains("auth") ||
            message.contains("credential") || message.contains("token") || message.contains("cookie") ||
            message.contains("api key") || message.contains("missing key") || message.contains("login") ||
            message.contains("401") || message.contains("403")
        {
            return "auth"
        }
        if message.contains("source") || message.contains("not supported") || message.contains("unavailable") ||
            message.contains("invalid config") || message.contains("configuration") || message.contains("setting")
        {
            return authConfigured ? "configuration" : "auth"
        }
        if message.contains("base url") || message.contains("baseurl") || message.contains("endpoint") ||
            message.contains("deployment") || message.contains("project") || message.contains("workspace") ||
            message.contains("organization") || message.contains("organisation") || message.contains("org id") ||
            message.contains("基础 url") || message.contains("端点") || message.contains("部署") ||
            message.contains("项目") || message.contains("工作区") || message.contains("组织")
        {
            return "configuration"
        }
        if message.contains("parse") || message.contains("decode") || message.contains("json") ||
            message.contains("format") || message.contains("html")
        {
            return "parse"
        }
        if message.contains("api") || message.contains("http") || message.contains("status") ||
            message.contains("404") || message.contains("429") || message.contains("500") ||
            message.contains("502") || message.contains("503")
        {
            return "api"
        }
        return "unknown"
    }

    private static func safeDescription(category: String) -> String {
        switch category {
        case "network":
            return "Network error - check connection, proxy, SSL, or provider status."
        case "auth":
            return "Authentication issue - check token, cookie, account, or login state."
        case "api":
            return "Provider API error - service returned an unexpected response."
        case "parse":
            return "Parse error - provider response format changed or is incomplete."
        case "configuration":
            return "Configuration issue - check source mode and provider settings."
        default:
            return "Unexpected error - inspect the redacted message."
        }
    }

    private static func message(_ error: Error) -> String {
        let nsError = error as NSError
        if !nsError.localizedDescription.isEmpty {
            return nsError.localizedDescription
        }
        return String(describing: error)
    }
}

public struct UsageProviderDiagnosticRedactionSummary: Codable, Sendable, Equatable {
    public let applied: Bool
    public let redactedFields: [String]

    public init() {
        self.applied = true
        self.redactedFields = [
            "accountLabel",
            "authorization",
            "cookie",
            "email",
            "password",
            "token",
        ]
    }
}

public enum UsageProviderDiagnostics {
    public static func diagnoseUnlessCancelled(
        entry: UsageProviderEntry,
        source: String,
        config: AppConfig,
        selectedAccount: UsageProviderTokenAccount? = nil,
        storageFootprint: ProviderStorageFootprint? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> UsageProviderDiagnosticExport {
        try Task.checkCancellation()
        let providerConfig = config.usage.providers[entry.id]
        let startedAt = Date()
        let locallyConfigured = entry.isConfigured()
        let auth = UsageProviderDiagnosticAuthSummary(
            providerID: entry.id,
            providerConfig: providerConfig,
            environment: environment,
            selectedAccount: selectedAccount,
            locallyConfigured: locallyConfigured)

        do {
            try Task.checkCancellation()
            let snapshot = try await entry.fetch()
            try Task.checkCancellation()
            let actualSource = Self.actualSource(requested: source, snapshot: snapshot)
            return UsageProviderDiagnosticExport(
                schemaVersion: "1.0",
                generatedAt: Date(),
                provider: entry.id,
                displayName: UsageDiagnosticRedactor.redact(entry.name),
                source: actualSource,
                sourceMode: source,
                configured: auth.configured,
                auth: auth,
                selectedAccount: selectedAccount.map(UsageProviderDiagnosticSelectedAccount.init(account:)),
                settings: UsageProviderDiagnosticSettingsSummary(
                    providerID: entry.id,
                    config: providerConfig,
                    sourceModes: entry.sourceModes,
                    displayMetadata: entry.displayMetadata,
                    cliSessionPolicy: entry.cliSessionPolicy,
                    signInCommand: entry.signInCommand,
                    dashboardURL: entry.dashboardURL,
                    subscriptionDashboardURL: entry.subscriptionDashboardURL,
                    changelogURL: entry.changelogURL),
                usage: UsageProviderDiagnosticUsageSummary(snapshot: snapshot),
                storage: storageFootprint.map { UsageProviderDiagnosticStorageSummary(footprint: $0) },
                fetchAttempts: [
                    UsageProviderDiagnosticFetchAttempt(
                        kind: actualSource,
                        wasAvailable: true,
                        durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                        errorCategory: nil),
                ],
                error: nil,
                repairActions: [],
                redaction: UsageProviderDiagnosticRedactionSummary())
        } catch {
            try UsageProviderCancellation.rethrowIfCancelled(error)
            let diagnosticError = UsageProviderDiagnosticError(error: error, authConfigured: auth.configured)
            let repairActions = UsageProviderRepairActions.actions(
                providerID: entry.id,
                providerName: entry.name,
                configured: auth.configured,
                errorMessage: diagnosticError.message,
                category: diagnosticError.category,
                source: source,
                hasStatusPage: entry.statusURL != nil,
                statusURL: entry.statusURL)
            return UsageProviderDiagnosticExport(
                schemaVersion: "1.0",
                generatedAt: Date(),
                provider: entry.id,
                displayName: UsageDiagnosticRedactor.redact(entry.name),
                source: source,
                sourceMode: source,
                configured: auth.configured,
                auth: auth,
                selectedAccount: selectedAccount.map(UsageProviderDiagnosticSelectedAccount.init(account:)),
                settings: UsageProviderDiagnosticSettingsSummary(
                    providerID: entry.id,
                    config: providerConfig,
                    sourceModes: entry.sourceModes,
                    displayMetadata: entry.displayMetadata,
                    cliSessionPolicy: entry.cliSessionPolicy,
                    signInCommand: entry.signInCommand,
                    dashboardURL: entry.dashboardURL,
                    subscriptionDashboardURL: entry.subscriptionDashboardURL,
                    changelogURL: entry.changelogURL),
                usage: nil,
                storage: storageFootprint.map { UsageProviderDiagnosticStorageSummary(footprint: $0) },
                fetchAttempts: [
                    UsageProviderDiagnosticFetchAttempt(
                        kind: source,
                        wasAvailable: false,
                        durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                        errorCategory: diagnosticError.category),
                ],
                error: diagnosticError,
                repairActions: repairActions,
                redaction: UsageProviderDiagnosticRedactionSummary())
        }
    }

    public static func diagnose(
        entry: UsageProviderEntry,
        source: String,
        config: AppConfig,
        selectedAccount: UsageProviderTokenAccount? = nil,
        storageFootprint: ProviderStorageFootprint? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> UsageProviderDiagnosticExport {
        let providerConfig = config.usage.providers[entry.id]
        let startedAt = Date()
        let locallyConfigured = entry.isConfigured()
        let auth = UsageProviderDiagnosticAuthSummary(
            providerID: entry.id,
            providerConfig: providerConfig,
            environment: environment,
            selectedAccount: selectedAccount,
            locallyConfigured: locallyConfigured)

        do {
            let snapshot = try await entry.fetch()
            let actualSource = Self.actualSource(requested: source, snapshot: snapshot)
            return UsageProviderDiagnosticExport(
                schemaVersion: "1.0",
                generatedAt: Date(),
                provider: entry.id,
                displayName: UsageDiagnosticRedactor.redact(entry.name),
                source: actualSource,
                sourceMode: source,
                configured: auth.configured,
                auth: auth,
                selectedAccount: selectedAccount.map(UsageProviderDiagnosticSelectedAccount.init(account:)),
                settings: UsageProviderDiagnosticSettingsSummary(
                    providerID: entry.id,
                    config: providerConfig,
                    sourceModes: entry.sourceModes,
                    displayMetadata: entry.displayMetadata,
                    cliSessionPolicy: entry.cliSessionPolicy,
                    signInCommand: entry.signInCommand,
                    dashboardURL: entry.dashboardURL,
                    subscriptionDashboardURL: entry.subscriptionDashboardURL,
                    changelogURL: entry.changelogURL),
                usage: UsageProviderDiagnosticUsageSummary(snapshot: snapshot),
                storage: storageFootprint.map { UsageProviderDiagnosticStorageSummary(footprint: $0) },
                fetchAttempts: [
                    UsageProviderDiagnosticFetchAttempt(
                        kind: actualSource,
                        wasAvailable: true,
                        durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                        errorCategory: nil),
                ],
                error: nil,
                repairActions: [],
                redaction: UsageProviderDiagnosticRedactionSummary())
        } catch {
            let diagnosticError = UsageProviderDiagnosticError(error: error, authConfigured: auth.configured)
            let repairActions = UsageProviderRepairActions.actions(
                providerID: entry.id,
                providerName: entry.name,
                configured: auth.configured,
                errorMessage: diagnosticError.message,
                category: diagnosticError.category,
                source: source,
                hasStatusPage: entry.statusURL != nil,
                statusURL: entry.statusURL)
            return UsageProviderDiagnosticExport(
                schemaVersion: "1.0",
                generatedAt: Date(),
                provider: entry.id,
                displayName: UsageDiagnosticRedactor.redact(entry.name),
                source: source,
                sourceMode: source,
                configured: auth.configured,
                auth: auth,
                selectedAccount: selectedAccount.map(UsageProviderDiagnosticSelectedAccount.init(account:)),
                settings: UsageProviderDiagnosticSettingsSummary(
                    providerID: entry.id,
                    config: providerConfig,
                    sourceModes: entry.sourceModes,
                    displayMetadata: entry.displayMetadata,
                    cliSessionPolicy: entry.cliSessionPolicy,
                    signInCommand: entry.signInCommand,
                    dashboardURL: entry.dashboardURL,
                    subscriptionDashboardURL: entry.subscriptionDashboardURL,
                    changelogURL: entry.changelogURL),
                usage: nil,
                storage: storageFootprint.map { UsageProviderDiagnosticStorageSummary(footprint: $0) },
                fetchAttempts: [
                    UsageProviderDiagnosticFetchAttempt(
                        kind: source,
                        wasAvailable: false,
                        durationMilliseconds: Self.durationMilliseconds(since: startedAt),
                        errorCategory: diagnosticError.category),
                ],
                error: diagnosticError,
                repairActions: repairActions,
                redaction: UsageProviderDiagnosticRedactionSummary())
        }
    }

    private static func durationMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
    }

    private static func actualSource(requested: String, snapshot: UsageSnapshot) -> String {
        snapshot.sourceLabel ?? requested
    }
}

public enum UsageProviderDiagnosticTextRenderer {
    public static func render(_ diagnostics: [UsageProviderDiagnosticExport]) -> String {
        diagnostics.map(Self.render(diagnostic:)).joined(separator: "\n\n")
    }

    private static func render(diagnostic: UsageProviderDiagnosticExport) -> String {
        var lines: [String] = []
        lines.append("\(diagnostic.displayName) (\(diagnostic.provider))")
        lines.append("  configured: \(diagnostic.configured ? "yes" : "no")")
        lines.append("  source: \(diagnostic.source)")
        if diagnostic.source != diagnostic.sourceMode {
            lines.append("  source mode: \(diagnostic.sourceMode)")
        }
        if !diagnostic.auth.modes.isEmpty {
            lines.append("  auth modes: \(diagnostic.auth.modes.joined(separator: ", "))")
        }
        if let account = diagnostic.selectedAccount {
            lines.append("  account: \(account.label)")
        }
        lines.append(contentsOf: Self.render(settings: diagnostic.settings))
        if let storage = diagnostic.storage {
            lines.append(contentsOf: Self.render(storage: storage))
        }
        if let error = diagnostic.error {
            lines.append("  error: \(error.category) - \(error.safeDescription)")
            lines.append("  message: \(error.message)")
            for action in diagnostic.repairActions {
                lines.append("  next: \(action.title) - \(action.detail)")
                if let command = action.command, !command.isEmpty {
                    lines.append("    command: \(command)")
                }
                if let url = action.url, !url.isEmpty {
                    lines.append("    url: \(url)")
                }
            }
            return lines.joined(separator: "\n")
        }
        guard let usage = diagnostic.usage else {
            lines.append("  usage: no data")
            return lines.joined(separator: "\n")
        }
        if let plan = usage.planName, !plan.isEmpty {
            lines.append("  plan: \(plan)")
        }
        if let account = usage.accountLabel, !account.isEmpty {
            lines.append("  usage account: \(account)")
        }
        if usage.windows.isEmpty, usage.providerCost == nil {
            lines.append("  usage: empty")
        }
        for window in usage.windows {
            lines.append("  \(window.label): \(Self.percent(window.usedPercent)) used, \(Self.percent(window.remainingPercent)) remaining")
        }
        if let cost = usage.providerCost {
            lines.append("  cost: \(Self.money(cost.used, code: cost.currencyCode))\(Self.limitSuffix(cost))")
        }
        return lines.joined(separator: "\n")
    }

    private static func render(settings: UsageProviderDiagnosticSettingsSummary) -> [String] {
        var lines: [String] = []
        if let command = settings.signInCommand, !command.isEmpty {
            lines.append("  sign in: \(command)")
        }
        lines.append("  cli name: \(settings.cliName)")
        let labels = [settings.sessionLabel, settings.weeklyLabel, settings.opusLabel]
            .compactMap { label in
                guard let label, !label.isEmpty else { return nil }
                return label
            }
            .joined(separator: " / ")
        if !labels.isEmpty {
            lines.append("  window labels: \(labels)")
        }
        var traits: [String] = []
        if settings.isPrimaryProvider { traits.append("primary") }
        if settings.usesAccountFallback { traits.append("account-fallback") }
        if settings.supportsCredits { traits.append("credits") }
        if settings.supportsOpus { traits.append("tertiary-window") }
        if !traits.isEmpty {
            lines.append("  traits: \(traits.joined(separator: ", "))")
        }
        if !settings.creditsHint.isEmpty {
            lines.append("  credits: \(settings.creditsHint)")
        }
        if !settings.sourceModes.isEmpty {
            lines.append("  source modes: \(settings.sourceModes.joined(separator: ", "))")
        }
        if let dashboard = settings.dashboardURL, !dashboard.isEmpty {
            lines.append("  dashboard: \(dashboard)")
        }
        if let subscription = settings.subscriptionDashboardURL, !subscription.isEmpty {
            lines.append("  subscription: \(subscription)")
        }
        if let changelog = settings.changelogURL, !changelog.isEmpty {
            lines.append("  changelog: \(changelog)")
        }
        let hints = settings.environmentHints
        appendHint("api key env", values: hints.apiKey, to: &lines)
        appendHint("cookie env", values: hints.cookieHeader, to: &lines)
        appendHint("base url env", values: hints.baseURL, to: &lines)
        appendHint("project env", values: hints.project, to: &lines)
        appendHint("organization env", values: hints.organization, to: &lines)
        appendHint("source env", values: hints.sourceMode, to: &lines)
        appendHint("cookie source env", values: hints.cookieSource, to: &lines)
        return lines
    }

    private static func render(storage: UsageProviderDiagnosticStorageSummary) -> [String] {
        var lines: [String] = []
        let status = storage.hasLocalData ? storage.byteCountText : "no local data"
        lines.append("  storage: \(status) across \(storage.pathCount) paths")
        if storage.missingPathCount > 0 {
            lines.append("  storage missing paths: \(storage.missingPathCount)")
            lines.append(contentsOf: Self.storagePathLines(label: "storage missing path", paths: storage.missingPaths, totalCount: storage.missingPathCount))
        }
        if storage.unreadablePathCount > 0 {
            lines.append("  storage unreadable paths: \(storage.unreadablePathCount)")
            lines.append(contentsOf: Self.storagePathLines(label: "storage unreadable path", paths: storage.unreadablePaths, totalCount: storage.unreadablePathCount))
        }
        for component in storage.topComponents.prefix(3) {
            lines.append("  storage component: \(component.name) \(component.byteCountText) - \(component.path)")
        }
        for recommendation in storage.cleanupRecommendations.prefix(3) {
            lines.append("  cleanup: \(recommendation.title) \(recommendation.byteCountText) - \(recommendation.path)")
        }
        return lines
    }

    private static func storagePathLines(label: String, paths: [String], totalCount: Int, limit: Int = 3) -> [String] {
        var lines = paths.prefix(limit).map { "  \(label): \($0)" }
        if totalCount > limit {
            lines.append("  \(label): ... (+\(totalCount - limit) more)")
        }
        return lines
    }

    private static func appendHint(_ label: String, values: [String], to lines: inout [String]) {
        guard !values.isEmpty else { return }
        lines.append("  \(label): \(values.joined(separator: ", "))")
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func money(_ value: Double, code: String) -> String {
        if code.uppercased() == "USD" {
            return String(format: "$%.2f", value)
        }
        return "\(String(format: "%.2f", value)) \(code)"
    }

    private static func limitSuffix(_ cost: UsageProviderDiagnosticCostSummary) -> String {
        guard cost.limit > 0 else { return "" }
        let percent = cost.usedPercent.map { " (\(Self.percent($0)) used)" } ?? ""
        return " / \(Self.money(cost.limit, code: cost.currencyCode))\(percent)"
    }
}

public enum UsageDiagnosticRedactor {
    public static func redact(_ text: String) -> String {
        var output = text
        output = Self.replace(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: output, with: "<redacted-email>", options: [.caseInsensitive])
        output = Self.replace(pattern: #"(?i)\bbearer\s+[a-z0-9._\-+/=]{8,}\b"#, in: output, with: "Bearer <redacted>")
        output = Self.replace(pattern: #"(?i)(authorization\s*:\s*)([^\r\n,}]+)"#, in: output, with: "$1<redacted>")
        output = Self.replace(pattern: #"(?i)(cookie\s*:\s*)([^\r\n}]+)"#, in: output, with: "$1<redacted>")
        output = Self.replace(pattern: ##"(?i)("?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|session[_-]?token|password|secret)"?\s*[:=]\s*"?)([^"',\s}]{6,})"?"##, in: output, with: "$1<redacted>")
        output = Self.replace(pattern: #"\b(sk-[A-Za-z0-9_\-]{12,}|sk-api-[A-Za-z0-9_\-]{8,}|sk-cp-[A-Za-z0-9_\-]{8,}|ghp_[A-Za-z0-9_]{12,}|github_pat_[A-Za-z0-9_]{12,})\b"#, in: output, with: "<redacted-token>")
        output = Self.replace(pattern: #"(?i)([?&](?:token|key|secret|password|session|code)=)[^&\s]+"#, in: output, with: "$1<redacted>")
        output = Self.replace(
            pattern: #"(?i)((?:^|[/._-])(?:[a-z0-9]+[-_])?(?:api[-_]?key|access[-_]?token|refresh[-_]?token|session[-_]?token|token|key|secret|password|credential)\s*=\s*)[^/\\'",\]}\)\s]+"#,
            in: output,
            with: "$1<redacted>")
        return output
    }

    private static func replace(
        pattern: String,
        in text: String,
        with template: String,
        options: NSRegularExpression.Options = []) -> String
    {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}
