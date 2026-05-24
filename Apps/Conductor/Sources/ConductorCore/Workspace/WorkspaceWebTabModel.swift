import Foundation

public struct WebTabID: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
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
        errorMessage: String? = nil
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
    public mutating func append(url: URL?, title: String? = nil, pendingAddress: String = "") -> WebTabID {
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
