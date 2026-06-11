import Foundation

/// 某个 pane 里 agent 的可恢复会话引用：恢复 pane 时把 resume 命令预输入到提示符。
public struct AgentSessionRef: Codable, Equatable, Sendable {
    /// agent id（"claude" / "codex"）。
    public var agent: String
    public var sessionID: String

    public init(agent: String, sessionID: String) {
        self.agent = agent
        self.sessionID = sessionID
    }

    /// 续聊命令。未知 agent 返回 nil。
    public var resumeCommand: String? {
        switch agent {
        case "claude": return "claude --resume \(sessionID)"
        case "codex": return "codex resume \(sessionID)"
        default: return nil
        }
    }
}

/// 按 cwd 定位 claude / codex 最近一次会话的 ID（纯启发式）：
/// - Claude Code：`~/.claude/projects/<slug>/<uuid>.jsonl`，slug 是 cwd 非字母数字字符全替换成 '-'；
///   取该目录里最近修改的 jsonl，文件名即会话 ID。
/// - Codex：`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`，首行 session_meta 带 id + cwd；
///   按修改时间从新到旧读首行，取第一个 cwd 匹配的。
/// 同目录同时跑多个同款 agent 时可能取到相邻会话，属可接受的误差。
public enum AgentSessionLocator {
    /// 综合入口：根据 agent id + cwd 找会话。不支持的 agent 返回 nil。
    public static func locate(
        agent: String, cwd: String,
        claudeProjectsRoot: URL? = nil, codexSessionsRoot: URL? = nil
    ) -> AgentSessionRef? {
        let id: String?
        switch agent {
        case "claude": id = claudeSessionID(cwd: cwd, projectsRoot: claudeProjectsRoot)
        case "codex": id = codexSessionID(cwd: cwd, sessionsRoot: codexSessionsRoot)
        default: id = nil
        }
        return id.map { AgentSessionRef(agent: agent, sessionID: $0) }
    }

    /// Claude 把 cwd 映射成项目目录名：非字母数字（含开头的 '/'）全部替换为 '-'。
    public static func claudeProjectSlug(_ cwd: String) -> String {
        String(cwd.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    public static func claudeSessionID(cwd: String, projectsRoot: URL? = nil) -> String? {
        let root = projectsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        let dir = root.appendingPathComponent(claudeProjectSlug(cwd), isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return nil }
        let newest = files
            .filter { $0.pathExtension == "jsonl" }
            .max { modificationDate($0) < modificationDate($1) }
        return newest.map { $0.deletingPathExtension().lastPathComponent }
    }

    public static func codexSessionID(
        cwd: String, sessionsRoot: URL? = nil, maxFiles: Int = 40
    ) -> String? {
        let root = sessionsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }
        var candidates: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            candidates.append(url)
        }
        candidates.sort { modificationDate($0) > modificationDate($1) }
        for url in candidates.prefix(maxFiles) {
            guard let meta = readSessionMeta(url) else { continue }
            if meta.cwd == cwd { return meta.id }
        }
        return nil
    }

    /// 读 rollout 文件首行的 session_meta。首行带完整 base_instructions，可能很长，
    /// 读前 512KB 截到首个换行，避免整文件载入。
    private static func readSessionMeta(_ url: URL) -> (id: String, cwd: String)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 524_288), !data.isEmpty else { return nil }
        let firstLine = data.prefix(while: { $0 != UInt8(ascii: "\n") })
        guard let obj = try? JSONSerialization.jsonObject(with: firstLine) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let payload = obj["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String
        else { return nil }
        return (id, cwd)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
