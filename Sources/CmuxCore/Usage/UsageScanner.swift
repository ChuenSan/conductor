import Foundation

/// 扫描本机 Claude Code / Codex 的会话日志，按天 / 模型聚合 token 与估算成本（ccusage 思路）。
///
/// - Claude：`~/.claude/projects/**/*.jsonl`，assistant 行带 `message.usage` + `message.model`，
///   顶层 `timestamp`。按 (message.id, requestId) 去重，避免一条消息多行重复计数。
/// - Codex：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`，`event_msg` 的 `token_count`
///   事件里 `info.total_token_usage` 是**累计值**，取最后一个即该会话总量。
///
/// 为控制开销：只扫 `daysBack` 天内修改过的文件，且 Claude 侧先用子串预筛行再做 JSON 解析。
public struct UsageScanner: Sendable {
    private let claudeProjectsDir: URL
    private let codexSessionsDir: URL

    public init(claudeProjectsDir: URL? = nil, codexSessionsDir: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.claudeProjectsDir = claudeProjectsDir
            ?? home.appendingPathComponent(".claude/projects", isDirectory: true)
        self.codexSessionsDir = codexSessionsDir
            ?? home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    /// 一条用量记录：day/source/model/project + token 统计。dedupKey 仅 Claude 用（跨文件全局去重）。
    private struct UsageRecord: Sendable {
        let dedupKey: String?
        let day: String
        let source: UsageSource
        let model: String
        let project: String
        let totals: UsageTotals
    }
    private struct FilePartial: Sendable { var records: [UsageRecord]; var hadUsage: Bool }
    private struct UncheckedSendable<T>: @unchecked Sendable { let value: T }

    public func scan(daysBack: Int = 30, now: Date = Date()) -> UsageReport {
        let cutoff = now.addingTimeInterval(-Double(daysBack) * 86_400)
        let claudeFiles = jsonlFiles(in: claudeProjectsDir, modifiedAfter: cutoff)
        let codexFiles = jsonlFiles(in: codexSessionsDir, modifiedAfter: cutoff)

        // 文件级并行解析（吃满多核）；Claude 跨文件全局去重（resume/fork 会复制历史消息）。
        let claudeParts = parallel(claudeFiles) { self.processClaudeFile($0) }
        let codexParts = parallel(codexFiles) { self.processCodexFile($0) }

        var records: [UsageRecord] = []
        var sessionsBySource: [UsageSource: Int] = [:]
        var seen = Set<String>()
        for (parts, source) in [(claudeParts, UsageSource.claude), (codexParts, .codex)] {
            for p in parts {
                if p.hadUsage { sessionsBySource[source, default: 0] += 1 }
                for r in p.records {
                    if let key = r.dedupKey {
                        if seen.contains(key) { continue }
                        seen.insert(key)
                    }
                    records.append(r)
                }
            }
        }
        return buildReport(records: records, sessionsBySource: sessionsBySource, daysBack: daysBack, now: now)
    }

    /// Swift 6 安全的并行 map：各迭代写入独立下标，结果拷出后再回收。
    private func parallel<T: Sendable>(_ files: [URL], _ body: @escaping @Sendable (URL) -> T) -> [T] {
        let count = files.count
        guard count > 0 else { return [] }
        let storage = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
        let box = UncheckedSendable(value: storage)
        let filesBox = UncheckedSendable(value: files)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            box.value.baseAddress!.advanced(by: i).initialize(to: body(filesBox.value[i]))
        }
        let out = Array(storage)
        storage.baseAddress!.deinitialize(count: count)
        storage.deallocate()
        return out
    }

    // MARK: - Claude

