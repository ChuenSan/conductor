import Foundation

/// 用户配置（来自 `~/.config/conductor/config.yaml`）。纯 Codable 模型，不含 YAML 解析（那在 App 层用 Yams）。
///
/// **容错**：每个结构都自定义 `init(from:)`，缺字段用默认、未知字段忽略——
/// 保证旧/新配置文件都能加载，单个坏字段不至于整份失效（高商用）。
/// `validated()` 进一步夹紧非法值（字号范围、枚举回退）。
public struct AppConfig: Codable, Equatable, Sendable {
    public var appearance: Appearance
    public var terminal: TerminalConfig
    public var behavior: Behavior
    public var keybindings: [String: String]
    public var ghosttyOverrides: [String: String]
    public var workspaceDefaults: WorkspaceDefaults
    public var usage: UsageConfig
    public var companion: CompanionConfig

    public init(appearance: Appearance = .init(),
                terminal: TerminalConfig = .init(),
                behavior: Behavior = .init(),
                keybindings: [String: String] = [:],
                ghosttyOverrides: [String: String] = [:],
                workspaceDefaults: WorkspaceDefaults = .init(),
                usage: UsageConfig = .init(),
                companion: CompanionConfig = .init()) {
        self.appearance = appearance
        self.terminal = terminal
        self.behavior = behavior
        self.keybindings = keybindings
        self.ghosttyOverrides = ghosttyOverrides
        self.workspaceDefaults = workspaceDefaults
        self.usage = usage
        self.companion = companion
    }

    public static let `default` = AppConfig()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = c.value(.appearance, AppConfig.default.appearance)
        terminal = c.value(.terminal, AppConfig.default.terminal)
        behavior = c.value(.behavior, AppConfig.default.behavior)
        keybindings = c.value(.keybindings, [:])
        ghosttyOverrides = c.value(.ghosttyOverrides, [:])
        workspaceDefaults = c.value(.workspaceDefaults, .init())
        usage = c.value(.usage, .init())
        companion = c.value(.companion, AppConfig.default.companion)
    }

    /// 夹紧非法值，返回修正后的副本。
    public func validated() -> AppConfig {
        var copy = self
        copy.appearance = appearance.validated()
        copy.terminal = terminal.validated()
        copy.behavior = behavior.validated()
        copy.usage = usage.validated()
        copy.companion = companion.validated()
        copy.ghosttyOverrides = ghosttyOverrides.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return copy
    }
}

// MARK: - usage（账号用量 provider 的启用与凭证）

/// 用量 provider 配置：按 provider id 存「是否启用 + 凭证 + 来源偏好 + 高级字段」。
/// 应用内填的 key 会被注入进程环境变量（解决 GUI 不继承 shell env），fetcher 据此取数。
public struct UsageConfig: Codable, Equatable, Sendable {
    public static let manualProviderRefreshIntervalSeconds = 0
    public static let defaultProviderRefreshIntervalSeconds = 300
    public static let allowedProviderRefreshIntervalSeconds = [0, 60, 120, 300, 900, 1800]
    public static let allowedWeeklyProgressWorkDays = [4, 5, 7]
    public static let maxStatusBarOverviewProviders = 3

    public var quotaWarnings: QuotaWarningConfig
    public var quotaWarningMarkersVisible: Bool
    public var usageBarsShowUsed: Bool
    public var resetTimesShowAbsolute: Bool
    public var showOptionalCreditsAndExtraUsage: Bool
    public var hidePersonalInfo: Bool
    public var weeklyProgressWorkDays: Int?
    public var providerChangelogLinksEnabled: Bool
    public var providerStorageFootprintsEnabled: Bool
    public var providerRefreshIntervalSeconds: Int
    public var providerOrder: [String]
    public var providersSortedAlphabetically: Bool
    public var statusBarOverviewProviderIDs: [String]
    public var statusBarOverviewSelectionBasisIDs: [String]
    public var providers: [String: UsageProviderConfig]

