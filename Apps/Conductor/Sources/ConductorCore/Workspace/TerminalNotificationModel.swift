import Foundation

public enum TerminalNotificationKind: String, Codable, Sendable {
    case notification
    case bell
    case agent
}

public struct TerminalNotificationRecord: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let workspaceID: WorkspaceID
    public let paneID: PaneID?
    public let terminalID: TerminalID
    public var title: String
    public var body: String
    public let createdAt: Date
    public var isRead: Bool
    public var kind: TerminalNotificationKind

    public init(
        id: UUID = UUID(),
        workspaceID: WorkspaceID,
        paneID: PaneID?,
        terminalID: TerminalID,
        title: String,
        body: String,
        createdAt: Date = Date(),
        isRead: Bool = false,
        kind: TerminalNotificationKind = .notification
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.paneID = paneID
        self.terminalID = terminalID
        self.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(96))
        self.body = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        self.createdAt = createdAt
        self.isRead = isRead
        self.kind = kind
    }
}

public struct TerminalNotificationSnapshot: Equatable, Codable, Sendable {
    public var records: [TerminalNotificationRecord]
    public var unreadCount: Int
    public var unreadCountByWorkspaceID: [WorkspaceID: Int]
    public var unreadCountByPaneID: [PaneID: Int]
    public var unreadCountByTerminalID: [TerminalID: Int]
    public var latestByTerminalID: [TerminalID: TerminalNotificationRecord]
    public var latestUnread: TerminalNotificationRecord?

    public static let empty = TerminalNotificationSnapshot(
        records: [],
        unreadCount: 0,
        unreadCountByWorkspaceID: [:],
        unreadCountByPaneID: [:],
        unreadCountByTerminalID: [:],
        latestByTerminalID: [:],
        latestUnread: nil
    )

    public func unreadCount(for workspaceID: WorkspaceID) -> Int {
        unreadCountByWorkspaceID[workspaceID] ?? 0
    }

    public func unreadCount(for paneID: PaneID) -> Int {
        unreadCountByPaneID[paneID] ?? 0
    }

    public func unreadCount(for terminalID: TerminalID) -> Int {
        unreadCountByTerminalID[terminalID] ?? 0
    }
}

public struct TerminalNotificationState: Equatable, Codable, Sendable {
    public private(set) var records: [TerminalNotificationRecord]
    public private(set) var snapshot: TerminalNotificationSnapshot

    public init(records: [TerminalNotificationRecord] = []) {
        self.records = Self.sorted(records)
        self.snapshot = Self.makeSnapshot(records: self.records)
    }

    @discardableResult
    public mutating func add(
        workspaceID: WorkspaceID,
        paneID: PaneID?,
        terminalID: TerminalID,
        title: String,
        body: String,
        kind: TerminalNotificationKind = .notification,
        createdAt: Date = Date()
    ) -> TerminalNotificationRecord {
        let fallbackTitle: String
        switch kind {
        case .bell:
            fallbackTitle = "Bell"
        case .agent:
            fallbackTitle = "Agent"
        case .notification:
            fallbackTitle = "Terminal"
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notification = TerminalNotificationRecord(
            workspaceID: workspaceID,
            paneID: paneID,
            terminalID: terminalID,
            title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
            body: body,
            createdAt: createdAt,
            kind: kind
        )

        records.removeAll {
            $0.workspaceID == workspaceID && $0.terminalID == terminalID
        }
        records.insert(notification, at: 0)
        refreshSnapshot()
        return notification
    }

    @discardableResult
    public mutating func markRead(id: UUID) -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return false }
        guard !records[index].isRead else { return false }
        records[index].isRead = true
        refreshSnapshot()
        return true
    }

    @discardableResult
    public mutating func markTerminalRead(_ terminalID: TerminalID) -> Bool {
        var changed = false
        for index in records.indices where records[index].terminalID == terminalID && !records[index].isRead {
            records[index].isRead = true
            changed = true
        }
        if changed { refreshSnapshot() }
        return changed
    }

    @discardableResult
    public mutating func markWorkspaceRead(_ workspaceID: WorkspaceID) -> Bool {
        var changed = false
        for index in records.indices where records[index].workspaceID == workspaceID && !records[index].isRead {
            records[index].isRead = true
            changed = true
        }
        if changed { refreshSnapshot() }
        return changed
    }

    @discardableResult
    public mutating func clear(id: UUID) -> Bool {
        let oldCount = records.count
        records.removeAll { $0.id == id }
        guard records.count != oldCount else { return false }
        refreshSnapshot()
        return true
    }

    @discardableResult
    public mutating func clearTerminal(_ terminalID: TerminalID) -> Bool {
        let oldCount = records.count
        records.removeAll { $0.terminalID == terminalID }
        guard records.count != oldCount else { return false }
        refreshSnapshot()
        return true
    }

    @discardableResult
    public mutating func clearAll() -> Bool {
        guard !records.isEmpty else { return false }
        records.removeAll(keepingCapacity: true)
        refreshSnapshot()
        return true
    }

    @discardableResult
    public mutating func keepOnlyTerminals(_ terminalIDs: Set<TerminalID>) -> Bool {
        let oldCount = records.count
        records.removeAll { !terminalIDs.contains($0.terminalID) }
        guard records.count != oldCount else { return false }
        refreshSnapshot()
        return true
    }

    private mutating func refreshSnapshot() {
        records = Self.sorted(records)
        snapshot = Self.makeSnapshot(records: records)
    }

    private static func sorted(_ records: [TerminalNotificationRecord]) -> [TerminalNotificationRecord] {
        records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func makeSnapshot(records: [TerminalNotificationRecord]) -> TerminalNotificationSnapshot {
        var unreadCount = 0
        var unreadCountByWorkspaceID: [WorkspaceID: Int] = [:]
        var unreadCountByPaneID: [PaneID: Int] = [:]
        var unreadCountByTerminalID: [TerminalID: Int] = [:]
        var latestByTerminalID: [TerminalID: TerminalNotificationRecord] = [:]
        var latestUnread: TerminalNotificationRecord?

        for record in records {
            if latestByTerminalID[record.terminalID] == nil {
                latestByTerminalID[record.terminalID] = record
            }

            guard !record.isRead else { continue }
            unreadCount += 1
            unreadCountByWorkspaceID[record.workspaceID, default: 0] += 1
            if let paneID = record.paneID {
                unreadCountByPaneID[paneID, default: 0] += 1
            }
            unreadCountByTerminalID[record.terminalID, default: 0] += 1
            if latestUnread == nil {
                latestUnread = record
            }
        }

        return TerminalNotificationSnapshot(
            records: records,
            unreadCount: unreadCount,
            unreadCountByWorkspaceID: unreadCountByWorkspaceID,
            unreadCountByPaneID: unreadCountByPaneID,
            unreadCountByTerminalID: unreadCountByTerminalID,
            latestByTerminalID: latestByTerminalID,
            latestUnread: latestUnread
        )
    }
}

