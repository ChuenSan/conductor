import Foundation

public struct WebTabID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct WorkspaceWebNavigationEntry: Codable, Equatable, Sendable {
    public var url: URL
    public var title: String?

    public init(url: URL, title: String? = nil) {
        self.url = url
        self.title = title
    }
}

public enum WorkspaceWebDownloadPhase: String, Codable, Equatable, Sendable {
    case requested
    case downloading
    case finished
    case failed
}

public struct WorkspaceWebDownloadState: Codable, Equatable, Sendable {
    public var phase: WorkspaceWebDownloadPhase
    public var filename: String
    public var destinationPath: String?
    public var errorMessage: String?
    public var updatedAt: Date

    public init(
        phase: WorkspaceWebDownloadPhase,
        filename: String,
        destinationPath: String? = nil,
        errorMessage: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.phase = phase
        self.filename = filename
        self.destinationPath = destinationPath
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }
}

public struct WorkspaceWebRuntimeEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case console
        case pageError
        case unhandledRejection
    }

    public var kind: Kind
    public var level: String
    public var message: String
    public var sourceURL: String?
    public var lineNumber: Int?
    public var columnNumber: Int?
    public var occurredAt: Date

    public init(
        kind: Kind,
        level: String,
        message: String,
        sourceURL: String? = nil,
        lineNumber: Int? = nil,
        columnNumber: Int? = nil,
        occurredAt: Date = Date()
    ) {
        self.kind = kind
        self.level = level
        self.message = String(message.prefix(1_000))
        self.sourceURL = sourceURL
        self.lineNumber = lineNumber
        self.columnNumber = columnNumber
        self.occurredAt = occurredAt
    }
}

public struct WorkspaceWebTabState: Identifiable, Codable, Equatable, Sendable {
    public var id: WebTabID
    public var url: URL?
    public var pendingAddress: String
    public var title: String?
    public var faviconURL: URL?
    public var isLoading: Bool
    public var estimatedProgress: Double
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var errorMessage: String?
    public var navigationEntries: [WorkspaceWebNavigationEntry]
    public var currentNavigationIndex: Int?
    public var scrollY: Double?
    public var downloadState: WorkspaceWebDownloadState?
    public var runtimeEvents: [WorkspaceWebRuntimeEvent]

    public init(
        id: WebTabID = WebTabID(),
        url: URL? = nil,
        pendingAddress: String = "",
        title: String? = nil,
        faviconURL: URL? = nil,
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        errorMessage: String? = nil,
        navigationEntries: [WorkspaceWebNavigationEntry] = [],
        currentNavigationIndex: Int? = nil,
        scrollY: Double? = nil,
        downloadState: WorkspaceWebDownloadState? = nil,
        runtimeEvents: [WorkspaceWebRuntimeEvent] = []
    ) {
        self.id = id
        self.url = url
        self.pendingAddress = pendingAddress
        self.title = title
        self.faviconURL = faviconURL
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.errorMessage = errorMessage
        self.navigationEntries = navigationEntries
        self.currentNavigationIndex = currentNavigationIndex
        self.scrollY = scrollY
        self.downloadState = downloadState
        self.runtimeEvents = runtimeEvents
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case pendingAddress
        case title
        case faviconURL
        case isLoading
        case estimatedProgress
        case canGoBack
        case canGoForward
        case errorMessage
        case navigationEntries
        case currentNavigationIndex
        case scrollY
        case downloadState
        case runtimeEvents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(WebTabID.self, forKey: .id)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        pendingAddress = try container.decodeIfPresent(String.self, forKey: .pendingAddress) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)
        faviconURL = try container.decodeIfPresent(URL.self, forKey: .faviconURL)
        isLoading = try container.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false
        estimatedProgress = try container.decodeIfPresent(Double.self, forKey: .estimatedProgress) ?? 0
        canGoBack = try container.decodeIfPresent(Bool.self, forKey: .canGoBack) ?? false
        canGoForward = try container.decodeIfPresent(Bool.self, forKey: .canGoForward) ?? false
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        navigationEntries = try container.decodeIfPresent([WorkspaceWebNavigationEntry].self, forKey: .navigationEntries) ?? []
        currentNavigationIndex = try container.decodeIfPresent(Int.self, forKey: .currentNavigationIndex)
        scrollY = try container.decodeIfPresent(Double.self, forKey: .scrollY)
        downloadState = try container.decodeIfPresent(WorkspaceWebDownloadState.self, forKey: .downloadState)
        runtimeEvents = try container.decodeIfPresent([WorkspaceWebRuntimeEvent].self, forKey: .runtimeEvents) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(pendingAddress, forKey: .pendingAddress)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(faviconURL, forKey: .faviconURL)
        try container.encode(isLoading, forKey: .isLoading)
        try container.encode(estimatedProgress, forKey: .estimatedProgress)
        try container.encode(canGoBack, forKey: .canGoBack)
        try container.encode(canGoForward, forKey: .canGoForward)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        if !navigationEntries.isEmpty {
            try container.encode(navigationEntries, forKey: .navigationEntries)
        }
        try container.encodeIfPresent(currentNavigationIndex, forKey: .currentNavigationIndex)
        try container.encodeIfPresent(scrollY, forKey: .scrollY)
        try container.encodeIfPresent(downloadState, forKey: .downloadState)
        if !runtimeEvents.isEmpty {
            try container.encode(runtimeEvents, forKey: .runtimeEvents)
        }
    }

    public var displayTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if let hostDisplay {
            return hostDisplay
        }
        if !pendingAddress.isEmpty {
            return pendingAddress
        }
        return "New Tab"
    }

    public var hostDisplay: String? {
        guard let url else { return nil }
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            return host
        }
        return url.scheme == "file" ? url.lastPathComponent : url.absoluteString
    }
}

