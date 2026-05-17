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
            .background(model.theme.terminalRaisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalPane))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalPane)
                    .stroke(model.theme.terminalOuterStroke, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(model.shellAnimation(ConductorMotion.layout), value: model.sidebarVisible)
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
        .background(ConductorWindowBackdrop(theme: model.theme))
        .ignoresSafeArea(.container, edges: .top)
        .tint(model.theme.accent)
        .environment(\.conductorFontScale, model.appearance.fontScale)
        .environment(\.conductorTheme, model.theme)
        .overlay {
            ZStack {
                if model.commandPaletteVisible {
                    CommandPaletteView(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                if model.settingsPanelVisible {
                    AppearanceSettingsPanel(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                if model.workspaceOverviewVisible {
                    WorkspaceOverviewPanel(model: model)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .animation(model.shellAnimation(ConductorMotion.standard), value: model.commandPaletteVisible)
        .animation(model.shellAnimation(ConductorMotion.standard), value: model.settingsPanelVisible)
        .animation(model.shellAnimation(ConductorMotion.standard), value: model.workspaceOverviewVisible)
    }
}

private struct CommandPaletteView: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var query = ""
    @State private var selectedCommandID: String?
    @FocusState private var searchFocused: Bool

    private var commands: [CommandPaletteItem] {
        ConductorCommandCatalog.items(model: model, run: run)
    }

    private var filteredCommands: [CommandPaletteItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return commands }
        return commands.filter { command in
            "\(command.title) \(command.shortcut) \(command.section) \(command.keywords)"
                .lowercased()
                .contains(normalizedQuery)
        }
    }

    private var suggestedCommands: [CommandPaletteItem] {
        let ids = ["new-tab", "split-right", "workspace-overview", "notifications", "appearance-settings"]
        return ids.compactMap { id in
            commands.first { $0.id == id }
        }
    }

    private var terminalCount: Int {
        model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var focusedTerminalTitle: String {
        model.workspace.focusedPane?.selectedTab?.title ?? "终端"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ConductorGlassSurface(style: .palette, clarity: model.appearance.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 10) {
                    commandHeader
                    CommandStatusStrip(
                        workspaceTitle: model.workspace.title,
                        terminalTitle: focusedTerminalTitle,
                        paneCount: model.workspace.panes.count,
                        terminalCount: terminalCount,
                        unreadCount: model.notifications.snapshot.unreadCount
                    )
                    commandSearchField

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        suggestionShelf
                    }

                    commandResults
                }
                .padding(12)
            }
            .frame(width: 560)
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
            .onExitCommand {
                model.hideCommandPalette()
            }
        }
    }

    private var commandHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Command Center")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ConductorDesign.primaryText)
                Text(model.workspace.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                ConductorMotion.perform {
                    model.hideCommandPalette()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭命令中心")
        }
    }

    private var commandSearchField: some View {
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
        .background(Color.white.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup)
                .stroke(Color.white.opacity(0.56), lineWidth: 1)
        }
    }

    private var suggestionShelf: some View {
        HStack(spacing: 8) {
            ForEach(suggestedCommands) { command in
                CommandSuggestionButton(
                    command: command,
                    selected: command.id == selectedCommandID
                ) {
                    selectedCommandID = command.id
                }
            }
        }
    }

    private var commandResults: some View {
        Group {
            if filteredCommands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    Text("没有匹配的命令")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ConductorDesign.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                            if index == 0 || filteredCommands[index - 1].section != command.section {
                                CommandSectionTitle(command.section)
                            }
                            CommandButton(
                                command: command,
                                selected: command.id == selectedCommandID,
                                action: command.action,
                                onHover: {
                                    if !command.disabled {
                                        selectedCommandID = command.id
                                    }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 332)
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
    var disabledReason: String? = nil
    var keywords = ""
    let action: () -> Void

    var systemImage: String {
        switch id {
        case "new-terminal":
            "plus.rectangle.on.rectangle"
        case "new-tab":
            "plus"
        case "duplicate-tab", "duplicate-workspace":
            "plus.square.on.square"
        case "split-right":
            "rectangle.split.2x1"
        case "split-down":
            "rectangle.split.1x2"
        case "next-tab", "next-pane":
            "arrow.right"
        case "previous-tab", "previous-pane":
            "arrow.left"
        case "notifications":
            "bell"
        case "jump-unread":
            "bell.badge"
        case "close-tab", "close-pane", "clear-notifications":
            "xmark"
        case "move-tab-left":
            "arrow.left.to.line"
        case "move-tab-right":
            "arrow.right.to.line"
        case "move-tab-next-pane":
            "arrowshape.turn.up.right"
        case "move-tab-new-split":
            "rectangle.split.2x1"
        case "toggle-zoom":
            "arrow.up.left.and.arrow.down.right"
        case "equalize-splits":
            "equal.square"
        case "workspace-overview":
            "rectangle.3.group"
        case "appearance-settings":
            "slider.horizontal.3"
        case "reset-workspace":
            "arrow.counterclockwise"
        case "install-codex-hooks":
            "bolt.horizontal.circle"
        case "debug-notification":
            "bell.badge"
        default:
            "command"
        }
    }

    var discoveryShortcut: String {
        if shortcut.hasPrefix("Cmd") {
            return shortcut
        }
        switch id {
        case "notifications":
            return "工具栏"
        default:
            return "Command Center"
        }
    }
}

private enum ConductorCommandCatalog {
    @MainActor
    static func items(
        model: ConductorWindowModel,
        run: @escaping (@escaping () -> Void) -> Void
    ) -> [CommandPaletteItem] {
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
            CommandPaletteItem(id: "split-right", section: "创建", title: "向右分屏", shortcut: "Cmd-D", disabled: !model.canSplit, disabledReason: "当前布局已到可用分屏上限", keywords: "split right vertical") {
                run {
                    model.splitRight()
                }
            },
            CommandPaletteItem(id: "split-down", section: "创建", title: "向下分屏", shortcut: "Cmd-Shift-D", disabled: !model.canSplit, disabledReason: "当前布局已到可用分屏上限", keywords: "split down horizontal") {
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
            CommandPaletteItem(id: "notifications", section: "导航", title: "通知中心", shortcut: "\(model.notifications.snapshot.unreadCount)", keywords: "notification unread agent") {
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
                disabledReason: "没有未读通知",
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
            CommandPaletteItem(id: "close-pane", section: "整理", title: "关闭分屏", shortcut: "Cmd-Shift-W", disabled: !model.canCloseFocusedPane, disabledReason: "至少保留一个分屏", keywords: "close pane split") {
                run {
                    model.closePane(model.workspace.focusedPaneID)
                }
            },
            CommandPaletteItem(id: "move-tab-left", section: "整理", title: "标签左移", shortcut: "Cmd-Shift-,", disabled: !model.canMoveSelectedTabLeft, disabledReason: "已经在最左侧", keywords: "move tab left") {
                run {
                    model.moveSelectedTabLeft()
                }
            },
            CommandPaletteItem(id: "move-tab-right", section: "整理", title: "标签右移", shortcut: "Cmd-Shift-.", disabled: !model.canMoveSelectedTabRight, disabledReason: "已经在最右侧", keywords: "move tab right") {
                run {
                    model.moveSelectedTabRight()
                }
            },
            CommandPaletteItem(id: "move-tab-next-pane", section: "整理", title: "移到下一个分屏", shortcut: "Cmd-Opt-M", disabled: !model.canMoveSelectedTabToNextPane, disabledReason: "需要另一个分屏", keywords: "move tab pane") {
                run {
                    model.moveSelectedTabToNextPane()
                }
            },
            CommandPaletteItem(id: "move-tab-new-split", section: "整理", title: "移到右侧新分屏", shortcut: "Cmd-Opt-Shift-M", disabled: !model.canMoveSelectedTabToNewSplit, disabledReason: "需要可移动标签和可用分屏空间", keywords: "move tab new split") {
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
                disabledReason: "需要多个分屏",
                keywords: "zoom pane"
            ) {
                run {
                    model.toggleZoom()
                }
            },
            CommandPaletteItem(id: "equalize-splits", section: "视图", title: "均分分屏", shortcut: "Cmd-Shift-=", disabled: model.workspace.root.leaves.count <= 1, disabledReason: "需要多个分屏", keywords: "equalize split layout") {
                run {
                    model.equalizeSplits()
                }
            },
            CommandPaletteItem(id: "workspace-overview", section: "视图", title: "工作区总览", shortcut: "Cmd-O", keywords: "workspace overview mission control") {
                run {
                    model.toggleWorkspaceOverview()
                }
            },
            CommandPaletteItem(id: "appearance-settings", section: "视图", title: "外观设置", shortcut: "Theme", keywords: "appearance theme settings") {
                run {
                    model.toggleSettingsPanel()
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
            CommandPaletteItem(id: "clear-notifications", section: "整理", title: "清空通知", shortcut: "Clear", disabled: model.notifications.records.isEmpty, disabledReason: "通知中心为空", keywords: "notification clear") {
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

    @MainActor
    static func shortcutGuideItems(model: ConductorWindowModel) -> [CommandShortcutGuideItem] {
        items(model: model) { _ in }
            .filter { $0.section != "调试" }
            .map { command in
                CommandShortcutGuideItem(
                    id: command.id,
                    section: command.section,
                    title: command.title,
                    shortcut: command.discoveryShortcut,
                    systemImage: command.systemImage
                )
            }
    }
}

private struct CommandShortcutGuideItem: Identifiable {
    let id: String
    let section: String
    let title: String
    let shortcut: String
    let systemImage: String
}

private struct CommandSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Rectangle()
                .fill(Color.white.opacity(0.24))
                .frame(height: 1)
        }
        .padding(.top, 5)
        .padding(.horizontal, 4)
    }
}

private struct CommandButton: View {
    let command: CommandPaletteItem
    var selected = false
    let action: () -> Void
    var onHover: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: command.systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.primaryText)
                        .lineLimit(1)
                    if let disabledReason = command.disabledReason, command.disabled {
                        Text(disabledReason)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(command.shortcut)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Color.white.opacity(command.disabled ? 0.10 : 0.24))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .frame(height: command.disabledReason != nil && command.disabled ? 42 : 36)
            .background(rowFill)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.row)
                    .stroke(selected ? Color.accentColor.opacity(0.52) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(command.disabled)
        .opacity(command.disabled ? 0.62 : 1)
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

    private var rowFill: Color {
        if selected {
            return Color.white.opacity(0.38)
        }
        if hovering {
            return Color.white.opacity(0.26)
        }
        return Color.white.opacity(0.11)
    }

    private var iconColor: Color {
        if command.disabled {
            return ConductorDesign.tertiaryText
        }
        return selected ? Color.accentColor : ConductorDesign.secondaryText
    }

    private var iconFill: Color {
        if selected {
            return Color.accentColor.opacity(0.13)
        }
        return Color.white.opacity(command.disabled ? 0.10 : 0.22)
    }
}

private struct CommandStatusStrip: View {
    let workspaceTitle: String
    let terminalTitle: String
    let paneCount: Int
    let terminalCount: Int
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 7) {
            CommandStatusChip(systemImage: "rectangle.3.group", title: "工作区", value: workspaceTitle)
            CommandStatusChip(systemImage: "terminal", title: "当前", value: terminalTitle)
            CommandStatusChip(systemImage: "square.split.2x2", title: "分屏", value: "\(paneCount)")
            CommandStatusChip(systemImage: unreadCount > 0 ? "bell.badge" : "bell", title: "通知", value: "\(unreadCount)")
        }
    }
}

private struct CommandStatusChip: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(Color.white.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct CommandSuggestionButton: View {
    let command: CommandPaletteItem
    let selected: Bool
    let onHover: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: command.action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: command.systemImage)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : Color.accentColor)
                    Spacer()
                    if command.disabled {
                        Image(systemName: "lock")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                    }
                }
                Text(command.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(command.shortcut)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.58) : Color.white.opacity(0.34), lineWidth: selected ? 1.4 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(command.disabled)
        .opacity(command.disabled ? 0.62 : 1)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
            if value && !command.disabled {
                onHover()
            }
        }
        .animation(ConductorMotion.micro, value: hovering)
        .animation(ConductorMotion.standard, value: selected)
        .help(command.title)
    }

    private var cardFill: Color {
        if selected {
            return Color.white.opacity(0.36)
        }
        if hovering {
            return Color.white.opacity(0.28)
        }
        return Color.white.opacity(0.18)
    }
}

