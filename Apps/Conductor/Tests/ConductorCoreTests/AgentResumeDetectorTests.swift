import Testing
@testable import ConductorCore

@Test func agentResumeDetectorBuildsKnownProviderCommandsFromSessionIDs() {
    let codex = AgentResumeDetector.metadata(providerID: "codex", sessionIdentifier: "019e029c-b1e9-7e31-992e-df4638cf8ee8")
    #expect(codex?.providerID == "codex")
    #expect(codex?.displayName == "Codex")
    #expect(codex?.resumeCommand == "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")

    let claude = AgentResumeDetector.metadata(providerID: "cc", sessionIdentifier: "abc123-session")
    #expect(claude?.providerID == "claude")
    #expect(claude?.displayName == "Claude Code")
    #expect(claude?.resumeCommand == "claude --resume abc123-session")
}

@Test func agentResumeDetectorReadsResumeHintsFromTerminalText() {
    let codexText = """
    Token usage: total=2,602
    To continue this session, run codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8
    """
    let codex = AgentResumeDetector.detect(in: codexText)
    #expect(codex?.providerID == "codex")
    #expect(codex?.sessionIdentifier == "019e029c-b1e9-7e31-992e-df4638cf8ee8")
    #expect(codex?.resumeCommand == "codex resume 019e029c-b1e9-7e31-992e-df4638cf8ee8")

    let claudeText = "Resume later with claude --resume \"abc123-session\""
    let claude = AgentResumeDetector.detect(in: claudeText)
    #expect(claude?.providerID == "claude")
    #expect(claude?.sessionIdentifier == "abc123-session")
    #expect(claude?.resumeCommand == "claude --resume abc123-session")
}

@Test func agentResumeDetectorRejectsUnsafeSessionIDs() {
    let unsafe = AgentResumeDetector.metadata(providerID: "codex", sessionIdentifier: "abc;rm -rf /")
    #expect(unsafe == nil)

    let text = "To continue, run codex resume abc;rm -rf /"
    #expect(AgentResumeDetector.detect(in: text)?.sessionIdentifier == nil)
}
