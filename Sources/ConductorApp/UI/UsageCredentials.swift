import ConductorCore
import Foundation

/// 账号用量凭证桥接：把应用内填写的 provider 配置注入进程环境变量，并解析 provider 的「是否显示」。
///
/// 背景：各 provider 的 fetcher 默认读 `ProcessInfo.processInfo.environment`，而 Finder 启动的 GUI
/// **不继承** 用户 shell 里 export 的变量（如 `Z_AI_API_KEY`）。CodexBar 的做法是让用户在应用内填 key、
/// 再注入抓取进程的 env。这里照搬并扩展：把 config.yaml 里的 API key、Cookie、Base URL、项目/组织
/// 字段翻译成各 fetcher 已经支持的环境变量，避免 UI 设置只是“看起来能填”。
enum UsageCredentials {
    private static var activeManagedEnvNames: Set<String> = []
    private static var originalEnvValues: [String: String] = [:]
    private static var originallyMissingEnvNames: Set<String> = []
    private static let browserCredentialProviderIDs: Set<String> = [
        "abacus",
        "alibabatokenplan",
        "augment",
        "commandcode",
        "codex",
        "copilot",
        "cursor",
        "devin",
        "factory",
        "grok",
        "manus",
        "mimo",
        "mistral",
        "ollama",
        "opencode",
        "opencodego",
        "perplexity",
        "t3chat",
        "windsurf",
    ]

    /// provider id → 主环境变量名（仅 API-key / token 型 provider）。
    /// cookie / OAuth / 本地登录文件型不在此（它们另有检测路径，不靠 env key）。
    static let envVar = UsageProviderConfigCapabilities.apiKeyEnvironmentNames

    /// 该 provider 是否支持「应用内填 key」（即有可注入的环境变量）。
    static func acceptsAPIKey(_ id: String) -> Bool { self.envVar[id] != nil }

    /// 把应用内配置写进进程环境，使 fetcher 能取到。幂等，可重复调用。
    static func apply(_ config: AppConfig) {
        var nextManagedEnvNames: Set<String> = []
        for (id, providerConfig) in config.usage.providers {
            guard UsageProviderCatalog.entry(for: id)?.isEnabled(in: config) ?? false else { continue }
            applyProviderConfig(id: id, config: providerConfig, managedEnvNames: &nextManagedEnvNames)
        }

        if config.usage.providers["claude"]?.flags["avoidKeychainPrompts"] == true {
            apply("1", to: ["CONDUCTOR_CLAUDE_AVOID_KEYCHAIN"], managedEnvNames: &nextManagedEnvNames)
        }
        restoreInactiveManagedEnvNames(keeping: nextManagedEnvNames)
        activeManagedEnvNames = nextManagedEnvNames
    }

