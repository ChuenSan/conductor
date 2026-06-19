import Foundation

public enum UsageProviderInteraction: Sendable {
    case foreground
    case background
}

public enum UsageProviderRuntimeContext {
    @TaskLocal public static var forcedWebRefreshProviderIDs: Set<String> = []
    @TaskLocal public static var interaction: UsageProviderInteraction = .foreground

    public static func withForcedWebRefresh<T>(
        for providerID: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        var next = forcedWebRefreshProviderIDs
        next.insert(providerID)
        return try await $forcedWebRefreshProviderIDs.withValue(next) {
            try await operation()
        }
    }

    public static func withInteraction<T>(
        _ interaction: UsageProviderInteraction,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $interaction.withValue(interaction) {
            try await operation()
        }
    }

    public static var currentInteraction: UsageProviderInteraction {
        interaction
    }

    static func isForcedWebRefresh(
        providerID: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        forcedWebRefreshProviderIDs.contains(providerID)
            || UsageProviderRuntimeConfig.truthy(env["CONDUCTOR_USAGE_\(envSafe(providerID))_WEB_FORCE_REFRESH"])
    }

    private static func envSafe(_ raw: String) -> String {
        raw.uppercased().map { ch in
            ch.isLetter || ch.isNumber ? ch : "_"
        }.reduce(into: "") { $0.append($1) }
    }
}
