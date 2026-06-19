import CryptoKit
#if canImport(Darwin)
import Darwin
#endif
import Foundation

public enum CodexManagedAccountPromotionError: LocalizedError, Equatable, Sendable {
    case targetManagedAccountNotFound
    case targetManagedAccountAuthMissing
    case targetManagedAccountAuthUnreadable
    case liveAccountUnreadable
    case liveAccountMissingIdentityForPreservation
    case liveAccountAPIKeyOnlyUnsupported
    case displacedLiveManagedAccountConflict
    case displacedLiveImportFailed
    case managedStoreCommitFailed
    case liveAuthSwapFailed

    public var errorDescription: String? {
        switch self {
        case .targetManagedAccountNotFound:
            return L("未找到要设为本机的 Codex 托管账号。")
        case .targetManagedAccountAuthMissing:
            return L("该 Codex 托管账号缺少 auth.json，请先重登。")
        case .targetManagedAccountAuthUnreadable:
            return L("该 Codex 托管账号 auth.json 无法解析，请先重登。")
        case .liveAccountUnreadable:
            return L("当前本机 Codex auth.json 无法读取，拒绝覆盖以避免丢失登录态。")
        case .liveAccountMissingIdentityForPreservation:
            return L("当前本机 Codex 账号无法识别，拒绝覆盖以避免丢失登录态。")
        case .liveAccountAPIKeyOnlyUnsupported:
            return L("当前本机 Codex 账号像 API Key-only 配置，暂不能自动保存为托管账号。")
        case .displacedLiveManagedAccountConflict:
            return L("当前本机 Codex 账号与已有托管账号冲突，请先重登或移除冲突账号。")
        case .displacedLiveImportFailed:
            return L("保存当前本机 Codex 账号失败，未覆盖 auth.json。")
        case .managedStoreCommitFailed:
            return L("写入 Codex 托管账号列表失败。")
        case .liveAuthSwapFailed:
            return L("写入本机 Codex auth.json 失败。")
        }
    }
}

public struct CodexManagedAccountPromotionResult: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case promoted
        case convergedNoOp
    }

    public enum DisplacedLiveDisposition: Equatable, Sendable {
        case none
        case alreadyManaged(managedAccountID: UUID)
        case imported(managedAccountID: UUID)
    }

    public let targetManagedAccountID: UUID
    public let outcome: Outcome
    public let displacedLiveDisposition: DisplacedLiveDisposition
    public let didMutateLiveAuth: Bool

    public init(
        targetManagedAccountID: UUID,
        outcome: Outcome,
        displacedLiveDisposition: DisplacedLiveDisposition,
        didMutateLiveAuth: Bool
    ) {
        self.targetManagedAccountID = targetManagedAccountID
        self.outcome = outcome
        self.displacedLiveDisposition = displacedLiveDisposition
        self.didMutateLiveAuth = didMutateLiveAuth
    }
}

public struct CodexManagedAccountPromoter {
    private let store: FileCodexManagedAccountStore
    private let liveHomeURL: URL
    private let managedHomesRootURL: URL
    private let fileManager: FileManager

    public init(
        store: FileCodexManagedAccountStore = FileCodexManagedAccountStore(),
        liveHomeURL: URL = CodexManagedAccountDiscovery.codexHomeURL(),
        managedHomesRootURL: URL = CodexManagedAccountDiscovery.managedHomesRootURL(),
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.liveHomeURL = liveHomeURL
        self.managedHomesRootURL = managedHomesRootURL
        self.fileManager = fileManager
    }