    static func providerDiscoveryEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for name in activeManagedEnvNames {
            if let original = originalEnvValues[name] {
                environment[name] = original
            } else if originallyMissingEnvNames.contains(name) {
                environment.removeValue(forKey: name)
            }
        }
        return environment
    }

    /// provider 是否应在用量区显示：跟随 CodexBar 的 provider defaultEnabled metadata，
    /// 用户显式开关会覆盖默认值。
    static func isVisible(_ entry: UsageProviderEntry, config: AppConfig) -> Bool {
        entry.isEnabled(in: config)
    }

    /// Opening a usage drawer should not touch browser cookie stores, because Chromium
    /// cookie decryption can raise the system "Chrome Safe Storage" Keychain prompt.
    static func shouldDeferBrowserCredentialProbe(
        _ entry: UsageProviderEntry,
        config: AppConfig,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let id = entry.id
        guard browserCredentialProviderIDs.contains(id) else { return false }
        guard shouldReadBrowserCredentials(providerID: id, config: config, env: env) else { return false }
        return !hasManualCredential(providerID: id, config: config, env: env)
    }

    static func isConfiguredWithoutBrowserPrompt(
        _ entry: UsageProviderEntry,
        config: AppConfig,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard !shouldDeferBrowserCredentialProbe(entry, config: config, env: env) else {
            return false
        }
        return entry.isConfigured()
    }

    private static func applyProviderConfig(
        id: String,
        config: UsageProviderConfig,
        managedEnvNames: inout Set<String>
    ) {
        var patch = UsageProviderConfigCapabilities.environmentPatch(providerID: id, config: config)
        if let account = selectedTokenAccount(from: config.tokenAccounts) {
            patch.merge(UsageProviderConfigCapabilities.environmentPatch(providerID: id, account: account))
        }
        apply(patch, managedEnvNames: &managedEnvNames)
    }

    private static func selectedTokenAccount(from data: UsageProviderTokenAccountData?) -> UsageProviderTokenAccount? {
        guard let data, !data.accounts.isEmpty else { return nil }
        return data.accounts[data.clampedActiveIndex()]
    }

    private static func apply(_ patch: UsageProviderEnvironmentPatch, managedEnvNames: inout Set<String>) {
        for name in patch.unset where !name.isEmpty {
            recordOriginalEnvValue(for: name)
            unsetenv(name)
            managedEnvNames.insert(name)
        }
        for (name, value) in patch.set where !name.isEmpty {
            apply(value, to: [name], managedEnvNames: &managedEnvNames)
        }
    }

    private static func apply(_ value: String, to names: [String], managedEnvNames: inout Set<String>) {
        for name in names where !name.isEmpty {
            recordOriginalEnvValue(for: name)
            setenv(name, value, 1)
            managedEnvNames.insert(name)
        }
    }

    private static func restoreInactiveManagedEnvNames(keeping nextManagedEnvNames: Set<String>) {
        let inactive = activeManagedEnvNames.subtracting(nextManagedEnvNames)
        for name in inactive {
            if let original = originalEnvValues[name] {
                setenv(name, original, 1)
            } else {
                unsetenv(name)
            }
        }
    }

    private static func recordOriginalEnvValue(for name: String) {
        guard originalEnvValues[name] == nil, !originallyMissingEnvNames.contains(name) else {
            return
        }
        if let existing = getenv(name) {
            originalEnvValues[name] = String(cString: existing)
        } else {
            originallyMissingEnvNames.insert(name)
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func hasManualCredential(
        providerID id: String,
        config: AppConfig,
        env: [String: String]
    ) -> Bool {
        let providerConfig = config.usage.providers[id]
        if normalized(providerConfig?.apiKey) != nil { return true }
        if normalized(providerConfig?.cookieHeader) != nil { return true }

        var names: [String] = []
        if let primary = envVar[id] { names.append(primary) }
        names += UsageProviderConfigCapabilities.apiKeyAliases[id] ?? []
        names += UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames[id]
            ?? UsageProviderConfigCapabilities.conductorCookieEnvironmentNames(id)

        return names.contains { envValue($0, env: env) != nil }
    }

    private static func shouldReadBrowserCredentials(
        providerID id: String,
        config: AppConfig,
        env: [String: String]
    ) -> Bool {
        let providerConfig = config.usage.providers[id]
        if let cookieSource = normalized(providerConfig?.cookieSource)
            ?? envValue(UsageProviderConfigCapabilities.conductorCookieSourceEnvironmentNames(id)[0], env: env)
        {
            switch cookieSource.lowercased() {
            case "manual", "off":
                return false
            default:
                return true
            }
        }

        let sourceMode = normalized(providerConfig?.sourceMode)
            ?? envValue(UsageProviderConfigCapabilities.conductorSourceEnvironmentNames(id)[0], env: env)
        switch sourceMode?.lowercased() {
        case "api", "cli", "file", "keychain", "manual", "oauth", "off", "token":
            return false
        case "browser":
            return true
        default:
            return true
        }
    }

    private static func envValue(_ name: String, env: [String: String]) -> String? {
        if let value = normalized(env[name]) { return value }
        guard let raw = getenv(name) else { return nil }
        return normalized(String(cString: raw))
    }

}
