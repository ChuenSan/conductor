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
        .animation(ConductorMotion.layout, value: model.sidebarVisible)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(ConductorMotion.standard, value: model.commandPaletteVisible)
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
            CommandPaletteItem(id: "install-codex-hooks", section: "集成", title: "连接 Codex 完成通知", shortcut: "Codex", keywords: "codex hooks notification agent") {
                run {
                    model.installCodexNotificationHooks()
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
            .animation(ConductorMotion.standard, value: selectedCommandID)
            .animation(ConductorMotion.micro, value: query)
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
        ConductorMotion.perform {
            action()
            model.hideCommandPalette()
        }
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
        .animation(ConductorMotion.micro, value: selected)
        .animation(ConductorMotion.micro, value: hovering)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
            if value {
                onHover()
            }
        }
    }
}

struct NotificationPanelView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.30),
                    Color.white.opacity(0.10),
                    Color.black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                notificationHeader

                Rectangle()
                    .fill(Color.white.opacity(0.34))
                    .frame(height: 1)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.black.opacity(0.045))
                            .frame(height: 1)
                    }

                if model.notifications.records.isEmpty {
                    emptyNotifications
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
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
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                    removal: .opacity.combined(with: .scale(scale: 0.96))
                                ))
                            }
                        }
                        .padding(10)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 28, y: 16)
        .animation(ConductorMotion.layout, value: model.notifications.records.map(\.id))
        .animation(ConductorMotion.emphasized, value: model.notifications.snapshot.unreadCount)
    }

    private var notificationHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: model.notifications.snapshot.unreadCount > 0 ? "bell.badge.fill" : "bell")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text("通知")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ConductorDesign.primaryText)
            if model.notifications.snapshot.unreadCount > 0 {
                Text("\(model.notifications.snapshot.unreadCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
            }
            Spacer()
            Button("跳转") {
                ConductorMotion.perform {
                    _ = model.jumpToLatestUnread()
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(model.notifications.snapshot.latestUnread == nil ? ConductorDesign.tertiaryText : Color.accentColor)
            .disabled(model.notifications.snapshot.latestUnread == nil)
            Button("清空") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.clearAllNotifications()
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(model.notifications.records.isEmpty ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
            .disabled(model.notifications.records.isEmpty)
        }
        .padding(.top, 34)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background(.regularMaterial.opacity(0.72))
    }

    private var emptyNotifications: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text("暂无通知")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ConductorDesign.secondaryText)
            Text("Codex 完成、终端通知和响铃都会出现在这里")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                ConductorMotion.perform {
                    model.installCodexNotificationHooks()
                }
            } label: {
                Label("连接 Codex", systemImage: "bolt.horizontal.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.30))
                    .clipShape(Capsule())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
        HStack(alignment: .top, spacing: 9) {
            Button {
                ConductorMotion.perform(onOpen)
            } label: {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color.white.opacity(0.18))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.26), lineWidth: 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if unread {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 2, y: -2)
                            }
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        rowTitle
                        rowBody
                        rowMetadata
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(ConductorPressButtonStyle())

            Button {
                ConductorMotion.perform(ConductorMotion.layout, onClear)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovering ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(hovering ? 0.22 : 0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .help("清除通知")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    unread ? Color.accentColor.opacity(0.22) : Color.white.opacity(0.28),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(hovering ? 0.085 : 0.045), radius: hovering ? 10 : 6, y: hovering ? 6 : 3)
        .scaleEffect(hovering ? 1.002 : 1)
        .animation(ConductorMotion.micro, value: hovering)
        .animation(ConductorMotion.emphasized, value: unread)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
    }

    private var rowTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(notification.title)
                .font(.system(size: 12.5, weight: unread ? .semibold : .medium))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var rowBody: some View {
        if !notification.body.isEmpty {
            Text(notification.body)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineSpacing(1.5)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowMetadata: some View {
        HStack(spacing: 6) {
            Label(kindLabel, systemImage: kindChipIcon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())

            Label(terminalTitle, systemImage: "terminal")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(Color.white.opacity(0.18))
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
    }

    private var rowBackground: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(hovering ? 0.30 : (unread ? 0.24 : 0.18)),
                Color.white.opacity(unread ? 0.10 : 0.055),
                Color.black.opacity(0.025)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconName: String {
        switch notification.kind {
        case .agent:
            "terminal"
        case .bell:
            "bell"
        case .notification:
            "terminal"
        }
    }

    private var kindChipIcon: String {
        switch notification.kind {
        case .agent:
            "bolt.horizontal"
        case .bell:
            "bell"
        case .notification:
            "app.badge"
        }
    }

    private var kindLabel: String {
        switch notification.kind {
        case .agent:
            "Agent"
        case .bell:
            "响铃"
        case .notification:
            "终端"
        }
    }

    private var iconColor: Color {
        switch notification.kind {
        case .agent:
            ConductorDesign.secondaryText
        case .bell:
            ConductorDesign.warmAccent
        case .notification:
            ConductorDesign.secondaryText
        }
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
        model.sidebarVisible ? 56 : 80
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            if model.sidebarVisible {
                expandedSidebar
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                collapsedSidebar
                    .transition(.opacity.combined(with: .move(edge: .leading)))
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
        .overlay(alignment: .top) {
            if !model.sidebarVisible {
                collapsedTrafficLightShelf
            }
        }
        .shadow(
            color: ConductorDesign.shadow(ConductorTokens.Shadow.panelOpacity),
            radius: ConductorTokens.Shadow.panelRadius,
            y: ConductorTokens.Shadow.panelY
        )
        .animation(ConductorMotion.layout, value: model.sidebarVisible)
        .animation(ConductorMotion.standard, value: model.workspace.id)
        .animation(ConductorMotion.layout, value: model.workspaces.map(\.id))
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
                    ConductorMotion.perform {
                        model.renameTerminal(renamingTerminalID, title: terminalTitleDraft)
                    }
                }
                renamingTerminalID = nil
            }
        }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        if model.sidebarVisible {
            HStack {
                Spacer()
                sidebarToggleButton
            }
            .frame(height: sidebarHeaderHeight, alignment: .bottom)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                sidebarToggleButton
            }
            .frame(maxWidth: .infinity)
            .frame(height: sidebarHeaderHeight, alignment: .bottom)
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            ConductorMotion.perform(ConductorMotion.layout) {
                finishWorkspaceRenameIfNeeded()
                model.sidebarVisible.toggle()
            }
        } label: {
            Image(systemName: model.sidebarVisible ? "chevron.left" : "sidebar.left")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 26, height: 24)
                .background(Color.black.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .help(model.sidebarVisible ? "收起侧边栏" : "展开侧边栏")
    }

    private var collapsedTrafficLightShelf: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white.opacity(0.20))
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                }
                .frame(height: 34)
                .padding(.horizontal, 6)
                .padding(.top, 6)
            Rectangle()
                .fill(ConductorDesign.sidebarStroke.opacity(0.45))
                .frame(height: 1)
                .padding(.horizontal, 18)
                .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .frame(height: 48)
        .allowsHitTesting(false)
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
                ConductorMotion.perform {
                    model.theme = model.theme == .codexDark ? .flexoki : .codexDark
                }
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
                    ConductorMotion.perform(ConductorMotion.layout) {
                        finishWorkspaceRenameIfNeeded()
                        model.newWorkspace()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(ConductorPressButtonStyle())
                .help("新建工作区")
            }
            .padding(.trailing, 5)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(model.workspaces) { workspace in
                            workspaceRow(for: workspace)
                                .id(workspace.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .leading)),
                                    removal: .opacity.combined(with: .move(edge: .trailing))
                                ))
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
                                ConductorMotion.perform {
                                    model.selectWorkspace(workspace.id)
                                }
                            }
                            .id(workspace.id)
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
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
                ConductorMotion.perform {
                    model.theme = model.theme == .codexDark ? .flexoki : .codexDark
                }
            }
            SidebarRailButton(icon: "gearshape", help: "设置") {}
        }
    }

    @ViewBuilder
    private func quickActions(showsLabels: Bool) -> some View {
        Group {
            SidebarActionRow(icon: "plus.rectangle.on.rectangle", title: "新开终端", showsTitle: showsLabels, help: "新开终端 Cmd-T") {
                finishWorkspaceRenameIfNeeded()
                model.newTerminal()
            }
            SidebarActionRow(icon: "plus", title: "新标签", showsTitle: showsLabels, help: "在当前分屏中新建标签 Cmd-Shift-T") {
                finishWorkspaceRenameIfNeeded()
                if let paneID = model.workspace.focusedPane?.id {
                    model.newTab(in: paneID)
                }
            }
            SidebarActionRow(icon: "rectangle.split.2x1", title: "向右分屏", showsTitle: showsLabels, disabled: !model.canSplit, help: "向右分屏 Cmd-D") {
                finishWorkspaceRenameIfNeeded()
                model.splitRight()
            }
            SidebarActionRow(icon: "rectangle.split.1x2", title: "向下分屏", showsTitle: showsLabels, disabled: !model.canSplit, help: "向下分屏 Cmd-Shift-D") {
                finishWorkspaceRenameIfNeeded()
                model.splitDown()
            }
            SidebarActionRow(icon: "command", title: "命令面板", showsTitle: showsLabels, help: "打开命令面板 Cmd-K") {
                finishWorkspaceRenameIfNeeded()
                model.toggleCommandPalette()
            }
            SidebarActionRow(
                icon: model.notifications.snapshot.unreadCount > 0 ? "bell.badge" : "bell",
                title: "通知 \(model.notifications.snapshot.unreadCount)",
                showsTitle: showsLabels,
                help: "查看通知和跳转未读"
            ) {
                finishWorkspaceRenameIfNeeded()
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
            finishWorkspaceRenameIfNeeded(except: workspace.id)
            model.selectWorkspace(workspace.id)
        } onRename: {
            finishWorkspaceRenameIfNeeded(except: workspace.id)
            beginRenameWorkspace(workspace)
        }
        .contextMenu {
            Button("重命名工作区...") {
                ConductorMotion.perform {
                    finishWorkspaceRenameIfNeeded(except: workspace.id)
                    beginRenameWorkspace(workspace)
                }
            }
            Button("复制工作区") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.duplicateWorkspace(workspace.id)
                }
            }
            Divider()
            Button("关闭其他工作区") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded(except: workspace.id)
                    model.closeOtherWorkspaces(keeping: workspace.id)
                }
            }
            .disabled(model.workspaces.count <= 1)
            Button("关闭右侧工作区") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspacesToRight(of: workspace.id)
                }
            }
            .disabled(model.workspaces.count <= 1)
            Divider()
            Button("关闭工作区") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspace(workspace.id)
                }
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
            ConductorMotion.perform {
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

    private func beginRenameFocusedTerminal() {
        guard let tab = model.workspace.focusedPane?.selectedTab else { return }
        terminalTitleDraft = tab.title
        renamingTerminalID = tab.id
    }

    private func scrollSidebarSelection(_ proxy: ScrollViewProxy) {
        withAnimation(ConductorMotion.standard) {
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
        Button {
            ConductorMotion.perform(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
                .frame(width: 34, height: 34)
                .background(selected ? ConductorDesign.selectedFill : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .animation(ConductorMotion.standard, value: selected)
        .animation(ConductorMotion.micro, value: disabled)
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
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                displayRow
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(ConductorMotion.standard, value: selected)
        .animation(ConductorMotion.standard, value: editing)
        .animation(ConductorMotion.standard, value: terminalCount)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
        .help(title)
    }

    private var editingRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14)
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
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
        .background(selected ? ConductorDesign.selectedFill : ConductorDesign.hoverFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .onAppear {
            renameCancelled = false
        }
    }

    private var displayRow: some View {
        Button {
            ConductorMotion.perform(action)
        } label: {
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
        .buttonStyle(ConductorPressButtonStyle())
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
        Button {
            ConductorMotion.perform(action)
        } label: {
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
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.micro, value: hovering)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
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
                    finishWorkspaceRenameIfNeeded()
                    model.newWorkspace()
                }
            }

            ConductorPillGroup {
                ConductorIconButton(systemImage: "plus.rectangle.on.rectangle", help: "新开终端 Cmd-T", title: "新终端") {
                    finishWorkspaceRenameIfNeeded()
                    model.newTerminal()
                }
                ConductorIconButton(systemImage: "plus", help: "新标签 Cmd-Shift-T", title: "新标签") {
                    finishWorkspaceRenameIfNeeded()
                    if let paneID = model.workspace.focusedPane?.id {
                        model.newTab(in: paneID)
                    }
                }
            }

            ConductorPillGroup {
                ConductorIconButton(systemImage: "rectangle.split.2x1", help: "向右分屏 Cmd-D", title: "右分屏", disabled: !model.canSplit) {
                    finishWorkspaceRenameIfNeeded()
                    model.splitRight()
                }
                ConductorIconButton(systemImage: "rectangle.split.1x2", help: "向下分屏 Cmd-Shift-D", title: "下分屏", disabled: !model.canSplit) {
                    finishWorkspaceRenameIfNeeded()
                    model.splitDown()
                }
                ConductorIconButton(
                    systemImage: "arrow.up.left.and.arrow.down.right",
                    help: model.workspace.isZoomed ? "还原当前分屏" : "放大当前分屏",
                    title: nil,
                    disabled: model.workspace.root.leaves.count <= 1,
                    active: model.workspace.isZoomed
                ) {
                    finishWorkspaceRenameIfNeeded()
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
                    finishWorkspaceRenameIfNeeded()
                    model.toggleNotificationPanel()
                }
                ConductorIconButton(systemImage: "ellipsis", help: "命令面板 Cmd-K", title: "命令") {
                    finishWorkspaceRenameIfNeeded()
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
            ConductorMotion.perform {
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
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .scale(scale: 0.92))
                            ))
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
        .animation(ConductorMotion.layout, value: workspaceIDs)
    }

    private func scrollToSelectedWorkspace(_ proxy: ScrollViewProxy) {
        withAnimation(ConductorMotion.standard) {
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
                finishWorkspaceRenameIfNeeded(except: workspace.id)
                model.selectWorkspace(workspace.id)
            },
            onRename: {
                ConductorMotion.perform {
                    finishWorkspaceRenameIfNeeded(except: workspace.id)
                    onBeginRename(workspace)
                }
            },
            onCommitRename: onCommitRename,
            onCancelRename: onCancelRename,
            onDuplicate: {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.duplicateWorkspace(workspace.id)
                }
            },
            onClose: {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspace(workspace.id)
                }
            },
            onCloseOthers: {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded(except: workspace.id)
                    model.closeOtherWorkspaces(keeping: workspace.id)
                }
            },
            onCloseRight: {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspacesToRight(of: workspace.id)
                }
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

    private func finishWorkspaceRenameIfNeeded(except workspaceID: WorkspaceID? = nil) {
        guard let editingWorkspaceID,
              editingWorkspaceID != workspaceID else {
            return
        }
        onCommitRename()
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
                Button {
                    ConductorMotion.perform(ConductorMotion.layout, onClose)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(canClose ? (selected ? ConductorDesign.tertiaryText : ConductorDesign.terminalTextMuted.opacity(0.70)) : Color.clear)
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ConductorPressButtonStyle())
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
        .scaleEffect(hovering && !selected ? 0.992 : 1)
        .animation(nil, value: selected)
        .animation(ConductorMotion.micro, value: hovering)
        .animation(ConductorMotion.standard, value: editing)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab))
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                onSelect()
            }
        )
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                ConductorMotion.perform(onRename)
            }
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
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.moveWorkspace(WorkspaceID(uuid), before: targetWorkspaceID)
                }
            }
        }
        return true
    }
}
