import ConductorCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private func withoutShellAnimation(_ action: () -> Void) {
    ConductorMotion.withoutAnimation(action)
}

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorRootView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .trailing) {
                shellContent
            }
        }
        .padding(.leading, ConductorDesign.shellLeadingPadding)
        .padding(.trailing, ConductorDesign.shellTrailingPadding)
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
        .environment(\.colorScheme, model.theme.chromeColorScheme)
        .preferredColorScheme(model.theme.chromeColorScheme)
        .tint(model.theme.floatingEmphasis)
        .environment(\.conductorFontScale, model.appearance.fontScale)
        .environment(\.conductorFontFamily, model.appearance.fontFamily)
        .environment(\.conductorTheme, model.theme)
        .environment(\.locale, model.appearance.language.locale)
        .overlay {
            ZStack {
                if model.commandPaletteVisible {
                    CommandPaletteView(model: model)
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.panelTransition)
                }
                if model.settingsPanelVisible {
                    AppearanceSettingsPanel(model: model)
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.panelTransition)
                }
                if model.workspaceOverviewVisible {
                    WorkspaceOverviewPanel(model: model)
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.panelTransition)
                }
            }
        }
        .animation(model.shellAnimation(ConductorMotion.panel), value: model.commandPaletteVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: model.settingsPanelVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: model.workspaceOverviewVisible)
    }

    private var shellContent: some View {
        HStack(alignment: .top, spacing: ConductorDesign.shellGap) {
            ConductorSidebar(model: model)
            ConductorShellJoiner(theme: model.theme)

            VStack(spacing: 0) {
                ConductorToolbar(model: model)
                ZStack(alignment: .topTrailing) {
                    SplitNodeView(node: model.workspace.visibleRoot, model: model)
                        .background(model.theme.terminalBackground)
                    if model.terminalSearchVisible {
                        TerminalContextSearchBar(model: model)
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                            .transition(ConductorMotion.searchTransition)
                    }
                }
                .animation(model.shellAnimation(ConductorMotion.search), value: model.terminalSearchVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(model.theme.terminalBackground)
            .overlay(alignment: .leading) {
                TerminalSidebarContactWash(theme: model.theme)
                    .allowsHitTesting(false)
            }
        }
    }

}

private struct TerminalContextSearchBar: View {
    @ObservedObject var model: ConductorWindowModel
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily

    private var metadata: TerminalSearchMetadata {
        model.focusedTerminalSearchMetadata
    }

    private var selectedTarget: TerminalSearchTargetDisplay? {
        model.terminalSearchTargets.first { $0.id == model.terminalSearchTargetID } ??
            model.terminalSearchTargets.first { $0.id == model.focusedTerminalID }
    }

    private var matchText: String {
        guard !query.isEmpty else { return L("输入搜索", "Type to search") }
        guard let total = metadata.total else { return L("搜索中", "Searching") }
        guard total > 0 else { return L("无结果", "No results") }
        if let selected = metadata.selected {
            return "\(selected + 1)/\(total)"
        }
        return "0/\(total)"
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.58))

            Menu {
                ForEach(model.terminalSearchTargets) { target in
                    Button {
                        model.selectTerminalSearchTarget(target.id)
                    } label: {
                        Label(
                            "\(target.title) · \(target.subtitle)",
                            systemImage: target.id == selectedTarget?.id ? "checkmark" : "terminal"
                        )
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: selectedTarget?.isActive == true ? "scope" : "terminal")
                        .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    Text(selectedTarget?.title ?? L("当前终端", "Current terminal"))
                        .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.conductorSystem(size: 8.5, weight: .bold, family: fontFamily, scale: fontScale))
                        .opacity(0.62)
                }
                .foregroundStyle(theme.shellChromeText.opacity(0.72))
                .padding(.horizontal, 8)
                .frame(width: 118, height: 22, alignment: .leading)
                .background(Color.white.opacity(theme.usesDarkChrome ? 0.045 : 0.075))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .help(L("选择搜索的终端", "Choose terminal to search"))

            TextField(L("搜索选中终端", "Search selected terminal"), text: $query)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 11.5, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText)
                .frame(width: 168)
                .focused($searchFocused)
                .onSubmit {
                    model.performCommand(.findNext)
                }

            Text(matchText)
                .font(.conductorSystem(size: 10, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.52))
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)

            TerminalSearchIconButton(
                systemImage: "chevron.up",
                help: L("上一个结果 Shift-Cmd-G", "Previous result Shift-Cmd-G"),
                disabled: !hasQuery
            ) {
                model.performCommand(.findPrevious)
            }

            TerminalSearchIconButton(
                systemImage: "chevron.down",
                help: L("下一个结果 Cmd-G", "Next result Cmd-G"),
                disabled: !hasQuery
            ) {
                model.performCommand(.findNext)
            }

            TerminalSearchIconButton(
                systemImage: "xmark",
                help: L("关闭搜索 Esc", "Close search Esc")
            ) {
                model.closeTerminalSearch()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.96 : 0.92))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.10 : 0.18), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.26 : 0.14), radius: 14, x: 0, y: 8)
        }
        .onAppear {
            query = model.terminalSearchQuery
            focusSearchField()
        }
        .onChange(of: model.terminalSearchFocusGeneration) { _, _ in
            focusSearchField()
        }
        .onChange(of: query) { _, next in
            model.setTerminalSearchQuery(next)
        }
        .onChange(of: model.terminalSearchQuery) { _, next in
            guard next != query else { return }
            query = next
        }
    }

    private func focusSearchField() {
        Task { @MainActor in
            searchFocused = true
        }
    }
}

private struct TerminalSearchIconButton: View {
    let systemImage: String
    let help: String
    var disabled = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            guard !disabled else { return }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(theme.shellChromeText.opacity(disabled ? 0.26 : (hovering ? 0.82 : 0.56)))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(hovering && !disabled ? 0.070 : 0.018))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.95))
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(ConductorMotion.hover, value: hovering)
        .help(help)
    }
}

private struct ConductorShellJoiner: View {
    let theme: TerminalTheme

    var body: some View {
        Color.clear
            .frame(width: ConductorDesign.shellJoinerWidth)
            .frame(maxHeight: .infinity)
            .allowsHitTesting(false)
    }
}

private struct TerminalSidebarContactWash: View {
    let theme: TerminalTheme

    var body: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(theme.usesDarkChrome ? 0.10 : 0.030),
                theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.04 : 0.018),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: theme.usesDarkChrome ? 12 : 8)
    }
}

struct NotificationPanelRootView: View {
    @ObservedObject var model: ConductorWindowModel

    var body: some View {
        NotificationPanelView(model: model)
            .environment(\.colorScheme, model.theme.chromeColorScheme)
            .preferredColorScheme(model.theme.chromeColorScheme)
            .environment(\.conductorTheme, model.theme)
            .environment(\.conductorFontScale, model.appearance.fontScale)
            .environment(\.conductorFontFamily, model.appearance.fontFamily)
            .environment(\.locale, model.appearance.language.locale)
    }
}

private struct FloatingPanelHeader<Trailing: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let closeHelp: String
    let onClose: () -> Void
    let trailing: Trailing
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    init(
        systemImage: String,
        title: String,
        subtitle: String,
        closeHelp: String,
        onClose: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.closeHelp = closeHelp
        self.onClose = onClose
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 24, height: 24)
                .background(theme.floatingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.conductorSystem(size: 14, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 10)

            trailing

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(theme.floatingControlFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help(closeHelp)
        }
    }
}

private extension FloatingPanelHeader where Trailing == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String,
        closeHelp: String,
        onClose: @escaping () -> Void
    ) {
        self.init(
            systemImage: systemImage,
            title: title,
            subtitle: subtitle,
            closeHelp: closeHelp,
            onClose: onClose
        ) {
            EmptyView()
        }
    }
}