    public init(
        quotaWarnings: QuotaWarningConfig = .init(),
        quotaWarningMarkersVisible: Bool = true,
        usageBarsShowUsed: Bool = false,
        resetTimesShowAbsolute: Bool = false,
        showOptionalCreditsAndExtraUsage: Bool = true,
        hidePersonalInfo: Bool = false,
        weeklyProgressWorkDays: Int? = nil,
        providerChangelogLinksEnabled: Bool = false,
        providerStorageFootprintsEnabled: Bool = false,
        providerRefreshIntervalSeconds: Int = Self.defaultProviderRefreshIntervalSeconds,
        providerOrder: [String] = [],
        providersSortedAlphabetically: Bool = false,
        statusBarOverviewProviderIDs: [String] = [],
        statusBarOverviewSelectionBasisIDs: [String] = [],
        providers: [String: UsageProviderConfig] = [:])
    {
        self.quotaWarnings = quotaWarnings
        self.quotaWarningMarkersVisible = quotaWarningMarkersVisible
        self.usageBarsShowUsed = usageBarsShowUsed
        self.resetTimesShowAbsolute = resetTimesShowAbsolute
        self.showOptionalCreditsAndExtraUsage = showOptionalCreditsAndExtraUsage
        self.hidePersonalInfo = hidePersonalInfo
        self.weeklyProgressWorkDays = Self.normalizedWeeklyProgressWorkDays(weeklyProgressWorkDays)
        self.providerChangelogLinksEnabled = providerChangelogLinksEnabled
        self.providerStorageFootprintsEnabled = providerStorageFootprintsEnabled
        self.providerRefreshIntervalSeconds = Self.normalizedProviderRefreshIntervalSeconds(
            providerRefreshIntervalSeconds)
        self.providerOrder = providerOrder
        self.providersSortedAlphabetically = providersSortedAlphabetically
        self.statusBarOverviewProviderIDs = statusBarOverviewProviderIDs
        self.statusBarOverviewSelectionBasisIDs = statusBarOverviewSelectionBasisIDs
        self.providers = providers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quotaWarnings = c.value(.quotaWarnings, .init())
        quotaWarningMarkersVisible = c.value(.quotaWarningMarkersVisible, true)
        usageBarsShowUsed = c.value(.usageBarsShowUsed, false)
        resetTimesShowAbsolute = c.value(.resetTimesShowAbsolute, false)
        showOptionalCreditsAndExtraUsage = c.value(.showOptionalCreditsAndExtraUsage, true)
        hidePersonalInfo = c.value(.hidePersonalInfo, false)
        weeklyProgressWorkDays = Self.normalizedWeeklyProgressWorkDays(
            try? c.decodeIfPresent(Int.self, forKey: .weeklyProgressWorkDays))
        providerChangelogLinksEnabled = c.value(.providerChangelogLinksEnabled, false)
        providerStorageFootprintsEnabled = c.value(.providerStorageFootprintsEnabled, false)
        providerRefreshIntervalSeconds = Self.normalizedProviderRefreshIntervalSeconds(
            c.value(.providerRefreshIntervalSeconds, Self.defaultProviderRefreshIntervalSeconds))
        providerOrder = c.value(.providerOrder, [])
        providersSortedAlphabetically = c.value(.providersSortedAlphabetically, false)
        statusBarOverviewProviderIDs = c.value(.statusBarOverviewProviderIDs, [])
        statusBarOverviewSelectionBasisIDs = c.value(.statusBarOverviewSelectionBasisIDs, [])
        providers = c.value(.providers, [:])
    }

    func validated() -> UsageConfig {
        var copy = self
        copy.quotaWarnings = quotaWarnings.validated()
        copy.providerRefreshIntervalSeconds = Self.normalizedProviderRefreshIntervalSeconds(
            providerRefreshIntervalSeconds)
        copy.providerOrder = Self.normalizedProviderOrder(providerOrder)
        copy.statusBarOverviewProviderIDs = Self.normalizedProviderOrder(statusBarOverviewProviderIDs)
        copy.statusBarOverviewSelectionBasisIDs = Self.normalizedProviderOrder(statusBarOverviewSelectionBasisIDs)
        copy.weeklyProgressWorkDays = Self.normalizedWeeklyProgressWorkDays(weeklyProgressWorkDays)
        copy.providers = providers.compactMapValues { $0.validated() }
        return copy
    }

    public func effectiveProviderOrder(knownProviderIDs: [String]) -> [String] {
        Self.effectiveProviderOrder(raw: providerOrder, knownProviderIDs: knownProviderIDs)
    }

