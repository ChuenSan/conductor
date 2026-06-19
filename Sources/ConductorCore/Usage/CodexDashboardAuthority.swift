import Foundation

public enum CodexIdentity: Codable, Equatable, Sendable {
    case providerAccount(id: String)
    case emailOnly(normalizedEmail: String)
    case unresolved
}

public enum CodexIdentityResolver {
    public static func resolve(accountID: String?, email: String?) -> CodexIdentity {
        if let accountID = normalizeAccountID(accountID) {
            return .providerAccount(id: accountID)
        }
        if let email = normalizeEmail(email) {
            return .emailOnly(normalizedEmail: email)
        }
        return .unresolved
    }

    public static func normalizeEmail(_ email: String?) -> String? {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty
        else {
            return nil
        }
        return email.lowercased()
    }

    public static func normalizeAccountID(_ accountID: String?) -> String? {
        guard let accountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountID.isEmpty
        else {
            return nil
        }
        return accountID
    }

    public static func firstEmail(in raw: String?) -> String? {
        guard let raw else { return nil }
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let match = raw.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        return normalizeEmail(String(raw[match]))
    }
}

public struct CodexAuthBackedAccount: Equatable, Sendable {
    public let identity: CodexIdentity
    public let email: String?
    public let plan: String?

    public init(identity: CodexIdentity, email: String?, plan: String?) {
        self.identity = identity
        self.email = email
        self.plan = plan
    }
}

public enum CodexDashboardSourceKind: String, Codable, Sendable {
    case liveWeb
    case cachedDashboard
}

public enum CodexDashboardDisposition: String, Codable, Sendable {
    case attach
    case displayOnly
    case failClosed
}

public enum CodexDashboardAllowedEffect: String, Codable, CaseIterable, Hashable, Sendable {
    case usageBackfill
    case creditsAttachment
    case refreshGuardSeed
    case historicalBackfill
    case cachedDashboardReuse
}

public enum CodexDashboardCleanup: String, Codable, CaseIterable, Hashable, Sendable {
    case dashboardSnapshot
    case dashboardDerivedUsage
    case dashboardDerivedCredits
    case dashboardRefreshGuardSeed
    case dashboardCache
}

public struct CodexDashboardKnownOwnerCandidate: Equatable, Hashable, Sendable {
    public let identity: CodexIdentity
    public let normalizedEmail: String?

    public init(identity: CodexIdentity, normalizedEmail: String?) {
        self.identity = identity
        self.normalizedEmail = normalizedEmail
    }

    public func hash(into hasher: inout Hasher) {
        switch identity {
        case let .providerAccount(id):
            hasher.combine("providerAccount")
            hasher.combine(id)
        case let .emailOnly(normalizedEmail):
            hasher.combine("emailOnly")
            hasher.combine(normalizedEmail)
        case .unresolved:
            hasher.combine("unresolved")
        }
        hasher.combine(normalizedEmail)
    }
}

public struct CodexDashboardOwnershipProofContext: Equatable, Sendable {
    public let currentIdentity: CodexIdentity
    public let expectedScopedEmail: String?
    public let trustedCurrentUsageEmail: String?
    public let dashboardSignedInEmail: String?
    public let knownOwners: [CodexDashboardKnownOwnerCandidate]

    public init(
        currentIdentity: CodexIdentity,
        expectedScopedEmail: String?,
        trustedCurrentUsageEmail: String?,
        dashboardSignedInEmail: String?,
        knownOwners: [CodexDashboardKnownOwnerCandidate])
    {
        self.currentIdentity = currentIdentity
        self.expectedScopedEmail = expectedScopedEmail
        self.trustedCurrentUsageEmail = trustedCurrentUsageEmail
        self.dashboardSignedInEmail = dashboardSignedInEmail
        self.knownOwners = knownOwners
    }
}

public struct CodexDashboardRoutingHints: Equatable, Sendable {
    public let targetEmail: String?
    public let lastKnownDashboardRoutingEmail: String?

    public init(targetEmail: String?, lastKnownDashboardRoutingEmail: String?) {
        self.targetEmail = targetEmail
        self.lastKnownDashboardRoutingEmail = lastKnownDashboardRoutingEmail
    }
}

public struct CodexDashboardAuthorityInput: Equatable, Sendable {
    public let sourceKind: CodexDashboardSourceKind
    public let proof: CodexDashboardOwnershipProofContext
    public let routing: CodexDashboardRoutingHints