private struct FloatingPanelDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.floatingSeparator)
            .frame(height: 1)
    }
}

private struct CommandPaletteView: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var query = ""
    @State private var selectedCommandID: String?
    @FocusState private var searchFocused: Bool
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

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

    private var filteredCommandIDs: [String] {
        filteredCommands.map(\.id)
    }

    var body: some View {
        ZStack {
            ConductorGlassSurface(style: .panel, clarity: model.appearance.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 10) {
                    commandHeader
                    FloatingPanelDivider()
                    commandSearchField
                    commandResults
                }
                .padding(12)
            }
            .frame(width: 690, height: 486)
            .onAppear {
                focusSearchField()
                ensureSelection()
            }
            .onChange(of: query) {
                ensureSelection()
            }
            .animation(ConductorMotion.selection, value: selectedCommandID)
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
        FloatingPanelHeader(
            systemImage: "command",
            title: "Command Center",
            subtitle: model.workspace.title,
            closeHelp: L("关闭命令中心", "Close Command Center")
        ) {
            model.hideCommandPalette()
        }
    }

    private var commandSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            TextField(L("搜索命令", "Search commands"), text: $query)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 13, weight: .medium, scale: fontScale))
                .focused($searchFocused)
            Text("↵")
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(theme.floatingControlStrongFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup)
                .stroke(theme.floatingStroke, lineWidth: 1)
        }
    }

    private var commandResults: some View {
        Group {
            if filteredCommands.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.conductorSystem(size: 22, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    Text(L("没有匹配的命令", "No matching commands"))
                        .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
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
                            .transition(ConductorMotion.rowTransition)
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(ConductorMotion.list, value: filteredCommandIDs)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity)
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

    private func focusSearchField() {
        Task { @MainActor in
            searchFocused = true
        }
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
        case "new-workspace":
            WorkspaceChromeGlyph.systemName(selected: false)
        case "new-terminal":
            "plus.rectangle.on.rectangle"
        case "duplicate-tab", "duplicate-workspace":
            "plus.square.on.square"
        case "split-right":
            "rectangle.split.2x1"
        case "split-down":
            "rectangle.split.1x2"
        case "next-tab", "next-pane", "focus-right":
            "arrow.right"
        case "previous-tab", "previous-pane", "focus-left":
            "arrow.left"
        case "focus-up":
            "arrow.up"
        case "focus-down":
            "arrow.down"
        case "resize-left", "resize-right":
            "arrow.left.and.right"
        case "resize-up", "resize-down":
            "arrow.up.and.down"
        case "notifications":
            "bell"
        case "jump-unread":
            "bell.badge"
        case "context-search", "find-next", "find-previous":
            "magnifyingglass"
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
        case "toggle-fullscreen":
            "arrow.up.left.and.arrow.down.right.circle"
        case "flash-focused-pane":
            "scope"
        case "equalize-splits":
            "equal.square"
        case "workspace-overview":
            WorkspaceChromeGlyph.systemName(selected: false)
        case "appearance-settings":
            "slider.horizontal.3"
        case "reset-workspace":
            "arrow.counterclockwise"
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
            return L("工具栏", "Toolbar")
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
        func perform(_ command: ConductorShellCommand) {
            run {
                _ = model.performCommand(command)
            }
        }

        func canPerform(_ command: ConductorShellCommand) -> Bool {
            model.canPerformCommand(command)
        }

        return [
            CommandPaletteItem(id: "new-workspace", section: L("创建", "Create"), title: L("新建工作区", "New Workspace"), shortcut: "Cmd-N", keywords: "workspace new") {
                perform(.newWorkspace)
            },
            CommandPaletteItem(id: "new-terminal", section: L("创建", "Create"), title: L("新开终端", "New Terminal"), shortcut: "Cmd-T", keywords: "terminal pane shell") {
                perform(.newTerminal)
            },
            CommandPaletteItem(id: "duplicate-tab", section: L("创建", "Create"), title: L("复制当前标签", "Duplicate Current Tab"), shortcut: "Duplicate", keywords: "copy tab duplicate") {
                perform(.duplicateSelectedTab)
            },
            CommandPaletteItem(id: "split-right", section: L("创建", "Create"), title: L("向右分屏", "Split Right"), shortcut: "Cmd-D", disabled: !canPerform(.splitRight), disabledReason: L("当前布局已到可用分屏上限", "Current layout has reached the split limit"), keywords: "split right vertical") {
                perform(.splitRight)
            },
            CommandPaletteItem(id: "split-down", section: L("创建", "Create"), title: L("向下分屏", "Split Down"), shortcut: "Cmd-Shift-D", disabled: !canPerform(.splitDown), disabledReason: L("当前布局已到可用分屏上限", "Current layout has reached the split limit"), keywords: "split down horizontal") {
                perform(.splitDown)
            },
            CommandPaletteItem(id: "next-tab", section: L("导航", "Navigate"), title: L("下一个标签", "Next Tab"), shortcut: "Cmd-]", keywords: "next tab") {
                perform(.selectNextTab)
            },
            CommandPaletteItem(id: "previous-tab", section: L("导航", "Navigate"), title: L("上一个标签", "Previous Tab"), shortcut: "Cmd-[", keywords: "previous tab") {
                perform(.selectPreviousTab)
            },
            CommandPaletteItem(id: "next-pane", section: L("导航", "Navigate"), title: L("下一个分屏", "Next Pane"), shortcut: "Cmd-Shift-]", keywords: "next pane focus") {
                perform(.focusNextPane)
            },
            CommandPaletteItem(id: "previous-pane", section: L("导航", "Navigate"), title: L("上一个分屏", "Previous Pane"), shortcut: "Cmd-Shift-[", keywords: "previous pane focus") {
                perform(.focusPreviousPane)
            },
            CommandPaletteItem(id: "notifications", section: L("导航", "Navigate"), title: L("通知中心", "Notification Center"), shortcut: "Cmd-Opt-N", keywords: "notification unread agent") {
                perform(.toggleNotifications)
            },
            CommandPaletteItem(
                id: "jump-unread",
                section: L("导航", "Navigate"),
                title: L("跳到最新未读", "Jump to Latest Unread"),
                shortcut: "Cmd-Opt-J",
                disabled: !canPerform(.jumpToLatestUnread),
                disabledReason: L("没有未读通知", "No unread notifications"),
                keywords: "notification unread jump"
            ) {
                perform(.jumpToLatestUnread)
            },
            CommandPaletteItem(id: "context-search", section: L("导航", "Navigate"), title: L("上下文搜索", "Context Search"), shortcut: "Cmd-F", keywords: "find search terminal context") {
                perform(.showTerminalSearch)
            },
            CommandPaletteItem(
                id: "find-next",
                section: L("导航", "Navigate"),
                title: L("下一个搜索结果", "Find Next"),
                shortcut: "Cmd-G",
                disabled: !canPerform(.findNext),
                disabledReason: L("先打开上下文搜索", "Open Context Search first"),
                keywords: "find next search result"
            ) {
                perform(.findNext)
            },
            CommandPaletteItem(
                id: "find-previous",
                section: L("导航", "Navigate"),
                title: L("上一个搜索结果", "Find Previous"),
                shortcut: "Cmd-Shift-G",
                disabled: !canPerform(.findPrevious),
                disabledReason: L("先打开上下文搜索", "Open Context Search first"),
                keywords: "find previous search result"
            ) {
                perform(.findPrevious)
            },
            CommandPaletteItem(id: "focus-left", section: L("导航", "Navigate"), title: L("聚焦左侧分屏", "Focus Pane Left"), shortcut: "Cmd-Opt-←", keywords: "focus pane left") {
                perform(.focusPaneLeft)
            },
            CommandPaletteItem(id: "focus-right", section: L("导航", "Navigate"), title: L("聚焦右侧分屏", "Focus Pane Right"), shortcut: "Cmd-Opt-→", keywords: "focus pane right") {
                perform(.focusPaneRight)
            },
            CommandPaletteItem(id: "focus-up", section: L("导航", "Navigate"), title: L("聚焦上方分屏", "Focus Pane Up"), shortcut: "Cmd-Opt-↑", keywords: "focus pane up") {
                perform(.focusPaneUp)
            },
            CommandPaletteItem(id: "focus-down", section: L("导航", "Navigate"), title: L("聚焦下方分屏", "Focus Pane Down"), shortcut: "Cmd-Opt-↓", keywords: "focus pane down") {
                perform(.focusPaneDown)
            },
            CommandPaletteItem(id: "close-tab", section: L("整理", "Organize"), title: L("关闭标签", "Close Tab"), shortcut: "Cmd-W", keywords: "close tab") {
                perform(.closeSelectedTab)
            },
            CommandPaletteItem(id: "close-pane", section: L("整理", "Organize"), title: L("关闭分屏", "Close Pane"), shortcut: "Cmd-Shift-W", disabled: !canPerform(.closeFocusedPane), disabledReason: L("至少保留一个分屏", "Keep at least one pane"), keywords: "close pane split") {
                perform(.closeFocusedPane)
            },
            CommandPaletteItem(id: "move-tab-left", section: L("整理", "Organize"), title: L("标签左移", "Move Tab Left"), shortcut: "Cmd-Shift-,", disabled: !canPerform(.moveTabLeft), disabledReason: L("已经在最左侧", "Already on the left"), keywords: "move tab left") {
                perform(.moveTabLeft)
            },
            CommandPaletteItem(id: "move-tab-right", section: L("整理", "Organize"), title: L("标签右移", "Move Tab Right"), shortcut: "Cmd-Shift-.", disabled: !canPerform(.moveTabRight), disabledReason: L("已经在最右侧", "Already on the right"), keywords: "move tab right") {
                perform(.moveTabRight)
            },
            CommandPaletteItem(id: "move-tab-next-pane", section: L("整理", "Organize"), title: L("移到下一个分屏", "Move to Next Pane"), shortcut: "Cmd-Opt-M", disabled: !canPerform(.moveTabToNextPane), disabledReason: L("需要另一个分屏", "Requires another pane"), keywords: "move tab pane") {
                perform(.moveTabToNextPane)
            },
            CommandPaletteItem(id: "move-tab-new-split", section: L("整理", "Organize"), title: L("移到右侧新分屏", "Move to New Right Split"), shortcut: "Cmd-Opt-Shift-M", disabled: !canPerform(.moveTabToNewRightSplit), disabledReason: L("需要可移动标签和可用分屏空间", "Requires a movable tab and split space"), keywords: "move tab new split") {
                perform(.moveTabToNewRightSplit)
            },
            CommandPaletteItem(id: "resize-left", section: L("整理", "Organize"), title: L("向左调整分屏", "Resize Pane Left"), shortcut: "Cmd-Shift-←", disabled: !canPerform(.resizePaneLeft), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split left") {
                perform(.resizePaneLeft)
            },
            CommandPaletteItem(id: "resize-right", section: L("整理", "Organize"), title: L("向右调整分屏", "Resize Pane Right"), shortcut: "Cmd-Shift-→", disabled: !canPerform(.resizePaneRight), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split right") {
                perform(.resizePaneRight)
            },
            CommandPaletteItem(id: "resize-up", section: L("整理", "Organize"), title: L("向上调整分屏", "Resize Pane Up"), shortcut: "Cmd-Shift-↑", disabled: !canPerform(.resizePaneUp), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split up") {
                perform(.resizePaneUp)
            },
            CommandPaletteItem(id: "resize-down", section: L("整理", "Organize"), title: L("向下调整分屏", "Resize Pane Down"), shortcut: "Cmd-Shift-↓", disabled: !canPerform(.resizePaneDown), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split down") {
                perform(.resizePaneDown)
            },
            CommandPaletteItem(
                id: "toggle-zoom",
                section: L("视图", "View"),
                title: model.workspace.isZoomed ? L("还原当前分屏", "Restore Current Pane") : L("放大当前分屏", "Zoom Current Pane"),
                shortcut: "Cmd-Opt-Z",
                disabled: !canPerform(.toggleZoom),
                disabledReason: L("需要多个分屏", "Requires multiple panes"),
                keywords: "zoom pane"
            ) {
                perform(.toggleZoom)
            },
            CommandPaletteItem(id: "equalize-splits", section: L("视图", "View"), title: L("均分分屏", "Equalize Splits"), shortcut: "Cmd-Shift-=", disabled: !canPerform(.equalizeSplits), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "equalize split layout") {
                perform(.equalizeSplits)
            },
            CommandPaletteItem(id: "flash-focused-pane", section: L("视图", "View"), title: L("闪烁当前分屏", "Flash Focused Pane"), shortcut: "Cmd-Shift-H", keywords: "flash highlight focused pane") {
                perform(.flashFocusedPane)
            },
            CommandPaletteItem(id: "workspace-overview", section: L("视图", "View"), title: L("工作区总览", "Workspace Overview"), shortcut: "Cmd-O", keywords: "workspace overview mission control") {
                perform(.toggleWorkspaceOverview)
            },
            CommandPaletteItem(id: "toggle-fullscreen", section: L("视图", "View"), title: L("切换全屏", "Toggle Full Screen"), shortcut: "Ctrl-Cmd-F", keywords: "fullscreen window mac") {
                perform(.toggleFullScreen)
            },
            CommandPaletteItem(id: "appearance-settings", section: L("视图", "View"), title: L("外观设置", "Appearance Settings"), shortcut: "Cmd-,", keywords: "appearance theme settings") {
                perform(.toggleSettings)
            },
            CommandPaletteItem(id: "duplicate-workspace", section: L("视图", "View"), title: L("复制工作区", "Duplicate Workspace"), shortcut: "Duplicate", keywords: "workspace duplicate") {
                perform(.duplicateWorkspace)
            },
            CommandPaletteItem(id: "reset-workspace", section: L("视图", "View"), title: L("重置工作区", "Reset Workspace"), shortcut: "Reset", keywords: "workspace reset") {
                perform(.resetWorkspace)
            },
            CommandPaletteItem(id: "clear-notifications", section: L("整理", "Organize"), title: L("清空通知", "Clear Notifications"), shortcut: "Clear", disabled: !canPerform(.clearNotifications), disabledReason: L("通知中心为空", "Notification Center is empty"), keywords: "notification clear") {
                perform(.clearNotifications)
            },
            CommandPaletteItem(id: "debug-notification", section: L("通知", "Notifications"), title: L("发送测试通知", "Send Test Notification"), shortcut: "Test", keywords: "notification test") {
                perform(.testNotification)
            }
        ]
    }

    @MainActor
    static func shortcutGuideItems(model: ConductorWindowModel) -> [CommandShortcutGuideItem] {
        items(model: model) { _ in }
            .filter { $0.section != L("调试", "Debug") }
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
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Rectangle()
                .fill(theme.floatingSeparator)
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
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: command.systemImage)
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(command.title)
                        .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.primaryText)
                        .lineLimit(1)
                    if let disabledReason = command.disabledReason, command.disabled {
                        Text(disabledReason)
                            .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(command.shortcut)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(command.disabled ? theme.floatingControlFill.opacity(0.50) : theme.floatingControlFill)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .frame(height: command.disabledReason != nil && command.disabled ? 42 : 36)
            .background(rowFill)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.row)
                    .stroke(selected ? theme.floatingSelectedStroke : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(command.disabled)
        .opacity(command.disabled ? 0.62 : 1)
        .animation(ConductorMotion.selection, value: selected)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
            if value {
                onHover()
            }
        }
    }

    private var rowFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        if hovering {
            return theme.floatingHoverFill
        }
        return theme.floatingControlFill.opacity(0.50)
    }

    private var iconColor: Color {
        if command.disabled {
            return ConductorDesign.tertiaryText
        }
        return selected ? theme.floatingEmphasis : ConductorDesign.secondaryText
    }

    private var iconFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        return command.disabled ? theme.floatingControlFill.opacity(0.45) : theme.floatingControlFill
    }
}

