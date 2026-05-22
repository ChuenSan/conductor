import ConductorCore
import AppKit
import QuartzCore
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
    @State private var fileManagerPresentationRequest: FileManagerPanelRequest?
    @State private var fileManagerTrayVisible = false
    @State private var fileManagerAnimationGeneration = 0

    private let fileManagerTargetWidth: CGFloat = 468
    private let fileManagerAnimationDuration: TimeInterval = 0.18

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
                    AppearanceSettingsPanel(
                        model: model,
                        snapshot: SettingsPanelSnapshot(model: model)
                    )
                        .environment(\.conductorTheme, model.theme)
                        .environment(\.conductorFontScale, model.appearance.fontScale)
                        .environment(\.conductorFontFamily, model.appearance.fontFamily)
                        .environment(\.locale, model.appearance.language.locale)
                        .transition(ConductorMotion.settingsPanelTransition)
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
        .onAppear {
            synchronizeFileManagerPresentation(animated: false)
        }
        .onChange(of: model.fileManagerPanelRequest?.id) { _, _ in
            synchronizeFileManagerPresentation(animated: true)
        }
    }

    private var shellContent: some View {
        let workspaceSnapshot = WorkspaceChromeSnapshot(model: model)

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
                    theme: model.theme,
                    appearance: model.appearance
                )
                ZStack(alignment: .trailing) {
                    primaryWorkspaceContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    fileManagerTray
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
            FileManagerCompositorSlideHost(
                visible: fileManagerTrayVisible,
                reducedMotion: model.appearance.reducedMotion,
                duration: fileManagerAnimationDuration
            ) {
                FileManagerPanel(
                    model: model,
                    request: request,
                    searchFocusToken: model.fileManagerSearchFocusGeneration,
                    searchNextToken: model.fileManagerSearchNextGeneration,
                    searchPreviousToken: model.fileManagerSearchPreviousGeneration
                )
            }
            .frame(width: fileManagerTargetWidth)
            .frame(maxHeight: .infinity)
            .clipped()
            .shadow(color: Color.black.opacity(model.theme.usesDarkChrome ? 0.22 : 0.14), radius: 18, x: -8, y: 0)
        }
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
        if model.selectedWorkspaceFileTab != nil {
            ConductorFileWorkspaceView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            terminalStage
        }
    }

    private var terminalStage: some View {
        SplitNodeView(node: model.workspace.visibleRoot, model: model)
            .background(model.theme.terminalBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct FileManagerCompositorSlideHost<Content: View>: NSViewRepresentable {
    let visible: Bool
    let reducedMotion: Bool
    let duration: TimeInterval
    let content: Content

    init(
        visible: Bool,
        reducedMotion: Bool,
        duration: TimeInterval,
        @ViewBuilder content: () -> Content
    ) {
        self.visible = visible
        self.reducedMotion = reducedMotion
        self.duration = duration
        self.content = content()
    }

    func makeNSView(context: Context) -> FileManagerCompositorSlideHostView<Content> {
        FileManagerCompositorSlideHostView(rootView: content)
    }

    func updateNSView(_ nsView: FileManagerCompositorSlideHostView<Content>, context: Context) {
        nsView.update(rootView: content, visible: visible, duration: duration, animated: !reducedMotion)
    }
}

@MainActor
private final class FileManagerCompositorSlideHostView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private var currentVisible: Bool?
    private var lastKnownBoundsSize: CGSize = .zero

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true
        layer?.actions = Self.disabledLayerActions
        canDrawSubviewsIntoLayer = true

        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        hostingView.layer?.masksToBounds = true
        hostingView.layer?.actions = Self.disabledLayerActions
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        super.layout()
        hostingView.frame = bounds
        hostingView.bounds = NSRect(origin: .zero, size: bounds.size)
        let sizeChanged = lastKnownBoundsSize != bounds.size
        lastKnownBoundsSize = bounds.size
        if sizeChanged, let currentVisible {
            applyVisibility(currentVisible, animated: false, duration: 0)
        }
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        currentVisible == true ? super.hitTest(point) : nil
    }

    func update(rootView: Content, visible: Bool, duration: TimeInterval, animated: Bool) {
        hostingView.rootView = rootView
        hostingView.frame = bounds
        hostingView.bounds = NSRect(origin: .zero, size: bounds.size)
        let didChangeVisibility = currentVisible != visible
        currentVisible = visible
        applyVisibility(visible, animated: animated && didChangeVisibility && bounds.width > 1, duration: duration)
    }

    private func applyVisibility(_ visible: Bool, animated: Bool, duration: TimeInterval) {
        guard let layer = hostingView.layer else { return }
        let targetTransform = CATransform3DMakeTranslation(visible ? 0 : max(1, bounds.width), 0, 0)
        if animated {
            let fromTransform = layer.presentation()?.transform ?? layer.transform
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = targetTransform
            CATransaction.commit()

            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: fromTransform)
            animation.toValue = NSValue(caTransform3D: targetTransform)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.86, 0.18, 1.0)
            animation.isRemovedOnCompletion = true
            layer.add(animation, forKey: "conductor.file-manager.compositor-slide")
        } else {
            layer.removeAnimation(forKey: "conductor.file-manager.compositor-slide")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = targetTransform
            CATransaction.commit()
        }
    }

    private static var disabledLayerActions: [String: CAAction] {
        [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "transform": NSNull(),
            "opacity": NSNull(),
            "contentsScale": NSNull(),
            "backgroundColor": NSNull()
        ]
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
    @Namespace private var commandSelectionNamespace
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
                                selectionNamespace: commandSelectionNamespace,
                                action: command.action,
                                onHover: {
                                    if !command.disabled {
                                        selectedCommandID = command.id
                                    }
                                }
                            )
                            .transition(ConductorMotion.rowTransition(itemCount: filteredCommands.count))
                        }
                    }
                    .padding(.vertical, 1)
                    .animation(ConductorMotion.list(itemCount: filteredCommands.count), value: filteredCommandIDs)
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
            CommandPaletteItem(
                id: "new-terminal-current-directory",
                section: L("创建", "Create"),
                title: L("从当前目录新开终端", "New Terminal at Current Directory"),
                shortcut: "Current CWD",
                disabled: !canPerform(.newTerminalAtFocusedDirectory),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "terminal cwd current directory folder"
            ) {
                perform(.newTerminalAtFocusedDirectory)
            },
            CommandPaletteItem(id: "duplicate-tab", section: L("创建", "Create"), title: L("复制当前标签", "Duplicate Current Tab"), shortcut: "Duplicate", keywords: "copy tab duplicate") {
                perform(.duplicateSelectedTab)
            },
            CommandPaletteItem(
                id: "open-current-directory",
                section: L("上下文", "Context"),
                title: L("打开当前目录", "Open Current Directory"),
                shortcut: "Finder",
                disabled: !canPerform(.openFocusedDirectory),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "open reveal finder cwd folder directory"
            ) {
                perform(.openFocusedDirectory)
            },
            CommandPaletteItem(
                id: "copy-current-directory",
                section: L("上下文", "Context"),
                title: L("复制当前目录路径", "Copy Current Directory Path"),
                shortcut: "Copy",
                disabled: !canPerform(.copyFocusedDirectory),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "copy path cwd folder directory"
            ) {
                perform(.copyFocusedDirectory)
            },
            CommandPaletteItem(
                id: "file-manager",
                section: L("上下文", "Context"),
                title: L("文件管理器", "File Manager"),
                shortcut: "Files",
                disabled: !canPerform(.toggleFileManager),
                disabledReason: L("当前终端还没有可用目录", "Current terminal has no available directory"),
                keywords: "file files browser manager cwd folder directory preview"
            ) {
                perform(.toggleFileManager)
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

private struct SettingsPanelSnapshot: Equatable {
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let agentHookSettingsMessage: String?
    let agentCLIStatuses: [AgentHookProvider: AgentCLIStatus]
    let terminalFontDownloadStates: [TerminalFontPreset: TerminalFontDownloadState]

    @MainActor
    init(model: ConductorWindowModel) {
        self.theme = model.theme
        self.appearance = model.appearance
        self.agentHookSettingsMessage = model.agentHookSettingsMessage
        self.agentCLIStatuses = model.agentCLIStatuses
        self.terminalFontDownloadStates = model.terminalFontDownloadStates
    }
}

private struct AppearanceSettingsPanel: View {
    let model: ConductorWindowModel
    let snapshot: SettingsPanelSnapshot
    @State private var selectedSection: SettingsPanelSection = .overview
    @State private var selectedTerminalSettingsSection: TerminalSettingsSection = .typography
    @Namespace private var settingsSelectionNamespace
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        ZStack {
            ConductorGlassSurface(style: .panel, clarity: snapshot.appearance.chromeClarity, interactive: true) {
                VStack(spacing: 0) {
                    FloatingPanelHeader(
                        systemImage: "gearshape",
                        title: L("设置", "Settings"),
                        subtitle: snapshot.theme.title,
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
            .frame(width: 900, height: 610)
            .onExitCommand {
                model.hideSettingsPanel()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSidebarSummary(theme: snapshot.theme, appearance: snapshot.appearance)

            sidebarGroup(
                title: L("常用", "General"),
                sections: [.overview, .interface, .terminal]
            )

            sidebarGroup(
                title: L("工作流", "Workflow"),
                sections: [.shell, .automation, .commands]
            )

            sidebarGroup(
                title: L("外观", "Look"),
                sections: [.themes]
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(theme.floatingControlFill.opacity(0.18))
    }

    private func sidebarGroup(title: String, sections: [SettingsPanelSection]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SidebarSectionTitle(title)

            VStack(spacing: 3) {
                ForEach(sections) { section in
                    SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section,
                        selectionNamespace: settingsSelectionNamespace
                    ) {
                        selectSection(section)
                    }
                }
            }
        }
    }

    private var contentPane: some View {
        ZStack {
            theme.floatingControlFill.opacity(0.06)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    detailContent
                }
                .frame(maxWidth: 660, alignment: .topLeading)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailContent: some View {
        SettingsPaneHeading(section: selectedSection)

        switch selectedSection {
        case .overview:
            overviewSettings
        case .interface:
            interfaceSettings
        case .terminal:
            terminalSettingsDashboard
        case .shell:
            shellAndProxySettings
        case .automation:
            automationSettings
        case .commands:
            commandSettings
        case .themes:
            themeSettings
        }
    }

    private func selectSection(_ section: SettingsPanelSection) {
        guard selectedSection != section else { return }
        ConductorMotion.withoutAnimation {
            selectedSection = section
        }
    }

    private var overviewSettings: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("当前状态", "Current State"),
                subtitle: L("主题、终端字体、密度和工作流开关", "Theme, terminal font, density, and workflow toggles"),
                systemImage: "rectangle.grid.2x2"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsOverviewGrid(snapshot: snapshot)

                    VStack(spacing: 0) {
                        SettingsQuickJumpButton(
                            title: L("调整终端", "Tune Terminal"),
                            subtitle: snapshot.appearance.terminalRenderer.selectedFontStatusTitle,
                            systemImage: "terminal"
                        ) {
                            selectSection(.terminal)
                        }

                        SettingsControlDivider()

                        SettingsQuickJumpButton(
                            title: L("换主题", "Change Theme"),
                            subtitle: snapshot.theme.title,
                            systemImage: "swatchpalette"
                        ) {
                            selectSection(.themes)
                        }
                    }
                    .background(theme.floatingControlFill.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var interfaceSettings: some View {
        let appearance = snapshot.appearance
        return LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("外观控制", "Appearance Controls"),
                subtitle: L("像系统偏好设置一样直接调整，不用在卡片海里找选项", "Direct controls, tuned like a native settings inspector"),
                systemImage: "slider.horizontal.3"
            ) {
                SettingsFormSurface {
                    SettingsControlRow(
                        title: L("窗口密度", "Window Density"),
                        subtitle: appearance.density.subtitle,
                        systemImage: "rectangle.compress.vertical"
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceDensity.allCases,
                            selection: appearance.density,
                            title: { $0.title }
                        ) { density in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setAppearanceDensity(density)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("浮层清晰度", "Layer Clarity"),
                        subtitle: appearance.chromeClarity.subtitle,
                        systemImage: "square.stack.3d.up"
                    ) {
                        SettingsSegmentedPicker(
                            options: ChromeClarity.allCases,
                            selection: appearance.chromeClarity,
                            title: { $0.title }
                        ) { clarity in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setChromeClarity(clarity)
                            }
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("文字", "Text"),
                subtitle: L("这些只影响应用壳层文字，不会触碰终端渲染", "Shell text only; terminal rendering stays separate"),
                systemImage: "textformat"
            ) {
                SettingsFormSurface {
                    SettingsControlRow(
                        title: L("语言", "Language"),
                        subtitle: appearance.language.subtitle,
                        systemImage: "character.bubble"
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceLanguage.allCases,
                            selection: appearance.language,
                            title: { $0.title }
                        ) { language in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setLanguage(language)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("字体", "Font"),
                        subtitle: appearance.fontFamily.subtitle,
                        systemImage: appearance.fontFamily.systemImage
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceFontFamily.allCases,
                            selection: appearance.fontFamily,
                            title: { $0.title }
                        ) { family in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setFontFamily(family)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("字号", "Font Size"),
                        subtitle: appearance.fontScale.subtitle,
                        systemImage: "textformat.size"
                    ) {
                        SettingsSegmentedPicker(
                            options: AppearanceFontScale.allCases,
                            selection: appearance.fontScale,
                            title: { $0.title }
                        ) { scale in
                            model.performShellMotion(ConductorMotion.selection) {
                                model.setFontScale(scale)
                            }
                        }
                    }
                }
            }

        }
    }

    private var terminalSettingsDashboard: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            terminalSettingsSectionRail

            activeTerminalSettingsSection
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var terminalSettingsSectionRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            TerminalSettingsSectionRail(
                selection: selectedTerminalSettingsSection
            ) { section in
                ConductorMotion.withoutAnimation {
                    selectedTerminalSettingsSection = section
                }
            }

            SettingsSectionLabel(
                title: selectedTerminalSettingsSection.title,
                subtitle: selectedTerminalSettingsSection.subtitle
            )
        }
    }

    @ViewBuilder
    private var activeTerminalSettingsSection: some View {
        switch selectedTerminalSettingsSection {
        case .typography:
            terminalTypographySettings
        case .display:
            terminalCursorSettings
            terminalBackgroundSettings
        case .selection:
            terminalSelectionMouseSettings
        case .input:
            terminalClipboardSettings
            terminalKeyboardSettings
        }
    }

    private var shellAndProxySettings: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            terminalShellSettings

            SettingsSectionLabel(
                title: L("网络环境", "Network Environment"),
                subtitle: L("写入新终端进程的代理变量，和 Shell 启动项属于同一条启动路径", "Proxy variables for new terminal processes live with startup behavior")
            )

            proxySettings
        }
    }

    private var automationSettings: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            aiSettings

            SettingsSectionLabel(
                title: L("终端提醒", "Terminal Alerts"),
                subtitle: L("命令完成通知和铃声是工作流反馈，不再散落在终端视觉设置里", "Command finish alerts and bell feedback belong with workflow feedback")
            )

            terminalNotificationSettings
        }
    }

    @ViewBuilder
    private var terminalShellSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let commandOverride = renderer.ghosttyOverride(for: "initial-command")
        let directoryOverride = renderer.ghosttyOverride(for: "working-directory")
        let scrollbackOverride = renderer.ghosttyOverride(for: "scrollback-limit")

        SettingsPreferenceGroup(
            title: L("Shell 与启动", "Shell and Startup"),
            subtitle: L("启动命令、默认目录和滚屏历史，按终端用户真正会设置的方式呈现", "Startup command, default directory, and scrollback history presented as product settings"),
            systemImage: "terminal"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("Shell 集成", "Shell Integration"),
                    subtitle: L("已启用 detect，并保留 no-cursor；这里不需要手动配置", "Enabled with detect and no-cursor; no manual setup needed"),
                    systemImage: "point.3.connected.trianglepath.dotted"
                ) {
                    SettingsStatusPill(title: L("自动管理", "Managed"), systemImage: "lock.fill")
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("启动命令", "Startup Command"),
                    subtitle: L("留空时打开默认登录 shell；适合进入 tmux、ssh 或固定开发环境", "Leave empty for the default login shell; useful for tmux, ssh, or a fixed dev environment"),
                    systemImage: "terminal"
                ) {
                    ShellCommandSettingControl(
                        value: commandOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "initial-command", value: $0) },
                        reset: { resetGhosttyOverride(key: "initial-command") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("默认工作目录", "Default Working Directory"),
                    subtitle: L("留空时继承工作区或新建终端时的目录", "Leave empty to inherit the workspace or new-terminal directory"),
                    systemImage: "folder"
                ) {
                    WorkingDirectorySettingControl(
                        value: directoryOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "working-directory", value: $0) },
                        reset: { resetGhosttyOverride(key: "working-directory") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("滚屏历史", "Scrollback History"),
                    subtitle: L("控制终端保留多少历史输出；越大越占内存", "Controls how much terminal history is retained; larger values use more memory"),
                    systemImage: "scroll"
                ) {
                    ScrollbackPresetPicker(
                        value: scrollbackOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "scrollback-limit", value: $0) },
                        reset: { resetGhosttyOverride(key: "scrollback-limit") }
                    )
                }
            }
        }
    }

    private var terminalBackgroundSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let blurOverride = renderer.ghosttyOverride(for: "background-blur")
        let imageOverride = renderer.ghosttyOverride(for: "background-image")
        let imageOpacityOverride = renderer.ghosttyOverride(for: "background-image-opacity")
        let imageFitOverride = renderer.ghosttyOverride(for: "background-image-fit")
        let selectionForegroundOverride = renderer.ghosttyOverride(for: "selection-foreground")
        let selectionBackgroundOverride = renderer.ghosttyOverride(for: "selection-background")
        let searchBackgroundOverride = renderer.ghosttyOverride(for: "search-background")

        return SettingsPreferenceGroup(
            title: L("背景与颜色", "Background and Colors"),
            subtitle: L("终端画布、背景图、选区和搜索高亮；整套主题仍在主题页管理", "Terminal canvas, background image, selection, and search highlight; full themes stay in Themes"),
            systemImage: "paintpalette"
        ) {
            SettingsFormSurface {
                SettingsSliderRow(
                    title: L("背景不透明度", "Background Opacity"),
                    subtitle: L("降低后可以透出窗口材质，100% 最清晰", "Lower values show the window material; 100% is clearest"),
                    systemImage: "circle.lefthalf.filled",
                    value: renderer.backgroundOpacity,
                    range: 0.35...1,
                    step: 0.01,
                    valueText: percentText(renderer.backgroundOpacity)
                ) { opacity in
                    model.setTerminalBackgroundOpacity(opacity)
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("背景模糊", "Background Blur"),
                    subtitle: L("透明背景下柔化后方内容，默认跟随内置策略", "Softens content behind transparent terminals; default follows the built-in policy"),
                    systemImage: "water.waves"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: blurOverride),
                        action: { setBooleanOverride(key: "background-blur", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("背景图片", "Background Image"),
                    subtitle: L("选择一张图片作为终端背景，留空时使用主题背景", "Choose an image for the terminal background, or leave empty to use the theme"),
                    systemImage: "photo"
                ) {
                    GhosttyFileOverrideControl(
                        key: "background-image",
                        value: imageOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "background-image", value: $0) },
                        reset: { resetGhosttyOverride(key: "background-image") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("图片显示方式", "Image Fit"),
                    subtitle: L("控制背景图片如何填充终端区域", "Controls how the background image fills the terminal area"),
                    systemImage: "rectangle.resize"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: imageFitOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("完整显示", "Contain"), value: "contain"),
                            GhosttyPresetOption(title: L("填满裁切", "Cover"), value: "cover"),
                            GhosttyPresetOption(title: L("拉伸", "Stretch"), value: "stretch"),
                            GhosttyPresetOption(title: L("原始大小", "Original"), value: "none")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "background-image-fit", value: $0) },
                        reset: { resetGhosttyOverride(key: "background-image-fit") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("图片透明度", "Image Opacity"),
                    subtitle: L("让背景图片更轻，避免干扰终端文字", "Makes the image quieter so terminal text stays readable"),
                    systemImage: "slider.horizontal.3"
                ) {
                    GhosttySliderOverrideControl(
                        key: "background-image-opacity",
                        value: imageOpacityOverride.normalizedValue,
                        range: 0...1,
                        step: 0.01,
                        defaultValue: 1,
                        valueText: { "\(Int(($0 * 100).rounded()))%" },
                        setValue: { setGhosttyOverrideValue(key: "background-image-opacity", value: String(format: "%.2f", Double($0))) },
                        reset: { resetGhosttyOverride(key: "background-image-opacity") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("选区文字", "Selection Text"),
                    subtitle: L("选中内容时的文字颜色，默认跟随主题", "Text color for selected content; defaults to the theme"),
                    systemImage: "text.cursor"
                ) {
                    GhosttyColorOverrideControl(
                        key: "selection-foreground",
                        value: selectionForegroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "selection-foreground", value: $0) },
                        reset: { resetGhosttyOverride(key: "selection-foreground") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("选区背景", "Selection Background"),
                    subtitle: L("拖选文本时的高亮颜色", "Highlight color used while selecting text"),
                    systemImage: "selection.pin.in.out"
                ) {
                    GhosttyColorOverrideControl(
                        key: "selection-background",
                        value: selectionBackgroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "selection-background", value: $0) },
                        reset: { resetGhosttyOverride(key: "selection-background") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("搜索高亮", "Search Highlight"),
                    subtitle: L("搜索命中结果的背景色", "Background color for search matches"),
                    systemImage: "magnifyingglass"
                ) {
                    GhosttyColorOverrideControl(
                        key: "search-background",
                        value: searchBackgroundOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "search-background", value: $0) },
                        reset: { resetGhosttyOverride(key: "search-background") }
                    )
                }
            }
        }
    }

    private var terminalSelectionMouseSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let clearTypingOverride = renderer.ghosttyOverride(for: "selection-clear-on-typing")
        let clearCopyOverride = renderer.ghosttyOverride(for: "selection-clear-on-copy")
        let copyOverride = renderer.ghosttyOverride(for: "copy-on-select")
        let hideMouseOverride = renderer.ghosttyOverride(for: "mouse-hide-while-typing")
        let reportingOverride = renderer.ghosttyOverride(for: "mouse-reporting")
        let scrollOverride = renderer.ghosttyOverride(for: "mouse-scroll-multiplier")
        let linkOverride = renderer.ghosttyOverride(for: "link-url")
        let previewOverride = renderer.ghosttyOverride(for: "link-previews")

        return SettingsPreferenceGroup(
            title: L("选择、鼠标与链接", "Selection, Mouse, and Links"),
            subtitle: L("日常复制、鼠标交互和链接识别，不展示底层配置细节", "Daily copy, mouse interaction, and link detection without raw config details"),
            systemImage: "cursorarrow.click"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("输入时清除选区", "Clear Selection While Typing"),
                    subtitle: L("开始输入后自动取消当前选区", "Automatically clears the current selection when typing starts"),
                    systemImage: "keyboard"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clearTypingOverride),
                        action: { setBooleanOverride(key: "selection-clear-on-typing", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("复制后清除选区", "Clear Selection After Copy"),
                    subtitle: L("复制完成后收起高亮，适合连续操作", "Clears the highlight after copying"),
                    systemImage: "doc.on.doc"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clearCopyOverride),
                        action: { setBooleanOverride(key: "selection-clear-on-copy", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("选中即复制", "Copy On Select"),
                    subtitle: L("像 X11 终端一样，选中文本后立即写入剪贴板", "Copies selected text immediately, similar to X11 terminals"),
                    systemImage: "doc.on.clipboard"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: copyOverride),
                        action: { setBooleanOverride(key: "copy-on-select", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("输入时隐藏鼠标", "Hide Mouse While Typing"),
                    subtitle: L("减少鼠标指针挡住终端文本的情况", "Keeps the pointer from covering terminal text while typing"),
                    systemImage: "cursorarrow.slash"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: hideMouseOverride),
                        action: { setBooleanOverride(key: "mouse-hide-while-typing", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("应用鼠标上报", "App Mouse Reporting"),
                    subtitle: L("允许 vim、tmux、less 等终端应用接收鼠标事件", "Lets terminal apps such as vim, tmux, and less receive mouse events"),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: reportingOverride),
                        action: { setBooleanOverride(key: "mouse-reporting", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("滚轮速度", "Scroll Speed"),
                    subtitle: L("调整鼠标或触控板滚动终端历史的速度", "Adjusts mouse or trackpad scroll speed through terminal history"),
                    systemImage: "scroll"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: scrollOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("较慢", "Slower"), value: "0.5"),
                            GhosttyPresetOption(title: L("标准", "Standard"), value: "1"),
                            GhosttyPresetOption(title: L("较快", "Faster"), value: "2"),
                            GhosttyPresetOption(title: L("很快", "Fast"), value: "3")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "mouse-scroll-multiplier", value: $0) },
                        reset: { resetGhosttyOverride(key: "mouse-scroll-multiplier") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("链接识别", "Link Detection"),
                    subtitle: L("识别终端输出里的 URL，方便点击打开", "Detects URLs in terminal output so they can be opened"),
                    systemImage: "link"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: linkOverride),
                        action: { setBooleanOverride(key: "link-url", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("链接预览", "Link Previews"),
                    subtitle: L("悬停链接时显示预览能力，默认跟随内置支持", "Shows link preview behavior on hover when supported"),
                    systemImage: "rectangle.on.rectangle"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: previewOverride),
                        action: { setBooleanOverride(key: "link-previews", state: $0) }
                    )
                }
            }
        }
    }

    private var terminalClipboardSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let readOverride = renderer.ghosttyOverride(for: "clipboard-read")
        let writeOverride = renderer.ghosttyOverride(for: "clipboard-write")
        let trimOverride = renderer.ghosttyOverride(for: "clipboard-trim-trailing-spaces")
        let protectionOverride = renderer.ghosttyOverride(for: "clipboard-paste-protection")
        let bracketedOverride = renderer.ghosttyOverride(for: "clipboard-paste-bracketed-safe")

        return SettingsPreferenceGroup(
            title: L("剪贴板与粘贴安全", "Clipboard and Paste Safety"),
            subtitle: L("把安全相关行为说成人话：读写、清理空格、粘贴保护", "Human-facing controls for clipboard access, trimming, and paste protection"),
            systemImage: "doc.on.clipboard"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("允许读取剪贴板", "Allow Clipboard Read"),
                    subtitle: L("终端应用可以从系统剪贴板读取内容", "Terminal apps may read from the system clipboard"),
                    systemImage: "arrow.down.doc"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: readOverride),
                        action: { setBooleanOverride(key: "clipboard-read", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("允许写入剪贴板", "Allow Clipboard Write"),
                    subtitle: L("终端应用可以把内容写入系统剪贴板", "Terminal apps may write to the system clipboard"),
                    systemImage: "arrow.up.doc"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: writeOverride),
                        action: { setBooleanOverride(key: "clipboard-write", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("复制时清理尾随空格", "Trim Trailing Spaces"),
                    subtitle: L("复制多行输出时去掉行尾多余空格", "Removes extra spaces at line endings when copying output"),
                    systemImage: "text.alignleft"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: trimOverride),
                        action: { setBooleanOverride(key: "clipboard-trim-trailing-spaces", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("危险粘贴保护", "Paste Protection"),
                    subtitle: L("粘贴疑似多行命令或危险内容时保留确认保护", "Keeps confirmation protection for suspicious multi-line or risky pastes"),
                    systemImage: "exclamationmark.shield"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: protectionOverride),
                        action: { setBooleanOverride(key: "clipboard-paste-protection", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("Bracketed Paste 安全模式", "Bracketed Paste Safety"),
                    subtitle: L("让支持的 shell 和编辑器更准确地区分键入与粘贴", "Helps supported shells and editors distinguish typed input from pasted text"),
                    systemImage: "brackets.curly"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: bracketedOverride),
                        action: { setBooleanOverride(key: "clipboard-paste-bracketed-safe", state: $0) }
                    )
                }
            }
        }
    }

    private var terminalNotificationSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let finishOverride = renderer.ghosttyOverride(for: "notify-on-command-finish")
        let actionOverride = renderer.ghosttyOverride(for: "notify-on-command-finish-action")
        let afterOverride = renderer.ghosttyOverride(for: "notify-on-command-finish-after")
        let bellPathOverride = renderer.ghosttyOverride(for: "bell-audio-path")
        let bellVolumeOverride = renderer.ghosttyOverride(for: "bell-audio-volume")

        return SettingsPreferenceGroup(
            title: L("通知与铃声", "Notifications and Bell"),
            subtitle: L("命令结束提醒和终端铃声；AI Agent 通知仍在 AI 页管理", "Command-finish alerts and terminal bell; AI agent notifications stay in AI"),
            systemImage: "bell.badge"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("命令完成通知", "Command Finish Notification"),
                    subtitle: L("长命令结束后提醒你回来处理", "Alerts you when a long-running command finishes"),
                    systemImage: "checkmark.circle"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: finishOverride),
                        action: { setBooleanOverride(key: "notify-on-command-finish", state: $0) }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("通知方式", "Notification Action"),
                    subtitle: L("选择只发系统通知，还是同时吸引注意", "Choose whether to only notify or also request attention"),
                    systemImage: "app.badge"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: actionOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("系统通知", "Notification"), value: "notify"),
                            GhosttyPresetOption(title: L("请求注意", "Request Attention"), value: "attention"),
                            GhosttyPresetOption(title: L("通知并请求注意", "Notify and Attention"), value: "notify,attention")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "notify-on-command-finish-action", value: $0) },
                        reset: { resetGhosttyOverride(key: "notify-on-command-finish-action") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("超过多久提醒", "Notify After"),
                    subtitle: L("只有运行时间超过这个阈值的命令才提醒", "Only commands longer than this threshold will alert"),
                    systemImage: "timer"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: afterOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("5 秒", "5 seconds"), value: "5s"),
                            GhosttyPresetOption(title: L("10 秒", "10 seconds"), value: "10s"),
                            GhosttyPresetOption(title: L("30 秒", "30 seconds"), value: "30s"),
                            GhosttyPresetOption(title: L("1 分钟", "1 minute"), value: "1m")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "notify-on-command-finish-after", value: $0) },
                        reset: { resetGhosttyOverride(key: "notify-on-command-finish-after") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("铃声音频", "Bell Sound"),
                    subtitle: L("选择自定义铃声文件，留空时使用默认反馈", "Choose a custom bell sound file, or leave empty for the default feedback"),
                    systemImage: "speaker.wave.2"
                ) {
                    GhosttyFileOverrideControl(
                        key: "bell-audio-path",
                        value: bellPathOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "bell-audio-path", value: $0) },
                        reset: { resetGhosttyOverride(key: "bell-audio-path") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("铃声音量", "Bell Volume"),
                    subtitle: L("调低可以保留提示但不打断工作", "Lower volume keeps feedback without interrupting work"),
                    systemImage: "speaker.wave.1"
                ) {
                    GhosttySliderOverrideControl(
                        key: "bell-audio-volume",
                        value: bellVolumeOverride.normalizedValue,
                        range: 0...1,
                        step: 0.01,
                        defaultValue: 1,
                        valueText: { "\(Int(($0 * 100).rounded()))%" },
                        setValue: { setGhosttyOverrideValue(key: "bell-audio-volume", value: String(format: "%.2f", Double($0))) },
                        reset: { resetGhosttyOverride(key: "bell-audio-volume") }
                    )
                }
            }
        }
    }

    private var terminalKeyboardSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let optionOverride = renderer.ghosttyOverride(for: "macos-option-as-alt")
        let remapOverride = renderer.ghosttyOverride(for: "key-remap")

        return SettingsPreferenceGroup(
            title: L("键盘", "Keyboard"),
            subtitle: L("这里放终端输入层设置；应用级快捷键仍在命令页管理", "Terminal input settings live here; app shortcuts stay in Commands"),
            systemImage: "keyboard"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("Option 作为 Alt", "Option As Alt"),
                    subtitle: L("给 vim、emacs、tmux 等终端程序发送 Alt/Meta 组合键", "Sends Alt/Meta key combinations to terminal apps such as vim, emacs, and tmux"),
                    systemImage: "option"
                ) {
                    GhosttyPresetOverrideMenu(
                        value: optionOverride.normalizedValue,
                        options: [
                            GhosttyPresetOption(title: L("关闭", "Off"), value: "false"),
                            GhosttyPresetOption(title: L("左 Option", "Left Option"), value: "left"),
                            GhosttyPresetOption(title: L("右 Option", "Right Option"), value: "right"),
                            GhosttyPresetOption(title: L("左右都启用", "Both Options"), value: "true")
                        ],
                        setValue: { setGhosttyOverrideValue(key: "macos-option-as-alt", value: $0) },
                        reset: { resetGhosttyOverride(key: "macos-option-as-alt") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("高级键位映射", "Advanced Key Remap"),
                    subtitle: L("只在需要兼容特殊终端工作流时填写；常用快捷键请去命令页", "Use only for special terminal workflows; common shortcuts belong in Commands"),
                    systemImage: "keyboard.badge.ellipsis"
                ) {
                    GhosttyInlineTextOverrideControl(
                        key: "key-remap",
                        placeholder: "ctrl+a=home",
                        value: remapOverride.normalizedValue,
                        systemImage: "keyboard",
                        setValue: { setGhosttyOverrideValue(key: "key-remap", value: $0) },
                        reset: { resetGhosttyOverride(key: "key-remap") }
                    )
                }
            }
        }
    }

    private var terminalTypographySettings: some View {
        let appearance = snapshot.appearance
        let renderer = appearance.terminalRenderer
        let downloadStates = snapshot.terminalFontDownloadStates
        return VStack(alignment: .leading, spacing: 16) {
            TerminalRendererSummary(appearance: appearance)

            SettingsPreferenceGroup(
                title: L("字体与字格", "Typography"),
                subtitle: L("管理终端实际使用的字体、字号、行高和字格密度", "Controls the terminal font, size, line height, and cell density"),
                systemImage: "textformat.size"
            ) {
                SettingsFormSurface {
                    SettingsControlRow(
                        title: L("终端字体", "Terminal Font"),
                        subtitle: renderer.selectedFontStatusTitle,
                        systemImage: "textformat"
                    ) {
                        HStack(spacing: 8) {
                            TerminalFontPickerMenu(
                                selection: renderer.fontPreset,
                                downloadStates: downloadStates,
                                action: { preset in
                                    model.performShellMotion(ConductorMotion.selection) {
                                        model.setTerminalFontPreset(preset)
                                    }
                                },
                                download: { preset in
                                    model.downloadTerminalFont(preset)
                                }
                            )

                            let selectedChoice = TerminalFontLibrary.choices.first { $0.preset == renderer.fontPreset }
                            if let selectedChoice, !selectedChoice.isInstalled, selectedChoice.canDownload {
                                Button {
                                    model.downloadTerminalFont(selectedChoice.preset)
                                } label: {
                                    if downloadStates[selectedChoice.preset]?.isDownloading == true {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Label(
                                            selectedChoice.preset.directDownloadURL == nil ? L("获取", "Get") : L("下载", "Download"),
                                            systemImage: selectedChoice.preset.directDownloadURL == nil ? "safari" : "arrow.down.circle"
                                        )
                                        .labelStyle(.titleAndIcon)
                                    }
                                }
                                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                                .disabled(downloadStates[selectedChoice.preset]?.isDownloading == true)
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsControlRow(
                        title: L("自定义字体", "Custom Font"),
                        subtitle: customTerminalFontSubtitle(for: appearance),
                        systemImage: "square.and.arrow.down"
                    ) {
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { renderer.useCustomFont },
                                set: { model.setTerminalUseCustomFont($0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(renderer.customFontFamilyName == nil)

                            Button(L("导入", "Import")) {
                                model.importTerminalFont()
                            }
                        }
                    }

                    SettingsControlDivider()

                    SettingsSliderRow(
                        title: L("终端字号", "Terminal Font Size"),
                        subtitle: L("调大更清晰，调小能显示更多行列", "Larger is easier to read; smaller fits more rows and columns"),
                        systemImage: "textformat.size",
                        value: appearance.terminalFontSize,
                        range: AppearancePreferences.minTerminalFontSize...AppearancePreferences.maxTerminalFontSize,
                        step: 0.5,
                        valueText: terminalFontSizeText(appearance.terminalFontSize)
                    ) { fontSize in
                        model.setTerminalFontSize(fontSize)
                    }

                    SettingsControlDivider()

                    SettingsSliderRow(
                        title: L("行高", "Line Height"),
                        subtitle: L("让输出更紧凑或更舒展", "Makes terminal output tighter or more relaxed"),
                        systemImage: "arrow.up.and.down.text.horizontal",
                        value: renderer.lineHeight,
                        range: 0.80...1.50,
                        step: 0.01,
                        valueText: multiplierText(renderer.lineHeight)
                    ) { lineHeight in
                        model.setTerminalLineHeight(lineHeight)
                    }
                }
            }
        }
    }

    private var terminalCursorSettings: some View {
        let renderer = snapshot.appearance.terminalRenderer
        let colorOverride = renderer.ghosttyOverride(for: "cursor-color")
        let opacityOverride = renderer.ghosttyOverride(for: "cursor-opacity")
        let textOverride = renderer.ghosttyOverride(for: "cursor-text")
        let clickOverride = renderer.ghosttyOverride(for: "cursor-click-to-move")

        return SettingsPreferenceGroup(
            title: L("光标", "Cursor"),
            subtitle: L("光标形状、颜色、闪烁和点击移动，都是日常输入会感知到的项", "Cursor shape, color, blink, and click-to-move are visible during daily typing"),
            systemImage: "cursorarrow"
        ) {
            SettingsFormSurface {
                SettingsControlRow(
                    title: L("光标样式", "Cursor Style"),
                    subtitle: L("选择块、空心块、竖线或下划线光标", "Choose block, hollow block, bar, or underline"),
                    systemImage: "cursorarrow"
                    ) {
                        SettingsSegmentedPicker(
                            options: TerminalCursorStyle.allCases,
                            selection: renderer.cursorStyle,
                            title: { $0.title }
                        ) { style in
                            model.setTerminalCursorStyle(style)
                    }
                }

                SettingsControlDivider()

                SettingsToggleRow(
                    title: L("光标闪烁", "Cursor Blink"),
                    subtitle: L("关闭后光标保持常亮，适合减少视觉干扰", "Keeps the cursor steady when disabled"),
                    systemImage: "cursorarrow.motionlines",
                    isOn: Binding(
                        get: { renderer.cursorBlink },
                        set: { model.setTerminalCursorBlink($0) }
                    )
                )

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("光标颜色", "Cursor Color"),
                    subtitle: L("默认跟随主题，也可以指定一个固定颜色", "Follows the theme by default, or use a fixed color"),
                    systemImage: "paintpalette"
                ) {
                    GhosttyColorOverrideControl(
                        key: "cursor-color",
                        value: colorOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "cursor-color", value: $0) },
                        reset: { resetGhosttyOverride(key: "cursor-color") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("光标透明度", "Cursor Opacity"),
                    subtitle: L("降低后光标更轻，保持 100% 最醒目", "Lower values make the cursor quieter; 100% is most visible"),
                    systemImage: "slider.horizontal.3"
                ) {
                    GhosttySliderOverrideControl(
                        key: "cursor-opacity",
                        value: opacityOverride.normalizedValue,
                        range: 0.15...1,
                        step: 0.01,
                        defaultValue: 1,
                        valueText: { "\(Int(($0 * 100).rounded()))%" },
                        setValue: { setGhosttyOverrideValue(key: "cursor-opacity", value: String(format: "%.2f", Double($0))) },
                        reset: { resetGhosttyOverride(key: "cursor-opacity") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("光标内文字颜色", "Cursor Text Color"),
                    subtitle: L("光标覆盖字符时使用的文字颜色", "Text color used when the cursor covers a character"),
                    systemImage: "character.cursor.ibeam"
                ) {
                    GhosttyColorOverrideControl(
                        key: "cursor-text",
                        value: textOverride.normalizedValue,
                        setValue: { setGhosttyOverrideValue(key: "cursor-text", value: $0) },
                        reset: { resetGhosttyOverride(key: "cursor-text") }
                    )
                }

                SettingsControlDivider()

                SettingsControlRow(
                    title: L("点击移动光标", "Click To Move Cursor"),
                    subtitle: L("允许鼠标点击把光标移动到目标位置", "Allows mouse clicks to move the cursor position"),
                    systemImage: "cursorarrow.click"
                ) {
                    GhosttyBooleanOverridePicker(
                        state: booleanState(for: clickOverride),
                        action: { setBooleanOverride(key: "cursor-click-to-move", state: $0) }
                    )
                }
            }
        }
    }

    private func setGhosttyOverrideValue(key: String, value: String) {
        model.setGhosttyOverrideValue(key: key, value: value)
        model.setGhosttyOverrideEnabled(key: key, enabled: !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func resetGhosttyOverride(key: String) {
        model.setGhosttyOverrideEnabled(key: key, enabled: false)
    }

    private func booleanState(for override: TerminalGhosttyConfigOverride) -> GhosttyBooleanOverrideState {
        guard override.enabled else { return .defaultValue }
        return override.normalizedValue.lowercased() == "false" ? .off : .on
    }

    private func setBooleanOverride(key: String, state: GhosttyBooleanOverrideState) {
        switch state {
        case .defaultValue:
            resetGhosttyOverride(key: key)
        case .on:
            setGhosttyOverrideValue(key: key, value: "true")
        case .off:
            setGhosttyOverrideValue(key: key, value: "false")
        }
    }

    private var proxySettings: some View {
        let proxy = snapshot.appearance.terminalRenderer.proxy
        return VStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("终端代理", "Terminal Proxy"),
                subtitle: proxy.statusTitle,
                systemImage: "network"
            ) {
                SettingsFormSurface {
                    SettingsToggleRow(
                        title: L("启用代理", "Enable Proxy"),
                        subtitle: L("写入新终端进程的 HTTP(S)/ALL_PROXY 环境变量", "Writes HTTP(S)/ALL_PROXY env vars for new terminal processes"),
                        systemImage: "switch.2",
                        isOn: Binding(
                            get: { proxy.enabled },
                            set: { model.setTerminalProxyEnabled($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "HTTP_PROXY",
                        subtitle: "http://127.0.0.1:7890",
                        systemImage: "globe",
                        text: Binding(
                            get: { proxy.httpProxy },
                            set: { model.setTerminalProxyHTTP($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "HTTPS_PROXY",
                        subtitle: "http://127.0.0.1:7890",
                        systemImage: "lock.globe",
                        text: Binding(
                            get: { proxy.httpsProxy },
                            set: { model.setTerminalProxyHTTPS($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "ALL_PROXY",
                        subtitle: "socks5://127.0.0.1:7890",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        text: Binding(
                            get: { proxy.allProxy },
                            set: { model.setTerminalProxyAll($0) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsTextFieldRow(
                        title: "NO_PROXY",
                        subtitle: "localhost,127.0.0.1,::1",
                        systemImage: "nosign",
                        text: Binding(
                            get: { proxy.noProxy },
                            set: { model.setTerminalProxyNoProxy($0) }
                        )
                    )
                }
            }
        }
    }

    private var aiSettings: some View {
        let appearance = snapshot.appearance
        let agentCLIStatuses = snapshot.agentCLIStatuses
        return VStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("AI 安装检测", "AI Installation Check"),
                subtitle: L("检测本机可用的 AI CLI，并给未安装的代理提供官方安装入口", "Detects local AI CLIs and provides official install pages for missing agents"),
                systemImage: "magnifyingglass"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsFormSurface {
                        ForEach(AgentHookProvider.allCases) { provider in
                            AgentCLIStatusRow(
                                provider: provider,
                                status: agentCLIStatuses[provider] ?? .unknown(provider: provider),
                                install: { model.openAgentInstallPage(provider) }
                            )

                            if provider.id != AgentHookProvider.allCases.last?.id {
                                SettingsControlDivider()
                            }
                        }
                    }

                    HStack {
                        Text(L("检测 PATH、/opt/homebrew/bin 和 /usr/local/bin；安装后点重新检测。", "Scans PATH, /opt/homebrew/bin, and /usr/local/bin; scan again after installing."))
                            .font(.conductorSystem(size: 10.3, weight: .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 12)

                        Button {
                            model.refreshAgentCLIStatuses()
                        } label: {
                            Label(L("重新检测", "Scan Again"), systemImage: "arrow.clockwise")
                        }
                    }
                }
            }

            SettingsPreferenceGroup(
                title: L("Agent 通知", "Agent Notifications"),
                subtitle: L("Codex、Claude Code 等本地 agent hook", "Local agent hooks for Codex, Claude Code, and others"),
                systemImage: "bell.badge"
            ) {
                SettingsFormSurface {
                    ForEach(AgentHookProvider.allCases) { provider in
                        SettingsToggleRow(
                            title: provider.title,
                            subtitle: appearance.agentNotifications.isEnabled(for: provider) ? L("通知桥接已开启", "Notification bridge enabled") : L("不会安装或触发通知桥接", "Notification bridge disabled"),
                            systemImage: provider.systemImage,
                            isOn: Binding(
                                get: { appearance.agentNotifications.isEnabled(for: provider) },
                                set: { enabled in
                                    model.performShellMotion(ConductorMotion.selection) {
                                        model.setAgentNotificationsEnabled(enabled, for: provider)
                                    }
                                }
                            )
                        )

                        if provider.id != AgentHookProvider.allCases.last?.id {
                            SettingsControlDivider()
                        }
                    }
                }
                if let message = snapshot.agentHookSettingsMessage {
                    Text(message)
                        .font(.conductorSystem(size: 10.5, weight: .medium, scale: appearance.fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            if agentCLIStatuses.values.allSatisfy({ $0.state == .unknown }) {
                model.refreshAgentCLIStatuses()
            }
        }
    }

    private func customTerminalFontSubtitle(for appearance: AppearancePreferences) -> String {
        if let name = appearance.terminalRenderer.customFontFamilyName,
           appearance.terminalRenderer.useCustomFont {
            return name
        }
        return L("导入 .ttf/.otf/.ttc 并直接用于 Ghostty", "Import .ttf/.otf/.ttc and use it in Ghostty")
    }

    private func terminalFontSizeText(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    private func multiplierText(_ value: CGFloat) -> String {
        String(format: "%.2fx", Double(value))
    }

    private func percentText(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var commandSettings: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("命令与快捷键", "Commands and Shortcuts"),
                subtitle: L("保留密集列表，适合快速扫视", "Dense command list for fast scanning"),
                systemImage: "keyboard"
            ) {
                CommandShortcutGuide(model: model, height: 260)
            }
        }
    }

    private var themeSettings: some View {
        let activeTheme = snapshot.theme
        return LazyVStack(alignment: .leading, spacing: 16) {
            SettingsPreferenceGroup(
                title: L("当前主题", "Current Theme"),
                subtitle: L("主题会同时影响窗口、终端和强调色", "Themes affect the window, terminal, and accent colors together"),
                systemImage: "swatchpalette"
            ) {
                SelectedThemeShowcase(theme: activeTheme)
            }

            SettingsPreferenceGroup(
                title: L("选择主题", "Choose Theme"),
                subtitle: L("选择后立即应用到当前窗口", "Selection applies immediately to the current window"),
                systemImage: "list.bullet"
            ) {
                SettingsFormSurface {
                    ForEach(Array(TerminalTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                        ThemeOptionRow(
                            theme: theme,
                            selected: activeTheme == theme
                        ) {
                            model.performShellMotion(ConductorMotion.selection) {
                                model.theme = theme
                            }
                        }

                        if index != TerminalTheme.allCases.count - 1 {
                            SettingsControlDivider()
                        }
                    }
                }
            }
        }
    }
}

private enum SettingsPanelSection: String, CaseIterable, Identifiable {
    case overview
    case interface
    case terminal
    case shell
    case automation
    case commands
    case themes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            L("概览", "Overview")
        case .interface:
            L("界面外观", "Interface")
        case .terminal:
            L("终端体验", "Terminal")
        case .shell:
            L("启动/代理", "Startup")
        case .automation:
            L("AI/通知", "AI")
        case .commands:
            L("快捷键", "Shortcuts")
        case .themes:
            L("主题", "Themes")
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            L("当前配置和入口", "Current configuration and entry points")
        case .interface:
            L("窗口、语言和壳层文字", "Window, language, and shell text")
        case .terminal:
            L("字体、显示、输入", "Font, display, input")
        case .shell:
            L("命令、目录、网络", "Command, directory, network")
        case .automation:
            L("Agent、通知、铃声", "Agents, alerts, bell")
        case .commands:
            L("快捷键与命令入口", "Shortcuts and commands")
        case .themes:
            L("整套窗口、终端和强调色", "Window, terminal, and accent colors")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .interface:
            "textformat"
        case .terminal:
            "terminal"
        case .shell:
            "network"
        case .automation:
            "sparkles"
        case .commands:
            "command"
        case .themes:
            "swatchpalette"
        }
    }
}

private enum TerminalSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case typography
    case display
    case selection
    case input

    var id: String { rawValue }

    var title: String {
        switch self {
        case .typography:
            L("字体", "Font")
        case .display:
            L("显示", "Display")
        case .selection:
            L("选择", "Select")
        case .input:
            L("输入", "Input")
        }
    }

    var subtitle: String {
        switch self {
        case .typography:
            L("字体族、字号、行高和自定义字体", "Font family, size, line height, and custom fonts")
        case .display:
            L("光标、背景、透明度和图像背景", "Cursor, background, opacity, and background images")
        case .selection:
            L("选择行为、鼠标、链接和滚动", "Selection behavior, mouse, links, and scrolling")
        case .input:
            L("剪贴板、粘贴安全和键盘输入", "Clipboard, paste safety, and keyboard input")
        }
    }

    var systemImage: String {
        switch self {
        case .typography:
            "textformat"
        case .display:
            "display"
        case .selection:
            "cursorarrow"
        case .input:
            "keyboard"
        }
    }
}

private struct TerminalSettingsSectionRail: View {
    let selection: TerminalSettingsSection
    let action: (TerminalSettingsSection) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TerminalSettingsSection.allCases) { section in
                Button {
                    guard section != selection else { return }
                    action(section)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.systemImage)
                            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                            .frame(width: 13)
                        Text(section.title)
                            .font(.conductorSystem(size: 10.8, weight: section == selection ? .semibold : .medium, scale: fontScale))
                            .lineLimit(1)
                    }
                    .foregroundStyle(section == selection ? ConductorDesign.primaryText : ConductorDesign.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(section == selection ? theme.floatingSelectedFill : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(theme.floatingControlFill.opacity(0.26))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.42), lineWidth: 0.8)
        }
    }
}

private struct SettingsSidebarSummary: View {
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var activeTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(activeTheme.floatingEmphasis)
                    .frame(width: 16)

                Text(L("设置", "Settings"))
                    .font(.conductorSystem(size: 12.4, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
            }

            Text("\(theme.title) · \(appearance.density.title) · \(appearance.fontScale.title)")
                .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.bottom, 2)
    }
}

private struct SettingsPaneHeading: View {
    let section: SettingsPanelSection
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: section.systemImage)
                        .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                        .foregroundStyle(theme.floatingEmphasis)
                        .frame(width: 15)

                    Text(section.title)
                        .font(.conductorSystem(size: 18, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                }
                Text(section.subtitle)
                    .font(.conductorSystem(size: 11.2, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }
}

private struct SettingsSectionLabel: View {
    let title: String
    let subtitle: String
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.conductorSystem(size: 11.5, weight: .bold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .textCase(.uppercase)
            Text(subtitle)
                .font(.conductorSystem(size: 10.4, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private struct SettingsInfoRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.88))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }
}

private struct AgentCLIStatusRow: View {
    let provider: AgentHookProvider
    let status: AgentCLIStatus
    let install: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    private var subtitle: String {
        switch status.state {
        case .unknown:
            return L("尚未检测，打开此页会自动扫描", "Not scanned yet; this page scans automatically")
        case .checking:
            return L("正在检测命令行工具是否可用", "Checking whether the CLI is available")
        case .installed(let path):
            return path
        case .missing:
            return provider.installHint
        }
    }

    var body: some View {
        SettingsControlRow(
            title: provider.title,
            subtitle: subtitle,
            systemImage: provider.systemImage
        ) {
            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch status.state {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .frame(width: 112, alignment: .trailing)
        case .installed:
            SettingsStatusPill(title: L("已安装", "Installed"), systemImage: "checkmark.circle.fill")
        case .missing:
            Button {
                install()
            } label: {
                Label(L("安装", "Install"), systemImage: "arrow.down.circle")
            }
            .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
        case .unknown:
            SettingsStatusPill(title: L("未检测", "Not Checked"), systemImage: "questionmark.circle")
        }
    }
}

private struct SettingsOverviewGrid: View {
    let snapshot: SettingsPanelSnapshot
    @Environment(\.conductorFontScale) private var fontScale

    private var terminalSizeText: String {
        let rounded = (snapshot.appearance.terminalFontSize * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    var body: some View {
        SettingsFormSurface {
            SettingsOverviewTile(
                title: L("主题", "Theme"),
                value: snapshot.theme.title,
                systemImage: "swatchpalette"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("终端字体", "Terminal Font"),
                value: snapshot.appearance.terminalRenderer.effectiveFontFamilyName,
                systemImage: "textformat"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("字号", "Size"),
                value: terminalSizeText,
                systemImage: "textformat.size"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("密度", "Density"),
                value: snapshot.appearance.density.title,
                systemImage: "rectangle.compress.vertical"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("代理", "Proxy"),
                value: snapshot.appearance.terminalRenderer.proxy.enabled ? L("开启", "On") : L("关闭", "Off"),
                systemImage: "network"
            )
            SettingsControlDivider()
            SettingsOverviewTile(
                title: L("AI 通知", "AI Alerts"),
                value: snapshot.appearance.agentNotifications.codex || snapshot.appearance.agentNotifications.claudeCode ? L("开启", "On") : L("关闭", "Off"),
                systemImage: "sparkles"
            )
        }
    }
}

private struct SettingsOverviewTile: View {
    let title: String
    let value: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.84))
                .frame(width: 18)

            Text(title)
                .font(.conductorSystem(size: 12.2, weight: .medium, scale: fontScale))
                .foregroundStyle(ConductorDesign.primaryText)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.conductorSystem(size: 12.1, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
    }
}

private struct SettingsQuickJumpButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis.opacity(0.86))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.conductorSystem(size: 12.3, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10.3, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.conductorSystem(size: 10, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(hovering ? theme.floatingHoverFill.opacity(0.70) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .onHover { hovering = $0 }
    }
}

private struct GhosttyConfigReferenceCard: View {
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(TerminalGhosttyConfigCatalog.totalKeyCount)")
                    .font(.conductorSystem(size: 24, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .monospacedDigit()
                Text(L("个 Ghostty 上游真实配置项", "real upstream Ghostty config keys"))
                    .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                Spacer(minLength: 0)
                SettingsStatusPill(title: TerminalGhosttyConfigCatalog.sourceTitle, systemImage: "doc.text.magnifyingglass")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(TerminalGhosttyConfigCatalog.functionGroups) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)
                        Text(group.countTitle)
                            .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                            .foregroundStyle(ConductorDesign.tertiaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 42, alignment: .leading)
                    .background(theme.floatingControlFill.opacity(0.54))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(theme.floatingStroke.opacity(0.60), lineWidth: 1)
                    }
                }
            }

            Text(L(
                "当前页把上游配置按功能归类。嵌入式 surface 常用项优先使用专用控件；平台级和少见项保留为高级兼容设置。",
                "This page groups upstream settings by function. Common embedded-surface options use dedicated controls; platform-level and uncommon keys remain advanced compatibility settings."
            ))
            .font(.conductorSystem(size: 10.3, weight: .medium, scale: fontScale))
            .foregroundStyle(ConductorDesign.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(theme.floatingControlFill.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct GhosttyFunctionalConfigBrowser: View {
    let renderer: TerminalRendererPreferences
    @Binding var search: String
    let resetOverrides: () -> Void
    let updateOverrideValue: (String, String) -> Void
    let updateOverrideEnabled: (String, Bool) -> Void
    @State private var selectedGroupID = TerminalGhosttyConfigCatalog.productGroups[0].id
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var filteredGroups: [GhosttyConfigFunctionGroup] {
        TerminalGhosttyConfigCatalog.filteredProductGroups(matching: search)
    }

    private var enabledCount: Int {
        renderer.activeGhosttyOverrides.count
    }

    private var selectedGroup: GhosttyConfigFunctionGroup {
        TerminalGhosttyConfigCatalog.productGroups.first { $0.id == selectedGroupID }
            ?? TerminalGhosttyConfigCatalog.productGroups[0]
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField(L("搜索设置", "Search settings"), text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                SettingsStatusPill(
                    title: L("已启用 \(enabledCount)", "\(enabledCount) enabled"),
                    systemImage: "checklist.checked"
                )

                Button(L("清空", "Clear"), action: resetOverrides)
                    .disabled(renderer.ghosttyOverrides.isEmpty)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(TerminalGhosttyConfigCatalog.productGroups) { group in
                        GhosttySettingsCategoryRow(
                            group: group,
                            selected: !isSearching && group.id == selectedGroup.id
                        ) {
                            search = ""
                            selectedGroupID = group.id
                        }
                    }
                }
                .padding(8)
                .frame(width: 178, alignment: .topLeading)
                .background(theme.floatingControlFill.opacity(0.42))
                .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                        .stroke(theme.floatingStroke.opacity(0.66), lineWidth: 1)
                }

                LazyVStack(alignment: .leading, spacing: 12) {
                    if isSearching {
                        ForEach(filteredGroups) { group in
                            GhosttyConfigFunctionSection(
                                renderer: renderer,
                                group: group,
                                updateOverrideValue: updateOverrideValue,
                                updateOverrideEnabled: updateOverrideEnabled
                            )
                        }
                    } else {
                        GhosttyConfigFunctionSection(
                            renderer: renderer,
                            group: selectedGroup,
                            updateOverrideValue: updateOverrideValue,
                            updateOverrideEnabled: updateOverrideEnabled
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Text(L(
                "没有列出 Ghostty 的窗口、GTK、Linux、Quick Terminal、自动更新等无关项；这些不属于 Conductor 的嵌入式终端设置。",
                "Ghostty window, GTK, Linux, Quick Terminal, auto-update, and other irrelevant keys are intentionally hidden from Conductor's embedded terminal settings."
            ))
            .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
            .foregroundStyle(ConductorDesign.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct GhosttySettingsCategoryRow: View {
    let group: GhosttyConfigFunctionGroup
    let selected: Bool
    let action: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: group.systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                        .font(.conductorSystem(size: 11.2, weight: selected ? .bold : .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(group.countTitle)
                        .font(.conductorSystem(size: 9.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(selected ? theme.floatingSelectedFill : theme.floatingControlFill.opacity(0.54))
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
                    .stroke(selected ? theme.floatingSelectedStroke : theme.floatingStroke.opacity(0.66), lineWidth: 1)
            }
        }
        .buttonStyle(ConductorPressButtonStyle())
    }
}

private struct GhosttyConfigFunctionSection: View {
    let renderer: TerminalRendererPreferences
    let group: GhosttyConfigFunctionGroup
    let updateOverrideValue: (String, String) -> Void
    let updateOverrideEnabled: (String, Bool) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: group.systemImage)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .frame(width: 24, height: 24)
                    .background(theme.floatingControlStrongFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(group.title)
                            .font(.conductorSystem(size: 12.2, weight: .bold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                        SettingsStatusPill(title: group.countTitle, systemImage: "number")
                    }
                    Text(group.subtitle)
                        .font(.conductorSystem(size: 10.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            SettingsFormSurface {
                ForEach(group.keys, id: \.self) { key in
                    GhosttyStyledConfigRow(
                        key: key,
                        override: renderer.ghosttyOverride(for: key),
                        updateOverrideValue: updateOverrideValue,
                        updateOverrideEnabled: updateOverrideEnabled
                    )

                    if key != group.keys.last {
                        SettingsControlDivider()
                    }
                }
            }
        }
    }
}

private struct GhosttyStyledConfigRow: View {
    let key: String
    let override: TerminalGhosttyConfigOverride
    let updateOverrideValue: (String, String) -> Void
    let updateOverrideEnabled: (String, Bool) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var isManagedByDefault: Bool {
        TerminalGhosttyConfigCatalog.activeKeys.contains(key)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: controlIcon)
                .font(.conductorSystem(size: 12, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 26, height: 26)
                .background(theme.floatingControlStrongFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(TerminalGhosttyConfigCatalog.displayTitle(for: key))
                        .font(.system(size: 11.3, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)

                    Text(key)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(theme.floatingControlFill.opacity(0.75))
                        .clipShape(Capsule())

                    if isManagedByDefault {
                        Text(L("内置", "Built-in"))
                            .font(.conductorSystem(size: 9, weight: .bold, scale: fontScale))
                            .foregroundStyle(theme.floatingEmphasis)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(theme.floatingControlStrongFill)
                            .clipShape(Capsule())
                    }
                }

                Text(TerminalGhosttyConfigCatalog.description(for: key))
                    .font(.conductorSystem(size: 9.6, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            control
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var controlIcon: String {
        switch TerminalGhosttyConfigCatalog.controlStyle(for: key) {
        case .boolean:
            "switch.2"
        case .choice:
            "list.bullet.rectangle"
        case .percent:
            "slider.horizontal.3"
        case .duration:
            "timer"
        case .color:
            "paintpalette"
        case .filePath:
            "folder"
        case .number:
            "number"
        case .text:
            "text.cursor"
        }
    }

    @ViewBuilder
    private var control: some View {
        switch TerminalGhosttyConfigCatalog.controlStyle(for: key) {
        case .boolean:
            GhosttyBooleanOverridePicker(
                state: booleanState,
                action: setBooleanState
            )
        case .choice(let choices):
            GhosttyChoiceOverrideMenu(
                key: key,
                value: override.normalizedValue,
                enabled: override.enabled,
                choices: choices,
                setValue: { value in
                    updateOverrideValue(key, value)
                    updateOverrideEnabled(key, true)
                },
                setDefault: {
                    updateOverrideEnabled(key, false)
                }
            )
        case .color:
            GhosttyColorOverrideControl(
                key: key,
                value: override.normalizedValue,
                setValue: setOverrideValue,
                reset: resetOverride
            )
        case .filePath:
            GhosttyFileOverrideControl(
                key: key,
                value: override.normalizedValue,
                setValue: setOverrideValue,
                reset: resetOverride
            )
        case .percent:
            GhosttySliderOverrideControl(
                key: key,
                value: override.normalizedValue,
                range: 0...1,
                step: 0.01,
                defaultValue: defaultNumericValue,
                valueText: { "\(Int(($0 * 100).rounded()))%" },
                setValue: { value in setOverrideValue(String(format: "%.2f", Double(value))) },
                reset: resetOverride
            )
        case .duration:
            GhosttyInlineTextOverrideControl(
                key: key,
                placeholder: TerminalGhosttyConfigCatalog.valueHint(for: key),
                value: override.value,
                systemImage: "timer",
                setValue: setOverrideValue,
                reset: resetOverride
            )
        case .number:
            GhosttyInlineTextOverrideControl(
                key: key,
                placeholder: TerminalGhosttyConfigCatalog.valueHint(for: key),
                value: override.value,
                systemImage: "number",
                setValue: setOverrideValue,
                reset: resetOverride
            )
        case .text:
            GhosttyInlineTextOverrideControl(
                key: key,
                placeholder: TerminalGhosttyConfigCatalog.valueHint(for: key),
                value: override.value,
                systemImage: "text.cursor",
                setValue: setOverrideValue,
                reset: resetOverride
            )
        }
    }

    private var defaultNumericValue: CGFloat {
        switch key {
        case "background-opacity", "background-image-opacity", "cursor-opacity", "minimum-contrast", "bell-audio-volume":
            1
        case "faint-opacity":
            0.5
        default:
            0
        }
    }

    private func setOverrideValue(_ value: String) {
        updateOverrideValue(key, value)
        updateOverrideEnabled(key, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func resetOverride() {
        updateOverrideEnabled(key, false)
    }

    private var booleanState: GhosttyBooleanOverrideState {
        guard override.enabled else { return .defaultValue }
        return override.normalizedValue.lowercased() == "false" ? .off : .on
    }

    private func setBooleanState(_ state: GhosttyBooleanOverrideState) {
        switch state {
        case .defaultValue:
            updateOverrideEnabled(key, false)
        case .on:
            updateOverrideValue(key, "true")
            updateOverrideEnabled(key, true)
        case .off:
            updateOverrideValue(key, "false")
            updateOverrideEnabled(key, true)
        }
    }
}

private enum GhosttyBooleanOverrideState: String, CaseIterable, Hashable {
    case defaultValue
    case on
    case off

    var title: String {
        switch self {
        case .defaultValue:
            L("默认", "Default")
        case .on:
            L("开", "On")
        case .off:
            L("关", "Off")
        }
    }
}

private struct GhosttyBooleanOverridePicker: View {
    let state: GhosttyBooleanOverrideState
    let action: (GhosttyBooleanOverrideState) -> Void

    var body: some View {
        Picker(
            "",
            selection: Binding(
                get: { state },
                set: { value in
                    guard value != state else { return }
                    action(value)
                }
            )
        ) {
            ForEach(GhosttyBooleanOverrideState.allCases, id: \.self) { option in
                Text(option.title)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 236)
    }
}

private struct GhosttyChoiceOverrideMenu: View {
    let key: String
    let value: String
    let enabled: Bool
    let choices: [String]
    let setValue: (String) -> Void
    let setDefault: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var title: String {
        enabled && !value.isEmpty ? value : L("默认", "Default")
    }

    var body: some View {
        Menu {
            Button(L("默认", "Default")) {
                setDefault()
            }
            Divider()
            ForEach(choices, id: \.self) { choice in
                Button(choice) {
                    setValue(choice)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.floatingEmphasis)
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
    }
}

private struct GhosttyPresetOption: Hashable {
    let title: String
    let value: String
}

private struct GhosttyPresetOverrideMenu: View {
    let value: String
    let options: [GhosttyPresetOption]
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var selectedTitle: String {
        guard !value.isEmpty else { return L("默认", "Default") }
        return options.first { $0.value == value }?.title ?? value
    }

    var body: some View {
        Menu {
            Button(L("默认", "Default")) {
                reset()
            }
            Divider()
            ForEach(options, id: \.self) { option in
                Button(option.title) {
                    setValue(option.value)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedTitle)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
    }
}

private struct ShellCommandSettingControl: View {
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        HStack(spacing: 8) {
            TextField(L("默认登录 shell", "Default login shell"), text: Binding(
                get: { value },
                set: { setValue($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .frame(width: 186)

            GhosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

private struct WorkingDirectorySettingControl: View {
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var displayName: String {
        guard !value.isEmpty else { return L("继承", "Inherit") }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let url = panel.url {
                    setValue(url.path)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(L("选择", "Choose"))
                }
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            }

            Text(displayName)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(value.isEmpty ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            GhosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

private struct ScrollbackPresetPicker: View {
    private struct Preset: Hashable {
        let title: String
        let value: String
    }

    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var presets: [Preset] {
        [
            Preset(title: L("默认", "Default"), value: ""),
            Preset(title: "10k", value: "10000"),
            Preset(title: "50k", value: "50000"),
            Preset(title: "100k", value: "100000"),
            Preset(title: L("无限制", "Unlimited"), value: "0")
        ]
    }

    private var selectedPreset: Preset {
        presets.first { $0.value == value } ?? Preset(title: value, value: value)
    }

    var body: some View {
        Menu {
            ForEach(presets, id: \.self) { preset in
                Button(preset.title) {
                    if preset.value.isEmpty {
                        reset()
                    } else {
                        setValue(preset.value)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedPreset.title)
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .frame(width: 236, alignment: .trailing)
        }
        .menuStyle(.button)
    }
}

private struct GhosttyResetButton: View {
    let disabled: Bool
    let action: () -> Void
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(disabled ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
                .frame(width: 24, height: 24)
                .background(theme.floatingControlFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
    }
}

private struct GhosttyInlineTextOverrideControl: View {
    let key: String
    let placeholder: String
    let value: String
    let systemImage: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 22, height: 22)
                .background(theme.floatingControlStrongFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            TextField(placeholder, text: Binding(
                get: { value },
                set: { setValue($0) }
            ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 176)

            GhosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

private struct GhosttySliderOverrideControl: View {
    let key: String
    let value: String
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let defaultValue: CGFloat
    let valueText: (CGFloat) -> String
    let setValue: (CGFloat) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var currentValue: CGFloat {
        guard let parsed = Double(value) else { return defaultValue }
        return min(max(CGFloat(parsed), range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { Double(currentValue) },
                    set: { setValue(CGFloat($0)) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .frame(width: 142)

            Text(valueText(currentValue))
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)

            GhosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

private struct GhosttyColorOverrideControl: View {
    let key: String
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorTheme) private var theme

    private var currentColor: Color {
        Color.ghosttyHex(value) ?? Color(nsColor: .textColor)
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(currentColor)
                .frame(width: 22, height: 22)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(theme.floatingStroke.opacity(0.75), lineWidth: 1)
                }

            ColorPicker("", selection: Binding(
                get: { currentColor },
                set: { setValue($0.ghosttyHexString ?? "#FFFFFF") }
            ))
            .labelsHidden()
            .frame(width: 34)

            Text(value.isEmpty ? L("默认", "Default") : value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 112, alignment: .leading)

            GhosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

private struct GhosttyFileOverrideControl: View {
    let key: String
    let value: String
    let setValue: (String) -> Void
    let reset: () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var displayName: String {
        guard !value.isEmpty else { return L("未选择", "Not selected") }
        return URL(fileURLWithPath: value).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = key == "working-directory"
                panel.canChooseFiles = key != "working-directory"
                if panel.runModal() == .OK, let url = panel.url {
                    setValue(url.path)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text(L("选择", "Choose"))
                }
                .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
            }

            Text(displayName)
                .font(.conductorSystem(size: 10.2, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            GhosttyResetButton(
                disabled: value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                action: reset
            )
        }
        .frame(width: 236, alignment: .trailing)
    }
}

private struct TerminalRendererSummary: View {
    let appearance: AppearancePreferences
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            summaryTile(
                title: L("字体", "Font"),
                value: appearance.terminalRenderer.effectiveFontFamilyName,
                systemImage: "textformat"
            )
            summaryTile(
                title: L("字号", "Size"),
                value: terminalFontSizeText(appearance.terminalFontSize),
                systemImage: "textformat.size"
            )
            summaryTile(
                title: L("透明度", "Opacity"),
                value: percentText(appearance.terminalRenderer.backgroundOpacity),
                systemImage: "circle.lefthalf.filled"
            )
            summaryTile(
                title: L("代理", "Proxy"),
                value: appearance.terminalRenderer.proxy.enabled ? L("开启", "On") : L("关闭", "Off"),
                systemImage: "network"
            )
        }
    }

    private func summaryTile(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 22, height: 22)
                .background(theme.floatingControlStrongFill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.conductorSystem(size: 9.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                Text(value)
                    .font(.conductorSystem(size: 10.6, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 44)
        .background(theme.floatingControlFill.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.64), lineWidth: 1)
        }
    }

    private func terminalFontSizeText(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded)) pt"
        }
        return String(format: "%.1f pt", Double(rounded))
    }

    private func percentText(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private extension Color {
    var ghosttyHexString: String? {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return nil }
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func ghosttyHex(_ value: String) -> Color? {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard trimmed.count == 6 || trimmed.count == 8 else { return nil }

        var raw: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&raw) else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if trimmed.count == 8 {
            red = CGFloat((raw & 0xFF00_0000) >> 24) / 255
            green = CGFloat((raw & 0x00FF_0000) >> 16) / 255
            blue = CGFloat((raw & 0x0000_FF00) >> 8) / 255
            alpha = CGFloat(raw & 0x0000_00FF) / 255
        } else {
            red = CGFloat((raw & 0xFF0000) >> 16) / 255
            green = CGFloat((raw & 0x00FF00) >> 8) / 255
            blue = CGFloat(raw & 0x0000FF) / 255
            alpha = 1
        }

        return Color(nsColor: NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha))
    }
}

private struct TerminalFontPickerMenu: View {
    let selection: TerminalFontPreset
    let downloadStates: [TerminalFontPreset: TerminalFontDownloadState]
    let action: (TerminalFontPreset) -> Void
    let download: (TerminalFontPreset) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var selectedChoice: TerminalFontChoice {
        TerminalFontLibrary.choices.first { $0.preset == selection }
            ?? TerminalFontLibrary.choices[0]
    }

    var body: some View {
        Menu {
            ForEach(TerminalFontLibrary.choices) { choice in
                Menu {
                    Button {
                        guard choice.preset != selection else { return }
                        action(choice.preset)
                    } label: {
                        Label(
                            choice.preset == selection ? L("当前使用", "Current Font") : L("设为终端字体", "Use for Terminal"),
                            systemImage: choice.preset == selection ? "checkmark.circle" : "textformat"
                        )
                    }
                    .disabled(choice.preset == selection)

                    if !choice.isInstalled, choice.canDownload {
                        Button {
                            download(choice.preset)
                        } label: {
                            Label(
                                choice.preset.directDownloadURL == nil ? L("打开获取页", "Open Get Page") : L("下载并安装", "Download and Install"),
                                systemImage: choice.preset.directDownloadURL == nil ? "safari" : "arrow.down.circle"
                            )
                        }
                        .disabled(downloadStates[choice.preset]?.isDownloading == true)
                    }
                } label: {
                    Label(
                        "\(choice.displayName) · \(menuStatusTitle(for: choice))",
                        systemImage: menuStatusIcon(for: choice)
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(selectedChoice.displayName)
                        .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                        .lineLimit(1)
                    Text(selectedChoice.statusTitle)
                        .font(.conductorSystem(size: 9.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(selectedChoice.isInstalled ? theme.floatingEmphasis : ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.floatingEmphasis)
            .frame(width: 212, alignment: .trailing)
        }
        .menuStyle(.button)
    }

    private func menuStatusTitle(for choice: TerminalFontChoice) -> String {
        switch downloadStates[choice.preset] {
        case .downloading:
            return L("下载中", "Downloading")
        case .installed(let family):
            return L("已安装：\(family)", "Installed: \(family)")
        case .failed:
            return L("下载失败", "Download Failed")
        case .idle, .none:
            return choice.statusTitle
        }
    }

    private func menuStatusIcon(for choice: TerminalFontChoice) -> String {
        switch downloadStates[choice.preset] {
        case .downloading:
            "arrow.down.circle"
        case .failed:
            "exclamationmark.triangle"
        case .installed:
            "checkmark.circle"
        case .idle, .none:
            choice.isInstalled ? "checkmark.circle" : "arrow.down.circle"
        }
    }
}

private struct SettingsStatusPill: View {
    let title: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 9.5, weight: .bold, scale: fontScale))
            Text(title)
                .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
        }
        .foregroundStyle(theme.floatingEmphasis)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(theme.floatingControlStrongFill)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(theme.floatingStroke.opacity(0.75), lineWidth: 1)
        }
    }
}

private struct SettingsPreferenceGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let content: Content
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis.opacity(0.82))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.conductorSystem(size: 11.5, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10.1, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(.top, 2)
    }
}

private struct SettingsFormSurface<Content: View>: View {
    let content: Content
    @Environment(\.conductorTheme) private var theme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            content
        }
        .background(theme.floatingControlFill.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.48), lineWidth: 0.8)
        }
    }
}

private struct SettingsControlRow<Trailing: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let trailing: Trailing
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.84))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isOn: Binding<Bool>

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        ) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

private struct SettingsTextFieldRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let text: Binding<String>

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        ) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 278)
        }
    }
}

private struct SettingsSliderRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let valueText: String
    let action: (CGFloat) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        SettingsControlRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage
        ) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { action(CGFloat($0)) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: Double(step)
                )
                .frame(width: 192)

                Text(valueText)
                    .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .monospacedDigit()
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }
}

private struct SettingsControlDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.floatingSeparator.opacity(0.70))
            .frame(height: 1)
            .padding(.leading, 50)
    }
}

private struct SettingsSegmentedPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let action: (Option) -> Void

    var body: some View {
        Picker(
            "",
            selection: Binding(
                get: { selection },
                set: { value in
                    guard value != selection else { return }
                    action(value)
                }
            )
        ) {
            ForEach(options, id: \.self) { option in
                Text(title(option))
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 278)
    }
}

private struct SettingsMenuPicker<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let title: (Option) -> String
    let action: (Option) -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) {
                    guard option != selection else { return }
                    action(option)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(title(selection))
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(theme.floatingEmphasis)
            .frame(width: 278, alignment: .trailing)
        }
        .menuStyle(.button)
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
    let selectionNamespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? theme.floatingEmphasis : ConductorDesign.secondaryText)
                    .frame(width: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.conductorSystem(size: 11.6, weight: selected ? .semibold : .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(section.subtitle)
                        .font(.conductorSystem(size: 9.4, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 44, alignment: .center)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.selectionGlide, value: selected)
        .animation(ConductorMotion.hover, value: hovering)
    }

    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
        return ZStack {
            shape
                .fill(hovering ? theme.floatingHoverFill : Color.clear)
            if selected {
                shape
                    .fill(theme.floatingSelectedFill)
                    .matchedGeometryEffect(id: "settings-section-selection", in: selectionNamespace)
            }
        }
    }
}

private struct CommandShortcutGuide: View {
    let model: ConductorWindowModel
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

private struct SelectedThemeShowcase: View {
    let theme: TerminalTheme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThemePreviewArtwork(theme: theme, height: 238)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("当前主题", "Current Theme"))
                        .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .textCase(.uppercase)
                    Text(theme.title)
                        .font(.conductorSystem(size: 22, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(theme.themeDescription)
                        .font(.conductorSystem(size: 11.2, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 5) {
                    ThemeSwatch(color: theme.accent, width: 30)
                    ThemeSwatch(color: theme.floatingPanelBase, width: 30)
                    ThemeSwatch(color: theme.terminalChrome, width: 30)
                    ThemeSwatch(color: theme.terminalBackground, width: 30)
                }

                Text(theme.designLanguage.title)
                    .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(theme.floatingSelectedFill)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    theme.floatingControlStrongFill,
                    theme.floatingControlFill.opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ConductorTokens.Radius.card, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.82), lineWidth: 1)
        }
    }
}

private struct ThemeOptionRow: View {
    let theme: TerminalTheme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var activeTheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.conductorSystem(size: 13, weight: .semibold, scale: fontScale))
                    .foregroundStyle(selected ? activeTheme.floatingEmphasis : ConductorDesign.tertiaryText.opacity(0.62))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(theme.title)
                            .font(.conductorSystem(size: 12.4, weight: .semibold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)

                        Text(theme.designLanguage.title)
                            .font(.conductorSystem(size: 9.3, weight: .bold, scale: fontScale))
                            .foregroundStyle(activeTheme.floatingEmphasis.opacity(0.9))
                            .padding(.horizontal, 6)
                            .frame(height: 17)
                            .background(activeTheme.floatingControlFill.opacity(0.58))
                            .clipShape(Capsule())
                    }

                    Text(theme.themeDescription)
                        .font(.conductorSystem(size: 10.1, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 4) {
                    ThemeSwatch(color: theme.accent, width: 22)
                    ThemeSwatch(color: theme.floatingPanelBase, width: 22)
                    ThemeSwatch(color: theme.terminalChrome, width: 22)
                    ThemeSwatch(color: theme.terminalBackground, width: 22)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(rowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .animation(ConductorMotion.hover, value: hovering)
    }

    private var rowFill: Color {
        if selected {
            return activeTheme.floatingSelectedFill
        }
        if hovering {
            return activeTheme.floatingHoverFill.opacity(0.72)
        }
        return Color.clear
    }
}

private struct ThemePreviewArtwork: View {
    let theme: TerminalTheme
    var height: CGFloat
    var showsSidebar: Bool = true

    private var large: Bool {
        height > 100
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: theme.windowBackdropStops,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ThemePreviewMotif(theme: theme)
                .opacity(large ? 1 : 0.72)

            HStack(spacing: large ? 8 : 5) {
                if showsSidebar {
                    VStack(alignment: .leading, spacing: large ? 7 : 5) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.white.opacity(0.82))
                                .frame(width: large ? 5 : 4, height: large ? 5 : 4)
                            Circle()
                                .fill(theme.accent.opacity(0.76))
                                .frame(width: large ? 5 : 4, height: large ? 5 : 4)
                            Spacer(minLength: 0)
                        }
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.shellSelectedFill)
                            .frame(height: large ? 12 : 8)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(theme.shellHoverFill)
                            .frame(width: large ? 42 : 26, height: large ? 10 : 8)
                        Spacer(minLength: 0)
                    }
                    .padding(large ? 9 : 6)
                    .frame(width: large ? 72 : 45)
                    .background(theme.shellPanelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous))
                }

                VStack(spacing: 0) {
                    HStack(spacing: large ? 6 : 4) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(theme.accent.opacity(0.80))
                            .frame(width: large ? 32 : 18, height: large ? 5 : 4)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white.opacity(theme.usesDarkChrome ? 0.22 : 0.58))
                            .frame(width: large ? 48 : 28, height: large ? 5 : 4)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, large ? 10 : 7)
                    .frame(height: large ? 25 : 16)
                    .background(theme.terminalChrome.opacity(0.92))

                    VStack(alignment: .leading, spacing: large ? 5 : 3) {
                        PreviewTerminalLine(prompt: "$", text: "swift build", accent: theme.accent, fontSize: large ? 10 : 8.5)
                        PreviewTerminalLine(prompt: ">", text: "Conductor", accent: theme.accent, fontSize: large ? 10 : 8.5)
                        Rectangle()
                            .fill(theme.accent.opacity(0.86))
                            .frame(width: large ? 42 : 22, height: large ? 3 : 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(large ? 11 : 7)
                    .background(theme.terminalBackground)
                }
                .clipShape(RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous))
            }
            .padding(large ? 10 : 6)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: large ? 13 : 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: large ? 13 : 9, style: .continuous)
                .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.22 : 0.42), lineWidth: 1)
        }
    }
}

private struct ThemePreviewMotif: View {
    let theme: TerminalTheme

    var body: some View {
        GeometryReader { proxy in
            switch theme.designLanguage {
            case .neon:
                Path { path in
                    let step: CGFloat = 18
                    var x: CGFloat = 0
                    while x <= proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += step
                    }
                }
                .stroke(theme.accent.opacity(0.20), lineWidth: 0.7)
            case .paper, .editorial:
                VStack(spacing: 13) {
                    ForEach(0..<12, id: \.self) { _ in
                        Rectangle()
                            .fill(theme.shellStroke.opacity(0.36))
                            .frame(height: 1)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)
            case .glass, .fluid, .frost:
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.16))
                        .frame(width: proxy.size.width * 0.42)
                        .blur(radius: 22)
                        .offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.18)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(theme.usesDarkChrome ? 0.18 : 0.34), lineWidth: 1)
                        .frame(width: proxy.size.width * 0.42, height: proxy.size.height * 0.44)
                        .offset(x: proxy.size.width * 0.22, y: proxy.size.height * 0.18)
                }
            case .botanical:
                HStack(alignment: .bottom, spacing: 11) {
                    ForEach(0..<9, id: \.self) { index in
                        Capsule()
                            .fill(theme.accent.opacity(index.isMultiple(of: 2) ? 0.20 : 0.10))
                            .frame(width: 5, height: CGFloat(24 + index * 7))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(18)
            case .sunlit, .warm:
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.24),
                        theme.accent.opacity(0.16),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .studio, .minimal, .system:
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme.usesDarkChrome ? 0.025 : 0.18),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PreviewTerminalLine: View {
    let prompt: String
    let text: String
    let accent: Color
    var fontSize: CGFloat = 8.5

    var body: some View {
        HStack(spacing: 4) {
            Text(prompt)
                .foregroundStyle(accent)
            Text(text)
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(1)
        }
        .font(.system(size: fontSize, weight: .medium, design: .monospaced))
    }
}

private struct ThemeSwatch: View {
    let color: Color
    var width: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: width, height: 5)
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
                                    .transition(ConductorMotion.rowTransition(itemCount: filteredWorkspaces.count))
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.bottom, 2)
                            .animation(ConductorMotion.list(itemCount: filteredWorkspaces.count), value: filteredWorkspaceIDs)
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
            .animation(ConductorMotion.feedback, value: highlightedWorkspaceID)
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
        ConductorMotion.withoutAnimation {
            model.selectWorkspace(workspaceID)
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
        .scaleEffect(hovering ? 1.006 : 1)
        .shadow(
            color: Color.black.opacity(hovering ? (theme.usesDarkChrome ? 0.16 : 0.08) : 0),
            radius: hovering ? 10 : 0,
            x: 0,
            y: hovering ? 5 : 0
        )
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

private struct ConductorSidebar: View {
    let model: ConductorWindowModel
    let snapshot: WorkspaceChromeSnapshot
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    let sidebarVisible: Bool
    @State private var renamingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""
    @State private var sidebarToggleHovering = false
    @Namespace private var sidebarSelectionNamespace
    @State private var visualSelectedSidebarWorkspaceID: WorkspaceID?
    @Environment(\.conductorFontScale) private var fontScale

    private var sidebarHeaderHeight: CGFloat {
        sidebarVisible ? 54 : 82
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            if sidebarVisible {
                expandedSidebar
                    .transition(.opacity)
            } else {
                collapsedSidebar
                    .transition(.opacity)
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
        .onAppear {
            setVisualSidebarSelection(snapshot.selectedWorkspaceID, animated: false)
        }
        .onChange(of: snapshot.selectedWorkspaceID) {
            setVisualSidebarSelection(snapshot.selectedWorkspaceID, animated: true)
        }
        .onChange(of: snapshot.workspaceIDs) {
            if visualSelectedSidebarWorkspaceID == nil || !snapshot.workspaceIDs.contains(visualSelectedSidebarWorkspaceID!) {
                setVisualSidebarSelection(snapshot.selectedWorkspaceID, animated: false)
            }
        }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SidebarDockButton(icon: "plus.rectangle.on.rectangle", help: L("新开终端 Cmd-T", "New Terminal Cmd-T")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.newTerminal)
                }
                SidebarDockButton(icon: "command", help: L("打开命令面板 Cmd-K", "Open Command Center Cmd-K")) {
                    finishWorkspaceRenameIfNeeded()
                    model.performCommand(.toggleCommandPalette)
                }
                Spacer(minLength: 0)
                SidebarDockButton(icon: "gearshape", help: L("设置", "Settings")) {
                    finishWorkspaceRenameIfNeeded()
                    ConductorMotion.perform(ConductorMotion.panel) {
                        model.performCommand(.toggleSettings)
                    }
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 9)
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
            SidebarRailButton(icon: "plus.rectangle.on.rectangle", help: L("新开终端 Cmd-T", "New Terminal Cmd-T")) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.newTerminal)
            }
            SidebarRailButton(icon: "command", help: L("打开命令面板 Cmd-K", "Open Command Center Cmd-K")) {
                finishWorkspaceRenameIfNeeded()
                model.performCommand(.toggleCommandPalette)
            }
        }
    }

    private var collapsedSidebarFooter: some View {
        VStack(spacing: 6) {
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

    private func workspaceRow(for row: WorkspaceChromeDisplayModel) -> some View {
        WorkspaceSidebarRow(
            title: row.title,
            subtitle: row.subtitle,
            splitCount: row.splitCount,
            terminalCount: row.terminalCount,
            unreadCount: row.unreadCount,
            selected: row.selected,
            visuallySelected: visualSelectedSidebarWorkspaceID == row.id,
            selectionNamespace: sidebarSelectionNamespace,
            editing: renamingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onCommitRename: commitWorkspaceRename,
            onCancelRename: cancelWorkspaceRename
        ) {
            setVisualSidebarSelection(row.id, animated: true)
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

    private func setVisualSidebarSelection(_ workspaceID: WorkspaceID, animated: Bool) {
        let update = {
            visualSelectedSidebarWorkspaceID = workspaceID
        }
        if animated {
            model.performShellMotion(ConductorMotion.selectionGlide, update)
        } else {
            ConductorMotion.withoutAnimation(update)
        }
    }

}

private struct SidebarRailShape: InsettableShape {
    var bottomLeadingRadius: CGFloat = ConductorDesign.sidebarCornerRadius
    var bottomTrailingRadius: CGFloat = 14
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

private struct WorkspaceChromeSnapshot: Equatable {
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

private struct WorkspaceChromeDisplayModel: Identifiable, Equatable {
    let id: WorkspaceID
    let title: String
    var subtitle: String = ""
    let splitCount: Int
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
}

private struct WorkspaceFileTabDisplayModel: Identifiable, Equatable {
    var id: String { tab.id }
    let tab: ConductorWorkspaceFileTab
    let selected: Bool
    let dirty: Bool
}

private enum WorkspaceChromeGlyph {
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
    let icon: String
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
                .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                .foregroundStyle(disabled ? theme.shellChromeTextMuted.opacity(0.50) : theme.shellChromeText.opacity(0.86))
                .frame(width: 28, height: 27)
                .background(hovering && !disabled ? theme.shellHoverFill.opacity(0.78) : theme.shellControlFill.opacity(0.34))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .scaleEffect(hovering && !disabled ? 1.035 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .animation(ConductorMotion.micro, value: disabled)
        .onHover { hovering = $0 }
        .macNativeTooltip(help)
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
        .macNativeTooltip(help)
    }
}

private struct SidebarSectionTitle: View {
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
        .background {
            sidebarRowBackground
        }
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
                subtitle: subtitle,
                splitCount: splitCount,
                terminalCount: terminalCount,
                unreadCount: unreadCount,
                selected: selected,
                visuallySelected: visuallySelected,
                selectionNamespace: selectionNamespace,
                hovering: hovering,
                themeID: theme.id,
                fontScaleID: fontScale.id
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

    private var sidebarRowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
        return ZStack {
            shape
                .fill(hovering ? theme.shellHoverFill : Color.clear)
            if visuallySelected {
                shape
                    .fill(theme.shellSelectedFill)
                    .matchedGeometryEffect(id: "sidebar-workspace-selection", in: selectionNamespace)
            }
        }
    }
}

private struct WorkspaceSidebarRowContent: View, Equatable {
    let title: String
    let subtitle: String
    let splitCount: Int
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
    let visuallySelected: Bool
    let selectionNamespace: Namespace.ID
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
        lhs.visuallySelected == rhs.visuallySelected &&
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
        .padding(.leading, 7)
        .padding(.trailing, 7)
        .frame(height: 48)
        .background {
            let shape = RoundedRectangle(cornerRadius: ConductorTokens.Radius.row, style: .continuous)
            shape
                .fill(hovering ? theme.shellHoverFill : Color.clear)
            if visuallySelected {
                shape
                    .fill(theme.shellSelectedFill)
                    .matchedGeometryEffect(id: "sidebar-workspace-selection", in: selectionNamespace)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .contentShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.row))
        .transaction { transaction in
            transaction.animation = nil
        }
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

private struct ConductorToolbar: View {
    let model: ConductorWindowModel
    let workspaceSnapshot: WorkspaceChromeSnapshot
    let theme: TerminalTheme
    let appearance: AppearancePreferences
    @State private var editingWorkspaceID: WorkspaceID?
    @State private var workspaceTitleDraft = ""

    var body: some View {
        ConductorTerminalToolbarSurface(theme: theme) {
            HStack(spacing: ConductorTokens.Space.toolbarGap) {
                WorkspaceTabStrip(
                    model: model,
                    snapshot: workspaceSnapshot,
                    appearance: appearance,
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
                        systemImage: "folder",
                        help: L("文件管理器", "File Manager"),
                        title: L("文件", "Files"),
                        disabled: !model.canPerformCommand(.toggleFileManager),
                        active: model.fileManagerPanelRequest != nil
                    ) {
                        finishWorkspaceRenameIfNeeded()
                        model.performCommand(.toggleFileManager)
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
                        systemImage: workspaceSnapshot.totalUnreadCount > 0 ? "bell.badge" : "bell",
                        help: L("通知中心 Cmd-Opt-N", "Notification Center Cmd-Opt-N"),
                        title: workspaceSnapshot.totalUnreadCount > 0 ? L("通知 \(workspaceSnapshot.totalUnreadCount)", "Alerts \(workspaceSnapshot.totalUnreadCount)") : L("通知", "Alerts"),
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
            .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        }
        .frame(height: ConductorDesign.toolbarHeight(for: appearance))
        .animation(model.shellAnimation(ConductorMotion.standard), value: theme)
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
    let model: ConductorWindowModel
    let snapshot: WorkspaceChromeSnapshot
    let appearance: AppearancePreferences
    @Binding var editingWorkspaceID: WorkspaceID?
    @Binding var workspaceTitleDraft: String
    let onBeginRename: (WorkspaceChromeDisplayModel) -> Void
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    @Namespace private var selectionNamespace
    @State private var scrollTargetID: WorkspaceID?
    @State private var visualSelectedWorkspaceID: WorkspaceID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WorkspaceTabMetrics.spacing) {
                ForEach(snapshot.rows) { row in
                    workspaceTabView(for: row)
                        .transition(ConductorMotion.tabTransition)
                }

                if !snapshot.fileTabs.isEmpty {
                    WorkspaceTabSectionDivider()
                    ForEach(snapshot.fileTabs) { fileTab in
                        WorkspaceFileTopTab(
                            tab: fileTab.tab,
                            appearance: appearance,
                            selected: fileTab.selected,
                            dirty: fileTab.dirty,
                            onSelect: {
                                finishWorkspaceRenameIfNeeded()
                                model.selectWorkspaceFileTab(fileTab.id)
                            },
                            onClose: {
                                withoutShellAnimation {
                                    finishWorkspaceRenameIfNeeded()
                                    model.closeWorkspaceFileTab(fileTab.tab)
                                }
                            }
                        )
                        .transition(ConductorMotion.tabTransition)
                    }
                }
            }
            .padding(.horizontal, WorkspaceTabMetrics.edgePadding)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollTargetID, anchor: .center)
        .onAppear {
            setVisualSelection(snapshot.selectedWorkspaceID, animated: false)
            syncScrollTarget(animated: false)
        }
        .onChange(of: snapshot.selectedWorkspaceID) {
            setVisualSelection(snapshot.selectedWorkspaceID, animated: true)
            syncScrollTarget(animated: true)
        }
        .onChange(of: snapshot.workspaceIDs) {
            if visualSelectedWorkspaceID == nil || !snapshot.workspaceIDs.contains(visualSelectedWorkspaceID!) {
                setVisualSelection(snapshot.selectedWorkspaceID, animated: false)
            }
            syncScrollTarget(animated: true)
        }
        .frame(
            minWidth: WorkspaceTabMetrics.width(for: appearance),
            maxWidth: .infinity,
            minHeight: WorkspaceTabMetrics.height(for: appearance),
            maxHeight: WorkspaceTabMetrics.height(for: appearance),
            alignment: .leading
        )
        .clipped()
        .mask(ConductorHorizontalFadeMask())
        .animation(model.shellAnimation(ConductorMotion.list), value: snapshot.workspaceIDs)
    }

    private func syncScrollTarget(animated: Bool) {
        guard snapshot.workspaceIDs.contains(snapshot.selectedWorkspaceID) else { return }
        let update = {
            scrollTargetID = snapshot.selectedWorkspaceID
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
            appearance: appearance,
            active: row.selected && snapshot.selectedWorkspaceFileTabID == nil,
            visuallySelected: visualSelectedWorkspaceID == row.id && snapshot.selectedWorkspaceFileTabID == nil,
            selectionNamespace: selectionNamespace,
            canClose: snapshot.canCloseWorkspace,
            editing: editingWorkspaceID == row.id,
            titleDraft: $workspaceTitleDraft,
            onSelect: {
                setVisualSelection(row.id, animated: true)
                finishWorkspaceRenameIfNeeded(except: row.id)
                ConductorMotion.withoutAnimation {
                    model.selectWorkspace(row.id)
                    model.selectTerminalStage()
                }
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

    private func finishWorkspaceRenameIfNeeded(except workspaceID: WorkspaceID? = nil) {
        guard let editingWorkspaceID,
              editingWorkspaceID != workspaceID else {
            return
        }
        onCommitRename()
    }

    private func setVisualSelection(_ workspaceID: WorkspaceID, animated: Bool) {
        let update = {
            visualSelectedWorkspaceID = workspaceID
        }
        if animated {
            model.performShellMotion(ConductorMotion.selectionGlide, update)
        } else {
            ConductorMotion.withoutAnimation(update)
        }
    }
}

private struct WorkspaceTabSectionDivider: View {
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.45 : 0.28))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
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

private struct WorkspaceFileTopTab: View {
    let tab: ConductorWorkspaceFileTab
    let appearance: AppearancePreferences
    let selected: Bool
    let dirty: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.92) : theme.shellControlFill.opacity(0.58)
        }
        return hovering ? theme.shellHoverFill.opacity(0.86) : theme.shellControlFill.opacity(0.52)
    }

    private var selectedFill: Color {
        theme.usesDarkChrome ? theme.shellPanelStrong.opacity(0.72) : theme.shellPanelStrong.opacity(0.82)
    }

    private var tabStroke: Color {
        if selected {
            return theme.shellStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.42) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.34 : 0.18)
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    private var fileIcon: String {
        let ext = tab.fileURL.pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return "doc.richtext"
        }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) {
            return "photo"
        }
        return "doc.text"
    }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: fileIcon)
                    .font(.system(size: 10.8, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? theme.shellChromeText.opacity(0.90) : theme.shellChromeTextMuted.opacity(0.70))
                    .frame(width: 17, height: 17)
                Text(tab.title)
                    .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Circle()
                    .fill(theme.floatingEmphasis.opacity(0.92))
                    .frame(width: 5, height: 5)
                    .opacity(dirty ? 1 : 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect()
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 8.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(titleColor.opacity(selected || hovering ? 0.74 : 0.52))
                    .frame(width: 13, height: 13)
                    .clipShape(Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(ConductorPressButtonStyle())
            .macNativeTooltip(L("关闭文件", "Close File"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background {
            ZStack {
                tabShape
                    .fill(baseFill)
                if selected {
                    tabShape
                        .fill(selectedFill)
                }
            }
        }
        .clipShape(tabShape)
        .overlay {
            tabShape
                .stroke(tabStroke, lineWidth: 1)
        }
        .scaleEffect(hovering && !selected ? 1.006 : 1)
        .animation(ConductorMotion.hover, value: hovering)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(tabShape)
        .contextMenu {
            Button(L("关闭文件", "Close File")) {
                onClose()
            }
            Button(L("在访达中显示", "Reveal in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([tab.fileURL])
            }
        }
    }
}

private struct WorkspaceTopTab: View {
    let row: WorkspaceChromeDisplayModel
    let appearance: AppearancePreferences
    let active: Bool
    let visuallySelected: Bool
    let selectionNamespace: Namespace.ID
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
        active
    }

    private var unreadCount: Int {
        row.unreadCount
    }

    private var tabShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ConductorTokens.Radius.workspaceTab, style: .continuous)
    }

    private var baseFill: Color {
        if theme.usesDarkChrome {
            return hovering ? theme.shellHoverFill.opacity(0.92) : theme.shellControlFill.opacity(0.72)
        }
        return hovering ? theme.shellHoverFill.opacity(0.86) : theme.shellControlFill.opacity(0.62)
    }

    private var selectedFill: Color {
        theme.usesDarkChrome ? theme.shellPanelStrong.opacity(0.72) : theme.shellPanelStrong.opacity(0.82)
    }

    private var tabStroke: Color {
        if selected {
            return theme.shellStroke.opacity((theme.usesDarkChrome ? 0.58 : 0.42) * appearance.chromeClarity.strokeMultiplier)
        }
        return theme.shellStroke.opacity(hovering ? 0.34 : 0.18)
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
                WorkspaceTopTabContent(
                    title: row.title,
                    terminalCount: row.terminalCount,
                    unreadCount: unreadCount,
                    selected: selected,
                    themeID: theme.id,
                    fontScaleID: fontScale.id
                )
                .equatable()
                .contentShape(Rectangle())
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
                .macNativeTooltip(L("关闭工作区", "Close Workspace"))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, editing ? 8 : 6)
        .frame(
            width: WorkspaceTabMetrics.width(for: appearance),
            height: WorkspaceTabMetrics.height(for: appearance)
        )
        .background {
            ZStack {
                tabShape
                    .fill(baseFill)
                if visuallySelected {
                    tabShape
                        .fill(selectedFill)
                        .matchedGeometryEffect(id: "workspace-tab-selection", in: selectionNamespace)
                }
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
        .animation(ConductorMotion.attention, value: unreadCount)
        .onHover { value in
            ConductorMotion.perform(ConductorMotion.hover) {
                hovering = value
            }
        }
        .contentShape(tabShape)
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
    }
}

private struct WorkspaceTopTabContent: View, Equatable {
    let title: String
    let terminalCount: Int
    let unreadCount: Int
    let selected: Bool
    let themeID: String
    let fontScaleID: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    nonisolated static func == (lhs: WorkspaceTopTabContent, rhs: WorkspaceTopTabContent) -> Bool {
        lhs.title == rhs.title &&
        lhs.terminalCount == rhs.terminalCount &&
        lhs.unreadCount == rhs.unreadCount &&
        lhs.selected == rhs.selected &&
        lhs.themeID == rhs.themeID &&
        lhs.fontScaleID == rhs.fontScaleID
    }

    private var titleColor: Color {
        selected ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.86)
    }

    var body: some View {
        HStack(spacing: 7) {
            WorkspaceTabGlyph(selected: selected)
            Text(title)
                .font(.conductorSystem(size: 11.3, weight: .semibold, scale: fontScale))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(terminalCount)")
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
