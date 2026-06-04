import Foundation
import Testing
@testable import ConductorCore

@Test func attentionStorePersistsAndListsNewestFirst() throws {
    let directoryURL = try temporaryAttentionDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let workspaceID = WorkspaceID()
    let terminalID = TerminalID()
    let store = ConductorAttentionStore(directoryURL: directoryURL, isEnabled: true)
    let first = ConductorAttentionEvent(
        createdAt: Date(timeIntervalSince1970: 10),
        kind: .manual,
        title: "First",
        workspaceID: workspaceID,
        terminalID: terminalID,
        source: "test"
    )
    let second = ConductorAttentionEvent(
        createdAt: Date(timeIntervalSince1970: 20),
        kind: .agentReply,
        title: "Second",
        source: "test"
    )

    store.append(first)
    store.append(second)

    let reloaded = ConductorAttentionStore(directoryURL: directoryURL, isEnabled: true)
    let events = reloaded.events()
    #expect(events.map(\.title) == ["Second", "First"])
    #expect(events[1].workspaceID == workspaceID)
    #expect(events[1].terminalID == terminalID)
}

@Test func attentionStoreMarksReadAndClears() throws {
    let directoryURL = try temporaryAttentionDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let store = ConductorAttentionStore(directoryURL: directoryURL, isEnabled: true)
    let event = store.append(ConductorAttentionEvent(kind: .manual, title: "Ping", source: "test"))

    let marked = store.markRead(id: event.id)
    #expect(marked?.readAt != nil)
    #expect(store.events(includeRead: false).isEmpty)

    let cleared = store.clear(id: event.id)
    #expect(cleared == 1)
    #expect(store.events().isEmpty)
}

@Test func attentionStoreMarksMultipleEventsRead() throws {
    let directoryURL = try temporaryAttentionDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let store = ConductorAttentionStore(directoryURL: directoryURL, isEnabled: true)
    let first = store.append(ConductorAttentionEvent(kind: .manual, title: "One", source: "test"))
    let second = store.append(ConductorAttentionEvent(kind: .manual, title: "Two", source: "test"))
    let third = store.append(ConductorAttentionEvent(kind: .manual, title: "Three", source: "test"))

    let changed = store.markRead(ids: [first.id, third.id])

    #expect(changed == 2)
    #expect(store.events(includeRead: false).map(\.id) == [second.id])
}

@Test func attentionStoreLimitsOldEvents() throws {
    let directoryURL = try temporaryAttentionDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let store = ConductorAttentionStore(directoryURL: directoryURL, isEnabled: true, maxEvents: 2)
    store.append(ConductorAttentionEvent(createdAt: Date(timeIntervalSince1970: 1), kind: .manual, title: "One", source: "test"))
    store.append(ConductorAttentionEvent(createdAt: Date(timeIntervalSince1970: 2), kind: .manual, title: "Two", source: "test"))
    store.append(ConductorAttentionEvent(createdAt: Date(timeIntervalSince1970: 3), kind: .manual, title: "Three", source: "test"))

    #expect(store.events().map(\.title) == ["Three", "Two"])
}

@Test func attentionStoreCoalescesUnreadTerminalEventsWithinWindow() throws {
    let directoryURL = try temporaryAttentionDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let workspaceID = WorkspaceID()
    let terminalID = TerminalID()
    let store = ConductorAttentionStore(directoryURL: directoryURL, isEnabled: true)
    let first = ConductorAttentionEvent(
        createdAt: Date(timeIntervalSince1970: 10),
        kind: .agentReply,
        title: "Agent replied",
        body: "First body",
        workspaceID: workspaceID,
        terminalID: terminalID,
        source: "agent-hook"
    )
    let duplicate = ConductorAttentionEvent(
        createdAt: Date(timeIntervalSince1970: 12),
        kind: .agentReply,
        title: "Agent replied again",
        body: "Latest body",
        workspaceID: workspaceID,
        terminalID: terminalID,
        source: "agent-hook"
    )
    let outsideWindow = ConductorAttentionEvent(
        createdAt: Date(timeIntervalSince1970: 30),
        kind: .agentReply,
        title: "Agent replied later",
        body: "Later body",
        workspaceID: workspaceID,
        terminalID: terminalID,
        source: "agent-hook"
    )

    let firstResult = store.appendCoalescing(first, window: 8)
    let duplicateResult = store.appendCoalescing(duplicate, window: 8)
    let outsideResult = store.appendCoalescing(outsideWindow, window: 8)
    let events = store.events()

    #expect(firstResult.coalesced == false)
    #expect(firstResult.suppressedCount == 0)
    #expect(duplicateResult.coalesced)
    #expect(duplicateResult.event.id == first.id)
    #expect(duplicateResult.event.body == "Latest body")
    #expect(duplicateResult.suppressedCount == 1)
    #expect(duplicateResult.event.details["suppressedCount"] == "1")
    #expect(duplicateResult.event.details["lastSuppressedAt"] != nil)
    #expect(outsideResult.coalesced == false)
    #expect(events.map(\.id) == [outsideWindow.id, first.id])
    #expect(events.first?.details["suppressedCount"] == nil)
    #expect(events.last?.details["suppressedCount"] == "1")
}

private func temporaryAttentionDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("conductor-attention-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