    private func processClaudeFile(_ file: URL) -> FilePartial {
        var records: [UsageRecord] = []
        var fileHadUsage = false
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return FilePartial(records: records, hadUsage: false)
        }
        let fileDay = dayString(date: fileModified(file))
        var project = ""   // 取文件里第一条带 cwd 的行（会话工作目录）
        text.enumerateLines { line, _ in
                if project.isEmpty, line.contains("\"cwd\":\""),
                   let cwd = Self.quotedValue(in: line, afterKey: "\"cwd\":\""), cwd.hasPrefix("/") {
                    project = cwd
                }
                guard line.contains("input_tokens") else { return }    // 预筛，省掉绝大多数行
                // 大行（含 thinking/content）全量 JSON 解析很贵：只抠出小小的 usage 子对象解析，
                // model/id/timestamp 用定向字符串扫描，避免 tokenize 整行。
                guard let usageStr = Self.braceObject(in: line, afterKey: "\"usage\":"),
                      let usageData = usageStr.data(using: .utf8),
                      let usage = try? JSONSerialization.jsonObject(with: usageData) as? [String: Any]
                else { return }

                let model = Self.quotedValue(in: line, afterKey: "\"model\":\"") ?? "claude-unknown"
                if model == "<synthetic>" { return }

                // 去重键：msg id（以 "msg_" 开头）+ requestId。无 id 时给唯一键（必然计入）。
                let msgID = Self.quotedValue(in: line, afterKey: "\"id\":\"msg_") ?? ""
                let reqID = Self.quotedValue(in: line, afterKey: "\"requestId\":\"") ?? ""
                let dedupKey = msgID.isEmpty ? UUID().uuidString : "\(msgID)|\(reqID)"

                let input = intValue(usage["input_tokens"])
                let output = intValue(usage["output_tokens"])
                let cacheWrite = intValue(usage["cache_creation_input_tokens"])
                let cacheRead = intValue(usage["cache_read_input_tokens"])
                if input + output + cacheWrite + cacheRead == 0 { return }

                let day = Self.quotedValue(in: line, afterKey: "\"timestamp\":\"").flatMap { $0.count >= 10 ? String($0.prefix(10)) : nil } ?? fileDay
                let pricing = ModelPricing.forModel(model)
                var t = UsageTotals()
                t.inputTokens = input
                t.outputTokens = output
                t.cacheCreationTokens = cacheWrite
                t.cacheReadTokens = cacheRead
                t.costUSD = pricing.cost(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
                records.append(UsageRecord(
                    dedupKey: dedupKey, day: day, source: .claude,
                    model: normalizeModel(model), project: project, totals: t))
                fileHadUsage = true
            }
        // cwd 可能晚于首条用量行出现，统一回填。
        if !project.isEmpty {
            records = records.map { r in
                r.project.isEmpty
                    ? UsageRecord(dedupKey: r.dedupKey, day: r.day, source: r.source,
                                  model: r.model, project: project, totals: r.totals)
                    : r
            }
        }
        return FilePartial(records: records, hadUsage: fileHadUsage)
    }

    // MARK: - Codex

    private func processCodexFile(_ file: URL) -> FilePartial {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            return FilePartial(records: [], hadUsage: false)
        }
        // model / cwd 单次字符串扫描（避免逐行解析含大段 instructions 的行）。
        let model = Self.quotedValue(in: text, afterKey: "\"model\":\"") ?? "gpt-5-codex"
        let project = Self.quotedValue(in: text, afterKey: "\"cwd\":\"").flatMap { $0.hasPrefix("/") ? $0 : nil } ?? ""
        var metaDay: String?
        var lastTotal: [String: Any]?
        text.enumerateLines { line, _ in
            let isToken = line.contains("token_count")
            let isMeta = metaDay == nil && line.contains("session_meta")
            guard isToken || isMeta else { return }   // 只解析需要的行
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let payload = obj["payload"] as? [String: Any]
            if isMeta, (obj["type"] as? String) == "session_meta" {
                metaDay = dayString(fromISO: obj["timestamp"] as? String)
                    ?? dayString(fromISO: payload?["timestamp"] as? String)
            }
            if (payload?["type"] as? String) == "token_count",
               let info = payload?["info"] as? [String: Any],
               let total = info["total_token_usage"] as? [String: Any] {
                lastTotal = total
            }
        }
        guard let total = lastTotal else {
            return FilePartial(records: [], hadUsage: false)
        }
        let inputAll = intValue(total["input_tokens"])
        let cached = intValue(total["cached_input_tokens"])
        let output = intValue(total["output_tokens"]) + intValue(total["reasoning_output_tokens"])
        let uncachedInput = max(0, inputAll - cached)
        if inputAll + output == 0 {
            return FilePartial(records: [], hadUsage: false)
        }

