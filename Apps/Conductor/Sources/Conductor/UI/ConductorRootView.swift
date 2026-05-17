import ConductorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConductorRootView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        HStack(alignment: .top, spacing: ConductorDesign.shellGap) {
            ConductorSidebar(model: model)

            VStack(spacing: 0) {
                ConductorToolbar(model: model)
                SplitNodeView(node: model.workspace.visibleRoot, model: model)
                    .background(model.theme.terminalBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ConductorTokens.Palette.terminalRaised)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalPane))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalPane)
                    .stroke(Color.black.opacity(0.68), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: ConductorDesign.shadow(0.16), radius: 18, y: 8)
        }
        .padding(.horizontal, ConductorDesign.shellHorizontalPadding)
        .padding(.top, ConductorDesign.shellTopPadding)
        .padding(.bottom, ConductorDesign.shellBottomPadding)
        .frame(
            minWidth: 1080,
            maxWidth: .infinity,
            minHeight: 720,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(ConductorDesign.windowBackground)
        .ignoresSafeArea(.container, edges: .top)
        .tint(model.theme.accent)
        .overlay {
            if model.commandPaletteVisible {
                CommandPaletteView(model: model)
            }
        }
    }
}

private struct CommandPaletteView: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var query = ""
    @State private var selectedCommandID: String?
    @FocusState private var searchFocused: Bool

    private var commands: [CommandPaletteItem] {
        [
            CommandPaletteItem(id: "new-terminal", section: "创建", title: "新开终端", shortcut: "Cmd-T", keywords: "terminal pane shell") {
                run {
                    model.newTerminal()
                }
            },
            CommandPaletteItem(id: "new-tab", section: "创建", title: "新标签", shortcut: "Cmd-Shift-T", keywords: "tab terminal") {
                run {
                    if let paneID = model.workspace.focusedPane?.id {
                        model.newTab(in: paneID)
                    }
                }
            },
            CommandPaletteItem(id: "duplicate-tab", section: "创建", title: "复制当前标签", shortcut: "Duplicate", keywords: "copy tab duplicate") {
                run {
                    model.duplicateSelectedTab()
                }
            },
            CommandPaletteItem(id: "split-right", section: "创建", title: "向右分屏", shortcut: "Cmd-D", disabled: !model.canSplit, keywords: "split right vertical") {
                run {
                    model.splitRight()
                }
            },
            CommandPaletteItem(id: "split-down", section: "创建", title: "向下分屏", shortcut: "Cmd-Shift-D", disabled: !model.canSplit, keywords: "split down horizontal") {
                run {
                    model.splitDown()
                }
            },
            CommandPaletteItem(id: "next-tab", section: "导航", title: "下一个标签", shortcut: "Cmd-]", keywords: "next tab") {
                run {
                    model.selectNextTab()
                }
            },
            CommandPaletteItem(id: "previous-tab", section: "导航", title: "上一个标签", shortcut: "Cmd-[", keywords: "previous tab") {
                run {
                    model.selectPreviousTab()
                }
            },
            CommandPaletteItem(id: "next-pane", section: "导航", title: "下一个分屏", shortcut: "Cmd-Shift-]", keywords: "next pane focus") {
                run {
                    model.focusNextPane()
                }
            },
            CommandPaletteItem(id: "previous-pane", section: "导航", title: "上一个分屏", shortcut: "Cmd-Shift-[", keywords: "previous pane focus") {
                run {
                    model.focusPreviousPane()
                }
            },
            CommandPaletteItem(
                id: "notifications",
                section: "导航",
                title: "通知中心",
                shortcut: "\(model.notifications.snapshot.unreadCount)",
                keywords: "notification unread agent"
            ) {
                run {
                    model.toggleNotificationPanel()
                }
            },
            CommandPaletteItem(
                id: "jump-unread",
                section: "导航",
                title: "跳到最新未读",
                shortcut: "Unread",
                disabled: model.notifications.snapshot.latestUnread == nil,
                keywords: "notification unread jump"
            ) {
                run {
                    _ = model.jumpToLatestUnread()
                }
            },
            CommandPaletteItem(id: "close-tab", section: "整理", title: "关闭标签", shortcut: "Cmd-W", keywords: "close tab") {
                run {
                    model.closeSelectedTab()
                }
            },
            CommandPaletteItem(id: "close-pane", section: "整理", title: "关闭分屏", shortcut: "Cmd-Shift-W", disabled: !model.canCloseFocusedPane, keywords: "close pane split") {
                run {
                    model.closePane(model.workspace.focusedPaneID)
                }
            },
            CommandPaletteItem(id: "move-tab-left", section: "整理", title: "标签左移", shortcut: "Cmd-Shift-,", disabled: !model.canMoveSelectedTabLeft, keywords: "move tab left") {
                run {
                    model.moveSelectedTabLeft()
                }
            },
            CommandPaletteItem(id: "move-tab-right", section: "整理", title: "标签右移", shortcut: "Cmd-Shift-.", disabled: !model.canMoveSelectedTabRight, keywords: "move tab right") {
                run {
                    model.moveSelectedTabRight()
                }
            },
            CommandPaletteItem(id: "move-tab-next-pane", section: "整理", title: "移到下一个分屏", shortcut: "Cmd-Opt-M", disabled: !model.canMoveSelectedTabToNextPane, keywords: "move tab pane") {
                run {
                    model.moveSelectedTabToNextPane()
                }
            },
            CommandPaletteItem(id: "move-tab-new-split", section: "整理", title: "移到右侧新分屏", shortcut: "Cmd-Opt-Shift-M", disabled: !model.canMoveSelectedTabToNewSplit, keywords: "move tab new split") {
                run {
                    model.moveSelectedTabToNewSplit(.right)
                }
            },
            CommandPaletteItem(
                id: "toggle-zoom",
                section: "视图",
                title: model.workspace.isZoomed ? "还原当前分屏" : "放大当前分屏",
                shortcut: "Cmd-Z",
                disabled: model.workspace.root.leaves.count <= 1,
                keywords: "zoom pane"
            ) {
                run {
                    model.toggleZoom()
                }
            },
            CommandPaletteItem(id: "equalize-splits", section: "视图", title: "均分分屏", shortcut: "Cmd-Shift-=", disabled: model.workspace.root.leaves.count <= 1, keywords: "equalize split layout") {
                run {
                    model.equalizeSplits()
                }
            },
            CommandPaletteItem(id: "duplicate-workspace", section: "视图", title: "复制工作区", shortcut: "Duplicate", keywords: "workspace duplicate") {
                run {
                    model.duplicateWorkspace(model.workspace.id)
                }
            },
            CommandPaletteItem(id: "reset-workspace", section: "视图", title: "重置工作区", shortcut: "Reset", keywords: "workspace reset") {
                run {
                    model.resetWorkspace()
                }
            },
            CommandPaletteItem(id: "clear-notifications", section: "整理", title: "清空通知", shortcut: "Clear", disabled: model.notifications.records.isEmpty, keywords: "notification clear") {
                run {
                    model.clearAllNotifications()
                }
            },
            CommandPaletteItem(id: "debug-notification", section: "调试", title: "模拟当前终端通知", shortcut: "Test", keywords: "notification test") {
                run {
                    model.notifyFocusedTerminalForTesting()
                }
            }
        ]
    }

    private var filteredCommands: [CommandPaletteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return commands }
        return commands.filter { command in
            "\(command.title) \(command.shortcut) \(command.keywords)"
                .lowercased()
                .contains(normalizedQuery)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture {
                    model.hideCommandPalette()
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    TextField("搜索命令", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($searchFocused)
                    Text("↵")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Color.white.opacity(0.50))
                .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup))
                .overlay {
                    RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup)
                        .stroke(ConductorDesign.toolbarStroke, lineWidth: 1)
                }

                if filteredCommands.isEmpty {
                    Text("没有匹配的命令")
                        .font(.system(size: 12))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                if index == 0 || filteredCommands[index - 1].section != command.section {
                                    CommandSectionTitle(command.section)
                                }
                                CommandButton(
                                    title: command.title,
                                    shortcut: command.shortcut,
                                    selected: command.id == selectedCommandID,
                                    disabled: command.disabled,
                                    action: command.action,
                                    onHover: {
                                        if !command.disabled {
                                            selectedCommandID = command.id
                                        }
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 360)
                }
            }
            .padding(10)
            .frame(width: 340)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.sidebar))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.sidebar)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 22, y: 10)
            .onAppear {
                searchFocused = true
                ensureSelection()
            }
            .onChange(of: query) {
                ensureSelection()
            }
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    moveSelection(by: -1)
                case .down:
                    moveSelection(by: 1)
                default:
                    break
                }
            }
            .onSubmit {
                executeSelected()
            }
        }
    }

    private func run(_ action: () -> Void) {
        action()
        model.hideCommandPalette()
    }

    private func ensureSelection() {
        let enabledCommands = filteredCommands.filter { !$0.disabled }
        guard !enabledCommands.isEmpty else {
            selectedCommandID = nil
            return
        }
        if let selectedCommandID,
           enabledCommands.contains(where: { $0.id == selectedCommandID }) {
            return
        }
        selectedCommandID = enabledCommands.first?.id
    }

    private func moveSelection(by offset: Int) {
        let enabledCommands = filteredCommands.filter { !$0.disabled }
        guard !enabledCommands.isEmpty else {
            selectedCommandID = nil
            return
        }
        let currentIndex = enabledCommands.firstIndex { $0.id == selectedCommandID } ?? 0
        let nextIndex = (currentIndex + offset + enabledCommands.count) % enabledCommands.count
        selectedCommandID = enabledCommands[nextIndex].id
    }

    private func executeSelected() {
        ensureSelection()
        guard let selectedCommandID,
              let command = filteredCommands.first(where: { $0.id == selectedCommandID }),
              !command.disabled else {
            return
        }
        command.action()
    }
}

