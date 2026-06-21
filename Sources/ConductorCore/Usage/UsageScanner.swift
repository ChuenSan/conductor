import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// 扫描本机 Claude Code / Codex 的会话日志，按天 / 模型聚合 token 与估算成本（ccusage 思路）。
///
/// - Claude：`~/.claude/projects/**/*.jsonl`，assistant 行带 `message.usage` + `message.model`，
///   顶层 `timestamp`。按 (message.id, requestId) 去重，避免一条消息多行重复计数。
/// - Codex：`CODEX_HOME/sessions` 或 `~/.codex/sessions`，以及 sibling
///   `archived_sessions`。`event_msg` 的 `token_count` 事件里
///   `info.total_token_usage` 是累计值，`last_token_usage` 是单轮候选增量；
///   二者按 CodexBar 的 baseline/divergent 口径 reconciled 成每日行级成本。
/// - Pi：`~/.pi/agent/sessions/**/*.jsonl`，`model_change` 建 provider/model 上下文，
///   assistant `message.usage` 按 Codex / Claude 归因。
///
/// 为控制开销：Claude 全量枚举项目日志后按行内 timestamp 过滤窗口；Codex 用
/// `daysBack` 的 mtime/日期分区缩小扫描面；Pi 则按 mtime 或文件名会话开始时间选候选，
/// 再按行内 timestamp 归入窗口。Claude 侧先用子串预筛行再做 JSON 解析。
public struct UsageScanner: Sendable {
    private static let codexJSONLPrefixBytes = 256 * 1024
    private static let claudeJSONLPrefixBytes = 512 * 1024
    private static let piJSONLPrefixBytes = 512 * 1024

    private let claudeProjectsDirs: [URL]
    private let codexSessionsDir: URL
    private let codexArchivedSessionsDir: URL?
    private let codexTraceDatabaseURL: URL?
    private let modelsDevCacheRoot: URL?
    private let piSessionsDir: URL

    public init(
        claudeProjectsDir: URL? = nil,
        codexSessionsDir: URL? = nil,
        codexArchivedSessionsDir: URL? = nil,
        codexTraceDatabaseURL: URL? = nil,
        modelsDevCacheRoot: URL? = nil,
        piSessionsDir: URL? = nil)
    {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let claudeProjectsDir {
            self.claudeProjectsDirs = [claudeProjectsDir]
        } else {
            self.claudeProjectsDirs = [
                home.appendingPathComponent(".config/claude/projects", isDirectory: true),
                home.appendingPathComponent(".claude/projects", isDirectory: true),
            ]
        }
        let resolvedCodexSessionsDir = codexSessionsDir ?? Self.defaultCodexSessionsDir(home: home)
        self.codexSessionsDir = resolvedCodexSessionsDir
        self.codexArchivedSessionsDir = codexArchivedSessionsDir
            ?? Self.defaultCodexArchivedSessionsDir(sessionsDir: resolvedCodexSessionsDir)
        self.codexTraceDatabaseURL = codexTraceDatabaseURL
            ?? home.appendingPathComponent(".codex/logs_2.sqlite", isDirectory: false)
        self.modelsDevCacheRoot = modelsDevCacheRoot
        self.piSessionsDir = piSessionsDir
            ?? home.appendingPathComponent(".pi/agent/sessions", isDirectory: true)
    }

    /// 一条用量记录：day/source/model/project + token 统计。dedupKey 仅 Claude 用（跨文件全局去重）。
    typealias CancellationCheck = @Sendable () throws -> Void

    private struct UsageRecord: Sendable, Codable {
        let dedupKey: String?
        let day: String
        let source: UsageSource
        let session: String?
        let model: String
        let project: String
        let totals: UsageTotals
        let standardCostUSD: Double?
        let priorityCostUSD: Double?
        let standardTokens: Int?
        let priorityTokens: Int?
        let sourcePath: String?
        let claudeMessageID: String?
        let claudeRequestID: String?
        let claudeIsSidechain: Bool?
        let claudePathRole: ClaudePathRole?

        init(
            dedupKey: String?,
            day: String,
            source: UsageSource,
            session: String? = nil,
            model: String,
            project: String,
            totals: UsageTotals,
            standardCostUSD: Double? = nil,
            priorityCostUSD: Double? = nil,
            standardTokens: Int? = nil,
            priorityTokens: Int? = nil,
            sourcePath: String? = nil,
            claudeMessageID: String? = nil,
            claudeRequestID: String? = nil,
            claudeIsSidechain: Bool? = nil,
            claudePathRole: ClaudePathRole? = nil)
        {
            self.dedupKey = dedupKey
            self.day = day
            self.source = source
            let trimmedSession = session?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.session = trimmedSession.isEmpty ? nil : trimmedSession
            self.model = model
            self.project = project
            self.totals = Self.counted(totals)
            self.standardCostUSD = standardCostUSD
            self.priorityCostUSD = priorityCostUSD
            self.standardTokens = standardTokens
            self.priorityTokens = priorityTokens
            self.sourcePath = sourcePath
            self.claudeMessageID = claudeMessageID
            self.claudeRequestID = claudeRequestID
            self.claudeIsSidechain = claudeIsSidechain
            self.claudePathRole = claudePathRole
        }

        var countedTotals: UsageTotals { Self.counted(self.totals) }
        var claudeCanonicalKey: String? {
            guard Self.isClaudeLogSource(source),
                  let messageID = claudeMessageID,
                  let requestID = claudeRequestID
            else { return nil }
            return "\(source.rawValue):\(messageID):\(requestID)"
        }

        private static func isClaudeLogSource(_ source: UsageSource) -> Bool {
            source == .claude || source == .vertexai
        }

        func replacingProject(_ project: String) -> UsageRecord {
            UsageRecord(
                dedupKey: dedupKey,
                day: day,
                source: source,
                session: session,
                model: model,
                project: project,
                totals: totals,
                standardCostUSD: standardCostUSD,
                priorityCostUSD: priorityCostUSD,
                standardTokens: standardTokens,
                priorityTokens: priorityTokens,
                sourcePath: sourcePath,
                claudeMessageID: claudeMessageID,
                claudeRequestID: claudeRequestID,
                claudeIsSidechain: claudeIsSidechain,
                claudePathRole: claudePathRole)
        }

        private static func counted(_ totals: UsageTotals) -> UsageTotals {
            guard totals.requestCount == 0, totals.totalTokens > 0 || totals.costUSD > 0 else {
                return totals
            }
            var counted = totals
            counted.requestCount = 1
            return counted
        }
    }
    private struct FilePartial: Sendable, Codable {
        var records: [UsageRecord]
        var hadUsage: Bool
        var claudeAppendState: ClaudeAppendState? = nil
        var codexAppendState: CodexAppendState? = nil
        var piAppendState: PiAppendState? = nil
    }
    private enum FileKind: String, Sendable, Codable { case claude, codex, pi }
    private enum ClaudePathRole: String, Sendable, Codable { case parent, subagent }
    private struct ClaudeAppendState: Sendable, Codable {
        let project: String
    }
    private struct CodexAppendState: Sendable, Codable {
        let model: String
        let project: String
        let session: String?
        let metaDay: String?
        let lastUsage: CodexTokenUsage?
        let rawTotalsBaseline: CodexTokenUsage?
        let hasDivergentTotals: Bool
        let activeTurnID: String?
        let isForked: Bool
    }
    private struct PiAppendState: Sendable, Codable {
        let context: PiIdentity?
    }
    private struct ScanContext: Sendable {
        let daysBack: Int
        let startDay: String
        let endDay: String
        let cutoff: Date
        let claudeFiles: [URL]
        let codexFiles: [URL]
        let piFiles: [URL]
        let priorityTurns: [String: CodexPriorityTurn]
    }
    private struct FileStamp: Sendable, Codable, Equatable {
        let modificationUnixMs: Int64
        let size: Int64
        let fileIdentity: String?
        let contentSignature: String?
    }
    private struct FileCacheEntry: Sendable, Codable {
        let kind: FileKind
        let stamp: FileStamp
        let partial: FilePartial
        let parsedBytes: Int64?
    }
    private struct FileCacheArtifact: Sendable, Codable {
        var version = 1
        var parserVersion: Int = UsageScanner.fileCacheParserVersion
        var pricingStamp: FileStamp?
        var builtInPricingKey: String = UsageScanner.builtInPricingKey()
        var priorityMetadataKey: String?
        var files: [String: FileCacheEntry] = [:]
    }
    private struct PiIdentity: Sendable, Codable {
        let source: UsageSource
        let model: String
    }
    private struct CodexPriorityTurn: Sendable {
        let turnID: String
        let model: String?
        let timestampUnix: Int64?
        let rowID: Int64?
    }
    private struct CodexPriorityMemoState: Sendable {
        var coverageSinceEpoch: Int64
        var lastRowID: Int64
        var fileIdentity: UInt64?
        var fileStamp: FileStamp?
        var turns: [String: CodexPriorityTurn]
        var requestSourcesByTurnID: [String: [Int64: CodexPriorityTurn]]
        var completedModelsByTurnID: [String: [Int64: String]]
    }
    private struct CodexTokenSnapshot: Sendable {
        let timestamp: String
        let date: Date?
        let usage: CodexTokenUsage
    }
    private struct CodexFileIdentity: Sendable {
        let sessionID: String?
        let fileID: String?
    }
    private struct CodexForkCachedFile: Sendable {
        let path: String
        let stamp: FileStamp?
    }
    private struct CodexForkCachedSnapshots: Sendable {
        let stamp: FileStamp?
        let snapshots: [CodexTokenSnapshot]
    }
    private struct CodexForkLookupCache: Sendable {
        var fileBySessionID: [String: CodexForkCachedFile] = [:]
        var snapshotsBySessionID: [String: CodexForkCachedSnapshots] = [:]
    }
    private struct CodexTokenUsage: Sendable, Codable {
        let inputAll: Int
        let cached: Int
        let output: Int

        var uncachedInput: Int { max(0, inputAll - cached) }
        var totalTokens: Int { uncachedInput + cached + output }
        var clampedCached: CodexTokenUsage {
            CodexTokenUsage(inputAll: inputAll, cached: min(cached, inputAll), output: output)
        }

        static let zero = CodexTokenUsage(inputAll: 0, cached: 0, output: 0)
    }
    private struct CodexTokenDeltaState: Sendable {
        var previousTotals: CodexTokenUsage?
        var rawTotalsBaseline: CodexTokenUsage?
        var sawDivergentTotals = false

        var hasDivergentTotals: Bool {
            sawDivergentTotals && !UsageScanner.codexTokensEqual(rawTotalsBaseline, previousTotals)
        }
    }
    private struct CodexModeSplit: Sendable {
        var standardCostUSD = 0.0
        var priorityCostUSD = 0.0
        var standardTokens = 0
        var priorityTokens = 0

        var hasPriorityEvidence: Bool { priorityTokens > 0 }
    }
    private struct UncheckedSendable<T>: @unchecked Sendable { let value: T }
    private final class LockedState<State>: @unchecked Sendable {
        private let lock = NSLock()
        private var state: State

        init(_ state: State) {
            self.state = state
        }

        func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result {
            lock.lock()
            defer { lock.unlock() }
            return try body(&state)
        }
    }

    private static let fileCacheParserVersion = 21
    private static let codexActiveSessionLookbackDays = 30
    private static let codexPriorityMemo = LockedState<[String: CodexPriorityMemoState]>([:])
    private let codexForkLookupCache = LockedState(CodexForkLookupCache())

    public func scan(daysBack: Int = 30, now: Date = Date()) -> UsageReport {
        let context = makeScanContext(daysBack: daysBack, now: now)

        // 文件级并行解析（吃满多核）；Claude 跨文件全局去重（resume/fork 会复制历史消息）。
        let claudeParts = parallel(context.claudeFiles) {
            (try? self.processClaudeFile($0)) ?? FilePartial(records: [], hadUsage: false)
        }
        let codexParts = parallel(context.codexFiles) {
            (try? self.processCodexFile($0, priorityTurns: context.priorityTurns))
                ?? FilePartial(records: [], hadUsage: false)
        }
        let piParts = parallel(context.piFiles) {
            (try? self.processPiFile($0)) ?? FilePartial(records: [], hadUsage: false)
        }
        var report = buildReport(parts: claudeParts + codexParts + piParts, context: context, now: now)
        report.sourceInfo = UsageReportSourceInfo(
            source: .directScan,
            loadedAt: now)
        return report
    }

    public func scanWithFileCache(
        daysBack: Int = 30,
        now: Date = Date(),
        cacheRoot: URL? = nil,
        forceRescan: Bool = false,
        checkCancellation: (@Sendable () throws -> Void)? = nil) throws -> UsageReport
    {
        let context = makeScanContext(daysBack: daysBack, now: now)
        var cache = forceRescan ? FileCacheArtifact() : Self.loadFileCache(cacheRoot: cacheRoot)
        let pricingStamp = fileStamp(ModelsDevCache.cacheFileURL(cacheRoot: modelsDevCacheRoot ?? cacheRoot))
        let builtInPricingKey = Self.builtInPricingKey()
        let priorityMetadataKey = Self.priorityMetadataKey(context.priorityTurns)
        if cache.version != 1 ||
            cache.parserVersion != Self.fileCacheParserVersion ||
            cache.pricingStamp != pricingStamp ||
            cache.builtInPricingKey != builtInPricingKey
        {
            cache = FileCacheArtifact()
        } else if cache.priorityMetadataKey != priorityMetadataKey {
            cache.files = cache.files.filter { $0.value.kind != .codex }
        }
        cache.pricingStamp = pricingStamp
        cache.builtInPricingKey = builtInPricingKey
        cache.priorityMetadataKey = priorityMetadataKey

        var retainedPaths = Set<String>()
        let claudeParts = try cachedParts(
            files: context.claudeFiles,
            kind: .claude,
            cache: &cache,
            retainedPaths: &retainedPaths,
            checkCancellation: checkCancellation)
        let codexParts = try cachedParts(
            files: context.codexFiles,
            kind: .codex,
            cache: &cache,
            retainedPaths: &retainedPaths,
            priorityTurns: context.priorityTurns,
            checkCancellation: checkCancellation)
        let piParts = try cachedParts(
            files: context.piFiles,
            kind: .pi,
            cache: &cache,
            retainedPaths: &retainedPaths,
            checkCancellation: checkCancellation)

        cache.files = cache.files.filter { retainedPaths.contains($0.key) }
        Self.saveFileCache(cache, cacheRoot: cacheRoot)
        var report = buildReport(parts: claudeParts + codexParts + piParts, context: context, now: now)
        report.sourceInfo = UsageReportSourceInfo(
            source: .fileCacheScan,
            loadedAt: now,
            cachePath: Self.fileCacheFileURL(cacheRoot: cacheRoot).path,
            reason: forceRescan ? "force rescan" : nil)
        return report
    }

