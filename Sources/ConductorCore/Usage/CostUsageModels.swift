import Foundation

private struct CostUsageAnyCodingKey: CodingKey, Sendable {
    var intValue: Int?
    var stringValue: String

    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }

    init?(stringValue: String) {
        self.intValue = nil
        self.stringValue = stringValue
    }
}

public struct CostUsageTokenSnapshot: Sendable, Equatable, Codable {
    public let sessionTokens: Int?
    public let sessionCostUSD: Double?
    public let sessionRequests: Int?
    public let last30DaysTokens: Int?
    public let last30DaysCostUSD: Double?
    public let last30DaysRequests: Int?
    public let currencyCode: String
    public let historyDays: Int
    public let historyLabel: String?
    public let daily: [CostUsageDailyReport.Entry]
    public let updatedAt: Date

    public init(
        sessionTokens: Int?,
        sessionCostUSD: Double?,
        sessionRequests: Int? = nil,
        last30DaysTokens: Int?,
        last30DaysCostUSD: Double?,
        last30DaysRequests: Int? = nil,
        currencyCode: String = "USD",
        historyDays: Int = 30,
        historyLabel: String? = nil,
        daily: [CostUsageDailyReport.Entry],
        updatedAt: Date)
    {
        self.sessionTokens = sessionTokens
        self.sessionCostUSD = sessionCostUSD
        self.sessionRequests = sessionRequests
        self.last30DaysTokens = last30DaysTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.last30DaysRequests = last30DaysRequests
        let trimmedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currencyCode = trimmedCurrency.isEmpty ? "USD" : trimmedCurrency.uppercased()
        self.historyDays = max(1, min(365, historyDays))
        let trimmedLabel = historyLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.historyLabel = trimmedLabel.isEmpty ? nil : trimmedLabel
        self.daily = daily
        self.updatedAt = updatedAt
    }
}

public struct CostUsageDailyReport: Sendable, Equatable, Codable {
    public struct ModelBreakdown: Sendable, Equatable, Codable {
        public let source: UsageSource
        public let modelName: String
        public let costUSD: Double?
        public let totalTokens: Int?
        public let requestCount: Int?
        public let standardCostUSD: Double?
        public let priorityCostUSD: Double?
        public let standardTokens: Int?
        public let priorityTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case source
            case modelName
            case costUSD
            case cost
            case totalTokens
            case requestCount
            case requests
            case standardCostUSD
            case priorityCostUSD
            case standardTokens
            case priorityTokens
        }

        public init(
            source: UsageSource,
            modelName: String,
            costUSD: Double?,
            totalTokens: Int? = nil,
            requestCount: Int? = nil,
            standardCostUSD: Double? = nil,
            priorityCostUSD: Double? = nil,
            standardTokens: Int? = nil,
            priorityTokens: Int? = nil)
        {
            self.source = source
            self.modelName = modelName
            self.costUSD = costUSD
            self.totalTokens = totalTokens
            self.requestCount = requestCount
            self.standardCostUSD = standardCostUSD
            self.priorityCostUSD = priorityCostUSD
            self.standardTokens = standardTokens
            self.priorityTokens = priorityTokens
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let modelName = try container.decode(String.self, forKey: .modelName)
            self.source = try container.decodeIfPresent(UsageSource.self, forKey: .source)
                ?? Self.inferredSource(for: modelName)
            self.modelName = modelName
            self.costUSD =
                try container.decodeIfPresent(Double.self, forKey: .costUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .cost)
            self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            self.requestCount =
                try container.decodeIfPresent(Int.self, forKey: .requestCount)
                ?? container.decodeIfPresent(Int.self, forKey: .requests)
            self.standardCostUSD = try container.decodeIfPresent(Double.self, forKey: .standardCostUSD)
            self.priorityCostUSD = try container.decodeIfPresent(Double.self, forKey: .priorityCostUSD)
            self.standardTokens = try container.decodeIfPresent(Int.self, forKey: .standardTokens)
            self.priorityTokens = try container.decodeIfPresent(Int.self, forKey: .priorityTokens)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(source, forKey: .source)
            try container.encode(modelName, forKey: .modelName)
            try container.encodeIfPresent(costUSD, forKey: .costUSD)
            try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(requestCount, forKey: .requestCount)
            try container.encodeIfPresent(standardCostUSD, forKey: .standardCostUSD)
            try container.encodeIfPresent(priorityCostUSD, forKey: .priorityCostUSD)
            try container.encodeIfPresent(standardTokens, forKey: .standardTokens)
            try container.encodeIfPresent(priorityTokens, forKey: .priorityTokens)
        }

