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
    let notificationPanelVisible: Bool
    let commandPaletteVisible: Bool

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
        self.notificationPanelVisible = model.notificationPanelVisible
        self.commandPaletteVisible = model.commandPaletteVisible
    }
}

struct ConductorToolbar: View {
    let model: ConductorWindowModel
    let workspaceSnapshot: WorkspaceChromeSnapshot
    let toolbarSnapshot: ToolbarChromeSnapshot
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

                ConductorPillGroup {
                    ConductorIconButton(state: toolbarControlState(id: "new-workspace", systemImage: "plus", tooltip: L("新建工作区 Cmd-N", "New Workspace Cmd-N"), title: L("工作区", "Workspace"))) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.newWorkspace)
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(state: toolbarControlState(id: "new-terminal", systemImage: "plus.rectangle.on.rectangle", tooltip: L("新开终端 Cmd-T", "New Terminal Cmd-T"), title: L("终端", "Terminal"))) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.newTerminal)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(state: toolbarControlState(id: "new-web-tab", systemImage: "globe", tooltip: L("新建网页标签 Cmd-Shift-T", "New Web Tab Cmd-Shift-T"), title: L("网页", "Web"))) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.newWebTab)
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(state: toolbarControlState(id: "split-right", systemImage: "rectangle.split.2x1", tooltip: L("向右分屏 Cmd-D", "Split Right Cmd-D"), title: L("右分屏", "Right"), isEnabled: toolbarSnapshot.canSplitRight)) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.splitRight)
                        }
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(state: toolbarControlState(id: "split-down", systemImage: "rectangle.split.1x2", tooltip: L("向下分屏 Cmd-Shift-D", "Split Down Cmd-Shift-D"), title: L("下分屏", "Down"), isEnabled: toolbarSnapshot.canSplitDown)) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.splitDown)
                        }
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(state: toolbarControlState(
                        id: "toggle-zoom",
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        tooltip: toolbarSnapshot.isZoomed ? L("还原当前分屏 Cmd-Opt-Z", "Restore Current Pane Cmd-Opt-Z") : L("放大当前分屏 Cmd-Opt-Z", "Zoom Current Pane Cmd-Opt-Z"),
                        title: toolbarSnapshot.isZoomed ? L("还原", "Restore") : L("放大", "Zoom"),
                        isEnabled: toolbarSnapshot.canToggleZoom,
                        isActive: toolbarSnapshot.isZoomed
                    )) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.toggleZoom)
                        }
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(state: toolbarControlState(
                        id: "toggle-file-manager",
                        systemImage: "folder",
                        tooltip: L("文件管理器", "File Manager"),
                        title: L("文件", "Files"),
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
                        tooltip: L("工作区总览 Cmd-O", "Workspace Overview Cmd-O"),
                        title: L("总览", "Overview"),
                        isActive: toolbarSnapshot.workspaceOverviewVisible
                    )) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleWorkspaceOverview)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(state: toolbarControlState(
                        id: "toggle-notifications",
                        systemImage: workspaceSnapshot.totalUnreadCount > 0 ? "bell.badge" : "bell",
                        tooltip: L("通知中心 Cmd-Opt-N", "Notification Center Cmd-Opt-N"),
                        title: workspaceSnapshot.totalUnreadCount > 0 ? L("通知 \(workspaceSnapshot.totalUnreadCount)", "Alerts \(workspaceSnapshot.totalUnreadCount)") : L("通知", "Alerts"),
                        isActive: toolbarSnapshot.notificationPanelVisible
                    )) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleNotifications)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(state: toolbarControlState(
                        id: "toggle-command-palette",
                        systemImage: "ellipsis",
                        tooltip: L("命令面板 Cmd-K", "Command Center Cmd-K"),
                        title: L("命令", "Command"),
                        isActive: toolbarSnapshot.commandPaletteVisible
                    )) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleCommandPalette)
                    }
                }
            }
            .controlSize(.small)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        }
        .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        .animation(model.shellAnimation(ConductorMotion.standard), value: theme)
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

    private func toolbarControlState(
        id: String,
        systemImage: String,
        tooltip: String,
        title: String,
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
