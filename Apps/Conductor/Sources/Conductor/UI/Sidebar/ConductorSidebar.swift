import AppKit
import CodexBar
import ConductorCore
import SwiftUI

private func withoutShellAnimation(_ action: () -> Void) {
    ConductorMotion.withoutAnimation(action)
}

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private struct WindowControlButtons: View {
    let spacing: CGFloat
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.conductorTheme) private var theme
    @State private var isHoveringGroup = false

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    private var isWindowActive: Bool {
        controlActiveState != .inactive
    }

    var body: some View {
        HStack(spacing: spacing) {
            // Close Button (Red)
            controlButton(
                id: "close",
                activeColor: Color(red: 1.0, green: 0.38, blue: 0.34),
                inactiveColor: theme.usesDarkChrome ? Color(white: 0.30) : Color(white: 0.84),
                symbolName: "xmark",
                symbolSize: 5.5,
                symbolColor: Color(red: 0.35, green: 0.03, blue: 0.02),
                accessibilityLabel: L("关闭窗口", "Close Window")
            ) {
                NSApp.keyWindow?.performClose(nil)
            }

            // Minimize Button (Yellow)
            controlButton(
                id: "minimize",
                activeColor: Color(red: 1.0, green: 0.74, blue: 0.18),
                inactiveColor: theme.usesDarkChrome ? Color(white: 0.30) : Color(white: 0.84),
                symbolName: "minus",
                symbolSize: 5.5,
                symbolColor: Color(red: 0.38, green: 0.20, blue: 0.01),
                accessibilityLabel: L("最小化窗口", "Minimize Window")
            ) {
                NSApp.keyWindow?.performMiniaturize(nil)
            }

            // Fullscreen Button (Green)
            controlButton(
                id: "fullscreen",
                activeColor: Color(red: 0.15, green: 0.79, blue: 0.25),
                inactiveColor: theme.usesDarkChrome ? Color(white: 0.30) : Color(white: 0.84),
                symbolName: "arrow.up.left.and.arrow.down.right",
                symbolSize: 4.5,
                symbolColor: Color(red: 0.01, green: 0.32, blue: 0.04),
                accessibilityLabel: L("切换全屏", "Toggle Full Screen")
            ) {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
        .frame(height: 16)
        .onHover { hovering in
            isHoveringGroup = hovering
        }
    }

    @ViewBuilder
    private func controlButton(
        id: String,
        activeColor: Color,
        inactiveColor: Color,
        symbolName: String,
        symbolSize: CGFloat,
        symbolColor: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(isWindowActive ? activeColor : inactiveColor)
                .overlay {
                    Circle()
                        .stroke(isWindowActive ? Color.black.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 0.7)
                }
                .overlay {
                    if isHoveringGroup && isWindowActive {
                        Image(systemName: symbolName)
                            .font(.system(size: symbolSize, weight: .bold))
                            .foregroundStyle(symbolColor)
                    }
                }
                .frame(width: 12, height: 12)
        }
        .buttonStyle(.plain)
        .frame(width: 12, height: 12)
        .accessibilityLabel(accessibilityLabel)
        .macNativeTooltip(accessibilityLabel)
    }
}

struct ConductorSidebar: View {
    let model: ConductorWindowModel
    let snapshot: WorkspaceChromeSnapshot
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let sidebarVisible: Bool
    @State private var renamingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""
    @State private var sidebarToggleHovering = false
    @Namespace private var sidebarSelectionNamespace
    @Namespace private var railSelectionNamespace
    @Environment(\.conductorFontScale) private var fontScale