        let day = metaDay ?? dayString(fromCodexPath: file) ?? dayString(date: fileModified(file))
        let pricing = ModelPricing.forModel(model)
        var t = UsageTotals()
        t.inputTokens = uncachedInput
        t.outputTokens = output
        t.cacheReadTokens = cached
        t.costUSD = pricing.cost(input: uncachedInput, output: output, cacheWrite: 0, cacheRead: cached)
        let record = UsageRecord(
            dedupKey: nil, day: day, source: .codex,
            model: normalizeModel(model), project: project, totals: t)
        return FilePartial(records: [record], hadUsage: true)
    }

    // MARK: - 聚合

    private func buildReport(records: [UsageRecord], sessionsBySource: [UsageSource: Int], daysBack: Int, now: Date) -> UsageReport {
        var report = UsageReport()
        report.sessionsScanned = sessionsBySource.values.reduce(0, +)
        report.sessionsBySource = sessionsBySource
        report.daysBack = daysBack
        report.generatedAt = now

        var byModelMap: [String: ModelUsage] = [:]
        var byDayMap: [String: UsageTotals] = [:]
        var byDaySourceMap: [String: [UsageSource: UsageTotals]] = [:]
        var byProjectMap: [String: UsageTotals] = [:]
        var byProjectSourceMap: [String: [UsageSource: UsageTotals]] = [:]
        for r in records {
            report.grand += r.totals
            report.bySource[r.source, default: UsageTotals()] += r.totals
            byDayMap[r.day, default: UsageTotals()] += r.totals
            byDaySourceMap[r.day, default: [:]][r.source, default: UsageTotals()] += r.totals
            byProjectMap[r.project, default: UsageTotals()] += r.totals
            byProjectSourceMap[r.project, default: [:]][r.source, default: UsageTotals()] += r.totals
            let mKey = "\(r.source.rawValue):\(r.model)"
            if let existing = byModelMap[mKey] {
                byModelMap[mKey] = ModelUsage(model: r.model, source: r.source, totals: existing.totals + r.totals)
            } else {
                byModelMap[mKey] = ModelUsage(model: r.model, source: r.source, totals: r.totals)
            }
        }
        report.byModel = byModelMap.values.sorted { $0.totals.costUSD > $1.totals.costUSD }
        report.byDay = byDayMap.map {
            DailyUsage(day: $0.key, totals: $0.value, bySource: byDaySourceMap[$0.key] ?? [:])
        }.sorted { $0.day < $1.day }
        report.byProject = byProjectMap.map {
            ProjectUsage(path: $0.key, totals: $0.value, bySource: byProjectSourceMap[$0.key] ?? [:])
        }.sorted { $0.totals.costUSD > $1.totals.costUSD }
        return report
    }

    // MARK: - 工具

    private func jsonlFiles(in dir: URL, modifiedAfter cutoff: Date) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mod = values?.contentModificationDate, mod < cutoff { continue }
            out.append(url)
        }
        return out
    }

    private func fileModified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }

    /// 抠出 `afterKey` 之后那个 `{...}`（按花括号配对，跳过字符串内的括号）。用于只解析小 usage 子对象。
    static func braceObject(in line: String, afterKey key: String) -> String? {
        guard let r = line.range(of: key) else { return nil }
        let tail = line[r.upperBound...]
        guard let open = tail.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inStr = false
        var esc = false
        var idx = open
        while idx < tail.endIndex {
            let c = tail[idx]
            if inStr {
                if esc { esc = false }
                else if c == "\\" { esc = true }
                else if c == "\"" { inStr = false }
            } else {
                if c == "\"" { inStr = true }
                else if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 { return String(tail[open...idx]) }
                }
            }
            idx = tail.index(after: idx)
        }
        return nil
    }

    /// 读 `afterKey`（含起始引号）之后到下一个 `"` 之间的值。用于定向取 model/id/timestamp。
    static func quotedValue(in text: String, afterKey key: String) -> String? {
        guard let r = text.range(of: key) else { return nil }
        let tail = text[r.upperBound...]
        guard let endQuote = tail.firstIndex(of: "\"") else { return nil }
        return String(tail[tail.startIndex..<endQuote])
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return 0
    }

    private func dayString(fromISO iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        return String(iso.prefix(10))   // yyyy-MM-dd
    }

    private static let pathDayRegex = try? NSRegularExpression(pattern: #"/(\d{4})/(\d{2})/(\d{2})/"#)

    private func dayString(fromCodexPath url: URL) -> String? {
        let path = url.path
        guard let re = Self.pathDayRegex,
              let m = re.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let yr = Range(m.range(at: 1), in: path),
              let mo = Range(m.range(at: 2), in: path),
              let dy = Range(m.range(at: 3), in: path) else { return nil }
        return "\(path[yr])-\(path[mo])-\(path[dy])"
    }

    private func dayString(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 收敛模型名做展示/聚合（去掉日期后缀等噪音）。
    private func normalizeModel(_ model: String) -> String {
        model
    }
}
