import Foundation

public enum UsageProviderRepairActionKind: String, Codable, Sendable {
    case configureCredential
    case signIn
    case allowKeychain
    case solveCloudflare
    case checkNetwork
    case checkProviderStatus
    case adjustSource
    case inspectResponse
    case waitOrRetry
    case retry
    case copyDiagnostics
}

public struct UsageProviderRepairAction: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: UsageProviderRepairActionKind
    public let title: String
    public let detail: String
    public let command: String?
    public let url: String?

    public init(
        id: String,
        kind: UsageProviderRepairActionKind,
        title: String,
        detail: String,
        command: String? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.command = command
        self.url = url
    }
}

public enum UsageProviderRepairActions {
    public static func actions(
        providerID: String,
        providerName: String,
        configured: Bool,
        error: Error,
        source: String = "auto",
        hasStatusPage: Bool = false,
        statusURL: String? = nil
    ) -> [UsageProviderRepairAction] {
        let diagnostic = UsageProviderDiagnosticError(error: error, authConfigured: configured)
        return Self.actions(
            providerID: providerID,
            providerName: providerName,
            configured: configured,
            errorMessage: diagnostic.message,
            category: diagnostic.category,
            source: source,
            hasStatusPage: hasStatusPage,
            statusURL: statusURL)
    }

