import AppKit
import SwiftUI

/// 整体布局：左侧工作区栏 | (顶部 Tab 栏 + 终端分屏区)。
struct RootView: View {
    @ObservedObject var coordinator: AppCoordinator
    /// 观察配置：主题变化时整棵外壳重渲染(AppStyle 跟随)。
    @ObservedObject private var configStore = ConfigStore.shared
    /// 语言热切换：revision 变 → `.id()` 强制整棵树重建，所有 L() 文案按新语言重新求值。
    @ObservedObject private var localization = AppLanguage.revision

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(coordinator: coordinator)
                .frame(width: coordinator.sidebarPresentation.isCollapsed ? AppStyle.sidebarCollapsedWidth : AppStyle.sidebarWidth)
            VStack(spacing: 0) {
                TabBarView(coordinator: coordinator)
                ZStack(alignment: .center) {
                    TerminalAreaView(container: coordinator.containerView)
                    if QuickStartAvailability.showsEmptyIllustration(
                        tabCount: activeWorkspaceMetrics?.tabCount,
                        totalPaneCount: activeWorkspaceMetrics?.totalPaneCount,
                        isPanelPresented: coordinator.isSidePanelPresented
                    ) {
                        QuickStartLaunchPanel(
                            title: activeWorkspaceName,
                            subtitle: L("空工作区"),
                            primaryActions: terminalPrimaryActions,
                            secondaryActions: terminalSecondaryActions
                        )
                        .padding(.horizontal, 32)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)))
                    }
                }
                StatusBarView(coordinator: coordinator, usageMonitor: coordinator.usageMonitor)
            }
            if coordinator.settingsPresentation.isPresented {
                SettingsView(coordinator: coordinator, onClose: { coordinator.closeSettings() })
                    .frame(width: 560)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if coordinator.cliToolsPresentation.isPresented {
                ToolsPanelView(coordinator: coordinator, onClose: { coordinator.closeCLITools() })
                    .frame(width: 440)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if coordinator.sessionPresentation.isPresented {
                SessionManagerView(coordinator: coordinator, onClose: { coordinator.closeSessionManager() })
                    .frame(width: 400)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .id(localization.value)   // 语言切换 → 重建子树（TerminalAreaView 复用同一 NSView，终端不受影响）
        .background(AppStyle.windowBackground)
        .ignoresSafeArea()
        .animation(Motion.panel, value: coordinator.sidebarPresentation.isCollapsed)
        .animation(Motion.panel, value: coordinator.settingsPresentation.isPresented)
        .animation(Motion.panel, value: coordinator.cliToolsPresentation.isPresented)
        .animation(Motion.panel, value: coordinator.sessionPresentation.isPresented)
        .animation(Motion.panel, value: activeWorkspaceMetrics?.totalPaneCount)
    }

    private var activeWorkspaceMetrics: (tabCount: Int, totalPaneCount: Int)? {
        guard let workspace = coordinator.store.workspaces.first(where: { $0.id == coordinator.store.activeWorkspace }) else {
            return nil
        }
        return (
            tabCount: workspace.tabs.count,
            totalPaneCount: workspace.tabs.reduce(0) { $0 + $1.paneCount }
        )
    }

    private var activeWorkspaceName: String {
        coordinator.store.workspaces.first { $0.id == coordinator.store.activeWorkspace }?.name ?? L("工作区")
    }

    private var terminalPrimaryActions: [QuickStartAction] {
        [
            QuickStartAction(id: "newTab", title: L("新标签"), systemImage: "plus", isPrimary: true) {
                coordinator.newTab()
            },
        ]
    }

    private var terminalSecondaryActions: [QuickStartAction] {
        [
            QuickStartAction(id: "commandPalette", title: L("命令"), systemImage: "command") {
                coordinator.openCommandPalette()
            },
            QuickStartAction(id: "openSettings", title: L("设置"), systemImage: "gearshape") {
                coordinator.openSettings()
            },
        ]
    }
}

/// 把 AppKit 的终端分屏容器（承载 libghostty 视图）嵌入 SwiftUI 布局。
struct TerminalAreaView: NSViewRepresentable {
    let container: NSView
    func makeNSView(context: Context) -> NSView { container }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