    public func promoteManagedAccount(id: UUID) throws -> CodexManagedAccountPromotionResult {
        let snapshot = try store.loadAccounts()
        let prepared = snapshot.accounts.map { prepareManagedAccount($0) }
        guard let target = prepared.first(where: { $0.persisted.id == id }) else {
            throw CodexManagedAccountPromotionError.targetManagedAccountNotFound
        }
        let targetAuth = try requiredTargetAuthMaterial(target)
        let liveState = prepareLiveAccount()

        if case let .readable(liveAuth) = liveState,
           identityMatches(targetAuth.identity, liveAuth.identity)
        {
            return CodexManagedAccountPromotionResult(
                targetManagedAccountID: id,
                outcome: .convergedNoOp,
                displacedLiveDisposition: .none,
                didMutateLiveAuth: false)
        }

        let disposition = try preserveDisplacedLive(
            state: liveState,
            target: target,
            candidates: prepared.filter { $0.persisted.id != id })

        do {
            try swapLiveAuthData(targetAuth.rawData)
        } catch {
            throw CodexManagedAccountPromotionError.liveAuthSwapFailed
        }

        return CodexManagedAccountPromotionResult(
            targetManagedAccountID: id,
            outcome: .promoted,
            displacedLiveDisposition: disposition,
            didMutateLiveAuth: true)
    }

    private struct AuthIdentity: Equatable, Sendable {
        let email: String?
        let identity: CodexIdentity
        let providerAccountID: String?
        let workspaceLabel: String?
        let workspaceAccountID: String?
    }

    private struct AuthMaterial: Equatable, Sendable {
        let homeURL: URL
        let rawData: Data
        let identity: AuthIdentity
        let authFingerprint: String
        let hasUsableOAuthTokens: Bool
    }

    private enum ManagedHomeState: Equatable {
        case missing(URL)
        case unreadable(URL)
        case readable(AuthMaterial)
    }

    private enum LiveHomeState: Equatable {
        case missing(URL)
        case unreadable(URL)
        case apiKeyOnly(AuthMaterial?)
        case readable(AuthMaterial)
    }

    private struct PreparedManagedAccount {
        let persisted: CodexManagedAccount
        let persistedIdentity: AuthIdentity
        let homeState: ManagedHomeState

        var authIdentity: AuthIdentity? {
            switch homeState {
            case let .readable(material):
                return material.identity
            case .missing, .unreadable:
                return nil
            }
        }
    }

    private func prepareManagedAccount(_ account: CodexManagedAccount) -> PreparedManagedAccount {
        let homeURL = URL(fileURLWithPath: account.managedHomePath, isDirectory: true)
        return PreparedManagedAccount(
            persisted: account,
            persistedIdentity: persistedIdentity(account),
            homeState: prepareManagedHomeState(homeURL))
    }

    private func prepareManagedHomeState(_ homeURL: URL) -> ManagedHomeState {
        switch readAuthMaterial(homeURL: homeURL) {
        case .missing:
            return .missing(homeURL)
        case .unreadable, .apiKeyOnly:
            return .unreadable(homeURL)
        case let .readable(material):
            return .readable(material)
        }
    }

    private func prepareLiveAccount() -> LiveHomeState {
        readAuthMaterial(homeURL: liveHomeURL)
    }

    private func readAuthMaterial(homeURL: URL) -> LiveHomeState {
        let authURL = Self.authFileURL(for: homeURL)
        guard fileManager.fileExists(atPath: authURL.path) else {
            return .missing(homeURL)
        }
        guard let data = try? Data(contentsOf: authURL) else {
            return .unreadable(homeURL)
        }
        do {
            let material = try authMaterial(homeURL: homeURL, data: data)
            if !material.hasUsableOAuthTokens,
               material.identity.identity == .unresolved,
               material.identity.email == nil
            {
                return .apiKeyOnly(material)
            }
            return .readable(material)
        } catch AuthParseError.apiKeyOnly {
            return .apiKeyOnly(nil)
        } catch {
            return .unreadable(homeURL)
        }
    }

    private enum AuthParseError: Error {
        case unreadable
        case apiKeyOnly
    }

    private func authMaterial(homeURL: URL, data: Data) throws -> AuthMaterial {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthParseError.unreadable
        }
        guard let tokens = json["tokens"] as? [String: Any] else {
            throw AuthParseError.apiKeyOnly
        }

