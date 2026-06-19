import CryptoKit
import Foundation

public enum UsageAccountCacheKey {
    public static func tokenAccountKey(
        providerID: String,
        account: UsageProviderTokenAccount,
        usageAccountLabel: String? = nil)
        -> String
    {
        let provider = normalizedProviderID(providerID)
        if provider == "codex" {
            if let accountID = CodexIdentityResolver.normalizeAccountID(account.organizationID) {
                return "codex-account:\(sha256Prefix(accountID))"
            }
            if let external = normalized(account.externalIdentifier),
               external.lowercased() != "live-system",
               !external.lowercased().hasPrefix("managed:")
            {
                return "codex-account:\(sha256Prefix(external))"
            }
            if let email = CodexIdentityResolver.firstEmail(in: account.label)
                ?? CodexIdentityResolver.firstEmail(in: usageAccountLabel)
            {
                return "codex-email:\(sha256Prefix(email))"
            }
        }

        if let external = normalized(account.externalIdentifier) {
            return "external:\(provider):\(sha256Prefix(external.lowercased()))"
        }
        return "token:\(provider):\(account.id.uuidString.lowercased())"
    }

    public static func snapshotDerivedKey(
        providerID: String,
        usageAccountLabel: String?)
        -> String?
    {
        let provider = normalizedProviderID(providerID)
        guard provider == "codex",
              let email = CodexIdentityResolver.firstEmail(in: usageAccountLabel)
        else {
            return nil
        }
        return "codex-email:\(sha256Prefix(email))"
    }

    public static func storageID(providerID: String, accountKey: String?) -> String {
        let provider = normalizedProviderID(providerID)
        guard let accountKey = normalized(accountKey) else { return provider }
        return "\(provider)|account:\(accountKey)"
    }

    public static func isScopedStorageID(_ storageID: String, providerID: String) -> Bool {
        storageID.hasPrefix("\(normalizedProviderID(providerID))|account:")
    }

    private static func normalizedProviderID(_ providerID: String) -> String {
        normalized(providerID)?.lowercased() ?? providerID.lowercased()
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func sha256Prefix(_ raw: String) -> String {
        SHA256.hash(data: Data(raw.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(20)
            .description
    }
}
