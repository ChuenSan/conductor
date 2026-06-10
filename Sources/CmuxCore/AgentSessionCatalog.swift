import Foundation

/// 一条可浏览、可续聊的 agent 会话记录。
public struct AgentSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(agent):\(sessionID)" }
    public let agent: String
    public let sessionID: String
    public let cwd: String?
    public let title: String
    public let modifiedAt: Date
    /// 会话日志文件路径（预览用）。旧缓存没有该字段 → nil，刷新后补齐。
    public let filePath: String?

    public init(
        agent: String, sessionID: String, cwd: String?, title: String, modifiedAt: Date,
        filePath: String? = nil
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.title = title
        self.modifiedAt = modifiedAt
        self.filePath = filePath
    }

    public var resumeCommand: String? {
        AgentSessionRef(agent: agent, sessionID: sessionID).resumeCommand
    }

    public var shortID: String {
        sessionID.count > 10 ? String(sessionID.prefix(8)) + "…" : sessionID
    }

    /// 会话是否属于某工作区目录（cwd 是该路径或其子路径）。
    public func belongsToWorkspace(_ workspacePath: String) -> Bool {
        guard let cwd, !workspacePath.isEmpty else { return false }
        let ws = workspacePath.hasSuffix("/") ? String(workspacePath.dropLast()) : workspacePath
        return cwd == ws || cwd.hasPrefix(ws + "/")
    }

    /// 会话是否属于某 pane 目录（精确匹配或子路径）。
    public func belongsToDirectory(_ directory: String) -> Bool {
        guard let cwd, !directory.isEmpty else { return false }
        let dir = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        return cwd == dir || cwd.hasPrefix(dir + "/")
    }
}

/// 扫描本机 claude / codex 会话日志，列出可续聊记录。
public enum AgentSessionCatalog {
    public static let supportedAgents = ["claude", "codex"]

