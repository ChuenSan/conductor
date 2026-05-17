import Foundation

enum ConductorAgentHookBridge {
    static let notificationName = Notification.Name("com.conductor.agent-hook")

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
}

enum ConductorHookCLI {
    static func runIfNeeded(arguments: [String]) -> Bool {
        let args = Array(arguments.dropFirst())
        guard args.count >= 3, args[0] == "hooks" else { return false }

        let agent = args[1].lowercased()
        let action = args[2].lowercased()
        guard agent == "codex" else {
            print("{}")
            return true
        }

        if action == "install" {
            do {
                let bridgePath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "Conductor"
                print(try CodexNotificationHookInstaller.install(bridgePath: bridgePath))
            } catch {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                Foundation.exit(1)
            }
            return true
        }

        let payload = readHookPayload()
        postCodexEvent(action: action, payload: payload)
        print("{}")
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

    private static func postCodexEvent(action: String, payload: [String: Any]) {
        guard let terminalID = ProcessInfo.processInfo.environment["CONDUCTOR_TERMINAL_ID"],
              !terminalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        var userInfo: [String: String] = [
            ConductorAgentHookBridge.Key.terminalID: terminalID,
            ConductorAgentHookBridge.Key.agent: "codex",
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

        if action == "stop" || action == "agent-response" {
            let cwd = userInfo[ConductorAgentHookBridge.Key.cwd]
            userInfo[ConductorAgentHookBridge.Key.title] = "Codex 完成"
            userInfo[ConductorAgentHookBridge.Key.body] = codexCompletionBody(payload: payload, cwd: cwd)
        }

        DistributedNotificationCenter.default().postNotificationName(
            ConductorAgentHookBridge.notificationName,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    private static func codexCompletionBody(payload: [String: Any], cwd: String?) -> String {
        if let message = firstString(in: payload, keys: ["last_assistant_message", "lastAssistantMessage", "message", "summary"]) {
            let normalized = normalizedSingleLine(message)
            if !normalized.isEmpty {
                return String(normalized.prefix(220))
            }
        }

        if let cwd, !cwd.isEmpty {
            let project = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath).lastPathComponent
            if !project.isEmpty {
                return "\(project) 的 Codex 对话已完成，等待下一步。"
            }
        }
        return "Codex 对话已完成，等待下一步。"
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
