import Foundation

enum UsageProviderRuntimeConfig {
    static func manualCookieHeader(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        CookieHeaderNormalizer.normalize(env["CONDUCTOR_USAGE_\(envSafe(providerID))_COOKIE"])
    }

    static func shouldReadBrowserCookies(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if let cookieSource = cookieSource(providerID: providerID, env: env) {
            switch cookieSource {
            case "manual", "off":
                return false
            default:
                return true
            }
        }
        switch sourceMode(providerID: providerID, env: env) {
        case "api", "cli", "file", "keychain", "manual", "oauth", "off", "token":
            return false
        case "browser":
            return true
        default:
            return true
        }
    }

    static func shouldUseLocalCredentials(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        switch sourceMode(providerID: providerID, env: env) {
        case "manual", "off":
            return false
        default:
            return true
        }
    }

    static func cookieSource(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        normalized(env["CONDUCTOR_USAGE_\(envSafe(providerID))_COOKIE_SOURCE"])?.lowercased()
    }

    static func sourceMode(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        normalized(env["CONDUCTOR_USAGE_\(envSafe(providerID))_SOURCE"])?.lowercased()
    }

    static func webTimeout(
        providerID: String,
        defaultValue: TimeInterval,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        guard let raw = normalized(env["CONDUCTOR_USAGE_\(envSafe(providerID))_WEB_TIMEOUT"]),
              let value = TimeInterval(raw),
              value.isFinite,
              value > 0
        else {
            return defaultValue
        }
        return value
    }

    static func webDebugDumpHTML(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        truthy(env["CONDUCTOR_USAGE_\(envSafe(providerID))_WEB_DEBUG_DUMP_HTML"])
    }

    static func webBatterySaver(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        truthy(env["CONDUCTOR_USAGE_\(envSafe(providerID))_WEB_BATTERY_SAVER"])
    }

    static func shouldUseOpenAIWebBatterySaver(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        webBatterySaver(providerID: providerID, env: env)
            && !UsageProviderRuntimeContext.isForcedWebRefresh(providerID: providerID, env: env)
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func truthy(_ raw: String?) -> Bool {
        switch normalized(raw)?.lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }

    private static func envSafe(_ raw: String) -> String {
        raw.uppercased().map { ch in
            ch.isLetter || ch.isNumber ? ch : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}
