import Foundation

/// 富用量模型，移植自 CodexBar `UsageFetcher.swift` 的 RateWindow / NamedRateWindow /
/// ProviderCostSnapshot / UsageSnapshot。相比基础 `CodexUsageSnapshot`（仅 session/weekly 双窗），
/// 这里有三窗 + 额外命名窗 + 额度/美元(credits/cost)，能完整承载各 provider 的用量。
///
/// `RateWindow.title` 允许 provider 在快照里覆盖 catalog 的默认窗口标签。

/// 一个限流窗口（某周期的已用百分比 + 重置信息）。
public struct RateWindow: Codable, Sendable, Equatable {
    /// 显示标签，如 "Session" / "Weekly" / "Opus" / "Credits"；nil 时 UI 用位置默认名。
    public var title: String?
    /// 已用百分比 0...100。
    public var usedPercent: Double
    /// 窗口时长（分钟）；nil 表示无固定周期。
    public var windowMinutes: Int?
    /// 重置时刻。
    public var resetsAt: Date?
    /// 文本化的重置描述（部分 provider 只给文字）。
    public var resetDescription: String?

    public init(
        title: String? = nil,
        usedPercent: Double,
        windowMinutes: Int? = nil,
        resetsAt: Date? = nil,
        resetDescription: String? = nil)
    {
        self.title = title
        self.usedPercent = max(0, min(100, usedPercent))
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public var remainingPercent: Double { max(0, 100 - self.usedPercent) }
}

/// 额外的命名窗口（如 Claude 的 Daily Routines、各家的细分配额）。
public struct NamedRateWindow: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var window: RateWindow

    public init(id: String, title: String, window: RateWindow) {
        self.id = id
        self.title = title
        self.window = window
    }
}

/// 额度 / 消费快照（credits、按量计费、消费上限）。移植自 CodexBar `ProviderCostSnapshot`。
public struct ProviderCostSnapshot: Codable, Sendable, Equatable {
    /// 已用金额（主单位，如美元）。
    public var used: Double
    /// 上限金额；<= 0 表示无明确上限（仅显示余额/已用）。
    public var limit: Double
    /// 货币代码，如 "USD" / "CNY"。
    public var currencyCode: String
    /// 周期描述，如 "Monthly" / "Spend limit" / "Balance"。
    public var period: String?
    public var resetsAt: Date?

    public init(
        used: Double,
        limit: Double,
        currencyCode: String = "USD",
        period: String? = nil,
        resetsAt: Date? = nil)
    {
        self.used = used
        self.limit = limit
        self.currencyCode = currencyCode
        self.period = period
        self.resetsAt = resetsAt
    }

    public var hasLimit: Bool { self.limit > 0 }
    public var usedPercent: Double {
        guard self.limit > 0 else { return 0 }
        return max(0, min(100, self.used / self.limit * 100))
    }
}

public struct AmpWorkspaceBalance: Codable, Sendable, Equatable {
    public var name: String
    public var remaining: Double

    public init(name: String, remaining: Double) {
        self.name = name
        self.remaining = remaining
    }
}

public struct AmpUsageDetails: Codable, Sendable, Equatable {
    public var individualCredits: Double?
    public var workspaceBalances: [AmpWorkspaceBalance]

    public init(individualCredits: Double? = nil, workspaceBalances: [AmpWorkspaceBalance] = []) {
        self.individualCredits = individualCredits
        self.workspaceBalances = workspaceBalances
    }

    public var isEmpty: Bool {
        individualCredits == nil && workspaceBalances.isEmpty
    }
}

public struct CodexRateLimitResetCreditsSnapshot: Codable, Sendable, Equatable {
    public var credits: [CodexRateLimitResetCredit]
    public var availableCount: Int
    public var updatedAt: Date

    public init(credits: [CodexRateLimitResetCredit], availableCount: Int, updatedAt: Date) {
        self.credits = credits
        self.availableCount = max(0, availableCount)
        self.updatedAt = updatedAt
    }

    public var nextExpiringAvailableCredit: CodexRateLimitResetCredit? {
        credits
            .filter { credit in
                credit.status == .available && (credit.expiresAt ?? .distantPast) > updatedAt
            }
            .min { lhs, rhs in
                guard let lhsExpiresAt = lhs.expiresAt else { return false }
                guard let rhsExpiresAt = rhs.expiresAt else { return true }
                return lhsExpiresAt < rhsExpiresAt
            }
    }
}

public struct CodexRateLimitResetCredit: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var resetType: String
    public var status: CodexRateLimitResetCreditStatus
    public var grantedAt: Date
    public var expiresAt: Date?
    public var redeemStartedAt: Date?
    public var redeemedAt: Date?
    public var title: String?
    public var description: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case redeemStartedAt = "redeem_started_at"
        case redeemedAt = "redeemed_at"
        case title
        case description
    }

    public init(
        id: String,
        resetType: String,
        status: CodexRateLimitResetCreditStatus,
        grantedAt: Date,
        expiresAt: Date?,
        redeemStartedAt: Date?,
        redeemedAt: Date?,
        title: String?,
        description: String?)
    {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.redeemStartedAt = redeemStartedAt
        self.redeemedAt = redeemedAt
        self.title = title
        self.description = description
    }
}

