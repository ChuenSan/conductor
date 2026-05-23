import AppKit
import ConductorCore
import SwiftUI

private func withoutShellAnimation(_ action: () -> Void) {
    ConductorMotion.withoutAnimation(action)
}

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

private struct WindowControlButtons: View {
    private let controls: [WindowControl] = [
        WindowControl(id: "close", color: Color(red: 1.0, green: 0.33, blue: 0.32), accessibilityLabel: L("关闭窗口", "Close Window")) {
            NSApp.keyWindow?.performClose(nil)
        },
        WindowControl(id: "minimize", color: Color(red: 1.0, green: 0.75, blue: 0.10), accessibilityLabel: L("最小化窗口", "Minimize Window")) {
            NSApp.keyWindow?.performMiniaturize(nil)
        },
        WindowControl(id: "fullscreen", color: Color(red: 0.14, green: 0.78, blue: 0.27), accessibilityLabel: L("切换全屏", "Toggle Full Screen")) {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(controls) { control in
                Button(action: control.action) {
                    Circle()
                        .fill(control.color)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.7)
                        }
                        .frame(width: 13, height: 13)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel)
                .macNativeTooltip(control.accessibilityLabel)
            }
        }
        .frame(height: 20)
    }
}

private struct WindowControl: Identifiable {
    let id: String
    let color: Color
    let accessibilityLabel: String
    let action: () -> Void
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
    @Environment(\.conductorFontScale) private var fontScale

