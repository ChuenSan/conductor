import Testing
@testable import ConductorCore

@Test func agentIntegrationCatalog() {
    guard let codex = AgentIntegrationCatalog.definition(named: "codex") else {
        Issue.record("agent catalog should include Codex"); return
    }
    #expect(codex.binaryName == "codex", "Codex integration should resolve codex binary")
    #expect(codex.configDirectoryEnvironmentOverride == "CODEX_HOME", "Codex integration should respect CODEX_HOME")
    #expect(codex.lifecycleEvents.contains(where: { $0.agentEvent == "UserPromptSubmit" }), "Codex should define prompt submit lifecycle")
    #expect(codex.feedEvents.contains("PreToolUse"), "Codex should define feed bridge events")

    guard let claude = AgentIntegrationCatalog.definition(named: "cc") else {
        Issue.record("agent catalog should resolve Claude alias"); return
    }
    #expect(claude.id == "claude", "Claude alias should resolve built-in Claude integration")

    guard let rovo = AgentIntegrationCatalog.definition(named: "rovo") else {
        Issue.record("agent catalog should resolve Rovo alias"); return
    }
    #expect(rovo.id == "rovodev", "Rovo alias should resolve Rovo Dev integration")
    #expect(AgentIntegrationCatalog.definition(named: "unknown-agent") == nil, "unknown agent should not resolve")
}