    private var sidebarHeaderHeight: CGFloat {
        sidebarVisible ? 50 : ConductorDesign.sidebarCollapsedCapHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            if sidebarVisible {
                expandedSidebar
                    .padding(.horizontal, ConductorTokens.Space.sidebarX)
                    .transition(ConductorMotion.sidebarContentTransition)
            } else {
                collapsedSidebar
                    .frame(width: ConductorDesign.sidebarCollapsedBodyWidth, alignment: .center)
                    .transition(ConductorMotion.sidebarContentTransition)
            }
        }
        .padding(.top, ConductorTokens.Space.sidebarTop)
        .padding(.bottom, ConductorTokens.Space.sidebarBottom)
        .frame(width: sidebarVisible ? ConductorDesign.sidebarWidth(for: appearance) : ConductorDesign.sidebarCollapsedWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            SidebarRailSurface(theme: theme, clarity: appearance.chromeClarity, isCollapsed: !sidebarVisible)
        }
        .overlay {
            SidebarBookSpineChrome(
                collapsed: !sidebarVisible,
                theme: theme,
                clarity: appearance.chromeClarity
            )
            .allowsHitTesting(false)
        }
        .clipShape(SidebarRailShape())
        .animation(model.shellAnimation(ConductorMotion.layout), value: sidebarVisible)
        .animation(model.shellAnimation(ConductorMotion.standard), value: theme)
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        if sidebarVisible {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    WindowControlButtons(spacing: 8)
                    Spacer(minLength: 8)
                    sidebarToggleButton
                }
                .padding(.horizontal, ConductorTokens.Space.sidebarX + 4)
                .padding(.top, 14)
            }
            .frame(height: sidebarHeaderHeight, alignment: .top)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    WindowControlButtons(spacing: 6)
                    Spacer()
                }
                .padding(.top, 16)
            }
            .frame(height: sidebarHeaderHeight, alignment: .top)
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            finishWorkspaceRenameIfNeeded()
            model.sidebarVisible.toggle()
        } label: {
            Image(systemName: sidebarVisible ? "chevron.left" : "sidebar.left")
                .font(.conductorSystem(size: 11.5, weight: .bold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 26, height: 24)
                .background(sidebarToggleFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
        .buttonStyle(ConductorPressButtonStyle())
        .accessibilityLabel(sidebarVisible ? L("收起侧边栏", "Collapse Sidebar") : L("展开侧边栏", "Expand Sidebar"))
        .conductorHover($sidebarToggleHovering)
        .macNativeTooltip(sidebarVisible ? L("收起侧边栏", "Collapse Sidebar") : L("展开侧边栏", "Expand Sidebar"))
    }

    private var sidebarToggleFill: Color {
        if sidebarToggleHovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.95 : 0.70)
        }
        return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.36 : 0.18)
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            workspaceSection
                .frame(maxHeight: .infinity)

            tokenRecordsSidebarEntry

            Spacer(minLength: 8)

            expandedSidebarDock
        }
        .frame(maxHeight: .infinity)
    }

    private var expandedSidebarDock: some View {
        SidebarDockSurface {
            HStack(spacing: 6) {
                SidebarDockButton(id: "sidebar-dock.new-terminal", icon: "plus.rectangle.on.rectangle", help: commandTooltip(L("新开终端", "New Terminal"), command: .newTerminal, fallback: "Cmd-T")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newTerminal)
                }
                SidebarDockButton(id: "sidebar-dock.command-palette", icon: "command", help: commandTooltip(L("打开命令面板", "Open Command Palette"), command: .toggleCommandPalette, fallback: "Cmd-K")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.toggleCommandPalette)
                }
                Spacer(minLength: 0)
                SidebarDockButton(id: "sidebar-dock.settings", icon: "gearshape", help: commandTooltip(L("设置", "Settings"), command: .toggleSettings, fallback: "Cmd-,")) {
                    finishWorkspaceRenameIfNeeded()
                    ConductorMotion.perform(ConductorMotion.panel) {
                        model.performCommand(.toggleSettings)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.bottom, 3)
    }

    private var tokenRecordsSidebarEntry: some View {
        SidebarDockSurface(horizontalPadding: 0) {
            TokenRecordsSidebarCard {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.openTokenRecords)
            }
        }
    }

    private func commandTooltip(_ title: String, command: ConductorShellCommand, fallback: String) -> String {
        "\(title) \(model.shortcutTitle(for: command, fallback: fallback))"
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SidebarSectionTitle(L("工作区", "Workspaces"))
                SidebarWorkspaceHeaderStats(
                    splitCount: snapshot.currentSplitCount,
                    terminalCount: snapshot.currentTerminalCount,
                    activeAgentCount: snapshot.currentActiveAgentCount
                )
                Spacer()
                Button {
                    ConductorMotion.perform(ConductorMotion.list) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.newWorkspace)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(ConductorPressButtonStyle())
                .accessibilityLabel(commandTooltip(L("新建工作区", "New Workspace"), command: .newWorkspace, fallback: "Cmd-N"))
                .macNativeTooltip(commandTooltip(L("新建工作区", "New Workspace"), command: .newWorkspace, fallback: "Cmd-N"))
            }
            .padding(.trailing, 5)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(snapshot.rows) { row in
                        workspaceRow(for: row)
                            .id(row.id)
                            .transition(ConductorMotion.rowTransition(itemCount: snapshot.rows.count))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 2)
            }
            .mask(ConductorVerticalFadeMask(fadesTop: false))
            .frame(minHeight: 72, maxHeight: .infinity)
            .animation(nil, value: snapshot.selectedWorkspaceID)
            .animation(model.shellAnimation(ConductorMotion.list(itemCount: snapshot.rows.count)), value: snapshot.workspaceIDs)
        }
    }

    private var collapsedSidebar: some View {
        VStack(spacing: 6) {
            SidebarRailButton(
                id: "sidebar-rail.toggle-sidebar",
                icon: "sidebar.left",
                help: L("展开侧边栏", "Expand Sidebar"),
                namespace: railSelectionNamespace
            ) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.sidebarVisible.toggle()
                }
            }
            .padding(.top, 4)

            CollapsedRailSeparator()

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(snapshot.rows) { row in
                        SidebarRailButton(
                            id: "sidebar-rail.workspace.\(row.id)",
                            icon: WorkspaceChromeGlyph.systemName(selected: row.selected),
                            selected: row.selected,
                            activeAgentCount: row.activeAgentCount,
                            unreadCount: row.unreadCount,
                            help: workspaceTooltip(for: row),
                            namespace: railSelectionNamespace
                        ) {
                            withoutShellAnimation {
                                model.activateWorkspace(row.id, source: .sidebar)
                            }
                        }
                        .id(row.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .mask(ConductorVerticalFadeMask(fadesTop: false))
            .frame(maxHeight: .infinity)

            CollapsedRailSeparator()

            collapsedSidebarActions

            Spacer(minLength: 8)

            collapsedSidebarFooter
        }
    }

    private var collapsedSidebarActions: some View {
        VStack(spacing: 8) {
            SidebarRailButton(
                id: "sidebar-rail.new-terminal",
                icon: "plus.rectangle.on.rectangle",
                help: commandTooltip(L("新开终端", "New Terminal"), command: .newTerminal, fallback: "Cmd-T"),
                namespace: railSelectionNamespace
            ) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.newTerminal)
            }
            SidebarRailButton(
                id: "sidebar-rail.command-palette",
                icon: "command",
                help: commandTooltip(L("打开命令面板", "Open Command Palette"), command: .toggleCommandPalette, fallback: "Cmd-K"),
                namespace: railSelectionNamespace
            ) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
            SidebarRailButton(
                id: "sidebar-rail.token-records",
                icon: "chart.bar.fill",
                help: commandTooltip(L("Token 记录", "Token Records"), command: .openTokenRecords, fallback: "Usage"),
                namespace: railSelectionNamespace
            ) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.openTokenRecords)
            }
        }
    }

    private var collapsedSidebarFooter: some View {
        VStack(spacing: 0) {
            SidebarRailButton(
                id: "sidebar-rail.settings",
                icon: "gearshape",
                help: commandTooltip(L("设置", "Settings"), command: .toggleSettings, fallback: "Cmd-,"),
                namespace: railSelectionNamespace
            ) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.panel) {
                    model.performCommand(.toggleSettings)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var themeMenuItems: some View {
        ForEach(TerminalTheme.allCases) { theme in
            Button(theme.title) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.selection) {
                    model.theme = theme
                }
            }
        }
    }

    private func workspaceRow(for row: WorkspaceChromeDisplayModel) -> some View {
        WorkspaceSidebarRow(
            title: row.title,
            subtitle: row.subtitle,
            splitCount: row.splitCount,
            terminalCount: row.terminalCount,
            activeAgentCount: row.activeAgentCount,
            unreadCount: row.unreadCount,
            metadata: row.metadata,
            selected: row.selected,
            visuallySelected: row.selected,
            selectionNamespace: sidebarSelectionNamespace,
            editing: renamingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onCommitRename: commitWorkspaceRename,
            onCancelRename: cancelWorkspaceRename
        ) {
            finishWorkspaceRenameIfNeeded(except: row.id)
            withoutShellAnimation {
                model.activateWorkspace(row.id, source: .sidebar)
            }
        } onRename: {
            finishWorkspaceRenameIfNeeded(except: row.id)
            beginRenameWorkspace(row)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macNativeTooltip(workspaceTooltip(for: row))
        .contextMenu {
            Button(L("重命名工作区...", "Rename Workspace...")) {
                ConductorMotion.perform(ConductorMotion.selection) {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    beginRenameWorkspace(row)
                }
            }
            Button(L("复制工作区", "Duplicate Workspace")) {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.activateWorkspace(row.id, source: .sidebar)
                    model.performCommand(.duplicateWorkspace)
                }
            }
            if row.metadata?.rootPath != nil || row.metadata?.runningPorts.isEmpty == false {
                Divider()
            }
            if row.metadata?.rootPath != nil {
                Button(L("在 Finder 打开根目录", "Open Root in Finder")) {
                    withoutShellAnimation {
                        finishWorkspaceRenameIfNeeded(except: row.id)
                        model.activateWorkspace(row.id, source: .sidebar)
                        model.performCommand(.openCurrentWorkspaceRoot)
                    }
                }
            }
            if let port = row.metadata?.runningPorts.first {
                Button(L("打开端口 :\(port)", "Open Port :\(port)")) {
                    withoutShellAnimation {
                        finishWorkspaceRenameIfNeeded(except: row.id)
                        model.activateWorkspace(row.id, source: .sidebar)
                        model.performCommand(.openCurrentWorkspaceFirstService)
                    }
                }
            }
            Divider()
            Button(L("关闭其他工作区", "Close Other Workspaces")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.activateWorkspace(row.id, source: .sidebar)
                    model.performCommand(.closeOtherWorkspaces)
                }
            }
            .disabled(!snapshot.canCloseWorkspace)
            Button(L("关闭右侧工作区", "Close Workspaces to the Right")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.activateWorkspace(row.id, source: .sidebar)
                    model.performCommand(.closeWorkspacesToRight)
                }
            }
            .disabled(!canCloseWorkspacesToRight(of: row.id))
            Divider()
            Button(L("关闭工作区", "Close Workspace")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.activateWorkspace(row.id, source: .sidebar)
                    model.performCommand(.closeCurrentWorkspace)
                }
            }
            .disabled(!snapshot.canCloseWorkspace)
        }
    }

    private func workspaceTooltip(for row: WorkspaceChromeDisplayModel) -> String {
        var lines = [row.title]
        if let project = row.metadata?.projectName,
           project != row.title {
            lines.append(L("项目：\(project)", "Project: \(project)"))
        }
        if let root = row.metadata?.rootPath {
            lines.append(L("路径：\(root)", "Path: \(root)"))
        } else {
            lines.append(row.subtitle)
        }
        lines.append(L("\(row.splitCount) 分屏 · \(row.terminalCount) 终端", "\(row.splitCount) panes · \(row.terminalCount) terminals"))
        if let metadata = row.metadata {
            if metadata.runningPorts.isEmpty {
                lines.append(L("端口：未检测到运行中的服务", "Ports: no running service detected"))
            } else {
                let ports = metadata.runningPorts.prefix(4).map { ":\($0)" }.joined(separator: " ")
                lines.append(L("端口：\(ports)", "Ports: \(ports)"))
            }
            if metadata.health != "ok" {
                lines.append(L("状态：\(metadata.health)", "Health: \(metadata.health)"))
            }
        }
        if row.activeAgentCount > 0 {
            lines.append(L("\(row.activeAgentCount) 个 AI 终端运行中", "\(row.activeAgentCount) AI terminals running"))
        }
        if row.unreadCount > 0 {
            lines.append(L("\(row.unreadCount) 条未读通知", "\(row.unreadCount) unread notifications"))
        }
        return lines.joined(separator: "\n")
    }

    private func canCloseWorkspacesToRight(of workspaceID: WorkspaceID) -> Bool {
        guard let index = snapshot.workspaceIDs.firstIndex(of: workspaceID) else { return false }
        return index < snapshot.workspaceIDs.count - 1
    }

    private func beginRenameWorkspace(_ row: WorkspaceChromeDisplayModel) {
        workspaceTitleDraft = row.title
        renamingWorkspaceID = row.id
    }

    private func commitWorkspaceRename() {
        if let renamingWorkspaceID {
            ConductorMotion.perform(ConductorMotion.selection) {
                model.renameWorkspace(renamingWorkspaceID, title: workspaceTitleDraft)
            }
        }
        renamingWorkspaceID = nil
    }

    private func finishWorkspaceRenameIfNeeded(except workspaceID: WorkspaceID? = nil) {
        guard let renamingWorkspaceID,
              renamingWorkspaceID != workspaceID else {
            return
        }
        commitWorkspaceRename()
    }

    private func cancelWorkspaceRename() {
        renamingWorkspaceID = nil
    }

}