private struct CommandPaletteItem: Identifiable {
    let id: String
    let section: String
    let title: String
    let shortcut: String
    var disabled = false
    var keywords = ""
    let action: () -> Void
}

private struct CommandSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ConductorDesign.tertiaryText)
            .padding(.top, 4)
            .padding(.horizontal, 10)
    }
}

private struct CommandButton: View {
    let title: String
    let shortcut: String
    var selected = false
    var disabled = false
    let action: () -> Void
    var onHover: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(selected ? ConductorDesign.selectedFill : (hovering ? ConductorDesign.hoverFill : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover {
            hovering = $0
            if $0 {
                onHover()
            }
        }
    }
}

struct NotificationPanelView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: model.notifications.snapshot.unreadCount > 0 ? "bell.badge" : "bell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("通知")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ConductorDesign.primaryText)
                if model.notifications.snapshot.unreadCount > 0 {
                    Text("\(model.notifications.snapshot.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                Spacer()
                Button("跳转") {
                    _ = model.jumpToLatestUnread()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.notifications.snapshot.latestUnread == nil ? ConductorDesign.tertiaryText : Color.accentColor)
                .disabled(model.notifications.snapshot.latestUnread == nil)
                Button("清空") {
                    model.clearAllNotifications()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.notifications.records.isEmpty ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
                .disabled(model.notifications.records.isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider()
                .opacity(0.45)

            if model.notifications.records.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    Text("暂无通知")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ConductorDesign.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.notifications.records) { notification in
                            NotificationRowView(
                                notification: notification,
                                terminalTitle: title(for: notification.terminalID),
                                unread: !notification.isRead,
                                onOpen: {
                                    _ = model.openNotification(notification.id)
                                },
                                onClear: {
                                    model.clearNotification(notification.id)
                                }
                            )
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .background(ConductorDesign.windowBackground)
    }

    private func title(for terminalID: TerminalID) -> String {
        for workspace in model.workspaces {
            for pane in workspace.panes.values {
                if let tab = pane.tabs.first(where: { $0.id == terminalID }) {
                    return tab.title
                }
            }
        }
        return "终端"
    }
}

private struct NotificationRowView: View {
    let notification: TerminalNotificationRecord
    let terminalTitle: String
    let unread: Bool
    let onOpen: () -> Void
    let onClear: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(unread ? Color.accentColor : Color.clear)
                        .overlay {
                            Circle()
                                .stroke(Color.accentColor.opacity(unread ? 0.95 : 0.25), lineWidth: 1)
                        }
                        .frame(width: 7, height: 7)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(notification.title)
                                .font(.system(size: 12, weight: unread ? .semibold : .medium))
                                .foregroundStyle(ConductorDesign.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(ConductorDesign.tertiaryText)
                        }
                        if !notification.body.isEmpty {
                            Text(notification.body)
                                .font(.system(size: 11))
                                .foregroundStyle(ConductorDesign.secondaryText)
                                .lineLimit(3)
                        }
                        Text(terminalTitle)
                            .font(.system(size: 10))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovering ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("清除通知")
        }
        .padding(9)
        .background(hovering ? ConductorDesign.hoverFill : Color.white.opacity(unread ? 0.34 : 0.20))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.row)
                .stroke(unread ? Color.accentColor.opacity(0.16) : ConductorDesign.sidebarStroke, lineWidth: 1)
        }
        .onHover { hovering = $0 }
    }
}