private struct AppearanceSettingsPanel: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var selectedSection: SettingsPanelSection = .themes
    @Environment(\.conductorTheme) private var theme

    private let optionColumns = [
        GridItem(.adaptive(minimum: 162, maximum: 224), spacing: 10)
    ]

    private let themeColumns = [
        GridItem(.adaptive(minimum: 142, maximum: 168), spacing: 10)
    ]

    var body: some View {
        ZStack {
            ConductorGlassSurface(style: .panel, clarity: model.appearance.chromeClarity, interactive: true) {
                VStack(spacing: 0) {
                    FloatingPanelHeader(
                        systemImage: "gearshape",
                        title: L("设置", "Settings"),
                        subtitle: model.theme.title,
                        closeHelp: L("关闭设置", "Close Settings")
                    ) {
                        model.hideSettingsPanel()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    FloatingPanelDivider()
                        .padding(.horizontal, 14)

                    HStack(spacing: 0) {
                        sidebar

                        Rectangle()
                            .fill(theme.floatingSeparator)
                            .frame(width: 1)
                            .padding(.vertical, 14)

                        contentPane
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous)
                    .stroke(theme.floatingStroke.opacity(0.82), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .frame(width: 760, height: 520)
            .onExitCommand {
                model.hideSettingsPanel()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSidebarSummary(theme: model.theme, appearance: model.appearance)

            SidebarSectionTitle(L("分类", "Categories"))

            VStack(spacing: 3) {
                ForEach(SettingsPanelSection.allCases) { section in
                    SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section
                    ) {
                        model.performShellMotion(ConductorMotion.selection) {
                            selectedSection = section
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 178)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var contentPane: some View {
        ZStack {
            theme.floatingControlFill.opacity(0.16)

            ScrollView {
                detailContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPaneHeading(section: selectedSection)

            switch selectedSection {
            case .interface:
                interfaceSettings
            case .commands:
                commandSettings
            case .themes:
                themeSettings
            }
        }
    }

    private var interfaceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("窗口密度", "Window Density"),
                subtitle: L("控制工具栏、标签和侧边栏的空间节奏", "Controls spacing across toolbars, tabs, and the sidebar"),
                systemImage: "rectangle.compress.vertical"
            ) {
                LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 10) {
                    ForEach(AppearanceDensity.allCases) { density in
                        SettingsOptionCard(
                            title: density.title,
                            subtitle: density.subtitle,
                            systemImage: "rectangle.3.group",
                            selected: model.appearance.density == density
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setAppearanceDensity(density)
                            }
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("浮层清晰度", "Layer Clarity"),
                subtitle: L("调整玻璃浮层的边界和对比度", "Tunes glass-panel boundaries and contrast"),
                systemImage: "square.stack.3d.up"
            ) {
                LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 10) {
                    ForEach(ChromeClarity.allCases) { clarity in
                        SettingsOptionCard(
                            title: clarity.title,
                            subtitle: clarity.subtitle,
                            systemImage: "sparkle.magnifyingglass",
                            selected: model.appearance.chromeClarity == clarity
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setChromeClarity(clarity)
                            }
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("语言", "Language"),
                subtitle: L("设置整个应用的显示语言", "Sets the display language across the app"),
                systemImage: "character.bubble"
            ) {
                LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 10) {
                    ForEach(AppearanceLanguage.allCases) { language in
                        SettingsOptionCard(
                            title: language.title,
                            subtitle: language.subtitle,
                            systemImage: "character.bubble",
                            selected: model.appearance.language == language
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setLanguage(language)
                            }
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("字体", "Font"),
                subtitle: L("选择设置、侧边栏和工具栏使用的字体气质", "Chooses the voice for settings, sidebars, and toolbars"),
                systemImage: "textformat"
            ) {
                LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 10) {
                    ForEach(AppearanceFontFamily.allCases) { family in
                        SettingsOptionCard(
                            title: family.title,
                            subtitle: family.subtitle,
                            systemImage: family.systemImage,
                            selected: model.appearance.fontFamily == family,
                            fontFamily: family
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setFontFamily(family)
                            }
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("字号", "Font Size"),
                subtitle: L("改变低频界面文字，不影响终端渲染", "Changes shell text without affecting terminal rendering"),
                systemImage: "textformat.size"
            ) {
                LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 10) {
                    ForEach(AppearanceFontScale.allCases) { scale in
                        SettingsOptionCard(
                            title: scale.title,
                            subtitle: scale.subtitle,
                            systemImage: "textformat.size",
                            selected: model.appearance.fontScale == scale
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setFontScale(scale)
                            }
                        }
                    }
                }
            }
        }
    }

    private var commandSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("Agent 通知", "Agent Notifications"),
                subtitle: L("为本地 agent hook 打开通知桥接", "Enables notification bridges for local agent hooks"),
                systemImage: "bell.badge"
            ) {
                LazyVGrid(columns: optionColumns, alignment: .leading, spacing: 10) {
                    ForEach(AgentHookProvider.allCases) { provider in
                        let enabled = model.appearance.agentNotifications.isEnabled(for: provider)
                        SettingsOptionCard(
                            title: provider.title,
                            subtitle: enabled ? L("已开启", "Enabled") : L("已关闭", "Disabled"),
                            systemImage: provider.systemImage,
                            selected: enabled
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setAgentNotificationsEnabled(!enabled, for: provider)
                            }
                        }
                    }
                }
                if let message = model.agentHookSettingsMessage {
                    Text(message)
                        .font(.conductorSystem(size: 10.5, weight: .medium, scale: model.appearance.fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsPreferenceGroup(
                title: L("命令与快捷键", "Commands and Shortcuts"),
                subtitle: L("按工作流分组的可用命令", "Available commands grouped by workflow"),
                systemImage: "keyboard"
            ) {
                CommandShortcutGuide(model: model, height: 260)
            }
        }
    }

    private var themeSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SelectedThemeShowcase(theme: model.theme)

            SettingsPreferenceGroup(
                title: L("主题库", "Theme Library"),
                subtitle: L("主题同时控制窗口、浮层、终端和强调色", "Themes coordinate the window, panels, terminal, and accent color"),
                systemImage: "swatchpalette"
            ) {
                LazyVGrid(columns: themeColumns, alignment: .leading, spacing: 10) {
                    ForEach(TerminalTheme.allCases) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            selected: model.theme == theme
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.theme = theme
                            }
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
            L("界面", "Interface")
        case .commands:
            L("命令", "Commands")
        case .themes:
            L("主题", "Themes")
        }
    }

    var subtitle: String {
        switch self {
        case .interface:
            L("语言、字体和字号", "Language, font, and size")
        case .commands:
            L("Agent 通知与快捷入口", "Agent notifications and shortcuts")
        case .themes:
            L("整套窗口、终端和强调色", "Window, terminal, and accent colors")
        }
    }

    var systemImage: String {
        switch self {
        case .interface:
            "textformat"
        case .commands:
            "command"
        case .themes:
            "swatchpalette"
        }
    }
}

private struct SettingsOptionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let selected: Bool
    var fontFamily: AppearanceFontFamily? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var activeFontFamily
    @Environment(\.conductorTheme) private var theme

    private var resolvedFontFamily: AppearanceFontFamily {
        fontFamily ?? activeFontFamily
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 13, weight: .semibold, family: resolvedFontFamily, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.conductorSystem(size: 12, weight: .semibold, family: resolvedFontFamily, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10, weight: .medium, family: resolvedFontFamily, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.tertiaryText.opacity(0.70))
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.row + 2, style: .continuous)
                    .stroke(selected ? theme.floatingSelectedStroke : theme.floatingStroke.opacity(hovering ? 0.86 : 0.54), lineWidth: selected ? 1.2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row + 2, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.selection, value: selected)
        .help(title)
    }

    private var cardFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        if hovering {
            return theme.floatingHoverFill
        }
        return theme.floatingControlFill.opacity(0.56)
    }
}

private extension AppearanceFontFamily {
    var systemImage: String {
        switch self {
        case .system:
            "textformat"
        case .rounded:
            "textformat.alt"
        case .serif:
            "textformat.abc"
        case .monospaced:
            "number"
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
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
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
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.selection, value: selected)
        .animation(ConductorMotion.hover, value: hovering)
        .help(section.title)
    }

    private var rowFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        if hovering {
            return theme.floatingHoverFill
        }
        return Color.clear
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
        .background(theme.floatingControlFill)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.floatingStroke, lineWidth: 1)
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
                .foregroundStyle(ConductorDesign.secondaryText)
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
                .background(theme.floatingSelectedFill)
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
                    .stroke(selected ? theme.floatingSelectedStroke : theme.shellStroke.opacity(hovering ? 0.58 : 0.34), lineWidth: selected ? 1.2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.selection, value: selected)
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
                .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.tertiaryText.opacity(0.70))
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
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

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
            ConductorGlassSurface(style: .panel, clarity: model.appearance.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    FloatingPanelDivider()
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
                                    .transition(ConductorMotion.rowTransition)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.bottom, 2)
                            .animation(ConductorMotion.list, value: filteredWorkspaceIDs)
                        }
                        .scrollIndicators(.visible)
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(12)
            }
            .frame(width: 690, height: 486)
            .onAppear {
                highlightedWorkspaceID = model.workspace.id
                focusSearchField()
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
            .animation(ConductorMotion.selection, value: highlightedWorkspaceID)
        }
    }

    private var header: some View {
        FloatingPanelHeader(
            systemImage: WorkspaceChromeGlyph.systemName(selected: false),
            title: L("工作区总览", "Workspace Overview"),
            subtitle: L("\(model.workspaces.count) 个工作区", "\(model.workspaces.count) workspaces"),
            closeHelp: L("关闭总览", "Close Overview")
        ) {
            model.hideWorkspaceOverview()
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            TextField(L("搜索工作区", "Search workspaces"), text: $query)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 13, weight: .medium, scale: fontScale))
                .focused($searchFocused)
            Text("↵")
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(theme.floatingControlStrongFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup)
                .stroke(theme.floatingStroke, lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: false))
                .font(.conductorSystem(size: 24, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text(L("没有匹配的工作区", "No matching workspaces"))
                .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
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
        model.selectWorkspace(workspaceID)
    }

    private func focusSearchField() {
        Task { @MainActor in
            searchFocused = true
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
    @Environment(\.conductorFontScale) private var fontScale

    private var terminalCount: Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var focusedTerminalTitle: String {
        workspace.focusedPane?.selectedTab?.title ?? L("终端", "Terminal")
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
                        Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                            .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                            .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                            .frame(width: 16)
                        Text(workspace.title)
                            .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
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

                    HStack(spacing: 6) {
                        WorkspaceOverviewMetric(systemImage: "square.split.2x2", value: "\(workspace.panes.count)")
                        WorkspaceOverviewMetric(systemImage: "terminal", value: "\(terminalCount)")
                        if workspace.isZoomed {
                            WorkspaceOverviewMetric(systemImage: "arrow.up.left.and.arrow.down.right", value: L("放大", "Zoom"))
                        }
                    }

                    Text(focusedTerminalTitle)
                        .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
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
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
            if value {
                onHover()
            }
        }
        .animation(ConductorMotion.selection, value: selected)
        .animation(ConductorMotion.selection, value: highlighted)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .help("\(workspace.title) · \(workspace.panes.count) \(L("分屏", "panes")) · \(terminalCount) \(L("终端", "terminals"))")
    }

    private var cardFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        if highlighted || hovering {
            return theme.floatingHoverFill
        }
        return theme.floatingControlFill.opacity(0.76)
    }

    private var borderColor: Color {
        if selected {
            return theme.floatingSelectedStroke
        }
        if highlighted {
            return theme.floatingSelectedStroke.opacity(0.78)
        }
        return theme.floatingStroke
    }
}

