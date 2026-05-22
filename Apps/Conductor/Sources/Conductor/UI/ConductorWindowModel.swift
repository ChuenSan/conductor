import AppKit
import ConductorCore
import Foundation
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

enum TerminalProgressKind: String, Equatable {
    case removed
    case set
    case error
    case indeterminate
    case paused
}

struct TerminalSearchMetadata: Equatable {
    var active = false
    var needle: String?
    var total: Int?
    var selected: Int?
}

struct TerminalSearchTargetDisplay: Identifiable, Equatable {
    let id: TerminalID
    let title: String
    let subtitle: String
    let isActive: Bool
}

struct TerminalDisplayMetadata: Equatable {
    var workingDirectory: String?
    var unreadCount = 0
    var lastNotificationTitle: String?
    var lastNotificationBody: String?
    var progressKind: TerminalProgressKind?
    var progressPercent: Int?
    var lastCommandExitCode: Int?
    var lastCommandDurationNanoseconds: UInt64?
    var cellWidth: UInt32?
    var cellHeight: UInt32?
    var search = TerminalSearchMetadata()
    var readonly = false
    var bellCount = 0
}

private enum TerminalContextMenuAction {
    case renameTerminal
    case restoreTerminalTitle
    case duplicateTerminal
    case showSearch
    case showFileManager
    case openDirectory
    case copyDirectory
    case newTerminal
    case newTerminalAtDirectory
    case splitRight
    case splitDown
    case closePane
    case closeTerminal
    case closeOtherTerminals
    case closeTerminalsToRight
    case renameWorkspace
    case duplicateWorkspace
    case closeWorkspace
}

@MainActor
private final class TerminalContextMenuController: NSObject, NSMenuDelegate {
    private var nextActionTag = 1
    private var actions: [Int: @MainActor () -> Void] = [:]
    var onClose: (() -> Void)?

    func makeItem(
        title: String,
        enabled: Bool,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let actionTag = nextActionTag
        nextActionTag += 1
        actions[actionTag] = action

        let item = NSMenuItem(
            title: title,
            action: #selector(performMenuAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = actionTag
        item.isEnabled = enabled
        item.representedObject = self
        return item
    }

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        actions[sender.tag]?()
    }

    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.onClose?()
        }
    }
}

private struct TerminalContextMenuTarget {
    let workspaceID: WorkspaceID
    let workspace: WorkspaceState
    let paneID: PaneID
    let tab: TerminalTabState
}

struct ConductorWorkspaceFileTab: Identifiable, Equatable, Hashable, Sendable {
    var id: String { fileURL.standardizedFileURL.path }
    let fileURL: URL
    let rootURL: URL
    let title: String

    init(fileURL: URL, rootURL: URL) {
        let file = fileURL.standardizedFileURL
        self.fileURL = file
        self.rootURL = rootURL.standardizedFileURL
        self.title = file.lastPathComponent
    }
}

enum ConductorWorkspaceContentTabID: Equatable, Hashable {
    case terminal(TerminalID)
    case file(String)
}

@MainActor
final class ConductorWindowModel: ObservableObject, GhosttyAppRuntimeActionDelegate {
    @Published var workspace: WorkspaceState {
        didSet {
            let previousWorkspace = oldValue
            selectedWorkspaceID = workspace.id
            let shouldSyncPreviousWorkspace = !skipPreviousWorkspaceSyncForNextAssignment
            skipPreviousWorkspaceSyncForNextAssignment = false
            if shouldSyncPreviousWorkspace {
                if previousWorkspace.id == workspace.id {
                    syncSelectedWorkspace()
                } else {
                    syncWorkspace(previousWorkspace)
                }
            }
            persist()
        }
    }
    @Published private(set) var workspaces: [WorkspaceState]
    @Published var theme: TerminalTheme {
        didSet {
            surfaces.values.forEach {
                $0.applyAppearance(theme: theme, terminalFontSize: appearance.terminalFontSize)
            }
            persist()
        }
    }
    @Published var appearance: AppearancePreferences {
        didSet {
            guard oldValue != appearance else { return }
            ConductorAppearanceRuntime.apply(appearance)
            TerminalAppearanceRuntime.apply(appearance)
            ConductorMotion.setReducedMotion(appearance.reducedMotion)
            if oldValue.terminalFontSize != appearance.terminalFontSize ||
                oldValue.terminalRenderer != appearance.terminalRenderer {
                surfaces.values.forEach {
                    $0.applyAppearance(theme: theme, terminalFontSize: appearance.terminalFontSize)
                }
            }
            persist()
        }
    }
    @Published private(set) var metadataByTerminalID: [TerminalID: TerminalDisplayMetadata] = [:]
    @Published private(set) var notifications = TerminalNotificationState()
    @Published var notificationPanelVisible = false {
        didSet {
            guard oldValue != notificationPanelVisible else { return }
            onNotificationPanelVisibilityChange?(notificationPanelVisible)
        }
    }
    @Published var sidebarVisible = true
    @Published var commandPaletteVisible = false
    @Published var settingsPanelVisible = false
    @Published var workspaceOverviewVisible = false
    @Published var terminalSearchVisible = false
    @Published var fileManagerPanelRequest: FileManagerPanelRequest?
    @Published private(set) var workspaceFileTabs: [ConductorWorkspaceFileTab] = []
    @Published private(set) var dirtyWorkspaceFileTabIDs: Set<String> = []
    @Published private(set) var externallyChangedWorkspaceFileTabIDs: Set<String> = []
    @Published private(set) var workspaceFileEditorSaveRequestTokensByTabID: [String: Int] = [:]
    @Published private(set) var workspaceFileEditorSaveAndCloseRequestTokensByTabID: [String: Int] = [:]
    @Published private(set) var workspaceFileSearchFocusGeneration = 0
    @Published private(set) var workspaceFileSearchNextGeneration = 0
    @Published private(set) var workspaceFileSearchPreviousGeneration = 0
    @Published private(set) var workspaceFileLayoutRevision = 0
    @Published private(set) var fileManagerKeyboardFocused = false
    @Published private(set) var fileManagerSearchFocusGeneration = 0
    @Published private(set) var fileManagerSearchNextGeneration = 0
    @Published private(set) var fileManagerSearchPreviousGeneration = 0
    @Published private(set) var selectedWorkspaceContentTabID: ConductorWorkspaceContentTabID?
    @Published var terminalSearchQuery = ""
    @Published private(set) var agentHookSettingsMessage: String?
    @Published private(set) var agentCLIStatuses: [AgentHookProvider: AgentCLIStatus]
    @Published private(set) var terminalFontDownloadStates: [TerminalFontPreset: TerminalFontDownloadState]
    @Published private(set) var terminalSearchFocusGeneration = 0
    @Published private(set) var terminalSearchTargetID: TerminalID?
    @Published private(set) var paneFlashTokens: [PaneID: UInt64] = [:]
    @Published private(set) var terminalTabDropTargetByPaneID: [PaneID: TerminalTabDropTarget] = [:]
    @Published private(set) var activeTerminalTabDragID: TerminalID?
    private var terminalTabDragGeneration: UInt64 = 0

    var onNotificationPanelVisibilityChange: ((Bool) -> Void)?

    var selectedWorkspaceFileTab: ConductorWorkspaceFileTab? {
        guard case .file(let selectedWorkspaceFileTabID) = selectedWorkspaceContentTabID else { return nil }
        return workspaceFileTabs.first { $0.id == selectedWorkspaceFileTabID }
    }

    var selectedWorkspaceFileTabID: String? {
        guard case .file(let selectedWorkspaceFileTabID) = selectedWorkspaceContentTabID else { return nil }
        return selectedWorkspaceFileTabID
    }

    var selectedWorkspaceTerminalTabID: TerminalID? {
        if case .terminal(let terminalID) = selectedWorkspaceContentTabID,
           workspace.paneID(containing: terminalID) != nil {
            return terminalID
        }
        return focusedTerminalID
    }

    var workspaceTerminalContentTabs: [TerminalTabState] {
        workspace.focusedPane?.selectedTab.map { [$0] } ?? []
    }

    private func markTerminalInteractionFocus() {
        if fileManagerKeyboardFocused {
            fileManagerKeyboardFocused = false
        }
    }

    private let persistence = WorkspacePersistence()
    private var surfaces: [TerminalID: TerminalSurface] = [:]
    private var pendingPersistence: DispatchWorkItem?
    private var pendingMetadataByTerminalID: [TerminalID: TerminalDisplayMetadata] = [:]
    private var pendingMetadataPublish: DispatchWorkItem?
    private var activeTerminalContextMenuController: TerminalContextMenuController?
    private var selectedWorkspaceID: WorkspaceID
    private var skipPreviousWorkspaceSyncForNextAssignment = false
    private var pendingNavigationRefreshTerminalIDs = Set<TerminalID>()

    init() {
        let persisted = persistence.load()
        var persistedWorkspaces = persisted?.workspaces ?? [WorkspaceState()]
        for index in persistedWorkspaces.indices {
            persistedWorkspaces[index].normalizeMixedSplitLayout()
        }
        let selectedID = persisted?.selectedWorkspaceID ?? persistedWorkspaces[0].id
        self.workspaces = persistedWorkspaces
        self.selectedWorkspaceID = selectedID
        self.workspace = persistedWorkspaces.first { $0.id == selectedID } ?? persistedWorkspaces[0]
        self.theme = persisted?.theme ?? .graphite
        self.appearance = persisted?.appearance ?? AppearancePreferences()
        self.agentCLIStatuses = Dictionary(uniqueKeysWithValues: AgentHookProvider.allCases.map { ($0, .unknown(provider: $0)) })
        self.terminalFontDownloadStates = [:]
        ConductorAppearanceRuntime.apply(self.appearance)
        TerminalAppearanceRuntime.apply(self.appearance)
        ConductorMotion.setReducedMotion(self.appearance.reducedMotion)
    }

    #if DEBUG
    init(
        previewWorkspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID? = nil,
        theme: TerminalTheme = .graphite,
        appearance: AppearancePreferences = AppearancePreferences(),
        notifications: TerminalNotificationState = TerminalNotificationState(),
        sidebarVisible: Bool = true,
        commandPaletteVisible: Bool = false,
        notificationPanelVisible: Bool = false,
        settingsPanelVisible: Bool = false,
        workspaceOverviewVisible: Bool = false
    ) {
        let resolvedWorkspaces = previewWorkspaces.isEmpty ? [WorkspaceState()] : previewWorkspaces
        let selectedID = selectedWorkspaceID ?? resolvedWorkspaces[0].id
        self.workspaces = resolvedWorkspaces
        self.selectedWorkspaceID = selectedID
        self.workspace = resolvedWorkspaces.first { $0.id == selectedID } ?? resolvedWorkspaces[0]
        self.theme = theme
        self.appearance = appearance
        self.notifications = notifications
        self.agentCLIStatuses = Dictionary(uniqueKeysWithValues: AgentHookProvider.allCases.map { ($0, .unknown(provider: $0)) })
        self.terminalFontDownloadStates = [:]
        self.sidebarVisible = sidebarVisible
        self.commandPaletteVisible = commandPaletteVisible
        self.notificationPanelVisible = notificationPanelVisible
        self.settingsPanelVisible = settingsPanelVisible
        self.workspaceOverviewVisible = workspaceOverviewVisible
        ConductorAppearanceRuntime.apply(self.appearance)
        TerminalAppearanceRuntime.apply(self.appearance)
        ConductorMotion.setReducedMotion(self.appearance.reducedMotion)
    }
    #endif

    var canSplit: Bool {
        workspace.canSplit()
    }

    var canCloseFocusedPane: Bool {
        workspace.canClosePane(workspace.focusedPaneID)
    }

    var canMoveSelectedTabLeft: Bool {
        workspace.canMoveSelectedTab(offset: -1)
    }

