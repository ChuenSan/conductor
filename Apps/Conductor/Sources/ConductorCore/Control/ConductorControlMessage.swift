import Foundation

public struct ConductorControlRequest: Codable, Equatable, Sendable {
    public var id: String
    public var method: String
    public var params: [String: ConductorControlJSON]
    public var client: ConductorControlClient?

    public init(
        id: String = UUID().uuidString,
        method: String,
        params: [String: ConductorControlJSON] = [:],
        client: ConductorControlClient? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.client = client
    }
}

public struct ConductorControlClient: Codable, Equatable, Sendable {
    public var name: String
    public var version: String?

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }
}

public struct ConductorControlResponse: Codable, Equatable, Sendable {
    public var id: String
    public var ok: Bool
    public var result: ConductorControlJSON?
    public var error: ConductorControlError?

    public static func success(id: String, result: ConductorControlJSON = .object([:])) -> Self {
        ConductorControlResponse(id: id, ok: true, result: result, error: nil)
    }

    public static func failure(id: String, error: ConductorControlError) -> Self {
        ConductorControlResponse(id: id, ok: false, result: nil, error: error)
    }
}

public struct ConductorControlError: Codable, Error, Equatable, Sendable {
    public var code: String
    public var message: String
    public var details: [String: ConductorControlJSON]

    public init(
        code: String,
        message: String,
        details: [String: ConductorControlJSON] = [:]
    ) {
        self.code = code
        self.message = message
        self.details = details
    }

    public static func invalidParams(_ message: String, details: [String: ConductorControlJSON] = [:]) -> Self {
        ConductorControlError(code: "invalid_params", message: message, details: details)
    }

    public static func methodNotFound(_ method: String) -> Self {
        ConductorControlError(
            code: "method_not_found",
            message: "Unknown control method.",
            details: ["method": .string(method)]
        )
    }

    public static func targetNotFound(_ message: String, details: [String: ConductorControlJSON] = [:]) -> Self {
        ConductorControlError(code: "target_not_found", message: message, details: details)
    }

    public static func commandDisabled(_ message: String, details: [String: ConductorControlJSON] = [:]) -> Self {
        ConductorControlError(code: "command_disabled", message: message, details: details)
    }
}

public enum ConductorControlMethod {
    public static let appPing = "app.ping"
    public static let appVersion = "app.version"
    public static let appStatus = "app.status"
    public static let appDiagnostics = "app.diagnostics"
    public static let appDiagnosticsExport = "app.diagnosticsExport"
    public static let appQuit = "app.quit"
    public static let workspaceList = "workspace.list"
    public static let workspaceCreate = "workspace.create"
    public static let workspaceSelect = "workspace.select"
    public static let workspaceRename = "workspace.rename"
    public static let workspaceClose = "workspace.close"
    public static let workspaceDuplicate = "workspace.duplicate"
    public static let workspaceMetadata = "workspace.metadata"
    public static let surfaceList = "surface.list"
    public static let surfaceFocus = "surface.focus"
    public static let surfaceSplit = "surface.split"
    public static let surfaceClose = "surface.close"
    public static let surfaceZoom = "surface.zoom"
    public static let surfaceMove = "surface.move"
    public static let terminalSendText = "terminal.sendText"
    public static let terminalSendKey = "terminal.sendKey"
    public static let terminalVisibleText = "terminal.visibleText"
    public static let terminalCwd = "terminal.cwd"
    public static let terminalTitle = "terminal.title"
    public static let terminalRename = "terminal.rename"
    public static let terminalSampleScroll = "terminal.sampleScroll"
    public static let terminalAgent = "terminal.agent"
    public static let terminalResumeAgent = "terminal.resumeAgent"
    public static let terminalResumeAgents = "terminal.resumeAgents"
    public static let browserOpen = "browser.open"
    public static let browserSelect = "browser.select"
    public static let browserNavigate = "browser.navigate"
    public static let browserReload = "browser.reload"
    public static let browserStop = "browser.stop"
    public static let browserBack = "browser.back"
    public static let browserForward = "browser.forward"
    public static let browserSnapshot = "browser.snapshot"
    public static let browserScreenshot = "browser.screenshot"
    public static let browserClick = "browser.click"
    public static let browserFill = "browser.fill"
    public static let browserPress = "browser.press"
    public static let browserWait = "browser.wait"
    public static let browserFind = "browser.find"
    public static let browserEvaluate = "browser.evaluate"
    public static let notificationCreate = "notification.create"
    public static let notificationList = "notification.list"
    public static let notificationClear = "notification.clear"
    public static let notificationFocus = "notification.focus"
    public static let notificationFocusLatest = "notification.focusLatest"
    public static let notificationMarkRead = "notification.markRead"
    public static let notificationTest = "notification.test"
    public static let updateStatus = "update.status"
    public static let updateCheck = "update.check"
    public static let updateDownload = "update.download"
    public static let updateCancel = "update.cancel"
    public static let updateInstall = "update.install"
    public static let updateRehearseInstall = "update.rehearseInstall"
    public static let fileOpen = "file.open"
    public static let fileReveal = "file.reveal"
    public static let fileSave = "file.save"
    public static let fileSnapshot = "file.snapshot"
    public static let commandList = "command.list"
    public static let commandRun = "command.run"
}
