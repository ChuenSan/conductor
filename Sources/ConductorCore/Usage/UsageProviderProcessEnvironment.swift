import Foundation

public enum UsageProviderProcessEnvironment {
    public static func scrubbedChildEnvironment(
        from environment: [String: String] = ProcessInfo.processInfo.environment,
        preservingProviderID providerID: String? = nil
    ) -> [String: String] {
        var result = environment
        var namesToRemove = sensitiveEnvironmentNames
        if let providerID {
            namesToRemove.subtract(allowedEnvironmentNames(for: providerID))
        }
        for name in namesToRemove {
            result.removeValue(forKey: name)
        }
        return result
    }

    public static var sensitiveEnvironmentNames: Set<String> {
        var names: Set<String> = []
        names.formUnion(UsageProviderConfigCapabilities.apiKeyEnvironmentNames.values)
        names.formUnion(UsageProviderConfigCapabilities.apiKeyAliases.values.flatMap { $0 })
        names.formUnion(UsageProviderConfigCapabilities.baseURLEnvironmentNames.values)
        names.formUnion(UsageProviderConfigCapabilities.projectEnvironmentNames.values.flatMap { $0 })
        names.formUnion(UsageProviderConfigCapabilities.organizationEnvironmentNames.values.flatMap { $0 })
        names.formUnion(UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames.values.flatMap { $0 })
        names.formUnion(UsageProviderConfigCapabilities.extraEnvironmentNames.values.flatMap { $0.values.flatMap { $0 } })

        for providerID in providerIDs {
            let hints = UsageProviderConfigCapabilities.environmentHints(providerID: providerID)
            names.formUnion(hints.sourceMode)
            names.formUnion(hints.cookieSource)
            names.formUnion(UsageProviderConfigCapabilities.conductorCookieEnvironmentNames(providerID))
            names.formUnion(UsageProviderConfigCapabilities.extraEnvironmentNames(
                providerID: providerID,
                key: "token"))
        }

        names.formUnion([
            "CLAUDE_CONFIG_DIR",
            "CLAUDE_OAUTH_ACCESS_TOKEN",
            "CLAUDE_SESSION_KEY",
            "CODEX_HOME",
            "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN",
            "CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN",
            "CONDUCTOR_USAGE_CLAUDE_SESSION_KEY",
        ])
        return names
    }

    private static func allowedEnvironmentNames(for providerID: String) -> Set<String> {
        let normalizedID = providerID.lowercased()
        let hints = UsageProviderConfigCapabilities.environmentHints(providerID: normalizedID)
        var names = Set(hints.apiKey)
        names.formUnion(hints.cookieHeader)
        names.formUnion(hints.baseURL)
        names.formUnion(hints.project)
        names.formUnion(hints.organization)
        names.formUnion(hints.sourceMode)
        names.formUnion(hints.cookieSource)
        names.formUnion(hints.extra.values.flatMap { $0 })

        if let support = UsageProviderConfigCapabilities.tokenAccountSupportByProviderID[normalizedID] {
            switch support.injection {
            case let .environment(keys, scrub):
                names.formUnion(keys)
                names.subtract(scrub)
            case .cookieHeader:
                names.formUnion(UsageProviderConfigCapabilities.conductorCookieEnvironmentNames(normalizedID))
            }
        }

        switch normalizedID {
        case "claude":
            names.formUnion([
                "CLAUDE_CONFIG_DIR",
                "CLAUDE_OAUTH_ACCESS_TOKEN",
                "CLAUDE_SESSION_KEY",
                "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN",
                "CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN",
                "CONDUCTOR_USAGE_CLAUDE_SESSION_KEY",
            ])
        case "codex":
            names.insert("CODEX_HOME")
        default:
            break
        }

        return names
    }

    private static var providerIDs: Set<String> {
        Set(UsageProviderCatalog.providerSourceModes.keys)
            .union(UsageProviderConfigCapabilities.apiKeyEnvironmentNames.keys)
            .union(UsageProviderConfigCapabilities.baseURLEnvironmentNames.keys)
            .union(UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames.keys)
            .union(UsageProviderConfigCapabilities.tokenAccountSupportByProviderID.keys)
    }
}