private struct AppearanceSettingsPanel: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var selectedSection: SettingsPanelSection = .interface
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 178), spacing: 9)
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.08)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ConductorGlassSurface(style: .sidebar, clarity: model.appearance.chromeClarity, interactive: true) {
                HStack(spacing: 0) {
                    sidebar

                    Rectangle()
                        .fill(theme.shellStroke.opacity(0.16))
                        .frame(width: 1)
                        .padding(.vertical, 18)

                    contentPane
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous)
                    .stroke(theme.shellStroke.opacity(0.82), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .frame(width: 690, height: 486)
            .onExitCommand {
                model.hideSettingsPanel()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.accent.opacity(0.88))
                    .frame(width: 24, height: 24)
                    .background(theme.shellControlFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("设置")
                        .font(.conductorSystem(size: 13, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                    Text(model.theme.title)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 4)

            SidebarSeparator()
                .padding(.horizontal, -2)

            SidebarSectionTitle("分类")

            VStack(spacing: 3) {
                ForEach(SettingsPanelSection.allCases) { section in
                    SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section
                    ) {
                        model.performShellMotion {
                            selectedSection = section
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 164)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentPane: some View {
        VStack(spacing: 0) {
            header

            SidebarSeparator()
                .padding(.horizontal, 4)
                .padding(.vertical, 0)

            ScrollView {
                detailContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: selectedSection.systemImage)
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.accent.opacity(0.88))
                .frame(width: 24, height: 24)
                .background(theme.shellControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(selectedSection.title)
                    .font(.conductorSystem(size: 14, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                Text(selectedSection.subtitle)
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
            }

            Spacer()

            Button {
                model.performShellMotion {
                    model.hideSettingsPanel()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(theme.shellControlFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭设置")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .interface:
            interfaceSettings
        case .commands:
            commandSettings
        case .themes:
            themeSettings
        }
    }

    private var interfaceSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsSectionLabel("界面")
            AppearanceSegmentedControl(
                title: "密度",
                options: AppearanceDensity.allCases,
                selection: Binding(
                    get: { model.appearance.density },
                    set: { density in
                        model.performShellMotion {
                            model.setAppearanceDensity(density)
                        }
                    }
                ),
                titleForOption: \.title,
                subtitleForOption: \.subtitle
            )
            AppearanceSegmentedControl(
                title: "清晰度",
                options: ChromeClarity.allCases,
                selection: Binding(
                    get: { model.appearance.chromeClarity },
                    set: { clarity in
                        model.performShellMotion {
                            model.setChromeClarity(clarity)
                        }
                    }
                ),
                titleForOption: \.title,
                subtitleForOption: \.subtitle
            )
            AppearanceSegmentedControl(
                title: "字体",
                options: AppearanceFontScale.allCases,
                selection: Binding(
                    get: { model.appearance.fontScale },
                    set: { fontScale in
                        model.performShellMotion {
                            model.setFontScale(fontScale)
                        }
                    }
                ),
                titleForOption: \.title,
                subtitleForOption: \.subtitle
            )
            AppearanceToggleRow(
                title: "降低动态效果",
                subtitle: "减少面板、tab 和选中反馈的过渡",
                isOn: Binding(
                    get: { model.appearance.reducedMotion },
                    set: { model.setReducedMotion($0) }
                )
            )
        }
    }

    private var commandSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel("命令与快捷键")
            CommandShortcutGuide(model: model, height: 372)
        }
    }

    private var themeSettings: some View {
        VStack(alignment: .leading, spacing: 9) {
            SettingsSectionLabel("全壳主题")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
                ForEach(TerminalTheme.allCases) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        selected: model.theme == theme
                    ) {
                        model.performShellMotion {
                            model.theme = theme
                        }
                    }
                }
            }
        }
    }
}

private enum SettingsPanelSection: String, CaseIterable, Identifiable {
    case interface
    case commands
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interface:
            "界面"
        case .commands:
            "命令"
        case .themes:
            "主题"
        }
    }

    var subtitle: String {
        switch self {
        case .interface:
            "密度、清晰度、字体和动态效果"
        case .commands:
            "Command Center 与快捷入口"
        case .themes:
            "整套窗口、终端和强调色"
        }
    }

    var systemImage: String {
        switch self {
        case .interface:
            "rectangle.3.group"
        case .commands:
            "command"
        case .themes:
            "swatchpalette"
        }
    }
}

