import AppKit
import ConductorCore
import Foundation

@MainActor
final class ConductorControlRouter {
    private weak var model: ConductorWindowModel?
    private var errorHistory = ConductorControlErrorHistory()
    private static let iso8601Formatter = ISO8601DateFormatter()

    init(model: ConductorWindowModel) {
        self.model = model
    }

    func handle(_ request: ConductorControlRequest) async -> ConductorControlResponse {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        guard let model else {
            return failure(
                id: request.id,
                method: request.method,
                error: ConductorControlError(
                    code: "app_unavailable",
                    message: "Conductor model is unavailable."
                )
            )
        }

        do {
            let result: ConductorControlJSON
            switch request.method {
            case ConductorControlMethod.appPing:
                result = .object(["message": .string("pong")])
            case ConductorControlMethod.appVersion:
                result = versionResult()
            case ConductorControlMethod.appStatus:
                result = statusResult(model: model)
            case ConductorControlMethod.appDiagnostics:
                result = diagnosticsResult(model: model)
            case ConductorControlMethod.appDiagnosticsExport:
                result = try diagnosticsExportResult(request: request, model: model)
            case ConductorControlMethod.appQuit:
                result = appQuit(model: model)
            case ConductorControlMethod.sessionInspect:
                result = sessionInspectResult(model: model)
            case ConductorControlMethod.sessionRestorePrevious:
                result = try restorePreviousSession(model: model)
            case ConductorControlMethod.workspaceList:
                result = workspaceListResult(model: model)
            case ConductorControlMethod.workspaceCreate:
                result = try createWorkspace(request: request, model: model)
            case ConductorControlMethod.workspaceSelect:
                result = try selectWorkspace(request: request, model: model)
            case ConductorControlMethod.workspaceRename:
                result = try renameWorkspace(request: request, model: model)
            case ConductorControlMethod.workspaceClose:
                result = try closeWorkspace(request: request, model: model)
            case ConductorControlMethod.workspaceDuplicate:
                result = try duplicateWorkspace(request: request, model: model)
            case ConductorControlMethod.workspaceMetadata:
                result = try await workspaceMetadata(request: request, model: model)
            case ConductorControlMethod.surfaceList:
                result = surfaceListResult(model: model)
            case ConductorControlMethod.surfaceFocus:
                result = try focusSurface(request: request, model: model)
            case ConductorControlMethod.surfaceSplit:
                result = try splitSurface(request: request, model: model)
            case ConductorControlMethod.surfaceClose:
                result = try closeSurface(request: request, model: model)
            case ConductorControlMethod.surfaceZoom:
                result = try zoomSurface(model: model)
            case ConductorControlMethod.surfaceMove:
                result = try moveSurface(request: request, model: model)
            case ConductorControlMethod.terminalSendText:
                result = try sendTerminalText(request: request, model: model)
            case ConductorControlMethod.terminalSendKey:
                result = try sendTerminalKey(request: request, model: model)
            case ConductorControlMethod.terminalVisibleText:
                result = try visibleTerminalText(request: request, model: model)
            case ConductorControlMethod.terminalCwd:
                result = try terminalCwd(request: request, model: model)
            case ConductorControlMethod.terminalTitle:
                result = try terminalTitle(request: request, model: model)
            case ConductorControlMethod.terminalRename:
                result = try renameTerminal(request: request, model: model)
            case ConductorControlMethod.terminalSampleScroll:
                result = try sampleTerminalScroll(request: request, model: model)
            case ConductorControlMethod.terminalAgent:
                result = try terminalAgent(request: request, model: model)
            case ConductorControlMethod.terminalResumeAgent:
                result = try resumeTerminalAgent(request: request, model: model)
            case ConductorControlMethod.terminalResumeAgents:
                result = try resumeTerminalAgents(request: request, model: model)
            case ConductorControlMethod.browserOpen:
                result = try openBrowser(request: request, model: model)
            case ConductorControlMethod.browserSelect:
                result = try selectBrowser(request: request, model: model)
            case ConductorControlMethod.browserNavigate:
                result = try navigateBrowser(request: request, model: model)
            case ConductorControlMethod.browserReload:
                result = try browserAction(request: request, model: model, methodName: "reload") { webTabID in
                    model.controlReloadBrowser(webTabID: webTabID)
                }
            case ConductorControlMethod.browserStop:
                result = try browserAction(request: request, model: model, methodName: "stop") { webTabID in
                    model.controlStopBrowser(webTabID: webTabID)
                }
            case ConductorControlMethod.browserBack:
                result = try browserAction(request: request, model: model, methodName: "back") { webTabID in
                    model.controlBrowserBack(webTabID: webTabID)
                }
            case ConductorControlMethod.browserForward:
                result = try browserAction(request: request, model: model, methodName: "forward") { webTabID in
                    model.controlBrowserForward(webTabID: webTabID)
                }
            case ConductorControlMethod.browserSnapshot:
                result = try await browserSnapshot(request: request, model: model)
            case ConductorControlMethod.browserScreenshot:
                result = try await browserScreenshot(request: request, model: model)
            case ConductorControlMethod.browserClick:
                result = try await browserClick(request: request, model: model)
            case ConductorControlMethod.browserFill:
                result = try await browserFill(request: request, model: model)
            case ConductorControlMethod.browserPress:
                result = try await browserPress(request: request, model: model)
            case ConductorControlMethod.browserWait:
                result = try await browserWait(request: request, model: model)
            case ConductorControlMethod.browserFind:
                result = try await browserFind(request: request, model: model)
            case ConductorControlMethod.browserEvaluate:
                result = try await browserEvaluate(request: request, model: model)
            case ConductorControlMethod.notificationCreate:
                result = try createNotification(request: request, model: model)
            case ConductorControlMethod.notificationList:
                result = notificationListResult(model: model)
            case ConductorControlMethod.notificationClear:
                result = try notificationClearResult(request: request, model: model)
            case ConductorControlMethod.notificationFocus:
                result = try notificationFocus(request: request, model: model)
            case ConductorControlMethod.notificationFocusLatest:
                result = try notificationFocusLatest(request: request, model: model)
            case ConductorControlMethod.notificationMarkRead:
                result = try notificationMarkRead(request: request, model: model)
            case ConductorControlMethod.notificationTest:
                result = try await notificationTest(request: request, model: model)
            case ConductorControlMethod.updateStatus:
                result = updateResult(model: model)
            case ConductorControlMethod.updateCheck:
                result = try await updateCheck(request: request, model: model)
            case ConductorControlMethod.updateDownload:
                result = try await updateDownload(request: request, model: model)
            case ConductorControlMethod.updateCancel:
                result = updateCancel(model: model)
            case ConductorControlMethod.updateInstall:
                result = updateInstall(model: model)
            case ConductorControlMethod.updateRehearseInstall:
                result = try await updateRehearseInstall(model: model)
            case ConductorControlMethod.fileOpen:
                result = try fileOpen(request: request, model: model)
            case ConductorControlMethod.fileReveal:
                result = try fileReveal(request: request, model: model)
            case ConductorControlMethod.fileSave:
                result = try fileSave(request: request, model: model)
            case ConductorControlMethod.fileSnapshot:
                result = try fileSnapshot(request: request, model: model)
            case ConductorControlMethod.commandList:
                result = commandListResult(model: model)
            case ConductorControlMethod.commandRun:
                result = try runCommand(request: request, model: model)
            default:
                return failure(id: request.id, method: request.method, error: .methodNotFound(request.method))
            }
            return success(id: request.id, method: request.method, startedAt: startedAt, result: result)
        } catch let error as ConductorControlError {
            return failure(id: request.id, method: request.method, error: error)
        } catch {
            return failure(
                id: request.id,
                method: request.method,
                error: ConductorControlError(
                    code: "internal_error",
                    message: error.localizedDescription
                )
            )
        }
    }

    private func success(
        id: String,
        method: String,
        startedAt: UInt64,
        result: ConductorControlJSON
    ) -> ConductorControlResponse {
        recordPerformanceBudgetSample(method: method, startedAt: startedAt)
        return .success(id: id, result: result)
    }

    private func recordPerformanceBudgetSample(method: String, startedAt: UInt64) {
        guard let budgetID = performanceBudgetID(for: method) else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        guard let sample = ConductorPerformanceDiagnostics.shared.recordBudgetSample(
            budgetID: budgetID,
            durationNanoseconds: elapsed,
            source: "control.\(method)"
        ) else {
            return
        }
        ConductorDiagnostics.record("performance-budget-sample", fields: [
            "budget": sample.budgetID,
            "durationMS": String(sample.durationMilliseconds),
            "targetMS": String(sample.targetMilliseconds),
            "status": sample.status,
            "source": sample.source
        ])
    }

    private func performanceBudgetID(for method: String) -> String? {
        switch method {
        case ConductorControlMethod.workspaceSelect:
            "workspace.switch"
        case ConductorControlMethod.surfaceFocus:
            "terminal.tab-switch"
        case ConductorControlMethod.browserOpen, ConductorControlMethod.browserNavigate:
            "browser.restore"
        default:
            nil
        }
    }

    private func failure(
        id: String,
        method: String,
        error: ConductorControlError
    ) -> ConductorControlResponse {
        errorHistory.append(ConductorControlErrorRecord(
            timestamp: Date(),
            requestID: id,
            method: method,
            code: error.code,
            message: error.message,
            details: error.details
        ))
        ConductorDiagnostics.record("control-request-failed", fields: [
            "method": method,
            "code": error.code,
            "request": id
        ])
        return .failure(id: id, error: error)
    }

    private func versionResult() -> ConductorControlJSON {
        let version = ConductorAppVersion.current()
        return .object([
            "version": .string(version.version),
            "build": .string(version.build),
            "display": .string(version.displayText),
            "socket": .string(ConductorControlSocket.socketURL().path)
        ])
    }

    private func statusResult(model: ConductorWindowModel) -> ConductorControlJSON {
        .object([
            "version": versionResult(),
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
            "focusedTerminalID": model.focusedTerminalID.map { .string($0.description) } ?? .null,
            "workspaceCount": .int(model.workspaces.count),
            "webTabCount": .int(model.workspaceContentWebTabCount),
            "fileTabCount": .int(model.workspaceContentFileTabCount),
            "surfaceCount": .int(model.runtimeSurfaceCount),
            "metadataCount": .int(model.runtimeMetadataCount),
            "settingsVisible": .bool(model.settingsPanelVisible),
            "commandPaletteVisible": .bool(model.commandPaletteVisible),
            "attentionUnreadCount": .int(model.controlAttentionEvents(includeRead: false).count),
            "update": updateResult(model: model),
            "sessionJournal": sessionJournalSummaryResult(model.controlSessionJournalSummary),
            "sessionRestore": sessionRestoreReportResult(model.controlSessionRestoreReport)
        ])
    }

    private func diagnosticsResult(model: ConductorWindowModel) -> ConductorControlJSON {
        let performanceSnapshot = ConductorPerformanceDiagnostics.shared.snapshot()
        return .object([
            "status": statusResult(model: model),
            "session": .object([
                "journal": sessionJournalSummaryResult(model.controlSessionJournalSummary),
                "journalPath": .string(model.controlSessionJournalURL.path),
                "restoreHealth": sessionRestoreReportResult(model.controlSessionRestoreReport),
                "inspect": sessionInspectResult(model: model)
            ]),
            "attention": .object([
                "storePath": .string(model.controlAttentionStoreURL.path),
                "eventCount": .int(model.controlAttentionEvents().count),
                "unreadCount": .int(model.controlAttentionEvents(includeRead: false).count)
            ]),
            "notifications": .object([
                "authorization": .string(notificationAuthorizationStateResult(model.notificationAuthorizationState)),
                "launchSupportsSystemNotifications": .bool(Bundle.main.bundleURL.pathExtension == "app")
            ]),
            "update": updateResult(model: model),
            "logs": .object([
                "diagnosticsLogPath": .string(ConductorDiagnostics.logURL.path),
                "availableLogCount": .int(ConductorDiagnostics.logURLs.filter { FileManager.default.fileExists(atPath: $0.path) }.count)
            ]),
            "control": .object([
                "socket": .string(ConductorControlSocket.socketURL().path),
                "transport": .string("user-local-unix-domain-socket"),
                "recentErrorCount": .int(errorHistory.records.count),
                "recentErrors": .array(errorHistory.latestFirst.map(controlErrorRecordResult))
            ]),
            "performance": performanceDiagnosticsResult(performanceSnapshot)
        ])
    }

