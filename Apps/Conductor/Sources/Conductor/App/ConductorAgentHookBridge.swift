import Foundation

enum AgentHookProvider: String, CaseIterable, Codable, Identifiable {
    case codex
    case claudeCode

    var id: String { rawValue }

    init?(cliName: String) {
        switch cliName.lowercased() {
        case "codex":
            self = .codex
        case "claude", "claude-code", "cc":
            self = .claudeCode
        default:
            return nil
        }
    }

    var cliName: String {
        switch self {
        case .codex:
            "codex"
        case .claudeCode:
            "claude"
        }
    }

    var title: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude Code / cc"
        }
    }

    var systemImage: String {
        switch self {
        case .codex:
            "terminal.fill"
        case .claudeCode:
            "text.bubble"
        }
    }

    var executableCandidates: [String] {
        switch self {
        case .codex:
            ["codex"]
        case .claudeCode:
            ["claude", "claude-code"]
        }
    }

    var installURL: URL? {
        switch self {
        case .codex:
            URL(string: "https://github.com/openai/codex")
        case .claudeCode:
            URL(string: "https://code.claude.com/docs/en/installation")
        }
    }

    var installHint: String {
        switch self {
        case .codex:
            ConductorLocalization.text(zh: "安装 OpenAI Codex CLI 后重新检测", en: "Install OpenAI Codex CLI, then scan again")
        case .claudeCode:
            ConductorLocalization.text(zh: "安装 Claude Code 后重新检测", en: "Install Claude Code, then scan again")
        }
    }
}

enum ConductorAgentHookBridge {
    static let eventName = Notification.Name("com.conductor.agent-hook")

    enum Key {
        static let terminalID = "terminalID"
        static let agent = "agent"
        static let action = "action"
        static let title = "title"
        static let body = "body"
        static let cwd = "cwd"
        static let sessionID = "sessionID"
        static let turnID = "turnID"
    }

    static func writePendingEvent(_ userInfo: [String: String]) {
        let fileManager = FileManager.default
        let directoryURL = pendingEventDirectory(fileManager: fileManager)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: userInfo, options: [.sortedKeys]) else {
            return
        }
        let fileURL = directoryURL.appendingPathComponent("\(UUID().uuidString).json")
        try? data.write(to: fileURL, options: [.atomic])
    }

    static func drainPendingEvents() -> [[String: String]] {
        let fileManager = FileManager.default
        let directoryURL = pendingEventDirectory(fileManager: fileManager)
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return fileURLs
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                modificationDate(for: lhs) < modificationDate(for: rhs)
            }
            .compactMap { fileURL in
                defer { try? fileManager.removeItem(at: fileURL) }
                guard let data = try? Data(contentsOf: fileURL),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
                    return nil
                }
                return object
            }
    }

    private static func pendingEventDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent("AgentHookEvents", isDirectory: true)
    }

    private static func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

enum ConductorHookCLI {
    static func runIfNeeded(arguments: [String]) -> Bool {
        let args = Array(arguments.dropFirst())
        guard args.count >= 3, args[0] == "hooks" else { return false }

        let agent = args[1].lowercased()
        let action = args[2].lowercased()
        guard let provider = AgentHookProvider(cliName: agent) else {
            return true
        }

        let payload = readHookPayload()
        postAgentEvent(provider: provider, action: action, payload: payload)
        if provider == .codex {
            print("{}")
        }
        return true
    }

    private static func readHookPayload() -> [String: Any] {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func postAgentEvent(provider: AgentHookProvider, action: String, payload: [String: Any]) {
        guard let terminalID = ProcessInfo.processInfo.environment["CONDUCTOR_TERMINAL_ID"],
              !terminalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var userInfo: [String: String] = [
            ConductorAgentHookBridge.Key.terminalID: terminalID,
            ConductorAgentHookBridge.Key.agent: provider.cliName,
            ConductorAgentHookBridge.Key.action: action
        ]

        if let cwd = firstString(in: payload, keys: ["cwd", "workspace", "working_directory", "workingDirectory"]) {
            userInfo[ConductorAgentHookBridge.Key.cwd] = cwd
        }
        if let sessionID = firstString(in: payload, keys: ["session_id", "sessionId"]) {
            userInfo[ConductorAgentHookBridge.Key.sessionID] = sessionID
        }
        if let turnID = firstString(in: payload, keys: ["turn_id", "turnId"]) {
            userInfo[ConductorAgentHookBridge.Key.turnID] = turnID
        }

        if action == "stop" || action == "agent-response" || action == "subagent-stop" {
            let cwd = userInfo[ConductorAgentHookBridge.Key.cwd]
            userInfo[ConductorAgentHookBridge.Key.title] = provider.title
            userInfo[ConductorAgentHookBridge.Key.body] = completionBody(payload: payload, cwd: cwd)
        }

        ConductorAgentHookBridge.writePendingEvent(userInfo)
        DistributedNotificationCenter.default().postNotificationName(
            ConductorAgentHookBridge.eventName,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private static func completionBody(payload: [String: Any], cwd: String?) -> String {
        if let message = firstString(in: payload, keys: ["last_assistant_message", "lastAssistantMessage", "message", "summary"]) {
            let normalized = normalizedSingleLine(message)
            if !normalized.isEmpty {
                return String(normalized.prefix(220))
            }
        }

        if let cwd, !cwd.isEmpty {
            let project = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath).lastPathComponent
            if !project.isEmpty {
                return "\(project) 的终端任务已完成，等待下一步。"
            }
        }
        return "终端任务已完成，等待下一步。"
    }

    private static func firstString(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func normalizedSingleLine(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