    public static func effectiveProviderOrder(
        raw: [String],
        knownProviderIDs: [String]
    ) -> [String] {
        let known = normalizedProviderOrder(knownProviderIDs)
        guard !known.isEmpty else { return [] }
        let knownSet = Set(known)
        var seen: Set<String> = []
        var ordered: [String] = []
        for id in normalizedProviderOrder(raw) where knownSet.contains(id) && !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        if ordered.isEmpty {
            ordered = known
            seen = Set(known)
        }
        for id in known where !seen.contains(id) {
            ordered.append(id)
            seen.insert(id)
        }
        return ordered
    }

    public static func normalizedProviderOrder(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in raw {
            let id = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }

    public static func normalizedProviderRefreshIntervalSeconds(_ raw: Int) -> Int {
        if allowedProviderRefreshIntervalSeconds.contains(raw) { return raw }
        return defaultProviderRefreshIntervalSeconds
    }

    public static func normalizedWeeklyProgressWorkDays(_ raw: Int?) -> Int? {
        guard let raw else { return nil }
        return allowedWeeklyProgressWorkDays.contains(raw) ? raw : nil
    }

    public func effectiveStatusBarOverviewProviderIDs(
        activeProviderIDs: [String],
        maxVisibleProviders: Int = Self.maxStatusBarOverviewProviders
    ) -> [String] {
        Self.effectiveStatusBarOverviewProviderIDs(
            selected: statusBarOverviewProviderIDs,
            selectionBasis: statusBarOverviewSelectionBasisIDs,
            activeProviderIDs: activeProviderIDs,
            maxVisibleProviders: maxVisibleProviders)
    }

    public static func effectiveStatusBarOverviewProviderIDs(
        selected: [String],
        selectionBasis: [String],
        activeProviderIDs: [String],
        maxVisibleProviders: Int = Self.maxStatusBarOverviewProviders
    ) -> [String] {
        guard maxVisibleProviders > 0 else { return [] }
        let active = normalizedProviderOrder(activeProviderIDs)
        guard !active.isEmpty else { return [] }
        let hasPreference = !selected.isEmpty || !selectionBasis.isEmpty
        guard hasPreference else { return Array(active.prefix(maxVisibleProviders)) }
        if active.count <= maxVisibleProviders,
           !statusBarOverviewSelectionApplies(selectionBasis: selectionBasis, activeProviderIDs: active)
        {
            return active
        }
        let selectedSet = Set(normalizedProviderOrder(selected))
        return Array(active.filter { selectedSet.contains($0) }.prefix(maxVisibleProviders))
    }

    public static func statusBarOverviewSelectionApplies(
        selectionBasis: [String],
        activeProviderIDs: [String]
    ) -> Bool {
        Set(normalizedProviderOrder(selectionBasis)) == Set(normalizedProviderOrder(activeProviderIDs))
    }
}

public struct UsageProviderConfig: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case enabled
        case apiKey
        case sourceMode
        case cookieSource
        case cookieHeader
        case projectID
        case baseURL
        case organizationID
        case flags
        case extra
        case tokenAccounts
        case quotaWarnings
    }

    /// 是否在用量区显示并抓取。nil = 未设置（回落到「检测到凭证才显示」）。
    public var enabled: Bool?
    /// 应用内填写的 API key / token；落盘到 config.yaml。
    public var apiKey: String?
    /// 用量来源偏好：auto / cli / oauth / api / browser / manual 等。具体 provider 自行解释。
    public var sourceMode: String?
    /// Cookie 来源偏好：auto / browser / manual / off 等。
    public var cookieSource: String?
    /// 手工粘贴的 Cookie 或 Authorization header。
    public var cookieHeader: String?
    /// 平台项目 ID（OpenAI project、Azure deployment/project 等）。
    public var projectID: String?
    /// 自定义 API base URL。
    public var baseURL: String?
    /// 组织 / workspace / account id。
    public var organizationID: String?
    /// provider 专属开关，如 historicalTracking、avoidKeychainPrompts。
    public var flags: [String: Bool]
    /// provider 专属字符串槽位，避免为了一个字段反复扩模型。
    public var extra: [String: String]
    /// 多账号凭证。CLI 的 --account / --account-index / --all-accounts 与后续 UI 共用这里。
    public var tokenAccounts: UsageProviderTokenAccountData?
    /// 单 provider 配额告警覆盖：可单独开关 session/weekly 与阈值。
    public var quotaWarnings: QuotaWarningConfig?

    public init(
        enabled: Bool? = nil,
        apiKey: String? = nil,
        sourceMode: String? = nil,
        cookieSource: String? = nil,
        cookieHeader: String? = nil,
        projectID: String? = nil,
        baseURL: String? = nil,
        organizationID: String? = nil,
        flags: [String: Bool] = [:],
        extra: [String: String] = [:],
        tokenAccounts: UsageProviderTokenAccountData? = nil,
        quotaWarnings: QuotaWarningConfig? = nil)
    {
        self.enabled = enabled
        self.apiKey = apiKey
        self.sourceMode = sourceMode
        self.cookieSource = cookieSource
        self.cookieHeader = cookieHeader
        self.projectID = projectID
        self.baseURL = baseURL
        self.organizationID = organizationID
        self.flags = flags
        self.extra = extra
        self.tokenAccounts = tokenAccounts
        self.quotaWarnings = quotaWarnings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        let key = try? c.decodeIfPresent(String.self, forKey: .apiKey)
        apiKey = (key?.isEmpty == true) ? nil : key
        sourceMode = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .sourceMode))
        cookieSource = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .cookieSource))
        cookieHeader = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .cookieHeader))
        projectID = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .projectID))
        baseURL = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .baseURL))
        organizationID = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .organizationID))
        flags = (try? c.decodeIfPresent([String: Bool].self, forKey: .flags)) ?? [:]
        extra = (try? c.decodeIfPresent([String: String].self, forKey: .extra)) ?? [:]
        extra = extra.compactMapValues(Self.nonEmpty)
        tokenAccounts = try? c.decodeIfPresent(UsageProviderTokenAccountData.self, forKey: .tokenAccounts)
        quotaWarnings = try? c.decodeIfPresent(QuotaWarningConfig.self, forKey: .quotaWarnings)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(apiKey, forKey: .apiKey)
        try c.encodeIfPresent(sourceMode, forKey: .sourceMode)
        try c.encodeIfPresent(cookieSource, forKey: .cookieSource)
        try c.encodeIfPresent(cookieHeader, forKey: .cookieHeader)
        try c.encodeIfPresent(projectID, forKey: .projectID)
        try c.encodeIfPresent(baseURL, forKey: .baseURL)
        try c.encodeIfPresent(organizationID, forKey: .organizationID)
        if !flags.isEmpty { try c.encode(flags, forKey: .flags) }
        if !extra.isEmpty { try c.encode(extra, forKey: .extra) }
        try c.encodeIfPresent(tokenAccounts, forKey: .tokenAccounts)
        if let quotaWarnings, !quotaWarnings.isEmpty {
            try c.encode(quotaWarnings, forKey: .quotaWarnings)
        }
    }

    func validated() -> UsageProviderConfig {
        var copy = self
        copy.apiKey = Self.nonEmpty(apiKey)
        copy.sourceMode = Self.nonEmpty(sourceMode)
        copy.cookieSource = Self.nonEmpty(cookieSource)
        copy.cookieHeader = Self.nonEmpty(cookieHeader)
        copy.projectID = Self.nonEmpty(projectID)
        copy.baseURL = Self.nonEmpty(baseURL)
        copy.organizationID = Self.nonEmpty(organizationID)
        copy.extra = extra.compactMapValues(Self.nonEmpty)
        copy.tokenAccounts = tokenAccounts?.validated()
        let cleanQuotaWarnings = quotaWarnings?.validated()
        copy.quotaWarnings = cleanQuotaWarnings?.isEmpty == true ? nil : cleanQuotaWarnings
        return copy
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public struct UsageProviderTokenAccount: Codable, Equatable, Identifiable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case token
        case addedAt
        case lastUsed
        case externalIdentifier
        case organizationID = "organizationId"
    }

    public var id: UUID
    public var label: String
    public var token: String
    public var addedAt: TimeInterval
    public var lastUsed: TimeInterval?
    public var externalIdentifier: String?
    public var organizationID: String?

    public init(
        id: UUID = UUID(),
        label: String,
        token: String,
        addedAt: TimeInterval = Date().timeIntervalSince1970,
        lastUsed: TimeInterval? = nil,
        externalIdentifier: String? = nil,
        organizationID: String? = nil)
    {
        self.id = id
        self.label = label
        self.token = token
        self.addedAt = addedAt
        self.lastUsed = lastUsed
        self.externalIdentifier = externalIdentifier
        self.organizationID = organizationID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        label = c.value(.label, "")
        token = c.value(.token, "")
        addedAt = c.value(.addedAt, Date().timeIntervalSince1970)
        lastUsed = try? c.decodeIfPresent(TimeInterval.self, forKey: .lastUsed)
        externalIdentifier = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .externalIdentifier))
        organizationID = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .organizationID))
    }

    public var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id.uuidString : trimmed
    }

    func validated() -> UsageProviderTokenAccount? {
        let label = Self.nonEmpty(label)
        let token = Self.nonEmpty(token)
        guard let label, let token else { return nil }
        return UsageProviderTokenAccount(
            id: id,
            label: label,
            token: token,
            addedAt: addedAt,
            lastUsed: lastUsed,
            externalIdentifier: Self.nonEmpty(externalIdentifier),
            organizationID: Self.nonEmpty(organizationID))
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public struct UsageProviderTokenAccountData: Codable, Equatable, Sendable {
    public var version: Int
    public var accounts: [UsageProviderTokenAccount]
    public var activeIndex: Int

    public init(version: Int = 1, accounts: [UsageProviderTokenAccount] = [], activeIndex: Int = 0) {
        self.version = version
        self.accounts = accounts
        self.activeIndex = activeIndex
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.value(.version, 1)
        accounts = c.value(.accounts, [])
        activeIndex = c.value(.activeIndex, 0)
    }

    public func clampedActiveIndex() -> Int {
        guard !accounts.isEmpty else { return 0 }
        return min(max(activeIndex, 0), accounts.count - 1)
    }

    @discardableResult
    public mutating func markAccountUsed(
        id: UUID,
        at timestamp: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            return false
        }
        accounts[index].lastUsed = timestamp
        return true
    }

    func validated() -> UsageProviderTokenAccountData? {
        let accounts = accounts.compactMap { $0.validated() }
        guard !accounts.isEmpty else { return nil }
        return UsageProviderTokenAccountData(
            version: max(1, version),
            accounts: accounts,
            activeIndex: min(max(activeIndex, 0), accounts.count - 1))
    }
}

