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

struct ConductorSidebar: View {
    let model: ConductorWindowModel
    let snapshot: WorkspaceChromeSnapshot
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let sidebarVisible: Bool
    @State private var renamingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""
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
        .background(.regularMaterial)
        .animation(model.shellAnimation(ConductorMotion.layout), value: sidebarVisible)
        .animation(model.shellAnimation(ConductorMotion.standard), value: theme)
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        if sidebarVisible {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    sidebarToggleButton
                }
                .padding(.horizontal, ConductorTokens.Space.sidebarX + 4)
                .padding(.top, 14)
            }
            .frame(height: sidebarHeaderHeight, alignment: .top)
        } else {
            Color.clear
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
                .frame(width: 26, height: 24)
                .accessibilityHidden(true)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(sidebarVisible ? L("收起侧边栏", "Collapse Sidebar") : L("展开侧边栏", "Expand Sidebar"))
        .help(sidebarVisible ? L("收起侧边栏", "Collapse Sidebar") : L("展开侧边栏", "Expand Sidebar"))
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
        HStack(spacing: 6) {
            ControlGroup {
                sidebarDockButton(icon: "plus.rectangle.on.rectangle", help: commandTooltip(L("新开终端", "New Terminal"), command: .newTerminal, fallback: "Cmd-T")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newTerminal)
                }
                sidebarDockButton(icon: "command", help: commandTooltip(L("打开命令面板", "Open Command Palette"), command: .toggleCommandPalette, fallback: "Cmd-K")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.toggleCommandPalette)
                }
                sidebarDockButton(icon: "chart.bar", help: L("打开 Token 记录", "Open Token Records")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.openTokenRecords)
                }
            }
            .controlSize(.small)

            Spacer(minLength: 0)

            ControlGroup {
                sidebarDockButton(icon: "gearshape", help: commandTooltip(L("设置", "Settings"), command: .toggleSettings, fallback: "Cmd-,")) {
                    finishWorkspaceRenameIfNeeded()
                    ConductorMotion.perform(ConductorMotion.panel) {
                        model.performCommand(.toggleSettings)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 3)
    }

    private func sidebarDockButton(
        icon: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(help, systemImage: icon)
        }
        .labelStyle(.iconOnly)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .help(help)
        .accessibilityLabel(help)
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
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(commandTooltip(L("新建工作区", "New Workspace"), command: .newWorkspace, fallback: "Cmd-N"))
                .help(commandTooltip(L("新建工作区", "New Workspace"), command: .newWorkspace, fallback: "Cmd-N"))
            }
            .padding(.trailing, 5)

            List(selection: selectedWorkspaceBinding) {
                ForEach(snapshot.rows) { row in
                    workspaceRow(for: row)
                        .id(row.id)
                        .tag(row.id)
                        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                        .listRowSeparator(.hidden)
                        .transition(ConductorMotion.rowTransition(itemCount: snapshot.rows.count))
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 72, maxHeight: .infinity)
            .animation(nil, value: snapshot.selectedWorkspaceID)
            .animation(model.shellAnimation(ConductorMotion.list(itemCount: snapshot.rows.count)), value: snapshot.workspaceIDs)
        }
    }

    private var selectedWorkspaceBinding: Binding<WorkspaceID?> {
        Binding(
            get: { snapshot.selectedWorkspaceID },
            set: { newValue in
                guard let newValue else { return }
                finishWorkspaceRenameIfNeeded(except: newValue)
                withoutShellAnimation {
                    model.activateWorkspace(newValue, source: .sidebar)
                }
            }
        )
    }

    private var collapsedSidebar: some View {
        VStack(spacing: 6) {
            sidebarRailButton(
                icon: "sidebar.left",
                help: L("展开侧边栏", "Expand Sidebar")
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
                        sidebarRailButton(
                            icon: WorkspaceChromeGlyph.systemName(selected: row.selected),
                            selected: row.selected,
                            activeAgentCount: row.activeAgentCount,
                            unreadCount: row.unreadCount,
                            help: workspaceTooltip(for: row)
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
            sidebarRailButton(
                icon: "plus.rectangle.on.rectangle",
                help: commandTooltip(L("新开终端", "New Terminal"), command: .newTerminal, fallback: "Cmd-T")
            ) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.newTerminal)
            }
            sidebarRailButton(
                icon: "command",
                help: commandTooltip(L("打开命令面板", "Open Command Palette"), command: .toggleCommandPalette, fallback: "Cmd-K")
            ) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
            sidebarRailButton(
                icon: "chart.bar.fill",
                help: commandTooltip(L("Token 记录", "Token Records"), command: .openTokenRecords, fallback: "Usage")
            ) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.openTokenRecords)
            }
        }
    }

    private var collapsedSidebarFooter: some View {
        VStack(spacing: 0) {
            sidebarRailButton(
                icon: "gearshape",
                help: commandTooltip(L("设置", "Settings"), command: .toggleSettings, fallback: "Cmd-,")
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

    private func sidebarRailButton(
        icon: String,
        selected: Bool = false,
        disabled: Bool = false,
        activeAgentCount: Int = 0,
        unreadCount: Int = 0,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !disabled else { return }
            action()
        } label: {
            Label {
                Text(help)
            } icon: {
                ZStack {
                    Image(systemName: icon)
                        .font(.conductorSystem(size: 13, weight: selected ? .bold : .semibold, scale: fontScale))
                        .foregroundStyle(selected ? theme.shellChromeText : ConductorDesign.secondaryText)

                    if activeAgentCount > 0 {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.floatingEmphasis)
                            .scaleEffect(0.44)
                            .frame(width: 11, height: 11)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .accessibilityHidden(true)
                    }

                    if unreadCount > 0 {
                        sidebarRailUnreadBadge(count: unreadCount)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selected ? theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.34 : 0.24) : Color.clear)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .help(help)
        .accessibilityLabel(help)
    }

    private func sidebarRailUnreadBadge(count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.conductorSystem(size: 7.5, weight: .black, scale: fontScale))
            .monospacedDigit()
            .foregroundStyle(theme.usesDarkChrome ? Color.primary.opacity(0.95) : theme.floatingEmphasis)
            .frame(minWidth: 13)
            .frame(height: 13)
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
            editing: renamingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onCommitRename: commitWorkspaceRename,
            onCancelRename: cancelWorkspaceRename
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(workspaceTooltip(for: row))
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
        Label {
            Text(valueText)
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
        } icon: {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(emphasis ? theme.floatingEmphasis : theme.shellChromeTextMuted.opacity(0.72))
        .frame(height: 16)
        .help(help)
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
        .frame(height: 16)
        .help(L("AI 终端运行中", "AI terminal running"))
    }
}

private struct CollapsedRailSeparator: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(ConductorTokens.Settings.subtleSeparator(dark: theme.usesDarkChrome))
            .frame(height: 1)
            .padding(.horizontal, 11)
            .padding(.vertical, 2)
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
    let editing: Bool
    @Binding var titleDraft: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

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
        .contentShape(Rectangle())
        .animation(nil, value: editing)
        .animation(ConductorMotion.emphasized, value: activeAgentCount)
        .animation(ConductorMotion.selection, value: unreadCount)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var displayTab: some View {
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
            Label {
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

                    Label {
                        HStack(spacing: 4) {
                            Text(subtitle)
                                .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(workspaceMetaText)
                                .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                                .lineLimit(1)
                        }
                    } icon: {
                        Image(systemName: "folder")
                            .font(.conductorSystem(size: 8.5, weight: .semibold, scale: fontScale))
                            .accessibilityHidden(true)
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(selected ? 0.72 : 0.58))
                }
            } icon: {
                Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                    .font(.conductorSystem(size: 11, weight: .bold, scale: fontScale))
                    .foregroundStyle(selected ? theme.shellChromeText.opacity(0.86) : theme.shellChromeTextMuted.opacity(0.62))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
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
        .frame(height: 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("\(count) 个 AI 终端运行中", "\(count) AI terminals running"))
    }

    private func unreadMetric(count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.conductorSystem(size: 8.5, weight: .black, scale: fontScale))
            .monospacedDigit()
            .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.floatingEmphasis)
            .frame(height: 15)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("\(count) 条未读通知", "\(count) unread notifications"))
    }
}
