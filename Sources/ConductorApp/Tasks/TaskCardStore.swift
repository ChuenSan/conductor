import Combine
import ConductorCore
import Foundation

enum TaskCardExecutor: Codable, Equatable, Sendable {
    case shell
    case agent(String)

    var selectionID: String {
        switch self {
        case .shell:
            return "shell"
        case let .agent(id):
            return "agent:\(id)"
        }
    }

    var agentID: String? {
        guard case let .agent(id) = self else { return nil }
        return id
    }

    init(selectionID: String) {
        if selectionID.hasPrefix("agent:") {
            let id = String(selectionID.dropFirst("agent:".count))
            self = id.isEmpty ? .shell : .agent(id)
        } else {
            self = .shell
        }
    }
}

struct TaskCard: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var title: String
    var prompt: String
    var workspaceID: String?
    var executor: TaskCardExecutor
    var createdAt: Date
    var updatedAt: Date
    var lastRunAt: Date?
    var runCount: Int
    var pinned: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, title, prompt, workspaceID, executor, createdAt, updatedAt, lastRunAt, runCount, pinned
    }

    /// 宽容解码：老的 task-cards.json 没有 pinned（以后新增字段同理），缺了就给默认，
    /// 绝不能因为多一个字段就整盘解码失败把用户卡片清空。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        prompt = try c.decode(String.self, forKey: .prompt)
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        executor = try c.decode(TaskCardExecutor.self, forKey: .executor)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastRunAt = try c.decodeIfPresent(Date.self, forKey: .lastRunAt)
        runCount = (try? c.decode(Int.self, forKey: .runCount)) ?? 0
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
    }

    init(id: String, title: String, prompt: String, workspaceID: String?,
         executor: TaskCardExecutor, createdAt: Date, updatedAt: Date,
         lastRunAt: Date?, runCount: Int, pinned: Bool = false) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.workspaceID = workspaceID
        self.executor = executor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastRunAt = lastRunAt
        self.runCount = runCount
        self.pinned = pinned
    }

    /// prompt 里的 {{变量}}（去重、保序）。
    var variableNames: [String] { TaskCardTemplate.variables(in: prompt) }

    var displayTitle: String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty { return cleanTitle }
        let firstLine = prompt
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return firstLine?.isEmpty == false ? firstLine! : L("新任务")
    }

    static func fresh(workspaceID: String?) -> TaskCard {
        TaskCard(
            id: "task-\(UUID().uuidString)",
            title: "",
            prompt: "",
            workspaceID: workspaceID,
            executor: .shell,
            createdAt: Date(),
            updatedAt: Date(),
            lastRunAt: nil,
            runCount: 0)
    }
}

/// {{变量}} 模板工具：从 prompt 抽变量名、用填好的值替换。
enum TaskCardTemplate {
    private static let pattern = try! NSRegularExpression(pattern: "\\{\\{\\s*([^{}]+?)\\s*\\}\\}")

    static func variables(in text: String) -> [String] {
        let ns = text as NSString
        var seen = Set<String>()
        var ordered: [String] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            ordered.append(name)
        }
        return ordered
    }

    static func substitute(_ text: String, values: [String: String]) -> String {
        var out = text
        for (name, value) in values {
            // 替换 {{ name }}（容忍内部空格）。
            let escaped = NSRegularExpression.escapedPattern(for: name)
            if let re = try? NSRegularExpression(pattern: "\\{\\{\\s*\(escaped)\\s*\\}\\}") {
                let ns = out as NSString
                out = re.stringByReplacingMatches(
                    in: out, range: NSRange(location: 0, length: ns.length),
                    withTemplate: NSRegularExpression.escapedTemplate(for: value))
            }
        }
        return out
    }
}

/// 把任务牌甩到某个终端 pane 上、且该任务含 {{变量}} 时，用这个信号让（仍开着的）任务面板弹出填值，
/// 填完在该 pane 跑。cross 组件（pane 落点在主窗、填值 UI 在浮动面板）靠它搭桥。
struct TaskDropFillRequest: Equatable {
    let cardID: String
    let paneID: String
    let nonce: Int
}

@MainActor
final class TaskCardStore: ObservableObject {
    @Published private(set) var cards: [TaskCard] = []
    /// 落点为某 pane 的变量任务待填值（面板观察它来弹填值条）。
    @Published var pendingDropFill: TaskDropFillRequest?
    private var dropFillNonce = 0

    func requestDropFill(cardID: String, paneID: String) {
        dropFillNonce += 1
        pendingDropFill = TaskDropFillRequest(cardID: cardID, paneID: paneID, nonce: dropFillNonce)
    }

    private let fileURL: URL

    init(fileURL: URL = TaskCardStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    @discardableResult
    func create(workspaceID: String?) -> TaskCard {
        let card = TaskCard.fresh(workspaceID: workspaceID)
        cards.insert(card, at: 0)
        persist()
        return card
    }

    func upsert(_ card: TaskCard) {
        var normalized = card
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.prompt = normalized.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.updatedAt = Date()
        if let index = cards.firstIndex(where: { $0.id == card.id }) {
            cards[index] = normalized
        } else {
            cards.insert(normalized, at: 0)
        }
        persist()
    }

    func delete(_ id: String) {
        cards.removeAll { $0.id == id }
        persist()
    }

    func togglePin(_ id: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].pinned.toggle()
        cards[index].updatedAt = Date()
        persist()
    }

    func markRan(_ id: String, at date: Date = Date()) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].lastRunAt = date
        cards[index].runCount += 1
        cards[index].updatedAt = date
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([TaskCard].self, from: data)
        else {
            cards = []
            return
        }
        cards = decoded
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil)
            let data = try Self.encoder.encode(cards)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[conductor] failed to save task cards: \(error)")
        }
    }

    nonisolated private static var defaultFileURL: URL {
        let appSupport = ConductorPaths.appSupportDirectory()
        return appSupport.appendingPathComponent("task-cards.json")
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
