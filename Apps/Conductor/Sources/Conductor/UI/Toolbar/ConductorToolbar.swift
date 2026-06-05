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
    let resumableAgentCount: Int
    let canOpenLocalService: Bool
    let localServiceTitle: String?

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
        self.resumableAgentCount = model.controlResumableTerminalAgents(workspaceID: model.workspace.id).count
        if let serviceURL = model.currentWorkspaceFirstLocalServiceURL {
            self.canOpenLocalService = model.canPerformCommand(.openCurrentWorkspaceFirstService)
            self.localServiceTitle = Self.serviceTitle(for: serviceURL)
        } else {
            self.canOpenLocalService = false
            self.localServiceTitle = nil
        }
    }

    var workspaceActionCount: Int {
        [resumableAgentCount > 0, canOpenLocalService]
            .filter { $0 }
            .count
    }

    var hasWorkspaceActions: Bool {
        workspaceActionCount > 0
    }

    private static func serviceTitle(for url: URL) -> String {
        if let port = url.port {
            return ":\(port)"
        }
        let host = url.host() ?? url.absoluteString
        return host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Service" : host
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
        .background(.regularMaterial)
        .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        .animation(model.shellAnimation(ConductorMotion.standard), value: theme)
        .animation(model.shellAnimation(ConductorMotion.panel), value: shouldShowUpdateButton)
        .animation(model.shellAnimation(ConductorMotion.panel), value: updateState.phase)
        .animation(model.shellAnimation(ConductorMotion.panel), value: toolbarSnapshot.workspaceActionCount)
        .onChange(of: model.workspaceRenameRequest) { _, request in
            guard let request,
                  let row = workspaceSnapshot.rows.first(where: { $0.id == request.workspaceID }) else {
                return
            }
            beginRenameWorkspace(row)
        }
    }

    private var toolbarActions: some View {
        ControlGroup {
            if shouldShowUpdateButton {
                toolbarUpdateButton
                    .transition(.identity)
            }

            if toolbarSnapshot.hasWorkspaceActions {
                toolbarMenu(
                    title: primaryWorkspaceActionTitle,
                    systemImage: primaryWorkspaceActionIcon,
                    help: primaryWorkspaceActionTooltip
                ) {
                    if toolbarSnapshot.resumableAgentCount > 0 {
                        Button(
                            L("恢复当前工作区 Agent", "Resume Workspace Agents"),
                            systemImage: "arrow.clockwise.circle"
                        ) {
                            finishWorkspaceRenameIfNeeded()
                            model.performCommand(.resumeCurrentWorkspaceAgents)
                        }
                    }

                    if toolbarSnapshot.canOpenLocalService {
                        Button(
                            L("打开本地服务", "Open Local Service"),
                            systemImage: "network"
                        ) {
                            finishWorkspaceRenameIfNeeded()
                            model.performCommand(.openCurrentWorkspaceFirstService)
                        }
                    }

                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            toolbarMenu(
                title: L("新建", "New"),
                systemImage: "plus",
                help: L("新建工作区、终端或网页", "Create workspace, terminal, or web tab")
            ) {
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

            toolbarIconButton(systemImage: "rectangle.split.2x1", help: commandTooltip(L("向右分屏", "Split Right"), command: .splitRight, fallback: "Cmd-D"), enabled: toolbarSnapshot.canSplitRight) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.splitRight)
                }
            }
            toolbarIconButton(systemImage: "rectangle.split.1x2", help: commandTooltip(L("向下分屏", "Split Down"), command: .splitDown, fallback: "Cmd-Shift-D"), enabled: toolbarSnapshot.canSplitDown) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.splitDown)
                }
            }
            toolbarIconButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                help: toolbarSnapshot.isZoomed ? commandTooltip(L("还原当前分屏", "Restore Current Pane"), command: .toggleZoom, fallback: "Cmd-Opt-Z") : commandTooltip(L("放大当前分屏", "Zoom Current Pane"), command: .toggleZoom, fallback: "Cmd-Opt-Z"),
                enabled: toolbarSnapshot.canToggleZoom,
                active: toolbarSnapshot.isZoomed
            ) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.toggleZoom)
                }
            }

            toolbarIconButton(systemImage: "folder", help: L("文件管理器", "File Manager"), enabled: toolbarSnapshot.canToggleFileManager, active: toolbarSnapshot.fileManagerActive) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleFileManager)
            }
            toolbarIconButton(systemImage: WorkspaceChromeGlyph.systemName(selected: false), help: commandTooltip(L("工作区面板", "Workspaces"), command: .toggleWorkspaceOverview, fallback: "Cmd-O"), active: toolbarSnapshot.workspaceOverviewVisible) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleWorkspaceOverview)
            }
            toolbarIconButton(systemImage: "command", help: commandTooltip(L("命令面板", "Command Palette"), command: .toggleCommandPalette, fallback: "Cmd-K"), active: toolbarSnapshot.commandPaletteVisible) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
        }
        .controlGroupStyle(.automatic)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
    }

    private var toolbarUpdateButton: some View {
        Button(action: performUpdateAction) {
            HStack(spacing: 5) {
                if updateState.phase == .checking {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                } else if updateState.phase == .downloading {
                    ProgressView(value: updateState.downloadProgress?.fraction ?? 0)
                        .controlSize(.mini)
                        .tint(.white)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }

                Text(updateButtonTitle)
                    .font(.conductorSystem(size: 10.6, weight: .bold, family: appearance.fontFamily, scale: appearance.fontScale))
                    .lineLimit(1)
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .help(updateButtonTooltip)
        .accessibilityLabel(Text(updateButtonTooltip))
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(3)
    }

    private var updateButtonTitle: String {
        switch updateState.phase {
        case .checking:
            return L("检查中", "Checking")
        case .downloading:
            guard let progress = updateState.downloadProgress else {
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

    private var updateButtonTooltip: String {
        switch updateState.phase {
        case .available:
            return L("下载可用更新", "Download available update")
        case .downloading:
            return L("打开更新进度，可取消下载", "Open update progress and cancel download")
        case .downloaded:
            return L("安装更新并重新打开", "Install update and reopen")
        case .installing:
            return L("正在安装更新", "Installing update")
        default:
            return L("检查更新", "Check for updates")
        }
    }

    @MainActor
    private func performUpdateAction() {
        switch updateState.phase {
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

    private func toolbarMenu<MenuContent: View>(
        title: String?,
        systemImage: String,
        help: String,
        enabled: Bool = true,
        active: Bool = false,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        Menu {
            menuContent()
        } label: {
            if let title {
                Label(title, systemImage: systemImage)
            } else {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .tint(active ? theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.42 : 0.30) : Color.clear)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var shouldShowUpdateButton: Bool {
        switch updateState.phase {
        case .checking, .available, .downloading, .downloaded, .installing, .failed:
            true
        case .idle, .upToDate:
            false
        }
    }

    private var primaryWorkspaceActionTitle: String {
        if toolbarSnapshot.resumableAgentCount > 0 {
            return L("续接", "Resume")
        }
        if toolbarSnapshot.canOpenLocalService {
            return toolbarSnapshot.localServiceTitle ?? L("服务", "Service")
        }
        return L("操作", "Actions")
    }

    private var primaryWorkspaceActionIcon: String {
        if toolbarSnapshot.resumableAgentCount > 0 {
            return "arrow.clockwise.circle"
        }
        if toolbarSnapshot.canOpenLocalService {
            return "network"
        }
        return "ellipsis.circle"
    }

    private var primaryWorkspaceActionTooltip: String {
        if toolbarSnapshot.resumableAgentCount > 0 {
            return L("恢复当前工作区可续接的 Agent", "Resume agents in this workspace")
        }
        if toolbarSnapshot.canOpenLocalService {
            return L("打开当前工作区检测到的本地服务", "Open the detected local service for this workspace")
        }
        return L("工作区操作", "Workspace actions")
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

    private func toolbarIconButton(
        systemImage: String,
        help: String,
        enabled: Bool = true,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(help, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .foregroundStyle(active ? theme.floatingEmphasis : ConductorDesign.primaryText)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
        .fixedSize(horizontal: true, vertical: false)
    }

}
