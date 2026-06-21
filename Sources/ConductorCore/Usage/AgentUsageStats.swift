import Foundation

/// 每百万 token 的单价（美元）。用于把 token 数估算成成本。
public struct ModelPricing: Sendable, Equatable {
    private static let codexPriorityInputTokenLimit = 272_000

    public let inputPerM: Double
    public let outputPerM: Double
    public let cacheWritePerM: Double
    public let cacheReadPerM: Double
    public let thresholdTokens: Int?
    public let inputPerMAboveThreshold: Double?
    public let outputPerMAboveThreshold: Double?
    public let cacheWritePerMAboveThreshold: Double?
    public let cacheReadPerMAboveThreshold: Double?
    public let displayLabel: String?

    public init(
        inputPerM: Double,
        outputPerM: Double,
        cacheWritePerM: Double,
        cacheReadPerM: Double,
        thresholdTokens: Int? = nil,
        inputPerMAboveThreshold: Double? = nil,
        outputPerMAboveThreshold: Double? = nil,
        cacheWritePerMAboveThreshold: Double? = nil,
        cacheReadPerMAboveThreshold: Double? = nil,
        displayLabel: String? = nil)
    {
        self.inputPerM = inputPerM
        self.outputPerM = outputPerM
        self.cacheWritePerM = cacheWritePerM
        self.cacheReadPerM = cacheReadPerM
        self.thresholdTokens = thresholdTokens
        self.inputPerMAboveThreshold = inputPerMAboveThreshold
        self.outputPerMAboveThreshold = outputPerMAboveThreshold
        self.cacheWritePerMAboveThreshold = cacheWritePerMAboveThreshold
        self.cacheReadPerMAboveThreshold = cacheReadPerMAboveThreshold
        let trimmedDisplayLabel = displayLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayLabel = trimmedDisplayLabel.isEmpty ? nil : trimmedDisplayLabel
    }

    public static func builtInPricingFingerprint() -> String {
        var parts = [
            "codexPriorityInputTokenLimit=\(codexPriorityInputTokenLimit)",
            "claudeFullContextStandardPricingCutoff=\(Int(claudeFullContextStandardPricingCutoff.timeIntervalSince1970))",
        ]
        for model in codexBuiltinPricing.keys.sorted() {
            if let pricing = codexBuiltinPricing[model] {
                parts.append(pricingFingerprintLine(provider: "codex", model: model, pricing: pricing))
            }
        }
        for model in codexPriorityModelKeys {
            if let pricing = codexPriorityForModel(model) {
                parts.append(pricingFingerprintLine(provider: "codex-priority", model: model, pricing: pricing))
            }
        }
        for model in claudeBuiltinPricing.keys.sorted() {
            if let pricing = claudeBuiltinPricing[model] {
                parts.append(pricingFingerprintLine(provider: "claude", model: model, pricing: pricing))
            }
        }
        for model in claudeHistoricalLongContextPricing.keys.sorted() {
            if let pricing = claudeHistoricalLongContextPricing[model] {
                parts.append(pricingFingerprintLine(provider: "claude-historical", model: model, pricing: pricing))
            }
        }
        return parts.joined(separator: "\n")
    }

    /// 按模型名（子串匹配）查单价。命中不到时回退到一个保守的 Sonnet 档（估算）。
    /// 价格基于 2026 年公开价目表；第三方代理实际计费可能不同，故 UI 标注"估算"。
    public static func forModel(
        _ rawModel: String,
        cacheRoot: URL? = nil,
        pricingDate: Date? = nil) -> ModelPricing
    {
        let m = rawModel.lowercased()
        if let pricingDate,
           let datedClaudePricing = claudeDatedBuiltinPricing(for: rawModel, pricingDate: pricingDate)
        {
            return datedClaudePricing
        }
        if let providerID = modelsDevProviderID(for: m),
           let lookup = ModelsDevPricingPipeline.lookup(providerID: providerID, modelID: rawModel, cacheRoot: cacheRoot)
        {
            return ModelPricing(modelsDev: lookup.pricing, fallback: fallbackForModel(rawModel))
        }
        return fallbackForModel(rawModel)
    }

    public static func codexDisplayLabel(_ rawModel: String) -> String? {
        codexBuiltinPricing[normalizedCodexBuiltinKey(rawModel)]?.displayLabel
    }

    static func normalizedCodexModel(_ rawModel: String) -> String {
        normalizedCodexBuiltinKey(rawModel)
    }

