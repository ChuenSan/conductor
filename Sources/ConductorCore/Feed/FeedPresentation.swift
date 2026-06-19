import Foundation

/// 一个审批按钮：文案 + 点下去对应的决策 + 视觉角色。纯展示派生，供 GUI 渲染。
public struct FeedActionButton: Equatable, Sendable, Identifiable {
    public enum Role: String, Sendable { case allow, deny, neutral }
    public var label: String
    public var decision: FeedDecision
    public var role: Role
    public var id: String { "\(role.rawValue):\(label)" }

    public init(label: String, decision: FeedDecision, role: Role) {
        self.label = label
        self.decision = decision
        self.role = role
    }
}

/// 由请求派生出该展示什么按钮——permission/exitPlan/question 各不同。纯函数，可单测。
public enum FeedPresentation {
    public static func actions(for request: FeedRequest) -> [FeedActionButton] {
        switch request.kind {
        case let .permission(tool, category, _):
            return [
                FeedActionButton(label: L("允许一次"), decision: .allow(.once), role: .allow),
                FeedActionButton(label: L("总是允许 %@", tool), decision: .allow(.tool), role: .allow),
                FeedActionButton(label: L("允许所有%@", category.label), decision: .allow(.category), role: .allow),
                FeedActionButton(label: L("拒绝"), decision: .deny(.once), role: .deny),
            ]
        case .exitPlan:
            return [
                FeedActionButton(label: L("批准计划"), decision: .allow(.once), role: .allow),
                FeedActionButton(label: L("拒绝"), decision: .deny(.once), role: .deny),
            ]
        case let .question(_, options):
            return options.enumerated().map { index, option in
                FeedActionButton(label: option, decision: .answer(optionIndex: index), role: .neutral)
            }
        }
    }

    /// 标题（请求类型的一句话）。
    public static func title(for request: FeedRequest) -> String {
        switch request.kind {
        case let .permission(tool, _, _): return L("%@ 请求权限", tool)
        case .exitPlan: return L("Agent 想退出计划模式开始执行")
        case .question: return L("Agent 有个问题")
        }
    }

    /// 正文（要批的具体内容：命令 / 计划 / 题干）。
    public static func body(for request: FeedRequest) -> String? {
        switch request.kind {
        case let .permission(_, _, detail): return detail
        case let .exitPlan(plan): return plan
        case let .question(prompt, _): return prompt
        }
    }
}
