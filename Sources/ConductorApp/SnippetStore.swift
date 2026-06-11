import Foundation

/// 一条命令片段：一键发到当前终端，免去反复敲长命令。
struct Snippet: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var command: String
    /// true = 发出后直接回车执行；false = 只摆在提示符上（可改完再回车）。
    var autoRun: Bool = false
}

/// 片段库：JSON 持久化在 Application Support/conductor/snippets.json。
@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published private(set) var snippets: [Snippet] = []

    private static var fileURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
            .appendingPathComponent("snippets.json")
    }

    private init() {
        load()
    }

    func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let i = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[i] = snippet
        save()
    }

    func remove(_ id: String) {
        snippets.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        snippets.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else {
            snippets = Self.starterPack
            return
        }
        snippets = decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snippets)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("[conductor] 写 snippets.json 失败：\(error)")
        }
    }

    /// 首次使用的示例片段（用户可改可删），展示「直接执行」与「摆在提示符」两种用法。
    private static var starterPack: [Snippet] {
        [
            Snippet(name: L("Git 状态"), command: "git status", autoRun: true),
            Snippet(name: L("Git 最近提交"), command: "git log --oneline -10", autoRun: true),
            Snippet(name: L("提交全部改动"), command: "git add -A && git commit -m \"\"", autoRun: false),
        ]
    }
}
