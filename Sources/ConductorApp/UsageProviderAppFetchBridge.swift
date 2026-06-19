import ConductorCore
import Foundation

enum UsageProviderAppFetchBridge {
    static func fetch(
        _ provider: UsageProviderEntry,
        config: AppConfig,
        operation: () async throws -> UsageSnapshot
    ) async throws -> UsageSnapshot {
        let accountID = selectedTokenAccountID(providerID: provider.id, config: config)
        let sidecar = tokenAccountUpdateSidecar(providerID: provider.id, config: config)
        do {
            let snapshot = try await withTokenAccountUpdateSidecar(sidecar) {
                try await operation()
            }
            await persistTokenAccountUpdateIfNeeded(
                sidecar,
                providerID: provider.id,
                accountID: accountID,
                markUsed: true)
            sidecar?.cleanup()
            return snapshot
        } catch {
            await persistTokenAccountUpdateIfNeeded(
                sidecar,
                providerID: provider.id,
                accountID: accountID,
                markUsed: false)
            sidecar?.cleanup()
            throw error
        }
    }

    private static func tokenAccountUpdateSidecar(
        providerID: String,
        config: AppConfig
    ) -> TokenAccountUpdateSidecar? {
        guard providerID == "antigravity",
              let tokenAccounts = config.usage.providers[providerID]?.tokenAccounts,
              !tokenAccounts.accounts.isEmpty
        else {
            return nil
        }

        let account = tokenAccounts.accounts[tokenAccounts.clampedActiveIndex()]
        let filename = "conductor-\(providerID)-token-update-\(UUID().uuidString).json"
        return TokenAccountUpdateSidecar(
            providerID: providerID,
            accountID: account.id,
            url: FileManager.default.temporaryDirectory.appendingPathComponent(filename))
    }

    private static func selectedTokenAccountID(
        providerID: String,
        config: AppConfig
    ) -> UUID? {
        guard let tokenAccounts = config.usage.providers[providerID]?.tokenAccounts,
              !tokenAccounts.accounts.isEmpty
        else {
            return nil
        }
        return tokenAccounts.accounts[tokenAccounts.clampedActiveIndex()].id
    }

    private static func withTokenAccountUpdateSidecar<T>(
        _ sidecar: TokenAccountUpdateSidecar?,
        operation: () async throws -> T
    ) async throws -> T {
        guard let sidecar else { return try await operation() }
        let patch = UsageProviderEnvironmentPatch(
            set: [AntigravityUsageFetcher.tokenAccountUpdatePathEnvironmentKey: sidecar.url.path])
        return try await withTemporaryEnvironment(patch, operation: operation)
    }

    private static func withTemporaryEnvironment<T>(
        _ patch: UsageProviderEnvironmentPatch,
        operation: () async throws -> T
    ) async throws -> T {
        let restore = applyTemporaryEnvironment(patch)
        defer { restoreTemporaryEnvironment(restore) }
        return try await operation()
    }

    private static func applyTemporaryEnvironment(_ patch: UsageProviderEnvironmentPatch) -> TemporaryEnvironmentRestore {
        var restore = TemporaryEnvironmentRestore()
        for name in patch.unset where !name.isEmpty {
            recordEnvironmentValue(name, into: &restore)
            unsetenv(name)
        }
        for (name, value) in patch.set where !name.isEmpty {
            recordEnvironmentValue(name, into: &restore)
            setenv(name, value, 1)
        }
        return restore
    }

    private static func recordEnvironmentValue(
        _ name: String,
        into restore: inout TemporaryEnvironmentRestore
    ) {
        guard !restore.recordedNames.contains(name) else { return }
        if let value = getenv(name) {
            restore.values[name] = String(cString: value)
        } else {
            restore.missing.insert(name)
        }
    }

    private static func restoreTemporaryEnvironment(_ restore: TemporaryEnvironmentRestore) {
        for (name, value) in restore.values {
            setenv(name, value, 1)
        }
        for name in restore.missing {
            unsetenv(name)
        }
    }

    @MainActor
    private static func persistTokenAccountUpdateIfNeeded(
        _ sidecar: TokenAccountUpdateSidecar?,
        providerID: String,
        accountID: UUID?,
        markUsed: Bool
    ) {
        let updatedToken: String?
        if let sidecar,
           FileManager.default.fileExists(atPath: sidecar.url.path),
           let token = try? String(contentsOf: sidecar.url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            updatedToken = token
        } else {
            updatedToken = nil
        }

        guard markUsed || updatedToken != nil,
              let accountID
        else { return }

        var config = ConfigStore.shared.config
        guard var providerConfig = config.usage.providers[providerID],
              var tokenAccounts = providerConfig.tokenAccounts,
              let index = tokenAccounts.accounts.firstIndex(where: { $0.id == accountID })
        else {
            return
        }

        var didChange = false
        if let updatedToken, tokenAccounts.accounts[index].token != updatedToken {
            tokenAccounts.accounts[index].token = updatedToken
            didChange = true
        }
        if markUsed {
            tokenAccounts.markAccountUsed(id: accountID)
            didChange = true
        }
        guard didChange else { return }
        providerConfig.tokenAccounts = tokenAccounts
        config.usage.providers[providerID] = providerConfig
        ConfigStore.shared.set(config)
        ConfigStore.shared.persist()
    }

    private struct TokenAccountUpdateSidecar {
        let providerID: String
        let accountID: UUID
        let url: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private struct TemporaryEnvironmentRestore {
        var values: [String: String] = [:]
        var missing: Set<String> = []

        var recordedNames: Set<String> {
            Set(values.keys).union(missing)
        }
    }
}
