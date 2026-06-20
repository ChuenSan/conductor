import Foundation
import XCTest
@testable import ConductorCore

final class OpenAIDashboardUsageTests: XCTestCase {
    func testParseDashboardBodySignals() {
        let body = """
        Codex usage
        5-hour limit
        73% remaining
        Resets today 8:30 PM

        Weekly usage
        41% used

        Code review
        12% remaining

        Credits remaining 1,234.5
        """

        let limits = OpenAIDashboardParser.parseRateLimits(bodyText: body)

        XCTAssertEqual(limits.primary?.usedPercent, 27)
        XCTAssertEqual(limits.primary?.windowMinutes, 300)
        XCTAssertEqual(limits.secondary?.usedPercent, 41)
        XCTAssertEqual(OpenAIDashboardParser.parseCodeReviewRemainingPercent(bodyText: body), 12)
        XCTAssertEqual(OpenAIDashboardParser.parseCreditsRemaining(bodyText: body), 1_234.5)
    }

    func testDashboardSnapshotMapsCodeReviewToExtraWindow() {
        let snapshot = OpenAIDashboardSnapshot(
            signedInEmail: "dev@example.com",
            codeReviewRemainingPercent: 18,
            primaryLimit: RateWindow(usedPercent: 30, resetsAt: Date(timeIntervalSince1970: 1), resetDescription: nil),
            secondaryLimit: RateWindow(usedPercent: 40, resetsAt: Date(timeIntervalSince1970: 2), resetDescription: nil),
            creditsRemaining: 99,
            accountPlan: "plus")

        let codex = snapshot.toCodexUsageSnapshot()

        XCTAssertEqual(codex.accountLabel, "dev@example.com")
        XCTAssertEqual(codex.planType, "plus")
        XCTAssertEqual(codex.session?.usedPercent, 30)
        XCTAssertEqual(codex.weekly?.usedPercent, 40)
        XCTAssertEqual(codex.providerCost?.used, 99)
        XCTAssertEqual(codex.extraRateWindows.first?.id, "code-review")
        XCTAssertEqual(codex.extraRateWindows.first?.window.usedPercent, 82)
    }

    func testDashboardExtraWindowsMergeAPIAndHydratedSourcesByID() {
        let base = [
            NamedRateWindow(
                id: "codex-spark",
                title: "Codex Spark",
                window: RateWindow(usedPercent: 12)),
            NamedRateWindow(
                id: "shared",
                title: "API Shared",
                window: RateWindow(usedPercent: 20)),
        ]
        let hydrated = [
            NamedRateWindow(
                id: "shared",
                title: "Hydrated Shared",
                window: RateWindow(usedPercent: 99)),
            NamedRateWindow(
                id: "dashboard-extra",
                title: "Dashboard Extra",
                window: RateWindow(usedPercent: 44)),
        ]

        let merged = OpenAIDashboardUsageFetcher.mergedExtraRateWindows(base: base, hydrated: hydrated)

        XCTAssertEqual(merged?.map(\.id), ["codex-spark", "shared", "dashboard-extra"])
        XCTAssertEqual(merged?[1].title, "API Shared")
        XCTAssertEqual(merged?[1].window.usedPercent, 20)
        XCTAssertEqual(merged?[2].window.usedPercent, 44)
    }