    var canMoveSelectedTabRight: Bool {
        workspace.canMoveSelectedTab(offset: 1)
    }

    var canMoveSelectedTabToNextPane: Bool {
        workspace.canMoveSelectedTabToNextPane()
    }

    var canMoveSelectedTabToNewSplit: Bool {
        workspace.canMoveSelectedTabToNewSplit()
    }

    func canMoveTabToNewSplit(_ tabID: TerminalID) -> Bool {
        workspace.canMoveTabToNewSplit(tabID)
    }

    func canMoveTabToSplit(_ tabID: TerminalID, targetPaneID: PaneID) -> Bool {
        workspace.canMoveTabToSplit(tabID, targetPaneID: targetPaneID)
    }

    func cycleTheme() {
        theme = theme.next
    }

    func setAppearanceDensity(_ density: AppearanceDensity) {
        guard appearance.density != density else { return }
        appearance.density = density
    }

    func setChromeClarity(_ chromeClarity: ChromeClarity) {
        guard appearance.chromeClarity != chromeClarity else { return }
        appearance.chromeClarity = chromeClarity
    }

    func setFontScale(_ fontScale: AppearanceFontScale) {
        guard appearance.fontScale != fontScale else { return }
        appearance.fontScale = fontScale
    }

    func setLanguage(_ language: AppearanceLanguage) {
        guard appearance.language != language else { return }
        appearance.language = language
    }

    func setFontFamily(_ fontFamily: AppearanceFontFamily) {
        guard appearance.fontFamily != fontFamily else { return }
        appearance.fontFamily = fontFamily
    }

    func setTerminalFontSize(_ terminalFontSize: CGFloat) {
        let clamped = AppearancePreferences.clampedTerminalFontSize(terminalFontSize)
        let rounded = (clamped * 2).rounded() / 2
        guard appearance.terminalFontSize != rounded else { return }
        appearance.terminalFontSize = rounded
    }

    func setTerminalFontPreset(_ preset: TerminalFontPreset) {
        guard appearance.terminalRenderer.fontPreset != preset || appearance.terminalRenderer.useCustomFont else { return }
        appearance.terminalRenderer.fontPreset = preset
        appearance.terminalRenderer.useCustomFont = false
    }

