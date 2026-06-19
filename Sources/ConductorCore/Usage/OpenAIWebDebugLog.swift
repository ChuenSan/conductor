import Foundation

public struct UsageWebDebugSnapshot: Sendable {
    public let text: String
    public let status: String?
    public let artifactPaths: [String]

    public init(text: String, status: String?, artifactPaths: [String]) {
        self.text = text
        self.status = status
        self.artifactPaths = artifactPaths
    }
}

public typealias OpenAIWebDebugSnapshot = UsageWebDebugSnapshot

public final class UsageWebDebugLog: @unchecked Sendable {
    public static let openAI = UsageWebDebugLog(
        label: "OpenAI web",
        artifactPattern: #"/[^\s;]+codex-openai-dashboard-\d+\.(?:html|txt)"#)
    public static let claude = UsageWebDebugLog(label: "Claude web")

    private let lock = NSLock()
    private var lines: [String] = []
    private var status: String?
    private let maxLines = 240
    private let label: String
    private let artifactRegex: NSRegularExpression?

    private init(label: String, artifactPattern: String? = nil) {
        self.label = label
        if let artifactPattern {
            self.artifactRegex = try? NSRegularExpression(
                pattern: artifactPattern,
                options: [.caseInsensitive])
        } else {
            self.artifactRegex = nil
        }
    }

    public func reset(context: String) {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        status = nil
        lock.unlock()
        let stamp = Self.timestamp()
        append("[\(stamp)] \(label) \(context) start")
    }

    public func append(_ message: String) {
        let safeMessage = UsageDiagnosticRedactor.redact(message)
        lock.lock()
        lines.append(safeMessage)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()
    }

    public func updateStatus(_ message: String?) {
        let safeMessage = message.map(UsageDiagnosticRedactor.redact)
        lock.lock()
        status = safeMessage
        lock.unlock()
    }

    public func snapshot() -> UsageWebDebugSnapshot {
        lock.lock()
        let text = lines.joined(separator: "\n")
        let currentStatus = status
        lock.unlock()
        return UsageWebDebugSnapshot(
            text: text,
            status: currentStatus,
            artifactPaths: artifactPaths(in: text))
    }

    public func snapshotText() -> String {
        lock.lock()
        let text = lines.joined(separator: "\n")
        lock.unlock()
        return text
    }

    public func clear() {
        lock.lock()
        lines.removeAll(keepingCapacity: true)
        status = nil
        lock.unlock()
    }

    @discardableResult
    public func trimForMemoryPressure() -> Int {
        lock.lock()
        let count = lines.count
        lines.removeAll(keepingCapacity: false)
        status = nil
        lock.unlock()
        return count
    }

    public func artifactPaths() -> [String] {
        artifactPaths(in: snapshotText())
    }

    private func artifactPaths(in text: String) -> [String] {
        guard let artifactRegex else {
            return []
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var paths: [String] = []
        var seen = Set<String>()
        for match in artifactRegex.matches(in: text, range: nsRange) {
            guard let range = Range(match.range, in: text) else { continue }
            let path = String(text[range])
            if seen.insert(path).inserted {
                paths.append(path)
            }
        }
        return paths
    }

    public func logger(prefix: String? = nil) -> @Sendable (String) -> Void {
        { [weak self] message in
            guard let self else { return }
            if let prefix, !prefix.isEmpty {
                self.append("\(prefix) \(message)")
            } else {
                self.append(message)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

public enum OpenAIWebDebugLog {
    public static let shared = UsageWebDebugLog.openAI
}

public enum ClaudeWebDebugLog {
    public static let shared = UsageWebDebugLog.claude
}