// MARK: - appearance

public struct Appearance: Codable, Equatable, Sendable {
    public var theme: String
    public var font: FontConfig
    public var padding: Padding
    public var cursorStyle: String       // bar | block | underline
    public var colors: Colors?

    public init(theme: String = "dark", font: FontConfig = .init(),
                padding: Padding = .init(), cursorStyle: String = "bar",
                colors: Colors? = nil) {
        self.theme = theme
        self.font = font
        self.padding = padding
        self.cursorStyle = cursorStyle
        self.colors = colors
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Appearance()
        theme = c.value(.theme, d.theme)
        font = c.value(.font, d.font)
        padding = c.value(.padding, d.padding)
        cursorStyle = c.value(.cursorStyle, d.cursorStyle)
        colors = (try? c.decodeIfPresent(Colors.self, forKey: .colors)) ?? nil
    }

    static let validCursorStyles: Set<String> = ["bar", "block", "underline"]

    func validated() -> Appearance {
        var copy = self
        copy.font = font.validated()
        if !Appearance.validCursorStyles.contains(cursorStyle) { copy.cursorStyle = "bar" }
        return copy
    }
}

public struct FontConfig: Codable, Equatable, Sendable {
    public var family: String
    public var size: Int

    public init(family: String = "SF Mono", size: Int = 13) {
        self.family = family
        self.size = size
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FontConfig()
        family = c.value(.family, d.family)
        size = c.value(.size, d.size)
    }

