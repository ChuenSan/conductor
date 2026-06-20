import Foundation
import XCTest
@testable import ConductorCore

final class CursorUsageTests: XCTestCase {
    func testExtractsCursorUserIDFromWorkosSessionCookie() {
        let header = "other=1; WorkosCursorSessionToken=user_test%3A%3Atoken-value; theme=dark"

        XCTAssertEqual(CursorUsageFetcher.cursorUserID(fromCookieHeader: header), "user_test")
    }

    func testParsesLegacyCursorRequestUsage() throws {
        let json = """
        {
          "gpt-4": {
            "numRequests": 200,
            "numRequestsTotal": 240,
            "maxRequestUsage": 500
          }
        }
        """

        let usage = try XCTUnwrap(CursorUsageFetcher.parseLegacyRequestUsage(Data(json.utf8)))

        XCTAssertEqual(usage.used, 240)
        XCTAssertEqual(usage.limit, 500)
        XCTAssertEqual(usage.usedPercent, 48)
    }

    func testLegacyCursorRequestQuotaOverridesTokenBreakdown() throws {
        let summary = """
        {
          "membershipType": "enterprise",
          "billingCycleStart": "2026-06-01T00:00:00.000Z",
          "billingCycleEnd": "2026-07-01T00:00:00.000Z",
          "individualUsage": {
            "plan": {
              "used": 5000,
              "limit": 10000,
              "autoPercentUsed": 25,
              "apiPercentUsed": 80,
              "totalPercentUsed": 50
            }
          }
        }
        """

        let snapshot = try CursorUsageFetcher.parse(
            Data(summary.utf8),
            legacyRequestUsage: CursorUsageFetcher.LegacyRequestUsage(used: 240, limit: 500))

        XCTAssertEqual(snapshot.primary?.title, "Requests")
        XCTAssertEqual(snapshot.primary?.usedPercent, 48)
        XCTAssertNil(snapshot.secondary)
        XCTAssertNil(snapshot.tertiary)
        XCTAssertEqual(snapshot.planName, "Cursor Enterprise")
    }

    func testCursorFetchAddsLegacyUsageRequestWhenCookieCarriesUserID() async throws {
        CursorUsageMockURLProtocol.reset()
        CursorUsageMockURLProtocol.enqueue(path: "/api/usage-summary", statusCode: 200, body: """
        {
          "membershipType": "enterprise",
          "individualUsage": {
            "plan": {
              "totalPercentUsed": 50,
              "autoPercentUsed": 25,
              "apiPercentUsed": 80
            }
          }
        }
        """)
        CursorUsageMockURLProtocol.enqueue(path: "/api/usage", statusCode: 200, body: """
        {
          "gpt-4": {
            "numRequestsTotal": 240,
            "maxRequestUsage": 500
          }
        }
        """)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CursorUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await withEnvironment("CONDUCTOR_USAGE_CURSOR_COOKIE", "WorkosCursorSessionToken=user_test%3A%3Atoken") {
            try await CursorUsageFetcher.fetch(session: session)
        }

        XCTAssertEqual(snapshot.primary?.title, "Requests")
        XCTAssertEqual(snapshot.primary?.usedPercent, 48)
        XCTAssertNil(snapshot.secondary)
        XCTAssertEqual(snapshot.planName, "Cursor Enterprise")

        let requests = CursorUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, ["/api/usage-summary", "/api/usage"])
        XCTAssertEqual(
            URLComponents(url: requests[1].url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "user" })?.value,
            "user_test")
    }

    func testCursorFetchKeepsUsageSummaryWhenLegacyRequestFails() async throws {
        CursorUsageMockURLProtocol.reset()
        CursorUsageMockURLProtocol.enqueue(path: "/api/usage-summary", statusCode: 200, body: """
        {
          "membershipType": "pro",
          "individualUsage": {
            "plan": {
              "totalPercentUsed": 50,
              "autoPercentUsed": 25,
              "apiPercentUsed": 80
            }
          }
        }
        """)
        CursorUsageMockURLProtocol.enqueue(path: "/api/usage", statusCode: 500, body: "{}")

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CursorUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await withEnvironment("CONDUCTOR_USAGE_CURSOR_COOKIE", "WorkosCursorSessionToken=user_test%3A%3Atoken") {
            try await CursorUsageFetcher.fetch(session: session)
        }

        XCTAssertEqual(snapshot.primary?.title, L("本期"))
        XCTAssertEqual(snapshot.primary?.usedPercent, 50)
        XCTAssertEqual(snapshot.secondary?.usedPercent, 25)
        XCTAssertEqual(snapshot.tertiary?.usedPercent, 80)
        XCTAssertEqual(snapshot.planName, "Cursor Pro")
    }

    private func withEnvironment<T>(
        _ key: String,
        _ value: String,
        operation: () async throws -> T) async rethrows -> T
    {
        let old = getenv(key).map { String(cString: $0) }
        setenv(key, value, 1)
        defer {
            if let old {
                setenv(key, old, 1)
            } else {
                unsetenv(key)
            }
        }
        return try await operation()
    }
}

private final class CursorUsageMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: [(statusCode: Int, body: String)]] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset() {
        lock.lock()
        responses = [:]
        requests = []
        lock.unlock()
    }

    static func enqueue(path: String, statusCode: Int, body: String) {
        lock.lock()
        responses[path, default: []].append((statusCode, body))
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        let value = requests
        lock.unlock()
        return value
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? "/"
        Self.lock.lock()
        Self.requests.append(request)
        let response: (statusCode: Int, body: String)?
        if var queue = Self.responses[path], !queue.isEmpty {
            response = queue.removeFirst()
            Self.responses[path] = queue
        } else {
            response = nil
        }
        Self.lock.unlock()

        let statusCode = response?.statusCode ?? 404
        let body = response?.body ?? "{}"
        let http = HTTPURLResponse(
            url: request.url ?? URL(string: "https://cursor.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