        private static func inferredSource(for modelName: String) -> UsageSource {
            let lower = modelName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lower.contains("bedrock") {
                return .bedrock
            }
            if lower.contains("claude") {
                return lower.contains("@") ? .vertexai : .claude
            }
            return .codex
        }
    }

    public struct Entry: Sendable, Equatable, Codable {
        public let date: String
        public let inputTokens: Int?
        public let cacheReadTokens: Int?
        public let cacheCreationTokens: Int?
        public let outputTokens: Int?
        public let totalTokens: Int?
        public let requestCount: Int?
        public let costUSD: Double?
        public let modelsUsed: [String]?
        public let modelBreakdowns: [ModelBreakdown]?

        private enum CodingKeys: String, CodingKey {
            case date
            case inputTokens
            case cacheReadTokens
            case cacheCreationTokens
            case cacheReadInputTokens
            case cacheCreationInputTokens
            case outputTokens
            case totalTokens
            case requestCount
            case requests
            case costUSD
            case totalCost
            case modelsUsed
            case models
            case modelBreakdowns
        }

        public init(
            date: String,
            inputTokens: Int?,
            outputTokens: Int?,
            cacheReadTokens: Int? = nil,
            cacheCreationTokens: Int? = nil,
            totalTokens: Int?,
            requestCount: Int? = nil,
            costUSD: Double?,
            modelsUsed: [String]?,
            modelBreakdowns: [ModelBreakdown]?)
        {
            self.date = date
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.cacheReadTokens = cacheReadTokens
            self.cacheCreationTokens = cacheCreationTokens
            self.totalTokens = totalTokens
            self.requestCount = requestCount
            self.costUSD = costUSD
            self.modelsUsed = modelsUsed
            self.modelBreakdowns = modelBreakdowns
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.date = try container.decode(String.self, forKey: .date)
            self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
            self.cacheReadTokens =
                try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens)
            self.cacheCreationTokens =
                try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .cacheCreationInputTokens)
            self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
            self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            self.requestCount =
                try container.decodeIfPresent(Int.self, forKey: .requestCount)
                ?? container.decodeIfPresent(Int.self, forKey: .requests)
            self.costUSD =
                try container.decodeIfPresent(Double.self, forKey: .costUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .totalCost)
            self.modelsUsed = Self.decodeModelsUsed(from: container)
            self.modelBreakdowns = try container.decodeIfPresent([ModelBreakdown].self, forKey: .modelBreakdowns)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(date, forKey: .date)
            try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
            try container.encodeIfPresent(cacheReadTokens, forKey: .cacheReadTokens)
            try container.encodeIfPresent(cacheCreationTokens, forKey: .cacheCreationTokens)
            try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
            try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(requestCount, forKey: .requestCount)
            try container.encodeIfPresent(costUSD, forKey: .costUSD)
            try container.encodeIfPresent(modelsUsed, forKey: .modelsUsed)
            try container.encodeIfPresent(modelBreakdowns, forKey: .modelBreakdowns)
        }

        private static func decodeModelsUsed(from container: KeyedDecodingContainer<CodingKeys>) -> [String]? {
            if let modelsUsed = try? container.decodeIfPresent([String].self, forKey: .modelsUsed) {
                return modelsUsed
            }
            if let models = try? container.decodeIfPresent([String].self, forKey: .models) {
                return models
            }
            guard container.contains(.models),
                  let modelMap = try? container.nestedContainer(keyedBy: CostUsageAnyCodingKey.self, forKey: .models)
            else { return nil }
            let names = modelMap.allKeys.map(\.stringValue).sorted()
            return names.isEmpty ? nil : names
        }
    }

    public struct Summary: Sendable, Equatable, Codable {
        public let totalInputTokens: Int?
        public let totalOutputTokens: Int?
        public let cacheReadTokens: Int?
        public let cacheCreationTokens: Int?
        public let totalTokens: Int?
        public let totalCostUSD: Double?

        private enum CodingKeys: String, CodingKey {
            case totalInputTokens
            case totalOutputTokens
            case cacheReadTokens
            case cacheCreationTokens
            case totalCacheReadTokens
            case totalCacheCreationTokens
            case totalTokens
            case totalCostUSD
            case totalCost
        }

        public init(
            totalInputTokens: Int?,
            totalOutputTokens: Int?,
            cacheReadTokens: Int? = nil,
            cacheCreationTokens: Int? = nil,
            totalTokens: Int?,
            totalCostUSD: Double?)
        {
            self.totalInputTokens = totalInputTokens
            self.totalOutputTokens = totalOutputTokens
            self.cacheReadTokens = cacheReadTokens
            self.cacheCreationTokens = cacheCreationTokens
            self.totalTokens = totalTokens
            self.totalCostUSD = totalCostUSD
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.totalInputTokens = try container.decodeIfPresent(Int.self, forKey: .totalInputTokens)
            self.totalOutputTokens = try container.decodeIfPresent(Int.self, forKey: .totalOutputTokens)
            self.cacheReadTokens =
                try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .totalCacheReadTokens)
            self.cacheCreationTokens =
                try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens)
                ?? container.decodeIfPresent(Int.self, forKey: .totalCacheCreationTokens)
            self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            self.totalCostUSD =
                try container.decodeIfPresent(Double.self, forKey: .totalCostUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .totalCost)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(totalInputTokens, forKey: .totalInputTokens)
            try container.encodeIfPresent(totalOutputTokens, forKey: .totalOutputTokens)
            try container.encodeIfPresent(cacheReadTokens, forKey: .cacheReadTokens)
            try container.encodeIfPresent(cacheCreationTokens, forKey: .cacheCreationTokens)
            try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(totalCostUSD, forKey: .totalCostUSD)
        }
    }

    public let data: [Entry]
    public let summary: Summary?

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case summary
        case daily
        case totals
    }

    public init(data: [Entry], summary: Summary?) {
        self.data = data
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.type) || container.contains(.data) {
            self.data = try container.decode([Entry].self, forKey: .data)
            self.summary = try container.decodeIfPresent(Summary.self, forKey: .summary)
            return
        }

        self.data = try container.decode([Entry].self, forKey: .daily)
        self.summary = try container.decodeIfPresent(Summary.self, forKey: .totals)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("daily", forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

public struct CostUsageSessionReport: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public let session: String
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let totalTokens: Int?
        public let costUSD: Double?
        public let lastActivity: String?

        private enum CodingKeys: String, CodingKey {
            case session
            case sessionId
            case inputTokens
            case outputTokens
            case totalTokens
            case costUSD
            case totalCost
            case lastActivity
        }

        public init(
            session: String,
            inputTokens: Int?,
            outputTokens: Int?,
            totalTokens: Int?,
            costUSD: Double?,
            lastActivity: String?)
        {
            self.session = session
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
            self.totalTokens = totalTokens
            self.costUSD = costUSD
            self.lastActivity = lastActivity
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.session =
                try container.decodeIfPresent(String.self, forKey: .session)
                ?? container.decode(String.self, forKey: .sessionId)
            self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens)
            self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens)
            self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            self.costUSD =
                try container.decodeIfPresent(Double.self, forKey: .costUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .totalCost)
            self.lastActivity = try container.decodeIfPresent(String.self, forKey: .lastActivity)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(session, forKey: .session)
            try container.encodeIfPresent(inputTokens, forKey: .inputTokens)
            try container.encodeIfPresent(outputTokens, forKey: .outputTokens)
            try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(costUSD, forKey: .costUSD)
            try container.encodeIfPresent(lastActivity, forKey: .lastActivity)
        }
    }

    public struct Summary: Sendable, Equatable, Codable {
        public let totalCostUSD: Double?

        private enum CodingKeys: String, CodingKey {
            case totalCostUSD
            case totalCost
        }

        public init(totalCostUSD: Double?) {
            self.totalCostUSD = totalCostUSD
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.totalCostUSD =
                try container.decodeIfPresent(Double.self, forKey: .totalCostUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .totalCost)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(totalCostUSD, forKey: .totalCostUSD)
        }
    }

    public let data: [Entry]
    public let summary: Summary?

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case summary
        case sessions
        case totals
    }

    public init(data: [Entry], summary: Summary?) {
        self.data = data
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.type) {
            _ = try container.decode(String.self, forKey: .type)
            self.data = try container.decode([Entry].self, forKey: .data)
            self.summary = try container.decodeIfPresent(Summary.self, forKey: .summary)
            return
        }

        self.data = try container.decode([Entry].self, forKey: .sessions)
        self.summary = try container.decodeIfPresent(Summary.self, forKey: .totals)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("session", forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

public struct CostUsageMonthlyReport: Sendable, Equatable, Codable {
    public struct Entry: Sendable, Equatable, Codable {
        public let month: String
        public let totalTokens: Int?
        public let costUSD: Double?

        private enum CodingKeys: String, CodingKey {
            case month
            case totalTokens
            case costUSD
            case totalCost
        }

        public init(month: String, totalTokens: Int?, costUSD: Double?) {
            self.month = month
            self.totalTokens = totalTokens
            self.costUSD = costUSD
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.month = try container.decode(String.self, forKey: .month)
            self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            self.costUSD =
                try container.decodeIfPresent(Double.self, forKey: .costUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .totalCost)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(month, forKey: .month)
            try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(costUSD, forKey: .costUSD)
        }
    }

    public struct Summary: Sendable, Equatable, Codable {
        public let totalTokens: Int?
        public let totalCostUSD: Double?

        private enum CodingKeys: String, CodingKey {
            case totalTokens
            case costUSD
            case totalCostUSD
            case totalCost
        }

        public init(totalTokens: Int?, totalCostUSD: Double?) {
            self.totalTokens = totalTokens
            self.totalCostUSD = totalCostUSD
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens)
            self.totalCostUSD =
                try container.decodeIfPresent(Double.self, forKey: .totalCostUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .costUSD)
                ?? container.decodeIfPresent(Double.self, forKey: .totalCost)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(totalTokens, forKey: .totalTokens)
            try container.encodeIfPresent(totalCostUSD, forKey: .totalCostUSD)
        }
    }

    public let data: [Entry]
    public let summary: Summary?

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case summary
        case monthly
        case totals
    }

    public init(data: [Entry], summary: Summary?) {
        self.data = data
        self.summary = summary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.type) {
            _ = try container.decode(String.self, forKey: .type)
            self.data = try container.decode([Entry].self, forKey: .data)
            self.summary = try container.decodeIfPresent(Summary.self, forKey: .summary)
            return
        }

        self.data = try container.decode([Entry].self, forKey: .monthly)
        self.summary = try container.decodeIfPresent(Summary.self, forKey: .totals)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(summary, forKey: .summary)
    }
}