private struct WorkspaceOverviewMetric: View {
    let systemImage: String
    let value: String
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
            Text(value)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .lineLimit(1)
        }
        .foregroundStyle(ConductorDesign.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(theme.floatingControlFill)
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
                    .fill(focused ? theme.floatingEmphasis : Color.white.opacity(0.32))
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
                    .fill(theme.floatingEmphasis.opacity(focused ? 0.76 : 0.34))
                    .frame(width: focused ? 44 : 25, height: 2)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 22, height: 2)
            }
            .padding(6)

            if unreadCount > 0 {
                Circle()
                    .fill(theme.floatingEmphasis)
                    .frame(width: 6, height: 6)
                    .offset(x: -1, y: -1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(focused ? theme.floatingSelectedStroke : Color.white.opacity(0.14), lineWidth: focused ? 1.3 : 1)
        }
    }
}

struct NotificationPanelView: View {
    @ObservedObject var model: ConductorWindowModel
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        ConductorGlassSurface(style: .panel, clarity: model.appearance.chromeClarity, interactive: true) {
            VStack(alignment: .leading, spacing: 0) {
                notificationHeader

                Rectangle()
                    .fill(theme.floatingSeparator)
                    .frame(height: 1)

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
                                .transition(ConductorMotion.rowTransition)
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
        .animation(ConductorMotion.list, value: model.notifications.records.map(\.id))
        .animation(ConductorMotion.emphasized, value: model.notifications.snapshot.unreadCount)
    }

    private var notificationHeader: some View {
        FloatingPanelHeader(
            systemImage: model.notifications.snapshot.unreadCount > 0 ? "bell.badge.fill" : "bell",
            title: L("通知", "Notifications"),
            subtitle: model.notifications.records.isEmpty ? L("暂无通知", "No notifications") : L("\(model.notifications.records.count) 条记录", "\(model.notifications.records.count) records"),
            closeHelp: L("关闭通知", "Close Notifications")
        ) {
            model.hideNotificationPanel()
        } trailing: {
            Button(L("跳转", "Jump")) {
                ConductorMotion.perform(ConductorMotion.selection) {
                    model.performCommand(.jumpToLatestUnread)
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .foregroundStyle(model.notifications.snapshot.latestUnread == nil ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
            .disabled(!model.canPerformCommand(.jumpToLatestUnread))
            Button(L("清空", "Clear")) {
                ConductorMotion.perform(ConductorMotion.list) {
                    model.performCommand(.clearNotifications)
                }
            }
            .buttonStyle(ConductorPressButtonStyle())
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            .foregroundStyle(model.notifications.records.isEmpty ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
            .disabled(!model.canPerformCommand(.clearNotifications))
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var emptyNotifications: some View {
        VStack(spacing: 6) {
            Image(systemName: "bell.slash")
                .font(.conductorSystem(size: 21, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Text(L("暂无通知", "No notifications"))
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
            Text(L("终端通知、响铃和任务完成都会出现在这里", "Terminal notifications, bells, and task completions appear here"))
                .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .multilineTextAlignment(.center)
            Button {
                ConductorMotion.perform(ConductorMotion.emphasized) {
                    model.performCommand(.testNotification)
                }
            } label: {
                Label(L("发送测试通知", "Send Test Notification"), systemImage: "bell.badge")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .padding(.horizontal, 9)
                    .frame(height: 23)
                    .background(theme.floatingControlStrongFill)
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
        return L("终端", "Terminal")
    }
}

private struct NotificationRowView: View {
    let notification: TerminalNotificationRecord
    let terminalTitle: String
    let unread: Bool
    let onOpen: () -> Void
    let onClear: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                onOpen()
            } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: iconName)
                        .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(iconColor)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(theme.floatingControlFill)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(theme.floatingStroke, lineWidth: 1)
                        }
                        .overlay(alignment: .topTrailing) {
                            if unread {
                                Circle()
                                    .fill(theme.floatingEmphasis)
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
                ConductorMotion.perform(ConductorMotion.list, onClear)
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                    .foregroundStyle(hovering ? ConductorDesign.secondaryText : ConductorDesign.tertiaryText)
                    .frame(width: 18, height: 18)
                    .background(hovering ? theme.floatingControlFill : theme.floatingControlFill.opacity(0.40))
                    .clipShape(Circle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .help(L("清除通知", "Clear Notification"))
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    unread ? theme.floatingSelectedStroke : theme.floatingStroke,
                    lineWidth: 1
                )
        }
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.emphasized, value: unread)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
    }

    private var rowTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(notification.title)
                .font(.conductorSystem(size: 11.5, weight: unread ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(notification.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var rowBody: some View {
        if !notification.body.isEmpty {
            Text(notification.body)
                .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineSpacing(1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowMetadata: some View {
        HStack(spacing: 5) {
            Label(kindLabel, systemImage: kindChipIcon)
                .font(.conductorSystem(size: 9, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(theme.floatingControlFill.opacity(0.58))
                .clipShape(Capsule())

            Label(terminalTitle, systemImage: "terminal")
                .font(.conductorSystem(size: 9, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .frame(height: 16)
                .background(theme.floatingControlFill)
                .clipShape(Capsule())

            Spacer(minLength: 0)
        }
    }

    private var rowBackground: some View {
        LinearGradient(
            colors: [
                hovering ? theme.floatingControlStrongFill : (unread ? theme.floatingSelectedFill : theme.floatingControlFill),
                unread ? theme.floatingHoverFill : theme.floatingControlFill.opacity(0.35),
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
            L("响铃", "Bell")
        case .notification:
            L("终端", "Terminal")
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
        WindowControl(id: "close", color: Color(red: 1.0, green: 0.33, blue: 0.32), accessibilityLabel: "关闭窗口") {
            NSApp.keyWindow?.performClose(nil)
        },
        WindowControl(id: "minimize", color: Color(red: 1.0, green: 0.75, blue: 0.10), accessibilityLabel: "最小化窗口") {
            NSApp.keyWindow?.performMiniaturize(nil)
        },
        WindowControl(id: "fullscreen", color: Color(red: 0.14, green: 0.78, blue: 0.27), accessibilityLabel: "切换全屏") {
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
                .help(control.accessibilityLabel)
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

private struct ConductorSidebar: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var renamingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""
    @State private var sidebarToggleHovering = false
    @Environment(\.conductorFontScale) private var fontScale

    private var terminalCount: Int {
        model.workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    }

    private var focusedTerminalTitle: String {
        model.workspace.focusedPane?.selectedTab?.title ?? L("无", "None")
    }

    private var workspaceRows: [WorkspaceChromeDisplayModel] {
        let selectedWorkspaceID = model.workspace.id
        let notificationSnapshot = model.notifications.snapshot
        return model.workspaces.map { workspace in
            WorkspaceChromeDisplayModel(
                id: workspace.id,
                title: workspace.title,
                splitCount: workspace.panes.count,
                terminalCount: workspaceTerminalCount(workspace),
                unreadCount: notificationSnapshot.unreadCount(for: workspace.id),
                selected: workspace.id == selectedWorkspaceID
            )
        }
    }

    private var sidebarHeaderHeight: CGFloat {
        model.sidebarVisible ? 54 : 82
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
        .frame(width: model.sidebarVisible ? ConductorDesign.sidebarWidth(for: model.appearance) : ConductorDesign.sidebarCollapsedWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            SidebarRailSurface(theme: model.theme, clarity: model.appearance.chromeClarity)
        }
        .overlay {
            SidebarBookSpineChrome(
                collapsed: !model.sidebarVisible,
                theme: model.theme,
                clarity: model.appearance.chromeClarity
            )
            .allowsHitTesting(false)
        }
        .clipShape(SidebarRailShape())
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
            withoutShellAnimation {
                finishWorkspaceRenameIfNeeded()
                model.sidebarVisible.toggle()
            }
        } label: {
            Image(systemName: model.sidebarVisible ? "chevron.left" : "sidebar.left")
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
        .help(model.sidebarVisible ? L("收起侧边栏", "Collapse Sidebar") : L("展开侧边栏", "Expand Sidebar"))
    }

    private var sidebarToggleFill: Color {
        if sidebarToggleHovering {
            return model.theme.shellHoverFill.opacity(model.theme.usesDarkChrome ? 0.95 : 0.70)
        }
        return model.theme.shellControlFill.opacity(model.theme.usesDarkChrome ? 0.36 : 0.18)
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            workspaceSection
                .frame(maxHeight: .infinity)

            SidebarSeparator()

            SidebarSectionTitle(L("状态", "Status"))
            SidebarStatusSummary(
                splitCount: model.workspace.panes.count,
                terminalCount: terminalCount,
                unreadCount: model.notifications.snapshot.unreadCount,
                focusedTerminalTitle: focusedTerminalTitle
            )

            SidebarSeparator()

            SidebarSectionTitle(L("快捷操作", "Quick Actions"))
            primaryQuickActions(showsLabels: true)

            Spacer(minLength: 8)

            expandedSidebarFooter
        }
        .frame(maxHeight: .infinity)
    }

    private var expandedSidebarFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            SidebarActionRow(icon: "paintpalette", title: model.theme.title, help: L("切换主题", "Switch Theme")) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.selection) {
                    model.cycleTheme()
                }
            }
            .contextMenu {
                themeMenuItems
            }
            SidebarActionRow(icon: "gearshape", title: L("设置", "Settings"), help: L("设置", "Settings")) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.panel) {
                    model.performCommand(.toggleSettings)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SidebarSectionTitle(L("工作区", "Workspaces"))
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
                .help(L("新建工作区 Cmd-N", "New Workspace Cmd-N"))
            }
            .padding(.trailing, 5)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(workspaceRows) { row in
                        workspaceRow(for: row)
                            .id(row.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .mask(ConductorVerticalFadeMask())
            .frame(minHeight: 72, maxHeight: .infinity)
            .animation(nil, value: model.workspace.id)
        }
    }

    private var collapsedSidebar: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(workspaceRows) { row in
                        SidebarRailButton(
                            icon: WorkspaceChromeGlyph.systemName(selected: row.selected),
                            selected: row.selected,
                            help: row.title
                        ) {
                            withoutShellAnimation {
                                model.selectWorkspace(row.id)
                            }
                        }
                        .id(row.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .mask(ConductorVerticalFadeMask())
            .frame(maxHeight: .infinity)

            SidebarSeparator()
                .padding(.horizontal, -1)

            primaryQuickActions(showsLabels: false)

            Spacer(minLength: 8)

            collapsedSidebarFooter
        }
    }

    private var collapsedSidebarFooter: some View {
        VStack(spacing: 6) {
            SidebarRailButton(icon: "paintpalette", help: model.theme.title) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.selection) {
                    model.cycleTheme()
                }
            }
            .contextMenu {
                themeMenuItems
            }
            SidebarRailButton(icon: "gearshape", help: L("设置", "Settings")) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.panel) {
                    model.performCommand(.toggleSettings)
                }
            }
        }
        .padding(.bottom, 10)
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

    @ViewBuilder
    private func primaryQuickActions(showsLabels: Bool) -> some View {
        Group {
            SidebarActionRow(icon: "plus.rectangle.on.rectangle", title: L("新开终端", "New Terminal"), showsTitle: showsLabels, help: L("新开终端 Cmd-T", "New Terminal Cmd-T")) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.newTerminal)
            }
            SidebarActionRow(icon: "rectangle.split.2x1", title: L("向右分屏", "Split Right"), showsTitle: showsLabels, disabled: !model.canPerformCommand(.splitRight), help: L("向右分屏 Cmd-D", "Split Right Cmd-D")) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.splitRight)
                }
            }
            SidebarActionRow(icon: "rectangle.split.1x2", title: L("向下分屏", "Split Down"), showsTitle: showsLabels, disabled: !model.canPerformCommand(.splitDown), help: L("向下分屏 Cmd-Shift-D", "Split Down Cmd-Shift-D")) {
                finishWorkspaceRenameIfNeeded()
                ConductorMotion.perform(ConductorMotion.layout) {
                    model.performCommand(.splitDown)
                }
            }
            SidebarActionRow(icon: "command", title: L("命令面板", "Command Center"), showsTitle: showsLabels, help: L("打开命令面板 Cmd-K", "Open Command Center Cmd-K")) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
        }
    }

    private func workspaceRow(for row: WorkspaceChromeDisplayModel) -> some View {
        WorkspaceSidebarRow(
            title: row.title,
            terminalCount: row.terminalCount,
            unreadCount: row.unreadCount,
            selected: row.selected,
            editing: renamingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onCommitRename: commitWorkspaceRename,
            onCancelRename: cancelWorkspaceRename
        ) {
            finishWorkspaceRenameIfNeeded(except: row.id)
            withoutShellAnimation {
                model.selectWorkspace(row.id)
            }
        } onRename: {
            finishWorkspaceRenameIfNeeded(except: row.id)
            beginRenameWorkspace(row)
        }
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
            .disabled(model.workspaces.count <= 1)
            Button(L("关闭右侧工作区", "Close Workspaces to the Right")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspacesToRight(of: row.id)
                }
            }
            .disabled(model.workspaces.count <= 1)
            Divider()
            Button(L("关闭工作区", "Close Workspace")) {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspace(row.id)
                }
            }
            .disabled(model.workspaces.count <= 1)
        }
    }

    private func workspaceTerminalCount(_ workspace: WorkspaceState) -> Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
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
    var leadingRadius: CGFloat = ConductorDesign.sidebarCornerRadius
    var trailingRadius: CGFloat = 8
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let leading = min(leadingRadius, rect.width / 2, rect.height / 2)
        let trailing = min(trailingRadius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leading, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailing, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + trailing),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
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
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leading))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + leading, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
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
                        Color.black.opacity(theme.usesDarkChrome ? 0.08 : 0.020)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 10)
            }
            .overlay {
                shape
                    .strokeBorder(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.22 : 0.10), lineWidth: 0.6)
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
                    theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.12 : 0.050),
                    theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.10 : 0.028)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 13)
        }
        .opacity(0.62)
    }
}