    public init(
        sourceKind: CodexDashboardSourceKind,
        proof: CodexDashboardOwnershipProofContext,
        routing: CodexDashboardRoutingHints)
    {
        self.sourceKind = sourceKind
        self.proof = proof
        self.routing = routing
    }
}

public enum CodexDashboardDecisionReason: Equatable, Sendable {
    case exactProviderAccountMatch
    case trustedEmailMatchNoCompetingOwner
    case trustedContinuityNoCompetingOwner
    case wrongEmail(expected: String?, actual: String?)
    case sameEmailAmbiguity(email: String)
    case unresolvedWithoutTrustedEvidence
    case providerAccountMissingScopedEmail
    case providerAccountLacksExactOwnershipProof
    case missingDashboardSignedInEmail
}

public struct CodexDashboardAuthorityDecision: Equatable, Sendable {
    public let disposition: CodexDashboardDisposition
    public let reason: CodexDashboardDecisionReason
    public let allowedEffects: Set<CodexDashboardAllowedEffect>
    public let cleanup: Set<CodexDashboardCleanup>

    public init(
        disposition: CodexDashboardDisposition,
        reason: CodexDashboardDecisionReason,
        allowedEffects: Set<CodexDashboardAllowedEffect>,
        cleanup: Set<CodexDashboardCleanup>)
    {
        self.disposition = disposition
        self.reason = reason
        self.allowedEffects = allowedEffects
        self.cleanup = cleanup
    }
}

public enum CodexDashboardPolicyError: LocalizedError, Equatable, Sendable {
    case displayOnly(CodexDashboardAuthorityDecision)

    public var errorDescription: String? {
        switch self {
        case let .displayOnly(decision):
            decision.policyErrorDescription
        }
    }
}

public extension CodexDashboardAuthorityDecision {
    var policyErrorDescription: String {
        switch reason {
        case let .wrongEmail(expected, actual):
            var details: [String] = []
            if let expected {
                details.append(L("期望 %@", expected))
            }
            if let actual {
                details.append(L("实际 %@", actual))
            }
            if details.isEmpty {
                return L("OpenAI dashboard 属于错误账号。")
            }
            return L("OpenAI dashboard 属于错误账号（%@）。", details.joined(separator: ", "))
        case .unresolvedWithoutTrustedEvidence:
            return L("当前 Codex 身份未解析，且没有可信登录态可证明 dashboard 归属。")
        case .providerAccountMissingScopedEmail:
            return L("当前 Codex provider account 缺少 scoped email，无法证明 dashboard 归属。")
        case .providerAccountLacksExactOwnershipProof:
            return L("OpenAI dashboard 无法证明属于当前 provider account。")
        case .missingDashboardSignedInEmail:
            return L("OpenAI dashboard 未暴露登录邮箱，无法确认账号归属。")
        case let .sameEmailAmbiguity(email):
            return L("OpenAI dashboard 邮箱 %@ 同时属于多个已知账号，只能展示，不能附加到当前账号。", email)
        default:
            return L("OpenAI dashboard 被 Codex dashboard authority 拒绝。")
        }
    }

    func diagnosticCategory(authConfigured: Bool) -> String {
        switch reason {
        case .wrongEmail, .sameEmailAmbiguity, .providerAccountLacksExactOwnershipProof:
            return "configuration"
        case .unresolvedWithoutTrustedEvidence, .providerAccountMissingScopedEmail:
            return authConfigured ? "configuration" : "auth"
        case .missingDashboardSignedInEmail:
            return "auth"
        default:
            return "unknown"
        }
    }
}

