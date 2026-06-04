import Foundation

public struct ConductorAttentionEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case agentReply
        case terminalBell
        case commandFinished
        case updateAvailable
        case updateFailed
        case browserError
        case sessionRecovery
        case permissionWarning
        case manual
    }

    public enum Severity: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    public var id: UUID
    public var createdAt: Date
    public var kind: Kind
    public var severity: Severity
    public var title: String
    public var body: String
    public var workspaceID: WorkspaceID?
    public var terminalID: TerminalID?
    public var webTabID: WebTabID?
    public var source: String
    public var readAt: Date?
    public var details: [String: String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: Kind,
        severity: Severity = .info,
        title: String,
        body: String = "",
        workspaceID: WorkspaceID? = nil,
        terminalID: TerminalID? = nil,
        webTabID: WebTabID? = nil,
        source: String,
        readAt: Date? = nil,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.severity = severity
        self.title = title
        self.body = body
        self.workspaceID = workspaceID
        self.terminalID = terminalID
        self.webTabID = webTabID
        self.source = source
        self.readAt = readAt
        self.details = details
    }

    public var isUnread: Bool {
        readAt == nil
    }
}
