import Foundation

public struct ConductorSessionJournalEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case snapshotSaved
        case workspaceCreated
        case workspaceRenamed
        case workspaceDuplicated
        case workspaceClosed
        case workspaceSelected
        case terminalCreated
        case terminalDuplicated
        case terminalClosed
        case paneClosed
        case browserTabOpened
        case browserTabNavigated
        case browserTabClosed
        case fileTabOpened
        case fileTabClosed
    }

    public var id: UUID
    public var timestamp: Date
    public var kind: Kind
    public var selectedWorkspaceID: WorkspaceID?
    public var workspaceID: WorkspaceID?
    public var paneID: PaneID?
    public var terminalID: TerminalID?
    public var webTabID: WebTabID?
    public var workspaceCount: Int
    public var terminalCount: Int
    public var webTabCount: Int
    public var fileTabCount: Int
    public var details: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case kind
        case selectedWorkspaceID
        case workspaceID
        case paneID
        case terminalID
        case webTabID
        case workspaceCount
        case terminalCount
        case webTabCount
        case fileTabCount
        case details
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        selectedWorkspaceID: WorkspaceID? = nil,
        workspaceID: WorkspaceID? = nil,
        paneID: PaneID? = nil,
        terminalID: TerminalID? = nil,
        webTabID: WebTabID? = nil,
        workspaceCount: Int = 0,
        terminalCount: Int = 0,
        webTabCount: Int = 0,
        fileTabCount: Int = 0,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.selectedWorkspaceID = selectedWorkspaceID
        self.workspaceID = workspaceID
        self.paneID = paneID
        self.terminalID = terminalID
        self.webTabID = webTabID
        self.workspaceCount = workspaceCount
        self.terminalCount = terminalCount
        self.webTabCount = webTabCount
        self.fileTabCount = fileTabCount
        self.details = details
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeUUID(forKey: .id) ?? UUID()
        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        kind = try container.decode(Kind.self, forKey: .kind)
        selectedWorkspaceID = try container.decodeWorkspaceIDIfPresent(forKey: .selectedWorkspaceID)
        workspaceID = try container.decodeWorkspaceIDIfPresent(forKey: .workspaceID)
        paneID = try container.decodePaneIDIfPresent(forKey: .paneID)
        terminalID = try container.decodeTerminalIDIfPresent(forKey: .terminalID)
        webTabID = try container.decodeWebTabIDIfPresent(forKey: .webTabID)
        workspaceCount = try container.decodeIfPresent(Int.self, forKey: .workspaceCount) ?? 0
        terminalCount = try container.decodeIfPresent(Int.self, forKey: .terminalCount) ?? 0
        webTabCount = try container.decodeIfPresent(Int.self, forKey: .webTabCount) ?? 0
        fileTabCount = try container.decodeIfPresent(Int.self, forKey: .fileTabCount) ?? 0
        details = try container.decodeIfPresent([String: String].self, forKey: .details) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(selectedWorkspaceID?.description, forKey: .selectedWorkspaceID)
        try container.encodeIfPresent(workspaceID?.description, forKey: .workspaceID)
        try container.encodeIfPresent(paneID?.description, forKey: .paneID)
        try container.encodeIfPresent(terminalID?.description, forKey: .terminalID)
        try container.encodeIfPresent(webTabID?.rawValue.uuidString, forKey: .webTabID)
        try container.encode(workspaceCount, forKey: .workspaceCount)
        try container.encode(terminalCount, forKey: .terminalCount)
        try container.encode(webTabCount, forKey: .webTabCount)
        try container.encode(fileTabCount, forKey: .fileTabCount)
        try container.encode(details, forKey: .details)
    }
}

private struct ConductorSessionJournalRawID: Codable {
    var rawValue: UUID
}

private extension KeyedDecodingContainer {
    func decodeUUID(forKey key: Key) throws -> UUID? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return UUID(uuidString: value)
        }
        if let value = try? decodeIfPresent(UUID.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(ConductorSessionJournalRawID.self, forKey: key) {
            return value.rawValue
        }
        return nil
    }

    func decodeWorkspaceIDIfPresent(forKey key: Key) throws -> WorkspaceID? {
        try decodeUUID(forKey: key).map(WorkspaceID.init)
    }

    func decodePaneIDIfPresent(forKey key: Key) throws -> PaneID? {
        try decodeUUID(forKey: key).map(PaneID.init)
    }

    func decodeTerminalIDIfPresent(forKey key: Key) throws -> TerminalID? {
        try decodeUUID(forKey: key).map(TerminalID.init)
    }

    func decodeWebTabIDIfPresent(forKey key: Key) throws -> WebTabID? {
        try decodeUUID(forKey: key).map { WebTabID(rawValue: $0) }
    }
}

