import CmuxCore
import Foundation

/// 会话 transcript 内存缓存：按文件路径 + 修改时间失效，避免重复解析大 jsonl。
@MainActor
final class SessionPreviewCache: ObservableObject {
    static let shared = SessionPreviewCache()

    private struct Entry {
        let mtime: Date
        let messages: [AgentSessionMessage]
    }

    private var entries: [String: Entry] = [:]
    private var inflight: [String: Task<[AgentSessionMessage], Never>] = [:]

    func messages(for record: AgentSessionRecord) async -> [AgentSessionMessage] {
        guard let path = record.filePath else { return [] }
        let mtime = Self.modificationDate(path)
        if let cached = entries[path], cached.mtime == mtime { return cached.messages }
        if let task = inflight[path] { return await task.value }

        let agent = record.agent
        let task = Task.detached(priority: .userInitiated) {
            AgentSessionPreview.loadFull(agent: agent, filePath: path)
        }
        inflight[path] = task
        let messages = await task.value
        inflight[path] = nil
        entries[path] = Entry(mtime: mtime, messages: messages)
        return messages
    }

    func prefetch(_ record: AgentSessionRecord) {
        guard record.filePath != nil else { return }
        Task { _ = await messages(for: record) }
    }

    private static func modificationDate(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)
            ?? .distantPast
    }
}
