import Foundation

public struct CodexActiveAccountResolution: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case noAccounts
        case liveSystemDefault
        case configuredAccount
        case refreshedDiscoveredAccount
        case managedAccountConvergedToLiveSystem
        case managedAccountMissingFellBackToLiveSystem
    }

    public let persistedAccount: UsageProviderTokenAccount?
    public let resolvedAccount: UsageProviderTokenAccount?
    public let requiresPersistenceCorrection: Bool
    public let reason: Reason

    public init(
        persistedAccount: UsageProviderTokenAccount?,
        resolvedAccount: UsageProviderTokenAccount?,
        requiresPersistenceCorrection: Bool,
        reason: Reason)
    {
        self.persistedAccount = persistedAccount
        self.resolvedAccount = resolvedAccount
        self.requiresPersistenceCorrection = requiresPersistenceCorrection
        self.reason = reason
    }
}

public enum CodexActiveAccountResolver {
    public static func correctedTokenAccountData(
        configured data: UsageProviderTokenAccountData?,
        discoveredAccounts: [UsageProviderTokenAccount])
        -> UsageProviderTokenAccountData?
    {
        let resolution = resolveDefaultAccount(
            configured: data,
            discoveredAccounts: discoveredAccounts)
        guard resolution.requiresPersistenceCorrection,
              let resolvedAccount = resolution.resolvedAccount
        else {
            return nil
        }

        var accounts = mergedAccounts(
            configured: data?.accounts ?? [],
            discovered: discoveredAccounts)
        if accounts.isEmpty {
            accounts = [resolvedAccount]
        }
        let activeIndex: Int
        if let index = accounts.firstIndex(where: { representsSameAccount($0, resolvedAccount) }) {
            var resolved = resolvedAccount
            resolved.addedAt = accounts[index].addedAt   // 同上：保留原 addedAt，别用 discovery 的新时间戳
            accounts[index] = resolved
            activeIndex = index
        } else {
            accounts.append(resolvedAccount)
            activeIndex = accounts.count - 1
        }

        let corrected = UsageProviderTokenAccountData(
            version: max(1, data?.version ?? 1),
            accounts: accounts,
            activeIndex: activeIndex).validated()
        guard corrected != data else { return nil }
        return corrected
    }

    public static func resolveDefaultAccount(
        configured data: UsageProviderTokenAccountData?,
        discoveredAccounts: [UsageProviderTokenAccount])
        -> CodexActiveAccountResolution
    {
        guard let data, !data.accounts.isEmpty else {
            if let live = liveSystemAccount(in: discoveredAccounts) {
                return CodexActiveAccountResolution(
                    persistedAccount: nil,
                    resolvedAccount: live,
                    requiresPersistenceCorrection: false,
                    reason: .liveSystemDefault)
            }
            return CodexActiveAccountResolution(
                persistedAccount: nil,
                resolvedAccount: nil,
                requiresPersistenceCorrection: false,
                reason: .noAccounts)
        }

        let clampedIndex = data.clampedActiveIndex()
        let persisted = data.accounts[clampedIndex]
        let indexWasClamped = clampedIndex != data.activeIndex

        guard let discovered = discoveredAccount(matching: persisted, in: discoveredAccounts) else {
            if !isLiveSystemAccount(persisted),
               let live = liveSystemAccount(in: discoveredAccounts)
            {
                return CodexActiveAccountResolution(
                    persistedAccount: persisted,
                    resolvedAccount: live,
                    requiresPersistenceCorrection: true,
                    reason: .managedAccountMissingFellBackToLiveSystem)
            }
            return CodexActiveAccountResolution(
                persistedAccount: persisted,
                resolvedAccount: persisted,
                requiresPersistenceCorrection: indexWasClamped,
                reason: .configuredAccount)
        }

        let convergedToLive = !isLiveSystemAccount(persisted) && isLiveSystemAccount(discovered)
        return CodexActiveAccountResolution(
            persistedAccount: persisted,
            resolvedAccount: discovered,
            requiresPersistenceCorrection: indexWasClamped || discovered != persisted,
            reason: convergedToLive ? .managedAccountConvergedToLiveSystem : .refreshedDiscoveredAccount)
    }

    public static func mergedAccounts(
        configured: [UsageProviderTokenAccount],
        discovered: [UsageProviderTokenAccount])
        -> [UsageProviderTokenAccount]
    {
        guard !configured.isEmpty else { return discovered }

        var merged = configured.map { configuredAccount -> UsageProviderTokenAccount in
            guard var match = discoveredAccount(matching: configuredAccount, in: discovered) else {
                return configuredAccount
            }
            // 保留原账号的 addedAt——discovery 每次发现都盖 Date()，若覆盖会让修正值永远不同于
            // 现存 → 反复写盘 → config 热更新死循环（CPU 飙高、codex 详情点开即崩的根因）。
            match.addedAt = configuredAccount.addedAt
            return match
        }
        for discoveredAccount in discovered where !merged.contains(where: { representsSameAccount($0, discoveredAccount) }) {
            merged.append(discoveredAccount)
        }
        return merged
    }

    public static func representsSameAccount(
        _ lhs: UsageProviderTokenAccount,
        _ rhs: UsageProviderTokenAccount)
        -> Bool
    {
        if lhs.id == rhs.id { return true }
        if let lhsExternal = normalized(lhs.externalIdentifier)?.lowercased(),
           let rhsExternal = normalized(rhs.externalIdentifier)?.lowercased(),
           lhsExternal == rhsExternal
        {
            return true
        }
        guard let lhsPath = normalized(lhs.token),
              let rhsPath = normalized(rhs.token)
        else { return false }
        return NSString(string: lhsPath).standardizingPath == NSString(string: rhsPath).standardizingPath
    }

    public static func isLiveSystemAccount(_ account: UsageProviderTokenAccount) -> Bool {
        normalized(account.externalIdentifier)?.lowercased() == "live-system"
    }

    private static func discoveredAccount(
        matching account: UsageProviderTokenAccount,
        in discoveredAccounts: [UsageProviderTokenAccount])
        -> UsageProviderTokenAccount?
    {
        discoveredAccounts.first { representsSameAccount($0, account) }
    }

    private static func liveSystemAccount(
        in accounts: [UsageProviderTokenAccount])
        -> UsageProviderTokenAccount?
    {
        accounts.first(where: isLiveSystemAccount)
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
