import Foundation
import Testing
@testable import ConductorCore

@Test func controlRequestRoundTripsFlexibleParams() throws {
    let request = ConductorControlRequest(
        id: "req-1",
        method: ConductorControlMethod.terminalSendText,
        params: [
            "terminalID": .string(UUID().uuidString),
            "text": .string("echo hi\n"),
            "force": .bool(true),
            "count": .int(2)
        ],
        client: ConductorControlClient(name: "test", version: "1")
    )

    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(ConductorControlRequest.self, from: data)

    #expect(decoded == request)
    #expect(decoded.params["text"]?.stringValue == "echo hi\n")
    #expect(decoded.params["force"]?.boolValue == true)
}

@Test func controlResponseEncodesSuccessAndErrors() throws {
    let success = ConductorControlResponse.success(
        id: "req-2",
        result: .object([
            "message": .string("pong"),
            "nested": .object(["ok": .bool(true)])
        ])
    )
    let successData = try JSONEncoder().encode(success)
    let decodedSuccess = try JSONDecoder().decode(ConductorControlResponse.self, from: successData)
    #expect(decodedSuccess == success)
    #expect(decodedSuccess.ok)

    let failure = ConductorControlResponse.failure(
        id: "req-3",
        error: .targetNotFound(
            "Missing target.",
            details: ["terminalID": .string("missing")]
        )
    )
    let failureData = try JSONEncoder().encode(failure)
    let decodedFailure = try JSONDecoder().decode(ConductorControlResponse.self, from: failureData)
    #expect(decodedFailure == failure)
    #expect(decodedFailure.error?.code == "target_not_found")
}

@Test func controlSocketUsesApplicationSupportPath() {
    let path = ConductorControlSocket.socketURL(environment: [:]).path
    #expect(path.contains("Application Support/Conductor/control.sock"))
}

@Test func controlSocketHonorsEnvironmentOverride() {
    let path = "/tmp/conductor-control-test.sock"
    let url = ConductorControlSocket.socketURL(environment: [
        ConductorControlSocket.overrideEnvironmentKey: path
    ])
    #expect(url.path == path)
}

@Test func controlMethodCatalogIncludesWorkbenchAutomationSurface() {
    let methods = [
        ConductorControlMethod.appPing,
        ConductorControlMethod.appVersion,
        ConductorControlMethod.appStatus,
        ConductorControlMethod.appDiagnostics,
        ConductorControlMethod.appDiagnosticsExport,
        ConductorControlMethod.appQuit,
        ConductorControlMethod.sessionInspect,
        ConductorControlMethod.sessionRestorePrevious,
        ConductorControlMethod.workspaceList,
        ConductorControlMethod.workspaceCreate,
        ConductorControlMethod.workspaceSelect,
        ConductorControlMethod.workspaceRename,
        ConductorControlMethod.workspaceClose,
        ConductorControlMethod.workspaceDuplicate,
        ConductorControlMethod.workspaceMetadata,
        ConductorControlMethod.surfaceList,
        ConductorControlMethod.surfaceFocus,
        ConductorControlMethod.surfaceSplit,
        ConductorControlMethod.surfaceClose,
        ConductorControlMethod.surfaceZoom,
        ConductorControlMethod.surfaceMove,
        ConductorControlMethod.terminalSendText,
        ConductorControlMethod.terminalSendKey,
        ConductorControlMethod.terminalVisibleText,
        ConductorControlMethod.terminalCwd,
        ConductorControlMethod.terminalTitle,
        ConductorControlMethod.terminalRename,
        ConductorControlMethod.terminalSampleScroll,
        ConductorControlMethod.terminalAgent,
        ConductorControlMethod.terminalResumeAgent,
        ConductorControlMethod.terminalResumeAgents,
        ConductorControlMethod.browserOpen,
        ConductorControlMethod.browserSelect,
        ConductorControlMethod.browserNavigate,
        ConductorControlMethod.browserReload,
        ConductorControlMethod.browserStop,
        ConductorControlMethod.browserBack,
        ConductorControlMethod.browserForward,
        ConductorControlMethod.browserSnapshot,
        ConductorControlMethod.browserScreenshot,
        ConductorControlMethod.browserClick,
        ConductorControlMethod.browserFill,
        ConductorControlMethod.browserPress,
        ConductorControlMethod.browserWait,
        ConductorControlMethod.browserFind,
        ConductorControlMethod.browserEvaluate,
        ConductorControlMethod.notificationCreate,
        ConductorControlMethod.notificationList,
        ConductorControlMethod.notificationClear,
        ConductorControlMethod.notificationFocus,
        ConductorControlMethod.notificationFocusLatest,
        ConductorControlMethod.notificationMarkRead,
        ConductorControlMethod.notificationTest,
        ConductorControlMethod.updateStatus,
        ConductorControlMethod.updateCheck,
        ConductorControlMethod.updateDownload,
        ConductorControlMethod.updateCancel,
        ConductorControlMethod.updateInstall,
        ConductorControlMethod.updateRehearseInstall,
        ConductorControlMethod.fileOpen,
        ConductorControlMethod.fileReveal,
        ConductorControlMethod.fileSave,
        ConductorControlMethod.fileSnapshot,
        ConductorControlMethod.commandList,
        ConductorControlMethod.commandRun
    ]

    #expect(methods.count == Set(methods).count)
    #expect(methods.allSatisfy { $0.contains(".") })
}

@Test func controlErrorHistoryKeepsLatestRecordsFirstAndCapsCapacity() {
    var history = ConductorControlErrorHistory(capacity: 2)
    history.append(ConductorControlErrorRecord(
        timestamp: Date(timeIntervalSince1970: 1),
        requestID: "one",
        method: ConductorControlMethod.workspaceSelect,
        code: "invalid_params",
        message: "First"
    ))
    history.append(ConductorControlErrorRecord(
        timestamp: Date(timeIntervalSince1970: 2),
        requestID: "two",
        method: ConductorControlMethod.browserClick,
        code: "command_disabled",
        message: "Second"
    ))
    history.append(ConductorControlErrorRecord(
        timestamp: Date(timeIntervalSince1970: 3),
        requestID: "three",
        method: ConductorControlMethod.commandRun,
        code: "target_not_found",
        message: "Third"
    ))

    #expect(history.records.map(\.requestID) == ["two", "three"])
    #expect(history.latestFirst.map(\.requestID) == ["three", "two"])
}