    func validated() -> FontConfig {
        var copy = self
        copy.size = min(max(size, 6), 72)     // 字号夹到 6...72
        if family.trimmingCharacters(in: .whitespaces).isEmpty { copy.family = "SF Mono" }
        return copy
    }
}

public struct Padding: Codable, Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int = 14, y: Int = 12) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Padding()
        x = c.value(.x, d.x)
        y = c.value(.y, d.y)
    }
}

public struct Colors: Codable, Equatable, Sendable {
    public var background: String?
    public var foreground: String?
    public var cursor: String?
    public var selection: String?
    public var ansi: [String]?

    public init(background: String? = nil, foreground: String? = nil,
                cursor: String? = nil, selection: String? = nil, ansi: [String]? = nil) {
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
    }
}

// MARK: - terminal

public struct TerminalConfig: Codable, Equatable, Sendable {
    public var shell: String?           // nil = 用户登录 shell
    public var scrollback: Int
    public var copyOnSelect: Bool
    public var confirmCloseRunning: Bool
    public var autoResumeAgentSessions: Bool
    public var aiAgents: [AIAgentConfig]

    public init(shell: String? = nil, scrollback: Int = 60000,
                copyOnSelect: Bool = false, confirmCloseRunning: Bool = true,
                autoResumeAgentSessions: Bool = true,
                aiAgents: [AIAgentConfig] = []) {
        self.shell = shell
        self.scrollback = scrollback
        self.copyOnSelect = copyOnSelect
        self.confirmCloseRunning = confirmCloseRunning
        self.autoResumeAgentSessions = autoResumeAgentSessions
        self.aiAgents = aiAgents
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TerminalConfig()
        shell = (try? c.decodeIfPresent(String.self, forKey: .shell)) ?? nil
        scrollback = c.value(.scrollback, d.scrollback)
        copyOnSelect = c.value(.copyOnSelect, d.copyOnSelect)
        confirmCloseRunning = c.value(.confirmCloseRunning, d.confirmCloseRunning)
        autoResumeAgentSessions = c.value(.autoResumeAgentSessions, d.autoResumeAgentSessions)
        aiAgents = c.value(.aiAgents, d.aiAgents)
    }