private struct ConductorSidebar: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var renamingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""
    @State private var renamingTerminalID: TerminalID?
    @State private var terminalTitleDraft = ""

    private var terminalCount: Int {
        model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var focusedTerminalTitle: String {
        model.workspace.focusedPane?.selectedTab?.title ?? "无"
    }

    private var sidebarHeaderHeight: CGFloat {
        model.sidebarVisible ? 56 : 72
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            if model.sidebarVisible {
                expandedSidebar
            } else {
                collapsedSidebar
            }
        }
        .padding(.horizontal, model.sidebarVisible ? ConductorTokens.Space.sidebarX : 6)
        .padding(.top, ConductorTokens.Space.sidebarTop)
        .padding(.bottom, ConductorTokens.Space.sidebarBottom)
        .frame(width: model.sidebarVisible ? ConductorDesign.sidebarWidth : ConductorDesign.sidebarCollapsedWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius)
                .stroke(Color.white.opacity(0.70), lineWidth: 1)
        }
        .shadow(
            color: ConductorDesign.shadow(ConductorTokens.Shadow.panelOpacity),
            radius: ConductorTokens.Shadow.panelRadius,
            y: ConductorTokens.Shadow.panelY
        )
        .alert("重命名标签", isPresented: Binding(
            get: { renamingTerminalID != nil },
            set: { if !$0 { renamingTerminalID = nil } }
        )) {
            TextField("标签名称", text: $terminalTitleDraft)
            Button("取消", role: .cancel) {
                renamingTerminalID = nil
            }
            Button("保存") {
                if let renamingTerminalID {
                    model.renameTerminal(renamingTerminalID, title: terminalTitleDraft)
                }
                renamingTerminalID = nil
            }
        }
    }

    private var sidebarHeader: some View {
        HStack {
            Spacer()
            Button {
                model.sidebarVisible.toggle()
            } label: {
                Image(systemName: model.sidebarVisible ? "chevron.left" : "sidebar.left")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 26, height: 24)
                    .background(Color.black.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .help(model.sidebarVisible ? "收起侧边栏" : "展开侧边栏")
        }
        .frame(height: sidebarHeaderHeight, alignment: .bottom)
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            workspaceSection
                .frame(maxHeight: .infinity)

            SidebarSeparator()

            SidebarSectionTitle("状态")
            VStack(spacing: 4) {
                MetricRow(title: "分屏", value: "\(model.workspace.panes.count)")
                MetricRow(title: "终端", value: "\(terminalCount)")
                MetricRow(title: "通知", value: "\(model.notifications.snapshot.unreadCount)")
                MetricRow(title: "当前", value: focusedTerminalTitle)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(ConductorDesign.sidebarStroke, lineWidth: 1)
            }

            SidebarSeparator()

            SidebarSectionTitle("快捷操作")
            quickActions(showsLabels: true)

            Spacer(minLength: 8)

            SidebarActionRow(icon: "paintpalette", title: model.theme.title, help: "切换终端配色") {
                model.theme = model.theme == .codexDark ? .flexoki : .codexDark
            }
            SidebarActionRow(icon: "gearshape", title: "设置", help: "设置") {}
        }
        .frame(maxHeight: .infinity)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SidebarSectionTitle("工作区")
                Spacer()
                Button {
                    model.newWorkspace()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("新建工作区")
            }
            .padding(.trailing, 5)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(model.workspaces) { workspace in
                            workspaceRow(for: workspace)
                                .id(workspace.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .mask(ConductorVerticalFadeMask())
                .onAppear {
                    scrollSidebarSelection(proxy)
                }
                .onChange(of: model.workspace.id) {
                    scrollSidebarSelection(proxy)
                }
                .onChange(of: model.workspaces.map(\.id)) {
                    scrollSidebarSelection(proxy)
                }
            }
            .frame(minHeight: 72, maxHeight: .infinity)
        }
    }

    private var collapsedSidebar: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(model.workspaces) { workspace in
                            SidebarRailButton(
                                icon: workspace.id == model.workspace.id ? "rectangle.3.group.fill" : "rectangle.3.group",
                                selected: workspace.id == model.workspace.id,
                                help: workspace.title
                            ) {
                                model.selectWorkspace(workspace.id)
                            }
                            .id(workspace.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .mask(ConductorVerticalFadeMask())
                .onAppear {
                    scrollSidebarSelection(proxy)
                }
                .onChange(of: model.workspace.id) {
                    scrollSidebarSelection(proxy)
                }
                .onChange(of: model.workspaces.map(\.id)) {
                    scrollSidebarSelection(proxy)
                }
            }
            .frame(maxHeight: .infinity)

            SidebarSeparator()
                .padding(.horizontal, -1)

            quickActions(showsLabels: false)

            Spacer(minLength: 8)

            SidebarRailButton(icon: "paintpalette", help: model.theme.title) {
                model.theme = model.theme == .codexDark ? .flexoki : .codexDark
            }
            SidebarRailButton(icon: "gearshape", help: "设置") {}
        }
    }

    @ViewBuilder
    private func quickActions(showsLabels: Bool) -> some View {
        Group {
            SidebarActionRow(icon: "plus.rectangle.on.rectangle", title: "新开终端", showsTitle: showsLabels, help: "新开终端 Cmd-T") {
                model.newTerminal()
            }
            SidebarActionRow(icon: "plus", title: "新标签", showsTitle: showsLabels, help: "在当前分屏中新建标签 Cmd-Shift-T") {
                if let paneID = model.workspace.focusedPane?.id {
                    model.newTab(in: paneID)
                }
            }
            SidebarActionRow(icon: "rectangle.split.2x1", title: "向右分屏", showsTitle: showsLabels, disabled: !model.canSplit, help: "向右分屏 Cmd-D") {
                model.splitRight()
            }
            SidebarActionRow(icon: "rectangle.split.1x2", title: "向下分屏", showsTitle: showsLabels, disabled: !model.canSplit, help: "向下分屏 Cmd-Shift-D") {
                model.splitDown()
            }
            SidebarActionRow(icon: "command", title: "命令面板", showsTitle: showsLabels, help: "打开命令面板 Cmd-K") {
                model.toggleCommandPalette()
            }
            SidebarActionRow(
                icon: model.notifications.snapshot.unreadCount > 0 ? "bell.badge" : "bell",
                title: "通知 \(model.notifications.snapshot.unreadCount)",
                showsTitle: showsLabels,
                help: "查看通知和跳转未读"
            ) {
                model.toggleNotificationPanel()
            }
            SidebarActionRow(icon: "text.cursor", title: "重命名工作区", showsTitle: showsLabels, help: "重命名当前工作区") {
                beginRenameWorkspace(model.workspace)
            }
            SidebarActionRow(icon: "tag", title: "重命名标签", showsTitle: showsLabels, help: "重命名当前标签") {
                beginRenameFocusedTerminal()
            }
        }
    }

    private func workspaceRow(for workspace: WorkspaceState) -> some View {
        WorkspaceSidebarRow(
            title: workspace.title,
            terminalCount: workspaceTerminalCount(workspace),
            unreadCount: model.notifications.snapshot.unreadCount(for: workspace.id),
            selected: workspace.id == model.workspace.id,
            editing: renamingWorkspaceID == workspace.id,
            titleDraft: $workspaceTitleDraft,
            onCommitRename: commitWorkspaceRename,
            onCancelRename: cancelWorkspaceRename
        ) {
            model.selectWorkspace(workspace.id)
        } onRename: {
            beginRenameWorkspace(workspace)
        }
        .contextMenu {
            Button("重命名工作区...") {
                beginRenameWorkspace(workspace)
            }
            Button("复制工作区") {
                model.duplicateWorkspace(workspace.id)
            }
            Divider()
            Button("关闭其他工作区") {
                model.closeOtherWorkspaces(keeping: workspace.id)
            }
            .disabled(model.workspaces.count <= 1)
            Button("关闭右侧工作区") {
                model.closeWorkspacesToRight(of: workspace.id)
            }
            .disabled(model.workspaces.count <= 1)
            Divider()
            Button("关闭工作区") {
                model.closeWorkspace(workspace.id)
            }
            .disabled(model.workspaces.count <= 1)
        }
    }

    private func workspaceTerminalCount(_ workspace: WorkspaceState) -> Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private func beginRenameWorkspace(_ workspace: WorkspaceState) {
        workspaceTitleDraft = workspace.title
        renamingWorkspaceID = workspace.id
    }

    private func commitWorkspaceRename() {
        if let renamingWorkspaceID {
            model.renameWorkspace(renamingWorkspaceID, title: workspaceTitleDraft)
        }
        renamingWorkspaceID = nil
    }

    private func cancelWorkspaceRename() {
        renamingWorkspaceID = nil
    }

    private func beginRenameFocusedTerminal() {
        guard let tab = model.workspace.focusedPane?.selectedTab else { return }
        terminalTitleDraft = tab.title
        renamingTerminalID = tab.id
    }

    private func scrollSidebarSelection(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(model.workspace.id, anchor: .center)
        }
    }
}

