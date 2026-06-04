import ConductorCore
import Foundation
import Yams

struct PersistedWindowState: Codable {
    var workspaces: [WorkspaceState]
    var selectedWorkspaceID: WorkspaceID
    var theme: TerminalTheme
    var appearance: AppearancePreferences
    var workspaceWebTabs: [WorkspaceWebTabState]
    var workspaceFileTabs: [PersistedFileTab]
    var selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID?
    var workspaceContentStates: [PersistedWorkspaceContentState]

    init(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences = AppearancePreferences(),
        workspaceWebTabs: [WorkspaceWebTabState] = [],
        workspaceFileTabs: [PersistedFileTab] = [],
        selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID? = nil,
        workspaceContentStates: [PersistedWorkspaceContentState] = []
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.theme = theme
        self.appearance = appearance
        self.workspaceWebTabs = workspaceWebTabs
        self.workspaceFileTabs = workspaceFileTabs
        self.selectedWorkspaceContentTabID = selectedWorkspaceContentTabID
        self.workspaceContentStates = workspaceContentStates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(TerminalTheme.self, forKey: .theme)
        self.appearance = try container.decodeIfPresent(AppearancePreferences.self, forKey: .appearance) ?? AppearancePreferences()
        self.workspaceWebTabs = try container.decodeIfPresent([WorkspaceWebTabState].self, forKey: .workspaceWebTabs) ?? []
        self.workspaceFileTabs = try container.decodeIfPresent([PersistedFileTab].self, forKey: .workspaceFileTabs) ?? []
        self.selectedWorkspaceContentTabID = (try? container.decodeIfPresent(PersistedWorkspaceContentTabID.self, forKey: .selectedWorkspaceContentTabID)) ?? nil
        self.workspaceContentStates = try container.decodeIfPresent([PersistedWorkspaceContentState].self, forKey: .workspaceContentStates) ?? []

        if let workspaces = try container.decodeIfPresent([WorkspaceState].self, forKey: .workspaces),
           !workspaces.isEmpty {
            self.workspaces = workspaces
            self.selectedWorkspaceID = try container.decodeIfPresent(WorkspaceID.self, forKey: .selectedWorkspaceID) ?? workspaces[0].id
            return
        }

        let legacyWorkspace = try container.decode(WorkspaceState.self, forKey: .workspace)
        self.workspaces = [legacyWorkspace]
        self.selectedWorkspaceID = legacyWorkspace.id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaces, forKey: .workspaces)
        try container.encode(selectedWorkspaceID, forKey: .selectedWorkspaceID)
        try container.encode(theme, forKey: .theme)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(workspaceWebTabs, forKey: .workspaceWebTabs)
        try container.encode(workspaceFileTabs, forKey: .workspaceFileTabs)
        try container.encodeIfPresent(selectedWorkspaceContentTabID, forKey: .selectedWorkspaceContentTabID)
        try container.encode(workspaceContentStates, forKey: .workspaceContentStates)
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case workspaces
        case selectedWorkspaceID
        case theme
        case appearance
        case workspaceWebTabs
        case workspaceFileTabs
        case selectedWorkspaceContentTabID
        case workspaceContentStates
    }
}

/// On-disk representation of an open file editor tab. File tabs aren't tied to
/// the workspace split tree, so they persist as a flat list alongside it.
struct PersistedFileTab: Codable, Equatable {
    var filePath: String
    var rootPath: String
}

/// Per-workspace content tabs that are not part of the terminal split tree.
struct PersistedWorkspaceContentState: Codable, Equatable {
    var workspaceID: WorkspaceID
    var workspaceWebTabs: [WorkspaceWebTabState]
    var workspaceFileTabs: [PersistedFileTab]
    var selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID?
}

enum PersistedWorkspaceContentTabID: Codable, Equatable {
    case terminal(TerminalID)
    case file(String)
    case web(WebTabID)
}

