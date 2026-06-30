import SwiftUI

enum ManagementWorkspaceDestination: Equatable {
    case settings
    case tools(ToolsTab)
    case sessions

    static func current(settingsPresented: Bool,
                        toolsPresented: Bool,
                        toolsTab: ToolsTab,
                        sessionsPresented: Bool) -> ManagementWorkspaceDestination? {
        if settingsPresented { return .settings }
        if toolsPresented { return .tools(toolsTab) }
        if sessionsPresented { return .sessions }
        return nil
    }
}

/// Full-page replacement for the old right drawers. It keeps management tasks
/// in a stable sidebar-detail workspace instead of squeezing them into a panel.
struct ManagementWorkspaceView: View {
    let coordinator: AppCoordinator
    @ObservedObject private var configStore = ConfigStore.shared
    @StateObject private var agentToolsStore = AgentToolsConsoleStore()
    @State private var skillsReloadID = UUID()

    private var destination: ManagementWorkspaceDestination {
        ManagementWorkspaceDestination.current(
            settingsPresented: coordinator.settingsPresentation.isPresented,
            toolsPresented: coordinator.cliToolsPresentation.isPresented,
            toolsTab: coordinator.toolsTab,
            sessionsPresented: coordinator.sessionPresentation.isPresented) ?? .tools(.cli)
    }

    var body: some View {
        HStack(spacing: 0) {
            navigationSidebar
            Rectangle()
                .fill(AppStyle.separator.opacity(0.34))
                .frame(width: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .onAppear { agentToolsStore.start() }
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(Motion.panel) { coordinator.closeManagementWorkspace() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text(L("返回应用"))
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(AppStyle.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppStyle.hoverFill))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(L("返回应用"))

            VStack(alignment: .leading, spacing: 12) {
                managementSection
                capabilitySection
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(AppStyle.chromeFill.opacity(AppStyle.theme.isDark ? 0.58 : 0.66))
    }

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sidebarSectionLabel(L("管理"))
            sidebarButton(
                title: L("设置"),
                subtitle: L("外观、终端、快捷键"),
                systemImage: "gearshape",
                selected: destination == .settings) {
                    withAnimation(Motion.snappy) { coordinator.openSettings() }
                }
            sidebarButton(
                title: L("Agent 会话"),
                subtitle: L("续聊、筛选、收藏"),
                systemImage: "bubble.left.and.text.bubble.right",
                selected: destination == .sessions) {
                    withAnimation(Motion.snappy) { coordinator.openSessionManager() }
                }
        }
    }

    private var capabilitySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sidebarSectionLabel(CapabilityLibraryPresentation.title)
            ForEach(CapabilityLibrarySection.panelTabs) { section in
                if let tab = section.toolsTab {
                    sidebarButton(
                        title: section.title,
                        subtitle: sidebarSubtitle(for: tab),
                        systemImage: section.systemImage,
                        selected: destination == .tools(tab)) {
                            withAnimation(Motion.snappy) { coordinator.openTools(tab) }
                        }
                }
            }
        }
    }

    private func sidebarSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AppStyle.textTertiary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    private func sidebarButton(title: String,
                               subtitle: String,
                               systemImage: String,
                               selected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? AppStyle.theme.primarySolidText : AppStyle.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? AppStyle.theme.primarySolidText : AppStyle.textSecondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(selected ? AppStyle.theme.primarySolidText.opacity(0.82) : AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AppStyle.accent : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .settings:
            SettingsView(
                coordinator: coordinator,
                onClose: { coordinator.closeManagementWorkspace() },
                showsCloseButton: false)
        case .sessions:
            SessionManagerView(
                coordinator: coordinator,
                onClose: { coordinator.closeManagementWorkspace() },
                showsCloseButton: false)
        case .tools(let tab):
            VStack(spacing: 0) {
                capabilityHeader(for: tab)
                Divider().opacity(0.35)
                toolContent(tab)
            }
        }
    }

    private func capabilityHeader(for tab: ToolsTab) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tab.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppStyle.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(CapabilityLibraryPresentation.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func toolContent(_ tab: ToolsTab) -> some View {
        switch tab {
        case .cli:
            CLIToolsView(coordinator: coordinator, onClose: { coordinator.closeManagementWorkspace() })
        case .usage:
            UsageStatsView {
                coordinator.openAgentToolsManagement(.usage)
            }
        case .skills:
            AgentToolsSkillsView(
                store: agentToolsStore,
                initialSection: "library",
                reloadID: skillsReloadID,
                onOpenModule: { openPanelModule($0) })
        case .mcp:
            AgentToolsMCPWorkbenchView(store: agentToolsStore)
        case .hooks:
            AgentToolsHooksWorkbenchView(store: agentToolsStore)
        case .snippets:
            SnippetsManagerView(coordinator: coordinator)
        case .coCreate:
            CoCreateView()
        }
    }

    private func openPanelModule(_ module: AgentToolsManagementModule) {
        let tab: ToolsTab?
        switch module {
        case .cli: tab = .cli
        case .usage: tab = .usage
        case .skills: tab = .skills
        case .mcp: tab = .mcp
        case .hooks: tab = .hooks
        default: tab = nil
        }
        if let tab { withAnimation(Motion.snappy) { coordinator.openTools(tab) } }
    }

    private func sidebarSubtitle(for tab: ToolsTab) -> String {
        switch tab {
        case .cli: return L("检测与启动")
        case .usage: return L("成本、Token、趋势")
        case .skills: return L("技能库与同步")
        case .mcp: return L("工具服务器")
        case .hooks: return L("自动化 Hook")
        case .snippets: return L("常用命令")
        case .coCreate: return L("反馈与共创")
        }
    }
}