public enum WorkspaceContentSelection: Equatable, Sendable {
    case terminal(TerminalID)
    case file(String)
    case web(WebTabID)
}

public struct WorkspaceWebTabCloseResult: Equatable, Sendable {
    public var closedTabID: WebTabID?
    public var nextContentSelection: WorkspaceContentSelection?

    public init(closedTabID: WebTabID?, nextContentSelection: WorkspaceContentSelection?) {
        self.closedTabID = closedTabID
        self.nextContentSelection = nextContentSelection
    }
}

public struct WorkspaceWebTabList: Equatable, Sendable {
    public private(set) var tabs: [WorkspaceWebTabState]
    public private(set) var selectedTabID: WebTabID?

    public init(tabs: [WorkspaceWebTabState] = [], selectedTabID: WebTabID? = nil) {
        self.tabs = tabs
        self.selectedTabID = tabs.contains(where: { $0.id == selectedTabID }) ? selectedTabID : tabs.last?.id
    }

    @discardableResult
    public mutating func append(
        url: URL?,
        title: String? = nil,
        pendingAddress: String = ""
    ) -> WebTabID {
        let tab = WorkspaceWebTabState(url: url, pendingAddress: pendingAddress, title: title)
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
    }

    public mutating func select(_ id: WebTabID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    public mutating func update(_ id: WebTabID, mutate: (inout WorkspaceWebTabState) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate(&tabs[index])
    }

    @discardableResult
    public mutating func close(
        _ id: WebTabID,
        fallbackFileTabID: String?,
        fallbackTerminalID: TerminalID?
    ) -> WorkspaceWebTabCloseResult {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return WorkspaceWebTabCloseResult(
                closedTabID: nil,
                nextContentSelection: fallbackSelection(fileID: fallbackFileTabID, terminalID: fallbackTerminalID)
            )
        }

        tabs.remove(at: index)
        guard selectedTabID == id else {
            return WorkspaceWebTabCloseResult(
                closedTabID: id,
                nextContentSelection: selectedTabID.map { .web($0) }
            )
        }

        if !tabs.isEmpty {
            let next = tabs[min(index, tabs.count - 1)].id
            selectedTabID = next
            return WorkspaceWebTabCloseResult(closedTabID: id, nextContentSelection: .web(next))
        }

        selectedTabID = nil
        return WorkspaceWebTabCloseResult(
            closedTabID: id,
            nextContentSelection: fallbackSelection(fileID: fallbackFileTabID, terminalID: fallbackTerminalID)
        )
    }

    private func fallbackSelection(fileID: String?, terminalID: TerminalID?) -> WorkspaceContentSelection? {
        if let fileID {
            return .file(fileID)
        }
        if let terminalID {
            return .terminal(terminalID)
        }
        return nil
    }
}