    static func normalizedClaudeModel(_ rawModel: String) -> String {
        normalizedClaudeBuiltinKey(rawModel)
    }

    static func codexBuiltInPricing(for rawModel: String) -> ModelPricing? {
        codexBuiltinPricing[normalizedCodexBuiltinKey(rawModel)]
    }

    static func claudeBuiltInPricing(for rawModel: String, pricingDate: Date? = nil) -> ModelPricing? {
        let key = normalizedClaudeBuiltinKey(rawModel)
        if let pricingDate,
           claudeHistoricalLongContextPricing[key] != nil
        {
            return claudeDatedBuiltinPricing(for: rawModel, pricingDate: pricingDate)
        }
        return claudeBuiltinPricing[key]
    }

    static func pricingFromModelsDev(_ modelsDev: ModelsDevPricingInfo, fallback: ModelPricing) -> ModelPricing {
        ModelPricing(modelsDev: modelsDev, fallback: fallback)
    }

    private static func fallbackForModel(_ rawModel: String) -> ModelPricing {
        let m = rawModel.lowercased()
        // OpenAI / Codex
        if let codexPricing = codexBuiltinPricing[normalizedCodexBuiltinKey(rawModel)] {
            return codexPricing
        }
        if m.contains("gpt-5") || m.contains("codex") || m.contains("o4") || m.contains("o3") {
            if m.contains("mini") || m.contains("nano") {
                return ModelPricing(inputPerM: 0.25, outputPerM: 2.0, cacheWritePerM: 0.25, cacheReadPerM: 0.025)
            }
            return ModelPricing(inputPerM: 1.25, outputPerM: 10.0, cacheWritePerM: 1.25, cacheReadPerM: 0.125)
        }
        // Anthropic Claude
        if let claudePricing = claudeBuiltinPricing[normalizedClaudeBuiltinKey(rawModel)] {
            return claudePricing
        }
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

    private static let claudeSonnet4LongContextPricing = ModelPricing(
        inputPerM: 3,
        outputPerM: 15,
        cacheWritePerM: 3.75,
        cacheReadPerM: 0.30,
        thresholdTokens: 200_000,
        inputPerMAboveThreshold: 6,
        outputPerMAboveThreshold: 22.5,
        cacheWritePerMAboveThreshold: 7.5,
        cacheReadPerMAboveThreshold: 0.6)

    private static let claudeBuiltinPricing: [String: ModelPricing] = [
        "claude-fable-5": ModelPricing(inputPerM: 10, outputPerM: 50, cacheWritePerM: 12.5, cacheReadPerM: 1),
        "claude-haiku-4-5-20251001": ModelPricing(inputPerM: 1, outputPerM: 5, cacheWritePerM: 1.25, cacheReadPerM: 0.10),
        "claude-haiku-4-5": ModelPricing(inputPerM: 1, outputPerM: 5, cacheWritePerM: 1.25, cacheReadPerM: 0.10),
        "claude-opus-4-5-20251101": ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5),
        "claude-opus-4-5": ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5),
        "claude-opus-4-6-20260205": ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5),
        "claude-opus-4-6": ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5),
        "claude-opus-4-7": ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5),
        "claude-opus-4-8": ModelPricing(inputPerM: 5, outputPerM: 25, cacheWritePerM: 6.25, cacheReadPerM: 0.5),
        "claude-sonnet-4-5": claudeSonnet4LongContextPricing,
        "claude-sonnet-4-5-20250929": claudeSonnet4LongContextPricing,
        "claude-sonnet-4-6": ModelPricing(inputPerM: 3, outputPerM: 15, cacheWritePerM: 3.75, cacheReadPerM: 0.30),
        "claude-opus-4-20250514": ModelPricing(inputPerM: 15, outputPerM: 75, cacheWritePerM: 18.75, cacheReadPerM: 1.5),
        "claude-opus-4-1": ModelPricing(inputPerM: 15, outputPerM: 75, cacheWritePerM: 18.75, cacheReadPerM: 1.5),
        "claude-sonnet-4-20250514": claudeSonnet4LongContextPricing,
    ]

    private static let claudeHistoricalLongContextPricing: [String: ModelPricing] = [
        "claude-opus-4-6": ModelPricing(
            inputPerM: 5,
            outputPerM: 25,
            cacheWritePerM: 6.25,
            cacheReadPerM: 0.5,
            thresholdTokens: 200_000,
            inputPerMAboveThreshold: 10,
            outputPerMAboveThreshold: 37.5,
            cacheWritePerMAboveThreshold: 12.5,
            cacheReadPerMAboveThreshold: 1),
        "claude-sonnet-4-6": ModelPricing(
            inputPerM: 3,
            outputPerM: 15,
            cacheWritePerM: 3.75,
            cacheReadPerM: 0.30,
            thresholdTokens: 200_000,
            inputPerMAboveThreshold: 6,
            outputPerMAboveThreshold: 22.5,
            cacheWritePerMAboveThreshold: 7.5,
            cacheReadPerMAboveThreshold: 0.6),
    ]

    private static let codexBuiltinPricing: [String: ModelPricing] = [
        "gpt-5": ModelPricing(inputPerM: 1.25, outputPerM: 10, cacheWritePerM: 1.25, cacheReadPerM: 0.125),
        "gpt-5-codex": ModelPricing(inputPerM: 1.25, outputPerM: 10, cacheWritePerM: 1.25, cacheReadPerM: 0.125),
        "gpt-5-mini": ModelPricing(inputPerM: 0.25, outputPerM: 2, cacheWritePerM: 0.25, cacheReadPerM: 0.025),
        "gpt-5-nano": ModelPricing(inputPerM: 0.05, outputPerM: 0.4, cacheWritePerM: 0.05, cacheReadPerM: 0.005),
        "gpt-5-pro": ModelPricing(inputPerM: 15, outputPerM: 120, cacheWritePerM: 15, cacheReadPerM: 15),
        "gpt-5.1": ModelPricing(inputPerM: 1.25, outputPerM: 10, cacheWritePerM: 1.25, cacheReadPerM: 0.125),
        "gpt-5.1-codex": ModelPricing(inputPerM: 1.25, outputPerM: 10, cacheWritePerM: 1.25, cacheReadPerM: 0.125),
        "gpt-5.1-codex-max": ModelPricing(inputPerM: 1.25, outputPerM: 10, cacheWritePerM: 1.25, cacheReadPerM: 0.125),
        "gpt-5.1-codex-mini": ModelPricing(inputPerM: 0.25, outputPerM: 2, cacheWritePerM: 0.25, cacheReadPerM: 0.025),
        "gpt-5.2": ModelPricing(inputPerM: 1.75, outputPerM: 14, cacheWritePerM: 1.75, cacheReadPerM: 0.175),
        "gpt-5.2-codex": ModelPricing(inputPerM: 1.75, outputPerM: 14, cacheWritePerM: 1.75, cacheReadPerM: 0.175),
        "gpt-5.2-pro": ModelPricing(inputPerM: 21, outputPerM: 168, cacheWritePerM: 21, cacheReadPerM: 21),
        "gpt-5.3-codex": ModelPricing(inputPerM: 1.75, outputPerM: 14, cacheWritePerM: 1.75, cacheReadPerM: 0.175),
        "gpt-5.3-codex-spark": ModelPricing(
            inputPerM: 0,
            outputPerM: 0,
            cacheWritePerM: 0,
            cacheReadPerM: 0,
            displayLabel: "Research Preview"),
        "gpt-5.4": ModelPricing(
            inputPerM: 2.5,
            outputPerM: 15,
            cacheWritePerM: 2.5,
            cacheReadPerM: 0.25,
            thresholdTokens: 272_000,
            inputPerMAboveThreshold: 5,
            outputPerMAboveThreshold: 22.5,
            cacheWritePerMAboveThreshold: 5,
            cacheReadPerMAboveThreshold: 0.5),
        "gpt-5.4-mini": ModelPricing(inputPerM: 0.75, outputPerM: 4.5, cacheWritePerM: 0.75, cacheReadPerM: 0.075),
        "gpt-5.4-nano": ModelPricing(inputPerM: 0.20, outputPerM: 1.25, cacheWritePerM: 0.20, cacheReadPerM: 0.020),
        "gpt-5.4-pro": ModelPricing(inputPerM: 30, outputPerM: 180, cacheWritePerM: 30, cacheReadPerM: 30),
        "gpt-5.5": ModelPricing(
            inputPerM: 5,
            outputPerM: 30,
            cacheWritePerM: 5,
            cacheReadPerM: 0.5,
            thresholdTokens: 272_000,
            inputPerMAboveThreshold: 10,
            outputPerMAboveThreshold: 45,
            cacheWritePerMAboveThreshold: 10,
            cacheReadPerMAboveThreshold: 1),
        "gpt-5.5-pro": ModelPricing(inputPerM: 30, outputPerM: 180, cacheWritePerM: 30, cacheReadPerM: 30),
    ]

    private static let codexPriorityModelKeys = [
        "gpt-5.4",
        "gpt-5.4-mini",
        "gpt-5.5",
    ]

    private static func normalizedCodexBuiltinKey(_ rawModel: String) -> String {
        var trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("openai/") {
            trimmed = String(trimmed.dropFirst("openai/".count))
        }
        if codexBuiltinPricing[trimmed] != nil {
            return trimmed
        }
        if let datedSuffix = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<datedSuffix.lowerBound])
            if codexBuiltinPricing[base] != nil {
                return base
            }
        }
        return trimmed
    }

    private init(modelsDev: ModelsDevPricingInfo, fallback: ModelPricing) {
        self.init(
            inputPerM: modelsDev.inputCostPerM,
            outputPerM: modelsDev.outputCostPerM,
            cacheWritePerM: modelsDev.cacheCreationInputCostPerM ?? modelsDev.inputCostPerM,
            cacheReadPerM: modelsDev.cacheReadInputCostPerM ?? modelsDev.inputCostPerM,
            thresholdTokens: modelsDev.thresholdTokens ?? fallback.thresholdTokens,
            inputPerMAboveThreshold: modelsDev.inputCostPerMAboveThreshold,
            outputPerMAboveThreshold: modelsDev.outputCostPerMAboveThreshold,
            cacheWritePerMAboveThreshold: modelsDev.cacheCreationInputCostPerMAboveThreshold,
            cacheReadPerMAboveThreshold: modelsDev.cacheReadInputCostPerMAboveThreshold,
            displayLabel: fallback.displayLabel)
    }

    private static func modelsDevProviderID(for normalizedModel: String) -> String? {
        if normalizedModel.contains("claude") { return "anthropic" }
        if normalizedModel.contains("gpt") || normalizedModel.contains("codex") ||
            normalizedModel.contains("o3") || normalizedModel.contains("o4")
        {
            return "openai"
        }
        return nil
    }

    private static let claudeFullContextStandardPricingCutoff = Date(timeIntervalSince1970: 1_773_360_000)

    private static func claudeDatedBuiltinPricing(for rawModel: String, pricingDate: Date) -> ModelPricing? {
        let key = normalizedClaudeBuiltinKey(rawModel)
        guard claudeHistoricalLongContextPricing[key] != nil else { return nil }
        if pricingDate < claudeFullContextStandardPricingCutoff {
            return claudeHistoricalLongContextPricing[key]
        }
        return claudeBuiltinPricing[key]
    }

    private static func normalizedClaudeBuiltinKey(_ rawModel: String) -> String {
        var trimmed = rawModel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("anthropic.") {
            trimmed = String(trimmed.dropFirst("anthropic.".count))
        }
        if let lastDot = trimmed.lastIndex(of: "."), trimmed.contains("claude-") {
            let tail = String(trimmed[trimmed.index(after: lastDot)...])
            if tail.hasPrefix("claude-") {
                trimmed = tail
            }
        }
        if let version = trimmed.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
            trimmed.removeSubrange(version)
        }
        if claudeBuiltinPricing[trimmed] != nil {
            return trimmed
        }
        if let compactDate = trimmed.range(of: #"-\d{8}$"#, options: .regularExpression) {
            let base = String(trimmed[..<compactDate.lowerBound])
            if claudeBuiltinPricing[base] != nil {
                return base
            }
        }
        return trimmed
    }

    /// Codex Fast / priority tier pricing. Nil means the model has no known priority tier.
    public static func codexPriorityForModel(_ rawModel: String, inputTokens: Int? = nil) -> ModelPricing? {
        if let inputTokens, max(0, inputTokens) > codexPriorityInputTokenLimit {
            return nil
        }
        switch normalizedCodexBuiltinKey(rawModel) {
        case "gpt-5.5":
            return ModelPricing(inputPerM: 12.5, outputPerM: 75, cacheWritePerM: 12.5, cacheReadPerM: 1.25)
        case "gpt-5.4-mini":
            return ModelPricing(inputPerM: 1.5, outputPerM: 9, cacheWritePerM: 1.5, cacheReadPerM: 0.15)
        case "gpt-5.4":
            return ModelPricing(inputPerM: 5, outputPerM: 30, cacheWritePerM: 5, cacheReadPerM: 0.5)
        default:
            return nil
        }
    }

    private static func pricingFingerprintLine(provider: String, model: String, pricing: ModelPricing) -> String {
        [
            "\(provider)|model=\(model)",
            optionalPricingFingerprint(pricing.inputPerM),
            optionalPricingFingerprint(pricing.outputPerM),
            optionalPricingFingerprint(pricing.cacheWritePerM),
            optionalPricingFingerprint(pricing.cacheReadPerM),
            pricing.thresholdTokens.map(String.init) ?? "nil",
            optionalPricingFingerprint(pricing.inputPerMAboveThreshold),
            optionalPricingFingerprint(pricing.outputPerMAboveThreshold),
            optionalPricingFingerprint(pricing.cacheWritePerMAboveThreshold),
            optionalPricingFingerprint(pricing.cacheReadPerMAboveThreshold),
            pricing.displayLabel ?? "nil",
        ].joined(separator: "|")
    }

    private static func optionalPricingFingerprint(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.17g", value)
    }

    public func cost(input: Int, output: Int, cacheWrite: Int, cacheRead: Int, cacheWrite1h: Int = 0) -> Double {
        let cacheWrite1h = min(max(0, cacheWrite1h), max(0, cacheWrite))
        let cacheWrite5m = max(0, cacheWrite - cacheWrite1h)
        let usesThreshold = thresholdTokens.map { input + cacheWrite + cacheRead > $0 } ?? false
        let inputRate = usesThreshold ? inputPerMAboveThreshold ?? inputPerM : inputPerM
        let outputRate = usesThreshold ? outputPerMAboveThreshold ?? outputPerM : outputPerM
        let cacheWriteRate = usesThreshold ? cacheWritePerMAboveThreshold ?? cacheWritePerM : cacheWritePerM
        let cacheReadRate = usesThreshold ? cacheReadPerMAboveThreshold ?? cacheReadPerM : cacheReadPerM
        return (Double(input) * inputRate
            + Double(output) * outputRate
            + Double(cacheWrite5m) * cacheWriteRate
            + Double(cacheWrite1h) * inputRate * 2
            + Double(cacheRead) * cacheReadRate) / 1_000_000.0
    }
}

