import XCTest
@testable import ConductorCore

final class UsageProviderDiagnosticsTests: XCTestCase {
    func testRedactorRemovesCommonSecrets() {
        let input = """
        dev@example.com
        Authorization: Bearer sk-secret1234567890
        Cookie: session=abc1234567890
        https://example.test?token=abc1234567890&ok=1
        """
        let output = UsageDiagnosticRedactor.redact(input)

        XCTAssertFalse(output.contains("dev@example.com"))
        XCTAssertFalse(output.contains("sk-secret1234567890"))
        XCTAssertFalse(output.contains("session=abc1234567890"))
        XCTAssertFalse(output.contains("token=abc1234567890"))
        XCTAssertTrue(output.contains("<redacted-email>"))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testRedactorKeepsEncodedJSONValidWhenPathSegmentContainsSecretKey() throws {
        let input = #"{"storage":{"unreadablePaths":["~\/.claude\/private-token=diagnose-secret"],"topComponents":[]}}"#
        let output = UsageDiagnosticRedactor.redact(input)

        XCTAssertFalse(output.contains("diagnose-secret"))
        XCTAssertTrue(output.contains("private-token=<redacted>"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(output.utf8)))
    }

    func testSourceEnvironmentDoesNotCountAsCredential() async {
        let entry = UsageProviderEntry(
            id: "poe",
            name: "Poe",
            logo: "poe",
            fallbackSystemImage: "p.circle",
            isConfigured: { false },
            fetch: {
                throw DiagnosticTestError.message(
                    "Missing API token for dev@example.com Authorization: Bearer sk-secret1234567890")
            })

        let diagnostic = await UsageProviderDiagnostics.diagnose(
            entry: entry,
            source: "auto",
            config: .default,
            environment: ["CONDUCTOR_USAGE_POE_SOURCE": "auto"])

        XCTAssertFalse(diagnostic.configured)
        XCTAssertEqual(diagnostic.error?.category, "auth")
        XCTAssertFalse(diagnostic.error?.message.contains("dev@example.com") ?? true)
        XCTAssertFalse(diagnostic.error?.message.contains("sk-secret1234567890") ?? true)
    }

    func testDiagnoseUnlessCancelledPropagatesCancellation() async throws {
        let entry = UsageProviderEntry(
            id: "poe",
            name: "Poe",
            logo: "poe",
            fallbackSystemImage: "p.circle",
            isConfigured: { true },
            fetch: {
                throw CancellationError()
            })

        do {
            _ = try await UsageProviderDiagnostics.diagnoseUnlessCancelled(
                entry: entry,
                source: "auto",
                config: .default)
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected: serve deadline cancellation must not be converted into a diagnostic error.
        }
    }

    func testRepairActionsSuggestCredentialForMissingKey() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "poe",
            providerName: "Poe",
            configured: false,
            errorMessage: "Missing API token",
            category: "auth")