    private func appQuit(model: ConductorWindowModel) -> ConductorControlJSON {
        model.flushPersistence()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            NSApp.terminate(nil)
        }
        return .object(["quitting": .bool(true)])
    }

    private func sessionInspectResult(model: ConductorWindowModel) -> ConductorControlJSON {
        let restoreReport = model.controlSessionRestoreReport
        let recentEvents = model.controlSessionJournalEntries(limit: 12)
        let surfaces = model.controlSessionSurfaceInspection()
        let issues = sessionInspectIssues(
            report: restoreReport,
            canRestorePrevious: model.canRestorePreviousSessionSnapshot,
            journalEntryCount: model.controlSessionJournalSummary.entryCount,
            surfaceIssueCount: surfaces.issueCount
        )
        return .object([
            "state": .string(sessionInspectState(report: restoreReport, issueCount: issues.count)),
            "canRestorePrevious": .bool(model.canRestorePreviousSessionSnapshot),
            "current": .object([
                "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
                "workspaceCount": .int(model.workspaces.count),
                "terminalCount": .int(surfaces.terminalCount),
                "webTabCount": .int(surfaces.browserCount),
                "fileTabCount": .int(surfaces.fileCount),
                "focusedTerminalID": model.focusedTerminalID.map { .string($0.description) } ?? .null
            ]),
            "surfaces": sessionSurfaceInspectionResult(surfaces),
            "surfaceIssues": sessionSurfaceRecoveryIssuesResult(surfaces.recoveryIssues),
            "restore": sessionRestoreReportResult(restoreReport),
            "journal": .object([
                "path": .string(model.controlSessionJournalURL.path),
                "summary": sessionJournalSummaryResult(model.controlSessionJournalSummary),
                "recentEvents": .array(recentEvents.map(sessionJournalEventResult))
            ]),
            "issues": .array(issues),
            "recommendedActions": .array(sessionInspectRecommendations(
                report: restoreReport,
                canRestorePrevious: model.canRestorePreviousSessionSnapshot,
                issueCount: issues.count
            ).map { .string($0) })
        ])
    }

    private func restorePreviousSession(model: ConductorWindowModel) throws -> ConductorControlJSON {
        guard model.canRestorePreviousSessionSnapshot else {
            throw ConductorControlError.commandDisabled("No previous session snapshot is available.")
        }
        guard model.restorePreviousSessionSnapshot() else {
            let report = model.controlSessionRestoreReport
            throw ConductorControlError.commandDisabled(
                "Previous session snapshot could not be restored.",
                details: [
                    "state": .string(report.state.rawValue),
                    "message": .string(report.message),
                    "attemptedPaths": .array(report.attemptedPaths.map { .string($0) }),
                    "failedPaths": .array(report.failedPaths.map { .string($0) })
                ]
            )
        }
        return .object([
            "restored": .bool(true),
            "sessionRestore": sessionRestoreReportResult(model.controlSessionRestoreReport)
        ])
    }

    private func sessionInspectState(
        report: WorkspacePersistenceLoadReport,
        issueCount: Int
    ) -> String {
        if issueCount > 0 {
            return "needs_attention"
        }
        switch report.state {
        case .restored, .restoredFromPrevious, .restoredFromJournal:
            return "healthy"
        case .disabled:
            return "disabled"
        case .missing, .reset:
            return "new_session"
        case .failed:
            return "failed"
        }
    }

    private func sessionInspectIssues(
        report: WorkspacePersistenceLoadReport,
        canRestorePrevious: Bool,
        journalEntryCount: Int,
        surfaceIssueCount: Int
    ) -> [ConductorControlJSON] {
        var issues: [ConductorControlJSON] = []
        if report.state == .failed {
            issues.append(sessionInspectIssue(
                severity: "critical",
                kind: "restore_failed",
                title: "Session restore failed.",
                detail: report.message
            ))
        }
        if report.state == .restoredFromPrevious {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "fallback_snapshot_used",
                title: "Previous snapshot was used.",
                detail: "The latest session snapshot was unavailable or invalid."
            ))
        }
        if report.state == .restoredFromJournal {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "journal_replay_used",
                title: "Session journal replay was used.",
                detail: "Snapshots were unavailable or invalid, so Conductor rebuilt a workspace skeleton from recorded session events."
            ))
        }
        if report.droppedWorkspaceCount > 0 {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "workspaces_dropped",
                title: "Some workspaces were skipped.",
                detail: "\(report.droppedWorkspaceCount) invalid workspace snapshots were not restored."
            ))
        }
        if report.droppedWebTabCount > 0 || report.droppedFileTabCount > 0 {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "content_tabs_dropped",
                title: "Some tabs were not restored.",
                detail: "\(report.droppedWebTabCount) web tabs and \(report.droppedFileTabCount) file tabs were dropped."
            ))
        }
        if !report.missingFilePaths.isEmpty {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "missing_files",
                title: "File tabs point to missing files.",
                detail: report.missingFilePaths.prefix(3).joined(separator: "\n"),
                count: report.missingFilePaths.count
            ))
        }
        if !report.failedPaths.isEmpty {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "state_files_unavailable",
                title: "Some state files could not be loaded.",
                detail: report.failedPaths.prefix(3).joined(separator: "\n"),
                count: report.failedPaths.count
            ))
        }
        if journalEntryCount == 0 && report.state != .disabled {
            issues.append(sessionInspectIssue(
                severity: "info",
                kind: "journal_empty",
                title: "Session journal has no recent entries.",
                detail: "Use the workbench normally; Conductor records semantic changes for recovery diagnostics."
            ))
        }
        if surfaceIssueCount > 0 {
            issues.append(sessionInspectIssue(
                severity: "warning",
                kind: "surface_issues",
                title: "Some restored surfaces need attention.",
                detail: "\(surfaceIssueCount) terminal, browser, or file surface checks reported issues.",
                count: surfaceIssueCount
            ))
        }
        if !canRestorePrevious && report.state == .failed {
            issues.append(sessionInspectIssue(
                severity: "critical",
                kind: "no_previous_snapshot",
                title: "No previous valid snapshot is available.",
                detail: "Conductor cannot roll back this session automatically."
            ))
        }
        return issues
    }

    private func sessionSurfaceInspectionResult(
        _ snapshot: SessionSurfaceInspectionSnapshot
    ) -> ConductorControlJSON {
        .object([
            "workspaceCount": .int(snapshot.workspaces.count),
            "terminalCount": .int(snapshot.terminalCount),
            "browserCount": .int(snapshot.browserCount),
            "fileCount": .int(snapshot.fileCount),
            "issueCount": .int(snapshot.issueCount),
            "criticalIssueCount": .int(snapshot.criticalIssueCount),
            "warningIssueCount": .int(snapshot.warningIssueCount),
            "issues": sessionSurfaceRecoveryIssuesResult(snapshot.recoveryIssues),
            "workspaces": .array(snapshot.workspaces.map(sessionSurfaceWorkspaceResult))
        ])
    }

    private func sessionSurfaceRecoveryIssuesResult(
        _ issues: [SessionSurfaceInspectionSnapshot.RecoveryIssue]
    ) -> ConductorControlJSON {
        .array(issues.map(sessionSurfaceRecoveryIssueResult))
    }

    private func sessionSurfaceRecoveryIssueResult(
        _ issue: SessionSurfaceInspectionSnapshot.RecoveryIssue
    ) -> ConductorControlJSON {
        .object([
            "id": .string(issue.id),
            "severity": .string(issue.severity.rawValue),
            "kind": .string(issue.kind),
            "surfaceKind": .string(issue.surfaceKind.rawValue),
            "workspaceID": .string(issue.workspaceID.description),
            "workspaceTitle": .string(issue.workspaceTitle),
            "terminalID": issue.terminalID.map { .string($0.description) } ?? .null,
            "webTabID": issue.webTabID.map { .string($0.rawValue.uuidString) } ?? .null,
            "fileTabID": issue.fileTabID.map { .string($0) } ?? .null,
            "surfaceTitle": .string(issue.surfaceTitle),
            "title": .string(issue.title),
            "detail": .string(issue.detail),
            "impact": .string(issue.impact),
            "suggestedAction": .string(issue.suggestedAction),
            "primaryAction": .object([
                "kind": .string(issue.primaryAction.kind),
                "title": .string(issue.primaryAction.title),
                "detail": .string(issue.primaryAction.detail),
                "systemImage": .string(issue.primaryAction.systemImage),
                "destructive": .bool(issue.primaryAction.destructive)
            ])
        ])
    }

    private func sessionSurfaceWorkspaceResult(
        _ workspace: SessionSurfaceInspectionSnapshot.Workspace
    ) -> ConductorControlJSON {
        .object([
            "id": .string(workspace.id.description),
            "title": .string(workspace.title),
            "selected": .bool(workspace.selected),
            "terminalCount": .int(workspace.terminals.count),
            "browserCount": .int(workspace.webTabs.count),
            "fileCount": .int(workspace.files.count),
            "terminals": .array(workspace.terminals.map(sessionSurfaceTerminalResult)),
            "webTabs": .array(workspace.webTabs.map(sessionSurfaceWebTabResult)),
            "files": .array(workspace.files.map(sessionSurfaceFileTabResult))
        ])
    }

    private func sessionSurfaceTerminalResult(
        _ terminal: SessionSurfaceInspectionSnapshot.Terminal
    ) -> ConductorControlJSON {
        .object([
            "id": .string(terminal.id.description),
            "paneID": .string(terminal.paneID.description),
            "title": .string(terminal.title),
            "workingDirectory": terminal.workingDirectory.map { .string($0) } ?? .null,
            "selected": .bool(terminal.selected),
            "focused": .bool(terminal.focused),
            "userTitle": terminal.userTitle.map { .string($0) } ?? .null,
            "agent": .object([
                "available": .bool(terminal.hasAgentSnapshot),
                "displayName": terminal.agentDisplayName.map { .string($0) } ?? .null,
                "state": terminal.agentState.map { .string($0) } ?? .null,
                "sessionIdentifier": terminal.agentSessionIdentifier.map { .string($0) } ?? .null,
                "resumeCommand": terminal.agentResumeCommand.map { .string($0) } ?? .null
            ]),
            "lastCommand": .object([
                "exitCode": terminal.lastCommandExitCode.map { .int($0) } ?? .null,
                "finishedAt": terminal.lastCommandFinishedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null
            ]),
            "process": .object([
                "restoredFromSession": .bool(terminal.restoredFromSession),
                "reattached": .bool(terminal.processReattached),
                "status": .string(terminal.processReattached ? "reattached" : (terminal.restoredFromSession ? "fresh-after-restore" : "live"))
            ]),
            "search": .object([
                "active": .bool(terminal.searchActive),
                "needle": terminal.searchNeedle.map { .string($0) } ?? .null
            ]),
            "issues": .array(terminal.issues.map { .string($0) })
        ])
    }

    private func sessionSurfaceWebTabResult(
        _ tab: SessionSurfaceInspectionSnapshot.WebTab
    ) -> ConductorControlJSON {
        .object([
            "id": .string(tab.id.rawValue.uuidString),
            "title": .string(tab.title),
            "url": tab.url.map { .string($0) } ?? .null,
            "pendingAddress": .string(tab.pendingAddress),
            "selected": .bool(tab.selected),
            "loading": .bool(tab.loading),
            "errorMessage": tab.errorMessage.map { .string($0) } ?? .null,
            "historyCount": .int(tab.historyCount),
            "currentHistoryIndex": tab.currentHistoryIndex.map { .int($0) } ?? .null,
            "canGoBack": .bool(tab.canGoBack),
            "canGoForward": .bool(tab.canGoForward),
            "scrollY": tab.scrollY.map { .double($0) } ?? .null,
            "hasInteractionState": .bool(tab.hasInteractionState),
            "runtimeEventCount": .int(tab.runtimeEventCount),
            "latestRuntimeEvent": tab.latestRuntimeEvent.map(webRuntimeEventResult) ?? .null,
            "issues": .array(tab.issues.map { .string($0) })
        ])
    }

    private func sessionSurfaceFileTabResult(
        _ tab: SessionSurfaceInspectionSnapshot.FileTab
    ) -> ConductorControlJSON {
        .object([
            "id": .string(tab.id),
            "title": .string(tab.title),
            "path": .string(tab.path),
            "rootPath": .string(tab.rootPath),
            "selected": .bool(tab.selected),
            "dirty": .bool(tab.dirty),
            "externallyChanged": .bool(tab.externallyChanged),
            "exists": .bool(tab.exists),
            "issues": .array(tab.issues.map { .string($0) })
        ])
    }

    private func sessionInspectIssue(
        severity: String,
        kind: String,
        title: String,
        detail: String,
        count: Int? = nil
    ) -> ConductorControlJSON {
        var object: [String: ConductorControlJSON] = [
            "severity": .string(severity),
            "kind": .string(kind),
            "title": .string(title),
            "detail": .string(detail)
        ]
        if let count {
            object["count"] = .int(count)
        }
        return .object(object)
    }

    private func sessionInspectRecommendations(
        report: WorkspacePersistenceLoadReport,
        canRestorePrevious: Bool,
        issueCount: Int
    ) -> [String] {
        guard issueCount > 0 else {
            return ["No recovery action needed."]
        }
        var actions: [String] = []
        if canRestorePrevious && (report.state == .failed || report.state == .restoredFromPrevious || report.state == .restoredFromJournal) {
            actions.append("Run `conductor session restore-previous` if the current workspace looks wrong.")
        }
        if !report.missingFilePaths.isEmpty {
            actions.append("Recreate or remove missing file tabs listed in `restore.missingFilePaths`.")
        }
        if !report.failedPaths.isEmpty {
            actions.append("Export diagnostics before deleting state files so restore failures can be traced.")
        }
        if actions.isEmpty {
            actions.append("Review `issues` and `journal.recentEvents` to confirm what changed.")
        }
        return actions
    }

    private func performanceDiagnosticsResult(
        _ snapshot: ConductorPerformanceDiagnosticsSnapshot
    ) -> ConductorControlJSON {
        let latestSamplesByBudget = latestPerformanceSamplesByBudget(snapshot.recentBudgetSamples)
        let report = performanceBudgetReportResult(
            snapshot: snapshot,
            latestSamplesByBudget: latestSamplesByBudget
        )
        return .object([
            "mainThread": .object([
                "recentStallCount": .int(snapshot.recentMainThreadStalls.count),
                "recentStalls": .array(snapshot.recentMainThreadStalls.map(mainThreadStallResult)),
                "status": .string(snapshot.recentMainThreadStalls.isEmpty ? "no_recent_stalls" : "recent_stalls_recorded")
            ]),
            "budgets": .object([
                "count": .int(snapshot.budgets.count),
                "items": .array(snapshot.budgets.map { budget in
                    performanceBudgetResult(budget, latestSample: latestSamplesByBudget[budget.id])
                }),
                "state": .string(snapshot.recentBudgetSamples.isEmpty ? "targets_defined" : "samples_recorded")
            ]),
            "samples": .object([
                "recentCount": .int(snapshot.recentBudgetSamples.count),
                "recent": .array(snapshot.recentBudgetSamples.map(performanceBudgetSampleResult))
            ]),
            "report": report
        ])
    }

    private func latestPerformanceSamplesByBudget(
        _ samples: [ConductorPerformanceBudgetSample]
    ) -> [String: ConductorPerformanceBudgetSample] {
        var latest: [String: ConductorPerformanceBudgetSample] = [:]
        for sample in samples where latest[sample.budgetID] == nil {
            latest[sample.budgetID] = sample
        }
        return latest
    }

    private func performanceBudgetReportResult(
        snapshot: ConductorPerformanceDiagnosticsSnapshot,
        latestSamplesByBudget: [String: ConductorPerformanceBudgetSample]
    ) -> ConductorControlJSON {
        let missingBudgetIDs = snapshot.budgets
            .map(\.id)
            .filter { latestSamplesByBudget[$0] == nil }
        let overBudgetSamples = snapshot.recentBudgetSamples.filter { $0.status == "over_budget" }
        let slowestRecentSample = snapshot.recentBudgetSamples.max {
            $0.durationMilliseconds < $1.durationMilliseconds
        }
        let status: String
        if snapshot.recentBudgetSamples.isEmpty {
            status = "no_samples"
        } else if !overBudgetSamples.isEmpty {
            status = "recent_over_budget"
        } else if !missingBudgetIDs.isEmpty {
            status = "partial_coverage"
        } else {
            status = "covered"
        }

        return .object([
            "status": .string(status),
            "budgetCount": .int(snapshot.budgets.count),
            "sampledBudgetCount": .int(latestSamplesByBudget.count),
            "missingBudgetCount": .int(missingBudgetIDs.count),
            "missingBudgetIDs": .array(missingBudgetIDs.map { .string($0) }),
            "recentSampleCount": .int(snapshot.recentBudgetSamples.count),
            "recentOverBudgetCount": .int(overBudgetSamples.count),
            "recentOverBudgetSamples": .array(overBudgetSamples.map(performanceBudgetSampleResult)),
            "slowestRecentSample": slowestRecentSample.map(performanceBudgetSampleResult) ?? .null
        ])
    }

    private func mainThreadStallResult(_ record: ConductorMainThreadStallRecord) -> ConductorControlJSON {
        .object([
            "timestamp": .string(Self.iso8601Formatter.string(from: record.timestamp)),
            "durationMS": .int(record.durationMilliseconds),
            "thresholdMS": .int(record.thresholdMilliseconds)
        ])
    }

    private func performanceBudgetResult(
        _ budget: ConductorPerformanceBudget,
        latestSample: ConductorPerformanceBudgetSample?
    ) -> ConductorControlJSON {
        .object([
            "id": .string(budget.id),
            "name": .string(budget.name),
            "targetMS": .int(budget.targetMilliseconds),
            "measurement": .string(budget.measurement),
            "status": .string(latestSample?.status ?? "not_sampled"),
            "lastSample": latestSample.map(performanceBudgetSampleResult) ?? .null
        ])
    }

    private func performanceBudgetSampleResult(_ sample: ConductorPerformanceBudgetSample) -> ConductorControlJSON {
        .object([
            "timestamp": .string(Self.iso8601Formatter.string(from: sample.timestamp)),
            "budgetID": .string(sample.budgetID),
            "name": .string(sample.name),
            "durationMS": .int(sample.durationMilliseconds),
            "targetMS": .int(sample.targetMilliseconds),
            "status": .string(sample.status),
            "source": .string(sample.source)
        ])
    }

    private func controlErrorRecordResult(_ record: ConductorControlErrorRecord) -> ConductorControlJSON {
        .object([
            "timestamp": .string(Self.iso8601Formatter.string(from: record.timestamp)),
            "requestID": .string(record.requestID),
            "method": .string(record.method),
            "code": .string(record.code),
            "message": .string(record.message),
            "details": .object(record.details)
        ])
    }

    private func diagnosticsExportResult(
        request: ConductorControlRequest,
        model: ConductorWindowModel
    ) throws -> ConductorControlJSON {
        let outputPath = request.params["outputPath"]?.stringValue
        ConductorDiagnostics.recordSync("diagnostics-export-start", fields: [
            "output": outputPath ?? "default"
        ])
        let export = try ConductorDiagnosticsBundleExporter.export(
            summary: diagnosticsResult(model: model),
            logURLs: ConductorDiagnostics.logURLs,
            outputPath: outputPath
        )
        ConductorDiagnostics.recordSync("diagnostics-export-complete", fields: [
            "path": export.directoryURL.path,
            "files": String(export.files.count),
            "missing": String(export.missingFiles.count)
        ])
        return .object([
            "path": .string(export.directoryURL.path),
            "createdAt": .string(Self.iso8601Formatter.string(from: export.createdAt)),
            "fileCount": .int(export.files.count),
            "missingFiles": .array(export.missingFiles.map { .string($0) }),
            "files": .array(export.files.map { file in
                .object([
                    "path": .string(file.relativePath),
                    "bytes": .int(file.byteCount)
                ])
            })
        ])
    }

    private func updateResult(model: ConductorWindowModel) -> ConductorControlJSON {
        var payload = updateStatePayload(model.updateState)
        payload["automaticChecks"] = automaticUpdateDiagnosticsResult(model.automaticUpdateDiagnostics)
        return .object(payload)
    }

    private func updateStatePayload(_ state: ConductorUpdateState) -> [String: ConductorControlJSON] {
        var payload: [String: ConductorControlJSON] = [
            "phase": .string(updatePhaseResult(state.phase)),
            "currentVersion": .string(state.currentVersion.displayText),
            "canCheck": .bool(state.canCheck),
            "canDownload": .bool(state.canDownload),
            "canInstall": .bool(state.canInstall),
            "lastCheckedAt": state.lastCheckedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null
        ]
        payload["availableVersion"] = state.availableVersion.map { .string($0.displayText) } ?? .null
        payload["selectedPackageKind"] = state.selectedPackageKind.map { .string($0.rawValue) } ?? .null
        payload["downloadedPackagePath"] = state.downloadedPackageURL.map { .string($0.path) } ?? .null
        if let progress = state.downloadProgress {
            payload["downloadProgress"] = .object([
                "bytesWritten": .int(Int(progress.bytesWritten)),
                "expectedBytes": .int(Int(progress.expectedBytes)),
                "fraction": .double(progress.fraction)
            ])
        } else {
            payload["downloadProgress"] = .null
        }
        if let manifest = state.manifest {
            payload["manifest"] = .object([
                "version": .string(manifest.version),
                "build": .string(manifest.build),
                "channel": .string(manifest.channel),
                "platform": .string(manifest.platform),
                "arch": .string(manifest.arch),
                "createdAt": .string(manifest.createdAt),
                "hasDelta": .bool(manifest.delta != nil)
            ])
        } else {
            payload["manifest"] = .null
        }
        if let artifact = state.selectedArtifact {
            payload["selectedArtifact"] = .object([
                "filename": .string(artifact.filename),
                "size": .int(Int(artifact.size)),
                "changedFiles": artifact.changedFiles.map { .int($0) } ?? .null,
                "removedFiles": artifact.removedFiles.map { .int($0) } ?? .null
            ])
        } else {
            payload["selectedArtifact"] = .null
        }
        return payload
    }

    private func automaticUpdateDiagnosticsResult(
        _ diagnostics: ConductorAutomaticUpdateDiagnostics
    ) -> ConductorControlJSON {
        .object([
            "enabled": .bool(diagnostics.isEnabled),
            "running": .bool(diagnostics.isRunning),
            "currentIntervalSeconds": diagnostics.currentIntervalSeconds.map { .double($0) } ?? .null,
            "nextCheckAt": diagnostics.nextCheckAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "lastAttemptAt": diagnostics.lastAttemptAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "lastCompletedAt": diagnostics.lastCompletedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "lastSuccessAt": diagnostics.lastSuccessAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "lastFailureAt": diagnostics.lastFailureAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "consecutiveFailures": .int(diagnostics.consecutiveFailures),
            "lastFailureDescription": diagnostics.lastFailureDescription.map { .string($0) } ?? .null
        ])
    }

    private func updatePhaseResult(_ phase: ConductorUpdatePhase) -> String {
        switch phase {
        case .idle:
            "idle"
        case .checking:
            "checking"
        case .upToDate:
            "up-to-date"
        case .available:
            "available"
        case .downloading:
            "downloading"
        case .downloaded:
            "downloaded"
        case .installing:
            "installing"
        case .failed:
            "failed"
        }
    }

    private func updateCheck(
        request: ConductorControlRequest,
        model: ConductorWindowModel
    ) async throws -> ConductorControlJSON {
        if let manifestURL = request.params["manifestURL"]?.stringValue {
            model.setUpdateManifestURL(manifestURL, persist: false)
        }
        let timeout = try doubleParam(
            "timeoutSeconds",
            request.params,
            defaultValue: 15,
            lowerBound: 0.2,
            upperBound: 120
        )
        model.checkForUpdates(manual: true)
        return try await waitForUpdateState(
            model: model,
            timeoutSeconds: timeout,
            isWaiting: { phase in
                if case .checking = phase { return true }
                return false
            }
        )
    }

    private func updateDownload(
        request: ConductorControlRequest,
        model: ConductorWindowModel
    ) async throws -> ConductorControlJSON {
        let timeout = try doubleParam(
            "timeoutSeconds",
            request.params,
            defaultValue: 60,
            lowerBound: 0.2,
            upperBound: 600
        )
        model.downloadAvailableUpdate()
        return try await waitForUpdateState(
            model: model,
            timeoutSeconds: timeout,
            isWaiting: { phase in
                if case .downloading = phase { return true }
                return false
            }
        )
    }

    private func updateCancel(model: ConductorWindowModel) -> ConductorControlJSON {
        model.cancelUpdateOperation()
        return updateResult(model: model)
    }

    private func updateInstall(model: ConductorWindowModel) -> ConductorControlJSON {
        model.installDownloadedUpdateAndRelaunch()
        return updateResult(model: model)
    }

    private func updateRehearseInstall(model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let rehearsal = try await model.rehearseDownloadedUpdateInstall()
        var payload = updateStatePayload(model.updateState)
        payload["automaticChecks"] = automaticUpdateDiagnosticsResult(model.automaticUpdateDiagnostics)
        payload["installRehearsal"] = .object([
            "ok": .bool(true),
            "scriptPath": .string(rehearsal.scriptURL.path),
            "logPath": .string(rehearsal.logURL.path),
            "exitStatus": .int(Int(rehearsal.exitStatus))
        ])
        return .object(payload)
    }

    private func waitForUpdateState(
        model: ConductorWindowModel,
        timeoutSeconds: Double,
        isWaiting: (ConductorUpdatePhase) -> Bool
    ) async throws -> ConductorControlJSON {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while isWaiting(model.updateState.phase) {
            if Date() >= deadline {
                throw ConductorControlError(
                    code: "timeout",
                    message: "Timed out waiting for update operation to settle.",
                    details: ["phase": .string(updatePhaseResult(model.updateState.phase))]
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        return updateResult(model: model)
    }

    private func fileOpen(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let fileURL = try fileURLParam("path", request.params, model: model)
        let rootURL = try optionalFileURLParam("rootPath", request.params, model: model)
            ?? (try optionalFileURLParam("root", request.params, model: model))
        let values = try fileResourceValues(
            for: fileURL,
            keys: [.isDirectoryKey],
            missingCode: "file_not_found"
        )
        guard values.isDirectory != true else {
            throw ConductorControlError(
                code: "file_is_directory",
                message: "file.open requires a file path.",
                details: ["path": .string(fileURL.path)]
            )
        }
        guard let tab = model.controlOpenFile(fileURL, rootURL: rootURL) else {
            throw ConductorControlError.targetNotFound(
                "File could not be opened.",
                details: ["path": .string(fileURL.path)]
            )
        }
        return .object([
            "opened": .bool(true),
            "selectedFileTabID": .string(tab.id),
            "file": fileTabResult(tab, model: model, includeText: false, maxTextBytes: 0)
        ])
    }

    private func fileReveal(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let targetURL = try optionalFileURLParam("path", request.params, model: model)
            ?? optionalFileTargetURL(request.params, model: model)
        let rootURL = try optionalFileURLParam("rootPath", request.params, model: model)
            ?? (try optionalFileURLParam("root", request.params, model: model))
        if let targetURL {
            _ = try fileResourceValues(
                for: targetURL,
                keys: [.isDirectoryKey],
                missingCode: "file_not_found"
            )
        }
        let request = model.controlRevealFile(targetURL, rootURL: rootURL)
        return .object([
            "panelVisible": .bool(model.fileManagerPanelRequest != nil),
            "rootPath": .string(request.rootURL.path),
            "selectedPath": request.selectedURL.map { .string($0.path) } ?? .null
        ])
    }

    private func fileSave(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        if let text = request.params["text"]?.stringValue {
            let fileURL = try requiredFileTargetURL(request.params, model: model)
            try writeFileText(text, to: fileURL)
            let tab = model.workspaceFileTabs.first { $0.id == fileURL.path }
                ?? ConductorWorkspaceFileTab(fileURL: fileURL, rootURL: fileURL.deletingLastPathComponent())
            if model.workspaceFileTabs.contains(where: { $0.id == tab.id }) {
                model.markWorkspaceFileBufferSaved(tabID: tab.id, text: text)
            }
            return .object([
                "mode": .string("write"),
                "writtenBytes": .int(text.utf8.count),
                "saveRequested": .bool(false),
                "file": fileTabResult(tab, model: model, includeText: false, maxTextBytes: 0)
            ])
        }

        guard let tab = fileTargetTab(request.params, model: model, allowSynthetic: false) else {
            throw ConductorControlError.targetNotFound("No open file tab is selected or targeted.")
        }
        guard let buffer = model.workspaceFileBufferSnapshot(for: tab.id),
              buffer.canSave,
              buffer.isEditable,
              !buffer.isReadOnly else {
            throw ConductorControlError(
                code: "file_buffer_unavailable",
                message: "File tab has no synchronized editable buffer to save.",
                details: [
                    "fileTabID": .string(tab.id),
                    "path": .string(tab.fileURL.path),
                    "bufferAvailable": .bool(model.workspaceFileBufferSnapshot(for: tab.id) != nil),
                    "isEditable": .bool(model.workspaceFileBufferSnapshot(for: tab.id)?.isEditable ?? false),
                    "isReadOnly": .bool(model.workspaceFileBufferSnapshot(for: tab.id)?.isReadOnly ?? false)
                ]
            )
        }
        try writeFileText(buffer.text, to: tab.fileURL)
        model.markWorkspaceFileBufferSaved(tabID: tab.id, text: buffer.text)
        return .object([
            "mode": .string("buffered-editor-save"),
            "writtenBytes": .int(buffer.text.utf8.count),
            "saveRequested": .bool(false),
            "file": fileTabResult(tab, model: model, includeText: false, maxTextBytes: 0)
        ])
    }

    private func fileSnapshot(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let includeText = request.params["includeText"]?.boolValue ?? false
        let maxTextBytes = Int(try doubleParam(
            "maxTextBytes",
            request.params,
            defaultValue: 64 * 1024,
            lowerBound: 0,
            upperBound: 512 * 1024
        ))
        let explicitTarget = fileTargetString(request.params)
        let tab = explicitTarget == nil && model.selectedWorkspaceFileTab == nil
            ? nil
            : fileTargetTab(request.params, model: model, allowSynthetic: true)
        if explicitTarget != nil && tab == nil {
            throw ConductorControlError.targetNotFound(
                "File target not found.",
                details: ["target": .string(explicitTarget ?? "")]
            )
        }
        return .object([
            "selectedFileTabID": model.selectedWorkspaceFileTab.map { .string($0.id) } ?? .null,
            "fileTabCount": .int(model.workspaceFileTabs.count),
            "fileTabs": .array(model.workspaceFileTabs.map { fileTabResult($0, model: model, includeText: false, maxTextBytes: 0) }),
            "file": tab.map { fileTabResult($0, model: model, includeText: includeText, maxTextBytes: maxTextBytes) } ?? .null
        ])
    }

    private func fileTabResult(
        _ tab: ConductorWorkspaceFileTab,
        model: ConductorWindowModel,
        includeText: Bool,
        maxTextBytes: Int
    ) -> ConductorControlJSON {
        var payload: [String: ConductorControlJSON] = [
            "id": .string(tab.id),
            "title": .string(tab.title),
            "path": .string(tab.fileURL.path),
            "rootPath": .string(tab.rootURL.path),
            "selected": .bool(model.selectedWorkspaceFileTab?.id == tab.id),
            "dirty": .bool(model.isWorkspaceFileTabDirty(tab.id)),
            "externallyChanged": .bool(model.isWorkspaceFileTabExternallyChanged(tab.id)),
            "buffer": fileBufferResult(model.workspaceFileBufferSnapshot(for: tab.id))
        ]
        if let values = try? tab.fileURL.resourceValues(
            forKeys: [.isDirectoryKey, .isReadableKey, .isWritableKey, .fileSizeKey, .contentModificationDateKey]
        ) {
            payload["exists"] = .bool(true)
            payload["isDirectory"] = .bool(values.isDirectory == true)
            payload["isReadable"] = .bool(values.isReadable != false)
            payload["isWritable"] = .bool(values.isWritable != false)
            payload["byteCount"] = .int(values.fileSize ?? 0)
            payload["modifiedAt"] = values.contentModificationDate.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null
        } else {
            payload["exists"] = .bool(false)
            payload["isDirectory"] = .null
            payload["isReadable"] = .null
            payload["isWritable"] = .null
            payload["byteCount"] = .null
            payload["modifiedAt"] = .null
        }
        payload["text"] = includeText ? fileTextSnapshot(tab.fileURL, maxBytes: maxTextBytes) : .null
        return .object(payload)
    }

    private func fileBufferResult(_ buffer: WorkspaceFileBufferSnapshot?) -> ConductorControlJSON {
        guard let buffer else {
            return .object([
                "available": .bool(false),
                "dirty": .bool(false),
                "canSave": .bool(false),
                "isEditable": .bool(false),
                "isReadOnly": .bool(false),
                "byteCount": .int(0),
                "updatedAt": .null,
                "savedRevision": .int(0)
            ])
        }
        return .object([
            "available": .bool(true),
            "dirty": .bool(buffer.isDirty),
            "canSave": .bool(buffer.canSave),
            "isEditable": .bool(buffer.isEditable),
            "isReadOnly": .bool(buffer.isReadOnly),
            "byteCount": .int(buffer.text.utf8.count),
            "updatedAt": .string(Self.iso8601Formatter.string(from: buffer.updatedAt)),
            "savedRevision": .int(buffer.savedRevision)
        ])
    }

    private func fileTextSnapshot(_ fileURL: URL, maxBytes: Int) -> ConductorControlJSON {
        guard maxBytes > 0 else {
            return .object(["included": .bool(false)])
        }
        guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .isReadableKey]),
              values.isDirectory != true,
              values.isReadable != false else {
            return .object([
                "included": .bool(false),
                "error": .string("not_readable")
            ])
        }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: maxTextBytesForRead(maxBytes)) ?? Data()
            guard !data.contains(0) else {
                return .object([
                    "included": .bool(false),
                    "binary": .bool(true)
                ])
            }
            let truncated = (values.fileSize ?? data.count) > maxBytes || data.count > maxBytes
            let visibleData = data.prefix(maxBytes)
            let text = String(data: visibleData, encoding: .utf8)
                ?? String(data: visibleData, encoding: .utf16)
                ?? String(decoding: visibleData, as: UTF8.self)
            return .object([
                "included": .bool(true),
                "binary": .bool(false),
                "truncated": .bool(truncated),
                "bytesRead": .int(visibleData.count),
                "value": .string(text)
            ])
        } catch {
            return .object([
                "included": .bool(false),
                "error": .string(error.localizedDescription)
            ])
        }
    }

    private func maxTextBytesForRead(_ maxBytes: Int) -> Int {
        min(max(maxBytes + 1, 1), 512 * 1024 + 1)
    }

    private func fileTargetTab(
        _ params: [String: ConductorControlJSON],
        model: ConductorWindowModel,
        allowSynthetic: Bool
    ) -> ConductorWorkspaceFileTab? {
        guard let target = fileTargetString(params),
              target != "selected",
              target != "focused" else {
            return model.selectedWorkspaceFileTab
        }
        if let tab = model.workspaceFileTabs.first(where: { $0.id == target || $0.title == target }) {
            return tab
        }
        let fileURL = model.controlResolveFileURL(target)
        if let tab = model.workspaceFileTabs.first(where: { $0.id == fileURL.path }) {
            return tab
        }
        return allowSynthetic ? ConductorWorkspaceFileTab(
            fileURL: fileURL,
            rootURL: fileURL.deletingLastPathComponent()
        ) : nil
    }

    private func requiredFileTargetURL(
        _ params: [String: ConductorControlJSON],
        model: ConductorWindowModel
    ) throws -> URL {
        if let value = params["path"]?.stringValue ?? fileTargetString(params),
           value != "selected",
           value != "focused" {
            return model.controlResolveFileURL(value)
        }
        if let selected = model.selectedWorkspaceFileTab {
            return selected.fileURL
        }
        throw ConductorControlError.targetNotFound("No file path or selected file tab was found.")
    }

    private func optionalFileTargetURL(
        _ params: [String: ConductorControlJSON],
        model: ConductorWindowModel
    ) -> URL? {
        guard let value = fileTargetString(params),
              value != "selected",
              value != "focused" else {
            return model.selectedWorkspaceFileTab?.fileURL
        }
        return model.controlResolveFileURL(value)
    }

    private func fileTargetString(_ params: [String: ConductorControlJSON]) -> String? {
        let value = params["fileTabID"]?.stringValue
            ?? params["target"]?.stringValue
            ?? params["path"]?.stringValue
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func fileURLParam(
        _ key: String,
        _ params: [String: ConductorControlJSON],
        model: ConductorWindowModel
    ) throws -> URL {
        model.controlResolveFileURL(try stringParam(key, params))
    }

    private func optionalFileURLParam(
        _ key: String,
        _ params: [String: ConductorControlJSON],
        model: ConductorWindowModel
    ) throws -> URL? {
        guard let value = params[key]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return model.controlResolveFileURL(value)
    }

    private func fileResourceValues(
        for fileURL: URL,
        keys: Set<URLResourceKey>,
        missingCode: String
    ) throws -> URLResourceValues {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ConductorControlError(
                code: missingCode,
                message: "File does not exist.",
                details: ["path": .string(fileURL.path)]
            )
        }
        do {
            return try fileURL.resourceValues(forKeys: keys)
        } catch {
            throw ConductorControlError(
                code: "file_unavailable",
                message: error.localizedDescription,
                details: ["path": .string(fileURL.path)]
            )
        }
    }

    private func writeFileText(_ text: String, to fileURL: URL) throws {
        let maxBytes = 2 * 1024 * 1024
        let data = Data(text.utf8)
        guard data.count <= maxBytes else {
            throw ConductorControlError(
                code: "file_too_large",
                message: "file.save text is larger than 2 MB.",
                details: ["path": .string(fileURL.path)]
            )
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let values = try fileResourceValues(
                for: fileURL,
                keys: [.isDirectoryKey, .isWritableKey],
                missingCode: "file_not_found"
            )
            guard values.isDirectory != true else {
                throw ConductorControlError(
                    code: "file_is_directory",
                    message: "file.save requires a file path.",
                    details: ["path": .string(fileURL.path)]
                )
            }
            guard values.isWritable != false else {
                throw ConductorControlError(
                    code: "file_not_writable",
                    message: "File is not writable.",
                    details: ["path": .string(fileURL.path)]
                )
            }
        } else {
            let parent = fileURL.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: parent.path) else {
                throw ConductorControlError(
                    code: "file_parent_not_found",
                    message: "Parent directory does not exist.",
                    details: ["path": .string(parent.path)]
                )
            }
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw ConductorControlError(
                code: "file_write_failed",
                message: error.localizedDescription,
                details: ["path": .string(fileURL.path)]
            )
        }
    }

    private func notificationAuthorizationStateResult(_ state: AgentReplyNotificationAuthorizationState) -> String {
        switch state {
        case .unavailable:
            "unavailable"
        case .authorized:
            "authorized"
        case .denied:
            "denied"
        case .notDetermined:
            "not-determined"
        case .unknown:
            "unknown"
        }
    }

    private func sessionJournalSummaryResult(_ summary: ConductorSessionJournalSummary) -> ConductorControlJSON {
        .object([
            "entryCount": .int(summary.entryCount),
            "fileSizeBytes": .int(summary.fileSizeBytes),
            "latestEvent": summary.latestEvent.map(sessionJournalEventResult) ?? .null
        ])
    }

    private func sessionRestoreReportResult(_ report: WorkspacePersistenceLoadReport) -> ConductorControlJSON {
        .object([
            "state": .string(report.state.rawValue),
            "sourcePath": report.sourcePath.map { .string($0) } ?? .null,
            "attemptedPaths": .array(report.attemptedPaths.map { .string($0) }),
            "failedPaths": .array(report.failedPaths.map { .string($0) }),
            "originalWorkspaceCount": .int(report.originalWorkspaceCount),
            "restoredWorkspaceCount": .int(report.restoredWorkspaceCount),
            "droppedWorkspaceCount": .int(report.droppedWorkspaceCount),
            "originalWebTabCount": .int(report.originalWebTabCount),
            "restoredWebTabCount": .int(report.restoredWebTabCount),
            "droppedWebTabCount": .int(report.droppedWebTabCount),
            "originalFileTabCount": .int(report.originalFileTabCount),
            "restoredFileTabCount": .int(report.restoredFileTabCount),
            "droppedFileTabCount": .int(report.droppedFileTabCount),
            "missingFilePaths": .array(report.missingFilePaths.map { .string($0) }),
            "message": .string(report.message)
        ])
    }

    private func sessionJournalEventResult(_ event: ConductorSessionJournalEvent) -> ConductorControlJSON {
        .object([
            "id": .string(event.id.uuidString),
            "timestamp": .string(Self.iso8601Formatter.string(from: event.timestamp)),
            "kind": .string(event.kind.rawValue),
            "selectedWorkspaceID": event.selectedWorkspaceID.map { .string($0.description) } ?? .null,
            "workspaceID": event.workspaceID.map { .string($0.description) } ?? .null,
            "paneID": event.paneID.map { .string($0.description) } ?? .null,
            "terminalID": event.terminalID.map { .string($0.description) } ?? .null,
            "webTabID": event.webTabID.map { .string($0.rawValue.uuidString) } ?? .null,
            "workspaceCount": .int(event.workspaceCount),
            "terminalCount": .int(event.terminalCount),
            "webTabCount": .int(event.webTabCount),
            "fileTabCount": .int(event.fileTabCount),
            "details": .object(event.details.mapValues { .string($0) })
        ])
    }

    private func workspaceListResult(model: ConductorWindowModel) -> ConductorControlJSON {
        .object([
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
            "workspaces": .array(model.workspaces.map { workspaceJSON($0, selectedID: model.controlSelectedWorkspaceID) })
        ])
    }

    private func workspaceMetadata(
        request: ConductorControlRequest,
        model: ConductorWindowModel
    ) async throws -> ConductorControlJSON {
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        let contexts = model.controlWorkspaceMetadataContexts()
        let filteredContexts: [ConductorWorkspaceMetadataContext]
        if let workspaceID {
            filteredContexts = contexts.filter { $0.workspaceID == workspaceID }
            guard !filteredContexts.isEmpty else {
                throw ConductorControlError.targetNotFound(
                    "Workspace not found.",
                    details: ["workspaceID": .string(workspaceID.description)]
                )
            }
        } else {
            filteredContexts = contexts
        }
        let snapshots = await ConductorWorkspaceMetadataService.snapshots(for: filteredContexts)
        return .object([
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
            "workspaceCount": .int(snapshots.count),
            "workspaces": .array(snapshots.map(workspaceMetadataResult))
        ])
    }

    private func workspaceMetadataResult(_ snapshot: WorkspaceMetadataSnapshot) -> ConductorControlJSON {
        .object([
            "id": .string(snapshot.workspaceID.description),
            "title": .string(snapshot.title),
            "selected": .bool(snapshot.selected),
            "rootPath": snapshot.rootPath.map { .string($0) } ?? .null,
            "rootSource": .string(snapshot.rootSource),
            "projectName": .string(snapshot.projectName),
            "counts": .object([
                "paneCount": .int(snapshot.counts.paneCount),
                "terminalCount": .int(snapshot.counts.terminalCount),
                "webTabCount": .int(snapshot.counts.webTabCount),
                "fileTabCount": .int(snapshot.counts.fileTabCount)
            ]),
            "runningPorts": .array(snapshot.runningPorts.map { .int($0) }),
            "devServers": .array(snapshot.devServers.map(workspaceDevServerMetadataResult)),
            "portScanState": .string(snapshot.portScanState),
            "activeAgentCount": .int(snapshot.activeAgentCount),
            "unreadCount": .int(snapshot.unreadCount),
            "terminals": .array(snapshot.terminals.map(workspaceTerminalMetadataResult)),
            "files": .array(snapshot.files.map(workspaceFileMetadataResult)),
            "webTabs": .array(snapshot.webTabs.map(workspaceWebMetadataResult)),
            "health": .string(snapshot.health),
            "refreshedAt": .string(Self.iso8601Formatter.string(from: snapshot.refreshedAt))
        ])
    }

    private func workspaceTerminalMetadataResult(_ summary: WorkspaceMetadataSnapshot.TerminalSummary) -> ConductorControlJSON {
        .object([
            "id": .string(summary.id.description),
            "paneID": .string(summary.paneID.description),
            "title": .string(summary.title),
            "workingDirectory": summary.workingDirectory.map { .string($0) } ?? .null,
            "selected": .bool(summary.selected),
            "activeAgentTitle": summary.activeAgentTitle.map { .string($0) } ?? .null,
            "activeAgentStartedAt": summary.activeAgentStartedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "agentState": summary.agentState.map { .string($0) } ?? .null,
            "agentUpdatedAt": summary.agentUpdatedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "lastCommandExitCode": summary.lastCommandExitCode.map { .int($0) } ?? .null,
            "lastCommandDurationNanoseconds": summary.lastCommandDurationNanoseconds.map { .int(Int($0)) } ?? .null,
            "lastCommandFinishedAt": summary.lastCommandFinishedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "searchActive": .bool(summary.searchActive),
            "searchNeedle": summary.searchNeedle.map { .string($0) } ?? .null,
            "searchTotal": summary.searchTotal.map { .int($0) } ?? .null,
            "searchSelected": summary.searchSelected.map { .int($0) } ?? .null,
            "readonly": .bool(summary.readonly)
        ])
    }

    private func workspaceDevServerMetadataResult(_ summary: WorkspaceMetadataSnapshot.DevServerSummary) -> ConductorControlJSON {
        .object([
            "port": .int(summary.port),
            "url": .string(summary.url),
            "label": .string(summary.label),
            "processID": summary.processID.map { .int($0) } ?? .null,
            "processName": summary.processName.map { .string($0) } ?? .null,
            "workingDirectory": summary.workingDirectory.map { .string($0) } ?? .null
        ])
    }

    private func workspaceFileMetadataResult(_ summary: WorkspaceMetadataSnapshot.FileSummary) -> ConductorControlJSON {
        .object([
            "id": .string(summary.id),
            "title": .string(summary.title),
            "path": .string(summary.path),
            "rootPath": .string(summary.rootPath),
            "selected": .bool(summary.selected),
            "dirty": .bool(summary.dirty)
        ])
    }

    private func workspaceWebMetadataResult(_ summary: WorkspaceMetadataSnapshot.WebSummary) -> ConductorControlJSON {
        .object([
            "id": .string(summary.id.rawValue.uuidString),
            "title": summary.title.map { .string($0) } ?? .null,
            "url": summary.url.map { .string($0) } ?? .null,
            "pendingAddress": .string(summary.pendingAddress),
            "selected": .bool(summary.selected),
            "loading": .bool(summary.loading),
            "errorMessage": summary.errorMessage.map { .string($0) } ?? .null
        ])
    }

    private func workspaceJSON(_ workspace: WorkspaceState, selectedID: WorkspaceID) -> ConductorControlJSON {
        let panes = workspace.root.leaves.compactMap { paneID -> ConductorControlJSON? in
            guard let pane = workspace.panes[paneID] else { return nil }
            return .object([
                "id": .string(pane.id.description),
                "selectedTerminalID": .string(pane.selectedTabID.description),
                "terminals": .array(pane.tabs.map { tab in
                    .object([
                        "id": .string(tab.id.description),
                        "title": .string(tab.title),
                        "userTitle": tab.userTitle.map { .string($0) } ?? .null,
                        "workingDirectory": tab.workingDirectory.map { .string($0) } ?? .null,
                        "selected": .bool(tab.id == pane.selectedTabID)
                    ])
                })
            ])
        }
        return .object([
            "id": .string(workspace.id.description),
            "title": .string(workspace.title),
            "selected": .bool(workspace.id == selectedID),
            "focusedPaneID": .string(workspace.focusedPaneID.description),
            "zoomed": .bool(workspace.isZoomed),
            "paneCount": .int(workspace.panes.count),
            "terminalCount": .int(workspace.panes.values.reduce(0) { $0 + $1.tabs.count }),
            "panes": .array(panes)
        ])
    }

    private func createWorkspace(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let title = request.params["title"]?.stringValue
        let id = model.controlCreateWorkspace(title: title)
        return .object([
            "workspaceID": .string(id.description),
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description)
        ])
    }

    private func selectWorkspace(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let workspaceID = try workspaceIDParam(request.params)
        guard model.activateWorkspace(workspaceID, source: .programmatic) else {
            throw ConductorControlError.targetNotFound(
                "Workspace not found.",
                details: ["workspaceID": .string(workspaceID.description)]
            )
        }
        return .object([
            "workspaceID": .string(workspaceID.description),
            "selected": .bool(true)
        ])
    }

    private func renameWorkspace(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let title = try stringParam("title", request.params)
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        guard model.controlRenameWorkspace(workspaceID, title: title) else {
            throw ConductorControlError.targetNotFound(
                "Workspace not found.",
                details: workspaceID.map { ["workspaceID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "workspaceID": .string((workspaceID ?? model.controlSelectedWorkspaceID).description),
            "title": .string(title)
        ])
    }

    private func closeWorkspace(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        let targetID = workspaceID ?? model.controlSelectedWorkspaceID
        guard model.controlCloseWorkspace(workspaceID) else {
            throw ConductorControlError.commandDisabled(
                "Workspace cannot be closed.",
                details: workspaceID.map { ["workspaceID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "closedWorkspaceID": .string(targetID.description),
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description)
        ])
    }

    private func duplicateWorkspace(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        let sourceID = workspaceID ?? model.controlSelectedWorkspaceID
        guard let duplicatedID = model.controlDuplicateWorkspace(workspaceID) else {
            throw ConductorControlError.targetNotFound(
                "Workspace not found.",
                details: workspaceID.map { ["workspaceID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "sourceWorkspaceID": .string(sourceID.description),
            "workspaceID": .string(duplicatedID.description),
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description)
        ])
    }

    private func surfaceListResult(model: ConductorWindowModel) -> ConductorControlJSON {
        var surfaces: [ConductorControlJSON] = []
        for workspace in model.workspaces {
            for paneID in workspace.root.leaves {
                guard let pane = workspace.panes[paneID] else { continue }
                for tab in pane.tabs {
                    surfaces.append(.object([
                        "type": .string("terminal"),
                        "id": .string(tab.id.description),
                        "terminalID": .string(tab.id.description),
                        "workspaceID": .string(workspace.id.description),
                        "paneID": .string(pane.id.description),
                        "title": .string(tab.title),
                        "selected": .bool(workspace.id == model.controlSelectedWorkspaceID && pane.selectedTabID == tab.id),
                        "focused": .bool(workspace.id == model.controlSelectedWorkspaceID && model.focusedTerminalID == tab.id),
                        "workingDirectory": tab.workingDirectory.map { .string($0) } ?? .null
                    ]))
                }
            }
        }
        for tab in model.workspaceWebTabs {
            surfaces.append(.object([
                "type": .string("browser"),
                "id": .string(tab.id.rawValue.uuidString),
                "webTabID": .string(tab.id.rawValue.uuidString),
                "title": .string(tab.displayTitle),
                "url": tab.url.map { .string($0.absoluteString) } ?? .null,
                "selected": .bool(model.selectedWorkspaceWebTabID == tab.id),
                "loading": .bool(tab.isLoading),
                "canGoBack": .bool(tab.canGoBack),
                "canGoForward": .bool(tab.canGoForward),
                "historyCount": .int(tab.navigationEntries.count),
                "historyIndex": tab.currentNavigationIndex.map { .int($0) } ?? .null,
                "scrollY": tab.scrollY.map { .double($0) } ?? .null,
                "download": tab.downloadState.map(webDownloadStateResult) ?? .null,
                "runtimeEventCount": .int(tab.runtimeEvents.count),
                "latestRuntimeEvent": tab.runtimeEvents.last.map(webRuntimeEventResult) ?? .null
            ]))
        }
        for tab in model.workspaceFileTabs {
            surfaces.append(.object([
                "type": .string("file"),
                "id": .string(tab.id),
                "title": .string(tab.title),
                "path": .string(tab.fileURL.path),
                "selected": .bool(model.selectedWorkspaceFileTabID == tab.id)
            ]))
        }
        return .object([
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
            "focusedTerminalID": model.focusedTerminalID.map { .string($0.description) } ?? .null,
            "surfaces": .array(surfaces)
        ])
    }

    private func webDownloadStateResult(_ state: WorkspaceWebDownloadState) -> ConductorControlJSON {
        var payload: [String: ConductorControlJSON] = [
            "phase": .string(state.phase.rawValue),
            "filename": .string(state.filename),
            "updatedAt": .string(Self.iso8601Formatter.string(from: state.updatedAt))
        ]
        payload["destinationPath"] = state.destinationPath.map { .string($0) } ?? .null
        payload["errorMessage"] = state.errorMessage.map { .string($0) } ?? .null
        return .object(payload)
    }

    private func focusSurface(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let surfaceType = request.params["type"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        if let webTabID = try optionalWebTabIDParam(request.params) {
            guard model.controlSelectBrowser(webTabID: webTabID, workspaceID: workspaceID) else {
                throw ConductorControlError.targetNotFound(
                    "Browser surface not found.",
                    details: ["webTabID": .string(webTabID.rawValue.uuidString)]
                )
            }
            return .object([
                "type": .string("browser"),
                "webTabID": .string(webTabID.rawValue.uuidString),
                "workspaceID": .string(model.controlSelectedWorkspaceID.description),
                "focused": .bool(true)
            ])
        }
        if let fileTabID = request.params["fileTabID"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fileTabID.isEmpty {
            guard model.controlSelectFileTab(fileTabID, workspaceID: workspaceID) else {
                throw ConductorControlError.targetNotFound(
                    "File surface not found.",
                    details: ["fileTabID": .string(fileTabID)]
                )
            }
            return .object([
                "type": .string("file"),
                "fileTabID": .string(model.selectedWorkspaceFileTabID ?? fileTabID),
                "workspaceID": .string(model.controlSelectedWorkspaceID.description),
                "focused": .bool(true)
            ])
        }
        if surfaceType == "browser" || surfaceType == "web" {
            throw ConductorControlError.invalidParams(
                "Browser surface focus requires webTabID.",
                details: ["parameter": .string("webTabID")]
            )
        }
        if surfaceType == "file" {
            throw ConductorControlError.invalidParams(
                "File surface focus requires fileTabID.",
                details: ["parameter": .string("fileTabID")]
            )
        }
        let terminalID = try optionalTerminalIDParam(request.params)
        guard model.controlFocusTerminal(terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal surface not found.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "type": .string("terminal"),
            "terminalID": (terminalID ?? model.focusedTerminalID).map { .string($0.description) } ?? .null,
            "workspaceID": .string(model.controlSelectedWorkspaceID.description),
            "focused": .bool(true)
        ])
    }

    private func splitSurface(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let rawDirection = request.params["direction"]?.stringValue ?? "right"
        guard let direction = SplitDirection(rawValue: rawDirection) else {
            throw ConductorControlError.invalidParams(
                "direction must be one of left, right, up, or down.",
                details: ["direction": .string(rawDirection)]
            )
        }
        guard let result = model.controlSplitSurface(direction: direction) else {
            throw ConductorControlError.commandDisabled("Surface cannot be split in the current context.")
        }
        return .object([
            "direction": .string(direction.rawValue),
            "paneID": .string(result.paneID.description),
            "terminalID": .string(result.terminalID.description)
        ])
    }

    private func closeSurface(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        guard model.controlCloseSurface(terminalID: terminalID) else {
            throw ConductorControlError.commandDisabled(
                "Surface cannot be closed.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": terminalID.map { .string($0.description) } ?? .null,
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description)
        ])
    }

    private func zoomSurface(model: ConductorWindowModel) throws -> ConductorControlJSON {
        guard model.controlToggleSurfaceZoom() else {
            throw ConductorControlError.commandDisabled("Surface zoom requires more than one pane.")
        }
        return .object([
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
            "zoomed": .bool(model.workspace.isZoomed)
        ])
    }

    private func moveSurface(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let mode = try stringParam("mode", request.params)
        guard model.controlMoveSurface(mode: mode) else {
            throw ConductorControlError.commandDisabled(
                "Surface cannot be moved in the requested mode.",
                details: ["mode": .string(mode)]
            )
        }
        return .object([
            "mode": .string(mode),
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description),
            "focusedTerminalID": model.focusedTerminalID.map { .string($0.description) } ?? .null
        ])
    }

    private func sendTerminalText(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let text = try stringParam("text", request.params)
        let terminalID = try optionalTerminalIDParam(request.params)
        guard model.controlSendText(text, terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found or unavailable for input.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": (terminalID ?? model.focusedTerminalID).map { .string($0.description) } ?? .null,
            "bytes": .int(text.utf8.count)
        ])
    }

    private func visibleTerminalText(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        guard let text = model.controlVisibleText(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found or visible text unavailable.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": (terminalID ?? model.focusedTerminalID).map { .string($0.description) } ?? .null,
            "text": .string(text)
        ])
    }

    private func sendTerminalKey(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let key = try stringParam("key", request.params)
        let terminalID = try optionalTerminalIDParam(request.params)
        guard model.controlSendKey(key, terminalID: terminalID) else {
            throw ConductorControlError.invalidParams(
                "Unsupported key or terminal not found.",
                details: [
                    "key": .string(key),
                    "terminalID": terminalID.map { .string($0.description) } ?? .null
                ]
            )
        }
        return .object([
            "terminalID": (terminalID ?? model.focusedTerminalID).map { .string($0.description) } ?? .null,
            "key": .string(key)
        ])
    }

    private func sampleTerminalScroll(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        guard let sample = model.controlSampleTerminalScroll(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found or unavailable for scroll sampling.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": (terminalID ?? model.focusedTerminalID).map { .string($0.description) } ?? .null,
            "sample": performanceBudgetSampleResult(sample)
        ])
    }

    private func terminalCwd(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        guard let info = model.controlTerminalInfo(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": .string(info.tab.id.description),
            "workspaceID": .string(info.workspaceID.description),
            "paneID": .string(info.paneID.description),
            "cwd": info.cwd.map { .string($0.path) } ?? .null,
            "rawWorkingDirectory": info.tab.workingDirectory.map { .string($0) } ?? .null
        ])
    }

    private func terminalTitle(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        guard let info = model.controlTerminalInfo(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": .string(info.tab.id.description),
            "workspaceID": .string(info.workspaceID.description),
            "paneID": .string(info.paneID.description),
            "title": .string(info.tab.title),
            "userTitle": info.tab.userTitle.map { .string($0) } ?? .null
        ])
    }

    private func renameTerminal(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let title = try stringParam("title", request.params)
        let terminalID = try optionalTerminalIDParam(request.params)
        guard model.controlRenameTerminal(terminalID, title: title) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found or title was empty.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        guard let info = model.controlTerminalInfo(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Renamed terminal could not be read back.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": .string(info.tab.id.description),
            "workspaceID": .string(info.workspaceID.description),
            "paneID": .string(info.paneID.description),
            "title": .string(info.tab.title),
            "userTitle": info.tab.userTitle.map { .string($0) } ?? .null
        ])
    }

    private func terminalAgent(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        _ = model.controlRefreshTerminalAgentResumeMetadata(terminalID: terminalID)
        guard let info = model.controlTerminalInfo(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "terminalID": .string(info.tab.id.description),
            "workspaceID": .string(info.workspaceID.description),
            "paneID": .string(info.paneID.description),
            "agent": terminalAgentSnapshotResult(info.tab.agentSnapshot)
        ])
    }

    private func resumeTerminalAgent(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let terminalID = try optionalTerminalIDParam(request.params)
        guard let info = model.controlTerminalInfo(terminalID: terminalID) else {
            throw ConductorControlError.targetNotFound(
                "Terminal not found.",
                details: terminalID.map { ["terminalID": .string($0.description)] } ?? [:]
            )
        }
        guard let resumeCommand = model.controlTerminalAgentResumeCommand(terminalID: info.tab.id) else {
            throw ConductorControlError.commandDisabled(
                "Terminal has no supported agent resume command.",
                details: [
                    "terminalID": .string(info.tab.id.description),
                    "agent": terminalAgentSnapshotResult(info.tab.agentSnapshot)
                ]
            )
        }
        let updatedInfo = model.controlTerminalInfo(terminalID: info.tab.id) ?? info
        let dryRun = request.params["dryRun"]?.boolValue ?? false
        if dryRun {
            return .object([
                "terminalID": .string(updatedInfo.tab.id.description),
                "workspaceID": .string(updatedInfo.workspaceID.description),
                "paneID": .string(updatedInfo.paneID.description),
                "sent": .bool(false),
                "dryRun": .bool(true),
                "resumeCommand": .string(resumeCommand),
                "agent": terminalAgentSnapshotResult(updatedInfo.tab.agentSnapshot)
            ])
        }
        guard model.controlResumeTerminalAgent(terminalID: updatedInfo.tab.id) else {
            throw ConductorControlError.commandDisabled(
                "Terminal agent resume command could not be sent.",
                details: ["terminalID": .string(updatedInfo.tab.id.description)]
            )
        }
        return .object([
            "terminalID": .string(updatedInfo.tab.id.description),
            "workspaceID": .string(updatedInfo.workspaceID.description),
            "paneID": .string(updatedInfo.paneID.description),
            "sent": .bool(true),
            "dryRun": .bool(false),
            "resumeCommand": .string(resumeCommand),
            "agent": terminalAgentSnapshotResult(updatedInfo.tab.agentSnapshot)
        ])
    }

    private func resumeTerminalAgents(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        let scope = request.params["scope"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let includeAllWorkspaces = request.params["allWorkspaces"]?.boolValue == true || scope == "all"
        let dryRun = request.params["dryRun"]?.boolValue ?? false
        let results = model.controlResumeTerminalAgents(
            workspaceID: workspaceID,
            includeAllWorkspaces: includeAllWorkspaces,
            dryRun: dryRun
        )
        let sentCount = results.filter(\.sent).count
        return .object([
            "scope": .string(includeAllWorkspaces ? "all" : "workspace"),
            "workspaceID": workspaceID.map { .string($0.description) } ?? (includeAllWorkspaces ? .null : .string(model.controlSelectedWorkspaceID.description)),
            "dryRun": .bool(dryRun),
            "targetCount": .int(results.count),
            "sentCount": .int(sentCount),
            "skippedCount": .int(results.count - sentCount),
            "results": .array(results.map(terminalAgentResumeBatchResult))
        ])
    }

    private func terminalAgentResumeBatchResult(_ result: TerminalAgentResumeBatchResult) -> ConductorControlJSON {
        .object([
            "workspaceID": .string(result.target.workspaceID.description),
            "paneID": .string(result.target.paneID.description),
            "terminalID": .string(result.target.terminalID.description),
            "terminalTitle": .string(result.target.terminalTitle),
            "providerID": result.target.providerID.map { .string($0) } ?? .null,
            "displayName": .string(result.target.displayName),
            "sent": .bool(result.sent),
            "dryRun": .bool(result.dryRun),
            "resumeCommand": .string(result.target.resumeCommand),
            "failureReason": result.failureReason.map { .string($0) } ?? .null,
            "agent": terminalAgentSnapshotResult(result.target.agentSnapshot)
        ])
    }

    private func terminalAgentSnapshotResult(_ snapshot: TerminalAgentSnapshot?) -> ConductorControlJSON {
        guard let snapshot else {
            return .object([
                "available": .bool(false),
                "resumable": .bool(false),
                "providerID": .null,
                "displayName": .null,
                "state": .null,
                "sessionIdentifier": .null,
                "resumeCommand": .null,
                "lastEvent": .null,
                "startedAt": .null,
                "updatedAt": .null
            ])
        }
        return .object([
            "available": .bool(true),
            "resumable": .bool(snapshot.resumeCommand != nil && snapshot.sessionIdentifier != nil),
            "providerID": snapshot.providerID.map { .string($0) } ?? .null,
            "displayName": .string(snapshot.displayName),
            "state": .string(snapshot.state.rawValue),
            "sessionIdentifier": snapshot.sessionIdentifier.map { .string($0) } ?? .null,
            "resumeCommand": snapshot.resumeCommand.map { .string($0) } ?? .null,
            "lastEvent": snapshot.lastEvent.map { .string($0) } ?? .null,
            "startedAt": snapshot.startedAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "updatedAt": .string(Self.iso8601Formatter.string(from: snapshot.updatedAt))
        ])
    }

    private func openBrowser(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let input = try stringParam("input", request.params)
        guard let tabID = model.controlOpenBrowser(input: input) else {
            throw ConductorControlError.commandDisabled("Could not open a browser tab.")
        }
        return .object([
            "webTabID": .string(tabID.rawValue.uuidString),
            "input": .string(input)
        ])
    }

    private func selectBrowser(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let webTabID = try webTabIDParam(request.params)
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        guard model.controlSelectBrowser(webTabID: webTabID, workspaceID: workspaceID) else {
            throw ConductorControlError.targetNotFound(
                "Browser tab not found.",
                details: [
                    "webTabID": .string(webTabID.rawValue.uuidString),
                    "workspaceID": workspaceID.map { .string($0.description) } ?? .null
                ]
            )
        }
        return .object([
            "selected": .bool(true),
            "webTabID": .string(webTabID.rawValue.uuidString),
            "selectedWorkspaceID": .string(model.controlSelectedWorkspaceID.description)
        ])
    }

    private func navigateBrowser(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let input = try stringParam("input", request.params)
        let webTabID = try optionalWebTabIDParam(request.params)
        guard model.controlNavigateBrowser(input: input, webTabID: webTabID) else {
            throw ConductorControlError.targetNotFound(
                "Browser tab not found.",
                details: webTabID.map { ["webTabID": .string($0.rawValue.uuidString)] } ?? [:]
            )
        }
        return .object([
            "webTabID": (webTabID ?? model.selectedWorkspaceWebTabID).map { .string($0.rawValue.uuidString) } ?? .null,
            "input": .string(input)
        ])
    }

    private func browserAction(
        request: ConductorControlRequest,
        model: ConductorWindowModel,
        methodName: String,
        perform: (WebTabID?) -> Bool
    ) throws -> ConductorControlJSON {
        let webTabID = try optionalWebTabIDParam(request.params)
        guard perform(webTabID) else {
            throw ConductorControlError.targetNotFound(
                "Browser tab not found.",
                details: webTabID.map { ["webTabID": .string($0.rawValue.uuidString)] } ?? [:]
            )
        }
        return .object([
            "action": .string(methodName),
            "webTabID": (webTabID ?? model.selectedWorkspaceWebTabID).map { .string($0.rawValue.uuidString) } ?? .null
        ])
    }

    private func browserSnapshot(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let snapshot = try await model.controlBrowserSnapshot(webTabID: webTabID)
            return browserSnapshotResult(snapshot)
        } catch ConductorBrowserSnapshotError.targetNotFound {
            throw ConductorControlError.targetNotFound(
                "Browser tab not found.",
                details: webTabID.map { ["webTabID": .string($0.rawValue.uuidString)] } ?? [:]
            )
        } catch ConductorBrowserSnapshotError.pageUnavailable {
            throw ConductorControlError.commandDisabled(
                "Browser tab has not loaded a page surface yet.",
                details: webTabID.map { ["webTabID": .string($0.rawValue.uuidString)] } ?? [:]
            )
        }
    }

    private func browserSnapshotResult(_ snapshot: ConductorBrowserSnapshot) -> ConductorControlJSON {
        .object([
            "webTabID": .string(snapshot.webTabID.rawValue.uuidString),
            "title": .string(snapshot.title),
            "url": .string(snapshot.url),
            "text": .string(snapshot.text),
            "selectedText": .string(snapshot.selectedText),
            "runtimeEvents": .array(snapshot.runtimeEvents.map(webRuntimeEventResult)),
            "links": .array(snapshot.links.map { link in
                .object([
                    "id": .string(link.id),
                    "text": .string(link.text),
                    "href": .string(link.href)
                ])
            }),
            "fields": .array(snapshot.fields.map { field in
                .object([
                    "id": .string(field.id),
                    "tag": .string(field.tag),
                    "type": .string(field.type),
                    "name": .string(field.name),
                    "placeholder": .string(field.placeholder),
                    "label": .string(field.label),
                    "value": .string(field.value)
                ])
            }),
            "buttons": .array(snapshot.buttons.map { button in
                .object([
                    "id": .string(button.id),
                    "text": .string(button.text)
                ])
            }),
            "frames": .array(snapshot.frames.map { frame in
                .object([
                    "id": .string(frame.id),
                    "title": .string(frame.title),
                    "name": .string(frame.name),
                    "url": .string(frame.url),
                    "source": .string(frame.source),
                    "accessible": .bool(frame.accessible),
                    "sameOrigin": .bool(frame.sameOrigin),
                    "visible": .bool(frame.visible),
                    "text": .string(frame.text),
                    "linkCount": .int(frame.linkCount),
                    "fieldCount": .int(frame.fieldCount),
                    "buttonCount": .int(frame.buttonCount),
                    "reason": .string(frame.reason)
                ])
            })
        ])
    }

    private func webRuntimeEventResult(_ event: WorkspaceWebRuntimeEvent) -> ConductorControlJSON {
        .object([
            "kind": .string(event.kind.rawValue),
            "level": .string(event.level),
            "message": .string(event.message),
            "sourceURL": event.sourceURL.map { .string($0) } ?? .null,
            "lineNumber": event.lineNumber.map { .int($0) } ?? .null,
            "columnNumber": event.columnNumber.map { .int($0) } ?? .null,
            "occurredAt": .string(Self.iso8601Formatter.string(from: event.occurredAt))
        ])
    }

    private func browserScreenshot(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let screenshot = try await model.controlBrowserScreenshot(webTabID: webTabID)
            return browserScreenshotResult(screenshot)
        } catch ConductorBrowserSnapshotError.targetNotFound {
            throw ConductorControlError.targetNotFound(
                "Browser tab not found.",
                details: webTabID.map { ["webTabID": .string($0.rawValue.uuidString)] } ?? [:]
            )
        } catch ConductorBrowserSnapshotError.pageUnavailable {
            throw ConductorControlError.commandDisabled(
                "Browser tab has not loaded a page surface yet.",
                details: webTabID.map { ["webTabID": .string($0.rawValue.uuidString)] } ?? [:]
            )
        } catch ConductorBrowserSnapshotError.captureFailed(let message) {
            throw ConductorControlError.commandDisabled(
                "Browser screenshot failed.",
                details: [
                    "reason": .string(message),
                    "webTabID": webTabID.map { .string($0.rawValue.uuidString) } ?? .null
                ]
            )
        } catch ConductorBrowserSnapshotError.writeFailed(let message) {
            throw ConductorControlError.commandDisabled(
                "Browser screenshot could not be saved.",
                details: [
                    "reason": .string(message),
                    "webTabID": webTabID.map { .string($0.rawValue.uuidString) } ?? .null
                ]
            )
        }
    }

    private func browserScreenshotResult(_ screenshot: ConductorBrowserScreenshot) -> ConductorControlJSON {
        .object([
            "webTabID": .string(screenshot.webTabID.rawValue.uuidString),
            "title": .string(screenshot.title),
            "url": .string(screenshot.url),
            "path": .string(screenshot.path),
            "width": .int(screenshot.width),
            "height": .int(screenshot.height),
            "scale": .double(screenshot.scale)
        ])
    }

    private func browserClick(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let target = try stringParam("target", request.params)
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let result = try await model.controlBrowserClick(webTabID: webTabID, target: target)
            return browserAutomationResult(result)
        } catch let error as ConductorBrowserSnapshotError {
            throw browserControlError(error, webTabID: webTabID)
        }
    }

    private func browserFill(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let target = try stringParam("target", request.params)
        let value = request.params["value"]?.stringValue ?? ""
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let result = try await model.controlBrowserFill(webTabID: webTabID, target: target, value: value)
            return browserAutomationResult(result)
        } catch let error as ConductorBrowserSnapshotError {
            throw browserControlError(error, webTabID: webTabID)
        }
    }

    private func browserPress(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let key = try stringParam("key", request.params)
        let target = request.params["target"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let result = try await model.controlBrowserPress(
                webTabID: webTabID,
                key: key,
                target: target?.isEmpty == false ? target : nil
            )
            return browserAutomationResult(result)
        } catch let error as ConductorBrowserSnapshotError {
            throw browserControlError(error, webTabID: webTabID)
        }
    }

    private func browserWait(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let condition = (request.params["condition"]?.stringValue ?? "selector")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let target = request.params["target"]?.stringValue ?? ""
        let allowedConditions = Set([
            "selector",
            "element",
            "visible",
            "text",
            "load",
            "ready",
            "idle",
            "networkidle",
            "url",
            "title",
            "hidden",
            "gone",
            "detached"
        ])
        guard allowedConditions.contains(condition) else {
            throw ConductorControlError.invalidParams(
                "Unknown browser wait condition.",
                details: ["condition": .string(condition)]
            )
        }
        let targetlessConditions = Set(["load", "ready", "idle", "networkidle"])
        if !targetlessConditions.contains(condition),
           target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ConductorControlError.invalidParams(
                "Browser wait requires a target for this condition.",
                details: ["condition": .string(condition)]
            )
        }

        let timeoutSeconds = try doubleParam(
            "timeoutSeconds",
            request.params,
            defaultValue: 5,
            lowerBound: 0.1,
            upperBound: 30
        )
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let result = try await model.controlBrowserWait(
                webTabID: webTabID,
                condition: condition,
                target: target,
                timeoutSeconds: timeoutSeconds
            )
            return browserAutomationResult(result)
        } catch let error as ConductorBrowserSnapshotError {
            throw browserControlError(error, webTabID: webTabID)
        }
    }

    private func browserFind(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let query = try stringParam("query", request.params)
        let frameID = request.params["frameID"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let result = try await model.controlBrowserFind(
                webTabID: webTabID,
                query: query,
                frameID: frameID?.isEmpty == false ? frameID : nil
            )
            return browserAutomationResult(result)
        } catch let error as ConductorBrowserSnapshotError {
            throw browserControlError(error, webTabID: webTabID)
        }
    }

    private func browserEvaluate(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let script = try stringParam("script", request.params)
        let frameID = request.params["frameID"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        let webTabID = try optionalWebTabIDParam(request.params)
        do {
            let result = try await model.controlBrowserEvaluate(
                webTabID: webTabID,
                script: script,
                frameID: frameID?.isEmpty == false ? frameID : nil
            )
            return browserAutomationResult(result)
        } catch let error as ConductorBrowserSnapshotError {
            throw browserControlError(error, webTabID: webTabID)
        }
    }

    private func browserAutomationResult(_ result: ConductorBrowserAutomationResult) -> ConductorControlJSON {
        var object: [String: ConductorControlJSON] = [
            "webTabID": .string(result.webTabID.rawValue.uuidString),
            "action": .string(result.action),
            "title": .string(result.title),
            "url": .string(result.url),
            "target": .string(result.target),
            "matched": .bool(result.matched),
            "message": .string(result.message),
            "text": .string(result.text),
            "value": .string(result.value)
        ]
        if let matches = result.matches {
            object["matches"] = .int(matches)
        }
        if let scriptResult = result.result {
            object["result"] = .string(scriptResult)
        }
        if let resultType = result.resultType {
            object["resultType"] = .string(resultType)
        }
        if let errorCode = result.errorCode {
            object["errorCode"] = .string(errorCode)
        }
        return .object(object)
    }

    private func browserControlError(
        _ error: ConductorBrowserSnapshotError,
        webTabID: WebTabID?
    ) -> ConductorControlError {
        let details = webTabID.map { ["webTabID": ConductorControlJSON.string($0.rawValue.uuidString)] } ?? [:]
        switch error {
        case .targetNotFound:
            return .targetNotFound("Browser tab not found.", details: details)
        case .pageUnavailable:
            return .commandDisabled("Browser tab has not loaded a page surface yet.", details: details)
        case .captureFailed(let message):
            return .commandDisabled("Browser screenshot failed.", details: details.merging(["reason": .string(message)]) { current, _ in current })
        case .writeFailed(let message):
            return .commandDisabled("Browser screenshot could not be saved.", details: details.merging(["reason": .string(message)]) { current, _ in current })
        case .automationFailed(let message, let code):
            var errorDetails = details
            errorDetails["reason"] = .string(message)
            if let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorDetails["automationError"] = .string(code)
            }
            return .commandDisabled("Browser automation failed.", details: errorDetails)
        }
    }

    private func createNotification(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let title = try stringParam("title", request.params)
        let body = request.params["body"]?.stringValue ?? ""
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        let terminalID = try optionalTerminalIDParam(request.params)
        let webTabID = try optionalWebTabIDParam(request.params)
        let event = model.controlCreateAttentionEvent(
            title: title,
            body: body,
            workspaceID: workspaceID,
            terminalID: terminalID,
            webTabID: webTabID,
            source: "control"
        )
        ConductorDiagnostics.record(
            "control-notification-create",
            fields: [
                "id": event.id.uuidString,
                "title": title,
                "bodyLength": body.count
            ]
        )
        NSApp.requestUserAttention(.informationalRequest)
        return .object([
            "notificationID": .string(event.id.uuidString),
            "title": .string(title),
            "body": .string(body),
            "inAppStore": .bool(true),
            "attentionRequested": .bool(true)
        ])
    }

    private func notificationListResult(model: ConductorWindowModel? = nil) -> ConductorControlJSON {
        let events = model?.controlAttentionEvents() ?? []
        return .object([
            "notifications": .array(events.map(notificationEventResult)),
            "unreadCount": .int(events.filter(\.isUnread).count),
            "inAppStore": .bool(true)
        ])
    }

    private func notificationClearResult(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let notificationID = try optionalNotificationIDParam(request.params)
        let cleared = model.controlClearAttentionEvent(id: notificationID)
        return .object([
            "cleared": .int(cleared),
            "inAppStore": .bool(true)
        ])
    }

    private func notificationFocus(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let notificationID = try notificationIDParam(request.params)
        guard let event = model.controlFocusAttentionEvent(id: notificationID) else {
            throw ConductorControlError.targetNotFound(
                "Notification target is no longer available.",
                details: ["notificationID": .string(notificationID.uuidString)]
            )
        }
        return .object([
            "notificationID": .string(event.id.uuidString),
            "focused": .bool(true),
            "event": notificationEventResult(event)
        ])
    }

    private func notificationFocusLatest(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        guard let event = model.controlFocusLatestAttentionEvent(workspaceID: workspaceID) else {
            throw ConductorControlError.targetNotFound(
                "No unread notification with a focusable target was found.",
                details: workspaceID.map { ["workspaceID": .string($0.description)] } ?? [:]
            )
        }
        return .object([
            "notificationID": .string(event.id.uuidString),
            "focused": .bool(true),
            "event": notificationEventResult(event)
        ])
    }

    private func notificationMarkRead(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let workspaceID = try optionalWorkspaceIDParam(request.params)
        let changed = model.controlMarkAttentionEventsRead(workspaceID: workspaceID)
        return .object([
            "markedRead": .int(changed),
            "workspaceID": workspaceID.map { .string($0.description) } ?? .null,
            "inAppStore": .bool(true)
        ])
    }

    private func notificationTest(request: ConductorControlRequest, model: ConductorWindowModel) async throws -> ConductorControlJSON {
        let title = request.params["title"]?.stringValue ?? "Conductor Test Notification"
        let body = request.params["body"]?.stringValue ?? "If you see this banner, system notification delivery is working."
        let playSound = request.params["playSound"]?.boolValue
        let result = await model.controlSendSystemNotificationTest(
            title: title,
            body: body,
            playSound: playSound
        )
        ConductorDiagnostics.record(
            "control-notification-test",
            fields: [
                "status": result.status.rawValue,
                "authorization": notificationAuthorizationStateResult(result.authorizationState),
                "addedToNotificationCenter": result.addedToNotificationCenter ? "true" : "false",
                "launchSupportsSystemNotifications": result.launchSupportsSystemNotifications ? "true" : "false"
            ]
        )
        return .object([
            "status": .string(result.status.rawValue),
            "authorization": .string(notificationAuthorizationStateResult(result.authorizationState)),
            "launchSupportsSystemNotifications": .bool(result.launchSupportsSystemNotifications),
            "addedToNotificationCenter": .bool(result.addedToNotificationCenter),
            "error": result.errorMessage.map { .string($0) } ?? .null,
            "title": .string(title),
            "body": .string(body)
        ])
    }

    private func notificationEventResult(_ event: ConductorAttentionEvent) -> ConductorControlJSON {
        .object([
            "id": .string(event.id.uuidString),
            "createdAt": .string(Self.iso8601Formatter.string(from: event.createdAt)),
            "kind": .string(event.kind.rawValue),
            "severity": .string(event.severity.rawValue),
            "title": .string(event.title),
            "body": .string(event.body),
            "workspaceID": event.workspaceID.map { .string($0.description) } ?? .null,
            "terminalID": event.terminalID.map { .string($0.description) } ?? .null,
            "webTabID": event.webTabID.map { .string($0.rawValue.uuidString) } ?? .null,
            "source": .string(event.source),
            "read": .bool(!event.isUnread),
            "readAt": event.readAt.map { .string(Self.iso8601Formatter.string(from: $0)) } ?? .null,
            "details": .object(event.details.mapValues { .string($0) })
        ])
    }

    private func commandListResult(model: ConductorWindowModel) -> ConductorControlJSON {
        .object([
            "commands": .array(model.shellCommandsForPalette().map { command in
                let descriptor = command.descriptor
                let enabled = model.canPerformCommand(command)
                let ranking = model.shellCommandRanking(for: command)
                return ConductorControlJSON.object([
                    "id": .string(command.rawValue),
                    "catalogID": .string(descriptor.id),
                    "category": .string(descriptor.category),
                    "title": .string(command.displayTitle(model: model)),
                    "description": .string(descriptor.outcome),
                    "keywords": .string(descriptor.keywords),
                    "systemImage": .string(descriptor.systemImage),
                    "protocolMethod": .string(descriptor.protocolMethod),
                    "enabled": .bool(enabled),
                    "disabledReason": enabled ? .null : .string(command.disabledReason(model: model) ?? "Command is unavailable in the current context."),
                    "shortcut": .string(model.shortcutTitle(for: command, fallback: descriptor.shortcutFallback)),
                    "ranking": shellCommandRankingResult(ranking)
                ])
            })
        ])
    }

    private func shellCommandRankingResult(_ ranking: ConductorWindowModel.ShellCommandRanking) -> ConductorControlJSON {
        .object([
            "score": .int(ranking.score),
            "recent": .bool(ranking.isRecent),
            "recentRank": ranking.recentRank.map { .int($0) } ?? .null,
            "contextual": .bool(ranking.isContextual),
            "contextReasons": .array(ranking.contextReasons.map { .string($0) }),
            "badge": ranking.badge.map { .string($0) } ?? .null
        ])
    }

    private func runCommand(request: ConductorControlRequest, model: ConductorWindowModel) throws -> ConductorControlJSON {
        let rawCommand = try stringParam("command", request.params)
        guard let command = ConductorShellCommand(rawValue: rawCommand) else {
            throw ConductorControlError.invalidParams(
                "Unknown command.",
                details: ["command": .string(rawCommand)]
            )
        }
        guard model.canPerformCommand(command) else {
            throw ConductorControlError.commandDisabled(
                "Command is disabled in the current context.",
                details: [
                    "command": .string(rawCommand),
                    "disabledReason": .string(command.disabledReason(model: model) ?? "Command is unavailable in the current context.")
                ]
            )
        }
        let performed = model.performCommand(command)
        return .object([
            "command": .string(rawCommand),
            "performed": .bool(performed)
        ])
    }

    private func stringParam(_ key: String, _ params: [String: ConductorControlJSON]) throws -> String {
        guard let value = params[key]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConductorControlError.invalidParams(
                "Missing or empty string parameter.",
                details: ["parameter": .string(key)]
            )
        }
        return value
    }

    private func doubleParam(
        _ key: String,
        _ params: [String: ConductorControlJSON],
        defaultValue: Double,
        lowerBound: Double,
        upperBound: Double
    ) throws -> Double {
        guard let rawValue = params[key] else {
            return defaultValue
        }
        let value: Double
        switch rawValue {
        case .int(let rawNumber):
            value = Double(rawNumber)
        case .double(let rawNumber):
            value = rawNumber
        case .string(let rawString):
            guard let parsed = Double(rawString) else {
                throw ConductorControlError.invalidParams(
                    "Parameter must be numeric.",
                    details: ["parameter": .string(key)]
                )
            }
            value = parsed
        default:
            throw ConductorControlError.invalidParams(
                "Parameter must be numeric.",
                details: ["parameter": .string(key)]
            )
        }
        guard value.isFinite else {
            throw ConductorControlError.invalidParams(
                "Parameter must be finite.",
                details: ["parameter": .string(key)]
            )
        }
        return min(max(value, lowerBound), upperBound)
    }

    private func workspaceIDParam(_ params: [String: ConductorControlJSON]) throws -> WorkspaceID {
        let value = try stringParam("workspaceID", params)
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "workspaceID must be a UUID string.",
                details: ["workspaceID": .string(value)]
            )
        }
        return WorkspaceID(uuid)
    }

    private func optionalWorkspaceIDParam(_ params: [String: ConductorControlJSON]) throws -> WorkspaceID? {
        guard let value = params["workspaceID"]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "workspaceID must be a UUID string.",
                details: ["workspaceID": .string(value)]
            )
        }
        return WorkspaceID(uuid)
    }

    private func optionalTerminalIDParam(_ params: [String: ConductorControlJSON]) throws -> TerminalID? {
        guard let value = params["terminalID"]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "terminalID must be a UUID string.",
                details: ["terminalID": .string(value)]
            )
        }
        return TerminalID(uuid)
    }

    private func optionalWebTabIDParam(_ params: [String: ConductorControlJSON]) throws -> WebTabID? {
        guard let value = params["webTabID"]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "webTabID must be a UUID string.",
                details: ["webTabID": .string(value)]
            )
        }
        return WebTabID(rawValue: uuid)
    }

    private func webTabIDParam(_ params: [String: ConductorControlJSON]) throws -> WebTabID {
        let value = try stringParam("webTabID", params)
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "webTabID must be a UUID string.",
                details: ["webTabID": .string(value)]
            )
        }
        return WebTabID(rawValue: uuid)
    }

    private func notificationIDParam(_ params: [String: ConductorControlJSON]) throws -> UUID {
        let value = try stringParam("notificationID", params)
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "notificationID must be a UUID string.",
                details: ["notificationID": .string(value)]
            )
        }
        return uuid
    }

    private func optionalNotificationIDParam(_ params: [String: ConductorControlJSON]) throws -> UUID? {
        guard let value = params["notificationID"]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let uuid = UUID(uuidString: value) else {
            throw ConductorControlError.invalidParams(
                "notificationID must be a UUID string.",
                details: ["notificationID": .string(value)]
            )
        }
        return uuid
    }
}