public enum CostUsagePricing {
    private static let codexModelsDevProviderID = "openai"
    private static let claudeModelsDevProviderID = "anthropic"

    public static func normalizeCodexModel(_ raw: String) -> String {
        ModelPricing.normalizedCodexModel(raw)
    }

    public static func normalizeClaudeModel(_ raw: String) -> String {
        ModelPricing.normalizedClaudeModel(raw)
    }

    public static func codexDisplayLabel(model: String) -> String? {
        ModelPricing.codexDisplayLabel(model)
    }

    public static func codexCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        let fallback = ModelPricing.codexBuiltInPricing(for: model)
        let pricing = self.modelsDevPricing(
            providerID: self.codexModelsDevProviderID,
            model: model,
            catalog: modelsDevCatalog,
            cacheRoot: modelsDevCacheRoot,
            fallback: fallback)
            ?? fallback
        guard let pricing else { return nil }
        return self.codexCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens)
    }

    public static func codexPriorityCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int = 0,
        outputTokens: Int) -> Double?
    {
        guard let pricing = ModelPricing.codexPriorityForModel(model, inputTokens: inputTokens) else {
            return nil
        }
        return self.codexCostUSD(
            pricing: pricing,
            inputTokens: inputTokens,
            cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens)
    }

    public static func claudeCostUSD(
        model: String,
        inputTokens: Int,
        cacheReadInputTokens: Int,
        cacheCreationInputTokens: Int,
        cacheCreationInputTokens1h: Int = 0,
        outputTokens: Int,
        pricingDate: Date? = nil,
        modelsDevCatalog: ModelsDevCatalog? = nil,
        modelsDevCacheRoot: URL? = nil) -> Double?
    {
        if let pricingDate,
           let pricing = ModelPricing.claudeBuiltInPricing(for: model, pricingDate: pricingDate)
        {
            return pricing.cost(
                input: max(0, inputTokens),
                output: max(0, outputTokens),
                cacheWrite: max(0, cacheCreationInputTokens),
                cacheRead: max(0, cacheReadInputTokens),
                cacheWrite1h: max(0, cacheCreationInputTokens1h))
        }

        let fallback = ModelPricing.claudeBuiltInPricing(for: model)
        let pricing = self.modelsDevPricing(
            providerID: self.claudeModelsDevProviderID,
            model: model,
            catalog: modelsDevCatalog,
            cacheRoot: modelsDevCacheRoot,
            fallback: fallback)
            ?? fallback
        guard let pricing else { return nil }
        return pricing.cost(
            input: max(0, inputTokens),
            output: max(0, outputTokens),
            cacheWrite: max(0, cacheCreationInputTokens),
            cacheRead: max(0, cacheReadInputTokens),
            cacheWrite1h: max(0, cacheCreationInputTokens1h))
    }

    public static func modelsDevCatalog(now: Date = Date(), cacheRoot: URL? = nil) -> ModelsDevCatalog? {
        ModelsDevCache.load(now: now, cacheRoot: cacheRoot).artifact?.catalog
    }

    private static func codexCostUSD(
        pricing: ModelPricing,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int) -> Double
    {
        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let uncached = max(0, inputTokens - cached)
        return pricing.cost(
            input: uncached,
            output: max(0, outputTokens),
            cacheWrite: 0,
            cacheRead: cached)
    }

    private static func modelsDevPricing(
        providerID: String,
        model: String,
        catalog: ModelsDevCatalog?,
        cacheRoot: URL?,
        fallback: ModelPricing?) -> ModelPricing?
    {
        let lookup = catalog?.pricing(providerID: providerID, modelID: model)
            ?? ModelsDevPricingPipeline.lookup(
                providerID: providerID,
                modelID: model,
                cacheRoot: cacheRoot)
        guard let pricing = lookup?.pricing else { return nil }
        return ModelPricing.pricingFromModelsDev(
            pricing,
            fallback: fallback ?? ModelPricing.forModel(model, cacheRoot: cacheRoot))
    }
}

