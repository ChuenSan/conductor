import Foundation

public enum CostUsageError: LocalizedError, Sendable {
    case timedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .timedOut(seconds):
            if seconds >= 60, seconds % 60 == 0 {
                return "Cost refresh timed out after \(seconds / 60)m."
            }
            return "Cost refresh timed out after \(seconds)s."
        }
    }
}

public struct CostUsageCorpusFingerprint: Sendable, Codable, Equatable {
    public let roots: [String: Int64]
    public let fileCount: Int
    public let totalBytes: Int64
    public let newestModificationUnixMs: Int64

    public init(
        roots: [String: Int64],
        fileCount: Int,
        totalBytes: Int64,
        newestModificationUnixMs: Int64)
    {
        self.roots = roots
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.newestModificationUnixMs = newestModificationUnixMs
    }
}

public struct CostUsageFetcher: Sendable {
    public struct Options: Sendable {
        public var cacheRoot: URL?
        public var refreshMinIntervalSeconds: TimeInterval
        public var forceRefresh: Bool

        public init(
            cacheRoot: URL? = nil,
            refreshMinIntervalSeconds: TimeInterval = 60,
            forceRefresh: Bool = false)
        {
            self.cacheRoot = cacheRoot
            self.refreshMinIntervalSeconds = refreshMinIntervalSeconds
            self.forceRefresh = forceRefresh
        }
    }

    private let scanner: UsageScanner
    private let options: Options

    public init(scanner: UsageScanner? = nil, options: Options = Options()) {
        self.options = options
        self.scanner = scanner ?? UsageScanner(modelsDevCacheRoot: options.cacheRoot)
    }

    public func loadCachedReport(daysBack: Int = 30, now: Date = Date()) async -> UsageReport? {
        let days = Self.clampedHistoryDays(daysBack)
        return try? await CostUsageScanExecutor.run { _ in
            guard let artifact = CostUsageReportCache.load(cacheRoot: options.cacheRoot),
                  artifact.daysBack == days
            else { return nil }
            return self.cachedReport(from: artifact, now: now, reason: "explicit cache read")
        }
    }

    public func loadCachedTokenSnapshot(daysBack: Int = 30, now: Date = Date()) async -> CostUsageTokenSnapshot? {
        guard let report = await self.loadCachedReport(daysBack: daysBack, now: now) else { return nil }
        return report.costUsageDailyReport.tokenSnapshot(now: report.generatedAt, historyDays: report.daysBack)
    }

    public func loadReport(
        daysBack: Int = 30,
        now: Date = Date(),
        forceRefresh: Bool = false,
        refreshPricingInBackground: Bool = false) async throws -> UsageReport
    {
        let days = Self.clampedHistoryDays(daysBack)
        if refreshPricingInBackground {
            Task.detached(priority: .utility) {
                await ModelsDevPricingPipeline.refreshIfNeeded(now: now, cacheRoot: options.cacheRoot)
            }
        } else {
            await ModelsDevPricingPipeline.refreshIfNeeded(now: now, cacheRoot: options.cacheRoot)
        }

        let shouldForceRefresh = forceRefresh || options.forceRefresh
        if !shouldForceRefresh,
           let cached = CostUsageReportCache.load(cacheRoot: options.cacheRoot),
           cached.daysBack == days,
           now.timeIntervalSince(cached.generatedAt) >= 0,
           now.timeIntervalSince(cached.generatedAt) < options.refreshMinIntervalSeconds
        {
            return self.cachedReport(from: cached, now: now, reason: "refresh interval")
        }

        let fingerprint = try await CostUsageScanExecutor.run { checkCancellation in
            try checkCancellation()
            let value = try scanner.corpusFingerprint(
                daysBack: days,
                now: now,
                checkCancellation: checkCancellation)
            try checkCancellation()
            return value
        }

        if !shouldForceRefresh,
           let cached = CostUsageReportCache.load(cacheRoot: options.cacheRoot),
           cached.daysBack == days,
           cached.fingerprint == fingerprint,
           now.timeIntervalSince(cached.generatedAt) >= 0
        {
            return self.cachedReport(from: cached, now: now, reason: "fingerprint match")
        }

        let report = try await CostUsageScanExecutor.run { checkCancellation in
            try checkCancellation()
            let report = try scanner.scanWithFileCache(
                daysBack: days,
                now: now,
                cacheRoot: options.cacheRoot,
                forceRescan: shouldForceRefresh,
                checkCancellation: checkCancellation)
            try checkCancellation()
            return report
        }
        CostUsageReportCache.save(
            report: report,
            daysBack: days,
            fingerprint: fingerprint,
            cacheRoot: options.cacheRoot)
        return report
    }

