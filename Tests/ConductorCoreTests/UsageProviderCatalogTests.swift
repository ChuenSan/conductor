import XCTest
@testable import ConductorCore

final class UsageProviderCatalogTests: XCTestCase {
    func testChangelogURLsMatchCodexBarProviders() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["codex"]?.changelogURL, "https://github.com/openai/codex/releases")
        XCTAssertEqual(providers["claude"]?.changelogURL, "https://github.com/anthropics/claude-code/releases")
        XCTAssertEqual(providers["gemini"]?.changelogURL, "https://github.com/google-gemini/gemini-cli/releases")
        XCTAssertEqual(providers["grok"]?.changelogURL, "https://x.ai/news")
        XCTAssertNil(providers["openai"]?.changelogURL)
    }

    func testDashboardURLsMatchCodexBarProviders() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["codex"]?.dashboardURL, "https://chatgpt.com/codex/settings/usage")
        XCTAssertEqual(providers["claude"]?.dashboardURL, "https://console.anthropic.com/settings/billing")
        XCTAssertEqual(providers["claude"]?.subscriptionDashboardURL, "https://claude.ai/settings/usage")
        XCTAssertEqual(providers["qwen"]?.dashboardURL, "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan")
        XCTAssertEqual(providers["openai"]?.dashboardURL, "https://platform.openai.com/usage")
        XCTAssertEqual(providers["elevenlabs"]?.subscriptionDashboardURL, "https://elevenlabs.io/app/subscription")
        XCTAssertNil(providers["litellm"]?.dashboardURL)
    }

    func testDefaultEnabledMatchesCodexBarProviders() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["codex"]?.defaultEnabled, true)
        XCTAssertEqual(providers["claude"]?.defaultEnabled, false)
        XCTAssertEqual(providers["openai"]?.defaultEnabled, false)
        XCTAssertEqual(providers["zed"]?.defaultEnabled, false)

        let config = AppConfig()
        XCTAssertEqual(providers["codex"]?.isEnabled(in: config), true)
        XCTAssertEqual(providers["claude"]?.isEnabled(in: config), false)
    }

    func testSourceModesMatchCodexBarFetchPlansWithConductorAliases() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["openai"]?.sourceModes, ["auto", "api"])
        XCTAssertEqual(providers["zed"]?.sourceModes, ["auto", "api"])
        XCTAssertEqual(providers["qwen"]?.sourceModes, ["auto", "web", "api"])
        XCTAssertEqual(providers["codex"]?.sourceModes, ["auto", "web", "cli", "oauth"])
        XCTAssertEqual(providers["opencode"]?.sourceModes, ["auto", "web"])
        XCTAssertEqual(providers["opencodego"]?.sourceModes, ["auto", "web"])
        XCTAssertFalse(providers["codex"]?.supportsSourceMode("dashboard") ?? true)
        XCTAssertFalse(providers["openai"]?.supportsSourceMode("oauth") ?? true)
        XCTAssertFalse(providers["opencodego"]?.supportsSourceMode("browser") ?? true)
    }

    func testCLISessionPoliciesExposeOneShotHelpers() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["codex"]?.cliSessionPolicy.kind, "persistent")
        XCTAssertTrue(providers["codex"]?.cliSessionPolicy.persistsAcrossRequests ?? false)
        XCTAssertEqual(providers["codex"]?.cliSessionPolicy.idleWindowSeconds, 90)
        XCTAssertEqual(providers["kilo"]?.cliSessionPolicy.kind, "oneShot")
        XCTAssertEqual(providers["claude"]?.cliSessionPolicy.kind, "persistent")
        XCTAssertTrue(providers["claude"]?.cliSessionPolicy.persistsAcrossRequests ?? false)
        XCTAssertEqual(providers["claude"]?.cliSessionPolicy.idleWindowSeconds, 90)
    }

    func testDisplayMetadataMatchesCodexBarProviders() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["codex"]?.displayMetadata.sessionLabel, "Session")
        XCTAssertEqual(providers["codex"]?.displayMetadata.weeklyLabel, "Weekly")
        XCTAssertEqual(providers["codex"]?.displayMetadata.supportsCredits, true)
        XCTAssertEqual(providers["codex"]?.displayMetadata.isPrimaryProvider, true)
        XCTAssertEqual(providers["codex"]?.displayMetadata.usesAccountFallback, true)
        XCTAssertEqual(providers["claude"]?.displayMetadata.opusLabel, "Sonnet")
        XCTAssertEqual(providers["claude"]?.displayMetadata.supportsOpus, true)
        XCTAssertEqual(providers["qwen"]?.displayMetadata.cliName, "alibaba-coding-plan")
        XCTAssertEqual(providers["glm"]?.displayMetadata.toggleTitle, "Show z.ai usage")
        XCTAssertEqual(providers["openrouter"]?.displayMetadata.creditsHint, "Credit balance from OpenRouter API")
    }

    func testSignInCommandsMatchKnownCLIProviders() throws {
        let providers = Dictionary(uniqueKeysWithValues: UsageProviderCatalog.all.map { ($0.id, $0) })

        XCTAssertEqual(providers["codex"]?.signInCommand, "codex login --device-auth")
        XCTAssertEqual(providers["claude"]?.signInCommand, "claude /login")
        XCTAssertEqual(providers["gemini"]?.signInCommand, "gemini auth")
        XCTAssertEqual(providers["qwen"]?.signInCommand, "qwen login")
        XCTAssertEqual(providers["augment"]?.signInCommand, "auggie login")
        XCTAssertNil(providers["openai"]?.signInCommand)
    }

    func testConfigEnvironmentHintsExposeProviderSettingsInputs() throws {
        let qwen = UsageProviderConfigCapabilities.environmentHints(providerID: "qwen")
        XCTAssertEqual(qwen.apiKey, ["ALIBABA_CODING_PLAN_API_KEY", "ALIBABA_QWEN_API_KEY", "DASHSCOPE_API_KEY"])
        XCTAssertEqual(qwen.baseURL, ["ALIBABA_CODING_PLAN_HOST"])
        XCTAssertTrue(qwen.sourceMode.contains("CONDUCTOR_USAGE_QWEN_SOURCE"))
        XCTAssertEqual(qwen.extra["region"], ["ALIBABA_CODING_PLAN_REGION", "QWEN_REGION"])
        XCTAssertEqual(qwen.extra["quotaURL"], ["ALIBABA_CODING_PLAN_QUOTA_URL"])

        let minimax = UsageProviderConfigCapabilities.environmentHints(providerID: "minimax")
        XCTAssertEqual(minimax.apiKey, ["MINIMAX_CODING_API_KEY", "MINIMAX_API_KEY"])
        XCTAssertEqual(minimax.cookieHeader, ["MINIMAX_COOKIE", "MINIMAX_COOKIE_HEADER"])
        XCTAssertEqual(minimax.baseURL, ["MINIMAX_HOST"])
        XCTAssertEqual(minimax.extra["region"], ["MINIMAX_REGION"])
        XCTAssertEqual(minimax.extra["remainsURL"], ["MINIMAX_REMAINS_URL"])
        XCTAssertEqual(minimax.extra["codingPlanURL"], ["MINIMAX_CODING_PLAN_URL"])
        XCTAssertEqual(minimax.extra["billingHistoryURL"], ["MINIMAX_BILLING_HISTORY_URL"])
        XCTAssertEqual(
            minimax.extra["requireProviderEndpointOverrides"],
            ["MINIMAX_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"])

        let azure = UsageProviderConfigCapabilities.environmentHints(providerID: "azureopenai")
        XCTAssertEqual(azure.apiKey, ["AZURE_OPENAI_API_KEY"])
        XCTAssertEqual(azure.baseURL, ["AZURE_OPENAI_ENDPOINT"])
        XCTAssertEqual(azure.project, ["AZURE_OPENAI_DEPLOYMENT_NAME"])
        XCTAssertEqual(azure.extra["apiVersion"], ["AZURE_OPENAI_API_VERSION"])

        let claude = UsageProviderConfigCapabilities.environmentHints(providerID: "claude")
        XCTAssertEqual(claude.apiKey, ["ANTHROPIC_ADMIN_KEY", "ANTHROPIC_ADMIN_API_KEY"])
        XCTAssertEqual(claude.cookieHeader, ["CONDUCTOR_USAGE_CLAUDE_COOKIE"])
        XCTAssertEqual(claude.baseURL, ["CONDUCTOR_USAGE_CLAUDE_WEB_API_BASE_URL"])
        XCTAssertEqual(claude.organization, [
            "CONDUCTOR_USAGE_CLAUDE_ORGANIZATION_ID",
            "CLAUDE_ORGANIZATION_ID",
            "ANTHROPIC_ORGANIZATION_ID",
        ])
        XCTAssertEqual(claude.extra["sessionKey"], ["CONDUCTOR_USAGE_CLAUDE_SESSION_KEY", "CLAUDE_SESSION_KEY"])
        XCTAssertEqual(claude.extra["oauthToken"], ["CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN", "CLAUDE_OAUTH_ACCESS_TOKEN"])
        XCTAssertEqual(claude.extra["subscriptionType"], ["CONDUCTOR_USAGE_CLAUDE_SUBSCRIPTION_TYPE"])

        let perplexity = UsageProviderConfigCapabilities.environmentHints(providerID: "perplexity")
        XCTAssertEqual(perplexity.apiKey, [])
        XCTAssertEqual(perplexity.cookieHeader, [
            "PERPLEXITY_SESSION_TOKEN",
            "perplexity_session_token",
            "PERPLEXITY_COOKIE",
        ])

        let manus = UsageProviderConfigCapabilities.environmentHints(providerID: "manus")
        XCTAssertEqual(manus.apiKey, [])
        XCTAssertEqual(manus.cookieHeader, [
            "MANUS_SESSION_TOKEN",
            "manus_session_token",
            "MANUS_SESSION_ID",
            "manus_session_id",
            "MANUS_COOKIE",
            "manus_cookie",
        ])

        let commandCode = UsageProviderConfigCapabilities.environmentHints(providerID: "commandcode")
        XCTAssertEqual(commandCode.apiKey, [])
        XCTAssertEqual(commandCode.cookieHeader, [
            "COMMANDCODE_SESSION_TOKEN",
            "COMMANDCODE_COOKIE",
            "COMMANDCODE_TOKEN",
        ])

        let tokenPlan = UsageProviderConfigCapabilities.environmentHints(providerID: "alibabatokenplan")
        XCTAssertEqual(tokenPlan.apiKey, [])
        XCTAssertEqual(tokenPlan.cookieHeader, ["ALIBABA_TOKEN_PLAN_COOKIE"])
    }

    func testCookieHeaderCapabilityMatchesWebSessionProviders() throws {
        for providerID in ["codex", "copilot", "commandcode", "manus", "perplexity", "alibabatokenplan"] {
            XCTAssertTrue(UsageProviderConfigCapabilities.supportsCookieHeader(providerID), providerID)
        }
        XCTAssertFalse(UsageProviderConfigCapabilities.supportsCookieHeader("openai"))
        XCTAssertFalse(UsageProviderConfigCapabilities.supportsCookieHeader("azureopenai"))
    }

    func testAPIOnlyProvidersWarnOnCookieConfiguration() throws {
        let config = AppConfig(usage: UsageConfig(providers: [
            "openai": UsageProviderConfig(cookieHeader: "session=unused", cookieSource: "manual"),
        ]))

        let issues = UsageProviderConfigValidator.issues(for: "openai", in: config)

        XCTAssertTrue(issues.contains { $0.code == "cookie_source_unused" })
        XCTAssertTrue(issues.contains { $0.code == "cookie_header_unused" })
    }

    func testClaudeTokenAccountsRouteByCredentialKind() throws {
        let admin = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "claude",
            account: UsageProviderTokenAccount(label: "Admin", token: "Bearer sk-ant-admin-test"))
        XCTAssertEqual(admin.set["ANTHROPIC_ADMIN_KEY"], "sk-ant-admin-test")
        XCTAssertEqual(admin.set["ANTHROPIC_ADMIN_API_KEY"], "sk-ant-admin-test")
        XCTAssertEqual(admin.set["CONDUCTOR_USAGE_CLAUDE_SOURCE"], "api")
        XCTAssertTrue(admin.unset.contains("CONDUCTOR_USAGE_CLAUDE_COOKIE"))

        let oauth = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "claude",
            account: UsageProviderTokenAccount(label: "OAuth", token: "Bearer sk-ant-oat-test"))
        XCTAssertEqual(oauth.set["CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN"], "sk-ant-oat-test")
        XCTAssertEqual(oauth.set["CLAUDE_OAUTH_ACCESS_TOKEN"], "sk-ant-oat-test")
        XCTAssertEqual(oauth.set["CONDUCTOR_USAGE_CLAUDE_SOURCE"], "oauth")
        XCTAssertTrue(oauth.unset.contains("ANTHROPIC_ADMIN_KEY"))

        let cookie = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "claude",
            account: UsageProviderTokenAccount(
                label: "Web",
                token: "sk-ant-sid-test",
                organizationID: "org-test"))
        XCTAssertEqual(cookie.set["CONDUCTOR_USAGE_CLAUDE_COOKIE"], "sessionKey=sk-ant-sid-test")
        XCTAssertEqual(cookie.set["CONDUCTOR_USAGE_CLAUDE_COOKIE_SOURCE"], "manual")
        XCTAssertEqual(cookie.set["CONDUCTOR_USAGE_CLAUDE_SOURCE"], "web")
        XCTAssertEqual(cookie.set["CONDUCTOR_USAGE_CLAUDE_ORGANIZATION_ID"], "org-test")
        XCTAssertEqual(cookie.set["CLAUDE_ORGANIZATION_ID"], "org-test")

        let configDir = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "claude",
            account: UsageProviderTokenAccount(label: "Local", token: "/tmp/claude-profile"))
        XCTAssertEqual(configDir.set["CLAUDE_CONFIG_DIR"], "/tmp/claude-profile")
        XCTAssertNil(configDir.set["CONDUCTOR_USAGE_CLAUDE_SOURCE"])
        XCTAssertTrue(configDir.unset.contains("CONDUCTOR_CLAUDE_AVOID_KEYCHAIN"))
    }

    func testSessionTokenProvidersUseCookieAccountSupportInsteadOfAPIKey() throws {
        for providerID in ["alibabatokenplan", "commandcode", "manus", "perplexity"] {
            XCTAssertFalse(UsageProviderConfigCapabilities.supportsAPIKey(providerID), providerID)
            XCTAssertTrue(UsageProviderConfigCapabilities.supportsTokenAccounts(providerID), providerID)
        }

        let commandCode = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "commandcode",
            account: UsageProviderTokenAccount(label: "CommandCode", token: "cc-session"))
        XCTAssertEqual(commandCode.set["COMMANDCODE_SESSION_TOKEN"], "cc-session")
        XCTAssertEqual(commandCode.set["COMMANDCODE_COOKIE"], "cc-session")
        XCTAssertEqual(commandCode.set["COMMANDCODE_TOKEN"], "cc-session")
        XCTAssertEqual(commandCode.set["CONDUCTOR_USAGE_COMMANDCODE_COOKIE_SOURCE"], "manual")

        let manus = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "manus",
            account: UsageProviderTokenAccount(label: "Manus", token: "manus-session"))
        XCTAssertEqual(manus.set["MANUS_SESSION_TOKEN"], "session_id=manus-session")
        XCTAssertEqual(manus.set["MANUS_SESSION_ID"], "session_id=manus-session")
        XCTAssertEqual(manus.set["MANUS_COOKIE"], "session_id=manus-session")
        XCTAssertEqual(manus.set["CONDUCTOR_USAGE_MANUS_COOKIE_SOURCE"], "manual")

        let perplexity = UsageProviderConfigCapabilities.environmentPatch(
            providerID: "perplexity",
            account: UsageProviderTokenAccount(label: "Perplexity", token: "pplx-session"))
        XCTAssertEqual(perplexity.set["PERPLEXITY_SESSION_TOKEN"], "pplx-session")
        XCTAssertEqual(perplexity.set["PERPLEXITY_COOKIE"], "pplx-session")
        XCTAssertEqual(perplexity.set["CONDUCTOR_USAGE_PERPLEXITY_COOKIE_SOURCE"], "manual")
    }

    func testProviderSelectionAcceptsAliasesAndCommaLists() throws {
        let ids = try UsageProviderCatalog.entries(
            for: "azure-openai,github-copilot,claude-code,alibaba")
            .map(\.id)

        XCTAssertEqual(ids, ["azureopenai", "copilot", "claude", "qwen"])
        XCTAssertEqual(UsageProviderCatalog.canonicalProviderID(" Open-Code-Go "), "opencodego")
    }

    func testProviderSelectionUsesConfigOrderForCollections() throws {
        let config = AppConfig(
            usage: UsageConfig(
                providers: [
                    "claude": UsageProviderConfig(enabled: true),
                    "qwen": UsageProviderConfig(enabled: true),
                    "codex": UsageProviderConfig(enabled: false),
                ],
                providerOrder: ["qwen", "claude", "codex", "copilot"]))

        XCTAssertEqual(
            try UsageProviderCatalog.entries(for: nil, config: config).map(\.id),
            ["qwen", "claude"])
        XCTAssertEqual(
            try UsageProviderCatalog.entries(for: "both", config: config).map(\.id),
            ["claude", "codex"])
        XCTAssertEqual(
            Array(try UsageProviderCatalog.entries(for: "all", config: config).map(\.id).prefix(4)),
            ["qwen", "claude", "codex", "copilot"])
        XCTAssertEqual(
            try UsageProviderCatalog.entries(for: "codex,claude", config: config).map(\.id),
            ["codex", "claude"])
    }
}