private struct SettingsSidebarItem: View {
    let section: SettingsPanelSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.accent : ConductorDesign.secondaryText)
                    .frame(width: 14)

                Text(section.title)
                    .font(.conductorSystem(size: 12, weight: selected ? .semibold : .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(rowFill)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
        .animation(ConductorMotion.standard, value: selected)
        .animation(ConductorMotion.micro, value: hovering)
        .help(section.title)
    }

    private var rowFill: Color {
        if selected {
            return theme.shellSelectedFill
        }
        if hovering {
            return theme.shellHoverFill
        }
        return Color.clear
    }
}

private struct AppearanceSegmentedControl<Option: Identifiable & Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let titleForOption: (Option) -> String
    let subtitleForOption: (Option) -> String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)

            HStack(spacing: 5) {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(titleForOption(option))
                            .font(.conductorSystem(size: 11, weight: selection == option ? .bold : .semibold, scale: fontScale))
                            .foregroundStyle(selection == option ? ConductorDesign.primaryText : ConductorDesign.secondaryText)
                            .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(selection == option ? theme.shellSelectedFill : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(selection == option ? theme.shellStroke.opacity(0.54) : Color.clear, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("\(titleForOption(option)) · \(subtitleForOption(option))")
                }
            }
            .padding(3)
            .background(theme.shellPanelStrong.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(theme.shellStroke.opacity(0.30), lineWidth: 1)
            }
        }
    }
}

private struct AppearanceToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
        }
        .toggleStyle(.switch)
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(theme.shellPanelStrong.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.shellStroke.opacity(0.30), lineWidth: 1)
        }
        .help(subtitle)
    }
}