        XCTAssertTrue(actions.contains { $0.kind == .configureCredential })
        XCTAssertTrue(actions.contains { $0.detail.contains("POE_API_KEY") })
        XCTAssertEqual(
            actions.first { $0.id == "configureCredential" }?.url,
            "https://poe.com/api/keys")
    }

    func testRepairActionsSuggestSeparateBaseURLForLiteLLM() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "litellm",
            providerName: "LiteLLM",
            configured: false,
            errorMessage: "Missing LiteLLM base URL. Set LITELLM_BASE_URL",
            category: "configuration")

        let configureActions = actions.filter { $0.kind == .configureCredential }
        XCTAssertGreaterThanOrEqual(configureActions.count, 2)
        XCTAssertTrue(actions.contains { $0.id == "configure-base-url" && $0.detail.contains("LITELLM_BASE_URL") })
        XCTAssertEqual(
            actions.first { $0.id == "configure-base-url" }?.command,
            "conductorctl config set --provider litellm --key baseURL --value <url>")
        XCTAssertTrue(actions.contains { $0.id == "configureCredential" && $0.detail.contains("LITELLM_API_KEY") })
        XCTAssertEqual(
            actions.first { $0.id == "configureCredential" }?.command,
            "conductorctl config set-api-key --provider litellm --api-key <key>")
    }

    func testRepairActionsSuggestProjectDeploymentForAzureOpenAI() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "azureopenai",
            providerName: "Azure OpenAI",
            configured: true,
            errorMessage: "Missing deployment name. Set AZURE_OPENAI_DEPLOYMENT_NAME",
            category: "configuration")

        let projectAction = actions.first { $0.id == "configure-project" }
        XCTAssertTrue(projectAction?.detail.contains("AZURE_OPENAI_DEPLOYMENT_NAME") == true)
        XCTAssertEqual(
            projectAction?.command,
            "conductorctl config set --provider azureopenai --key projectID --value <project>")
    }

    func testRepairActionsSuggestOpenAIBillingKeyForForbiddenCreditGrants() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "openai",
            providerName: "OpenAI",
            configured: true,
            errorMessage: "OpenAI credit grants returned 403 forbidden for project-level key",
            category: "auth")

        let billingAction = actions.first { $0.id == "configure-openai-billing-key" }
        XCTAssertTrue(billingAction?.detail.contains("OPENAI_ADMIN_KEY") == true)
        XCTAssertEqual(
            billingAction?.command,
            "conductorctl config set-api-key --provider openai --api-key <key>")
        XCTAssertTrue(actions.contains { $0.kind == .configureCredential && $0.detail.contains("OPENAI_API_KEY") })
        XCTAssertEqual(
            actions.first { $0.id == "configure-openai-billing-key" }?.url,
            "https://platform.openai.com/usage")
    }

    func testRepairActionsSuggestLiteLLMVirtualKeyForMissingUserID() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "litellm",
            providerName: "LiteLLM",
            configured: true,
            errorMessage: "LiteLLM key info missing user_id or team_id",
            category: "auth")

        XCTAssertTrue(actions.contains { $0.id == "configure-litellm-virtual-key" && $0.detail.contains("user_id") })
    }

    func testRepairActionsSuggestCLICommandForCodexAuth() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "codex",
            providerName: "Codex",
            configured: true,
            errorMessage: "401 unauthorized",
            category: "auth")

        XCTAssertTrue(actions.contains { $0.kind == .signIn && $0.command == "codex login --device-auth" })
    }

    func testRepairActionsSuggestConfigCommandForSourceModeMismatch() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "codex",
            providerName: "Codex",
            configured: true,
            errorMessage: "wrong account source mode mismatch",
            category: "configuration",
            source: "web")

        XCTAssertEqual(
            actions.first { $0.id == "adjust-source-mode" }?.command,
            "conductorctl config set --provider codex --key sourceMode --value <source>")
    }

    func testRepairActionsReadCLICommandFromProviderCatalog() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "qwen",
            providerName: "Qwen",
            configured: true,
            errorMessage: "session token expired",
            category: "auth")

        XCTAssertTrue(actions.contains { $0.kind == .signIn && $0.command == "qwen login" })
    }

    func testRepairActionsSuggestManualCookieCommandForSessionProviders() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "commandcode",
            providerName: "Command Code",
            configured: true,
            errorMessage: "session expired",
            category: "auth",
            source: "auto")

        let cookieAction = actions.first { $0.id == "configure-cookie-header" }
        XCTAssertEqual(cookieAction?.kind, .configureCredential)
        XCTAssertEqual(
            cookieAction?.command,
            "conductorctl config set-cookie --provider commandcode --cookie <cookie>")
        XCTAssertTrue(cookieAction?.detail.contains("COMMANDCODE_SESSION_TOKEN") == true)
        XCTAssertTrue(cookieAction?.detail.contains("token account") == true)
    }

    func testRepairActionsSuggestManualCookieEnvironmentForManusSessionID() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "manus",
            providerName: "Manus",
            configured: false,
            errorMessage: "missing session_id cookie",
            category: "auth",
            source: "web")

        XCTAssertTrue(actions.contains {
            $0.id == "configureCredential" &&
                $0.detail.contains("MANUS_SESSION_ID") &&
                $0.detail.contains("conductorctl config set-cookie --provider manus")
        })
        XCTAssertTrue(actions.contains {
            $0.id == "configure-cookie-header" &&
                $0.command == "conductorctl config set-cookie --provider manus --cookie <cookie>"
        })
    }

    func testSettingsSummaryIncludesProviderMetadataAndEnvironmentHints() {
        let settings = UsageProviderDiagnosticSettingsSummary(
            providerID: "gemini",
            config: nil,
            signInCommand: "gemini auth",
            dashboardURL: "https://gemini.google.com",
            changelogURL: "https://github.com/google-gemini/gemini-cli/releases")

        XCTAssertEqual(settings.signInCommand, "gemini auth")
        XCTAssertEqual(settings.dashboardURL, "https://gemini.google.com")
        XCTAssertEqual(settings.changelogURL, "https://github.com/google-gemini/gemini-cli/releases")
        XCTAssertEqual(settings.sourceModes, ["auto", "api"])
        XCTAssertTrue(settings.environmentHints.sourceMode.contains("CONDUCTOR_USAGE_GEMINI_SOURCE"))
    }

    func testTextRendererIncludesProviderMetadataAndEnvironmentHints() {
        let diagnostic = UsageProviderDiagnosticExport(
            schemaVersion: "1.0",
            generatedAt: Date(timeIntervalSince1970: 0),
            provider: "qwen",
            displayName: "Qwen",
            source: "api",
            sourceMode: "api",
            configured: false,
            auth: UsageProviderDiagnosticAuthSummary(
                providerID: "qwen",
                providerConfig: nil,
                environment: [:],
                selectedAccount: nil,
                locallyConfigured: false),
            selectedAccount: nil,
            settings: UsageProviderDiagnosticSettingsSummary(
                providerID: "qwen",
                config: nil,
                signInCommand: "qwen login",
                dashboardURL: "https://modelstudio.console.alibabacloud.com/ap-southeast-1/?tab=coding-plan#/efm/coding_plan",
                changelogURL: nil),
            usage: nil,
            storage: UsageProviderDiagnosticStorageSummary(footprint: ProviderStorageFootprint(
                providerID: "codex",
                totalBytes: 2048,
                paths: [NSHomeDirectory() + "/.codex"],
                missingPaths: [NSHomeDirectory() + "/.codex/missing"],
                unreadablePaths: [NSHomeDirectory() + "/.codex/token=abc1234567890"],
                components: [
                    .init(path: NSHomeDirectory() + "/.codex/sessions", totalBytes: 2048),
                ],
                updatedAt: Date(timeIntervalSince1970: 0))),
            fetchAttempts: [],
            error: nil,
            repairActions: [],
            redaction: UsageProviderDiagnosticRedactionSummary())

        let output = UsageProviderDiagnosticTextRenderer.render([diagnostic])

        XCTAssertTrue(output.contains("sign in: qwen login"))
        XCTAssertTrue(output.contains("source modes: auto, web, api"))
        XCTAssertTrue(output.contains("dashboard: https://modelstudio.console.alibabacloud.com"))
        XCTAssertTrue(output.contains("api key env: ALIBABA_CODING_PLAN_API_KEY"))
        XCTAssertTrue(output.contains("source env: CONDUCTOR_USAGE_QWEN_SOURCE"))
        XCTAssertTrue(output.contains("storage: 2 KB across 1 paths"))
        XCTAssertTrue(output.contains("storage missing paths: 1"))
        XCTAssertTrue(output.contains("storage missing path: ~/.codex/missing"))
        XCTAssertTrue(output.contains("storage unreadable paths: 1"))
        XCTAssertTrue(output.contains("storage unreadable path: ~/.codex/token=<redacted>"))
        XCTAssertTrue(output.contains("storage component: sessions 2 KB - ~/.codex/sessions"))
        XCTAssertTrue(output.contains("cleanup: Manual cleanup: sessions 2 KB - ~/.codex/sessions"))
    }

    func testDiagnosticReportsActualSourceSeparatelyFromRequestedSourceMode() async {
        let entry = UsageProviderEntry(
            id: "windsurf",
            name: "Windsurf",
            logo: "windsurf",
            fallbackSystemImage: "w.circle",
            isConfigured: { true },
            fetch: {
                UsageSnapshot(
                    sourceLabel: "local",
                    primary: RateWindow(title: "Daily", usedPercent: 20))
            })

        let diagnostic = await UsageProviderDiagnostics.diagnose(
            entry: entry,
            source: "auto",
            config: .default)

        XCTAssertEqual(diagnostic.source, "local")
        XCTAssertEqual(diagnostic.sourceMode, "auto")
        XCTAssertEqual(diagnostic.usage?.sourceLabel, "local")
        XCTAssertEqual(diagnostic.fetchAttempts.first?.kind, "local")

        let output = UsageProviderDiagnosticTextRenderer.render([diagnostic])
        XCTAssertTrue(output.contains("source: local"))
        XCTAssertTrue(output.contains("source mode: auto"))
    }

    func testStorageSummaryRedactsAndLimitsDiagnosticPayload() {
        let footprint = ProviderStorageFootprint(
            providerID: "codex",
            totalBytes: 4096,
            paths: [NSHomeDirectory() + "/.codex"],
            missingPaths: [NSHomeDirectory() + "/.codex/missing"],
            unreadablePaths: [NSHomeDirectory() + "/.codex/private-token=abc1234567890"],
            components: [
                .init(path: NSHomeDirectory() + "/.codex/sessions", totalBytes: 3072),
                .init(path: NSHomeDirectory() + "/.codex/cache", totalBytes: 1024),
            ],
            updatedAt: Date(timeIntervalSince1970: 10))

        let summary = UsageProviderDiagnosticStorageSummary(
            footprint: footprint,
            maxComponents: 1,
            maxRecommendations: 1)

        XCTAssertEqual(summary.pathCount, 1)
        XCTAssertEqual(summary.missingPathCount, 1)
        XCTAssertEqual(summary.unreadablePathCount, 1)
        XCTAssertEqual(summary.missingPaths, ["~/.codex/missing"])
        XCTAssertEqual(summary.topComponents.map(\.path), ["~/.codex/sessions"])
        XCTAssertEqual(summary.cleanupRecommendations.count, 1)
        XCTAssertFalse(summary.unreadablePaths.joined().contains("abc1234567890"))
        XCTAssertEqual(summary.unreadablePaths, ["~/.codex/private-token=<redacted>"])
        let home = NSHomeDirectory()
        if home.hasPrefix("/var/") {
            let privateHomePath = "/private" + home + "/.codex/private-token=abc1234567890"
            XCTAssertEqual(
                UsageProviderDiagnosticStorageSummary.safePath(privateHomePath),
                "~/.codex/private-token=<redacted>")
        }
    }

    func testRepairActionsPreferWebSignInForCodexDashboardAuth() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "codex",
            providerName: "Codex",
            configured: true,
            errorMessage: "OpenAI dashboard session expired",
            category: "auth",
            source: "web")

        XCTAssertTrue(actions.contains { $0.kind == .signIn && $0.command == nil && $0.title.contains("网页") })
        XCTAssertFalse(actions.contains { $0.command == "codex login --device-auth" })
        XCTAssertEqual(
            actions.first { $0.kind == .signIn && $0.command == nil }?.url,
            "https://chatgpt.com/codex/settings/usage")
    }

    func testRepairActionsAttachDashboardURLForCookieBackedWebLogin() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "cursor",
            providerName: "Cursor",
            configured: true,
            errorMessage: "Cursor login session expired",
            category: "auth",
            source: "web")

        let signIn = actions.first { $0.kind == .signIn && $0.title.contains("网页") }
        XCTAssertEqual(signIn?.command, nil)
        XCTAssertEqual(signIn?.url, "https://cursor.com/dashboard?tab=usage")
    }

    func testRepairActionsTreatHyphenatedSignInAsAuth() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "mimo",
            providerName: "Xiaomi MiMo",
            configured: true,
            errorMessage: "Xiaomi MiMo requires sign-in",
            source: "web")

        XCTAssertTrue(actions.contains { $0.kind == .signIn && $0.title.contains("网页") })
        XCTAssertFalse(actions.contains { $0.kind == .copyDiagnostics })
    }

    func testRepairActionsUseLocalCredentialGuidanceForZed() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "zed",
            providerName: "Zed",
            configured: false,
            errorMessage: "Not signed in to Zed. Sign in with GitHub from the Zed editor first.",
            category: "auth")

        XCTAssertTrue(actions.contains { $0.kind == .configureCredential && $0.detail.contains("Zed 编辑器") })
        XCTAssertTrue(actions.contains { $0.kind == .signIn && $0.title.contains("本机登录态") })
        XCTAssertFalse(actions.contains { $0.detail.contains("浏览器 Cookie") })
    }

    func testDashboardPolicyDiagnosticsUseAuthorityReason() {
        let decision = CodexDashboardAuthorityDecision(
            disposition: .failClosed,
            reason: .providerAccountLacksExactOwnershipProof,
            allowedEffects: [],
            cleanup: Set(CodexDashboardCleanup.allCases))
        let diagnostic = UsageProviderDiagnosticError(
            error: OpenAIDashboardUsageError.policyRejected(decision),
            authConfigured: true)

        XCTAssertEqual(diagnostic.category, "configuration")
        XCTAssertTrue(diagnostic.message.contains("provider account"))
    }

    func testDashboardNoDataCloudflareClassifiesAsNetwork() {
        let diagnostic = UsageProviderDiagnosticError(
            error: OpenAIDashboardUsageError.noDashboardData("Cloudflare challenge cf-ray"),
            authConfigured: true)

        XCTAssertEqual(diagnostic.category, "network")
    }

    func testMissingBaseURLClassifiesAsConfiguration() {
        let diagnostic = UsageProviderDiagnosticError(
            error: DiagnosticTestError.message("Missing LiteLLM base URL. Set LITELLM_BASE_URL"),
            authConfigured: true)

        XCTAssertEqual(diagnostic.category, "configuration")
    }

    func testRepairActionsClassifyCloudflareAndKeychain() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "openai",
            providerName: "OpenAI",
            configured: true,
            errorMessage: "Cloudflare challenge detected after Chrome Safe Storage keychain prompt",
            category: "network")

        XCTAssertTrue(actions.contains { $0.kind == .solveCloudflare })
        XCTAssertTrue(actions.contains { $0.kind == .allowKeychain })
        XCTAssertEqual(
            actions.first { $0.kind == .solveCloudflare }?.url,
            "https://platform.openai.com/usage")
    }

    func testRepairActionsIncludeStatusPageForNetworkProvider() {
        let actions = UsageProviderRepairActions.actions(
            providerID: "claude",
            providerName: "Claude",
            configured: true,
            errorMessage: "NSURLErrorDomain SSL error",
            category: "network",
            hasStatusPage: true,
            statusURL: "https://status.anthropic.com/")

        XCTAssertTrue(actions.contains { $0.kind == .checkNetwork })
        XCTAssertTrue(actions.contains { $0.kind == .checkProviderStatus })
        XCTAssertEqual(
            actions.first { $0.kind == .checkProviderStatus }?.url,
            "https://status.anthropic.com/")
    }
}

private enum DiagnosticTestError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}
