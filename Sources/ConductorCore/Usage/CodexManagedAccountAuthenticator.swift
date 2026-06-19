import CryptoKit
import Foundation

public enum CodexManagedAccountAuthenticationError: LocalizedError, Equatable, Sendable {
    case loginFailed(CodexLoginRunner.Result)
    case missingEmail
    case missingAuthFile
    case unreadableAuthFile
    case managedStoreCommitFailed

    public var errorDescription: String? {
        switch self {
        case let .loginFailed(result):
            let prefix: String = switch result.outcome {
            case .success:
                L("Codex 登录成功但未生成账号信息。")
            case .missingBinary:
                L("未找到 Codex CLI。")
            case let .launchFailed(message):
                L("无法启动 codex login：%@", message)
            case .timedOut:
                L("codex login 超时。")
            case let .failed(status):
                L("codex login 退出码：%d。", Int(status))
            }
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? prefix : "\(prefix)\n\(output)"
        case .missingEmail:
            return L("Codex 登录成功，但 auth.json 中没有账号邮箱。")
        case .missingAuthFile:
            return L("Codex 登录未写入 auth.json。")
        case .unreadableAuthFile:
            return L("Codex auth.json 无法解析。")
        case .managedStoreCommitFailed:
            return L("写入 Codex 托管账号列表失败。")
        }
    }
}

public struct CodexManagedAccountAuthenticator {
    public typealias LoginRunner = @Sendable (String, TimeInterval) async -> CodexLoginRunner.Result

    private let store: FileCodexManagedAccountStore
    private let managedHomesRootURL: URL
    private let fileManager: FileManager
    private let loginRunner: LoginRunner

    public init(
        store: FileCodexManagedAccountStore = FileCodexManagedAccountStore(),
        managedHomesRootURL: URL = CodexManagedAccountDiscovery.managedHomesRootURL(),
        fileManager: FileManager = .default,
        loginRunner: @escaping LoginRunner = { homePath, timeout in
            await CodexLoginRunner.run(homePath: homePath, timeout: timeout)
        })
    {
        self.store = store
        self.managedHomesRootURL = managedHomesRootURL
        self.fileManager = fileManager
        self.loginRunner = loginRunner
    }

    public func authenticateManagedAccount(
        existingAccountID: UUID? = nil,
        timeout: TimeInterval = 120
    ) async throws -> CodexManagedAccount {
        let snapshot = try store.loadAccounts()
        let homeURL = managedHomesRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: homeURL, withIntermediateDirectories: true)

        do {
            let result = await loginRunner(homeURL.path, timeout)
            guard case .success = result.outcome else {
                throw CodexManagedAccountAuthenticationError.loginFailed(result)
            }

            let identity = try authIdentity(homeURL: homeURL)
            guard let email = normalized(identity.email) else {
                throw CodexManagedAccountAuthenticationError.missingEmail
            }

            let existing = reconciledExistingAccount(
                snapshot: snapshot,
                existingAccountID: existingAccountID,
                email: email,
                providerAccountID: identity.providerAccountID)
            let now = Date().timeIntervalSince1970
            let account = CodexManagedAccount(
                id: existing?.id ?? UUID(),
                email: email,
                providerAccountID: identity.providerAccountID ?? existing?.providerAccountID,
                workspaceLabel: identity.workspaceLabel ?? existing?.workspaceLabel,
                workspaceAccountID: identity.workspaceAccountID ?? existing?.workspaceAccountID,
                authFingerprint: identity.authFingerprint,
                managedHomePath: homeURL.path,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now,
                lastAuthenticatedAt: now)

            let replacedIDs = replacedAccountIDs(
                snapshot: snapshot,
                existingAccountID: existingAccountID,
                matchedAccountID: existing?.id,
                email: email,
                providerAccountID: identity.providerAccountID)
            let replacedHomePaths = snapshot.accounts
                .filter { replacedIDs.contains($0.id) }
                .map(\.managedHomePath)

            try store.storeAccounts(CodexManagedAccountSet(
                version: snapshot.version,
                accounts: snapshot.accounts.filter { !replacedIDs.contains($0.id) } + [account]))

            for path in replacedHomePaths where path != homeURL.path {
                removeManagedHomeIfSafe(path)
            }
            return account
        } catch {
            removeManagedHomeIfSafe(homeURL.path)
            throw error
        }
    }

    private struct AuthIdentity {
        let email: String?
        let providerAccountID: String?
        let workspaceLabel: String?
        let workspaceAccountID: String?
        let authFingerprint: String
    }

    private func authIdentity(homeURL: URL) throws -> AuthIdentity {
        let authURL = homeURL.appendingPathComponent("auth.json", isDirectory: false)
        guard fileManager.fileExists(atPath: authURL.path) else {
            throw CodexManagedAccountAuthenticationError.missingAuthFile
        }
        guard let data = try? Data(contentsOf: authURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any]
        else {
            throw CodexManagedAccountAuthenticationError.unreadableAuthFile
        }

        let idToken = (tokens["id_token"] as? String) ?? (tokens["idToken"] as? String)
        let payload = idToken.flatMap(CodexUsageFetcher.parseJWT)
        let profile = payload?["https://api.openai.com/profile"] as? [String: Any]
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

        return AuthIdentity(
            email: normalized((payload?["email"] as? String) ?? (profile?["email"] as? String)),
            providerAccountID: accountID,
            workspaceLabel: workspaceLabel,
            workspaceAccountID: accountID,
            authFingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }

    private func reconciledExistingAccount(
        snapshot: CodexManagedAccountSet,
        existingAccountID: UUID?,
        email: String,
        providerAccountID: String?
    ) -> CodexManagedAccount? {
        if let existingAccountID,
           let existing = snapshot.account(id: existingAccountID)
        {
            return existing
        }
        let normalizedEmail = email.lowercased()
        if let providerAccountID = normalized(providerAccountID),
           let exact = snapshot.accounts.first(where: {
               $0.email.lowercased() == normalizedEmail
                   && normalized($0.providerAccountID)?.lowercased() == providerAccountID.lowercased()
           })
        {
            return exact
        }
        return snapshot.accounts.first {
            $0.email.lowercased() == normalizedEmail && normalized($0.providerAccountID) == nil
        }
    }

    private func replacedAccountIDs(
        snapshot: CodexManagedAccountSet,
        existingAccountID: UUID?,
        matchedAccountID: UUID?,
        email: String,
        providerAccountID: String?
    ) -> Set<UUID> {
        var ids = Set([existingAccountID, matchedAccountID].compactMap { $0 })
        let normalizedEmail = email.lowercased()
        let normalizedProviderID = normalized(providerAccountID)?.lowercased()
        for account in snapshot.accounts {
            guard account.email.lowercased() == normalizedEmail else { continue }
            if let normalizedProviderID {
                guard normalized(account.providerAccountID)?.lowercased() == normalizedProviderID else { continue }
                ids.insert(account.id)
            } else if normalized(account.providerAccountID) == nil {
                ids.insert(account.id)
            }
        }
        return ids
    }

    private func removeManagedHomeIfSafe(_ path: String) {
        let homeURL = URL(fileURLWithPath: path, isDirectory: true)
        let rootPath = managedHomesRootURL.standardizedFileURL.path
        let homePath = homeURL.standardizedFileURL.path
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard homePath.hasPrefix(rootPrefix), homePath != rootPath else { return }
        try? fileManager.removeItem(at: homeURL)
    }

    private func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