/// 一组 token 统计（可累加）。
public struct UsageTotals: Sendable, Equatable, Codable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    public var cacheCreationTokens: Int = 0
    public var cacheReadTokens: Int = 0
    public var costUSD: Double = 0
    public var requestCount: Int = 0

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case inputTokens
        case outputTokens
        case cacheCreationTokens
        case cacheReadTokens
        case costUSD
        case requestCount
        case requests
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
        self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        self.cacheCreationTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
        self.cacheReadTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
        self.costUSD = try container.decodeIfPresent(Double.self, forKey: .costUSD) ?? 0
        self.requestCount =
            try container.decodeIfPresent(Int.self, forKey: .requestCount)
            ?? container.decodeIfPresent(Int.self, forKey: .requests)
            ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(cacheCreationTokens, forKey: .cacheCreationTokens)
        try container.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try container.encode(costUSD, forKey: .costUSD)
        try container.encode(requestCount, forKey: .requestCount)
    }

    public var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    public static func + (a: UsageTotals, b: UsageTotals) -> UsageTotals {
        var r = UsageTotals()
        r.inputTokens = a.inputTokens + b.inputTokens
        r.outputTokens = a.outputTokens + b.outputTokens
        r.cacheCreationTokens = a.cacheCreationTokens + b.cacheCreationTokens
        r.cacheReadTokens = a.cacheReadTokens + b.cacheReadTokens
        r.costUSD = a.costUSD + b.costUSD
        r.requestCount = a.requestCount + b.requestCount
        return r
    }

    public static func += (a: inout UsageTotals, b: UsageTotals) { a = a + b }
}

