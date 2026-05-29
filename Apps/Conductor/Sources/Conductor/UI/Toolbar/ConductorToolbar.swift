import ConductorCore
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ToolbarChromeSnapshot: Equatable {
    let canSplitRight: Bool
    let canSplitDown: Bool
    let canToggleZoom: Bool
    let isZoomed: Bool
    let canToggleFileManager: Bool
    let fileManagerActive: Bool
    let workspaceOverviewVisible: Bool
    let commandPaletteVisible: Bool
    let replyNotificationsEnabled: Bool

    @MainActor
    init(model: ConductorWindowModel) {
        RenderCounter.increment("toolbar-chrome-snapshot")
        self.canSplitRight = model.canPerformCommand(.splitRight)
        self.canSplitDown = model.canPerformCommand(.splitDown)
        self.canToggleZoom = model.canPerformCommand(.toggleZoom)
        self.isZoomed = model.workspace.isZoomed
        self.canToggleFileManager = model.canPerformCommand(.toggleFileManager)
        self.fileManagerActive = model.fileManagerPanelRequest != nil
        self.workspaceOverviewVisible = model.workspaceOverviewVisible
        self.commandPaletteVisible = model.commandPaletteVisible
        self.replyNotificationsEnabled = model.appearance.agentReplyNotifications.enabled
    }
}

struct ConductorToolbar: View {
    let model: ConductorWindowModel
    let workspaceSnapshot: WorkspaceChromeSnapshot
    let toolbarSnapshot: ToolbarChromeSnapshot
    let updateState: ConductorUpdateState
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    @State private var editingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""

    var body: some View {
        ConductorTerminalToolbarSurface(theme: theme) {
            HStack(spacing: ConductorTokens.Space.toolbarGap) {
                WorkspaceTabStrip(
                    model: model,
                    snapshot: workspaceSnapshot,
                    appearance: appearance,
                    editingWorkspaceID: $editingWorkspaceID,
                    workspaceTitleDraft: $workspaceTitleDraft,
                    onBeginRename: beginRenameWorkspace,
                    onCommitRename: commitWorkspaceRename,
                    onCancelRename: cancelWorkspaceRename
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

                toolbarActions
            }
            .controlSize(.small)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        }
        .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        .animation(model.shellAnimation(ConductorMotion.standard), value: theme)
        .animation(model.shellAnimation(ConductorMotion.panel), value: shouldShowUpdateButton)
        .animation(model.shellAnimation(ConductorMotion.panel), value: updateState.phase)
    }

    private var toolbarActions: some View {
        ConductorToolbarActionCluster {
            if shouldShowUpdateButton {
                ConductorToolbarUpdateButton(model: model, state: updateState)
                    .transition(.identity)
                ConductorToolbarActionDivider()
            }

            ConductorIconButton(state: toolbarControlState(
                id: "check-notifications",
                systemImage: toolbarSnapshot.replyNotificationsEnabled ? "bell.badge.fill" : "bell",
                tooltip: L("检测通知权限", "Check Notification Permission"),
                isActive: toolbarSnapshot.replyNotificationsEnabled
            )) {
                finishWorkspaceRenameIfNeeded()
                model.checkNotificationPermissionFromToolbar()
            }
            ConductorToolbarActionDivider()

            ConductorToolbarMenuButton(
                state: toolbarControlState(
                    id: "new-actions",
                    systemImage: "plus",
                    tooltip: L("新建工作区、终端或网页", "Create workspace, terminal, or web tab"),
                    title: L("新建", "New")))
            {
                Button(L("新建工作区", "New Workspace"), systemImage: "plus") {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newWorkspace)
                }

                Button(L("新开终端", "New Terminal"), systemImage: "plus.rectangle.on.rectangle") {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newTerminal)
                }

                Button(L("新建网页标签", "New Web Tab"), systemImage: "globe") {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newWebTab)
                }
            }

            ConductorToolbarActionDivider()