public struct ConductorSessionJournalSummary: Equatable, Sendable {
    public var entryCount: Int
    public var latestEvent: ConductorSessionJournalEvent?
    public var fileSizeBytes: Int

    public init(
        entryCount: Int,
        latestEvent: ConductorSessionJournalEvent?,
        fileSizeBytes: Int
    ) {
        self.entryCount = entryCount
        self.latestEvent = latestEvent
        self.fileSizeBytes = fileSizeBytes
    }
}

public struct ConductorSessionJournalReplayFileTab: Equatable, Sendable {
    public var filePath: String
    public var rootPath: String

    public init(filePath: String, rootPath: String) {
        self.filePath = filePath
        self.rootPath = rootPath
    }
}

public struct ConductorSessionJournalReplayWorkspaceContent: Equatable, Sendable {
    public var workspaceID: WorkspaceID
    public var webTabs: [WorkspaceWebTabState]
    public var fileTabs: [ConductorSessionJournalReplayFileTab]
    public var selectedContentTabID: WorkspaceContentSelection?

    public init(
        workspaceID: WorkspaceID,
        webTabs: [WorkspaceWebTabState],
        fileTabs: [ConductorSessionJournalReplayFileTab],
        selectedContentTabID: WorkspaceContentSelection?
    ) {
        self.workspaceID = workspaceID
        self.webTabs = webTabs
        self.fileTabs = fileTabs
        self.selectedContentTabID = selectedContentTabID
    }
}

public struct ConductorSessionJournalReplayResult: Equatable, Sendable {
    public var workspaces: [WorkspaceState]
    public var selectedWorkspaceID: WorkspaceID
    public var workspaceContentStates: [ConductorSessionJournalReplayWorkspaceContent]
    public var replayedEventCount: Int
    public var droppedEventCount: Int

    public init(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID,
        workspaceContentStates: [ConductorSessionJournalReplayWorkspaceContent],
        replayedEventCount: Int,
        droppedEventCount: Int
    ) {
        self.workspaces = workspaces
        self.selectedWorkspaceID = selectedWorkspaceID
        self.workspaceContentStates = workspaceContentStates
        self.replayedEventCount = replayedEventCount
        self.droppedEventCount = droppedEventCount
    }
}

public final class ConductorSessionJournal: @unchecked Sendable {
    public static let fileName = "session-journal.ndjson"
    public static let previousFileName = "session-journal.previous.ndjson"

    private let fileManager: FileManager
    private let fileURL: URL
    private let previousFileURL: URL
    private let isEnabled: Bool
    private let maxFileSizeBytes: Int
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        isEnabled: Bool = true,
        maxFileSizeBytes: Int = 2_000_000
    ) {
        self.fileManager = fileManager
        self.isEnabled = isEnabled
        self.maxFileSizeBytes = maxFileSizeBytes
        let baseURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileURL = baseURL.appendingPathComponent(Self.fileName)
        self.previousFileURL = baseURL.appendingPathComponent(Self.previousFileName)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public var url: URL {
        fileURL
    }

    public func append(_ event: ConductorSessionJournalEvent) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try rotateIfNeeded()
            var data = try encoder.encode(event)
            data.append(0x0A)
            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: [.atomic])
            }
        } catch {
            // Journaling must never block the app's normal snapshot path.
        }
    }

    public func recentEntries(limit: Int) -> [ConductorSessionJournalEvent] {
        guard isEnabled, limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(limit).compactMap { line in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(ConductorSessionJournalEvent.self, from: lineData)
        }
    }

    public func summary(limit: Int = 1_000) -> ConductorSessionJournalSummary {
        let entries = recentEntries(limit: limit)
        let size = ((try? fileManager.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber)?.intValue ?? 0
        return ConductorSessionJournalSummary(
            entryCount: entries.count,
            latestEvent: entries.last,
            fileSizeBytes: size
        )
    }

    public func replay(limit: Int = 5_000) -> ConductorSessionJournalReplayResult? {
        Self.replay(recentEntries(limit: limit))
    }

    public static func replay(_ entries: [ConductorSessionJournalEvent]) -> ConductorSessionJournalReplayResult? {
        var replayer = ConductorSessionJournalReplayer()
        for event in entries.sorted(by: { $0.timestamp < $1.timestamp }) {
            replayer.apply(event)
        }
        return replayer.result()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
        try? fileManager.removeItem(at: previousFileURL)
    }

    private func rotateIfNeeded() throws {
        guard fileManager.fileExists(atPath: fileURL.path),
              let size = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size]) as? NSNumber,
              size.intValue >= maxFileSizeBytes else {
            return
        }
        try? fileManager.removeItem(at: previousFileURL)
        try fileManager.moveItem(at: fileURL, to: previousFileURL)
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["CONDUCTOR_STATE_PATH"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: overridePath)
                .deletingLastPathComponent()
        }
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("Conductor", isDirectory: true)
    }
}

