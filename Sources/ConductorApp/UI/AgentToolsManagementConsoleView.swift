import AppKit
import ConductorCore
import SwiftUI

enum AgentToolsManagementModule: String, CaseIterable, Identifiable {
    case overview
    case cli
    case usage
    case skills
    case mcp
    case hooks
    case snippets
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("总览")
        case .cli: return "CLI"
        case .usage: return L("用量")
        case .skills: return "Skills"
        case .mcp: return "MCP"
        case .hooks: return "Hooks"
        case .snippets: return L("片段")
        case .activity: return L("活动")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return L("跨渠道能力、状态和入口")
        case .cli: return L("命令行工具、渠道和凭证")
        case .usage: return L("账号用量、成本和趋势")
        case .skills: return L("中央库、安装和分发")
        case .mcp: return L("服务器、工具和授权")
        case .hooks: return L("事件、通知和自动化")
        case .snippets: return L("片段、模板和快捷动作")
        case .activity: return L("日志、变更和任务轨迹")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "rectangle.3.group"
        case .cli: return "terminal"
        case .usage: return "chart.bar.xaxis"
        case .skills: return "wand.and.stars"
        case .mcp: return "point.3.connected.trianglepath.dotted"
        case .hooks: return "link"
        case .snippets: return "text.badge.star"
        case .activity: return "waveform.path.ecg"
        }
    }

    /// 管理台左栏只展示已实现的模块。片段/活动仍走各自现成入口，不在这里摆空占位。
    static let railModules: [AgentToolsManagementModule] = [.overview, .cli, .usage, .skills, .mcp, .hooks]
}

enum AgentToolsConsoleLayout {
    static let horizontalPadding: CGFloat = 18
    static let bottomPadding: CGFloat = 18
    static let columnGap: CGFloat = 10
    static let railWidth: CGFloat = 174
    static let inspectorWidth: CGFloat = 248

    static func modalSize() -> CGSize {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1512, height: 982)
        let maxWidth = max(960, visible.width - 64)
        let maxHeight = max(680, visible.height - 64)
        let preferredWidth = min(1540, max(1180, visible.width * 0.90))
        let preferredHeight = min(920, max(760, visible.height * 0.86))
        return CGSize(
            width: min(preferredWidth, maxWidth),
            height: min(preferredHeight, maxHeight))
    }

}