    /// 扫描全部会话，按修改时间从新到旧排序。
    public static func scan(
        limit: Int = 200,
        claudeProjectsRoot: URL? = nil,
        codexSessionsRoot: URL? = nil
    ) -> [AgentSessionRecord] {
        var records: [AgentSessionRecord] = []
        records.append(contentsOf: scanClaude(limit: limit, projectsRoot: claudeProjectsRoot))
        records.append(contentsOf: scanCodex(limit: limit, sessionsRoot: codexSessionsRoot))
        return records
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// 按工作区路径过滤（cwd 落在工作区内）。
    public static func scanForWorkspace(
        _ workspacePath: String, limit: Int = 50,
        claudeProjectsRoot: URL? = nil, codexSessionsRoot: URL? = nil
    ) -> [AgentSessionRecord] {
        scan(limit: limit * 4, claudeProjectsRoot: claudeProjectsRoot, codexSessionsRoot: codexSessionsRoot)
            .filter { $0.belongsToWorkspace(workspacePath) }
            .prefix(limit)
            .map { $0 }
    }

    /// 按 pane 目录过滤。
    public static func scanForDirectory(
        _ directory: String, limit: Int = 20,
        claudeProjectsRoot: URL? = nil, codexSessionsRoot: URL? = nil
    ) -> [AgentSessionRecord] {
        scan(limit: limit * 4, claudeProjectsRoot: claudeProjectsRoot, codexSessionsRoot: codexSessionsRoot)
            .filter { $0.belongsToDirectory(directory) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Claude

    static func scanClaude(limit: Int, projectsRoot: URL?) -> [AgentSessionRecord] {
        let root = projectsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return [] }

        var records: [AgentSessionRecord] = []
        for projectDir in projects where projectDir.hasDirectoryPath {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])
            else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let sessionID = file.deletingPathExtension().lastPathComponent
                let meta = readClaudeMeta(file)
                let title = meta.title ?? L("Claude 会话")
                guard !isUtilityCommandTitle(title) else { continue }
                let cwd = meta.cwd ?? inferCwdFromSlug(projectDir.lastPathComponent)
                records.append(AgentSessionRecord(
                    agent: "claude", sessionID: sessionID, cwd: cwd, title: title,
                    modifiedAt: modificationDate(file), filePath: file.path))
            }
        }
        return records
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map { $0 }
    }

    /// 读 claude jsonl 前几行：首条用户消息作标题，首条 cwd 作目录。
    static func readClaudeMeta(_ url: URL) -> (title: String?, cwd: String?) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              !data.isEmpty else { return (nil, nil) }
        var title: String?
        var cwd: String?
        var lineStart = 0
        var scanned = 0
        while lineStart < data.count, scanned < 80 {
            let lineEnd = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            let line = data[lineStart..<lineEnd]
            lineStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
            scanned += 1
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if cwd == nil, let path = obj["cwd"] as? String, !path.isEmpty { cwd = path }
            if title == nil {
                if obj["type"] as? String == "queue-operation",
                   obj["operation"] as? String == "enqueue",
                   let content = obj["content"] as? String, !content.isEmpty {
                    title = trimTitle(content)
                } else if obj["type"] as? String == "user",
                          let message = obj["message"] as? [String: Any],
                          let content = message["content"] as? String, !content.isEmpty {
                    title = trimTitle(content)
                }
            }
            if title != nil, cwd != nil { break }
        }
        return (title, cwd)
    }

    /// slug 反推 cwd 的粗猜（读不到 jsonl 内 cwd 时的兜底）。
    static func inferCwdFromSlug(_ slug: String) -> String? {
        guard slug.hasPrefix("-") else { return nil }
        let body = String(slug.dropFirst())
        guard !body.isEmpty else { return nil }
        return "/" + body.replacingOccurrences(of: "-", with: "/")
    }

    // MARK: - Codex

    static func scanCodex(limit: Int, sessionsRoot: URL?) -> [AgentSessionRecord] {
        let root = sessionsRoot
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            files.append(url)
        }
        files.sort { modificationDate($0) > modificationDate($1) }

        var records: [AgentSessionRecord] = []
        for file in files.prefix(limit * 2) {
            guard let meta = readCodexMeta(file) else { continue }
            if let title = meta.title, isUtilityCommandTitle(title) { continue }
            records.append(AgentSessionRecord(
                agent: "codex", sessionID: meta.id, cwd: meta.cwd,
                title: meta.title ?? L("Codex 会话"),
                modifiedAt: modificationDate(file), filePath: file.path))
            if records.count >= limit { break }
        }
        return records
    }

    static func readCodexMeta(_ url: URL) -> (id: String, cwd: String?, title: String?)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let chunk = try? handle.read(upToCount: 524_288), !chunk.isEmpty else { return nil }

        var id: String?
        var cwd: String?
        var title: String?
        var lineStart = 0
        var scanned = 0
        while lineStart < chunk.count, scanned < 120 {
            let lineEnd = chunk[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? chunk.endIndex
            let line = chunk[lineStart..<lineEnd]
            lineStart = lineEnd < chunk.endIndex ? chunk.index(after: lineEnd) : chunk.endIndex
            scanned += 1
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            let type = obj["type"] as? String
            if id == nil, type == "session_meta",
               let payload = obj["payload"] as? [String: Any],
               let sessionID = payload["id"] as? String {
                id = sessionID
                cwd = payload["cwd"] as? String
            }
            if title == nil, type == "event_msg",
               let payload = obj["payload"] as? [String: Any],
               payload["type"] as? String == "user_message",
               let message = payload["message"] as? String, !message.isEmpty {
                title = trimTitle(message)
            }
            if id != nil, title != nil { break }
        }
        guard let id else { return nil }
        return (id, cwd, title)
    }

    // MARK: - Helpers

    /// 纯斜杠命令会话（如 `/usage`、`/status`）：一次性工具调用，没有真实对话，列表里全是噪音。
    /// 带参数/正文的命令（如 `/review 这个 PR`）仍视为真实会话保留。
    public static func isUtilityCommandTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // claude 把斜杠命令存成 XML 包裹形式：args 为空即裸命令
        if t.hasPrefix("<command-name>"), t.contains("<command-args></command-args>") {
            return true
        }
        guard t.hasPrefix("/"), t.count > 1 else { return false }
        return !t.contains(" ")
    }

    static func trimTitle(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return L("会话") }
        if collapsed.count <= 72 { return collapsed }
        return String(collapsed.prefix(69)) + "…"
    }

    static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }
}