private struct ConductorSessionJournalReplayer {
    private struct WorkspaceDraft {
        var id: WorkspaceID
        var title: String
        var panes: [PaneID: PaneState]
        var focusedPaneID: PaneID
        var webTabs: [WorkspaceWebTabState] = []
        var fileTabs: [ConductorSessionJournalReplayFileTab] = []
        var selectedContentTabID: WorkspaceContentSelection?
    }

    private var workspaces: [WorkspaceDraft] = []
    private var selectedWorkspaceID: WorkspaceID?
    private var replayedEventCount = 0
    private var droppedEventCount = 0

    mutating func apply(_ event: ConductorSessionJournalEvent) {
        switch event.kind {
        case .snapshotSaved:
            replayedEventCount += 1
        case .workspaceCreated:
            guard let workspaceID = event.workspaceID ?? event.selectedWorkspaceID else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(
                workspaceID,
                title: detail("title", in: event) ?? "Recovered Workspace",
                paneID: event.paneID,
                terminalID: event.terminalID,
                workingDirectory: detail("workingDirectory", in: event)
            )
            selectedWorkspaceID = workspaceID
            replayedEventCount += 1
        case .workspaceRenamed:
            guard let workspaceID = event.workspaceID, let index = index(of: workspaceID) else {
                droppedEventCount += 1
                return
            }
            workspaces[index].title = detail("title", in: event) ?? workspaces[index].title
            replayedEventCount += 1
        case .workspaceDuplicated:
            guard let workspaceID = event.workspaceID else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(workspaceID, title: detail("title", in: event) ?? "Recovered Copy")
            selectedWorkspaceID = workspaceID
            replayedEventCount += 1
        case .workspaceClosed:
            guard let workspaceID = event.workspaceID,
                  workspaces.count > 1,
                  let index = index(of: workspaceID) else {
                droppedEventCount += 1
                return
            }
            workspaces.remove(at: index)
            if selectedWorkspaceID == workspaceID {
                selectedWorkspaceID = workspaces.last?.id
            }
            replayedEventCount += 1
        case .workspaceSelected:
            guard let workspaceID = event.workspaceID ?? event.selectedWorkspaceID else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(workspaceID)
            selectedWorkspaceID = workspaceID
            replayedEventCount += 1
        case .terminalCreated, .terminalDuplicated:
            guard let workspaceID = event.workspaceID ?? event.selectedWorkspaceID,
                  let terminalID = event.terminalID else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(workspaceID)
            addTerminal(
                terminalID,
                paneID: event.paneID,
                workspaceID: workspaceID,
                title: detail("title", in: event) ?? "zsh",
                workingDirectory: detail("workingDirectory", in: event),
                createsPane: detail("source", in: event) == "split"
            )
            selectedWorkspaceID = workspaceID
            replayedEventCount += 1
        case .terminalClosed:
            guard let workspaceID = event.workspaceID ?? selectedWorkspaceID,
                  let terminalID = event.terminalID,
                  removeTerminal(terminalID, workspaceID: workspaceID) else {
                droppedEventCount += 1
                return
            }
            replayedEventCount += 1
        case .paneClosed:
            guard let workspaceID = event.workspaceID ?? selectedWorkspaceID,
                  let paneID = event.paneID,
                  removePane(paneID, workspaceID: workspaceID) else {
                droppedEventCount += 1
                return
            }
            replayedEventCount += 1
        case .browserTabOpened:
            guard let workspaceID = event.workspaceID ?? event.selectedWorkspaceID,
                  let webTabID = event.webTabID else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(workspaceID)
            upsertWebTab(
                webTabID,
                workspaceID: workspaceID,
                input: detail("input", in: event),
                urlString: detail("url", in: event),
                title: detail("title", in: event)
            )
            selectedWorkspaceID = workspaceID
            replayedEventCount += 1
        case .browserTabNavigated:
            guard let workspaceID = event.workspaceID ?? event.selectedWorkspaceID,
                  let webTabID = event.webTabID else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(workspaceID)
            upsertWebTab(
                webTabID,
                workspaceID: workspaceID,
                input: detail("input", in: event),
                urlString: detail("url", in: event),
                title: detail("title", in: event)
            )
            replayedEventCount += 1
        case .browserTabClosed:
            guard let workspaceID = event.workspaceID ?? selectedWorkspaceID,
                  let webTabID = event.webTabID,
                  let workspaceIndex = index(of: workspaceID) else {
                droppedEventCount += 1
                return
            }
            workspaces[workspaceIndex].webTabs.removeAll { $0.id == webTabID }
            if case .web(webTabID) = workspaces[workspaceIndex].selectedContentTabID {
                workspaces[workspaceIndex].selectedContentTabID = fallbackSelection(in: workspaces[workspaceIndex])
            }
            replayedEventCount += 1
        case .fileTabOpened:
            guard let workspaceID = event.workspaceID ?? event.selectedWorkspaceID,
                  let path = detail("path", in: event),
                  !path.isEmpty else {
                droppedEventCount += 1
                return
            }
            ensureWorkspace(workspaceID)
            addFileTab(path: path, rootPath: detail("root", in: event), workspaceID: workspaceID)
            selectedWorkspaceID = workspaceID
            replayedEventCount += 1
        case .fileTabClosed:
            guard let workspaceID = event.workspaceID ?? selectedWorkspaceID,
                  let path = detail("path", in: event),
                  let workspaceIndex = index(of: workspaceID) else {
                droppedEventCount += 1
                return
            }
            workspaces[workspaceIndex].fileTabs.removeAll { $0.filePath == path }
            if case .file(path) = workspaces[workspaceIndex].selectedContentTabID {
                workspaces[workspaceIndex].selectedContentTabID = fallbackSelection(in: workspaces[workspaceIndex])
            }
            replayedEventCount += 1
        }
    }

