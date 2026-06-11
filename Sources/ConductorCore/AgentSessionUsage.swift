import Foundation

/// 一个会话的 token 用量合计（claude / codex 的 jsonl 里解析）。
public struct AgentSessionUsage: Sendable, Equatable {
    public var inputTokens: Int = 0
    public var outputTokens: Int = 0
    /// 缓存命中读取（便宜一个数量级）。
    public var cacheReadTokens: Int = 0
    /// 缓存写入（claude 独有计费项）。
    public var cacheCreationTokens: Int = 0
    public var model: String?

    public init() {}

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    /// 估算成本（美元）；认不出模型时返回 nil。
    /// 订阅制（Claude Pro / ChatGPT）下这只是「等价 API 价」参考。
    public var estimatedCostUSD: Double? {
        guard let pricing = Pricing.match(model) else { return nil }
        return (Double(inputTokens) * pricing.input
            + Double(outputTokens) * pricing.output
            + Double(cacheReadTokens) * pricing.cacheRead
            + Double(cacheCreationTokens) * pricing.cacheWrite) / 1_000_000
    }

    /// 每百万 token 的美元单价（常见模型的公开 API 价，估算用）。
    struct Pricing {
        let input: Double
        let output: Double
        let cacheRead: Double
        let cacheWrite: Double

        static func match(_ model: String?) -> Pricing? {
            guard let model = model?.lowercased() else { return nil }
            if model.contains("opus") {
                return Pricing(input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75)
            }
            if model.contains("sonnet") {
                return Pricing(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)
            }
            if model.contains("haiku") {
                return Pricing(input: 1, output: 5, cacheRead: 0.1, cacheWrite: 1.25)
            }
            if model.contains("gpt-5") || model.contains("codex") {
                return Pricing(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 0)
            }
            return nil
        }
    }
}

/// 从会话日志解析 token 用量。
/// - claude：逐行累加 assistant 消息的 `message.usage`（每轮 input 即每轮计费口径）；
/// - codex：取最后一条 `token_count` 事件的 `total_token_usage`（本身就是累计值）。
public enum AgentSessionUsageScanner {
    public static func scan(agent: String, filePath: String) -> AgentSessionUsage? {
        guard let data = FileManager.default.contents(atPath: filePath),
              let text = String(data: data, encoding: .utf8) else { return nil }
        switch agent {
        case "claude": return scanClaude(text)
        case "codex": return scanCodex(text)
        default: return nil
        }
    }

    // MARK: - claude

    private static func scanClaude(_ text: String) -> AgentSessionUsage? {
        var usage = AgentSessionUsage()
        var sawAny = false
        text.enumerateLines { line, _ in
            // 粗筛省掉绝大多数行的 JSON 解析
            guard line.contains("\"usage\""), line.contains("\"assistant\""),
                  let obj = parse(line),
                  let message = obj["message"] as? [String: Any],
                  let u = message["usage"] as? [String: Any] else { return }
            usage.inputTokens += intValue(u["input_tokens"])
            usage.outputTokens += intValue(u["output_tokens"])
            usage.cacheReadTokens += intValue(u["cache_read_input_tokens"])
            usage.cacheCreationTokens += intValue(u["cache_creation_input_tokens"])
            if let model = message["model"] as? String, !model.isEmpty {
                usage.model = model
            }
            sawAny = true
        }
        return sawAny ? usage : nil
    }

    // MARK: - codex

    private static func scanCodex(_ text: String) -> AgentSessionUsage? {
        var lines: [Substring] = []
        text.split(separator: "\n", omittingEmptySubsequences: true).forEach { lines.append($0) }

        var usage = AgentSessionUsage()
        var sawTotals = false
        // 倒着找最后一条 token_count（累计值），以及最近一次 turn_context 里的模型名
        for line in lines.reversed() {
            if usage.model == nil, line.contains("\"model\""),
               let obj = parse(String(line)) {
                let payload = obj["payload"] as? [String: Any] ?? obj
                if let model = payload["model"] as? String, !model.isEmpty {
                    usage.model = model
                }
            }
            guard !sawTotals, line.contains("\"token_count\""),
                  let obj = parse(String(line)),
                  let payload = obj["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let totals = info["total_token_usage"] as? [String: Any] else { continue }
            let input = intValue(totals["input_tokens"])
            let cached = intValue(totals["cached_input_tokens"])
            // codex 的 input 含 cached 子集，拆开便于按缓存价折算
            usage.inputTokens = max(0, input - cached)
            usage.cacheReadTokens = cached
            usage.outputTokens = intValue(totals["output_tokens"])
            sawTotals = true
            if usage.model != nil { break }
        }
        return sawTotals ? usage : nil
    }

    // MARK: - 小工具

    private static func parse(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func intValue(_ any: Any?) -> Int {
        (any as? Int) ?? (any as? NSNumber)?.intValue ?? 0
    }
}
