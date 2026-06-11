import Foundation
import ConductorCore

/// 一条 agent 完成记录（hook Stop 事件落账）。
struct AgentActivityEntry: Identifiable, Equatable, Codable {
    var id = UUID()
    let date: Date
    let paneID: PaneID?
    let agentID: String?
    let title: String
    let message: String
    /// 本轮思考用时（busy → done）；nil = 未知（hook 没装或事件丢失）。旧记录解码为 nil。
    var duration: TimeInterval?

    /// 28s →「28 秒」；95s →「1 分 35 秒」；3700s →「1 小时 2 分」。
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(1, Int(seconds.rounded()))
        if total < 60 { return L("%ld 秒", total) }
        if total < 3600 {
            let m = total / 60
            let s = total % 60
            return s == 0 ? L("%ld 分钟", m) : L("%1$ld 分 %2$ld 秒", m, s)
        }
        let h = total / 3600
        let m = (total % 3600) / 60
        return m == 0 ? L("%ld 小时", h) : L("%1$ld 小时 %2$ld 分", h, m)
    }
}

/// Agent 活动账本：hook 完成事件的滚动记录（最多 50 条），驱动状态栏铃铛与通知中心列表。
/// 系统通知一闪而过，错过了还能回这里找「刚才是谁干完了什么」。
/// JSON 持久化：重启后记录还在（旧 pane 已不存在，列表里置灰展示）。
@MainActor
final class AgentActivityLog: ObservableObject {
    @Published private(set) var entries: [AgentActivityEntry] = []
    /// 未查看条数（铃铛角标）；打开通知中心即清零。
    @Published private(set) var unseenCount = 0

    private static let limit = 50

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
            .appendingPathComponent("activity.json")
    }

    /// 磁盘文件结构：记录 + 未读数一起存，重启不丢角标。
    private struct Snapshot: Codable {
        var entries: [AgentActivityEntry]
        var unseen: Int
    }

    init() {
        load()
    }

    func record(paneID: PaneID?, agentID: String?, title: String, message: String,
                duration: TimeInterval? = nil) {
        entries.insert(
            AgentActivityEntry(date: Date(), paneID: paneID, agentID: agentID,
                               title: title, message: message, duration: duration),
            at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        unseenCount += 1
        scheduleSave()
    }

    func markSeen() {
        guard unseenCount != 0 else { return }
        unseenCount = 0
        scheduleSave()
    }

    /// 删掉单条记录（通知中心行内 ✕）。
    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        unseenCount = 0
        scheduleSave()
    }

    // MARK: - 持久化

    private var saveWork: DispatchWorkItem?

    /// 短暂合并连发的写盘（hook 可能一波多条）。
    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let snapshot = try? Self.decoder.decode(Snapshot.self, from: data) else { return }
        entries = Array(snapshot.entries.prefix(Self.limit))
        unseenCount = snapshot.unseen
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(Snapshot(entries: entries, unseen: unseenCount))
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("[conductor] 写 activity.json 失败：\(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