            ConductorIconButton(state: toolbarControlState(id: "split-right", systemImage: "rectangle.split.2x1", tooltip: commandTooltip(L("向右分屏", "Split Right"), command: .splitRight, fallback: "Cmd-D"), isEnabled: toolbarSnapshot.canSplitRight)) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.splitRight)
                }
            }
            ConductorSegmentDivider()
            ConductorIconButton(state: toolbarControlState(id: "split-down", systemImage: "rectangle.split.1x2", tooltip: commandTooltip(L("向下分屏", "Split Down"), command: .splitDown, fallback: "Cmd-Shift-D"), isEnabled: toolbarSnapshot.canSplitDown)) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.splitDown)
                }
            }
            ConductorSegmentDivider()
            ConductorIconButton(state: toolbarControlState(
                id: "toggle-zoom",
                systemImage: "arrow.up.left.and.arrow.down.right",
                tooltip: toolbarSnapshot.isZoomed ? commandTooltip(L("还原当前分屏", "Restore Current Pane"), command: .toggleZoom, fallback: "Cmd-Opt-Z") : commandTooltip(L("放大当前分屏", "Zoom Current Pane"), command: .toggleZoom, fallback: "Cmd-Opt-Z"),
                isEnabled: toolbarSnapshot.canToggleZoom,
                isActive: toolbarSnapshot.isZoomed
            )) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.toggleZoom)
                }
            }

            ConductorToolbarActionDivider()

            ConductorIconButton(state: toolbarControlState(
                id: "toggle-file-manager",
                systemImage: "folder",
                tooltip: L("文件管理器", "File Manager"),
                isEnabled: toolbarSnapshot.canToggleFileManager,
                isActive: toolbarSnapshot.fileManagerActive
            )) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleFileManager)
            }
            ConductorSegmentDivider()
            ConductorIconButton(state: toolbarControlState(
                id: "toggle-workspace-overview",
                systemImage: WorkspaceChromeGlyph.systemName(selected: false),
                tooltip: commandTooltip(L("工作区总览", "Workspace Overview"), command: .toggleWorkspaceOverview, fallback: "Cmd-O"),
                isActive: toolbarSnapshot.workspaceOverviewVisible
            )) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleWorkspaceOverview)
            }
            ConductorSegmentDivider()
            ConductorIconButton(state: toolbarControlState(
                id: "toggle-command-palette",
                systemImage: "command",
                tooltip: commandTooltip(L("命令面板", "Command Palette"), command: .toggleCommandPalette, fallback: "Cmd-K"),
                isActive: toolbarSnapshot.commandPaletteVisible
            )) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
        }
    }

    private var shouldShowUpdateButton: Bool {
        switch updateState.phase {
        case .checking, .available, .downloading, .downloaded, .installing, .failed:
            true
        case .idle, .upToDate:
            false
        }
    }

    private func beginRenameWorkspace(_ row: WorkspaceChromeDisplayModel) {
        workspaceTitleDraft = row.title
        editingWorkspaceID = row.id
    }

    private func commitWorkspaceRename() {
        if let editingWorkspaceID {
            ConductorMotion.perform(ConductorMotion.selection) {
                model.renameWorkspace(editingWorkspaceID, title: workspaceTitleDraft)
            }
        }
        editingWorkspaceID = nil
    }

    private func finishWorkspaceRenameIfNeeded() {
        guard editingWorkspaceID != nil else { return }
        commitWorkspaceRename()
    }

    private func cancelWorkspaceRename() {
        editingWorkspaceID = nil
    }

    private func commandTooltip(_ title: String, command: ConductorShellCommand, fallback: String) -> String {
        "\(title) \(model.shortcutTitle(for: command, fallback: fallback))"
    }

    private func toolbarControlState(
        id: String,
        systemImage: String,
        tooltip: String,
        title: String? = nil,
        isEnabled: Bool = true,
        isActive: Bool = false
    ) -> ConductorControlState {
        ConductorControlState(
            id: id,
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            isActive: isActive,
            tooltip: tooltip,
            accessibilityLabel: tooltip
        )
    }

}