private struct CommandShortcutGuide: View {
    @ObservedObject var model: ConductorWindowModel
    var height: CGFloat = 178
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var items: [CommandShortcutGuideItem] {
        ConductorCommandCatalog.shortcutGuideItems(model: model)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index == 0 || items[index - 1].section != item.section {
                        Text(item.section)
                            .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .padding(.top, index == 0 ? 0 : 4)
                            .padding(.horizontal, 2)
                    }
                    CommandShortcutGuideRow(item: item)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .frame(height: height)
        .background(theme.shellPanelStrong.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.shellStroke.opacity(0.30), lineWidth: 1)
        }
    }
}

private struct CommandShortcutGuideRow: View {
    let item: CommandShortcutGuideItem
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            Text(item.title)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(item.shortcut)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 17)
                .background(theme.shellSelectedFill)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}

private struct SettingsSectionLabel: View {
    let title: String
    @Environment(\.conductorFontScale) private var fontScale

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .foregroundStyle(ConductorDesign.tertiaryText)
            .padding(.horizontal, 2)
    }
}

private struct ThemePreviewCard: View {
    let theme: TerminalTheme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                previewWindow
                footer
            }
            .padding(8)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? theme.accent.opacity(0.78) : theme.shellStroke.opacity(hovering ? 0.58 : 0.34), lineWidth: selected ? 1.2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
        .animation(ConductorMotion.micro, value: selected)
        .help(theme.title)
    }

    private var previewWindow: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: theme.windowBackdropStops,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.white.opacity(0.82))
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(theme.accent.opacity(0.76))
                            .frame(width: 4, height: 4)
                        Spacer(minLength: 0)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.shellSelectedFill)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.shellHoverFill)
                        .frame(width: 26, height: 8)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(width: 45)
                .background(theme.shellPanelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(theme.accent.opacity(0.80))
                            .frame(width: 18, height: 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 28, height: 4)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 16)
                    .background(theme.terminalChrome.opacity(0.92))

                    VStack(alignment: .leading, spacing: 3) {
                        PreviewTerminalLine(prompt: "$", text: "swift build", accent: theme.accent)
                        PreviewTerminalLine(prompt: ">", text: "Conductor", accent: theme.accent)
                        Rectangle()
                            .fill(theme.accent.opacity(0.86))
                            .frame(width: 22, height: 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(theme.terminalBackground)
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(6)
        }
        .frame(height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 5) {
                Text(theme.title)
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ThemeSwatch(color: theme.accent)
                    ThemeSwatch(color: theme.shellPanelBackground)
                    ThemeSwatch(color: theme.terminalChrome)
                    ThemeSwatch(color: theme.terminalBackground)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? theme.accent : ConductorDesign.tertiaryText.opacity(0.70))
        }
    }

    private var cardFill: Color {
        if selected {
            return theme.shellPanelStrong.opacity(0.62)
        }
        return theme.shellPanelStrong.opacity(hovering ? 0.48 : 0.34)
    }
}

private struct PreviewTerminalLine: View {
    let prompt: String
    let text: String
    let accent: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(prompt)
                .foregroundStyle(accent)
            Text(text)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
        }
        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
    }
}

private struct ThemeSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: 16, height: 5)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Color.white.opacity(0.36), lineWidth: 0.5)
            }
    }
}

