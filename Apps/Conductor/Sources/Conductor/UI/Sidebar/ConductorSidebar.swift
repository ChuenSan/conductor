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

    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }

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
        HStack(spacing: spacing) {
            ForEach(controls) { control in
                Button(action: control.action) {
                    Circle()
                        .fill(control.color)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.12), lineWidth: 0.7)
                        }
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .frame(width: 12, height: 12)
                .accessibilityLabel(control.accessibilityLabel)
                .macNativeTooltip(control.accessibilityLabel)
            }
        }
        .frame(height: 16)
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
                    WindowControlButtons(spacing: 6)
                    Spacer(minLength: 8)
                    sidebarToggleButton
                }
                .padding(.horizontal, ConductorTokens.Space.sidebarX)
                .padding(.top, 10)
            }
            .frame(height: sidebarHeaderHeight, alignment: .top)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    WindowControlButtons(spacing: 6)
                    Spacer()
                }
                .padding(.top, 12)
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
                ConductorMotion.perform(ConductorMotion.panel) {
                    ConductorUsageFeature.openTokenRecords(
                        style: tokenRecordsPanelStyle,
                        languageIdentifier: appearance.language.usageFeatureLanguageIdentifier)
                }
            }
        }
    }

    private var tokenRecordsPanelStyle: ConductorUsagePanelStyle {
        ConductorUsagePanelStyle(
            panelBase: theme.floatingPanelBase,
            panelWash: theme.floatingPanelWash,
            controlFill: theme.floatingControlFill,
            controlStrongFill: theme.floatingControlStrongFill,
            stroke: theme.floatingStroke,
            separator: theme.floatingSeparator,
            emphasis: theme.floatingEmphasis,
            primaryText: theme.shellChromeText,
            secondaryText: theme.shellChromeTextMuted.opacity(0.86),
            tertiaryText: theme.shellChromeTextMuted.opacity(0.64),
            usesDarkChrome: theme.usesDarkChrome)
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
                            help: row.title,
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
                help: L("Token 记录", "Token Records"),
                namespace: railSelectionNamespace
            ) {
                finishWorkspaceRenameIfNeeded()
                ConductorUsageFeature.openTokenRecords(
                    style: tokenRecordsPanelStyle,
                    languageIdentifier: appearance.language.usageFeatureLanguageIdentifier)
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
            if isCollapsed {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.08 : 0.05),
                                Color.clear,
                                theme.accent.opacity(theme.usesDarkChrome ? 0.05 : 0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: 6)
                    .offset(x: 2)
            }

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            theme.shellPanelBackground,
                            theme.shellPanelBackground.opacity(0.95),
                            theme.shellPanelStrong.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if isCollapsed {
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme.usesDarkChrome ? 0.04 : 0.08),
                                Color.clear,
                                Color.black.opacity(theme.usesDarkChrome ? 0.04 : 0.0)
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
                            Color.white.opacity(theme.usesDarkChrome ? 0.12 : 0.36),
                            theme.shellStroke.opacity(theme.usesDarkChrome ? 0.18 : 0.10),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.6
                )
        }
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

struct WorkspaceWebTabDisplayModel: Identifiable, Equatable {
    var id: WebTabID { tab.id }
    let tab: WorkspaceWebTabState
    let selected: Bool
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
}

