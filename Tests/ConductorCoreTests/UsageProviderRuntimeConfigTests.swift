import XCTest
@testable import ConductorCore
#if os(macOS)
import SweetCookieKit
#endif

final class UsageProviderRuntimeConfigTests: XCTestCase {
    func testManualCookieHeaderUsesProviderScopedEnvAndStripsCookiePrefix() {
        let env = [
            "CONDUCTOR_USAGE_CURSOR_COOKIE": " Cookie: a=1; b=2 ",
        ]

        XCTAssertEqual(
            UsageProviderRuntimeConfig.manualCookieHeader(providerID: "cursor", env: env),
            "a=1; b=2")
    }

    func testCookieHeaderNormalizerExtractsCurlCookieArguments() {
        XCTAssertEqual(
            CookieHeaderNormalizer.normalize(#"curl -H "Cookie: a=1; b=2" https://example.test"#),
            "a=1; b=2")
        XCTAssertEqual(
            CookieHeaderNormalizer.normalize(#"curl --cookie 'session=abc; flag=true' https://example.test"#),
            "session=abc; flag=true")
        XCTAssertEqual(
            CookieHeaderNormalizer.pairs(from: " a=1; b = two ; missing ")
                .map { "\($0.name)=\($0.value)" },
            ["a=1", "b=two"])
    }

    func testOpenCodeManualCookieHeadersKeepOnlySessionCookies() {
        let header = "other=drop; auth=keep; theme=dark; __Host-auth=host"
        XCTAssertEqual(
            OpenCodeUsageFetcher.cookieHeader(env: ["CONDUCTOR_USAGE_OPENCODE_COOKIE": header]),
            "auth=keep; __Host-auth=host")
        XCTAssertEqual(
            OpenCodeGoUsageFetcher.cookieHeader(env: ["CONDUCTOR_USAGE_OPENCODEGO_COOKIE": header]),
            "auth=keep; __Host-auth=host")
        XCTAssertNil(OpenCodeGoUsageFetcher.cookieHeader(env: [
            "CONDUCTOR_USAGE_OPENCODEGO_COOKIE": "theme=dark",
            "CONDUCTOR_USAGE_OPENCODEGO_COOKIE_SOURCE": "manual",
        ]))
        XCTAssertFalse(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "opencodego",
            env: ["CONDUCTOR_USAGE_OPENCODEGO_COOKIE_SOURCE": "manual"]))
    }

    func testMiniMaxManualCookieSourceDoesNotImplyBrowserSession() {
        XCTAssertFalse(MiniMaxUsageFetcher.hasSession(env: [
            "CONDUCTOR_USAGE_MINIMAX_COOKIE_SOURCE": "manual",
        ]))
        XCTAssertEqual(MiniMaxUsageFetcher.cookieHeader(env: [
            "CONDUCTOR_USAGE_MINIMAX_COOKIE": "Cookie: HERTZ-SESSION=abc; other=1",
            "CONDUCTOR_USAGE_MINIMAX_COOKIE_SOURCE": "manual",
        ]), "HERTZ-SESSION=abc; other=1")
    }

    func testQwenTokenPrefersCodingPlanEnvironmentLikeCodexBar() {
        XCTAssertEqual(QwenUsageFetcher.token(env: [
            "DASHSCOPE_API_KEY": "dashscope-token",
            "ALIBABA_QWEN_API_KEY": "qwen-token",
            "ALIBABA_CODING_PLAN_API_KEY": "coding-plan-token",
        ]), "coding-plan-token")
        XCTAssertEqual(QwenUsageFetcher.token(env: [
            "DASHSCOPE_API_KEY": "dashscope-token",
            "ALIBABA_QWEN_API_KEY": "qwen-token",
        ]), "qwen-token")
        XCTAssertEqual(QwenUsageFetcher.token(env: [
            "DASHSCOPE_API_KEY": "dashscope-token",
        ]), "dashscope-token")
    }

    func testKiloSourceModeRoutesBearerTokensLikeCodexBar() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilo-source-routing-\(UUID().uuidString)", isDirectory: true)
        let authURL = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("kilo", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
        try FileManager.default.createDirectory(
            at: authURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try #"{"kilo":{"access":"cli-token"}}"#.write(to: authURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(KiloUsageFetcher.token(env: ["HOME": root.path]), "cli-token")
        XCTAssertEqual(KiloUsageFetcher.token(env: [
            "HOME": root.path,
            "KILO_API_KEY": "api-token",
        ]), "api-token")
        XCTAssertNil(KiloUsageFetcher.token(env: [
            "HOME": root.path,
            "CONDUCTOR_USAGE_KILO_SOURCE": "api",
        ]))
        XCTAssertEqual(KiloUsageFetcher.token(env: [
            "HOME": root.path,
            "KILO_API_KEY": "api-token",
            "CONDUCTOR_USAGE_KILO_SOURCE": "cli",
        ]), "cli-token")
        XCTAssertNil(KiloUsageFetcher.token(env: [
            "HOME": root.path,
            "KILO_API_KEY": "api-token",
            "CONDUCTOR_USAGE_KILO_SOURCE": "web",
        ]))
    }

    func testCookieSourceManualAndOffDisableBrowserCookieReads() {
        XCTAssertFalse(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "cursor",
            env: ["CONDUCTOR_USAGE_CURSOR_COOKIE_SOURCE": "manual"]))
        XCTAssertFalse(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "cursor",
            env: ["CONDUCTOR_USAGE_CURSOR_COOKIE_SOURCE": " off "]))
        XCTAssertFalse(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "cursor",
            env: ["CONDUCTOR_USAGE_CURSOR_SOURCE": "manual"]))
        XCTAssertFalse(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "cursor",
            env: ["CONDUCTOR_USAGE_CURSOR_SOURCE": "api"]))
    }

    func testCookieSourceDefaultsToBrowserReads() {
        XCTAssertTrue(UsageProviderRuntimeConfig.shouldReadBrowserCookies(providerID: "cursor", env: [:]))
        XCTAssertTrue(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "cursor",
            env: ["CONDUCTOR_USAGE_CURSOR_COOKIE_SOURCE": "browser"]))
        XCTAssertTrue(UsageProviderRuntimeConfig.shouldReadBrowserCookies(
            providerID: "cursor",
            env: ["CONDUCTOR_USAGE_CURSOR_COOKIE_SOURCE": "auto"]))
    }

    #if os(macOS)
    func testBrowserCookieAccessGateSuppressesDefaultHomeUnderTests() {
        let decision = BrowserCookieAccessGate.cookieStoreAccessDecision(
            homeDirectories: BrowserCookieClient.defaultHomeDirectories(),
            processName: "swiftpm-testing-helper",
            environment: [:])

        XCTAssertEqual(decision, .suppressed)
        XCTAssertEqual(BrowserCookieAccessGate.cookieStoreAccessDecision(
            homeDirectories: BrowserCookieClient.defaultHomeDirectories(),
            processName: "swiftpm-testing-helper",
            environment: [BrowserCookieAccessGate.allowTestCookieAccessEnvironmentKey: "1"]), .allowed)
    }

    func testBrowserCookieAccessGateRecordsDeniedChromiumCooldown() {
        BrowserCookieAccessGate.resetForTesting()
        let now = Date(timeIntervalSince1970: 10)

        BrowserCookieAccessGate.recordDenied(for: .chrome, now: now)

        XCTAssertFalse(BrowserCookieAccessGate.shouldAttempt(.chrome, now: now.addingTimeInterval(1)))
        BrowserCookieAccessGate.resetForTesting()
    }
    #endif

    func testWebTimeoutUsesProviderScopedEnv() {
        XCTAssertEqual(UsageProviderRuntimeConfig.webTimeout(
            providerID: "codex",
            defaultValue: 35,
            env: [:]), 35)
        XCTAssertEqual(UsageProviderRuntimeConfig.webTimeout(
            providerID: "codex",
            defaultValue: 35,
            env: ["CONDUCTOR_USAGE_CODEX_WEB_TIMEOUT": " 12.5 "]), 12.5)
        XCTAssertEqual(UsageProviderRuntimeConfig.webTimeout(
            providerID: "codex",
            defaultValue: 35,
            env: ["CONDUCTOR_USAGE_CODEX_WEB_TIMEOUT": "0"]), 35)
        XCTAssertEqual(UsageProviderRuntimeConfig.webTimeout(
            providerID: "codex",
            defaultValue: 35,
            env: ["CONDUCTOR_USAGE_CODEX_WEB_TIMEOUT": "not-a-number"]), 35)
    }

    func testWebDebugDumpHTMLUsesProviderScopedEnv() {
        XCTAssertFalse(UsageProviderRuntimeConfig.webDebugDumpHTML(providerID: "codex", env: [:]))
        XCTAssertTrue(UsageProviderRuntimeConfig.webDebugDumpHTML(
            providerID: "codex",
            env: ["CONDUCTOR_USAGE_CODEX_WEB_DEBUG_DUMP_HTML": "1"]))
        XCTAssertTrue(UsageProviderRuntimeConfig.webDebugDumpHTML(
            providerID: "codex",
            env: ["CONDUCTOR_USAGE_CODEX_WEB_DEBUG_DUMP_HTML": " true "]))
        XCTAssertFalse(UsageProviderRuntimeConfig.webDebugDumpHTML(
            providerID: "codex",
            env: ["CONDUCTOR_USAGE_CODEX_WEB_DEBUG_DUMP_HTML": "0"]))
    }
}
