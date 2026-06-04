import Foundation

public struct WorkspaceMetadataSnapshot: Equatable, Codable, Sendable {
    public struct Counts: Equatable, Codable, Sendable {
        public var paneCount: Int
        public var terminalCount: Int
        public var webTabCount: Int
        public var fileTabCount: Int

        public init(
            paneCount: Int,
            terminalCount: Int,
            webTabCount: Int,
            fileTabCount: Int
        ) {
            self.paneCount = paneCount
            self.terminalCount = terminalCount
            self.webTabCount = webTabCount
            self.fileTabCount = fileTabCount
        }
    }

    public struct TerminalSummary: Equatable, Codable, Sendable {
        public var id: TerminalID
        public var paneID: PaneID
        public var title: String
        public var workingDirectory: String?
        public var selected: Bool
        public var activeAgentTitle: String?
        public var activeAgentStartedAt: Date?
        public var agentState: String?
        public var agentUpdatedAt: Date?
        public var lastCommandExitCode: Int?
        public var lastCommandDurationNanoseconds: UInt64?
        public var lastCommandFinishedAt: Date?
        public var searchActive: Bool
        public var searchNeedle: String?
        public var searchTotal: Int?
        public var searchSelected: Int?
        public var readonly: Bool

        public init(
            id: TerminalID,
            paneID: PaneID,
            title: String,
            workingDirectory: String?,
            selected: Bool,
            activeAgentTitle: String?,
            activeAgentStartedAt: Date? = nil,
            agentState: String? = nil,
            agentUpdatedAt: Date? = nil,
            lastCommandExitCode: Int? = nil,
            lastCommandDurationNanoseconds: UInt64? = nil,
            lastCommandFinishedAt: Date? = nil,
            searchActive: Bool = false,
            searchNeedle: String? = nil,
            searchTotal: Int? = nil,
            searchSelected: Int? = nil,
            readonly: Bool
        ) {
            self.id = id
            self.paneID = paneID
            self.title = title
            self.workingDirectory = workingDirectory
            self.selected = selected
            self.activeAgentTitle = activeAgentTitle
            self.activeAgentStartedAt = activeAgentStartedAt
            self.agentState = agentState
            self.agentUpdatedAt = agentUpdatedAt
            self.lastCommandExitCode = lastCommandExitCode
            self.lastCommandDurationNanoseconds = lastCommandDurationNanoseconds
            self.lastCommandFinishedAt = lastCommandFinishedAt
            self.searchActive = searchActive
            self.searchNeedle = searchNeedle
            self.searchTotal = searchTotal
            self.searchSelected = searchSelected
            self.readonly = readonly
        }
    }

    public struct FileSummary: Equatable, Codable, Sendable {
        public var id: String
        public var title: String
        public var path: String
        public var rootPath: String
        public var selected: Bool
        public var dirty: Bool

        public init(
            id: String,
            title: String,
            path: String,
            rootPath: String,
            selected: Bool,
            dirty: Bool
        ) {
            self.id = id
            self.title = title
            self.path = path
            self.rootPath = rootPath
            self.selected = selected
            self.dirty = dirty
        }
    }

    public struct WebSummary: Equatable, Codable, Sendable {
        public var id: WebTabID
        public var title: String?
        public var url: String?
        public var pendingAddress: String
        public var selected: Bool
        public var loading: Bool
        public var errorMessage: String?

        public init(
            id: WebTabID,
            title: String?,
            url: String?,
            pendingAddress: String,
            selected: Bool,
            loading: Bool,
            errorMessage: String?
        ) {
            self.id = id
            self.title = title
            self.url = url
            self.pendingAddress = pendingAddress
            self.selected = selected
            self.loading = loading
            self.errorMessage = errorMessage
        }
    }

    public struct DevServerSummary: Equatable, Codable, Sendable {
        public var port: Int
        public var url: String
        public var label: String
        public var processID: Int?
        public var processName: String?
        public var workingDirectory: String?

        public init(
            port: Int,
            url: String,
            label: String,
            processID: Int? = nil,
            processName: String? = nil,
            workingDirectory: String? = nil
        ) {
            self.port = port
            self.url = url
            self.label = label
            self.processID = processID
            self.processName = processName
            self.workingDirectory = workingDirectory
        }
    }

    public var workspaceID: WorkspaceID
    public var title: String
    public var selected: Bool
    public var rootPath: String?
    public var rootSource: String
    public var projectName: String
    public var counts: Counts
    public var runningPorts: [Int]
    public var devServers: [DevServerSummary]
    public var portScanState: String
    public var activeAgentCount: Int
    public var unreadCount: Int
    public var terminals: [TerminalSummary]
    public var files: [FileSummary]
    public var webTabs: [WebSummary]
    public var health: String
    public var refreshedAt: Date

    public init(
        workspaceID: WorkspaceID,
        title: String,
        selected: Bool,
        rootPath: String?,
        rootSource: String,
        projectName: String,
        counts: Counts,
        runningPorts: [Int],
        devServers: [DevServerSummary] = [],
        portScanState: String,
        activeAgentCount: Int,
        unreadCount: Int,
        terminals: [TerminalSummary],
        files: [FileSummary],
        webTabs: [WebSummary],
        health: String,
        refreshedAt: Date = Date()
    ) {
        self.workspaceID = workspaceID
        self.title = title
        self.selected = selected
        self.rootPath = rootPath
        self.rootSource = rootSource
        self.projectName = projectName
        self.counts = counts
        self.runningPorts = runningPorts
        self.devServers = devServers
        self.portScanState = portScanState
        self.activeAgentCount = activeAgentCount
        self.unreadCount = unreadCount
        self.terminals = terminals
        self.files = files
        self.webTabs = webTabs
        self.health = health
        self.refreshedAt = refreshedAt
    }
}
