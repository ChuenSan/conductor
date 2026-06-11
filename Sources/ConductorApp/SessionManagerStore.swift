import ConductorCore
import Foundation

/// 会话列表磁盘缓存 + 后台扫描。
@MainActor
final class SessionManagerStore: ObservableObject {
    static let shared = SessionManagerStore()

    @Published private(set) var records: [AgentSessionRecord] = [] {
        didSet { scopeCache.removeAll() }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var lastScannedAt: Date?
    @Published private(set) var scanError: String?
    /// 收藏置顶的会话 id（`agent:sessionID`），跨启动保留。
    @Published private(set) var pinnedIDs: Set<String>

    /// 按目录范围过滤的结果缓存：侧栏每次 body 求值都要查，别反复过滤几百条。
    /// records 一变整体失效。
    private var scopeCache: [String: [AgentSessionRecord]] = [:]

    private static let pinnedKey = "sessions.pinned"
    private let cacheURL: URL
    private var scanTask: Task<Void, Never>?

    private struct CacheFile: Codable {
        var scannedAt: Date
        var records: [AgentSessionRecord]
    }

    init() {
        cacheURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
            .appendingPathComponent("sessions-cache.json")
        pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? [])
        loadCache()
    }

    func isPinned(_ record: AgentSessionRecord) -> Bool {
        pinnedIDs.contains(record.id)
    }

    func togglePin(_ record: AgentSessionRecord) {
        if !pinnedIDs.insert(record.id).inserted {
            pinnedIDs.remove(record.id)
        }
        UserDefaults.standard.set(Array(pinnedIDs).sorted(), forKey: Self.pinnedKey)
    }

    /// 删除会话：磁盘上的 jsonl 一并删（无法撤销，调用方先确认）。
    func delete(_ record: AgentSessionRecord) {
        if let path = record.filePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        records.removeAll { $0.id == record.id }
        if pinnedIDs.remove(record.id) != nil {
            UserDefaults.standard.set(Array(pinnedIDs).sorted(), forKey: Self.pinnedKey)
        }
        // 同步改写磁盘缓存，避免下次启动「亡灵会话」闪现
        let cache = CacheFile(scannedAt: lastScannedAt ?? Date(), records: records)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    func refresh(force: Bool = false) {
        if isLoading, !force { return }
        scanTask?.cancel()
        isLoading = true
        scanError = nil
        scanTask = Task(priority: .utility) { [cacheURL] in
            let scanned = await Task.detached { AgentSessionCatalog.scan(limit: 200) }.value
            let cache = CacheFile(scannedAt: Date(), records: scanned)
            if let data = try? JSONEncoder().encode(cache) {
                try? FileManager.default.createDirectory(
                    at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                Self.shared.records = scanned
                Self.shared.lastScannedAt = cache.scannedAt
                Self.shared.isLoading = false
            }
        }
    }

    func recordsForWorkspace(_ path: String, limit: Int = 8) -> [AgentSessionRecord] {
        let key = "w|\(limit)|\(path)"
        if let hit = scopeCache[key] { return hit }
        let result = Array(records.filter { $0.belongsToWorkspace(path) }.prefix(limit))
        scopeCache[key] = result
        return result
    }

    func recordsForDirectory(_ directory: String, limit: Int = 12) -> [AgentSessionRecord] {
        let key = "d|\(limit)|\(directory)"
        if let hit = scopeCache[key] { return hit }
        let result = Array(records.filter { $0.belongsToDirectory(directory) }.prefix(limit))
        scopeCache[key] = result
        return result
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(CacheFile.self, from: data)
        else { return }
        // 旧缓存可能还存着 /usage 这类纯命令会话，加载时一并滤掉
        records = cache.records.filter { !AgentSessionCatalog.isUtilityCommandTitle($0.title) }
        lastScannedAt = cache.scannedAt
    }
}
