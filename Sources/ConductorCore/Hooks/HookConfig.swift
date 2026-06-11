import Foundation

/// 一条已配置的 hook。
public struct HookEntry: Sendable, Identifiable, Equatable {
    public var id: String { "\(source.rawValue):\(event):\(command.hashValue)" }
    public let source: HookSource
    public let event: String
    public let command: String
    public let timeout: Int?
    /// 是否由 conductor 安装（命令里带 `#conductor:` 哨兵）。
    public var managedByConductor: Bool { command.contains("#conductor:") }

    public init(source: HookSource, event: String, command: String, timeout: Int?) {
        self.source = source
        self.event = event
        self.command = command
        self.timeout = timeout
    }
}

public enum HookSource: String, Sendable, CaseIterable, Codable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// 该 agent 的 hook 配置文件路径。
    public var configURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        }
    }
}

/// 常见 hook 事件名。
public enum HookEventName {
    public static let stop = "Stop"
    public static let sessionStart = "SessionStart"
    public static let userPromptSubmit = "UserPromptSubmit"
    public static let subagentStop = "SubagentStop"
}

/// 对 `hooks.<Event>[].hooks[]{type,command,timeout}` 这种 schema 的读写器。
/// Claude 的 settings.json 还含其它键（env / model 等），本类型只动 `hooks` 子树，
/// 其余键原样保留（含敏感信息），不读不改不打印。
public struct HookConfigDocument: Sendable {
    public let url: URL
    public let source: HookSource

    public init(url: URL, source: HookSource) {
        self.url = url
        self.source = source
    }

    public init(source: HookSource) {
        self.url = source.configURL
        self.source = source
    }

    public func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    /// 读出所有 hook 条目。
    public func entries() -> [HookEntry] {
        let root = load()
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var out: [HookEntry] = []
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                let inner = group["hooks"] as? [[String: Any]] ?? []
                for h in inner {
                    guard let command = h["command"] as? String else { continue }
                    let timeout = (h["timeout"] as? Int) ?? (h["timeout"] as? NSNumber)?.intValue
                    out.append(HookEntry(source: source, event: event, command: command, timeout: timeout))
                }
            }
        }
        return out.sorted { ($0.event, $0.command) < ($1.event, $1.command) }
    }

    /// 往某事件加一条 command hook（已存在完全相同命令则跳过）。写回，保留其它键。
    public func addCommand(event: String, command: String, timeout: Int = 5000) throws {
        var root = load()
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var groups = hooks[event] as? [[String: Any]] ?? []

        let exists = groups.contains { group in
            let inner = group["hooks"] as? [[String: Any]] ?? []
            return inner.contains { ($0["command"] as? String) == command }
        }
        if !exists {
            groups.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
            hooks[event] = groups
            root["hooks"] = hooks
            try write(root)
        }
    }

    /// 移除满足条件（命令包含某子串）的 hook。空了的事件/分组一并清掉。
    @discardableResult
    public func removeCommands(containing needle: String) throws -> Int {
        var root = load()
        guard var hooks = root["hooks"] as? [String: Any] else { return 0 }
        var removed = 0
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group -> [String: Any]? in
                var inner = group["hooks"] as? [[String: Any]] ?? []
                let before = inner.count
                inner = inner.filter { !(($0["command"] as? String)?.contains(needle) ?? false) }
                removed += before - inner.count
                if inner.isEmpty { return nil }
                var g = group
                g["hooks"] = inner
                return g
            }
            if groups.isEmpty { hooks.removeValue(forKey: event) }
            else { hooks[event] = groups }
        }
        if removed > 0 {
            root["hooks"] = hooks
            try write(root)
        }
        return removed
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url)
    }
}
