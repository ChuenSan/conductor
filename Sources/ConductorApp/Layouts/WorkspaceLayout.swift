import Combine
import ConductorCore
import Foundation

// MARK: - 工作区布局（"现场存档"）
//
// 一个布局 = 某工作区现场的命名快照：分屏/标签结构（复用 Codable 的 Tab/SplitNode）+ 每个 pane 的
// cwd、启动命令、可恢复的 agent 会话。复原时重建结构 → 逐 pane cd → 续聊 session 或跑启动命令。
// 形状刻意贴近现有 PersistedState(store/paneCwds/paneSessions)，复原直接复用 restoreTab/stageSessionRestore。

/// 布局里单个 pane 的"意图"。key 用 pane.value（与 capturedCwds/capturedSessions 一致）。
struct LayoutPaneSpec: Codable, Equatable {
    /// 复原时 cd 到的目录。
    var cwd: String?
    /// 复原时自动跑的命令（用户可自定义；非 agent 的普通终端用它"开局"）。
    var startupCommand: String?
    /// 可恢复的 agent 会话（含 session id / launchCommand / lifecycle）；有则优先续聊。
    var session: AgentSessionRef?

    var isEmpty: Bool {
        (cwd?.isEmpty ?? true)
            && (startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && session == nil
    }
}

struct WorkspaceLayout: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// 结构：直接存 Codable 的 Tab（含 rootSplit/ratio/customTitle/activePane）。
    var tabs: [Tab]
    var activeTab: TabID?
    /// 每个 pane（pane.value）的意图。
    var panes: [String: LayoutPaneSpec]
    /// 源工作区路径（做模板时清空 → 布局脱离具体目录）。
    var sourcePath: String?

    var paneCount: Int { tabs.reduce(0) { $0 + $1.rootSplit.leaves().count } }
    /// 模板 = 不绑定具体路径，可用于在任意目录起新工作区。
    var isTemplate: Bool { sourcePath == nil }

    static func fresh(name: String, tabs: [Tab], activeTab: TabID?,
                      panes: [String: LayoutPaneSpec], sourcePath: String?) -> WorkspaceLayout {
        WorkspaceLayout(
            id: "layout-\(UUID().uuidString)",
            name: name,
            createdAt: Date(), updatedAt: Date(),
            tabs: tabs, activeTab: activeTab,
            panes: panes, sourcePath: sourcePath)
    }
}

@MainActor
final class LayoutStore: ObservableObject {
    @Published private(set) var layouts: [WorkspaceLayout] = []

    private let fileURL: URL

    init(fileURL: URL = LayoutStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// 最近更新的排前。
    var sorted: [WorkspaceLayout] {
        layouts.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func upsert(_ layout: WorkspaceLayout) -> WorkspaceLayout {
        var normalized = layout
        normalized.name = normalized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.name.isEmpty { normalized.name = L("未命名布局") }
        normalized.updatedAt = Date()
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = normalized
        } else {
            layouts.insert(normalized, at: 0)
        }
        persist()
        return normalized
    }

    func rename(_ id: String, to name: String) {
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        layouts[index].name = trimmed.isEmpty ? layouts[index].name : trimmed
        layouts[index].updatedAt = Date()
        persist()
    }

    func setStartupCommand(layoutID: String, pane: String, command: String?) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        var spec = layouts[index].panes[pane] ?? LayoutPaneSpec()
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        spec.startupCommand = (trimmed?.isEmpty ?? true) ? nil : trimmed
        layouts[index].panes[pane] = spec
        layouts[index].updatedAt = Date()
        persist()
    }

    func delete(_ id: String) {
        layouts.removeAll { $0.id == id }
        persist()
    }

    func layout(_ id: String) -> WorkspaceLayout? {
        layouts.first { $0.id == id }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([WorkspaceLayout].self, from: data)
        else {
            layouts = []
            return
        }
        layouts = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try Self.encoder.encode(layouts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[conductor] failed to save layouts: \(error)")
        }
    }

    nonisolated private static var defaultFileURL: URL {
        ConductorPaths.appSupportDirectory()
            .appendingPathComponent("layouts.json")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