public enum UsageSource: String, Sendable, Codable, CaseIterable {
    case claude
    case codex
    case vertexai
    case bedrock

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .vertexai: return "Vertex AI"
        case .bedrock: return "AWS Bedrock"
        }
    }
}

public struct ModelUsage: Sendable, Identifiable, Equatable, Codable {
    public let model: String
    public let source: UsageSource
    public let totals: UsageTotals
    public var id: String { "\(source.rawValue):\(model)" }
}

/// 某一天内某个来源/模型的成本明细。对齐 CodexBar `CostUsageDailyReport.ModelBreakdown`
/// 的展示语义，同时保留 Conductor 的来源维度，方便 CLI/UI 按 Codex/Claude 过滤。
public struct UsageModelBreakdown: Sendable, Identifiable, Equatable, Codable {
    public let model: String
    public let source: UsageSource
    public let totals: UsageTotals
    public let standardCostUSD: Double?
    public let priorityCostUSD: Double?
    public let standardTokens: Int?
    public let priorityTokens: Int?

    public var id: String { "\(source.rawValue):\(model)" }

    public init(
        model: String,
        source: UsageSource,
        totals: UsageTotals,
        standardCostUSD: Double? = nil,
        priorityCostUSD: Double? = nil,
        standardTokens: Int? = nil,
        priorityTokens: Int? = nil
    ) {
        self.model = model
        self.source = source
        self.totals = totals
        self.standardCostUSD = standardCostUSD
        self.priorityCostUSD = priorityCostUSD
        self.standardTokens = standardTokens
        self.priorityTokens = priorityTokens
    }
}