    public func loadReportOrFallback(
        daysBack: Int = 30,
        now: Date = Date(),
        forceRefresh: Bool = false,
        refreshPricingInBackground: Bool = false) async -> UsageReport
    {
        do {
            return try await self.loadReport(
                daysBack: daysBack,
                now: now,
                forceRefresh: forceRefresh,
                refreshPricingInBackground: refreshPricingInBackground)
        } catch {
            var report = scanner.scan(daysBack: daysBack, now: now)
            report.sourceInfo = UsageReportSourceInfo(
                source: .fallbackScan,
                loadedAt: now,
                reason: String(describing: error))
            return report
        }
    }

    public func loadReportOrFallbackUnlessCancelled(
        daysBack: Int = 30,
        now: Date = Date(),
        forceRefresh: Bool = false,
        refreshPricingInBackground: Bool = false) async throws -> UsageReport
    {
        try Task.checkCancellation()
        do {
            return try await self.loadReport(
                daysBack: daysBack,
                now: now,
                forceRefresh: forceRefresh,
                refreshPricingInBackground: refreshPricingInBackground)
        } catch {
            try UsageProviderCancellation.rethrowIfCancelled(error)
            try Task.checkCancellation()
            var report = scanner.scan(daysBack: daysBack, now: now)
            report.sourceInfo = UsageReportSourceInfo(
                source: .fallbackScan,
                loadedAt: now,
                reason: String(describing: error))
            return report
        }
    }

    public func loadTokenSnapshot(
        daysBack: Int = 30,
        now: Date = Date(),
        forceRefresh: Bool = false) async throws -> CostUsageTokenSnapshot
    {
        let report = try await self.loadReport(daysBack: daysBack, now: now, forceRefresh: forceRefresh)
        return report.costUsageDailyReport.tokenSnapshot(now: now, historyDays: report.daysBack)
    }

    @discardableResult
    public static func clearCache(
        cacheRoot: URL? = nil,
        includePricing: Bool = false,
        applicationSupportRoot: URL? = nil) -> [URL]
    {
        var removed = CostUsageReportCache.clear(cacheRoot: cacheRoot)
        removed.append(contentsOf: UsageScanner.clearFileCache(cacheRoot: cacheRoot))
        removed.append(contentsOf: UsageCacheCleaner.clearUIPanelUsageCaches(
            applicationSupportRoot: applicationSupportRoot))
        if includePricing {
            let pricing = ModelsDevCache.cacheFileURL(cacheRoot: cacheRoot)
            if FileManager.default.fileExists(atPath: pricing.path) {
                try? FileManager.default.removeItem(at: pricing)
                removed.append(pricing)
            }
        }
        return removed
    }

    public static func clampedHistoryDays(_ daysBack: Int) -> Int {
        max(1, min(365, daysBack))
    }

    private func cachedReport(
        from artifact: CostUsageReportCacheArtifact,
        now: Date,
        reason: String) -> UsageReport
    {
        var report = artifact.report
        let age = max(0, now.timeIntervalSince(artifact.generatedAt))
        report.sourceInfo = UsageReportSourceInfo(
            source: .reportCache,
            loadedAt: now,
            cacheAgeSeconds: age,
            cachePath: CostUsageReportCache.cacheFileURL(cacheRoot: options.cacheRoot).path,
            reason: reason)
        return report
    }
}

private struct CostUsageReportCacheArtifact: Codable, Sendable {
    var version = 9
    var daysBack: Int
    var generatedAt: Date
    var fingerprint: CostUsageCorpusFingerprint
    var report: UsageReport
}

private enum CostUsageReportCache {
    private static let artifactVersion = 9

    static func cacheFileURL(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? defaultCacheRoot()
        return root
            .appendingPathComponent("cost-usage", isDirectory: true)
            .appendingPathComponent("local-report-v\(artifactVersion).json", isDirectory: false)
    }

    static func load(cacheRoot: URL? = nil) -> CostUsageReportCacheArtifact? {
        let url = cacheFileURL(cacheRoot: cacheRoot)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CostUsageReportCacheArtifact.self, from: data),
              decoded.version == artifactVersion
        else { return nil }
        return decoded
    }

    static func save(
        report: UsageReport,
        daysBack: Int,
        fingerprint: CostUsageCorpusFingerprint,
        cacheRoot: URL? = nil)
    {
        let url = cacheFileURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let artifact = CostUsageReportCacheArtifact(
            daysBack: daysBack,
            generatedAt: report.generatedAt,
            fingerprint: fingerprint,
            report: report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(artifact) else { return }
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

    static func clear(cacheRoot: URL? = nil) -> [URL] {
        let url = cacheFileURL(cacheRoot: cacheRoot)
        let directory = url.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)
        else { return [] }
        var removed: [URL] = []
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("local-report-v"), name.hasSuffix(".json") else { continue }
            try? FileManager.default.removeItem(at: file)
            removed.append(file)
        }
        return removed
    }

    private static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("Conductor", isDirectory: true)
    }
}