public extension CostUsageDailyReport {
    private struct BreakdownKey: Hashable {
        let source: UsageSource
        let modelName: String
    }

    private struct BreakdownAccumulator {
        let source: UsageSource
        let modelName: String
        var costUSD: Double = 0
        var sawCost = false
        var totalTokens: Int = 0
        var sawTotalTokens = false
        var requestCount: Int = 0
        var sawRequestCount = false
        var standardCostUSD: Double = 0
        var sawStandardCost = false
        var priorityCostUSD: Double = 0
        var sawPriorityCost = false
        var standardTokens: Int = 0
        var sawStandardTokens = false
        var priorityTokens: Int = 0
        var sawPriorityTokens = false

        init(source: UsageSource, modelName: String) {
            self.source = source
            self.modelName = modelName
        }

        mutating func add(_ breakdown: ModelBreakdown) {
            if let costUSD = breakdown.costUSD {
                self.costUSD += costUSD
                self.sawCost = true
            }
            if let totalTokens = breakdown.totalTokens {
                self.totalTokens += totalTokens
                self.sawTotalTokens = true
            }
            if let requestCount = breakdown.requestCount {
                self.requestCount += requestCount
                self.sawRequestCount = true
            }
            if let standardCostUSD = breakdown.standardCostUSD {
                self.standardCostUSD += standardCostUSD
                self.sawStandardCost = true
            }
            if let priorityCostUSD = breakdown.priorityCostUSD {
                self.priorityCostUSD += priorityCostUSD
                self.sawPriorityCost = true
            }
            if let standardTokens = breakdown.standardTokens {
                self.standardTokens += standardTokens
                self.sawStandardTokens = true
            }
            if let priorityTokens = breakdown.priorityTokens {
                self.priorityTokens += priorityTokens
                self.sawPriorityTokens = true
            }
        }