    func result() -> ConductorSessionJournalReplayResult? {
        let validWorkspaces = workspaces.compactMap(makeWorkspace)
        guard !validWorkspaces.isEmpty else { return nil }
        let validWorkspaceIDs = Set(validWorkspaces.map(\.id))
        let selected = selectedWorkspaceID.flatMap { id in
            validWorkspaceIDs.contains(id) ? id : nil
        } ?? validWorkspaces.last!.id
        let contentStates = workspaces.compactMap { draft -> ConductorSessionJournalReplayWorkspaceContent? in
            guard validWorkspaceIDs.contains(draft.id) else { return nil }
            let terminalIDs = terminalIDs(in: draft)
            let selection = sanitizedSelection(
                draft.selectedContentTabID,
                webTabs: draft.webTabs,
                fileTabs: draft.fileTabs,
                terminalIDs: terminalIDs
            )
            guard !draft.webTabs.isEmpty || !draft.fileTabs.isEmpty || selection != nil else { return nil }
            return ConductorSessionJournalReplayWorkspaceContent(
                workspaceID: draft.id,
                webTabs: draft.webTabs,
                fileTabs: draft.fileTabs,
                selectedContentTabID: selection
            )
        }
        return ConductorSessionJournalReplayResult(
            workspaces: validWorkspaces,
            selectedWorkspaceID: selected,
            workspaceContentStates: contentStates,
            replayedEventCount: replayedEventCount,
            droppedEventCount: droppedEventCount
        )
    }

