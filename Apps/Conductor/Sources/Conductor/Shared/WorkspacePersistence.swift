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

    init(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences = AppearancePreferences(),
        workspaceWebTabs: [WorkspaceWebTabState] = [],
        workspaceFileTabs: [PersistedFileTab] = [],
        selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID? = nil
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.theme = theme
        self.appearance = appearance
        self.workspaceWebTabs = workspaceWebTabs
        self.workspaceFileTabs = workspaceFileTabs
        self.selectedWorkspaceContentTabID = selectedWorkspaceContentTabID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(TerminalTheme.self, forKey: .theme)
        self.appearance = try container.decodeIfPresent(AppearancePreferences.self, forKey: .appearance) ?? AppearancePreferences()
        self.workspaceWebTabs = try container.decodeIfPresent([WorkspaceWebTabState].self, forKey: .workspaceWebTabs) ?? []
        self.workspaceFileTabs = try container.decodeIfPresent([PersistedFileTab].self, forKey: .workspaceFileTabs) ?? []
        self.selectedWorkspaceContentTabID = (try? container.decodeIfPresent(PersistedWorkspaceContentTabID.self, forKey: .selectedWorkspaceContentTabID)) ?? nil

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
    }
}

/// On-disk representation of an open file editor tab. File tabs aren't tied to
/// the workspace split tree, so they persist as a flat list alongside it.
struct PersistedFileTab: Codable, Equatable {
    var filePath: String
    var rootPath: String
}

enum PersistedWorkspaceContentTabID: Codable, Equatable {
    case terminal(TerminalID)
    case file(String)
    case web(WebTabID)
}