        func build() -> ModelBreakdown {
            ModelBreakdown(
                source: source,
                modelName: modelName,
                costUSD: sawCost ? costUSD : nil,
                totalTokens: sawTotalTokens ? totalTokens : nil,
                requestCount: sawRequestCount ? requestCount : nil,
                standardCostUSD: sawStandardCost ? standardCostUSD : nil,
                priorityCostUSD: sawPriorityCost ? priorityCostUSD : nil,
                standardTokens: sawStandardTokens ? standardTokens : nil,
                priorityTokens: sawPriorityTokens ? priorityTokens : nil)
        }
    }

    private struct EntryAccumulator {
        var inputTokens: Int = 0
        var sawInputTokens = false
        var outputTokens: Int = 0
        var sawOutputTokens = false
        var cacheReadTokens: Int = 0
        var sawCacheReadTokens = false
        var cacheCreationTokens: Int = 0
        var sawCacheCreationTokens = false
        var totalTokens: Int = 0
        var sawTotalTokens = false
        var derivedTotalTokensWithoutExplicitTotal: Int = 0
        var requestCount: Int = 0
        var sawRequestCount = false
        var costUSD: Double = 0
        var sawCost = false
        var modelsUsed = Set<String>()
        var breakdowns: [BreakdownKey: BreakdownAccumulator] = [:]

