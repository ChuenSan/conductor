import SwiftUI

/// 工具面板分段。
enum ToolsTab: String, CaseIterable, Identifiable {
    case cli
    case usage
    case skills
    case hooks
    case snippets
    case coCreate

    var id: String { rawValue }
    /// 面板分段里展示的 tab。共创计划由 tab 栏右上角按钮进入，不占面板分段。
    static var panelTabs: [ToolsTab] { allCases.filter { $0 != .coCreate } }
    var title: String {
        switch self {
        case .cli: return "CLI"
        case .usage: return L("用量")
        case .skills: return "Skills"
        case .hooks: return "Hooks"
        case .snippets: return L("片段")
        case .coCreate: return L("共创")
        }
    }
    var icon: String {
        switch self {
        case .cli: return "terminal"
        case .usage: return "chart.bar.xaxis"
        case .skills: return "wand.and.stars"
        case .hooks: return "link"
        case .snippets: return "text.badge.star"
        case .coCreate: return "text.bubble"
        }
    }
}

/// 右侧多分段工具面板：CLI 工具检测 / Token 用量 / Skill 管理 / Hook 管理。
struct ToolsPanelView: View {
    let coordinator: AppCoordinator
    var onClose: () -> Void = {}
    /// 主题变 → 重渲染（AppStyle 跟随）。不观察的话切主题后面板会停在旧配色。
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(AppStyle.separator)
            content
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.windowBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(AppStyle.separator).frame(width: 1).allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            segmented
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppStyle.hoverFill))
                    .contentShape(Circle())
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// 分段控件：凹槽容器 + 选中片「抬起」（白片/亮片 + 柔阴影），对标系统分段而非彩色按钮。
    private var segmented: some View {
        let theme = AppStyle.theme
        return HStack(spacing: 2) {
            ForEach(ToolsTab.panelTabs) { tab in
                let selected = coordinator.toolsTab == tab
                Button {
                    withAnimation(Motion.snappy) {
                        coordinator.toolsTab = tab
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(selected ? AppStyle.accent : AppStyle.textTertiary)
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? AppStyle.textPrimary : AppStyle.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(theme.elevated)
                                .shadow(color: .black.opacity(theme.isDark ? 0.35 : 0.10), radius: 3, y: 1)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppStyle.hoverFill))
    }

    @ViewBuilder
    private var content: some View {
        switch coordinator.toolsTab {
        case .cli:
            CLIToolsView(coordinator: coordinator, onClose: onClose)
        case .usage:
            UsageStatsView()
        case .skills:
            SkillsManagerView()
        case .hooks:
            HooksManagerView()
        case .snippets:
            SnippetsManagerView(coordinator: coordinator)
        case .coCreate:
            CoCreateView()
        }
    }
}