    private func makeWorkspace(_ draft: WorkspaceDraft) -> WorkspaceState? {
        guard !draft.panes.isEmpty else { return nil }
        let leaves = draft.panes.keys.sorted { $0.description < $1.description }
        guard let root = SplitNode.line(leaves: leaves, axis: .horizontal) else { return nil }
        return WorkspaceState(
            id: draft.id,
            title: draft.title,
            root: root,
            panes: draft.panes,
            focusedPaneID: draft.panes[draft.focusedPaneID] == nil ? leaves[0] : draft.focusedPaneID
        )
    }

    private mutating func ensureWorkspace(
        _ workspaceID: WorkspaceID,
        title: String = "Recovered Workspace",
        paneID: PaneID? = nil,
        terminalID: TerminalID? = nil,
        workingDirectory: String? = nil
    ) {
        guard index(of: workspaceID) == nil else { return }
        let resolvedPaneID = paneID ?? PaneID()
        let tab = TerminalTabState(
            id: terminalID ?? TerminalID(),
            title: "zsh",
            workingDirectory: clean(workingDirectory)
        )
        let pane = PaneState(id: resolvedPaneID, tabs: [tab])
        workspaces.append(WorkspaceDraft(
            id: workspaceID,
            title: clean(title) ?? "Recovered Workspace",
            panes: [resolvedPaneID: pane],
            focusedPaneID: resolvedPaneID,
            selectedContentTabID: .terminal(tab.id)
        ))
    }

    private mutating func addTerminal(
        _ terminalID: TerminalID,
        paneID: PaneID?,
        workspaceID: WorkspaceID,
        title: String,
        workingDirectory: String?,
        createsPane: Bool
    ) {
        guard let workspaceIndex = index(of: workspaceID) else { return }
        if containsTerminal(terminalID, in: workspaces[workspaceIndex]) {
            return
        }
        let tab = TerminalTabState(
            id: terminalID,
            title: clean(title) ?? "zsh",
            workingDirectory: clean(workingDirectory)
        )
        let resolvedPaneID = paneID ?? workspaces[workspaceIndex].focusedPaneID
        if createsPane || workspaces[workspaceIndex].panes[resolvedPaneID] == nil {
            var pane = PaneState(id: resolvedPaneID, tabs: [tab])
            pane.selectedTabID = terminalID
            workspaces[workspaceIndex].panes[resolvedPaneID] = pane
        } else {
            var pane = workspaces[workspaceIndex].panes[resolvedPaneID]!
            pane.tabs.append(tab)
            pane.selectedTabID = terminalID
            workspaces[workspaceIndex].panes[resolvedPaneID] = pane
        }
        workspaces[workspaceIndex].focusedPaneID = resolvedPaneID
        workspaces[workspaceIndex].selectedContentTabID = .terminal(terminalID)
    }

    private mutating func removeTerminal(_ terminalID: TerminalID, workspaceID: WorkspaceID) -> Bool {
        guard let workspaceIndex = index(of: workspaceID) else { return false }
        for paneID in workspaces[workspaceIndex].panes.keys.sorted(by: { $0.description < $1.description }) {
            guard var pane = workspaces[workspaceIndex].panes[paneID],
                  let tabIndex = pane.tabs.firstIndex(where: { $0.id == terminalID }) else {
                continue
            }
            guard pane.tabs.count > 1 || workspaces[workspaceIndex].panes.count > 1 else {
                return false
            }
            pane.tabs.remove(at: tabIndex)
            if pane.tabs.isEmpty {
                workspaces[workspaceIndex].panes.removeValue(forKey: paneID)
                if workspaces[workspaceIndex].focusedPaneID == paneID {
                    workspaces[workspaceIndex].focusedPaneID = workspaces[workspaceIndex].panes.keys.sorted { $0.description < $1.description }[0]
                }
            } else {
                pane.selectedTabID = pane.tabs[min(tabIndex, pane.tabs.count - 1)].id
                workspaces[workspaceIndex].panes[paneID] = pane
            }
            if case .terminal(terminalID) = workspaces[workspaceIndex].selectedContentTabID {
                workspaces[workspaceIndex].selectedContentTabID = fallbackSelection(in: workspaces[workspaceIndex])
            }
            return true
        }
        return false
    }

