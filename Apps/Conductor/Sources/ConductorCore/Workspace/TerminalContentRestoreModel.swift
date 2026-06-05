import Foundation

public struct PersistedTerminalContentSnapshot: Codable, Equatable, Sendable {
    public var terminalID: TerminalID
    public var workspaceID: WorkspaceID
    public var paneID: PaneID?
    public var capturedAt: Date
    public var workingDirectory: String?
    public var text: String
    public var agentSnapshot: TerminalAgentSnapshot?

    public init(
        terminalID: TerminalID,
        workspaceID: WorkspaceID,
        paneID: PaneID?,
        capturedAt: Date,
        workingDirectory: String?,
        text: String,
        agentSnapshot: TerminalAgentSnapshot?
    ) {
        self.terminalID = terminalID
        self.workspaceID = workspaceID
        self.paneID = paneID
        self.capturedAt = capturedAt
        self.workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.text = TerminalContentSnapshotSanitizer.sanitizedText(text)
        self.agentSnapshot = agentSnapshot
    }
}

public struct PersistedTerminalContentSnapshotFile: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var capturedAt: Date
    public var snapshots: [PersistedTerminalContentSnapshot]

    public init(
        schemaVersion: Int = PersistedTerminalContentSnapshotFile.currentSchemaVersion,
        capturedAt: Date,
        snapshots: [PersistedTerminalContentSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.snapshots = snapshots
    }

    public func filtered(validTerminalIDs: Set<TerminalID>) -> PersistedTerminalContentSnapshotFile {
        PersistedTerminalContentSnapshotFile(
            schemaVersion: schemaVersion,
            capturedAt: capturedAt,
            snapshots: snapshots.filter { validTerminalIDs.contains($0.terminalID) }
        )
    }
}

public struct RestoredTerminalContent: Codable, Equatable, Sendable {
    public static let restoreHintPrefix = "Conductor restore hint:"

    public var terminalID: TerminalID
    public var capturedAt: Date
    public var text: String
    public var resumeHint: String?

    public init(terminalID: TerminalID, capturedAt: Date, text: String, resumeHint: String?) {
        self.terminalID = terminalID
        self.capturedAt = capturedAt
        self.text = text
        self.resumeHint = resumeHint
    }

    public static func make(
        terminalID: TerminalID,
        capturedAt: Date,
        rawText: String,
        tabAgentSnapshot: TerminalAgentSnapshot?,
        persistedAgentSnapshot: TerminalAgentSnapshot?,
        maxUTF8Bytes: Int = TerminalContentSnapshotSanitizer.defaultMaxUTF8Bytes
    ) -> RestoredTerminalContent? {
        var text = TerminalContentSnapshotSanitizer.sanitizedText(rawText, maxUTF8Bytes: maxUTF8Bytes)
        let resumeHint = resumeCommand(tabAgentSnapshot: tabAgentSnapshot, persistedAgentSnapshot: persistedAgentSnapshot)
        if let resumeHint {
            text = textWithoutExistingRestoreHints(text)
            text = text.isEmpty ? "\(restoreHintPrefix) \(resumeHint)" : "\(text)\n\(restoreHintPrefix) \(resumeHint)"
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RestoredTerminalContent(
            terminalID: terminalID,
            capturedAt: capturedAt,
            text: text,
            resumeHint: resumeHint
        )
    }

    private static func resumeCommand(
        tabAgentSnapshot: TerminalAgentSnapshot?,
        persistedAgentSnapshot: TerminalAgentSnapshot?
    ) -> String? {
        let candidates = [tabAgentSnapshot, persistedAgentSnapshot]
        for candidate in candidates {
            if let metadata = AgentResumeDetector.metadata(
                providerID: candidate?.providerID,
                sessionIdentifier: candidate?.sessionIdentifier
            ) {
                return metadata.resumeCommand
            }
            if let resumeCommand = candidate?.resumeCommand,
               let metadata = AgentResumeDetector.detect(in: resumeCommand) {
                return metadata.resumeCommand
            }
        }
        return nil
    }

    private static func textWithoutExistingRestoreHints(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(restoreHintPrefix) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum TerminalContentSnapshotSanitizer {
    public static let defaultMaxUTF8Bytes = 32 * 1024

    public static func sanitizedText(
        _ rawText: String,
        maxUTF8Bytes: Int = defaultMaxUTF8Bytes
    ) -> String {
        let printable = rawText.unicodeScalars.map { scalar -> Character in
            if scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar) {
                return Character(scalar)
            }
            return "\n"
        }
        let normalized = String(printable)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return suffixWithinUTF8Limit(normalized, maxBytes: maxUTF8Bytes)
    }

    private static func suffixWithinUTF8Limit(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0, text.utf8.count > maxBytes else { return text }
        var result = ""
        for character in text.reversed() {
            let next = String(character) + result
            if next.utf8.count > maxBytes { break }
            result = next
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