    func testCookieSelectionTimeoutClampsLocalLimitToRemainingDeadline() throws {
        let now = Date()
        let timeout = try OpenAIDashboardUsageFetcher.remainingCookieSelectionTimeout(
            until: now.addingTimeInterval(2),
            cappedAt: 10,
            now: now)

        XCTAssertEqual(timeout, 2, accuracy: 0.001)
        XCTAssertThrowsError(try OpenAIDashboardUsageFetcher.remainingCookieSelectionTimeout(
            until: now.addingTimeInterval(-0.001),
            cappedAt: 10,
            now: now)) { error in
                XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testBoundedCookieLoadCannotExceedSharedDeadline() async throws {
        let start = Date()
        let timeoutProbe = OpenAIDashboardTimeoutProbe()

        do {
            let _: Bool = try await OpenAIDashboardUsageFetcher.runBoundedCookieLoad(
                deadline: start.addingTimeInterval(0.05),
                timeoutObserver: timeoutProbe.record)
            {
                Thread.sleep(forTimeInterval: 0.5)
                return true
            }
            XCTFail("Expected cookie load timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let firedAt = try XCTUnwrap(timeoutProbe.firedAt)
        XCTAssertLessThan(firedAt.timeIntervalSince(start), 0.3)
    }

    func testBoundedCookieLoadTimeoutObserverStaysSilentWhenOperationWins() async throws {
        let timeoutProbe = OpenAIDashboardTimeoutProbe()

        let value = try await OpenAIDashboardUsageFetcher.runBoundedCookieLoad(
            deadline: Date().addingTimeInterval(0.05),
            timeoutObserver: timeoutProbe.record)
        {
            true
        }
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(value)
        XCTAssertNil(timeoutProbe.firedAt)
    }

    func testTimedOutCookieLoadWorkStaysOrderedBeforeRetry() async throws {
        let log = OpenAIDashboardCookieOperationLog()
        let firstOperationStarted = DispatchSemaphore(value: 0)
        let allowFirstOperationToFinish = DispatchSemaphore(value: 0)

        do {
            let _: Bool = try await OpenAIDashboardUsageFetcher.runBoundedCookieLoad(
                deadline: Date().addingTimeInterval(0.05))
            {
                log.append("first-start")
                firstOperationStarted.signal()
                _ = allowFirstOperationToFinish.wait(timeout: .now() + 5)
                log.append("first-end")
                return true
            }
            XCTFail("Expected first cookie load timeout")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let firstOperationStartResult = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: firstOperationStarted.wait(timeout: .now() + 5))
            }
        }
        XCTAssertEqual(firstOperationStartResult, .success)

        do {
            let _: Bool = try await OpenAIDashboardUsageFetcher.runBoundedCookieLoad(
                deadline: Date().addingTimeInterval(0.05))
            {
                log.append("second")
                return true
            }
            XCTFail("Expected retry to wait behind first cookie load")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        allowFirstOperationToFinish.signal()
        let _: Bool = try await OpenAIDashboardUsageFetcher.runBoundedCookieLoad(
            deadline: Date().addingTimeInterval(1))
        {
            true
        }

        XCTAssertEqual(log.snapshot, ["first-start", "first-end", "second"])
    }

    func testParseCreditEventsFromCreditsHistoryHTML() {
        let html = """
        <main>
          <section>
            <h2>Credits usage history</h2>
            <table>
              <tbody>
                <tr>
                  <td>Jun 17, 2026</td>
                  <td>Claude &amp; Codex</td>
                  <td>1,234 credits</td>
                </tr>
                <tr>
                  <td>2026-06-16</td>
                  <td>Codex</td>
                  <td>2.5 credits</td>
                </tr>
              </tbody>
            </table>
          </section>
        </main>
        """

        let events = OpenAIDashboardParser.parseCreditEvents(fromHTML: html)
        let breakdown = OpenAIDashboardSnapshot.makeDailyBreakdown(from: events, maxDays: 30)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.service, "Claude & Codex")
        XCTAssertEqual(events.first?.creditsUsed, 1_234)
        XCTAssertEqual(breakdown.first?.day, "2026-06-17")
        XCTAssertEqual(breakdown.first?.totalCreditsUsed, 1_234)
    }

    func testParseUsageBreakdownJSONFiltersSkillUsageServices() {
        let raw = """
        [
          {
            "day": "2026-06-17",
            "services": [
              { "service": "CLI", "creditsUsed": 4.5 },
              { "service": "SkillUsage:test", "creditsUsed": 99 }
            ],
            "totalCreditsUsed": 103.5
          },
          {
            "day": "2026-06-16",
            "services": [
              { "service": "Desktop", "creditsUsed": "1.25" }
            ]
          }
        ]
        """

        let breakdown = OpenAIDashboardParser.parseUsageBreakdownJSON(raw)

        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown[0].day, "2026-06-17")
        XCTAssertEqual(breakdown[0].services.map(\.service), ["CLI"])
        XCTAssertEqual(breakdown[0].totalCreditsUsed, 4.5)
        XCTAssertEqual(breakdown[1].services.first?.creditsUsed, 1.25)
    }

    func testParseUsageBreakdownFromCodexBarScriptValue() {
        let html = #"""
        <script>
          window.__codexbarUsageBreakdownJSON = "[{\"day\":\"2026-06-18\",\"services\":[{\"service\":\"CLI\",\"creditsUsed\":7}],\"totalCreditsUsed\":7}]";
        </script>
        """#

        let breakdown = OpenAIDashboardParser.parseUsageBreakdown(fromHTML: html)

        XCTAssertEqual(breakdown.count, 1)
        XCTAssertEqual(breakdown.first?.day, "2026-06-18")
        XCTAssertEqual(breakdown.first?.services.first?.service, "CLI")
        XCTAssertEqual(breakdown.first?.totalCreditsUsed, 7)
    }

    func testDashboardCacheReusableSnapshotForCLIMatchesEmail() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-dashboard-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = OpenAIDashboardSnapshot(
            signedInEmail: "Dev@Example.com",
            usageBreakdown: [
                OpenAIDashboardDailyBreakdown(
                    day: "2026-06-18",
                    services: [OpenAIDashboardServiceUsage(service: "CLI", creditsUsed: 2)],
                    totalCreditsUsed: 2)
            ])
        OpenAIDashboardCacheStore.save(
            OpenAIDashboardCache(accountEmail: "dev@example.com", snapshot: snapshot),
            cacheRoot: root)

        let reused = OpenAIDashboardCacheStore.reusableSnapshotForCLI(
            reportAccount: "dev@example.com - Personal",
            usageAccountLabel: nil,
            sourceLabel: "oauth",
            cacheRoot: root)

        XCTAssertEqual(reused?.signedInEmail, "Dev@Example.com")
        XCTAssertEqual(reused?.usageBreakdown.first?.totalCreditsUsed, 2)
        XCTAssertNotNil(OpenAIDashboardCacheStore.load(cacheRoot: root))
    }

    func testDashboardCreditHistoryMergesPerAccountAcrossCacheSaves() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-dashboard-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = OpenAIDashboardSnapshot(
            signedInEmail: "dev@example.com",
            creditEvents: [
                CreditEvent(
                    date: Date(timeIntervalSince1970: 1_779_811_200),
                    service: "Codex",
                    creditsUsed: 3),
            ])
        let second = OpenAIDashboardSnapshot(
            signedInEmail: "dev@example.com",
            creditEvents: [
                CreditEvent(
                    date: Date(timeIntervalSince1970: 1_779_897_600),
                    service: "Code Review",
                    creditsUsed: 4),
            ])

        OpenAIDashboardCacheStore.save(
            OpenAIDashboardCache(accountEmail: "Dev@Example.com", snapshot: first),
            cacheRoot: root)
        OpenAIDashboardCacheStore.save(
            OpenAIDashboardCache(accountEmail: "dev@example.com", snapshot: second),
            cacheRoot: root)

        let cache = OpenAIDashboardCacheStore.load(cacheRoot: root)
        let history = OpenAIDashboardCreditHistoryStore.load(
            accountEmail: "dev@example.com",
            cacheRoot: root)

        XCTAssertEqual(cache?.snapshot.creditEvents.count, 2)
        XCTAssertEqual(history?.creditEvents.count, 2)
        XCTAssertEqual(cache?.snapshot.dailyBreakdown.count, 2)
        XCTAssertEqual(cache?.snapshot.creditEvents.first?.service, "Code Review")
    }

    func testDashboardCreditHistoryIsScopedByAccountEmail() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-dashboard-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        OpenAIDashboardCacheStore.save(
            OpenAIDashboardCache(
                accountEmail: "dev@example.com",
                snapshot: OpenAIDashboardSnapshot(
                    signedInEmail: "dev@example.com",
                    creditEvents: [
                        CreditEvent(
                            date: Date(timeIntervalSince1970: 1_779_811_200),
                            service: "Codex",
                            creditsUsed: 3),
                    ])),
            cacheRoot: root)
        OpenAIDashboardCacheStore.save(
            OpenAIDashboardCache(
                accountEmail: "other@example.com",
                snapshot: OpenAIDashboardSnapshot(signedInEmail: "other@example.com")),
            cacheRoot: root)

        let devHistory = OpenAIDashboardCreditHistoryStore.load(
            accountEmail: "dev@example.com",
            cacheRoot: root)
        let otherHistory = OpenAIDashboardCreditHistoryStore.load(
            accountEmail: "other@example.com",
            cacheRoot: root)

        XCTAssertEqual(devHistory?.creditEvents.count, 1)
        XCTAssertEqual(otherHistory?.creditEvents.count, 0)
    }

    func testDashboardCacheReusableSnapshotForCLIClearsWrongAccount() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-dashboard-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let snapshot = OpenAIDashboardSnapshot(
            signedInEmail: "other@example.com",
            primaryLimit: RateWindow(usedPercent: 10))
        OpenAIDashboardCacheStore.save(
            OpenAIDashboardCache(accountEmail: "other@example.com", snapshot: snapshot),
            cacheRoot: root)

        let reused = OpenAIDashboardCacheStore.reusableSnapshotForCLI(
            reportAccount: "dev@example.com",
            usageAccountLabel: nil,
            sourceLabel: "oauth",
            cacheRoot: root)

        XCTAssertNil(reused)
        XCTAssertNil(OpenAIDashboardCacheStore.load(cacheRoot: root))
    }

    func testCodexDashboardAuthorityAllowsCachedReuseForExactProviderAccount() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .cachedDashboard,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .providerAccount(id: "acct_1"),
                expectedScopedEmail: "dev@example.com",
                trustedCurrentUsageEmail: "dev@example.com",
                dashboardSignedInEmail: "dev@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct_1"),
                        normalizedEmail: "dev@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "dev@example.com",
                lastKnownDashboardRoutingEmail: "dev@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        XCTAssertEqual(decision.disposition, .attach)
        XCTAssertEqual(decision.reason, .exactProviderAccountMatch)
        XCTAssertTrue(decision.allowedEffects.contains(.cachedDashboardReuse))
        XCTAssertTrue(decision.cleanup.isEmpty)
    }

    func testCodexDashboardAuthorityDisplayOnlyForSameEmailAmbiguity() {
        let input = CodexDashboardAuthorityInput(
            sourceKind: .cachedDashboard,
            proof: CodexDashboardOwnershipProofContext(
                currentIdentity: .emailOnly(normalizedEmail: "dev@example.com"),
                expectedScopedEmail: "dev@example.com",
                trustedCurrentUsageEmail: "dev@example.com",
                dashboardSignedInEmail: "dev@example.com",
                knownOwners: [
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct_1"),
                        normalizedEmail: "dev@example.com"),
                    CodexDashboardKnownOwnerCandidate(
                        identity: .providerAccount(id: "acct_2"),
                        normalizedEmail: "dev@example.com"),
                ]),
            routing: CodexDashboardRoutingHints(
                targetEmail: "dev@example.com",
                lastKnownDashboardRoutingEmail: "dev@example.com"))

        let decision = CodexDashboardAuthority.evaluate(input)

        XCTAssertEqual(decision.disposition, .displayOnly)
        XCTAssertEqual(decision.reason, .sameEmailAmbiguity(email: "dev@example.com"))
        XCTAssertFalse(decision.allowedEffects.contains(.cachedDashboardReuse))
        XCTAssertTrue(decision.cleanup.contains(.dashboardCache))
    }

    #if os(macOS) && canImport(WebKit)
    func testWebKitUsageBreakdownRecoveryWaitsBrieflyAfterChartError() {
        let now = Date()

        XCTAssertTrue(OpenAIDashboardWebKitUsageFetcher.shouldWaitForUsageBreakdownRecovery(.init(
            now: now,
            errorFirstSeenAt: now.addingTimeInterval(-1))))
        XCTAssertFalse(OpenAIDashboardWebKitUsageFetcher.shouldWaitForUsageBreakdownRecovery(.init(
            now: now,
            errorFirstSeenAt: now.addingTimeInterval(-5))))
    }
    #endif

    func testDashboardOwnershipRejectsWrongAccount() throws {
        let auth = try Self.writeCodexAuth(email: "dev@example.com", accountID: "acct_dev")
        defer { try? FileManager.default.removeItem(at: auth.root) }
        let snapshot = OpenAIDashboardSnapshot(
            signedInEmail: "other@example.com",
            primaryLimit: RateWindow(usedPercent: 10, resetsAt: Date(timeIntervalSince1970: 1)))

        XCTAssertThrowsError(try OpenAIDashboardUsageFetcher.validateDashboardOwnership(
            snapshot: snapshot,
            expectedEmail: "dev@example.com",
            env: auth.env)) { error in
                guard case let OpenAIDashboardUsageError.policyRejected(decision) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(decision.disposition, .failClosed)
                XCTAssertEqual(decision.reason, .wrongEmail(expected: "dev@example.com", actual: "other@example.com"))
        }
    }

    func testDashboardCachedCookieRetriesOnlyRecoverableFailures() {
        let wrongEmail = CodexDashboardAuthorityDecision(
            disposition: .failClosed,
            reason: .wrongEmail(expected: "dev@example.com", actual: "other@example.com"),
            allowedEffects: [],
            cleanup: Set(CodexDashboardCleanup.allCases))
        let lacksProof = CodexDashboardAuthorityDecision(
            disposition: .failClosed,
            reason: .providerAccountLacksExactOwnershipProof,
            allowedEffects: [],
            cleanup: Set(CodexDashboardCleanup.allCases))

        XCTAssertTrue(OpenAIDashboardUsageFetcher.shouldRetryWithFreshBrowserCookie(
            after: OpenAIDashboardUsageError.noDashboardData("empty")))
        XCTAssertTrue(OpenAIDashboardUsageFetcher.shouldRetryWithFreshBrowserCookie(
            after: OpenAIDashboardUsageError.unauthorized))
        XCTAssertTrue(OpenAIDashboardUsageFetcher.shouldRetryWithFreshBrowserCookie(
            after: OpenAIDashboardUsageError.policyRejected(wrongEmail)))
        XCTAssertFalse(OpenAIDashboardUsageFetcher.shouldRetryWithFreshBrowserCookie(
            after: OpenAIDashboardUsageError.policyRejected(lacksProof)))
        XCTAssertFalse(OpenAIDashboardUsageFetcher.shouldRetryWithFreshBrowserCookie(
            after: OpenAIDashboardUsageError.network("offline")))
    }

    func testDashboardCookieCandidateAcceptsMatchingEmail() async {
        OpenAIDashboardUsageMockURLProtocol.reset()
        OpenAIDashboardUsageMockURLProtocol.enqueue(
            url: "https://chatgpt.com/backend-api/me",
            statusCode: 200,
            body: #"{"user":{"email":"Dev@Example.com"}}"#)
        let session = Self.mockSession()

        let evaluation = await OpenAIDashboardUsageFetcher.evaluateCookieCandidate(
            cookieHeader: "__Secure-next-auth.session-token=abc; _account=acct",
            expectedEmail: "dev@example.com",
            sourceLabel: "Chrome Default",
            session: session,
            timeout: 1)

        XCTAssertEqual(evaluation, .accepted(signedInEmail: "dev@example.com"))
    }

    func testDashboardCookieCandidateRejectsWrongEmail() async {
        OpenAIDashboardUsageMockURLProtocol.reset()
        OpenAIDashboardUsageMockURLProtocol.enqueue(
            url: "https://chatgpt.com/backend-api/me",
            statusCode: 200,
            body: #"{"email":"other@example.com"}"#)
        let session = Self.mockSession()

        let evaluation = await OpenAIDashboardUsageFetcher.evaluateCookieCandidate(
            cookieHeader: "__Secure-next-auth.session-token=abc; _account=acct",
            expectedEmail: "dev@example.com",
            sourceLabel: "Chrome Default",
            session: session,
            timeout: 1)

        XCTAssertEqual(
            evaluation,
            .rejectedWrongEmail(expected: "dev@example.com", actual: "other@example.com"))
    }

    func testDashboardOwnershipFailsClosedWhenExpectedEmailHasNoDashboardEmail() throws {
        let auth = try Self.writeCodexAuth(email: "dev@example.com", accountID: "acct_dev")
        defer { try? FileManager.default.removeItem(at: auth.root) }
        let snapshot = OpenAIDashboardSnapshot(
            primaryLimit: RateWindow(usedPercent: 10, resetsAt: Date(timeIntervalSince1970: 1)))

        XCTAssertThrowsError(try OpenAIDashboardUsageFetcher.validateDashboardOwnership(
            snapshot: snapshot,
            expectedEmail: "dev@example.com",
            env: auth.env)) { error in
                guard case let OpenAIDashboardUsageError.policyRejected(decision) = error else {
                    return XCTFail("Unexpected error: \(error)")
                }
                XCTAssertEqual(decision.disposition, .failClosed)
                XCTAssertEqual(decision.reason, .missingDashboardSignedInEmail)
        }
    }

    private static func writeCodexAuth(
        email: String,
        accountID: String
    ) throws -> (root: URL, env: [String: String]) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-dashboard-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let idToken = try jwt(payload: [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_account_name": "Test",
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
        """.data(using: .utf8)!.write(to: root.appendingPathComponent("auth.json"))
        return (root, ["CODEX_HOME": root.path])
    }

    private static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OpenAIDashboardUsageMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func jwt(payload: [String: Any]) throws -> String {
        let header = try base64URL(["alg": "none", "typ": "JWT"])
        let payload = try base64URL(payload)
        return "\(header).\(payload)."
    }

    private static func base64URL(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class OpenAIDashboardTimeoutProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFiredAt: Date?

    var firedAt: Date? {
        lock.withOpenAIDashboardUsageLock { storedFiredAt }
    }

    func record() {
        lock.withOpenAIDashboardUsageLock {
            if storedFiredAt == nil {
                storedFiredAt = Date()
            }
        }
    }
}

private final class OpenAIDashboardCookieOperationLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    var snapshot: [String] {
        lock.withOpenAIDashboardUsageLock { entries }
    }

    func append(_ entry: String) {
        lock.withOpenAIDashboardUsageLock {
            entries.append(entry)
        }
    }
}

private final class OpenAIDashboardUsageMockURLProtocol: URLProtocol {
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

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        let response: Response? = Self.lock.withOpenAIDashboardUsageLock {
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
    func withOpenAIDashboardUsageLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
