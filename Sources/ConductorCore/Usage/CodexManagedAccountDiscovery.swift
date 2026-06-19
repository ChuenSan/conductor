import CryptoKit
import Foundation

public enum CodexManagedAccountDiscovery {
    public static let storePathEnvironmentName = "CONDUCTOR_CODEXBAR_MANAGED_ACCOUNTS_PATH"

    public static func tokenAccounts(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [UsageProviderTokenAccount] {
        accountDrafts(env: env, fileManager: fileManager).map(\.tokenAccount)
    }

    public static func accountEmails(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [String] {
        var seen = Set<String>()
        return accountDrafts(env: env, fileManager: fileManager)
            .map(\.email)
            .filter { seen.insert($0).inserted }
    }

    public static func dashboardKnownOwners(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [CodexDashboardKnownOwnerCandidate] {
        var seen = Set<CodexDashboardKnownOwnerCandidate>()
        var owners: [CodexDashboardKnownOwnerCandidate] = []
        for draft in accountDrafts(env: env, fileManager: fileManager) {
            let email = draft.email
            let ids = [
                draft.providerAccountID,
                draft.workspaceAccountID,
            ]
            for id in ids.compactMap(CodexIdentityResolver.normalizeAccountID) {
                let owner = CodexDashboardKnownOwnerCandidate(
                    identity: .providerAccount(id: id),
                    normalizedEmail: email)
                if seen.insert(owner).inserted {
                    owners.append(owner)
                }
            }
            if ids.compactMap(CodexIdentityResolver.normalizeAccountID).isEmpty {
                let owner = CodexDashboardKnownOwnerCandidate(
                    identity: .emailOnly(normalizedEmail: email),
                    normalizedEmail: email)
                if seen.insert(owner).inserted {
                    owners.append(owner)
                }
            }
        }
        return owners
    }

    public static func storeURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let raw = normalized(env[storePathEnvironmentName]) {
            return URL(fileURLWithPath: raw, isDirectory: false)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("managed-codex-accounts.json", isDirectory: false)
    }

    public static func codexHomeURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let raw = normalized(env["CODEX_HOME"]) {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    public static func managedHomesRootURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        return base
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("managed-codex-homes", isDirectory: true)
    }

    private static func draft(
        from account: CodexManagedAccount,
        fileManager: FileManager
    ) -> CodexAccountDraft {
        let fingerprint = normalized(account.authFingerprint)
            ?? authFingerprint(homePath: account.managedHomePath, fileManager: fileManager)
        return CodexAccountDraft(
            id: account.id,
            email: normalizedEmail(account.email),
            providerAccountID: normalized(account.providerAccountID),
            workspaceLabel: normalized(account.workspaceLabel),
            workspaceAccountID: normalized(account.workspaceAccountID),
            homePath: account.managedHomePath,
            authFingerprint: fingerprint,
            externalIdentifier: account.providerAccountID ?? "managed:\(account.id.uuidString.lowercased())",
            isLive: false)
    }

    private static func accountDrafts(
        env: [String: String],
        fileManager: FileManager
    ) -> [CodexAccountDraft] {
        let managed = (try? FileCodexManagedAccountStore(
            fileURL: storeURL(env: env, fileManager: fileManager),
            fileManager: fileManager).loadAccounts())?.accounts ?? []
        var drafts = managed.map { draft(from: $0, fileManager: fileManager) }

        if let live = liveSystemAccount(env: env, fileManager: fileManager) {
            mergeLive(live, into: &drafts)
        }

        return drafts.sorted { lhs, rhs in
            if lhs.email != rhs.email {
                return lhs.email < rhs.email
            }
            if lhs.isLive != rhs.isLive {
                return lhs.isLive && !rhs.isLive
            }
            if lhs.label != rhs.label {
                return lhs.label < rhs.label
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func liveSystemAccount(
        env: [String: String],
        fileManager: FileManager
    ) -> CodexAccountDraft? {
        let homeURL = codexHomeURL(env: env, fileManager: fileManager)
        let authURL = homeURL.appendingPathComponent("auth.json", isDirectory: false)
        guard fileManager.fileExists(atPath: authURL.path),
              let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any]
        else {
            return nil
        }

        let idToken = (tokens["id_token"] as? String) ?? (tokens["idToken"] as? String)
        let payload = idToken.flatMap(CodexUsageFetcher.parseJWT)
        let profile = payload?["https://api.openai.com/profile"] as? [String: Any]
        guard let email = normalized((payload?["email"] as? String) ?? (profile?["email"] as? String)) else {
            return nil
        }

        let auth = payload?["https://api.openai.com/auth"] as? [String: Any]
        let accountID = normalized(
            (tokens["account_id"] as? String)
                ?? (tokens["accountId"] as? String)
                ?? (auth?["chatgpt_account_id"] as? String)
                ?? (payload?["chatgpt_account_id"] as? String))
        let workspaceLabel = normalized(
            (auth?["chatgpt_account_name"] as? String)
                ?? (auth?["account_name"] as? String)
                ?? (payload?["chatgpt_account_name"] as? String))
        let fingerprint = sha256Hex(data)

        return CodexAccountDraft(
            id: stableUUID(seed: "codex-live:\(accountID ?? email):\(fingerprint)"),
            email: normalizedEmail(email),
            providerAccountID: accountID,
            workspaceLabel: workspaceLabel,
            workspaceAccountID: accountID,
            homePath: homeURL.path,
            authFingerprint: fingerprint,
            externalIdentifier: "live-system",
            isLive: true)
    }

    private static func mergeLive(_ live: CodexAccountDraft, into drafts: inout [CodexAccountDraft]) {
        if let fingerprint = live.authFingerprint,
           let index = drafts.firstIndex(where: { $0.authFingerprint == fingerprint })
        {
            drafts[index] = live.reusingStoredIdentity(from: drafts[index])
            return
        }
        if let index = drafts.firstIndex(where: { $0.homePath == live.homePath }) {
            drafts[index] = live.reusingStoredIdentity(from: drafts[index])
            return
        }
        if let workspaceAccountID = live.workspaceAccountID,
           let index = drafts.firstIndex(where: {
               $0.email == live.email && $0.workspaceAccountID == workspaceAccountID
           })
        {
            drafts[index] = live.reusingStoredIdentity(from: drafts[index])
            return
        }
        if let index = drafts.firstIndex(where: {
            $0.email == live.email && $0.workspaceAccountID == nil && live.workspaceAccountID == nil
        }) {
            drafts[index] = live.reusingStoredIdentity(from: drafts[index])
            return
        }
        drafts.append(live)
    }

    private static func authFingerprint(homePath: String, fileManager: FileManager) -> String? {
        let url = URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return sha256Hex(data)
    }

    private static func stableUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let first = String(hex.prefix(8))
        let second = String(hex.dropFirst(8).prefix(4))
        let third = String(hex.dropFirst(12).prefix(4))
        let fourth = String(hex.dropFirst(16).prefix(4))
        let fifth = String(hex.dropFirst(20).prefix(12))
        let uuidString = "\(first)-\(second)-\(third)-\(fourth)-\(fifth)"
        return UUID(uuidString: uuidString) ?? UUID()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public struct CodexManagedAccount: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let email: String
    public let providerAccountID: String?
    public let workspaceLabel: String?
    public let workspaceAccountID: String?
    public let authFingerprint: String?
    public let managedHomePath: String
    public let createdAt: TimeInterval
    public let updatedAt: TimeInterval
    public let lastAuthenticatedAt: TimeInterval?

    public init(
        id: UUID,
        email: String,
        providerAccountID: String? = nil,
        workspaceLabel: String? = nil,
        workspaceAccountID: String? = nil,
        authFingerprint: String? = nil,
        managedHomePath: String,
        createdAt: TimeInterval,
        updatedAt: TimeInterval,
        lastAuthenticatedAt: TimeInterval? = nil)
    {
        self.id = id
        self.email = email
        self.providerAccountID = providerAccountID
        self.workspaceLabel = workspaceLabel
        self.workspaceAccountID = workspaceAccountID
        self.authFingerprint = authFingerprint
        self.managedHomePath = managedHomePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAuthenticatedAt = lastAuthenticatedAt
    }
}

public struct CodexManagedAccountSet: Codable, Equatable, Sendable {
    public let version: Int
    public let accounts: [CodexManagedAccount]

    public init(version: Int, accounts: [CodexManagedAccount]) {
        self.version = version
        self.accounts = accounts
    }

    public func account(id: UUID) -> CodexManagedAccount? {
        accounts.first { $0.id == id }
    }
}

public enum FileCodexManagedAccountStoreError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
}

public struct FileCodexManagedAccountStore: @unchecked Sendable {
    public static let currentVersion = 3

    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = CodexManagedAccountDiscovery.storeURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func loadAccounts() throws -> CodexManagedAccountSet {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return CodexManagedAccountSet(version: Self.currentVersion, accounts: [])
        }
        let data = try Data(contentsOf: fileURL)
        let set = try JSONDecoder().decode(CodexManagedAccountSet.self, from: data)
        guard (1...Self.currentVersion).contains(set.version) else {
            throw FileCodexManagedAccountStoreError.unsupportedVersion(set.version)
        }
        return CodexManagedAccountSet(
            version: Self.currentVersion,
            accounts: sanitized(set.accounts))
    }

    public func storeAccounts(_ accounts: CodexManagedAccountSet) throws {
        let normalized = CodexManagedAccountSet(
            version: Self.currentVersion,
            accounts: sanitized(accounts.accounts))
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try data.write(to: fileURL, options: [.atomic])
        #if os(macOS)
        try? fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: fileURL.path)
        #endif
    }

    @discardableResult
    public func removeManagedAccount(
        id: UUID,
        deleteManagedHome: Bool = true,
        managedHomesRootURL: URL? = nil
    ) throws -> Bool {
        let snapshot = try loadAccounts()
        guard let account = snapshot.account(id: id) else { return false }

        let remaining = snapshot.accounts.filter { $0.id != id }
        try storeAccounts(CodexManagedAccountSet(
            version: snapshot.version,
            accounts: remaining))

        guard deleteManagedHome else { return true }
        let homeURL = URL(fileURLWithPath: account.managedHomePath, isDirectory: true)
        let rootURL = managedHomesRootURL ?? CodexManagedAccountDiscovery.managedHomesRootURL(fileManager: fileManager)
        if isSafeManagedHome(homeURL, under: rootURL),
           fileManager.fileExists(atPath: homeURL.path)
        {
            try? fileManager.removeItem(at: homeURL)
        }
        return true
    }

    private func sanitized(_ accounts: [CodexManagedAccount]) -> [CodexManagedAccount] {
        var seenIDs: Set<UUID> = []
        var seenKeys: Set<String> = []
        var out: [CodexManagedAccount] = []
        for account in accounts {
            guard seenIDs.insert(account.id).inserted else { continue }
            let email = account.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty, !account.managedHomePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let key = [email, account.providerAccountID ?? account.managedHomePath].joined(separator: "\u{0}")
            guard seenKeys.insert(key).inserted else { continue }
            out.append(account)
        }
        return out
    }

    private func isSafeManagedHome(_ homeURL: URL, under rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let homePath = homeURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return homePath.hasPrefix(rootPrefix) && homePath != rootPath
    }
}

private struct CodexAccountDraft {
    let id: UUID
    let email: String
    let providerAccountID: String?
    let workspaceLabel: String?
    let workspaceAccountID: String?
    let homePath: String
    let authFingerprint: String?
    let externalIdentifier: String?
    let isLive: Bool

    var label: String {
        guard let workspaceLabel,
              workspaceLabel.compare("Personal", options: [.caseInsensitive]) != .orderedSame
        else {
            return email
        }
        return "\(email) - \(workspaceLabel)"
    }

    var tokenAccount: UsageProviderTokenAccount {
        UsageProviderTokenAccount(
            id: id,
            label: label,
            token: homePath,
            externalIdentifier: externalIdentifier,
            organizationID: workspaceAccountID)
    }

    func reusingStoredIdentity(from stored: CodexAccountDraft) -> CodexAccountDraft {
        CodexAccountDraft(
            id: stored.id,
            email: email,
            providerAccountID: providerAccountID ?? stored.providerAccountID,
            workspaceLabel: workspaceLabel ?? stored.workspaceLabel,
            workspaceAccountID: workspaceAccountID ?? stored.workspaceAccountID,
            homePath: homePath,
            authFingerprint: authFingerprint ?? stored.authFingerprint,
            externalIdentifier: externalIdentifier ?? stored.externalIdentifier,
            isLive: true)
    }
}