    public func corpusFingerprint(daysBack: Int = 30, now: Date = Date()) -> CostUsageCorpusFingerprint {
        try! corpusFingerprint(daysBack: daysBack, now: now, checkCancellation: nil)
    }

    func corpusFingerprint(
        daysBack: Int = 30,
        now: Date = Date(),
        checkCancellation: CancellationCheck?) throws -> CostUsageCorpusFingerprint
    {
        try checkCancellation?()
        let normalizedDays = max(1, min(365, daysBack))
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(normalizedDays - 1), to: todayStart) ?? todayStart
        let startDay = dayString(date: cutoff)
        let endDay = dayString(date: now)
        let sessionRoots = codexSessionRoots()
        let codexFiles = try codexSessionFiles(
            sinceDay: startDay,
            untilDay: endDay,
            modifiedAfter: cutoff,
            checkCancellation: checkCancellation)
        let roots = claudeProjectsDirs + sessionRoots + [piSessionsDir]
        let files = try jsonlFiles(in: claudeProjectsDirs, checkCancellation: checkCancellation)
            + piSessionFiles(modifiedAfter: cutoff, checkCancellation: checkCancellation)
            + codexFiles
        let pricingCacheFile = ModelsDevCache.cacheFileURL(cacheRoot: modelsDevCacheRoot)
        let metadataFiles = [pricingCacheFile].filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        var rootStamps: [String: Int64] = [:]
        for root in roots + metadataFiles {
            try checkCancellation?()
            rootStamps[root.path] = modificationUnixMs(root)
        }
        rootStamps["pricing:built-in"] =
            Int64(bitPattern: Self.stableHash(ModelPricing.builtInPricingFingerprint()))
        if let codexTraceDatabaseURL,
           FileManager.default.fileExists(atPath: codexTraceDatabaseURL.path)
        {
            try checkCancellation?()
            let priorityTurns = codexPriorityTurns(sinceDay: startDay, untilDay: endDay)
            rootStamps["codex-priority:\(codexTraceDatabaseURL.path)"] =
                Self.priorityMetadataIntKey(priorityTurns)
        }
        var fileCount = 0
        var totalBytes: Int64 = 0
        var newestModificationUnixMs: Int64 = 0
        for file in files + metadataFiles {
            try checkCancellation?()
            let metadata = fileMetadata(file)
            fileCount += 1
            totalBytes += metadata.size
            newestModificationUnixMs = max(newestModificationUnixMs, metadata.modificationUnixMs)
        }
        return CostUsageCorpusFingerprint(
            roots: rootStamps,
            fileCount: fileCount,
            totalBytes: totalBytes,
            newestModificationUnixMs: newestModificationUnixMs)
    }

    @discardableResult
    public static func clearFileCache(cacheRoot: URL? = nil) -> [URL] {
        let directory = fileCacheFileURL(cacheRoot: cacheRoot).deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)
        else { return [] }
        var removed: [URL] = []
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("file-cache-v"), name.hasSuffix(".json") else { continue }
            try? FileManager.default.removeItem(at: file)
            removed.append(file)
        }
        return removed
    }

    public static func fileCacheFileURL(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? defaultCacheRoot()
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("file-cache-v\(fileCacheParserVersion).json", isDirectory: false)
    }

    private func makeScanContext(daysBack: Int, now: Date) -> ScanContext {
        let normalizedDays = max(1, daysBack)
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(normalizedDays - 1), to: todayStart) ?? todayStart
        let startDay = dayString(date: windowStart)
        let endDay = dayString(date: now)
        let cutoff = windowStart
        return ScanContext(
            daysBack: daysBack,
            startDay: startDay,
            endDay: endDay,
            cutoff: cutoff,
            claudeFiles: jsonlFiles(in: claudeProjectsDirs),
            codexFiles: codexSessionFiles(sinceDay: startDay, untilDay: endDay, modifiedAfter: cutoff),
            piFiles: piSessionFiles(modifiedAfter: cutoff),
            priorityTurns: codexPriorityTurns(sinceDay: startDay, untilDay: endDay))
    }

    private struct FileWorkItem: Sendable {
        let index: Int
        let file: URL
        let kind: FileKind
        let stamp: FileStamp
        let cached: FileCacheEntry?
    }

    private struct FileWorkResult: Sendable {
        let index: Int
        let file: URL
        let kind: FileKind
        let stamp: FileStamp
        let processed: ProcessedFilePartial
    }

    private struct ProcessedFilePartial: Sendable {
        let partial: FilePartial
        let parsedBytes: Int64
    }

    private func cachedParts(
        files: [URL],
        kind: FileKind,
        cache: inout FileCacheArtifact,
        retainedPaths: inout Set<String>,
        priorityTurns: [String: CodexPriorityTurn] = [:],
        checkCancellation: CancellationCheck?) throws -> [FilePartial]
    {
        guard !files.isEmpty else { return [] }
        var parts = Array<FilePartial?>(repeating: nil, count: files.count)
        var work: [FileWorkItem] = []
        for (index, file) in files.enumerated() {
            try checkCancellation?()
            let path = fileCacheKey(file)
            retainedPaths.insert(path)
            guard let stamp = fileStamp(file) else { continue }
            if let cached = cache.files[path],
               cached.kind == kind,
               cached.stamp == stamp
            {
                parts[index] = cached.partial
            } else {
                let appendable = appendableCachedEntry(
                    cache.files[path],
                    kind: kind,
                    newStamp: stamp)
                work.append(FileWorkItem(index: index, file: file, kind: kind, stamp: stamp, cached: appendable))
            }
        }

        let results = try parallelItemsThrowing(work) { item in
            FileWorkResult(
                index: item.index,
                file: item.file,
                kind: item.kind,
                stamp: item.stamp,
                processed: try processFile(
                    item.file,
                    kind: item.kind,
                    priorityTurns: priorityTurns,
                    cached: item.cached,
                    checkCancellation: checkCancellation))
        }
        try checkCancellation?()
        for result in results {
            parts[result.index] = result.processed.partial
            cache.files[fileCacheKey(result.file)] = FileCacheEntry(
                kind: result.kind,
                stamp: result.stamp,
                partial: result.processed.partial,
                parsedBytes: result.processed.parsedBytes)
        }
        return parts.compactMap(\.self)
    }

    private func appendableCachedEntry(
        _ cached: FileCacheEntry?,
        kind: FileKind,
        newStamp: FileStamp) -> FileCacheEntry?
    {
        let parsedBytes = cached?.parsedBytes ?? cached?.stamp.size ?? 0
        guard let cached,
              cached.kind == kind,
              parsedBytes > 0,
              parsedBytes <= newStamp.size,
              newStamp.size > cached.stamp.size
        else { return nil }
        if let oldIdentity = cached.stamp.fileIdentity,
           let newIdentity = newStamp.fileIdentity,
           oldIdentity != newIdentity
        {
            return nil
        }
        switch kind {
        case .claude:
            return cached
        case .codex:
            return cached.partial.codexAppendState?.lastUsage == nil ? nil : cached
        case .pi:
            return cached
        }
    }

    private func processFile(
        _ file: URL,
        kind: FileKind,
        priorityTurns: [String: CodexPriorityTurn],
        cached: FileCacheEntry? = nil,
        checkCancellation: CancellationCheck? = nil) throws -> ProcessedFilePartial
    {
        let startOffset = cached?.parsedBytes ?? cached?.stamp.size ?? 0
        try checkCancellation?()
        let parsedBytes = try parsedJSONLBytes(
            file,
            startOffset: startOffset,
            checkCancellation: checkCancellation)
        switch kind {
        case .claude:
            if let cached,
               let appended = try processClaudeFileAppend(
                   file,
                   startOffset: startOffset,
                   cached: cached.partial,
                   checkCancellation: checkCancellation)
            {
                return ProcessedFilePartial(
                    partial: mergeFilePartials(cached.partial, appended),
                    parsedBytes: parsedBytes)
            }
            return ProcessedFilePartial(
                partial: try processClaudeFile(file, checkCancellation: checkCancellation),
                parsedBytes: try parsedJSONLBytes(file, checkCancellation: checkCancellation))
        case .codex:
            if let cached,
               let appended = try processCodexFileAppend(
                   file,
                   startOffset: startOffset,
                   cached: cached.partial,
                   priorityTurns: priorityTurns,
                   checkCancellation: checkCancellation)
            {
                return ProcessedFilePartial(
                    partial: mergeFilePartials(cached.partial, appended),
                    parsedBytes: parsedBytes)
            }
            return ProcessedFilePartial(
                partial: try processCodexFile(file, priorityTurns: priorityTurns, checkCancellation: checkCancellation),
                parsedBytes: try parsedJSONLBytes(file, checkCancellation: checkCancellation))
        case .pi:
            if let cached,
               let appended = try processPiFileAppend(
                   file,
                   startOffset: startOffset,
                   cached: cached.partial,
                   checkCancellation: checkCancellation)
            {
                return ProcessedFilePartial(
                    partial: mergeFilePartials(cached.partial, appended),
                    parsedBytes: parsedBytes)
            }
            return ProcessedFilePartial(
                partial: try processPiFile(file, checkCancellation: checkCancellation),
                parsedBytes: try parsedJSONLBytes(file, checkCancellation: checkCancellation))
        }
    }

    private func mergeFilePartials(_ cached: FilePartial, _ appended: FilePartial) -> FilePartial {
        let combinedRecords = cached.records + appended.records
        let records = combinedRecords.contains { $0.source == .claude || $0.source == .vertexai }
            ? Self.mergeClaudeInFileRecords(combinedRecords)
            : combinedRecords
        return FilePartial(
            records: records,
            hadUsage: cached.hadUsage || appended.hadUsage,
            claudeAppendState: appended.claudeAppendState ?? cached.claudeAppendState,
            codexAppendState: appended.codexAppendState ?? cached.codexAppendState,
            piAppendState: appended.piAppendState ?? cached.piAppendState)
    }

    private static func loadFileCache(cacheRoot: URL? = nil) -> FileCacheArtifact {
        let url = fileCacheFileURL(cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(FileCacheArtifact.self, from: data),
              decoded.version == 1,
              decoded.parserVersion == fileCacheParserVersion
        else { return FileCacheArtifact() }
        return decoded
    }

    private static func saveFileCache(_ cache: FileCacheArtifact, cacheRoot: URL? = nil) {
        let url = fileCacheFileURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        do {
            try data.write(to: tmp, options: [.atomic])
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Conductor", isDirectory: true)
    }

    private static func priorityMetadataKey(_ turns: [String: CodexPriorityTurn]) -> String {
        guard !turns.isEmpty else { return "empty" }
        let text = turns.keys.sorted().map { key in
            "\(key)=\(turns[key]?.model ?? "")"
        }.joined(separator: "\n")
        return String(format: "%016llx", stableHash(text))
    }

    private static func priorityMetadataIntKey(_ turns: [String: CodexPriorityTurn]) -> Int64 {
        Int64(bitPattern: stableHash(priorityMetadataKey(turns)))
    }

    private static func builtInPricingKey() -> String {
        "builtin-\(String(format: "%016llx", stableHash(ModelPricing.builtInPricingFingerprint())))"
    }

    private static func stableHash(_ text: String) -> UInt64 {
        stableHash(Data(text.utf8))
    }

    private static func stableHash(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return hash
    }

    private static func defaultCodexSessionsDir(home: URL) -> URL {
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
        }
        return home.appendingPathComponent(".codex/sessions", isDirectory: true)
    }

    private static func defaultCodexArchivedSessionsDir(sessionsDir: URL) -> URL? {
        guard sessionsDir.lastPathComponent == "sessions" else { return nil }
        return sessionsDir
            .deletingLastPathComponent()
            .appendingPathComponent("archived_sessions", isDirectory: true)
    }

    private func codexSessionRoots() -> [URL] {
        var roots = [codexSessionsDir]
        if let codexArchivedSessionsDir {
            roots.append(codexArchivedSessionsDir)
        }
        return roots
    }

    private func codexPriorityTurns(sinceDay: String, untilDay: String) -> [String: CodexPriorityTurn] {
        guard let url = codexTraceDatabaseURL,
              FileManager.default.fileExists(atPath: url.path) else { return [:] }

        #if canImport(SQLite3)
        guard let opened = openCodexPriorityDatabase(at: url) else { return [:] }
        let db = opened.db
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        let since = epochSeconds(dayKey: sinceDay) ?? 0
        let until = (epochSeconds(dayKey: untilDay) ?? Int64.max - 86_399) + 86_399
        guard let maxRowID = maxCodexLogsRowID(db) else { return [:] }

        var state = Self.codexPriorityMemo.withLock { $0[url.path] }
        if let memo = state,
           maxRowID < memo.lastRowID
               || since < memo.coverageSinceEpoch
               || memo.fileIdentity != opened.fileIdentity
               || (maxRowID == memo.lastRowID && memo.fileStamp != opened.fileStamp)
        {
            state = nil
        }

        var resolved = state ?? CodexPriorityMemoState(
            coverageSinceEpoch: since,
            lastRowID: 0,
            fileIdentity: opened.fileIdentity,
            fileStamp: opened.fileStamp,
            turns: [:],
            requestSourcesByTurnID: [:],
            completedModelsByTurnID: [:])

        if state != nil {
            var pruned = resolved
            if pruneDeletedCodexPrioritySources(db, from: &pruned) {
                storeCodexPriorityMemoIfNewer(pruned, forPath: url.path, allowSameCursor: true)
                resolved = pruned
            }
        }

        if maxRowID > resolved.lastRowID {
            var updated = resolved
            guard accumulateCodexPriorityTurns(db, into: &updated) else {
                return filterCodexPriorityTurns(resolved, since: since, until: until)
            }
            updated.lastRowID = maxRowID
            updated.fileIdentity = opened.fileIdentity
            updated.fileStamp = opened.fileStamp
            storeCodexPriorityMemoIfNewer(updated, forPath: url.path)
            resolved = updated
        } else if state == nil {
            storeCodexPriorityMemoIfNewer(resolved, forPath: url.path)
        }

        return filterCodexPriorityTurns(resolved, since: since, until: until)
        #else
        _ = sinceDay
        _ = untilDay
        return [:]
        #endif
    }

    #if canImport(SQLite3)
    private func filterCodexPriorityTurns(
        _ state: CodexPriorityMemoState,
        since: Int64,
        until: Int64) -> [String: CodexPriorityTurn]
    {
        var turns = state.turns
        for (turnID, modelsByRowID) in state.completedModelsByTurnID {
            guard let existing = turns[turnID],
                  let model = latestCodexCompletedModel(modelsByRowID)
            else { continue }
            turns[turnID] = CodexPriorityTurn(
                turnID: existing.turnID,
                model: model,
                timestampUnix: existing.timestampUnix,
                rowID: existing.rowID)
        }
        return turns.filter { _, turn in
            guard let timestamp = turn.timestampUnix else { return true }
            return timestamp >= since && timestamp <= until
        }
    }

    private func storeCodexPriorityMemoIfNewer(
        _ updated: CodexPriorityMemoState,
        forPath path: String,
        allowSameCursor: Bool = false)
    {
        Self.codexPriorityMemo.withLock { memo in
            if !allowSameCursor,
               let existing = memo[path],
               existing.fileIdentity == updated.fileIdentity,
               existing.fileStamp == updated.fileStamp,
               existing.lastRowID >= updated.lastRowID,
               existing.coverageSinceEpoch <= updated.coverageSinceEpoch
            {
                return
            }
            memo[path] = updated
        }
    }

    private func accumulateCodexPriorityTurns(
        _ db: OpaquePointer?,
        into state: inout CodexPriorityMemoState) -> Bool
    {
        let sql: String
        if state.lastRowID == 0 {
            sql = """
                select rowid, ts, feedback_log_body
                from logs
                where ts >= ?
                  and (feedback_log_body like '%websocket request:%'
                       or feedback_log_body like '%response.completed%')
                order by rowid asc
                """
        } else {
            sql = """
                select rowid, ts, feedback_log_body
                from logs
                where rowid > ? and ts >= ?
                  and (feedback_log_body like '%websocket request:%'
                       or feedback_log_body like '%response.completed%')
                order by rowid asc
                """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        if state.lastRowID == 0 {
            sqlite3_bind_int64(stmt, 1, state.coverageSinceEpoch)
        } else {
            sqlite3_bind_int64(stmt, 1, state.lastRowID)
            sqlite3_bind_int64(stmt, 2, state.coverageSinceEpoch)
        }

        while true {
            let stepResult = sqlite3_step(stmt)
            guard stepResult == SQLITE_ROW else { return stepResult == SQLITE_DONE }
            let rowID = sqlite3_column_int64(stmt, 0)
            let timestamp = sqlite3_column_int64(stmt, 1)
            guard let bodyCString = sqlite3_column_text(stmt, 2) else { continue }
            let body = String(cString: bodyCString)
            if let completed = parseCodexCompletedTraceRow(body: body) {
                state.completedModelsByTurnID[completed.turnID, default: [:]][rowID] = completed.model
                continue
            }
            guard var parsed = parseCodexPriorityTraceRow(timestamp: timestamp, body: body) else { continue }
            parsed = CodexPriorityTurn(
                turnID: parsed.turnID,
                model: parsed.model,
                timestampUnix: parsed.timestampUnix,
                rowID: rowID)
            state.requestSourcesByTurnID[parsed.turnID, default: [:]][rowID] = parsed
            state.turns[parsed.turnID] = latestCodexPriorityTurn(
                state.requestSourcesByTurnID[parsed.turnID] ?? [:]) ?? parsed
        }
    }

    private func pruneDeletedCodexPrioritySources(
        _ db: OpaquePointer?,
        from state: inout CodexPriorityMemoState) -> Bool
    {
        let rowIDs =
            state.requestSourcesByTurnID.values.flatMap(\.keys) +
            state.completedModelsByTurnID.values.flatMap(\.keys)
        guard !rowIDs.isEmpty, let retained = retainedCodexPriorityRowIDs(db, rowIDs: rowIDs) else {
            return false
        }
        var didPrune = false
        for (turnID, sources) in state.requestSourcesByTurnID {
            let retainedSources = sources.filter { retained.contains($0.key) }
            guard retainedSources.count != sources.count else { continue }
            didPrune = true
            if retainedSources.isEmpty {
                state.requestSourcesByTurnID.removeValue(forKey: turnID)
                state.turns.removeValue(forKey: turnID)
            } else {
                state.requestSourcesByTurnID[turnID] = retainedSources
                state.turns[turnID] = latestCodexPriorityTurn(retainedSources)
            }
        }
        for (turnID, completions) in state.completedModelsByTurnID {
            let retainedCompletions = completions.filter { retained.contains($0.key) }
            guard retainedCompletions.count != completions.count else { continue }
            didPrune = true
            if retainedCompletions.isEmpty {
                state.completedModelsByTurnID.removeValue(forKey: turnID)
            } else {
                state.completedModelsByTurnID[turnID] = retainedCompletions
            }
        }
        return didPrune
    }

    private func latestCodexPriorityTurn(_ sources: [Int64: CodexPriorityTurn]) -> CodexPriorityTurn? {
        sources.max { $0.key < $1.key }?.value
    }

    private func latestCodexCompletedModel(_ modelsByRowID: [Int64: String]) -> String? {
        modelsByRowID.max { $0.key < $1.key }?.value
    }

    private func retainedCodexPriorityRowIDs(_ db: OpaquePointer?, rowIDs: [Int64]) -> Set<Int64>? {
        guard !rowIDs.isEmpty else { return [] }
        var retained: Set<Int64> = []
        let chunkSize = 500
        for start in stride(from: 0, to: rowIDs.count, by: chunkSize) {
            let chunk = Array(rowIDs[start..<min(start + chunkSize, rowIDs.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let query = "select rowid from logs where rowid in (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            for (offset, rowID) in chunk.enumerated() {
                sqlite3_bind_int64(stmt, Int32(offset + 1), rowID)
            }
            while true {
                let stepResult = sqlite3_step(stmt)
                if stepResult == SQLITE_DONE { break }
                guard stepResult == SQLITE_ROW else { return nil }
                retained.insert(sqlite3_column_int64(stmt, 0))
            }
        }
        return retained
    }

    private func maxCodexLogsRowID(_ db: OpaquePointer?) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "select max(rowid) from logs", -1, &stmt, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    private func openCodexPriorityDatabase(at url: URL) -> (db: OpaquePointer?, fileIdentity: UInt64?, fileStamp: FileStamp?)? {
        let identity = codexPriorityDatabaseFileIdentity(at: url)
        let stamp = fileStamp(url)
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        guard codexPriorityDatabaseFileIdentity(at: url) == identity,
              fileStamp(url) == stamp
        else {
            sqlite3_close(db)
            return nil
        }
        return (db, identity, stamp)
    }

    private func codexPriorityDatabaseFileIdentity(at url: URL) -> UInt64? {
        guard let value = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.systemFileNumber]
        else { return nil }
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let int = value as? Int {
            return UInt64(int)
        }
        return nil
    }
    #endif

    private func parseCodexPriorityTraceRow(timestamp: Int64, body: String) -> CodexPriorityTurn? {
        let marker = "websocket request:"
        guard let markerRange = body.range(of: marker) else { return nil }
        let prefix = String(body[..<markerRange.lowerBound])
        let jsonText = body[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              request["type"] as? String == "response.create",
              request["service_tier"] as? String == "priority"
        else { return nil }

        let turnID = value(named: "turn.id", in: prefix)
            ?? value(named: "turn_id", in: prefix)
            ?? stringValue(request["turn_id"])
        guard let turnID, !turnID.isEmpty else { return nil }
        return CodexPriorityTurn(
            turnID: turnID,
            model: stringValue(request["model"]),
            timestampUnix: timestamp,
            rowID: nil)
    }

    private func parseCodexCompletedTraceRow(body: String) -> (turnID: String, model: String)? {
        let marker = "websocket event:"
        guard let markerRange = body.range(of: marker) else { return nil }
        let prefix = String(body[..<markerRange.lowerBound])
        let jsonText = body[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = jsonText.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              event["type"] as? String == "response.completed",
              let response = event["response"] as? [String: Any],
              let model = stringValue(response["model"]),
              !model.isEmpty
        else { return nil }

        let turnID = value(named: "turn.id", in: prefix)
            ?? value(named: "turn_id", in: prefix)
        guard let turnID, !turnID.isEmpty else { return nil }
        return (turnID, model)
    }

    private func value(named name: String, in text: String) -> String? {
        guard let range = text.range(of: "\(name)=") else { return nil }
        let tail = text[range.upperBound...]
        let value = tail.prefix { char in
            !char.isWhitespace && char != "," && char != "]" && char != ")"
        }
        return value.isEmpty ? nil : String(value)
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

    private func parallelItems<Item: Sendable, T: Sendable>(
        _ items: [Item],
        _ body: @escaping @Sendable (Item) -> T) -> [T]
    {
        let count = items.count
        guard count > 0 else { return [] }
        let storage = UnsafeMutableBufferPointer<T>.allocate(capacity: count)
        let box = UncheckedSendable(value: storage)
        let itemsBox = UncheckedSendable(value: items)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            box.value.baseAddress!.advanced(by: i).initialize(to: body(itemsBox.value[i]))
        }
        let out = Array(storage)
        storage.baseAddress!.deinitialize(count: count)
        storage.deallocate()
        return out
    }

    private func parallelItemsThrowing<Item: Sendable, T: Sendable>(
        _ items: [Item],
        _ body: @escaping @Sendable (Item) throws -> T) throws -> [T]
    {
        let count = items.count
        guard count > 0 else { return [] }
        let results = LockedState(Array<T?>(repeating: nil, count: count))
        let firstError = LockedState<Error?>(nil)
        let itemsBox = UncheckedSendable(value: items)
        DispatchQueue.concurrentPerform(iterations: count) { i in
            if firstError.withLock({ $0 != nil }) {
                return
            }
            do {
                let value = try body(itemsBox.value[i])
                results.withLock { $0[i] = value }
            } catch {
                firstError.withLock { stored in
                    if stored == nil {
                        stored = error
                    }
                }
            }
        }
        if let error = firstError.withLock({ $0 }) {
            throw error
        }
        return results.withLock { $0.compactMap(\.self) }
    }

    private func checkCancellationIfNeeded(
        _ checkCancellation: CancellationCheck?,
        counter: inout Int,
        every interval: Int = 64,
        capturedError: inout Error?,
        stop: inout Bool)
    {
        counter += 1
        guard interval <= 1 || counter % interval == 0 else { return }
        do {
            try checkCancellation?()
        } catch {
            capturedError = error
            stop = true
        }
    }

    private func checkCancellationIfNeeded(
        _ checkCancellation: CancellationCheck?,
        counter: inout Int,
        every interval: Int = 64) throws
    {
        counter += 1
        guard interval <= 1 || counter % interval == 0 else { return }
        try checkCancellation?()
    }

    private func throwCapturedCancellation(_ error: Error?) throws {
        if let error {
            throw error
        }
    }

    // MARK: - Claude

    private func processClaudeFile(
        _ file: URL,
        checkCancellation: CancellationCheck? = nil) throws -> FilePartial
    {
        var records: [UsageRecord] = []
        var fileHadUsage = false
        try checkCancellation?()
        let session = Self.sessionKey(file: file)
        let sourcePath = file.path
        let pathRole = Self.claudePathRole(file: file)
        var project = ""   // 取文件里第一条带 cwd 的行（会话工作目录）
        var lineCounter = 0
        do {
            try scanJSONLLines(
                file,
                maxLineBytes: Self.claudeJSONLPrefixBytes,
                prefixBytes: Self.claudeJSONLPrefixBytes,
                checkCancellation: checkCancellation) { line, wasTruncated in
                try checkCancellationIfNeeded(checkCancellation, counter: &lineCounter)
                guard !wasTruncated else { return }
                if project.isEmpty, line.contains("\"cwd\":\""),
                   let cwd = Self.quotedValue(in: line, afterKey: "\"cwd\":\""), cwd.hasPrefix("/") {
                    project = cwd
                }
                guard let record = claudeUsageRecord(
                    from: line,
                    fileSession: session,
                    project: project,
                    sourcePath: sourcePath,
                    pathRole: pathRole)
                else { return }
                records.append(record)
                fileHadUsage = true
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return FilePartial(records: records, hadUsage: false)
        }
        // cwd 可能晚于首条用量行出现，统一回填。
        records = Self.mergeClaudeInFileRecords(records)
        if !project.isEmpty {
            records = records.map { r in
                r.project.isEmpty ? r.replacingProject(project) : r
            }
        }
        return FilePartial(
            records: records,
            hadUsage: fileHadUsage,
            claudeAppendState: ClaudeAppendState(project: project))
    }

    private func processClaudeFileAppend(
        _ file: URL,
        startOffset: Int64,
        cached: FilePartial,
        checkCancellation: CancellationCheck? = nil) throws -> FilePartial?
    {
        try checkCancellation?()
        let session = Self.sessionKey(file: file)
        let sourcePath = file.path
        let pathRole = Self.claudePathRole(file: file)
        var project = cached.claudeAppendState?.project ?? cached.records.first(where: { !$0.project.isEmpty })?.project ?? ""
        var records: [UsageRecord] = []
        var lineCounter = 0
        do {
            try scanJSONLLines(
                file,
                startOffset: startOffset,
                maxLineBytes: Self.claudeJSONLPrefixBytes,
                prefixBytes: Self.claudeJSONLPrefixBytes,
                checkCancellation: checkCancellation) { line, wasTruncated in
                try checkCancellationIfNeeded(checkCancellation, counter: &lineCounter)
                guard !wasTruncated else { return }
                if line.contains("\"cwd\":\""),
                   let cwd = Self.quotedValue(in: line, afterKey: "\"cwd\":\""), cwd.hasPrefix("/") {
                    project = cwd
                }
                guard let record = claudeUsageRecord(
                    from: line,
                    fileSession: session,
                    project: project,
                    sourcePath: sourcePath,
                    pathRole: pathRole)
                else { return }
                records.append(record)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        records = Self.mergeClaudeInFileRecords(records)
        if !project.isEmpty {
            records = records.map { record in
                record.project.isEmpty ? record.replacingProject(project) : record
            }
        }
        return FilePartial(
            records: records,
            hadUsage: !records.isEmpty,
            claudeAppendState: ClaudeAppendState(project: project))
    }

    private func claudeOneHourCacheCreationTokens(usage: [String: Any], total: Int) -> Int {
        guard let cacheCreation = usage["cache_creation"] as? [String: Any] else { return 0 }
        let tokens = intValue(cacheCreation["ephemeral_1h_input_tokens"])
        return min(max(0, tokens), max(0, total))
    }

    private static func claudePathRole(file: URL) -> ClaudePathRole {
        file.path.contains("/subagents/") ? .subagent : .parent
    }

    private func claudeUsageRecord(
        from line: String,
        fileSession: String,
        project: String,
        sourcePath: String,
        pathRole: ClaudePathRole) -> UsageRecord?
    {
        guard line.contains(#""assistant""#), line.contains(#""usage""#),
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let timestampText = stringValue(obj["timestamp"]),
              let timestamp = parseTimestamp(timestampText),
              let message = obj["message"] as? [String: Any],
              let model = stringValue(message["model"]),
              !model.isEmpty,
              let usage = message["usage"] as? [String: Any]
        else { return nil }
        if model == "<synthetic>" { return nil }

        let input = nonNegativeInt(usage["input_tokens"])
        let output = nonNegativeInt(usage["output_tokens"])
        let cacheWrite = nonNegativeInt(usage["cache_creation_input_tokens"])
        let cacheWrite1h = claudeOneHourCacheCreationTokens(usage: usage, total: cacheWrite)
        let cacheRead = nonNegativeInt(usage["cache_read_input_tokens"])
        if input + output + cacheWrite + cacheRead == 0 { return nil }

        let messageID = stringValue(message["id"]).flatMap { $0.isEmpty ? nil : $0 }
        let requestID = stringValue(obj["requestId"]).flatMap { $0.isEmpty ? nil : $0 }
        let dedupKey = messageID.flatMap { messageID in
            requestID.map { "\(messageID):\($0)" }
        } ?? UUID().uuidString
        let session = stringValue(
            obj["sessionId"]
                ?? obj["session_id"]
                ?? (obj["metadata"] as? [String: Any])?["sessionId"]
                ?? (message["metadata"] as? [String: Any])?["sessionId"])
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? fileSession
        let isSidechain = boolValue(obj["isSidechain"])
        let source: UsageSource = Self.isVertexAIUsageEntry(obj: obj) ? .vertexai : .claude

        let pricing = ModelPricing.forModel(model, cacheRoot: modelsDevCacheRoot, pricingDate: timestamp)
        var totals = UsageTotals()
        totals.inputTokens = input
        totals.outputTokens = output
        totals.cacheCreationTokens = cacheWrite
        totals.cacheReadTokens = cacheRead
        totals.costUSD = pricing.cost(
            input: input,
            output: output,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead,
            cacheWrite1h: cacheWrite1h)
        return UsageRecord(
            dedupKey: dedupKey,
            day: dayString(date: timestamp),
            source: source,
            session: session,
            model: normalizeModel(model),
            project: project,
            totals: totals,
            sourcePath: sourcePath,
            claudeMessageID: messageID,
            claudeRequestID: requestID,
            claudeIsSidechain: isSidechain,
            claudePathRole: pathRole)
    }

    private func boolValue(_ any: Any?) -> Bool {
        if let bool = any as? Bool { return bool }
        if let number = any as? NSNumber { return number.boolValue }
        if let text = any as? String {
            return ["true", "1", "yes"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return false
    }

    private static let vertexProviderKeys: Set<String> = [
        "provider",
        "platform",
        "backend",
        "api_provider",
        "apiprovider",
        "api_type",
        "apitype",
        "source",
        "vendor",
        "client",
    ]

    private static func isVertexAIUsageEntry(obj: [String: Any]) -> Bool {
        if let message = obj["message"] as? [String: Any],
           let messageID = message["id"] as? String,
           messageID.contains("_vrtx_")
        {
            return true
        }
        if let requestID = obj["requestId"] as? String,
           requestID.contains("_vrtx_")
        {
            return true
        }
        if let message = obj["message"] as? [String: Any],
           let model = message["model"] as? String,
           modelNameLooksVertex(model)
        {
            return true
        }

        var candidates: [[String: Any]] = [obj]
        if let metadata = obj["metadata"] as? [String: Any] { candidates.append(metadata) }
        if let request = obj["request"] as? [String: Any] { candidates.append(request) }
        if let context = obj["context"] as? [String: Any] { candidates.append(context) }
        if let client = obj["client"] as? [String: Any] { candidates.append(client) }
        if let message = obj["message"] as? [String: Any] {
            if let metadata = message["metadata"] as? [String: Any] { candidates.append(metadata) }
            if let request = message["request"] as? [String: Any] { candidates.append(request) }
        }
        return candidates.contains { containsVertexAIMetadata(in: $0) }
    }

    private static func modelNameLooksVertex(_ model: String) -> Bool {
        model.hasPrefix("claude-") && model.contains("@")
    }

    private static func containsVertexAIMetadata(in dict: [String: Any]) -> Bool {
        for (key, value) in dict {
            let lowerKey = key.lowercased()
            if lowerKey.contains("vertex") || lowerKey.contains("gcp") {
                return true
            }
            if vertexProviderKeys.contains(lowerKey),
               let text = value as? String,
               stringLooksVertex(text)
            {
                return true
            }
            if let nested = value as? [String: Any], containsVertexAIMetadata(in: nested) {
                return true
            }
            if let array = value as? [Any], containsVertexAIMetadata(in: array) {
                return true
            }
        }
        return false
    }

    private static func containsVertexAIMetadata(in array: [Any]) -> Bool {
        for entry in array {
            if let dict = entry as? [String: Any], containsVertexAIMetadata(in: dict) {
                return true
            }
        }
        return false
    }

    private static func stringLooksVertex(_ value: String) -> Bool {
        value.lowercased().contains("vertex")
    }

    private static func mergeClaudeInFileRecords(_ records: [UsageRecord]) -> [UsageRecord] {
        var keyed: [String: UsageRecord] = [:]
        var unkeyed: [UsageRecord] = []
        for record in records {
            guard let key = record.claudeCanonicalKey else {
                unkeyed.append(record)
                continue
            }
            keyed[key] = record
        }
        return keyed.keys.sorted().compactMap { keyed[$0] } + unkeyed
    }

    private static func claudeRecordWins(candidate: UsageRecord, existing: UsageRecord) -> Bool {
        let candidateSidechain = candidate.claudeIsSidechain == true
        let existingSidechain = existing.claudeIsSidechain == true
        if candidateSidechain != existingSidechain {
            return existingSidechain
        }
        let candidateRole = candidate.claudePathRole ?? .parent
        let existingRole = existing.claudePathRole ?? .parent
        if candidateRole != existingRole {
            return existingRole == .subagent
        }
        return (candidate.sourcePath ?? "") < (existing.sourcePath ?? "")
    }

    private static func reconciledUsageRecords(_ records: [UsageRecord]) -> [UsageRecord] {
        var ordinary: [UsageRecord] = []
        var ordinarySeen = Set<String>()
        var claudeWinners: [String: UsageRecord] = [:]

        for record in records {
            if let key = record.claudeCanonicalKey {
                if let existing = claudeWinners[key] {
                    if claudeRecordWins(candidate: record, existing: existing) {
                        claudeWinners[key] = record
                    }
                } else {
                    claudeWinners[key] = record
                }
                continue
            }

            if let key = record.dedupKey {
                if ordinarySeen.contains(key) { continue }
                ordinarySeen.insert(key)
            }
            ordinary.append(record)
        }

        ordinary.append(contentsOf: claudeWinners.keys.sorted().compactMap { claudeWinners[$0] })
        return ordinary
    }

    // MARK: - Codex

    private func codexTurnCost(
        rowModel: String,
        turn: CodexPriorityTurn?,
        usage: CodexTokenUsage) -> (model: String, costUSD: Double)
    {
        let priorityInputTokens = usage.inputAll
        let priorityMetadataModel = turn?.model
        let pricedModel: String
        if let priorityMetadataModel,
           ModelPricing.codexPriorityForModel(priorityMetadataModel, inputTokens: priorityInputTokens) != nil
        {
            pricedModel = priorityMetadataModel
        } else {
            pricedModel = rowModel
        }

        let baseCost = ModelPricing.forModel(pricedModel, cacheRoot: modelsDevCacheRoot).cost(
            input: usage.uncachedInput,
            output: usage.output,
            cacheWrite: 0,
            cacheRead: usage.cached)
        guard turn != nil,
              let priorityPricing = ModelPricing.codexPriorityForModel(pricedModel, inputTokens: priorityInputTokens)
        else {
            return (pricedModel, baseCost)
        }
        let priorityCost = priorityPricing.cost(
            input: usage.uncachedInput,
            output: usage.output,
            cacheWrite: 0,
            cacheRead: usage.cached)
        return (pricedModel, max(priorityCost, baseCost))
    }

    private func processCodexFile(
        _ file: URL,
        priorityTurns: [String: CodexPriorityTurn],
        checkCancellation: CancellationCheck? = nil) throws -> FilePartial
    {
        try checkCancellation?()
        let fallbackModel = "gpt-5-codex"
        var currentModel = fallbackModel
        var project = ""
        var metaDay: String?
        var lastRawUsage: CodexTokenUsage?
        var deltaState = CodexTokenDeltaState()
        var activeTurnID: String?
        var sessionID: String?
        var forkedFromID: String?
        var forkTimestamp: String?
        var lastTokenDay: String?
        var split = CodexModeSplit()
        var deltaRecords: [UsageRecord] = []
        var lineCounter = 0
        do {
            try scanJSONLLines(
                file,
                maxLineBytes: Self.codexJSONLPrefixBytes,
                prefixBytes: Self.codexJSONLPrefixBytes,
                checkCancellation: checkCancellation) { line, wasTruncated in
                try checkCancellationIfNeeded(checkCancellation, counter: &lineCounter)
                let isToken = line.contains("token_count")
                let isMeta = line.contains("session_meta")
                let isTaskStarted = line.contains("\"task_started\"")
                let isTurnContext = line.contains("\"turn_context\"")
                guard isToken || isMeta || isTaskStarted || isTurnContext else { return }   // 只解析需要的行
                if wasTruncated {
                    if isTurnContext, let model = Self.codexTurnContextModelPrefix(in: line) {
                        currentModel = model
                    }
                    return
                }
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                let payload = obj["payload"] as? [String: Any]
                if isMeta, (obj["type"] as? String) == "session_meta" {
                    metaDay = metaDay
                        ?? dayString(fromISO: obj["timestamp"] as? String)
                        ?? dayString(fromISO: payload?["timestamp"] as? String)
                    sessionID = sessionID
                        ?? stringValue(payload?["id"] ?? payload?["session_id"] ?? payload?["sessionId"] ?? obj["session_id"] ?? obj["sessionId"])
                    forkedFromID = forkedFromID ?? codexForkParentID(from: payload)
                    forkTimestamp = forkTimestamp ?? stringValue(payload?["timestamp"] ?? obj["timestamp"])
                    if project.isEmpty,
                       let cwd = stringValue(payload?["cwd"] ?? payload?["workingDirectory"] ?? obj["cwd"]),
                       cwd.hasPrefix("/")
                    {
                        project = cwd
                    }
                    if let model = stringValue(payload?["model"] ?? obj["model"]), !model.isEmpty {
                        currentModel = model
                    }
                }
                if isTaskStarted, (payload?["type"] as? String) == "task_started" {
                    activeTurnID = stringValue(payload?["turn_id"] ?? payload?["turnId"] ?? payload?["id"])
                }
                if isTurnContext, (obj["type"] as? String) == "turn_context" {
                    if let model = stringValue(payload?["model"] ?? (payload?["info"] as? [String: Any])?["model"]) {
                        currentModel = model
                    }
                    if project.isEmpty,
                       let cwd = stringValue(payload?["cwd"] ?? (payload?["info"] as? [String: Any])?["cwd"]),
                       cwd.hasPrefix("/")
                    {
                        project = cwd
                    }
                }
                if (payload?["type"] as? String) == "token_count",
                   let info = payload?["info"] as? [String: Any] {
                    lastTokenDay = dayString(fromISO: obj["timestamp"] as? String)
                        ?? dayString(fromISO: payload?["timestamp"] as? String)
                        ?? lastTokenDay
                    let usage = (info["total_token_usage"] as? [String: Any]).map(codexTokenUsage)
                    if let usage {
                        lastRawUsage = usage
                    }
                    let last = (info["last_token_usage"] as? [String: Any]).map(codexTokenUsage)
                    guard usage != nil || last != nil else { return }
                    if let rawDelta = codexTokenRowDelta(last: last, total: usage, state: &deltaState),
                       rawDelta.totalTokens > 0
                    {
                        let delta = rawDelta.clampedCached
                        let turn = activeTurnID.flatMap { priorityTurns[$0] }
                        let modelFromInfo = stringValue(info["model"] ?? info["model_name"] ?? payload?["model"] ?? obj["model"])
                        let rowModel = currentModel.isEmpty ? modelFromInfo ?? fallbackModel : currentModel
                        let priced = codexTurnCost(rowModel: rowModel, turn: turn, usage: delta)
                        let splitModel = priced.model
                        let cost = priced.costUSD
                        if turn == nil {
                            split.standardCostUSD += cost
                            split.standardTokens += delta.totalTokens
                        } else {
                            split.priorityCostUSD += cost
                            split.priorityTokens += delta.totalTokens
                        }
                        if forkedFromID == nil {
                            let day = dayString(fromISO: obj["timestamp"] as? String)
                                ?? metaDay
                                ?? dayString(fromCodexPath: file)
                                ?? dayString(date: fileModified(file))
                            var totals = UsageTotals()
                            totals.inputTokens = delta.uncachedInput
                            totals.outputTokens = delta.output
                            totals.cacheReadTokens = delta.cached
                            totals.costUSD = cost
                            deltaRecords.append(UsageRecord(
                                dedupKey: nil,
                                day: day,
                                source: .codex,
                                session: nil,
                                model: normalizeModel(splitModel),
                                project: project,
                                totals: totals,
                                standardCostUSD: turn == nil ? cost : nil,
                                priorityCostUSD: turn == nil ? nil : cost,
                                standardTokens: turn == nil ? delta.totalTokens : nil,
                                priorityTokens: turn == nil ? nil : delta.totalTokens))
                        }
                    }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return FilePartial(records: [], hadUsage: false)
        }
        guard let rawUsage = lastRawUsage ?? deltaState.rawTotalsBaseline ?? deltaState.previousTotals else {
            return FilePartial(records: [], hadUsage: false)
        }
        if rawUsage.totalTokens == 0 {
            return FilePartial(records: [], hadUsage: false)
        }
        let forkBaseline = codexForkBaseline(
            parentSessionID: forkedFromID,
            forkTimestamp: forkTimestamp,
            currentSessionID: sessionID)
        if forkedFromID != nil, forkBaseline == nil {
            return FilePartial(records: [], hadUsage: false)
        }
        let usage = forkBaseline.map { codexTokenDelta(from: $0, to: rawUsage) ?? rawUsage } ?? rawUsage
        if usage.totalTokens == 0 {
            return FilePartial(
                records: [],
                hadUsage: false,
                codexAppendState: CodexAppendState(
                    model: currentModel.isEmpty ? fallbackModel : currentModel,
                    project: project,
                    session: Self.sessionKey(file: file, explicit: sessionID),
                    metaDay: metaDay,
                    lastUsage: deltaState.previousTotals ?? rawUsage,
                    rawTotalsBaseline: deltaState.rawTotalsBaseline ?? rawUsage,
                    hasDivergentTotals: deltaState.hasDivergentTotals,
                    activeTurnID: activeTurnID,
                    isForked: forkedFromID != nil))
        }

        let day = lastTokenDay ?? metaDay ?? dayString(fromCodexPath: file) ?? dayString(date: fileModified(file))
        let session = Self.sessionKey(file: file, explicit: sessionID)
        let finalModel = currentModel.isEmpty ? fallbackModel : currentModel
        if forkedFromID == nil, !deltaRecords.isEmpty {
            let sessionRecords = deltaRecords.map { record in
                UsageRecord(
                    dedupKey: record.dedupKey,
                    day: record.day,
                    source: record.source,
                    session: session,
                    model: record.model,
                    project: record.project.isEmpty ? project : record.project,
                    totals: record.totals,
                    standardCostUSD: record.standardCostUSD,
                    priorityCostUSD: record.priorityCostUSD,
                    standardTokens: record.standardTokens,
                    priorityTokens: record.priorityTokens)
            }
            return FilePartial(
                records: sessionRecords,
                hadUsage: true,
                codexAppendState: CodexAppendState(
                    model: finalModel,
                    project: project,
                    session: session,
                    metaDay: metaDay,
                    lastUsage: deltaState.previousTotals ?? rawUsage,
                    rawTotalsBaseline: deltaState.rawTotalsBaseline ?? rawUsage,
                    hasDivergentTotals: deltaState.hasDivergentTotals,
                    activeTurnID: activeTurnID,
                    isForked: false))
        }

        let countedUsage = usage.clampedCached
        let pricing = ModelPricing.forModel(finalModel, cacheRoot: modelsDevCacheRoot)
        let shouldUseModeSplit = split.hasPriorityEvidence && forkedFromID == nil
        var t = UsageTotals()
        t.inputTokens = countedUsage.uncachedInput
        t.outputTokens = countedUsage.output
        t.cacheReadTokens = countedUsage.cached
        t.costUSD = shouldUseModeSplit
            ? split.standardCostUSD + split.priorityCostUSD
            : pricing.cost(input: countedUsage.uncachedInput, output: countedUsage.output, cacheWrite: 0, cacheRead: countedUsage.cached)
        let record = UsageRecord(
            dedupKey: nil, day: day, source: .codex,
            session: session,
            model: normalizeModel(finalModel), project: project, totals: t,
            standardCostUSD: shouldUseModeSplit && split.standardTokens > 0 ? split.standardCostUSD : nil,
            priorityCostUSD: shouldUseModeSplit ? split.priorityCostUSD : nil,
            standardTokens: shouldUseModeSplit && split.standardTokens > 0 ? split.standardTokens : nil,
            priorityTokens: shouldUseModeSplit ? split.priorityTokens : nil)
        return FilePartial(
            records: [record],
            hadUsage: true,
            codexAppendState: CodexAppendState(
                model: finalModel,
                project: project,
                session: session,
                metaDay: metaDay,
                lastUsage: deltaState.previousTotals ?? rawUsage,
                rawTotalsBaseline: deltaState.rawTotalsBaseline ?? rawUsage,
                hasDivergentTotals: deltaState.hasDivergentTotals,
                activeTurnID: activeTurnID,
                isForked: forkedFromID != nil))
    }

    private func codexForkParentID(from payload: [String: Any]?) -> String? {
        guard let payload else { return nil }
        for key in ["forked_from_id", "forkedFromId", "parent_session_id", "parentSessionId"] {
            guard let value = stringValue(payload[key]), !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    private func codexForkBaseline(
        parentSessionID: String?,
        forkTimestamp: String?,
        currentSessionID: String?) -> CodexTokenUsage?
    {
        guard let parentSessionID, !parentSessionID.isEmpty,
              parentSessionID != currentSessionID,
              let forkTimestamp, !forkTimestamp.isEmpty,
              let parentFile = codexSessionFile(sessionID: parentSessionID)
        else { return nil }

        let forkDate = parseTimestamp(forkTimestamp)
        var inherited: CodexTokenUsage?
        for snapshot in codexTokenSnapshots(sessionID: parentSessionID, file: parentFile) {
            let isAtOrBefore: Bool
            if let snapshotDate = snapshot.date, let forkDate {
                isAtOrBefore = snapshotDate <= forkDate
            } else {
                isAtOrBefore = snapshot.timestamp <= forkTimestamp
            }
            if isAtOrBefore {
                inherited = snapshot.usage
            }
        }
        return inherited ?? CodexTokenUsage(inputAll: 0, cached: 0, output: 0)
    }

    private func codexSessionFile(sessionID: String) -> URL? {
        if let cached = cachedCodexSessionFile(sessionID: sessionID) {
            return cached
        }

        if let file = codexSessionFileByFilename(sessionID: sessionID) {
            rememberCodexSessionFile(file, sessionID: sessionID)
            return file
        }

        if let indexed = codexIndexSessionFilesUntilFound(sessionID: sessionID) {
            return indexed
        }

        return nil
    }

    private func cachedCodexSessionFile(sessionID: String) -> URL? {
        guard let cached = codexForkLookupCache.withLock({ $0.fileBySessionID[sessionID] }) else {
            return nil
        }
        let file = URL(fileURLWithPath: cached.path)
        guard let stamp = fileStamp(file) else {
            codexForkLookupCache.withLock { cache in
                cache.fileBySessionID.removeValue(forKey: sessionID)
                cache.snapshotsBySessionID.removeValue(forKey: sessionID)
            }
            return nil
        }
        guard stamp != cached.stamp else { return file }

        let metadata = codexSessionMetadata(in: file)
        guard metadata.sessionID == nil || metadata.sessionID == sessionID else {
            codexForkLookupCache.withLock { cache in
                if cache.fileBySessionID[sessionID]?.path == cached.path {
                    cache.fileBySessionID.removeValue(forKey: sessionID)
                    cache.snapshotsBySessionID.removeValue(forKey: sessionID)
                }
            }
            return nil
        }

        codexForkLookupCache.withLock { cache in
            cache.fileBySessionID[sessionID] = CodexForkCachedFile(path: file.path, stamp: stamp)
            cache.snapshotsBySessionID.removeValue(forKey: sessionID)
        }
        return file
    }

    private func rememberCodexSessionFile(_ file: URL, sessionID: String) {
        let stamp = fileStamp(file)
        codexForkLookupCache.withLock { cache in
            let previous = cache.fileBySessionID[sessionID]
            cache.fileBySessionID[sessionID] = CodexForkCachedFile(path: file.path, stamp: stamp)
            if previous?.path != file.path || previous?.stamp != stamp {
                cache.snapshotsBySessionID.removeValue(forKey: sessionID)
            }
        }
    }

    private func codexSessionFileByFilename(sessionID: String) -> URL? {
        for root in codexSessionRoots() {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                guard file.lastPathComponent.contains(sessionID) else { continue }
                let metadata = codexSessionMetadata(in: file)
                if metadata.sessionID == nil || metadata.sessionID == sessionID {
                    return file
                }
            }
        }
        return nil
    }

    private func codexIndexSessionFilesUntilFound(sessionID: String) -> URL? {
        var found: URL?
        for root in codexSessionRoots() {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            else { continue }
            for case let file as URL in enumerator where file.pathExtension == "jsonl" {
                let indexedSessionID = codexSessionMetadata(in: file).sessionID
                guard let indexedSessionID, !indexedSessionID.isEmpty else { continue }
                rememberCodexSessionFile(file, sessionID: indexedSessionID)
                if indexedSessionID == sessionID {
                    found = file
                }
            }
        }
        return found
    }

    private func codexSessionMetadata(in file: URL) -> (sessionID: String?, forkedFromID: String?, forkTimestamp: String?) {
        var metadata: (sessionID: String?, forkedFromID: String?, forkTimestamp: String?) = (nil, nil, nil)
        var didFind = false
        _ = try? scanJSONLLines(
            file,
            maxLineBytes: Self.codexJSONLPrefixBytes,
            prefixBytes: Self.codexJSONLPrefixBytes,
            checkCancellation: nil) { line, wasTruncated in
            guard !didFind else { return }
            guard !wasTruncated else { return }
            guard line.contains("session_meta"),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "session_meta"
            else { return }
            let payload = obj["payload"] as? [String: Any]
            metadata.sessionID = stringValue(payload?["id"] ?? payload?["session_id"] ?? payload?["sessionId"] ?? obj["session_id"] ?? obj["sessionId"])
            metadata.forkedFromID = codexForkParentID(from: payload)
            metadata.forkTimestamp = stringValue(payload?["timestamp"] ?? obj["timestamp"])
            didFind = true
        }
        return metadata
    }

    private func codexTokenSnapshots(sessionID: String, file: URL) -> [CodexTokenSnapshot] {
        let stamp = fileStamp(file)
        if let cached = codexForkLookupCache.withLock({ cache -> [CodexTokenSnapshot]? in
            guard let cached = cache.snapshotsBySessionID[sessionID],
                  cached.stamp == stamp
            else { return nil }
            return cached.snapshots
        }) {
            return cached
        }
        let snapshots = codexTokenSnapshots(in: file)
        codexForkLookupCache.withLock { cache in
            cache.snapshotsBySessionID[sessionID] = CodexForkCachedSnapshots(
                stamp: stamp,
                snapshots: snapshots)
        }
        return snapshots
    }

    private func codexTokenSnapshots(in file: URL) -> [CodexTokenSnapshot] {
        var snapshots: [CodexTokenSnapshot] = []
        _ = try? scanJSONLLines(
            file,
            maxLineBytes: Self.codexJSONLPrefixBytes,
            prefixBytes: Self.codexJSONLPrefixBytes,
            checkCancellation: nil) { line, wasTruncated in
            guard !wasTruncated else { return }
            guard line.contains("token_count"),
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any]
            else { return }
            let timestamp = stringValue(obj["timestamp"] ?? payload["timestamp"]) ?? ""
            snapshots.append(CodexTokenSnapshot(
                timestamp: timestamp,
                date: parseTimestamp(timestamp),
                usage: codexTokenUsage(total)))
        }
        return snapshots
    }

    private func processCodexFileAppend(
        _ file: URL,
        startOffset: Int64,
        cached: FilePartial,
        priorityTurns: [String: CodexPriorityTurn],
        checkCancellation: CancellationCheck? = nil) throws -> FilePartial?
    {
        try checkCancellation?()
        guard let state = cached.codexAppendState,
              let initialUsage = state.lastUsage
        else { return nil }
        if state.isForked {
            return nil
        }

        var records: [UsageRecord] = []
        let session = Self.sessionKey(file: file, explicit: state.session)
        var currentModel = state.model
        var activeTurnID = state.activeTurnID
        var deltaState = CodexTokenDeltaState(
            previousTotals: initialUsage,
            rawTotalsBaseline: state.rawTotalsBaseline ?? initialUsage,
            sawDivergentTotals: state.hasDivergentTotals)
        var sawToken = false
        var lineCounter = 0
        do {
            try scanJSONLLines(
                file,
                startOffset: startOffset,
                maxLineBytes: Self.codexJSONLPrefixBytes,
                prefixBytes: Self.codexJSONLPrefixBytes,
                checkCancellation: checkCancellation) { line, wasTruncated in
                try checkCancellationIfNeeded(checkCancellation, counter: &lineCounter)
                let isToken = line.contains("token_count")
                let isTaskStarted = line.contains("\"task_started\"")
                let isTurnContext = line.contains("\"turn_context\"")
                guard isToken || isTaskStarted || isTurnContext else { return }
                if wasTruncated {
                    if isTurnContext, let model = Self.codexTurnContextModelPrefix(in: line) {
                        currentModel = model
                    }
                    return
                }
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                let payload = obj["payload"] as? [String: Any]
                if isTaskStarted, (payload?["type"] as? String) == "task_started" {
                    activeTurnID = stringValue(payload?["turn_id"] ?? payload?["turnId"] ?? payload?["id"])
                }
                if isTurnContext, (obj["type"] as? String) == "turn_context" {
                    if let model = stringValue(payload?["model"] ?? (payload?["info"] as? [String: Any])?["model"]) {
                        currentModel = model
                    }
                }
                if (payload?["type"] as? String) == "token_count",
                   let info = payload?["info"] as? [String: Any] {
                    let usage = (info["total_token_usage"] as? [String: Any]).map(codexTokenUsage)
                    let last = (info["last_token_usage"] as? [String: Any]).map(codexTokenUsage)
                    guard usage != nil || last != nil else { return }
                    guard let rawDelta = codexTokenRowDelta(last: last, total: usage, state: &deltaState) else { return }
                    sawToken = true
                    guard rawDelta.totalTokens > 0 else { return }
                    let delta = rawDelta.clampedCached
                    let turn = activeTurnID.flatMap { priorityTurns[$0] }
                    let modelFromInfo = stringValue(info["model"] ?? info["model_name"] ?? payload?["model"] ?? obj["model"])
                    let rowModel = currentModel.isEmpty ? modelFromInfo ?? state.model : currentModel
                    let priced = codexTurnCost(rowModel: rowModel, turn: turn, usage: delta)
                    let model = priced.model
                    let cost = priced.costUSD
                    var totals = UsageTotals()
                    totals.inputTokens = delta.uncachedInput
                    totals.outputTokens = delta.output
                    totals.cacheReadTokens = delta.cached
                    totals.costUSD = cost
                    let day = dayString(fromISO: obj["timestamp"] as? String)
                        ?? state.metaDay
                        ?? dayString(fromCodexPath: file)
                        ?? dayString(date: fileModified(file))
                    records.append(UsageRecord(
                        dedupKey: nil,
                        day: day,
                        source: .codex,
                        session: session,
                        model: normalizeModel(model),
                        project: state.project,
                        totals: totals,
                        standardCostUSD: turn == nil ? cost : nil,
                        priorityCostUSD: turn == nil ? nil : cost,
                        standardTokens: turn == nil ? delta.totalTokens : nil,
                        priorityTokens: turn == nil ? nil : delta.totalTokens))
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }

        return FilePartial(
            records: records,
            hadUsage: !records.isEmpty || cached.hadUsage,
            codexAppendState: CodexAppendState(
                model: currentModel,
                project: state.project,
                session: session,
                metaDay: state.metaDay,
                lastUsage: sawToken ? deltaState.previousTotals : state.lastUsage,
                rawTotalsBaseline: sawToken ? deltaState.rawTotalsBaseline : state.rawTotalsBaseline,
                hasDivergentTotals: sawToken ? deltaState.hasDivergentTotals : state.hasDivergentTotals,
                activeTurnID: activeTurnID,
                isForked: false))
    }

    // MARK: - Pi

    private func processPiFile(
        _ file: URL,
        checkCancellation: CancellationCheck? = nil) throws -> FilePartial
    {
        var records: [UsageRecord] = []
        try checkCancellation?()
        let session = Self.sessionKey(file: file)
        var context: PiIdentity?
        var lineCounter = 0
        do {
            try scanJSONLLines(
                file,
                maxLineBytes: Self.piJSONLPrefixBytes,
                prefixBytes: Self.piJSONLPrefixBytes,
                checkCancellation: checkCancellation) { line, wasTruncated in
                try checkCancellationIfNeeded(checkCancellation, counter: &lineCounter)
                guard !wasTruncated else { return }
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = object["type"] as? String
                else { return }

                if type == "model_change" {
                    context = piIdentity(entry: object, message: nil, fallback: nil)
                    return
                }

                guard type == "message",
                      let message = object["message"] as? [String: Any],
                      (message["role"] as? String) == "assistant",
                      let identity = piIdentity(entry: object, message: message, fallback: context),
                      let date = timestampDate(entry: object, message: message)
                else { return }

                let usage = (message["usage"] as? [String: Any]) ?? [:]
                var input = nonNegativeInt(
                    usage["input"]
                        ?? usage["inputTokens"]
                        ?? usage["input_tokens"]
                        ?? usage["promptTokens"]
                        ?? usage["prompt_tokens"])
                let cacheRead = nonNegativeInt(
                    usage["cacheRead"]
                        ?? usage["cacheReadTokens"]
                        ?? usage["cache_read"]
                        ?? usage["cache_read_tokens"]
                        ?? usage["cacheReadInputTokens"]
                        ?? usage["cache_read_input_tokens"])
                let cacheWrite = nonNegativeInt(
                    usage["cacheWrite"]
                        ?? usage["cacheWriteTokens"]
                        ?? usage["cache_write"]
                        ?? usage["cache_write_tokens"]
                        ?? usage["cacheCreationTokens"]
                        ?? usage["cache_creation_tokens"]
                        ?? usage["cacheCreationInputTokens"]
                        ?? usage["cache_creation_input_tokens"])
                let output = nonNegativeInt(
                    usage["output"]
                        ?? usage["outputTokens"]
                        ?? usage["output_tokens"]
                        ?? usage["completionTokens"]
                        ?? usage["completion_tokens"])
                let directTotal = nonNegativeInt(
                    usage["totalTokens"]
                        ?? usage["total_tokens"]
                        ?? usage["tokenCount"]
                        ?? usage["token_count"]
                        ?? usage["tokens"])
                let derivedTotal = input + cacheRead + cacheWrite + output
                if directTotal > derivedTotal {
                    input += directTotal - derivedTotal
                }
                if input + cacheRead + cacheWrite + output == 0 { return }

                let pricing = ModelPricing.forModel(identity.model, cacheRoot: modelsDevCacheRoot, pricingDate: date)
                var totals = UsageTotals()
                totals.inputTokens = input
                totals.cacheReadTokens = cacheRead
                totals.cacheCreationTokens = cacheWrite
                totals.outputTokens = output
                totals.costUSD = pricing.cost(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
                records.append(UsageRecord(
                    dedupKey: nil,
                    day: dayString(date: date),
                    source: identity.source,
                    session: session,
                    model: normalizeModel(identity.model),
                    project: piProject(entry: object, message: message),
                    totals: totals))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return FilePartial(records: records, hadUsage: false)
        }
        return FilePartial(
            records: records,
            hadUsage: !records.isEmpty,
            piAppendState: PiAppendState(context: context))
    }

    private func processPiFileAppend(
        _ file: URL,
        startOffset: Int64,
        cached: FilePartial,
        checkCancellation: CancellationCheck? = nil) throws -> FilePartial?
    {
        try checkCancellation?()
        let session = Self.sessionKey(file: file)
        var records: [UsageRecord] = []
        var context = cached.piAppendState?.context
        var lineCounter = 0
        do {
            try scanJSONLLines(
                file,
                startOffset: startOffset,
                maxLineBytes: Self.piJSONLPrefixBytes,
                prefixBytes: Self.piJSONLPrefixBytes,
                checkCancellation: checkCancellation) { line, wasTruncated in
                try checkCancellationIfNeeded(checkCancellation, counter: &lineCounter)
                guard !wasTruncated else { return }
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = object["type"] as? String
                else { return }

                if type == "model_change" {
                    context = piIdentity(entry: object, message: nil, fallback: nil)
                    return
                }

                guard type == "message",
                      let message = object["message"] as? [String: Any],
                      (message["role"] as? String) == "assistant",
                      let identity = piIdentity(entry: object, message: message, fallback: context),
                      let date = timestampDate(entry: object, message: message)
                else { return }

                let usage = (message["usage"] as? [String: Any]) ?? [:]
                var input = nonNegativeInt(
                    usage["input"]
                        ?? usage["inputTokens"]
                        ?? usage["input_tokens"]
                        ?? usage["promptTokens"]
                        ?? usage["prompt_tokens"])
                let cacheRead = nonNegativeInt(
                    usage["cacheRead"]
                        ?? usage["cacheReadTokens"]
                        ?? usage["cache_read"]
                        ?? usage["cache_read_tokens"]
                        ?? usage["cacheReadInputTokens"]
                        ?? usage["cache_read_input_tokens"])
                let cacheWrite = nonNegativeInt(
                    usage["cacheWrite"]
                        ?? usage["cacheWriteTokens"]
                        ?? usage["cache_write"]
                        ?? usage["cache_write_tokens"]
                        ?? usage["cacheCreationTokens"]
                        ?? usage["cache_creation_tokens"]
                        ?? usage["cacheCreationInputTokens"]
                        ?? usage["cache_creation_input_tokens"])
                let output = nonNegativeInt(
                    usage["output"]
                        ?? usage["outputTokens"]
                        ?? usage["output_tokens"]
                        ?? usage["completionTokens"]
                        ?? usage["completion_tokens"])
                let directTotal = nonNegativeInt(
                    usage["totalTokens"]
                        ?? usage["total_tokens"]
                        ?? usage["tokenCount"]
                        ?? usage["token_count"]
                        ?? usage["tokens"])
                let derivedTotal = input + cacheRead + cacheWrite + output
                if directTotal > derivedTotal {
                    input += directTotal - derivedTotal
                }
                if input + cacheRead + cacheWrite + output == 0 { return }

                let pricing = ModelPricing.forModel(identity.model, cacheRoot: modelsDevCacheRoot, pricingDate: date)
                var totals = UsageTotals()
                totals.inputTokens = input
                totals.cacheReadTokens = cacheRead
                totals.cacheCreationTokens = cacheWrite
                totals.outputTokens = output
                totals.costUSD = pricing.cost(input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
                records.append(UsageRecord(
                    dedupKey: nil,
                    day: dayString(date: date),
                    source: identity.source,
                    session: session,
                    model: normalizeModel(identity.model),
                    project: piProject(entry: object, message: message),
                    totals: totals))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
        }
        return FilePartial(
            records: records,
            hadUsage: !records.isEmpty,
            piAppendState: PiAppendState(context: context))
    }

    private func piIdentity(entry: [String: Any], message: [String: Any]?, fallback: PiIdentity?) -> PiIdentity? {
        let providerText = stringValue(message?["provider"] ?? entry["provider"])
        let source = providerText.flatMap(piSource) ?? fallback?.source
        let modelText = stringValue(message?["model"] ?? entry["model"] ?? message?["modelId"] ?? entry["modelId"])
        guard let source else { return nil }
        if let modelText, !modelText.isEmpty {
            return PiIdentity(source: source, model: normalizePiModel(modelText, source: source))
        }
        if let fallback, fallback.source == source {
            return fallback
        }
        return nil
    }

    private func piSource(_ raw: String) -> UsageSource? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "openai-codex", "codex":
            return .codex
        case "anthropic", "claude", "claude-code":
            return .claude
        case "vertexai", "vertex-ai", "vertex", "google-vertex-ai":
            return .vertexai
        default:
            return nil
        }
    }

    private func normalizePiModel(_ raw: String, source: UsageSource) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        switch source {
        case .codex: return "gpt-5-codex"
        case .claude: return "claude-unknown"
        case .vertexai: return "claude-unknown"
        case .bedrock: return "aws-bedrock"
        }
    }

    private static func sessionKey(file: URL, explicit: String? = nil) -> String {
        let trimmed = explicit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let base = file.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? file.lastPathComponent : base
    }

    private func piProject(entry: [String: Any], message: [String: Any]) -> String {
        stringValue(message["cwd"] ?? entry["cwd"] ?? message["workspacePath"] ?? entry["workspacePath"]) ?? ""
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
        var byDayModelMap: [String: [String: UsageModelBreakdown]] = [:]
        var byMonthMap: [String: UsageTotals] = [:]
        var byMonthSourceMap: [String: [UsageSource: UsageTotals]] = [:]
        var bySessionMap: [String: UsageTotals] = [:]
        var bySessionNameMap: [String: String] = [:]
        var bySessionSourceMap: [String: UsageSource] = [:]
        var bySessionProjectMap: [String: String] = [:]
        var bySessionLastActivityMap: [String: String] = [:]
        var bySessionModelsMap: [String: Set<String>] = [:]
        var byProjectMap: [String: UsageTotals] = [:]
        var byProjectSourceMap: [String: [UsageSource: UsageTotals]] = [:]
        for r in records {
            let totals = r.countedTotals
            report.grand += totals
            report.bySource[r.source, default: UsageTotals()] += totals
            byDayMap[r.day, default: UsageTotals()] += totals
            byDaySourceMap[r.day, default: [:]][r.source, default: UsageTotals()] += totals
            if let month = UsageReport.monthKey(fromDay: r.day) {
                byMonthMap[month, default: UsageTotals()] += totals
                byMonthSourceMap[month, default: [:]][r.source, default: UsageTotals()] += totals
            }
            if let session = r.session, !session.isEmpty {
                let sessionKey = "\(r.source.rawValue):\(session)"
                bySessionMap[sessionKey, default: UsageTotals()] += totals
                bySessionNameMap[sessionKey] = session
                bySessionSourceMap[sessionKey] = r.source
                if !(r.project.isEmpty) {
                    let existingProject = bySessionProjectMap[sessionKey] ?? ""
                    if existingProject.isEmpty { bySessionProjectMap[sessionKey] = r.project }
                }
                let existingActivity = bySessionLastActivityMap[sessionKey] ?? ""
                if r.day > existingActivity { bySessionLastActivityMap[sessionKey] = r.day }
                bySessionModelsMap[sessionKey, default: []].insert(r.model)
            }
            let dayModelKey = "\(r.source.rawValue):\(r.model)"
            if let existing = byDayModelMap[r.day]?[dayModelKey] {
                let hasSplit =
                    existing.standardCostUSD != nil || existing.priorityCostUSD != nil ||
                    existing.standardTokens != nil || existing.priorityTokens != nil ||
                    r.standardCostUSD != nil || r.priorityCostUSD != nil ||
                    r.standardTokens != nil || r.priorityTokens != nil
                let existingStandardCost = existing.standardCostUSD
                    ?? (hasSplit && existing.priorityCostUSD == nil ? existing.totals.costUSD : nil)
                let existingStandardTokens = existing.standardTokens
                    ?? (hasSplit && existing.priorityTokens == nil ? existing.totals.totalTokens : nil)
                let recordStandardCost = r.standardCostUSD
                    ?? (hasSplit && r.priorityCostUSD == nil ? totals.costUSD : nil)
                let recordStandardTokens = r.standardTokens
                    ?? (hasSplit && r.priorityTokens == nil ? totals.totalTokens : nil)
                byDayModelMap[r.day]?[dayModelKey] = UsageModelBreakdown(
                    model: r.model,
                    source: r.source,
                    totals: existing.totals + totals,
                    standardCostUSD: optionalSum(existingStandardCost, recordStandardCost),
                    priorityCostUSD: optionalSum(existing.priorityCostUSD, r.priorityCostUSD),
                    standardTokens: optionalSum(existingStandardTokens, recordStandardTokens),
                    priorityTokens: optionalSum(existing.priorityTokens, r.priorityTokens))
            } else {
                byDayModelMap[r.day, default: [:]][dayModelKey] = UsageModelBreakdown(
                    model: r.model,
                    source: r.source,
                    totals: totals,
                    standardCostUSD: r.standardCostUSD,
                    priorityCostUSD: r.priorityCostUSD,
                    standardTokens: r.standardTokens,
                    priorityTokens: r.priorityTokens)
            }
            byProjectMap[r.project, default: UsageTotals()] += totals
            byProjectSourceMap[r.project, default: [:]][r.source, default: UsageTotals()] += totals
            let mKey = "\(r.source.rawValue):\(r.model)"
            if let existing = byModelMap[mKey] {
                byModelMap[mKey] = ModelUsage(model: r.model, source: r.source, totals: existing.totals + totals)
            } else {
                byModelMap[mKey] = ModelUsage(model: r.model, source: r.source, totals: totals)
            }
        }
        report.byModel = byModelMap.values.sorted { $0.totals.costUSD > $1.totals.costUSD }
        report.byDay = byDayMap.map {
            let breakdowns = byDayModelMap[$0.key].map { Array($0.values) } ?? []
            return DailyUsage(
                day: $0.key,
                totals: $0.value,
                bySource: byDaySourceMap[$0.key] ?? [:],
                modelBreakdowns: sortedModelBreakdowns(breakdowns))
        }.sorted { $0.day < $1.day }
        report.byMonth = byMonthMap.map {
            MonthlyUsage(month: $0.key, totals: $0.value, bySource: byMonthSourceMap[$0.key] ?? [:])
        }.sorted { $0.month < $1.month }
        report.bySession = bySessionMap.compactMap { key, totals in
            guard let session = bySessionNameMap[key], let source = bySessionSourceMap[key] else { return nil }
            return SessionUsage(
                session: session,
                source: source,
                project: bySessionProjectMap[key] ?? "",
                totals: totals,
                lastActivity: bySessionLastActivityMap[key],
                models: Array(bySessionModelsMap[key] ?? []).sorted())
        }.sorted { lhs, rhs in
            let lActivity = lhs.lastActivity ?? ""
            let rActivity = rhs.lastActivity ?? ""
            if lActivity != rActivity { return lActivity > rActivity }
            if lhs.totals.costUSD != rhs.totals.costUSD { return lhs.totals.costUSD > rhs.totals.costUSD }
            if lhs.totals.totalTokens != rhs.totals.totalTokens { return lhs.totals.totalTokens > rhs.totals.totalTokens }
            return lhs.session < rhs.session
        }
        report.byProject = byProjectMap.map {
            ProjectUsage(path: $0.key, totals: $0.value, bySource: byProjectSourceMap[$0.key] ?? [:])
        }.sorted { $0.totals.costUSD > $1.totals.costUSD }
        return report
    }

    private func buildReport(parts: [FilePartial], context: ScanContext, now: Date) -> UsageReport {
        var candidateRecords: [UsageRecord] = []
        var sessionsBySource: [UsageSource: Int] = [:]
        for p in parts {
            var sourcesIncludedInFile = Set<UsageSource>()
            for r in p.records {
                guard r.day >= context.startDay, r.day <= context.endDay else { continue }
                sourcesIncludedInFile.insert(r.source)
                candidateRecords.append(r)
            }
            for source in sourcesIncludedInFile {
                sessionsBySource[source, default: 0] += 1
            }
        }
        let records = Self.reconciledUsageRecords(candidateRecords)
        return buildReport(records: records, sessionsBySource: sessionsBySource, daysBack: context.daysBack, now: now)
    }

    // MARK: - 工具

    private func codexSessionFiles(
        sinceDay: String,
        untilDay: String,
        modifiedAfter cutoff: Date) -> [URL]
    {
        (try? codexSessionFiles(
            sinceDay: sinceDay,
            untilDay: untilDay,
            modifiedAfter: cutoff,
            checkCancellation: nil)) ?? []
    }

    private func codexSessionFiles(
        sinceDay: String,
        untilDay: String,
        modifiedAfter cutoff: Date,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        var seenPaths = Set<String>()
        var out: [URL] = []
        for root in codexSessionRoots() {
            try checkCancellation?()
            let rootFiles = try codexSessionFiles(
                root: root,
                sinceDay: sinceDay,
                untilDay: untilDay,
                includeRecursive: false,
                checkCancellation: checkCancellation)
            for file in rootFiles.sorted(by: { $0.path < $1.path }) where !seenPaths.contains(file.path) {
                seenPaths.insert(file.path)
                out.append(file)
            }

            let activeFiles = try codexRecentlyModifiedSessionFiles(
                root: root,
                sinceDay: sinceDay,
                untilDay: untilDay,
                modifiedAfter: cutoff,
                checkCancellation: checkCancellation)
            for file in activeFiles.sorted(by: { $0.path < $1.path }) where !seenPaths.contains(file.path) {
                seenPaths.insert(file.path)
                out.append(file)
            }
        }
        return try uniqueCodexFiles(out, checkCancellation: checkCancellation)
    }

    private func codexSessionFiles(
        root: URL,
        sinceDay: String,
        untilDay: String,
        includeRecursive: Bool,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        let partitioned = try codexSessionFilesByDatePartition(
            root: root,
            sinceDay: sinceDay,
            untilDay: untilDay,
            checkCancellation: checkCancellation)
        let flat = codexSessionFilesFlat(root: root, sinceDay: sinceDay, untilDay: untilDay)
        let recursive = includeRecursive
            ? try codexLegacySessionFilesRecursive(root: root, checkCancellation: checkCancellation)
            : []
        var seen = Set<String>()
        var out: [URL] = []
        for file in partitioned + flat + recursive where !seen.contains(file.path) {
            seen.insert(file.path)
            out.append(file)
        }
        return out
    }

    private func codexRecentlyModifiedSessionFiles(
        root: URL,
        sinceDay: String,
        untilDay: String,
        modifiedAfter cutoff: Date,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        let lookbackSince = dayString(sinceDay, addingDays: -Self.codexActiveSessionLookbackDays) ?? sinceDay
        let partitioned = try codexSessionFilesByDatePartition(
            root: root,
            sinceDay: lookbackSince,
            untilDay: untilDay,
            checkCancellation: checkCancellation)
        let partitionedModified = partitioned.filter { file in
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate
            else { return false }
            return modified >= cutoff
        }
        let legacy = try codexLegacyRecentlyModifiedSessionFiles(
            root: root,
            modifiedAfter: cutoff,
            checkCancellation: checkCancellation)
        var seen = Set(partitionedModified.map(\.path))
        var out = partitionedModified
        for file in legacy where !seen.contains(file.path) {
            seen.insert(file.path)
            out.append(file)
        }
        return out
    }

    private func codexSessionFilesByDatePartition(
        root: URL,
        sinceDay: String,
        untilDay: String,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var out: [URL] = []
        for dayKey in dayKeys(sinceDay: sinceDay, untilDay: untilDay) {
            try checkCancellation?()
            let parts = dayKey.split(separator: "-")
            guard parts.count == 3 else { continue }
            let dayDir = root
                .appendingPathComponent(String(parts[0]), isDirectory: true)
                .appendingPathComponent(String(parts[1]), isDirectory: true)
                .appendingPathComponent(String(parts[2]), isDirectory: true)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dayDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            else { continue }
            for item in items where item.pathExtension.lowercased() == "jsonl" {
                let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile != false else { continue }
                out.append(item)
            }
        }
        return out
    }

    private func codexSessionFilesFlat(root: URL, sinceDay: String, untilDay: String) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let items = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles])
        else { return [] }

        var out: [URL] = []
        for item in items where item.pathExtension.lowercased() == "jsonl" {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            if let day = dayString(fromCodexFilename: item.lastPathComponent),
               !isDay(day, inRangeSince: sinceDay, until: untilDay)
            {
                continue
            }
            out.append(item)
        }
        return out
    }

    private func codexLegacyRecentlyModifiedSessionFiles(
        root: URL,
        modifiedAfter cutoff: Date,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        let rootPath = root.standardizedFileURL.path
        var out: [URL] = []
        var scanned = 0
        for case let file as URL in enumerator {
            scanned += 1
            if scanned % 128 == 0 {
                try checkCancellation?()
            }
            if codexDatePartitionAncestor(file, rootPath: rootPath) {
                enumerator.skipDescendants()
                continue
            }
            guard file.pathExtension.lowercased() == "jsonl" else { continue }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modified = values?.contentModificationDate,
                  modified >= cutoff
            else { continue }
            out.append(file)
        }
        return out
    }

    private func codexLegacySessionFilesRecursive(
        root: URL,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        let rootPath = root.standardizedFileURL.path
        var out: [URL] = []
        var scanned = 0
        for case let file as URL in enumerator {
            scanned += 1
            if scanned % 128 == 0 {
                try checkCancellation?()
            }
            if codexDatePartitionAncestor(file, rootPath: rootPath) {
                enumerator.skipDescendants()
                continue
            }
            guard file.pathExtension.lowercased() == "jsonl" else { continue }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            out.append(file)
        }
        return out
    }

    private func codexDatePartitionAncestor(_ url: URL, rootPath: String) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return false }
        let relative = String(path.dropFirst(rootPath.count + 1))
        let parts = relative.split(separator: "/")
        guard parts.count == 1 else { return false }
        let part = String(parts[0])
        return part.count == 4 && part.allSatisfy(\.isNumber)
    }

    private func uniqueCodexFiles(_ files: [URL]) -> [URL] {
        (try? uniqueCodexFiles(files, checkCancellation: nil)) ?? files
    }

    private func uniqueCodexFiles(
        _ files: [URL],
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        var seenSessionIDs = Set<String>()
        var seenFileIDs = Set<String>()
        var out: [URL] = []
        for file in codexFilesInScanOrder(files) {
            try checkCancellation?()
            let identity = codexFileIdentity(file)
            if let fileID = identity.fileID, seenFileIDs.contains(fileID) {
                continue
            }
            if let sessionID = identity.sessionID, seenSessionIDs.contains(sessionID) {
                continue
            }
            out.append(file)
            if let fileID = identity.fileID {
                seenFileIDs.insert(fileID)
            }
            if let sessionID = identity.sessionID {
                seenSessionIDs.insert(sessionID)
                rememberCodexSessionFile(file, sessionID: sessionID)
            }
        }
        return out
    }

    private func codexFilesInScanOrder(_ files: [URL]) -> [URL] {
        files.sorted { lhs, rhs in
            let leftRank = codexRootRank(lhs)
            let rightRank = codexRootRank(rhs)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.path < rhs.path
        }
    }

    private func codexRootRank(_ file: URL) -> Int {
        let path = file.standardizedFileURL.path
        let sessionsPath = codexSessionsDir.standardizedFileURL.path
        if path == sessionsPath || path.hasPrefix(sessionsPath + "/") {
            return 0
        }
        if let codexArchivedSessionsDir {
            let archivedPath = codexArchivedSessionsDir.standardizedFileURL.path
            if path == archivedPath || path.hasPrefix(archivedPath + "/") {
                return 1
            }
        }
        return 2
    }

    private func codexFileIdentity(_ file: URL) -> CodexFileIdentity {
        let metadata = codexSessionMetadata(in: file)
        return CodexFileIdentity(
            sessionID: metadata.sessionID,
            fileID: fileSystemIdentity(file))
    }

    private func fileSystemIdentity(_ file: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else {
            return nil
        }
        let systemNumber = (attributes[.systemNumber] as? NSNumber)?.uint64Value
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        guard let systemNumber, let fileNumber else { return nil }
        return "\(systemNumber):\(fileNumber)"
    }

    private func jsonlFiles(in dirs: [URL]) -> [URL] {
        (try? jsonlFiles(in: dirs, checkCancellation: nil)) ?? []
    }

    private func jsonlFiles(
        in dirs: [URL],
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        var seen = Set<String>()
        var out: [URL] = []
        for dir in dirs {
            try checkCancellation?()
            for file in try jsonlFiles(in: dir, checkCancellation: checkCancellation)
                where !seen.contains(file.path)
            {
                seen.insert(file.path)
                out.append(file)
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private func jsonlFiles(
        in dir: URL,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var out: [URL] = []
        var scanned = 0
        for case let url as URL in en {
            scanned += 1
            if scanned % 128 == 0 {
                try checkCancellation?()
            }
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile != false else { continue }
            out.append(url)
        }
        return out
    }

    private func jsonlFiles(in dirs: [URL], modifiedAfter cutoff: Date) -> [URL] {
        (try? jsonlFiles(in: dirs, modifiedAfter: cutoff, checkCancellation: nil)) ?? []
    }

    private func jsonlFiles(
        in dirs: [URL],
        modifiedAfter cutoff: Date,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        var seen = Set<String>()
        var out: [URL] = []
        for dir in dirs {
            try checkCancellation?()
            for file in try jsonlFiles(in: dir, modifiedAfter: cutoff, checkCancellation: checkCancellation)
                where !seen.contains(file.path)
            {
                seen.insert(file.path)
                out.append(file)
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private func jsonlFiles(in dir: URL, modifiedAfter cutoff: Date) -> [URL] {
        (try? jsonlFiles(in: dir, modifiedAfter: cutoff, checkCancellation: nil)) ?? []
    }

    private func piSessionFiles(modifiedAfter cutoff: Date) -> [URL] {
        (try? piSessionFiles(modifiedAfter: cutoff, checkCancellation: nil)) ?? []
    }

    private func piSessionFiles(
        modifiedAfter cutoff: Date,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        guard FileManager.default.fileExists(atPath: piSessionsDir.path) else { return [] }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: piSessionsDir,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])
        else { return [] }

        var out: [URL] = []
        var scanned = 0
        for case let url as URL in enumerator {
            scanned += 1
            if scanned % 128 == 0 {
                try checkCancellation?()
            }
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let startedAt = Self.piSessionStartDate(fromFilename: url.lastPathComponent)
            let modifiedAt = values?.contentModificationDate
            guard Self.shouldIncludePiSessionFile(
                startedAt: startedAt,
                modifiedAt: modifiedAt,
                cutoff: cutoff)
            else { continue }
            out.append(url)
        }
        return out.sorted { $0.path < $1.path }
    }

    private func jsonlFiles(
        in dir: URL,
        modifiedAfter cutoff: Date,
        checkCancellation: CancellationCheck?) throws -> [URL]
    {
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        var scanned = 0
        for case let url as URL in en {
            scanned += 1
            if scanned % 128 == 0 {
                try checkCancellation?()
            }
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mod = values?.contentModificationDate, mod < cutoff { continue }
            out.append(url)
        }
        return out
    }

    private static let piSessionStartFilenameRegex = try? NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z_"#)

    private static func shouldIncludePiSessionFile(
        startedAt: Date?,
        modifiedAt: Date?,
        cutoff: Date) -> Bool
    {
        if let modifiedAt, localMidnight(modifiedAt) >= cutoff {
            return true
        }
        if let startedAt, localMidnight(startedAt) >= cutoff {
            return true
        }
        return false
    }

    private static func piSessionStartDate(fromFilename filename: String) -> Date? {
        guard let regex = piSessionStartFilenameRegex else { return nil }
        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard let match = regex.firstMatch(in: filename, range: range),
              let dateRange = Range(match.range(at: 1), in: filename),
              let hourRange = Range(match.range(at: 2), in: filename),
              let minuteRange = Range(match.range(at: 3), in: filename),
              let secondRange = Range(match.range(at: 4), in: filename),
              let millisRange = Range(match.range(at: 5), in: filename)
        else { return nil }
        let text = "\(filename[dateRange])T\(filename[hourRange]):\(filename[minuteRange]):\(filename[secondRange]).\(filename[millisRange])Z"
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private static func localMidnight(_ date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return Calendar.current.date(from: components) ?? date
    }

    private func fileModified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }

    private func modificationUnixMs(_ url: URL) -> Int64 {
        fileMetadata(url).modificationUnixMs
    }

    private func fileMetadata(_ url: URL) -> (modificationUnixMs: Int64, size: Int64) {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return (0, 0)
        }
        let modified = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return (Int64((modified * 1000).rounded()), Int64(values.fileSize ?? 0))
    }

    private func fileStamp(_ url: URL) -> FileStamp? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let metadata = fileMetadata(url)
        return FileStamp(
            modificationUnixMs: metadata.modificationUnixMs,
            size: metadata.size,
            fileIdentity: fileSystemIdentity(url),
            contentSignature: fileContentSignature(url, size: metadata.size))
    }

    private func fileCacheKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func fileContentSignature(_ url: URL, size: Int64) -> String? {
        guard size > 0 else { return "empty" }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let sampleBytes = 4096
        var sample = Data()
        if let head = try? handle.read(upToCount: sampleBytes) {
            sample.append(head)
        }
        if size > Int64(sampleBytes) {
            let tailOffset = UInt64(max(0, size - Int64(sampleBytes)))
            try? handle.seek(toOffset: tailOffset)
            if let tail = try? handle.readToEnd() {
                sample.append(tail)
            }
        }
        return "\(size)-\(String(format: "%016llx", Self.stableHash(sample)))"
    }

    private func parsedJSONLBytes(
        _ url: URL,
        startOffset: Int64 = 0,
        checkCancellation: CancellationCheck? = nil) throws -> Int64
    {
        do {
            return try scanJSONLLines(
                url,
                startOffset: startOffset,
                checkCancellation: checkCancellation) { _, _ in }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return startOffset
        }
    }

    @discardableResult
    private func scanJSONLLines(
        _ url: URL,
        startOffset: Int64 = 0,
        maxLineBytes: Int = 512 * 1024,
        prefixBytes: Int = 512 * 1024,
        checkCancellation: CancellationCheck? = nil,
        onLine: (String, Bool) throws -> Void) throws -> Int64
    {
        try checkCancellation?()
        let normalizedOffset = max(0, startOffset)
        let prefixLimit = max(0, prefixBytes)
        let lineLimit = max(1, maxLineBytes)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if normalizedOffset > 0 {
            try handle.seek(toOffset: UInt64(normalizedOffset))
        }

        var line = Data()
        line.reserveCapacity(4 * 1024)
        var lineBytes = 0
        var wasTruncated = false
        var bytesRead: Int64 = 0
        var parsedBytes = normalizedOffset

        func appendSegment(_ bytes: UnsafePointer<UInt8>, count: Int) {
            guard count > 0 else { return }
            lineBytes += count
            if line.count < prefixLimit {
                let appendCount = min(prefixLimit - line.count, count)
                if appendCount > 0 {
                    line.append(bytes, count: appendCount)
                }
            }
            if lineBytes > lineLimit || lineBytes > prefixLimit {
                wasTruncated = true
            }
        }

        func consumeLine(terminated: Bool, absoluteOffset: Int64) throws {
            defer { line.removeAll(keepingCapacity: true) }
            defer {
                lineBytes = 0
                wasTruncated = false
            }
            guard !line.isEmpty else {
                parsedBytes = absoluteOffset
                return
            }
            guard terminated || (!wasTruncated && Self.isCompleteJSONLLine(line)) else {
                return
            }
            let text = String(decoding: line, as: UTF8.self)
            try onLine(text, wasTruncated)
            if terminated || !wasTruncated {
                parsedBytes = absoluteOffset
            }
        }

        while true {
            try checkCancellation?()
            let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()
            if chunk.isEmpty { break }
            let chunkStartOffset = normalizedOffset + bytesRead
            bytesRead += Int64(chunk.count)
            try checkCancellation?()
            try chunk.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                var segmentStart = 0
                var index = 0
                while index < rawBuffer.count {
                    if base[index] == 0x0A {
                        appendSegment(base.advanced(by: segmentStart), count: index - segmentStart)
                        try consumeLine(
                            terminated: true,
                            absoluteOffset: chunkStartOffset + Int64(index + 1))
                        segmentStart = index + 1
                    }
                    index += 1
                }
                if segmentStart < rawBuffer.count {
                    appendSegment(
                        base.advanced(by: segmentStart),
                        count: rawBuffer.count - segmentStart)
                }
            }
        }

        try checkCancellation?()
        if !line.isEmpty {
            try consumeLine(
                terminated: false,
                absoluteOffset: normalizedOffset + bytesRead)
        }
        return parsedBytes
    }

    private static func isCompleteJSONLLine(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func codexTurnContextModelPrefix(in text: String) -> String? {
        let object = text[...]
        guard Self.extractJSONStringField("type", from: object, atDepth: 1) == "turn_context",
              let payloadText = Self.extractJSONObjectField("payload", from: object, atDepth: 1)
        else { return nil }

        let payloadModel = Self.extractJSONStringField("model", from: payloadText, atDepth: 1)
            ?? Self.extractJSONStringField("model_name", from: payloadText, atDepth: 1)
        if let payloadModel { return payloadModel }

        guard let infoText = Self.extractJSONObjectField("info", from: payloadText, atDepth: 1) else {
            return nil
        }
        return Self.extractJSONStringField("model", from: infoText, atDepth: 1)
            ?? Self.extractJSONStringField("model_name", from: infoText, atDepth: 1)
    }

    private static func extractJSONStringField(
        _ field: String,
        from text: Substring,
        atDepth targetDepth: Int) -> String?
    {
        Self.extractJSONField(field, from: text, atDepth: targetDepth) { text, index in
            guard index < text.endIndex, text[index] == "\"" else { return nil }
            let value = Self.parseJSONString(in: text, index: &index)
            return value?.isEmpty == true ? nil : value
        }
    }

    private static func extractJSONObjectField(
        _ field: String,
        from text: Substring,
        atDepth targetDepth: Int) -> Substring?
    {
        Self.extractJSONField(field, from: text, atDepth: targetDepth) { text, index in
            guard index < text.endIndex, text[index] == "{" else { return nil }
            return text[index...]
        }
    }

    private static func extractJSONField<T>(
        _ field: String,
        from text: Substring,
        atDepth targetDepth: Int,
        parseValue: (Substring, inout String.Index) -> T?) -> T?
    {
        var index = text.startIndex
        var depth = 0

        while index < text.endIndex {
            let character = text[index]
            if character == "{" {
                depth += 1
                text.formIndex(after: &index)
            } else if character == "}" {
                depth -= 1
                text.formIndex(after: &index)
            } else if character == "\"" {
                var valueIndex = index
                guard let key = Self.parseJSONString(in: text, index: &valueIndex) else { return nil }
                defer { index = valueIndex }
                guard depth == targetDepth, key == field else { continue }

                Self.skipJSONWhitespace(in: text, index: &valueIndex)
                guard valueIndex < text.endIndex, text[valueIndex] == ":" else { continue }
                text.formIndex(after: &valueIndex)
                Self.skipJSONWhitespace(in: text, index: &valueIndex)
                if let value = parseValue(text, &valueIndex) {
                    return value
                }
            } else {
                text.formIndex(after: &index)
            }
        }

        return nil
    }

    private static func parseJSONString(in text: Substring, index: inout String.Index) -> String? {
        guard index < text.endIndex, text[index] == "\"" else { return nil }
        text.formIndex(after: &index)
        var value = ""
        var isEscaped = false
        while index < text.endIndex {
            let character = text[index]
            if isEscaped {
                value.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                text.formIndex(after: &index)
                return value
            } else {
                value.append(character)
            }
            text.formIndex(after: &index)
        }
        return nil
    }

    private static func skipJSONWhitespace(in text: Substring, index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            text.formIndex(after: &index)
        }
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
        if let s = any as? String, let d = Double(s), d.isFinite { return Int(d.rounded()) }
        return 0
    }

    private func nonNegativeInt(_ any: Any?) -> Int {
        max(0, intValue(any))
    }

    private func stringValue(_ any: Any?) -> String? {
        (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func timestampDate(entry: [String: Any], message: [String: Any]) -> Date? {
        parseTimestamp(message["timestamp"]) ?? parseTimestamp(entry["timestamp"])
    }

    private func parseTimestamp(_ any: Any?) -> Date? {
        if let n = any as? NSNumber {
            let raw = n.doubleValue
            guard raw.isFinite else { return nil }
            return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
        }
        if let s = any as? String {
            if let raw = Double(s), raw.isFinite {
                return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
            }
            return parseISO(s)
        }
        return nil
    }

    private func parseISO(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private func dayString(fromISO iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        return String(iso.prefix(10))   // yyyy-MM-dd
    }

    private static let codexFilenameDayRegex = try? NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})"#)
    private static let pathDayRegex = try? NSRegularExpression(pattern: #"/(\d{4})/(\d{2})/(\d{2})/"#)

    private func dayString(fromCodexFilename filename: String) -> String? {
        guard let re = Self.codexFilenameDayRegex,
              let match = re.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
              let range = Range(match.range(at: 1), in: filename)
        else { return nil }
        return String(filename[range])
    }

    private func dayString(fromCodexPath url: URL) -> String? {
        let path = url.path
        guard let re = Self.pathDayRegex,
              let m = re.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let yr = Range(m.range(at: 1), in: path),
              let mo = Range(m.range(at: 2), in: path),
              let dy = Range(m.range(at: 3), in: path) else { return nil }
        return "\(path[yr])-\(path[mo])-\(path[dy])"
    }

    private func epochSeconds(dayKey: String) -> Int64? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: dayKey) else { return nil }
        return Int64(date.timeIntervalSince1970)
    }

    private func date(fromDayKey dayKey: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dayKey)
    }

    private func dayString(_ dayKey: String, addingDays days: Int) -> String? {
        guard let date = date(fromDayKey: dayKey),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: date)
        else { return nil }
        return dayString(date: shifted)
    }

    private func dayKeys(sinceDay: String, untilDay: String) -> [String] {
        guard let since = date(fromDayKey: sinceDay),
              let until = date(fromDayKey: untilDay)
        else { return sinceDay <= untilDay ? [sinceDay] : [] }
        var out: [String] = []
        var cursor = since
        while cursor <= until {
            out.append(dayString(date: cursor))
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor),
                  next > cursor
            else { break }
            cursor = next
        }
        return out
    }

    private func isDay(_ day: String, inRangeSince sinceDay: String, until untilDay: String) -> Bool {
        day >= sinceDay && day <= untilDay
    }

    private func dayString(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func codexTokenUsage(_ total: [String: Any]) -> CodexTokenUsage {
        CodexTokenUsage(
            inputAll: intValue(total["input_tokens"]),
            cached: intValue(total["cached_input_tokens"] ?? total["cache_read_input_tokens"]),
            output: intValue(total["output_tokens"]))
    }

    private func codexTokenDelta(from previous: CodexTokenUsage?, to current: CodexTokenUsage) -> CodexTokenUsage? {
        guard let previous else { return current }
        return codexTotalDelta(from: previous, to: current)
    }

    private static func codexTokensEqual(_ lhs: CodexTokenUsage?, _ rhs: CodexTokenUsage?) -> Bool {
        lhs?.inputAll == rhs?.inputAll && lhs?.cached == rhs?.cached && lhs?.output == rhs?.output
    }

    private func codexTokensAtLeast(_ lhs: CodexTokenUsage, _ rhs: CodexTokenUsage) -> Bool {
        lhs.inputAll >= rhs.inputAll && lhs.cached >= rhs.cached && lhs.output >= rhs.output
    }

    private func codexTokensAtMost(_ lhs: CodexTokenUsage, _ rhs: CodexTokenUsage) -> Bool {
        lhs.inputAll <= rhs.inputAll && lhs.cached <= rhs.cached && lhs.output <= rhs.output
    }

    private func codexAddTokens(_ lhs: CodexTokenUsage, _ rhs: CodexTokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            inputAll: lhs.inputAll + rhs.inputAll,
            cached: lhs.cached + rhs.cached,
            output: lhs.output + rhs.output)
    }

    private func codexMinTokens(_ lhs: CodexTokenUsage, _ rhs: CodexTokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            inputAll: min(lhs.inputAll, rhs.inputAll),
            cached: min(lhs.cached, rhs.cached),
            output: min(lhs.output, rhs.output))
    }

    private func codexTotalDelta(from baseline: CodexTokenUsage?, to current: CodexTokenUsage) -> CodexTokenUsage {
        let baseline = baseline ?? .zero
        return CodexTokenUsage(
            inputAll: max(0, current.inputAll - baseline.inputAll),
            cached: max(0, current.cached - baseline.cached),
            output: max(0, current.output - baseline.output))
    }

    private func codexDivergentTotalDelta(
        rawBaseline: CodexTokenUsage?,
        countedBaseline: CodexTokenUsage?,
        current: CodexTokenUsage) -> CodexTokenUsage
    {
        let rawBaseline = rawBaseline ?? .zero
        let countedBaseline = countedBaseline ?? .zero

        func delta(raw: Int, counted: Int, current: Int) -> Int {
            if current >= raw {
                return max(0, current - raw)
            }
            return max(0, current - counted)
        }

        return CodexTokenUsage(
            inputAll: delta(raw: rawBaseline.inputAll, counted: countedBaseline.inputAll, current: current.inputAll),
            cached: delta(raw: rawBaseline.cached, counted: countedBaseline.cached, current: current.cached),
            output: delta(raw: rawBaseline.output, counted: countedBaseline.output, current: current.output))
    }

    private func codexShouldPreferTotalDelta(
        rawBaseline: CodexTokenUsage?,
        currentTotal: CodexTokenUsage,
        totalDelta: CodexTokenUsage,
        lastDelta: CodexTokenUsage,
        sawDivergentTotals: Bool) -> Bool
    {
        guard !sawDivergentTotals, let rawBaseline else { return false }
        return codexTokensAtLeast(currentTotal, rawBaseline)
            && codexTokensAtMost(totalDelta, lastDelta)
    }

    private func codexTokenRowDelta(
        last: CodexTokenUsage?,
        total: CodexTokenUsage?,
        state: inout CodexTokenDeltaState) -> CodexTokenUsage?
    {
        if let last {
            var adjustedDelta = last
            let previous = state.previousTotals ?? .zero
            if let total {
                let totalDelta = codexTotalDelta(from: state.rawTotalsBaseline, to: total)
                if codexShouldPreferTotalDelta(
                    rawBaseline: state.rawTotalsBaseline,
                    currentTotal: total,
                    totalDelta: totalDelta,
                    lastDelta: last,
                    sawDivergentTotals: state.sawDivergentTotals)
                {
                    adjustedDelta = totalDelta
                }
                let countedTotals = codexAddTokens(previous, adjustedDelta)
                state.previousTotals = countedTotals
                state.rawTotalsBaseline = total
                if !Self.codexTokensEqual(total, countedTotals) {
                    state.sawDivergentTotals = true
                }
            } else {
                let countedTotals = codexAddTokens(previous, adjustedDelta)
                state.previousTotals = countedTotals
                state.rawTotalsBaseline = countedTotals
            }
            return adjustedDelta
        }

        guard let total else { return nil }
        let delta = state.sawDivergentTotals
            ? codexDivergentTotalDelta(
                rawBaseline: state.rawTotalsBaseline,
                countedBaseline: state.previousTotals,
                current: total)
            : codexTotalDelta(from: state.rawTotalsBaseline, to: total)
        let previous = state.previousTotals ?? .zero
        state.previousTotals = codexAddTokens(previous, delta)
        state.rawTotalsBaseline = total
        if !Self.codexTokensEqual(state.rawTotalsBaseline, state.previousTotals) {
            state.sawDivergentTotals = true
        }
        return delta
    }

    private func optionalSum(_ lhs: Double?, _ rhs: Double?) -> Double? {
        if lhs == nil, rhs == nil { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }

    private func optionalSum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        if lhs == nil, rhs == nil { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }

    /// 收敛模型名做展示/聚合（去掉日期后缀等噪音）。
    private func normalizeModel(_ model: String) -> String {
        model
    }

    private func sortedModelBreakdowns(_ breakdowns: [UsageModelBreakdown]) -> [UsageModelBreakdown] {
        breakdowns.sorted { lhs, rhs in
            if lhs.totals.costUSD != rhs.totals.costUSD {
                return lhs.totals.costUSD > rhs.totals.costUSD
            }
            if lhs.totals.totalTokens != rhs.totals.totalTokens {
                return lhs.totals.totalTokens > rhs.totals.totalTokens
            }
            if lhs.source.rawValue != rhs.source.rawValue {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            return lhs.model > rhs.model
        }
    }
}