private struct SidebarSeparator: View {
    var body: some View {
        Rectangle()
            .fill(ConductorDesign.sidebarStroke)
            .frame(height: 1)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
    }
}

private struct SidebarRailButton: View {
    let icon: String
    var selected = false
    var disabled = false
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
                .frame(width: 34, height: 34)
                .background(selected ? ConductorDesign.selectedFill : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
    }
}

private struct SidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(ConductorTokens.Typography.section)
            .foregroundStyle(ConductorDesign.tertiaryText)
            .padding(.horizontal, 8)
            .padding(.top, 2)
    }
}

private struct SidebarRow: View {
    let icon: String
    let title: String
    let selected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .frame(width: 14)
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
            Text(title)
                .font(selected ? ConductorTokens.Typography.rowSelected : ConductorTokens.Typography.row)
                .foregroundStyle(ConductorDesign.primaryText)
            Spacer()
        }
        .padding(.horizontal, 7)
        .frame(height: 25)
        .background(selected ? ConductorDesign.selectedFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
    }
}

private struct WorkspaceSidebarRow: View {
    let title: String
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
    let editing: Bool
    @Binding var titleDraft: String
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let action: () -> Void
    let onRename: () -> Void
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        Group {
            if editing {
                editingRow
            } else {
                displayRow
            }
        }
        .onHover { hovering = $0 }
        .help(title)
    }

    private var editingRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
                .foregroundStyle(Color.accentColor)
            RenameTextField(
                text: $titleDraft,
                placeholder: "工作区名称",
                font: .systemFont(ofSize: 12, weight: .semibold),
                textColor: NSColor.labelColor,
                onCommit: onCommitRename,
                onCancel: onCancelRename
            )
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(ConductorDesign.selectedFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .onAppear {
            renameCancelled = false
        }
    }

    private var displayRow: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "rectangle.3.group.fill" : "rectangle.3.group")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
                Text(title)
                    .font(selected ? ConductorTokens.Typography.rowSelected : ConductorTokens.Typography.row)
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(terminalCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 14)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(selected ? ConductorDesign.selectedFill : (hovering ? ConductorDesign.hoverFill : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded(onRename)
        )
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .frame(width: 14)
                if showsTitle {
                    Text(title)
                        .font(ConductorTokens.Typography.row)
                    Spacer()
                }
            }
            .foregroundStyle(ConductorDesign.secondaryText)
            .padding(.horizontal, showsTitle ? 8 : 0)
            .frame(width: showsTitle ? nil : 34, height: showsTitle ? 28 : 34)
            .background(hovering ? ConductorDesign.hoverFill : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: showsTitle ? ConductorTokens.Radius.row : 11))
            .contentShape(RoundedRectangle(cornerRadius: showsTitle ? ConductorTokens.Radius.row : 11))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .onHover { hovering = $0 }
        .help(help ?? title)
    }
}

