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

struct WorkspacePersistenceLoadReport: Equatable {
    enum State: String {
        case disabled
        case reset
        case missing
        case restored
        case restoredFromPrevious
        case restoredFromJournal
        case failed
    }

    var state: State
    var sourcePath: String?
    var attemptedPaths: [String]
    var failedPaths: [String]
    var originalWorkspaceCount: Int
    var restoredWorkspaceCount: Int
    var droppedWorkspaceCount: Int
    var originalWebTabCount: Int
    var restoredWebTabCount: Int
    var droppedWebTabCount: Int
    var originalFileTabCount: Int
    var restoredFileTabCount: Int
    var droppedFileTabCount: Int
    var missingFilePaths: [String]
    var message: String

    static func initial() -> WorkspacePersistenceLoadReport {
        WorkspacePersistenceLoadReport(
            state: .missing,
            sourcePath: nil,
            attemptedPaths: [],
            failedPaths: [],
            originalWorkspaceCount: 0,
            restoredWorkspaceCount: 0,
            droppedWorkspaceCount: 0,
            originalWebTabCount: 0,
            restoredWebTabCount: 0,
            droppedWebTabCount: 0,
            originalFileTabCount: 0,
            restoredFileTabCount: 0,
            droppedFileTabCount: 0,
            missingFilePaths: [],
            message: "Session state has not been loaded yet."
        )
    }
}

/// On-disk representation of an open file editor tab. File tabs aren't tied to
/// the workspace split tree, so they persist as a flat list alongside it.
struct PersistedFileTab: Codable, Equatable {
    var filePath: String
    var rootPath: String
}