private struct WorkspaceOverviewPanel: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var query = ""
    @State private var highlightedWorkspaceID: WorkspaceID?
    @FocusState private var searchFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 214, maximum: 236), spacing: 10)
    ]

    private var filteredWorkspaces: [WorkspaceState] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return model.workspaces }
        return model.workspaces.filter { workspace in
            workspaceSearchText(workspace)
                .lowercased()
                .contains(normalizedQuery)
        }
    }

    private var filteredWorkspaceIDs: [WorkspaceID] {
        filteredWorkspaces.map(\.id)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ConductorGlassSurface(style: .palette, clarity: model.appearance.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    searchField

                    if filteredWorkspaces.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, alignment: .center, spacing: 10) {
                                ForEach(filteredWorkspaces) { workspace in
                                    WorkspaceOverviewCard(
                                        workspace: workspace,
                                        theme: model.theme,
                                        selected: workspace.id == model.workspace.id,
                                        highlighted: workspace.id == highlightedWorkspaceID,
                                        unreadCount: model.notifications.snapshot.unreadCount(for: workspace.id),
                                        unreadCountForPane: { paneID in
                                            model.notifications.snapshot.unreadCount(for: paneID)
                                        }
                                    ) {
                                        openWorkspace(workspace.id)
                                    } onHover: {
                                        highlightedWorkspaceID = workspace.id
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.bottom, 2)
                        }
                        .scrollIndicators(.visible)
                        .frame(maxHeight: 438)
                    }
                }
                .padding(12)
            }
            .frame(width: 760)
            .onAppear {
                highlightedWorkspaceID = model.workspace.id
                searchFocused = true
                ensureHighlight()
            }
            .onChange(of: query) {
                ensureHighlight()
            }
            .onChange(of: filteredWorkspaceIDs) {
                ensureHighlight()
            }
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    moveHighlight(by: -1)
                case .right:
                    moveHighlight(by: 1)
                case .up:
                    moveHighlight(by: -3)
                case .down:
                    moveHighlight(by: 3)
                default:
                    break
                }
            }
            .onSubmit {
                openHighlightedWorkspace()
            }
            .onExitCommand {
                model.hideWorkspaceOverview()
            }
            .animation(ConductorMotion.standard, value: highlightedWorkspaceID)
            .animation(ConductorMotion.micro, value: query)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("工作区总览")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ConductorDesign.primaryText)
                Text("\(model.workspaces.count) 个工作区")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ConductorDesign.tertiaryText)
            }

            Spacer()

            Button {
                ConductorMotion.perform {
                    model.hideWorkspaceOverview()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("关闭总览")
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConductorDesign.tertiaryText)
            TextField("搜索工作区", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($searchFocused)
            Text("↵")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ConductorDesign.tertiaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Color.white.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup)
                .stroke(Color.white.opacity(0.56), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text("没有匹配的工作区")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ConductorDesign.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private func workspaceSearchText(_ workspace: WorkspaceState) -> String {
        let titles = workspace.panes.values.flatMap { pane in
            pane.tabs.map(\.title)
        }
        let directories = workspace.panes.values.flatMap { pane in
            pane.tabs.compactMap(\.workingDirectory)
        }
        return ([workspace.title] + titles + directories).joined(separator: " ")
    }

    private func ensureHighlight() {
        guard !filteredWorkspaces.isEmpty else {
            highlightedWorkspaceID = nil
            return
        }
        if let highlightedWorkspaceID,
           filteredWorkspaces.contains(where: { $0.id == highlightedWorkspaceID }) {
            return
        }
        highlightedWorkspaceID = filteredWorkspaces.first(where: { $0.id == model.workspace.id })?.id ?? filteredWorkspaces.first?.id
    }

    private func moveHighlight(by offset: Int) {
        guard !filteredWorkspaces.isEmpty else {
            highlightedWorkspaceID = nil
            return
        }
        let currentIndex = filteredWorkspaces.firstIndex { $0.id == highlightedWorkspaceID } ?? 0
        let nextIndex = max(0, min(filteredWorkspaces.count - 1, currentIndex + offset))
        highlightedWorkspaceID = filteredWorkspaces[nextIndex].id
    }

    private func openHighlightedWorkspace() {
        ensureHighlight()
        guard let highlightedWorkspaceID else { return }
        openWorkspace(highlightedWorkspaceID)
    }

    private func openWorkspace(_ workspaceID: WorkspaceID) {
        ConductorMotion.perform {
            model.selectWorkspace(workspaceID)
        }
    }
}

private struct WorkspaceOverviewCard: View {
    let workspace: WorkspaceState
    let theme: TerminalTheme
    let selected: Bool
    let highlighted: Bool
    let unreadCount: Int
    let unreadCountForPane: (PaneID) -> Int
    let action: () -> Void
    let onHover: () -> Void
    @State private var hovering = false

    private var terminalCount: Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var focusedTerminalTitle: String {
        workspace.focusedPane?.selectedTab?.title ?? "终端"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                WorkspaceMiniLayout(
                    workspace: workspace,
                    theme: theme,
                    unreadCountForPane: unreadCountForPane
                )
                .frame(height: 114)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Image(systemName: selected ? "rectangle.3.group.fill" : "rectangle.3.group")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(selected ? theme.accent : ConductorDesign.secondaryText)
                            .frame(width: 16)
                        Text(workspace.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        if unreadCount > 0 {
                            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 16, minHeight: 15)
                                .background(theme.accent)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        WorkspaceOverviewMetric(systemImage: "square.split.2x2", value: "\(workspace.panes.count)")
                        WorkspaceOverviewMetric(systemImage: "terminal", value: "\(terminalCount)")
                        if workspace.isZoomed {
                            WorkspaceOverviewMetric(systemImage: "arrow.up.left.and.arrow.down.right", value: "Zoom")
                        }
                    }

                    Text(focusedTerminalTitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(9)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: selected || highlighted ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
            if value {
                onHover()
            }
        }
        .animation(ConductorMotion.standard, value: selected)
        .animation(ConductorMotion.standard, value: highlighted)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .help("\(workspace.title) · \(workspace.panes.count) 分屏 · \(terminalCount) 终端")
    }

    private var cardFill: Color {
        if selected {
            return Color.white.opacity(0.42)
        }
        if highlighted || hovering {
            return Color.white.opacity(0.31)
        }
        return Color.white.opacity(0.20)
    }

    private var borderColor: Color {
        if selected {
            return theme.accent.opacity(0.88)
        }
        if highlighted {
            return theme.accent.opacity(0.46)
        }
        return Color.white.opacity(0.38)
    }
}

private struct WorkspaceOverviewMetric: View {
    let systemImage: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 9.5, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(ConductorDesign.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(Color.white.opacity(0.22))
        .clipShape(Capsule())
    }
}

private struct WorkspaceMiniLayout: View {
    let workspace: WorkspaceState
    let theme: TerminalTheme
    let unreadCountForPane: (PaneID) -> Int

    var body: some View {
        WorkspaceMiniNode(
            node: workspace.root,
            workspace: workspace,
            theme: theme,
            unreadCountForPane: unreadCountForPane
        )
        .padding(5)
        .background(
            LinearGradient(
                colors: [
                    theme.terminalChrome.opacity(0.96),
                    theme.terminalRaisedBackground.opacity(0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct WorkspaceMiniNode: View {
    let node: SplitNode
    let workspace: WorkspaceState
    let theme: TerminalTheme
    let unreadCountForPane: (PaneID) -> Int

    var body: some View {
        GeometryReader { proxy in
            nodeView(node, size: proxy.size)
        }
    }

    @ViewBuilder
    private func nodeView(_ node: SplitNode, size: CGSize) -> some View {
        switch node {
        case let .leaf(paneID):
            WorkspaceMiniPane(
                pane: workspace.panes[paneID],
                focused: paneID == workspace.focusedPaneID,
                unreadCount: unreadCountForPane(paneID),
                theme: theme
            )
        case let .split(axis, first, second, fraction):
            let gap: CGFloat = 4
            if axis == .horizontal {
                HStack(spacing: gap) {
                    WorkspaceMiniNode(node: first, workspace: workspace, theme: theme, unreadCountForPane: unreadCountForPane)
                        .frame(width: max(1, (size.width - gap) * fraction))
                    WorkspaceMiniNode(node: second, workspace: workspace, theme: theme, unreadCountForPane: unreadCountForPane)
                        .frame(width: max(1, (size.width - gap) * (1 - fraction)))
                }
            } else {
                VStack(spacing: gap) {
                    WorkspaceMiniNode(node: first, workspace: workspace, theme: theme, unreadCountForPane: unreadCountForPane)
                        .frame(height: max(1, (size.height - gap) * fraction))
                    WorkspaceMiniNode(node: second, workspace: workspace, theme: theme, unreadCountForPane: unreadCountForPane)
                        .frame(height: max(1, (size.height - gap) * (1 - fraction)))
                }
            }
        }
    }
}

private struct WorkspaceMiniPane: View {
    let pane: PaneState?
    let focused: Bool
    let unreadCount: Int
    let theme: TerminalTheme

    private var title: String {
        pane?.selectedTab?.title ?? "终端"
    }

    private var tabCount: Int {
        pane?.tabs.count ?? 0
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.terminalBackground)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.terminalChrome.opacity(0.92))
                        .frame(height: 13)
                }

            HStack(spacing: 4) {
                Circle()
                    .fill(focused ? theme.accent : Color.white.opacity(0.32))
                    .frame(width: 4.5, height: 4.5)
                Text(title)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(focused ? 0.86 : 0.58))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if tabCount > 1 {
                    Text("\(tabCount)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.70))
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 13)

            VStack(alignment: .leading, spacing: 3) {
                Spacer(minLength: 13)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 32, height: 2)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(theme.accent.opacity(focused ? 0.92 : 0.40))
                    .frame(width: focused ? 44 : 25, height: 2)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 22, height: 2)
            }
            .padding(6)

            if unreadCount > 0 {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 6, height: 6)
                    .offset(x: -1, y: -1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(focused ? theme.accent.opacity(0.74) : Color.white.opacity(0.14), lineWidth: focused ? 1.3 : 1)
        }
    }
}

struct NotificationPanelView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        ConductorGlassSurface(style: .panel, clarity: model.appearance.chromeClarity, interactive: true) {
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
                        LazyVStack(spacing: 5) {
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
                        .padding(8)
                    }
                    .scrollIndicators(.visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }
            }
        }
        .frame(
            minWidth: ConductorTokens.Space.notificationPanelMinWidth,
            minHeight: ConductorTokens.Space.notificationPanelMinHeight
        )
        .animation(ConductorMotion.layout, value: model.notifications.records.map(\.id))
        .animation(ConductorMotion.emphasized, value: model.notifications.snapshot.unreadCount)
    }

    private var notificationHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: model.notifications.snapshot.unreadCount > 0 ? "bell.badge.fill" : "bell")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, height: 20)
                .background(Color.white.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("通知")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ConductorDesign.primaryText)
            if model.notifications.snapshot.unreadCount > 0 {
                Text("\(model.notifications.snapshot.unreadCount)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
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
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(model.notifications.snapshot.latestUnread == nil ? ConductorDesign.tertiaryText : Color.accentColor)
            .disabled(model.notifications.snapshot.latestUnread == nil)
            Button("清空") {
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.clearAllNotifications()
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(model.notifications.records.isEmpty ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
            .disabled(model.notifications.records.isEmpty)
        }
        .padding(.top, 24)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(Color.white.opacity(0.12))
    }

    private var emptyNotifications: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text("暂无通知")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ConductorDesign.secondaryText)
            Text("Codex 完成、终端通知和响铃都会出现在这里")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                ConductorMotion.perform {
                    model.installCodexNotificationHooks()
                }
            } label: {
                Label("连接 Codex", systemImage: "bolt.horizontal.circle")
                    .font(.system(size: 10.5, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 23)
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
        HStack(alignment: .top, spacing: 7) {
            Button {
                ConductorMotion.perform(onOpen)
            } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: iconName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.white.opacity(0.18))
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.26), lineWidth: 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if unread {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 5, height: 5)
                                    .offset(x: 2, y: -2)
                            }
                        }

                    VStack(alignment: .leading, spacing: 4) {
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
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(hovering ? 0.22 : 0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .help("清除通知")
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    unread ? Color.accentColor.opacity(0.26) : Color.white.opacity(0.32),
                    lineWidth: 1
                )
        }
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(notification.title)
                .font(.system(size: 11.5, weight: unread ? .semibold : .medium))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var rowBody: some View {
        if !notification.body.isEmpty {
            Text(notification.body)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowMetadata: some View {
        HStack(spacing: 5) {
            Label(kindLabel, systemImage: kindChipIcon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(Color.white.opacity(0.14))
                .clipShape(Capsule())

            Label(terminalTitle, systemImage: "terminal")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 16)
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

private struct WindowControlButtons: View {
    private let controls: [WindowControl] = [
        WindowControl(color: Color(red: 1.0, green: 0.33, blue: 0.32), accessibilityLabel: "关闭窗口") {
            NSApp.keyWindow?.performClose(nil)
        },
        WindowControl(color: Color(red: 1.0, green: 0.75, blue: 0.10), accessibilityLabel: "最小化窗口") {
            NSApp.keyWindow?.performMiniaturize(nil)
        },
        WindowControl(color: Color(red: 0.14, green: 0.78, blue: 0.27), accessibilityLabel: "缩放窗口") {
            NSApp.keyWindow?.performZoom(nil)
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
                .help(control.accessibilityLabel)
            }
        }
        .frame(height: 20)
    }
}

private struct WindowControl: Identifiable {
    let id = UUID()
    let color: Color
    let accessibilityLabel: String
    let action: () -> Void
}

private struct ConductorSidebar: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var renamingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""
    @Environment(\.conductorFontScale) private var fontScale

    private var terminalCount: Int {
        model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var focusedTerminalTitle: String {
        model.workspace.focusedPane?.selectedTab?.title ?? "无"
    }

    private var sidebarHeaderHeight: CGFloat {
        model.sidebarVisible ? 54 : 82
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
        .frame(width: model.sidebarVisible ? ConductorDesign.sidebarWidth(for: model.appearance) : ConductorDesign.sidebarCollapsedWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            ConductorGlassSurface(style: .sidebar, clarity: model.appearance.chromeClarity, interactive: true) {
                model.theme.shellPanelBackground
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous)
                .stroke(model.theme.shellStroke.opacity(0.82), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if !model.sidebarVisible {
                collapsedTrafficLightShelf
            }
        }
        .animation(model.shellAnimation(ConductorMotion.layout), value: model.sidebarVisible)
        .animation(model.shellAnimation(ConductorMotion.standard), value: model.workspace.id)
        .animation(model.shellAnimation(ConductorMotion.layout), value: model.workspaces.map(\.id))
        .animation(model.shellAnimation(ConductorMotion.layout), value: model.appearance.density)
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        if model.sidebarVisible {
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
            ConductorMotion.perform(ConductorMotion.layout) {
                finishWorkspaceRenameIfNeeded()
                model.sidebarVisible.toggle()
            }
        } label: {
            Image(systemName: model.sidebarVisible ? "chevron.left" : "sidebar.left")
                .font(.conductorSystem(size: 11.5, weight: .bold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 26, height: 24)
                .background(model.theme.shellControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .help(model.sidebarVisible ? "收起侧边栏" : "展开侧边栏")
    }

    private var collapsedTrafficLightShelf: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.26),
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 58)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(model.theme.shellStroke.opacity(0.30))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
            }
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            workspaceSection
                .frame(maxHeight: .infinity)

            SidebarSeparator()

            SidebarSectionTitle("状态")
            SidebarStatusSummary(
                splitCount: model.workspace.panes.count,
                terminalCount: terminalCount,
                unreadCount: model.notifications.snapshot.unreadCount,
                focusedTerminalTitle: focusedTerminalTitle
            )

            SidebarSeparator()

            SidebarSectionTitle("快捷操作")
            primaryQuickActions(showsLabels: true)

            Spacer(minLength: 8)

            SidebarActionRow(icon: "paintpalette", title: model.theme.title, help: "切换主题") {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform {
                    model.cycleTheme()
                }
            }
            .contextMenu {
                themeMenuItems
            }
            SidebarActionRow(icon: "gearshape", title: "设置", help: "设置") {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform {
                    model.toggleSettingsPanel()
                }
            }
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
                        .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
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

            primaryQuickActions(showsLabels: false)

            Spacer(minLength: 8)

            SidebarRailButton(icon: "paintpalette", help: model.theme.title) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform {
                    model.cycleTheme()
                }
            }
            .contextMenu {
                themeMenuItems
            }
            SidebarRailButton(icon: "gearshape", help: "设置") {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform {
                    model.toggleSettingsPanel()
                }
            }
        }
    }

    @ViewBuilder
    private var themeMenuItems: some View {
        ForEach(TerminalTheme.allCases) { theme in
            Button(theme.title) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform {
                    model.theme = theme
                }
            }
        }
    }

    @ViewBuilder
    private func primaryQuickActions(showsLabels: Bool) -> some View {
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

    private func scrollSidebarSelection(_ proxy: ScrollViewProxy) {
        withAnimation(ConductorMotion.standard) {
            proxy.scrollTo(model.workspace.id, anchor: .center)
        }
    }
}

private struct SidebarStatusSummary: View {
    let splitCount: Int
    let terminalCount: Int
    let unreadCount: Int
    let focusedTerminalTitle: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                SidebarStatusPill(title: "分屏", value: "\(splitCount)")
                SidebarStatusPill(title: "终端", value: "\(terminalCount)")
                if unreadCount > 0 {
                    SidebarStatusPill(title: "未读", value: unreadCount > 99 ? "99+" : "\(unreadCount)", highlighted: true)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.accent.opacity(0.88))
                    .frame(width: 14)
                Text("焦点")
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                Text(focusedTerminalTitle)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.shellPanelStrong.opacity(0.36))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row + 2, style: .continuous))
    }
}

