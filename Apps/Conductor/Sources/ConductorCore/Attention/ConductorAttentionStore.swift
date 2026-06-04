import Foundation

public struct ConductorAttentionAppendResult: Equatable, Sendable {
    public let event: ConductorAttentionEvent
    public let coalesced: Bool
    public let suppressedCount: Int

    public init(event: ConductorAttentionEvent, coalesced: Bool, suppressedCount: Int) {
        self.event = event
        self.coalesced = coalesced
        self.suppressedCount = suppressedCount
    }
}

public final class ConductorAttentionStore: @unchecked Sendable {
    public static let fileName = "attention-events.json"

    private let fileManager: FileManager
    private let fileURL: URL
    private let isEnabled: Bool
    private let maxEvents: Int
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        isEnabled: Bool = true,
        maxEvents: Int = 250
    ) {
        self.fileManager = fileManager
        self.isEnabled = isEnabled
        self.maxEvents = max(1, maxEvents)
        let baseURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.fileURL = baseURL.appendingPathComponent(Self.fileName)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public var url: URL {
        fileURL
    }

    @discardableResult
    public func append(_ event: ConductorAttentionEvent) -> ConductorAttentionEvent {
        guard isEnabled else { return event }
        lock.lock()
        defer { lock.unlock() }
        var events = loadEventsOnQueue()
        events.append(event)
        events = Array(events.sorted { $0.createdAt < $1.createdAt }.suffix(maxEvents))
        saveEventsOnQueue(events)
        return event
    }

    @discardableResult
    public func appendCoalescing(
        _ event: ConductorAttentionEvent,
        window: TimeInterval
    ) -> ConductorAttentionAppendResult {
        guard isEnabled else {
            return ConductorAttentionAppendResult(event: event, coalesced: false, suppressedCount: 0)
        }
        guard window > 0, event.terminalID != nil else {
            let appended = append(event)
            return ConductorAttentionAppendResult(event: appended, coalesced: false, suppressedCount: 0)
        }
        lock.lock()
        defer { lock.unlock() }
        var events = loadEventsOnQueue()
        if let index = events.indices.reversed().first(where: { candidateIndex in
            let candidate = events[candidateIndex]
            let age = event.createdAt.timeIntervalSince(candidate.createdAt)
            return candidate.isUnread &&
                candidate.kind == event.kind &&
                candidate.source == event.source &&
                candidate.terminalID == event.terminalID &&
                age >= 0 &&
                age <= window
        }) {
            var existing = events[index]
            let nextSuppressedCount = (Int(existing.details["suppressedCount"] ?? "") ?? 0) + 1
            existing.details["suppressedCount"] = String(nextSuppressedCount)
            existing.details["lastSuppressedAt"] = ISO8601DateFormatter().string(from: event.createdAt)
            if !event.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.body = event.body
            }
            events[index] = existing
            saveEventsOnQueue(events)
            return ConductorAttentionAppendResult(event: existing, coalesced: true, suppressedCount: nextSuppressedCount)
        }

        events.append(event)
        events = Array(events.sorted { $0.createdAt < $1.createdAt }.suffix(maxEvents))
        saveEventsOnQueue(events)
        return ConductorAttentionAppendResult(event: event, coalesced: false, suppressedCount: 0)
    }

    public func events(limit: Int? = nil, includeRead: Bool = true) -> [ConductorAttentionEvent] {
        guard isEnabled else { return [] }
        lock.lock()
        defer { lock.unlock() }
        var events = loadEventsOnQueue().sorted { $0.createdAt > $1.createdAt }
        if !includeRead {
            events = events.filter(\.isUnread)
        }
        if let limit {
            events = Array(events.prefix(max(0, limit)))
        }
        return events
    }

    @discardableResult
    public func markRead(id: UUID, at date: Date = Date()) -> ConductorAttentionEvent? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        var events = loadEventsOnQueue()
        guard let index = events.firstIndex(where: { $0.id == id }) else { return nil }
        events[index].readAt = events[index].readAt ?? date
        saveEventsOnQueue(events)
        return events[index]
    }

    @discardableResult
    public func markRead(ids: Set<UUID>, at date: Date = Date()) -> Int {
        guard isEnabled, !ids.isEmpty else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        var events = loadEventsOnQueue()
        var changed = 0
        for index in events.indices where ids.contains(events[index].id) && events[index].readAt == nil {
            events[index].readAt = date
            changed += 1
        }
        if changed > 0 {
            saveEventsOnQueue(events)
        }
        return changed
    }

    @discardableResult
    public func clear(id: UUID? = nil) -> Int {
        guard isEnabled else { return 0 }
        lock.lock()
        defer { lock.unlock() }
        var events = loadEventsOnQueue()
        let countBefore = events.count
        if let id {
            events.removeAll { $0.id == id }
        } else {
            events.removeAll()
        }
        saveEventsOnQueue(events)
        return countBefore - events.count
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
    }

    private func loadEventsOnQueue() -> [ConductorAttentionEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([ConductorAttentionEvent].self, from: data)) ?? []
    }

    private func saveEventsOnQueue(_ events: [ConductorAttentionEvent]) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Attention state must not block terminal or notification delivery.
        }
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
