import CryptoKit
import Foundation

enum AgentNotificationHookInstaller {
    private static let trustBegin = "# BEGIN CONDUCTOR CODEX HOOK TRUST"
    private static let trustEnd = "# END CONDUCTOR CODEX HOOK TRUST"

    static func install(provider: AgentHookProvider, bridgePath: String) throws -> String {
        switch provider {
        case .codex:
            return try installCodex(bridgePath: bridgePath)
        case .claudeCode:
            return try installClaudeCode(bridgePath: bridgePath)
        }
    }

    private static func installCodex(bridgePath: String) throws -> String {
        let fileManager = FileManager.default
        let codexHome = resolvedCodexHome()
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)

        let hooksURL = codexHome.appendingPathComponent("hooks.json")
        var root = try readJSONObject(at: hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let events = [
            ("SessionStart", "session-start"),
            ("UserPromptSubmit", "prompt-submit"),
            ("Stop", "stop")
        ]
        for (eventName, action) in events {
            let command = hookCommand(provider: .codex, bridgePath: bridgePath, action: action)
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                removingOwnedHooks(from: group, provider: .codex)
            }
            groups.append([
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                        "timeout": 5_000
                    ] as [String: Any]
                ]
            ] as [String: Any])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        let hooksData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try hooksData.write(to: hooksURL, options: .atomic)

        let configURL = codexHome.appendingPathComponent("config.toml")
        let existingConfig = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let enabledConfig = enablingCodexHooks(in: existingConfig)
        let trustedConfig = installingTrustEntries(
            in: enabledConfig,
            hooks: hooks,
            hooksURL: hooksURL
        )
        try trustedConfig.write(to: configURL, atomically: true, encoding: .utf8)

        return "已写入 \(hooksURL.path)，Codex Stop 后会发送 Conductor 通知。"
    }

    private static func installClaudeCode(bridgePath: String) throws -> String {
        let fileManager = FileManager.default
        let claudeHome = resolvedClaudeHome()
        try fileManager.createDirectory(at: claudeHome, withIntermediateDirectories: true)

        let settingsURL = claudeHome.appendingPathComponent("settings.json")
        var root = try readJSONObject(at: settingsURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let events = [
            ("UserPromptSubmit", "prompt-submit"),
            ("Stop", "stop"),
            ("SubagentStop", "subagent-stop"),
            ("Notification", "notification")
        ]

        for (eventName, action) in events {
            let command = hookCommand(provider: .claudeCode, bridgePath: bridgePath, action: action)
            var groups = hooks[eventName] as? [[String: Any]] ?? []
            groups = groups.compactMap { group in
                removingOwnedHooks(from: group, provider: .claudeCode)
            }
            groups.append([
                "hooks": [
                    [
                        "type": "command",
                        "command": command,
                        "timeout": 5
                    ] as [String: Any]
                ]
            ] as [String: Any])
            hooks[eventName] = groups
        }

        root["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
        return "已写入 \(settingsURL.path)，Claude Code/cc 会发送 Conductor 通知。"
    }

    private static func resolvedCodexHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private static func resolvedClaudeHome() -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }

    private static func readJSONObject(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "Conductor.AgentHooks",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(url.path) 不是有效 JSON，未自动修改。"]
            )
        }
        return object
    }

    private static func removingOwnedHooks(from group: [String: Any], provider: AgentHookProvider) -> [String: Any]? {
        guard var hookList = group["hooks"] as? [[String: Any]] else { return group }
        hookList.removeAll { hook in
            guard let command = hook["command"] as? String else { return false }
            return isOwnedCommand(command, provider: provider)
        }
        guard !hookList.isEmpty else { return nil }
        var next = group
        next["hooks"] = hookList
        return next
    }

    private static func isOwnedCommand(_ command: String, provider: AgentHookProvider) -> Bool {
        let normalized = command
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = normalized.lowercased()
        let hasConductorMarker = lowercased.contains("conductor") || normalized.contains("CONDUCTOR_")
        guard hasConductorMarker else { return false }

        switch provider {
        case .codex:
            return containsHookInvocation(providerToken: "codex", in: lowercased)
        case .claudeCode:
            return containsHookInvocation(providerToken: "claude", in: lowercased)
                || containsHookInvocation(providerToken: "cc", in: lowercased)
        }
    }

    private static func containsHookInvocation(providerToken: String, in command: String) -> Bool {
        command.range(
            of: "(^|[;&|()[:space:]])hooks[[:space:]]+\(providerToken)($|[[:space:]])",
            options: .regularExpression
        ) != nil
    }

    private static func hookCommand(provider: AgentHookProvider, bridgePath: String, action: String) -> String {
        let bridge = shellQuoted(bridgePath)
        switch provider {
        case .codex:
            return "[ -n \"$CONDUCTOR_TERMINAL_ID\" ] && [ \"$CONDUCTOR_AGENT_HOOKS_DISABLED\" != \"1\" ] && [ \"$CONDUCTOR_CODEX_HOOKS_DISABLED\" != \"1\" ] && \(bridge) hooks codex \(action) || echo '{}'"
        case .claudeCode:
            return "[ -n \"$CONDUCTOR_TERMINAL_ID\" ] && [ \"$CONDUCTOR_AGENT_HOOKS_DISABLED\" != \"1\" ] && [ \"$CONDUCTOR_CLAUDE_HOOKS_DISABLED\" != \"1\" ] && \(bridge) hooks claude \(action) >/dev/null 2>&1 || true"
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func enablingCodexHooks(in content: String) -> String {
        var lines = content.components(separatedBy: "\n")
        if lines.last == "" {
            lines.removeLast()
        }

        var featuresStart: Int?
        var featuresEnd = lines.count
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[features]" {
                featuresStart = index
                featuresEnd = lines[(index + 1)...].firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
                break
            }
        }

        if let featuresStart {
            if let hooksIndex = lines[(featuresStart + 1)..<featuresEnd].firstIndex(where: { lineDefinesKey("hooks", line: $0) }) {
                lines[hooksIndex] = "hooks = true"
            } else {
                lines.insert("hooks = true", at: featuresStart + 1)
            }
        } else if let dottedIndex = lines.firstIndex(where: { lineDefinesKey("features.hooks", line: $0) }) {
            lines[dottedIndex] = "features.hooks = true"
        } else {
            if !lines.isEmpty { lines.append("") }
            lines.append("[features]")
            lines.append("hooks = true")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func lineDefinesKey(_ key: String, line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#") else { return false }
        return trimmed.hasPrefix("\(key) ") || trimmed.hasPrefix("\(key)=")
    }

    private static func installingTrustEntries(
        in content: String,
        hooks: [String: Any],
        hooksURL: URL
    ) -> String {
        let entries = codexHookTrustEntries(hooks: hooks, hooksURL: hooksURL)
        var lines = content.components(separatedBy: "\n")
        removeTrustBlock(from: &lines)
        removeTrustEntries(from: &lines, keys: Set(entries.map(\.key)))
        if lines.last == "" {
            lines.removeLast()
        }

        guard !entries.isEmpty else {
            return lines.joined(separator: "\n") + "\n"
        }

        if !lines.isEmpty { lines.append("") }
        lines.append(trustBegin)
        for entry in entries {
            lines.append("[hooks.state.\"\(tomlEscaped(entry.key))\"]")
            lines.append("trusted_hash = \"\(tomlEscaped(entry.hash))\"")
        }
        lines.append(trustEnd)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func removeTrustBlock(from lines: inout [String]) {
        while let start = lines.firstIndex(of: trustBegin) {
            guard let end = lines[start...].firstIndex(of: trustEnd) else {
                lines.removeSubrange(start..<lines.endIndex)
                return
            }
            lines.removeSubrange(start...end)
        }
    }

    private static func removeTrustEntries(from lines: inout [String], keys: Set<String>) {
        guard !keys.isEmpty else { return }
        let headers = Set(keys.map { "[hooks.state.\"\(tomlEscaped($0))\"]" })
        var index = lines.startIndex
        while index < lines.endIndex {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard headers.contains(trimmed) else {
                index = lines.index(after: index)
                continue
            }

            var end = lines.index(after: index)
            while end < lines.endIndex {
                let candidate = lines[end].trimmingCharacters(in: .whitespaces)
                if candidate.hasPrefix("[") && candidate.hasSuffix("]") {
                    break
                }
                end = lines.index(after: end)
            }
            lines.removeSubrange(index..<end)
        }
    }

    private static func codexHookTrustEntries(hooks: [String: Any], hooksURL: URL) -> [(key: String, hash: String)] {
        let events = [
            ("SessionStart", "session_start"),
            ("UserPromptSubmit", "user_prompt_submit"),
            ("Stop", "stop")
        ]
        let source = hooksURL.standardizedFileURL.path
        var entries: [(String, String)] = []
        for (eventName, eventLabel) in events {
            guard let groups = hooks[eventName] as? [[String: Any]] else { continue }
            for (groupIndex, group) in groups.enumerated() {
                guard let hookList = group["hooks"] as? [[String: Any]] else { continue }
                for (handlerIndex, hook) in hookList.enumerated() {
                    guard let command = hook["command"] as? String, isOwnedCommand(command, provider: .codex) else { continue }
                    let timeout = hook["timeout"] as? Int ?? 5_000
                    let key = "\(source):\(eventLabel):\(groupIndex):\(handlerIndex)"
                    let hash = codexCommandHookHash(eventLabel: eventLabel, command: command, timeout: timeout)
                    entries.append((key, hash))
                }
            }
        }
        return entries
    }

    private static func codexCommandHookHash(eventLabel: String, command: String, timeout: Int) -> String {
        let handler: [String: Any] = [
            "async": false,
            "command": command,
            "timeout": max(timeout, 1),
            "type": "command"
        ]
        let identity: [String: Any] = [
            "event_name": eventLabel,
            "hooks": [handler]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return "sha256:\(digest)"
    }

    private static func tomlEscaped(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                escaped += "\\\""
            case 0x5C:
                escaped += "\\\\"
            case 0x0A:
                escaped += "\\n"
            case 0x0D:
                escaped += "\\r"
            case 0x09:
                escaped += "\\t"
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}
