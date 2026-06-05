import AppKit
import CodexBar
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
    var activeAgentTitle: String?
    var activeAgentStartedAt: Date?
    var progressKind: TerminalProgressKind?
    var progressPercent: Int?
    var lastCommandExitCode: Int?
    var lastCommandDurationNanoseconds: UInt64?
    var cellWidth: UInt32?
    var cellHeight: UInt32?
    var search = TerminalSearchMetadata()
    var readonly = false
    var bellCount = 0

    var hasActiveAgent: Bool {
        activeAgentTitle?.isEmpty == false
    }
}

enum TerminalContextMenuAction {
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

struct WorkspaceFileBufferSnapshot: Equatable {
    var text: String
    var savedText: String
    var canSave: Bool
    var isEditable: Bool
    var isReadOnly: Bool
    var updatedAt: Date
    var savedRevision: Int

    var isDirty: Bool {
        text != savedText
    }
}

struct TerminalAgentResumeBatchTarget: Equatable {
    var workspaceID: WorkspaceID
    var paneID: PaneID
    var terminalID: TerminalID
    var terminalTitle: String
    var providerID: String?
    var displayName: String
    var resumeCommand: String
    var agentSnapshot: TerminalAgentSnapshot?
}

struct TerminalAgentResumeBatchResult: Equatable {
    var target: TerminalAgentResumeBatchTarget
    var sent: Bool
    var dryRun: Bool
    var failureReason: String?
}

struct WorkspaceRenameRequest: Equatable {
    var id = UUID()
    var workspaceID: WorkspaceID
}

private struct WorkspaceContentRuntimeState: Equatable {
    var webTabs: [WorkspaceWebTabState] = []
    var fileTabs: [ConductorWorkspaceFileTab] = []
    var dirtyFileTabIDs: Set<String> = []
    var externallyChangedFileTabIDs: Set<String> = []
    var selectedContentTabID: ConductorWorkspaceContentTabID?
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
    case web(WebTabID)