        let idToken = string(tokens["id_token"]) ?? string(tokens["idToken"])
        let payload = idToken.flatMap(CodexUsageFetcher.parseJWT)
        let profile = payload?["https://api.openai.com/profile"] as? [String: Any]
        let auth = payload?["https://api.openai.com/auth"] as? [String: Any]
        let email = CodexIdentityResolver.normalizeEmail(
            string(payload?["email"])
                ?? string(profile?["email"]))
        let accountID = CodexIdentityResolver.normalizeAccountID(
            string(tokens["account_id"])
                ?? string(tokens["accountId"])
                ?? string(auth?["chatgpt_account_id"])
                ?? string(payload?["chatgpt_account_id"]))
        let workspaceLabel = normalized(
            string(auth?["chatgpt_account_name"])
                ?? string(auth?["account_name"])
                ?? string(payload?["chatgpt_account_name"]))
        let accessToken = normalized(string(tokens["access_token"]) ?? string(tokens["accessToken"]))
        let refreshToken = normalized(string(tokens["refresh_token"]) ?? string(tokens["refreshToken"]))
        return AuthMaterial(
            homeURL: homeURL,
            rawData: data,
            identity: AuthIdentity(
                email: email,
                identity: CodexIdentityResolver.resolve(accountID: accountID, email: email),
                providerAccountID: accountID,
                workspaceLabel: workspaceLabel,
                workspaceAccountID: accountID),
            authFingerprint: sha256Hex(data),
            hasUsableOAuthTokens: accessToken != nil && refreshToken != nil)
    }

    private func persistedIdentity(_ account: CodexManagedAccount) -> AuthIdentity {
        let email = CodexIdentityResolver.normalizeEmail(account.email)
        let accountID = CodexIdentityResolver.normalizeAccountID(account.providerAccountID)
        return AuthIdentity(
            email: email,
            identity: CodexIdentityResolver.resolve(accountID: accountID, email: email),
            providerAccountID: accountID,
            workspaceLabel: normalized(account.workspaceLabel),
            workspaceAccountID: CodexIdentityResolver.normalizeAccountID(account.workspaceAccountID))
    }

    private func requiredTargetAuthMaterial(_ target: PreparedManagedAccount) throws -> AuthMaterial {
        switch target.homeState {
        case .missing:
            throw CodexManagedAccountPromotionError.targetManagedAccountAuthMissing
        case .unreadable:
            throw CodexManagedAccountPromotionError.targetManagedAccountAuthUnreadable
        case let .readable(material):
            guard material.identity.email != nil else {
                throw CodexManagedAccountPromotionError.targetManagedAccountAuthUnreadable
            }
            return material
        }
    }

    private func preserveDisplacedLive(
        state: LiveHomeState,
        target: PreparedManagedAccount,
        candidates: [PreparedManagedAccount]
    ) throws -> CodexManagedAccountPromotionResult.DisplacedLiveDisposition {
        switch state {
        case .missing:
            return .none
        case .unreadable:
            throw CodexManagedAccountPromotionError.liveAccountUnreadable
        case .apiKeyOnly:
            throw CodexManagedAccountPromotionError.liveAccountAPIKeyOnlyUnsupported
        case let .readable(liveAuth):
            if let targetIdentity = target.authIdentity,
               identityMatches(targetIdentity, liveAuth.identity)
            {
                return .none
            }

            if let destination = candidates.first(where: {
                guard let candidateIdentity = $0.authIdentity else { return false }
                return identityMatches(candidateIdentity, liveAuth.identity)
            }) {
                let refreshed = try refreshExistingManagedAccount(destination, with: liveAuth)
                return .alreadyManaged(managedAccountID: refreshed.id)
            }

            if hasConflictingReadableManagedHome(candidates: candidates, liveIdentity: liveAuth.identity) {
                throw CodexManagedAccountPromotionError.displacedLiveManagedAccountConflict
            }

            if let destination = persistedRepairDestination(candidates: candidates, liveIdentity: liveAuth.identity) {
                let refreshed = try refreshExistingManagedAccount(destination, with: liveAuth)
                return .alreadyManaged(managedAccountID: refreshed.id)
            }

            guard liveAuth.identity.identity != .unresolved, liveAuth.identity.email != nil else {
                throw CodexManagedAccountPromotionError.liveAccountMissingIdentityForPreservation
            }
            let imported = try importDisplacedLiveAccount(liveAuth)
            return .imported(managedAccountID: imported.id)
        }
    }

    private func hasConflictingReadableManagedHome(
        candidates: [PreparedManagedAccount],
        liveIdentity: AuthIdentity
    ) -> Bool {
        guard let liveProviderID = liveIdentity.providerAccountID else { return false }
        return candidates.contains { candidate in
            guard CodexIdentityResolver.normalizeAccountID(candidate.persisted.providerAccountID) == liveProviderID else {
                return false
            }
            if let liveEmail = liveIdentity.email,
               CodexIdentityResolver.normalizeEmail(candidate.persisted.email) != liveEmail
            {
                return false
            }
            guard let candidateIdentity = candidate.authIdentity else { return false }
            return !identityMatches(candidateIdentity, liveIdentity)
        }
    }

    private func persistedRepairDestination(
        candidates: [PreparedManagedAccount],
        liveIdentity: AuthIdentity
    ) -> PreparedManagedAccount? {
        if let providerID = liveIdentity.providerAccountID {
            if let destination = candidates.first(where: { candidate in
                guard CodexIdentityResolver.normalizeAccountID(candidate.persisted.providerAccountID) == providerID else {
                    return false
                }
                if let liveEmail = liveIdentity.email {
                    return CodexIdentityResolver.normalizeEmail(candidate.persisted.email) == liveEmail
                }
                return true
            }),
                !isReadable(destination.homeState)
            {
                return destination
            }
            if let liveEmail = liveIdentity.email {
                return candidates.first { candidate in
                    CodexIdentityResolver.normalizeAccountID(candidate.persisted.providerAccountID) == nil
                        && CodexIdentityResolver.normalizeEmail(candidate.persisted.email) == liveEmail
                }
            }
            return nil
        }

        guard let liveEmail = liveIdentity.email else { return nil }
        return candidates.first { candidate in
            CodexIdentityResolver.normalizeAccountID(candidate.persisted.providerAccountID) == nil
                && CodexIdentityResolver.normalizeEmail(candidate.persisted.email) == liveEmail
        }
    }

    private func refreshExistingManagedAccount(
        _ destination: PreparedManagedAccount,
        with liveAuth: AuthMaterial
    ) throws -> CodexManagedAccount {
        let homeURL = URL(fileURLWithPath: destination.persisted.managedHomePath, isDirectory: true)
        guard isSafeManagedHome(homeURL) else {
            throw CodexManagedAccountPromotionError.displacedLiveImportFailed
        }

        let latest = try store.loadAccounts()
        guard latest.account(id: destination.persisted.id) != nil else {
            throw CodexManagedAccountPromotionError.managedStoreCommitFailed
        }

        let now = Date().timeIntervalSince1970
        let refreshed = CodexManagedAccount(
            id: destination.persisted.id,
            email: liveAuth.identity.email ?? destination.persisted.email,
            providerAccountID: liveAuth.identity.providerAccountID ?? destination.persisted.providerAccountID,
            workspaceLabel: liveAuth.identity.workspaceLabel ?? destination.persisted.workspaceLabel,
            workspaceAccountID: liveAuth.identity.workspaceAccountID ?? destination.persisted.workspaceAccountID,
            authFingerprint: liveAuth.authFingerprint,
            managedHomePath: destination.persisted.managedHomePath,
            createdAt: destination.persisted.createdAt,
            updatedAt: now,
            lastAuthenticatedAt: now)

        do {
            try writeManagedAuthData(liveAuth.rawData, to: homeURL)
        } catch let error as CodexManagedAccountPromotionError {
            throw error
        } catch {
            throw CodexManagedAccountPromotionError.displacedLiveImportFailed
        }

        do {
            try store.storeAccounts(CodexManagedAccountSet(
                version: latest.version,
                accounts: latest.accounts.map { $0.id == refreshed.id ? refreshed : $0 }))
            return refreshed
        } catch {
            throw CodexManagedAccountPromotionError.managedStoreCommitFailed
        }
    }

    private func importDisplacedLiveAccount(_ liveAuth: AuthMaterial) throws -> CodexManagedAccount {
        let homeURL = managedHomesRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard let email = liveAuth.identity.email,
              liveAuth.identity.identity != .unresolved
        else {
            throw CodexManagedAccountPromotionError.liveAccountMissingIdentityForPreservation
        }

        do {
            try writeManagedAuthData(liveAuth.rawData, to: homeURL)
            let now = Date().timeIntervalSince1970
            let account = CodexManagedAccount(
                id: UUID(uuidString: homeURL.lastPathComponent) ?? UUID(),
                email: email,
                providerAccountID: liveAuth.identity.providerAccountID,
                workspaceLabel: liveAuth.identity.workspaceLabel,
                workspaceAccountID: liveAuth.identity.workspaceAccountID,
                authFingerprint: liveAuth.authFingerprint,
                managedHomePath: homeURL.path,
                createdAt: now,
                updatedAt: now,
                lastAuthenticatedAt: now)
            let latest = try store.loadAccounts()
            try store.storeAccounts(CodexManagedAccountSet(
                version: latest.version,
                accounts: latest.accounts + [account]))
            return account
        } catch let error as CodexManagedAccountPromotionError {
            removeManagedHomeIfSafe(homeURL)
            throw error
        } catch {
            removeManagedHomeIfSafe(homeURL)
            throw CodexManagedAccountPromotionError.displacedLiveImportFailed
        }
    }

    private func writeManagedAuthData(_ data: Data, to homeURL: URL) throws {
        guard isSafeManagedHome(homeURL) else {
            throw CodexManagedAccountPromotionError.displacedLiveImportFailed
        }
        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)
        let authURL = Self.authFileURL(for: homeURL)
        try data.write(to: authURL, options: [.atomic])
        try? fileManager.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: authURL.path)
    }

    private func swapLiveAuthData(_ data: Data) throws {
        try fileManager.createDirectory(at: liveHomeURL, withIntermediateDirectories: true)
        let authURL = Self.authFileURL(for: liveHomeURL)
        let stagedURL = liveHomeURL.appendingPathComponent(
            "auth.json.conductor-staged-\(UUID().uuidString)",
            isDirectory: false)

        do {
            try data.write(to: stagedURL)
            try? fileManager.setAttributes([
                .posixPermissions: NSNumber(value: Int16(0o600)),
            ], ofItemAtPath: stagedURL.path)
            try renameItem(at: stagedURL, to: authURL)
        } catch {
            try? fileManager.removeItem(at: stagedURL)
            throw error
        }
    }

    private func renameItem(at sourceURL: URL, to destinationURL: URL) throws {
        #if canImport(Darwin)
        let result = sourceURL.path.withCString { sourceFS in
            destinationURL.path.withCString { destinationFS in
                rename(sourceFS, destinationFS)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: destinationURL.path])
        }
        #else
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        #endif
    }

    private func identityMatches(_ lhs: AuthIdentity, _ rhs: AuthIdentity) -> Bool {
        switch (lhs.identity, rhs.identity) {
        case let (.providerAccount(leftID), .providerAccount(rightID)):
            guard leftID == rightID else { return false }
            guard let leftEmail = lhs.email, let rightEmail = rhs.email else { return true }
            return leftEmail == rightEmail
        case let (.emailOnly(leftEmail), .emailOnly(rightEmail)):
            return leftEmail == rightEmail
        default:
            return false
        }
    }

    private func isReadable(_ state: ManagedHomeState) -> Bool {
        if case .readable = state { return true }
        return false
    }

    private func isSafeManagedHome(_ homeURL: URL) -> Bool {
        let rootPath = managedHomesRootURL.standardizedFileURL.path
        let homePath = homeURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return homePath.hasPrefix(rootPrefix) && homePath != rootPath
    }

    private func removeManagedHomeIfSafe(_ homeURL: URL) {
        guard isSafeManagedHome(homeURL), fileManager.fileExists(atPath: homeURL.path) else { return }
        try? fileManager.removeItem(at: homeURL)
    }

    private func string(_ value: Any?) -> String? {
        value as? String
    }

    private func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func authFileURL(for homeURL: URL) -> URL {
        homeURL.appendingPathComponent("auth.json", isDirectory: false)
    }
}
