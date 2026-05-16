import ConductorCore
import Foundation

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

@MainActor
final class ConductorWindowModel: ObservableObject, GhosttyAppRuntimeActionDelegate {
    @Published var workspace: WorkspaceState {
        didSet {
            selectedWorkspaceID = workspace.id
            syncSelectedWorkspace()
            persist()
        }
    }
    @Published private(set) var workspaces: [WorkspaceState]
    @Published var theme: TerminalTheme {
        didSet {
            surfaces.values.forEach { $0.applyTheme(theme) }
            persist()
        }
    }
    @Published private(set) var metadataByTerminalID: [TerminalID: TerminalDisplayMetadata] = [:]
    @Published private(set) var notifications = TerminalNotificationState()
    @Published var notificationPanelVisible = false
    @Published var sidebarVisible = true
    @Published var commandPaletteVisible = false

    private let persistence = WorkspacePersistence()
    private var surfaces: [TerminalID: TerminalSurface] = [:]
    private var pendingPersistence: DispatchWorkItem?
    private var pendingMetadataByTerminalID: [TerminalID: TerminalDisplayMetadata] = [:]
    private var pendingMetadataPublish: DispatchWorkItem?
    private var selectedWorkspaceID: WorkspaceID

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
        self.theme = persisted?.theme ?? .codexDark
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

    var runtimeSurfaceCount: Int {
        surfaces.count
    }

    var runtimeMetadataCount: Int {
        metadataByTerminalID.count + pendingMetadataByTerminalID.count
    }

    func runtimeHasSurface(for terminalID: TerminalID) -> Bool {
        surfaces[terminalID] != nil
    }

    func surface(for tab: TerminalTabState) -> TerminalSurface {
        if let surface = surfaces[tab.id] {
            return surface
        }
        let surface = TerminalSurface(id: tab.id, theme: theme, workingDirectory: tab.workingDirectory)
        surface.onFocusRequest = { [weak self] terminalID in
            self?.focusTerminal(terminalID)
        }
        surfaces[tab.id] = surface
        return surface
    }

    func newTerminal() {
        let signpost = ConductorSignpost.begin("new-terminal")
        defer { ConductorSignpost.end("new-terminal", signpost) }
        workspace.newTerminal(title: nextTerminalTitle(prefix: "zsh"))
    }

    func newTab(in paneID: PaneID) {
        let signpost = ConductorSignpost.begin("new-tab")
        defer { ConductorSignpost.end("new-tab", signpost) }
        workspace.focusPane(paneID)
        workspace.newTab(title: nextTerminalTitle(prefix: "tab"))
    }

    func splitRight() {
        let signpost = ConductorSignpost.begin("split-right")
        defer { ConductorSignpost.end("split-right", signpost) }
        workspace.splitWorkspaceEdge(.right, title: nextTerminalTitle(prefix: "zsh"))
    }

    func splitDown() {
        let signpost = ConductorSignpost.begin("split-down")
        defer { ConductorSignpost.end("split-down", signpost) }
        workspace.splitWorkspaceEdge(.down, title: nextTerminalTitle(prefix: "zsh"))
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
            return workspace.selectTab(lastTabID, in: paneID)
        }

        if let offset {
            if offset > 0, offset <= pane.tabs.count {
                return workspace.selectTab(pane.tabs[offset - 1].id, in: paneID)
            }
            return workspace.selectAdjacentTab(offset: offset, in: paneID) != nil
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
        return workspace.splitWorkspaceEdge(direction, title: nextTerminalTitle(prefix: "zsh")) != nil
    }

    func ghosttyRuntimeDidRequestFocus(terminalID: TerminalID, direction: FocusDirection) -> Bool {
        guard let paneID = workspace.paneID(containing: terminalID) else { return false }
        workspace.focusPane(paneID)
        return workspace.focusAdjacentPane(direction) != nil
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
        workspace.selectTab(terminalID, in: paneID)
        markTerminalNotificationsRead(terminalID)
    }

    func focusPane(_ paneID: PaneID) {
        workspace.focusPane(paneID)
    }

    func focusTerminal(_ terminalID: TerminalID) {
        if workspace.paneID(containing: terminalID) == nil,
           let workspaceID = workspaces.first(where: { $0.paneID(containing: terminalID) != nil })?.id {
            selectWorkspace(workspaceID)
        }
        guard let paneID = workspace.paneID(containing: terminalID) else { return }
        workspace.selectTab(terminalID, in: paneID)
    }

