import XCTest
@testable import ConductorCore

final class AppConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    func testDefaults() {
        let c = AppConfig.default
        XCTAssertEqual(c.appearance.theme, "dark")
        XCTAssertEqual(c.appearance.font.family, "SF Mono")
        XCTAssertEqual(c.appearance.font.size, 13)
        XCTAssertEqual(c.appearance.cursorStyle, "bar")
        XCTAssertEqual(c.terminal.scrollback, 60000)
        XCTAssertTrue(c.terminal.confirmCloseRunning)
        XCTAssertTrue(c.terminal.autoResumeAgentSessions)
        XCTAssertTrue(c.terminal.aiAgents.isEmpty)
        XCTAssertEqual(c.behavior.newTabCwd, "workspace")
        XCTAssertTrue(c.keybindings.isEmpty)
        XCTAssertTrue(c.ghosttyOverrides.isEmpty)
        XCTAssertEqual(c.usage.providerRefreshIntervalSeconds, 300)
        XCTAssertFalse(c.usage.usageBarsShowUsed)
        XCTAssertFalse(c.usage.resetTimesShowAbsolute)
        XCTAssertTrue(c.usage.showOptionalCreditsAndExtraUsage)
        XCTAssertFalse(c.usage.hidePersonalInfo)
        XCTAssertNil(c.usage.weeklyProgressWorkDays)
        XCTAssertFalse(c.usage.providerChangelogLinksEnabled)
        XCTAssertFalse(c.usage.providerStorageFootprintsEnabled)
        XCTAssertTrue(c.usage.statusBarOverviewProviderIDs.isEmpty)
        XCTAssertTrue(c.usage.statusBarOverviewSelectionBasisIDs.isEmpty)
    }

    func testFullDecode() throws {
        let c = try decode("""
        {
          "appearance": { "theme": "light", "font": { "family": "Menlo", "size": 16 },
                          "padding": { "x": 8, "y": 6 }, "cursorStyle": "block" },
          "terminal": { "shell": "/bin/bash", "scrollback": 5000, "copyOnSelect": true,
                        "confirmCloseRunning": false,
                        "autoResumeAgentSessions": false,
                        "aiAgents": [
                          { "id": "codex", "title": "Codex", "command": "codex", "enabled": true },
                          { "id": "local", "title": "Local Agent", "command": "local-agent", "enabled": false }
                        ] },
          "behavior": { "restoreLayoutOnLaunch": false, "newTabCwd": "home" },
          "keybindings": { "newTab": "cmd+t" },
          "ghosttyOverrides": { "cursor-style": "block", "background-opacity": "0.92" },
          "workspaceDefaults": { "shell": "/bin/zsh", "startupCommand": "ls" }
        }
        """)
        XCTAssertEqual(c.appearance.theme, "light")
        XCTAssertEqual(c.appearance.font.family, "Menlo")
        XCTAssertEqual(c.appearance.font.size, 16)
        XCTAssertEqual(c.appearance.cursorStyle, "block")
        XCTAssertEqual(c.terminal.shell, "/bin/bash")
        XCTAssertEqual(c.terminal.scrollback, 5000)
        XCTAssertTrue(c.terminal.copyOnSelect)
        XCTAssertFalse(c.terminal.autoResumeAgentSessions)
        XCTAssertEqual(c.terminal.aiAgents.map(\.id), ["codex", "local"])
        XCTAssertEqual(c.terminal.aiAgents[1].title, "Local Agent")
        XCTAssertEqual(c.terminal.aiAgents[1].command, "local-agent")
        XCTAssertFalse(c.terminal.aiAgents[1].enabled)
        XCTAssertFalse(c.behavior.restoreLayoutOnLaunch)
        XCTAssertEqual(c.behavior.newTabCwd, "home")
        XCTAssertEqual(c.keybindings["newTab"], "cmd+t")
        XCTAssertEqual(c.ghosttyOverrides["cursor-style"], "block")
        XCTAssertEqual(c.ghosttyOverrides["background-opacity"], "0.92")
        XCTAssertEqual(c.workspaceDefaults.startupCommand, "ls")
    }

    func testMissingFieldsUseDefaults() throws {
        // 只给一个深层字段，其余应全部回退默认
        let c = try decode(#"{ "appearance": { "font": { "size": 20 } } }"#)
        XCTAssertEqual(c.appearance.font.size, 20)
        XCTAssertEqual(c.appearance.font.family, "SF Mono")   // 缺 → 默认
        XCTAssertEqual(c.appearance.theme, "dark")            // 缺 → 默认
        XCTAssertEqual(c.appearance.padding.x, 14)            // 缺 → 默认
        XCTAssertEqual(c.terminal.scrollback, 60000)          // 整段缺 → 默认
        XCTAssertEqual(c.behavior.newTabCwd, "workspace")
    }

    func testUnknownFieldsIgnored() throws {
        let c = try decode("""
        { "appearance": { "theme": "dark", "bogusKey": 123 }, "totallyUnknown": true }
        """)
        XCTAssertEqual(c.appearance.theme, "dark")
    }

    func testEmptyObjectIsAllDefaults() throws {
        let c = try decode("{}")
        XCTAssertEqual(c, AppConfig.default)
    }

    func testValidatedClampsFontSize() {
        var c = AppConfig.default
        c.appearance.font.size = 999
        XCTAssertEqual(c.validated().appearance.font.size, 72)
        c.appearance.font.size = 2
        XCTAssertEqual(c.validated().appearance.font.size, 6)
    }

    func testValidatedClampsScrollbackToMinimum() {
        var c = AppConfig.default
        c.terminal.scrollback = 5000          // 旧配置里的小值
        XCTAssertEqual(c.validated().terminal.scrollback, 60_000)
        c.terminal.scrollback = 99_000_000
        XCTAssertEqual(c.validated().terminal.scrollback, 1_000_000)
    }

    func testValidatedCleansAIAgents() {
        var c = AppConfig.default
        c.terminal.aiAgents = [
            AIAgentConfig(id: " codex ", title: " Codex CLI ", command: " codex ", enabled: true),
            AIAgentConfig(id: "codex", title: "Duplicate", command: "codex-beta", enabled: true),
            AIAgentConfig(id: "empty-command", title: "Broken", command: " ", enabled: true),
            AIAgentConfig(id: " ", title: "No ID", command: "agent", enabled: true),
        ]

        let agents = c.validated().terminal.aiAgents
        XCTAssertEqual(agents, [
            AIAgentConfig(id: "codex", title: "Codex CLI", command: "codex", enabled: true),
        ])
    }

    func testValidatedFallsBackInvalidEnums() {
        var c = AppConfig.default
        c.appearance.cursorStyle = "wat"
        c.behavior.newTabCwd = "nope"
        let v = c.validated()
        XCTAssertEqual(v.appearance.cursorStyle, "bar")
        XCTAssertEqual(v.behavior.newTabCwd, "workspace")
    }

    func testUsageTokenAccountsDecodeWithDefaults() throws {
        let c = try decode("""
        {
          "usage": {
            "providers": {
              "codex": {
                "tokenAccounts": {
                  "accounts": [
                    { "label": "alpha", "token": "/tmp/codex-alpha" },
                    { "label": "beta", "token": "/tmp/codex-beta" }
                  ],
                  "activeIndex": 8
                }
              }
            }
          }
        }
        """)
        let data = try XCTUnwrap(c.usage.providers["codex"]?.tokenAccounts)
        XCTAssertEqual(data.accounts.map(\.label), ["alpha", "beta"])
        XCTAssertEqual(data.accounts.first?.token, "/tmp/codex-alpha")
        XCTAssertEqual(data.version, 1)
        XCTAssertEqual(data.validated()?.clampedActiveIndex(), 1)
    }

    func testUsageProviderOrderNormalizesAndCompletesKnownProviders() {
        let order = UsageConfig.effectiveProviderOrder(
            raw: [" claude ", "codex", "claude", "missing", ""],
            knownProviderIDs: ["codex", "claude", "gemini"])
        XCTAssertEqual(order, ["claude", "codex", "gemini"])
    }

    func testUsageProviderOrderFallsBackToCatalogOrderWhenEmpty() {
        let order = UsageConfig.effectiveProviderOrder(
            raw: ["missing"],
            knownProviderIDs: ["codex", "claude"])
        XCTAssertEqual(order, ["codex", "claude"])
    }

    func testUsageProvidersSortedAlphabeticallyDecodes() throws {
        XCTAssertFalse(AppConfig.default.usage.providersSortedAlphabetically)

        let c = try decode(#"{ "usage": { "providersSortedAlphabetically": true } }"#)
        XCTAssertTrue(c.usage.providersSortedAlphabetically)
    }

    func testUsageProviderRefreshIntervalDecodeAndValidate() throws {
        let c = try decode(#"{ "usage": { "providerRefreshIntervalSeconds": 60 } }"#)
        XCTAssertEqual(c.usage.providerRefreshIntervalSeconds, 60)

        let manual = try decode(#"{ "usage": { "providerRefreshIntervalSeconds": 0 } }"#)
        XCTAssertEqual(manual.usage.providerRefreshIntervalSeconds, 0)

        var invalid = AppConfig.default
        invalid.usage.providerRefreshIntervalSeconds = 7
        XCTAssertEqual(invalid.validated().usage.providerRefreshIntervalSeconds, 300)
    }

    func testUsageBarsShowUsedDecodes() throws {
        let c = try decode(#"{ "usage": { "usageBarsShowUsed": true } }"#)
        XCTAssertTrue(c.usage.usageBarsShowUsed)
    }

    func testResetTimesShowAbsoluteDecodes() throws {
        let c = try decode(#"{ "usage": { "resetTimesShowAbsolute": true } }"#)
        XCTAssertTrue(c.usage.resetTimesShowAbsolute)
    }

    func testShowOptionalCreditsAndExtraUsageDecodes() throws {
        let c = try decode(#"{ "usage": { "showOptionalCreditsAndExtraUsage": false } }"#)
        XCTAssertFalse(c.usage.showOptionalCreditsAndExtraUsage)
    }

    func testHidePersonalInfoDecodes() throws {
        let c = try decode(#"{ "usage": { "hidePersonalInfo": true } }"#)
        XCTAssertTrue(c.usage.hidePersonalInfo)
    }

    func testWeeklyProgressWorkDaysDecodesAndNormalizes() throws {
        let c = try decode(#"{ "usage": { "weeklyProgressWorkDays": 5 } }"#)
        XCTAssertEqual(c.usage.weeklyProgressWorkDays, 5)

        let invalid = try decode(#"{ "usage": { "weeklyProgressWorkDays": 6 } }"#)
        XCTAssertNil(invalid.usage.weeklyProgressWorkDays)
    }

    func testProviderChangelogLinksEnabledDecodes() throws {
        let c = try decode(#"{ "usage": { "providerChangelogLinksEnabled": true } }"#)
        XCTAssertTrue(c.usage.providerChangelogLinksEnabled)
    }

    func testProviderStorageFootprintsEnabledDecodes() throws {
        let c = try decode(#"{ "usage": { "providerStorageFootprintsEnabled": true } }"#)
        XCTAssertTrue(c.usage.providerStorageFootprintsEnabled)
    }

    func testStatusBarOverviewProviderSelectionDefaultsToFirstThreeActiveProviders() {
        let ids = AppConfig.default.usage.effectiveStatusBarOverviewProviderIDs(
            activeProviderIDs: ["codex", "claude", "gemini", "cursor"])
        XCTAssertEqual(ids, ["codex", "claude", "gemini"])
    }

    func testStatusBarOverviewProviderSelectionPreservesExplicitSelectionInActiveOrder() {
        var usage = UsageConfig(
            statusBarOverviewProviderIDs: ["cursor", "claude", "missing", "cursor"],
            statusBarOverviewSelectionBasisIDs: ["codex", "claude", "gemini", "cursor"])
            .validated()
        let ids = usage.effectiveStatusBarOverviewProviderIDs(
            activeProviderIDs: ["codex", "claude", "gemini", "cursor"])
        XCTAssertEqual(ids, ["claude", "cursor"])

        usage.statusBarOverviewProviderIDs = []
        usage.statusBarOverviewSelectionBasisIDs = ["codex", "claude", "gemini", "cursor"]
        XCTAssertEqual(
            usage.effectiveStatusBarOverviewProviderIDs(activeProviderIDs: ["codex", "claude", "gemini", "cursor"]),
            [])
    }

    func testStatusBarOverviewProviderSelectionFallsBackWhenSmallActiveSetChanged() {
        let usage = UsageConfig(
            statusBarOverviewProviderIDs: ["claude"],
            statusBarOverviewSelectionBasisIDs: ["codex", "claude", "gemini", "cursor"])
        let ids = usage.effectiveStatusBarOverviewProviderIDs(activeProviderIDs: ["codex", "claude"])
        XCTAssertEqual(ids, ["codex", "claude"])
    }

    func testRoundTripEncodeDecode() throws {
        let original = AppConfig(
            appearance: Appearance(theme: "light", font: FontConfig(family: "Menlo", size: 15)),
            terminal: TerminalConfig(shell: "/bin/bash"),
            keybindings: ["newTab": "cmd+t"],
            ghosttyOverrides: ["cursor-style": "underline"]
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(AppConfig.self, from: data)
        XCTAssertEqual(back, original)
    }
}
