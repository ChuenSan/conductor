import Foundation

/// 每百万 token 的单价（美元）。用于把 token 数估算成成本。
public struct ModelPricing: Sendable, Equatable {
    public let inputPerM: Double
    public let outputPerM: Double
    public let cacheWritePerM: Double
    public let cacheReadPerM: Double

    public init(inputPerM: Double, outputPerM: Double, cacheWritePerM: Double, cacheReadPerM: Double) {
        self.inputPerM = inputPerM
        self.outputPerM = outputPerM
        self.cacheWritePerM = cacheWritePerM
        self.cacheReadPerM = cacheReadPerM
    }

    /// 按模型名（子串匹配）查单价。命中不到时回退到一个保守的 Sonnet 档（估算）。
    /// 价格基于 2026 年公开价目表；第三方代理实际计费可能不同，故 UI 标注"估算"。
    public static func forModel(_ rawModel: String) -> ModelPricing {
        let m = rawModel.lowercased()
        // OpenAI / Codex
        if m.contains("gpt-5") || m.contains("codex") || m.contains("o4") || m.contains("o3") {
            if m.contains("mini") || m.contains("nano") {
                return ModelPricing(inputPerM: 0.25, outputPerM: 2.0, cacheWritePerM: 0.25, cacheReadPerM: 0.025)
            }
            return ModelPricing(inputPerM: 1.25, outputPerM: 10.0, cacheWritePerM: 1.25, cacheReadPerM: 0.125)
        }
        // Anthropic Claude
        if m.contains("opus") {
            // 旧款 Opus 4 / 4.1 为 $15/$75；当前 4.5+ 为 $5/$25。
            if m.contains("opus-4-1") || m.contains("opus-4-0") || m.contains("opus-4-2025") {
                return ModelPricing(inputPerM: 15, outputPerM: 75, cacheWritePerM: 18.75, cacheReadPerM: 1.5)
            }
            return ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5)
        }
        if m.contains("sonnet") {
            return ModelPricing(inputPerM: 3, outputPerM: 15, cacheWritePerM: 3.75, cacheReadPerM: 0.30)
        }
        if m.contains("haiku") {
            if m.contains("3-5") || m.contains("3.5") {
                return ModelPricing(inputPerM: 0.80, outputPerM: 4, cacheWritePerM: 1, cacheReadPerM: 0.08)
            }
            return ModelPricing(inputPerM: 1, outputPerM: 5, cacheWritePerM: 1.25, cacheReadPerM: 0.10)
        }
        if m.contains("gemini") {
            return ModelPricing(inputPerM: 1.25, outputPerM: 5, cacheWritePerM: 1.625, cacheReadPerM: 0.3125)
        }
        return ModelPricing(inputPerM: 3, outputPerM: 15, cacheWritePerM: 3.75, cacheReadPerM: 0.30)
    }

    public func cost(input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        (Double(input) * inputPerM
            + Double(output) * outputPerM
            + Double(cacheWrite) * cacheWritePerM
            + Double(cacheRead) * cacheReadPerM) / 1_000_000.0
    }
}

/// 一组 token 统计（可累加）。
public struct UsageTotals: Sendable, Equatable, Codable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var costUSD: Double = 0

    public init() {}

    public var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    public static func + (a: UsageTotals, b: UsageTotals) -> UsageTotals {
        var r = UsageTotals()
        r.inputTokens = a.inputTokens + b.inputTokens
        r.outputTokens = a.outputTokens + b.outputTokens
        r.cacheCreationTokens = a.cacheCreationTokens + b.cacheCreationTokens
        r.cacheReadTokens = a.cacheReadTokens + b.cacheReadTokens
        r.costUSD = a.costUSD + b.costUSD
        return r
    }

    public static func += (a: inout UsageTotals, b: UsageTotals) { a = a + b }
}

public enum UsageSource: String, Sendable, Codable, CaseIterable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

public struct ModelUsage: Sendable, Identifiable, Equatable, Codable {
    public let model: String
    public let source: UsageSource
    public let totals: UsageTotals
    public var id: String { "\(source.rawValue):\(model)" }
}

public struct DailyUsage: Sendable, Identifiable, Equatable, Codable {
    public let day: String   // yyyy-MM-dd
    public let totals: UsageTotals
    /// 当天按来源（Claude / Codex）细分，用于堆叠图。
    public let bySource: [UsageSource: UsageTotals]
    public var id: String { day }

    public init(day: String, totals: UsageTotals, bySource: [UsageSource: UsageTotals] = [:]) {
        self.day = day
        self.totals = totals
        self.bySource = bySource
    }
}

/// 某个项目（工作目录）的用量。
public struct ProjectUsage: Sendable, Identifiable, Equatable, Codable {
    /// 项目工作目录绝对路径（未知时为空串）。
    public let path: String
    public let totals: UsageTotals
    /// 按来源（Claude / Codex）细分，用于按 CLI 过滤。
    public let bySource: [UsageSource: UsageTotals]
    public var id: String { path }

    public init(path: String, totals: UsageTotals, bySource: [UsageSource: UsageTotals] = [:]) {
        self.path = path
        self.totals = totals
        self.bySource = bySource
    }
}

/// 完整用量报告。
public struct UsageReport: Sendable, Equatable, Codable {
    public var grand: UsageTotals = UsageTotals()
    public var byModel: [ModelUsage] = []
    public var byDay: [DailyUsage] = []
    public var byProject: [ProjectUsage] = []
    public var bySource: [UsageSource: UsageTotals] = [:]
    public var sessionsScanned: Int = 0
    /// 各来源的会话数。
    public var sessionsBySource: [UsageSource: Int] = [:]
    public var daysBack: Int = 0
    public var generatedAt: Date = Date()

    public init() {}

    public static func == (a: UsageReport, b: UsageReport) -> Bool {
        a.grand == b.grand && a.byModel == b.byModel && a.byDay == b.byDay
            && a.byProject == b.byProject
            && a.bySource == b.bySource && a.sessionsScanned == b.sessionsScanned
    }
}