        mutating func add(_ entry: Entry) {
            let derivedTokens = (entry.inputTokens ?? 0)
                + (entry.cacheReadTokens ?? 0)
                + (entry.cacheCreationTokens ?? 0)
                + (entry.outputTokens ?? 0)
            if let inputTokens = entry.inputTokens {
                self.inputTokens += inputTokens
                self.sawInputTokens = true
            }
            if let outputTokens = entry.outputTokens {
                self.outputTokens += outputTokens
                self.sawOutputTokens = true
            }
            if let cacheReadTokens = entry.cacheReadTokens {
                self.cacheReadTokens += cacheReadTokens
                self.sawCacheReadTokens = true
            }
            if let cacheCreationTokens = entry.cacheCreationTokens {
                self.cacheCreationTokens += cacheCreationTokens
                self.sawCacheCreationTokens = true
            }
            if let totalTokens = entry.totalTokens {
                self.totalTokens += totalTokens
                self.sawTotalTokens = true
            } else if derivedTokens > 0 {
                self.derivedTotalTokensWithoutExplicitTotal += derivedTokens
            }
            if let requestCount = entry.requestCount {
                self.requestCount += requestCount
                self.sawRequestCount = true
            }
            if let costUSD = entry.costUSD {
                self.costUSD += costUSD
                self.sawCost = true
            }
            if let modelsUsed = entry.modelsUsed {
                self.modelsUsed.formUnion(modelsUsed)
            }
            for breakdown in entry.modelBreakdowns ?? [] {
                let key = BreakdownKey(source: breakdown.source, modelName: breakdown.modelName)
                var accumulator = self.breakdowns[key] ?? BreakdownAccumulator(
                    source: breakdown.source,
                    modelName: breakdown.modelName)
                accumulator.add(breakdown)
                self.breakdowns[key] = accumulator
                self.modelsUsed.insert(breakdown.modelName)
            }
        }