public enum CodexRateLimitResetCreditStatus: Codable, Sendable, Equatable {
    case available
    case redeeming
    case redeemed
    case expired
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "available":
            self = .available
        case "redeeming":
            self = .redeeming
        case "redeemed":
            self = .redeemed
        case "expired":
            self = .expired
        default:
            self = .unknown(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var rawValue: String {
        switch self {
        case .available:
            "available"
        case .redeeming:
            "redeeming"
        case .redeemed:
            "redeemed"
        case .expired:
            "expired"
        case let .unknown(value):
            value
        }
    }
}

/// 一个 provider 的完整用量快照。移植自 CodexBar `UsageSnapshot`（取展示所需子集）。
public struct UsageSnapshot: Codable, Sendable, Equatable {
    /// 实际取数来源（如 api / web / cli / local）。区别于 CLI 请求的 source mode。
    public var sourceLabel: String?
    public var primary: RateWindow?
    public var secondary: RateWindow?
    public var tertiary: RateWindow?
    public var extraRateWindows: [NamedRateWindow]
    public var providerCost: ProviderCostSnapshot?
    /// Amp 专属余额明细：个人 credits 与 workspace balances。
    public var ampUsage: AmpUsageDetails?
    /// Claude Admin API 专属明细（最近 31 天成本/消息日桶）。通用 UI 可继续用 `providerCost` 展示摘要。
    public var claudeAdminAPIUsage: ClaudeAdminAPIUsageSnapshot?
    /// Codex 限额重置券，来自 ChatGPT backend `/wham/rate-limit-reset-credits`。
    public var codexResetCredits: CodexRateLimitResetCreditsSnapshot?
    /// 套餐 / 计划名（如 "Pro" / "Max" / "Free"）。
    public var planName: String?
    /// 账号标识（邮箱 / 组织），可空。
    public var accountLabel: String?
    public var updatedAt: Date

    public init(
        sourceLabel: String? = nil,
        primary: RateWindow? = nil,
        secondary: RateWindow? = nil,
        tertiary: RateWindow? = nil,
        extraRateWindows: [NamedRateWindow] = [],
        providerCost: ProviderCostSnapshot? = nil,
        ampUsage: AmpUsageDetails? = nil,
        claudeAdminAPIUsage: ClaudeAdminAPIUsageSnapshot? = nil,
        codexResetCredits: CodexRateLimitResetCreditsSnapshot? = nil,
        planName: String? = nil,
        accountLabel: String? = nil,
        updatedAt: Date = Date())
    {
        self.sourceLabel = Self.normalizedSourceLabel(sourceLabel)
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.extraRateWindows = extraRateWindows
        self.providerCost = providerCost
        self.ampUsage = ampUsage?.isEmpty == true ? nil : ampUsage
        self.claudeAdminAPIUsage = claudeAdminAPIUsage
        self.codexResetCredits = codexResetCredits
        self.planName = planName
        self.accountLabel = accountLabel
        self.updatedAt = updatedAt
    }

    public func withSourceLabel(_ sourceLabel: String?) -> UsageSnapshot {
        var copy = self
        copy.sourceLabel = Self.normalizedSourceLabel(sourceLabel)
        return copy
    }

    /// 是否完全没有可展示的数据。
    public var isEmpty: Bool {
        self.primary == nil && self.secondary == nil && self.tertiary == nil
            && self.extraRateWindows.isEmpty && self.providerCost == nil
            && self.ampUsage == nil
            && self.claudeAdminAPIUsage == nil && self.codexResetCredits == nil
    }

    /// 所有窗口（主/次/三 + 额外）按显示顺序展开，给 UI 迭代用。
    public var allWindows: [(title: String, window: RateWindow)] {
        var out: [(String, RateWindow)] = []
        if let primary { out.append((primary.title ?? L("会话"), primary)) }
        if let secondary { out.append((secondary.title ?? L("本周"), secondary)) }
        if let tertiary { out.append((tertiary.title ?? L("其它"), tertiary)) }
        for extra in self.extraRateWindows { out.append((extra.title, extra.window)) }
        return out
    }

    private static func normalizedSourceLabel(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}

public extension UsageSnapshot {
    /// 从 `CodexUsageSnapshot` 适配到通用 provider 用量模型。
    init(codexSnapshot snapshot: CodexUsageSnapshot) {
        func window(_ w: CodexUsageSnapshot.Window?, _ title: String) -> RateWindow? {
            guard let w else { return nil }
            return RateWindow(
                title: title,
                usedPercent: Double(w.usedPercent),
                windowMinutes: w.windowSeconds > 0 ? w.windowSeconds / 60 : nil,
                resetsAt: w.resetAt)
        }
        self.init(
            sourceLabel: snapshot.sourceLabel,
            primary: window(snapshot.session, L("会话")),
            secondary: window(snapshot.weekly, L("本周")),
            extraRateWindows: snapshot.extraRateWindows,
            providerCost: snapshot.providerCost,
            ampUsage: snapshot.ampUsage,
            codexResetCredits: snapshot.codexResetCredits,
            planName: snapshot.planType,
            accountLabel: snapshot.accountLabel)
    }
}