public enum CodexDashboardAuthority {
    public static func evaluate(_ input: CodexDashboardAuthorityInput) -> CodexDashboardAuthorityDecision {
        let proof = input.proof
        let currentIdentity = normalizeIdentity(proof.currentIdentity)
        let expectedScopedEmail = CodexIdentityResolver.normalizeEmail(proof.expectedScopedEmail)
        let trustedCurrentUsageEmail = CodexIdentityResolver.normalizeEmail(proof.trustedCurrentUsageEmail)
        let dashboardSignedInEmail = CodexIdentityResolver.normalizeEmail(proof.dashboardSignedInEmail)
        let knownOwners = normalizeKnownOwners(proof.knownOwners)

        guard let dashboardSignedInEmail else {
            return makeDecision(
                disposition: .failClosed,
                reason: .missingDashboardSignedInEmail,
                sourceKind: input.sourceKind)
        }

        if let expectedScopedEmail, dashboardSignedInEmail != expectedScopedEmail {
            return makeDecision(
                disposition: .failClosed,
                reason: .wrongEmail(expected: expectedScopedEmail, actual: dashboardSignedInEmail),
                sourceKind: input.sourceKind)
        }

        switch currentIdentity {
        case let .providerAccount(id):
            let exactMatch = knownOwners.contains { candidate in
                candidate.identity == .providerAccount(id: id) && candidate.normalizedEmail == dashboardSignedInEmail
            }
            if exactMatch {
                return makeDecision(
                    disposition: .attach,
                    reason: .exactProviderAccountMatch,
                    sourceKind: input.sourceKind)
            }
            guard expectedScopedEmail != nil else {
                return makeDecision(
                    disposition: .failClosed,
                    reason: .providerAccountMissingScopedEmail,
                    sourceKind: input.sourceKind)
            }
            if knownOwnerCount(for: dashboardSignedInEmail, in: knownOwners) > 1 {
                return makeDecision(
                    disposition: .displayOnly,
                    reason: .sameEmailAmbiguity(email: dashboardSignedInEmail),
                    sourceKind: input.sourceKind)
            }
            return makeDecision(
                disposition: .failClosed,
                reason: .providerAccountLacksExactOwnershipProof,
                sourceKind: input.sourceKind)

        case let .emailOnly(normalizedEmail):
            guard dashboardSignedInEmail == normalizedEmail else {
                return makeDecision(
                    disposition: .failClosed,
                    reason: .wrongEmail(expected: normalizedEmail, actual: dashboardSignedInEmail),
                    sourceKind: input.sourceKind)
            }
            if knownOwnerCount(for: normalizedEmail, in: knownOwners) > 1 {
                return makeDecision(
                    disposition: .displayOnly,
                    reason: .sameEmailAmbiguity(email: normalizedEmail),
                    sourceKind: input.sourceKind)
            }
            return makeDecision(
                disposition: .attach,
                reason: .trustedEmailMatchNoCompetingOwner,
                sourceKind: input.sourceKind)

        case .unresolved:
            guard let trustedCurrentUsageEmail else {
                return makeDecision(
                    disposition: .failClosed,
                    reason: .unresolvedWithoutTrustedEvidence,
                    sourceKind: input.sourceKind)
            }
            guard dashboardSignedInEmail == trustedCurrentUsageEmail else {
                return makeDecision(
                    disposition: .failClosed,
                    reason: .wrongEmail(expected: trustedCurrentUsageEmail, actual: dashboardSignedInEmail),
                    sourceKind: input.sourceKind)
            }
            if knownOwnerCount(for: trustedCurrentUsageEmail, in: knownOwners) > 1 {
                return makeDecision(
                    disposition: .displayOnly,
                    reason: .sameEmailAmbiguity(email: trustedCurrentUsageEmail),
                    sourceKind: input.sourceKind)
            }
            return makeDecision(
                disposition: .attach,
                reason: .trustedContinuityNoCompetingOwner,
                sourceKind: input.sourceKind)
        }
    }

    private static func normalizeIdentity(_ identity: CodexIdentity) -> CodexIdentity {
        switch identity {
        case let .providerAccount(id):
            if let normalizedID = CodexIdentityResolver.normalizeAccountID(id) {
                return .providerAccount(id: normalizedID)
            }
            return .unresolved
        case let .emailOnly(normalizedEmail):
            if let normalizedEmail = CodexIdentityResolver.normalizeEmail(normalizedEmail) {
                return .emailOnly(normalizedEmail: normalizedEmail)
            }
            return .unresolved
        case .unresolved:
            return .unresolved
        }
    }

    private static func normalizeKnownOwners(
        _ candidates: [CodexDashboardKnownOwnerCandidate])
        -> Set<CodexDashboardKnownOwnerCandidate>
    {
        Set(candidates.map { candidate in
            CodexDashboardKnownOwnerCandidate(
                identity: normalizeIdentity(candidate.identity),
                normalizedEmail: CodexIdentityResolver.normalizeEmail(candidate.normalizedEmail))
        })
    }

