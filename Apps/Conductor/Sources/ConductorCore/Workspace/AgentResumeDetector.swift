import Foundation

public struct AgentResumeMetadata: Equatable, Sendable {
    public var providerID: String
    public var displayName: String
    public var sessionIdentifier: String
    public var resumeCommand: String

    public init(
        providerID: String,
        displayName: String,
        sessionIdentifier: String,
        resumeCommand: String
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.sessionIdentifier = sessionIdentifier
        self.resumeCommand = resumeCommand
    }
}

public enum AgentResumeDetector {
    public static func metadata(providerID rawProviderID: String?, sessionIdentifier rawSessionID: String?) -> AgentResumeMetadata? {
        guard let providerID = normalizedProviderID(rawProviderID),
              let sessionID = normalizedSessionIdentifier(rawSessionID) else {
            return nil
        }
        let escapedID = shellEscaped(sessionID)
        switch providerID {
        case "codex":
            return AgentResumeMetadata(
                providerID: "codex",
                displayName: "Codex",
                sessionIdentifier: sessionID,
                resumeCommand: "codex resume \(escapedID)"
            )
        case "claude", "claude-code", "cc":
            return AgentResumeMetadata(
                providerID: "claude",
                displayName: "Claude Code",
                sessionIdentifier: sessionID,
                resumeCommand: "claude --resume \(escapedID)"
            )
        default:
            return nil
        }
    }

    public static func detect(in text: String, fallbackProviderID _: String? = nil) -> AgentResumeMetadata? {
        for line in text.components(separatedBy: .newlines).reversed() {
            if let metadata = detectCodexResume(in: line) {
                return metadata
            }
            if let metadata = detectClaudeResume(in: line) {
                return metadata
            }
        }
        return nil
    }

    private static func detectCodexResume(in line: String) -> AgentResumeMetadata? {
        guard let commandRange = line.range(of: "codex resume", options: [.caseInsensitive]) else {
            return nil
        }
        let suffix = String(line[commandRange.upperBound...])
        guard let sessionID = firstCommandArgument(in: suffix) else {
            return nil
        }
        return metadata(providerID: "codex", sessionIdentifier: sessionID)
    }

    private static func detectClaudeResume(in line: String) -> AgentResumeMetadata? {
        guard let commandRange = line.range(of: "claude", options: [.caseInsensitive]) else {
            return nil
        }
        let suffix = String(line[commandRange.upperBound...])
        guard suffix.contains("--resume") || suffix.contains(" -r ") || suffix.trimmingCharacters(in: .whitespaces).hasPrefix("-r ") else {
            return nil
        }
        let marker: String
        if suffix.contains("--resume") {
            marker = "--resume"
        } else {
            marker = "-r"
        }
        guard let markerRange = suffix.range(of: marker),
              let sessionID = firstCommandArgument(in: String(suffix[markerRange.upperBound...])) else {
            return nil
        }
        return metadata(providerID: "claude", sessionIdentifier: sessionID)
    }

    private static func firstCommandArgument(in rawSuffix: String) -> String? {
        let suffix = rawSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suffix.isEmpty else { return nil }
        if let first = suffix.first, first == "\"" || first == "'" {
            let tail = suffix.dropFirst()
            guard let endIndex = tail.firstIndex(of: first) else { return nil }
            return normalizedSessionIdentifier(String(tail[..<endIndex]))
        }
        let token = suffix.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return normalizedSessionIdentifier(token)
    }

    private static func normalizedProviderID(_ rawValue: String?) -> String? {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        switch normalized {
        case "codex":
            return "codex"
        case "claude", "claude-code", "cc":
            return "claude"
        default:
            return normalized
        }
    }

    private static func normalizedSessionIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'`<>[](){}.,;:")))
        guard trimmed.count >= 6, trimmed.count <= 160 else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private static func shellEscaped(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