final class WorkspacePersistence {
    static var isEnabledByDefault: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CONDUCTOR_DISABLE_PERSISTENCE"] != "1" else { return false }
        if environment["CONDUCTOR_NOTIFICATION_AUTORUN"] == "1" {
            return !(environment["CONDUCTOR_STATE_PATH"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return environment["CONDUCTOR_SMOKE_AUTORUN"] != "1" &&
            environment["CONDUCTOR_SHORTCUT_AUTORUN"] != "1" &&
            environment["CONDUCTOR_FOCUS_AUTORUN"] != "1" &&
            environment["CONDUCTOR_LAYOUT_AUTORUN"] != "1" &&
            environment["CONDUCTOR_LIFECYCLE_AUTORUN"] != "1" &&
            environment["CONDUCTOR_SHELL_PANEL_AUTORUN"] != "1" &&
            environment["CONDUCTOR_STRESS_AUTORUN"] != "1" &&
            environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] != "1" &&
            environment["CONDUCTOR_WORKSPACE_AUTORUN"] != "1"
    }

    private let fileURL: URL
    private let legacyJSONFileURL: URL?
    private let isEnabled: Bool

    init(fileManager: FileManager = .default, isEnabled: Bool = WorkspacePersistence.isEnabledByDefault) {
        self.isEnabled = isEnabled
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = baseURL.appendingPathComponent("Conductor", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let overridePath = ProcessInfo.processInfo.environment["CONDUCTOR_STATE_PATH"], !overridePath.isEmpty {
            self.fileURL = URL(fileURLWithPath: overridePath)
            self.legacyJSONFileURL = nil
        } else {
            self.fileURL = directoryURL.appendingPathComponent("window-state.yaml")
            self.legacyJSONFileURL = directoryURL.appendingPathComponent("window-state.json")
        }
    }

    func save(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences,
        workspaceWebTabs: [WorkspaceWebTabState] = [],
        workspaceFileTabs: [PersistedFileTab] = [],
        selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID? = nil,
        workspaceContentStates: [PersistedWorkspaceContentState] = []
    ) {
        guard isEnabled else { return }
        let persistedWorkspaces = workspaces.map(sanitizedWorkspace).filter(isValid)
        guard !persistedWorkspaces.isEmpty else { return }
        let selectedID = persistedWorkspaces.contains(where: { $0.id == selectedWorkspaceID })
            ? selectedWorkspaceID
            : persistedWorkspaces[0].id
        let validWorkspaceIDs = Set(persistedWorkspaces.map(\.id))
        let sanitizedContentStates = sanitizedWorkspaceContentStates(
            workspaceContentStates,
            validWorkspaceIDs: validWorkspaceIDs,
            legacyWebTabs: workspaceWebTabs,
            legacyFileTabs: workspaceFileTabs,
            legacySelection: selectedWorkspaceContentTabID,
            selectedWorkspaceID: selectedID
        ).states
        let selectedContent = sanitizedContentStates.first { $0.workspaceID == selectedID }
        let state = PersistedWindowState(
            workspaces: persistedWorkspaces,
            selectedWorkspaceID: selectedID,
            theme: theme,
            appearance: appearance,
            workspaceWebTabs: selectedContent?.workspaceWebTabs ?? [],
            workspaceFileTabs: selectedContent?.workspaceFileTabs ?? [],
            selectedWorkspaceContentTabID: selectedContent?.selectedWorkspaceContentTabID,
            workspaceContentStates: sanitizedContentStates
        )
        guard let data = encodeState(state, for: fileURL) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        if let legacyJSONFileURL {
            try? FileManager.default.removeItem(at: legacyJSONFileURL)
        }
    }

    private struct SanitizedFileTabsResult {
        var tabs: [PersistedFileTab]
    }

    private struct SanitizedWorkspaceContentStatesResult {
        var states: [PersistedWorkspaceContentState]
    }

    private func encodeState(_ state: PersistedWindowState, for url: URL) -> Data? {
        if url.pathExtension.lowercased() == "json" {
            return try? JSONEncoder().encode(state)
        }
        let encoder = YAMLEncoder()
        encoder.options.allowUnicode = true
        guard let text = try? encoder.encode(state) else { return nil }
        return text.data(using: .utf8)
    }

    private func isValid(_ workspace: WorkspaceState) -> Bool {
        guard !workspace.panes.isEmpty,
              workspace.panes[workspace.focusedPaneID] != nil else {
            return false
        }
        return workspace.hasCoherentSplitTree
    }

    private func sanitizedWorkspace(_ workspace: WorkspaceState) -> WorkspaceState {
        var sanitized = workspace
        sanitized.reconcileSplitTreeWithPanes()
        sanitized.zoomedPaneID = nil
        return sanitized
    }

    private func sanitizedWebTabs(_ tabs: [WorkspaceWebTabState]) -> [WorkspaceWebTabState] {
        tabs.map { tab in
            var sanitized = tab
            sanitized.isLoading = false
            sanitized.estimatedProgress = 0
            sanitized.canGoBack = false
            sanitized.canGoForward = false
            sanitized.errorMessage = nil
            return sanitized
        }
    }

    private func sanitizedWorkspaceContentStates(
        _ states: [PersistedWorkspaceContentState],
        validWorkspaceIDs: Set<WorkspaceID>,
        legacyWebTabs: [WorkspaceWebTabState],
        legacyFileTabs: [PersistedFileTab],
        legacySelection: PersistedWorkspaceContentTabID?,
        selectedWorkspaceID: WorkspaceID
    ) -> SanitizedWorkspaceContentStatesResult {
        var result: [PersistedWorkspaceContentState] = []
        var seenWorkspaceIDs = Set<WorkspaceID>()

        for state in states {
            let webTabs = sanitizedWebTabs(state.workspaceWebTabs)
            let fileReport = sanitizedFileTabs(state.workspaceFileTabs)
            guard validWorkspaceIDs.contains(state.workspaceID) else { continue }
            guard seenWorkspaceIDs.insert(state.workspaceID).inserted else { continue }
            let fileTabs = fileReport.tabs
            let selection = sanitizedSelection(
                state.selectedWorkspaceContentTabID,
                webTabs: webTabs,
                fileTabs: fileTabs
            )
            guard !webTabs.isEmpty || !fileTabs.isEmpty || selection != nil else { continue }
            result.append(PersistedWorkspaceContentState(
                workspaceID: state.workspaceID,
                workspaceWebTabs: webTabs,
                workspaceFileTabs: fileTabs,
                selectedWorkspaceContentTabID: selection
            ))
        }

        if !seenWorkspaceIDs.contains(selectedWorkspaceID),
           (!legacyWebTabs.isEmpty || !legacyFileTabs.isEmpty || legacySelection != nil) {
            let webTabs = sanitizedWebTabs(legacyWebTabs)
            let fileReport = sanitizedFileTabs(legacyFileTabs)
            let fileTabs = fileReport.tabs
            let selection = sanitizedSelection(legacySelection, webTabs: webTabs, fileTabs: fileTabs)
            if !webTabs.isEmpty || !fileTabs.isEmpty || selection != nil {
                result.append(PersistedWorkspaceContentState(
                    workspaceID: selectedWorkspaceID,
                    workspaceWebTabs: webTabs,
                    workspaceFileTabs: fileTabs,
                    selectedWorkspaceContentTabID: selection
                ))
            }
        }

        return SanitizedWorkspaceContentStatesResult(states: result)
    }

    private func sanitizedSelection(
        _ selection: PersistedWorkspaceContentTabID?,
        webTabs: [WorkspaceWebTabState],
        fileTabs: [PersistedFileTab]
    ) -> PersistedWorkspaceContentTabID? {
        switch selection {
        case .terminal:
            return selection
        case .file(let tabID):
            return fileTabs.contains { $0.filePath == tabID } ? selection : nil
        case .web(let webTabID):
            return webTabs.contains { $0.id == webTabID } ? selection : nil
        case nil:
            return nil
        }
    }

    /// Drops file tabs whose file no longer exists and de-duplicates by file path.
    private func sanitizedFileTabs(_ tabs: [PersistedFileTab]) -> SanitizedFileTabsResult {
        var seen = Set<String>()
        var result: [PersistedFileTab] = []
        for tab in tabs {
            guard !tab.filePath.isEmpty else { continue }
            guard FileManager.default.fileExists(atPath: tab.filePath) else { continue }
            guard seen.insert(tab.filePath).inserted else { continue }
            result.append(tab)
        }
        return SanitizedFileTabsResult(tabs: result)
    }

}