public struct DailyUsage: Sendable, Identifiable, Equatable, Codable {
    public let day: String   // yyyy-MM-dd
    public let totals: UsageTotals
    /// 当天按来源（Claude / Codex）细分，用于堆叠图。
    public let bySource: [UsageSource: UsageTotals]
    /// 当天按模型细分的成本/Token 明细，对齐 CodexBar daily `modelBreakdowns`。
    public let modelBreakdowns: [UsageModelBreakdown]
    public var id: String { day }

    public init(
        day: String,
        totals: UsageTotals,
        bySource: [UsageSource: UsageTotals] = [:],
        modelBreakdowns: [UsageModelBreakdown] = []
    ) {
        self.day = day
        self.totals = totals
        self.bySource = bySource
        self.modelBreakdowns = modelBreakdowns
    }
}

/// 某个月内的成本摘要。对齐 CodexBar `CostUsageMonthlyReport.Entry` 的 month/token/cost 语义，
/// 同时保留来源维度供 Conductor UI/CLI 过滤。
public struct MonthlyUsage: Sendable, Identifiable, Equatable, Codable {
    public let month: String   // yyyy-MM
    public let totals: UsageTotals
    public let bySource: [UsageSource: UsageTotals]
    public var id: String { month }

    public init(
        month: String,
        totals: UsageTotals,
        bySource: [UsageSource: UsageTotals] = [:]
    ) {
        self.month = month
        self.totals = totals
        self.bySource = bySource
    }
}