private struct TokenRecordsSidebarCard: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.fill")
                    .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .frame(width: 26, height: 26)
                    .background(theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.18 : 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Token 记录", "Token Records"))
                        .font(.conductorSystem(size: 12.2, weight: .semibold, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText)
                        .lineLimit(1)
                    Text(L("用量详情", "Usage details"))
                        .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.62))
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.shellStroke.opacity(hovering ? 0.36 : 0.22), lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .conductorHover($hovering)
        .macNativeTooltip(L("打开 Token 记录", "Open Token Records"))
    }

    private var cardFill: Color {
        if hovering {
            return theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.72 : 0.54)
        }
        return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.26 : 0.16)
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
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var hovering = false
    @State private var pulseActive = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            action()
        }) {
            ZStack {
                // Shared matched geometry background bubble for active selection (fluid liquid selection)
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.28 : 0.18),
                                    theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.08 : 0.04)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .matchedGeometryEffect(id: "rail-selection-bubble", in: namespace)
                }

                // Hover highlight overlay background
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovering ? theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.65 : 0.45) : Color.clear)
                    .animation(ConductorMotion.hover, value: hovering)

                // High-precision specular inner glow
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(theme.usesDarkChrome ? 0.12 : 0.22),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }

                // Icon inside with creative styling & animations
                Image(systemName: icon)
                    .font(.conductorSystem(size: 13, weight: selected ? .bold : .semibold, scale: fontScale))
                    .foregroundStyle(
                        selected ? theme.floatingEmphasis : (hovering ? theme.shellChromeText.opacity(0.92) : ConductorDesign.secondaryText)
                    )
                    .scaleEffect(hovering ? 1.14 : 1.0)
                    .rotationEffect(.degrees(hovering && !selected ? -4 : 0)) // Elegant tilt on hover
                    .offset(y: hovering ? -0.5 : 0)
                    .shadow(color: selected ? theme.floatingEmphasis.opacity(pulseActive ? 0.50 : 0.25) : Color.clear, radius: hovering ? 4 : 2)
                    .animation(ConductorMotion.hover, value: hovering)
            }
            .frame(width: 34, height: 34)
            .background {
                // Glass-orb bounding ring
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme.usesDarkChrome ? 0.14 : 0.42),
                                Color.white.opacity(theme.usesDarkChrome ? 0.03 : 0.10),
                                theme.floatingEmphasis.opacity(selected ? 0.42 : 0.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: selected ? 1.0 : 0.7
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(
                color: selected ? theme.floatingEmphasis.opacity(pulseActive ? 0.32 : 0.16) : Color.black.opacity(hovering ? 0.08 : 0.03),
                radius: selected ? (pulseActive ? 8 : 4) : (hovering ? 4 : 2),
                x: 0,
                y: selected ? 2 : 1
            )
            .overlay(alignment: .leading) {
                // Elegant fluid liquid edge indicator on the left side
                if selected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(theme.floatingEmphasis)
                        .frame(width: 3, height: 14)
                        .matchedGeometryEffect(id: "rail-selection-edge-indicator", in: namespace)
                        .padding(.leading, 1.5)
                }
            }
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.95))
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .macNativeTooltip(help)
        .accessibilityLabel(help)
        .conductorHover($hovering)
        .onAppear {
            if selected {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulseActive = true
                }
            }
        }
        .onChange(of: selected) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulseActive = true
                }
            } else {
                pulseActive = false
            }
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
                unreadCount: unreadCount,
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
            lhs.themeID == rhs.themeID &&
            lhs.fontScaleID == rhs.fontScaleID
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                .font(.conductorSystem(size: 11, weight: .bold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : ConductorDesign.secondaryText)
                .frame(width: 22, height: 22)
                .background(selected ? theme.shellControlRaisedFill.opacity(0.84) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(selected ? 0.94 : 0.84))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
                        .accessibilityHidden(true)
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
                    workspaceMetric(
                        systemImage: "rectangle.split.2x1",
                        value: splitCount,
                        accessibilityLabel: L("\(splitCount) 个分屏", "\(splitCount) panes")
                    )
                    workspaceMetric(
                        systemImage: "terminal",
                        value: terminalCount,
                        accessibilityLabel: L("\(terminalCount) 个终端", "\(terminalCount) terminals")
                    )
                }
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 15)
                        .background(theme.floatingEmphasis)
                        .clipShape(Capsule())
                        .accessibilityLabel(L("\(unreadCount) 条未读通知", "\(unreadCount) unread notifications"))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func workspaceMetric(systemImage: String, value: Int, accessibilityLabel: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
                .monospacedDigit()
        }
        .foregroundStyle(theme.shellChromeTextMuted.opacity(selected ? 0.78 : 0.62))
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(selected ? theme.shellHoverFill.opacity(0.70) : theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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
        .conductorHover($hovering)
        .macNativeTooltip(help ?? title, enabled: !showsTitle)
    }
}