final class WorkspacePersistence {
    static var isEnabledByDefault: Bool {
        ProcessInfo.processInfo.environment["CONDUCTOR_DISABLE_PERSISTENCE"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_SMOKE_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_SHORTCUT_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_FOCUS_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_LAYOUT_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_LIFECYCLE_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_SHELL_PANEL_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_NOTIFICATION_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_STRESS_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_RESIZE_STRESS_AUTORUN"] != "1" &&
            ProcessInfo.processInfo.environment["CONDUCTOR_WORKSPACE_AUTORUN"] != "1"
    }

    private let fileURL: URL
    private let legacyJSONFileURL: URL?
    private let snapshotDirectoryURL: URL?
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
            self.snapshotDirectoryURL = URL(fileURLWithPath: overridePath)
                .deletingLastPathComponent()
                .appendingPathComponent("session-snapshots", isDirectory: true)
        } else {
            self.fileURL = directoryURL.appendingPathComponent("window-state.yaml")
            self.legacyJSONFileURL = directoryURL.appendingPathComponent("window-state.json")
            self.snapshotDirectoryURL = directoryURL.appendingPathComponent("session-snapshots", isDirectory: true)
        }
    }

    func load() -> PersistedWindowState? {
        guard isEnabled else { return nil }
        if ProcessInfo.processInfo.environment["CONDUCTOR_RESET_STATE"] == "1" {
            reset()
            return nil
        }
        guard let state = loadState() else {
            return nil
        }
        let validWorkspaces = state.workspaces.map(sanitizedWorkspace).filter(isValid)
        guard !validWorkspaces.isEmpty else { return nil }
        let selectedWorkspaceID = validWorkspaces.contains(where: { $0.id == state.selectedWorkspaceID })
            ? state.selectedWorkspaceID
            : validWorkspaces[0].id
        return PersistedWindowState(
            workspaces: validWorkspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            theme: state.theme,
            appearance: state.appearance,
            workspaceWebTabs: sanitizedWebTabs(state.workspaceWebTabs),
            workspaceFileTabs: sanitizedFileTabs(state.workspaceFileTabs),
            selectedWorkspaceContentTabID: state.selectedWorkspaceContentTabID
        )
    }

    func save(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences,
        workspaceWebTabs: [WorkspaceWebTabState] = [],
        workspaceFileTabs: [PersistedFileTab] = [],
        selectedWorkspaceContentTabID: PersistedWorkspaceContentTabID? = nil
    ) {
        guard isEnabled else { return }
        let persistedWorkspaces = workspaces.map(sanitizedWorkspace).filter(isValid)
        guard !persistedWorkspaces.isEmpty else { return }
        let selectedID = persistedWorkspaces.contains(where: { $0.id == selectedWorkspaceID })
            ? selectedWorkspaceID
            : persistedWorkspaces[0].id
        let state = PersistedWindowState(
            workspaces: persistedWorkspaces,
            selectedWorkspaceID: selectedID,
            theme: theme,
            appearance: appearance,
            workspaceWebTabs: sanitizedWebTabs(workspaceWebTabs),
            workspaceFileTabs: sanitizedFileTabs(workspaceFileTabs),
            selectedWorkspaceContentTabID: selectedWorkspaceContentTabID
        )
        guard let data = encodeState(state, for: fileURL) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        if let legacyJSONFileURL {
            try? FileManager.default.removeItem(at: legacyJSONFileURL)
        }
        if let snapshotDirectoryURL {
            try? FileManager.default.removeItem(at: snapshotDirectoryURL)
        }
    }

    // MARK: - Terminal session snapshots (sidecar)

    /// Persists a terminal's prior-session VT scrollback to a sidecar file keyed by
    /// terminal ID. New snapshots use the `.vt` extension; legacy `.txt` plain-text
    /// snapshots from before the VT upgrade are still read on load.
    func saveTerminalSnapshot(id: TerminalID, text: String) {
        guard isEnabled, let snapshotDirectoryURL, !text.isEmpty else { return }
        try? FileManager.default.createDirectory(at: snapshotDirectoryURL, withIntermediateDirectories: true)
        let url = snapshotDirectoryURL.appendingPathComponent("\(id.description).vt")
        try? text.data(using: .utf8)?.write(to: url, options: [.atomic])
        // Drop any stale plain-text sidecar so the two formats never diverge.
        try? FileManager.default.removeItem(
            at: snapshotDirectoryURL.appendingPathComponent("\(id.description).txt")
        )
    }

    func loadTerminalSnapshot(id: TerminalID) -> String? {
        guard isEnabled, let snapshotDirectoryURL else { return nil }
        for ext in ["vt", "txt"] {
            let url = snapshotDirectoryURL.appendingPathComponent("\(id.description).\(ext)")
            if let data = try? Data(contentsOf: url) {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// One-shot: snapshots are consumed on restore so they never stack up.
    func removeTerminalSnapshot(id: TerminalID) {
        guard let snapshotDirectoryURL else { return }
        for ext in ["vt", "txt"] {
            try? FileManager.default.removeItem(
                at: snapshotDirectoryURL.appendingPathComponent("\(id.description).\(ext)")
            )
        }
    }

    /// Drops snapshot files for terminals that no longer exist.
    func pruneTerminalSnapshots(keeping retainedIDs: Set<TerminalID>) {
        guard let snapshotDirectoryURL else { return }
        var retained = Set<String>()
        for id in retainedIDs {
            retained.insert("\(id.description).vt")
            retained.insert("\(id.description).txt")
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshotDirectoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where !retained.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func loadState() -> PersistedWindowState? {
        let candidates = [fileURL, legacyJSONFileURL].compactMap(\.self)
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path),
                  let state = decodeState(at: url) else {
                continue
            }
            return state
        }
        return nil
    }

    private func decodeState(at url: URL) -> PersistedWindowState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if url.pathExtension.lowercased() == "json" {
            return try? JSONDecoder().decode(PersistedWindowState.self, from: data)
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return try? YAMLDecoder().decode(PersistedWindowState.self, from: text)
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

    /// Drops file tabs whose file no longer exists so restore never reopens a
    /// stale path, and de-duplicates by file path.
    private func sanitizedFileTabs(_ tabs: [PersistedFileTab]) -> [PersistedFileTab] {
        var seen = Set<String>()
        return tabs.filter { tab in
            guard !tab.filePath.isEmpty else { return false }
            guard FileManager.default.fileExists(atPath: tab.filePath) else { return false }
            return seen.insert(tab.filePath).inserted
        }
    }

}