private struct MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct ConductorToolbar: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var editingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""

    var body: some View {
        HStack(spacing: ConductorTokens.Space.toolbarGap) {
            WorkspaceTabStrip(
                model: model,
                editingWorkspaceID: $editingWorkspaceID,
                workspaceTitleDraft: $workspaceTitleDraft,
                onBeginRename: beginRenameWorkspace,
                onCommitRename: commitWorkspaceRename,
                onCancelRename: cancelWorkspaceRename
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            ConductorPillGroup {
                ConductorIconButton(systemImage: "plus", help: "新建工作区", title: "工作区") {
                    model.newWorkspace()
                }
            }

            ConductorPillGroup {
                ConductorIconButton(systemImage: "plus.rectangle.on.rectangle", help: "新开终端 Cmd-T", title: "新终端") {
                    model.newTerminal()
                }
                ConductorIconButton(systemImage: "plus", help: "新标签 Cmd-Shift-T", title: "新标签") {
                    if let paneID = model.workspace.focusedPane?.id {
                        model.newTab(in: paneID)
                    }
                }
            }

            ConductorPillGroup {
                ConductorIconButton(systemImage: "rectangle.split.2x1", help: "向右分屏 Cmd-D", title: "右分屏", disabled: !model.canSplit) {
                    model.splitRight()
                }
                ConductorIconButton(systemImage: "rectangle.split.1x2", help: "向下分屏 Cmd-Shift-D", title: "下分屏", disabled: !model.canSplit) {
                    model.splitDown()
                }
                ConductorIconButton(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    help: model.workspace.isZoomed ? "还原当前分屏" : "放大当前分屏",
                    title: nil,
                    disabled: model.workspace.root.leaves.count <= 1,
                    active: model.workspace.isZoomed
                ) {
                    model.toggleZoom()
                }
            }

            ConductorPillGroup {
                ConductorIconButton(
                    systemImage: model.notifications.snapshot.unreadCount > 0 ? "bell.badge" : "bell",
                    help: "通知中心",
                    title: model.notifications.snapshot.unreadCount > 0 ? "\(model.notifications.snapshot.unreadCount)" : nil,
                    active: model.notificationPanelVisible
                ) {
                    model.toggleNotificationPanel()
                }
                ConductorIconButton(systemImage: "ellipsis", help: "命令面板 Cmd-K", title: "命令") {
                    model.toggleCommandPalette()
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 4)
        .frame(height: ConductorDesign.toolbarHeight)
        .background(ConductorTokens.Palette.terminalChrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ConductorTokens.Palette.strokeOnDark.opacity(0.55))
                .frame(height: 1)
        }
    }

    private func beginRenameWorkspace(_ workspace: WorkspaceState) {
        workspaceTitleDraft = workspace.title
        editingWorkspaceID = workspace.id
    }

    private func commitWorkspaceRename() {
        if let editingWorkspaceID {
            model.renameWorkspace(editingWorkspaceID, title: workspaceTitleDraft)
        }
        editingWorkspaceID = nil
    }

    private func cancelWorkspaceRename() {
        editingWorkspaceID = nil
    }

}

private struct WorkspaceTabStrip: View {
    @ObservedObject var model: ConductorWindowModel
    @Binding var editingWorkspaceID: WorkspaceID?
    @Binding var workspaceTitleDraft: String
    let onBeginRename: (WorkspaceState) -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void

    private var workspaceIDs: [WorkspaceID] {
        model.workspaces.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WorkspaceTabMetrics.spacing) {
                    ForEach(model.workspaces) { workspace in
                        workspaceTabView(for: workspace)
                    }
                }
                .padding(.horizontal, WorkspaceTabMetrics.edgePadding)
            }
            .onDrop(
                of: [UTType.text],
                delegate: WorkspaceTabDropDelegate(
                    targetWorkspaceID: nil,
                    model: model
                )
            )
            .onAppear {
                scrollToSelectedWorkspace(proxy)
            }
            .onChange(of: model.workspace.id) {
                scrollToSelectedWorkspace(proxy)
            }
            .onChange(of: workspaceIDs) {
                scrollToSelectedWorkspace(proxy)
            }
        }
        .frame(minWidth: WorkspaceTabMetrics.width, maxWidth: .infinity, minHeight: WorkspaceTabMetrics.height, maxHeight: WorkspaceTabMetrics.height, alignment: .leading)
        .clipped()
        .mask(ConductorHorizontalFadeMask())
    }

    private func scrollToSelectedWorkspace(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo(model.workspace.id, anchor: .center)
        }
    }

    private func workspaceTabView(for workspace: WorkspaceState) -> some View {
        WorkspaceTopTab(
            workspace: workspace,
            unreadCount: model.notifications.snapshot.unreadCount(for: workspace.id),
            selected: workspace.id == model.workspace.id,
            canClose: model.workspaces.count > 1,
            editing: editingWorkspaceID == workspace.id,
            titleDraft: $workspaceTitleDraft,
            onSelect: {
                model.selectWorkspace(workspace.id)
            },
            onRename: {
                onBeginRename(workspace)
            },
            onCommitRename: onCommitRename,
            onCancelRename: onCancelRename,
            onDuplicate: {
                model.duplicateWorkspace(workspace.id)
            },
            onClose: {
                model.closeWorkspace(workspace.id)
            },
            onCloseOthers: {
                model.closeOtherWorkspaces(keeping: workspace.id)
            },
            onCloseRight: {
                model.closeWorkspacesToRight(of: workspace.id)
            }
        )
        .id(workspace.id)
        .onDrop(
            of: [UTType.text],
            delegate: WorkspaceTabDropDelegate(
                targetWorkspaceID: workspace.id,
                model: model
            )
        )
    }
}

