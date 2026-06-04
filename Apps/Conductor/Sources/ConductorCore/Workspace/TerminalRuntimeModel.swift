import Foundation

public enum TerminalAgentLifecycleState: String, Codable, Sendable {
    case active
    case idle
    case completed
}

public struct TerminalAgentSnapshot: Equatable, Codable, Sendable {
    public var providerID: String?
    public var displayName: String
    public var state: TerminalAgentLifecycleState
    public var startedAt: Date?
    public var updatedAt: Date
    public var lastEvent: String?
    public var resumeCommand: String?
    public var sessionIdentifier: String?

    public init(
        providerID: String? = nil,
        displayName: String,
        state: TerminalAgentLifecycleState,
        startedAt: Date? = nil,
        updatedAt: Date = Date(),
        lastEvent: String? = nil,
        resumeCommand: String? = nil,
        sessionIdentifier: String? = nil
    ) {
        self.providerID = Self.normalizedOptional(providerID)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.lastEvent = Self.normalizedOptional(lastEvent)
        self.resumeCommand = Self.normalizedOptional(resumeCommand)
        self.sessionIdentifier = Self.normalizedOptional(sessionIdentifier)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

public struct TerminalCommandSnapshot: Equatable, Codable, Sendable {
    public var exitCode: Int?
    public var durationNanoseconds: UInt64?
    public var finishedAt: Date

    public init(
        exitCode: Int?,
        durationNanoseconds: UInt64?,
        finishedAt: Date = Date()
    ) {
        self.exitCode = exitCode
        self.durationNanoseconds = durationNanoseconds
        self.finishedAt = finishedAt
    }
}

public struct TerminalSearchSnapshot: Equatable, Codable, Sendable {
    public var active: Bool
    public var needle: String?
    public var total: Int?
    public var selected: Int?
    public var updatedAt: Date

    public init(
        active: Bool,
        needle: String? = nil,
        total: Int? = nil,
        selected: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.active = active
        self.needle = needle.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
        }
        self.total = total
        self.selected = selected
        self.updatedAt = updatedAt
    }
}
