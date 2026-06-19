import XCTest
@testable import ConductorCore

final class MiniMaxUsageTests: XCTestCase {
    func testCookieHeaderExtractsAuthorizationAndGroupIDFromCurl() throws {
        let raw = """
        curl 'https://platform.minimax.io/v1/api/openplatform/coding_plan/remains?GroupId=123456' \\
          -H 'authorization: Bearer token123' \\
          -H 'Cookie: foo=bar; session=abc123'
        """

        let override = MiniMaxCookieHeader.override(from: raw)

        XCTAssertEqual(override?.cookieHeader, "foo=bar; session=abc123")
        XCTAssertEqual(override?.authorizationToken, "token123")
        XCTAssertEqual(override?.groupID, "123456")
    }

    func testCookieHeaderExtractsGroupIDFromCookieAndHeader() throws {
        let raw = """
        curl 'https://www.minimaxi.com/v1/api/openplatform/charge/combo/cycle_audio_resource_package' \\
          -b 'foo=bar; minimax_group_id_v2=2013894056999916075' \\
          -H 'x-group-id: 2013894056999916075'
        """

        let override = MiniMaxCookieHeader.override(from: raw)

        XCTAssertEqual(override?.cookieHeader, "foo=bar; minimax_group_id_v2=2013894056999916075")
        XCTAssertEqual(override?.groupID, "2013894056999916075")
    }

