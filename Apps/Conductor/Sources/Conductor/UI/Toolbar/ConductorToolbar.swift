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
                    ConductorIconButton(systemImage: "plus", help: L("新建工作区 Cmd-N", "New Workspace Cmd-N"), title: L("工作区", "Workspace")) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.newWorkspace)
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(systemImage: "plus.rectangle.on.rectangle", help: L("新开终端 Cmd-T", "New Terminal Cmd-T"), title: L("终端", "Terminal")) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.newTerminal)
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(systemImage: "rectangle.split.2x1", help: L("向右分屏 Cmd-D", "Split Right Cmd-D"), title: L("右分屏", "Right"), disabled: !toolbarSnapshot.canSplitRight) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.splitRight)
                        }
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(systemImage: "rectangle.split.1x2", help: L("向下分屏 Cmd-Shift-D", "Split Down Cmd-Shift-D"), title: L("下分屏", "Down"), disabled: !toolbarSnapshot.canSplitDown) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.splitDown)
                        }
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        help: toolbarSnapshot.isZoomed ? L("还原当前分屏 Cmd-Opt-Z", "Restore Current Pane Cmd-Opt-Z") : L("放大当前分屏 Cmd-Opt-Z", "Zoom Current Pane Cmd-Opt-Z"),
                        title: toolbarSnapshot.isZoomed ? L("还原", "Restore") : L("放大", "Zoom"),
                        disabled: !toolbarSnapshot.canToggleZoom,
                        active: toolbarSnapshot.isZoomed
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.toggleZoom)
                        }
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(
                        systemImage: "folder",
                        help: L("文件管理器", "File Manager"),
                        title: L("文件", "Files"),
                        disabled: !toolbarSnapshot.canToggleFileManager,
                        active: toolbarSnapshot.fileManagerActive
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleFileManager)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: WorkspaceChromeGlyph.systemName(selected: false),
                        help: L("工作区总览 Cmd-O", "Workspace Overview Cmd-O"),
                        title: L("总览", "Overview"),
                        active: toolbarSnapshot.workspaceOverviewVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleWorkspaceOverview)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: workspaceSnapshot.totalUnreadCount > 0 ? "bell.badge" : "bell",
                        help: L("通知中心 Cmd-Opt-N", "Notification Center Cmd-Opt-N"),
                        title: workspaceSnapshot.totalUnreadCount > 0 ? L("通知 \(workspaceSnapshot.totalUnreadCount)", "Alerts \(workspaceSnapshot.totalUnreadCount)") : L("通知", "Alerts"),
                        active: toolbarSnapshot.notificationPanelVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleNotifications)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: "ellipsis",
                        help: L("命令面板 Cmd-K", "Command Center Cmd-K"),
                        title: L("命令", "Command"),
                        active: toolbarSnapshot.commandPaletteVisible
                    ) {
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

}