/// Per-workspace content tabs that are not part of the terminal split tree.
/// The legacy flat `workspaceWebTabs`/`workspaceFileTabs` fields remain for
/// old snapshots and are migrated to the selected workspace on load.
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
    private let previousSnapshotURL: URL
    private let legacyJSONFileURL: URL?
    private let snapshotDirectoryURL: URL?
    private let isEnabled: Bool
    private(set) var lastLoadReport = WorkspacePersistenceLoadReport.initial()

    var hasPreviousSnapshot: Bool {
        isEnabled && FileManager.default.fileExists(atPath: previousSnapshotURL.path)
    }

    init(fileManager: FileManager = .default, isEnabled: Bool = WorkspacePersistence.isEnabledByDefault) {
        self.isEnabled = isEnabled
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = baseURL.appendingPathComponent("Conductor", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let overridePath = ProcessInfo.processInfo.environment["CONDUCTOR_STATE_PATH"], !overridePath.isEmpty {
            self.fileURL = URL(fileURLWithPath: overridePath)
            self.previousSnapshotURL = Self.previousSnapshotURL(for: URL(fileURLWithPath: overridePath))
            self.legacyJSONFileURL = nil
            self.snapshotDirectoryURL = URL(fileURLWithPath: overridePath)
                .deletingLastPathComponent()
                .appendingPathComponent("session-snapshots", isDirectory: true)
        } else {
            self.fileURL = directoryURL.appendingPathComponent("window-state.yaml")
            self.previousSnapshotURL = directoryURL.appendingPathComponent("window-state.previous.yaml")
            self.legacyJSONFileURL = directoryURL.appendingPathComponent("window-state.json")
            self.snapshotDirectoryURL = directoryURL.appendingPathComponent("session-snapshots", isDirectory: true)
        }
    }

    func load() -> PersistedWindowState? {
        guard isEnabled else {
            lastLoadReport = WorkspacePersistenceLoadReport(
                state: .disabled,
                sourcePath: nil,
                attemptedPaths: [],
                failedPaths: [],
                originalWorkspaceCount: 0,
                restoredWorkspaceCount: 0,
                droppedWorkspaceCount: 0,
                originalWebTabCount: 0,
                restoredWebTabCount: 0,
                droppedWebTabCount: 0,
                originalFileTabCount: 0,
                restoredFileTabCount: 0,
                droppedFileTabCount: 0,
                missingFilePaths: [],
                message: "Persistence is disabled for this launch."
            )
            return nil
        }
        if ProcessInfo.processInfo.environment["CONDUCTOR_RESET_STATE"] == "1" {
            reset()
            lastLoadReport = WorkspacePersistenceLoadReport(
                state: .reset,
                sourcePath: nil,
                attemptedPaths: [],
                failedPaths: [],
                originalWorkspaceCount: 0,
                restoredWorkspaceCount: 0,
                droppedWorkspaceCount: 0,
                originalWebTabCount: 0,
                restoredWebTabCount: 0,
                droppedWebTabCount: 0,
                originalFileTabCount: 0,
                restoredFileTabCount: 0,
                droppedFileTabCount: 0,
                missingFilePaths: [],
                message: "State was reset by CONDUCTOR_RESET_STATE."
            )
            return nil
        }
        let candidates = loadStateCandidates()
        guard !candidates.attemptedPaths.isEmpty else {
            if let journalRestored = restoreFromSessionJournal(attemptedPaths: [], failedPaths: []) {
                return journalRestored
            }
            lastLoadReport = WorkspacePersistenceLoadReport(
                state: .missing,
                sourcePath: nil,
                attemptedPaths: [],
                failedPaths: [],
                originalWorkspaceCount: 0,
                restoredWorkspaceCount: 0,
                droppedWorkspaceCount: 0,
                originalWebTabCount: 0,
                restoredWebTabCount: 0,
                droppedWebTabCount: 0,
                originalFileTabCount: 0,
                restoredFileTabCount: 0,
                droppedFileTabCount: 0,
                missingFilePaths: [],
                message: "No persisted session state was found."
            )
            return nil
        }

        if let restored = restoreFirstValidState(from: candidates) {
            return restored
        }

        if let journalRestored = restoreFromSessionJournal(
            attemptedPaths: candidates.attemptedPaths,
            failedPaths: candidates.failedPaths.isEmpty ? candidates.attemptedPaths : candidates.failedPaths
        ) {
            return journalRestored
        }

        lastLoadReport = WorkspacePersistenceLoadReport(
            state: .failed,
            sourcePath: nil,
            attemptedPaths: candidates.attemptedPaths,
            failedPaths: candidates.failedPaths.isEmpty ? candidates.attemptedPaths : candidates.failedPaths,
            originalWorkspaceCount: 0,
            restoredWorkspaceCount: 0,
            droppedWorkspaceCount: 0,
            originalWebTabCount: 0,
            restoredWebTabCount: 0,
            droppedWebTabCount: 0,
            originalFileTabCount: 0,
            restoredFileTabCount: 0,
            droppedFileTabCount: 0,
            missingFilePaths: [],
            message: "Persisted session state was found but no valid workspace could be restored."
        )
        return nil
    }

    private func restoreFromSessionJournal(attemptedPaths: [String], failedPaths: [String]) -> PersistedWindowState? {
        let journal = ConductorSessionJournal(directoryURL: fileURL.deletingLastPathComponent(), isEnabled: isEnabled)
        guard FileManager.default.fileExists(atPath: journal.url.path),
              let replay = journal.replay(),
              !replay.workspaces.isEmpty else {
            return nil
        }
        let validWorkspaces = replay.workspaces.map(sanitizedWorkspace).filter(isValid)
        guard !validWorkspaces.isEmpty else { return nil }
        let validWorkspaceIDs = Set(validWorkspaces.map(\.id))
        let selectedWorkspaceID = validWorkspaceIDs.contains(replay.selectedWorkspaceID)
            ? replay.selectedWorkspaceID
            : validWorkspaces[0].id
        let contentStates = replay.workspaceContentStates
            .filter { validWorkspaceIDs.contains($0.workspaceID) }
            .map { content in
                PersistedWorkspaceContentState(
                    workspaceID: content.workspaceID,
                    workspaceWebTabs: sanitizedWebTabs(content.webTabs),
                    workspaceFileTabs: content.fileTabs.map {
                        PersistedFileTab(filePath: $0.filePath, rootPath: $0.rootPath)
                    },
                    selectedWorkspaceContentTabID: Self.persistedSelection(content.selectedContentTabID)
                )
            }
        let contentReport = sanitizedWorkspaceContentStates(
            contentStates,
            validWorkspaceIDs: validWorkspaceIDs,
            legacyWebTabs: [],
            legacyFileTabs: [],
            legacySelection: nil,
            selectedWorkspaceID: selectedWorkspaceID
        )
        let selectedContent = contentReport.states.first { $0.workspaceID == selectedWorkspaceID }
        lastLoadReport = WorkspacePersistenceLoadReport(
            state: .restoredFromJournal,
            sourcePath: journal.url.path,
            attemptedPaths: attemptedPaths + [journal.url.path],
            failedPaths: failedPaths,
            originalWorkspaceCount: replay.workspaces.count,
            restoredWorkspaceCount: validWorkspaces.count,
            droppedWorkspaceCount: replay.workspaces.count - validWorkspaces.count,
            originalWebTabCount: contentReport.originalWebTabCount,
            restoredWebTabCount: contentReport.restoredWebTabCount,
            droppedWebTabCount: contentReport.droppedWebTabCount,
            originalFileTabCount: contentReport.originalFileTabCount,
            restoredFileTabCount: contentReport.restoredFileTabCount,
            droppedFileTabCount: contentReport.droppedFileTabCount,
            missingFilePaths: contentReport.missingFilePaths,
            message: "Recovered a session skeleton from the event journal after snapshot restore was unavailable."
        )
        return PersistedWindowState(
            workspaces: validWorkspaces,
            selectedWorkspaceID: selectedWorkspaceID,
            theme: .codexDark,
            appearance: AppearancePreferences(),
            workspaceWebTabs: selectedContent?.workspaceWebTabs ?? [],
            workspaceFileTabs: selectedContent?.workspaceFileTabs ?? [],
            selectedWorkspaceContentTabID: selectedContent?.selectedWorkspaceContentTabID,
            workspaceContentStates: contentReport.states
        )
    }

    private static func persistedSelection(_ selection: WorkspaceContentSelection?) -> PersistedWorkspaceContentTabID? {
        switch selection {
        case .terminal(let terminalID):
            .terminal(terminalID)
        case .file(let path):
            .file(path)
        case .web(let webTabID):
            .web(webTabID)
        case nil:
            nil
        }
    }

    func loadPreviousSnapshot() -> PersistedWindowState? {
        guard isEnabled else {
            lastLoadReport = WorkspacePersistenceLoadReport(
                state: .disabled,
                sourcePath: nil,
                attemptedPaths: [],
                failedPaths: [],
                originalWorkspaceCount: 0,
                restoredWorkspaceCount: 0,
                droppedWorkspaceCount: 0,
                originalWebTabCount: 0,
                restoredWebTabCount: 0,
                droppedWebTabCount: 0,
                originalFileTabCount: 0,
                restoredFileTabCount: 0,
                droppedFileTabCount: 0,
                missingFilePaths: [],
                message: "Persistence is disabled for this launch."
            )
            return nil
        }
        let candidates = loadStateCandidates([(previousSnapshotURL, .previous)])
        guard !candidates.attemptedPaths.isEmpty else {
            lastLoadReport = WorkspacePersistenceLoadReport(
                state: .missing,
                sourcePath: nil,
                attemptedPaths: [],
                failedPaths: [],
                originalWorkspaceCount: 0,
                restoredWorkspaceCount: 0,
                droppedWorkspaceCount: 0,
                originalWebTabCount: 0,
                restoredWebTabCount: 0,
                droppedWebTabCount: 0,
                originalFileTabCount: 0,
                restoredFileTabCount: 0,
                droppedFileTabCount: 0,
                missingFilePaths: [],
                message: "No previous session snapshot was found."
            )
            return nil
        }
        if let restored = restoreFirstValidState(from: candidates) {
            return restored
        }
        lastLoadReport = WorkspacePersistenceLoadReport(
            state: .failed,
            sourcePath: nil,
            attemptedPaths: candidates.attemptedPaths,
            failedPaths: candidates.failedPaths.isEmpty ? candidates.attemptedPaths : candidates.failedPaths,
            originalWorkspaceCount: 0,
            restoredWorkspaceCount: 0,
            droppedWorkspaceCount: 0,
            originalWebTabCount: 0,
            restoredWebTabCount: 0,
            droppedWebTabCount: 0,
            originalFileTabCount: 0,
            restoredFileTabCount: 0,
            droppedFileTabCount: 0,
            missingFilePaths: [],
            message: "Previous session snapshot exists but could not restore a valid workspace."
        )
        return nil
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
        preservePreviousSnapshotIfNeeded()
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: [.atomic])
    }

    func reset() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: previousSnapshotURL)
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

    private struct LoadedState {
        enum Source {
            case current
            case previous
            case legacy
        }

        var state: PersistedWindowState
        var url: URL
        var source: Source
    }

    private struct LoadStateCandidates {
        var loadedStates: [LoadedState]
        var attemptedPaths: [String]
        var failedPaths: [String]
    }

    private struct SanitizedFileTabsResult {
        var tabs: [PersistedFileTab]
        var originalCount: Int
        var droppedCount: Int
        var missingFilePaths: [String]
    }

    private struct SanitizedWorkspaceContentStatesResult {
        var states: [PersistedWorkspaceContentState]
        var originalWebTabCount: Int
        var restoredWebTabCount: Int
        var droppedWebTabCount: Int
        var originalFileTabCount: Int
        var restoredFileTabCount: Int
        var droppedFileTabCount: Int
        var missingFilePaths: [String]
    }

    private func loadStateCandidates(_ explicitCandidates: [(URL, LoadedState.Source)]? = nil) -> LoadStateCandidates {
        let legacyCandidates = legacyJSONFileURL.map { [($0, LoadedState.Source.legacy)] } ?? []
        let candidates: [(URL, LoadedState.Source)] = explicitCandidates ?? [
            (fileURL, .current),
            (previousSnapshotURL, .previous)
        ] + legacyCandidates
        var attemptedPaths: [String] = []
        var failedPaths: [String] = []
        var loadedStates: [LoadedState] = []
        for (url, source) in candidates where FileManager.default.fileExists(atPath: url.path) {
            attemptedPaths.append(url.path)
            if let state = decodeState(at: url) {
                loadedStates.append(LoadedState(state: state, url: url, source: source))
            } else {
                failedPaths.append(url.path)
            }
        }
        return LoadStateCandidates(
            loadedStates: loadedStates,
            attemptedPaths: attemptedPaths,
            failedPaths: failedPaths
        )
    }

    private func restoreFirstValidState(from candidates: LoadStateCandidates) -> PersistedWindowState? {
        var failedPaths = candidates.failedPaths
        for loaded in candidates.loadedStates {
            let sanitizedWorkspaces = loaded.state.workspaces.map(sanitizedWorkspace)
            let validWorkspaces = sanitizedWorkspaces.filter(isValid)
            guard !validWorkspaces.isEmpty else {
                failedPaths.append(loaded.url.path)
                continue
            }
            let selectedWorkspaceID = validWorkspaces.contains(where: { $0.id == loaded.state.selectedWorkspaceID })
                ? loaded.state.selectedWorkspaceID
                : validWorkspaces[0].id
            let validWorkspaceIDs = Set(validWorkspaces.map(\.id))
            let contentReport = sanitizedWorkspaceContentStates(
                loaded.state.workspaceContentStates,
                validWorkspaceIDs: validWorkspaceIDs,
                legacyWebTabs: loaded.state.workspaceWebTabs,
                legacyFileTabs: loaded.state.workspaceFileTabs,
                legacySelection: loaded.state.selectedWorkspaceContentTabID,
                selectedWorkspaceID: selectedWorkspaceID
            )
            let sanitizedContentStates = contentReport.states
            let selectedContent = sanitizedContentStates.first { $0.workspaceID == selectedWorkspaceID }
            let sanitizedFiles = selectedContent?.workspaceFileTabs ?? []
            let sanitizedWebTabs = selectedContent?.workspaceWebTabs ?? []
            let reportState: WorkspacePersistenceLoadReport.State = loaded.source == .previous ? .restoredFromPrevious : .restored
            lastLoadReport = WorkspacePersistenceLoadReport(
                state: reportState,
                sourcePath: loaded.url.path,
                attemptedPaths: candidates.attemptedPaths,
                failedPaths: failedPaths,
                originalWorkspaceCount: loaded.state.workspaces.count,
                restoredWorkspaceCount: validWorkspaces.count,
                droppedWorkspaceCount: loaded.state.workspaces.count - validWorkspaces.count,
                originalWebTabCount: contentReport.originalWebTabCount,
                restoredWebTabCount: contentReport.restoredWebTabCount,
                droppedWebTabCount: contentReport.droppedWebTabCount,
                originalFileTabCount: contentReport.originalFileTabCount,
                restoredFileTabCount: contentReport.restoredFileTabCount,
                droppedFileTabCount: contentReport.droppedFileTabCount,
                missingFilePaths: contentReport.missingFilePaths,
                message: reportState == .restoredFromPrevious
                    ? "Recovered session from the previous valid snapshot."
                    : "Restored session from the latest snapshot."
            )
            return PersistedWindowState(
                workspaces: validWorkspaces,
                selectedWorkspaceID: selectedWorkspaceID,
                theme: loaded.state.theme,
                appearance: loaded.state.appearance,
                workspaceWebTabs: sanitizedWebTabs,
                workspaceFileTabs: sanitizedFiles,
                selectedWorkspaceContentTabID: selectedContent?.selectedWorkspaceContentTabID,
                workspaceContentStates: sanitizedContentStates
            )
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

    private func preservePreviousSnapshotIfNeeded() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              decodeState(at: fileURL) != nil else {
            return
        }
        try? FileManager.default.removeItem(at: previousSnapshotURL)
        try? FileManager.default.copyItem(at: fileURL, to: previousSnapshotURL)
    }

    private static func previousSnapshotURL(for fileURL: URL) -> URL {
        let pathExtension = fileURL.pathExtension
        let baseURL = fileURL.deletingPathExtension()
        guard !pathExtension.isEmpty else {
            return URL(fileURLWithPath: baseURL.path + ".previous")
        }
        return URL(fileURLWithPath: baseURL.path + ".previous.\(pathExtension)")
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
        var originalWebTabCount = 0
        var restoredWebTabCount = 0
        var originalFileTabCount = 0
        var restoredFileTabCount = 0
        var missingFilePaths: [String] = []

        for state in states {
            originalWebTabCount += state.workspaceWebTabs.count
            originalFileTabCount += state.workspaceFileTabs.count
            let webTabs = sanitizedWebTabs(state.workspaceWebTabs)
            let fileReport = sanitizedFileTabs(state.workspaceFileTabs)
            missingFilePaths.append(contentsOf: fileReport.missingFilePaths)
            guard validWorkspaceIDs.contains(state.workspaceID) else { continue }
            guard seenWorkspaceIDs.insert(state.workspaceID).inserted else { continue }
            let fileTabs = fileReport.tabs
            let selection = sanitizedSelection(
                state.selectedWorkspaceContentTabID,
                webTabs: webTabs,
                fileTabs: fileTabs
            )
            restoredWebTabCount += webTabs.count
            restoredFileTabCount += fileTabs.count
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
            originalWebTabCount += legacyWebTabs.count
            originalFileTabCount += legacyFileTabs.count
            let webTabs = sanitizedWebTabs(legacyWebTabs)
            let fileReport = sanitizedFileTabs(legacyFileTabs)
            let fileTabs = fileReport.tabs
            let selection = sanitizedSelection(legacySelection, webTabs: webTabs, fileTabs: fileTabs)
            restoredWebTabCount += webTabs.count
            restoredFileTabCount += fileTabs.count
            missingFilePaths.append(contentsOf: fileReport.missingFilePaths)
            if !webTabs.isEmpty || !fileTabs.isEmpty || selection != nil {
                result.append(PersistedWorkspaceContentState(
                    workspaceID: selectedWorkspaceID,
                    workspaceWebTabs: webTabs,
                    workspaceFileTabs: fileTabs,
                    selectedWorkspaceContentTabID: selection
                ))
            }
        }

        return SanitizedWorkspaceContentStatesResult(
            states: result,
            originalWebTabCount: originalWebTabCount,
            restoredWebTabCount: restoredWebTabCount,
            droppedWebTabCount: max(0, originalWebTabCount - restoredWebTabCount),
            originalFileTabCount: originalFileTabCount,
            restoredFileTabCount: restoredFileTabCount,
            droppedFileTabCount: max(0, originalFileTabCount - restoredFileTabCount),
            missingFilePaths: Array(missingFilePaths.prefix(12))
        )
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

    /// Drops file tabs whose file no longer exists so restore never reopens a
    /// stale path, and de-duplicates by file path.
    private func sanitizedFileTabs(_ tabs: [PersistedFileTab]) -> SanitizedFileTabsResult {
        var seen = Set<String>()
        var result: [PersistedFileTab] = []
        var missingFilePaths: [String] = []
        var droppedCount = 0
        for tab in tabs {
            guard !tab.filePath.isEmpty else {
                droppedCount += 1
                continue
            }
            guard FileManager.default.fileExists(atPath: tab.filePath) else {
                droppedCount += 1
                missingFilePaths.append(tab.filePath)
                continue
            }
            guard seen.insert(tab.filePath).inserted else {
                droppedCount += 1
                continue
            }
            result.append(tab)
        }
        return SanitizedFileTabsResult(
            tabs: result,
            originalCount: tabs.count,
            droppedCount: droppedCount,
            missingFilePaths: Array(missingFilePaths.prefix(12))
        )
    }

}
