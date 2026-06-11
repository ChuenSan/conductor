import ConductorCore
import Foundation

/// 会话列表磁盘缓存 + 后台扫描。
@MainActor
final class SessionManagerStore: ObservableObject {
    static let shared = SessionManagerStore()

    @Published private(set) var records: [AgentSessionRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastScannedAt: Date?
    @Published private(set) var scanError: String?

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
        loadCache()
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
        records.filter { $0.belongsToWorkspace(path) }.prefix(limit).map { $0 }
    }

    func recordsForDirectory(_ directory: String, limit: Int = 12) -> [AgentSessionRecord] {
        records.filter { $0.belongsToDirectory(directory) }.prefix(limit).map { $0 }
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
