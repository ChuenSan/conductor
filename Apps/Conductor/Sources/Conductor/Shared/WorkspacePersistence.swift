import ConductorCore
import Foundation

struct PersistedWindowState: Codable {
    var workspaces: [WorkspaceState]
    var selectedWorkspaceID: WorkspaceID
    var theme: TerminalTheme
    var appearance: AppearancePreferences

    init(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences = AppearancePreferences()
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.theme = theme
        self.appearance = appearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.theme = try container.decode(TerminalTheme.self, forKey: .theme)
        self.appearance = try container.decodeIfPresent(AppearancePreferences.self, forKey: .appearance) ?? AppearancePreferences()

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
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case workspaces
        case selectedWorkspaceID
        case theme
        case appearance
    }
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
    private let isEnabled: Bool

    init(fileManager: FileManager = .default, isEnabled: Bool = WorkspacePersistence.isEnabledByDefault) {
        self.isEnabled = isEnabled
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = baseURL.appendingPathComponent("Conductor", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let overridePath = ProcessInfo.processInfo.environment["CONDUCTOR_STATE_PATH"], !overridePath.isEmpty {
            self.fileURL = URL(fileURLWithPath: overridePath)
        } else {
            self.fileURL = directoryURL.appendingPathComponent("window-state.json")
        }
    }

    func load() -> PersistedWindowState? {
        guard isEnabled else { return nil }
        if ProcessInfo.processInfo.environment["CONDUCTOR_RESET_STATE"] == "1" {
            reset()
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedWindowState.self, from: data) else {
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
            appearance: state.appearance
        )
    }

    func save(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        theme: TerminalTheme,
        appearance: AppearancePreferences
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
            appearance: appearance
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func isValid(_ workspace: WorkspaceState) -> Bool {
        guard !workspace.panes.isEmpty,
              workspace.panes[workspace.focusedPaneID] != nil else {
            return false
        }
        let leaves = Set(workspace.root.leaves)
        return !leaves.isEmpty && leaves.allSatisfy { workspace.panes[$0] != nil }
    }

    private func sanitizedWorkspace(_ workspace: WorkspaceState) -> WorkspaceState {
        var sanitized = workspace
        sanitized.zoomedPaneID = nil
        return sanitized
    }
}