        func build(date: String) -> Entry {
            let derivedTokens = self.inputTokens
                + self.cacheReadTokens
                + self.cacheCreationTokens
                + self.outputTokens
            let totalTokens: Int? = if self.sawTotalTokens {
                self.totalTokens + self.derivedTotalTokensWithoutExplicitTotal
            } else if derivedTokens > 0 {
                derivedTokens
            } else {
                nil
            }
            let breakdowns = self.breakdowns.isEmpty
                ? nil
                : CostUsageDailyReport.sortedModelBreakdowns(self.breakdowns.values.map { $0.build() })
            return Entry(
                date: date,
                inputTokens: sawInputTokens ? inputTokens : nil,
                outputTokens: sawOutputTokens ? outputTokens : nil,
                cacheReadTokens: sawCacheReadTokens ? cacheReadTokens : nil,
                cacheCreationTokens: sawCacheCreationTokens ? cacheCreationTokens : nil,
                totalTokens: totalTokens,
                requestCount: sawRequestCount ? requestCount : nil,
                costUSD: sawCost ? costUSD : nil,
                modelsUsed: modelsUsed.isEmpty ? nil : modelsUsed.sorted(),
                modelBreakdowns: breakdowns)
        }
    }

    func merged(with other: CostUsageDailyReport) -> CostUsageDailyReport {
        Self.merged([self, other])
    }

    static func merged(_ reports: [CostUsageDailyReport]) -> CostUsageDailyReport {
        let entries = mergedEntries(from: reports)
        guard !entries.isEmpty else { return CostUsageDailyReport(data: [], summary: nil) }
        return CostUsageDailyReport(data: entries, summary: mergedSummary(from: entries))
    }

    private static func mergedEntries(from reports: [CostUsageDailyReport]) -> [Entry] {
        var accumulators: [String: EntryAccumulator] = [:]
        for report in reports {
            for entry in report.data {
                var accumulator = accumulators[entry.date] ?? EntryAccumulator()
                accumulator.add(entry)
                accumulators[entry.date] = accumulator
            }
        }
        return accumulators.keys.sorted().map { date in
            accumulators[date, default: EntryAccumulator()].build(date: date)
        }
    }

    private static func mergedSummary(from entries: [Entry]) -> Summary {
        var inputTokens = 0
        var sawInputTokens = false
        var outputTokens = 0
        var sawOutputTokens = false
        var cacheReadTokens = 0
        var sawCacheReadTokens = false
        var cacheCreationTokens = 0
        var sawCacheCreationTokens = false
        var totalTokens = 0
        var sawTotalTokens = false
        var costUSD = 0.0
        var sawCost = false

        for entry in entries {
            if let value = entry.inputTokens {
                inputTokens += value
                sawInputTokens = true
            }
            if let value = entry.outputTokens {
                outputTokens += value
                sawOutputTokens = true
            }
            if let value = entry.cacheReadTokens {
                cacheReadTokens += value
                sawCacheReadTokens = true
            }
            if let value = entry.cacheCreationTokens {
                cacheCreationTokens += value
                sawCacheCreationTokens = true
            }
            if let value = entry.totalTokens {
                totalTokens += value
                sawTotalTokens = true
            }
            if let value = entry.costUSD {
                costUSD += value
                sawCost = true
            }
        }

        return Summary(
            totalInputTokens: sawInputTokens ? inputTokens : nil,
            totalOutputTokens: sawOutputTokens ? outputTokens : nil,
            cacheReadTokens: sawCacheReadTokens ? cacheReadTokens : nil,
            cacheCreationTokens: sawCacheCreationTokens ? cacheCreationTokens : nil,
            totalTokens: sawTotalTokens ? totalTokens : nil,
            totalCostUSD: sawCost ? costUSD : nil)
    }

    private static func sortedModelBreakdowns(_ breakdowns: [ModelBreakdown]) -> [ModelBreakdown] {
        breakdowns.sorted { lhs, rhs in
            let lhsCost = lhs.costUSD ?? -1
            let rhsCost = rhs.costUSD ?? -1
            if lhsCost != rhsCost { return lhsCost > rhsCost }
            let lhsTokens = lhs.totalTokens ?? -1
            let rhsTokens = rhs.totalTokens ?? -1
            if lhsTokens != rhsTokens { return lhsTokens > rhsTokens }
            if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
            return lhs.modelName < rhs.modelName
        }
    }

