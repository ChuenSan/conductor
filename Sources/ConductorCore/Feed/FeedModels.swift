import Foundation

/// agent 请求的动作类别——审批策略按它做粒度。
public enum FeedActionCategory: String, Codable, Sendable, CaseIterable {
    case readFile         // 读文件
    case writeFile        // 写 / 改 / 删文件
    case executeCommand   // 执行 shell 命令
    case network          // 网络访问
    case other
}

/// 一条待审批请求的内容。运行时类型，不持久化。
public enum FeedRequestKind: Equatable, Sendable {
    /// 工具 / 权限请求：工具名 + 动作类别 + 可选具体内容（executeCommand 时是命令行）。
    case permission(tool: String, category: FeedActionCategory, detail: String?)
    /// 退出计划模式：展示计划全文，等用户放行。
    case exitPlan(plan: String)
    /// 向用户提问：题干 + 选项。
    case question(prompt: String, options: [String])
}

/// 一条 agent 发来的待审批请求。运行时类型（socket 收到即建，GUI/规则处置后丢弃）。
public struct FeedRequest: Identifiable, Equatable, Sendable {
    public var id: String
    public var paneID: String?
    public var agent: String?       // claude / codex / …
    public var cwd: String?
    public var kind: FeedRequestKind
    public var createdAt: Date

    public init(id: String = UUID().uuidString,
                paneID: String? = nil,
                agent: String? = nil,
                cwd: String? = nil,
                kind: FeedRequestKind,
                createdAt: Date = Date()) {
        self.id = id
        self.paneID = paneID
        self.agent = agent
        self.cwd = cwd
        self.kind = kind
        self.createdAt = createdAt
    }

    /// 便捷取该请求的工具/类别（仅 permission 有）。
    public var tool: String? {
        if case let .permission(tool, _, _) = kind { return tool }
        return nil
    }
    public var category: FeedActionCategory? {
        if case let .permission(_, category, _) = kind { return category }
        return nil
    }
    public var detail: String? {
        if case let .permission(_, _, detail) = kind { return detail }
        return nil
    }
}

/// 审批粒度。
public enum FeedScope: String, Codable, Sendable {
    case once       // 仅这一次，不记忆
    case tool       // 记住：以后这个 agent 的这个工具+类别自动同样处理
    case category   // 记住：以后这个 agent 的这一动作类别（不限工具）自动同样处理
}

/// 用户或规则给出的决策。
public enum FeedDecision: Equatable, Sendable {
    case allow(FeedScope)
    case deny(FeedScope)
    case answer(optionIndex: Int)   // 针对 question

    public var isAllow: Bool { if case .allow = self { return true }; return false }
    public var isDeny: Bool { if case .deny = self { return true }; return false }
}