    func openTerminalFontDownload(_ preset: TerminalFontPreset) {
        guard let url = preset.downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    func downloadTerminalFont(_ preset: TerminalFontPreset) {
        guard terminalFontDownloadStates[preset]?.isDownloading != true else { return }
        guard preset.directDownloadURL != nil else {
            openTerminalFontDownload(preset)
            return
        }
        terminalFontDownloadStates[preset] = .downloading
        Task {
            do {
                let result = try await TerminalFontLibrary.downloadAndRegisterPreset(preset)
                TerminalFontAvailability.refresh()
                terminalFontDownloadStates[preset] = .installed(result.familyName)
                appearance.terminalRenderer.fontPreset = result.preset
                appearance.terminalRenderer.useCustomFont = false
            } catch {
                terminalFontDownloadStates[preset] = .failed(error.localizedDescription)
            }
        }
    }

    func setTerminalUseCustomFont(_ useCustomFont: Bool) {
        let hasCustomFont = appearance.terminalRenderer.customFontFamilyName?.isEmpty == false
        let resolved = useCustomFont && hasCustomFont
        guard appearance.terminalRenderer.useCustomFont != resolved else { return }
        if resolved {
            TerminalFontLibrary.registerCustomFontIfNeeded(
                path: appearance.terminalRenderer.customFontFilePath,
                bookmarkData: appearance.terminalRenderer.customFontBookmarkData
            )
        }
        appearance.terminalRenderer.useCustomFont = resolved
    }

    func importTerminalFont() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["ttf", "otf", "ttc"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = L("选择一个 .ttf、.otf 或 .ttc 字体文件", "Choose a .ttf, .otf, or .ttc font file")
        guard panel.runModal() == .OK,
              let url = panel.url,
              TerminalFontLibrary.registerCustomFontIfNeeded(path: url.path),
              let familyName = TerminalFontLibrary.familyName(in: url) else {
            return
        }
        appearance.terminalRenderer.customFontFilePath = url.path
        appearance.terminalRenderer.customFontBookmarkData = TerminalFontLibrary.bookmarkData(for: url)
        appearance.terminalRenderer.customFontFamilyName = familyName
        appearance.terminalRenderer.useCustomFont = true
    }

    func setTerminalLineHeight(_ lineHeight: CGFloat) {
        let rounded = (min(max(lineHeight, 0.80), 1.50) * 100).rounded() / 100
        guard appearance.terminalRenderer.lineHeight != rounded else { return }
        appearance.terminalRenderer.lineHeight = rounded
    }

    func setTerminalBackgroundOpacity(_ opacity: CGFloat) {
        let rounded = (min(max(opacity, 0.20), 1.0) * 100).rounded() / 100
        guard appearance.terminalRenderer.backgroundOpacity != rounded else { return }
        appearance.terminalRenderer.backgroundOpacity = rounded
    }

    func setTerminalCursorStyle(_ style: TerminalCursorStyle) {
        guard appearance.terminalRenderer.cursorStyle != style else { return }
        appearance.terminalRenderer.cursorStyle = style
    }

    func setTerminalCursorBlink(_ blink: Bool) {
        guard appearance.terminalRenderer.cursorBlink != blink else { return }
        appearance.terminalRenderer.cursorBlink = blink
    }

    func setTerminalShellIntegrationEnabled(_ enabled: Bool) {
        _ = enabled
        guard appearance.terminalRenderer.shellIntegrationEnabled != true else { return }
        appearance.terminalRenderer.shellIntegrationEnabled = true
    }

    func resetTerminalRendererPreferences() {
        let currentProxy = appearance.terminalRenderer.proxy
        let defaults = TerminalRendererPreferences(proxy: currentProxy)
        guard appearance.terminalRenderer != defaults else { return }
        appearance.terminalRenderer = defaults
    }

    func setTerminalProxyEnabled(_ enabled: Bool) {
        guard appearance.terminalRenderer.proxy.enabled != enabled else { return }
        appearance.terminalRenderer.proxy.enabled = enabled
    }

    func setTerminalProxyHTTP(_ value: String) {
        guard appearance.terminalRenderer.proxy.httpProxy != value else { return }
        appearance.terminalRenderer.proxy.httpProxy = value
    }

    func setTerminalProxyHTTPS(_ value: String) {
        guard appearance.terminalRenderer.proxy.httpsProxy != value else { return }
        appearance.terminalRenderer.proxy.httpsProxy = value
    }

    func setTerminalProxyAll(_ value: String) {
        guard appearance.terminalRenderer.proxy.allProxy != value else { return }
        appearance.terminalRenderer.proxy.allProxy = value
    }

    func setTerminalProxyNoProxy(_ value: String) {
        guard appearance.terminalRenderer.proxy.noProxy != value else { return }
        appearance.terminalRenderer.proxy.noProxy = value
    }

    func setGhosttyOverrideValue(key: String, value: String) {
        guard TerminalGhosttyConfigCatalog.knownKeySet.contains(key) else { return }
        var overrides = appearance.terminalRenderer.ghosttyOverrides
        if let index = overrides.firstIndex(where: { $0.key == key }) {
            guard overrides[index].value != value else { return }
            overrides[index].value = value
        } else {
            overrides.append(TerminalGhosttyConfigOverride(key: key, value: value, enabled: false))
        }
        appearance.terminalRenderer.ghosttyOverrides = TerminalRendererPreferences.normalizedOverrides(overrides)
    }

    func setGhosttyOverrideEnabled(key: String, enabled: Bool) {
        guard TerminalGhosttyConfigCatalog.knownKeySet.contains(key) else { return }
        var overrides = appearance.terminalRenderer.ghosttyOverrides
        if let index = overrides.firstIndex(where: { $0.key == key }) {
            guard overrides[index].enabled != enabled else { return }
            overrides[index].enabled = enabled
        } else {
            overrides.append(TerminalGhosttyConfigOverride(key: key, enabled: enabled))
        }
        appearance.terminalRenderer.ghosttyOverrides = TerminalRendererPreferences.normalizedOverrides(overrides)
    }

    func resetGhosttyOverrides() {
        guard !appearance.terminalRenderer.ghosttyOverrides.isEmpty else { return }
        appearance.terminalRenderer.ghosttyOverrides = []
    }

    func setReducedMotion(_ reducedMotion: Bool) {
        guard appearance.reducedMotion != reducedMotion else { return }
        appearance.reducedMotion = reducedMotion
    }

    func setAgentNotificationsEnabled(_ enabled: Bool, for provider: AgentHookProvider) {
        if enabled {
            do {
                let bridgePath = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "Conductor"
                agentHookSettingsMessage = try AgentNotificationHookInstaller.install(provider: provider, bridgePath: bridgePath)
            } catch {
                agentHookSettingsMessage = error.localizedDescription
                return
            }
        } else {
            agentHookSettingsMessage = "\(provider.title) \(L("通知已关闭", "notifications disabled"))"
        }

        var next = appearance.agentNotifications
        next.setEnabled(enabled, for: provider)
        guard next != appearance.agentNotifications else { return }
        appearance.agentNotifications = next
    }

    func refreshAgentCLIStatuses() {
        agentCLIStatuses = AgentCLIStatusDetector.checkingStatuses()
        Task.detached(priority: .utility) {
            let statuses = AgentCLIStatusDetector.detectAll()
            await MainActor.run {
                self.agentCLIStatuses = statuses
            }
        }
    }

    func openAgentInstallPage(_ provider: AgentHookProvider) {
        guard let url = provider.installURL else { return }
        NSWorkspace.shared.open(url)
    }

    func shellAnimation(_ animation: Animation?) -> Animation? {
        appearance.reducedMotion ? nil : animation
    }

    func performShellMotion(_ animation: Animation? = ConductorMotion.standard, _ action: () -> Void) {
        guard !appearance.reducedMotion else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, action)
            return
        }
        ConductorMotion.perform(animation, action)
    }

    func beginTerminalTabDrag(_ terminalID: TerminalID) {
        terminalTabDragGeneration &+= 1
        let generation = terminalTabDragGeneration
        activeTerminalTabDragID = terminalID
        if !terminalTabDropTargetByPaneID.isEmpty {
            terminalTabDropTargetByPaneID.removeAll()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self,
                  self.terminalTabDragGeneration == generation else {
                return
            }
            self.activeTerminalTabDragID = nil
            if !self.terminalTabDropTargetByPaneID.isEmpty {
                self.terminalTabDropTargetByPaneID.removeAll()
            }
        }
    }

    func endTerminalTabDrag() {
        terminalTabDragGeneration &+= 1
        activeTerminalTabDragID = nil
        if !terminalTabDropTargetByPaneID.isEmpty {
            terminalTabDropTargetByPaneID.removeAll()
        }
    }

    func hasActiveTerminalTabDrag() -> Bool {
        activeTerminalTabDragID != nil
    }

    func isTerminalTabDragging(_ terminalID: TerminalID) -> Bool {
        activeTerminalTabDragID == terminalID
    }

    func setTerminalTabDropTarget(for terminalID: TerminalID, target: TerminalTabDropTarget?) {
        guard let paneID = workspace.paneID(containing: terminalID) else { return }
        if let target {
            guard terminalTabDropTargetByPaneID[paneID] != target else { return }
            terminalTabDropTargetByPaneID[paneID] = target
        } else {
            guard terminalTabDropTargetByPaneID[paneID] != nil else { return }
            terminalTabDropTargetByPaneID.removeValue(forKey: paneID)
        }
    }

    func canPerformCommand(_ command: ConductorShellCommand) -> Bool {
        command.canPerform(model: self)
    }

    @discardableResult
    func performCommand(_ command: ConductorShellCommand, window: NSWindow? = nil) -> Bool {
        ConductorLog.performance.debug("shell command \(command.rawValue, privacy: .public)")
        ConductorDiagnostics.record(
            "shell-command",
            fields: [
                "name": command.rawValue,
                "panes": workspace.panes.count,
                "tabs": workspace.panes.values.reduce(0) { $0 + $1.tabs.count },
                "zoomed": workspace.isZoomed
            ]
        )
        let signpost = ConductorSignpost.begin("shell-command")
        defer { ConductorSignpost.end("shell-command", signpost) }
        let commandSignpost = ConductorSignpost.begin(command.signpostName)
        defer { ConductorSignpost.end(command.signpostName, commandSignpost) }
        let performed = command.perform(model: self, window: window)
        ConductorDiagnostics.record(
            "shell-command-result",
            fields: [
                "name": command.rawValue,
                "performed": performed,
                "panes": workspace.panes.count,
                "tabs": workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
            ]
        )
        return performed
    }

    var runtimeSurfaceCount: Int {
        surfaces.count
    }

    var runtimeMetadataCount: Int {
        metadataByTerminalID.count + pendingMetadataByTerminalID.count
    }

    var focusedTerminalID: TerminalID? {
        workspace.focusedPane?.selectedTabID
    }

    var focusedWorkingDirectoryURL: URL? {
        focusedTerminalID.flatMap { workingDirectoryURL(for: $0) }
    }

    private func workingDirectoryURL(for terminalID: TerminalID) -> URL? {
        guard let path = focusedWorkingDirectoryPath(for: terminalID) else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }

    var focusedTerminalSearchMetadata: TerminalSearchMetadata {
        guard let terminalID = terminalSearchTargetID ?? focusedTerminalID else {
            return TerminalSearchMetadata()
        }
        return metadata(for: terminalID).search
    }

    var terminalSearchTargets: [TerminalSearchTargetDisplay] {
        let leafPaneIDs = workspace.root.leaves.filter { workspace.panes[$0] != nil }
        let remainingPaneIDs = workspace.panes.keys
            .filter { !leafPaneIDs.contains($0) }
            .sorted { $0.description < $1.description }
        let paneIDs = leafPaneIDs + remainingPaneIDs

        return paneIDs.enumerated().flatMap { paneIndex, paneID in
            guard let pane = workspace.panes[paneID] else {
                return [TerminalSearchTargetDisplay]()
            }
            return pane.tabs.enumerated().map { tabIndex, tab in
                let subtitle: String
                if pane.tabs.count > 1 {
                    subtitle = L("分屏 \(paneIndex + 1) · 终端 \(tabIndex + 1)", "Pane \(paneIndex + 1) · Terminal \(tabIndex + 1)")
                } else {
                    subtitle = L("分屏 \(paneIndex + 1)", "Pane \(paneIndex + 1)")
                }
                return TerminalSearchTargetDisplay(
                    id: tab.id,
                    title: tab.title,
                    subtitle: subtitle,
                    isActive: tab.id == focusedTerminalID
                )
            }
        }
    }

    func runtimeHasSurface(for terminalID: TerminalID) -> Bool {
        surfaces[terminalID] != nil
    }

    func surface(for tab: TerminalTabState) -> TerminalSurface {
        if let surface = surfaces[tab.id] {
            return surface
        }
        ConductorLog.performance.debug("surface create requested terminal=\(tab.id.description, privacy: .public) activeBefore=\(self.surfaces.count, privacy: .public)")
        let surface = TerminalSurface(
            id: tab.id,
            theme: theme,
            terminalFontSize: appearance.terminalFontSize,
            workingDirectory: tab.workingDirectory
        )
        surface.onFocusRequest = { [weak self] terminalID in
            self?.focusTerminal(terminalID)
        }
        surface.onUserActivity = { [weak self] terminalID in
            self?.recordTerminalUserActivity(terminalID)
        }
        surface.onContextMenuRequest = { [weak self] terminalID, event, view in
            self?.showTerminalContextMenu(terminalID: terminalID, event: event, in: view) ?? false
        }
        surface.hasActiveTerminalTabDrag = { [weak self] in
            self?.hasActiveTerminalTabDrag() ?? false
        }
        surface.onTerminalTabDropTargetChange = { [weak self] targetTerminalID, target in
            self?.setTerminalTabDropTarget(for: targetTerminalID, target: target)
        }
        surface.onTerminalTabDropRequest = { [weak self] targetTerminalID, draggedTerminalID, target in
            guard let self,
                  let targetPaneID = self.workspace.paneID(containing: targetTerminalID) else {
                return false
            }
            self.terminalTabDropTargetByPaneID.removeValue(forKey: targetPaneID)
            ConductorMotion.perform(ConductorMotion.layout) {
                if target == .center {
                    guard self.workspace.paneID(containing: draggedTerminalID) != targetPaneID else { return }
                    self.moveTabToEnd(draggedTerminalID, in: targetPaneID)
                } else {
                    self.moveTabToSplit(draggedTerminalID, targetPaneID: targetPaneID, direction: target.direction)
                }
            }
            self.endTerminalTabDrag()
            return true
        }
        surfaces[tab.id] = surface
        return surface
    }

    func newTerminal() {
        let signpost = ConductorSignpost.begin("new-terminal")
        defer { ConductorSignpost.end("new-terminal", signpost) }
        let terminalID = workspace.newTerminal(title: nextTerminalTitle(prefix: "zsh"))
        markTerminalInteractionFocus()
        selectedWorkspaceContentTabID = .terminal(terminalID)
    }

    func newTerminalAtFocusedDirectory() {
        let signpost = ConductorSignpost.begin("new-terminal-current-directory")
        defer { ConductorSignpost.end("new-terminal-current-directory", signpost) }
        let terminalID = workspace.newTerminal(
            title: nextTerminalTitle(prefix: "zsh"),
            workingDirectory: focusedWorkingDirectoryURL?.path
        )
        markTerminalInteractionFocus()
        selectedWorkspaceContentTabID = .terminal(terminalID)
    }

    private func newTerminalAtDirectory(for terminalID: TerminalID) {
        let signpost = ConductorSignpost.begin("new-terminal-context-directory")
        defer { ConductorSignpost.end("new-terminal-context-directory", signpost) }
        guard activateTerminalContextTarget(terminalID) != nil else { return }
        let newTerminalID = workspace.newTerminal(
            title: nextTerminalTitle(prefix: "zsh"),
            workingDirectory: workingDirectoryURL(for: terminalID)?.path
        )
        markTerminalInteractionFocus()
        selectedWorkspaceContentTabID = .terminal(newTerminalID)
    }

    func openFocusedDirectory() {
        guard let url = focusedWorkingDirectoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    func toggleFileManagerPanel() {
        if fileManagerPanelRequest != nil {
            closeFileManagerPanel()
            return
        }
        showFileManagerForFocusedDirectory()
    }

    func showFileManagerForFocusedDirectory() {
        guard let url = focusedWorkingDirectoryURL else { return }
        showFileManager(rootURL: url)
    }

    @discardableResult
    func showFileManager(for terminalID: TerminalID) -> Bool {
        guard activateTerminalContextTarget(terminalID) != nil,
              let url = workingDirectoryURL(for: terminalID) else {
            return false
        }
        showFileManager(rootURL: url)
        return true
    }

    func closeFileManagerPanel() {
        fileManagerPanelRequest = nil
        fileManagerKeyboardFocused = false
    }

    func setFileManagerKeyboardFocused(_ focused: Bool) {
        guard fileManagerKeyboardFocused != focused else { return }
        fileManagerKeyboardFocused = focused
    }

    func openFileInWorkspace(_ fileURL: URL, rootURL: URL? = nil) {
        let standardizedFile = fileURL.standardizedFileURL
        let resolvedRoot = (rootURL ?? standardizedFile.deletingLastPathComponent()).standardizedFileURL
        let tab = ConductorWorkspaceFileTab(fileURL: standardizedFile, rootURL: resolvedRoot)
        workspaceFileTabs = [tab]
        pruneWorkspaceFileTabState(keeping: Set([tab.id]))
        selectedWorkspaceContentTabID = .file(tab.id)
        terminalSearchVisible = false
        workspaceOverviewVisible = false
    }

    func selectWorkspaceFileTab(_ tabID: String) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        selectedWorkspaceContentTabID = .file(tabID)
        terminalSearchVisible = false
        workspaceOverviewVisible = false
    }

    func closeWorkspaceFileTab(_ tab: ConductorWorkspaceFileTab) {
        guard workspaceFileTabs.contains(where: { $0.id == tab.id }) else { return }
        guard isWorkspaceFileTabDirty(tab.id) else {
            closeWorkspaceFileTabWithoutConfirmation(tab)
            return
        }

        let alert = NSAlert()
        alert.messageText = L("保存对 \(tab.title) 的更改？", "Save changes to \(tab.title)?")
        alert.informativeText = L("如果不保存，最近的编辑会丢失。", "If you do not save, recent edits will be lost.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("保存", "Save"))
        alert.addButton(withTitle: L("不保存", "Don't Save"))
        alert.addButton(withTitle: L("取消", "Cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            requestSaveAndCloseWorkspaceFileTab(tab)
        case .alertSecondButtonReturn:
            closeWorkspaceFileTabWithoutConfirmation(tab)
        default:
            break
        }
    }

    @discardableResult
    func closeWorkspaceFileTabAfterSaving(tabID: String) -> Bool {
        guard let tab = workspaceFileTabs.first(where: { $0.id == tabID }) else { return false }
        closeWorkspaceFileTabWithoutConfirmation(tab)
        return true
    }

    func closeWorkspaceFileTabs(matchingDeletedPaths deletedPaths: Set<String>) {
        guard !deletedPaths.isEmpty else { return }
        let standardizedPaths = Set(deletedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let tabsToClose = workspaceFileTabs.filter { tab in
            let path = tab.fileURL.standardizedFileURL.path
            return standardizedPaths.contains { deletedPath in
                path == deletedPath || path.hasPrefix(deletedPath + "/")
            }
        }
        for tab in tabsToClose {
            closeWorkspaceFileTabWithoutConfirmation(tab)
        }
    }

    func updateWorkspaceFileTabs(moving oldPath: String, to newURL: URL, isDirectory: Bool) {
        let oldPath = URL(fileURLWithPath: oldPath).standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        guard oldPath != newPath else { return }

        var dirtyIDs = dirtyWorkspaceFileTabIDs
        var externalIDs = externallyChangedWorkspaceFileTabIDs
        var saveTokens = workspaceFileEditorSaveRequestTokensByTabID
        var saveAndCloseTokens = workspaceFileEditorSaveAndCloseRequestTokensByTabID
        var movedSelectedFileTabID: String?

        workspaceFileTabs = workspaceFileTabs.map { tab in
            let filePath = tab.fileURL.standardizedFileURL.path
            guard filePath == oldPath || (isDirectory && filePath.hasPrefix(oldPath + "/")) else {
                return tab
            }

            let suffix = filePath == oldPath ? "" : String(filePath.dropFirst(oldPath.count))
            let movedFileURL = suffix.isEmpty ? newURL.standardizedFileURL : URL(fileURLWithPath: newPath + suffix).standardizedFileURL
            let movedRootURL = movedRootURL(for: tab.rootURL, oldPath: oldPath, newPath: newPath, isDirectory: isDirectory)
            let movedTab = ConductorWorkspaceFileTab(fileURL: movedFileURL, rootURL: movedRootURL)

            moveWorkspaceFileTabState(
                from: tab.id,
                to: movedTab.id,
                dirtyIDs: &dirtyIDs,
                externalIDs: &externalIDs,
                saveTokens: &saveTokens,
                saveAndCloseTokens: &saveAndCloseTokens
            )
            if selectedWorkspaceFileTabID == tab.id {
                movedSelectedFileTabID = movedTab.id
            }
            return movedTab
        }

        if let movedSelectedFileTabID {
            selectedWorkspaceContentTabID = .file(movedSelectedFileTabID)
        }
        dirtyWorkspaceFileTabIDs = dirtyIDs
        externallyChangedWorkspaceFileTabIDs = externalIDs
        workspaceFileEditorSaveRequestTokensByTabID = saveTokens
        workspaceFileEditorSaveAndCloseRequestTokensByTabID = saveAndCloseTokens
    }

    func setWorkspaceFileTabDirty(_ tabID: String, isDirty: Bool) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        if isDirty {
            dirtyWorkspaceFileTabIDs.insert(tabID)
        } else {
            dirtyWorkspaceFileTabIDs.remove(tabID)
        }
    }

    func isWorkspaceFileTabDirty(_ tabID: String) -> Bool {
        dirtyWorkspaceFileTabIDs.contains(tabID)
    }

    func setWorkspaceFileTabExternallyChanged(_ tabID: String, changed: Bool) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        if changed {
            externallyChangedWorkspaceFileTabIDs.insert(tabID)
        } else {
            externallyChangedWorkspaceFileTabIDs.remove(tabID)
        }
    }

    func isWorkspaceFileTabExternallyChanged(_ tabID: String) -> Bool {
        externallyChangedWorkspaceFileTabIDs.contains(tabID)
    }

    func workspaceFileEditorSaveRequestToken(for tabID: String) -> Int {
        workspaceFileEditorSaveRequestTokensByTabID[tabID] ?? 0
    }

    func workspaceFileEditorSaveAndCloseRequestToken(for tabID: String) -> Int {
        workspaceFileEditorSaveAndCloseRequestTokensByTabID[tabID] ?? 0
    }

    @discardableResult
    func requestSaveWorkspaceFileTab(_ tab: ConductorWorkspaceFileTab) -> Bool {
        guard workspaceFileTabs.contains(where: { $0.id == tab.id }) else { return false }
        workspaceFileEditorSaveRequestTokensByTabID[tab.id, default: 0] += 1
        return true
    }

    private func requestSaveAndCloseWorkspaceFileTab(_ tab: ConductorWorkspaceFileTab) {
        guard workspaceFileTabs.contains(where: { $0.id == tab.id }) else { return }
        selectedWorkspaceContentTabID = .file(tab.id)
        workspaceFileEditorSaveAndCloseRequestTokensByTabID[tab.id, default: 0] += 1
    }

    private func closeWorkspaceFileTabWithoutConfirmation(_ tab: ConductorWorkspaceFileTab) {
        guard let index = workspaceFileTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        workspaceFileTabs.remove(at: index)
        dirtyWorkspaceFileTabIDs.remove(tab.id)
        externallyChangedWorkspaceFileTabIDs.remove(tab.id)
        workspaceFileEditorSaveRequestTokensByTabID.removeValue(forKey: tab.id)
        workspaceFileEditorSaveAndCloseRequestTokensByTabID.removeValue(forKey: tab.id)
        if selectedWorkspaceFileTabID == tab.id {
            if workspaceFileTabs.isEmpty {
                selectedWorkspaceContentTabID = focusedTerminalID.map { .terminal($0) }
            } else {
                selectedWorkspaceContentTabID = .file(workspaceFileTabs[min(index, workspaceFileTabs.count - 1)].id)
            }
        }
    }

    private func pruneWorkspaceFileTabState(keeping retainedIDs: Set<String>) {
        dirtyWorkspaceFileTabIDs.formIntersection(retainedIDs)
        externallyChangedWorkspaceFileTabIDs.formIntersection(retainedIDs)
        workspaceFileEditorSaveRequestTokensByTabID = workspaceFileEditorSaveRequestTokensByTabID.filter { retainedIDs.contains($0.key) }
        workspaceFileEditorSaveAndCloseRequestTokensByTabID = workspaceFileEditorSaveAndCloseRequestTokensByTabID.filter { retainedIDs.contains($0.key) }
    }

    private func movedRootURL(for rootURL: URL, oldPath: String, newPath: String, isDirectory: Bool) -> URL {
        guard isDirectory else { return rootURL }
        let rootPath = rootURL.standardizedFileURL.path
        guard rootPath == oldPath || rootPath.hasPrefix(oldPath + "/") else { return rootURL }
        let suffix = rootPath == oldPath ? "" : String(rootPath.dropFirst(oldPath.count))
        return URL(fileURLWithPath: newPath + suffix).standardizedFileURL
    }

    private func moveWorkspaceFileTabState(
        from oldID: String,
        to newID: String,
        dirtyIDs: inout Set<String>,
        externalIDs: inout Set<String>,
        saveTokens: inout [String: Int],
        saveAndCloseTokens: inout [String: Int]
    ) {
        guard oldID != newID else { return }
        if dirtyIDs.remove(oldID) != nil {
            dirtyIDs.insert(newID)
        }
        if externalIDs.remove(oldID) != nil {
            externalIDs.insert(newID)
        }
        if let token = saveTokens.removeValue(forKey: oldID) {
            saveTokens[newID] = token
        }
        if let token = saveAndCloseTokens.removeValue(forKey: oldID) {
            saveAndCloseTokens[newID] = token
        }
    }

    func selectTerminalStage() {
        if let tab = workspace.focusedPane?.selectedTab {
            markTerminalInteractionFocus()
            selectedWorkspaceContentTabID = .terminal(tab.id)
            focusTerminal(tab.id)
        }
    }

    func selectWorkspaceTerminalTab(_ terminalID: TerminalID) {
        guard workspace.paneID(containing: terminalID) != nil else { return }
        markTerminalInteractionFocus()
        selectedWorkspaceContentTabID = .terminal(terminalID)
        terminalSearchVisible = false
        workspaceOverviewVisible = false
        focusTerminal(terminalID)
    }

    @discardableResult
    func insertPathIntoFocusedTerminal(_ url: URL) -> Bool {
        guard let tab = workspace.focusedPane?.selectedTab else { return false }
        return insertTextIntoTerminal(Self.shellEscapedText(url.standardizedFileURL.path) + " ", terminalID: tab.id)
    }

    @discardableResult
    func insertPathIntoTerminal(_ url: URL, terminalID: TerminalID) -> Bool {
        insertTextIntoTerminal(Self.shellEscapedText(url.standardizedFileURL.path) + " ", terminalID: terminalID)
    }

    @discardableResult
    func insertShellCommandForFocusedTerminal(_ command: String) -> Bool {
        guard let tab = workspace.focusedPane?.selectedTab else { return false }
        return insertTextIntoTerminal(command, terminalID: tab.id)
    }

    @discardableResult
    func insertCDCommandIntoFocusedTerminal(_ url: URL) -> Bool {
        let targetURL: URL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            targetURL = url
        } else {
            targetURL = url.deletingLastPathComponent()
        }
        return insertShellCommandForFocusedTerminal("cd \(Self.shellEscapedText(targetURL.standardizedFileURL.path))")
    }

    @discardableResult
    func insertListCommandIntoFocusedTerminal(_ url: URL) -> Bool {
        insertShellCommandForFocusedTerminal("ls -lah \(Self.shellEscapedText(url.standardizedFileURL.path))")
    }

    @discardableResult
    private func insertTextIntoTerminal(_ text: String, terminalID: TerminalID) -> Bool {
        guard let target = terminalContextMenuTarget(for: terminalID) else { return false }
        focusTerminal(target.tab.id)
        surface(for: target.tab).sendText(text)
        refreshSurfaceAfterNavigation(target.tab.id)
        return true
    }

    private func showFileManager(rootURL: URL, selectedURL: URL? = nil) {
        let standardizedRoot = rootURL.standardizedFileURL
        fileManagerPanelRequest = FileManagerPanelRequest(rootURL: standardizedRoot, selectedURL: selectedURL)
    }

    private func openWorkingDirectory(for terminalID: TerminalID) {
        guard let url = workingDirectoryURL(for: terminalID) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyFocusedDirectory() {
        guard let path = focusedWorkingDirectoryURL?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    private func copyWorkingDirectory(for terminalID: TerminalID) {
        guard let path = workingDirectoryURL(for: terminalID)?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func ghosttyRuntimeDidRequestOpenURL(terminalID: TerminalID?, url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return openLocalFileURLFromTerminal(terminalID: terminalID, url: url)
    }

    func splitRight() {
        let signpost = ConductorSignpost.begin("split-right")
        defer { ConductorSignpost.end("split-right", signpost) }
        performWorkspaceEdgeSplit(.right)
    }

    func splitDown() {
        let signpost = ConductorSignpost.begin("split-down")
        defer { ConductorSignpost.end("split-down", signpost) }
        performWorkspaceEdgeSplit(.down)
    }

    func ghosttyRuntimeDidRequestNewTab(terminalID: TerminalID) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        workspace.newTerminal(title: nextTerminalTitle(prefix: "zsh"))
        return true
    }

    func ghosttyRuntimeDidRequestMoveTab(terminalID: TerminalID, amount: Int) -> Bool {
        guard amount != 0,
              let paneID = workspace.paneID(containing: terminalID),
              workspace.selectTab(terminalID, in: paneID) else {
            return false
        }
        return workspace.moveSelectedTab(offset: amount, in: paneID)
    }

    func ghosttyRuntimeDidRequestSelectTab(terminalID: TerminalID, offset: Int?, last: Bool) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID),
              let pane = workspace.panes[paneID],
              workspace.selectTab(terminalID, in: paneID) else {
            return false
        }

        if last, let lastTabID = pane.tabs.last?.id {
            let didSelect = workspace.selectTab(lastTabID, in: paneID)
            if didSelect {
                markTerminalNotificationsRead(lastTabID)
                reconcileSurfaceFocus()
            }
            return didSelect
        }

        if let offset {
            if offset > 0, offset <= pane.tabs.count {
                let targetID = pane.tabs[offset - 1].id
                let didSelect = workspace.selectTab(targetID, in: paneID)
                if didSelect {
                    markTerminalNotificationsRead(targetID)
                    reconcileSurfaceFocus()
                }
                return didSelect
            }
            if let selectedID = workspace.selectAdjacentTab(offset: offset, in: paneID) {
                markTerminalNotificationsRead(selectedID)
                reconcileSurfaceFocus()
                return true
            }
            return false
        }

        return false
    }

    func ghosttyRuntimeDidRequestCommandPalette(terminalID: TerminalID) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        toggleCommandPalette()
        return true
    }

    func ghosttyRuntimeDidRequestSplit(terminalID: TerminalID, direction: SplitDirection) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        return performWorkspaceEdgeSplit(direction) != nil
    }

    func ghosttyRuntimeDidRequestFocus(terminalID: TerminalID, direction: FocusDirection) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        let didFocus = workspace.focusAdjacentPane(direction) != nil
        if didFocus {
            reconcileSurfaceFocus()
        }
        return didFocus
    }

    func ghosttyRuntimeDidRequestResize(terminalID: TerminalID, direction: ResizeSplitDirection, amount: UInt16) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        workspace.resizeFocusedSplit(direction: direction, amount: Double(amount))
        return true
    }

    func ghosttyRuntimeDidRequestEqualize(terminalID: TerminalID) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        workspace.equalizeSplits()
        return true
    }

    func ghosttyRuntimeDidRequestToggleZoom(terminalID: TerminalID) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        workspace.toggleZoom()
        return true
    }

    func ghosttyRuntimeDidSetTitle(terminalID: TerminalID, title: String) -> Bool {
        updateWorkspace(containing: terminalID) { workspace in
            workspace.updateTerminalTitle(terminalID, title: title)
        }
    }

    func ghosttyRuntimeDidSetWorkingDirectory(terminalID: TerminalID, workingDirectory: String) -> Bool {
        let updated = updateWorkspace(containing: terminalID) { workspace in
            workspace.updateTerminalWorkingDirectory(terminalID, workingDirectory: workingDirectory)
        }
        updateMetadata(for: terminalID) { metadata in
            metadata.workingDirectory = workingDirectory
        }
        return updated
    }

    func ghosttyRuntimeDidReceiveNotification(terminalID: TerminalID, title: String, body: String) -> Bool {
        recordTerminalNotification(terminalID: terminalID, title: title, body: body, kind: .notification)
    }

    func ghosttyRuntimeDidRingBell(terminalID: TerminalID) -> Bool {
        recordTerminalNotification(terminalID: terminalID, title: "Bell", body: "", kind: .bell)
    }

    func ghosttyRuntimeDidUpdateProgress(terminalID: TerminalID, kind: TerminalProgressKind, progress: Int?) -> Bool {
        updateMetadata(for: terminalID) { metadata in
            metadata.progressKind = kind == .removed ? nil : kind
            metadata.progressPercent = progress
        }
        return true
    }

    func ghosttyRuntimeDidFinishCommand(terminalID: TerminalID, exitCode: Int?, durationNanoseconds: UInt64) -> Bool {
        updateMetadata(for: terminalID) { metadata in
            metadata.lastCommandExitCode = exitCode
            metadata.lastCommandDurationNanoseconds = durationNanoseconds
            if metadata.progressKind != .error {
                metadata.progressKind = nil
                metadata.progressPercent = nil
            }
        }
        return true
    }

    func ghosttyRuntimeDidUpdateCellSize(terminalID: TerminalID, width: UInt32, height: UInt32) -> Bool {
        updateMetadata(for: terminalID) { metadata in
            metadata.cellWidth = width
            metadata.cellHeight = height
        }
        return true
    }

    func ghosttyRuntimeDidUpdateSearch(
        terminalID: TerminalID,
        active: Bool,
        needle: String?,
        total: Int?,
        selected: Int?
    ) -> Bool {
        updateMetadata(for: terminalID) { metadata in
            metadata.search.active = active
            if let needle {
                metadata.search.needle = String(needle.prefix(80))
            }
            if let total {
                metadata.search.total = total
            }
            if let selected {
                metadata.search.selected = selected
            }
            if !active {
                metadata.search = TerminalSearchMetadata()
            }
        }
        return true
    }

    func ghosttyRuntimeDidSetReadonly(terminalID: TerminalID, readonly: Bool) -> Bool {
        updateMetadata(for: terminalID) { metadata in
            metadata.readonly = readonly
        }
        return true
    }

    func ghosttyRuntimeDidRequestClose(terminalID: TerminalID) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        closeTab(terminalID, in: paneID)
        return true
    }

    func ghosttyRuntimeDidRequestCloseTabs(terminalID: TerminalID, scope: TabCloseScope) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID),
              workspace.selectTab(terminalID, in: paneID) else {
            return false
        }
        let result = workspace.closeTabs(scope: scope, in: paneID)
        closeSurfaces(for: result.closedTerminalIDs)
        return !result.closedTerminalIDs.isEmpty
    }

    func selectTab(_ terminalID: TerminalID, in paneID: PaneID) {
        let signpost = ConductorSignpost.begin("select-tab")
        defer { ConductorSignpost.end("select-tab", signpost) }
        guard let pane = workspace.panes[paneID],
              pane.tabs.contains(where: { $0.id == terminalID }) else {
            return
        }
        if pane.selectedTabID == terminalID, workspace.focusedPaneID == paneID {
            markTerminalInteractionFocus()
            markTerminalNotificationsRead(terminalID)
            return
        }
        markTerminalInteractionFocus()
        workspace.selectTab(terminalID, in: paneID)
        markTerminalNotificationsRead(terminalID)
        reconcileSurfaceFocus()
    }

    func focusPane(_ paneID: PaneID) {
        guard let pane = workspace.panes[paneID] else { return }
        if workspace.focusedPaneID == paneID {
            markTerminalInteractionFocus()
            markTerminalNotificationsRead(pane.selectedTabID)
            return
        }
        markTerminalInteractionFocus()
        workspace.focusPane(paneID)
        markTerminalNotificationsRead(pane.selectedTabID)
        reconcileSurfaceFocus()
    }

    func focusTerminal(_ terminalID: TerminalID) {
        let signpost = ConductorSignpost.begin("focus-terminal")
        defer { ConductorSignpost.end("focus-terminal", signpost) }
        if workspace.paneID(containing: terminalID) == nil,
           let workspaceID = workspaces.first(where: { $0.paneID(containing: terminalID) != nil })?.id {
            selectWorkspace(workspaceID)
        }
        guard let paneID = workspace.paneID(containing: terminalID) else { return }
        markTerminalInteractionFocus()
        markTerminalNotificationsRead(terminalID)
        if workspace.focusedPaneID == paneID,
           workspace.panes[paneID]?.selectedTabID == terminalID {
            return
        }
        workspace.focusPane(paneID)
        workspace.selectTab(terminalID, in: paneID)
        reconcileSurfaceFocus()
        refreshSurfaceAfterNavigation(terminalID)
    }

    func flashFocusedPane() {
        let paneID = workspace.focusedPaneID
        paneFlashTokens[paneID, default: 0] &+= 1
    }

    func showTerminalSearch() {
        if fileManagerPanelRequest != nil, fileManagerKeyboardFocused {
            commandPaletteVisible = false
            settingsPanelVisible = false
            workspaceOverviewVisible = false
            terminalSearchVisible = false
            fileManagerSearchFocusGeneration &+= 1
            return
        }
        if selectedWorkspaceFileTab != nil {
            commandPaletteVisible = false
            settingsPanelVisible = false
            workspaceOverviewVisible = false
            terminalSearchVisible = false
            workspaceFileSearchFocusGeneration &+= 1
            return
        }
        guard let terminalID = focusedTerminalID else { return }
        showTerminalSearch(for: terminalID)
    }

    func showTerminalSearch(for terminalID: TerminalID) {
        let signpost = ConductorSignpost.begin("terminal-search-show")
        defer { ConductorSignpost.end("terminal-search-show", signpost) }
        guard activateTerminalContextTarget(terminalID) != nil,
              let target = terminalSearchTarget(for: terminalID) else { return }
        commandPaletteVisible = false
        settingsPanelVisible = false
        workspaceOverviewVisible = false
        terminalSearchTargetID = terminalID
        terminalSearchQuery = metadata(for: terminalID).search.needle ?? ""
        terminalSearchVisible = true
        terminalSearchFocusGeneration &+= 1
        let surface = surface(for: target.tab)
        if !terminalSearchQuery.isEmpty {
            _ = surface.search(terminalSearchQuery)
        }
    }

    func selectTerminalSearchTarget(_ terminalID: TerminalID) {
        guard terminalSearchVisible,
              terminalSearchTargetID != terminalID,
              terminalSearchTarget(for: terminalID) != nil else { return }

        if let current = terminalSearchTargetTab() {
            _ = surface(for: current).endSearch()
        }

        terminalSearchTargetID = terminalID
        focusTerminal(terminalID)

        let query = terminalSearchQuery
        activateTerminalSearchSurface(terminalID: terminalID, query: query)
        Task { @MainActor [weak self] in
            self?.activateTerminalSearchSurface(terminalID: terminalID, query: query)
        }
    }

    func setTerminalSearchQuery(_ query: String) {
        guard terminalSearchQuery != query else { return }
        terminalSearchQuery = query
        applyTerminalSearchQuery(query)
    }

    func applyTerminalSearchQuery(_ query: String) {
        guard let tab = terminalSearchTargetTab() else { return }
        _ = surface(for: tab).search(query)
    }

    func navigateTerminalSearch(previous: Bool) {
        if selectedWorkspaceFileTab != nil {
            if previous {
                workspaceFileSearchPreviousGeneration &+= 1
            } else {
                workspaceFileSearchNextGeneration &+= 1
            }
            return
        }
        if fileManagerPanelRequest != nil {
            if previous {
                fileManagerSearchPreviousGeneration &+= 1
            } else {
                fileManagerSearchNextGeneration &+= 1
            }
            return
        }
        guard terminalSearchVisible,
              let tab = terminalSearchTargetTab() else { return }
        _ = surface(for: tab).navigateSearch(previous: previous)
    }

    func closeTerminalSearch() {
        let restoreTerminalID = terminalSearchTargetID ?? focusedTerminalID
        if terminalSearchVisible, let tab = terminalSearchTargetTab() {
            _ = surface(for: tab).endSearch()
        }
        terminalSearchVisible = false
        terminalSearchQuery = ""
        terminalSearchTargetID = nil
        if let restoreTerminalID {
            refreshSurfaceAfterNavigation(restoreTerminalID)
        }
    }

    @discardableResult
    func showTerminalContextMenu(terminalID: TerminalID, event: NSEvent, in view: NSView) -> Bool {
        guard let target = terminalContextMenuTarget(for: terminalID) else { return false }
        ConductorLog.performance.debug("context menu terminal=\(terminalID.description, privacy: .public) workspace=\(target.workspaceID.description, privacy: .public) pane=\(target.paneID.description, privacy: .public)")
        focusTerminal(terminalID)
        let targetDirectoryURL = workingDirectoryURL(for: terminalID)

        let menu = NSMenu(title: target.tab.title)
        menu.autoenablesItems = false
        let controller = TerminalContextMenuController()
        controller.onClose = { [weak self, weak controller] in
            DispatchQueue.main.async {
                guard let self, let controller else { return }
                if self.activeTerminalContextMenuController === controller {
                    self.activeTerminalContextMenuController = nil
                }
            }
        }
        menu.delegate = controller
        activeTerminalContextMenuController = controller

        let sourceWindow = view.window
        let targetWorkspaceID = target.workspaceID

        func addItem(
            _ title: String,
            enabled: Bool = true,
            action: TerminalContextMenuAction
        ) {
            let item = controller.makeItem(
                title: title,
                enabled: enabled,
                action: { [weak self] in
                    self?.performTerminalContextMenuAction(
                        action,
                        terminalID: terminalID,
                        workspaceID: targetWorkspaceID,
                        window: sourceWindow
                    )
                }
            )
            menu.addItem(item)
        }

        func addSeparator() {
            menu.addItem(.separator())
        }

        addItem(L("重命名当前终端...", "Rename Current Terminal..."), action: .renameTerminal)
        if target.tab.userTitle != nil {
            addItem(L("恢复终端标题", "Restore Terminal Title"), action: .restoreTerminalTitle)
        }
        addItem(L("复制当前终端", "Duplicate Current Terminal"), action: .duplicateTerminal)
        addItem(L("上下文搜索", "Context Search"), action: .showSearch)
        addItem(
            L("浏览当前目录", "Browse Current Directory"),
            enabled: targetDirectoryURL != nil,
            action: .showFileManager
        )
        addItem(
            L("打开当前目录", "Open Current Directory"),
            enabled: targetDirectoryURL != nil,
            action: .openDirectory
        )
        addItem(
            L("复制当前目录路径", "Copy Current Directory Path"),
            enabled: targetDirectoryURL != nil,
            action: .copyDirectory
        )

        addSeparator()

        addItem(L("新开终端", "New Terminal"), action: .newTerminal)
        addItem(
            L("从当前目录新开终端", "New Terminal at Current Directory"),
            enabled: targetDirectoryURL != nil,
            action: .newTerminalAtDirectory
        )
        addItem(L("向右分屏", "Split Right"), enabled: target.workspace.canSplit(), action: .splitRight)
        addItem(L("向下分屏", "Split Down"), enabled: target.workspace.canSplit(), action: .splitDown)
        addItem(
            L("关闭当前分屏", "Close Current Pane"),
            enabled: target.workspace.canClosePane(target.paneID),
            action: .closePane
        )

        addSeparator()

        addItem(L("关闭当前终端", "Close Current Terminal"), action: .closeTerminal)
        addItem(
            L("关闭其他终端", "Close Other Terminals"),
            enabled: target.workspace.canCloseOtherTabs(in: target.paneID),
            action: .closeOtherTerminals
        )
        addItem(
            L("关闭右侧终端", "Close Terminals to the Right"),
            enabled: target.workspace.canCloseTabsToRight(of: terminalID, in: target.paneID),
            action: .closeTerminalsToRight
        )

        addSeparator()

        addItem(L("重命名当前工作区...", "Rename Current Workspace..."), action: .renameWorkspace)
        addItem(L("复制当前工作区", "Duplicate Current Workspace"), action: .duplicateWorkspace)
        addItem(L("关闭当前工作区", "Close Current Workspace"), enabled: workspaces.count > 1, action: .closeWorkspace)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
        return true
    }

    @discardableResult
    private func performTerminalContextMenuAction(
        _ action: TerminalContextMenuAction,
        terminalID: TerminalID,
        workspaceID: WorkspaceID,
        window: NSWindow?
    ) -> Bool {
        ConductorLog.performance.debug("context menu action=\(String(describing: action), privacy: .public) terminal=\(terminalID.description, privacy: .public) workspace=\(workspaceID.description, privacy: .public)")
        switch action {
        case .renameTerminal:
            promptRenameTerminal(terminalID, window: window)
            return true
        case .restoreTerminalTitle:
            clearUserTerminalTitle(terminalID)
            return true
        case .showSearch:
            showTerminalSearch(for: terminalID)
            return true
        case .showFileManager:
            return showFileManager(for: terminalID)
        case .openDirectory:
            openWorkingDirectory(for: terminalID)
            return true
        case .copyDirectory:
            copyWorkingDirectory(for: terminalID)
            return true
        case .renameWorkspace:
            promptRenameWorkspace(workspaceID, window: window)
            return true
        case .duplicateWorkspace:
            duplicateWorkspace(workspaceID)
            return true
        case .closeWorkspace:
            closeWorkspace(workspaceID)
            return true
        case .duplicateTerminal:
            guard let target = activateTerminalContextTarget(terminalID) else { return false }
            duplicateTab(target.tab.id, in: target.paneID)
            return true
        case .newTerminal:
            guard activateTerminalContextTarget(terminalID) != nil else { return false }
            newTerminal()
            return true
        case .newTerminalAtDirectory:
            newTerminalAtDirectory(for: terminalID)
            return true
        case .splitRight:
            guard activateTerminalContextTarget(terminalID) != nil else { return false }
            splitRight()
            return true
        case .splitDown:
            guard activateTerminalContextTarget(terminalID) != nil else { return false }
            splitDown()
            return true
        case .closePane:
            guard let target = activateTerminalContextTarget(terminalID) else { return false }
            closePane(target.paneID)
            return true
        case .closeTerminal:
            guard let target = activateTerminalContextTarget(terminalID) else { return false }
            closeTab(target.tab.id, in: target.paneID)
            return true
        case .closeOtherTerminals:
            guard let target = activateTerminalContextTarget(terminalID) else { return false }
            closeOtherTabs(in: target.paneID)
            return true
        case .closeTerminalsToRight:
            guard let target = activateTerminalContextTarget(terminalID) else { return false }
            closeTabsToRight(in: target.paneID)
            return true
        }
    }

    func newWorkspace() {
        let signpost = ConductorSignpost.begin("new-workspace")
        defer { ConductorSignpost.end("new-workspace", signpost) }
        closeTerminalSearch()
        let next = WorkspaceState(title: nextWorkspaceTitle())
        workspaces.append(next)
        selectedWorkspaceID = next.id
        workspace = next
        commandPaletteVisible = false
        workspaceOverviewVisible = false
    }

    func duplicateWorkspace(_ workspaceID: WorkspaceID) {
        let signpost = ConductorSignpost.begin("duplicate-workspace")
        defer { ConductorSignpost.end("duplicate-workspace", signpost) }
        closeTerminalSearch()
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let source = workspace.id == workspaceID ? workspace : workspaces[index]
        let duplicate = source.duplicated(title: nextCopyTitle(for: source.title))
        workspaces.insert(duplicate, at: index + 1)
        selectedWorkspaceID = duplicate.id
        workspace = duplicate
        commandPaletteVisible = false
        workspaceOverviewVisible = false
    }

    func selectWorkspace(_ workspaceID: WorkspaceID) {
        let signpost = ConductorSignpost.begin("select-workspace")
        defer { ConductorSignpost.end("select-workspace", signpost) }
        guard workspaceID != workspace.id else {
            closeWorkspaceTransientPanels()
            return
        }
        guard let target = workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        closeTerminalSearch()
        selectedWorkspaceID = workspaceID
        workspace = target
        closeWorkspaceTransientPanels()
    }

    func renameWorkspace(_ workspaceID: WorkspaceID, title: String) {
        let cleanTitle = sanitizedTitle(title, fallback: "工作区")
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        workspaces[index].title = cleanTitle
        if workspace.id == workspaceID {
            workspace.title = cleanTitle
        } else {
            persist()
        }
    }

    func closeWorkspace(_ workspaceID: WorkspaceID) {
        guard workspaces.count > 1,
              let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }
        let closingWorkspace = workspaces[index]
        closeSurfaces(for: terminalIDs(in: closingWorkspace))
        workspaces.remove(at: index)
        if workspace.id == workspaceID {
            let nextIndex = min(index, workspaces.count - 1)
            selectWorkspaceAfterListMutation(workspaces[nextIndex])
        } else {
            persist()
        }
    }

    func closeOtherWorkspaces(keeping workspaceID: WorkspaceID) {
        guard workspaces.count > 1,
              let keptWorkspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        for closingWorkspace in workspaces where closingWorkspace.id != workspaceID {
            closeSurfaces(for: terminalIDs(in: closingWorkspace))
        }
        workspaces = [keptWorkspace]
        selectWorkspaceAfterListMutation(keptWorkspace)
        commandPaletteVisible = false
    }

    func closeWorkspacesToRight(of workspaceID: WorkspaceID) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }),
              index < workspaces.count - 1 else {
            return
        }
        let closingWorkspaces = workspaces[(index + 1)...]
        for closingWorkspace in closingWorkspaces {
            closeSurfaces(for: terminalIDs(in: closingWorkspace))
        }
        workspaces.removeSubrange((index + 1)..<workspaces.count)
        if workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
            syncSelectedWorkspace()
            persist()
        } else {
            selectWorkspaceAfterListMutation(workspaces[index])
        }
        commandPaletteVisible = false
    }

    func moveWorkspace(_ workspaceID: WorkspaceID, before targetWorkspaceID: WorkspaceID?) {
        syncSelectedWorkspace()
        guard let sourceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let moving = workspaces.remove(at: sourceIndex)
        let targetIndex: Int
        if let targetWorkspaceID,
           let rawTargetIndex = workspaces.firstIndex(where: { $0.id == targetWorkspaceID }) {
            targetIndex = rawTargetIndex
        } else {
            targetIndex = workspaces.count
        }
        workspaces.insert(moving, at: targetIndex)
        persist()
    }

    func renameTerminal(_ terminalID: TerminalID, title: String) {
        let cleanTitle = sanitizedTitle(title, fallback: "zsh")
        _ = updateWorkspace(containing: terminalID) { workspace in
            workspace.updateTerminalTitle(terminalID, title: cleanTitle, userEdited: true)
        }
    }

    func clearUserTerminalTitle(_ terminalID: TerminalID) {
        _ = updateWorkspace(containing: terminalID) { workspace in
            workspace.clearUserTerminalTitle(terminalID)
        }
    }

    func duplicateTab(_ terminalID: TerminalID, in paneID: PaneID) {
        _ = workspace.duplicateTab(terminalID, in: paneID)
    }

    func duplicateSelectedTab() {
        guard let pane = workspace.focusedPane else { return }
        duplicateTab(pane.selectedTabID, in: pane.id)
    }

    func closeTab(_ terminalID: TerminalID, in paneID: PaneID) {
        let signpost = ConductorSignpost.begin("close-tab")
        defer { ConductorSignpost.end("close-tab", signpost) }
        let result = workspace.closeTab(terminalID, in: paneID)
        closeSurfaces(for: result.closedTerminalIDs)
    }

    func closePane(_ paneID: PaneID) {
        let signpost = ConductorSignpost.begin("close-pane")
        defer { ConductorSignpost.end("close-pane", signpost) }
        let result = workspace.closePane(paneID)
        closeSurfaces(for: result.closedTerminalIDs)
    }

    func closeSelectedTab() {
        let signpost = ConductorSignpost.begin("close-selected-tab")
        defer { ConductorSignpost.end("close-selected-tab", signpost) }
        let result = workspace.closeSelectedTab()
        closeSurfaces(for: result.closedTerminalIDs)
    }

    func closeOtherTabs(in paneID: PaneID? = nil) {
        let result = workspace.closeTabs(scope: .others, in: paneID)
        closeSurfaces(for: result.closedTerminalIDs)
    }

    func closeTabsToRight(in paneID: PaneID? = nil) {
        let result = workspace.closeTabs(scope: .toRight, in: paneID)
        closeSurfaces(for: result.closedTerminalIDs)
    }

    func moveSelectedTabLeft() {
        guard workspace.canMoveSelectedTab(offset: -1) else { return }
        workspace.moveSelectedTab(offset: -1)
    }

    func moveSelectedTabRight() {
        guard workspace.canMoveSelectedTab(offset: 1) else { return }
        workspace.moveSelectedTab(offset: 1)
    }

    func moveSelectedTabToNextPane() {
        guard workspace.canMoveSelectedTabToNextPane() else { return }
        workspace.moveSelectedTabToNextPane()
    }

    func moveSelectedTabToNewSplit(_ direction: SplitDirection) {
        guard workspace.canMoveSelectedTabToNewSplit() else { return }
        workspace.moveSelectedTabToNewSplit(direction)
    }

    func moveTabToNewSplit(_ tabID: TerminalID, direction: SplitDirection) {
        guard workspace.canMoveTabToNewSplit(tabID) else { return }
        workspace.moveTabToNewSplit(tabID, direction)
        reconcileSurfaceFocus()
        refreshSurfaceAfterNavigation(tabID)
    }

    func moveTabToSplit(_ tabID: TerminalID, targetPaneID: PaneID, direction: SplitDirection) {
        guard workspace.canMoveTabToSplit(tabID, targetPaneID: targetPaneID) else { return }
        workspace.moveTabToSplit(tabID, targetPaneID: targetPaneID, direction)
        reconcileSurfaceFocus()
        refreshSurfaceAfterNavigation(tabID)
    }

    func reorderTab(_ tabID: TerminalID, before targetTabID: TerminalID, in paneID: PaneID) {
        workspace.reorderTab(tabID, before: targetTabID, in: paneID)
    }

    func moveTabToEnd(_ tabID: TerminalID, in paneID: PaneID) {
        workspace.moveTab(tabID, in: paneID)
    }

    func moveTab(_ tabID: TerminalID, before targetTabID: TerminalID, in paneID: PaneID) {
        workspace.moveTab(tabID, before: targetTabID, in: paneID)
    }

    func selectNextTab() {
        if let terminalID = workspace.selectAdjacentTab(offset: 1) {
            reconcileSurfaceFocus()
            refreshSurfaceAfterNavigation(terminalID)
        }
    }

    func selectPreviousTab() {
        if let terminalID = workspace.selectAdjacentTab(offset: -1) {
            reconcileSurfaceFocus()
            refreshSurfaceAfterNavigation(terminalID)
        }
    }

    func focusNextPane() {
        if let paneID = workspace.focusAdjacentPane(.next) {
            markSelectedTerminalNotificationsRead(in: paneID)
            reconcileSurfaceFocus()
        }
    }

    func focusPreviousPane() {
        if let paneID = workspace.focusAdjacentPane(.previous) {
            markSelectedTerminalNotificationsRead(in: paneID)
            reconcileSurfaceFocus()
        }
    }

    func focusPane(direction: FocusDirection) {
        if let paneID = workspace.focusAdjacentPane(direction) {
            markSelectedTerminalNotificationsRead(in: paneID)
            reconcileSurfaceFocus()
        }
    }

    func resizeFocusedSplit(direction: ResizeSplitDirection, amount: Double = 5) {
        let signpost = ConductorSignpost.begin("resize-split")
        defer { ConductorSignpost.end("resize-split", signpost) }
        workspace.resizeFocusedSplit(direction: direction, amount: amount)
    }

    func toggleCommandPalette() {
        let signpost = ConductorSignpost.begin("palette-toggle")
        defer { ConductorSignpost.end("palette-toggle", signpost) }
        commandPaletteVisible.toggle()
        if commandPaletteVisible {
            settingsPanelVisible = false
            workspaceOverviewVisible = false
            closeTerminalSearch()
        }
    }

    func hideCommandPalette() {
        commandPaletteVisible = false
    }

    func toggleSettingsPanel() {
        let signpost = ConductorSignpost.begin("settings-toggle")
        defer { ConductorSignpost.end("settings-toggle", signpost) }
        settingsPanelVisible.toggle()
        if settingsPanelVisible {
            commandPaletteVisible = false
            workspaceOverviewVisible = false
            closeTerminalSearch()
        }
    }

    func hideSettingsPanel() {
        settingsPanelVisible = false
    }

    func toggleWorkspaceOverview() {
        let signpost = ConductorSignpost.begin("overview-toggle")
        defer { ConductorSignpost.end("overview-toggle", signpost) }
        workspaceOverviewVisible.toggle()
        if workspaceOverviewVisible {
            commandPaletteVisible = false
            settingsPanelVisible = false
            closeTerminalSearch()
        }
    }

    func hideWorkspaceOverview() {
        workspaceOverviewVisible = false
    }

    @discardableResult
    func dismissVisibleShellPanel() -> Bool {
        if terminalSearchVisible {
            closeTerminalSearch()
            return true
        }
        if commandPaletteVisible {
            commandPaletteVisible = false
            return true
        }
        if settingsPanelVisible {
            settingsPanelVisible = false
            return true
        }
        if workspaceOverviewVisible {
            workspaceOverviewVisible = false
            return true
        }
        return false
    }

    func toggleNotificationPanel() {
        let signpost = ConductorSignpost.begin("notifications-toggle")
        defer { ConductorSignpost.end("notifications-toggle", signpost) }
        if notificationPanelVisible {
            onNotificationPanelVisibilityChange?(true)
            return
        }
        notificationPanelVisible = true
    }

    func hideNotificationPanel() {
        notificationPanelVisible = false
    }

    func notifyFocusedTerminalForTesting() {
        guard let tab = workspace.focusedPane?.selectedTab else { return }
        _ = recordTerminalNotification(
            terminalID: tab.id,
            title: "测试通知",
            body: "当前终端的通知通道可用。",
            kind: .agent
        )
    }

    @discardableResult
    func jumpToLatestUnread() -> Bool {
        guard let notification = notifications.snapshot.latestUnread else { return false }
        return openNotification(notification.id)
    }

    @discardableResult
    func openNotification(_ notificationID: UUID) -> Bool {
        guard let notification = notifications.records.first(where: { $0.id == notificationID }) else {
            return false
        }
        ConductorLog.performance.debug("open notification id=\(notificationID.uuidString, privacy: .public) terminal=\(notification.terminalID.description, privacy: .public)")
        focusTerminal(notification.terminalID)
        markNotificationRead(notificationID)
        refreshSurfaceAfterNavigation(notification.terminalID)
        return true
    }

    func markNotificationRead(_ notificationID: UUID) {
        guard let terminalID = notifications.records.first(where: { $0.id == notificationID })?.terminalID else {
            return
        }
        mutateNotifications { $0.markRead(id: notificationID) }
        refreshNotificationMetadata(for: terminalID)
    }

    func markTerminalNotificationsRead(_ terminalID: TerminalID) {
        guard notifications.snapshot.unreadCount(for: terminalID) > 0 || metadata(for: terminalID).unreadCount > 0 else {
            return
        }
        ConductorLog.performance.debug("mark notifications read terminal=\(terminalID.description, privacy: .public)")
        var next = notifications
        if next.markTerminalRead(terminalID) {
            notifications = next
        } else if metadata(for: terminalID).unreadCount == notifications.snapshot.unreadCount(for: terminalID) {
            return
        }
        refreshNotificationMetadata(for: terminalID)
    }

    func recordTerminalUserActivity(_ terminalID: TerminalID) {
        guard terminalLocation(for: terminalID) != nil else { return }
        markTerminalNotificationsRead(terminalID)
    }

    private func markSelectedTerminalNotificationsRead(in paneID: PaneID) {
        guard let terminalID = workspace.panes[paneID]?.selectedTabID else { return }
        markTerminalNotificationsRead(terminalID)
    }

    func clearNotification(_ notificationID: UUID) {
        guard let terminalID = notifications.records.first(where: { $0.id == notificationID })?.terminalID else {
            return
        }
        mutateNotifications { $0.clear(id: notificationID) }
        refreshNotificationMetadata(for: terminalID)
    }

    func clearAllNotifications() {
        let terminalIDs = Set(notifications.records.map(\.terminalID))
        mutateNotifications { $0.clearAll() }
        terminalIDs.forEach(refreshNotificationMetadata)
    }

    func receiveAgentHookNotification(_ userInfo: [String: String]?) {
        guard let userInfo,
              let rawTerminalID = userInfo[ConductorAgentHookBridge.Key.terminalID],
              let uuid = UUID(uuidString: rawTerminalID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        let agent = userInfo[ConductorAgentHookBridge.Key.agent] ?? ""
        guard appearance.agentNotifications.isEnabled(forAgentName: agent) else { return }

        let terminalID = TerminalID(uuid)
        let action = userInfo[ConductorAgentHookBridge.Key.action]?.lowercased() ?? ""
        switch action {
        case "prompt-submit", "session-start":
            markTerminalNotificationsRead(terminalID)
        case "stop", "agent-response", "subagent-stop", "notification":
            let title = userInfo[ConductorAgentHookBridge.Key.title] ?? "任务完成"
            let body = userInfo[ConductorAgentHookBridge.Key.body] ?? "终端任务已完成，等待下一步。"
            _ = recordTerminalNotification(
                terminalID: terminalID,
                title: title,
                body: body,
                kind: .agent
            )
        default:
            break
        }
    }

    func equalizeSplits() {
        workspace.equalizeSplits()
    }

    func toggleZoom() {
        workspace.toggleZoom()
    }

    func setSplitFraction(path: [SplitPathElement], fraction: Double) {
        let nextRoot = workspace.root.settingFraction(at: path[...], to: fraction)
        guard nextRoot != workspace.root else { return }
        let signpost = ConductorSignpost.begin("drag-split-divider")
        defer { ConductorSignpost.end("drag-split-divider", signpost) }
        workspace.root = nextRoot
    }

    @discardableResult
    private func performWorkspaceEdgeSplit(_ direction: SplitDirection) -> PaneID? {
        let previouslyVisibleTerminalIDs = selectedVisibleTerminalIDs(in: workspace)
        let title = nextTerminalTitle(prefix: "zsh")
        guard let newPaneID = workspace.splitWorkspaceEdge(direction, title: title) else {
            return nil
        }

        let visibleTerminalIDs = orderedUniqueTerminalIDs(
            previouslyVisibleTerminalIDs + selectedVisibleTerminalIDs(in: workspace)
        )
        reconcileSurfaceFocus()
        refreshSurfacesAfterSplit(visibleTerminalIDs)
        return newPaneID
    }

    private func selectedVisibleTerminalIDs(in workspace: WorkspaceState) -> [TerminalID] {
        workspace.visibleRoot.leaves.compactMap { paneID in
            workspace.panes[paneID]?.selectedTabID
        }
    }

    private func orderedUniqueTerminalIDs(_ terminalIDs: [TerminalID]) -> [TerminalID] {
        var seen = Set<TerminalID>()
        var unique: [TerminalID] = []
        for terminalID in terminalIDs where seen.insert(terminalID).inserted {
            unique.append(terminalID)
        }
        return unique
    }

    private func refreshSurfacesAfterSplit(_ terminalIDs: [TerminalID]) {
        guard !terminalIDs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.refreshSurfacesAfterSplitPass(terminalIDs)
            }
        }
    }

    private func refreshSurfacesAfterSplitPass(_ terminalIDs: [TerminalID]) {
        let focusedTerminalID = workspace.focusedPane?.selectedTabID
        for terminalID in terminalIDs {
            guard let surface = surfaces[terminalID] else { continue }
            let focused = terminalID == focusedTerminalID
            surface.attachIfPossible()
            surface.setFocused(focused, force: true)
            surface.syncGeometry(force: true)
            surface.refresh()
            if focused,
               !terminalSearchVisible,
               let window = surface.hostView.window,
               window.firstResponder !== surface.hostView {
                window.makeFirstResponder(surface.hostView)
            }
        }
    }

    private func refreshSurfaceAfterNavigation(_ terminalID: TerminalID) {
        guard let surface = surfaces[terminalID] else { return }
        guard pendingNavigationRefreshTerminalIDs.insert(terminalID).inserted else { return }
        let signpost = ConductorSignpost.begin("navigation-refresh")
        reconcileSurfaceFocus()
        surface.attachIfPossible()
        surface.setFocused(true, force: true)
        surface.syncGeometry(force: true)
        surface.refresh()
        Task { @MainActor [weak self] in
            defer {
                self?.pendingNavigationRefreshTerminalIDs.remove(terminalID)
                ConductorSignpost.end("navigation-refresh", signpost)
            }
            guard let surface = self?.surfaces[terminalID] else { return }
            surface.attachIfPossible()
            surface.syncGeometry(force: true)
            surface.refresh()
            guard self?.terminalSearchVisible != true else { return }
            if surface.hostView.window?.firstResponder !== surface.hostView {
                surface.hostView.window?.makeFirstResponder(surface.hostView)
            }
        }
    }

    private func reconcileSurfaceFocus() {
        let focusedTerminalID = workspace.focusedPane?.selectedTabID
        for (terminalID, surface) in surfaces {
            surface.setFocused(terminalID == focusedTerminalID)
        }
    }

    func closeAllSurfaces() {
        surfaces.values.forEach { $0.close() }
        surfaces.removeAll()
        metadataByTerminalID.removeAll(keepingCapacity: false)
        pendingMetadataByTerminalID.removeAll(keepingCapacity: false)
    }

    func flushPersistence() {
        pendingPersistence?.cancel()
        pendingPersistence = nil
        syncSelectedWorkspace()
        persistence.save(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            theme: theme,
            appearance: appearance
        )
    }

    func resetWorkspace() {
        closeSurfaces(for: terminalIDs(in: workspace))
        let replacement = WorkspaceState(title: workspace.title)
        replaceSelectedWorkspace(with: replacement)
        commandPaletteVisible = false
    }

    private func closeSurfaces(for terminalIDs: [TerminalID]) {
        if !terminalIDs.isEmpty {
            ConductorLog.performance.debug("surface close requested count=\(terminalIDs.count, privacy: .public) activeBefore=\(self.surfaces.count, privacy: .public)")
        }
        if let targetID = terminalSearchTargetID, terminalIDs.contains(targetID) {
            terminalSearchVisible = false
            terminalSearchQuery = ""
            terminalSearchTargetID = nil
        }
        for terminalID in terminalIDs {
            metadataByTerminalID.removeValue(forKey: terminalID)
            pendingMetadataByTerminalID.removeValue(forKey: terminalID)
            surfaces.removeValue(forKey: terminalID)?.close()
        }
        if !terminalIDs.isEmpty {
            var next = notifications
            for terminalID in terminalIDs {
                next.clearTerminal(terminalID)
            }
            notifications = next
        }
    }

    @discardableResult
    private func recordTerminalNotification(
        terminalID: TerminalID,
        title: String,
        body: String,
        kind: TerminalNotificationKind
    ) -> Bool {
        guard let location = terminalLocation(for: terminalID) else { return false }
        var nextNotifications = notifications
        let notification = nextNotifications.add(
            workspaceID: location.workspaceID,
            paneID: location.paneID,
            terminalID: terminalID,
            title: title,
            body: body,
            kind: kind
        )
        notifications = nextNotifications
        updateMetadata(for: terminalID) { metadata in
            metadata.unreadCount = notifications.snapshot.unreadCount(for: terminalID)
            metadata.lastNotificationTitle = notification.title
            metadata.lastNotificationBody = notification.body.isEmpty ? nil : notification.body
            if kind == .bell {
                metadata.bellCount += 1
            }
        }
        return true
    }

    private func mutateNotifications(_ mutation: (inout TerminalNotificationState) -> Void) {
        var next = notifications
        mutation(&next)
        notifications = next
    }

    private func refreshNotificationMetadata(for terminalID: TerminalID) {
        updateMetadata(for: terminalID) { metadata in
            metadata.unreadCount = notifications.snapshot.unreadCount(for: terminalID)
            if let latest = notifications.snapshot.latestByTerminalID[terminalID] {
                metadata.lastNotificationTitle = latest.title
                metadata.lastNotificationBody = latest.body.isEmpty ? nil : latest.body
            } else {
                metadata.lastNotificationTitle = nil
                metadata.lastNotificationBody = nil
            }
        }
    }

    private func terminalLocation(for terminalID: TerminalID) -> (workspaceID: WorkspaceID, paneID: PaneID)? {
        if let paneID = workspace.paneID(containing: terminalID) {
            return (workspace.id, paneID)
        }
        for candidate in workspaces {
            if let paneID = candidate.paneID(containing: terminalID) {
                return (candidate.id, paneID)
            }
        }
        return nil
    }

    private func terminalContextMenuTarget(for terminalID: TerminalID) -> TerminalContextMenuTarget? {
        if let paneID = workspace.paneID(containing: terminalID),
           let pane = workspace.panes[paneID],
           let tab = pane.tabs.first(where: { $0.id == terminalID }) {
            return TerminalContextMenuTarget(
                workspaceID: workspace.id,
                workspace: workspace,
                paneID: paneID,
                tab: tab
            )
        }

        for candidate in workspaces {
            guard let paneID = candidate.paneID(containing: terminalID),
                  let pane = candidate.panes[paneID],
                  let tab = pane.tabs.first(where: { $0.id == terminalID }) else {
                continue
            }
            return TerminalContextMenuTarget(
                workspaceID: candidate.id,
                workspace: candidate,
                paneID: paneID,
                tab: tab
            )
        }

        return nil
    }

    @discardableResult
    private func activateTerminalContextTarget(_ terminalID: TerminalID) -> TerminalContextMenuTarget? {
        guard let target = terminalContextMenuTarget(for: terminalID) else { return nil }
        if workspace.id != target.workspaceID {
            selectWorkspace(target.workspaceID)
        }
        guard let currentTarget = terminalContextMenuTarget(for: terminalID) else { return nil }
        selectTab(terminalID, in: currentTarget.paneID)
        refreshSurfaceAfterNavigation(terminalID)
        return currentTarget
    }

    private func terminalSearchTarget(for terminalID: TerminalID) -> (paneID: PaneID, tab: TerminalTabState)? {
        guard let paneID = workspace.paneID(containing: terminalID),
              let pane = workspace.panes[paneID],
              let tab = pane.tabs.first(where: { $0.id == terminalID }) else {
            return nil
        }
        return (paneID, tab)
    }

    private func terminalSearchTargetTab() -> TerminalTabState? {
        guard let terminalID = terminalSearchTargetID ?? focusedTerminalID else { return nil }
        return terminalSearchTarget(for: terminalID)?.tab
    }

    private func activateTerminalSearchSurface(terminalID: TerminalID, query: String) {
        guard let target = terminalSearchTarget(for: terminalID) else { return }
        let targetSurface = surface(for: target.tab)
        if !query.isEmpty {
            _ = targetSurface.search(query)
        }
    }

    private func promptRenameTerminal(_ terminalID: TerminalID, window: NSWindow?) {
        guard let target = terminalContextMenuTarget(for: terminalID),
              let title = promptForTitle(
                message: L("重命名当前终端", "Rename Current Terminal"),
                currentTitle: target.tab.title,
                placeholder: L("终端名称", "Terminal Name"),
                window: window
              ) else {
            return
        }
        renameTerminal(terminalID, title: title)
    }

    private func promptRenameWorkspace(_ workspaceID: WorkspaceID, window: NSWindow?) {
        guard let target = workspaces.first(where: { $0.id == workspaceID }),
              let title = promptForTitle(
                message: L("重命名当前工作区", "Rename Current Workspace"),
                currentTitle: target.title,
                placeholder: L("工作区名称", "Workspace Name"),
                window: window
              ) else {
            return
        }
        renameWorkspace(workspaceID, title: title)
    }

    private func promptForTitle(
        message: String,
        currentTitle: String,
        placeholder: String,
        window: NSWindow?
    ) -> String? {
        let field = NSTextField(string: currentTitle)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.lineBreakMode = .byTruncatingTail
        field.selectText(nil)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = L("输入一个短名称，方便在标签和工作区里快速识别。", "Enter a short name that is easy to scan in tabs and workspaces.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L("重命名", "Rename"))
        alert.addButton(withTitle: L("取消", "Cancel"))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if let window {
            alert.window.appearance = window.appearance
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func metadata(for terminalID: TerminalID) -> TerminalDisplayMetadata {
        pendingMetadataByTerminalID[terminalID] ?? metadataByTerminalID[terminalID] ?? TerminalDisplayMetadata()
    }

    private func focusedWorkingDirectoryPath(for terminalID: TerminalID) -> String? {
        let metadataPath = metadata(for: terminalID).workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataPath, !metadataPath.isEmpty {
            return metadataPath
        }
        guard let paneID = workspace.paneID(containing: terminalID),
              let tab = workspace.panes[paneID]?.tabs.first(where: { $0.id == terminalID }) else {
            return nil
        }
        let tabPath = tab.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        return tabPath?.isEmpty == false ? tabPath : nil
    }

    private func openLocalFileURLFromTerminal(terminalID: TerminalID?, url: URL) -> Bool {
        let fileURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            if let terminalID, containsTerminal(terminalID) {
                _ = recordTerminalNotification(
                    terminalID: terminalID,
                    title: L("文件不存在", "File Not Found"),
                    body: fileURL.path,
                    kind: .notification
                )
            } else {
                ConductorLog.terminal.warning("Ignoring missing local file URL: \(fileURL.path)")
            }
            return true
        }

        if isDirectory.boolValue {
            showFileManager(rootURL: fileURL)
        } else {
            showFileManager(rootURL: fileURL.deletingLastPathComponent(), selectedURL: fileURL)
            openFileInWorkspace(fileURL, rootURL: fileURL.deletingLastPathComponent())
        }
        return true
    }

    private static func shellEscapedText(_ value: String) -> String {
        if value.contains(where: { $0 == "\n" || $0 == "\r" }) {
            return shellSingleQuoted(value)
        }

        var result = value
        for character in "\\ ()[]{}<>\"'`!#$&;|*?\t" {
            result = result.replacingOccurrences(of: String(character), with: "\\\(character)")
        }
        return result
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func updateMetadata(for terminalID: TerminalID, _ update: (inout TerminalDisplayMetadata) -> Void) {
        guard containsTerminal(terminalID) else { return }
        var metadata = metadata(for: terminalID)
        update(&metadata)
        pendingMetadataByTerminalID[terminalID] = metadata
        scheduleMetadataPublish()
    }

    private func scheduleMetadataPublish() {
        guard pendingMetadataPublish == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMetadataPublish = nil
            guard !self.pendingMetadataByTerminalID.isEmpty else { return }
            var next = self.metadataByTerminalID
            for (terminalID, metadata) in self.pendingMetadataByTerminalID {
                next[terminalID] = metadata
            }
            self.pendingMetadataByTerminalID.removeAll(keepingCapacity: true)
            self.metadataByTerminalID = next.filter { terminalID, _ in
                self.containsTerminal(terminalID)
            }
        }
        pendingMetadataPublish = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: item)
    }

    private func persist() {
        pendingPersistence?.cancel()
        let workspaces = workspaces
        let selectedWorkspaceID = selectedWorkspaceID
        let theme = theme
        let appearance = appearance
        let item = DispatchWorkItem { [persistence] in
            let signpost = ConductorSignpost.begin("persistence-save")
            defer { ConductorSignpost.end("persistence-save", signpost) }
            persistence.save(
                workspaces: workspaces,
                selectedWorkspaceID: selectedWorkspaceID,
                theme: theme,
                appearance: appearance
            )
        }
        pendingPersistence = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func nextTerminalTitle(prefix: String) -> String {
        let count = workspace.panes.values.reduce(0) { $0 + $1.tabs.count } + 1
        return count == 1 ? prefix : "\(prefix) \(count)"
    }

    private func nextWorkspaceTitle() -> String {
        let base = "工作区"
        var index = workspaces.count + 1
        var candidate = "\(base) \(index)"
        let existingTitles = Set(workspaces.map(\.title))
        while existingTitles.contains(candidate) {
            index += 1
            candidate = "\(base) \(index)"
        }
        return candidate
    }

    private func nextCopyTitle(for title: String) -> String {
        let base = "\(title) 副本"
        var candidate = base
        var index = 2
        let existingTitles = Set(workspaces.map(\.title))
        while existingTitles.contains(candidate) {
            candidate = "\(base) \(index)"
            index += 1
        }
        return candidate
    }

    private func sanitizedTitle(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        return String(source.prefix(48))
    }

    private func syncSelectedWorkspace() {
        syncWorkspace(workspace)
    }

    private func syncWorkspace(_ snapshot: WorkspaceState) {
        if let index = workspaces.firstIndex(where: { $0.id == snapshot.id }) {
            guard workspaces[index] != snapshot else { return }
            workspaces[index] = snapshot
        } else {
            workspaces.append(snapshot)
        }
    }

    private func closeWorkspaceTransientPanels() {
        if terminalSearchVisible {
            closeTerminalSearch()
        }
        if commandPaletteVisible {
            commandPaletteVisible = false
        }
        if workspaceOverviewVisible {
            workspaceOverviewVisible = false
        }
    }

    private func replaceSelectedWorkspace(with replacement: WorkspaceState) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = replacement
        } else {
            workspaces.append(replacement)
        }
        selectWorkspaceAfterListMutation(replacement)
    }

    private func selectWorkspaceAfterListMutation(_ nextWorkspace: WorkspaceState) {
        selectedWorkspaceID = nextWorkspace.id
        skipPreviousWorkspaceSyncForNextAssignment = true
        workspace = nextWorkspace
    }

    private func updateWorkspace(containing terminalID: TerminalID, _ update: (inout WorkspaceState) -> Bool) -> Bool {
        if workspace.paneID(containing: terminalID) != nil {
            let updated = update(&workspace)
            return updated
        }
        guard let index = workspaces.firstIndex(where: { $0.paneID(containing: terminalID) != nil }) else {
            return false
        }
        var target = workspaces[index]
        let updated = update(&target)
        guard updated else { return false }
        workspaces[index] = target
        persist()
        return true
    }

    private func containsTerminal(_ terminalID: TerminalID) -> Bool {
        workspace.paneID(containing: terminalID) != nil ||
            workspaces.contains { $0.paneID(containing: terminalID) != nil }
    }

    private func terminalIDs(in workspace: WorkspaceState) -> [TerminalID] {
        workspace.panes.values.flatMap { pane in
            pane.tabs.map(\.id)
        }
    }
}