private enum WorkspaceTabMetrics {
    static let width: CGFloat = 132
    static let height: CGFloat = 25
    static let spacing: CGFloat = 4
    static let edgePadding: CGFloat = 6
}

private struct WorkspaceTopTab: View {
    let workspace: WorkspaceState
    let unreadCount: Int
    let selected: Bool
    let canClose: Bool
    let editing: Bool
    @Binding var titleDraft: String
    let onSelect: () -> Void
    let onRename: () -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onDuplicate: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseRight: () -> Void
    @State private var hovering = false
    @State private var renameCancelled = false
    @FocusState private var titleFieldFocused: Bool

    private var terminalCount: Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    var body: some View {
        HStack(spacing: 6) {
            if editing {
                Image(systemName: "rectangle.3.group.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14)
                RenameTextField(
                    text: $titleDraft,
                    placeholder: "工作区名称",
                    font: .systemFont(ofSize: 11.5, weight: .bold),
                    textColor: NSColor.labelColor,
                    onCommit: onCommitRename,
                    onCancel: onCancelRename
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    renameCancelled = false
                }
            } else {
                Image(systemName: selected ? "rectangle.3.group.fill" : "rectangle.3.group")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(selected ? ConductorDesign.primaryText : ConductorDesign.terminalTextMuted)
                    .frame(width: 14)
                Text(workspace.title)
                    .font(selected ? ConductorTokens.Typography.workspaceTabSelected : ConductorTokens.Typography.workspaceTab)
                    .foregroundStyle(selected ? ConductorDesign.primaryText : ConductorDesign.terminalTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(terminalCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? ConductorDesign.tertiaryText : ConductorDesign.terminalTextMuted)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 14)
                    .background(selected ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.08))
                    .clipShape(Capsule())
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 14)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(canClose ? (selected ? ConductorDesign.tertiaryText : ConductorDesign.terminalTextMuted.opacity(0.70)) : Color.clear)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canClose)
                .help("关闭工作区")
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, editing ? 7 : 5)
        .frame(width: WorkspaceTabMetrics.width, height: WorkspaceTabMetrics.height)
        .background(selected ? ConductorTokens.Palette.terminalChromeSelected : (hovering ? Color.white.opacity(0.06) : Color.white.opacity(0.035)))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab)
                .stroke(selected ? Color.white.opacity(0.72) : Color.white.opacity(hovering ? 0.07 : 0.025), lineWidth: 1)
        }
        .shadow(
            color: selected ? ConductorDesign.shadow(ConductorTokens.Shadow.controlOpacity) : ConductorDesign.shadow(0.030),
            radius: ConductorTokens.Shadow.controlRadius,
            y: ConductorTokens.Shadow.controlY
        )
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab))
        .simultaneousGesture(
            TapGesture(count: 1).onEnded(onSelect)
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded(onRename)
        )
        .onDrag {
            NSItemProvider(object: workspace.id.description as NSString)
        }
        .contextMenu {
            Button("重命名工作区...") {
                onRename()
            }
            Button("复制工作区") {
                onDuplicate()
            }
            Divider()
            Button("关闭其他工作区") {
                onCloseOthers()
            }
            .disabled(!canClose)
            Button("关闭右侧工作区") {
                onCloseRight()
            }
            .disabled(!canClose)
            Divider()
            Button("关闭工作区") {
                onClose()
            }
            .disabled(!canClose)
        }
        .help("\(workspace.title) · \(workspace.panes.count) 分屏 · \(terminalCount) 终端")
    }
}

private struct WorkspaceTabDropDelegate: DropDelegate {
    let targetWorkspaceID: WorkspaceID?
    let model: ConductorWindowModel

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let text: String?
            if let data = item as? Data {
                text = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                text = string
            } else if let nsString = item as? NSString {
                text = nsString as String
            } else {
                text = nil
            }

            guard let text,
                  let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }

            Task { @MainActor in
                model.moveWorkspace(WorkspaceID(uuid), before: targetWorkspaceID)
            }
        }
        return true
    }
}