private struct WorkspaceChromeDisplayModel: Identifiable, Equatable {
    let id: WorkspaceID
    let title: String
    let splitCount: Int
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
}

private enum WorkspaceChromeGlyph {
    static func systemName(selected: Bool) -> String {
        selected ? "square.grid.2x2.fill" : "square.grid.2x2"
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
                SidebarStatusPill(title: L("分屏", "Panes"), value: "\(splitCount)")
                SidebarStatusPill(title: L("终端", "Terms"), value: "\(terminalCount)")
                if unreadCount > 0 {
                    SidebarStatusPill(title: L("未读", "Unread"), value: unreadCount > 99 ? "99+" : "\(unreadCount)", highlighted: true)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis.opacity(0.88))
                    .frame(width: 14)
                Text(L("焦点", "Focus"))
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
                .foregroundStyle(highlighted ? theme.floatingEmphasis.opacity(0.86) : ConductorDesign.tertiaryText)
            Text(value)
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                .foregroundStyle(highlighted ? theme.floatingEmphasis : ConductorDesign.primaryText)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(highlighted ? theme.shellSelectedFill : theme.shellControlFill.opacity(0.72))
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
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.conductorSystem(size: 13, weight: .semibold, scale: fontScale))
                .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                .frame(width: 34, height: 34)
                .background(selected ? theme.shellSelectedFill : (hovering ? theme.shellHoverFill : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay {
                    ConductorMagneticGlow(cornerRadius: 11, active: selected, lineWidth: 0.8)
                        .opacity(selected ? 0.75 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .scaleEffect(hovering && !disabled ? 1.035 : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.selection, value: selected)
        .onHover { hovering = $0 }
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
                .foregroundStyle(selected ? theme.floatingEmphasis.opacity(0.90) : ConductorDesign.secondaryText)
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
                    .transition(.identity)
            } else {
                displayRow
                    .transition(.identity)
            }
        }
        .animation(nil, value: editing)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .help(title)
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
        .frame(height: 32)
        .background(selected ? theme.shellSelectedFill : theme.shellHoverFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .onAppear {
            renameCancelled = false
        }
    }

    private var displayRow: some View {
        Button(action: action) {
            WorkspaceSidebarRowContent(
                title: title,
                terminalCount: terminalCount,
                unreadCount: unreadCount,
                selected: selected,
                hovering: hovering
            )
            .equatable()
        }
        .buttonStyle(ConductorPressButtonStyle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                action()
                onRename()
            }
        )
    }
}

private struct WorkspaceSidebarRowContent: View, Equatable {
    let title: String
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
    let hovering: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceSidebarRowContent, rhs: WorkspaceSidebarRowContent) -> Bool {
        lhs.title == rhs.title &&
        lhs.terminalCount == rhs.terminalCount &&
        lhs.unreadCount == rhs.unreadCount &&
        lhs.selected == rhs.selected &&
        lhs.hovering == rhs.hovering
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                .foregroundStyle(selected ? theme.shellChromeText.opacity(0.94) : ConductorDesign.secondaryText)
                .frame(width: 19, height: 19)
                .background(selected ? theme.shellControlRaisedFill.opacity(0.84) : (hovering ? theme.shellHoverFill.opacity(0.62) : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(terminalCount)")
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .padding(.horizontal, 5)
                .frame(minWidth: 17, minHeight: 17)
                .background(selected ? theme.shellHoverFill.opacity(0.82) : Color.clear)
                .clipShape(Capsule())
            if unreadCount > 0 {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 14)
                    .background(theme.floatingEmphasis)
                    .clipShape(Capsule())
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                .fill(hovering ? theme.shellHoverFill : Color.clear)
            if selected {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                    .fill(theme.shellSelectedFill)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .transaction { transaction in
            transaction.animation = nil
        }
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
        .scaleEffect(hovering && !disabled ? (showsTitle ? 1.006 : 1.032) : 1)
        .animation(ConductorMotion.micro, value: disabled)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
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
                    ConductorIconButton(systemImage: "rectangle.split.2x1", help: L("向右分屏 Cmd-D", "Split Right Cmd-D"), title: L("右分屏", "Right"), disabled: !model.canPerformCommand(.splitRight)) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.splitRight)
                        }
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(systemImage: "rectangle.split.1x2", help: L("向下分屏 Cmd-Shift-D", "Split Down Cmd-Shift-D"), title: L("下分屏", "Down"), disabled: !model.canPerformCommand(.splitDown)) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.splitDown)
                        }
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        help: model.workspace.isZoomed ? L("还原当前分屏 Cmd-Opt-Z", "Restore Current Pane Cmd-Opt-Z") : L("放大当前分屏 Cmd-Opt-Z", "Zoom Current Pane Cmd-Opt-Z"),
                        title: model.workspace.isZoomed ? L("还原", "Restore") : L("放大", "Zoom"),
                        disabled: !model.canPerformCommand(.toggleZoom),
                        active: model.workspace.isZoomed
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        ConductorMotion.perform(ConductorMotion.layout) {
                            model.performCommand(.toggleZoom)
                        }
                    }
                }

                ConductorPillGroup {
                    ConductorIconButton(
                        systemImage: "magnifyingglass",
                        help: L("上下文搜索 Cmd-F", "Context Search Cmd-F"),
                        title: L("搜索", "Search"),
                        active: model.terminalSearchVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.showTerminalSearch)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: WorkspaceChromeGlyph.systemName(selected: false),
                        help: L("工作区总览 Cmd-O", "Workspace Overview Cmd-O"),
                        title: L("总览", "Overview"),
                        active: model.workspaceOverviewVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleWorkspaceOverview)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(
                        systemImage: model.notifications.snapshot.unreadCount > 0 ? "bell.badge" : "bell",
                        help: L("通知中心 Cmd-Opt-N", "Notification Center Cmd-Opt-N"),
                        title: model.notifications.snapshot.unreadCount > 0 ? L("通知 \(model.notifications.snapshot.unreadCount)", "Alerts \(model.notifications.snapshot.unreadCount)") : L("通知", "Alerts"),
                        active: model.notificationPanelVisible
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleNotifications)
                    }
                    ConductorSegmentDivider()
                    ConductorIconButton(systemImage: "ellipsis", help: L("命令面板 Cmd-K", "Command Center Cmd-K"), title: L("命令", "Command")) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleCommandPalette)
                    }
                }
            }
            .controlSize(.small)
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: ConductorDesign.toolbarHeight(for: model.appearance))
        }
        .frame(height: ConductorDesign.toolbarHeight(for: model.appearance))
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