    init(report: UsageReport) {
        let entries = report.byDay.map { day in
            Entry(
                date: day.day,
                inputTokens: day.totals.inputTokens,
                outputTokens: day.totals.outputTokens,
                cacheReadTokens: day.totals.cacheReadTokens,
                cacheCreationTokens: day.totals.cacheCreationTokens,
                totalTokens: day.totals.totalTokens,
                requestCount: day.totals.requestCount > 0 ? day.totals.requestCount : nil,
                costUSD: day.totals.costUSD,
                modelsUsed: day.modelBreakdowns.map(\.model).sorted(),
                modelBreakdowns: day.modelBreakdowns.map { model in
                    ModelBreakdown(
                        source: model.source,
                        modelName: model.model,
                        costUSD: model.totals.costUSD,
                        totalTokens: model.totals.totalTokens,
                        requestCount: model.totals.requestCount > 0 ? model.totals.requestCount : nil,
                        standardCostUSD: model.standardCostUSD,
                        priorityCostUSD: model.priorityCostUSD,
                        standardTokens: model.standardTokens,
                        priorityTokens: model.priorityTokens)
                })
        }
        self.init(
            data: entries,
            summary: Summary(
                totalInputTokens: report.grand.inputTokens,
                totalOutputTokens: report.grand.outputTokens,
                cacheReadTokens: report.grand.cacheReadTokens,
                cacheCreationTokens: report.grand.cacheCreationTokens,
                totalTokens: report.grand.totalTokens,
                totalCostUSD: report.grand.costUSD))
    }

    func tokenSnapshot(now: Date, historyDays: Int) -> CostUsageTokenSnapshot {
        let currentDay = self.data.max { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            let lhsCost = lhs.costUSD ?? -1
            let rhsCost = rhs.costUSD ?? -1
            if lhsCost != rhsCost { return lhsCost < rhsCost }
            return (lhs.totalTokens ?? -1) < (rhs.totalTokens ?? -1)
        }
        let totalCost = self.summary?.totalCostUSD ?? self.data.compactMap(\.costUSD).reduce(0, +)
        let totalTokens = self.summary?.totalTokens ?? self.data.compactMap(\.totalTokens).reduce(0, +)
        let totalRequests = self.data.compactMap(\.requestCount).reduce(0, +)
        return CostUsageTokenSnapshot(
            sessionTokens: currentDay?.totalTokens,
            sessionCostUSD: currentDay?.costUSD,
            sessionRequests: currentDay?.requestCount,
            last30DaysTokens: totalTokens > 0 ? totalTokens : nil,
            last30DaysCostUSD: totalCost > 0 ? totalCost : nil,
            last30DaysRequests: totalRequests > 0 ? totalRequests : nil,
            historyDays: historyDays,
            daily: self.data,
            updatedAt: now)
    }
}

public extension UsageReport {
    var costUsageDailyReport: CostUsageDailyReport {
        CostUsageDailyReport(report: self)
    }

    var costUsageSessionReport: CostUsageSessionReport {
        CostUsageSessionReport(
            data: self.bySession.map { session in
                CostUsageSessionReport.Entry(
                    session: session.session,
                    inputTokens: session.totals.inputTokens,
                    outputTokens: session.totals.outputTokens,
                    totalTokens: session.totals.totalTokens,
                    costUSD: session.totals.costUSD,
                    lastActivity: session.lastActivity)
            },
            summary: CostUsageSessionReport.Summary(totalCostUSD: self.grand.costUSD))
    }

    var costUsageMonthlyReport: CostUsageMonthlyReport {
        let months = self.monthSummaries
        return CostUsageMonthlyReport(
            data: months.map { month in
                CostUsageMonthlyReport.Entry(
                    month: month.month,
                    totalTokens: month.totals.totalTokens,
                    costUSD: month.totals.costUSD)
            },
            summary: CostUsageMonthlyReport.Summary(
                totalTokens: self.grand.totalTokens,
                totalCostUSD: self.grand.costUSD))
    }
}