/// 单个本机会话的成本摘要。对齐 CodexBar `CostUsageSessionReport.Entry` 的
/// session/token/cost/lastActivity 语义，并保留 Conductor 的来源、项目和模型维度。
public struct SessionUsage: Sendable, Identifiable, Equatable, Codable {
    public let session: String
    public let source: UsageSource
    public let project: String
    public let totals: UsageTotals
    public let lastActivity: String?
    public let models: [String]
    public var id: String { "\(source.rawValue):\(session)" }

    public init(
        session: String,
        source: UsageSource,
        project: String = "",
        totals: UsageTotals,
        lastActivity: String? = nil,
        models: [String] = [])
    {
        self.session = session
        self.source = source
        self.project = project
        self.totals = totals
        self.lastActivity = lastActivity
        self.models = models
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

public enum UsageReportSource: String, Sendable, Equatable, Codable {
    case directScan = "direct_scan"
    case fileCacheScan = "file_cache_scan"
    case reportCache = "report_cache"
    case uiCache = "ui_cache"
    case fallbackScan = "fallback_scan"

    public var label: String {
        switch self {
        case .directScan: return "fresh scan"
        case .fileCacheScan: return "file-cache scan"
        case .reportCache: return "cost cache"
        case .uiCache: return "UI cache"
        case .fallbackScan: return "fallback scan"
        }
    }
}

public struct UsageReportSourceInfo: Sendable, Equatable, Codable {
    public let source: UsageReportSource
    public let loadedAt: Date
    public let cacheAgeSeconds: TimeInterval?
    public let cachePath: String?
    public let reason: String?

    public init(
        source: UsageReportSource,
        loadedAt: Date = Date(),
        cacheAgeSeconds: TimeInterval? = nil,
        cachePath: String? = nil,
        reason: String? = nil)
    {
        self.source = source
        self.loadedAt = loadedAt
        self.cacheAgeSeconds = cacheAgeSeconds
        self.cachePath = cachePath
        self.reason = reason
    }
}

/// 完整用量报告。
public struct UsageReport: Sendable, Equatable, Codable {
    public var grand: UsageTotals = UsageTotals()
    public var byModel: [ModelUsage] = []
    public var byDay: [DailyUsage] = []
    public var byMonth: [MonthlyUsage] = []
    public var bySession: [SessionUsage] = []
    public var byProject: [ProjectUsage] = []
    public var bySource: [UsageSource: UsageTotals] = [:]
    public var sessionsScanned: Int = 0
    /// 各来源的会话数。
    public var sessionsBySource: [UsageSource: Int] = [:]
    public var daysBack: Int = 0
    public var generatedAt: Date = Date()
    public var sourceInfo: UsageReportSourceInfo?

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case grand
        case byModel
        case byDay
        case byMonth
        case bySession
        case byProject
        case bySource
        case sessionsScanned
        case sessionsBySource
        case daysBack
        case generatedAt
        case sourceInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.grand = try container.decodeIfPresent(UsageTotals.self, forKey: .grand) ?? UsageTotals()
        self.byModel = try container.decodeIfPresent([ModelUsage].self, forKey: .byModel) ?? []
        self.byDay = try container.decodeIfPresent([DailyUsage].self, forKey: .byDay) ?? []
        self.byMonth = try container.decodeIfPresent([MonthlyUsage].self, forKey: .byMonth) ?? []
        self.bySession = try container.decodeIfPresent([SessionUsage].self, forKey: .bySession) ?? []
        self.byProject = try container.decodeIfPresent([ProjectUsage].self, forKey: .byProject) ?? []
        self.bySource = (try? container.decodeIfPresent([UsageSource: UsageTotals].self, forKey: .bySource)) ?? Self.decodeUsageTotalsBySource(from: container) ?? [:]
        self.sessionsScanned = try container.decodeIfPresent(Int.self, forKey: .sessionsScanned) ?? 0
        self.sessionsBySource = (try? container.decodeIfPresent([UsageSource: Int].self, forKey: .sessionsBySource)) ?? Self.decodeIntBySource(from: container) ?? [:]
        self.daysBack = try container.decodeIfPresent(Int.self, forKey: .daysBack) ?? 0
        self.generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        self.sourceInfo = try container.decodeIfPresent(UsageReportSourceInfo.self, forKey: .sourceInfo)
    }

    private static func decodeUsageTotalsBySource(
        from container: KeyedDecodingContainer<CodingKeys>) -> [UsageSource: UsageTotals]?
    {
        guard let raw = try? container.decodeIfPresent([String: UsageTotals].self, forKey: .bySource) else {
            return nil
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UsageSource(rawValue: key).map { ($0, value) }
        })
    }

