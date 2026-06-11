import Foundation

/// 一条「最近关闭」记录：误关后可一键恢复（重建 shell 回到原目录；进程内容无法复活）。
public enum ClosedRecord: Equatable {
    /// 整个 tab：完整分屏树 + 每个 pane 关闭时的 cwd 与 agent 会话（pane.value → 值）。
    case tab(
        workspaceID: WorkspaceID, tab: Tab,
        paneCwds: [String: String], paneSessions: [String: AgentSessionRef])
    /// 多分屏 tab 里关掉的单个 pane：记住它来自哪个 tab、目录、分屏方向与 agent 会话。
    case pane(
        workspaceID: WorkspaceID, tabID: TabID, pane: PaneID,
        cwd: String?, axis: SplitAxis, session: AgentSessionRef?)
}

/// 定长 LIFO 栈：保留最近 capacity 条关闭记录，⌘⇧T 逐条弹出恢复。
/// 只存会话内，不落盘（跨重启的现场由 PersistedState 整体恢复）。
public struct RecentlyClosedStack: Equatable {
    public private(set) var records: [ClosedRecord] = []
    public let capacity: Int

    public init(capacity: Int = 10) {
        self.capacity = max(1, capacity)
    }

    public var isEmpty: Bool { records.isEmpty }
    public var count: Int { records.count }

    public mutating func push(_ record: ClosedRecord) {
        records.append(record)
        if records.count > capacity {
            records.removeFirst(records.count - capacity)
        }
    }

    public mutating func pop() -> ClosedRecord? {
        records.popLast()
    }
}
