import Foundation

/// 一个被发现的 Skill（来自某个 `SKILL.md`）。
public struct SkillEntry: Sendable, Identifiable, Equatable {
    /// 用 SKILL.md 的绝对路径做稳定 id。
    public var id: String { markdownPath }
    public let name: String
    public let description: String
    public let version: String?
    public let author: String?
    public let source: SkillSource
    /// SKILL.md（或被禁用时的 SKILL.md.disabled）的绝对路径。
    public let markdownPath: String
    /// skill 所在目录。
    public let directory: String
    public let enabled: Bool

    public init(name: String, description: String, version: String?, author: String?,
                source: SkillSource, markdownPath: String, directory: String, enabled: Bool) {
        self.name = name
        self.description = description
        self.version = version
        self.author = author
        self.source = source
        self.markdownPath = markdownPath
        self.directory = directory
        self.enabled = enabled
    }
}

public enum SkillSource: String, Sendable, CaseIterable, Codable {
    case claude
    case codex
    case cursor
    case other

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .other: return L("其他")
        }
    }
}

/// 扫描本机各 agent 的 skills 目录，解析 `SKILL.md` 的 YAML frontmatter。
/// 禁用机制：把 `SKILL.md` 重命名为 `SKILL.md.disabled`（可逆，conductor 自己掌控，不依赖各家约定）。
public struct SkillCatalog: Sendable {
    public struct Root: Sendable {
        public let url: URL
        public let source: SkillSource
        public init(url: URL, source: SkillSource) {
            self.url = url
            self.source = source
        }
    }

    private let roots: [Root]

    public init(roots: [Root]? = nil) {
        if let roots {
            self.roots = roots
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.roots = [
            Root(url: home.appendingPathComponent(".claude/skills"), source: .claude),
            Root(url: home.appendingPathComponent(".claude/plugins"), source: .claude),
            Root(url: home.appendingPathComponent(".codex/skills"), source: .codex),
            Root(url: home.appendingPathComponent(".cursor/skills-cursor"), source: .cursor),
            Root(url: home.appendingPathComponent(".cursor/plugins"), source: .cursor),
        ]
    }

    public func scan() -> [SkillEntry] {
        var entries: [SkillEntry] = []
        var seenDirs = Set<String>()
        var seenNames = Set<String>()   // 同名 skill（不同插件缓存副本）只显示一份
        for root in roots {
            for url in skillFiles(in: root.url) {
                let dir = url.deletingLastPathComponent().path
                if seenDirs.contains(dir) { continue }
                seenDirs.insert(dir)
                guard let entry = parse(url: url, source: root.source) else { continue }
                let nameKey = "\(entry.source.rawValue)|\(entry.name.lowercased())"
                if seenNames.contains(nameKey) { continue }
                seenNames.insert(nameKey)
                entries.append(entry)
            }
        }
        return entries.sorted {
            if $0.source != $1.source { return $0.source.rawValue < $1.source.rawValue }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    /// 启用 / 禁用：在 SKILL.md <-> SKILL.md.disabled 之间重命名。返回新路径。
    @discardableResult
    public static func setEnabled(_ entry: SkillEntry, _ enabled: Bool) throws -> String {
        let fm = FileManager.default
        let current = URL(fileURLWithPath: entry.markdownPath)
        let dir = current.deletingLastPathComponent()
        let target = enabled
            ? dir.appendingPathComponent("SKILL.md")
            : dir.appendingPathComponent("SKILL.md.disabled")
        if current.path == target.path { return target.path }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: current, to: target)
        return target.path
    }

    // MARK: - 内部

    private func skillFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let en = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in en {
            let name = url.lastPathComponent
            if name == "SKILL.md" || name == "SKILL.md.disabled" { out.append(url) }
        }
        return out
    }

    private func parse(url: URL, source: SkillSource) -> SkillEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fm = parseFrontmatter(text)
        let dir = url.deletingLastPathComponent()
        let fallbackName = dir.lastPathComponent
        let name = fm["name"] ?? fallbackName
        let description = fm["description"] ?? ""
        let enabled = url.lastPathComponent == "SKILL.md"
        return SkillEntry(
            name: name,
            description: description,
            version: fm["version"],
            author: fm["author"],
            source: source,
            markdownPath: url.path,
            directory: dir.path,
            enabled: enabled)
    }

    /// 极简 frontmatter 解析：取首个 `---` 与下一个 `---` 之间，逐行 `key: value`，
    /// 同时把 `metadata:` 下缩进的 `version` / `author` 抽到平铺 map。够用且不引第三方 YAML。
    func parseFrontmatter(_ text: String) -> [String: String] {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        lines.removeFirst()
        var result: [String: String] = [:]
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            guard let colon = raw.firstIndex(of: ":") else { continue }
            let key = String(raw[raw.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            var value = String(raw[raw.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if value.hasPrefix("'") && value.hasSuffix("'") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            // 缩进的 version/author（metadata 下）也直接吃进来，平铺存储。
            if key == "name" || key == "description" || key == "version" || key == "author" {
                if result[key] == nil, !value.isEmpty { result[key] = value }
            }
        }
        return result
    }
}