    func testLocalStorageExtractsMiniMaxTokensAndGroupID() throws {
        let shortToken = String(repeating: "b", count: 24)
        let longToken = String(repeating: "a", count: 72)
        let payload = #"{"access_token":"\#(shortToken)","nested":{"token":"\#(longToken)"}}"#

        let tokens = MiniMaxLocalStorageImporter._extractAccessTokensForTesting(payload)

        XCTAssertTrue(tokens.contains(longToken))
        XCTAssertFalse(tokens.contains(shortToken))
        XCTAssertEqual(
            MiniMaxLocalStorageImporter._extractGroupIDForTesting(#"{"user":{"groupId":"98765"}}"#),
            "98765")
    }

    func testLocalStorageResolvesGroupIDFromJWTClaims() throws {
        let token = Self.makeJWT(payload: [
            "iss": "minimax",
            "group_id": "12345",
            "pad": String(repeating: "x", count: 80),
        ])

        XCTAssertTrue(MiniMaxLocalStorageImporter._isMiniMaxJWTForTesting(token))
        XCTAssertEqual(MiniMaxLocalStorageImporter._groupIDFromJWTForTesting(token), "12345")
    }

    func testLocalStorageRejectsNonMiniMaxJWTWithoutSignal() throws {
        let token = Self.makeJWT(payload: [
            "iss": "other",
            "pad": String(repeating: "y", count: 80),
        ])

        XCTAssertFalse(MiniMaxLocalStorageImporter._isMiniMaxJWTForTesting(token))
    }

    func testBillingHistoryParserAggregatesRecentSuccessfulRows() throws {
        let data = """
        {
          "base_resp": {"status_code": 0},
          "total_cnt": "4",
          "charge_records": [
            {
              "consume_token": "100",
              "consume_cash_after_voucher": "1.25",
              "consume_time": "2026-06-18T10:00:00Z",
              "method": "chat",
              "model": "MiniMax-M1",
              "status": "SUCCESS"
            },
            {
              "consume_input_token": 50,
              "consume_output_token": "25",
              "consume_cash": 0.75,
              "ymd": "2026-06-17",
              "method": "api",
              "model": "MiniMax-Text",
              "result": "SUCCESS"
            },
            {
              "consume_token": 999,
              "ymd": "2026-06-18",
              "method": "chat",
              "model": "MiniMax-M1",
              "status": "FAILED"
            },
            {
              "consume_token": 300,
              "ymd": "2026-05-01",
              "method": "old",
              "model": "Old",
              "status": "SUCCESS"
            }
          ]
        }
        """.data(using: .utf8)!

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-06-18T12:00:00Z")!
        let summary = try MiniMaxUsageFetcher.parseBillingHistory(data, now: now, calendar: calendar)

        XCTAssertEqual(summary.todayTokens, 100)
        XCTAssertEqual(summary.last30DaysTokens, 175)
        XCTAssertEqual(summary.todayCash, 1.25)
        XCTAssertEqual(summary.last30DaysCash, 2.0)
        XCTAssertEqual(summary.daily.map(\.day), ["2026-06-17", "2026-06-18"])
        XCTAssertEqual(summary.topModels.first?.name, "MiniMax-M1")
        XCTAssertEqual(summary.topMethods.first?.name, "chat")
    }

    func testWebFetchAttachesBillingHistorySummary() async throws {
        MiniMaxUsageMockURLProtocol.reset()
        let remainsURL = "https://platform.minimax.io/v1/api/openplatform/coding_plan/remains"
        let billingURL = "https://platform.minimax.io/account/amount?page=1&limit=100&aggregate=false"
        MiniMaxUsageMockURLProtocol.enqueue(url: remainsURL, statusCode: 200, body: Self.remainsBody)
        MiniMaxUsageMockURLProtocol.enqueue(url: billingURL, statusCode: 200, body: """
        {
          "base_resp": {"status_code": 0},
          "total_cnt": 1,
          "charge_records": [
            {
              "consume_token": 40,
              "consume_cash": 0.4,
              "ymd": "\(Self.todayString())",
              "method": "chat",
              "model": "MiniMax-M1",
              "status": "SUCCESS"
            }
          ]
        }
        """)

        let snapshot = try await MiniMaxUsageFetcher.fetch(env: Self.webEnv, session: Self.mockSession())

        XCTAssertEqual(snapshot.primary?.usedPercent, 25)
        XCTAssertTrue(snapshot.extraRateWindows.contains { $0.id == "minimax.billing.today" })
        XCTAssertTrue(snapshot.extraRateWindows.contains { $0.title.contains("MiniMax-M1") })
        XCTAssertEqual(MiniMaxUsageMockURLProtocol.recordedRequests().count, 2)
    }

    func testWebFetchUsesAuthorizationAndGroupIDFromCookieOverride() async throws {
        MiniMaxUsageMockURLProtocol.reset()
        let remainsURL = "https://platform.minimax.io/v1/api/openplatform/coding_plan/remains?GroupId=123456"
        let billingURL = "https://platform.minimax.io/account/amount?page=1&limit=100&aggregate=false"
        MiniMaxUsageMockURLProtocol.enqueue(url: remainsURL, statusCode: 200, body: Self.remainsBody)
        MiniMaxUsageMockURLProtocol.enqueue(url: billingURL, statusCode: 200, body: """
        {"base_resp":{"status_code":0},"total_cnt":0,"charge_records":[]}
        """)

        let rawCookie = """
        curl 'https://platform.minimax.io/v1/api/openplatform/coding_plan/remains?GroupId=123456' \\
          -H 'Authorization: Bearer token123' \\
          -H 'Cookie: foo=bar; session=abc123'
        """
        var env = Self.webEnv
        env["MINIMAX_COOKIE_HEADER"] = rawCookie
        env["CONDUCTOR_USAGE_MINIMAX_COOKIE"] = nil

        _ = try await MiniMaxUsageFetcher.fetch(env: env, session: Self.mockSession())

        let requests = MiniMaxUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.first?.url?.absoluteString, remainsURL)
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token123")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Cookie"), "foo=bar; session=abc123")
        XCTAssertEqual(requests.dropFirst().first?.value(forHTTPHeaderField: "Authorization"), "Bearer token123")
    }

    func testWebFetchKeepsQuotaWhenBillingHistoryFails() async throws {
        MiniMaxUsageMockURLProtocol.reset()
        let remainsURL = "https://platform.minimax.io/v1/api/openplatform/coding_plan/remains"
        let billingURL = "https://platform.minimax.io/account/amount?page=1&limit=100&aggregate=false"
        MiniMaxUsageMockURLProtocol.enqueue(url: remainsURL, statusCode: 200, body: Self.remainsBody)
        MiniMaxUsageMockURLProtocol.enqueue(url: billingURL, statusCode: 500, body: "{}")

        let snapshot = try await MiniMaxUsageFetcher.fetch(env: Self.webEnv, session: Self.mockSession())

        XCTAssertEqual(snapshot.primary?.usedPercent, 25)
        XCTAssertFalse(snapshot.extraRateWindows.contains { $0.id.hasPrefix("minimax.billing.") })
    }

    private static let remainsBody = """
    {
      "base_resp": {"status_code": 0},
      "data": {
        "plan_name": "Pro",
        "points_balance": 123,
        "model_remains": [
          {
            "current_interval_remaining_percent": 75,
            "current_weekly_remaining_percent": 60,
            "remains_time": 3600,
            "weekly_remains_time": 86400
          }
        ]
      }
    }
    """

    private static let webEnv: [String: String] = [
        "CONDUCTOR_USAGE_MINIMAX_SOURCE": "web",
        "CONDUCTOR_USAGE_MINIMAX_COOKIE_SOURCE": "manual",
        "CONDUCTOR_USAGE_MINIMAX_COOKIE": "HERTZ-SESSION=abc; group-id=demo",
        "MINIMAX_REMAINS_URL": "https://platform.minimax.io/v1/api/openplatform/coding_plan/remains",
        "MINIMAX_BILLING_HISTORY_URL": "https://platform.minimax.io/account/amount",
    ]

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MiniMaxUsageMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func makeJWT(payload: [String: Any]) -> String {
        let header = ["alg": "none", "typ": "JWT"]
        let headerData = try? JSONSerialization.data(withJSONObject: header)
        let payloadData = try? JSONSerialization.data(withJSONObject: payload)
        let headerPart = base64URL(headerData ?? Data())
        let payloadPart = base64URL(payloadData ?? Data())
        let signature = String(repeating: "s", count: 32)
        return "\(headerPart).\(payloadPart).\(signature)"
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class MiniMaxUsageMockURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
    }

    private static let lock = NSLock()
    private static var responses: [String: [Response]] = [:]
    private static var requests: [URLRequest] = []

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
        let response: Response? = Self.lock.withMiniMaxUsageLock {
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
    func withMiniMaxUsageLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