    private mutating func removePane(_ paneID: PaneID, workspaceID: WorkspaceID) -> Bool {
        guard let workspaceIndex = index(of: workspaceID),
              workspaces[workspaceIndex].panes.count > 1,
              workspaces[workspaceIndex].panes[paneID] != nil else {
            return false
        }
        workspaces[workspaceIndex].panes.removeValue(forKey: paneID)
        if workspaces[workspaceIndex].focusedPaneID == paneID {
            workspaces[workspaceIndex].focusedPaneID = workspaces[workspaceIndex].panes.keys.sorted { $0.description < $1.description }[0]
        }
        workspaces[workspaceIndex].selectedContentTabID = fallbackSelection(in: workspaces[workspaceIndex])
        return true
    }

    private mutating func upsertWebTab(
        _ webTabID: WebTabID,
        workspaceID: WorkspaceID,
        input: String?,
        urlString: String?,
        title: String?
    ) {
        guard let workspaceIndex = index(of: workspaceID) else { return }
        let url = clean(urlString).flatMap(URL.init(string:)) ?? clean(input).flatMap(URL.init(string:))
        let pendingAddress = clean(input) ?? url?.absoluteString ?? ""
        if let tabIndex = workspaces[workspaceIndex].webTabs.firstIndex(where: { $0.id == webTabID }) {
            workspaces[workspaceIndex].webTabs[tabIndex].url = url ?? workspaces[workspaceIndex].webTabs[tabIndex].url
            workspaces[workspaceIndex].webTabs[tabIndex].pendingAddress = pendingAddress
            workspaces[workspaceIndex].webTabs[tabIndex].title = clean(title) ?? workspaces[workspaceIndex].webTabs[tabIndex].title
        } else {
            workspaces[workspaceIndex].webTabs.append(WorkspaceWebTabState(
                id: webTabID,
                url: url,
                pendingAddress: pendingAddress,
                title: clean(title)
            ))
        }
        workspaces[workspaceIndex].selectedContentTabID = .web(webTabID)
    }

    private mutating func addFileTab(path: String, rootPath: String?, workspaceID: WorkspaceID) {
        guard let workspaceIndex = index(of: workspaceID) else { return }
        let resolvedRoot = clean(rootPath) ?? URL(fileURLWithPath: path).deletingLastPathComponent().path
        if !workspaces[workspaceIndex].fileTabs.contains(where: { $0.filePath == path }) {
            workspaces[workspaceIndex].fileTabs.append(ConductorSessionJournalReplayFileTab(
                filePath: path,
                rootPath: resolvedRoot
            ))
        }
        workspaces[workspaceIndex].selectedContentTabID = .file(path)
    }

    private func index(of workspaceID: WorkspaceID) -> Int? {
        workspaces.firstIndex { $0.id == workspaceID }
    }

    private func containsTerminal(_ terminalID: TerminalID, in workspace: WorkspaceDraft) -> Bool {
        workspace.panes.values.contains { pane in
            pane.tabs.contains { $0.id == terminalID }
        }
    }

    private func terminalIDs(in workspace: WorkspaceDraft) -> Set<TerminalID> {
        Set(workspace.panes.values.flatMap { pane in pane.tabs.map(\.id) })
    }

    private func fallbackSelection(in workspace: WorkspaceDraft) -> WorkspaceContentSelection? {
        if let webTab = workspace.webTabs.last {
            return .web(webTab.id)
        }
        if let fileTab = workspace.fileTabs.last {
            return .file(fileTab.filePath)
        }
        return (workspace.panes[workspace.focusedPaneID]?.selectedTabID).map { .terminal($0) }
    }

    private func sanitizedSelection(
        _ selection: WorkspaceContentSelection?,
        webTabs: [WorkspaceWebTabState],
        fileTabs: [ConductorSessionJournalReplayFileTab],
        terminalIDs: Set<TerminalID>
    ) -> WorkspaceContentSelection? {
        switch selection {
        case .web(let webTabID):
            webTabs.contains { $0.id == webTabID } ? selection : nil
        case .file(let fileID):
            fileTabs.contains { $0.filePath == fileID } ? selection : nil
        case .terminal(let terminalID):
            terminalIDs.contains(terminalID) ? selection : nil
        case nil:
            nil
        }
    }

    private func detail(_ key: String, in event: ConductorSessionJournalEvent) -> String? {
        clean(event.details[key])
    }

    private func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
