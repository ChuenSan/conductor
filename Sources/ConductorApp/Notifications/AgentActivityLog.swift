import Foundation
import ConductorCore

/// 一条 agent 完成记录（hook Stop 事件落账）。
struct AgentActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let paneID: PaneID?
    let agentID: String?
    let title: String
    let message: String
}

/// Agent 活动账本：hook 完成事件的滚动记录（最多 50 条），驱动状态栏铃铛与通知中心列表。
/// 系统通知一闪而过，错过了还能回这里找「刚才是谁干完了什么」。
@MainActor
final class AgentActivityLog: ObservableObject {
    @Published private(set) var entries: [AgentActivityEntry] = []
    /// 未查看条数（铃铛角标）；打开通知中心即清零。
    @Published private(set) var unseenCount = 0

    private static let limit = 50

    func record(paneID: PaneID?, agentID: String?, title: String, message: String) {
        entries.insert(
            AgentActivityEntry(date: Date(), paneID: paneID, agentID: agentID,
                               title: title, message: message),
            at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        unseenCount += 1
    }

    func markSeen() {
        unseenCount = 0
    }

    func clear() {
        entries.removeAll()
        unseenCount = 0
    }
}
