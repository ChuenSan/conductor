import Foundation
import XCTest
@testable import ConductorCore

final class GLMUsageTests: XCTestCase {
    func testParsesThreeZaiLimitsAndMCPDetails() throws {
        let json = """
        {
          "code": 200,
          "msg": "ok",
          "success": true,
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 25,
                "nextResetTime": 1775020168897
              },
              {
                "type": "TOKENS_LIMIT",
                "unit": 6,
                "number": 1,
                "percentage": 9,
                "nextResetTime": 1775588029998
              },
              {
                "type": "TIME_LIMIT",
                "unit": 5,
                "number": 1,
                "usage": 1000,
                "currentValue": 224,
                "remaining": 776,
                "percentage": 22,
                "usageDetails": [
                  { "modelCode": "search-prime", "usage": 210 },
                  { "modelCode": "web-reader", "usage": 14 },
                  { "modelCode": "zread", "usage": 0 }
                ]
              }
            ],
            "planName": "Pro"
          }
        }
        """

        let snapshot = try GLMUsageFetcher.parse(Data(json.utf8))

        XCTAssertEqual(snapshot.planType, "Pro")
        XCTAssertEqual(snapshot.session?.usedPercent, 25)
        XCTAssertEqual(snapshot.session?.windowSeconds, 18_000)
        XCTAssertEqual(snapshot.weekly?.usedPercent, 9)
        XCTAssertEqual(snapshot.weekly?.windowSeconds, 604_800)
        XCTAssertEqual(snapshot.extraRateWindows.map(\.id), [
            "zai.mcp.search-prime",
            "zai.mcp.web-reader",
        ])
        XCTAssertEqual(snapshot.extraRateWindows.first?.window.resetDescription, "MCP")
    }

    func testParsesZaiModelUsagePayloadAndHourlyBars() throws {
        let json = """
        {
          "code": 200,
          "msg": "success",
          "success": true,
          "data": {
            "x_time": ["2026-05-14 08:00", "2026-05-14 09:00"],
            "modelDataList": [
              { "modelName": "glm-4.6", "tokensUsage": [100, null] },
              { "modelName": "glm-4.5", "tokensUsage": [50, 25] }
            ]
          }
        }
        """

        let usage = try GLMUsageFetcher.parseModelUsage(Data(json.utf8))

        XCTAssertEqual(usage.xTime, ["2026-05-14 08:00", "2026-05-14 09:00"])
        XCTAssertEqual(usage.modelDataList[0].tokensUsage, [100, nil])
        XCTAssertEqual(usage.modelDataList[1].tokensUsage, [50, 25])

        let now = Self.date("2026-05-14 12:00")
        let bars = GLMUsageFetcher.hourlyBars(from: usage, now: now)
        XCTAssertEqual(bars.map { $0.label }, ["08", "08", "09"])
        XCTAssertEqual(bars.map { $0.model }, ["glm-4.6", "glm-4.5", "glm-4.5"])
        XCTAssertEqual(bars.map { $0.tokens }, [100, 50, 25])
    }

    func testFetchAttachesZaiModelUsageAsOptionalExtraWindows() async throws {
        GLMUsageMockURLProtocol.reset()
        GLMUsageMockURLProtocol.enqueue(path: "/api/monitor/usage/quota/limit", statusCode: 200, body: """
        {
          "code": 200,
          "msg": "ok",
          "success": true,
          "data": {
            "limits": [
              {
                "type": "TOKENS_LIMIT",
                "unit": 3,
                "number": 5,
                "percentage": 25,
                "nextResetTime": 1775020168897
              }
            ],
            "planName": "Pro"
          }
        }
        """)
        GLMUsageMockURLProtocol.enqueue(path: "/api/monitor/usage/model-usage", statusCode: 200, body: """
        {
          "code": 200,
          "msg": "success",
          "success": true,
          "data": {
            "x_time": ["2026-05-14 08:00"],
            "modelDataList": [
              { "modelName": "glm-4.6", "tokensUsage": [100] },
              { "modelName": "glm-4.5", "tokensUsage": [50] }
            ]
          }
        }
        """)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GLMUsageMockURLProtocol.self]
        let session = URLSession(configuration: config)

        let snapshot = try await GLMUsageFetcher.fetch(
            env: ["Z_AI_API_KEY": "token"],
            session: session)

        XCTAssertEqual(snapshot.extraRateWindows.map(\.id), [
            "zai.model.glm-4-6",
            "zai.model.glm-4-5",
        ])
        XCTAssertEqual(snapshot.extraRateWindows.first?.title, "glm-4.6 · 24h")
        XCTAssertEqual(snapshot.extraRateWindows.first?.window.windowMinutes, 1_440)

        let requests = GLMUsageMockURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "authorization"), "Bearer token")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    private static func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value) ?? Date()
    }
}

private final class GLMUsageMockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [String: [(statusCode: Int, body: String)]] = [:]
    private static var requests: [URLRequest] = []

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
            url: request.url ?? URL(string: "https://api.z.ai")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
