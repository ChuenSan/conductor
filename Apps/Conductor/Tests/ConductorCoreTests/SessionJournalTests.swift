import Foundation
import Testing
@testable import ConductorCore

@Test func sessionJournalAppendsAndReadsRecentEvents() throws {
    let directoryURL = try temporaryJournalDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let workspaceID = WorkspaceID()
    let terminalID = TerminalID()
    let journal = ConductorSessionJournal(directoryURL: directoryURL, isEnabled: true)

    journal.append(
        ConductorSessionJournalEvent(
            kind: .workspaceCreated,
            selectedWorkspaceID: workspaceID,
            workspaceID: workspaceID,
            terminalID: terminalID,
            workspaceCount: 1,
            terminalCount: 1,
            details: ["title": "Release"]
        )
    )

    let entries = journal.recentEntries(limit: 5)
    #expect(entries.count == 1)
    #expect(entries[0].kind == .workspaceCreated)
    #expect(entries[0].workspaceID == workspaceID)
    #expect(entries[0].terminalID == terminalID)
    #expect(entries[0].details["title"] == "Release")

    let rawText = try String(contentsOf: directoryURL.appendingPathComponent(ConductorSessionJournal.fileName), encoding: .utf8)
    #expect(rawText.contains("\"workspaceID\":\"\(workspaceID.description)\""))
    #expect(rawText.contains("\"terminalID\":\"\(terminalID.description)\""))
}

@Test func sessionJournalRotatesOversizedFiles() throws {
    let directoryURL = try temporaryJournalDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let journal = ConductorSessionJournal(
        directoryURL: directoryURL,
        isEnabled: true,
        maxFileSizeBytes: 1
    )
    journal.append(ConductorSessionJournalEvent(kind: .workspaceCreated))
    journal.append(ConductorSessionJournalEvent(kind: .snapshotSaved))

    let current = journal.recentEntries(limit: 5)
    #expect(current.count == 1)
    #expect(current[0].kind == .snapshotSaved)
    #expect(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(ConductorSessionJournal.previousFileName).path))
}

@Test func sessionJournalReadsLegacyRawValueIDs() throws {
    let directoryURL = try temporaryJournalDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let workspaceID = UUID()
    let terminalID = UUID()
    let legacyLine = """
    {"details":{},"fileTabCount":0,"id":"\(UUID().uuidString)","kind":"terminalCreated","selectedWorkspaceID":{"rawValue":"\(workspaceID.uuidString)"},"terminalCount":1,"terminalID":{"rawValue":"\(terminalID.uuidString)"},"timestamp":"2026-06-03T04:03:20Z","webTabCount":0,"workspaceCount":1,"workspaceID":{"rawValue":"\(workspaceID.uuidString)"}}
    """
    try legacyLine
        .appending("\n")
        .write(
            to: directoryURL.appendingPathComponent(ConductorSessionJournal.fileName),
            atomically: true,
            encoding: .utf8
        )

    let journal = ConductorSessionJournal(directoryURL: directoryURL, isEnabled: true)
    let entries = journal.recentEntries(limit: 1)
    #expect(entries.count == 1)
    if let entry = entries.first {
        #expect(entry.kind == .terminalCreated)
        #expect(entry.workspaceID?.rawValue == workspaceID)
        #expect(entry.terminalID?.rawValue == terminalID)
    }
}