    @discardableResult
    func newWorkspace() -> WorkspaceID {
        let signpost = ConductorSignpost.begin("new-workspace")
        defer { ConductorSignpost.end("new-workspace", signpost) }
        syncSelectedWorkspace()
        let next = WorkspaceState(title: nextWorkspaceTitle())
        workspaces.append(next)
        selectedWorkspaceID = next.id
        workspace = next
        commandPaletteVisible = false
        return next.id
    }

    func duplicateWorkspace(_ workspaceID: WorkspaceID) {
        let signpost = ConductorSignpost.begin("duplicate-workspace")
        defer { ConductorSignpost.end("duplicate-workspace", signpost) }
        syncSelectedWorkspace()
        guard let index = workspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let duplicate = workspaces[index].duplicated(title: nextCopyTitle(for: workspaces[index].title))
        workspaces.insert(duplicate, at: index + 1)
        selectedWorkspaceID = duplicate.id
        workspace = duplicate
        commandPaletteVisible = false
    }

    func selectWorkspace(_ workspaceID: WorkspaceID) {
        guard workspaceID != workspace.id,
              let target = workspaces.first(where: { $0.id == workspaceID }) else {
            return
        }
        syncSelectedWorkspace()
        selectedWorkspaceID = workspaceID
        workspace = target
        commandPaletteVisible = false
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
            selectedWorkspaceID = workspaces[nextIndex].id
            workspace = workspaces[nextIndex]
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
        selectedWorkspaceID = keptWorkspace.id
        workspace = keptWorkspace
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
            selectedWorkspaceID = workspaceID
            workspace = workspaces[index]
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
        workspace.selectAdjacentTab(offset: 1)
    }

    func selectPreviousTab() {
        workspace.selectAdjacentTab(offset: -1)
    }

    func focusNextPane() {
        workspace.focusAdjacentPane(.next)
    }

    func focusPreviousPane() {
        workspace.focusAdjacentPane(.previous)
    }

    func focusPane(direction: FocusDirection) {
        workspace.focusAdjacentPane(direction)
    }

    func resizeFocusedSplit(direction: ResizeSplitDirection, amount: Double = 5) {
        let signpost = ConductorSignpost.begin("resize-split")
        defer { ConductorSignpost.end("resize-split", signpost) }
        workspace.resizeFocusedSplit(direction: direction, amount: amount)
    }

    func toggleCommandPalette() {
        commandPaletteVisible.toggle()
    }

    func hideCommandPalette() {
        commandPaletteVisible = false
    }

    func toggleNotificationPanel() {
        notificationPanelVisible.toggle()
        if notificationPanelVisible {
            commandPaletteVisible = false
        }
    }

    func hideNotificationPanel() {
        notificationPanelVisible = false
    }

    func notifyFocusedTerminalForTesting() {
        guard let tab = workspace.focusedPane?.selectedTab else { return }
        _ = recordTerminalNotification(
            terminalID: tab.id,
            title: "Agent",
            body: "Conductor notification route is wired.",
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
        focusTerminal(notification.terminalID)
        markNotificationRead(notificationID)
        notificationPanelVisible = false
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
        mutateNotifications { $0.markTerminalRead(terminalID) }
        refreshNotificationMetadata(for: terminalID)
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

    func equalizeSplits() {
        workspace.equalizeSplits()
    }

    func toggleZoom() {
        workspace.toggleZoom()
    }

    func setSplitFraction(path: [SplitPathElement], fraction: Double) {
        let signpost = ConductorSignpost.begin("drag-split-divider")
        defer { ConductorSignpost.end("drag-split-divider", signpost) }
        workspace.setSplitFraction(path: path, fraction: fraction)
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
        persistence.save(workspaces: workspaces, selectedWorkspaceID: selectedWorkspaceID, theme: theme)
    }

    func resetWorkspace() {
        closeSurfaces(for: terminalIDs(in: workspace))
        let replacement = WorkspaceState(title: workspace.title)
        replaceSelectedWorkspace(with: replacement)
        commandPaletteVisible = false
    }

    private func closeSurfaces(for terminalIDs: [TerminalID]) {
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

    private func metadata(for terminalID: TerminalID) -> TerminalDisplayMetadata {
        pendingMetadataByTerminalID[terminalID] ?? metadataByTerminalID[terminalID] ?? TerminalDisplayMetadata()
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
        syncSelectedWorkspace()
        let workspaces = workspaces
        let selectedWorkspaceID = selectedWorkspaceID
        let theme = theme
        let item = DispatchWorkItem { [persistence] in
            persistence.save(workspaces: workspaces, selectedWorkspaceID: selectedWorkspaceID, theme: theme)
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
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
    }

    private func replaceSelectedWorkspace(with replacement: WorkspaceState) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = replacement
        } else {
            workspaces.append(replacement)
        }
        selectedWorkspaceID = replacement.id
        workspace = replacement
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
