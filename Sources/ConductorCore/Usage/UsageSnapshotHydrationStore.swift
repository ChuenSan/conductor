import Foundation

public struct UsageSnapshotHydrationRecord: Codable, Equatable, Sendable {
    public let version: Int
    public let providerID: String
    public let accountKey: String?
    public let storageID: String
    public let snapshot: UsageSnapshot
    public let recordedAt: Date
    public let source: String?

    public init(
        version: Int = 1,
        providerID: String,
        accountKey: String?,
        snapshot: UsageSnapshot,
        recordedAt: Date = Date(),
        source: String? = nil)
    {
        let normalizedProviderID = Self.normalizedProviderID(providerID)
        let normalizedAccountKey = Self.normalized(accountKey)
        self.version = version
        self.providerID = normalizedProviderID
        self.accountKey = normalizedAccountKey
        self.storageID = UsageAccountCacheKey.storageID(
            providerID: normalizedProviderID,
            accountKey: normalizedAccountKey)
        self.snapshot = snapshot
        self.recordedAt = recordedAt
        self.source = Self.normalized(source)
    }

    private static func normalizedProviderID(_ raw: String) -> String {
        normalized(raw)?.lowercased() ?? raw.lowercased()
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public enum UsageSnapshotHydrationStore {
    public static let defaultMaxAge: TimeInterval = 24 * 60 * 60

    private static let schemaVersion = 1
    private static let retention: TimeInterval = 14 * 24 * 60 * 60
    private static let maxRecords = 300
    private static let lock = NSLock()

    public static func save(
        providerID: String,
        accountKey: String?,
        snapshot: UsageSnapshot,
        recordedAt: Date = Date(),
        source: String? = nil,
        applicationSupportRoot: URL? = nil)
    {
        guard !snapshot.isEmpty else { return }
        lock.withLock {
            var cache = loadCache(applicationSupportRoot: applicationSupportRoot)
            let record = UsageSnapshotHydrationRecord(
                version: schemaVersion,
                providerID: providerID,
                accountKey: accountKey,
                snapshot: snapshot,
                recordedAt: recordedAt,
                source: source)
            cache.records[record.storageID] = record
            prune(&cache, now: recordedAt)
            write(cache, applicationSupportRoot: applicationSupportRoot)
        }
    }

    public static func loadRecord(
        providerID: String,
        accountKey: String?,
        maxAge: TimeInterval? = defaultMaxAge,
        applicationSupportRoot: URL? = nil)
        -> UsageSnapshotHydrationRecord?
    {
        lock.withLock {
            let cache = loadCache(applicationSupportRoot: applicationSupportRoot)
            return selectedRecord(
                in: cache,
                providerID: providerID,
                accountKey: accountKey,
                maxAge: maxAge)
        }
    }

    public static func loadSnapshot(
        providerID: String,
        accountKey: String?,
        maxAge: TimeInterval? = defaultMaxAge,
        applicationSupportRoot: URL? = nil)
        -> UsageSnapshot?
    {
        loadRecord(
            providerID: providerID,
            accountKey: accountKey,
            maxAge: maxAge,
            applicationSupportRoot: applicationSupportRoot)?
            .snapshot
    }

    @discardableResult
    public static func clear(applicationSupportRoot: URL? = nil) -> [URL] {
        lock.withLock {
            UsageCacheCleaner.removeCacheFileIfExists(fileURL(applicationSupportRoot: applicationSupportRoot))
        }
    }

    public static func fileURL(applicationSupportRoot: URL? = nil) -> URL {
        let root = applicationSupportRoot ?? UsageCacheCleaner.defaultApplicationSupportRoot()
        return root.appendingPathComponent("usage-snapshot-hydration.json", isDirectory: false)
    }

    private static func selectedRecord(
        in cache: Cache,
        providerID: String,
        accountKey: String?,
        maxAge: TimeInterval?)
        -> UsageSnapshotHydrationRecord?
    {
        let provider = normalizedProviderID(providerID)
        let normalizedAccountKey = normalized(accountKey)
        let storageID = UsageAccountCacheKey.storageID(
            providerID: provider,
            accountKey: normalizedAccountKey)
        let now = Date()

        if let scoped = cache.records[storageID],
           isFresh(scoped, now: now, maxAge: maxAge)
        {
            return scoped
        }

        guard normalizedAccountKey != nil else { return nil }
        let fallbackID = UsageAccountCacheKey.storageID(providerID: provider, accountKey: nil)
        guard let fallback = cache.records[fallbackID],
              isFresh(fallback, now: now, maxAge: maxAge)
        else {
            return nil
        }
        return fallback
    }

    private static func isFresh(
        _ record: UsageSnapshotHydrationRecord,
        now: Date,
        maxAge: TimeInterval?)
        -> Bool
    {
        guard let maxAge else { return true }
        return now.timeIntervalSince(record.recordedAt) <= maxAge
    }

    private static func loadCache(applicationSupportRoot: URL?) -> Cache {
        let url = fileURL(applicationSupportRoot: applicationSupportRoot)
        guard let data = try? Data(contentsOf: url) else {
            return Cache(version: schemaVersion, records: [:])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var cache = try? decoder.decode(Cache.self, from: data) else {
            return Cache(version: schemaVersion, records: [:])
        }
        cache.records = Dictionary(uniqueKeysWithValues: cache.records.values.map { record in
            let normalized = UsageSnapshotHydrationRecord(
                providerID: record.providerID,
                accountKey: record.accountKey,
                snapshot: record.snapshot,
                recordedAt: record.recordedAt,
                source: record.source)
            return (normalized.storageID, normalized)
        })
        return cache
    }

    private static func write(_ cache: Cache, applicationSupportRoot: URL?) {
        let url = fileURL(applicationSupportRoot: applicationSupportRoot)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
        }
    }

    private static func prune(_ cache: inout Cache, now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        cache.records = cache.records.filter { _, record in
            record.recordedAt >= cutoff
        }
        guard cache.records.count > maxRecords else { return }
        let keep = cache.records.values
            .sorted { $0.recordedAt > $1.recordedAt }
            .prefix(maxRecords)
        cache.records = Dictionary(uniqueKeysWithValues: keep.map { ($0.storageID, $0) })
    }

    private static func normalizedProviderID(_ raw: String) -> String {
        normalized(raw)?.lowercased() ?? raw.lowercased()
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private struct Cache: Codable {
        var version: Int
        var records: [String: UsageSnapshotHydrationRecord]
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