@Test func sessionJournalReplaysWorkspaceSkeletonFromEvents() throws {
    let firstWorkspaceID = WorkspaceID()
    let secondWorkspaceID = WorkspaceID()
    let splitPaneID = PaneID()
    let splitTerminalID = TerminalID()
    let webTabID = WebTabID()
    let filePath = "/tmp/conductor-replay/main.swift"
    let rootPath = "/tmp/conductor-replay"
    let openedAt = Date(timeIntervalSince1970: 10)

    let replay = ConductorSessionJournal.replay([
        ConductorSessionJournalEvent(
            timestamp: openedAt,
            kind: .workspaceCreated,
            selectedWorkspaceID: firstWorkspaceID,
            workspaceID: firstWorkspaceID,
            details: ["title": "Release"]
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(1),
            kind: .terminalCreated,
            selectedWorkspaceID: firstWorkspaceID,
            workspaceID: firstWorkspaceID,
            paneID: splitPaneID,
            terminalID: splitTerminalID,
            details: [
                "source": "split",
                "direction": "right",
                "workingDirectory": rootPath
            ]
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(2),
            kind: .browserTabOpened,
            selectedWorkspaceID: firstWorkspaceID,
            workspaceID: firstWorkspaceID,
            webTabID: webTabID,
            details: [
                "input": "https://example.com",
                "url": "https://example.com"
            ]
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(3),
            kind: .browserTabNavigated,
            selectedWorkspaceID: firstWorkspaceID,
            workspaceID: firstWorkspaceID,
            webTabID: webTabID,
            details: [
                "input": "https://example.com/docs",
                "url": "https://example.com/docs"
            ]
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(4),
            kind: .fileTabOpened,
            selectedWorkspaceID: firstWorkspaceID,
            workspaceID: firstWorkspaceID,
            details: [
                "path": filePath,
                "root": rootPath
            ]
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(5),
            kind: .workspaceCreated,
            selectedWorkspaceID: secondWorkspaceID,
            workspaceID: secondWorkspaceID,
            details: ["title": "Follow-up"]
        )
    ])

    #expect(replay != nil)
    guard let replay else { return }
    #expect(replay.workspaces.count == 2)
    #expect(replay.selectedWorkspaceID == secondWorkspaceID)
    #expect(replay.replayedEventCount == 6)
    #expect(replay.droppedEventCount == 0)

    let first = try #require(replay.workspaces.first { $0.id == firstWorkspaceID })
    #expect(first.title == "Release")
    #expect(first.panes.count == 2)
    #expect(first.panes[splitPaneID]?.selectedTabID == splitTerminalID)
    #expect(first.panes[splitPaneID]?.selectedTab?.workingDirectory == rootPath)

    let firstContent = try #require(replay.workspaceContentStates.first { $0.workspaceID == firstWorkspaceID })
    #expect(firstContent.webTabs.count == 1)
    #expect(firstContent.webTabs[0].id == webTabID)
    #expect(firstContent.webTabs[0].url?.absoluteString == "https://example.com/docs")
    #expect(firstContent.fileTabs == [
        ConductorSessionJournalReplayFileTab(filePath: filePath, rootPath: rootPath)
    ])
    #expect(firstContent.selectedContentTabID == .file(filePath))
}

@Test func sessionJournalReplayAppliesCloseEvents() throws {
    let workspaceID = WorkspaceID()
    let terminalID = TerminalID()
    let webTabID = WebTabID()
    let openedAt = Date(timeIntervalSince1970: 20)

    let replay = ConductorSessionJournal.replay([
        ConductorSessionJournalEvent(
            timestamp: openedAt,
            kind: .workspaceCreated,
            selectedWorkspaceID: workspaceID,
            workspaceID: workspaceID
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(1),
            kind: .terminalCreated,
            selectedWorkspaceID: workspaceID,
            workspaceID: workspaceID,
            terminalID: terminalID
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(2),
            kind: .browserTabOpened,
            selectedWorkspaceID: workspaceID,
            workspaceID: workspaceID,
            webTabID: webTabID,
            details: ["url": "https://example.com"]
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(3),
            kind: .browserTabClosed,
            selectedWorkspaceID: workspaceID,
            workspaceID: workspaceID,
            webTabID: webTabID
        ),
        ConductorSessionJournalEvent(
            timestamp: openedAt.addingTimeInterval(4),
            kind: .terminalClosed,
            selectedWorkspaceID: workspaceID,
            workspaceID: workspaceID,
            terminalID: terminalID
        )
    ])

    #expect(replay != nil)
    guard let replay else { return }
    let workspace = try #require(replay.workspaces.first)
    #expect(workspace.panes.values.reduce(0) { $0 + $1.tabs.count } == 1)
    #expect(replay.workspaceContentStates.first?.webTabs.isEmpty ?? true)
    #expect(replay.replayedEventCount == 5)
    #expect(replay.droppedEventCount == 0)
}

private func temporaryJournalDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("conductor-session-journal-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