private struct ConductorToolbarUpdateButton: View {
    let model: ConductorWindowModel
    let state: ConductorUpdateState

    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: 5) {
                if state.phase == .checking {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                } else if state.phase == .downloading {
                    ProgressView(value: state.downloadProgress?.fraction ?? 0)
                        .controlSize(.mini)
                        .tint(.white)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }

                Text(title)
                    .font(.conductorSystem(size: 10.6, weight: .bold, family: fontFamily, scale: fontScale))
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(buttonFill)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.12 : 0.28), lineWidth: 0.8)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.98, pressedOpacity: 0.94))
        .macNativeTooltip(tooltip)
        .accessibilityLabel(Text(tooltip))
        .conductorHover($hovering)
        .animation(ConductorMotion.hover, value: hovering)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
    }

    private var title: String {
        switch state.phase {
        case .checking:
            return L("检查中", "Checking")
        case .downloading:
            guard let progress = state.downloadProgress else {
                return L("下载中", "Downloading")
            }
            return "\(Int((progress.fraction * 100).rounded()))%"
        case .downloaded:
            return L("安装", "Install")
        case .installing:
            return L("安装中", "Installing")
        case .failed:
            return L("重试", "Retry")
        default:
            return L("更新", "Update")
        }
    }

    private var tooltip: String {
        switch state.phase {
        case .available:
            return L("下载可用更新", "Download available update")
        case .downloading:
            return L("打开更新进度", "Open update progress")
        case .downloaded:
            return L("安装更新并重新打开", "Install update and reopen")
        case .installing:
            return L("正在安装更新", "Installing update")
        default:
            return L("检查更新", "Check for updates")
        }
    }

    private var buttonFill: Color {
        let base = state.phase == .installing ? theme.floatingEmphasis : theme.accent
        return base.opacity(hovering ? 0.94 : 0.84)
    }

    @MainActor
    private func performAction() {
        switch state.phase {
        case .available:
            model.downloadAvailableUpdate()
        case .downloaded:
            model.installDownloadedUpdateAndRelaunch()
        case .downloading, .installing:
            model.showSettingsPanel(section: .updates)
        default:
            model.showUpdatesAndCheck()
        }
    }
}

private struct ConductorToolbarActionCluster<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 1) {
            content
        }
        .padding(2)
        .background(clusterFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                .stroke(clusterStroke, lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(theme.chromeMaterial.shadowOpacity), radius: 8, y: 2)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
    }

    private var clusterFill: Color {
        if theme.usesDarkChrome {
            return Color.white.opacity(0.014 * theme.chromeMaterial.controlOpacityBoost + theme.chromeMaterial.highlightOpacity * 0.12)
        }
        return theme.shellControlFill.opacity(0.18 * theme.chromeMaterial.controlOpacityBoost)
    }

    private var clusterStroke: Color {
        if theme.usesDarkChrome {
            return Color.white.opacity(0.024 * theme.chromeMaterial.strokeOpacityBoost + theme.chromeMaterial.highlightOpacity * 0.18)
        }
        return theme.shellStroke.opacity(0.12 * theme.chromeMaterial.strokeOpacityBoost)
    }
}

private struct ConductorToolbarActionDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.18 : 0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }
}

private struct ConductorToolbarMenuButton<MenuContent: View>: View {
    let state: ConductorControlState
    @ViewBuilder let menuContent: MenuContent

    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    init(
        state: ConductorControlState,
        @ViewBuilder menuContent: () -> MenuContent
    ) {
        self.state = state
        self.menuContent = menuContent()
    }

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 5) {
                Image(systemName: state.systemImage)
                    .renderingMode(.template)
                    .symbolRenderingMode(.monochrome)
                    .font(.conductorSystem(size: 11.4, weight: .semibold, family: fontFamily, scale: fontScale))

                if let title = state.title {
                    Text(title)
                        .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Image(systemName: "chevron.down")
                    .font(.conductorSystem(size: 7.5, weight: .bold, family: fontFamily, scale: fontScale))
                    .opacity(0.62)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, state.title == nil ? 7 : 8)
            .frame(height: 26)
            .background(background)
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.control, style: .continuous)
                    .stroke(buttonStroke, lineWidth: 0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.control, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .macNativeTooltip(state.tooltip)
        .accessibilityLabel(Text(state.accessibilityLabel))
        .conductorHover($hovering)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var foreground: Color {
        state.isActive ? theme.shellChromeText : theme.shellChromeText.opacity(hovering ? 0.82 : 0.64)
    }

    private var background: Color {
        if theme.usesDarkChrome {
            let base = state.isActive ? 0.052 : (hovering ? 0.030 : 0.0)
            return Color.white.opacity(base * theme.chromeMaterial.controlOpacityBoost + theme.chromeMaterial.highlightOpacity * 0.10)
        }
        return state.isActive ? theme.shellSelectedFill.opacity(0.52) : (hovering ? theme.shellHoverFill.opacity(0.42) : theme.shellControlFill.opacity(0.28))
    }

    private var buttonStroke: Color {
        if theme.usesDarkChrome {
            let base = state.isActive ? 0.075 : (hovering ? 0.044 : 0.0)
            return Color.white.opacity(base * theme.chromeMaterial.strokeOpacityBoost + theme.chromeMaterial.highlightOpacity * 0.12)
        }
        return theme.shellStroke.opacity(state.isActive ? 0.38 : (hovering ? 0.28 : 0.16))
    }
}
