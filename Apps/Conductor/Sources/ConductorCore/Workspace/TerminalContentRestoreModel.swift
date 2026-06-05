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
        text = textWithoutExistingRestoreHints(text)
        let resumeHint = resumeCommand(tabAgentSnapshot: tabAgentSnapshot, persistedAgentSnapshot: persistedAgentSnapshot)
        if let resumeHint {
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
        var lines: [String] = []
        var continuationLinesRemaining = 0
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(restoreHintPrefix) {
                continuationLinesRemaining = shouldStripRestoreHintContinuation(trimmed) ? 1 : 0
                continue
            }
            if continuationLinesRemaining > 0 {
                if trimmed.isEmpty {
                    continuationLinesRemaining = 0
                    lines.append(line)
                    continue
                }
                if isRestoreHintContinuation(trimmed) {
                    continuationLinesRemaining = 0
                    continue
                }
                continuationLinesRemaining = 0
            }
            lines.append(line)
        }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isRestoreHintContinuation(_ line: String) -> Bool {
        guard line.count >= 6, line.count <= 160 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        guard line.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return line.unicodeScalars.contains { scalar in
            CharacterSet.decimalDigits.contains(scalar) || "._:-".unicodeScalars.contains(scalar)
        }
    }

    private static func shouldStripRestoreHintContinuation(_ line: String) -> Bool {
        guard AgentResumeDetector.detect(in: line) == nil else { return false }
        let command = line
            .dropFirst(restoreHintPrefix.count)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return command == "codex resume" || command == "claude --resume"
    }
}

public enum TerminalContentSnapshotSanitizer {
    public static let defaultMaxUTF8Bytes = 32 * 1024

    public static func sanitizedText(
        _ rawText: String,
        maxUTF8Bytes: Int = defaultMaxUTF8Bytes
    ) -> String {
        guard maxUTF8Bytes > 0 else { return "" }
        let normalized = boundedPrintableTail(rawText, maxBytes: maxUTF8Bytes)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .spaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .spacesAndNewlines)
        return suffixWithinUTF8Limit(normalized, maxBytes: maxUTF8Bytes)
    }

    private static func boundedPrintableTail(_ rawText: String, maxBytes: Int) -> String {
        let safetyWindow = tailSafetyWindow(maxBytes: maxBytes)
        var tail = ""
        var tailByteCount = 0
        var index = rawText.unicodeScalars.startIndex
        while index < rawText.unicodeScalars.endIndex {
            let scalar = rawText.unicodeScalars[index]
            let character: Character?
            if scalar == "\r" {
                character = "\n"
                let nextIndex = rawText.unicodeScalars.index(after: index)
                if nextIndex < rawText.unicodeScalars.endIndex,
                   rawText.unicodeScalars[nextIndex] == "\n" {
                    index = rawText.unicodeScalars.index(after: nextIndex)
                } else {
                    index = nextIndex
                }
            } else {
                if scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar) {
                    character = Character(scalar)
                } else {
                    character = nil
                }
                index = rawText.unicodeScalars.index(after: index)
            }
            if let character {
                append(character, to: &tail, byteCount: &tailByteCount, maxBytes: safetyWindow)
            }
        }
        return tail
    }

    private static func append(
        _ character: Character,
        to tail: inout String,
        byteCount: inout Int,
        maxBytes: Int
    ) {
        tail.append(character)
        byteCount += String(character).utf8.count
        while byteCount > maxBytes, let first = tail.first {
            byteCount -= String(first).utf8.count
            tail.removeFirst()
        }
    }

    private static func tailSafetyWindow(maxBytes: Int) -> Int {
        let multiplied = maxBytes > Int.max / 4 ? Int.max : maxBytes * 4
        let added = maxBytes > Int.max - 4_096 ? Int.max : maxBytes + 4_096
        return max(multiplied, added)
    }

    private static func suffixWithinUTF8Limit(_ text: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        guard text.utf8.count > maxBytes else { return text }
        var byteCount = 0
        var startIndex = text.endIndex
        var index = text.endIndex
        while index > text.startIndex {
            let previousIndex = text.index(before: index)
            let characterByteCount = text[previousIndex..<index].utf8.count
            if byteCount + characterByteCount > maxBytes {
                break
            }
            byteCount += characterByteCount
            startIndex = previousIndex
            index = previousIndex
        }
        return String(text[startIndex...]).trimmingCharacters(in: .spacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension CharacterSet {
    static let spaces = CharacterSet(charactersIn: " ")
    static let spacesAndNewlines = CharacterSet(charactersIn: " \n")
}