private struct SidebarRailShape: InsettableShape {
    var bottomLeadingRadius: CGFloat = ConductorDesign.sidebarCornerRadius
    var bottomTrailingRadius: CGFloat = 0
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return uniformPath(in: r)
    }

    private func uniformPath(in r: CGRect) -> Path {
        let leading = min(bottomLeadingRadius, r.width / 2, r.height / 2)
        let trailing = min(bottomTrailingRadius, r.width / 2, r.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - trailing))
        if trailing > 0 {
            path.addQuadCurve(
                to: CGPoint(x: r.maxX - trailing, y: r.maxY),
                control: CGPoint(x: r.maxX, y: r.maxY)
            )
        }
        path.addLine(to: CGPoint(x: r.minX + leading, y: r.maxY))
        path.addQuadCurve(
            to: CGPoint(x: r.minX, y: r.maxY - leading),
            control: CGPoint(x: r.minX, y: r.maxY)
        )
        path.addLine(to: CGPoint(x: r.minX, y: r.minY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> SidebarRailShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}

private struct SidebarRailSurface: View {
    let theme: TerminalTheme
    let clarity: ChromeClarity
    let isCollapsed: Bool

    var body: some View {
        let shape = SidebarRailShape()
        
        ZStack {
            shape
                .fill(theme.shellPanelBackground)

            if theme.chromeMaterial.glassIntensity > 0 {
                shape
                    .fill(Color.white.opacity(theme.chromeMaterial.highlightOpacity * 0.32))
                    .blendMode(.screen)
                shape
                    .fill(theme.shellControlFill.opacity(theme.chromeMaterial.glassIntensity * 0.22))
            }

            if isCollapsed {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme.usesDarkChrome ? 0.018 : 0.05),
                                Color.clear,
                                Color.black.opacity(theme.usesDarkChrome ? 0.018 : 0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.overlay)
            }
        }
        .overlay {
            shape
                .strokeBorder(
                    LinearGradient(
                            colors: [
                            Color.white.opacity((theme.usesDarkChrome ? 0.07 : 0.24) * theme.chromeMaterial.strokeOpacityBoost),
                            theme.shellStroke.opacity((theme.usesDarkChrome ? 0.12 : 0.08) * theme.chromeMaterial.strokeOpacityBoost),
                            Color.black.opacity(theme.usesDarkChrome ? 0.06 : 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
        .shadow(color: Color.black.opacity(theme.chromeMaterial.shadowOpacity), radius: 12, x: 0, y: 2)
    }
}

private struct SidebarBookSpineChrome: View {
    let collapsed: Bool
    let theme: TerminalTheme
    let clarity: ChromeClarity

    var body: some View {
        Color.clear
    }
}

struct WorkspaceChromeSnapshot: Equatable {
    let selectedWorkspaceID: WorkspaceID
    let selectedWorkspaceFileTabID: String?
    let selectedWorkspaceWebTabID: WebTabID?
    let rows: [WorkspaceChromeDisplayModel]
    let workspaceIDs: [WorkspaceID]
    let fileTabs: [WorkspaceFileTabDisplayModel]
    let webTabs: [WorkspaceWebTabDisplayModel]
    let currentSplitCount: Int
    let currentTerminalCount: Int
    let currentActiveAgentCount: Int
    let canCloseWorkspace: Bool

    @MainActor
    init(model: ConductorWindowModel) {
        RenderCounter.increment("workspace-chrome-snapshot")
        let selectedWorkspaceID = model.workspace.id
        let metadataSnapshot = model.metadataByTerminalID
        let workspaceMetadata = model.workspaceMetadataSnapshots
        let rows = model.workspaces.map { workspace in
            let metadata = workspaceMetadata[workspace.id]
            return WorkspaceChromeDisplayModel(
                id: workspace.id,
                title: workspace.title,
                subtitle: Self.workspaceSubtitle(workspace, metadata: metadataSnapshot, workspaceMetadata: metadata),
                splitCount: workspace.panes.count,
                terminalCount: Self.workspaceTerminalCount(workspace),
                activeAgentCount: Self.workspaceActiveAgentCount(workspace, metadata: metadataSnapshot),
                unreadCount: model.attentionUnreadCount(for: workspace.id),
                metadata: metadata,
                selected: workspace.id == selectedWorkspaceID
            )
        }
        let selectedWorkspaceFileTabID = model.selectedWorkspaceFileTab?.id
        let selectedWorkspaceWebTabID = model.selectedWorkspaceWebTab?.id

        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedWorkspaceFileTabID = selectedWorkspaceFileTabID
        self.selectedWorkspaceWebTabID = selectedWorkspaceWebTabID
        self.rows = rows
        self.workspaceIDs = rows.map(\.id)
        self.fileTabs = model.workspaceFileTabs.map { tab in
            WorkspaceFileTabDisplayModel(
                tab: tab,
                selected: tab.id == selectedWorkspaceFileTabID,
                dirty: model.isWorkspaceFileTabDirty(tab.id)
            )
        }
        self.webTabs = model.workspaceWebTabs.map { tab in
            WorkspaceWebTabDisplayModel(
                tab: tab,
                selected: tab.id == selectedWorkspaceWebTabID
            )
        }
        self.currentSplitCount = model.workspace.panes.count
        self.currentTerminalCount = Self.workspaceTerminalCount(model.workspace)
        self.currentActiveAgentCount = Self.workspaceActiveAgentCount(model.workspace, metadata: metadataSnapshot)
        self.canCloseWorkspace = model.workspaces.count > 1
    }

    private static func workspaceTerminalCount(_ workspace: WorkspaceState) -> Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private static func workspaceActiveAgentCount(
        _ workspace: WorkspaceState,
        metadata: [TerminalID: TerminalDisplayMetadata]
    ) -> Int {
        workspace.panes.values.reduce(0) { count, pane in
            count + pane.tabs.filter { metadata[$0.id]?.hasActiveAgent == true }.count
        }
    }

    private static func workspaceSubtitle(
        _ workspace: WorkspaceState,
        metadata: [TerminalID: TerminalDisplayMetadata],
        workspaceMetadata: WorkspaceMetadataSnapshot?
    ) -> String {
        if let rootPath = workspaceMetadata?.rootPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rootPath.isEmpty {
            return abbreviatedPath(rootPath)
        }
        let selectedTab = workspace.focusedPane?.selectedTab
        if let terminalID = selectedTab?.id,
           let directory = metadata[terminalID]?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directory.isEmpty {
            return abbreviatedPath(directory)
        }
        if let directory = selectedTab?.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directory.isEmpty {
            return abbreviatedPath(directory)
        }
        if let directory = workspace.panes.values.lazy
            .flatMap({ $0.tabs })
            .compactMap({ $0.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return abbreviatedPath(directory)
        }
        return selectedTab?.title ?? L("等待终端", "Waiting for terminal")
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalized = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 2 else { return normalized }
        if normalized.hasPrefix("~/") {
            return "~/" + components.suffix(2).joined(separator: "/")
        }
        return ".../" + components.suffix(2).joined(separator: "/")
    }
}

struct WorkspaceChromeDisplayModel: Identifiable, Equatable {
    let id: WorkspaceID
    let title: String
    var subtitle: String = ""
    let splitCount: Int
    let terminalCount: Int
    let activeAgentCount: Int
    let unreadCount: Int
    let metadata: WorkspaceMetadataSnapshot?
    let selected: Bool
}

struct WorkspaceFileTabDisplayModel: Identifiable, Equatable {
    var id: String { tab.id }
    let tab: ConductorWorkspaceFileTab
    let selected: Bool
    let dirty: Bool
}

struct WorkspaceWebTabDisplayModel: Identifiable, Equatable {
    var id: WebTabID { tab.id }
    let tab: WorkspaceWebTabState
    let selected: Bool
}

enum WorkspaceChromeGlyph {
    static func systemName(selected: Bool) -> String {
        return selected ? "square.grid.2x2.fill" : "square.grid.2x2"
    }
}

private struct SidebarWorkspaceHeaderStats: View {
    let splitCount: Int
    let terminalCount: Int
    let activeAgentCount: Int
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            metric(systemImage: "rectangle.split.2x1", value: splitCount, help: L("当前工作区分屏数", "Panes in current workspace"))
            metric(systemImage: "terminal", value: terminalCount, help: L("当前工作区终端数", "Terminals in current workspace"))
            if activeAgentCount > 0 {
                agentMetric(count: activeAgentCount)
            }

        }
        .padding(.leading, 3)
        .accessibilityHidden(true)
    }

    private func metric(
        systemImage: String,
        value: Int,
        emphasis: Bool = false,
        help: String
    ) -> some View {
        metric(systemImage: systemImage, valueText: "\(value)", emphasis: emphasis, help: help)
    }

    private func metric(
        systemImage: String,
        valueText: String,
        emphasis: Bool = false,
        help: String
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .accessibilityHidden(true)
            Text(valueText)
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
        }
        .foregroundStyle(emphasis ? theme.floatingEmphasis : theme.shellChromeTextMuted.opacity(0.72))
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(emphasis ? theme.shellSelectedFill.opacity(0.90) : theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
        .clipShape(Capsule())
        .macNativeTooltip(help)
    }

    private func agentMetric(count: Int) -> some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.floatingEmphasis)
                .scaleEffect(0.48)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(count > 99 ? "99+" : "\(count)")
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
        }
        .foregroundStyle(theme.floatingEmphasis)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(theme.shellSelectedFill.opacity(0.90))
        .clipShape(Capsule())
        .macNativeTooltip(L("AI 终端运行中", "AI terminal running"))
    }
}

private struct TokenRecordsSidebarCard: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.86))
                    .frame(width: 22, height: 22)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Token 记录", "Token Records"))
                        .font(.conductorSystem(size: 11.7, weight: .semibold, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText)
                        .lineLimit(1)
                    Text(L("用量详情", "Usage details"))
                        .font(.conductorSystem(size: 9.8, weight: .medium, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.66))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(hovering ? 0.78 : 0.50))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(theme.shellStroke.opacity(hovering ? 0.34 : 0.18), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .conductorHover($hovering)
        .macNativeTooltip(L("打开 Token 记录", "Open Token Records"))
    }

    private var iconFill: Color {
        hovering ? theme.shellHoverFill.opacity(0.62) : theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.30)
    }

    private var cardFill: Color {
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.58 : 0.46)
        }
        return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.20 : 0.12)
    }
}

