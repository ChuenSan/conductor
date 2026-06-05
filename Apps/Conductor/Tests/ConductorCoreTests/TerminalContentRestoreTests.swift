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

    let expected = "previous output\nConductor restore hint: codex resume abc123-session"
    let hintCount = (restored?.text.components(separatedBy: "Conductor restore hint:").count ?? 1) - 1
    #expect(restored?.text == expected)
    #expect(restored?.text.split(separator: "\n").last == "Conductor restore hint: codex resume abc123-session")
    #expect(hintCount == 1)
}

@Test func restoredTerminalContentPrefersCurrentTabMetadataOverPersistedMetadata() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "last output",
        tabAgentSnapshot: TerminalAgentSnapshot(
            providerID: "codex",
            displayName: "Codex",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 2),
            sessionIdentifier: "tab-session"
        ),
        persistedAgentSnapshot: TerminalAgentSnapshot(
            providerID: "claude",
            displayName: "Claude Code",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 1),
            sessionIdentifier: "persisted-session"
        )
    )

    #expect(restored?.resumeHint == "codex resume tab-session")
    #expect(restored?.text == "last output\nConductor restore hint: codex resume tab-session")
}

@Test func restoredTerminalContentRemovesStaleHintWhenNoValidHintExists() {
    let raw = """
    previous output
    Conductor restore hint: codex resume stale-session
    final output
    """
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: raw,
        tabAgentSnapshot: nil,
        persistedAgentSnapshot: TerminalAgentSnapshot(
            providerID: "unknown",
            displayName: "Unknown",
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 1),
            sessionIdentifier: "stale-session"
        )
    )

    #expect(restored?.text == "previous output\nfinal output")
    #expect(restored?.resumeHint == nil)
    #expect(restored?.text.contains("Conductor restore hint:") == false)
}

@Test func restoredTerminalContentRemovesWrappedStaleHintContinuation() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "previous output\nConductor restore hint: codex resume\nabc123-session\nfinal output",
        tabAgentSnapshot: nil,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "previous output\nfinal output")
    #expect(restored?.text.contains("Conductor restore hint:") == false)
    #expect(restored?.text.contains("abc123-session") == false)
}

@Test func restoredTerminalContentRemovesOnlyOneWrappedCodexContinuation() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "previous\nConductor restore hint: codex resume\nabc123-session\n2026-06-05\nfinal",
        tabAgentSnapshot: nil,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "previous\n2026-06-05\nfinal")
}

@Test func restoredTerminalContentRemovesOnlyOneWrappedClaudeContinuation() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "previous\nConductor restore hint: claude --resume\nabc123-session\nbuild-123\nfinal",
        tabAgentSnapshot: nil,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "previous\nbuild-123\nfinal")
}

@Test func restoredTerminalContentKeepsNormalOutputAfterStaleHint() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "previous output\nConductor restore hint: codex resume\ndone",
        tabAgentSnapshot: nil,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "previous output\ndone")
}

@Test func restoredTerminalContentKeepsTokenLikeOutputAfterCompleteStaleHint() {
    let tokenLikeLines = ["2026-06-05", "build-123", "abc123-session"]

    for tokenLikeLine in tokenLikeLines {
        let restored = RestoredTerminalContent.make(
            terminalID: TerminalID(),
            capturedAt: Date(timeIntervalSince1970: 2),
            rawText: "previous output\nConductor restore hint: codex resume stale-session\n\(tokenLikeLine)\nfinal output",
            tabAgentSnapshot: nil,
            persistedAgentSnapshot: nil
        )

        #expect(restored?.text == "previous output\n\(tokenLikeLine)\nfinal output")
    }
}

@Test func restoredTerminalContentKeepsTokenLikeOutputAfterClaudeShortResumeHint() {
    let restored = RestoredTerminalContent.make(
        terminalID: TerminalID(),
        capturedAt: Date(timeIntervalSince1970: 2),
        rawText: "previous\nConductor restore hint: claude -r\nbuild-123\nfinal",
        tabAgentSnapshot: nil,
        persistedAgentSnapshot: nil
    )

    #expect(restored?.text == "previous\nbuild-123\nfinal")
}

@Test func terminalContentSnapshotSanitizesAndCapsText() {
    let raw = "line 1\u{0007}\nline 2\n\n"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 64)
    #expect(sanitized == "line 1\nline 2")

    let long = String(repeating: "x", count: 80)
    let capped = TerminalContentSnapshotSanitizer.sanitizedText(long, maxUTF8Bytes: 32)
    #expect(capped.utf8.count <= 32)
}

@Test func terminalContentSnapshotReturnsEmptyForInvalidByteLimits() {
    #expect(TerminalContentSnapshotSanitizer.sanitizedText("text", maxUTF8Bytes: 0) == "")
    #expect(TerminalContentSnapshotSanitizer.sanitizedText("text", maxUTF8Bytes: -1) == "")
}

@Test func terminalContentSnapshotKeepsOnlyBoundedSuffixForLargeInput() {
    let raw = String(repeating: "drop me\n", count: 2_000) + " final-suffix \n"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 16)
    #expect(sanitized.contains("final-suffix"))
    #expect(sanitized.contains("drop me") == false)
    #expect(sanitized.utf8.count <= 16)
}

@Test func terminalContentSnapshotCapsAtMultibyteCharacterBoundary() {
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText("a🙂b🙂c", maxUTF8Bytes: 5)
    #expect(sanitized == "🙂c")
    #expect(sanitized.utf8.count <= 5)
}

@Test func terminalContentSnapshotDropsNonNewlineControlsAndPreservesTabs() {
    let raw = "first\u{0007}\nsecond\tcolumn\u{0008}\n"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 64)
    #expect(sanitized == "first\nsecond\tcolumn")
}

@Test func terminalContentSnapshotTrimsSpacesWithoutStrippingTabs() {
    let raw = "\tfirst\t\n second \n"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 64)
    #expect(sanitized == "\tfirst\t\nsecond")
}

@Test func terminalContentSnapshotNormalizesCRLFAndCRBoundaries() {
    let raw = "line 1\r\nline 2\rline 3"
    let sanitized = TerminalContentSnapshotSanitizer.sanitizedText(raw, maxUTF8Bytes: 64)
    #expect(sanitized == "line 1\nline 2\nline 3")
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