private struct SidebarStatusPill: View {
    let title: String
    let value: String
    var highlighted = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                .foregroundStyle(highlighted ? theme.accent.opacity(0.86) : ConductorDesign.tertiaryText)
            Text(value)
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                .foregroundStyle(highlighted ? theme.accent : ConductorDesign.primaryText)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(highlighted ? theme.accent.opacity(0.12) : theme.shellControlFill.opacity(0.72))
        .clipShape(Capsule())
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

private struct SidebarRailButton: View {
    let icon: String
    var selected = false
    var disabled = false
    let help: String
    let action: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            ConductorMotion.perform(action)
        } label: {
            Image(systemName: icon)
                .font(.conductorSystem(size: 13, weight: .semibold, scale: fontScale))
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
                .frame(width: 34, height: 34)
                .background(selected ? theme.shellSelectedFill : Color.clear)
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
    @Environment(\.conductorFontScale) private var fontScale

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
            .foregroundStyle(ConductorDesign.tertiaryText)
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
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
            Text(title)
                .font(.conductorSystem(size: 12, weight: selected ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
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
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

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
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .frame(width: 14)
                .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
            RenameTextField(
                text: $titleDraft,
                placeholder: "工作区名称",
                font: .conductorSystemFont(ofSize: 12, weight: .semibold, scale: fontScale),
                textColor: NSColor.labelColor,
                onCommit: onCommitRename,
                onCancel: onCancelRename
            )
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(selected ? theme.shellSelectedFill : theme.shellHoverFill)
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
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .frame(width: 14)
                    .foregroundStyle(selected ? Color.accentColor : ConductorDesign.secondaryText)
                Text(title)
                    .font(.conductorSystem(size: 12, weight: selected ? .semibold : .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text("\(terminalCount)")
                    .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 14)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(selected ? theme.shellSelectedFill : (hovering ? theme.shellHoverFill : Color.clear))
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
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            ConductorMotion.perform(action)
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
            .foregroundStyle(ConductorDesign.secondaryText)
            .padding(.horizontal, showsTitle ? 8 : 0)
            .frame(width: showsTitle ? nil : 34, height: showsTitle ? 28 : 34)
            .background(hovering ? theme.shellHoverFill : Color.clear)
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

private struct ConductorToolbar: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var editingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""

    var body: some View {
        ConductorTerminalToolbarSurface(theme: model.theme) {
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
                    ConductorSegmentDivider()
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
                    ConductorSegmentDivider()
                    ConductorIconButton(systemImage: "rectangle.split.1x2", help: "向下分屏 Cmd-Shift-D", title: "下分屏", disabled: !model.canSplit) {
                        finishWorkspaceRenameIfNeeded()
                        model.splitDown()
                    }
                    ConductorSegmentDivider()
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
                        systemImage: "rectangle.3.group",
                        help: "工作区总览 Cmd-O",
                        title: nil,
                        active: model.workspaceOverviewVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.toggleWorkspaceOverview()
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: model.notifications.snapshot.unreadCount > 0 ? "bell.badge" : "bell",
                        help: "通知中心",
                        title: model.notifications.snapshot.unreadCount > 0 ? "\(model.notifications.snapshot.unreadCount)" : nil,
                        active: model.notificationPanelVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.toggleNotificationPanel()
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(systemImage: "ellipsis", help: "命令面板 Cmd-K", title: "命令") {
                        finishWorkspaceRenameIfNeeded()
                        model.toggleCommandPalette()
                    }
                }
            }
            .controlSize(.small)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: ConductorDesign.toolbarHeight(for: model.appearance))
        }
        .frame(height: ConductorDesign.toolbarHeight(for: model.appearance))
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
    @State private var scrollTargetID: WorkspaceID?

    private var workspaceIDs: [WorkspaceID] {
        model.workspaces.map(\.id)
    }

    var body: some View {
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
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollTargetID, anchor: .center)
        .onDrop(
            of: [UTType.text],
            delegate: WorkspaceTabDropDelegate(
                targetWorkspaceID: nil,
                model: model
            )
        )
        .onAppear {
            syncScrollTarget(animated: false)
        }
        .onChange(of: model.workspace.id) {
            syncScrollTarget(animated: true)
        }
        .onChange(of: workspaceIDs) {
            syncScrollTarget(animated: true)
        }
        .frame(
            minWidth: WorkspaceTabMetrics.width(for: model.appearance),
            maxWidth: .infinity,
            minHeight: WorkspaceTabMetrics.height(for: model.appearance),
            maxHeight: WorkspaceTabMetrics.height(for: model.appearance),
            alignment: .leading
        )
        .clipped()
        .mask(ConductorHorizontalFadeMask())
        .animation(ConductorMotion.layout, value: workspaceIDs)
    }

    private func syncScrollTarget(animated: Bool) {
        guard workspaceIDs.contains(model.workspace.id) else { return }
        let update = {
            scrollTargetID = model.workspace.id
        }
        if animated {
            model.performShellMotion(ConductorMotion.standard, update)
        } else {
            update()
        }
    }

    private func workspaceTabView(for workspace: WorkspaceState) -> some View {
        WorkspaceTopTab(
            workspace: workspace,
            unreadCount: model.notifications.snapshot.unreadCount(for: workspace.id),
            selected: workspace.id == model.workspace.id,
            accent: model.theme.accent,
            appearance: model.appearance,
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
    static func width(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.workspaceTabWidth
    }

    static func height(for appearance: AppearancePreferences) -> CGFloat {
        appearance.density.workspaceTabHeight
    }

    static let spacing: CGFloat = 8
    static let edgePadding: CGFloat = 2
}

private struct WorkspaceTopTab: View {
    let workspace: WorkspaceState
    let unreadCount: Int
    let selected: Bool
    let accent: Color
    let appearance: AppearancePreferences
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
    @Environment(\.conductorFontScale) private var fontScale

    private var terminalCount: Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var tabFill: some ShapeStyle {
        LinearGradient(
            colors: [
                selected ? accent.opacity(0.150 * appearance.chromeClarity.accentFillMultiplier) : (hovering ? Color.white.opacity(0.070) : Color.white.opacity(0.030)),
                selected ? Color.white.opacity(0.068) : (hovering ? Color.white.opacity(0.040) : Color.white.opacity(0.018))
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var tabStroke: Color {
        if selected {
            return accent.opacity(0.40 * appearance.chromeClarity.accentFillMultiplier)
        }
        return Color.white.opacity(hovering ? 0.120 : 0.070)
    }

    private var titleColor: Color {
        selected ? ConductorDesign.terminalText : ConductorDesign.terminalTextMuted
    }

    var body: some View {
        HStack(spacing: 7) {
            if editing {
                WorkspaceTabGlyph(selected: true, accent: accent)
                RenameTextField(
                    text: $titleDraft,
                    placeholder: "工作区名称",
                    font: .conductorSystemFont(ofSize: 11.5, weight: .bold, scale: fontScale),
                    textColor: NSColor.labelColor,
                    onCommit: onCommitRename,
                    onCancel: onCancelRename
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    renameCancelled = false
                }
            } else {
                WorkspaceTabGlyph(selected: selected, accent: accent)
                Text(workspace.title)
                    .font(.conductorSystem(size: 11.5, weight: selected ? .bold : .semibold, scale: fontScale))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(terminalCount)")
                    .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(selected ? accent.opacity(0.94) : ConductorDesign.terminalTextMuted.opacity(0.86))
                    .padding(.horizontal, 5)
                    .frame(minWidth: 21, minHeight: 20)
                    .background(selected ? accent.opacity(0.135 * appearance.chromeClarity.accentFillMultiplier) : Color.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
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
                        .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                        .foregroundStyle(canClose ? titleColor.opacity(selected || hovering ? 0.74 : 0.52) : Color.clear)
                        .frame(width: 13, height: 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ConductorPressButtonStyle())
                .disabled(!canClose)
                .help("关闭工作区")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, editing ? 8 : 6)
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background(tabFill)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(tabStroke, lineWidth: 1)
        }
        .animation(nil, value: selected)
        .animation(ConductorMotion.micro, value: hovering)
        .animation(ConductorMotion.standard, value: editing)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .onHover { value in
            withAnimation(ConductorMotion.micro) {
                hovering = value
            }
        }
        .contentShape(Capsule())
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

private struct WorkspaceTabGlyph: View {
    let selected: Bool
    let accent: Color

    var body: some View {
        Grid(horizontalSpacing: 2.4, verticalSpacing: 2.4) {
            GridRow {
                cell(opacity: selected ? 0.98 : 0.62)
                cell(opacity: selected ? 0.74 : 0.38)
            }
            GridRow {
                cell(opacity: selected ? 0.56 : 0.34)
                cell(opacity: selected ? 0.88 : 0.48)
            }
        }
        .frame(width: 16, height: 16)
        .padding(2)
        .background(selected ? accent.opacity(0.105) : Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(selected ? accent.opacity(0.24) : Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    private func cell(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.6, style: .continuous)
            .fill((selected ? accent : ConductorDesign.terminalTextMuted).opacity(opacity))
            .frame(width: 4.6, height: 4.6)
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