private struct WorkspaceTabStrip: View {
    @ObservedObject var model: ConductorWindowModel
    @Binding var editingWorkspaceID: WorkspaceID?
    @Binding var workspaceTitleDraft: String
    let onBeginRename: (WorkspaceChromeDisplayModel) -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @State private var scrollTargetID: WorkspaceID?

    private var workspaceRows: [WorkspaceChromeDisplayModel] {
        let selectedWorkspaceID = model.workspace.id
        let notificationSnapshot = model.notifications.snapshot
        return model.workspaces.map { workspace in
            WorkspaceChromeDisplayModel(
                id: workspace.id,
                title: workspace.title,
                splitCount: workspace.panes.count,
                terminalCount: workspaceTerminalCount(workspace),
                unreadCount: notificationSnapshot.unreadCount(for: workspace.id),
                selected: workspace.id == selectedWorkspaceID
            )
        }
    }

    private var workspaceIDs: [WorkspaceID] {
        workspaceRows.map(\.id)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WorkspaceTabMetrics.spacing) {
                ForEach(workspaceRows) { row in
                    workspaceTabView(for: row)
                        .transition(ConductorMotion.tabTransition)
                }
            }
            .padding(.horizontal, WorkspaceTabMetrics.edgePadding)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollTargetID, anchor: .center)
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
        .animation(ConductorMotion.list, value: workspaceIDs)
    }

    private func syncScrollTarget(animated: Bool) {
        guard workspaceIDs.contains(model.workspace.id) else { return }
        let update = {
            scrollTargetID = model.workspace.id
        }
        if animated {
            model.performShellMotion(ConductorMotion.scroll, update)
        } else {
            update()
        }
    }

    private func workspaceTabView(for row: WorkspaceChromeDisplayModel) -> some View {
        WorkspaceTopTab(
            row: row,
            appearance: model.appearance,
            canClose: model.workspaces.count > 1,
            editing: editingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onSelect: {
                finishWorkspaceRenameIfNeeded(except: row.id)
                model.selectWorkspace(row.id)
            },
            onRename: {
                ConductorMotion.perform(ConductorMotion.selection) {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    onBeginRename(row)
                }
            },
            onCommitRename: onCommitRename,
            onCancelRename: onCancelRename,
            onDuplicate: {
                ConductorMotion.perform(ConductorMotion.layout) {
                    finishWorkspaceRenameIfNeeded()
                    model.duplicateWorkspace(row.id)
                }
            },
            onClose: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspace(row.id)
                }
            },
            onCloseOthers: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded(except: row.id)
                    model.closeOtherWorkspaces(keeping: row.id)
                }
            },
            onCloseRight: {
                withoutShellAnimation {
                    finishWorkspaceRenameIfNeeded()
                    model.closeWorkspacesToRight(of: row.id)
                }
            }
        )
        .id(row.id)
    }

    private func workspaceTerminalCount(_ workspace: WorkspaceState) -> Int {
        workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
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

    static let spacing: CGFloat = 4
    static let edgePadding: CGFloat = 0
}

