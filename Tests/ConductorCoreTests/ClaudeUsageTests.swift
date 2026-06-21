import Foundation
import XCTest
@testable import ConductorCore

final class ClaudeUsageTests: XCTestCase {
    func testParsesClaudeCredentialsWithRefreshAndExpiryVariants() throws {
        let data = """
        {
          "claudeAiOauth": {
            "access_token": "access",
            "refresh_token": "refresh",
            "expires_at": 1893456000,
            "subscription_type": "max"
          }
        }
        """.data(using: .utf8)!

        let credentials = try XCTUnwrap(ClaudeUsageFetcher.parseCredentials(data))
        XCTAssertEqual(credentials.accessToken, "access")
        XCTAssertEqual(credentials.refreshToken, "refresh")
        XCTAssertEqual(credentials.subscriptionType, "max")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_893_456_000))
    }

    func testFetchRefreshesExpiredOAuthCredentialsAndPersistsCredentialsFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialsURL = root.appendingPathComponent(".credentials.json")
        try """
        {
          "claudeAiOauth": {
            "accessToken": "old-access",
            "refreshToken": "old-refresh",
            "expiresAt": "2020-01-01T00:00:00Z",
            "subscriptionType": "max"
          },
          "other": "preserved"
        }
        """.data(using: .utf8)!.write(to: credentialsURL)

        ClaudeUsageMockURLProtocol.reset()
        ClaudeUsageMockURLProtocol.enqueue(
            url: "https://platform.claude.com/v1/oauth/token",
            statusCode: 200,
            body: """
            {
              "access_token": "new-access",
              "refresh_token": "new-refresh",
              "expires_in": 3600,
              "subscription_type": "max"
            }
            """)
        ClaudeUsageMockURLProtocol.enqueue(
            url: "https://api.anthropic.com/api/oauth/usage",
            statusCode: 200,
            body: """
            {
              "five_hour": {
                "utilization": 42,
                "resets_at": "2026-06-19T12:00:00Z"
              },
              "seven_day": {
                "utilization": 21,
                "resets_at": "2026-06-25T12:00:00Z"
              }
            }
            """)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await ClaudeUsageFetcher.fetch(
            env: [
                "CLAUDE_CONFIG_DIR": root.path,
                "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
            ],
            session: session)

        XCTAssertEqual(snapshot.primary?.usedPercent, 42)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 21)
        XCTAssertEqual(snapshot.planName, "max")

        let requests = ClaudeUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://platform.claude.com/v1/oauth/token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded;charset=UTF-8")
        let body = String(data: requests[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=refresh_token"))
        XCTAssertTrue(body.contains("refresh_token=old-refresh"))
        XCTAssertTrue(body.contains("client_id=https%3A%2F%2Fclaude.ai%2Foauth%2Fclaude-code-client-metadata"))
        XCTAssertEqual(requests[1].url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")

        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: credentialsURL)) as? [String: Any]
        let oauth = saved?["claudeAiOauth"] as? [String: Any]
        XCTAssertEqual(oauth?["accessToken"] as? String, "new-access")
        XCTAssertEqual(oauth?["refreshToken"] as? String, "new-refresh")
        XCTAssertEqual(oauth?["subscriptionType"] as? String, "max")
        XCTAssertEqual(saved?["other"] as? String, "preserved")
        XCTAssertNotEqual(oauth?["expiresAt"] as? String, "2020-01-01T00:00:00Z")
    }

    func testExplicitClaudeCLISourceDoesNotFallbackToOAuthWhenCLIUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-usage-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialsURL = root.appendingPathComponent(".credentials.json")
        try """
        {
          "claudeAiOauth": {
            "accessToken": "oauth-access",
            "subscriptionType": "max"
          }
        }
        """.data(using: .utf8)!.write(to: credentialsURL)

        ClaudeUsageMockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        do {
            _ = try await ClaudeUsageFetcher.fetch(
                env: [
                    "CLAUDE_CONFIG_DIR": root.path,
                    "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
                    "CONDUCTOR_USAGE_CLAUDE_SOURCE": "cli",
                    "PATH": "/nonexistent",
                ],
                session: session)
            XCTFail("Expected explicit Claude CLI source to stop before OAuth fetch.")
        } catch let error as ClaudeUsageError {
            guard case .cliUnavailable = error else {
                return XCTFail("Expected cliUnavailable, got \(error).")
            }
        }

        XCTAssertEqual(ClaudeUsageMockURLProtocol.recordedRequests().count, 0)
    }

    func testFetchesClaudeUsageFromManualWebCookieSource() async throws {
        ClaudeUsageMockURLProtocol.reset()
        ClaudeUsageMockURLProtocol.enqueue(
            url: "https://claude.test/api/organizations",
            statusCode: 200,
            body: """
            [
              {
                "uuid": "org-1",
                "name": "Research",
                "capabilities": ["chat"]
              }
            ]
            """)
        ClaudeUsageMockURLProtocol.enqueue(
            url: "https://claude.test/api/organizations/org-1/usage",
            statusCode: 200,
            body: """
            {
              "five_hour": {
                "utilization": 33,
                "resets_at": "2026-06-19T12:00:00Z"
              },
              "seven_day": {
                "utilization": 44,
                "resets_at": "2026-06-25T12:00:00Z"
              },
              "seven_day_sonnet": {
                "utilization": 55,
                "resets_at": "2026-06-25T12:00:00Z"
              },
              "seven_day_routines": {
                "utilization": 12,
                "resets_at": "2026-06-25T12:00:00Z"
              },
              "extra_usage": {
                "used_credits": 1234,
                "monthly_credit_limit": 5000,
                "currency": "USD"
              }
            }
            """)
        ClaudeUsageMockURLProtocol.enqueue(
            url: "https://claude.test/api/account",
            statusCode: 200,
            body: """
            {
              "email_address": "web@example.com",
              "memberships": [
                {
                  "organization": {
                    "uuid": "org-1",
                    "rate_limit_tier": "claude_max",
                    "billing_type": "stripe"
                  }
                }
              ]
            }
            """)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await ClaudeUsageFetcher.fetch(
            env: [
                "CONDUCTOR_USAGE_CLAUDE_SOURCE": "web",
                "CONDUCTOR_USAGE_CLAUDE_COOKIE": "sessionKey=sk-ant-web-session; other=value",
                "CONDUCTOR_CLAUDE_WEB_API_BASE_URL": "https://claude.test/api",
                "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
            ],
            session: session)

        XCTAssertEqual(snapshot.primary?.usedPercent, 33)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 44)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 55)
        XCTAssertEqual(snapshot.extraRateWindows.first?.id, "claude-routines")
        XCTAssertEqual(snapshot.extraRateWindows.first?.window.usedPercent, 12)
        XCTAssertEqual(snapshot.providerCost?.used ?? -1, 12.34, accuracy: 0.0001)
        XCTAssertEqual(snapshot.providerCost?.limit ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(snapshot.planName, "Claude Max")
        XCTAssertEqual(snapshot.accountLabel, "web@example.com · Research")

        let requests = ClaudeUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Cookie") ?? "" }, [
            "sessionKey=sk-ant-web-session",
            "sessionKey=sk-ant-web-session",
            "sessionKey=sk-ant-web-session",
        ])
    }

    func testExplicitClaudeWebSourceDoesNotFallbackToOAuthWhenCookieMissing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-web-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialsURL = root.appendingPathComponent(".credentials.json")
        try """
        {
          "claudeAiOauth": {
            "accessToken": "oauth-access",
            "subscriptionType": "max"
          }
        }
        """.data(using: .utf8)!.write(to: credentialsURL)

        ClaudeUsageMockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        do {
            _ = try await ClaudeUsageFetcher.fetch(
                env: [
                    "CLAUDE_CONFIG_DIR": root.path,
                    "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
                    "CONDUCTOR_USAGE_CLAUDE_SOURCE": "web",
                    "CONDUCTOR_USAGE_CLAUDE_COOKIE_SOURCE": "off",
                ],
                session: session)
            XCTFail("Expected explicit Claude web source to stop before OAuth fetch.")
        } catch let error as ClaudeUsageError {
            guard case .webSessionMissing = error else {
                return XCTFail("Expected webSessionMissing, got \(error).")
            }
        }

        XCTAssertEqual(ClaudeUsageMockURLProtocol.recordedRequests().count, 0)
    }

    func testExplicitClaudeWebSourceRejectsInvalidManualCookieWithoutFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-web-invalid-cookie-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let credentialsURL = root.appendingPathComponent(".credentials.json")
        try """
        {
          "claudeAiOauth": {
            "accessToken": "oauth-access",
            "subscriptionType": "max"
          }
        }
        """.data(using: .utf8)!.write(to: credentialsURL)

        ClaudeUsageMockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)
        ClaudeWebDebugLog.shared.clear()

        do {
            _ = try await ClaudeUsageFetcher.fetch(
                env: [
                    "CLAUDE_CONFIG_DIR": root.path,
                    "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
                    "CONDUCTOR_USAGE_CLAUDE_SOURCE": "web",
                    "CONDUCTOR_USAGE_CLAUDE_COOKIE": "other=value",
                ],
                session: session)
            XCTFail("Expected invalid manual cookie to stop before OAuth or browser fallback.")
        } catch let error as ClaudeUsageError {
            guard case .webInvalidSessionKey = error else {
                return XCTFail("Expected webInvalidSessionKey, got \(error).")
            }
        }

        XCTAssertEqual(ClaudeUsageMockURLProtocol.recordedRequests().count, 0)
        let debugSnapshot = ClaudeWebDebugLog.shared.snapshot()
        XCTAssertEqual(debugSnapshot.status, "手动 Claude Cookie 无效。")
        XCTAssertTrue(debugSnapshot.text.contains("manual Claude cookie did not contain a valid sessionKey"))
    }

    func testExplicitClaudeWebSourceRejectsInvalidDirectSessionKeyWithoutFallback() async throws {
        ClaudeUsageMockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        do {
            _ = try await ClaudeUsageFetcher.fetch(
                env: [
                    "CONDUCTOR_USAGE_CLAUDE_SOURCE": "web",
                    "CONDUCTOR_USAGE_CLAUDE_SESSION_KEY": "not-a-claude-session",
                    "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
                ],
                session: session)
            XCTFail("Expected invalid direct session key to stop before browser fallback.")
        } catch let error as ClaudeUsageError {
            guard case .webInvalidSessionKey = error else {
                return XCTFail("Expected webInvalidSessionKey, got \(error).")
            }
        }

        XCTAssertEqual(ClaudeUsageMockURLProtocol.recordedRequests().count, 0)
    }

    func testClaudeAutoPlannerPrefersAdminAPIWhenConfigured() {
        let plan = ClaudeSourcePlanner.resolve(input: ClaudeSourcePlanningInput(
            selectedDataSource: .auto,
            hasAdminAPIKey: true,
            hasWebSession: false,
            hasCLI: true,
            hasOAuthCredentials: true))

        XCTAssertEqual(plan.executionStep?.dataSource, .api)
        XCTAssertEqual(plan.orderLabel, "api→oauth→cli→web")
    }

    func testFetchesClaudeAdminAPIUsageFromAPISource() async throws {
        ClaudeUsageMockURLProtocol.reset()
        ClaudeUsageMockURLProtocol.enqueuePrefix(
            urlPrefix: "https://api.anthropic.com/v1/organizations/cost_report?",
            statusCode: 200,
            body: """
            {
              "data": [
                {
                  "starting_at": "2026-06-18T00:00:00Z",
                  "ending_at": "2026-06-19T00:00:00Z",
                  "results": [
                    {
                      "amount": "1234",
                      "description": "Claude Sonnet 4",
                      "cost_type": "usage"
                    }
                  ]
                }
              ]
            }
            """)
        ClaudeUsageMockURLProtocol.enqueuePrefix(
            urlPrefix: "https://api.anthropic.com/v1/organizations/usage_report/messages?",
            statusCode: 200,
            body: """
            {
              "data": [
                {
                  "starting_at": "2026-06-18T00:00:00Z",
                  "ending_at": "2026-06-19T00:00:00Z",
                  "results": [
                    {
                      "uncached_input_tokens": 100,
                      "cache_creation": {
                        "ephemeral_1h_input_tokens": 20,
                        "ephemeral_5m_input_tokens": 5
                      },
                      "cache_read_input_tokens": 30,
                      "output_tokens": 40,
                      "model": "claude-sonnet-4"
                    }
                  ]
                }
              ]
            }
            """)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ClaudeUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await ClaudeUsageFetcher.fetch(
            env: [
                "CONDUCTOR_USAGE_CLAUDE_SOURCE": "api",
                "ANTHROPIC_ADMIN_KEY": "'admin-key'",
                "CONDUCTOR_CLAUDE_AVOID_KEYCHAIN": "1",
            ],
            session: session)

        XCTAssertEqual(snapshot.planName, "Admin API")
        XCTAssertEqual(snapshot.accountLabel, "Admin API")
        XCTAssertEqual(snapshot.providerCost?.used ?? -1, 12.34, accuracy: 0.0001)
        XCTAssertEqual(snapshot.providerCost?.period, "过去 30 天")
        let adminUsage = try XCTUnwrap(snapshot.claudeAdminAPIUsage)
        XCTAssertEqual(adminUsage.daily.count, 1)
        XCTAssertEqual(adminUsage.last30Days.totalTokens, 195)
        XCTAssertEqual(adminUsage.last30Days.inputTokens, 100)
        XCTAssertEqual(adminUsage.last30Days.cacheCreationInputTokens, 25)
        XCTAssertEqual(adminUsage.last30Days.cacheReadInputTokens, 30)
        XCTAssertEqual(adminUsage.last30Days.outputTokens, 40)
        XCTAssertEqual(adminUsage.topModels.first?.name, "claude-sonnet-4")
        XCTAssertEqual(adminUsage.topCostItems.first?.name, "Claude Sonnet 4")

        let requests = ClaudeUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "x-api-key") ?? "" }, ["admin-key", "admin-key"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "anthropic-version") ?? "" }, ["2023-06-01", "2023-06-01"])
        XCTAssertTrue(requests[0].url?.absoluteString.contains("group_by%5B%5D=description") == true)
        XCTAssertTrue(requests[1].url?.absoluteString.contains("group_by%5B%5D=model") == true)
    }

    func testFetchesClaudeUsageFromDirectCLIJSONOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cli-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let script = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        if [ -n "$ANTHROPIC_ADMIN_KEY" ]; then
          echo "leaked admin key" >&2
          exit 9
        fi
        /bin/cat <<'JSON'
        {
          "session_5h": { "pct_used": 64, "resets": "tomorrow at 9:00AM" },
          "week_all_models": { "pct_used": 25, "resets": "Jun 20 at 5:00PM" },
          "week_sonnet": { "pct_used": 10, "resets": "Jun 20 at 5:00PM" },
          "account_email": "cli@example.com",
          "account_org": "Core",
          "login_method": "Claude Max"
        }
        JSON
        """.data(using: .utf8)!.write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let snapshot = try await ClaudeUsageFetcher.fetch(
            env: [
                "CONDUCTOR_USAGE_CLAUDE_SOURCE": "cli",
                "CLAUDE_CLI_PATH": script.path,
                "ANTHROPIC_ADMIN_KEY": "should-not-leak-to-cli",
                "PATH": root.path,
            ])

        XCTAssertEqual(snapshot.primary?.usedPercent, 64)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 25)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 10)
        XCTAssertEqual(snapshot.planName, "Claude Max")
        XCTAssertEqual(snapshot.accountLabel, "cli@example.com · Core")
    }

    func testClaudeDirectCLIRetriesTransientLoadingUsageOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cli-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let marker = root.appendingPathComponent("attempts")
        let script = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        marker="$CLAUDE_FAKE_MARKER_FILE"
        attempt=1
        if [ -f "$marker" ]; then
          attempt=2
        fi
        echo attempt >> "$marker"
        if [ "$attempt" = "1" ]; then
          echo '{ "ok": false, "hint": "Still loading usage data" }'
          exit 0
        fi
        /bin/cat <<'JSON'
        {
          "session_5h": { "pct_used": 12, "resets": "tomorrow at 9:00AM" },
          "week_all_models": { "pct_used": 20, "resets": "Jun 20 at 5:00PM" },
          "account_email": "retry@example.com",
          "account_org": "Core"
        }
        JSON
        """.data(using: .utf8)!.write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let snapshot = try await ClaudeUsageFetcher.fetch(
            env: [
                "CONDUCTOR_USAGE_CLAUDE_SOURCE": "cli",
                "CLAUDE_CLI_PATH": script.path,
                "CLAUDE_FAKE_MARKER_FILE": marker.path,
                "PATH": root.path,
            ])

        XCTAssertEqual(snapshot.primary?.usedPercent, 12)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 20)
        XCTAssertEqual(snapshot.accountLabel, "retry@example.com · Core")
        let attempts = try String(contentsOf: marker)
            .components(separatedBy: .newlines)
            .filter { $0 == "attempt" }
        XCTAssertEqual(attempts.count, 2)
    }

    func testClaudeDirectCLIFallsBackToPTYWhenArgumentProbeOnlyShowsLoading() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cli-pty-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let marker = root.appendingPathComponent("attempts")
        let script = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        marker="$CLAUDE_FAKE_MARKER_FILE"
        if [ "$1" = "/usage" ]; then
          echo arg >> "$marker"
          echo '{ "ok": false, "hint": "Still loading usage data" }'
          exit 0
        fi
        read line
        echo pty >> "$marker"
        case "$line" in
          /usage*)
            /bin/cat <<'TEXT'
        Claude Code Usage
        Current session 81% left resets tomorrow at 9:00AM
        Current week (all models) 70% left resets Jun 20 at 5:00PM
        Current week (Sonnet only) 60% left resets Jun 20 at 5:00PM
        Account: pty@example.com
        Organization: Core
        Login method: Claude Max
        TEXT
            ;;
          *)
            echo "unexpected command: $line"
            ;;
        esac
        """.data(using: .utf8)!.write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let snapshot = try await ClaudeUsageFetcher.fetch(
            env: [
                "CONDUCTOR_USAGE_CLAUDE_SOURCE": "cli",
                "CLAUDE_CLI_PATH": script.path,
                "CLAUDE_FAKE_MARKER_FILE": marker.path,
                "PATH": root.path,
            ])

        XCTAssertEqual(snapshot.primary?.usedPercent, 19)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 30)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 40)
        XCTAssertEqual(snapshot.planName, "Claude Max")
        XCTAssertEqual(snapshot.accountLabel, "pty@example.com · Core")
        let attempts = try String(contentsOf: marker)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        XCTAssertEqual(attempts, ["arg", "arg", "pty"])
    }

    func testClaudeDirectCLIPersistentPTYSessionReusesInteractiveProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-cli-pty-persistent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let marker = root.appendingPathComponent("attempts")
        let script = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        marker="$CLAUDE_FAKE_MARKER_FILE"
        if [ "$1" = "/usage" ]; then
          echo arg >> "$marker"
          echo '{ "ok": false, "hint": "Still loading usage data" }'
          exit 0
        fi
        echo start >> "$marker"
        count=0
        while IFS= read -r line; do
          echo pty >> "$marker"
          case "$line" in
            /usage*)
              count=$((count + 1))
              /bin/cat <<'TEXT'
        Claude Code Usage
        Current session 81% left resets tomorrow at 9:00AM
        Current week (all models) 70% left resets Jun 20 at 5:00PM
        Current week (Sonnet only) 60% left resets Jun 20 at 5:00PM
        Account: persistent@example.com
        Organization: Core
        Login method: Claude Max
        TEXT
              if [ "$count" -ge 2 ]; then
                exit 0
              fi
              ;;
            *)
              echo "unexpected command: $line"
              ;;
          esac
        done
        """.data(using: .utf8)!.write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let env = [
            "CONDUCTOR_USAGE_CLAUDE_SOURCE": "cli",
            "CLAUDE_CLI_PATH": script.path,
            "CLAUDE_FAKE_MARKER_FILE": marker.path,
            "PATH": root.path,
        ]
        defer { Task { await ClaudeUsageFetcher.discardDirectCLITTYSessionForTesting(env: env) } }

        let first = try await ClaudeUsageFetcher.fetch(env: env)
        let second = try await ClaudeUsageFetcher.fetch(env: env)

        XCTAssertEqual(first.primary?.usedPercent, 19)
        XCTAssertEqual(second.primary?.usedPercent, 19)
        XCTAssertEqual(second.secondary?.usedPercent, 30)
        XCTAssertEqual(second.tertiary?.usedPercent, 40)
        XCTAssertEqual(second.planName, "Claude Max")
        XCTAssertEqual(second.accountLabel, "persistent@example.com · Core")
        let attempts = try String(contentsOf: marker)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
        XCTAssertEqual(attempts, ["arg", "arg", "start", "pty", "arg", "arg", "pty"])
    }

    func testParsesClaudeCLIUsageTextAsRemainingPercent() throws {
        let now = Date(timeIntervalSince1970: 1_780_320_000) // 2026-06-01T00:00:00Z
        let snapshot = try ClaudeUsageFetcher.parseCLIUsageOutput("""
        Claude Code Usage
        Current session 72% left resets 4:00PM
        Current week (all models) 80% left resets Jun 22 at 9:00AM
        Current week (Sonnet only) 50% left resets Jun 22 at 9:00AM
        Account: dev@example.com
        Organization: Research
        Login method: Max
        """, now: now)

        XCTAssertEqual(snapshot.primary?.usedPercent, 28)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 20)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 50)
        XCTAssertEqual(snapshot.planName, "Max")
        XCTAssertEqual(snapshot.accountLabel, "dev@example.com · Research")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let weeklyReset = try XCTUnwrap(snapshot.secondary?.resetsAt)
        let weeklyComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: weeklyReset)
        XCTAssertEqual(weeklyComponents.year, 2026)
        XCTAssertEqual(weeklyComponents.month, 6)
        XCTAssertEqual(weeklyComponents.day, 22)
        XCTAssertEqual(weeklyComponents.hour, 9)
        XCTAssertEqual(weeklyComponents.minute, 0)
    }
}

private final class ClaudeUsageMockURLProtocol: URLProtocol {
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

    static func enqueuePrefix(urlPrefix: String, statusCode: Int, body: String) {
        enqueue(url: "\(urlPrefix)*", statusCode: statusCode, body: body)
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
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let bodyStream = request.httpBodyStream {
            capturedRequest.httpBody = Self.readBody(from: bodyStream)
        }
        let response: Response? = Self.lock.withClaudeUsageLock {
            Self.requests.append(capturedRequest)
            guard let key = Self.responseKey(for: url),
                  var queue = Self.responses[key],
                  !queue.isEmpty
            else { return nil }
            let response = queue.removeFirst()
            Self.responses[key] = queue
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

    private static func readBody(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data
    }

    private static func responseKey(for url: String) -> String? {
        if let exact = responses[url], !exact.isEmpty { return url }
        return responses.keys.sorted().first { key in
            guard key.hasSuffix("*"),
                  responses[key]?.isEmpty == false
            else { return false }
            return url.hasPrefix(String(key.dropLast()))
        }
    }
}

private extension NSLock {
    func withClaudeUsageLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
