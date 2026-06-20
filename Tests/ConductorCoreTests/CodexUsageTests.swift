import Foundation
import XCTest
@testable import ConductorCore

final class CodexUsageTests: XCTestCase {
    func testMapsCodexRPCRateLimitsToUsageSnapshot() {
        let snapshot = CodexUsageFetcher.mapRPCSnapshot(
            rateLimits: CodexUsageFetcher.RPCRateLimitSnapshot(
                primary: CodexUsageFetcher.RPCRateLimitWindow(
                    usedPercent: 56.4,
                    windowDurationMins: 300,
                    resetsAt: 1_781_234_567),
                secondary: CodexUsageFetcher.RPCRateLimitWindow(
                    usedPercent: 9.2,
                    windowDurationMins: 10_080,
                    resetsAt: 1_781_999_999),
                credits: nil,
                planType: "pro"),
            account: CodexUsageFetcher.RPCAccountResponse(
                account: .chatgpt(email: "dev@example.com", planType: "plus"),
                requiresOpenaiAuth: false))

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.accountLabel, "dev@example.com")
        XCTAssertEqual(snapshot.session?.usedPercent, 56)
        XCTAssertEqual(snapshot.session?.windowSeconds, 18_000)
        XCTAssertEqual(snapshot.session?.resetAt, Date(timeIntervalSince1970: 1_781_234_567))
        XCTAssertEqual(snapshot.weekly?.usedPercent, 9)
        XCTAssertEqual(snapshot.weekly?.windowSeconds, 604_800)
        XCTAssertEqual(snapshot.weekly?.resetAt, Date(timeIntervalSince1970: 1_781_999_999))
    }

    func testCodexRPCPlanFallsBackToAccountPlan() {
        let snapshot = CodexUsageFetcher.mapRPCSnapshot(
            rateLimits: CodexUsageFetcher.RPCRateLimitSnapshot(
                primary: nil,
                secondary: nil,
                credits: nil,
                planType: nil),
            account: CodexUsageFetcher.RPCAccountResponse(
                account: .chatgpt(email: "dev@example.com", planType: "team"),
                requiresOpenaiAuth: false))

        XCTAssertEqual(snapshot.planType, "team")
        XCTAssertEqual(snapshot.accountLabel, "dev@example.com")
        XCTAssertTrue(snapshot.isEmpty)
    }

    func testMapsCodexRPCCreditsToProviderCost() {
        let snapshot = CodexUsageFetcher.mapRPCSnapshot(
            rateLimits: CodexUsageFetcher.RPCRateLimitSnapshot(
                primary: nil,
                secondary: nil,
                credits: CodexUsageFetcher.RPCCreditsSnapshot(
                    hasCredits: true,
                    unlimited: false,
                    balance: "12.34"),
                planType: "pro"))

        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertEqual(snapshot.providerCost?.used, 12.34)
        XCTAssertEqual(snapshot.providerCost?.limit, 0)
        XCTAssertEqual(snapshot.providerCost?.currencyCode, "USD")

        let usage = UsageSnapshot(codexSnapshot: snapshot)
        XCTAssertEqual(usage.providerCost?.used, 12.34)
        XCTAssertFalse(usage.isEmpty)
    }

    func testRecoversCodexRPCUsageFromErrorBody() throws {
        let message = """
        request failed status=500 body={
          "email": "dev@example.com",
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": {
              "used_percent": 64,
              "reset_at": 1781234567,
              "limit_window_seconds": 18000
            },
            "secondary_window": {
              "used_percent": 12,
              "reset_at": 1781999999,
              "limit_window_seconds": 604800
            }
          }
        } tail={ignored}
        """

        let snapshot = try XCTUnwrap(CodexUsageFetcher.recoverRPCSnapshotFromErrorMessageForTesting(message))

        XCTAssertEqual(snapshot.accountLabel, "dev@example.com")
        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.session?.usedPercent, 64)
        XCTAssertEqual(snapshot.session?.windowSeconds, 18_000)
        XCTAssertEqual(snapshot.session?.resetAt, Date(timeIntervalSince1970: 1_781_234_567))
        XCTAssertEqual(snapshot.weekly?.usedPercent, 12)
        XCTAssertEqual(snapshot.weekly?.windowSeconds, 604_800)
        XCTAssertEqual(snapshot.weekly?.resetAt, Date(timeIntervalSince1970: 1_781_999_999))
    }

    func testRecoversCodexRPCCreditsFromErrorBody() throws {
        let message = #"failed body={"email":"dev@example.com","plan_type":"team","credits":{"balance":"$8.75"},"note":"brace } inside string"} trailing"#

        let snapshot = try XCTUnwrap(CodexUsageFetcher.recoverRPCSnapshotFromErrorMessageForTesting(message))

        XCTAssertEqual(snapshot.accountLabel, "dev@example.com")
        XCTAssertEqual(snapshot.planType, "team")
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.providerCost?.used, 8.75)
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testCodexRPCRecoveryRejectsUsageWithoutSessionLane() {
        let message = """
        failed body={
          "email": "dev@example.com",
          "plan_type": "prolite",
          "rate_limit": {
            "primary_window": {
              "used_percent": "oops",
              "limit_window_seconds": 18000,
              "reset_at": 1781234567
            },
            "secondary_window": {
              "used_percent": 19,
              "limit_window_seconds": 604800,
              "reset_at": 1781999999
            }
          }
        }
        """

        XCTAssertNil(CodexUsageFetcher.recoverRPCSnapshotFromErrorMessageForTesting(message))
    }

    func testCodexRPCRecoveryKeepsCreditsWhenUsageWindowsAreMalformed() throws {
        let message = """
        failed body={
          "email": "dev@example.com",
          "plan_type": "prolite",
          "rate_limit": {
            "primary_window": {
              "used_percent": "oops",
              "limit_window_seconds": 18000,
              "reset_at": 1781234567
            },
            "secondary_window": {
              "used_percent": 19,
              "limit_window_seconds": 604800,
              "reset_at": 1781999999
            }
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": "14.5"
          }
        }
        """

        let snapshot = try XCTUnwrap(CodexUsageFetcher.recoverRPCSnapshotFromErrorMessageForTesting(message))

        XCTAssertEqual(snapshot.accountLabel, "dev@example.com")
        XCTAssertEqual(snapshot.planType, "prolite")
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.providerCost?.used, 14.5)
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testCodexCLILaunchGateOnlySkipsBackgroundRefreshes() {
        let gate = CodexCLILaunchGate.shared
        gate.resetForTesting()
        defer { gate.resetForTesting() }

        let throttled = gate.recordLaunchFailure(
            binary: "/usr/local/bin/codex",
            message: "Operation not permitted")

        XCTAssertNotNil(throttled)
        XCTAssertNil(gate.backgroundSkipMessage(
            binary: "/usr/local/bin/codex",
            interaction: .foreground))
        XCTAssertEqual(gate.backgroundSkipMessage(
            binary: "/usr/local/bin/codex",
            interaction: .background),
            throttled)
    }

    func testCodexCLILaunchGateScopesFailuresByBinaryAndExpires() {
        let gate = CodexCLILaunchGate.shared
        gate.resetForTesting()
        defer { gate.resetForTesting() }

        let now = Date(timeIntervalSince1970: 1_000)
        let binary = "/usr/local/bin/codex"
        let throttled = gate.recordLaunchFailure(
            binary: binary,
            message: "Operation not permitted",
            now: now)

        XCTAssertNotNil(throttled)
        XCTAssertEqual(
            gate.backgroundSkipMessage(
                binary: binary,
                now: now.addingTimeInterval(CodexCLILaunchGate.cooldown - 1),
                interaction: .background),
            throttled)
        XCTAssertNil(gate.backgroundSkipMessage(
            binary: "/opt/homebrew/bin/codex",
            now: now.addingTimeInterval(1),
            interaction: .background))
        XCTAssertNil(gate.backgroundSkipMessage(
            binary: binary,
            now: now.addingTimeInterval(CodexCLILaunchGate.cooldown + 1),
            interaction: .background))
    }

    func testCodexCLILaunchGateDoesNotThrottleTTYShutdownErrors() {
        let gate = CodexCLILaunchGate.shared
        gate.resetForTesting()
        defer { gate.resetForTesting() }

        XCTAssertNil(gate.recordLaunchFailure(
            binary: "codex",
            message: "openpty failed"))
        XCTAssertNil(gate.backgroundSkipMessage(
            binary: "codex",
            interaction: .background))
    }

    func testCodexRPCSessionKeyTracksAccountAndLaunchEnvironment() {
        let baseEnv = [
            "CODEX_HOME": "/Users/dev/.codex-alpha",
            "HOME": "/Users/dev",
            "PATH": "/usr/local/bin:/usr/bin",
            "XDG_CONFIG_HOME": "/Users/dev/.config",
        ]
        let baseKey = CodexUsageFetcher.codexRPCSessionKeyForTesting(env: baseEnv)

        var unrelated = baseEnv
        unrelated["TERM_PROGRAM"] = "Apple_Terminal"
        XCTAssertEqual(
            CodexUsageFetcher.codexRPCSessionKeyForTesting(env: unrelated),
            baseKey)

        let relevantChanges = [
            ("CONDUCTOR_CODEX_BINARY", "/tmp/codex-dev"),
            ("CODEX_BINARY", "/opt/codex"),
            ("CODEX_HOME", "/Users/dev/.codex-beta"),
            ("HOME", "/Users/other"),
            ("PATH", "/bin:/usr/bin"),
            ("XDG_CONFIG_HOME", "/tmp/xdg-config"),
        ]
        for (key, value) in relevantChanges {
            var env = baseEnv
            env[key] = value
            XCTAssertNotEqual(
                CodexUsageFetcher.codexRPCSessionKeyForTesting(env: env),
                baseKey,
                "\(key) must isolate app-server sessions")
        }
    }

    func testCodexRPCErrorDescriptionsKeepDiagnosticContext() throws {
        let message = "stdout closed stderr: permission denied | killed by macOS"

        XCTAssertEqual(
            CodexUsageFetcher.codexRPCErrorDescriptionForTesting(kind: "malformed", message: message),
            "Codex app-server returned invalid data: stdout closed stderr: permission denied | killed by macOS")
        XCTAssertEqual(
            CodexUsageFetcher.codexRPCErrorDescriptionForTesting(kind: "timeout", message: "initialize stderr: no reply"),
            "Codex app-server timed out waiting for initialize stderr: no reply")
    }

    func testCodexRPCFakeAppServerLifecycleIgnoresNotificationsAndWrongIDs() async throws {
        let result = try await CodexUsageFetcher.codexRPCFakeLifecycleForTesting()

        XCTAssertEqual(result.recordedMessages, [
            "request:1:initialize",
            "notify:initialized",
            "request:2:account/rateLimits/read",
            "request:3:account/read",
        ])
        XCTAssertEqual(result.accountLabel, "dev@example.com")
        XCTAssertEqual(result.planType, "pro")
        XCTAssertEqual(result.sessionUsedPercent, 42)
        XCTAssertEqual(result.weeklyUsedPercent, 11)
        XCTAssertTrue(result.isRunningAfterSuccess)
        XCTAssertEqual(result.shutdownCount, 1)
    }

    func testCodexRPCFakeAppServerTimeoutShutsDownTransport() async {
        let result = await CodexUsageFetcher.codexRPCFakeTimeoutForTesting()

        XCTAssertEqual(
            result.message,
            "Codex app-server timed out waiting for initialize stderr: no reply from fake app-server")
        XCTAssertEqual(result.shutdownCount, 1)
        XCTAssertFalse(result.isRunning)
    }

    func testCodexRPCFakeAppServerStdoutCloseKeepsDiagnostics() async {
        let result = await CodexUsageFetcher.codexRPCFakeStdoutClosedForTesting()

        XCTAssertEqual(
            result.message,
            "Codex app-server returned invalid data: stdout closed stderr: server closed pipe")
        XCTAssertEqual(result.shutdownCount, 1)
        XCTAssertFalse(result.isRunning)
    }

    func testParsesCodexHTTPCreditsToProviderCost() throws {
        let data = """
        {
          "plan_type": "pro",
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": "$19.50"
          }
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageFetcher.parse(data)

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
        XCTAssertEqual(snapshot.providerCost?.used, 19.50)
        XCTAssertFalse(snapshot.isEmpty)
    }

    func testParsesCodexAdditionalRateLimitsAsExtraWindows() throws {
        let data = """
        {
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "metered_feature": "gpt-5.3-codex-spark",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 12,
                  "reset_at": 1781234567,
                  "limit_window_seconds": 18000
                },
                "secondary_window": {
                  "used_percent": 34,
                  "reset_at": 1781999999,
                  "limit_window_seconds": 604800
                }
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexUsageFetcher.parse(data)

        XCTAssertEqual(snapshot.extraRateWindows.count, 2)
        XCTAssertEqual(snapshot.extraRateWindows[0].id, "codex-spark")
        XCTAssertEqual(snapshot.extraRateWindows[0].title, "Codex Spark 5-hour")
        XCTAssertEqual(snapshot.extraRateWindows[0].window.usedPercent, 12)
        XCTAssertEqual(snapshot.extraRateWindows[0].window.windowMinutes, 300)
        XCTAssertEqual(snapshot.extraRateWindows[0].window.resetsAt, Date(timeIntervalSince1970: 1_781_234_567))
        XCTAssertEqual(snapshot.extraRateWindows[1].id, "codex-spark-weekly")
        XCTAssertEqual(snapshot.extraRateWindows[1].title, "Codex Spark Weekly")
        XCTAssertEqual(snapshot.extraRateWindows[1].window.usedPercent, 34)
        XCTAssertEqual(snapshot.extraRateWindows[1].window.windowMinutes, 10_080)

        let usage = UsageSnapshot(codexSnapshot: snapshot)
        XCTAssertEqual(usage.extraRateWindows.map(\.id), ["codex-spark", "codex-spark-weekly"])
        XCTAssertFalse(usage.isEmpty)
    }

    func testDecodesCodexRateLimitResetCredits() throws {
        let data = """
        {
          "credits": [
            {
              "id": "expired",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "granted_at": "2026-05-18T00:39:53Z",
              "expires_at": "2026-06-17T00:39:53Z"
            },
            {
              "id": "next",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "granted_at": "2026-06-18T00:39:53.731630Z",
              "expires_at": "2026-07-18T00:39:53.731630Z",
              "redeem_started_at": null,
              "redeemed_at": null,
              "title": "One free rate limit reset",
              "description": "Thanks for using Codex!"
            },
            {
              "id": "future",
              "reset_type": "codex_rate_limits",
              "status": "future_status",
              "granted_at": "2026-06-12T04:03:43Z",
              "expires_at": "2026-07-10T04:03:43Z"
            }
          ],
          "available_count": 2
        }
        """.data(using: .utf8)!

        let now = ISO8601DateFormatter().date(from: "2026-06-19T00:00:00Z")!
        let snapshot = try CodexUsageFetcher.decodeRateLimitResetCredits(data, updatedAt: now)

        XCTAssertEqual(snapshot.availableCount, 2)
        XCTAssertEqual(snapshot.credits.count, 3)
        XCTAssertEqual(snapshot.credits[2].status, .unknown("future_status"))
        XCTAssertEqual(snapshot.nextExpiringAvailableCredit?.id, "next")
    }

    func testRejectsNegativeCodexRateLimitResetCreditCount() throws {
        let data = #"{"credits":[],"available_count":-1}"#.data(using: .utf8)!

        XCTAssertThrowsError(try CodexUsageFetcher.decodeRateLimitResetCredits(data)) { error in
            guard case CodexUsageError.invalidResponse = error else {
                XCTFail("Expected invalidResponse, got \(error)")
                return
            }
        }
    }

    func testFetchRefreshesStaleOAuthCredentialsAndPersistsAuthFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-usage-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let authURL = root.appendingPathComponent("auth.json")
        let staleIDToken = try Self.jwt(payload: ["email": "old@example.com"])
        let refreshedIDToken = try Self.jwt(payload: [
            "email": "fresh@example.com",
            "https://api.openai.com/auth": ["chatgpt_plan_type": "pro"],
        ])
        try """
        {
          "tokens": {
            "access_token": "old-access",
            "refresh_token": "old-refresh",
            "id_token": "\(staleIDToken)",
            "account_id": "acct_1"
          },
          "last_refresh": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!.write(to: authURL)

        CodexUsageMockURLProtocol.reset()
        CodexUsageMockURLProtocol.enqueue(
            url: "https://auth.openai.com/oauth/token",
            statusCode: 200,
            body: try Self.jsonString([
                "access_token": "new-access",
                "refresh_token": "new-refresh",
                "id_token": refreshedIDToken,
            ]))
        CodexUsageMockURLProtocol.enqueue(
            url: "https://chatgpt.com/backend-api/wham/usage",
            statusCode: 200,
            body: """
            {
              "plan_type": "pro",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 25,
                  "reset_at": 1781234567,
                  "limit_window_seconds": 18000
                }
              },
              "credits": { "balance": "7.25" }
            }
            """)
        CodexUsageMockURLProtocol.enqueue(
            url: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits",
            statusCode: 200,
            body: """
            {
              "credits": [
                {
                  "id": "RateLimitResetCredit_1",
                  "reset_type": "codex_rate_limits",
                  "status": "available",
                  "granted_at": "2026-06-18T00:39:53.731630Z",
                  "expires_at": "2099-07-18T00:39:53.731630Z",
                  "redeem_started_at": null,
                  "redeemed_at": null,
                  "title": "One free rate limit reset",
                  "description": "Thanks for using Codex!"
                }
              ],
              "available_count": 1
            }
            """)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CodexUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await CodexUsageFetcher.fetch(
            env: [
                "CODEX_HOME": root.path,
                "CONDUCTOR_USAGE_CODEX_SOURCE": "oauth",
            ],
            session: session)

        XCTAssertEqual(snapshot.planType, "pro")
        XCTAssertEqual(snapshot.accountLabel, "fresh@example.com")
        XCTAssertEqual(snapshot.session?.usedPercent, 25)
        XCTAssertEqual(snapshot.providerCost?.used, 7.25)
        XCTAssertEqual(snapshot.codexResetCredits?.availableCount, 1)
        XCTAssertEqual(snapshot.codexResetCredits?.nextExpiringAvailableCredit?.id, "RateLimitResetCredit_1")

        let requests = CodexUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://auth.openai.com/oauth/token")
        XCTAssertEqual(requests[1].url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "acct_1")
        XCTAssertEqual(requests[2].url?.absoluteString, "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "ChatGPT-Account-ID"), "acct_1")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "OpenAI-Beta"), "codex-1")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "originator"), "Codex Desktop")

        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: authURL)) as? [String: Any]
        let tokens = saved?["tokens"] as? [String: Any]
        XCTAssertEqual(tokens?["access_token"] as? String, "new-access")
        XCTAssertEqual(tokens?["refresh_token"] as? String, "new-refresh")
        XCTAssertEqual(tokens?["id_token"] as? String, refreshedIDToken)
        XCTAssertEqual(tokens?["account_id"] as? String, "acct_1")
        XCTAssertNotNil(saved?["last_refresh"] as? String)
    }

    func testDiscoversCodexBarManagedAccountsAndMergesLiveSystemAccount() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-accounts-\(UUID().uuidString)", isDirectory: true)
        let managedHome = root.appendingPathComponent("managed-alpha", isDirectory: true)
        let betaHome = root.appendingPathComponent("managed-beta", isDirectory: true)
        let liveHome = root.appendingPathComponent("live", isDirectory: true)
        let storeURL = root.appendingPathComponent("managed-codex-accounts.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Self.writeCodexAuth(
            home: managedHome,
            email: "dev@example.com",
            accountID: "acct_live",
            workspaceName: "Old Team")
        try Self.writeCodexAuth(
            home: betaHome,
            email: "team@example.com",
            accountID: "acct_beta",
            workspaceName: "Beta")
        try Self.writeCodexAuth(
            home: liveHome,
            email: "dev@example.com",
            accountID: "acct_live",
            workspaceName: "Team")

        let alphaID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let betaID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        try """
        {
          "version": 3,
          "accounts": [
            {
              "id": "\(alphaID.uuidString)",
              "email": "DEV@example.com",
              "providerAccountID": "acct_live",
              "workspaceLabel": "Old Team",
              "workspaceAccountID": "acct_live",
              "managedHomePath": "\(managedHome.path)",
              "createdAt": 1,
              "updatedAt": 2
            },
            {
              "id": "\(betaID.uuidString)",
              "email": "team@example.com",
              "providerAccountID": "acct_beta",
              "workspaceLabel": "Beta",
              "workspaceAccountID": "acct_beta",
              "managedHomePath": "\(betaHome.path)",
              "createdAt": 3,
              "updatedAt": 4
            }
          ]
        }
        """.data(using: .utf8)!.write(to: storeURL)

        let accounts = CodexManagedAccountDiscovery.tokenAccounts(env: [
            CodexManagedAccountDiscovery.storePathEnvironmentName: storeURL.path,
            "CODEX_HOME": liveHome.path,
        ])

        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.map(\.id), [alphaID, betaID])
        XCTAssertEqual(accounts[0].label, "dev@example.com - Team")
        XCTAssertEqual(accounts[0].token, liveHome.path)
        XCTAssertEqual(accounts[0].externalIdentifier, "live-system")
        XCTAssertEqual(accounts[0].organizationID, "acct_live")
        XCTAssertEqual(accounts[1].label, "team@example.com - Beta")
        XCTAssertEqual(accounts[1].token, betaHome.path)
    }

    func testManagedAccountStoreRemoveDeletesOnlySafeManagedHomes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-remove-\(UUID().uuidString)", isDirectory: true)
        let managedRoot = root.appendingPathComponent("managed-codex-homes", isDirectory: true)
        let managedHome = managedRoot.appendingPathComponent("alpha", isDirectory: true)
        let outsideHome = root.appendingPathComponent("outside-home", isDirectory: true)
        let storeURL = root.appendingPathComponent("managed-codex-accounts.json")
        try FileManager.default.createDirectory(at: managedHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let managedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let outsideID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let store = FileCodexManagedAccountStore(fileURL: storeURL)
        try store.storeAccounts(CodexManagedAccountSet(
            version: 3,
            accounts: [
                CodexManagedAccount(
                    id: managedID,
                    email: "managed@example.com",
                    providerAccountID: "acct_managed",
                    managedHomePath: managedHome.path,
                    createdAt: 1,
                    updatedAt: 2),
                CodexManagedAccount(
                    id: outsideID,
                    email: "outside@example.com",
                    providerAccountID: "acct_outside",
                    managedHomePath: outsideHome.path,
                    createdAt: 3,
                    updatedAt: 4),
            ]))

        let removedManaged = try store.removeManagedAccount(
            id: managedID,
            managedHomesRootURL: managedRoot)
        XCTAssertTrue(removedManaged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedHome.path))
        XCTAssertEqual(try store.loadAccounts().accounts.map(\.id), [outsideID])

        let removedOutside = try store.removeManagedAccount(
            id: outsideID,
            managedHomesRootURL: managedRoot)
        XCTAssertTrue(removedOutside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideHome.path))
        XCTAssertTrue(try store.loadAccounts().accounts.isEmpty)
    }

    func testManagedAccountAuthenticatorReauthenticatesAndReplacesManagedHome() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-reauth-\(UUID().uuidString)", isDirectory: true)
        let managedRoot = root.appendingPathComponent("managed-codex-homes", isDirectory: true)
        let oldHome = managedRoot.appendingPathComponent("old-home", isDirectory: true)
        let storeURL = root.appendingPathComponent("managed-codex-accounts.json")
        try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        try Self.writeCodexAuth(
            home: oldHome,
            email: "dev@example.com",
            accountID: "acct_old",
            workspaceName: "Old Team")
        defer { try? FileManager.default.removeItem(at: root) }

        let accountID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let store = FileCodexManagedAccountStore(fileURL: storeURL)
        try store.storeAccounts(CodexManagedAccountSet(
            version: 3,
            accounts: [
                CodexManagedAccount(
                    id: accountID,
                    email: "dev@example.com",
                    providerAccountID: "acct_old",
                    workspaceLabel: "Old Team",
                    workspaceAccountID: "acct_old",
                    managedHomePath: oldHome.path,
                    createdAt: 100,
                    updatedAt: 200),
            ]))

        let authenticator = CodexManagedAccountAuthenticator(
            store: store,
            managedHomesRootURL: managedRoot,
            loginRunner: { homePath, _ in
                do {
                    try Self.writeCodexAuth(
                        home: URL(fileURLWithPath: homePath, isDirectory: true),
                        email: "dev@example.com",
                        accountID: "acct_new",
                        workspaceName: "New Team")
                    return CodexLoginRunner.Result(outcome: .success, output: "")
                } catch {
                    return CodexLoginRunner.Result(outcome: .launchFailed(error.localizedDescription), output: "")
                }
            })

        let account = try await authenticator.authenticateManagedAccount(existingAccountID: accountID, timeout: 1)

        XCTAssertEqual(account.id, accountID)
        XCTAssertEqual(account.email, "dev@example.com")
        XCTAssertEqual(account.providerAccountID, "acct_new")
        XCTAssertEqual(account.workspaceLabel, "New Team")
        XCTAssertEqual(account.workspaceAccountID, "acct_new")
        XCTAssertEqual(account.createdAt, 100)
        XCTAssertNotEqual(account.managedHomePath, oldHome.path)
        XCTAssertTrue(account.managedHomePath.hasPrefix(managedRoot.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldHome.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: account.managedHomePath).appendingPathComponent("auth.json").path))

        let persisted = try store.loadAccounts()
        XCTAssertEqual(persisted.accounts.count, 1)
        XCTAssertEqual(persisted.accounts.first, account)
    }

    func testManagedAccountPromoterPreservesDisplacedLiveAccountAndSwapsAuth() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-managed-promote-\(UUID().uuidString)", isDirectory: true)
        let managedRoot = root.appendingPathComponent("managed-codex-homes", isDirectory: true)
        let targetHome = managedRoot.appendingPathComponent("target-home", isDirectory: true)
        let liveHome = root.appendingPathComponent("live", isDirectory: true)
        let storeURL = root.appendingPathComponent("managed-codex-accounts.json")
        try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        try Self.writeCodexAuth(
            home: targetHome,
            email: "target@example.com",
            accountID: "acct_target",
            workspaceName: "Target Team")
        try Self.writeCodexAuth(
            home: liveHome,
            email: "live@example.com",
            accountID: "acct_live",
            workspaceName: "Live Team")
        defer { try? FileManager.default.removeItem(at: root) }

        let targetID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let store = FileCodexManagedAccountStore(fileURL: storeURL)
        try store.storeAccounts(CodexManagedAccountSet(
            version: 3,
            accounts: [
                CodexManagedAccount(
                    id: targetID,
                    email: "target@example.com",
                    providerAccountID: "acct_target",
                    workspaceLabel: "Target Team",
                    workspaceAccountID: "acct_target",
                    managedHomePath: targetHome.path,
                    createdAt: 100,
                    updatedAt: 200),
            ]))

        let result = try CodexManagedAccountPromoter(
            store: store,
            liveHomeURL: liveHome,
            managedHomesRootURL: managedRoot)
            .promoteManagedAccount(id: targetID)

        XCTAssertEqual(result.outcome, .promoted)
        XCTAssertTrue(result.didMutateLiveAuth)
        guard case let .imported(importedID) = result.displacedLiveDisposition else {
            XCTFail("Expected displaced live account to be imported")
            return
        }

        XCTAssertEqual(try Self.codexAuthAccountID(home: liveHome), "acct_target")
        XCTAssertEqual(try Self.codexAuthAccountID(home: targetHome), "acct_target")

        let persisted = try store.loadAccounts()
        XCTAssertEqual(persisted.accounts.count, 2)
        XCTAssertNotNil(persisted.account(id: targetID))
        let imported = try XCTUnwrap(persisted.account(id: importedID))
        XCTAssertEqual(imported.email, "live@example.com")
        XCTAssertEqual(imported.providerAccountID, "acct_live")
        XCTAssertTrue(imported.managedHomePath.hasPrefix(managedRoot.path))
        XCTAssertEqual(try Self.codexAuthAccountID(home: URL(fileURLWithPath: imported.managedHomePath)), "acct_live")

        let discovered = CodexManagedAccountDiscovery.tokenAccounts(env: [
            CodexManagedAccountDiscovery.storePathEnvironmentName: storeURL.path,
            "CODEX_HOME": liveHome.path,
        ])
        let promotedLive = try XCTUnwrap(discovered.first { $0.id == targetID })
        XCTAssertEqual(promotedLive.externalIdentifier, "live-system")
        XCTAssertEqual(promotedLive.token, liveHome.path)
    }

    private static func jwt(payload: [String: Any]) throws -> String {
        let header = try base64URL(["alg": "none", "typ": "JWT"])
        let payload = try base64URL(payload)
        return "\(header).\(payload).signature"
    }

    private static func jsonString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private static func base64URL(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func writeCodexAuth(
        home: URL,
        email: String,
        accountID: String,
        workspaceName: String
    ) throws {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let idToken = try jwt(payload: [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_account_name": workspaceName,
            ],
        ])
        try """
        {
          "tokens": {
            "access_token": "access-\(accountID)",
            "refresh_token": "refresh-\(accountID)",
            "id_token": "\(idToken)",
            "account_id": "\(accountID)"
          },
          "last_refresh": "2026-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!.write(to: home.appendingPathComponent("auth.json"))
    }

    private static func codexAuthAccountID(home: URL) throws -> String? {
        let data = try Data(contentsOf: home.appendingPathComponent("auth.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tokens = json?["tokens"] as? [String: Any]
        return (tokens?["account_id"] as? String) ?? (tokens?["accountId"] as? String)
    }
}

private final class CodexUsageMockURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: [Response]] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        responses = [:]
        requests = []
    }

    static func enqueue(url: String, statusCode: Int, body: String) {
        lock.lock()
        defer { lock.unlock() }
        responses[url, default: []].append(Response(
            statusCode: statusCode,
            body: body.data(using: .utf8) ?? Data()))
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let response: Response? = Self.lock.withCodexUsageLock {
            Self.requests.append(request)
            guard var queue = Self.responses[url], !queue.isEmpty else { return nil }
            let response = queue.removeFirst()
            Self.responses[url] = queue
            return response
        }

        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension NSLock {
    func withCodexUsageLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