    private var sidebarHeaderHeight: CGFloat {
        sidebarVisible ? 54 : 82
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            if sidebarVisible {
                expandedSidebar
                    .transition(ConductorMotion.sidebarContentTransition)
            } else {
                collapsedSidebar
                    .transition(ConductorMotion.sidebarContentTransition)
            }
        }
        .padding(.horizontal, sidebarVisible ? ConductorTokens.Space.sidebarX : 6)
        .padding(.top, ConductorTokens.Space.sidebarTop)
        .padding(.bottom, ConductorTokens.Space.sidebarBottom)
        .frame(width: sidebarVisible ? ConductorDesign.sidebarWidth(for: appearance) : ConductorDesign.sidebarCollapsedWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            SidebarRailSurface(theme: theme, clarity: appearance.chromeClarity)
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
                    WindowControlButtons()
                    Spacer(minLength: 8)
                    sidebarToggleButton
                }
                .padding(.top, 11)
            }
            .frame(height: sidebarHeaderHeight, alignment: .top)
        } else {
            VStack(spacing: 0) {
                WindowControlButtons()
                    .padding(.top, 11)
                Spacer(minLength: 0)
                sidebarToggleButton
            }
            .frame(maxWidth: .infinity)
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
        }
        .buttonStyle(ConductorPressButtonStyle())
        .onHover { value in
            sidebarToggleHovering = value
        }
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

            Spacer(minLength: 8)

            expandedSidebarDock
        }
        .frame(maxHeight: .infinity)
    }

    private var expandedSidebarDock: some View {
        SidebarDockSurface {
            HStack(spacing: 6) {
                SidebarDockButton(id: "sidebar-dock.new-terminal", icon: "plus.rectangle.on.rectangle", help: L("新开终端 Cmd-T", "New Terminal Cmd-T")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newTerminal)
                }
                SidebarDockButton(id: "sidebar-dock.command-center", icon: "command", help: L("打开命令面板 Cmd-K", "Open Command Center Cmd-K")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.toggleCommandPalette)
                }
                Spacer(minLength: 0)
                SidebarDockButton(id: "sidebar-dock.settings", icon: "gearshape", help: L("设置", "Settings")) {
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

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SidebarSectionTitle(L("工作区", "Workspaces"))
                SidebarWorkspaceHeaderStats(
                    splitCount: snapshot.currentSplitCount,
                    terminalCount: snapshot.currentTerminalCount,
                    unreadCount: snapshot.totalUnreadCount
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
                .macNativeTooltip(L("新建工作区 Cmd-N", "New Workspace Cmd-N"))
            }
            .padding(.trailing, 5)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(snapshot.rows) { row in
                        SidebarRailButton(
                            id: "sidebar-rail.workspace.\(row.id)",
                            icon: WorkspaceChromeGlyph.systemName(selected: row.selected),
                            selected: row.selected,
                            help: row.title
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

            SidebarSeparator()
                .padding(.horizontal, -1)

            collapsedSidebarActions

            Spacer(minLength: 8)

            collapsedSidebarFooter
        }
    }

    private var collapsedSidebarActions: some View {
        VStack(spacing: 6) {
            SidebarRailButton(id: "sidebar-rail.new-terminal", icon: "plus.rectangle.on.rectangle", help: L("新开终端 Cmd-T", "New Terminal Cmd-T")) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.newTerminal)
            }
            SidebarRailButton(id: "sidebar-rail.command-center", icon: "command", help: L("打开命令面板 Cmd-K", "Open Command Center Cmd-K")) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
        }
    }

    private var collapsedSidebarFooter: some View {
        VStack(spacing: 0) {
            SidebarRailButton(id: "sidebar-rail.settings", icon: "gearshape", help: L("设置", "Settings")) {
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
            unreadCount: row.unreadCount,
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
                    model.duplicateWorkspace(row.id)
                }
            }
            Divider()
            Button(L("关闭其他工作区", "Close Other Workspaces")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.closeOtherWorkspaces(keeping: row.id)
                }
            }
            .disabled(!snapshot.canCloseWorkspace)
            Button(L("关闭右侧工作区", "Close Workspaces to the Right")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspacesToRight(of: row.id)
                }
            }
            .disabled(!snapshot.canCloseWorkspace)
            Divider()
            Button(L("关闭工作区", "Close Workspace")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspace(row.id)
                }
            }
            .disabled(!snapshot.canCloseWorkspace)
        }
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
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let leading = min(bottomLeadingRadius, rect.width / 2, rect.height / 2)
        let trailing = min(bottomTrailingRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - trailing))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - trailing, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + leading, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - leading),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
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

    var body: some View {
        let shape = SidebarRailShape()
        shape
            .fill(theme.shellPanelBackground)
            .overlay {
                shape
                    .fill(theme.shellPanelBackground.opacity(clarity.glassTintMultiplier))
            }
            .overlay {
                shape
                    .fill(theme.usesDarkChrome ? theme.terminalBackground.opacity(0.18) : Color.white.opacity(0.16))
            }
            .overlay {
                LinearGradient(
                    colors: [
                        Color.white.opacity(theme.usesDarkChrome ? 0.018 : 0.18),
                        Color.clear,
                        theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.16 : 0.030)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(shape)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.16 : 0.055)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
            }
            .overlay {
                shape
                    .strokeBorder(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.15 : 0.070), lineWidth: 0.6)
            }
    }
}

private struct SidebarBookSpineChrome: View {
    let collapsed: Bool
    let theme: TerminalTheme
    let clarity: ChromeClarity

    var body: some View {
        ZStack {
            if collapsed {
                collapsedSpine
            } else {
                expandedSpine
            }
        }
    }

    private var collapsedSpine: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white.opacity(theme.usesDarkChrome ? 0.012 : 0.026),
                    Color.clear,
                    Color.black.opacity(theme.usesDarkChrome ? 0.034 : 0.012)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .opacity(0.46)
        }
    }

    private var expandedSpine: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(
                colors: [
                    Color.clear,
                    theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.075 : 0.032),
                    theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.080 : 0.022)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 16)
        }
        .opacity(0.46)
    }
}

