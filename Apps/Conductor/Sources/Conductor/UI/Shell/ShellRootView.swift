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
    private let fileManagerAnimationDuration: TimeInterval = ConductorMotion.Timing.panelDrawer

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
            floatingPanelOverlay(shellSnapshot: shellSnapshot)
        }
        .animation(model.shellAnimation(ConductorMotion.panel), value: shellSnapshot.commandPaletteVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: shellSnapshot.settingsPanelVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: shellSnapshot.workspaceOverviewVisible)
        .animation(model.shellAnimation(ConductorMotion.panel), value: model.terminalSearchVisible)
        .onAppear {
            synchronizeFileManagerPresentation(animated: false)
            model.scheduleWorkspaceMetadataRefresh(reason: "shell-appear", debounceNanoseconds: 250_000_000)
        }
        .onChange(of: model.workspace.id) { _, _ in
            model.scheduleWorkspaceMetadataRefresh(reason: "workspace-selected", debounceNanoseconds: 250_000_000)
        }
        .onChange(of: model.workspaces.map(\.id)) { _, _ in
            model.scheduleWorkspaceMetadataRefresh(reason: "workspace-list")
        }
        .onChange(of: model.workspaceFileTabs.map(\.id)) { _, _ in
            model.scheduleWorkspaceMetadataRefresh(reason: "file-tabs")
        }
        .onChange(of: model.workspaceWebTabs.map(\.id)) { _, _ in
            model.scheduleWorkspaceMetadataRefresh(reason: "web-tabs")
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

    @ViewBuilder
    private func floatingPanelOverlay(shellSnapshot: ShellChromeSnapshot) -> some View {
        let hasFloatingPanel = shellSnapshot.commandPaletteVisible ||
            shellSnapshot.settingsPanelVisible ||
            shellSnapshot.workspaceOverviewVisible

        ZStack {
            if hasFloatingPanel {
                FloatingPanelCursorShield()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(0)
            }
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
                .zIndex(10)
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
                .zIndex(20)
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
                .zIndex(30)
            }
            if let toast = model.shellToast {
                ShellToastView(
                    toast: toast,
                    onAction: performShellToastAction,
                    onDismiss: { model.dismissShellToast(id: toast.id) }
                )
                .environment(\.conductorTheme, model.theme)
                .environment(\.conductorFontScale, model.appearance.fontScale)
                .environment(\.conductorFontFamily, model.appearance.fontFamily)
                .environment(\.locale, model.appearance.language.locale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 64)
                .padding(.trailing, 26)
                .transition(ConductorMotion.panelTransition)
                .zIndex(60)
            }
        }
    }

    private func performShellToastAction(_ action: ConductorShellToastAction?) {
        model.dismissShellToast()
        switch action {
        case .openNotificationSettings:
            model.openSystemNotificationSettings()
        case .checkNotificationPermission:
            model.checkNotificationPermissionFromToolbar()
        case .none:
            break
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
                    updateState: model.updateState,
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
            .shadow(color: Color.black.opacity(model.theme.usesDarkChrome ? 0.14 : 0.08), radius: 12, x: -4, y: 0)
            .animation(fileManagerTrayAnimation, value: fileManagerTrayVisible)
        }
    }

    private var fileManagerTrayAnimation: Animation? {
        guard !model.appearance.reducedMotion else { return nil }
        return ConductorMotion.panelDrawer
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
        if model.selectedWorkspaceWebTab != nil {
            ConductorWebWorkspaceView(
                model: model,
                snapshot: ConductorWebSnapshot(model: model)
            )
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
                    model.performCommand(.findNext)
                }
            Text(statusText)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .monospacedDigit()
                .frame(minWidth: 38, alignment: .trailing)
            terminalSearchButton("chevron.up", help: L("上一个搜索结果", "Previous Search Result")) {
                model.performCommand(.findPrevious)
            }
            terminalSearchButton("chevron.down", help: L("下一个搜索结果", "Next Search Result")) {
                model.performCommand(.findNext)
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
                .stroke(theme.floatingStroke.opacity(0.42), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.10 : 0.05), radius: 8, x: 0, y: 4)
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
        Rectangle()
            .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.30 : 0.20))
            .frame(width: 1)
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
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
            .keyboardShortcut(.cancelAction)
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
    let jumpTargetCount: Int

    @MainActor
    init(model: ConductorWindowModel) {
        self.subtitle = model.workspace.title
        self.chromeClarity = model.appearance.chromeClarity
        let commands = ConductorCommandCatalog.items(model: model)
        self.commands = commands
        self.jumpTargetCount = commands.filter(\.isJumpTarget).count
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
            ConductorGlassSurface(style: .palette, clarity: snapshot.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 6) {
                    commandHeader
                    commandSearchField
                    commandResults
                }
                .padding(8)
            }
            .frame(width: 604, height: 372)
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
            title: L("命令与跳转", "Commands and Jumps"),
            subtitle: snapshot.subtitle,
            detail: L("\(snapshot.jumpTargetCount) 个可跳转目标", "\(snapshot.jumpTargetCount) jump targets"),
            closeHelp: L("关闭命令面板", "Close Command Palette")
        ) {
            model.hideCommandPalette()
        }
    }

    private var commandSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .accessibilityHidden(true)
            TextField(L("搜索命令、工作区、终端或网页", "Search commands, workspaces, terminals, or web"), text: $query)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 12.4, weight: .medium, scale: fontScale))
                .focused($searchFocused)
            Text("↵")
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(theme.floatingControlFill.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.72), lineWidth: 0.8)
        }
    }

    private var commandResults: some View {
        Group {
            if filteredResult.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "command")
                        .font(.conductorSystem(size: 22, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    Text(L("没有匹配的结果", "No matching results"))
                        .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
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
        switch command.action {
        case .command(let shellCommand):
            _ = model.performCommand(shellCommand)
        case .workspace(let workspaceID):
            ConductorMotion.withoutAnimation {
                _ = model.activateWorkspace(workspaceID, source: .commandPalette)
            }
        case .terminal(let terminalID):
            _ = model.controlFocusTerminal(terminalID)
        case .webTab(let workspaceID, let tabID):
            model.selectWorkspaceWebTab(tabID, in: workspaceID)
        }
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

private enum CommandPaletteAction: Equatable {
    case command(ConductorShellCommand)
    case workspace(WorkspaceID)
    case terminal(TerminalID)
    case webTab(workspaceID: WorkspaceID, tabID: WebTabID)
}

private struct CommandPaletteItem: Identifiable, Equatable {
    let id: String
    let action: CommandPaletteAction
    let section: String
    let title: String
    let outcome: String
    let shortcut: String
    let disabled: Bool
    let disabledReason: String?
    let rankingBadge: String?
    let rankingHint: String?
    let keywords: String
    let searchText: String
    let systemImage: String

    init(
        id: String,
        action: CommandPaletteAction,
        section: String,
        title: String,
        outcome: String,
        shortcut: String,
        systemImage: String,
        disabled: Bool = false,
        disabledReason: String? = nil,
        rankingBadge: String? = nil,
        rankingHint: String? = nil,
        keywords: String = ""
    ) {
        self.id = id
        self.action = action
        self.section = section
        self.title = title
        self.outcome = outcome
        self.shortcut = shortcut
        self.disabled = disabled
        self.disabledReason = disabledReason
        self.rankingBadge = rankingBadge
        self.rankingHint = rankingHint
        self.keywords = keywords
        self.systemImage = systemImage
        self.searchText = "\(title) \(outcome) \(shortcut) \(section) \(keywords)".lowercased()
    }

    var searchCandidate: ConductorSearchCandidate {
        ConductorSearchCandidate(
            id: id,
            title: title,
            subtitle: disabled ? (disabledReason ?? outcome) : outcome,
            keywords: [keywords, section, shortcut, outcome],
            section: section,
            systemImage: systemImage,
            isEnabled: !disabled,
            disabledReason: disabledReason
        )
    }

    var isJumpTarget: Bool {
        switch action {
        case .workspace, .terminal, .webTab:
            return true
        case .command:
            return false
        }
    }

    func resolvingShortcut(using preferences: KeyboardShortcutPreferences) -> CommandPaletteItem {
        guard case .command(let command) = action else { return self }
        let resolvedShortcut = preferences.displayShortcut(for: command, fallback: shortcut)
        guard resolvedShortcut != shortcut else { return self }
        return CommandPaletteItem(
            id: id,
            action: action,
            section: section,
            title: title,
            outcome: outcome,
            shortcut: resolvedShortcut,
            systemImage: systemImage,
            disabled: disabled,
            disabledReason: disabledReason,
            rankingBadge: rankingBadge,
            rankingHint: rankingHint,
            keywords: keywords
        )
    }

    var discoveryShortcut: String {
        if shortcut.contains("Cmd") {
            return shortcut
        }
        return L("命令面板", "Command Palette")
    }

    static func rankingHint(for ranking: ConductorWindowModel.ShellCommandRanking) -> String? {
        var parts: [String] = []
        if let recentRank = ranking.recentRank {
            parts.append(
                ConductorLocalization.text(
                    zh: recentRank == 0 ? "刚刚使用过" : "最近使用过",
                    en: recentRank == 0 ? "Used just now" : "Used recently"
                )
            )
        }
        parts.append(contentsOf: ranking.contextReasons)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private enum ConductorCommandCatalog {
    @MainActor
    static func items(model: ConductorWindowModel) -> [CommandPaletteItem] {
        quickSwitchItems(model: model) + commandItems(model: model)
    }

    @MainActor
    private static func commandItems(model: ConductorWindowModel) -> [CommandPaletteItem] {
        model.shellCommandsForPalette().map { command in
            let descriptor = command.descriptor
            let disabled = !model.canPerformCommand(command)
            let ranking = model.shellCommandRanking(for: command)
            return CommandPaletteItem(
                id: descriptor.id,
                action: .command(command),
                section: descriptor.category,
                title: command.displayTitle(model: model),
                outcome: descriptor.outcome,
                shortcut: descriptor.shortcutFallback,
                systemImage: descriptor.systemImage,
                disabled: disabled,
                disabledReason: disabled ? command.disabledReason(model: model) : nil,
                rankingBadge: ranking.badge,
                rankingHint: CommandPaletteItem.rankingHint(for: ranking),
                keywords: descriptor.keywords
            )
            .resolvingShortcut(using: model.appearance.keyboardShortcuts)
        }
    }

    @MainActor
    private static func quickSwitchItems(model: ConductorWindowModel) -> [CommandPaletteItem] {
        let section = L("快速切换", "Quick Switch")
        var items: [CommandPaletteItem] = []
        items.reserveCapacity(model.workspaces.count * 3)

        for workspace in orderedWorkspaces(model: model) {
            let metadata = model.workspaceMetadataSnapshots[workspace.id]
            let workspaceSelected = workspace.id == model.workspace.id &&
                model.selectedWorkspaceFileTabID == nil &&
                model.selectedWorkspaceWebTabID == nil

            items.append(CommandPaletteItem(
                id: "jump-workspace-\(workspace.id.description)",
                action: .workspace(workspace.id),
                section: section,
                title: workspaceSelected ? L("当前工作区：\(workspace.title)", "Current Workspace: \(workspace.title)") : workspace.title,
                outcome: quickWorkspaceSubtitle(workspace: workspace, metadata: metadata),
                shortcut: L("跳转", "Jump"),
                systemImage: WorkspaceChromeGlyph.systemName(selected: workspaceSelected),
                rankingBadge: workspaceSelected ? L("当前", "Current") : nil,
                rankingHint: metadata?.rootPath ?? quickWorkspaceSubtitle(workspace: workspace, metadata: metadata),
                keywords: quickWorkspaceKeywords(workspace: workspace, metadata: metadata)
            ))

            let terminalSummaries = orderedTerminalSummaries(
                quickTerminalSummaries(workspace: workspace, metadata: metadata)
            )
            for terminal in terminalSummaries.prefix(12) {
                items.append(CommandPaletteItem(
                    id: "jump-terminal-\(terminal.id.description)",
                    action: .terminal(terminal.id),
                    section: section,
                    title: terminal.title,
                    outcome: quickTerminalSubtitle(workspace: workspace, terminal: terminal),
                    shortcut: L("终端", "Terminal"),
                    systemImage: terminal.activeAgentTitle?.isEmpty == false ? "sparkles" : "terminal",
                    rankingBadge: terminal.selected ? L("选中", "Selected") : nil,
                    rankingHint: terminal.workingDirectory ?? workspace.title,
                    keywords: [
                        workspace.title,
                        terminal.workingDirectory,
                        terminal.activeAgentTitle,
                        terminal.agentState,
                        "terminal shell pane jump switch"
                    ]
                    .compactMap { $0 }
                    .joined(separator: " ")
                ))
            }

            for webTab in orderedWebSummaries(metadata?.webTabs ?? []).prefix(10) {
                let title = webTab.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = webTab.url?.trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(CommandPaletteItem(
                    id: "jump-web-\(webTab.id.rawValue.uuidString)",
                    action: .webTab(workspaceID: workspace.id, tabID: webTab.id),
                    section: section,
                    title: title?.isEmpty == false ? title! : (url?.isEmpty == false ? url! : L("未命名网页", "Untitled Web Tab")),
                    outcome: quickWebSubtitle(workspace: workspace, webTab: webTab),
                    shortcut: L("网页", "Web"),
                    systemImage: webTab.loading ? "globe.badge.chevron.backward" : "globe",
                    rankingBadge: webTab.selected ? L("选中", "Selected") : nil,
                    rankingHint: url ?? webTab.pendingAddress,
                    keywords: [
                        workspace.title,
                        title,
                        url,
                        webTab.pendingAddress,
                        "web browser tab jump switch"
                    ]
                    .compactMap { $0 }
                    .joined(separator: " ")
                ))
            }
        }

        return items
    }

    @MainActor
    private static func orderedWorkspaces(model: ConductorWindowModel) -> [WorkspaceState] {
        model.workspaces.enumerated()
            .sorted { lhs, rhs in
                let lhsCurrent = lhs.element.id == model.workspace.id
                let rhsCurrent = rhs.element.id == model.workspace.id
                if lhsCurrent != rhsCurrent {
                    return lhsCurrent
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func orderedTerminalSummaries(
        _ terminals: [WorkspaceMetadataSnapshot.TerminalSummary]
    ) -> [WorkspaceMetadataSnapshot.TerminalSummary] {
        terminals.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.selected != rhs.element.selected {
                    return lhs.element.selected
                }
                let lhsActive = lhs.element.activeAgentTitle?.isEmpty == false
                let rhsActive = rhs.element.activeAgentTitle?.isEmpty == false
                if lhsActive != rhsActive {
                    return lhsActive
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func orderedWebSummaries(
        _ webTabs: [WorkspaceMetadataSnapshot.WebSummary]
    ) -> [WorkspaceMetadataSnapshot.WebSummary] {
        webTabs.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.selected != rhs.element.selected {
                    return lhs.element.selected
                }
                if lhs.element.loading != rhs.element.loading {
                    return lhs.element.loading
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func quickTerminalSummaries(
        workspace: WorkspaceState,
        metadata: WorkspaceMetadataSnapshot?
    ) -> [WorkspaceMetadataSnapshot.TerminalSummary] {
        if let terminals = metadata?.terminals, !terminals.isEmpty {
            return terminals
        }
        return workspace.panes.values.flatMap { pane in
            pane.tabs.map { tab in
                WorkspaceMetadataSnapshot.TerminalSummary(
                    id: tab.id,
                    paneID: pane.id,
                    title: tab.title,
                    workingDirectory: tab.workingDirectory,
                    selected: workspace.focusedPaneID == pane.id && pane.selectedTabID == tab.id,
                    activeAgentTitle: tab.agentSnapshot?.displayName,
                    readonly: false
                )
            }
        }
    }

    private static func quickWorkspaceSubtitle(
        workspace: WorkspaceState,
        metadata: WorkspaceMetadataSnapshot?
    ) -> String {
        if let rootPath = metadata?.rootPath, !rootPath.isEmpty {
            return abbreviatedPath(rootPath)
        }
        let terminalCount = metadata?.counts.terminalCount ?? workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
        return L("\(workspace.panes.count) 个分屏 · \(terminalCount) 个终端", "\(workspace.panes.count) panes · \(terminalCount) terminals")
    }

    private static func quickWorkspaceKeywords(
        workspace: WorkspaceState,
        metadata: WorkspaceMetadataSnapshot?
    ) -> String {
        var parts = [workspace.title, metadata?.projectName, metadata?.rootPath, ]
        parts.append(contentsOf: metadata?.terminals.map(\.title) ?? [])
        parts.append(contentsOf: metadata?.webTabs.compactMap(\.title) ?? [])
        parts.append(contentsOf: metadata?.webTabs.compactMap(\.url) ?? [])
        parts.append("workspace project switch jump")
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    private static func quickTerminalSubtitle(
        workspace: WorkspaceState,
        terminal: WorkspaceMetadataSnapshot.TerminalSummary
    ) -> String {
        if let agent = terminal.activeAgentTitle, !agent.isEmpty {
            return L("\(workspace.title) · \(agent) 运行中", "\(workspace.title) · \(agent) running")
        }
        if let workingDirectory = terminal.workingDirectory, !workingDirectory.isEmpty {
            return "\(workspace.title) · \(abbreviatedPath(workingDirectory))"
        }
        return workspace.title
    }

    private static func quickWebSubtitle(
        workspace: WorkspaceState,
        webTab: WorkspaceMetadataSnapshot.WebSummary
    ) -> String {
        if let error = webTab.errorMessage, !error.isEmpty {
            return "\(workspace.title) · \(error)"
        }
        if webTab.loading {
            return L("\(workspace.title) · 正在载入", "\(workspace.title) · Loading")
        }
        if let url = webTab.url, !url.isEmpty {
            return "\(workspace.title) · \(url)"
        }
        return workspace.title
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalized = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 3 else { return normalized }
        if normalized.hasPrefix("~/") {
            return "~/" + components.suffix(3).joined(separator: "/")
        }
        return ".../" + components.suffix(3).joined(separator: "/")
    }

    @MainActor
    static func shortcutGuideItems(model: ConductorWindowModel) -> [CommandShortcutGuideItem] {
        commandItems(model: model)
            .filter { $0.section != L("调试", "Debug") }
            .compactMap { command -> CommandShortcutGuideItem? in
                guard case .command(let shellCommand) = command.action else { return nil }
                return CommandShortcutGuideItem(
                    id: command.id,
                    command: shellCommand,
                    section: command.section,
                    title: command.title,
                    shortcut: command.discoveryShortcut,
                    systemImage: command.systemImage,
                    shortcutStatus: model.shortcutAssignmentTitle(for: shellCommand)
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
    let command: ConductorShellCommand
    let section: String
    let title: String
    let shortcut: String
    let systemImage: String
    let shortcutStatus: String
}

struct CommandShortcutGuideRowModel: Identifiable, Equatable {
    var id: String { item.id }
    let item: CommandShortcutGuideItem
    let showsSectionTitle: Bool
    let isFirst: Bool
}

private struct CommandPaletteHeader: View {
    let title: String
    let subtitle: String
    let detail: String
    let closeHelp: String
    let onClose: () -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "command")
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.82))
                .frame(width: 16, height: 18)
                .accessibilityHidden(true)

            Text(title)
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Text("\(subtitle) · \(detail)")
                .font(.conductorSystem(size: 9.8, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 10)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 9, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(theme.floatingControlFill.opacity(0.58))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeHelp)
            .macNativeTooltip(closeHelp)
        }
        .frame(height: 22)
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
                .font(.conductorSystem(size: compact ? 9.2 : 10.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
            Rectangle()
                .fill(theme.floatingSeparator.opacity(0.72))
                .frame(height: 1)
        }
        .padding(.top, compact ? 4 : 5)
        .padding(.horizontal, 3)
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
            HStack(spacing: 7) {
                Image(systemName: command.systemImage)
                    .font(.conductorSystem(size: 10.4, weight: .semibold, scale: fontScale))
                    .foregroundStyle(iconColor)
                    .frame(width: 20, height: 20)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.conductorSystem(size: 11.8, weight: selected ? .semibold : .medium, scale: fontScale))
                        .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(command.disabled ? (command.disabledReason ?? command.outcome) : command.outcome)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let rankingBadge = command.rankingBadge {
                    Text(rankingBadge)
                        .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                        .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : theme.floatingEmphasis.opacity(0.9))
                        .padding(.horizontal, 6)
                        .frame(height: 17)
                        .background(theme.floatingSelectedFill.opacity(command.disabled ? 0.24 : 0.5))
                        .clipShape(Capsule())
                }

                Text(command.shortcut)
                    .font(.conductorSystem(size: 9.8, weight: .medium, scale: fontScale))
                    .foregroundStyle(command.disabled ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(command.disabled ? theme.floatingControlFill.opacity(0.34) : theme.floatingControlFill.opacity(0.56))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 7)
            .frame(height: 38)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(command.disabled)
        .opacity(command.disabled ? 0.62 : 1)
        .macNativeTooltip(command.rankingHint ?? command.outcome)
        .onHover { value in
            guard hovering != value else { return }
            hovering = value
            if value {
                onHover()
            }
        }
    }

    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return ZStack {
            shape
                .fill(hovering ? theme.floatingHoverFill.opacity(0.54) : Color.clear)
            if selected {
                shape
                    .fill(theme.floatingSelectedFill.opacity(0.66))
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
            return theme.floatingControlFill.opacity(0.76)
        }
        return command.disabled ? theme.floatingControlFill.opacity(0.24) : theme.floatingControlFill.opacity(0.42)
    }
}

private struct WorkspaceOverviewSnapshot: Equatable {
    let chromeClarity: ChromeClarity
    let items: [WorkspaceOverviewItemSnapshot]
    let selectedWorkspaceID: WorkspaceID

    @MainActor
    init(model: ConductorWindowModel) {
        self.chromeClarity = model.appearance.chromeClarity
        self.items = model.workspaces.map { workspace in
            WorkspaceOverviewItemSnapshot(
                workspace: workspace,
                metadataByTerminalID: model.metadataByTerminalID,
                workspaceMetadata: model.workspaceMetadataSnapshots[workspace.id],
                unreadCount: model.attentionUnreadCount(for: workspace.id),
                resumableAgents: model.controlResumableTerminalAgents(workspaceID: workspace.id)
            )
        }
        self.selectedWorkspaceID = model.workspace.id
    }

    var workspaceCount: Int {
        items.count
    }
}

private struct WorkspaceOverviewItemSnapshot: Identifiable, Equatable {
    let workspace: WorkspaceState
    let workspaceMetadata: WorkspaceMetadataSnapshot?
    let terminalSummaries: [WorkspaceOverviewTerminalSummary]
    let fileSummaries: [WorkspaceMetadataSnapshot.FileSummary]
    let webSummaries: [WorkspaceMetadataSnapshot.WebSummary]
    let unreadCount: Int
    let resumableAgents: [TerminalAgentResumeBatchTarget]

    var id: WorkspaceID {
        workspace.id
    }

    init(
        workspace: WorkspaceState,
        metadataByTerminalID: [TerminalID: TerminalDisplayMetadata],
        workspaceMetadata: WorkspaceMetadataSnapshot?,
        unreadCount: Int,
        resumableAgents: [TerminalAgentResumeBatchTarget]
    ) {
        self.workspace = workspace
        self.workspaceMetadata = workspaceMetadata
        self.unreadCount = unreadCount
        self.resumableAgents = resumableAgents
        self.fileSummaries = workspaceMetadata?.files ?? []
        self.webSummaries = workspaceMetadata?.webTabs ?? []
        self.terminalSummaries = workspace.panes.values
            .flatMap(\.tabs)
            .map { tab in
                let metadata = metadataByTerminalID[tab.id]
                return WorkspaceOverviewTerminalSummary(
                    id: tab.id,
                    title: tab.title,
                    workingDirectory: metadata?.workingDirectory ?? tab.workingDirectory,
                    activeAgentTitle: metadata?.activeAgentTitle
                )
            }
    }

    var searchCandidate: ConductorSearchCandidate {
        ConductorSearchCandidate(
            id: workspace.id.description,
            title: workspace.title,
            subtitle: subtitle,
            keywords: keywords,
            section: L("工作区", "Workspaces"),
            systemImage: WorkspaceChromeGlyph.systemName(selected: false)
        )
    }

    var terminalCount: Int {
        terminalSummaries.count
    }

    var activeAgentCount: Int {
        workspaceMetadata?.activeAgentCount ?? terminalSummaries.filter { $0.activeAgentTitle?.isEmpty == false }.count
    }

    var subtitle: String {
        if let projectName = workspaceMetadata?.projectName,
           projectName != workspace.title {
            return projectName
        }
        return L("\(workspace.panes.count) 个分屏 · \(terminalCount) 个终端", "\(workspace.panes.count) panes · \(terminalCount) terminals")
    }

    var rootDisplay: String {
        guard let root = workspaceMetadata?.rootPath else {
            return terminalSummaries.compactMap(\.workingDirectory).first ?? L("未检测到项目根目录", "Project root not detected")
        }
        return Self.abbreviatedPath(root)
    }

    var portDisplay: String {
        guard let metadata = workspaceMetadata else { return L("等待刷新", "Refreshing") }
        if !metadata.devServers.isEmpty {
            return metadata.devServers.prefix(2).map { ":\($0.port)" }.joined(separator: " ")
        }
        guard !metadata.runningPorts.isEmpty else { return L("无端口", "No ports") }
        return metadata.runningPorts.prefix(2).map { ":\($0)" }.joined(separator: " ")
    }

    var healthDisplay: String {
        guard let health = workspaceMetadata?.health else {
            return L("刷新中", "Refreshing")
        }
        switch health {
        case "ok":
            return L("正常", "Healthy")
        case "metadata_partial":
            return L("部分信息不可用", "Partial metadata")
        case "root_unknown":
            return L("未识别根目录", "Root unknown")
        default:
            return health
        }
    }

    var keywords: [String] {
        var parts = [workspace.title, subtitle, rootDisplay, portDisplay]
        parts.append(contentsOf: terminalSummaries.map(\.title))
        parts.append(contentsOf: terminalSummaries.compactMap(\.workingDirectory))
        parts.append(contentsOf: terminalSummaries.compactMap(\.activeAgentTitle))
        parts.append(contentsOf: fileSummaries.map(\.title))
        parts.append(contentsOf: fileSummaries.map(\.path))
        parts.append(contentsOf: webSummaries.compactMap(\.title))
        parts.append(contentsOf: webSummaries.compactMap(\.url))
        parts.append(contentsOf: workspaceMetadata?.devServers.map(\.label) ?? [])
        parts.append(contentsOf: workspaceMetadata?.devServers.map(\.url) ?? [])
        parts.append(contentsOf: workspaceMetadata?.runningPorts.map(String.init) ?? [])
        return parts
    }

    private static func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let normalized = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        let components = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 3 else { return normalized }
        if normalized.hasPrefix("~/") {
            return "~/" + components.suffix(3).joined(separator: "/")
        }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}

private struct WorkspaceOverviewTerminalSummary: Identifiable, Equatable {
    let id: TerminalID
    let title: String
    let workingDirectory: String?
    let activeAgentTitle: String?
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
        let selectedItem = inspectorItem(in: result)
        ZStack {
            ConductorGlassSurface(style: .panel, clarity: snapshot.chromeClarity, interactive: true) {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    FloatingPanelDivider()

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            searchField

                            if result.items.isEmpty {
                                emptyState
                            } else {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(result.items) { item in
                                            WorkspaceOverviewListRow(
                                                item: item,
                                                selected: item.id == snapshot.selectedWorkspaceID,
                                                highlighted: item.id == highlightedWorkspaceID
                                            ) {
                                                highlightedWorkspaceID = item.id
                                            } open: {
                                                openWorkspace(item.id)
                                            } openRoot: {
                                                openWorkspaceRoot(item.id)
                                            } openFirstService: {
                                                openWorkspaceFirstService(item.id)
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
                        .frame(width: 286)

                        Rectangle()
                            .fill(theme.floatingSeparator.opacity(0.82))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)

                        WorkspaceInspectorPane(
                            model: model,
                            item: selectedItem,
                            selectedWorkspaceID: snapshot.selectedWorkspaceID,
                            openWorkspace: openWorkspace
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(12)
            }
            .frame(width: 760, height: 510)
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
            .animation(ConductorMotion.feedback, value: highlightedWorkspaceID)
        }
    }

    private var header: some View {
        FloatingPanelHeader(
            systemImage: WorkspaceChromeGlyph.systemName(selected: false),
            title: L("工作区", "Workspaces"),
            subtitle: L("\(snapshot.workspaceCount) 个工作区 · 状态检查器", "\(snapshot.workspaceCount) workspaces · inspector"),
            closeHelp: L("关闭工作区面板", "Close Workspace Panel")
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
                .stroke(theme.floatingStroke.opacity(0.42), lineWidth: 0.6)
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

    private func inspectorItem(in result: WorkspaceOverviewFilterResult) -> WorkspaceOverviewItemSnapshot? {
        if let highlightedWorkspaceID,
           let item = result.items.first(where: { $0.id == highlightedWorkspaceID }) {
            return item
        }
        if let item = result.items.first(where: { $0.id == snapshot.selectedWorkspaceID }) {
            return item
        }
        return result.items.first
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

    private func openWorkspaceRoot(_ workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.performCommand(.openCurrentWorkspaceRoot)
    }

    private func openWorkspaceFirstService(_ workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.performCommand(.openCurrentWorkspaceFirstService)
    }

    private func focusSearchField() {
        Task { @MainActor in
            searchFocused = true
        }
    }
}

private struct WorkspaceOverviewListRow: View {
    let item: WorkspaceOverviewItemSnapshot
    let selected: Bool
    let highlighted: Bool
    let inspect: () -> Void
    let open: () -> Void
    let openRoot: () -> Void
    let openFirstService: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: inspect) {
            HStack(spacing: 8) {
                Image(systemName: WorkspaceChromeGlyph.systemName(selected: selected))
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .frame(width: 22, height: 22)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(item.workspace.title)
                            .font(.conductorSystem(size: 11.8, weight: highlighted ? .semibold : .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if item.unreadCount > 0 {
                            WorkspaceInspectorPill(systemImage: "bell.fill", value: "\(item.unreadCount)", tone: .attention)
                        }
                        if item.activeAgentCount > 0 {
                            WorkspaceInspectorPill(systemImage: "sparkles", value: "\(item.activeAgentCount)", tone: .accent)
                        }
                    }

                    Text(item.rootDisplay)
                        .font(.conductorSystem(size: 9.6, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.portDisplay)
                        .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
                .frame(width: 58, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: 48)
            .background(rowFill)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: highlighted || selected ? 0.9 : 0.6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L("切到工作区", "Switch to Workspace"), action: open)
            if item.workspaceMetadata?.rootPath != nil {
                Button(L("在 Finder 打开根目录", "Open Root in Finder")) {
                    openRoot()
                }
            }
            if let port = item.workspaceMetadata?.runningPorts.first {
                Button(L("打开端口 :\(port)", "Open Port :\(port)")) {
                    openFirstService()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.workspace.title), \(item.rootDisplay), \(item.portDisplay)")
        .macNativeTooltip(L("查看工作区状态", "Inspect workspace status"))
        .onHover { value in
            hovering = value
            if value {
                inspect()
            }
        }
    }

    private var rowFill: Color {
        if highlighted || selected {
            return theme.floatingSelectedFill.opacity(selected ? 0.84 : 0.62)
        }
        return hovering ? theme.floatingHoverFill.opacity(0.66) : theme.floatingControlFill.opacity(0.42)
    }

    private var iconFill: Color {
        selected ? theme.floatingControlFill.opacity(0.82) : theme.floatingControlFill.opacity(0.42)
    }

    private var borderColor: Color {
        if selected || highlighted {
            return theme.floatingSelectedStroke.opacity(0.80)
        }
        return theme.floatingStroke.opacity(0.64)
    }
}

private struct WorkspaceInspectorPane: View {
    let model: ConductorWindowModel
    let item: WorkspaceOverviewItemSnapshot?
    let selectedWorkspaceID: WorkspaceID
    let openWorkspace: (WorkspaceID) -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Group {
            if let item {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorHeader(item)
                    HStack(spacing: 6) {
                        WorkspaceInspectorPill(systemImage: "square.split.2x2", value: "\(item.workspace.panes.count)", tone: .neutral)
                        WorkspaceInspectorPill(systemImage: "terminal", value: "\(item.terminalCount)", tone: .neutral)
                        WorkspaceInspectorPill(systemImage: "doc.text", value: "\(item.fileSummaries.count)", tone: item.fileSummaries.isEmpty ? .neutral : .accent)
                        WorkspaceInspectorPill(systemImage: "globe", value: "\(item.webSummaries.count)", tone: item.webSummaries.isEmpty ? .neutral : .accent)
                        WorkspaceInspectorPill(systemImage: "network", value: item.portDisplay, tone: item.workspaceMetadata?.runningPorts.isEmpty == false ? .accent : .neutral)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    WorkspaceInspectorSection(title: L("项目", "Project")) {
                        WorkspaceInspectorFact(label: L("根目录", "Root"), value: item.rootDisplay, systemImage: "folder")
                        WorkspaceInspectorFact(label: L("健康", "Health"), value: item.healthDisplay, systemImage: "waveform.path.ecg")
                        if let refreshedAt = item.workspaceMetadata?.refreshedAt {
                            WorkspaceInspectorFact(label: L("刷新", "Refreshed"), value: relativeTime(refreshedAt), systemImage: "clock")
                        }
                    }

                    WorkspaceInspectorSection(title: L("接续", "Continuity")) {
                        HStack(spacing: 6) {
                            WorkspaceInspectorActionButton(
                                title: item.resumableAgents.isEmpty ? L("无可续接", "No Agents") : L("续接全部", "Resume All"),
                                systemImage: "arrow.triangle.2.circlepath",
                                disabled: item.resumableAgents.isEmpty
                            ) {
                                resumeAgents(in: item.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if item.resumableAgents.isEmpty {
                            WorkspaceInspectorEmptyLine(text: L("这个工作区暂时没有可续接的 Agent", "No resumable agents in this workspace"))
                        } else {
                            ForEach(item.resumableAgents.prefix(3), id: \.terminalID) { agent in
                                WorkspaceInspectorResumeAgentLine(
                                    agent: agent,
                                    focus: { focusResumableAgent(agent) },
                                    resume: { resumeAgent(agent) },
                                    copyCommand: { copyResumeCommand(agent.resumeCommand) }
                                )
                            }
                            if item.resumableAgents.count > 3 {
                                WorkspaceInspectorEmptyLine(text: L("还有 \(item.resumableAgents.count - 3) 个可续接 Agent", "\(item.resumableAgents.count - 3) more resumable agents"))
                            }
                        }
                    }

                    WorkspaceInspectorSection(title: L("本地服务", "Local Services")) {
                        let servers = item.workspaceMetadata?.devServers ?? []
                        if servers.isEmpty {
                            WorkspaceInspectorEmptyLine(text: L("没有检测到本地服务", "No local services detected"))
                        } else {
                            ForEach(servers.prefix(3), id: \.url) { server in
                                WorkspaceInspectorDevServerLine(server: server) {
                                    openDevServer(server, in: item.id)
                                }
                            }
                            if servers.count > 3 {
                                WorkspaceInspectorEmptyLine(text: L("还有 \(servers.count - 3) 个服务", "\(servers.count - 3) more services"))
                            }
                        }
                    }

                    WorkspaceInspectorSection(title: L("终端", "Terminals")) {
                        if item.terminalSummaries.isEmpty {
                            WorkspaceInspectorEmptyLine(text: L("这个工作区还没有终端", "This workspace has no terminals"))
                        } else {
                            ForEach(item.terminalSummaries.prefix(4)) { terminal in
                                WorkspaceInspectorTerminalLine(terminal: terminal)
                            }
                            if item.terminalSummaries.count > 4 {
                                WorkspaceInspectorEmptyLine(text: L("还有 \(item.terminalSummaries.count - 4) 个终端", "\(item.terminalSummaries.count - 4) more terminals"))
                            }
                        }
                    }

                    WorkspaceInspectorSection(title: L("文件", "Files")) {
                        if item.fileSummaries.isEmpty {
                            WorkspaceInspectorEmptyLine(text: L("当前没有打开的文件", "No open files"))
                        } else {
                            ForEach(item.fileSummaries.prefix(4), id: \.id) { file in
                                WorkspaceInspectorFileLine(file: file) {
                                    model.selectWorkspaceFileTab(file.id, in: item.id)
                                }
                            }
                            if item.fileSummaries.count > 4 {
                                WorkspaceInspectorEmptyLine(text: L("还有 \(item.fileSummaries.count - 4) 个文件", "\(item.fileSummaries.count - 4) more files"))
                            }
                        }
                    }

                    WorkspaceInspectorSection(title: L("网页", "Web")) {
                        if item.webSummaries.isEmpty {
                            WorkspaceInspectorEmptyLine(text: L("当前没有打开的网页", "No open web tabs"))
                        } else {
                            ForEach(item.webSummaries.prefix(4), id: \.id) { webTab in
                                WorkspaceInspectorWebLine(webTab: webTab) {
                                    model.selectWorkspaceWebTab(webTab.id, in: item.id)
                                }
                            }
                            if item.webSummaries.count > 4 {
                                WorkspaceInspectorEmptyLine(text: L("还有 \(item.webSummaries.count - 4) 个网页", "\(item.webSummaries.count - 4) more web tabs"))
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    inspectorActions(item)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.leading")
                        .font(.conductorSystem(size: 24, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                    Text(L("选择一个工作区", "Select a workspace"))
                        .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.leading, 2)
    }

    private func inspectorHeader(_ item: WorkspaceOverviewItemSnapshot) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: WorkspaceChromeGlyph.systemName(selected: item.id == selectedWorkspaceID))
                .font(.conductorSystem(size: 13, weight: .bold, scale: fontScale))
                .foregroundStyle(item.id == selectedWorkspaceID ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                .frame(width: 28, height: 28)
                .background(theme.floatingControlFill.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.workspace.title)
                    .font(.conductorSystem(size: 15, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.rootDisplay)
                    .font(.conductorSystem(size: 10.4, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if item.id == selectedWorkspaceID {
                WorkspaceInspectorPill(systemImage: "checkmark", value: L("当前", "Current"), tone: .accent)
            }
        }
    }

    private func inspectorActions(_ item: WorkspaceOverviewItemSnapshot) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                WorkspaceInspectorActionButton(
                    title: item.id == selectedWorkspaceID ? L("已打开", "Current") : L("切到工作区", "Switch"),
                    systemImage: item.id == selectedWorkspaceID ? "checkmark" : "arrow.right",
                    disabled: item.id == selectedWorkspaceID
                ) {
                    openWorkspace(item.id)
                }

                if let server = item.workspaceMetadata?.devServers.first {
                    WorkspaceInspectorActionButton(title: L("打开 :\(server.port)", "Open :\(server.port)"), systemImage: "network") {
                        openFirstLocalService(in: item.id)
                    }
                } else if let port = item.workspaceMetadata?.runningPorts.first {
                    WorkspaceInspectorActionButton(title: L("打开 :\(port)", "Open :\(port)"), systemImage: "network") {
                        openFirstLocalService(in: item.id)
                    }
                }

                if item.workspaceMetadata?.rootPath != nil {
                    WorkspaceInspectorActionButton(title: L("Finder", "Finder"), systemImage: "folder") {
                        openRoot(in: item.id)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openDevServer(_ server: WorkspaceMetadataSnapshot.DevServerSummary, in workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.newWorkspaceWebTab(initialInput: server.url)
    }

    private func openFirstLocalService(in workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.performCommand(.openCurrentWorkspaceFirstService)
    }

    private func openRoot(in workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.performCommand(.openCurrentWorkspaceRoot)
    }

    private func resumeAgents(in workspaceID: WorkspaceID) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(workspaceID, source: .overview)
        }
        model.performCommand(.resumeCurrentWorkspaceAgents)
    }

    private func focusResumableAgent(_ agent: TerminalAgentResumeBatchTarget) {
        ConductorMotion.withoutAnimation {
            model.activateWorkspace(agent.workspaceID, source: .overview)
        }
        _ = model.controlFocusTerminal(agent.terminalID)
    }

    private func resumeAgent(_ agent: TerminalAgentResumeBatchTarget) {
        focusResumableAgent(agent)
        _ = model.controlResumeTerminalAgent(terminalID: agent.terminalID)
    }

    private func copyResumeCommand(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        model.showShellToast(
            title: L("已复制续接命令", "Resume Command Copied"),
            body: command,
            systemImage: "doc.on.doc",
            duration: 3
        )
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return L("\(seconds) 秒前", "\(seconds)s ago")
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return L("\(minutes) 分钟前", "\(minutes)m ago")
        }
        return L("\(minutes / 60) 小时前", "\(minutes / 60)h ago")
    }
}

private struct WorkspaceInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                Rectangle()
                    .fill(theme.floatingSeparator.opacity(0.70))
                    .frame(height: 1)
            }
            VStack(alignment: .leading, spacing: 5) {
                content
            }
        }
    }
}

private struct WorkspaceInspectorFact: View {
    let label: String
    let value: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .frame(width: 14)
            Text(label)
                .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .frame(width: 44, alignment: .leading)
            Text(value)
                .font(.conductorSystem(size: 10.6, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceInspectorResumeAgentLine: View {
    let agent: TerminalAgentResumeBatchTarget
    let focus: () -> Void
    let resume: () -> Void
    let copyCommand: () -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 18, height: 18)
                .background(theme.floatingControlFill.opacity(0.54))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)

            Button(action: focus) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.displayName)
                        .font(.conductorSystem(size: 10.7, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(1)
                    Text(agent.terminalTitle)
                        .font(.conductorSystem(size: 9.4, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .macNativeTooltip(L("定位到这个 Agent 终端", "Focus this agent terminal"))

            HStack(spacing: 4) {
                iconButton(systemImage: "paperplane", tooltip: L("发送续接命令", "Send resume command"), action: resume)
                iconButton(systemImage: "doc.on.doc", tooltip: L("复制续接命令", "Copy resume command"), action: copyCommand)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconButton(systemImage: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .frame(width: 22, height: 22)
                .background(theme.floatingControlFill.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.94, pressedOpacity: 0.88))
        .accessibilityLabel(tooltip)
        .macNativeTooltip(tooltip)
    }
}

private struct WorkspaceInspectorTerminalLine: View {
    let terminal: WorkspaceOverviewTerminalSummary
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: terminal.activeAgentTitle == nil ? "terminal" : "sparkles")
                .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(terminal.activeAgentTitle == nil ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
                .frame(width: 16, height: 16)
                .background(theme.floatingControlFill.opacity(0.46))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(terminal.title)
                    .font(.conductorSystem(size: 10.8, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .lineLimit(1)
                Text(terminal.activeAgentTitle ?? terminal.workingDirectory ?? L("等待目录", "Waiting for directory"))
                    .font(.conductorSystem(size: 9.3, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceInspectorDevServerLine: View {
    let server: WorkspaceMetadataSnapshot.DevServerSummary
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "network")
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .frame(width: 16, height: 16)
                    .background(theme.floatingSelectedFill.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(server.label)
                        .font(.conductorSystem(size: 10.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(server.workingDirectory.map(workspaceInspectorAbbreviatedPath) ?? server.url)
                        .font(.conductorSystem(size: 9.3, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Text(":\(server.port)")
                    .font(.conductorSystem(size: 9.4, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(hovering ? theme.floatingHoverFill.opacity(0.52) : theme.floatingControlFill.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .macNativeTooltip(L("打开 \(server.url)", "Open \(server.url)"))
        .onHover { hovering = $0 }
    }
}

private struct WorkspaceInspectorFileLine: View {
    let file: WorkspaceMetadataSnapshot.FileSummary
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: file.dirty ? "doc.text.fill" : "doc.text")
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, height: 16)
                    .background(iconFill)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(file.title)
                            .font(.conductorSystem(size: 10.8, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if file.dirty {
                            Text(L("未保存", "Unsaved"))
                                .font(.conductorSystem(size: 8.7, weight: .bold, scale: fontScale))
                                .foregroundStyle(theme.usesDarkChrome ? Color.orange.opacity(0.94) : Color.orange.opacity(0.82))
                                .lineLimit(1)
                        }
                    }
                    Text(workspaceInspectorAbbreviatedPath(file.path))
                        .font(.conductorSystem(size: 9.3, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if file.selected {
                    Image(systemName: "checkmark")
                        .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                        .foregroundStyle(theme.floatingEmphasis)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(rowFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .macNativeTooltip(L("打开文件标签", "Open file tab"))
        .onHover { hovering = $0 }
    }

    private var iconColor: Color {
        file.dirty || file.selected ? theme.floatingEmphasis : ConductorDesign.tertiaryText
    }

    private var iconFill: Color {
        file.selected ? theme.floatingSelectedFill.opacity(0.56) : theme.floatingControlFill.opacity(0.46)
    }

    private var rowFill: Color {
        if file.selected {
            return theme.floatingSelectedFill.opacity(0.34)
        }
        return hovering ? theme.floatingHoverFill.opacity(0.52) : theme.floatingControlFill.opacity(0.24)
    }
}

private struct WorkspaceInspectorPill: View {
    let systemImage: String
    let value: String
    let tone: WorkspaceInspectorPillTone
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 8.8, weight: .semibold, scale: fontScale))
                .accessibilityHidden(true)
            Text(value)
                .font(.conductorSystem(size: 9.4, weight: .semibold, scale: fontScale))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 5)
        .frame(height: 17)
        .background(background)
        .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral:
            return ConductorDesign.secondaryText
        case .accent:
            return theme.floatingEmphasis
        case .attention:
            return theme.usesDarkChrome ? Color.orange.opacity(0.94) : Color.orange.opacity(0.82)
        }
    }

    private var background: Color {
        switch tone {
        case .neutral:
            return theme.floatingControlFill.opacity(0.54)
        case .accent:
            return theme.floatingSelectedFill.opacity(0.68)
        case .attention:
            return Color.orange.opacity(theme.usesDarkChrome ? 0.16 : 0.10)
        }
    }
}

private enum WorkspaceInspectorPillTone {
    case neutral
    case accent
    case attention
}

private func workspaceInspectorAbbreviatedPath(_ path: String) -> String {
    let expanded = (path as NSString).expandingTildeInPath
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if expanded == home {
        return "~"
    }
    if expanded.hasPrefix(home + "/") {
        return "~/" + String(expanded.dropFirst(home.count + 1))
    }
    return expanded
}

private struct WorkspaceInspectorEmptyLine: View {
    let text: String
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Text(text)
            .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
            .foregroundStyle(ConductorDesign.tertiaryText)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
}

private struct WorkspaceInspectorWebLine: View {
    let webTab: WorkspaceMetadataSnapshot.WebSummary
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: webTab.loading ? "arrow.triangle.2.circlepath" : "globe")
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(webTab.selected ? theme.floatingEmphasis : ConductorDesign.tertiaryText)
                    .frame(width: 16, height: 16)
                    .background(webTab.selected ? theme.floatingSelectedFill.opacity(0.56) : theme.floatingControlFill.opacity(0.46))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(webTab.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? webTab.title! : webTab.pendingAddress)
                        .font(.conductorSystem(size: 10.8, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(webTab.url ?? webTab.pendingAddress)
                        .font(.conductorSystem(size: 9.3, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                if webTab.selected {
                    Image(systemName: "checkmark")
                        .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                        .foregroundStyle(theme.floatingEmphasis)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(hovering ? theme.floatingHoverFill.opacity(0.52) : theme.floatingControlFill.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .macNativeTooltip(L("打开网页标签", "Open web tab"))
        .onHover { hovering = $0 }
    }
}

private struct WorkspaceInspectorActionButton: View {
    let title: String
    let systemImage: String
    var disabled = false
    let action: () -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        Button(action: {
            guard !disabled else { return }
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .lineLimit(1)
            }
            .foregroundStyle(disabled ? ConductorDesign.tertiaryText : ConductorDesign.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(disabled ? theme.floatingControlFill.opacity(0.28) : theme.floatingControlFill.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.97, pressedOpacity: 0.94))
        .disabled(disabled)
        .accessibilityLabel(title)
        .macNativeTooltip(title)
    }
}

private struct FloatingPanelCursorShield: NSViewRepresentable {
    func makeNSView(context _: Context) -> FloatingPanelCursorShieldView {
        FloatingPanelCursorShieldView()
    }

    func updateNSView(_ view: FloatingPanelCursorShieldView, context _: Context) {
        view.window?.invalidateCursorRects(for: view)
        NSCursor.arrow.set()
    }
}

private final class FloatingPanelCursorShieldView: NSView {
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }
}
