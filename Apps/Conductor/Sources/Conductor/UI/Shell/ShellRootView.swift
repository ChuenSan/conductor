import ConductorCore
import AppKit
import SwiftUI

private func withoutShellAnimation(_ action: () -> Void) {
    ConductorMotion.withoutAnimation(action)
}

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ShellRootView: View {
    @ObservedObject var model: ConductorWindowModel
    @State private var fileManagerPresentationRequest: FileManagerPanelRequest?
    @State private var fileManagerTrayVisible = false
    @State private var fileManagerAnimationGeneration = 0
    @FocusState private var terminalSearchFocused: Bool

    private let fileManagerTargetWidth: CGFloat = 468
    private let fileManagerAnimationDuration: TimeInterval = 0.18

    var body: some View {
        let shellSnapshot = ShellChromeSnapshot(model: model)

        return GeometryReader { _ in
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
                if shellSnapshot.commandPaletteVisible {
                    CommandPaletteView(
                        model: model,
                        snapshot: CommandPaletteSnapshot(model: model)
                    )
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.panelTransition)
                }
                if shellSnapshot.settingsPanelVisible {
                    AppearanceSettingsPanel(
                        model: model,
                        commandShortcutRows: { ConductorCommandCatalog.shortcutGuideRows(model: model) }
                    )
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.settingsPanelTransition)
                }
                if shellSnapshot.workspaceOverviewVisible {
                    WorkspaceOverviewPanel(
                        model: model,
                        snapshot: WorkspaceOverviewSnapshot(model: model)
                    )
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.panelTransition)
                }
            }
        }
        .animation(model.shellAnimation(ConductorMotion.panel), value: shellSnapshot.commandPaletteVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: shellSnapshot.settingsPanelVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: shellSnapshot.workspaceOverviewVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: model.terminalSearchVisible)
        .onAppear {
            synchronizeFileManagerPresentation(animated: false)
        }
        .onChange(of: model.terminalSearchFocusGeneration) { _, _ in
            focusTerminalSearchField()
        }
        .onChange(of: model.terminalSearchVisible) { _, visible in
            if visible {
                focusTerminalSearchField()
            }
        }
        .onChange(of: model.fileManagerPanelRequest?.id) { _, _ in
            synchronizeFileManagerPresentation(animated: true)
        }
    }

    private var shellContent: some View {
        let workspaceSnapshot = WorkspaceChromeSnapshot(model: model)
        let toolbarSnapshot = ToolbarChromeSnapshot(model: model)

        return HStack(alignment: .top, spacing: ConductorDesign.shellGap) {
            ConductorSidebar(
                model: model,
                snapshot: workspaceSnapshot,
                theme: model.theme,
                appearance: model.appearance,
                sidebarVisible: model.sidebarVisible
            )
            ConductorShellJoiner(theme: model.theme)

            VStack(spacing: 0) {
                ConductorToolbar(
                    model: model,
                    workspaceSnapshot: workspaceSnapshot,
                    toolbarSnapshot: toolbarSnapshot,
                    theme: model.theme,
                    appearance: model.appearance
                )
                ZStack(alignment: .trailing) {
                    primaryWorkspaceContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    fileManagerTray
                    if model.terminalSearchVisible && model.fileManagerPanelRequest == nil {
                        TerminalSearchBar(model: model, focus: $terminalSearchFocused)
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .transition(ConductorMotion.panelTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(model.theme.terminalBackground)
            .overlay(alignment: .leading) {
                TerminalSidebarContactWash(theme: model.theme)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var fileManagerTray: some View {
        if let request = fileManagerPresentationRequest {
            FileManagerPanel(
                model: model,
                request: request,
                searchFocusToken: model.fileManagerSearchFocusGeneration,
                searchNextToken: model.fileManagerSearchNextGeneration,
                searchPreviousToken: model.fileManagerSearchPreviousGeneration
            )
            .frame(width: fileManagerTargetWidth)
            .frame(maxHeight: .infinity)
            .offset(x: fileManagerTrayVisible ? 0 : fileManagerTargetWidth)
            .clipped()
            .shadow(color: Color.black.opacity(model.theme.usesDarkChrome ? 0.22 : 0.14), radius: 18, x: -8, y: 0)
            .animation(fileManagerTrayAnimation, value: fileManagerTrayVisible)
        }
    }

    private var fileManagerTrayAnimation: Animation? {
        guard !model.appearance.reducedMotion else { return nil }
        return .timingCurve(0.18, 0.86, 0.18, 1.0, duration: fileManagerAnimationDuration)
    }

    private func synchronizeFileManagerPresentation(animated: Bool) {
        fileManagerAnimationGeneration &+= 1
        let generation = fileManagerAnimationGeneration
        let shouldAnimate = animated && !model.appearance.reducedMotion
        ConductorMotion.withoutAnimation {
            if let request = model.fileManagerPanelRequest {
                fileManagerPresentationRequest = request
                fileManagerTrayVisible = !shouldAnimate
            } else {
                if shouldAnimate, fileManagerPresentationRequest != nil {
                    fileManagerTrayVisible = false
                } else {
                    fileManagerTrayVisible = false
                    fileManagerPresentationRequest = nil
                }
            }
        }
        guard shouldAnimate else {
            return
        }

        if model.fileManagerPanelRequest != nil {
            DispatchQueue.main.async {
                guard fileManagerAnimationGeneration == generation else { return }
                ConductorMotion.withoutAnimation {
                    fileManagerTrayVisible = true
                }
                finishFileManagerAnimation(generation: generation)
            }
        } else {
            finishFileManagerAnimation(generation: generation)
        }
    }

    private func finishFileManagerAnimation(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + fileManagerAnimationDuration + 0.035) {
            guard fileManagerAnimationGeneration == generation else { return }
            ConductorMotion.withoutAnimation {
                if model.fileManagerPanelRequest == nil {
                    fileManagerTrayVisible = false
                    fileManagerPresentationRequest = nil
                } else if let request = model.fileManagerPanelRequest {
                    fileManagerPresentationRequest = request
                    fileManagerTrayVisible = true
                }
            }
        }
    }

    @ViewBuilder
    private var primaryWorkspaceContent: some View {
        if let webTab = model.selectedWorkspaceWebTab {
            ConductorWebWorkspaceView(model: model, tab: webTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.selectedWorkspaceFileTab != nil {
            ConductorFileWorkspaceView(
                model: model,
                snapshot: ConductorFileWorkspaceSnapshot(model: model)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            terminalStage
        }
    }

    private var terminalStage: some View {
        SplitNodeView(
            node: model.workspace.visibleRoot,
            model: model,
            theme: model.theme,
            appearance: model.appearance
        )
            .background(model.theme.terminalBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func focusTerminalSearchField() {
        terminalSearchFocused = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            guard model.terminalSearchVisible else { return }
            terminalSearchFocused = true
        }
    }

}

private struct TerminalSearchBar: View {
    let model: ConductorWindowModel
    var focus: FocusState<Bool>.Binding

    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    private var query: Binding<String> {
        Binding(
            get: { model.terminalSearchQuery },
            set: { model.setTerminalSearchQuery($0) }
        )
    }

    private var statusText: String {
        let metadata = model.focusedTerminalSearchMetadata
        guard let total = metadata.total, total > 0 else { return "0/0" }
        let selected = min(max((metadata.selected ?? 0) + 1, 1), total)
        return "\(selected)/\(total)"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .accessibilityHidden(true)
            TextField(L("搜索终端输出", "Search terminal output"), text: query)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 12, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .focused(focus)
                .frame(width: 220)
                .onSubmit {
                    model.navigateTerminalSearch(previous: false)
                }
            Text(statusText)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
            terminalSearchButton("chevron.up", help: L("上一个搜索结果", "Previous Search Result")) {
                model.navigateTerminalSearch(previous: true)
            }
            terminalSearchButton("chevron.down", help: L("下一个搜索结果", "Next Search Result")) {
                model.navigateTerminalSearch(previous: false)
            }
            terminalSearchButton("xmark", help: L("关闭搜索", "Close Search")) {
                model.closeTerminalSearch()
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(theme.floatingControlStrongFill)
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                .stroke(theme.floatingStroke, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.18 : 0.10), radius: 14, x: 0, y: 8)
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                focus.wrappedValue = true
            }
        }
    }

    private func terminalSearchButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 24, height: 24)
                .background(theme.floatingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
        .macNativeTooltip(help)
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
                theme.shellPanelBackground.opacity(theme.usesDarkChrome ? 0.34 : 0.22),
                theme.terminalBackground.opacity(theme.usesDarkChrome ? 0.16 : 0.075),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: theme.usesDarkChrome ? 22 : 18)
    }
}

struct FloatingPanelHeader<Trailing: View>: View {
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
                .accessibilityHidden(true)
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
            .accessibilityLabel(closeHelp)
            .macNativeTooltip(closeHelp)
        }
    }
}

extension FloatingPanelHeader where Trailing == EmptyView {
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

struct FloatingPanelDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.floatingSeparator)
            .frame(height: 1)
    }
}

private struct CommandPaletteSnapshot: Equatable {
    let subtitle: String
    let chromeClarity: ChromeClarity
    let commands: [CommandPaletteItem]

    @MainActor
    init(model: ConductorWindowModel) {
        self.subtitle = model.workspace.title
        self.chromeClarity = model.appearance.chromeClarity
        self.commands = ConductorCommandCatalog.items(model: model)
    }
}

private struct CommandPaletteView: View {
    let model: ConductorWindowModel
    let snapshot: CommandPaletteSnapshot
    @State private var query = ""
    @State private var selectedCommandID: String?
    @State private var filteredResult: CommandPaletteFilterResult
    @Namespace private var commandSelectionNamespace
    @FocusState private var searchFocused: Bool
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    init(model: ConductorWindowModel, snapshot: CommandPaletteSnapshot) {
        self.model = model
        self.snapshot = snapshot
        _filteredResult = State(initialValue: CommandPaletteFilterResult(commands: snapshot.commands, query: ""))
    }

    private var commands: [CommandPaletteItem] {
        snapshot.commands
    }

    var body: some View {
        ZStack {
            ConductorGlassSurface(style: .panel, clarity: snapshot.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 8) {
                    commandHeader
                    commandSearchField
                    commandResults
                }
                .padding(10)
            }
            .frame(width: 660, height: 430)
            .onAppear {
                refreshFilteredCommands()
                focusSearchField()
                ensureSelection()
            }
            .onChange(of: query) {
                refreshFilteredCommands()
            }
            .onChange(of: commands) {
                refreshFilteredCommands()
            }
            .animation(ConductorMotion.feedback, value: selectedCommandID)
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
        CommandPaletteHeader(
            subtitle: snapshot.subtitle,
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
                .accessibilityHidden(true)
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
            if filteredResult.rows.isEmpty {
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
                        ForEach(filteredResult.rows) { row in
                            if row.showsSectionTitle {
                                CommandSectionTitle(row.command.section, compact: true)
                            }
                            CommandButton(
                                command: row.command,
                                selected: row.id == selectedCommandID,
                                selectionNamespace: commandSelectionNamespace,
                                action: {
                                    execute(row.command)
                                },
                                onHover: {
                                    if !row.command.disabled {
                                        selectedCommandID = row.id
                                    }
                                }
                            )
                            .transition(ConductorMotion.rowTransition(itemCount: filteredResult.rows.count))
                            .conductorCascade(
                                index: row.presentationIndex,
                                itemCount: filteredResult.rows.count,
                                edge: .top,
                                distance: 8,
                                scale: 0.99
                            )
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(ConductorMotion.list(itemCount: filteredResult.rows.count), value: filteredResult.commandIDs)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func ensureSelection() {
        ensureSelection(in: filteredResult)
    }

    private func ensureSelection(in result: CommandPaletteFilterResult) {
        selectedCommandID = ConductorSearchSelection.resolvedSelection(
            currentID: selectedCommandID,
            results: result.searchResults
        )
    }

    private func moveSelection(by offset: Int) {
        selectedCommandID = ConductorSearchSelection.move(
            currentID: selectedCommandID,
            by: offset,
            results: filteredResult.searchResults,
            wraps: true
        )
    }

    private func execute(_ command: CommandPaletteItem) {
        guard !command.disabled else {
            return
        }
        _ = model.performCommand(command.command)
        model.hideCommandPalette()
    }

    private func executeSelected() {
        ensureSelection()
        guard let selectedCommandID,
              let command = filteredResult.command(for: selectedCommandID) else {
            return
        }
        execute(command)
    }

    private func focusSearchField() {
        Task { @MainActor in
            searchFocused = true
        }
    }

    private func refreshFilteredCommands() {
        let next = CommandPaletteFilterResult(commands: commands, query: query)
        guard next != filteredResult else { return }
        filteredResult = next
        ensureSelection(in: next)
    }
}

private struct CommandPaletteFilterResult: Equatable {
    static let empty = CommandPaletteFilterResult(rows: [], searchResults: [], commandIDs: [])

    let rows: [CommandPaletteFilteredRow]
    let searchResults: [ConductorSearchResult]
    let commandIDs: [String]

    init(commands: [CommandPaletteItem], query: String) {
        let commandByID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
        let searchResults = ConductorSearchMatcher.results(for: query, in: commands.map(\.searchCandidate))
        var previousSection: String?
        var rows: [CommandPaletteFilteredRow] = []
        var commandIDs: [String] = []
        rows.reserveCapacity(commands.count)
        commandIDs.reserveCapacity(commands.count)

        for result in searchResults {
            guard let command = commandByID[result.candidate.id] else { continue }
            let showsSectionTitle = command.section != previousSection
            previousSection = command.section
            rows.append(CommandPaletteFilteredRow(
                command: command,
                showsSectionTitle: showsSectionTitle,
                presentationIndex: rows.count
            ))
            commandIDs.append(command.id)
        }

        self.rows = rows
        self.searchResults = searchResults
        self.commandIDs = commandIDs
    }

    private init(
        rows: [CommandPaletteFilteredRow],
        searchResults: [ConductorSearchResult],
        commandIDs: [String]
    ) {
        self.rows = rows
        self.searchResults = searchResults
        self.commandIDs = commandIDs
    }

    func command(for id: String) -> CommandPaletteItem? {
        rows.first { $0.id == id }?.command
    }
}

private struct CommandPaletteFilteredRow: Identifiable, Equatable {
    var id: String { command.id }
    let command: CommandPaletteItem
    let showsSectionTitle: Bool
    let presentationIndex: Int
}

private struct CommandPaletteItem: Identifiable, Equatable {
    let id: String
    let command: ConductorShellCommand
    let section: String
    let title: String
    let shortcut: String
    let disabled: Bool
    let disabledReason: String?
    let keywords: String
    let searchText: String

    init(
        id: String,
        command: ConductorShellCommand,
        section: String,
        title: String,
        shortcut: String,
        disabled: Bool = false,
        disabledReason: String? = nil,
        keywords: String = ""
    ) {
        self.id = id
        self.command = command
        self.section = section
        self.title = title
        self.shortcut = shortcut
        self.disabled = disabled
        self.disabledReason = disabledReason
        self.keywords = keywords
        self.searchText = "\(title) \(shortcut) \(section) \(keywords)".lowercased()
    }

    var searchCandidate: ConductorSearchCandidate {
        ConductorSearchCandidate(
            id: id,
            title: title,
            subtitle: shortcut,
            keywords: [keywords, section, shortcut],
            section: section,
            systemImage: systemImage,
            isEnabled: !disabled,
            disabledReason: disabledReason
        )
    }

    var systemImage: String {
        switch id {
        case "new-workspace":
            WorkspaceChromeGlyph.systemName(selected: false)
        case "new-terminal":
            "plus.rectangle.on.rectangle"
        case "new-web-tab":
            "globe"
        case "new-terminal-current-directory":
            "arrow.turn.down.right"
        case "open-current-directory":
            "folder"
        case "file-manager":
            "folder"
        case "copy-current-directory":
            "doc.on.doc"
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
    static func items(model: ConductorWindowModel) -> [CommandPaletteItem] {
        func canPerform(_ command: ConductorShellCommand) -> Bool {
            model.canPerformCommand(command)
        }

        return [
            CommandPaletteItem(id: "new-workspace", command: .newWorkspace, section: L("创建", "Create"), title: L("新建工作区", "New Workspace"), shortcut: "Cmd-N", keywords: "workspace new"),
            CommandPaletteItem(id: "new-terminal", command: .newTerminal, section: L("创建", "Create"), title: L("新开终端", "New Terminal"), shortcut: "Cmd-T", keywords: "terminal pane shell"),
            CommandPaletteItem(
                id: "new-web-tab",
                command: .newWebTab,
                section: L("文件", "File"),
                title: L("新建网页标签页", "New Web Tab"),
                shortcut: "",
                keywords: "web browser url localhost website"
            ),
            CommandPaletteItem(
                id: "new-terminal-current-directory",
                command: .newTerminalAtFocusedDirectory,
                section: L("创建", "Create"),
                title: L("从当前目录新开终端", "New Terminal at Current Directory"),
                shortcut: "Current CWD",
                disabled: !canPerform(.newTerminalAtFocusedDirectory),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "terminal cwd current directory folder"
            ),
            CommandPaletteItem(id: "duplicate-tab", command: .duplicateSelectedTab, section: L("创建", "Create"), title: L("复制当前标签", "Duplicate Current Tab"), shortcut: "Duplicate", keywords: "copy tab duplicate"),
            CommandPaletteItem(
                id: "open-current-directory",
                command: .openFocusedDirectory,
                section: L("上下文", "Context"),
                title: L("打开当前目录", "Open Current Directory"),
                shortcut: "Finder",
                disabled: !canPerform(.openFocusedDirectory),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "open reveal finder cwd folder directory"
            ),
            CommandPaletteItem(
                id: "copy-current-directory",
                command: .copyFocusedDirectory,
                section: L("上下文", "Context"),
                title: L("复制当前目录路径", "Copy Current Directory Path"),
                shortcut: "Copy",
                disabled: !canPerform(.copyFocusedDirectory),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "copy path cwd folder directory"
            ),
            CommandPaletteItem(
                id: "file-manager",
                command: .toggleFileManager,
                section: L("上下文", "Context"),
                title: L("文件管理器", "File Manager"),
                shortcut: "Files",
                disabled: !canPerform(.toggleFileManager),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "file files browser manager cwd folder directory preview"
            ),
            CommandPaletteItem(
                id: "context-search",
                command: .showTerminalSearch,
                section: L("上下文", "Context"),
                title: L("搜索当前上下文", "Search Current Context"),
                shortcut: "Cmd-F",
                disabled: !canPerform(.showTerminalSearch),
                disabledReason: L("当前没有可搜索的终端、文件或文件面板", "No searchable terminal, file, or file panel is active"),
                keywords: "search find terminal file document context"
            ),
            CommandPaletteItem(
                id: "find-next",
                command: .findNext,
                section: L("上下文", "Context"),
                title: L("下一个搜索结果", "Next Search Result"),
                shortcut: "Cmd-G",
                disabled: !canPerform(.findNext),
                disabledReason: L("先打开搜索", "Open search first"),
                keywords: "search find next match"
            ),
            CommandPaletteItem(
                id: "find-previous",
                command: .findPrevious,
                section: L("上下文", "Context"),
                title: L("上一个搜索结果", "Previous Search Result"),
                shortcut: "Cmd-Shift-G",
                disabled: !canPerform(.findPrevious),
                disabledReason: L("先打开搜索", "Open search first"),
                keywords: "search find previous match"
            ),
            CommandPaletteItem(id: "split-right", command: .splitRight, section: L("创建", "Create"), title: L("向右分屏", "Split Right"), shortcut: "Cmd-D", disabled: !canPerform(.splitRight), disabledReason: L("当前布局已到可用分屏上限", "Current layout has reached the split limit"), keywords: "split right vertical"),
            CommandPaletteItem(id: "split-down", command: .splitDown, section: L("创建", "Create"), title: L("向下分屏", "Split Down"), shortcut: "Cmd-Shift-D", disabled: !canPerform(.splitDown), disabledReason: L("当前布局已到可用分屏上限", "Current layout has reached the split limit"), keywords: "split down horizontal"),
            CommandPaletteItem(id: "next-tab", command: .selectNextTab, section: L("导航", "Navigate"), title: L("下一个标签", "Next Tab"), shortcut: "Cmd-]", keywords: "next tab"),
            CommandPaletteItem(id: "previous-tab", command: .selectPreviousTab, section: L("导航", "Navigate"), title: L("上一个标签", "Previous Tab"), shortcut: "Cmd-[", keywords: "previous tab"),
            CommandPaletteItem(id: "next-pane", command: .focusNextPane, section: L("导航", "Navigate"), title: L("下一个分屏", "Next Pane"), shortcut: "Cmd-Shift-]", keywords: "next pane focus"),
            CommandPaletteItem(id: "previous-pane", command: .focusPreviousPane, section: L("导航", "Navigate"), title: L("上一个分屏", "Previous Pane"), shortcut: "Cmd-Shift-[", keywords: "previous pane focus"),
            CommandPaletteItem(id: "notifications", command: .toggleNotifications, section: L("导航", "Navigate"), title: L("通知中心", "Notification Center"), shortcut: "Cmd-Opt-N", keywords: "notification unread agent"),
            CommandPaletteItem(
                id: "jump-unread",
                command: .jumpToLatestUnread,
                section: L("导航", "Navigate"),
                title: L("跳到最新未读", "Jump to Latest Unread"),
                shortcut: "Cmd-Opt-J",
                disabled: !canPerform(.jumpToLatestUnread),
                disabledReason: L("没有未读通知", "No unread notifications"),
                keywords: "notification unread jump"
            ),
            CommandPaletteItem(id: "focus-left", command: .focusPaneLeft, section: L("导航", "Navigate"), title: L("聚焦左侧分屏", "Focus Pane Left"), shortcut: "Cmd-Opt-←", keywords: "focus pane left"),
            CommandPaletteItem(id: "focus-right", command: .focusPaneRight, section: L("导航", "Navigate"), title: L("聚焦右侧分屏", "Focus Pane Right"), shortcut: "Cmd-Opt-→", keywords: "focus pane right"),
            CommandPaletteItem(id: "focus-up", command: .focusPaneUp, section: L("导航", "Navigate"), title: L("聚焦上方分屏", "Focus Pane Up"), shortcut: "Cmd-Opt-↑", keywords: "focus pane up"),
            CommandPaletteItem(id: "focus-down", command: .focusPaneDown, section: L("导航", "Navigate"), title: L("聚焦下方分屏", "Focus Pane Down"), shortcut: "Cmd-Opt-↓", keywords: "focus pane down"),
            CommandPaletteItem(id: "close-tab", command: .closeSelectedTab, section: L("整理", "Organize"), title: L("关闭标签", "Close Tab"), shortcut: "Cmd-W", keywords: "close tab"),
            CommandPaletteItem(id: "close-pane", command: .closeFocusedPane, section: L("整理", "Organize"), title: L("关闭分屏", "Close Pane"), shortcut: "Cmd-Shift-W", disabled: !canPerform(.closeFocusedPane), disabledReason: L("至少保留一个分屏", "Keep at least one pane"), keywords: "close pane split"),
            CommandPaletteItem(id: "move-tab-left", command: .moveTabLeft, section: L("整理", "Organize"), title: L("标签左移", "Move Tab Left"), shortcut: "Cmd-Shift-,", disabled: !canPerform(.moveTabLeft), disabledReason: L("已经在最左侧", "Already on the left"), keywords: "move tab left"),
            CommandPaletteItem(id: "move-tab-right", command: .moveTabRight, section: L("整理", "Organize"), title: L("标签右移", "Move Tab Right"), shortcut: "Cmd-Shift-.", disabled: !canPerform(.moveTabRight), disabledReason: L("已经在最右侧", "Already on the right"), keywords: "move tab right"),
            CommandPaletteItem(id: "move-tab-next-pane", command: .moveTabToNextPane, section: L("整理", "Organize"), title: L("移到下一个分屏", "Move to Next Pane"), shortcut: "Cmd-Opt-M", disabled: !canPerform(.moveTabToNextPane), disabledReason: L("需要另一个分屏", "Requires another pane"), keywords: "move tab pane"),
            CommandPaletteItem(id: "move-tab-new-split", command: .moveTabToNewRightSplit, section: L("整理", "Organize"), title: L("移到右侧新分屏", "Move to New Right Split"), shortcut: "Cmd-Opt-Shift-M", disabled: !canPerform(.moveTabToNewRightSplit), disabledReason: L("需要可移动标签和可用分屏空间", "Requires a movable tab and split space"), keywords: "move tab new split"),
            CommandPaletteItem(id: "resize-left", command: .resizePaneLeft, section: L("整理", "Organize"), title: L("向左调整分屏", "Resize Pane Left"), shortcut: "Cmd-Shift-←", disabled: !canPerform(.resizePaneLeft), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split left"),
            CommandPaletteItem(id: "resize-right", command: .resizePaneRight, section: L("整理", "Organize"), title: L("向右调整分屏", "Resize Pane Right"), shortcut: "Cmd-Shift-→", disabled: !canPerform(.resizePaneRight), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split right"),
            CommandPaletteItem(id: "resize-up", command: .resizePaneUp, section: L("整理", "Organize"), title: L("向上调整分屏", "Resize Pane Up"), shortcut: "Cmd-Shift-↑", disabled: !canPerform(.resizePaneUp), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split up"),
            CommandPaletteItem(id: "resize-down", command: .resizePaneDown, section: L("整理", "Organize"), title: L("向下调整分屏", "Resize Pane Down"), shortcut: "Cmd-Shift-↓", disabled: !canPerform(.resizePaneDown), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "resize split down"),
            CommandPaletteItem(
                id: "toggle-zoom",
                command: .toggleZoom,
                section: L("视图", "View"),
                title: model.workspace.isZoomed ? L("还原当前分屏", "Restore Current Pane") : L("放大当前分屏", "Zoom Current Pane"),
                shortcut: "Cmd-Opt-Z",
                disabled: !canPerform(.toggleZoom),
                disabledReason: L("需要多个分屏", "Requires multiple panes"),
                keywords: "zoom pane"
            ),
            CommandPaletteItem(id: "equalize-splits", command: .equalizeSplits, section: L("视图", "View"), title: L("均分分屏", "Equalize Splits"), shortcut: "Cmd-Shift-=", disabled: !canPerform(.equalizeSplits), disabledReason: L("需要多个分屏", "Requires multiple panes"), keywords: "equalize split layout"),
            CommandPaletteItem(id: "flash-focused-pane", command: .flashFocusedPane, section: L("视图", "View"), title: L("闪烁当前分屏", "Flash Focused Pane"), shortcut: "Cmd-Shift-H", keywords: "flash highlight focused pane"),
            CommandPaletteItem(id: "workspace-overview", command: .toggleWorkspaceOverview, section: L("视图", "View"), title: L("工作区总览", "Workspace Overview"), shortcut: "Cmd-O", keywords: "workspace overview mission control"),
            CommandPaletteItem(id: "toggle-fullscreen", command: .toggleFullScreen, section: L("视图", "View"), title: L("切换全屏", "Toggle Full Screen"), shortcut: "Ctrl-Cmd-F", keywords: "fullscreen window mac"),
            CommandPaletteItem(id: "appearance-settings", command: .toggleSettings, section: L("视图", "View"), title: L("外观设置", "Appearance Settings"), shortcut: "Cmd-,", keywords: "appearance theme settings"),
            CommandPaletteItem(id: "duplicate-workspace", command: .duplicateWorkspace, section: L("视图", "View"), title: L("复制工作区", "Duplicate Workspace"), shortcut: "Duplicate", keywords: "workspace duplicate"),
            CommandPaletteItem(id: "reset-workspace", command: .resetWorkspace, section: L("视图", "View"), title: L("重置工作区", "Reset Workspace"), shortcut: "Reset", keywords: "workspace reset"),
            CommandPaletteItem(id: "clear-notifications", command: .clearNotifications, section: L("整理", "Organize"), title: L("清空通知", "Clear Notifications"), shortcut: "Clear", disabled: !canPerform(.clearNotifications), disabledReason: L("通知中心为空", "Notification Center is empty"), keywords: "notification clear"),
            CommandPaletteItem(id: "debug-notification", command: .testNotification, section: L("通知", "Notifications"), title: L("发送测试通知", "Send Test Notification"), shortcut: "Test", keywords: "notification test")
        ]
    }

    @MainActor
    static func shortcutGuideItems(model: ConductorWindowModel) -> [CommandShortcutGuideItem] {
        items(model: model)
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

    @MainActor
    static func shortcutGuideRows(model: ConductorWindowModel) -> [CommandShortcutGuideRowModel] {
        var previousSection: String?
        return shortcutGuideItems(model: model).enumerated().map { index, item in
            let showsSectionTitle = item.section != previousSection
            previousSection = item.section
            return CommandShortcutGuideRowModel(
                item: item,
                showsSectionTitle: showsSectionTitle,
                isFirst: index == 0
            )
        }
    }
}

struct CommandShortcutGuideItem: Identifiable, Equatable {
    let id: String
    let section: String
    let title: String
    let shortcut: String
    let systemImage: String
}

struct CommandShortcutGuideRowModel: Identifiable, Equatable {
    var id: String { item.id }
    let item: CommandShortcutGuideItem
    let showsSectionTitle: Bool
    let isFirst: Bool
}

private struct CommandPaletteHeader: View {
    let subtitle: String
    let closeHelp: String
    let onClose: () -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "command")
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.92))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            Text(L("命令", "Commands"))
                .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Text(subtitle)
                .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 10)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 22, height: 22)
                    .background(theme.floatingControlFill.opacity(0.82))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeHelp)
            .macNativeTooltip(closeHelp)
        }
        .frame(height: 24)
    }
}

private struct CommandSectionTitle: View {
    let title: String
    var compact = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    init(_ title: String, compact: Bool = false) {
        self.title = title
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.conductorSystem(size: compact ? 9.8 : 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Rectangle()
                .fill(theme.floatingSeparator)
                .frame(height: 1)
        }
        .padding(.top, compact ? 3 : 5)
        .padding(.horizontal, 4)
    }
}

private struct CommandButton: View {
    let command: CommandPaletteItem
    var selected = false
    let selectionNamespace: Namespace.ID
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
            .background(rowBackground)
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
        .animation(ConductorMotion.selectionGlide, value: selected)
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

    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
        return ZStack {
            shape
                .fill(hovering ? theme.floatingHoverFill : theme.floatingControlFill.opacity(0.50))
            if selected {
                shape
                    .fill(theme.floatingSelectedFill)
                    .matchedGeometryEffect(id: "command-selection", in: selectionNamespace)
            }
        }
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

private struct WorkspaceOverviewSnapshot: Equatable {
    let chromeClarity: ChromeClarity
    let items: [WorkspaceOverviewItemSnapshot]
    let selectedWorkspaceID: WorkspaceID
    let notifications: TerminalNotificationSnapshot

    @MainActor
    init(model: ConductorWindowModel) {
        self.chromeClarity = model.appearance.chromeClarity
        self.items = model.workspaces.map(WorkspaceOverviewItemSnapshot.init(workspace:))
        self.selectedWorkspaceID = model.workspace.id
        self.notifications = model.notifications.snapshot
    }

    var workspaceCount: Int {
        items.count
    }
}

private struct WorkspaceOverviewItemSnapshot: Identifiable, Equatable {
    let workspace: WorkspaceState

    var id: WorkspaceID {
        workspace.id
    }

    init(workspace: WorkspaceState) {
        self.workspace = workspace
    }

    var searchCandidate: ConductorSearchCandidate {
        ConductorSearchCandidate(
            id: workspace.id.description,
            title: workspace.title,
            subtitle: Self.subtitle(for: workspace),
            keywords: Self.keywords(for: workspace),
            section: L("工作区", "Workspaces"),
            systemImage: WorkspaceChromeGlyph.systemName(selected: false)
        )
    }

    private static func subtitle(for workspace: WorkspaceState) -> String {
        let terminalCount = workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
        return L("\(workspace.panes.count) 个分屏 · \(terminalCount) 个终端", "\(workspace.panes.count) panes · \(terminalCount) terminals")
    }

    private static func keywords(for workspace: WorkspaceState) -> [String] {
        var parts: [String] = []
        for pane in workspace.panes.values {
            for tab in pane.tabs {
                parts.append(tab.title)
                if let workingDirectory = tab.workingDirectory {
                    parts.append(workingDirectory)
                }
            }
        }
        return parts
    }
}

private struct WorkspaceOverviewFilterResult: Equatable {
    let items: [WorkspaceOverviewItemSnapshot]
    let ids: [WorkspaceID]
    let searchResults: [ConductorSearchResult]

    init(items: [WorkspaceOverviewItemSnapshot], query: String = "") {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id.description, $0) })
        let searchResults = ConductorSearchMatcher.results(for: query, in: items.map(\.searchCandidate))
        self.items = searchResults.compactMap { itemByID[$0.candidate.id] }
        self.ids = self.items.map(\.id)
        self.searchResults = searchResults
    }
}

private struct WorkspaceOverviewPanel: View {
    let model: ConductorWindowModel
    let snapshot: WorkspaceOverviewSnapshot
    @State private var query = ""
    @State private var highlightedWorkspaceID: WorkspaceID?
    @FocusState private var searchFocused: Bool
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    private var filteredResult: WorkspaceOverviewFilterResult {
        WorkspaceOverviewFilterResult(items: snapshot.items, query: query)
    }

    var body: some View {
        let result = filteredResult
        ZStack {
            ConductorGlassSurface(style: .panel, clarity: snapshot.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    FloatingPanelDivider()
                    searchField

                    if result.items.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(result.items) { item in
                                    WorkspaceOverviewRow(
                                        workspace: item.workspace,
                                        theme: theme,
                                        selected: item.id == snapshot.selectedWorkspaceID,
                                        highlighted: item.id == highlightedWorkspaceID,
                                        unreadCount: snapshot.notifications.unreadCount(for: item.id),
                                        unreadCountForPane: { paneID in
                                            snapshot.notifications.unreadCount(for: paneID)
                                        }
                                    ) {
                                        openWorkspace(item.id)
                                    } onHover: {
                                        highlightedWorkspaceID = item.id
                                    }
                                    .transition(ConductorMotion.rowTransition(itemCount: result.items.count))
                                }
                            }
                            .padding(.vertical, 1)
                            .animation(ConductorMotion.list(itemCount: result.items.count), value: result.ids)
                        }
                        .scrollIndicators(.visible)
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(12)
            }
            .frame(width: 620, height: 420)
            .onAppear {
                highlightedWorkspaceID = snapshot.selectedWorkspaceID
                focusSearchField()
                ensureHighlight()
            }
            .onChange(of: query) {
                ensureHighlight()
            }
            .onChange(of: result.ids) {
                ensureHighlight()
            }
            .onMoveCommand { direction in
                switch direction {
                case .up:
                    moveHighlight(by: -1)
                case .down:
                    moveHighlight(by: 1)
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
            .animation(ConductorMotion.feedback, value: highlightedWorkspaceID)
        }
    }

    private var header: some View {
        FloatingPanelHeader(
            systemImage: WorkspaceChromeGlyph.systemName(selected: false),
            title: L("工作区总览", "Workspace Overview"),
            subtitle: L("\(snapshot.workspaceCount) 个工作区", "\(snapshot.workspaceCount) workspaces"),
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
                .accessibilityHidden(true)
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

    private func ensureHighlight() {
        let result = filteredResult
        let preferredID = highlightedWorkspaceID.flatMap { id in
            result.ids.contains(id) ? id.description : nil
        } ?? (result.ids.contains(snapshot.selectedWorkspaceID) ? snapshot.selectedWorkspaceID.description : nil)
        let resolvedID = ConductorSearchSelection.resolvedSelection(
            currentID: preferredID,
            results: result.searchResults
        )
        highlightedWorkspaceID = resolvedID.flatMap { id in
            result.items.first { $0.id.description == id }?.id
        }
    }

    private func moveHighlight(by offset: Int) {
        let result = filteredResult
        let resolvedID = ConductorSearchSelection.move(
            currentID: highlightedWorkspaceID?.description,
            by: offset,
            results: result.searchResults,
            wraps: false
        )
        highlightedWorkspaceID = resolvedID.flatMap { id in
            result.items.first { $0.id.description == id }?.id
        }
    }

    private func openHighlightedWorkspace() {
        ensureHighlight()
        guard let highlightedWorkspaceID else { return }
        openWorkspace(highlightedWorkspaceID)
    }

    private func openWorkspace(_ workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.performShellMotion(ConductorMotion.panel) {
            model.hideWorkspaceOverview()
        }
    }

    private func focusSearchField() {
        Task { @MainActor in
            searchFocused = true
        }
    }
}

private struct WorkspaceOverviewRow: View {
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
            HStack(spacing: 10) {
                Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                    .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(workspace.title)
                        .font(.conductorSystem(size: 12.4, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(focusedTerminalTitle)
                        .font(.conductorSystem(size: 10.3, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    WorkspaceOverviewMetric(systemImage: "square.split.2x2", value: "\(workspace.panes.count)")
                    WorkspaceOverviewMetric(systemImage: "terminal", value: "\(terminalCount)")
                    if workspace.isZoomed {
                        WorkspaceOverviewMetric(systemImage: "arrow.up.left.and.arrow.down.right", value: L("放大", "Zoom"))
                    }
                    if unreadCount > 0 {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(theme.floatingEmphasis)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .conductorSignalPulse(active: true, trigger: unreadCount)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 46)
            .background(cardFill)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                    .stroke(borderColor, lineWidth: selected || highlighted ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
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
        .animation(ConductorMotion.standard, value: selected)
        .animation(ConductorMotion.feedback, value: highlighted)
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.attention, value: unreadCount)
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

    private var iconFill: Color {
        if selected {
            return theme.floatingSelectedFill
        }
        return theme.floatingControlFill.opacity(0.64)
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
