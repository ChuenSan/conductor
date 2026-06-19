import ConductorCore
import Foundation

/// 会话 transcript 内存缓存：按文件路径 + 修改时间失效，避免重复解析大 jsonl。
@MainActor
final class SessionPreviewCache: ObservableObject {
    static let shared = SessionPreviewCache()
    nonisolated static let hoverPreviewLimit = 16
    nonisolated static let hoverTailBytes = 262_144
    nonisolated static let expandedPreviewLimit = 80
    nonisolated static let expandedTailBytes = 1_572_864

    private struct Entry {
        let mtime: Date
        let messages: [AgentSessionMessage]
    }

    private struct RequestKey: Hashable {
        let path: String
        let limit: Int
        let tailBytes: Int
    }

    private var entries: [RequestKey: Entry] = [:]
    private var inflight: [RequestKey: Task<[AgentSessionMessage], Never>] = [:]

    func messages(
        for record: AgentSessionRecord,
        limit: Int = expandedPreviewLimit,
        tailBytes: Int = expandedTailBytes
    ) async -> [AgentSessionMessage] {
        guard let path = record.filePath else { return [] }
        let key = RequestKey(path: path, limit: limit, tailBytes: tailBytes)
        let mtime = Self.modificationDate(path)
        if let cached = entries[key], cached.mtime == mtime { return cached.messages }
        if let task = inflight[key] { return await task.value }

        let agent = record.agent
        let task = Task.detached(priority: .userInitiated) {
            AgentSessionPreview.load(agent: agent, filePath: path, limit: limit, tailBytes: tailBytes)
        }
        inflight[key] = task
        let messages = await task.value
        inflight[key] = nil
        entries[key] = Entry(mtime: mtime, messages: messages)
        return messages
    }

    func prefetch(
        _ record: AgentSessionRecord,
        limit: Int = hoverPreviewLimit,
        tailBytes: Int = hoverTailBytes
    ) {
        guard record.filePath != nil else { return }
        Task { _ = await messages(for: record, limit: limit, tailBytes: tailBytes) }
    }

    func trimCacheForMemoryPressure() -> Int {
        let count = entries.count
        entries.removeAll(keepingCapacity: false)
        return count
    }

    fileprivate static func modificationDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            ?? .distantPast
    }
}

/// 会话 token 用量缓存：同样按「路径 + 修改时间」失效。
/// 解析整个 jsonl 有成本，行可见时才按需算，结果缓存复用。
@MainActor
final class SessionUsageCache {
    static let shared = SessionUsageCache()

    private struct Entry {
        let mtime: Date
        let usage: AgentSessionUsage?
    }

    private var entries: [String: Entry] = [:]
    private var inflight: [String: Task<AgentSessionUsage?, Never>] = [:]

    func usage(for record: AgentSessionRecord) async -> AgentSessionUsage? {
        guard let path = record.filePath else { return nil }
        let mtime = SessionPreviewCache.modificationDate(path)
        if let cached = entries[path], cached.mtime == mtime { return cached.usage }
        if let task = inflight[path] { return await task.value }

        let agent = record.agent
        let task = Task.detached(priority: .utility) {
            AgentSessionUsageScanner.scan(agent: agent, filePath: path)
        }
        inflight[path] = task
        let usage = await task.value
        inflight[path] = nil
        entries[path] = Entry(mtime: mtime, usage: usage)
        return usage
    }

    func trimCacheForMemoryPressure() -> Int {
        let count = entries.count
        entries.removeAll(keepingCapacity: false)
        return count
    }
}