    public static func actions(
        providerID: String,
        providerName: String,
        configured: Bool,
        errorMessage: String?,
        category: String? = nil,
        source: String = "auto",
        hasStatusPage: Bool = false,
        statusURL: String? = nil
    ) -> [UsageProviderRepairAction] {
        let message = (errorMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let messageLower = message.lowercased()
        let lower = "\(providerID) \(providerName) \(category ?? "") \(source) \(message)".lowercased()
        var actions: [UsageProviderRepairAction] = []

        func add(
            _ kind: UsageProviderRepairActionKind,
            id: String? = nil,
            title: String,
            detail: String,
            command: String? = nil,
            url: String? = nil
        ) {
            let actionID = id ?? kind.rawValue
            guard !actions.contains(where: { $0.id == actionID }) else { return }
            actions.append(UsageProviderRepairAction(
                id: actionID,
                kind: kind,
                title: title,
                detail: detail,
                command: command,
                url: url))
        }

        if !configured {
            add(
                .configureCredential,
                title: L("补齐凭证"),
                detail: credentialDetail(providerID: providerID, providerName: providerName, source: source),
                command: credentialConfigCommand(providerID: providerID, source: source),
                url: dashboardURL(providerID: providerID))
        }

        let specificConfigurationActions = configurationRepairActions(
            providerID: providerID,
            providerName: providerName,
            source: source,
            lower: lower)
        for action in specificConfigurationActions {
            add(
                action.kind,
                id: action.id,
                title: action.title,
                detail: action.detail,
                command: action.command,
                url: action.url)
        }

        if category == "auth",
           shouldSuggestManualCookieCredential(providerID: providerID, source: source, lower: lower),
           let detail = manualCookieCredentialDetail(providerID: providerID)
        {
            add(
                .configureCredential,
                id: "configure-cookie-header",
                title: L("补充 Cookie 或会话令牌"),
                detail: detail,
                command: cookieConfigCommand(providerID: providerID),
                url: dashboardURL(providerID: providerID))
        }

        if containsAny(lower, Self.keychainKeywords) {
            add(
                .allowKeychain,
                title: L("允许钥匙串访问"),
                detail: L("在 macOS 弹窗中允许应用读取浏览器或 CLI 登录态；反复弹窗时优先选择“始终允许”。"))
        }

        if containsAny(lower, Self.cloudflareKeywords) {
            add(
                .solveCloudflare,
                title: L("通过浏览器验证"),
                detail: L("在默认浏览器打开 %@，完成 Cloudflare 或验证码后再刷新。", providerName),
                url: dashboardURL(providerID: providerID))
        }

        if category == "auth" || containsAny(lower, Self.authKeywords) {
            if prefersAPIKeyRepair(providerID: providerID, source: source) {
                add(
                    .configureCredential,
                    title: L("更新 API Key / Token"),
                    detail: apiKeyDetail(providerID: providerID, providerName: providerName),
                    command: apiKeyConfigCommand(providerID: providerID),
                    url: dashboardURL(providerID: providerID))
            } else if let detail = localCredentialRepairDetail(providerID: providerID, providerName: providerName) {
                add(
                    .signIn,
                    title: L("检查 %@ 本机登录态", providerName),
                    detail: detail)
            } else if prefersCookieRepair(source: source) {
                add(
                    .signIn,
                    title: L("重新登录 %@ 网页", providerName),
                    detail: L("浏览器 Cookie 或会话已失效；用同一个浏览器登录后再刷新。"),
                    url: dashboardURL(providerID: providerID))
            } else if let command = signInCommand(providerID: providerID) {
                add(
                    .signIn,
                    title: L("重新登录 %@ CLI", providerName),
                    detail: L("本机登录态失效或缺失；运行命令后回到管理台刷新。"),
                    command: command)
            } else if isCookieBacked(providerID: providerID, source: source) {
                add(
                    .signIn,
                    title: L("重新登录 %@ 网页", providerName),
                    detail: L("浏览器 Cookie 或会话已失效；用同一个浏览器登录后再刷新。"),
                    url: dashboardURL(providerID: providerID))
            } else {
                add(
                    .configureCredential,
                    title: L("更新 API Key / Token"),
                    detail: apiKeyDetail(providerID: providerID, providerName: providerName),
                    command: apiKeyConfigCommand(providerID: providerID),
                    url: dashboardURL(providerID: providerID))
            }
        }

        if category == "network" || containsAny(lower, Self.networkKeywords) {
            add(
                .checkNetwork,
                title: L("检查网络与证书"),
                detail: L("确认代理、DNS、SSL 证书和系统时间正常；公司网络下先验证该渠道域名可访问。"))
            if hasStatusPage {
                add(
                    .checkProviderStatus,
                    title: L("查看服务状态"),
                    detail: L("如果服务端正在故障，等待恢复后再刷新。"),
                    url: statusURL)
            }
        }

        if category == "configuration" || (shouldInferCategoryFromMessage(category) && containsAny(lower, Self.configurationKeywords)) {
            let hasSpecificConfigurationAction = !specificConfigurationActions.isEmpty
            let isSourceModeProblem = containsAny(messageLower, Self.sourceModeKeywords)
            if !hasSpecificConfigurationAction || isSourceModeProblem {
                add(
                    .adjustSource,
                    title: L("检查来源模式"),
                    detail: L("切换来源、Cookie 来源或项目/组织配置后刷新，避免读取到错误账号。"))
            }
        }

        if category == "parse" || containsAny(lower, Self.parseKeywords) {
            add(
                .inspectResponse,
                title: L("复制诊断信息"),
                detail: L("渠道返回结构可能变化；复制脱敏诊断后对照日志或提交给维护者。"))
        }

        if category == "api" || shouldTreatAsProviderAPIError(category: category, lower: messageLower) {
            add(
                .waitOrRetry,
                title: L("稍后重试"),
                detail: L("服务端返回限流或异常状态；等待几分钟，或查看状态页确认是否为平台故障。"))
            if hasStatusPage {
                add(
                    .checkProviderStatus,
                    title: L("查看服务状态"),
                    detail: L("如果服务端正在故障，等待恢复后再刷新。"),
                    url: statusURL)
            }
        }

        if actions.isEmpty {
            add(
                .copyDiagnostics,
                title: L("复制诊断信息"),
                detail: message.isEmpty
                    ? L("暂无明确错误文本；复制诊断信息后检查本机日志。")
                    : L("错误未命中已知分类；复制脱敏诊断信息后继续排查。"))
        }

        if !message.isEmpty {
            add(
                .retry,
                title: L("刷新重试"),
                detail: L("修复上面的凭证、登录态或网络问题后重新拉取用量。"))
        }

        return actions
    }

    private static let authKeywords = [
        "auth", "authorization", "unauthorized", "forbidden", "credential", "token", "cookie",
        "api key", "apikey", "missing key", "login", "log in", "sign in", "sign-in", "session", "401", "403",
        "未登录", "登录", "凭证", "授权", "无权限", "权限", "会话",
    ]

    private static let keychainKeywords = [
        "keychain", "safe storage", "security cli", "errsecinteraction", "errsecauthfailed",
        "chrome safe storage", "secretservice", "browser cookie access", "cookie helper",
        "钥匙串", "浏览器 cookie 读取被拒绝", "浏览器 cookie helper",
    ]

    private static let cloudflareKeywords = [
        "cloudflare", "captcha", "challenge", "turnstile", "interstitial", "cf-ray", "验证码",
    ]

    private static let networkKeywords = [
        "network", "timeout", "connection", "dns", "offline", "internet", "ssl", "certificate",
        "nsurlerrordomain", "-1001", "-1003", "-1004", "-1005", "-1009", "-1011", "-1200",
        "网络", "证书", "超时",
    ]

    private static let configurationKeywords = [
        "source", "not supported", "unavailable", "invalid config", "configuration", "setting",
        "project", "organization", "workspace", "wrong account", "account mismatch", "ambiguous",
        "ownership", "provider account", "known owner", "归属", "错账号", "账号不匹配",
        "歧义", "来源", "配置", "项目", "组织",
    ]

    private static let parseKeywords = [
        "parse", "decode", "json", "format", "html", "schema", "unexpected response",
        "解析", "格式",
    ]

    private static let apiKeywords = [
        "api", "http", "status", "rate limit", "too many requests", "429", "500", "502", "503",
        "限流",
    ]

    private static let baseURLKeywords = [
        "base url", "baseurl", "endpoint", "api url", "api host", "host url", "invalid url",
        "invalid endpoint", "基础 url", "端点", "地址无效", "地址",
    ]

    private static let projectKeywords = [
        "project", "deployment", "workspace", "project_id", "deployment_name",
        "项目", "部署", "工作区",
    ]

    private static let organizationKeywords = [
        "organization", "organisation", "org id", "org_id", "org/", "organizations/",
        "组织",
    ]

    private static let cookieSourceKeywords = [
        "cookie", "session token", "session_token", "session id", "session_id", "manual cookie",
        "浏览器 cookie", "手动 cookie", "会话令牌", "登录态",
    ]

    private static let sourceModeKeywords = [
        "source", "cookie source", "wrong account", "account mismatch", "ambiguous",
        "not supported", "来源", "错账号", "账号不匹配", "歧义",
    ]

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func shouldTreatAsProviderAPIError(category: String?, lower: String) -> Bool {
        guard category == nil || category == "unknown" else { return false }
        return containsAny(lower, Self.apiKeywords)
    }

    private static func shouldInferCategoryFromMessage(_ category: String?) -> Bool {
        category == nil || category == "unknown"
    }

    private static func signInCommand(providerID: String) -> String? {
        UsageProviderCatalog.all.first { $0.id == providerID }?.signInCommand
    }

    private static func dashboardURL(providerID: String) -> String? {
        UsageProviderCatalog.all.first { $0.id == providerID }?.dashboardURL
    }

    private static func configurationRepairActions(
        providerID: String,
        providerName: String,
        source: String,
        lower: String
    ) -> [UsageProviderRepairAction] {
        var actions: [UsageProviderRepairAction] = []

        func append(
            _ kind: UsageProviderRepairActionKind,
            id: String,
            title: String,
            detail: String,
            command: String? = nil,
            url: String? = nil
        ) {
            guard !actions.contains(where: { $0.id == id }) else { return }
            let effectiveURL = url ?? (kind == .configureCredential ? dashboardURL(providerID: providerID) : nil)
            actions.append(UsageProviderRepairAction(
                id: id,
                kind: kind,
                title: title,
                detail: detail,
                command: command,
                url: effectiveURL))
        }

        if let envVar = UsageProviderConfigCapabilities.baseURLEnvironmentNames[providerID],
           containsAny(lower, Self.baseURLKeywords)
        {
            append(
                .configureCredential,
                id: "configure-base-url",
                title: L("填写 %@ 地址", providerName),
                detail: L("设置 %@，或在该渠道设置里填写 Base URL / Endpoint 后刷新。", envVar),
                command: configSetCommand(providerID: providerID, key: "baseURL", value: "<url>"))
        }

        let projectEnvVars = UsageProviderConfigCapabilities.projectEnvironmentNames[providerID] ?? []
        if !projectEnvVars.isEmpty,
           containsAny(lower, Self.projectKeywords)
        {
            append(
                .configureCredential,
                id: "configure-project",
                title: L("填写项目或部署"),
                detail: L("设置 %@，或在该渠道设置里填写项目、部署或 workspace 后刷新。", joinedEnvironmentNames(projectEnvVars)),
                command: configSetCommand(providerID: providerID, key: "projectID", value: "<project>"))
        }

        let organizationEnvVars = UsageProviderConfigCapabilities.organizationEnvironmentNames[providerID] ?? []
        if !organizationEnvVars.isEmpty,
           containsAny(lower, Self.organizationKeywords)
        {
            append(
                .configureCredential,
                id: "configure-organization",
                title: L("填写组织"),
                detail: L("设置 %@，或在该渠道设置里选择正确组织后刷新。", joinedEnvironmentNames(organizationEnvVars)),
                command: configSetCommand(providerID: providerID, key: "organizationID", value: "<organization>"))
        }

        if providerID == "litellm",
           containsAny(lower, ["user_id", "team_id", "user id", "team id"])
        {
            append(
                .configureCredential,
                id: "configure-litellm-virtual-key",
                title: L("更换 LiteLLM virtual key"),
                detail: L("当前 key info 没有 user_id 或 team_id；换用绑定用户或团队预算的 LiteLLM virtual key 后刷新。"))
        }

        if providerID == "openai",
           containsAny(lower, ["403", "forbidden", "project 级", "project-level", "billing", "账单"])
        {
            append(
                .configureCredential,
                id: "configure-openai-billing-key",
                title: L("使用账单权限 OpenAI key"),
                detail: L("OpenAI credit grants 需要带账单权限的 key；优先设置 OPENAI_ADMIN_KEY，必要时再指定 OPENAI_ORG_ID 或 OPENAI_PROJECT_ID。"),
                command: apiKeyConfigCommand(providerID: providerID))
        }

        if isCookieBacked(providerID: providerID, source: source),
           containsAny(lower, Self.cookieSourceKeywords)
        {
            append(
                .configureCredential,
                id: "configure-cookie-header",
                title: L("补充 Cookie 或会话令牌"),
                detail: manualCookieCredentialDetail(providerID: providerID)
                    ?? L("如果自动浏览器读取不可用，可以设置 %@，或在账号设置里添加手动 Cookie。", joinedEnvironmentNames(cookieEnvironmentNames(providerID))),
                command: cookieConfigCommand(providerID: providerID))
        }

        if containsAny(lower, Self.sourceModeKeywords) {
            append(
                .adjustSource,
                id: "adjust-source-mode",
                title: L("切换来源模式"),
                detail: L("在该渠道设置里切换 API / CLI / browser / manual source，确认账号匹配后刷新。"),
                command: configSetCommand(providerID: providerID, key: "sourceMode", value: "<source>"))
        }

        return actions
    }

    private static func credentialDetail(providerID: String, providerName: String, source: String) -> String {
        let apiKeyNames = apiKeyEnvironmentNames(providerID)
        if !apiKeyNames.isEmpty {
            return L("填写 %@，或在 shell 环境中导出后重启/刷新。", joinedEnvironmentNames(apiKeyNames))
        }
        if let detail = manualCookieCredentialDetail(providerID: providerID) {
            return detail
        }
        if let localDetail = localCredentialSetupDetail(providerID: providerID, providerName: providerName) {
            return localDetail
        }
        if prefersCookieRepair(source: source), isCookieBacked(providerID: providerID, source: source) {
            return L("先在浏览器登录 %@，并允许应用读取 Cookie。", providerName)
        }
        if let command = signInCommand(providerID: providerID) {
            return L("先完成本机 CLI 登录，再刷新用量。命令：%@。", command)
        }
        if isCookieBacked(providerID: providerID, source: source) {
            return L("先在浏览器登录 %@，并允许应用读取 Cookie。", providerName)
        }
        return L("该渠道依赖本机登录态；确认账号可用后刷新。")
    }

    private static func apiKeyDetail(providerID: String, providerName: String) -> String {
        let apiKeyNames = apiKeyEnvironmentNames(providerID)
        if !apiKeyNames.isEmpty {
            return L("当前凭证可能过期或权限不足；更新 %@ 后刷新。", joinedEnvironmentNames(apiKeyNames))
        }
        return L("当前 %@ 凭证可能过期或权限不足；更新账号配置后刷新。", providerName)
    }

    private static func apiKeyEnvironmentNames(_ providerID: String) -> [String] {
        var names: [String] = []
        if let primary = UsageProviderConfigCapabilities.apiKeyEnvironmentNames[providerID] {
            names.append(primary)
        }
        names.append(contentsOf: UsageProviderConfigCapabilities.apiKeyAliases[providerID] ?? [])
        return names
    }

    private static func joinedEnvironmentNames(_ names: [String]) -> String {
        names.joined(separator: " / ")
    }

    private static func cookieEnvironmentNames(_ providerID: String) -> [String] {
        UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames[providerID]
            ?? UsageProviderConfigCapabilities.conductorCookieEnvironmentNames(providerID)
    }

    private static func manualCookieCredentialDetail(providerID: String) -> String? {
        guard isManualCookieCredentialProvider(providerID) else { return nil }
        return L("设置 %@，或运行 `%@` 写入手动 Cookie / session token；多账号场景可在账号设置里添加 token account。",
                 joinedEnvironmentNames(cookieEnvironmentNames(providerID)),
                 cookieConfigCommand(providerID: providerID))
    }

    private static func cookieConfigCommand(providerID: String) -> String {
        "conductorctl config set-cookie --provider \(providerID) --cookie <cookie>"
    }

    private static func apiKeyConfigCommand(providerID: String) -> String? {
        guard !apiKeyEnvironmentNames(providerID).isEmpty else { return nil }
        return "conductorctl config set-api-key --provider \(providerID) --api-key <key>"
    }

    private static func credentialConfigCommand(providerID: String, source: String) -> String? {
        if let command = apiKeyConfigCommand(providerID: providerID) {
            return command
        }
        if manualCookieCredentialDetail(providerID: providerID) != nil ||
            (prefersCookieRepair(source: source) && UsageProviderConfigCapabilities.supportsCookieHeader(providerID))
        {
            return cookieConfigCommand(providerID: providerID)
        }
        return nil
    }

    private static func configSetCommand(providerID: String, key: String, value: String) -> String {
        "conductorctl config set --provider \(providerID) --key \(key) --value \(value)"
    }

    private static func shouldSuggestManualCookieCredential(
        providerID: String,
        source: String,
        lower: String
    ) -> Bool {
        guard isManualCookieCredentialProvider(providerID) else { return false }
        if containsAny(lower, Self.cookieSourceKeywords) { return true }
        let loweredSource = source.lowercased()
        return loweredSource == "auto" ||
            loweredSource.contains("web") ||
            loweredSource.contains("browser") ||
            loweredSource.contains("cookie")
    }

    private static func isManualCookieCredentialProvider(_ providerID: String) -> Bool {
        if UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames[providerID]?.isEmpty == false {
            return true
        }
        guard let support = UsageProviderConfigCapabilities.tokenAccountSupportByProviderID[providerID],
              support.requiresManualCookieSource
        else {
            return false
        }
        if case .cookieHeader = support.injection {
            return true
        }
        return false
    }

    private static func prefersAPIKeyRepair(providerID: String, source: String) -> Bool {
        let loweredSource = source.lowercased()
        if loweredSource.contains("api") { return true }
        if loweredSource.contains("browser") || loweredSource.contains("web") || loweredSource.contains("cookie") {
            return false
        }
        return UsageProviderConfigCapabilities.apiKeyEnvironmentNames[providerID] != nil
    }

    private static func prefersCookieRepair(source: String) -> Bool {
        let loweredSource = source.lowercased()
        return loweredSource.contains("cookie") ||
            loweredSource.contains("browser") ||
            loweredSource.contains("web") ||
            loweredSource.contains("dashboard")
    }

    private static func localCredentialRepairDetail(providerID: String, providerName: String) -> String? {
        switch providerID {
        case "zed":
            return L("在 Zed 编辑器中使用 GitHub 重新登录，并允许钥匙串访问后刷新。")
        case "kiro":
            return L("确认 kiro-cli 已安装并能在 PATH 中运行，然后刷新。")
        case "jetbrains":
            return L("打开 JetBrains IDE，确认 AI Assistant 已登录且本地配额文件可读后刷新。")
        case "vertexai":
            return L("运行 `gcloud auth application-default login`，确认项目和 ADC 凭证可用后刷新。")
        case "bedrock":
            return L("确认 AWS 凭证、区域和 Cost Explorer 权限可用后刷新。")
        default:
            guard isLocalCredentialBacked(providerID) else { return nil }
            return L("确认 %@ 的本机凭证或登录态可读，然后刷新。", providerName)
        }
    }

    private static func localCredentialSetupDetail(providerID: String, providerName: String) -> String? {
        localCredentialRepairDetail(providerID: providerID, providerName: providerName)
    }

    private static func isLocalCredentialBacked(_ providerID: String) -> Bool {
        switch providerID {
        case "zed", "kiro", "jetbrains", "vertexai", "bedrock":
            return true
        default:
            return false
        }
    }

    private static func isCookieBacked(providerID: String, source: String) -> Bool {
        if UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames[providerID]?.isEmpty == false {
            return true
        }
        let loweredSource = source.lowercased()
        if loweredSource.contains("cookie") || loweredSource.contains("browser") || loweredSource.contains("web") {
            return true
        }
        switch providerID {
        case "codex", "claude", "augment", "antigravity", "cursor", "windsurf",
             "t3chat", "factory", "minimax", "mimo", "stepfun", "opencode", "opencodego":
            return true
        default:
            return false
        }
    }
}