    var diagnosticName: String {
        switch self {
        case .terminal:
            "terminal"
        case .file:
            "file"
        case .web:
            "web"
        }
    }
}

enum WorkspaceNavigationSource: String {
    case sidebar
    case tabStrip
    case overview
    case commandPalette
    case terminalFocus
    case newWorkspace
    case duplicateWorkspace
    case listMutation
    case programmatic
}

private enum ConductorUpdateCheckOutcome {
    case success
    case failure(String)
    case skipped
    case cancelled
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
            if !suppressWorkspaceAssignmentPersistence {
                persist()
            }
        }
    }
    @Published private(set) var workspaces: [WorkspaceState] {
        didSet { applyOcclusion() }
    }
    @Published var theme: TerminalTheme {
        didSet {
            surfaceCoordinator.applyAppearance(theme: theme, terminalFontSize: appearance.terminalFontSize)
            ConductorUsageFeature.configureHostMenuStyle(Self.usageMenuStyle(for: theme))
            persist()
        }
    }
    @Published var appearance: AppearancePreferences {
        didSet {
            guard oldValue != appearance else { return }
            ConductorAppearanceRuntime.apply(appearance)
            ConductorUsageFeature.configureHostLanguageIdentifier(appearance.language.usageFeatureLanguageIdentifier)
            TerminalAppearanceRuntime.apply(appearance)
            ConductorMotion.setReducedMotion(appearance.reducedMotion)
            if oldValue.terminalFontSize != appearance.terminalFontSize ||
                oldValue.terminalRenderer != appearance.terminalRenderer {
                surfaceCoordinator.applyAppearance(theme: theme, terminalFontSize: appearance.terminalFontSize)
            }
            persist()
        }
    }
    @Published private(set) var metadataByTerminalID: [TerminalID: TerminalDisplayMetadata] = [:]
    @Published private(set) var workspaceMetadataSnapshots: [WorkspaceID: WorkspaceMetadataSnapshot] = [:]
    @Published private(set) var applicationActive = NSApp.isActive
    @Published var sidebarVisible = true
    @Published var commandPaletteVisible = false
    @Published var settingsPanelVisible = false
    @Published var requestedSettingsSection: SettingsSectionID?
    @Published var workspaceOverviewVisible = false
    @Published var fileManagerPanelRequest: FileManagerPanelRequest?
    @Published private(set) var workspaceRenameRequest: WorkspaceRenameRequest?
    @Published private(set) var shellToast: ConductorShellToast?
    @Published private(set) var recentShellCommandIDs: [String] = []
    @Published private(set) var attentionEvents: [ConductorAttentionEvent] = []
    @Published private(set) var workspaceFileTabs: [ConductorWorkspaceFileTab] = []
    @Published private(set) var dirtyWorkspaceFileTabIDs: Set<String> = []
    @Published private(set) var externallyChangedWorkspaceFileTabIDs: Set<String> = []
    @Published private(set) var workspaceFileEditorSaveRequestTokensByTabID: [String: Int] = [:]
    @Published private(set) var workspaceFileEditorSaveAndCloseRequestTokensByTabID: [String: Int] = [:]
    @Published private(set) var workspaceFileEditorSavedRevisionByTabID: [String: Int] = [:]
    @Published private(set) var workspaceFileSearchFocusGeneration = 0
    @Published private(set) var workspaceFileSearchNextGeneration = 0
    @Published private(set) var workspaceFileSearchPreviousGeneration = 0
    @Published private(set) var workspaceFileLayoutRevision = 0
    @Published private(set) var fileManagerKeyboardFocused = false
    @Published private(set) var fileManagerSearchFocusGeneration = 0
    @Published private(set) var fileManagerSearchNextGeneration = 0
    @Published private(set) var fileManagerSearchPreviousGeneration = 0
    @Published private(set) var workspaceWebTabs: [WorkspaceWebTabState] = []
    @Published private(set) var workspaceWebTabNavigationGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebTabReloadGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebTabStopGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebTabBackGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebTabForwardGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebAddressFocusGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebFindFocusGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebFindNextGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var workspaceWebFindPreviousGenerationByID: [WebTabID: Int] = [:]
    @Published private(set) var selectedWorkspaceContentTabID: ConductorWorkspaceContentTabID?
    @Published var terminalSearchVisible = false
    @Published var terminalSearchQuery = ""
    @Published private(set) var agentHookSettingsMessage: String?
    @Published private(set) var notificationAuthorizationState: AgentReplyNotificationAuthorizationState = .unknown
    @Published private(set) var notificationDeliveryTestMessage: String?
    @Published private(set) var agentCLIStatuses: [AgentHookProvider: AgentCLIStatus]
    @Published private(set) var terminalFontDownloadStates: [TerminalFontPreset: TerminalFontDownloadState]
    @Published var updatePreferences = ConductorUpdatePreferences.defaults()
    @Published private(set) var updateState = ConductorUpdateState()
    @Published private(set) var automaticUpdateDiagnostics = ConductorAutomaticUpdateDiagnostics()
    @Published private(set) var terminalSearchFocusGeneration = 0
    @Published private(set) var terminalSearchTargetID: TerminalID?
    @Published private(set) var paneFlashTokens: [PaneID: UInt64] = [:]
    @Published private(set) var terminalTabDropTargetByPaneID: [PaneID: TerminalTabDropTarget] = [:]
    @Published private(set) var activeTerminalTabDragID: TerminalID?
    private var terminalTabDragGeneration: UInt64 = 0
    private var terminalTabDragLocalMouseUpMonitor: Any?
    private var terminalTabDragGlobalMouseUpMonitor: Any?

    var selectedWorkspaceFileTab: ConductorWorkspaceFileTab? {
        guard case .file(let selectedWorkspaceFileTabID) = selectedWorkspaceContentTabID else { return nil }
        return workspaceFileTabs.first { $0.id == selectedWorkspaceFileTabID }
    }

    var selectedWorkspaceFileTabID: String? {
        guard case .file(let selectedWorkspaceFileTabID) = selectedWorkspaceContentTabID else { return nil }
        return selectedWorkspaceFileTabID
    }

    var selectedWorkspaceWebTab: WorkspaceWebTabState? {
        guard case .web(let selectedWorkspaceWebTabID) = selectedWorkspaceContentTabID else { return nil }
        return workspaceWebTabs.first { $0.id == selectedWorkspaceWebTabID }
    }

    var selectedWorkspaceWebTabID: WebTabID? {
        guard case .web(let selectedWorkspaceWebTabID) = selectedWorkspaceContentTabID else { return nil }
        return selectedWorkspaceWebTabID
    }

    var selectedWorkspaceTerminalTabID: TerminalID? {
        switch selectedWorkspaceContentTabID {
        case .terminal(let terminalID) where workspace.paneID(containing: terminalID) != nil:
            return terminalID
        case .file, .web:
            return nil
        default:
            return focusedTerminalID
        }
    }

    var workspaceTerminalContentTabs: [TerminalTabState] {
        workspace.focusedPane?.selectedTab.map { [$0] } ?? []
    }

    var workspaceContentWebTabCount: Int {
        var states = workspaceContentStatesByWorkspaceID
        states[workspace.id] = currentWorkspaceContentState()
        return states.values.reduce(0) { $0 + $1.webTabs.count }
    }

    var workspaceContentFileTabCount: Int {
        var states = workspaceContentStatesByWorkspaceID
        states[workspace.id] = currentWorkspaceContentState()
        return states.values.reduce(0) { $0 + $1.fileTabs.count }
    }

    private func markTerminalInteractionFocus() {
        if fileManagerKeyboardFocused {
            fileManagerKeyboardFocused = false
        }
    }

    func setApplicationActive(_ active: Bool) {
        guard applicationActive != active else { return }
        applicationActive = active
        // The agent-state poll only matters while the user can see the window;
        // pause it when the app is in the background to avoid idle CPU.
        setBackgroundActivityPaused(!active)
    }

    private let persistence = WorkspacePersistence()
    private let attentionStore = ConductorAttentionStore(isEnabled: WorkspacePersistence.isEnabledByDefault)
    /// Serial queue for persistence encoding + atomic writes, keeping that work
    /// off the main thread. Serial so saves never race or interleave on disk.
    private let persistenceQueue = DispatchQueue(label: "app.conductor.persistence", qos: .utility)
    private let surfaceCoordinator = TerminalSurfaceCoordinator()
    private var pendingPersistence: DispatchWorkItem?
    private var pendingMetadataByTerminalID: [TerminalID: TerminalDisplayMetadata] = [:]
    private var pendingMetadataPublish: DispatchWorkItem?
    private var activeTerminalContextMenuController: TerminalContextMenuController?
    private var workspaceContentStatesByWorkspaceID: [WorkspaceID: WorkspaceContentRuntimeState] = [:]
    private var workspaceFileBufferSnapshotsByTabID: [String: WorkspaceFileBufferSnapshot] = [:]
    private var suppressWorkspaceAssignmentPersistence = false
    private var selectedWorkspaceID: WorkspaceID {
        didSet { applyOcclusion() }
    }
    private var skipPreviousWorkspaceSyncForNextAssignment = false
    private var suppressCrossWorkspaceTerminalFocusUntil = Date.distantPast
    private var panelCoordinator = PanelCoordinator()
    private var appearanceCoordinator = AppearanceCoordinator(appearance: AppearancePreferences())
    private var fileWorkspaceCoordinator = FileWorkspaceCoordinator()
    private let updatePreferencesStore = ConductorUpdatePreferencesStore()
    private let updateService = ConductorUpdateService()
    private let agentReplyNotificationService = AgentReplyNotificationService()
    private var updateTask: Task<Void, Never>?
    private var automaticUpdateCheckTask: Task<Void, Never>?
    private var automaticUpdateCheckGeneration: UInt64 = 0
    private var agentRuntimePollTask: Task<Void, Never>?
    private var workspaceMetadataRefreshTask: Task<Void, Never>?
    private var workspaceMetadataRefreshGeneration: UInt64 = 0
    private var shellToastDismissTask: Task<Void, Never>?
    private static let commandFinishedAttentionThresholdNanoseconds: UInt64 = 30_000_000_000
    private static let automaticUpdateInitialDelayNanoseconds: UInt64 = 1_500_000_000
    private static let automaticUpdateCheckIntervalNanoseconds: UInt64 = 3_600_000_000_000
    private static let automaticUpdateMaximumIntervalNanoseconds: UInt64 = 21_600_000_000_000

    init() {
        let initialWorkspace = WorkspaceState()
        self.workspaces = [initialWorkspace]
        self.selectedWorkspaceID = initialWorkspace.id
        self.workspace = initialWorkspace
        self.theme = .codexDark
        let resolvedAppearance = AppearancePreferences()
        self.appearance = resolvedAppearance
        self.recentShellCommandIDs = Self.loadRecentShellCommandIDs()
        self.appearanceCoordinator = AppearanceCoordinator(appearance: resolvedAppearance)
        self.agentCLIStatuses = Dictionary(uniqueKeysWithValues: AgentHookProvider.allCases.map { ($0, .unknown(provider: $0)) })
        self.terminalFontDownloadStates = [:]
        self.updatePreferences = updatePreferencesStore.load()
        self.updateState = ConductorUpdateState(currentVersion: ConductorAppVersion.current())
        self.attentionEvents = attentionStore.events(limit: 80)
        self.workspaceContentStatesByWorkspaceID = [:]
        self.workspaceWebTabs = []
        self.workspaceFileTabs = []
        self.dirtyWorkspaceFileTabIDs = []
        self.externallyChangedWorkspaceFileTabIDs = []
        self.selectedWorkspaceContentTabID = nil
        syncPanelCoordinatorFromPublished()
        syncFileWorkspaceCoordinatorFromPublished()
        ConductorAppearanceRuntime.apply(self.appearance)
        ConductorUsageFeature.configureHostLanguageIdentifier(self.appearance.language.usageFeatureLanguageIdentifier)
        ConductorUsageFeature.configureHostMenuStyle(Self.usageMenuStyle(for: self.theme))
        TerminalAppearanceRuntime.apply(self.appearance)
        ConductorMotion.setReducedMotion(self.appearance.reducedMotion)
        configureNotificationDeliveryIssueHandler()
        startAgentRuntimePolling()
        scheduleWorkspaceMetadataRefresh(reason: "launch", debounceNanoseconds: 300_000_000)
    }

    #if DEBUG
    init(
        previewWorkspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID? = nil,
        theme: TerminalTheme = .codexDark,
        appearance: AppearancePreferences = AppearancePreferences(),
        sidebarVisible: Bool = true,
        commandPaletteVisible: Bool = false,
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
        self.recentShellCommandIDs = Self.loadRecentShellCommandIDs()
        self.appearanceCoordinator = AppearanceCoordinator(appearance: appearance)
        self.agentCLIStatuses = Dictionary(uniqueKeysWithValues: AgentHookProvider.allCases.map { ($0, .unknown(provider: $0)) })
        self.terminalFontDownloadStates = [:]
        self.updatePreferences = updatePreferencesStore.load()
        self.updateState = ConductorUpdateState(currentVersion: ConductorAppVersion.current())
        self.attentionEvents = attentionStore.events(limit: 80)
        self.sidebarVisible = sidebarVisible
        self.commandPaletteVisible = commandPaletteVisible
        self.settingsPanelVisible = settingsPanelVisible
        self.workspaceOverviewVisible = workspaceOverviewVisible
        syncPanelCoordinatorFromPublished()
        syncFileWorkspaceCoordinatorFromPublished()
        ConductorAppearanceRuntime.apply(self.appearance)
        ConductorUsageFeature.configureHostLanguageIdentifier(self.appearance.language.usageFeatureLanguageIdentifier)
        ConductorUsageFeature.configureHostMenuStyle(Self.usageMenuStyle(for: self.theme))
        TerminalAppearanceRuntime.apply(self.appearance)
        ConductorMotion.setReducedMotion(self.appearance.reducedMotion)
        configureNotificationDeliveryIssueHandler()
        startAgentRuntimePolling()
        scheduleWorkspaceMetadataRefresh(reason: "debug-init", debounceNanoseconds: 300_000_000)
    }
    #endif

    private static func usageMenuStyle(for theme: TerminalTheme) -> ConductorUsagePanelStyle {
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

    private static let recentShellCommandsDefaultsKey = "conductor.shell.recentCommands"
    private static let maxRecentShellCommandCount = 12

    private static func loadRecentShellCommandIDs() -> [String] {
        let knownCommands = Set(ConductorShellCommand.allCases.map(\.rawValue))
        let stored = UserDefaults.standard.stringArray(forKey: recentShellCommandsDefaultsKey) ?? []
        var unique: [String] = []
        for commandID in stored where knownCommands.contains(commandID) && !unique.contains(commandID) {
            unique.append(commandID)
        }
        return Array(unique.prefix(maxRecentShellCommandCount))
    }

    private static func saveRecentShellCommandIDs(_ commandIDs: [String]) {
        UserDefaults.standard.set(Array(commandIDs.prefix(maxRecentShellCommandCount)), forKey: recentShellCommandsDefaultsKey)
    }

    func openTokenRecordsPanel() {
        ConductorMotion.perform(ConductorMotion.panel) {
            ConductorUsageFeature.openTokenRecords(
                style: Self.usageMenuStyle(for: self.theme),
                languageIdentifier: self.appearance.language.usageFeatureLanguageIdentifier)
        }
    }

    private func syncPanelCoordinatorFromPublished() {
        panelCoordinator.commandPaletteVisible = commandPaletteVisible
        panelCoordinator.settingsVisible = settingsPanelVisible
        panelCoordinator.workspaceOverviewVisible = workspaceOverviewVisible
        panelCoordinator.terminalSearchVisible = terminalSearchVisible
    }

    @discardableResult
    private func publishPanelState() -> Bool {
        var changed = false
        if commandPaletteVisible != panelCoordinator.commandPaletteVisible {
            commandPaletteVisible = panelCoordinator.commandPaletteVisible
            changed = true
        }
        if settingsPanelVisible != panelCoordinator.settingsVisible {
            settingsPanelVisible = panelCoordinator.settingsVisible
            changed = true
        }
        if workspaceOverviewVisible != panelCoordinator.workspaceOverviewVisible {
            workspaceOverviewVisible = panelCoordinator.workspaceOverviewVisible
            changed = true
        }
        if terminalSearchVisible != panelCoordinator.terminalSearchVisible {
            terminalSearchVisible = panelCoordinator.terminalSearchVisible
            changed = true
        }
        return changed
    }

    private func syncAppearanceCoordinatorFromPublished() {
        appearanceCoordinator = AppearanceCoordinator(appearance: appearance)
    }

    private func publishAppearanceState() {
        appearance = appearanceCoordinator.appearance
    }

    private func syncFileWorkspaceCoordinatorFromPublished() {
        fileWorkspaceCoordinator = FileWorkspaceCoordinator(
            tabs: workspaceFileTabs,
            dirtyTabIDs: dirtyWorkspaceFileTabIDs,
            externallyChangedTabIDs: externallyChangedWorkspaceFileTabIDs,
            selectedContentTabID: selectedWorkspaceContentTabID
        )
    }

    private func currentWorkspaceContentState() -> WorkspaceContentRuntimeState {
        WorkspaceContentRuntimeState(
            webTabs: workspaceWebTabs,
            fileTabs: workspaceFileTabs,
            dirtyFileTabIDs: dirtyWorkspaceFileTabIDs,
            externallyChangedFileTabIDs: externallyChangedWorkspaceFileTabIDs,
            selectedContentTabID: selectedWorkspaceContentTabID
        )
    }

    private func saveSelectedWorkspaceContentState() {
        workspaceContentStatesByWorkspaceID[workspace.id] = currentWorkspaceContentState()
    }

    private func applyWorkspaceContentState(for workspaceID: WorkspaceID) {
        let state = workspaceContentStatesByWorkspaceID[workspaceID] ?? WorkspaceContentRuntimeState()
        workspaceWebTabs = state.webTabs
        workspaceFileTabs = state.fileTabs
        dirtyWorkspaceFileTabIDs = state.dirtyFileTabIDs
        externallyChangedWorkspaceFileTabIDs = state.externallyChangedFileTabIDs
        selectedWorkspaceContentTabID = Self.validatedWorkspaceContentSelection(
            Self.persistedWorkspaceContentSelection(state.selectedContentTabID),
            workspace: workspace,
            webTabs: state.webTabs,
            fileTabIDs: Set(state.fileTabs.map(\.id))
        )
        pruneWorkspaceWebTabCommands(keeping: Set(state.webTabs.map(\.id)))
        syncFileWorkspaceCoordinatorFromPublished()
        syncPanelCoordinatorFromPublished()
    }

    private func removeWorkspaceContentState(for workspaceID: WorkspaceID) {
        workspaceContentStatesByWorkspaceID.removeValue(forKey: workspaceID)
        ConductorWebKitSurfaceStore.shared.keepOnly(retainedWebTabIDsForSurfaceStore(excluding: [workspaceID]))
    }

    private func removeWorkspaceContentStates(for workspaceIDs: Set<WorkspaceID>) {
        guard !workspaceIDs.isEmpty else { return }
        for workspaceID in workspaceIDs {
            workspaceContentStatesByWorkspaceID.removeValue(forKey: workspaceID)
        }
        ConductorWebKitSurfaceStore.shared.keepOnly(retainedWebTabIDsForSurfaceStore(excluding: workspaceIDs))
    }

    private func duplicatedContentState(from source: WorkspaceContentRuntimeState) -> WorkspaceContentRuntimeState {
        var webIDMap: [WebTabID: WebTabID] = [:]
        let webTabs = source.webTabs.map { tab in
            let copiedID = WebTabID()
            webIDMap[tab.id] = copiedID
            return WorkspaceWebTabState(
                id: copiedID,
                url: tab.url,
                pendingAddress: tab.pendingAddress,
                title: tab.title,
                faviconURL: tab.faviconURL,
                isLoading: false,
                estimatedProgress: 0,
                canGoBack: false,
                canGoForward: false,
                errorMessage: tab.errorMessage
            )
        }

        let selection: ConductorWorkspaceContentTabID?
        switch source.selectedContentTabID {
        case .file(let tabID):
            selection = source.fileTabs.contains(where: { $0.id == tabID }) ? .file(tabID) : nil
        case .web(let tabID):
            selection = webIDMap[tabID].map { .web($0) }
        case .terminal, nil:
            selection = nil
        }

        return WorkspaceContentRuntimeState(
            webTabs: webTabs,
            fileTabs: source.fileTabs,
            selectedContentTabID: selection
        )
    }

    @discardableResult
    private func publishFileWorkspaceState() -> Bool {
        var changed = false
        if workspaceFileTabs != fileWorkspaceCoordinator.tabs {
            workspaceFileTabs = fileWorkspaceCoordinator.tabs
            changed = true
        }
        if dirtyWorkspaceFileTabIDs != fileWorkspaceCoordinator.dirtyTabIDs {
            dirtyWorkspaceFileTabIDs = fileWorkspaceCoordinator.dirtyTabIDs
            changed = true
        }
        if externallyChangedWorkspaceFileTabIDs != fileWorkspaceCoordinator.externallyChangedTabIDs {
            externallyChangedWorkspaceFileTabIDs = fileWorkspaceCoordinator.externallyChangedTabIDs
            changed = true
        }
        if selectedWorkspaceContentTabID != fileWorkspaceCoordinator.selectedContentTabID {
            selectedWorkspaceContentTabID = fileWorkspaceCoordinator.selectedContentTabID
            changed = true
        }
        return changed
    }

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
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setDensity(density)
        publishAppearanceState()
    }

    func setFontScale(_ fontScale: AppearanceFontScale) {
        guard appearance.fontScale != fontScale else { return }
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setFontScale(fontScale)
        publishAppearanceState()
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
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setTerminalFontSize(terminalFontSize)
        publishAppearanceState()
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
        let rounded = AppearanceCoordinator.roundedTerminalBackgroundOpacity(opacity)
        guard appearance.terminalRenderer.backgroundOpacity != rounded else { return }
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setTerminalBackgroundOpacity(opacity)
        publishAppearanceState()
    }

    func setTerminalBackgroundBlur(_ enabled: Bool) {
        let blurOverride = appearance.terminalRenderer.ghosttyOverride(for: "background-blur")
        let value = enabled ? "true" : "false"
        guard blurOverride.enabled != true || blurOverride.normalizedValue != value else { return }
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setTerminalBackgroundBlur(enabled)
        publishAppearanceState()
    }

    func setTerminalBackgroundImageURL(_ imageURL: URL?) {
        let value = imageURL?.standardizedFileURL.path ?? ""
        let imageOverride = appearance.terminalRenderer.ghosttyOverride(for: "background-image")
        guard imageOverride.enabled != (!value.isEmpty) || imageOverride.normalizedValue != value else { return }
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setTerminalBackgroundImageURL(imageURL)
        publishAppearanceState()
    }

    func setTerminalBackgroundImageMode(_ imageMode: String) {
        let value = imageMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageModeOverride = appearance.terminalRenderer.ghosttyOverride(for: "background-image-fit")
        guard imageModeOverride.enabled != (!value.isEmpty) || imageModeOverride.normalizedValue != value else { return }
        syncAppearanceCoordinatorFromPublished()
        appearanceCoordinator.setTerminalBackgroundImageMode(imageMode)
        publishAppearanceState()
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

    func setTerminalScrollbackLimit(_ value: String) {
        let key = "scrollback-limit"
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var overrides = appearance.terminalRenderer.ghosttyOverrides.filter { $0.key != key }
        if !normalizedValue.isEmpty {
            overrides.append(TerminalGhosttyConfigOverride(key: key, value: normalizedValue, enabled: true))
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

    func setAgentReplyNotificationsEnabled(_ enabled: Bool) {
        guard appearance.agentReplyNotifications.enabled != enabled else { return }
        appearance.agentReplyNotifications.enabled = enabled
        if enabled {
            agentReplyNotificationService.requestAuthorization { [weak self] granted in
                guard let self else { return }
                self.notificationAuthorizationState = granted ? .authorized : .denied
                self.agentHookSettingsMessage = granted
                    ? L("工作完成通知已开启，正在配置终端 Hook。", "Work completion notifications enabled. Configuring terminal hooks.")
                    : L("通知权限未开启，请在系统设置里允许 Conductor 发送通知。", "Notifications are not allowed. Enable Conductor notifications in System Settings.")
                if granted {
                    self.installAgentReplyNotificationHooks()
                }
            }
        }
    }

    func setAgentReplyNotificationsOnlyWhenUnattended(_ onlyWhenUnattended: Bool) {
        guard appearance.agentReplyNotifications.onlyWhenUnattended != onlyWhenUnattended else { return }
        appearance.agentReplyNotifications.onlyWhenUnattended = onlyWhenUnattended
    }

    func setAgentReplyNotificationsIncludeSummary(_ includeSummary: Bool) {
        guard appearance.agentReplyNotifications.includeSummary != includeSummary else { return }
        appearance.agentReplyNotifications.includeSummary = includeSummary
    }

    func setAgentReplyNotificationsPlaySound(_ playSound: Bool) {
        guard appearance.agentReplyNotifications.playSound != playSound else { return }
        appearance.agentReplyNotifications.playSound = playSound
    }

    private func configureNotificationDeliveryIssueHandler() {
        agentReplyNotificationService.deliveryIssueHandler = { [weak self] issue in
            self?.handleAgentNotificationDeliveryIssue(issue)
        }
    }

    private func handleAgentNotificationDeliveryIssue(_ issue: AgentReplyNotificationDeliveryIssue) {
        switch issue {
        case .permissionUnavailable:
            showShellToast(
                title: L("系统通知没有显示", "System Notification Not Shown"),
                body: L(
                    "若要看到横幅，请在系统设置里允许 Conductor 通知。",
                    "Allow Conductor notifications in System Settings to show banners."
                ),
                systemImage: "bell.slash",
                tone: .warning,
                actionTitle: L("打开系统设置", "Open Settings"),
                action: .openNotificationSettings,
                duration: 7
            )
        case .deliveryFailed(let message):
            showShellToast(
                title: L("通知发送失败", "Notification Delivery Failed"),
                body: message.isEmpty
                    ? L("系统通知暂时没有投递成功，可以稍后重试。", "The system notification was not delivered. Try again later.")
                    : String(message.prefix(160)),
                systemImage: "exclamationmark.triangle",
                tone: .error,
                actionTitle: L("检查权限", "Check Permission"),
                action: .checkNotificationPermission,
                duration: 7
            )
        }
    }

    func refreshNotificationAuthorizationState() {
        agentReplyNotificationService.checkAuthorizationStatus { [weak self] state in
            self?.notificationAuthorizationState = state
        }
    }

    func checkNotificationPermissionFromToolbar() {
        showSettingsPanel(section: .automation)
        notificationDeliveryTestMessage = nil
        agentHookSettingsMessage = L("正在检测 macOS 通知权限...", "Checking macOS notification permission...")
        agentReplyNotificationService.checkAuthorizationStatus { [weak self] state in
            guard let self else { return }
            self.notificationAuthorizationState = state
            switch state {
            case .authorized:
                self.appearance.agentReplyNotifications.enabled = true
                self.agentHookSettingsMessage = L(
                    "通知权限已开启，后台命令、终端提醒和任务回复会尝试发送系统横幅。",
                    "Notifications are allowed. Background commands, terminal alerts, and task replies can send system banners."
                )
                self.installAgentReplyNotificationHooks()
            case .notDetermined:
                self.agentReplyNotificationService.requestAuthorization { [weak self] granted in
                    guard let self else { return }
                    self.notificationAuthorizationState = granted ? .authorized : .denied
                    self.appearance.agentReplyNotifications.enabled = granted
                    self.agentHookSettingsMessage = granted
                        ? L("通知权限已开启，正在配置终端 Hook。", "Notifications are allowed. Configuring terminal hooks.")
                        : L("通知权限未开启，请在系统设置里允许 Conductor 发送通知。", "Notifications are not allowed. Enable Conductor notifications in System Settings.")
                    if granted {
                        self.installAgentReplyNotificationHooks()
                    } else {
                        self.openSystemNotificationSettings()
                    }
                }
            case .denied:
                self.agentHookSettingsMessage = L(
                    "macOS 已拒绝通知权限，请在系统设置里允许 Conductor 发送通知。",
                    "macOS notification permission is denied. Enable Conductor notifications in System Settings."
                )
                self.openSystemNotificationSettings()
            case .unavailable:
                self.agentHookSettingsMessage = L(
                    "当前运行环境无法申请系统通知，请从 Conductor.app 启动后再试。",
                    "System notifications are unavailable in this launch context. Start from Conductor.app and try again."
                )
            case .unknown:
                self.agentHookSettingsMessage = L(
                    "暂时无法确认系统通知权限，请在系统设置里检查 Conductor 的通知设置。",
                    "Could not confirm notification permission. Check Conductor notification settings in System Settings."
                )
                self.openSystemNotificationSettings()
            }
        }
    }

    func sendTestSystemNotificationFromSettings() {
        notificationDeliveryTestMessage = L(
            "正在发送测试通知...",
            "Sending a test notification..."
        )
        let title = L("Conductor 测试通知", "Conductor Test Notification")
        let body = L(
            "如果你看到这条横幅，系统通知投递正常。",
            "If you see this banner, system notification delivery is working."
        )
        agentReplyNotificationService.sendTestNotification(
            title: title,
            body: body,
            playSound: appearance.agentReplyNotifications.playSound
        ) { [weak self] result in
            guard let self else { return }
            self.notificationAuthorizationState = result.authorizationState
            if result.status == .delivered {
                self.appearance.agentReplyNotifications.enabled = true
            }
            self.notificationDeliveryTestMessage = self.notificationTestMessage(for: result)
        }
    }

    func controlSendSystemNotificationTest(
        title: String,
        body: String,
        playSound: Bool?
    ) async -> AgentReplyNotificationTestResult {
        await withCheckedContinuation { continuation in
            agentReplyNotificationService.sendTestNotification(
                title: title,
                body: body,
                playSound: playSound ?? appearance.agentReplyNotifications.playSound
            ) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: result)
                    return
                }
                self.notificationAuthorizationState = result.authorizationState
                self.notificationDeliveryTestMessage = self.notificationTestMessage(for: result)
                continuation.resume(returning: result)
            }
        }
    }

    private func notificationTestMessage(for result: AgentReplyNotificationTestResult) -> String {
        switch result.status {
        case .delivered:
            return L(
                "测试通知已交给 Notification Center。如果仍然没有横幅，请检查专注模式和系统横幅样式。",
                "The test notification was handed to Notification Center. If no banner appeared, check Focus mode and banner style."
            )
        case .permissionUnavailable:
            if !result.launchSupportsSystemNotifications {
                return L(
                    "当前启动方式不能显示系统横幅；请从正式 Conductor.app 启动后再测试。",
                    "This launch mode cannot show system banners; start from Conductor.app and test again."
                )
            }
            if result.authorizationState == .denied {
                return L(
                    "macOS 已拒绝通知权限；请在系统设置里允许 Conductor。",
                    "macOS denied notification permission; allow Conductor in System Settings."
                )
            }
            return result.errorMessage ?? L(
                "系统通知当前不可用，请检查 macOS 通知设置。",
                "System notifications are unavailable. Check macOS notification settings."
            )
        case .deliveryFailed:
            let message = result.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let message, !message.isEmpty {
                return L("测试通知发送失败：\(message)", "Test notification failed: \(message)")
            }
            return L(
                "测试通知发送失败，请检查 macOS 通知设置。",
                "Test notification failed. Check macOS notification settings."
            )
        }
    }

    func installAgentReplyNotificationActivationHandler(_ handler: @escaping (UUID?, TerminalID?) -> Void) {
        agentReplyNotificationService.activateNotificationTarget = handler
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func installAgentReplyNotificationHooks(bridgePath: String? = nil) {
        guard appearance.agentReplyNotifications.enabled else { return }
        guard let resolvedBridgePath = bridgePath ?? Bundle.main.executablePath ?? CommandLine.arguments.first,
              !resolvedBridgePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            agentHookSettingsMessage = L("通知 Hook 配置失败：找不到 Conductor 可执行文件。", "Notification hook setup failed: Conductor executable was not found.")
            return
        }

        agentReplyNotificationService.requestAuthorization { [weak self] granted in
            guard !granted else { return }
            self?.agentHookSettingsMessage = L(
                "通知权限未开启，请在系统设置里允许 Conductor 发送通知。",
                "Notifications are not allowed. Enable Conductor notifications in System Settings."
            )
        }

        Task.detached(priority: .utility) {
            let results = AgentNotificationHookInstaller.installAll(bridgePath: resolvedBridgePath)
            let installed = results.compactMap { result -> String? in
                guard case let .success(providerName) = result else { return nil }
                return providerName
            }
            let errors = results.compactMap { result -> String? in
                guard case let .failure(error) = result else { return nil }
                return error.localizedDescription
            }
            await MainActor.run {
                if installed.isEmpty {
                    self.agentHookSettingsMessage = errors.first
                        ?? L("通知 Hook 配置失败。", "Notification hook setup failed.")
                } else {
                    self.agentHookSettingsMessage = L(
                        "已配置 \(installed.joined(separator: " / ")) 回复通知 Hook。",
                        "Configured reply notification hooks for \(installed.joined(separator: " / "))."
                    )
                }
            }
        }
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

    func setUpdateManifestURL(_ value: String, persist: Bool = true) {
        guard updatePreferences.manifestURLString != value else { return }
        updatePreferences.manifestURLString = value
        if persist {
            updatePreferencesStore.save(updatePreferences)
            synchronizeAutomaticUpdateChecks()
        }
    }

    func cancelUpdateOperation() {
        updateTask?.cancel()
        updateTask = nil

        switch updateState.phase {
        case .checking:
            updateState = ConductorUpdateState(
                currentVersion: ConductorAppVersion.current(),
                lastCheckedAt: updateState.lastCheckedAt
            )
        case .downloading:
            var availableState = updateState
            availableState.phase = updateState.manifest == nil ? .idle : .available
            availableState.downloadProgress = nil
            updateState = availableState
        default:
            break
        }
    }

    func setAutomaticUpdateChecksEnabled(_ enabled: Bool) {
        guard updatePreferences.automaticChecksEnabled != enabled else { return }
        updatePreferences.automaticChecksEnabled = enabled
        updatePreferencesStore.save(updatePreferences)
        synchronizeAutomaticUpdateChecks()
    }

    func setPrefersDeltaUpdates(_ enabled: Bool) {
        guard updatePreferences.prefersDeltaUpdates != enabled else { return }
        updatePreferences.prefersDeltaUpdates = enabled
        updatePreferencesStore.save(updatePreferences)
    }

    func startUpdateChecksIfNeeded() {
        synchronizeAutomaticUpdateChecks()
    }

    private func synchronizeAutomaticUpdateChecks() {
        automaticUpdateDiagnostics.isEnabled = updatePreferences.automaticChecksEnabled
        guard updatePreferences.automaticChecksEnabled,
              updatePreferences.manifestURL != nil else {
            stopAutomaticUpdateChecks()
            return
        }
        guard automaticUpdateCheckTask == nil else { return }
        automaticUpdateCheckGeneration &+= 1
        let generation = automaticUpdateCheckGeneration
        scheduleAutomaticUpdateCheck(after: Self.automaticUpdateInitialDelayNanoseconds)
        automaticUpdateCheckTask = Task { @MainActor [weak self] in
            await self?.runAutomaticUpdateChecks(generation: generation)
        }
    }

    private func stopAutomaticUpdateChecks() {
        automaticUpdateCheckGeneration &+= 1
        automaticUpdateCheckTask?.cancel()
        automaticUpdateCheckTask = nil
        automaticUpdateDiagnostics.isEnabled = updatePreferences.automaticChecksEnabled
        automaticUpdateDiagnostics.isRunning = false
        automaticUpdateDiagnostics.currentIntervalSeconds = nil
        automaticUpdateDiagnostics.nextCheckAt = nil
    }

    private func runAutomaticUpdateChecks(generation: UInt64) async {
        var sleepNanoseconds = Self.automaticUpdateInitialDelayNanoseconds
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: sleepNanoseconds)
            } catch {
                break
            }

            guard generation == automaticUpdateCheckGeneration else { break }
            guard updatePreferences.automaticChecksEnabled,
                  updatePreferences.manifestURL != nil else {
                break
            }

            let outcome: ConductorUpdateCheckOutcome
            if updateState.canCheck {
                automaticUpdateDiagnostics.lastAttemptAt = Date()
                automaticUpdateDiagnostics.currentIntervalSeconds = nil
                automaticUpdateDiagnostics.nextCheckAt = nil
                outcome = await withCheckedContinuation { continuation in
                    var didResume = false
                    _ = startUpdateCheck(manual: false) { checkOutcome in
                        guard !didResume else { return }
                        didResume = true
                        continuation.resume(returning: checkOutcome)
                    }
                }
            } else {
                outcome = .skipped
            }
            sleepNanoseconds = nextAutomaticUpdateDelay(after: outcome)
            scheduleAutomaticUpdateCheck(after: sleepNanoseconds)
        }

        if generation == automaticUpdateCheckGeneration {
            automaticUpdateCheckTask = nil
            automaticUpdateDiagnostics.isRunning = false
            automaticUpdateDiagnostics.nextCheckAt = nil
            automaticUpdateDiagnostics.currentIntervalSeconds = nil
        }
    }

    func checkForUpdates(manual: Bool = true) {
        _ = startUpdateCheck(manual: manual, completion: nil)
    }

    @discardableResult
    private func startUpdateCheck(
        manual: Bool = true,
        completion: (@MainActor (ConductorUpdateCheckOutcome) -> Void)?
    ) -> Bool {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let sampleSource = manual ? "ui.update.manual" : "ui.update.automatic"
        guard updateState.canCheck else {
            completion?(.skipped)
            return false
        }
        guard let manifestURL = updatePreferences.manifestURL else {
            if manual {
                updateState = ConductorUpdateState(
                    phase: .failed(L("请先填写更新清单地址。", "Enter an update manifest URL first.")),
                    currentVersion: ConductorAppVersion.current()
                )
                recordPerformanceBudgetSample(
                    budgetID: "update.check",
                    startedAt: startedAt,
                    source: sampleSource
                )
            }
            completion?(.skipped)
            return false
        }

        updateTask?.cancel()
        let preferences = updatePreferences
        let currentVersion = ConductorAppVersion.current()
        let previousState = updateState
        if manual {
            updateState = ConductorUpdateState(
                phase: .checking,
                currentVersion: currentVersion,
                lastCheckedAt: updateState.lastCheckedAt
            )
        }
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let manifest = try await updateService.fetchManifest(from: manifestURL)
                try Task.checkCancellation()
                let selected = manifest.selectedArtifact(prefersDeltaUpdates: preferences.prefersDeltaUpdates)
                let availableVersion = manifest.targetVersion
                let isAvailable = availableVersion > currentVersion
                updateState = ConductorUpdateState(
                    phase: isAvailable ? .available : .upToDate,
                    currentVersion: currentVersion,
                    availableVersion: isAvailable ? availableVersion : nil,
                    manifest: manifest,
                    selectedPackageKind: isAvailable ? selected.kind : nil,
                    selectedArtifact: isAvailable ? selected.artifact : nil,
                    lastCheckedAt: Date()
                )
                recordPerformanceBudgetSample(
                    budgetID: "update.check",
                    startedAt: startedAt,
                    source: sampleSource
                )
                completion?(.success)
            } catch is CancellationError {
                completion?(.cancelled)
            } catch {
                let message = localizedUpdateError(error)
                if manual {
                    updateState = ConductorUpdateState(
                        phase: .failed(message),
                        currentVersion: currentVersion,
                        lastCheckedAt: Date()
                    )
                } else {
                    var restoredState = previousState
                    restoredState.lastCheckedAt = Date()
                    updateState = restoredState
                }
                recordPerformanceBudgetSample(
                    budgetID: "update.check",
                    startedAt: startedAt,
                    source: sampleSource
                )
                completion?(.failure(message))
            }
        }
        return true
    }

    private func scheduleAutomaticUpdateCheck(after delayNanoseconds: UInt64) {
        automaticUpdateDiagnostics.isEnabled = updatePreferences.automaticChecksEnabled
        automaticUpdateDiagnostics.isRunning = true
        automaticUpdateDiagnostics.currentIntervalSeconds = Double(delayNanoseconds) / 1_000_000_000
        automaticUpdateDiagnostics.nextCheckAt = Date().addingTimeInterval(
            Double(delayNanoseconds) / 1_000_000_000
        )
    }

    private func nextAutomaticUpdateDelay(after outcome: ConductorUpdateCheckOutcome) -> UInt64 {
        let completedAt = Date()
        automaticUpdateDiagnostics.lastCompletedAt = completedAt
        switch outcome {
        case .success:
            if automaticUpdateDiagnostics.consecutiveFailures > 0 {
                ConductorDiagnostics.record("update-automatic-check-recovered", fields: [
                    "failures": automaticUpdateDiagnostics.consecutiveFailures
                ])
            }
            automaticUpdateDiagnostics.consecutiveFailures = 0
            automaticUpdateDiagnostics.lastSuccessAt = completedAt
            automaticUpdateDiagnostics.lastFailureDescription = nil
            return Self.automaticUpdateCheckIntervalNanoseconds
        case .failure(let message):
            automaticUpdateDiagnostics.consecutiveFailures += 1
            automaticUpdateDiagnostics.lastFailureAt = completedAt
            automaticUpdateDiagnostics.lastFailureDescription = message
            let delay = automaticUpdateBackoffDelay(
                consecutiveFailures: automaticUpdateDiagnostics.consecutiveFailures
            )
            ConductorDiagnostics.record("update-automatic-check-failed", fields: [
                "failures": automaticUpdateDiagnostics.consecutiveFailures,
                "nextDelaySeconds": Int(delay / 1_000_000_000),
                "reason": message
            ])
            return delay
        case .skipped, .cancelled:
            return Self.automaticUpdateCheckIntervalNanoseconds
        }
    }

    private func automaticUpdateBackoffDelay(consecutiveFailures: Int) -> UInt64 {
        guard consecutiveFailures > 0 else {
            return Self.automaticUpdateCheckIntervalNanoseconds
        }
        let multiplier = min(1 << min(consecutiveFailures, 3), 6)
        let delay = Self.automaticUpdateCheckIntervalNanoseconds * UInt64(multiplier)
        return min(delay, Self.automaticUpdateMaximumIntervalNanoseconds)
    }

    func downloadAvailableUpdate() {
        guard updateState.canDownload,
              let manifest = updateState.manifest,
              let selectedKind = updateState.selectedPackageKind,
              let selectedArtifact = updateState.selectedArtifact,
              let manifestURL = updatePreferences.manifestURL else {
            return
        }

        updateTask?.cancel()
        var downloadingState = updateState
        downloadingState.phase = .downloading
        downloadingState.downloadProgress = ConductorDownloadProgress(
            bytesWritten: 0,
            expectedBytes: selectedArtifact.size
        )
        updateState = downloadingState
        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let downloadedUpdate = try await updateService.downloadPackage(
                    manifest: manifest,
                    manifestURL: manifestURL,
                    kind: selectedKind,
                    artifact: selectedArtifact,
                    progress: { progress in
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            guard self.updateState.phase == .downloading else { return }
                            var nextState = self.updateState
                            nextState.downloadProgress = progress
                            self.updateState = nextState
                        }
                    }
                )
                try Task.checkCancellation()
                updateState = ConductorUpdateState(
                    phase: .downloaded,
                    currentVersion: ConductorAppVersion.current(),
                    availableVersion: manifest.targetVersion,
                    manifest: manifest,
                    selectedPackageKind: downloadedUpdate.kind,
                    selectedArtifact: downloadedUpdate.artifact,
                    downloadedPackageURL: downloadedUpdate.packageURL,
                    lastCheckedAt: updateState.lastCheckedAt
                )
            } catch is CancellationError {
            } catch {
                var failedState = updateState
                failedState.phase = .failed(localizedUpdateError(error))
                failedState.downloadProgress = nil
                updateState = failedState
            }
        }
    }

    func installDownloadedUpdateAndRelaunch() {
        guard updateState.canInstall,
              let manifest = updateState.manifest,
              let selectedKind = updateState.selectedPackageKind,
              let selectedArtifact = updateState.selectedArtifact,
              let packageURL = updateState.downloadedPackageURL,
              let manifestURL = updatePreferences.manifestURL else {
            return
        }

        let downloadedUpdate = ConductorDownloadedUpdate(
            packageURL: packageURL,
            artifactURL: manifestURL.deletingLastPathComponent().appendingPathComponent(selectedArtifact.filename),
            kind: selectedKind,
            manifest: manifest,
            artifact: selectedArtifact
        )
        var installingState = updateState
        installingState.phase = .installing
        updateState = installingState
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let preparedUpdate = try await updateService.prepareInstaller(for: downloadedUpdate)
                try updateService.launchInstallerAndTerminate(preparedUpdate)
            } catch {
                var failedState = updateState
                failedState.phase = .failed(localizedUpdateError(error))
                updateState = failedState
            }
        }
    }

    func rehearseDownloadedUpdateInstall() async throws -> ConductorInstallRehearsalResult {
        guard updateState.canInstall,
              let manifest = updateState.manifest,
              let selectedKind = updateState.selectedPackageKind,
              let selectedArtifact = updateState.selectedArtifact,
              let packageURL = updateState.downloadedPackageURL,
              let manifestURL = updatePreferences.manifestURL else {
            throw ConductorUpdateError.missingDownloadedPackage
        }

        let downloadedUpdate = ConductorDownloadedUpdate(
            packageURL: packageURL,
            artifactURL: manifestURL.deletingLastPathComponent().appendingPathComponent(selectedArtifact.filename),
            kind: selectedKind,
            manifest: manifest,
            artifact: selectedArtifact
        )
        let result = try await updateService.rehearseInstaller(for: downloadedUpdate)
        ConductorDiagnostics.record("update-install-rehearsal-complete", fields: [
            "script": result.scriptURL.path,
            "log": result.logURL.path,
            "status": result.exitStatus
        ])
        return result
    }

    func showUpdatesAndCheck() {
        showSettingsPanel(section: .updates)
        checkForUpdates(manual: true)
    }

    private func localizedUpdateError(_ error: Error) -> String {
        if let updateError = error as? ConductorUpdateError {
            switch updateError {
            case .missingManifestURL:
                return L("请先填写更新清单地址。", "Enter an update manifest URL first.")
            case .invalidHTTPStatus(let status):
                return L("更新服务器返回 HTTP \(status)。", "Update server returned HTTP \(status).")
            case .invalidManifest(let reason):
                return L("更新清单无法读取：\(reason)", "Update manifest could not be read: \(reason)")
            case .noAppBundle:
                return L("需要从 .app 包启动后才能自动替换。", "Conductor must be running from a .app bundle to replace itself.")
            case .checksumMismatch:
                return L("下载包校验失败，已停止安装。", "Downloaded update failed checksum verification.")
            case .missingDownloadedPackage:
                return L("找不到已下载的更新包。", "Downloaded update package was not found.")
            case .installerLaunchFailed(let reason):
                return L("无法启动安装器：\(reason)", "Could not start the installer: \(reason)")
            case .installerRehearsalFailed(let status, _):
                return L("安装演练失败，退出码 \(status)。", "Install rehearsal failed with status \(status).")
            }
        }
        return error.localizedDescription
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
        installTerminalTabDragEndMonitors(generation: generation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self,
                  self.terminalTabDragGeneration == generation else {
                return
            }
            self.finishTerminalTabDragIfCurrent(generation: generation)
        }
    }

    func endTerminalTabDrag() {
        terminalTabDragGeneration &+= 1
        removeTerminalTabDragEndMonitors()
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

    private func installTerminalTabDragEndMonitors(generation: UInt64) {
        removeTerminalTabDragEndMonitors()
        terminalTabDragLocalMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.scheduleTerminalTabDragEndConfirmation(generation: generation)
            return event
        }
        terminalTabDragGlobalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.scheduleTerminalTabDragEndConfirmation(generation: generation)
            }
        }
    }

    private func scheduleTerminalTabDragEndConfirmation(generation: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.finishTerminalTabDragIfCurrent(generation: generation)
        }
    }

    private func finishTerminalTabDragIfCurrent(generation: UInt64) {
        guard terminalTabDragGeneration == generation else { return }
        endTerminalTabDrag()
    }

    private func removeTerminalTabDragEndMonitors() {
        if let terminalTabDragLocalMouseUpMonitor {
            NSEvent.removeMonitor(terminalTabDragLocalMouseUpMonitor)
            self.terminalTabDragLocalMouseUpMonitor = nil
        }
        if let terminalTabDragGlobalMouseUpMonitor {
            NSEvent.removeMonitor(terminalTabDragGlobalMouseUpMonitor)
            self.terminalTabDragGlobalMouseUpMonitor = nil
        }
    }

    func setTerminalTabDropTarget(for terminalID: TerminalID, target: TerminalTabDropTarget?) {
        guard let paneID = workspace.paneID(containing: terminalID) else { return }
        setTerminalTabDropTarget(forPane: paneID, target: target)
    }

    func setTerminalTabDropTarget(forPane paneID: PaneID, target: TerminalTabDropTarget?) {
        if let target {
            guard let draggedTerminalID = activeTerminalTabDragID,
                  canPerformTerminalTabDrop(draggedTerminalID, targetPaneID: paneID, target: target) else {
                if terminalTabDropTargetByPaneID[paneID] != nil {
                    terminalTabDropTargetByPaneID.removeValue(forKey: paneID)
                }
                return
            }
            guard terminalTabDropTargetByPaneID[paneID] != target else { return }
            terminalTabDropTargetByPaneID[paneID] = target
        } else {
            guard terminalTabDropTargetByPaneID[paneID] != nil else { return }
            terminalTabDropTargetByPaneID.removeValue(forKey: paneID)
        }
    }

    @discardableResult
    func performTerminalTabDrop(_ draggedTerminalID: TerminalID, targetPaneID: PaneID, target: TerminalTabDropTarget) -> Bool {
        guard canPerformTerminalTabDrop(draggedTerminalID, targetPaneID: targetPaneID, target: target) else {
            endTerminalTabDrag()
            return false
        }
        terminalTabDropTargetByPaneID.removeValue(forKey: targetPaneID)
        let sourcePaneID = workspace.paneID(containing: draggedTerminalID)
        ConductorMotion.perform(ConductorMotion.layout) {
            if target == .center {
                guard sourcePaneID != targetPaneID else { return }
                self.moveTabToEnd(draggedTerminalID, in: targetPaneID)
            } else {
                self.moveTabToSplit(draggedTerminalID, targetPaneID: targetPaneID, direction: target.direction)
            }
        }
        endTerminalTabDrag()
        return true
    }

    func canPerformTerminalTabDrop(_ draggedTerminalID: TerminalID, targetPaneID: PaneID, target: TerminalTabDropTarget) -> Bool {
        guard let sourcePaneID = workspace.paneID(containing: draggedTerminalID),
              let sourcePane = workspace.panes[sourcePaneID],
              workspace.panes[targetPaneID] != nil else {
            return false
        }
        if target == .center {
            return sourcePaneID != targetPaneID && (sourcePane.tabs.count > 1 || workspace.panes.count > 1)
        }
        return workspace.canMoveTabToSplit(draggedTerminalID, targetPaneID: targetPaneID)
    }

    func canPerformCommand(_ command: ConductorShellCommand) -> Bool {
        command.canPerform(model: self)
    }

    struct ShellCommandRanking: Equatable {
        var score: Int
        var recentRank: Int?
        var contextReasons: [String]

        var isRecent: Bool {
            recentRank != nil
        }

        var isContextual: Bool {
            !contextReasons.isEmpty
        }

        var badge: String? {
            if let recentRank, recentRank < 3 {
                return ConductorLocalization.text(zh: "最近", en: "Recent")
            }
            return contextReasons.first
        }
    }

    func shellCommandRanking(for command: ConductorShellCommand) -> ShellCommandRanking {
        let recentRank = recentShellCommandIDs.firstIndex(of: command.rawValue)
        let contextReasons = shellCommandContextReasons(for: command)
        var score = canPerformCommand(command) ? 1_000 : -1_000
        if let recentRank {
            score += max(0, 420 - recentRank * 42)
        }
        score += contextReasons.count * 120
        return ShellCommandRanking(
            score: score,
            recentRank: recentRank,
            contextReasons: contextReasons
        )
    }

    func shellCommandsForPalette() -> [ConductorShellCommand] {
        let originalIndex = Dictionary(uniqueKeysWithValues: ConductorShellCommand.paletteOrder.enumerated().map { ($0.element, $0.offset) })
        return ConductorShellCommand.paletteOrder.sorted { lhs, rhs in
            let lhsRank = shellCommandRanking(for: lhs)
            let rhsRank = shellCommandRanking(for: rhs)
            if lhsRank.score != rhsRank.score {
                return lhsRank.score > rhsRank.score
            }
            switch (lhsRank.recentRank, rhsRank.recentRank) {
            case let (lhsRecent?, rhsRecent?) where lhsRecent != rhsRecent:
                return lhsRecent < rhsRecent
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return (originalIndex[lhs] ?? 0) < (originalIndex[rhs] ?? 0)
            }
        }
    }

    private func shellCommandContextReasons(for command: ConductorShellCommand) -> [String] {
        var reasons: [String] = []
        let contentSelection = selectedWorkspaceContentTabID

        switch command {
        case .focusWebAddress, .goBackSelectedWebTab, .goForwardSelectedWebTab,
                .reloadSelectedWebTab, .openSelectedWebTabExternally,
                .copySelectedWebTabURL, .copySelectedWebTabReference:
            if case .web = contentSelection {
                reasons.append(ConductorLocalization.text(zh: "当前网页", en: "Current Web"))
            }
        case .openSelectedFileExternally, .revealSelectedFileInFinder:
            if case .file = contentSelection {
                reasons.append(ConductorLocalization.text(zh: "当前文件", en: "Current File"))
            }
        case .duplicateSelectedTab:
            switch contentSelection {
            case .terminal:
                reasons.append(ConductorLocalization.text(zh: "当前终端", en: "Current Terminal"))
            case .web:
                reasons.append(ConductorLocalization.text(zh: "当前网页", en: "Current Web"))
            case .file:
                reasons.append(ConductorLocalization.text(zh: "当前文件", en: "Current File"))
            case nil:
                break
            }
        case .toggleFileManager, .openFocusedDirectory, .copyFocusedDirectory,
                .newTerminalAtFocusedDirectory:
            if case .terminal = contentSelection {
                reasons.append(ConductorLocalization.text(zh: "当前目录", en: "Current CWD"))
            } else if case .file = contentSelection {
                reasons.append(ConductorLocalization.text(zh: "当前文件", en: "Current File"))
            }
        case .openCurrentWorkspaceRoot:
            if currentWorkspaceRootURL != nil {
                reasons.append(ConductorLocalization.text(zh: "当前工作区", en: "Current Workspace"))
            }
        case .openCurrentWorkspaceFirstService:
            if currentWorkspaceFirstLocalServiceURL != nil {
                reasons.append(ConductorLocalization.text(zh: "本地服务", en: "Local Service"))
            }
        case .showTerminalSearch, .findNext, .findPrevious:
            switch contentSelection {
            case .terminal:
                reasons.append(ConductorLocalization.text(zh: "当前终端", en: "Current Terminal"))
            case .web:
                reasons.append(ConductorLocalization.text(zh: "当前网页", en: "Current Web"))
            case .file:
                reasons.append(ConductorLocalization.text(zh: "当前文件", en: "Current File"))
            case nil:
                break
            }
        case .jumpLatestUnreadAttention, .markCurrentWorkspaceAttentionRead:
            if !controlAttentionEvents(includeRead: false).isEmpty {
                reasons.append(ConductorLocalization.text(zh: "有未读", en: "Unread"))
            }
        case .resumeCurrentWorkspaceAgents:
            if !controlResumableTerminalAgents(workspaceID: controlSelectedWorkspaceID).isEmpty {
                reasons.append(ConductorLocalization.text(zh: "可续接", en: "Resumable"))
            }
        default:
            break
        }

        return reasons
    }

    @discardableResult
    func performCommand(_ command: ConductorShellCommand, window: NSWindow? = nil) -> Bool {
        guard !settingsPanelVisible || command.allowsWhenSettingsPanelVisible else {
            ConductorDiagnostics.record(
                "shell-command-blocked-by-settings",
                fields: ["name": command.rawValue]
            )
            return false
        }
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
        if performed {
            recordRecentShellCommand(command)
        }
        return performed
    }

    private func recordRecentShellCommand(_ command: ConductorShellCommand) {
        guard command != .toggleCommandPalette else { return }
        var next = recentShellCommandIDs.filter { $0 != command.rawValue }
        next.insert(command.rawValue, at: 0)
        next = Array(next.prefix(Self.maxRecentShellCommandCount))
        guard next != recentShellCommandIDs else { return }
        recentShellCommandIDs = next
        Self.saveRecentShellCommandIDs(next)
    }

    private func schedulePerformanceBudgetSample(
        budgetID: String,
        startedAt: UInt64,
        source: String
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.recordPerformanceBudgetSample(
                budgetID: budgetID,
                startedAt: startedAt,
                source: source
            )
        }
    }

    private func recordPerformanceBudgetSample(
        budgetID: String,
        startedAt: UInt64,
        source: String
    ) {
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        guard let sample = ConductorPerformanceDiagnostics.shared.recordBudgetSample(
            budgetID: budgetID,
            durationNanoseconds: elapsed,
            source: source
        ) else {
            return
        }
        ConductorDiagnostics.record("performance-budget-sample", fields: [
            "budget": sample.budgetID,
            "durationMS": String(sample.durationMilliseconds),
            "targetMS": String(sample.targetMilliseconds),
            "status": sample.status,
            "source": sample.source
        ])
    }

    func setKeyboardShortcut(_ shortcut: KeyboardShortcutDefinition, for command: ConductorShellCommand) {
        appearance.keyboardShortcuts.set(shortcut, for: command)
    }

    func resetKeyboardShortcut(for command: ConductorShellCommand) {
        appearance.keyboardShortcuts.reset(command)
    }

    func resetKeyboardShortcuts() {
        appearance.keyboardShortcuts.resetAll()
    }

    func exportKeyboardShortcutProfile(to url: URL) throws -> Int {
        let profile = appearance.keyboardShortcuts.exportProfile()
        let data = try KeyboardShortcutProfileCodec.encode(profile)
        try data.write(to: url, options: [.atomic])
        ConductorDiagnostics.record(
            "shortcut-profile-export",
            fields: [
                "path": url.path,
                "count": "\(profile.entries.count)"
            ]
        )
        return profile.entries.count
    }

    func importKeyboardShortcutProfile(from url: URL) throws -> KeyboardShortcutProfileImportResult {
        let data = try Data(contentsOf: url)
        let profile = try KeyboardShortcutProfileCodec.decode(data)
        let result = appearance.keyboardShortcuts.importProfile(profile)
        ConductorDiagnostics.record(
            "shortcut-profile-import",
            fields: [
                "path": url.path,
                "imported": "\(result.importedCount)",
                "unknown": "\(result.ignoredUnknownCommandCount)",
                "rejected": "\(result.rejectedShortcutCount)",
                "conflicts": "\(result.replacedConflictCount)"
            ]
        )
        return result
    }

    func shortcutTitle(for command: ConductorShellCommand, fallback: String = "") -> String {
        appearance.keyboardShortcuts.displayShortcut(for: command, fallback: fallback)
    }

    func shortcutAssignmentTitle(for command: ConductorShellCommand) -> String {
        if appearance.keyboardShortcuts.hasCustomShortcut(for: command) {
            return ConductorLocalization.text(zh: "自定义", en: "Custom")
        }
        if appearance.keyboardShortcuts.shortcut(for: command) != nil {
            return ConductorLocalization.text(zh: "默认", en: "Default")
        }
        return ConductorLocalization.text(zh: "未设置", en: "Unassigned")
    }

    func shortcutConflictTitle(
        for shortcut: KeyboardShortcutDefinition,
        assigningTo command: ConductorShellCommand
    ) -> String? {
        guard let conflict = appearance.keyboardShortcuts.conflictingCommand(
            for: shortcut,
            assigningTo: command
        ) else {
            return nil
        }
        return conflict.displayTitle(model: self)
    }

    var runtimeSurfaceCount: Int {
        surfaceCoordinator.runtimeSurfaceCount
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

    var currentWorkspaceRootURL: URL? {
        guard let rootPath = workspaceMetadataSnapshots[workspace.id]?.rootPath?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !rootPath.isEmpty else {
            return nil
        }
        let expanded = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return url
    }

    var currentWorkspaceFirstLocalServiceURL: URL? {
        guard let metadata = workspaceMetadataSnapshots[workspace.id] else { return nil }
        if let server = metadata.devServers.first,
           let url = URL(string: server.url) {
            return url
        }
        guard let port = metadata.runningPorts.first else { return nil }
        return URL(string: "http://localhost:\(port)")
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
        surfaceCoordinator.hasSurface(for: terminalID)
    }

    func surface(for tab: TerminalTabState) -> TerminalSurface {
        if let surface = surfaceCoordinator.existingSurface(for: tab.id) {
            return surface
        }
        ConductorLog.performance.debug("surface create requested terminal=\(tab.id.description, privacy: .public) activeBefore=\(self.surfaceCoordinator.runtimeSurfaceCount, privacy: .public)")
        let surface = surfaceCoordinator.surface(
            for: tab,
            theme: theme,
            terminalFontSize: appearance.terminalFontSize,
            launchEnvironment: [:],
            handlers: TerminalSurfaceHandlers { [weak self] surface in
                self?.installTerminalSurfaceHandlers(surface)
            }
        )
        applyOcclusion()
        return surface
    }

    private func installTerminalSurfaceHandlers(_ surface: TerminalSurface) {
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
            return self.performTerminalTabDrop(draggedTerminalID, targetPaneID: targetPaneID, target: target)
        }
    }

    func newTerminal() {
        createTerminal(workingDirectory: nil, signpostName: "new-terminal")
    }

    @discardableResult
    private func createTerminal(workingDirectory: String?, signpostName: StaticString) -> TerminalID {
        let signpost = ConductorSignpost.begin(signpostName)
        defer { ConductorSignpost.end(signpostName, signpost) }
        let terminalID = workspace.newTerminal(
            title: nextTerminalTitle(prefix: "zsh"),
            workingDirectory: workingDirectory
        )
        markTerminalInteractionFocus()
        selectedWorkspaceContentTabID = .terminal(terminalID)
        return terminalID
    }

    func newTerminalAtFocusedDirectory() {
        createTerminal(
            workingDirectory: focusedWorkingDirectoryURL?.path,
            signpostName: "new-terminal-current-directory"
        )
    }

    @discardableResult
    private func newTerminalAtDirectory(for terminalID: TerminalID) -> Bool {
        guard activateTerminalContextTarget(terminalID) != nil else { return false }
        createTerminal(
            workingDirectory: workingDirectoryURL(for: terminalID)?.path,
            signpostName: "new-terminal-context-directory"
        )
        return true
    }

    func openFocusedDirectory() {
        guard let url = focusedWorkingDirectoryURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openCurrentWorkspaceRootInFinder() {
        guard let url = currentWorkspaceRootURL else { return }
        NSWorkspace.shared.open(url)
        ConductorDiagnostics.record(
            "workspace-open-root",
            fields: [
                "workspace": workspace.id.description,
                "path": url.path
            ]
        )
    }

    func openCurrentWorkspaceFirstLocalService() {
        guard let url = currentWorkspaceFirstLocalServiceURL else { return }
        newWorkspaceWebTab(initialInput: url.absoluteString)
        ConductorDiagnostics.record(
            "workspace-open-service",
            fields: [
                "workspace": workspace.id.description,
                "url": url.absoluteString
            ]
        )
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

    func newWorkspaceWebTab(initialInput: String = "") {
        let resolver = WebAddressResolver()
        let url = resolver.resolve(initialInput)
        var list = WorkspaceWebTabList(tabs: workspaceWebTabs, selectedTabID: selectedWorkspaceWebTabID)
        let id = list.append(url: url, pendingAddress: initialInput)
        workspaceWebTabs = list.tabs
        selectedWorkspaceContentTabID = .web(id)
        closeWorkspaceTransientPanels()
        if url != nil {
            workspaceWebTabNavigationGenerationByID[id, default: 0] += 1
        }
        persist()
    }

    func selectWorkspaceWebTab(_ tabID: WebTabID) {
        guard workspaceWebTabs.contains(where: { $0.id == tabID }) else { return }
        selectedWorkspaceContentTabID = .web(tabID)
        closeWorkspaceTransientPanels()
        persist()
    }

    func selectWorkspaceWebTab(_ tabID: WebTabID, in workspaceID: WorkspaceID) {
        if workspaceID != workspace.id {
            guard activateWorkspace(workspaceID, source: .programmatic) else { return }
        }
        selectWorkspaceWebTab(tabID)
    }

    func closeWorkspaceWebTab(_ tabID: WebTabID) {
        var list = WorkspaceWebTabList(tabs: workspaceWebTabs, selectedTabID: selectedWorkspaceWebTabID)
        let result = list.close(
            tabID,
            fallbackFileTabID: workspaceFileTabs.last?.id,
            fallbackTerminalID: focusedTerminalID
        )
        workspaceWebTabs = list.tabs
        applyWorkspaceContentSelection(result.nextContentSelection)
        if let closedTabID = result.closedTabID {
            ConductorWebKitSurfaceStore.shared.remove(closedTabID)
        }
        pruneWorkspaceWebTabCommands(keeping: Set(workspaceWebTabs.map(\.id)))
        persist()
    }

    func navigateWorkspaceWebTab(_ tabID: WebTabID, input: String) {
        guard let url = WebAddressResolver().resolve(input) else { return }
        updateWorkspaceWebTab(tabID) { tab in
            tab.url = url
            tab.pendingAddress = input
            tab.errorMessage = nil
            tab.runtimeEvents.removeAll()
            tab.isLoading = true
            tab.estimatedProgress = 0
        }
        workspaceWebTabNavigationGenerationByID[tabID, default: 0] += 1
        persist()
    }

    func reloadWorkspaceWebTab(_ tabID: WebTabID) {
        guard workspaceWebTabs.contains(where: { $0.id == tabID }) else { return }
        clearWorkspaceWebRuntimeEvents(tabID, reason: "reload")
        workspaceWebTabReloadGenerationByID[tabID, default: 0] += 1
    }

    func reloadOrStopSelectedWorkspaceWebTab() {
        guard let tab = selectedWorkspaceWebTab else { return }
        if tab.isLoading {
            stopWorkspaceWebTab(tab.id)
        } else {
            reloadWorkspaceWebTab(tab.id)
        }
    }

    func stopWorkspaceWebTab(_ tabID: WebTabID) {
        guard workspaceWebTabs.contains(where: { $0.id == tabID }) else { return }
        workspaceWebTabStopGenerationByID[tabID, default: 0] += 1
    }

    func goBackWorkspaceWebTab(_ tabID: WebTabID) {
        guard workspaceWebTabs.first(where: { $0.id == tabID })?.canGoBack == true else { return }
        workspaceWebTabBackGenerationByID[tabID, default: 0] += 1
    }

    func goForwardWorkspaceWebTab(_ tabID: WebTabID) {
        guard workspaceWebTabs.first(where: { $0.id == tabID })?.canGoForward == true else { return }
        workspaceWebTabForwardGenerationByID[tabID, default: 0] += 1
    }

    func openWorkspaceWebTabExternally(_ tabID: WebTabID) {
        guard let url = workspaceWebTabs.first(where: { $0.id == tabID })?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func revealWorkspaceWebTabDownload(_ tabID: WebTabID) {
        guard let path = workspaceWebTabs.first(where: { $0.id == tabID })?.downloadState?.destinationPath else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSelectedWorkspaceWebTabExternally() {
        guard let tabID = selectedWorkspaceWebTabID else { return }
        openWorkspaceWebTabExternally(tabID)
    }

    func focusSelectedWorkspaceWebAddress() {
        guard let tabID = selectedWorkspaceWebTabID else { return }
        workspaceWebAddressFocusGenerationByID[tabID, default: 0] += 1
    }

    func focusSelectedWorkspaceWebFind() {
        guard let tabID = selectedWorkspaceWebTabID else { return }
        workspaceWebFindFocusGenerationByID[tabID, default: 0] += 1
    }

    func navigateSelectedWorkspaceWebFind(previous: Bool) {
        guard let tabID = selectedWorkspaceWebTabID else { return }
        if previous {
            workspaceWebFindPreviousGenerationByID[tabID, default: 0] += 1
        } else {
            workspaceWebFindNextGenerationByID[tabID, default: 0] += 1
        }
    }

    func copySelectedWorkspaceWebTabURL() {
        guard let url = selectedWorkspaceWebTab?.url else { return }
        copyTextToPasteboard(url.absoluteString)
    }

    func copySelectedWorkspaceWebTabReference() {
        guard let tab = selectedWorkspaceWebTab,
              let url = tab.url else { return }
        let title = tab.displayTitle.replacingOccurrences(of: "]", with: "\\]")
        copyTextToPasteboard("[\(title)](\(url.absoluteString))")
    }

    func updateWorkspaceWebTab(_ tabID: WebTabID, mutate: (inout WorkspaceWebTabState) -> Void) {
        guard let index = workspaceWebTabs.firstIndex(where: { $0.id == tabID }) else { return }
        mutate(&workspaceWebTabs[index])
    }

    func updateWorkspaceWebTabDownload(_ tabID: WebTabID, state: WorkspaceWebDownloadState?) {
        updateWorkspaceWebTab(tabID) { tab in
            tab.downloadState = state
            if state?.phase == .downloading || state?.phase == .requested {
                tab.errorMessage = nil
            }
        }
        persist()
    }

    func recordWorkspaceWebRuntimeEvent(_ tabID: WebTabID, event: WorkspaceWebRuntimeEvent) {
        updateWorkspaceWebTab(tabID) { tab in
            tab.runtimeEvents.append(event)
            if tab.runtimeEvents.count > 40 {
                tab.runtimeEvents.removeFirst(tab.runtimeEvents.count - 40)
            }
        }
        ConductorDiagnostics.record(
            "browser-runtime-event",
            fields: [
                "webTabID": tabID.rawValue.uuidString,
                "kind": event.kind.rawValue,
                "level": event.level,
                "message": String(event.message.prefix(160))
            ]
        )
        persist()
    }

    func clearWorkspaceWebRuntimeEvents(_ tabID: WebTabID, reason: String) {
        var removedCount = 0
        updateWorkspaceWebTab(tabID) { tab in
            removedCount = tab.runtimeEvents.count
            tab.runtimeEvents.removeAll()
        }
        guard removedCount > 0 else { return }
        ConductorDiagnostics.record(
            "browser-runtime-events-cleared",
            fields: [
                "webTabID": tabID.rawValue.uuidString,
                "reason": reason,
                "count": String(removedCount)
            ]
        )
        persist()
    }

    func persistWorkspaceWebTabs() {
        persist()
    }

    func failWorkspaceWebTab(_ tabID: WebTabID, url: URL?, message: String) {
        updateWorkspaceWebTab(tabID) { tab in
            tab.url = url ?? tab.url
            tab.isLoading = false
            tab.estimatedProgress = 0
            tab.errorMessage = String(message.prefix(240))
        }
        persist()
    }

    func openFileInWorkspace(_ fileURL: URL, rootURL: URL? = nil) {
        let standardizedFile = fileURL.standardizedFileURL
        let resolvedRoot = (rootURL ?? standardizedFile.deletingLastPathComponent()).standardizedFileURL
        syncFileWorkspaceCoordinatorFromPublished()
        fileWorkspaceCoordinator.openFile(standardizedFile, rootURL: resolvedRoot)
        let changed = publishFileWorkspaceState()
        pruneWorkspaceFileTabState(keeping: Set(workspaceFileTabs.map(\.id)))
        syncFileWorkspaceCoordinatorFromPublished()
        syncPanelCoordinatorFromPublished()
        panelCoordinator.terminalSearchVisible = false
        panelCoordinator.workspaceOverviewVisible = false
        fileManagerKeyboardFocused = false
        publishPanelState()
        if changed {
            persist()
        }
    }

    func selectWorkspaceFileTab(_ tabID: String) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        selectedWorkspaceContentTabID = .file(tabID)
        syncFileWorkspaceCoordinatorFromPublished()
        syncPanelCoordinatorFromPublished()
        panelCoordinator.terminalSearchVisible = false
        panelCoordinator.workspaceOverviewVisible = false
        fileManagerKeyboardFocused = false
        publishPanelState()
        persist()
    }

    func selectWorkspaceFileTab(_ tabID: String, in workspaceID: WorkspaceID) {
        if workspaceID != workspace.id {
            guard activateWorkspace(workspaceID, source: .programmatic) else { return }
        }
        selectWorkspaceFileTab(tabID)
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
    func openSelectedWorkspaceFileTabExternally() -> Bool {
        guard let tab = selectedWorkspaceFileTab else { return false }
        NSWorkspace.shared.open(tab.fileURL)
        ConductorDiagnostics.record(
            "file-tab-open-external",
            fields: [
                "tab": tab.id,
                "path": tab.fileURL.path
            ]
        )
        return true
    }

    @discardableResult
    func revealSelectedWorkspaceFileTabInFinder() -> Bool {
        guard let tab = selectedWorkspaceFileTab else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([tab.fileURL])
        ConductorDiagnostics.record(
            "file-tab-reveal-finder",
            fields: [
                "tab": tab.id,
                "path": tab.fileURL.path
            ]
        )
        return true
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
        var savedRevisions = workspaceFileEditorSavedRevisionByTabID
        var bufferSnapshots = workspaceFileBufferSnapshotsByTabID
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
                saveAndCloseTokens: &saveAndCloseTokens,
                savedRevisions: &savedRevisions,
                bufferSnapshots: &bufferSnapshots
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
        workspaceFileEditorSavedRevisionByTabID = savedRevisions
        workspaceFileBufferSnapshotsByTabID = bufferSnapshots
    }

    func setWorkspaceFileTabDirty(_ tabID: String, isDirty: Bool) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        syncFileWorkspaceCoordinatorFromPublished()
        fileWorkspaceCoordinator.setDirty(tabID, isDirty: isDirty)
        publishFileWorkspaceState()
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

    func workspaceFileEditorSavedRevision(for tabID: String) -> Int {
        workspaceFileEditorSavedRevisionByTabID[tabID] ?? 0
    }

    func workspaceFileBufferSnapshot(for tabID: String) -> WorkspaceFileBufferSnapshot? {
        workspaceFileBufferSnapshotsByTabID[tabID]
    }

    func updateWorkspaceFileBuffer(
        tabID: String,
        text: String,
        savedText: String,
        canSave: Bool,
        isEditable: Bool,
        isReadOnly: Bool
    ) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        let revision = workspaceFileBufferSnapshotsByTabID[tabID]?.savedRevision ?? 0
        workspaceFileBufferSnapshotsByTabID[tabID] = WorkspaceFileBufferSnapshot(
            text: text,
            savedText: savedText,
            canSave: canSave,
            isEditable: isEditable,
            isReadOnly: isReadOnly,
            updatedAt: Date(),
            savedRevision: revision
        )
    }

    func markWorkspaceFileBufferSaved(tabID: String, text: String) {
        guard workspaceFileTabs.contains(where: { $0.id == tabID }) else { return }
        let nextRevision = (workspaceFileEditorSavedRevisionByTabID[tabID] ?? 0) + 1
        let existing = workspaceFileBufferSnapshotsByTabID[tabID]
        workspaceFileBufferSnapshotsByTabID[tabID] = WorkspaceFileBufferSnapshot(
            text: text,
            savedText: text,
            canSave: existing?.canSave ?? true,
            isEditable: existing?.isEditable ?? true,
            isReadOnly: existing?.isReadOnly ?? false,
            updatedAt: Date(),
            savedRevision: nextRevision
        )
        workspaceFileEditorSavedRevisionByTabID[tabID] = nextRevision
        setWorkspaceFileTabDirty(tabID, isDirty: false)
        setWorkspaceFileTabExternallyChanged(tabID, changed: false)
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
        workspaceFileEditorSavedRevisionByTabID.removeValue(forKey: tab.id)
        workspaceFileBufferSnapshotsByTabID.removeValue(forKey: tab.id)
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
        workspaceFileEditorSavedRevisionByTabID = workspaceFileEditorSavedRevisionByTabID.filter { retainedIDs.contains($0.key) }
        workspaceFileBufferSnapshotsByTabID = workspaceFileBufferSnapshotsByTabID.filter { retainedIDs.contains($0.key) }
    }

    private func applyWorkspaceContentSelection(_ selection: WorkspaceContentSelection?) {
        switch selection {
        case .web(let tabID):
            selectedWorkspaceContentTabID = workspaceWebTabs.contains(where: { $0.id == tabID }) ? .web(tabID) : nil
        case .file(let tabID):
            selectedWorkspaceContentTabID = workspaceFileTabs.contains(where: { $0.id == tabID }) ? .file(tabID) : focusedTerminalID.map { .terminal($0) }
        case .terminal(let terminalID):
            if workspace.paneID(containing: terminalID) != nil {
                selectedWorkspaceContentTabID = .terminal(terminalID)
            } else {
                selectedWorkspaceContentTabID = focusedTerminalID.map { .terminal($0) }
            }
        case nil:
            selectedWorkspaceContentTabID = focusedTerminalID.map { .terminal($0) }
        }
    }

    private func pruneWorkspaceWebTabCommands(keeping retainedIDs: Set<WebTabID>) {
        ConductorWebKitSurfaceStore.shared.keepOnly(retainedWebTabIDsForSurfaceStore())
        workspaceWebTabNavigationGenerationByID = workspaceWebTabNavigationGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebTabReloadGenerationByID = workspaceWebTabReloadGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebTabStopGenerationByID = workspaceWebTabStopGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebTabBackGenerationByID = workspaceWebTabBackGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebTabForwardGenerationByID = workspaceWebTabForwardGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebAddressFocusGenerationByID = workspaceWebAddressFocusGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebFindFocusGenerationByID = workspaceWebFindFocusGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebFindNextGenerationByID = workspaceWebFindNextGenerationByID.filter { retainedIDs.contains($0.key) }
        workspaceWebFindPreviousGenerationByID = workspaceWebFindPreviousGenerationByID.filter { retainedIDs.contains($0.key) }
    }

    private func retainedWebTabIDsForSurfaceStore(excluding excludedWorkspaceIDs: Set<WorkspaceID> = []) -> Set<WebTabID> {
        var retained = Set(workspaceWebTabs.map(\.id))
        if excludedWorkspaceIDs.contains(workspace.id) {
            retained.removeAll()
        }
        for (workspaceID, contentState) in workspaceContentStatesByWorkspaceID where workspaceID != workspace.id {
            guard !excludedWorkspaceIDs.contains(workspaceID) else { continue }
            retained.formUnion(contentState.webTabs.map(\.id))
        }
        return retained
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
        saveAndCloseTokens: inout [String: Int],
        savedRevisions: inout [String: Int],
        bufferSnapshots: inout [String: WorkspaceFileBufferSnapshot]
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
        if let revision = savedRevisions.removeValue(forKey: oldID) {
            savedRevisions[newID] = revision
        }
        if let snapshot = bufferSnapshots.removeValue(forKey: oldID) {
            bufferSnapshots[newID] = snapshot
        }
    }

    func selectTerminalStage() {
        selectedWorkspaceContentTabID = nil
        activateWorkspaceStageForCurrentWorkspace(source: .programmatic)
    }

    func selectWorkspaceTerminalTab(_ terminalID: TerminalID) {
        guard workspace.paneID(containing: terminalID) != nil else { return }
        markTerminalInteractionFocus()
        selectedWorkspaceContentTabID = .terminal(terminalID)
        syncFileWorkspaceCoordinatorFromPublished()
        syncPanelCoordinatorFromPublished()
        panelCoordinator.terminalSearchVisible = false
        panelCoordinator.workspaceOverviewVisible = false
        publishPanelState()
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
        if terminalSearchVisible {
            closeTerminalSearch()
        }
        let standardizedRoot = rootURL.standardizedFileURL
        fileManagerPanelRequest = FileManagerPanelRequest(rootURL: standardizedRoot, selectedURL: selectedURL)
    }

    private func openWorkingDirectory(for terminalID: TerminalID) {
        guard let url = workingDirectoryURL(for: terminalID) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyFocusedDirectory() {
        guard let path = focusedWorkingDirectoryURL?.path else { return }
        copyTextToPasteboard(path)
    }

    private func copyWorkingDirectory(for terminalID: TerminalID) {
        guard let path = workingDirectoryURL(for: terminalID)?.path else { return }
        copyTextToPasteboard(path)
    }

    private func copyTextToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
                attendTerminal(lastTabID)
                reconcileSurfaceFocus()
            }
            return didSelect
        }

        if let offset {
            if offset > 0, offset <= pane.tabs.count {
                let targetID = pane.tabs[offset - 1].id
                let didSelect = workspace.selectTab(targetID, in: paneID)
                if didSelect {
                    attendTerminal(targetID)
                    reconcileSurfaceFocus()
                }
                return didSelect
            }
            if let selectedID = workspace.selectAdjacentTab(offset: offset, in: paneID) {
                attendTerminal(selectedID)
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

    func ghosttyRuntimeDidRingBell(terminalID: TerminalID) -> Bool {
        true
    }

    func ghosttyRuntimeDidReceiveNotification(terminalID: TerminalID, title: String, body: String) -> Bool {
        guard containsTerminal(terminalID) else { return false }
        let normalizedTitle = Self.normalizedTerminalNotificationTitle(title)
        let normalizedBody = Self.normalizedTerminalNotificationBody(body)
        let appendResult = controlCreateAttentionEventResult(
            title: normalizedTitle,
            body: normalizedBody,
            kind: .terminalBell,
            terminalID: terminalID,
            source: "terminal-escape",
            details: ["escape": "desktop-notification"],
            coalescingWindow: 6
        )
        ConductorDiagnostics.record(
            "terminal-notification-received",
            fields: [
                "terminal": terminalID.description,
                "coalesced": String(appendResult.coalesced),
                "suppressedCount": String(appendResult.suppressedCount)
            ]
        )
        if !appendResult.coalesced {
            let location = terminalLocation(for: terminalID)
            let request = TerminalAttentionNotificationRequest(
                attentionEventID: appendResult.event.id,
                terminalID: terminalID,
                kind: .terminalBell,
                title: normalizedTitle,
                body: normalizedBody,
                isUnattended: location.map { isTerminalUnattended(terminalID, location: $0) } ?? true
            )
            agentReplyNotificationService.deliverTerminalAttention(
                request,
                preferences: appearance.agentReplyNotifications
            )
            NSApp.requestUserAttention(.informationalRequest)
        }
        return true
    }

    func ghosttyRuntimeDidUpdateProgress(terminalID: TerminalID, kind: TerminalProgressKind, progress: Int?) -> Bool {
        updateMetadata(for: terminalID) { metadata in
            metadata.progressKind = kind == .removed ? nil : kind
            metadata.progressPercent = progress
        }
        return true
    }

    func ghosttyRuntimeDidFinishCommand(terminalID: TerminalID, exitCode: Int?, durationNanoseconds: UInt64) -> Bool {
        let currentMetadata = metadata(for: terminalID)
        handleCommandFinishedAttention(
            terminalID: terminalID,
            exitCode: exitCode,
            durationNanoseconds: durationNanoseconds,
            metadata: currentMetadata
        )
        let commandSnapshot = TerminalCommandSnapshot(
            exitCode: exitCode,
            durationNanoseconds: durationNanoseconds
        )
        _ = updateWorkspace(containing: terminalID) { workspace in
            var updated = workspace.updateTerminalCommandSnapshot(terminalID, snapshot: commandSnapshot)
            if let agentTitle = currentMetadata.activeAgentTitle,
               !agentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated = workspace.updateTerminalAgentSnapshot(
                    terminalID,
                    snapshot: TerminalAgentSnapshot(
                        displayName: agentTitle,
                        state: .completed,
                        startedAt: currentMetadata.activeAgentStartedAt,
                        lastEvent: "command-finished"
                    )
                ) || updated
            }
            return updated
        }
        updateMetadata(for: terminalID) { metadata in
            metadata.lastCommandExitCode = exitCode
            metadata.lastCommandDurationNanoseconds = durationNanoseconds
            metadata.activeAgentTitle = nil
            metadata.activeAgentStartedAt = nil
            if metadata.progressKind != .error {
                metadata.progressKind = nil
                metadata.progressPercent = nil
            }
        }
        return true
    }

    private func handleCommandFinishedAttention(
        terminalID: TerminalID,
        exitCode: Int?,
        durationNanoseconds: UInt64,
        metadata: TerminalDisplayMetadata
    ) {
        if let agentTitle = metadata.activeAgentTitle,
           !agentTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
        guard let location = terminalLocation(for: terminalID),
              isTerminalUnattended(terminalID, location: location) else {
            return
        }

        let failed = exitCode.map { $0 != 0 } ?? false
        let longRunning = durationNanoseconds >= Self.commandFinishedAttentionThresholdNanoseconds
        guard failed || longRunning else { return }

        let target = terminalContextMenuTarget(for: terminalID)
        let terminalTitle = target?.tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = terminalTitle?.isEmpty == false ? terminalTitle! : L("终端", "Terminal")
        let durationText = Self.commandDurationDescription(durationNanoseconds)
        let reason = failed ? "exit-nonzero" : "long-running"
        let eventTitle = failed ? L("命令失败", "Command Failed") : L("命令已完成", "Command Finished")
        let exitText = exitCode.map { "exit \($0)" } ?? L("退出码未知", "exit unknown")
        let appendResult = controlCreateAttentionEventResult(
            title: eventTitle,
            body: "\(resolvedTitle) · \(exitText) · \(durationText)",
            kind: .commandFinished,
            severity: failed ? .warning : .info,
            workspaceID: location.workspaceID,
            terminalID: terminalID,
            source: "terminal-command",
            details: [
                "reason": reason,
                "exitCode": exitCode.map(String.init) ?? "unknown",
                "durationMilliseconds": String(durationNanoseconds / 1_000_000),
                "duration": durationText
            ],
            coalescingWindow: 8
        )
        ConductorDiagnostics.record(
            "terminal-command-finished-attention",
            fields: [
                "terminal": terminalID.description,
                "exitCode": exitCode.map(String.init) ?? "unknown",
                "durationMilliseconds": String(durationNanoseconds / 1_000_000),
                "reason": reason,
                "coalesced": String(appendResult.coalesced),
                "suppressedCount": String(appendResult.suppressedCount)
            ]
        )
        if !appendResult.coalesced {
            let request = TerminalAttentionNotificationRequest(
                attentionEventID: appendResult.event.id,
                terminalID: terminalID,
                kind: .commandFinished,
                title: eventTitle,
                body: appendResult.event.body,
                isUnattended: true
            )
            agentReplyNotificationService.deliverTerminalAttention(
                request,
                preferences: appearance.agentReplyNotifications
            )
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    private static func commandDurationDescription(_ durationNanoseconds: UInt64) -> String {
        let seconds = Double(durationNanoseconds) / 1_000_000_000
        if seconds >= 60 {
            return String(format: "%.1f min", seconds / 60)
        }
        if seconds >= 1 {
            return String(format: "%.1f s", seconds)
        }
        return "\(durationNanoseconds / 1_000_000) ms"
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
        _ = updateWorkspace(containing: terminalID) { workspace in
            workspace.updateTerminalSearchSnapshot(
                terminalID,
                snapshot: active
                    ? TerminalSearchSnapshot(active: true, needle: needle, total: total, selected: selected)
                    : nil
            )
        }
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
            attendTerminal(terminalID)
            return
        }
        markTerminalInteractionFocus()
        workspace.selectTab(terminalID, in: paneID)
        attendTerminal(terminalID)
        reconcileSurfaceFocus()
    }

    func focusPane(_ paneID: PaneID) {
        guard let pane = workspace.panes[paneID] else { return }
        if workspace.focusedPaneID == paneID {
            markTerminalInteractionFocus()
            attendTerminal(pane.selectedTabID)
            return
        }
        markTerminalInteractionFocus()
        workspace.focusPane(paneID)
        attendTerminal(pane.selectedTabID)
        reconcileSurfaceFocus()
    }

    func focusTerminal(_ terminalID: TerminalID) {
        let signpost = ConductorSignpost.begin("focus-terminal")
        defer { ConductorSignpost.end("focus-terminal", signpost) }
        if workspace.paneID(containing: terminalID) == nil,
           let workspaceID = workspaces.first(where: { $0.paneID(containing: terminalID) != nil })?.id {
            guard !shouldSuppressCrossWorkspaceTerminalFocus(to: workspaceID, terminalID: terminalID) else {
                return
            }
            activateWorkspace(workspaceID, source: .terminalFocus)
        }
        guard let paneID = workspace.paneID(containing: terminalID) else { return }
        markTerminalInteractionFocus()
        attendTerminal(terminalID)
        if workspace.focusedPaneID == paneID,
           workspace.panes[paneID]?.selectedTabID == terminalID {
            reconcileSurfaceFocus()
            refreshSurfaceAfterNavigation(terminalID)
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
        if let webTab = selectedWorkspaceWebTab {
            if webTab.url == nil {
                focusSelectedWorkspaceWebAddress()
            } else {
                focusSelectedWorkspaceWebFind()
            }
            return
        }
        if fileManagerPanelRequest != nil, fileManagerKeyboardFocused {
            syncPanelCoordinatorFromPublished()
            panelCoordinator.closeTransientPanels()
            publishPanelState()
            fileManagerSearchFocusGeneration &+= 1
            return
        }
        if selectedWorkspaceFileTab != nil {
            syncPanelCoordinatorFromPublished()
            panelCoordinator.closeTransientPanels()
            publishPanelState()
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
        syncPanelCoordinatorFromPublished()
        panelCoordinator.commandPaletteVisible = false
        panelCoordinator.settingsVisible = false
        panelCoordinator.workspaceOverviewVisible = false
        panelCoordinator.terminalSearchVisible = true
        terminalSearchTargetID = terminalID
        terminalSearchQuery = metadata(for: terminalID).search.needle ?? ""
        publishPanelState()
        terminalSearchFocusGeneration &+= 1
        let surface = surface(for: target.tab)
        _ = surface.startSearchPrompt()
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
        if routeContextualSearchNavigation(previous: previous) {
            return
        }
        guard terminalSearchVisible,
              let tab = terminalSearchTargetTab() else { return }
        _ = surface(for: tab).navigateSearch(previous: previous)
    }

    private func routeContextualSearchNavigation(previous: Bool) -> Bool {
        if selectedWorkspaceWebTab?.url != nil {
            navigateSelectedWorkspaceWebFind(previous: previous)
            return true
        }
        if selectedWorkspaceFileTab != nil {
            if previous {
                workspaceFileSearchPreviousGeneration &+= 1
            } else {
                workspaceFileSearchNextGeneration &+= 1
            }
            return true
        }
        if fileManagerPanelRequest != nil {
            if previous {
                fileManagerSearchPreviousGeneration &+= 1
            } else {
                fileManagerSearchNextGeneration &+= 1
            }
            return true
        }
        return false
    }

    func closeTerminalSearch() {
        let restoreTerminalID = terminalSearchTargetID ?? focusedTerminalID
        if terminalSearchVisible, let tab = terminalSearchTargetTab() {
            _ = surface(for: tab).endSearch()
        }
        terminalSearchVisible = false
        terminalSearchQuery = ""
        terminalSearchTargetID = nil
        syncPanelCoordinatorFromPublished()
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
    func performTerminalContextMenuAction(_ action: TerminalContextMenuAction, terminalID: TerminalID) -> Bool {
        guard let target = terminalContextMenuTarget(for: terminalID) else { return false }
        focusTerminal(terminalID)
        return performTerminalContextMenuAction(
            action,
            terminalID: terminalID,
            workspaceID: target.workspaceID,
            window: NSApp.keyWindow ?? NSApp.mainWindow
        )
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
            return newTerminalAtDirectory(for: terminalID)
        case .newTerminalAtDirectory:
            return newTerminalAtDirectory(for: terminalID)
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
        let next = WorkspaceState(title: nextWorkspaceTitle())
        workspaces.append(next)
        activateWorkspace(next.id, source: .newWorkspace)
    }

    @discardableResult
    func openWorkspaceAtDirectory(
        _ directoryURL: URL,
        title: String? = nil,
        source: WorkspaceNavigationSource = .programmatic
    ) -> WorkspaceID {
        let standardized = directoryURL.standardizedFileURL
        let cleanTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminal = TerminalTabState(
            title: "zsh",
            workingDirectory: standardized.path
        )
        let pane = PaneState(tabs: [terminal])
        let next = WorkspaceState(
            title: cleanTitle?.isEmpty == false ? cleanTitle! : standardized.lastPathComponent,
            root: .leaf(pane.id),
            panes: [pane.id: pane],
            focusedPaneID: pane.id
        )
        workspaces.append(next)
        activateWorkspace(next.id, source: source)
        selectedWorkspaceContentTabID = .terminal(terminal.id)
        markTerminalInteractionFocus()
        return next.id
    }

    func duplicateWorkspace(_ workspaceID: WorkspaceID) {
        let signpost = ConductorSignpost.begin("duplicate-workspace")
        defer { ConductorSignpost.end("duplicate-workspace", signpost) }
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let source = workspace.id == workspaceID ? workspace : workspaces[index]
        let duplicate = source.duplicated(title: nextCopyTitle(for: source.title))
        if let sourceContent = workspace.id == workspaceID
            ? Optional(currentWorkspaceContentState())
            : workspaceContentStatesByWorkspaceID[workspaceID] {
            workspaceContentStatesByWorkspaceID[duplicate.id] = duplicatedContentState(from: sourceContent)
        }
        workspaces.insert(duplicate, at: index + 1)
        activateWorkspace(duplicate.id, source: .duplicateWorkspace)
    }

    func selectWorkspace(_ workspaceID: WorkspaceID) {
        activateWorkspace(workspaceID, source: .programmatic)
    }

    @discardableResult
    func activateWorkspace(_ workspaceID: WorkspaceID, source: WorkspaceNavigationSource) -> Bool {
        let target: WorkspaceState?
        if workspaceID == workspace.id {
            target = workspace
        } else {
            target = workspaces.first { $0.id == workspaceID }
        }
        guard let target else {
            recordWorkspaceNavigation(
                source: source,
                from: workspace.id,
                to: workspaceID,
                previousContent: selectedWorkspaceContentTabID,
                terminalID: nil,
                committed: false,
                reason: "missing-target"
            )
            return false
        }
        return activateWorkspace(target, source: source, syncPreviousWorkspace: true)
    }

    @discardableResult
    private func activateWorkspace(
        _ target: WorkspaceState,
        source: WorkspaceNavigationSource,
        syncPreviousWorkspace: Bool
    ) -> Bool {
        let signpost = ConductorSignpost.begin("workspace-navigation")
        defer { ConductorSignpost.end("workspace-navigation", signpost) }

        let previousWorkspaceID = workspace.id
        let previousContent = selectedWorkspaceContentTabID

        closeTerminalSearch()
        if target.id != workspace.id {
            saveSelectedWorkspaceContentState()
            if source != .terminalFocus {
                suppressCrossWorkspaceTerminalFocusUntil = Date().addingTimeInterval(0.35)
            }
            selectedWorkspaceID = target.id
            skipPreviousWorkspaceSyncForNextAssignment = !syncPreviousWorkspace
            suppressWorkspaceAssignmentPersistence = true
            workspace = target
            suppressWorkspaceAssignmentPersistence = false
            applyWorkspaceContentState(for: target.id)
            persist()
        } else {
            selectedWorkspaceID = workspace.id
        }

        let terminalID = activateWorkspaceStageForCurrentWorkspace(source: source)
        closeWorkspaceTransientPanels()
        recordWorkspaceNavigation(
            source: source,
            from: previousWorkspaceID,
            to: workspace.id,
            previousContent: previousContent,
            terminalID: terminalID,
            committed: true,
            reason: target.id == previousWorkspaceID ? "same-workspace" : "workspace-changed"
        )
        return true
    }

    private func shouldSuppressCrossWorkspaceTerminalFocus(to workspaceID: WorkspaceID, terminalID: TerminalID) -> Bool {
        guard workspaceID != workspace.id,
              Date() < suppressCrossWorkspaceTerminalFocusUntil else {
            return false
        }
        ConductorDiagnostics.record(
            "terminal-focus-suppressed-after-navigation",
            fields: [
                "currentWorkspace": workspace.id.description,
                "requestedWorkspace": workspaceID.description,
                "terminal": terminalID.description
            ]
        )
        return true
    }

    @discardableResult
    private func activateWorkspaceStageForCurrentWorkspace(source: WorkspaceNavigationSource) -> TerminalID? {
        guard let terminalID = workspace.focusedPane?.selectedTabID else {
            let previousContent = selectedWorkspaceContentTabID
            selectedWorkspaceContentTabID = nil
            reconcileSurfaceFocus()
            recordWorkspaceNavigation(
                source: source,
                from: workspace.id,
                to: workspace.id,
                previousContent: previousContent,
                terminalID: nil,
                committed: false,
                reason: "missing-focused-terminal"
            )
            return nil
        }

        markTerminalInteractionFocus()
        if shouldSelectTerminalOnWorkspaceActivation(source: source) {
            selectedWorkspaceContentTabID = .terminal(terminalID)
        } else if Self.validatedWorkspaceContentSelection(
            Self.persistedWorkspaceContentSelection(selectedWorkspaceContentTabID),
            workspace: workspace,
            webTabs: workspaceWebTabs,
            fileTabIDs: Set(workspaceFileTabs.map(\.id))
        ) == nil {
            selectedWorkspaceContentTabID = .terminal(terminalID)
        }
        reconcileSurfaceFocus()
        refreshSurfaceAfterNavigation(terminalID)
        return terminalID
    }

    private func shouldSelectTerminalOnWorkspaceActivation(source: WorkspaceNavigationSource) -> Bool {
        switch source {
        case .terminalFocus:
            return false
        case .sidebar,
             .tabStrip,
             .overview,
             .commandPalette,
             .newWorkspace,
             .duplicateWorkspace,
             .listMutation,
             .programmatic:
            return true
        }
    }

    private func recordWorkspaceNavigation(
        source: WorkspaceNavigationSource,
        from previousWorkspaceID: WorkspaceID,
        to nextWorkspaceID: WorkspaceID,
        previousContent: ConductorWorkspaceContentTabID?,
        terminalID: TerminalID?,
        committed: Bool,
        reason: String
    ) {
        ConductorDiagnostics.record(
            "workspace-navigation",
            fields: [
                "source": source.rawValue,
                "from": previousWorkspaceID.description,
                "to": nextWorkspaceID.description,
                "previousContent": previousContent?.diagnosticName ?? "none",
                "nextContent": selectedWorkspaceContentTabID?.diagnosticName ?? "none",
                "terminal": terminalID?.description ?? "none",
                "committed": committed,
                "reason": reason
            ]
        )
        _ = committed
        _ = previousWorkspaceID
        _ = nextWorkspaceID
        _ = terminalID
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

    func requestRenameCurrentWorkspace() {
        closeWorkspaceTransientPanels()
        workspaceRenameRequest = WorkspaceRenameRequest(workspaceID: workspace.id)
        ConductorDiagnostics.record(
            "workspace-rename-request",
            fields: [
                "workspace": workspace.id.description,
                "title": workspace.title
            ]
        )
    }

    func closeWorkspace(_ workspaceID: WorkspaceID) {
        guard workspaces.count > 1,
              let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }
        let closingWorkspace = workspaces[index]
        closeSurfaces(for: terminalIDs(in: closingWorkspace))
        removeWorkspaceContentState(for: workspaceID)
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
              let keptWorkspaceSnapshot = workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        let keptWorkspace = workspace.id == workspaceID ? workspace : keptWorkspaceSnapshot
        let closingWorkspaceIDs = Set(workspaces.map(\.id).filter { $0 != workspaceID })
        for closingWorkspace in workspaces where closingWorkspace.id != workspaceID {
            closeSurfaces(for: terminalIDs(in: closingWorkspace))
        }
        removeWorkspaceContentStates(for: closingWorkspaceIDs)
        workspaces = [keptWorkspace]
        selectWorkspaceAfterListMutation(keptWorkspace)
        syncPanelCoordinatorFromPublished()
        panelCoordinator.commandPaletteVisible = false
        publishPanelState()
    }

    func closeWorkspacesToRight(of workspaceID: WorkspaceID) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }),
              index < workspaces.count - 1 else {
            return
        }
        let closingWorkspaces = workspaces[(index + 1)...]
        let closingWorkspaceIDs = Set(closingWorkspaces.map(\.id))
        for closingWorkspace in closingWorkspaces {
            closeSurfaces(for: terminalIDs(in: closingWorkspace))
        }
        removeWorkspaceContentStates(for: closingWorkspaceIDs)
        workspaces.removeSubrange((index + 1)..<workspaces.count)
        if workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
            syncSelectedWorkspace()
            persist()
        } else {
            selectWorkspaceAfterListMutation(workspaces[index])
        }
        syncPanelCoordinatorFromPublished()
        panelCoordinator.commandPaletteVisible = false
        publishPanelState()
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
        if let tab = selectedWorkspaceWebTab {
            newWorkspaceWebTab(initialInput: tab.url?.absoluteString ?? tab.pendingAddress)
            return
        }
        if let tab = selectedWorkspaceFileTab {
            openFileInWorkspace(tab.fileURL, rootURL: tab.rootURL)
            return
        }
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
        if let webTabID = selectedWorkspaceWebTabID {
            closeWorkspaceWebTab(webTabID)
            return
        }
        if let fileTab = selectedWorkspaceFileTab {
            closeWorkspaceFileTab(fileTab)
            return
        }
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
            attendTerminal(terminalID)
            reconcileSurfaceFocus()
            refreshSurfaceAfterNavigation(terminalID)
        }
    }

    func selectPreviousTab() {
        if let terminalID = workspace.selectAdjacentTab(offset: -1) {
            attendTerminal(terminalID)
            reconcileSurfaceFocus()
            refreshSurfaceAfterNavigation(terminalID)
        }
    }

    func focusNextPane() {
        if let paneID = workspace.focusAdjacentPane(.next) {
            attendSelectedTerminal(in: paneID)
            reconcileSurfaceFocus()
        }
    }

    func focusPreviousPane() {
        if let paneID = workspace.focusAdjacentPane(.previous) {
            attendSelectedTerminal(in: paneID)
            reconcileSurfaceFocus()
        }
    }

    func focusPane(direction: FocusDirection) {
        if let paneID = workspace.focusAdjacentPane(direction) {
            attendSelectedTerminal(in: paneID)
            reconcileSurfaceFocus()
        }
    }

    func resizeFocusedSplit(direction: ResizeSplitDirection, amount: Double = 5) {
        let signpost = ConductorSignpost.begin("resize-split")
        defer { ConductorSignpost.end("resize-split", signpost) }
        workspace.resizeFocusedSplit(direction: direction, amount: amount)
    }

    func toggleCommandPalette() {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let wasVisible = commandPaletteVisible
        let signpost = ConductorSignpost.begin("palette-toggle")
        defer { ConductorSignpost.end("palette-toggle", signpost) }
        let shouldCloseTerminalSearch = !commandPaletteVisible && terminalSearchVisible
        if shouldCloseTerminalSearch {
            closeTerminalSearch()
        }
        syncPanelCoordinatorFromPublished()
        panelCoordinator.toggleCommandPalette()
        publishPanelState()
        if !wasVisible, commandPaletteVisible {
            schedulePerformanceBudgetSample(
                budgetID: "command-palette.open",
                startedAt: startedAt,
                source: "ui.command-palette.toggle"
            )
        }
    }

    func hideCommandPalette() {
        syncPanelCoordinatorFromPublished()
        panelCoordinator.commandPaletteVisible = false
        publishPanelState()
    }

    func toggleSettingsPanel() {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let wasVisible = settingsPanelVisible
        let signpost = ConductorSignpost.begin("settings-toggle")
        defer { ConductorSignpost.end("settings-toggle", signpost) }
        let shouldCloseTerminalSearch = !settingsPanelVisible && terminalSearchVisible
        if shouldCloseTerminalSearch {
            closeTerminalSearch()
        }
        syncPanelCoordinatorFromPublished()
        panelCoordinator.toggleSettings()
        publishPanelState()
        if !wasVisible, settingsPanelVisible {
            schedulePerformanceBudgetSample(
                budgetID: "settings.open",
                startedAt: startedAt,
                source: "ui.settings.toggle"
            )
        }
    }

    func showSettingsPanel(section: SettingsSectionID? = nil) {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let wasVisible = settingsPanelVisible
        let signpost = ConductorSignpost.begin("settings-show")
        defer { ConductorSignpost.end("settings-show", signpost) }
        if terminalSearchVisible {
            closeTerminalSearch()
        }
        requestedSettingsSection = section
        syncPanelCoordinatorFromPublished()
        panelCoordinator.settingsVisible = true
        panelCoordinator.commandPaletteVisible = false
        panelCoordinator.workspaceOverviewVisible = false
        panelCoordinator.terminalSearchVisible = false
        publishPanelState()
        if !wasVisible, settingsPanelVisible {
            schedulePerformanceBudgetSample(
                budgetID: "settings.open",
                startedAt: startedAt,
                source: "ui.settings.show"
            )
        }
    }

    func hideSettingsPanel() {
        syncPanelCoordinatorFromPublished()
        panelCoordinator.settingsVisible = false
        publishPanelState()
    }

    func toggleWorkspaceOverview() {
        let signpost = ConductorSignpost.begin("overview-toggle")
        defer { ConductorSignpost.end("overview-toggle", signpost) }
        let shouldCloseTerminalSearch = !workspaceOverviewVisible && terminalSearchVisible
        if shouldCloseTerminalSearch {
            closeTerminalSearch()
        }
        syncPanelCoordinatorFromPublished()
        panelCoordinator.toggleWorkspaceOverview()
        publishPanelState()
    }

    func hideWorkspaceOverview() {
        syncPanelCoordinatorFromPublished()
        panelCoordinator.workspaceOverviewVisible = false
        publishPanelState()
    }

    var attentionUnreadCount: Int {
        attentionEvents.filter(\.isUnread).count
    }

    func attentionUnreadCount(for workspaceID: WorkspaceID) -> Int {
        attentionEvents.filter { $0.isUnread && $0.workspaceID == workspaceID }.count
    }

    func hasUnreadAttentionEvent(in workspaceID: WorkspaceID? = nil) -> Bool {
        attentionStore.events(includeRead: false).contains { event in
            workspaceID == nil || event.workspaceID == workspaceID
        }
    }

    func refreshAttentionEvents() {
        attentionEvents = attentionStore.events(limit: 80)
    }

    func closeTransientPanels() {
        syncPanelCoordinatorFromPublished()
        panelCoordinator.closeTransientPanels()
        publishPanelState()
    }

    func showShellToast(
        title: String,
        body: String,
        systemImage: String,
        tone: ConductorShellToastTone = .info,
        actionTitle: String? = nil,
        action: ConductorShellToastAction? = nil,
        duration: TimeInterval = 5
    ) {
        shellToastDismissTask?.cancel()
        let toast = ConductorShellToast(
            title: title,
            body: body,
            systemImage: systemImage,
            tone: tone,
            actionTitle: actionTitle,
            action: action
        )
        shellToast = toast
        guard duration > 0 else { return }
        shellToastDismissTask = Task { [weak self, toastID = toast.id] in
            let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismissShellToast(id: toastID)
            }
        }
    }

    func dismissShellToast(id: UUID? = nil) {
        guard id == nil || shellToast?.id == id else { return }
        shellToastDismissTask?.cancel()
        shellToastDismissTask = nil
        shellToast = nil
    }

    func focusAttentionEvent(_ id: UUID) {
        guard controlFocusAttentionEvent(id: id) != nil else { return }
        closeTransientPanels()
    }

    func clearAttentionEvent(_ id: UUID) {
        _ = controlClearAttentionEvent(id: id)
    }

    func clearAllAttentionEvents() {
        _ = controlClearAttentionEvent()
    }

    @discardableResult
    func focusLatestUnreadAttentionEvent() -> Bool {
        if controlFocusLatestAttentionEvent(workspaceID: controlSelectedWorkspaceID) != nil {
            closeTransientPanels()
            return true
        }
        guard controlFocusLatestAttentionEvent() != nil else { return false }
        closeTransientPanels()
        return true
    }

    @discardableResult
    func focusAttentionNotificationResponse(attentionEventID: UUID?, terminalID: TerminalID?) -> Bool {
        if let attentionEventID,
           controlFocusAttentionEvent(id: attentionEventID) != nil {
            ConductorDiagnostics.record(
                "attention-notification-response-focused",
                fields: [
                    "attentionEvent": attentionEventID.uuidString,
                    "terminal": terminalID?.description ?? "none",
                    "mode": "event"
                ]
            )
            return true
        }

        if let terminalID,
           let event = attentionEvents.first(where: { $0.isUnread && $0.terminalID == terminalID }),
           controlFocusAttentionEvent(id: event.id) != nil {
            ConductorDiagnostics.record(
                "attention-notification-response-focused",
                fields: [
                    "attentionEvent": event.id.uuidString,
                    "terminal": terminalID.description,
                    "mode": "latest-terminal-event"
                ]
            )
            return true
        }

        if let terminalID,
           containsTerminal(terminalID) {
            focusTerminal(terminalID)
            ConductorDiagnostics.record(
                "attention-notification-response-focused",
                fields: [
                    "attentionEvent": attentionEventID?.uuidString ?? "none",
                    "terminal": terminalID.description,
                    "mode": "terminal-fallback"
                ]
            )
            return true
        }

        ConductorDiagnostics.record(
            "attention-notification-response-missing-target",
            fields: [
                "attentionEvent": attentionEventID?.uuidString ?? "none",
                "terminal": terminalID?.description ?? "none"
            ]
        )
        return false
    }

    @discardableResult
    func markCurrentWorkspaceAttentionRead() -> Int {
        controlMarkAttentionEventsRead(workspaceID: controlSelectedWorkspaceID)
    }

    @discardableResult
    func dismissVisibleShellPanel() -> Bool {
        if terminalSearchVisible {
            closeTerminalSearch()
            return true
        }
        syncPanelCoordinatorFromPublished()
        let dismissed = panelCoordinator.dismissVisibleShellPanel()
        publishPanelState()
        return dismissed
    }

    func recordTerminalUserActivity(_ terminalID: TerminalID) {
        guard terminalLocation(for: terminalID) != nil else { return }
        attendTerminal(terminalID)
    }

    private func attendSelectedTerminal(in paneID: PaneID) {
        guard let terminalID = workspace.panes[paneID]?.selectedTabID else { return }
        attendTerminal(terminalID)
    }

    private func attendTerminal(_ terminalID: TerminalID) {
        selectedWorkspaceContentTabID = .terminal(terminalID)
    }

    func receiveAgentHookNotification(_ userInfo: [String: String]?) {
        guard let userInfo,
              let rawTerminalID = userInfo[ConductorAgentHookBridge.Key.terminalID],
              let uuid = UUID(uuidString: rawTerminalID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            ConductorLog.app.info("Ignoring agent hook notification with missing terminal id")
            return
        }
        let agent = userInfo[ConductorAgentHookBridge.Key.agent] ?? ""
        let resumeMetadata = AgentResumeDetector.metadata(
            providerID: agent,
            sessionIdentifier: userInfo[ConductorAgentHookBridge.Key.sessionID]
        )

        let terminalID = TerminalID(uuid)
        let action = userInfo[ConductorAgentHookBridge.Key.action]?.lowercased() ?? ""
        ConductorLog.app.info("Received agent hook action=\(action, privacy: .public) agent=\(agent, privacy: .public) terminal=\(terminalID.description, privacy: .public)")
        ConductorDiagnostics.record(
            "agent-hook-received",
            fields: [
                "action": action,
                "agent": agent,
                "terminal": terminalID.description
            ]
        )
        switch action {
        case "prompt-submit", "session-start":
            let providerTitle = resumeMetadata?.displayName ?? Self.agentDisplayTitle(for: agent)
            let startedAt = Date()
            _ = updateWorkspace(containing: terminalID) { workspace in
                workspace.updateTerminalAgentSnapshot(
                    terminalID,
                    snapshot: TerminalAgentSnapshot(
                        providerID: resumeMetadata?.providerID ?? agent,
                        displayName: providerTitle,
                        state: .active,
                        startedAt: startedAt,
                        updatedAt: startedAt,
                        lastEvent: action,
                        resumeCommand: resumeMetadata?.resumeCommand,
                        sessionIdentifier: resumeMetadata?.sessionIdentifier
                    )
                )
            }
            updateMetadata(for: terminalID) { metadata in
                metadata.activeAgentTitle = providerTitle
                metadata.activeAgentStartedAt = startedAt
            }
        case "stop", "agent-response", "subagent-stop":
            let currentMetadata = metadata(for: terminalID)
            let existingSnapshot = controlTerminalInfo(terminalID: terminalID)?.tab.agentSnapshot
            _ = updateWorkspace(containing: terminalID) { workspace in
                workspace.updateTerminalAgentSnapshot(
                    terminalID,
                    snapshot: TerminalAgentSnapshot(
                        providerID: resumeMetadata?.providerID ?? existingSnapshot?.providerID ?? agent,
                        displayName: resumeMetadata?.displayName ?? existingSnapshot?.displayName ?? Self.agentDisplayTitle(for: agent),
                        state: .completed,
                        startedAt: currentMetadata.activeAgentStartedAt,
                        lastEvent: action,
                        resumeCommand: resumeMetadata?.resumeCommand ?? existingSnapshot?.resumeCommand,
                        sessionIdentifier: resumeMetadata?.sessionIdentifier ?? existingSnapshot?.sessionIdentifier
                    )
                )
            }
            updateMetadata(for: terminalID) { metadata in
                metadata.activeAgentTitle = nil
                metadata.activeAgentStartedAt = nil
            }
            deliverAgentReplyNotification(
                terminalID: terminalID,
                agentTitle: Self.agentDisplayTitle(for: agent),
                body: userInfo[ConductorAgentHookBridge.Key.body] ?? ""
            )
        default:
            break
        }
    }

    private func deliverAgentReplyNotification(
        terminalID: TerminalID,
        agentTitle: String,
        body: String
    ) {
        let location = terminalLocation(for: terminalID)
        if location == nil {
            ConductorLog.app.info("Agent reply notification has no open terminal match; delivering without activation target")
            ConductorDiagnostics.record("agent-notification-terminal-missing", fields: ["terminal": terminalID.description])
        }
        let appendResult = controlCreateAttentionEventResult(
            title: L("\(agentTitle) 已回复", "\(agentTitle) replied"),
            body: body,
            kind: .agentReply,
            workspaceID: location?.workspaceID,
            terminalID: terminalID,
            source: "agent-hook",
            details: ["agent": agentTitle],
            coalescingWindow: 8
        )
        guard !appendResult.coalesced else {
            ConductorDiagnostics.record(
                "agent-notification-coalesced",
                fields: [
                    "terminal": terminalID.description,
                    "suppressedCount": String(appendResult.suppressedCount)
                ]
            )
            return
        }
        let request = AgentReplyNotificationRequest(
            attentionEventID: appendResult.event.id,
            terminalID: terminalID,
            agentTitle: agentTitle,
            body: body,
            isUnattended: location.map { isTerminalUnattended(terminalID, location: $0) } ?? true
        )
        agentReplyNotificationService.deliver(request, preferences: appearance.agentReplyNotifications)
    }

    private func isTerminalUnattended(
        _ terminalID: TerminalID,
        location: (workspaceID: WorkspaceID, paneID: PaneID)
    ) -> Bool {
        guard applicationActive,
              workspace.id == location.workspaceID,
              workspace.focusedPaneID == location.paneID,
              workspace.panes[location.paneID]?.selectedTabID == terminalID,
              selectedWorkspaceTerminalTabID == terminalID else {
            return true
        }
        return false
    }

    private static func agentDisplayTitle(for rawAgent: String) -> String {
        if let provider = AgentHookProvider(cliName: rawAgent) {
            return provider.title
        }
        if let definition = AgentIntegrationCatalog.definition(named: rawAgent) {
            return definition.displayName
        }
        return L("AI 终端", "AI Terminal")
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
            guard let surface = surfaceCoordinator.existingSurface(for: terminalID) else { continue }
            let focused = terminalID == focusedTerminalID
            surface.attachIfPossible()
            surface.setFocused(focused, force: true)
            surface.syncGeometry(force: true)
            surface.refresh()
            if focused,
               !terminalSearchVisible,
               let window = surface.hostView.window,
               window.firstResponder !== surface.hostView,
               !windowHasEditableTextFocus(window) {
                window.makeFirstResponder(surface.hostView)
            }
        }
    }

    private func refreshSurfaceAfterNavigation(_ terminalID: TerminalID) {
        guard let surface = surfaceCoordinator.existingSurface(for: terminalID) else { return }
        guard surfaceCoordinator.markPendingNavigationRefresh(terminalID) else { return }
        let signpost = ConductorSignpost.begin("navigation-refresh")
        reconcileSurfaceFocus()
        surface.attachIfPossible()
        surface.setFocused(true, force: true)
        surface.syncGeometry(force: true)
        surface.refresh()
        Task { @MainActor [weak self] in
            defer {
                self?.surfaceCoordinator.clearPendingNavigationRefresh(terminalID)
                ConductorSignpost.end("navigation-refresh", signpost)
            }
            guard let surface = self?.surfaceCoordinator.existingSurface(for: terminalID) else { return }
            surface.attachIfPossible()
            surface.syncGeometry(force: true)
            surface.refresh()
            guard self?.terminalSearchVisible != true else { return }
            guard let window = surface.hostView.window else { return }
            if window.firstResponder !== surface.hostView,
               self?.windowHasEditableTextFocus(window) != true {
                window.makeFirstResponder(surface.hostView)
            }
        }
    }

    private func reconcileSurfaceFocus() {
        let focusedTerminalID = workspace.focusedPane?.selectedTabID
        surfaceCoordinator.setFocusedTerminal(focusedTerminalID)
    }

    private func windowHasEditableTextFocus(_ window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if let textView = responder as? NSTextView {
            return textView.isFieldEditor || textView.isEditable
        }
        if let control = responder as? NSControl,
           control.currentEditor() != nil {
            return true
        }
        return false
    }

    func closeAllSurfaces() {
        surfaceCoordinator.closeAllSurfaces()
        metadataByTerminalID.removeAll(keepingCapacity: false)
        pendingMetadataByTerminalID.removeAll(keepingCapacity: false)
    }

    func flushPersistence() {
        pendingPersistence?.cancel()
        pendingPersistence = nil
        syncSelectedWorkspace()
        saveSelectedWorkspaceContentState()
        let workspaceContentStates = persistedWorkspaceContentStates()
        let selectedContent = workspaceContentStates.first { $0.workspaceID == selectedWorkspaceID }
        persistence.save(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            theme: theme,
            appearance: appearance,
            workspaceWebTabs: selectedContent?.workspaceWebTabs ?? [],
            workspaceFileTabs: selectedContent?.workspaceFileTabs ?? [],
            selectedWorkspaceContentTabID: selectedContent?.selectedWorkspaceContentTabID,
            workspaceContentStates: workspaceContentStates
        )
    }

    func resetWorkspace() {
        closeSurfaces(for: terminalIDs(in: workspace))
        removeWorkspaceContentState(for: workspace.id)
        let replacement = WorkspaceState(title: workspace.title)
        replaceSelectedWorkspace(with: replacement)
        syncPanelCoordinatorFromPublished()
        panelCoordinator.commandPaletteVisible = false
        publishPanelState()
    }

    private func closeSurfaces(for terminalIDs: [TerminalID]) {
        if !terminalIDs.isEmpty {
            ConductorLog.performance.debug("surface close requested count=\(terminalIDs.count, privacy: .public) activeBefore=\(self.surfaceCoordinator.runtimeSurfaceCount, privacy: .public)")
        }
        if let targetID = terminalSearchTargetID, terminalIDs.contains(targetID) {
            terminalSearchVisible = false
            terminalSearchQuery = ""
            terminalSearchTargetID = nil
            syncPanelCoordinatorFromPublished()
        }
        for terminalID in terminalIDs {
            metadataByTerminalID.removeValue(forKey: terminalID)
            pendingMetadataByTerminalID.removeValue(forKey: terminalID)
        }
        surfaceCoordinator.closeSurfaces(for: terminalIDs)
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
            activateWorkspace(target.workspaceID, source: .terminalFocus)
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

    private enum VisibleAgentRuntimeState: Equatable {
        case active(title: String)
        case inactive(title: String)
    }

    private func startAgentRuntimePolling() {
        guard agentRuntimePollTask == nil else { return }
        agentRuntimePollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self {
                    self.refreshVisibleAgentRuntimeStates()
                } else {
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopAgentRuntimePolling() {
        agentRuntimePollTask?.cancel()
        agentRuntimePollTask = nil
    }

    @discardableResult
    private func updateTerminalAgentResumeMetadata(
        _ terminalID: TerminalID,
        metadata resumeMetadata: AgentResumeMetadata,
        lastEvent: String
    ) -> Bool {
        updateWorkspace(containing: terminalID) { workspace in
            guard let paneID = workspace.paneID(containing: terminalID),
                  let pane = workspace.panes[paneID],
                  let tab = pane.tabs.first(where: { $0.id == terminalID }) else {
                return false
            }
            let current = tab.agentSnapshot
            if current?.sessionIdentifier == resumeMetadata.sessionIdentifier,
               current?.resumeCommand == resumeMetadata.resumeCommand {
                return false
            }
            return workspace.updateTerminalAgentSnapshot(
                terminalID,
                snapshot: TerminalAgentSnapshot(
                    providerID: current?.providerID ?? resumeMetadata.providerID,
                    displayName: current?.displayName ?? resumeMetadata.displayName,
                    state: current?.state ?? .idle,
                    startedAt: current?.startedAt,
                    updatedAt: Date(),
                    lastEvent: lastEvent,
                    resumeCommand: resumeMetadata.resumeCommand,
                    sessionIdentifier: resumeMetadata.sessionIdentifier
                )
            )
        }
    }

    /// Pauses the per-terminal agent-state poll while the window is unfocused or
    /// the app is in the background, so an idle window costs nothing. Resumed
    /// when the window becomes key again.
    func setBackgroundActivityPaused(_ paused: Bool) {
        if paused {
            stopAgentRuntimePolling()
        } else {
            startAgentRuntimePolling()
        }
    }

    private func refreshVisibleAgentRuntimeStates() {
        let visible = WorkspaceVisibility.visibleTerminalIDs(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID
        )
        for terminalID in visible {
            guard let surface = surfaceCoordinator.existingSurface(for: terminalID) else {
                continue
            }
            // Intentionally NO surface.refresh() here. visibleText() is a cheap
            // viewport read; render cadence is libghostty's responsibility.
            let visibleText = surface.visibleText() ?? ""
            let current = metadata(for: terminalID)
            let resumeMetadata = AgentResumeDetector.detect(
                in: visibleText,
                fallbackProviderID: current.activeAgentTitle
            )
            guard let state = Self.visibleAgentRuntimeState(in: visibleText) else {
                if let resumeMetadata {
                    updateTerminalAgentResumeMetadata(
                        terminalID,
                        metadata: resumeMetadata,
                        lastEvent: "visible-resume-hint"
                    )
                }
                continue
            }
            switch state {
            case .active(let title):
                if let resumeMetadata {
                    updateTerminalAgentResumeMetadata(
                        terminalID,
                        metadata: resumeMetadata,
                        lastEvent: "visible-resume-hint"
                    )
                }
                guard current.activeAgentTitle != title else { continue }
                let startedAt = Date()
                _ = updateWorkspace(containing: terminalID) { workspace in
                    workspace.updateTerminalAgentSnapshot(
                        terminalID,
                        snapshot: TerminalAgentSnapshot(
                            providerID: resumeMetadata?.providerID ?? title.lowercased(),
                            displayName: resumeMetadata?.displayName ?? title,
                            state: .active,
                            startedAt: startedAt,
                            updatedAt: startedAt,
                            lastEvent: "visible-runtime",
                            resumeCommand: resumeMetadata?.resumeCommand,
                            sessionIdentifier: resumeMetadata?.sessionIdentifier
                        )
                    )
                }
                updateMetadata(for: terminalID) { metadata in
                    metadata.activeAgentTitle = title
                    metadata.activeAgentStartedAt = startedAt
                }
            case .inactive(let title):
                if let resumeMetadata {
                    updateTerminalAgentResumeMetadata(
                        terminalID,
                        metadata: resumeMetadata,
                        lastEvent: "visible-resume-hint"
                    )
                }
                guard current.activeAgentTitle == title else { continue }
                _ = updateWorkspace(containing: terminalID) { workspace in
                    workspace.updateTerminalAgentSnapshot(
                        terminalID,
                        snapshot: TerminalAgentSnapshot(
                            providerID: resumeMetadata?.providerID ?? title.lowercased(),
                            displayName: resumeMetadata?.displayName ?? title,
                            state: .completed,
                            startedAt: current.activeAgentStartedAt,
                            lastEvent: "visible-runtime",
                            resumeCommand: resumeMetadata?.resumeCommand,
                            sessionIdentifier: resumeMetadata?.sessionIdentifier
                        )
                    )
                }
                updateMetadata(for: terminalID) { metadata in
                    metadata.activeAgentTitle = nil
                    metadata.activeAgentStartedAt = nil
                }
            }
        }
    }

    /// Tells libghostty which surfaces are currently visible so it can pause
    /// renderers for hidden tabs, hidden splits, and background workspaces.
    /// Cheap: iterates only attached surfaces, and each `setVisible` call is
    /// a no-op when the value is unchanged.
    private func applyOcclusion() {
        let visible = WorkspaceVisibility.visibleTerminalIDs(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID
        )
        for entry in surfaceCoordinator.allSurfaces {
            entry.surface.setVisible(visible.contains(entry.id))
        }
    }

    private static func visibleAgentRuntimeState(in text: String?) -> VisibleAgentRuntimeState? {
        guard let text, !text.isEmpty else { return nil }
        let normalized = text.lowercased()
        let isCodexScreen = normalized.contains("openai codex") || normalized.contains("codex (v")
        guard isCodexScreen else { return nil }
        let isInterruptible = normalized.contains("esc to interrupt") || normalized.contains("ctrl-c to interrupt")
        let isWorking = normalized.contains("working") || normalized.contains("thinking")
        return isInterruptible && isWorking ? .active(title: "Codex") : .inactive(title: "Codex")
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
            ConductorLog.terminal.warning("Ignoring missing local file URL: \(fileURL.path)")
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
            RenderCounter.increment("metadata-publish")
            self.metadataByTerminalID = next.filter { terminalID, _ in
                self.containsTerminal(terminalID)
            }
            self.scheduleWorkspaceMetadataRefresh(reason: "terminal-metadata")
        }
        pendingMetadataPublish = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: item)
    }

    private func persist() {
        pendingPersistence?.cancel()
        saveSelectedWorkspaceContentState()
        let workspaceContentStates = persistedWorkspaceContentStates()
        let selectedContent = workspaceContentStates.first { $0.workspaceID == selectedWorkspaceID }
        let item = Self.makePersistenceSaveWorkItem(
            persistence: persistence,
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            theme: theme,
            appearance: appearance,
            workspaceWebTabs: selectedContent?.workspaceWebTabs ?? [],
            workspaceFileTabs: selectedContent?.workspaceFileTabs ?? [],
            selectedWorkspaceContentTabID: selectedContent?.selectedWorkspaceContentTabID,
            workspaceContentStates: workspaceContentStates
        )
        pendingPersistence = item
        // Debounce on main (so rapid edits coalesce), then encode + write on a
        // background queue so large YAML/blob serialization never stalls the UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !item.isCancelled else { return }
            self.persistenceQueue.async(execute: item)
        }
    }

    /// Builds the persistence-save work item from a NON-isolated context so its
    /// closure does not inherit this type's `@MainActor` isolation. A closure
    /// literal created inside a `@MainActor` method carries main-actor isolation;
    /// when such an item runs on the background `persistenceQueue`, Swift's runtime
    /// executor-isolation check traps (`dispatch_assert_queue` → EXC_BREAKPOINT).
    /// Constructing it here, where there is no actor isolation to inherit, lets the
    /// item run safely on any queue.
    private nonisolated static func makePersistenceSaveWorkItem(
        persistence: WorkspacePersistence,
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences,
        workspaceWebTabs: [WorkspaceWebTabState],
        workspaceFileTabs: [PersistedFileTab],
        selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID?,
        workspaceContentStates: [PersistedWorkspaceContentState]
    ) -> DispatchWorkItem {
        DispatchWorkItem {
            let signpost = ConductorSignpost.begin("persistence-save")
            defer { ConductorSignpost.end("persistence-save", signpost) }
            persistence.save(
                workspaces: workspaces,
                selectedWorkspaceID: selectedWorkspaceID,
                theme: theme,
                appearance: appearance,
                workspaceWebTabs: workspaceWebTabs,
                workspaceFileTabs: workspaceFileTabs,
                selectedWorkspaceContentTabID: selectedWorkspaceContentTabID,
                workspaceContentStates: workspaceContentStates
            )
        }
    }

    private func persistedFileTabs() -> [PersistedFileTab] {
        persistedFileTabs(workspaceFileTabs)
    }

    private func persistedFileTabs(_ tabs: [ConductorWorkspaceFileTab]) -> [PersistedFileTab] {
        tabs.map {
            PersistedFileTab(filePath: $0.fileURL.path, rootPath: $0.rootURL.path)
        }
    }

    private func persistedWorkspaceContentStates() -> [PersistedWorkspaceContentState] {
        let validWorkspaceIDs = Set(workspaces.map(\.id))
        return workspaceContentStatesByWorkspaceID
            .filter { validWorkspaceIDs.contains($0.key) }
            .map { workspaceID, state in
                PersistedWorkspaceContentState(
                    workspaceID: workspaceID,
                    workspaceWebTabs: state.webTabs,
                    workspaceFileTabs: persistedFileTabs(state.fileTabs),
                    selectedWorkspaceContentTabID: Self.persistedWorkspaceContentSelection(state.selectedContentTabID)
                )
            }
            .sorted { $0.workspaceID.description < $1.workspaceID.description }
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

    private static func normalizedTerminalNotificationTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? L("终端提醒", "Terminal Alert") : trimmed
        return String(source.prefix(80))
    }

    private static func normalizedTerminalNotificationBody(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(280))
    }

    private static func validatedWorkspaceContentSelection(
        _ selection: PersistedWorkspaceContentTabID?,
        workspace: WorkspaceState,
        webTabs: [WorkspaceWebTabState],
        fileTabIDs: Set<String>
    ) -> ConductorWorkspaceContentTabID? {
        switch selection {
        case .terminal(let terminalID):
            return workspace.paneID(containing: terminalID) == nil ? nil : .terminal(terminalID)
        case .file(let tabID):
            return fileTabIDs.contains(tabID) ? .file(tabID) : nil
        case .web(let webTabID):
            return webTabs.contains(where: { $0.id == webTabID }) ? .web(webTabID) : nil
        case nil:
            return nil
        }
    }

    private func persistedWorkspaceContentSelection() -> PersistedWorkspaceContentTabID? {
        Self.persistedWorkspaceContentSelection(selectedWorkspaceContentTabID)
    }

    private static func persistedWorkspaceContentSelection(
        _ selection: ConductorWorkspaceContentTabID?
    ) -> PersistedWorkspaceContentTabID? {
        switch selection {
        case .terminal(let terminalID):
            return .terminal(terminalID)
        case .file(let tabID):
            return .file(tabID)
        case .web(let tabID):
            return .web(tabID)
        case nil:
            return nil
        }
    }

    private func syncSelectedWorkspace() {
        syncWorkspace(workspace)
    }

    private func syncWorkspace(_ snapshot: WorkspaceState) {
        var synchronizedSnapshot = snapshot
        synchronizedSnapshot.reconcileSplitTreeWithPanes()
        if let index = workspaces.firstIndex(where: { $0.id == synchronizedSnapshot.id }) {
            guard workspaces[index] != synchronizedSnapshot else { return }
            workspaces[index] = synchronizedSnapshot
        } else {
            workspaces.append(synchronizedSnapshot)
        }
    }

    private func closeWorkspaceTransientPanels() {
        if terminalSearchVisible {
            closeTerminalSearch()
        }
        syncPanelCoordinatorFromPublished()
        panelCoordinator.commandPaletteVisible = false
        panelCoordinator.workspaceOverviewVisible = false
        publishPanelState()
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
        activateWorkspace(nextWorkspace, source: .listMutation, syncPreviousWorkspace: false)
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

    var controlSelectedWorkspaceID: WorkspaceID {
        selectedWorkspaceID
    }

    func controlWorkspaceMetadataContexts() -> [ConductorWorkspaceMetadataContext] {
        saveSelectedWorkspaceContentState()
        return workspaces.map { workspace in
            let selected = workspace.id == controlSelectedWorkspaceID
            let contentState = selected
                ? currentWorkspaceContentState()
                : (workspaceContentStatesByWorkspaceID[workspace.id] ?? WorkspaceContentRuntimeState())
            let selectedFileTabID: String? = {
                guard case .file(let tabID) = contentState.selectedContentTabID else { return nil }
                return tabID
            }()
            let selectedWebTabID: WebTabID? = {
                guard case .web(let tabID) = contentState.selectedContentTabID else { return nil }
                return tabID
            }()
            var candidateRootPaths: [String] = []
            for paneID in workspace.root.leaves {
                guard let pane = workspace.panes[paneID] else { continue }
                if let selectedTab = pane.selectedTab {
                    candidateRootPaths.append(contentsOf: workspaceRootCandidates(for: selectedTab))
                }
                for tab in pane.tabs where tab.id != pane.selectedTabID {
                    candidateRootPaths.append(contentsOf: workspaceRootCandidates(for: tab))
                }
            }
            if selected {
                if let focusedWorkingDirectoryURL {
                    candidateRootPaths.insert(focusedWorkingDirectoryURL.path, at: 0)
                }
            }
            candidateRootPaths.append(contentsOf: contentState.fileTabs.map(\.rootURL.path))

            let terminalSummaries = workspace.root.leaves.flatMap { paneID -> [WorkspaceMetadataSnapshot.TerminalSummary] in
                guard let pane = workspace.panes[paneID] else { return [] }
                return pane.tabs.map { tab in
                    let displayMetadata = metadata(for: tab.id)
                    let agentSnapshot = tab.agentSnapshot
                    let commandSnapshot = tab.lastCommandSnapshot
                    let searchSnapshot = tab.searchSnapshot
                    let activeAgentTitle = displayMetadata.activeAgentTitle
                        ?? (agentSnapshot?.state == .active ? agentSnapshot?.displayName : nil)
                    return WorkspaceMetadataSnapshot.TerminalSummary(
                        id: tab.id,
                        paneID: pane.id,
                        title: tab.title,
                        workingDirectory: displayMetadata.workingDirectory ?? tab.workingDirectory,
                        selected: tab.id == pane.selectedTabID,
                        activeAgentTitle: activeAgentTitle,
                        activeAgentStartedAt: displayMetadata.activeAgentStartedAt ?? agentSnapshot?.startedAt,
                        agentState: agentSnapshot?.state.rawValue,
                        agentUpdatedAt: agentSnapshot?.updatedAt,
                        lastCommandExitCode: displayMetadata.lastCommandExitCode ?? commandSnapshot?.exitCode,
                        lastCommandDurationNanoseconds: displayMetadata.lastCommandDurationNanoseconds ?? commandSnapshot?.durationNanoseconds,
                        lastCommandFinishedAt: commandSnapshot?.finishedAt,
                        searchActive: displayMetadata.search.active || (searchSnapshot?.active ?? false),
                        searchNeedle: displayMetadata.search.needle ?? searchSnapshot?.needle,
                        searchTotal: displayMetadata.search.total ?? searchSnapshot?.total,
                        searchSelected: displayMetadata.search.selected ?? searchSnapshot?.selected,
                        readonly: displayMetadata.readonly
                    )
                }
            }
            let terminals = workspace.panes.values.flatMap(\.tabs)
            let activeAgentCount = terminals.filter { metadata(for: $0.id).hasActiveAgent }.count
            return ConductorWorkspaceMetadataContext(
                workspaceID: workspace.id,
                title: workspace.title,
                selected: selected,
                candidateRootPaths: deduplicatedPaths(candidateRootPaths),
                counts: WorkspaceMetadataSnapshot.Counts(
                    paneCount: workspace.panes.count,
                    terminalCount: terminals.count,
                    webTabCount: contentState.webTabs.count,
                    fileTabCount: contentState.fileTabs.count
                ),
                activeAgentCount: activeAgentCount,
                unreadCount: attentionUnreadCount(for: workspace.id),
                terminals: terminalSummaries,
                files: contentState.fileTabs.map { tab in
                    WorkspaceMetadataSnapshot.FileSummary(
                        id: tab.id,
                        title: tab.title,
                        path: tab.fileURL.path,
                        rootPath: tab.rootURL.path,
                        selected: tab.id == selectedFileTabID,
                        dirty: contentState.dirtyFileTabIDs.contains(tab.id)
                    )
                },
                webTabs: contentState.webTabs.map { tab in
                    WorkspaceMetadataSnapshot.WebSummary(
                        id: tab.id,
                        title: tab.title,
                        url: tab.url?.absoluteString,
                        pendingAddress: tab.pendingAddress,
                        selected: tab.id == selectedWebTabID,
                        loading: tab.isLoading,
                        errorMessage: tab.errorMessage
                    )
                }
            )
        }
    }

    func scheduleWorkspaceMetadataRefresh(
        reason: String = "ui",
        debounceNanoseconds: UInt64 = 750_000_000
    ) {
        workspaceMetadataRefreshGeneration &+= 1
        let generation = workspaceMetadataRefreshGeneration
        workspaceMetadataRefreshTask?.cancel()
        workspaceMetadataRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled,
                  generation == self.workspaceMetadataRefreshGeneration else {
                return
            }
            let contexts = self.controlWorkspaceMetadataContexts()
            let signpost = ConductorSignpost.begin("workspace-metadata-refresh")
            let snapshots = await ConductorWorkspaceMetadataService.snapshots(for: contexts)
            ConductorSignpost.end("workspace-metadata-refresh", signpost)
            guard !Task.isCancelled,
                  generation == self.workspaceMetadataRefreshGeneration else {
                return
            }
            self.workspaceMetadataSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.workspaceID, $0) })
            ConductorDiagnostics.record(
                "workspace-metadata-refreshed",
                fields: [
                    "reason": reason,
                    "count": String(snapshots.count),
                    "selected": self.controlSelectedWorkspaceID.description
                ]
            )
        }
    }

    private func workspaceRootCandidates(for tab: TerminalTabState) -> [String] {
        [
            metadata(for: tab.id).workingDirectory,
            tab.workingDirectory
        ].compactMap { candidate in
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    private func deduplicatedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { path in
            seen.insert(path).inserted
        }
    }

    var controlAttentionStoreURL: URL {
        attentionStore.url
    }

    func controlAttentionEvents(limit: Int? = nil, includeRead: Bool = true) -> [ConductorAttentionEvent] {
        attentionStore.events(limit: limit, includeRead: includeRead)
    }

    @discardableResult
    func controlCreateAttentionEvent(
        title: String,
        body: String,
        kind: ConductorAttentionEvent.Kind = .manual,
        severity: ConductorAttentionEvent.Severity = .info,
        workspaceID: WorkspaceID? = nil,
        terminalID: TerminalID? = nil,
        webTabID: WebTabID? = nil,
        source: String,
        details: [String: String] = [:]
    ) -> ConductorAttentionEvent {
        controlCreateAttentionEventResult(
            title: title,
            body: body,
            kind: kind,
            severity: severity,
            workspaceID: workspaceID,
            terminalID: terminalID,
            webTabID: webTabID,
            source: source,
            details: details
        ).event
    }

    @discardableResult
    private func controlCreateAttentionEventResult(
        title: String,
        body: String,
        kind: ConductorAttentionEvent.Kind = .manual,
        severity: ConductorAttentionEvent.Severity = .info,
        workspaceID: WorkspaceID? = nil,
        terminalID: TerminalID? = nil,
        webTabID: WebTabID? = nil,
        source: String,
        details: [String: String] = [:],
        coalescingWindow: TimeInterval? = nil
    ) -> ConductorAttentionAppendResult {
        let resolvedWorkspaceID = workspaceID
            ?? terminalID.flatMap { terminalLocation(for: $0)?.workspaceID }
            ?? controlSelectedWorkspaceID
        let event = ConductorAttentionEvent(
            kind: kind,
            severity: severity,
            title: title,
            body: body,
            workspaceID: resolvedWorkspaceID,
            terminalID: terminalID,
            webTabID: webTabID,
            source: source,
            details: details
        )
        let appendResult: ConductorAttentionAppendResult
        if let coalescingWindow {
            appendResult = attentionStore.appendCoalescing(event, window: coalescingWindow)
        } else {
            appendResult = ConductorAttentionAppendResult(
                event: attentionStore.append(event),
                coalesced: false,
                suppressedCount: 0
            )
        }
        refreshAttentionEvents()
        ConductorDiagnostics.record(
            appendResult.coalesced ? "attention-event-coalesced" : "attention-event-created",
            fields: [
                "id": appendResult.event.id.uuidString,
                "kind": appendResult.event.kind.rawValue,
                "workspace": resolvedWorkspaceID.description,
                "terminal": terminalID?.description ?? "none",
                "source": source,
                "suppressedCount": String(appendResult.suppressedCount)
            ]
        )
        return appendResult
    }

    @discardableResult
    func controlClearAttentionEvent(id: UUID? = nil) -> Int {
        let count = attentionStore.clear(id: id)
        refreshAttentionEvents()
        return count
    }

    @discardableResult
    func controlFocusAttentionEvent(id: UUID) -> ConductorAttentionEvent? {
        guard let event = attentionStore.events().first(where: { $0.id == id }),
              focusAttentionTarget(event) else {
            return nil
        }
        let focusedEvent = attentionStore.markRead(id: id) ?? event
        refreshAttentionEvents()
        return focusedEvent
    }

    @discardableResult
    func controlFocusLatestAttentionEvent(workspaceID: WorkspaceID? = nil) -> ConductorAttentionEvent? {
        let events = attentionStore.events(includeRead: false)
        guard let event = events.first(where: { workspaceID == nil || $0.workspaceID == workspaceID }),
              focusAttentionTarget(event) else {
            return nil
        }
        let focusedEvent = attentionStore.markRead(id: event.id) ?? event
        refreshAttentionEvents()
        return focusedEvent
    }

    @discardableResult
    func controlMarkAttentionEventsRead(workspaceID: WorkspaceID? = nil) -> Int {
        let unreadIDs = attentionStore.events(includeRead: false)
            .filter { workspaceID == nil || $0.workspaceID == workspaceID }
            .map(\.id)
        let changed = attentionStore.markRead(ids: Set(unreadIDs))
        refreshAttentionEvents()
        return changed
    }

    private func focusAttentionTarget(_ event: ConductorAttentionEvent) -> Bool {
        if let terminalID = event.terminalID {
            guard containsTerminal(terminalID) else { return false }
            focusTerminal(terminalID)
            return true
        }
        if let webTabID = event.webTabID,
           workspaceWebTabs.contains(where: { $0.id == webTabID }) {
            if let workspaceID = event.workspaceID {
                _ = activateWorkspace(workspaceID, source: .programmatic)
            }
            selectWorkspaceWebTab(webTabID)
            return true
        }
        if let workspaceID = event.workspaceID {
            return activateWorkspace(workspaceID, source: .programmatic)
        }
        return true
    }

    @discardableResult
    func controlCreateWorkspace(title: String?) -> WorkspaceID {
        newWorkspace()
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            renameWorkspace(workspace.id, title: title)
        }
        return workspace.id
    }

    @discardableResult
    func controlRenameWorkspace(_ workspaceID: WorkspaceID?, title: String) -> Bool {
        let targetID = workspaceID ?? controlSelectedWorkspaceID
        guard workspaces.contains(where: { $0.id == targetID }) else { return false }
        renameWorkspace(targetID, title: title)
        return true
    }

    @discardableResult
    func controlDuplicateWorkspace(_ workspaceID: WorkspaceID?) -> WorkspaceID? {
        let sourceID = workspaceID ?? controlSelectedWorkspaceID
        guard workspaces.contains(where: { $0.id == sourceID }) else { return nil }
        duplicateWorkspace(sourceID)
        return workspace.id
    }

    @discardableResult
    func controlCloseWorkspace(_ workspaceID: WorkspaceID?) -> Bool {
        let targetID = workspaceID ?? controlSelectedWorkspaceID
        guard workspaces.count > 1,
              workspaces.contains(where: { $0.id == targetID }) else {
            return false
        }
        closeWorkspace(targetID)
        return true
    }

    @discardableResult
    func controlFocusTerminal(_ terminalID: TerminalID?) -> Bool {
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID, containsTerminal(targetID) else { return false }
        focusTerminal(targetID)
        return focusedTerminalID == targetID
    }

    @discardableResult
    func controlSplitSurface(direction: SplitDirection) -> (paneID: PaneID, terminalID: TerminalID)? {
        guard let paneID = performWorkspaceEdgeSplit(direction),
              let terminalID = workspace.panes[paneID]?.selectedTabID else {
            return nil
        }
        return (paneID, terminalID)
    }

    @discardableResult
    func controlCloseSurface(terminalID: TerminalID?) -> Bool {
        if let terminalID {
            guard containsTerminal(terminalID) else { return false }
            focusTerminal(terminalID)
        }
        let selectedWebTabIDBefore = selectedWorkspaceWebTabID
        let selectedFileTabIDBefore = selectedWorkspaceFileTabID
        let terminalCountBefore = workspaces.reduce(0) { partial, workspace in
            partial + workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
        }
        closeSelectedTab()
        let terminalCountAfter = workspaces.reduce(0) { partial, workspace in
            partial + workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
        }
        return terminalCountAfter != terminalCountBefore ||
            (selectedWebTabIDBefore != nil && selectedWorkspaceWebTabID != selectedWebTabIDBefore) ||
            (selectedFileTabIDBefore != nil && selectedWorkspaceFileTabID != selectedFileTabIDBefore)
    }

    @discardableResult
    func controlToggleSurfaceZoom() -> Bool {
        guard workspace.root.leaves.count > 1 else { return false }
        toggleZoom()
        return true
    }

    @discardableResult
    func controlMoveSurface(mode: String) -> Bool {
        switch mode {
        case "left":
            guard canMoveSelectedTabLeft else { return false }
            moveSelectedTabLeft()
        case "right":
            guard canMoveSelectedTabRight else { return false }
            moveSelectedTabRight()
        case "nextPane":
            guard canMoveSelectedTabToNextPane else { return false }
            moveSelectedTabToNextPane()
        case "newRightSplit":
            guard canMoveSelectedTabToNewSplit else { return false }
            moveSelectedTabToNewSplit(.right)
        case "newDownSplit":
            guard canMoveSelectedTabToNewSplit else { return false }
            moveSelectedTabToNewSplit(.down)
        default:
            return false
        }
        return true
    }

    func controlTerminalInfo(terminalID: TerminalID?) -> (workspaceID: WorkspaceID, paneID: PaneID, tab: TerminalTabState, cwd: URL?)? {
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID,
              let target = terminalContextMenuTarget(for: targetID) else {
            return nil
        }
        return (
            target.workspaceID,
            target.paneID,
            target.tab,
            workingDirectoryURL(for: target.tab.id)
        )
    }

    @discardableResult
    func controlRefreshTerminalAgentResumeMetadata(terminalID: TerminalID?) -> Bool {
        guard let info = controlTerminalInfo(terminalID: terminalID),
              let visibleText = controlVisibleText(terminalID: info.tab.id),
              let resumeMetadata = AgentResumeDetector.detect(
                in: visibleText,
                fallbackProviderID: info.tab.agentSnapshot?.providerID
              ) else {
            return false
        }
        return updateTerminalAgentResumeMetadata(
            info.tab.id,
            metadata: resumeMetadata,
            lastEvent: "control-visible-resume-hint"
        )
    }

    func controlTerminalAgentResumeCommand(terminalID: TerminalID?) -> String? {
        _ = controlRefreshTerminalAgentResumeMetadata(terminalID: terminalID)
        guard let info = controlTerminalInfo(terminalID: terminalID),
              let snapshot = info.tab.agentSnapshot else {
            return nil
        }
        return terminalAgentResumeCommand(snapshot: snapshot)
    }

    private func terminalAgentResumeCommand(snapshot: TerminalAgentSnapshot?) -> String? {
        guard let snapshot else { return nil }
        if let metadata = AgentResumeDetector.metadata(
            providerID: snapshot.providerID,
            sessionIdentifier: snapshot.sessionIdentifier
        ) {
            return metadata.resumeCommand
        }
        if let resumeCommand = snapshot.resumeCommand,
           let metadata = AgentResumeDetector.detect(in: resumeCommand) {
            return metadata.resumeCommand
        }
        return nil
    }

    func controlResumableTerminalAgents(
        workspaceID: WorkspaceID? = nil,
        includeAllWorkspaces: Bool = false
    ) -> [TerminalAgentResumeBatchTarget] {
        syncSelectedWorkspace()
        let targetWorkspaceID = workspaceID ?? (includeAllWorkspaces ? nil : controlSelectedWorkspaceID)
        return workspaces.flatMap { workspace -> [TerminalAgentResumeBatchTarget] in
            guard includeAllWorkspaces || workspace.id == targetWorkspaceID else { return [] }
            return workspace.root.leaves.flatMap { paneID -> [TerminalAgentResumeBatchTarget] in
                guard let pane = workspace.panes[paneID] else { return [] }
                return pane.tabs.compactMap { tab in
                    let snapshot = tab.agentSnapshot
                    guard let resumeCommand = terminalAgentResumeCommand(snapshot: snapshot) else {
                        return nil
                    }
                    let cleanDisplayName = snapshot?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return TerminalAgentResumeBatchTarget(
                        workspaceID: workspace.id,
                        paneID: paneID,
                        terminalID: tab.id,
                        terminalTitle: tab.userTitle ?? tab.title,
                        providerID: snapshot?.providerID,
                        displayName: cleanDisplayName.isEmpty ? "Agent" : cleanDisplayName,
                        resumeCommand: resumeCommand,
                        agentSnapshot: snapshot
                    )
                }
            }
        }
    }

    @discardableResult
    func controlResumeTerminalAgents(
        workspaceID: WorkspaceID? = nil,
        includeAllWorkspaces: Bool = false,
        dryRun: Bool = false
    ) -> [TerminalAgentResumeBatchResult] {
        let targets = controlResumableTerminalAgents(
            workspaceID: workspaceID,
            includeAllWorkspaces: includeAllWorkspaces
        )
        guard !dryRun else {
            return targets.map {
                TerminalAgentResumeBatchResult(target: $0, sent: false, dryRun: true, failureReason: nil)
            }
        }
        let originalWorkspaceID = controlSelectedWorkspaceID
        var results: [TerminalAgentResumeBatchResult] = []
        for target in targets {
            let sent = controlResumeTerminalAgent(terminalID: target.terminalID)
            results.append(TerminalAgentResumeBatchResult(
                target: target,
                sent: sent,
                dryRun: false,
                failureReason: sent ? nil : "resume_command_not_sent"
            ))
        }
        if originalWorkspaceID != controlSelectedWorkspaceID {
            _ = activateWorkspace(originalWorkspaceID, source: .programmatic)
        }
        if !results.isEmpty {
            ConductorDiagnostics.record(
                "terminal-agent-resume-batch",
                fields: [
                    "scope": includeAllWorkspaces ? "all" : "workspace",
                    "workspace": workspaceID?.description ?? (includeAllWorkspaces ? "all" : controlSelectedWorkspaceID.description),
                    "targetCount": String(results.count),
                    "sentCount": String(results.filter(\.sent).count),
                    "dryRun": dryRun ? "true" : "false"
                ]
            )
        }
        return results
    }

    @discardableResult
    func controlResumeTerminalAgent(terminalID: TerminalID?) -> Bool {
        guard let info = controlTerminalInfo(terminalID: terminalID),
              let resumeCommand = controlTerminalAgentResumeCommand(terminalID: info.tab.id) else {
            return false
        }
        let commandText = resumeCommand.hasSuffix("\n") ? resumeCommand : "\(resumeCommand)\n"
        ConductorDiagnostics.record(
            "terminal-agent-resume",
            fields: [
                "terminal": info.tab.id.description,
                "provider": info.tab.agentSnapshot?.providerID ?? "unknown",
                "hasSession": info.tab.agentSnapshot?.sessionIdentifier == nil ? "false" : "true"
            ]
        )
        return controlSendText(commandText, terminalID: info.tab.id)
    }

    @discardableResult
    func controlRenameTerminal(_ terminalID: TerminalID?, title: String) -> Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return false }
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID, containsTerminal(targetID) else { return false }
        renameTerminal(targetID, title: cleanTitle)
        return true
    }

    var controlFocusedWorkingDirectoryURL: URL? {
        focusedWorkingDirectoryURL
    }

    func controlResolveFileURL(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        let baseURL = focusedWorkingDirectoryURL ?? FileManager.default.homeDirectoryForCurrentUser
        return baseURL.appendingPathComponent(expanded).standardizedFileURL
    }

    @discardableResult
    func controlOpenFile(_ fileURL: URL, rootURL: URL? = nil) -> ConductorWorkspaceFileTab? {
        let standardizedFile = fileURL.standardizedFileURL
        openFileInWorkspace(
            standardizedFile,
            rootURL: (rootURL ?? standardizedFile.deletingLastPathComponent()).standardizedFileURL
        )
        return workspaceFileTabs.first { $0.id == standardizedFile.path }
    }

    @discardableResult
    func controlRevealFile(_ fileURL: URL?, rootURL: URL? = nil) -> FileManagerPanelRequest {
        let targetURL = fileURL?.standardizedFileURL
        let values = targetURL.flatMap { try? $0.resourceValues(forKeys: [.isDirectoryKey]) }
        let root: URL
        let selected: URL?
        if let targetURL, values?.isDirectory == true {
            root = (rootURL ?? targetURL).standardizedFileURL
            selected = nil
        } else if let targetURL {
            root = (rootURL ?? targetURL.deletingLastPathComponent()).standardizedFileURL
            selected = targetURL
        } else {
            root = (rootURL ?? focusedWorkingDirectoryURL ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
            selected = nil
        }
        showFileManager(rootURL: root, selectedURL: selected)
        return fileManagerPanelRequest ?? FileManagerPanelRequest(rootURL: root, selectedURL: selected)
    }

    @discardableResult
    func controlSendText(_ text: String, terminalID: TerminalID?) -> Bool {
        guard !text.isEmpty else { return false }
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID else { return false }
        return insertTextIntoTerminal(text, terminalID: targetID)
    }

    func controlVisibleText(terminalID: TerminalID?) -> String? {
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID,
              let target = terminalContextMenuTarget(for: targetID) else {
            return nil
        }
        if target.workspaceID != workspace.id {
            _ = activateWorkspace(target.workspaceID, source: .programmatic)
        }
        focusTerminal(target.tab.id)
        return surface(for: target.tab).visibleText()
    }

    func controlSampleTerminalScroll(terminalID: TerminalID?) -> ConductorPerformanceBudgetSample? {
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID,
              let target = terminalContextMenuTarget(for: targetID) else {
            return nil
        }
        if target.workspaceID != workspace.id {
            _ = activateWorkspace(target.workspaceID, source: .programmatic)
        }
        focusTerminal(target.tab.id)
        let surface = surface(for: target.tab)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        if surface.isReadyForInput {
            _ = surface.performBindingAction("scroll_to_row:0")
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return surface.recordScrollFrameSample(
            durationNanoseconds: elapsed,
            source: "control.terminal.sampleScroll"
        )
    }

    @discardableResult
    func controlSendKey(_ key: String, terminalID: TerminalID?) -> Bool {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let syntheticKey: (characters: String, ignoring: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags)
        switch normalized {
        case "enter", "return":
            syntheticKey = ("\r", "\r", 36, [])
        case "tab":
            syntheticKey = ("\t", "\t", 48, [])
        case "escape", "esc":
            syntheticKey = ("\u{1B}", "\u{1B}", 53, [])
        case "backspace":
            syntheticKey = ("\u{7F}", "\u{7F}", 51, [])
        case "ctrl-c", "control-c":
            syntheticKey = ("\u{03}", "c", 8, [.control])
        case "ctrl-d", "control-d":
            syntheticKey = ("\u{04}", "d", 2, [.control])
        case "up":
            syntheticKey = ("\u{F700}", "\u{F700}", 126, [])
        case "down":
            syntheticKey = ("\u{F701}", "\u{F701}", 125, [])
        case "right":
            syntheticKey = ("\u{F703}", "\u{F703}", 124, [])
        case "left":
            syntheticKey = ("\u{F702}", "\u{F702}", 123, [])
        default:
            return false
        }
        let targetID = terminalID ?? focusedTerminalID
        guard let targetID,
              let target = terminalContextMenuTarget(for: targetID) else {
            return false
        }
        if target.workspaceID != workspace.id {
            _ = activateWorkspace(target.workspaceID, source: .programmatic)
        }
        focusTerminal(target.tab.id)
        let surface = surface(for: target.tab)
        refreshSurfaceAfterNavigation(target.tab.id)
        return surface.sendSyntheticKey(
            characters: syntheticKey.characters,
            charactersIgnoringModifiers: syntheticKey.ignoring,
            keyCode: syntheticKey.keyCode,
            modifierFlags: syntheticKey.modifiers
        )
    }

    @discardableResult
    func controlOpenBrowser(input: String) -> WebTabID? {
        newWorkspaceWebTab(initialInput: input)
        return selectedWorkspaceWebTabID
    }

    @discardableResult
    func controlSelectBrowser(webTabID: WebTabID, workspaceID: WorkspaceID? = nil) -> Bool {
        if let workspaceID {
            selectWorkspaceWebTab(webTabID, in: workspaceID)
            return controlSelectedWorkspaceID == workspaceID && selectedWorkspaceWebTabID == webTabID
        }
        if workspaceWebTabs.contains(where: { $0.id == webTabID }) {
            selectWorkspaceWebTab(webTabID)
            return selectedWorkspaceWebTabID == webTabID
        }
        if let targetWorkspaceID = workspaceContentStatesByWorkspaceID.first(where: { _, state in
            state.webTabs.contains { $0.id == webTabID }
        })?.key {
            selectWorkspaceWebTab(webTabID, in: targetWorkspaceID)
            return controlSelectedWorkspaceID == targetWorkspaceID && selectedWorkspaceWebTabID == webTabID
        }
        return false
    }

    @discardableResult
    func controlSelectFileTab(_ fileTabID: String, workspaceID: WorkspaceID? = nil) -> Bool {
        if let workspaceID {
            let resolvedID: String
            if workspaceID == workspace.id {
                resolvedID = workspaceFileTabs.first {
                    $0.id == fileTabID || $0.title == fileTabID || $0.fileURL.path == fileTabID
                }?.id ?? fileTabID
            } else {
                resolvedID = workspaceContentStatesByWorkspaceID[workspaceID]?.fileTabs.first {
                    $0.id == fileTabID || $0.title == fileTabID || $0.fileURL.path == fileTabID
                }?.id ?? fileTabID
            }
            selectWorkspaceFileTab(resolvedID, in: workspaceID)
            return controlSelectedWorkspaceID == workspaceID && selectedWorkspaceFileTabID == resolvedID
        }
        if let resolvedID = workspaceFileTabs.first(where: { $0.id == fileTabID || $0.title == fileTabID || $0.fileURL.path == fileTabID })?.id {
            selectWorkspaceFileTab(resolvedID)
            return selectedWorkspaceFileTabID == resolvedID
        }
        if let targetWorkspaceID = workspaceContentStatesByWorkspaceID.first(where: { _, state in
            state.fileTabs.contains { $0.id == fileTabID || $0.title == fileTabID || $0.fileURL.path == fileTabID }
        })?.key {
            let targetState = workspaceContentStatesByWorkspaceID[targetWorkspaceID]
            let resolvedID = targetState?.fileTabs.first { $0.id == fileTabID || $0.title == fileTabID || $0.fileURL.path == fileTabID }?.id ?? fileTabID
            selectWorkspaceFileTab(resolvedID, in: targetWorkspaceID)
            return controlSelectedWorkspaceID == targetWorkspaceID && selectedWorkspaceFileTabID == resolvedID
        }
        return false
    }

    @discardableResult
    func controlNavigateBrowser(input: String, webTabID: WebTabID?) -> Bool {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            return false
        }
        navigateWorkspaceWebTab(targetID, input: input)
        return true
    }

    func controlBrowserSnapshot(webTabID: WebTabID?) async throws -> ConductorBrowserSnapshot {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        var snapshot = try await ConductorWebKitSurfaceStore.shared.snapshot(for: targetID)
        snapshot.runtimeEvents = workspaceWebTabs.first(where: { $0.id == targetID })?.runtimeEvents ?? []
        return snapshot
    }

    func controlBrowserScreenshot(webTabID: WebTabID?) async throws -> ConductorBrowserScreenshot {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        return try await ConductorWebKitSurfaceStore.shared.screenshot(for: targetID)
    }

    func controlBrowserClick(webTabID: WebTabID?, target: String) async throws -> ConductorBrowserAutomationResult {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        return try await ConductorWebKitSurfaceStore.shared.click(for: targetID, target: target)
    }

    func controlBrowserFill(webTabID: WebTabID?, target: String, value: String) async throws -> ConductorBrowserAutomationResult {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        return try await ConductorWebKitSurfaceStore.shared.fill(for: targetID, target: target, value: value)
    }

    func controlBrowserPress(webTabID: WebTabID?, key: String, target: String?) async throws -> ConductorBrowserAutomationResult {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        return try await ConductorWebKitSurfaceStore.shared.press(for: targetID, key: key, target: target)
    }

    func controlBrowserWait(
        webTabID: WebTabID?,
        condition: String,
        target: String,
        timeoutSeconds: Double
    ) async throws -> ConductorBrowserAutomationResult {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        return try await ConductorWebKitSurfaceStore.shared.wait(
            for: targetID,
            condition: condition,
            target: target,
            timeoutSeconds: timeoutSeconds
        )
    }

    func controlBrowserFind(webTabID: WebTabID?, query: String, frameID: String?) async throws -> ConductorBrowserAutomationResult {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        return try await ConductorWebKitSurfaceStore.shared.find(for: targetID, query: query, frameID: frameID)
    }

    func controlBrowserEvaluate(webTabID: WebTabID?, script: String, frameID: String?) async throws -> ConductorBrowserAutomationResult {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            throw ConductorBrowserSnapshotError.targetNotFound
        }
        let result = try await ConductorWebKitSurfaceStore.shared.evaluate(for: targetID, script: script, frameID: frameID)
        await captureBrowserRuntimeState(for: targetID, persistAfterCapture: true)
        return result
    }

    @discardableResult
    func controlReloadBrowser(webTabID: WebTabID?) -> Bool {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            return false
        }
        reloadWorkspaceWebTab(targetID)
        return true
    }

    @discardableResult
    func controlStopBrowser(webTabID: WebTabID?) -> Bool {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID,
              workspaceWebTabs.contains(where: { $0.id == targetID }) else {
            return false
        }
        stopWorkspaceWebTab(targetID)
        return true
    }

    @discardableResult
    func controlBrowserBack(webTabID: WebTabID?) -> Bool {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID else { return false }
        goBackWorkspaceWebTab(targetID)
        return true
    }

    @discardableResult
    func controlBrowserForward(webTabID: WebTabID?) -> Bool {
        let targetID = webTabID ?? selectedWorkspaceWebTabID
        guard let targetID else { return false }
        goForwardWorkspaceWebTab(targetID)
        return true
    }

    private func captureBrowserRuntimeState(for tabID: WebTabID, persistAfterCapture: Bool) async {
        guard let state = await ConductorWebKitSurfaceStore.shared.runtimeState(for: tabID) else { return }
        applyBrowserRuntimeState(state, to: tabID)
        if persistAfterCapture {
            persist()
        }
    }

    private func applyBrowserRuntimeState(_ state: ConductorWebRuntimeState, to tabID: WebTabID) {
        updateWorkspaceWebTab(tabID) { tab in
            if state.entries.count > 1, let currentIndex = state.currentIndex {
                tab.navigationEntries = state.entries
                tab.currentNavigationIndex = currentIndex
            } else if let url = tab.url, tab.navigationEntries.isEmpty {
                tab.navigationEntries = [WorkspaceWebNavigationEntry(url: url, title: tab.title)]
                tab.currentNavigationIndex = 0
            }
            if let scrollY = state.scrollY, scrollY.isFinite {
                tab.scrollY = max(0, scrollY)
            }
            let currentIndex = tab.currentNavigationIndex ?? 0
            tab.canGoBack = tab.canGoBack || currentIndex > 0
            tab.canGoForward = tab.canGoForward || currentIndex < tab.navigationEntries.count - 1
        }
    }

    private func terminalIDs(in workspace: WorkspaceState) -> [TerminalID] {
        workspace.panes.values.flatMap { pane in
            pane.tabs.map(\.id)
        }
    }

}