    private static func knownOwnerCount(
        for email: String,
        in candidates: Set<CodexDashboardKnownOwnerCandidate>) -> Int
    {
        candidates.count { $0.normalizedEmail == email }
    }

    private static func makeDecision(
        disposition: CodexDashboardDisposition,
        reason: CodexDashboardDecisionReason,
        sourceKind: CodexDashboardSourceKind) -> CodexDashboardAuthorityDecision
    {
        CodexDashboardAuthorityDecision(
            disposition: disposition,
            reason: reason,
            allowedEffects: allowedEffects(disposition: disposition, sourceKind: sourceKind),
            cleanup: disposition == .attach ? [] : Set(CodexDashboardCleanup.allCases))
    }

    private static func allowedEffects(
        disposition: CodexDashboardDisposition,
        sourceKind: CodexDashboardSourceKind) -> Set<CodexDashboardAllowedEffect>
    {
        guard disposition == .attach else { return [] }
        switch sourceKind {
        case .liveWeb:
            return [.usageBackfill, .creditsAttachment, .refreshGuardSeed, .historicalBackfill]
        case .cachedDashboard:
            return [.cachedDashboardReuse]
        }
    }
}

public enum CodexDashboardAuthorityContext {
    public static func makeLiveWebInput(
        dashboard: OpenAIDashboardSnapshot,
        env: [String: String] = ProcessInfo.processInfo.environment,
        routingTargetEmail: String? = nil
    ) -> CodexDashboardAuthorityInput {
        let auth = authBackedAccount(env: env)
        return CodexDashboardAuthorityInput(
            sourceKind: .liveWeb,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: auth.identity,
                expectedScopedEmail: auth.email,
                trustedCurrentUsageEmail: nil,
                dashboardSignedInEmail: dashboard.signedInEmail,
                knownOwners: CodexManagedAccountDiscovery.dashboardKnownOwners(env: env)),
            routing: CodexDashboardRoutingHints(
                targetEmail: CodexIdentityResolver.normalizeEmail(routingTargetEmail),
                lastKnownDashboardRoutingEmail: nil))
    }

    public static func makeCachedDashboardInput(
        dashboard: OpenAIDashboardSnapshot,
        cachedAccountEmail: String,
        trustedUsageEmail: String?,
        sourceLabel: String,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexDashboardAuthorityInput {
        let auth = authBackedAccount(env: env)
        let trustedCurrentUsageEmail = shouldTrustUsageEmail(sourceLabel: sourceLabel) ? trustedUsageEmail : nil
        return CodexDashboardAuthorityInput(
            sourceKind: .cachedDashboard,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: auth.identity,
                expectedScopedEmail: auth.email,
                trustedCurrentUsageEmail: trustedCurrentUsageEmail,
                dashboardSignedInEmail: dashboard.signedInEmail,
                knownOwners: CodexManagedAccountDiscovery.dashboardKnownOwners(env: env)),
            routing: CodexDashboardRoutingHints(
                targetEmail: auth.email,
                lastKnownDashboardRoutingEmail: cachedAccountEmail))
    }

    public static func shouldTrustUsageEmail(sourceLabel: String) -> Bool {
        switch sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "codex-cli", "cli", "oauth":
            return true
        default:
            return false
        }
    }

    public static func authBackedAccount(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> CodexAuthBackedAccount {
        guard let credentials = try? CodexUsageFetcher.loadCredentials(env: env) else {
            return CodexAuthBackedAccount(identity: .unresolved, email: nil, plan: nil)
        }

        let payload = credentials.idToken.flatMap(CodexUsageFetcher.parseJWT)
        let profile = payload?["https://api.openai.com/profile"] as? [String: Any]
        let auth = payload?["https://api.openai.com/auth"] as? [String: Any]
        let email = CodexIdentityResolver.normalizeEmail(
            (payload?["email"] as? String) ?? (profile?["email"] as? String))
        let accountID = CodexIdentityResolver.normalizeAccountID(
            credentials.accountId
                ?? (auth?["chatgpt_account_id"] as? String)
                ?? (payload?["chatgpt_account_id"] as? String))
        let plan = CodexIdentityResolver.normalizeAccountID(
            (auth?["chatgpt_plan_type"] as? String) ?? (payload?["chatgpt_plan_type"] as? String))
        return CodexAuthBackedAccount(
            identity: CodexIdentityResolver.resolve(accountID: accountID, email: email),
            email: email,
            plan: plan)
    }
}
