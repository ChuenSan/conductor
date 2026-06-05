import Foundation
import Testing
@testable import ConductorCore

@Test func restoredTerminalContentAppendsCodexHintAsFinalLine() {
    let terminalID = TerminalID()
    let snapshot = TerminalAgentSnapshot(
        providerID: "codex",
        displayName: "Codex",
        state: .completed,
        updatedAt: Date(timeIntervalSince1970: 1),
        resumeCommand: "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8",
        sessionIdentifier: "019e029c-b1e9-7e31-992e-df4638cf8ee8"
    )

    let restored = RestoredTerminalContent.make(
        terminalID: terminalID,
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "last output\n",
        tabAgentSnapshot: snapshot,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "last output\nConductor restore hint: codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")
    #expect(restored?.resumeHint == "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")
    #expect(restored?.text.split(separator: "\n").last == "Conductor restore hint: codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")
}

@Test func restoredTerminalContentAppendsClaudeHintAsFinalLine() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "",
        tabAgentSnapshot: TerminalAgentSnapshot(
            providerID: "claude",
            displayName: "Claude Code",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 1),
            sessionIdentifier: "abc123-session"
        ),
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "Conductor restore hint: claude --resume abc123-session")
    #expect(restored?.resumeHint == "claude --resume abc123-session")
}

@Test func restoredTerminalContentDoesNotDuplicateExistingHint() {
    let raw = """
    previous output
    Conductor restore hint: codex resume abc123-session
    """
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: raw,
        tabAgentSnapshot: TerminalAgentSnapshot(
            providerID: "codex",
            displayName: "Codex",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 1),
            sessionIdentifier: "abc123-session"
        ),
        persistedAgentSnapshot: nil
    )

    let hintCount = restored?.text.components(separatedBy: "Conductor restore hint:").count ?? 0
    #expect(hintCount == 2)
}

@Test func terminalContentSnapshotSanitizesAndCapsText() {
    let raw = "line 1\u{0007}\nline 2\n\n"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 64)
    #expect(sanitized == "line 1\nline 2")

    let long = String(repeating: "x", count: 80)
    let capped = TerminalContentSnapshotSanitizer.sanitizedText(long, maxUTF8Bytes: 32)
    #expect(capped.utf8.count <= 32)
}

@Test func terminalContentSnapshotFileDropsStaleTerminals() {
    let keepID = TerminalID()
    let dropID = TerminalID()
    let file = PersistedTerminalContentSnapshotFile(
        schemaVersion: 1,
        capturedAt: Date(timeIntervalSince1970: 10),
        snapshots: [
            PersistedTerminalContentSnapshot(
                terminalID: keepID,
                workspaceID: WorkspaceID(),
                paneID: PaneID(),
                capturedAt: Date(timeIntervalSince1970: 10),
                workingDirectory: "/tmp",
                text: "keep",
                agentSnapshot: nil
            ),
            PersistedTerminalContentSnapshot(
                terminalID: dropID,
                workspaceID: WorkspaceID(),
                paneID: PaneID(),
                capturedAt: Date(timeIntervalSince1970: 10),
                workingDirectory: "/tmp",
                text: "drop",
                agentSnapshot: nil
            )
        ]
    )

    let filtered = file.filtered(validTerminalIDs: Set([keepID]))
    #expect(filtered.snapshots.map(\.terminalID) == [keepID])
}