    func validated() -> TerminalConfig {
        var copy = self
        // 下限 6 万行：保证 agent 长输出可回看（旧配置里的小值也会被抬上来）
        copy.scrollback = min(max(scrollback, 60_000), 1_000_000)
        copy.aiAgents = AIAgentConfig.validatedList(aiAgents)
        return copy
    }
}

public struct AIAgentConfig: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var command: String
    public var enabled: Bool

    public init(id: String, title: String, command: String, enabled: Bool = true) {
        self.id = id
        self.title = title
        self.command = command
        self.enabled = enabled
    }

    func validated() -> AIAgentConfig? {
        let cleanID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty, !cleanCommand.isEmpty else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIAgentConfig(
            id: cleanID,
            title: cleanTitle.isEmpty ? cleanID : cleanTitle,
            command: cleanCommand,
            enabled: enabled)
    }

    public static func validatedList(_ agents: [AIAgentConfig]) -> [AIAgentConfig] {
        var seen: Set<String> = []
        var out: [AIAgentConfig] = []
        for agent in agents {
            guard let clean = agent.validated(), seen.insert(clean.id).inserted else { continue }
            out.append(clean)
        }
        return out
    }
}

// MARK: - behavior

public struct Behavior: Codable, Equatable, Sendable {
    public var restoreLayoutOnLaunch: Bool
    public var newTabCwd: String        // workspace | activePane | home

    public init(restoreLayoutOnLaunch: Bool = true, newTabCwd: String = "workspace") {
        self.restoreLayoutOnLaunch = restoreLayoutOnLaunch
        self.newTabCwd = newTabCwd
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Behavior()
        restoreLayoutOnLaunch = c.value(.restoreLayoutOnLaunch, d.restoreLayoutOnLaunch)
        newTabCwd = c.value(.newTabCwd, d.newTabCwd)
    }

    static let validNewTabCwd: Set<String> = ["workspace", "activePane", "home"]

    func validated() -> Behavior {
        var copy = self
        if !Behavior.validNewTabCwd.contains(newTabCwd) { copy.newTabCwd = "workspace" }
        return copy
    }
}

// MARK: - workspace defaults

public struct WorkspaceDefaults: Codable, Equatable, Sendable {
    public var shell: String?
    public var startupCommand: String?

    public init(shell: String? = nil, startupCommand: String? = nil) {
        self.shell = shell
        self.startupCommand = startupCommand
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shell = (try? c.decodeIfPresent(String.self, forKey: .shell)) ?? nil
        startupCommand = (try? c.decodeIfPresent(String.self, forKey: .startupCommand)) ?? nil
    }
}

// MARK: - 容错解码助手

extension KeyedDecodingContainer {
    /// 取 key 的值，缺失/类型错都回退到 `def`（不抛）。
    func value<T: Decodable>(_ key: Key, _ def: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? def
    }
}