private struct WorkspaceTopTab: View {
    let row: WorkspaceChromeDisplayModel
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
    @Environment(\.conductorTheme) private var theme

    private var selected: Bool {
        row.selected
    }

    private var unreadCount: Int {
        row.unreadCount
    }

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.76) : theme.shellControlFill.opacity(0.14)
        }
        return hovering ? theme.shellHoverFill.opacity(0.78) : theme.shellControlFill.opacity(0.52)
    }

    private var selectedFill: Color {
        theme.usesDarkChrome ? theme.shellSelectedFill.opacity(0.92) : theme.shellSelectedFill.opacity(0.78)
    }

    private var tabStroke: Color {
        if selected {
            return theme.shellStroke.opacity((theme.usesDarkChrome ? 0.70 : 0.52) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.44 : 0.24)
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    var body: some View {
        HStack(spacing: 7) {
            if editing {
                WorkspaceTabGlyph(selected: true)
                RenameTextField(
                    text: $titleDraft,
                    placeholder: L("工作区名称", "Workspace Name"),
                    font: .conductorSystemFont(ofSize: 11.5, weight: .bold, scale: fontScale),
                    textColor: NSColor(theme.shellChromeText),
                    onCommit: onCommitRename,
                    onCancel: onCancelRename
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    renameCancelled = false
                }
            } else {
                HStack(spacing: 7) {
                    WorkspaceTabGlyph(selected: selected)
                    Text(row.title)
                        .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(row.terminalCount)")
                        .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                        .foregroundStyle(selected ? theme.shellChromeText.opacity(0.72) : theme.shellChromeTextMuted.opacity(0.70))
                        .frame(minWidth: 17, minHeight: 17)
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 14)
                            .background(theme.floatingEmphasis.opacity(0.72))
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                        .foregroundStyle(canClose ? titleColor.opacity(selected || hovering ? 0.74 : 0.52) : Color.clear)
                        .frame(width: 13, height: 13)
                        .clipShape(Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(ConductorPressButtonStyle())
                .disabled(!canClose)
                .help(L("关闭工作区", "Close Workspace"))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, editing ? 8 : 6)
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background {
            if selected {
                tabShape
                    .fill(selectedFill)
            } else {
                tabShape
                    .fill(baseFill)
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 1)
        }
        .scaleEffect(hovering && !selected ? 1.006 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.selection, value: editing)
        .animation(ConductorMotion.emphasized, value: unreadCount)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(tabShape)
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard !editing else { return }
                onSelect()
                onRename()
            }
        )
        .contextMenu {
            Button(L("重命名工作区...", "Rename Workspace...")) {
                onRename()
            }
            Button(L("复制工作区", "Duplicate Workspace")) {
                onDuplicate()
            }
            Divider()
            Button(L("关闭其他工作区", "Close Other Workspaces")) {
                onCloseOthers()
            }
            .disabled(!canClose)
            Button(L("关闭右侧工作区", "Close Workspaces to the Right")) {
                onCloseRight()
            }
            .disabled(!canClose)
            Divider()
            Button(L("关闭工作区", "Close Workspace")) {
                onClose()
            }
            .disabled(!canClose)
        }
        .help("\(row.title) · \(row.splitCount) \(L("分屏", "panes")) · \(row.terminalCount) \(L("终端", "terminals"))")
    }
}

private struct WorkspaceTabGlyph: View {
    let selected: Bool
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
            .font(.system(size: 10.8, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
            .frame(width: 17, height: 17)
    }
}