    private static func decodeIntBySource(
        from container: KeyedDecodingContainer<CodingKeys>) -> [UsageSource: Int]?
    {
        guard let raw = try? container.decodeIfPresent([String: Int].self, forKey: .sessionsBySource) else {
            return nil
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UsageSource(rawValue: key).map { ($0, value) }
        })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(grand, forKey: .grand)
        try container.encode(byModel, forKey: .byModel)
        try container.encode(byDay, forKey: .byDay)
        try container.encode(byMonth, forKey: .byMonth)
        try container.encode(bySession, forKey: .bySession)
        try container.encode(byProject, forKey: .byProject)
        try container.encode(bySource, forKey: .bySource)
        try container.encode(sessionsScanned, forKey: .sessionsScanned)
        try container.encode(sessionsBySource, forKey: .sessionsBySource)
        try container.encode(daysBack, forKey: .daysBack)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encodeIfPresent(sourceInfo, forKey: .sourceInfo)
    }

    public static func == (a: UsageReport, b: UsageReport) -> Bool {
        a.grand == b.grand && a.byModel == b.byModel && a.byDay == b.byDay
            && a.byMonth == b.byMonth && a.bySession == b.bySession && a.byProject == b.byProject
            && a.bySource == b.bySource && a.sessionsScanned == b.sessionsScanned
            && a.sessionsBySource == b.sessionsBySource
            && a.sourceInfo == b.sourceInfo
    }
}

public extension UsageReport {
    func withSourceInfo(_ sourceInfo: UsageReportSourceInfo?) -> UsageReport {
        var copy = self
        copy.sourceInfo = sourceInfo
        return copy
    }
}

public extension UsageReport {
    var monthSummaries: [MonthlyUsage] {
        if !byMonth.isEmpty { return byMonth }
        var byMonthMap: [String: UsageTotals] = [:]
        var byMonthSourceMap: [String: [UsageSource: UsageTotals]] = [:]
        for day in byDay {
            guard let month = Self.monthKey(fromDay: day.day) else { continue }
            byMonthMap[month, default: UsageTotals()] += day.totals
            for (source, totals) in day.bySource {
                byMonthSourceMap[month, default: [:]][source, default: UsageTotals()] += totals
            }
        }
        return byMonthMap.map {
            MonthlyUsage(month: $0.key, totals: $0.value, bySource: byMonthSourceMap[$0.key] ?? [:])
        }.sorted { $0.month < $1.month }
    }

    static func monthKey(fromDay day: String) -> String? {
        guard day.count >= 7 else { return nil }
        let prefix = String(day.prefix(7))
        guard prefix.count == 7,
              prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-",
              prefix.prefix(4).allSatisfy(\.isNumber),
              prefix.suffix(2).allSatisfy(\.isNumber)
        else { return nil }
        return prefix
    }
}