private struct SidebarDockButton: View {
    let id: String
    let icon: String
    var disabled = false
    let help: String
    let action: () -> Void

    var body: some View {
        ConductorIconButton(
            state: ConductorControlState(
                id: id,
                systemImage: icon,
                isEnabled: !disabled,
                tooltip: help,
                accessibilityLabel: help
            ),
            variant: .sidebarDock,
            action: action
        )
    }
}

private struct CollapsedRailSeparator: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        LinearGradient(
            colors: [
                Color.clear,
                theme.shellStroke.opacity(theme.usesDarkChrome ? 0.38 : 0.22),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }
}

private struct SidebarDockSurface<Content: View>: View {
    var horizontalPadding: CGFloat = 2
    @ViewBuilder var content: Content
    @Environment(\.conductorTheme) private var theme

    init(horizontalPadding: CGFloat = 2, @ViewBuilder content: () -> Content) {
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 7) {
            Rectangle()
                .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.18 : 0.14))
                .frame(height: 1)
                .padding(.horizontal, horizontalPadding == 0 ? 9 : 4)

            content
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, 2)
    }
}

private struct SidebarRailButton: View {
    let id: String
    let icon: String
    var selected = false
    var disabled = false
    var activeAgentCount = 0
    var unreadCount = 0
    let help: String
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            action()
        }) {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.18 : 0.11))
                }

                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovering ? theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.44 : 0.30) : Color.clear)
                    .animation(ConductorMotion.hover, value: hovering)

                Image(systemName: icon)
                    .font(.conductorSystem(size: 13, weight: selected ? .bold : .semibold, scale: fontScale))
                    .foregroundStyle(
                        selected ? theme.floatingEmphasis : (hovering ? theme.shellChromeText.opacity(0.92) : ConductorDesign.secondaryText)
                    )
                    .scaleEffect(hovering ? 1.04 : 1.0)
                    .animation(ConductorMotion.hover, value: hovering)

                if activeAgentCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.floatingEmphasis)
                        .scaleEffect(0.44)
                        .frame(width: 11, height: 11)
                        .padding(3)
                        .background(theme.shellPanelBackground.opacity(0.94))
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .accessibilityHidden(true)
                }

                if unreadCount > 0 {
                    SidebarRailUnreadBadge(count: unreadCount)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.shellStroke.opacity(selected ? 0.24 : 0.12), lineWidth: 0.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.95))
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .macNativeTooltip(help)
        .accessibilityLabel(help)
        .conductorHover($hovering)
    }
}