struct WorkspaceChromeSnapshot: Equatable {
    let selectedWorkspaceID: WorkspaceID
    let selectedWorkspaceFileTabID: String?
    let rows: [WorkspaceChromeDisplayModel]
    let workspaceIDs: [WorkspaceID]
    let fileTabs: [WorkspaceFileTabDisplayModel]
    let currentSplitCount: Int
    let currentTerminalCount: Int
    let totalUnreadCount: Int
    let canCloseWorkspace: Bool

    @MainActor
    init(model: ConductorWindowModel) {
        RenderCounter.increment("workspace-chrome-snapshot")
        let selectedWorkspaceID = model.workspace.id
        let notificationSnapshot = model.notifications.snapshot
        let metadataSnapshot = model.metadataByTerminalID
        let rows = model.workspaces.map { workspace in
            WorkspaceChromeDisplayModel(
                id: workspace.id,
                title: workspace.title,
                subtitle: Self.workspaceSubtitle(workspace, metadata: metadataSnapshot),
                splitCount: workspace.panes.count,
                terminalCount: Self.workspaceTerminalCount(workspace),
                unreadCount: notificationSnapshot.unreadCount(for: workspace.id),
                selected: workspace.id == selectedWorkspaceID
            )
        }
        let selectedWorkspaceFileTabID = model.selectedWorkspaceFileTab?.id

        self.selectedWorkspaceID = selectedWorkspaceID
        self.selectedWorkspaceFileTabID = selectedWorkspaceFileTabID
        self.rows = rows
        self.workspaceIDs = rows.map(\.id)
        self.fileTabs = model.workspaceFileTabs.map { tab in
            WorkspaceFileTabDisplayModel(
                tab: tab,
                selected: tab.id == selectedWorkspaceFileTabID,
                dirty: model.isWorkspaceFileTabDirty(tab.id)
            )
        }
        self.currentSplitCount = model.workspace.panes.count
        self.currentTerminalCount = Self.workspaceTerminalCount(model.workspace)
        self.totalUnreadCount = notificationSnapshot.unreadCount
        self.canCloseWorkspace = model.workspaces.count > 1
    }

    private static func workspaceTerminalCount(_ workspace: WorkspaceState) -> Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private static func workspaceSubtitle(
        _ workspace: WorkspaceState,
        metadata: [TerminalID: TerminalDisplayMetadata]
    ) -> String {
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
    let unreadCount: Int
    let selected: Bool
}

struct WorkspaceFileTabDisplayModel: Identifiable, Equatable {
    var id: String { tab.id }
    let tab: ConductorWorkspaceFileTab
    let selected: Bool
    let dirty: Bool
}

enum WorkspaceChromeGlyph {
    static func systemName(selected: Bool) -> String {
        selected ? "square.grid.2x2.fill" : "square.grid.2x2"
    }
}

private struct SidebarWorkspaceHeaderStats: View {
    let splitCount: Int
    let terminalCount: Int
    let unreadCount: Int
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            metric(systemImage: "rectangle.split.2x1", value: splitCount, help: L("当前工作区分屏数", "Panes in current workspace"))
            metric(systemImage: "terminal", value: terminalCount, help: L("当前工作区终端数", "Terminals in current workspace"))

            if unreadCount > 0 {
                metric(systemImage: "bell", valueText: unreadCount > 99 ? "99+" : "\(unreadCount)", emphasis: true, help: L("未读通知", "Unread notifications"))
            }
        }
        .padding(.leading, 3)
        .accessibilityElement(children: .combine)
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

private struct SidebarSeparator: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.shellStroke.opacity(0.38))
            .frame(height: 1)
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
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
                .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.32 : 0.22))
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
    let help: String
    let action: () -> Void

    var body: some View {
        ConductorIconButton(
            state: ConductorControlState(
                id: id,
                systemImage: icon,
                isEnabled: !disabled,
                isActive: selected,
                tooltip: help,
                accessibilityLabel: help
            ),
            variant: .sidebarRail,
            action: action
        )
        .overlay {
            ConductorMagneticGlow(cornerRadius: 11, active: selected, lineWidth: 0.8)
                .opacity(selected ? 0.75 : 0)
                .allowsHitTesting(false)
        }
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

private struct SidebarRow: View {
    let icon: String
    let title: String
    let selected: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundStyle(selected ? theme.floatingEmphasis.opacity(0.90) : ConductorDesign.secondaryText)
            Text(title)
                .font(.conductorSystem(size: 12, weight: selected ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(selected ? 0.92 : 0.82))
            Spacer()
        }
        .padding(.horizontal, 7)
        .frame(height: 25)
        .background(selected ? theme.shellSelectedFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
    }
}

private struct WorkspaceSidebarRow: View {
    let title: String
    let subtitle: String
    let splitCount: Int
    let terminalCount: Int
    let unreadCount: Int
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
        .frame(height: editing ? 32 : 48)
        .background {
            sidebarRowBackground
        }
        .clipShape(rowShape)
        .contentShape(rowShape)
        .animation(nil, value: editing)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
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
                unreadCount: unreadCount,
                selected: selected,
                hovering: hovering,
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
                .fill(hovering ? theme.shellHoverFill : Color.clear)
            if visuallySelected {
                rowShape
                    .fill(theme.shellSelectedFill)
                    .matchedGeometryEffect(id: "sidebar-workspace-selection", in: selectionNamespace)
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
    let unreadCount: Int
    let selected: Bool
    let hovering: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceSidebarRowContent, rhs: WorkspaceSidebarRowContent) -> Bool {
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
            lhs.splitCount == rhs.splitCount &&
            lhs.terminalCount == rhs.terminalCount &&
            lhs.unreadCount == rhs.unreadCount &&
            lhs.selected == rhs.selected &&
            lhs.hovering == rhs.hovering &&
            lhs.themeID == rhs.themeID &&
            lhs.fontScaleID == rhs.fontScaleID
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                .font(.conductorSystem(size: 11, weight: .bold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : ConductorDesign.secondaryText)
                .frame(width: 22, height: 22)
                .background(selected ? theme.shellControlRaisedFill.opacity(0.84) : (hovering ? theme.shellHoverFill.opacity(0.62) : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(selected ? 0.94 : 0.84))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
                    Text(subtitle)
                        .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(theme.shellChromeTextMuted.opacity(selected ? 0.72 : 0.58))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    workspaceMetric(systemImage: "rectangle.split.2x1", value: splitCount)
                    workspaceMetric(systemImage: "terminal", value: terminalCount)
                }
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 15)
                        .background(theme.floatingEmphasis)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func workspaceMetric(systemImage: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
            Text("\(value)")
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
                .monospacedDigit()
        }
        .foregroundStyle(theme.shellChromeTextMuted.opacity(selected ? 0.78 : 0.62))
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(selected ? theme.shellHoverFill.opacity(0.70) : theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
        .clipShape(Capsule())
    }
}

private struct SidebarActionRow: View {
    let icon: String
    let title: String
    var showsTitle = true
    var disabled = false
    var help: String? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .frame(width: 14)
                if showsTitle {
                    Text(title)
                        .font(.conductorSystem(size: 12, weight: .medium, scale: fontScale))
                    Spacer()
                }
            }
            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.86))
            .padding(.horizontal, showsTitle ? 8 : 0)
            .frame(width: showsTitle ? nil : 34, height: showsTitle ? 28 : 34)
            .background(hovering ? theme.shellHoverFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: showsTitle ? ConductorTokens.Radius.row : 11))
            .contentShape(RoundedRectangle(cornerRadius: showsTitle ? ConductorTokens.Radius.row : 11))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .scaleEffect(hovering && !disabled ? (showsTitle ? 1.006 : 1.032) : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .macNativeTooltip(help ?? title, enabled: !showsTitle)
    }
}