private struct SidebarRailUnreadBadge: View {
    let count: Int
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var title: String {
        count > 99 ? "99+" : "\(count)"
    }

    private var foreground: Color {
        theme.usesDarkChrome ? Color.white.opacity(0.95) : theme.floatingEmphasis
    }

    private var fill: Color {
        theme.shellPanelBackground.opacity(theme.usesDarkChrome ? 0.98 : 0.94)
    }

    var body: some View {
        Text(title)
            .font(.conductorSystem(size: 7.5, weight: .black, scale: fontScale))
            .monospacedDigit()
            .foregroundStyle(foreground)
            .padding(.horizontal, count > 9 ? 3.5 : 4)
            .frame(minWidth: 13)
            .frame(height: 13)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(theme.floatingEmphasis.opacity(0.55), lineWidth: 0.7))
    }
}

struct SidebarSectionTitle: View {
    let title: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.74))
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }
}

private struct WorkspaceSidebarRow: View {
    let title: String
    let subtitle: String
    let splitCount: Int
    let terminalCount: Int
    let activeAgentCount: Int
    let unreadCount: Int
    let metadata: WorkspaceMetadataSnapshot?
    let selected: Bool
    let visuallySelected: Bool
    let selectionNamespace: Namespace.ID
    let editing: Bool
    @Binding var titleDraft: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let action: () -> Void
    let onRename: () -> Void
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
    }

    var body: some View {
        Group {
            if editing {
                editingRow
                    .transition(.identity)
            } else {
                displayTab
                    .transition(.identity)
            }
        }
        .frame(height: editing ? 32 : 46)
        .background {
            sidebarRowBackground
        }
        .clipShape(rowShape)
        .contentShape(rowShape)
        .animation(nil, value: editing)
        .animation(ConductorMotion.emphasized, value: activeAgentCount)
        .animation(ConductorMotion.selection, value: unreadCount)
        .frame(maxWidth: .infinity, alignment: .leading)
        .conductorHover($hovering)
    }

    private var editingRow: some View {
        HStack(spacing: 7) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: true))
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .frame(width: 14)
                .foregroundStyle(selected ? theme.floatingEmphasis.opacity(0.90) : ConductorDesign.secondaryText)
            RenameTextField(
                text: $titleDraft,
                placeholder: L("工作区名称", "Workspace Name"),
                font: .conductorSystemFont(ofSize: 12, weight: .semibold, scale: fontScale),
                textColor: NSColor(theme.shellChromeText),
                onCommit: onCommitRename,
                onCancel: onCancelRename
            )
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear {
            renameCancelled = false
        }
    }

    private var displayTab: some View {
        Button(action: action) {
            WorkspaceSidebarRowContent(
                title: title,
                subtitle: subtitle,
                splitCount: splitCount,
                terminalCount: terminalCount,
                activeAgentCount: activeAgentCount,
                unreadCount: unreadCount,
                metadata: metadata,
                selected: selected,
                themeID: theme.id,
                fontScaleID: fontScale.id
            )
            .equatable()
            .padding(.leading, 7)
            .padding(.trailing, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(rowShape)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .buttonStyle(ConductorPressButtonStyle())
    }

    private var sidebarRowBackground: some View {
        return ZStack {
            rowShape
                .fill(hovering ? theme.shellHoverFill.opacity(0.64) : Color.clear)
            if visuallySelected {
                rowShape
                    .fill(theme.shellSelectedFill.opacity(theme.usesDarkChrome ? 0.90 : 0.74))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct WorkspaceSidebarRowContent: View, Equatable {
    let title: String
    let subtitle: String
    let splitCount: Int
    let terminalCount: Int
    let activeAgentCount: Int
    let unreadCount: Int
    let metadata: WorkspaceMetadataSnapshot?
    let selected: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceSidebarRowContent, rhs: WorkspaceSidebarRowContent) -> Bool {
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
            lhs.splitCount == rhs.splitCount &&
            lhs.terminalCount == rhs.terminalCount &&
            lhs.activeAgentCount == rhs.activeAgentCount &&
            lhs.unreadCount == rhs.unreadCount &&
            lhs.metadata == rhs.metadata &&
            lhs.selected == rhs.selected &&
            lhs.themeID == rhs.themeID &&
            lhs.fontScaleID == rhs.fontScaleID
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                .font(.conductorSystem(size: 11, weight: .bold, scale: fontScale))
                .foregroundStyle(selected ? Color.white.opacity(0.96) : theme.shellChromeTextMuted.opacity(0.62))
                .frame(width: 20, height: 20)
                .background(selected ? theme.shellControlRaisedFill.opacity(0.44) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.conductorSystem(size: 12, weight: selected ? .semibold : .medium, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(selected ? 0.94 : 0.84))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if unreadCount > 0 {
                        unreadMetric(count: unreadCount)
                    }
                    if activeAgentCount > 0 {
                        agentMetric(count: activeAgentCount)
                    }
                    if let health = metadata?.health,
                       health != "ok" {
                        healthMetric(health)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
                        .accessibilityHidden(true)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(workspaceMetaText)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.shellChromeTextMuted.opacity(selected ? 0.72 : 0.58))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var workspaceMetaText: String {
        var pieces = [
            L("\(splitCount) 分屏", "\(splitCount) panes"),
            L("\(terminalCount) 终端", "\(terminalCount) terminals")
        ]
        if let port = metadata?.runningPorts.first {
            pieces.append(":\(port)")
        }
        return "· " + pieces.joined(separator: " · ")
    }

    private func healthMetric(_ health: String) -> some View {
        Image(systemName: health == "metadata_partial" ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
            .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
            .foregroundStyle(theme.usesDarkChrome ? Color.orange.opacity(0.92) : Color.orange.opacity(0.82))
            .frame(width: 15, height: 15)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.18 : 0.10))
            .clipShape(Circle())
            .accessibilityLabel(L("工作区状态需要检查：\(health)", "Workspace needs attention: \(health)"))
    }

    private func agentMetric(count: Int) -> some View {
        HStack(spacing: 3) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.floatingEmphasis)
                .scaleEffect(0.42)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
            Text(count > 99 ? "99+" : "\(count)")
                .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                .monospacedDigit()
        }
        .foregroundStyle(theme.floatingEmphasis)
        .padding(.horizontal, 4)
        .frame(height: 15)
        .background(selected ? theme.shellHoverFill.opacity(0.42) : theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.14 : 0.08))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(count) 个 AI 终端运行中", "\(count) AI terminals running"))
    }

    private func unreadMetric(count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.conductorSystem(size: 8.5, weight: .black, scale: fontScale))
            .monospacedDigit()
            .foregroundStyle(selected ? Color.white.opacity(0.96) : theme.floatingEmphasis)
            .padding(.horizontal, 4.5)
            .frame(height: 15)
            .background {
                Capsule()
                    .fill(selected ? theme.shellHoverFill.opacity(0.44) : theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.18 : 0.11))
            }
            .overlay {
                Capsule()
                    .stroke(theme.floatingEmphasis.opacity(selected ? 0.30 : 0.22), lineWidth: 0.6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(count) 条未读通知", "\(count) unread notifications"))
    }
}
