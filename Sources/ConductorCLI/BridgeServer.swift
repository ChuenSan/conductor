import ConductorCore
import CryptoKit
import Darwin
import Dispatch
import Foundation

private func handleUsageHTTPServerTerminationSignal(_: Int32) {}

enum BridgeServer {
    private static let websocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    private static let maxPayloadBytes = PayloadLimit.maxBytes

    static func run(host: String, port: Int, interval: Double) throws {
        let server = socket(AF_INET, SOCK_STREAM, 0)
        guard server >= 0 else { throw CLIError("socket() failed: \(errnoText())") }
        var reuse: Int32 = 1
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            close(server)
            throw CLIError("Invalid bridge host: \(host)")
        }

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(server)
            throw CLIError("bind(\(host):\(port)) failed: \(errnoText())")
        }
        guard listen(server, 32) == 0 else {
            close(server)
            throw CLIError("listen() failed: \(errnoText())")
        }

        print("Conductor bridge listening on http://\(host):\(port)")
        print("  POST rpc:  http://\(host):\(port)/rpc")
        print("  SSE events: http://\(host):\(port)/events")
        print("  WS rpc:    ws://\(host):\(port)/rpc")
        print("  WS events: ws://\(host):\(port)/events")

        while true {
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                throw CLIError("accept() failed: \(errnoText())")
            }
            DispatchQueue.global(qos: .userInitiated).async {
                handle(client: client, interval: interval)
            }
        }
    }

    private static func handle(client fd: Int32, interval: Double) {
        defer { close(fd) }
        do {
            let request = try HTTPRequest.read(from: fd)
            if request.method == "OPTIONS" {
                try writeHTTP(fd: fd, status: "204 No Content", body: Data())
                return
            }
            if request.isWebSocket, request.path == "/rpc" {
                try acceptWebSocket(request, fd: fd)
                try rpcWebSocketLoop(fd: fd)
            } else if request.isWebSocket, request.path == "/events" {
                try acceptWebSocket(request, fd: fd)
                eventsWebSocketLoop(
                    fd: fd,
                    interval: request.queryDouble("interval") ?? interval,
                    limit: request.queryInt("limit") ?? 100)
            } else if request.method == "POST", request.path == "/rpc" {
                try writeHTTP(fd: fd, status: "200 OK", body: proxyData(body: request.body))
            } else if request.method == "POST", request.path == "/batch" {
                try writeHTTP(
                    fd: fd,
                    status: "200 OK",
                    contentType: "application/x-ndjson",
                    body: proxyBatchData(body: request.body))
            } else if request.method == "GET", request.path == "/status" {
                try writeHTTP(fd: fd, status: "200 OK", body: proxyData(
                    body: AutomationCodec.encode(AutomationRequest(id: 1, method: AutomationMethod.appStatus))))
            } else if request.method == "GET", request.path == "/methods" {
                try writeHTTP(fd: fd, status: "200 OK", body: proxyData(
                    body: AutomationCodec.encode(AutomationRequest(id: 1, method: AutomationMethod.appMethods))))
            } else if request.method == "GET", request.path == "/health" {
                try writeHTTP(fd: fd, status: "200 OK", body: healthData())
            } else if request.method == "GET", request.path == "/openapi.json" {
                try writeHTTP(fd: fd, status: "200 OK", body: openAPIData())
            } else if request.method == "GET", request.path == "/events" {
                try writeSSEHeader(fd: fd)
                eventsSSELoop(
                    fd: fd,
                    interval: request.queryDouble("interval") ?? interval,
                    limit: request.queryInt("limit") ?? 100)
            } else {
                try writeHTTP(fd: fd, status: "200 OK", body: docsData())
            }
        } catch let error as CLIError {
            let body = jsonData(.object([
                "ok": .bool(false),
                "error": .string(error.description),
            ]))
            try? writeHTTP(fd: fd, status: error.httpStatus, body: body)
        } catch {
            let body = jsonData(.object([
                "ok": .bool(false),
                "error": .string("\(error)"),
            ]))
            try? writeHTTP(fd: fd, status: "500 Internal Server Error", body: body)
        }
    }

    private static func rpcWebSocketLoop(fd: Int32) throws {
        while true {
            let frame: WebSocketFrame
            do {
                frame = try readFrame(fd: fd)
            } catch let error as CLIError where error.description == "WebSocket frame too large" {
                try? sendFrame(fd: fd, opcode: 0x8, payload: Data([0x03, 0xF1]))
                return
            }
            switch frame.opcode {
            case 0x1:
                let response = proxyData(body: frame.payload)
                try sendFrame(fd: fd, opcode: 0x1, payload: response)
            case 0x8:
                try sendFrame(fd: fd, opcode: 0x8, payload: Data())
                return
            case 0x9:
                try sendFrame(fd: fd, opcode: 0xA, payload: frame.payload)
            default:
                break
            }
        }
    }

    private static func eventsWebSocketLoop(fd: Int32, interval: Double, limit: Int) {
        eventPollLoop(interval: interval, limit: limit) { event in
            try sendFrame(fd: fd, opcode: 0x1, payload: jsonData(event))
        }
    }

    private static func eventsSSELoop(fd: Int32, interval: Double, limit: Int) {
        eventPollLoop(interval: interval, limit: limit) { event in
            let item = object(event)
            let id = item["id"]?.stringValue
            let type = item["type"]?.stringValue ?? item["topic"]?.stringValue ?? "message"
            var payload = Data()
            if let id { payload.append(Data("id: \(id)\n".utf8)) }
            payload.append(Data("event: \(type)\n".utf8))
            payload.append(Data("data: ".utf8))
            payload.append(jsonData(event))
            payload.append(Data("\n\n".utf8))
            try writeAll(payload, fd: fd)
        }
    }

    private static func eventPollLoop(interval: Double, limit: Int, emit: (JSONValue) throws -> Void) {
        var seen = Set<String>()
        let sleepMicros = useconds_t(max(250_000, Int((interval * 1_000_000).rounded())))
        let limit = max(1, min(limit, 500))
        while true {
            guard let response = try? SocketClient().request(
                method: AutomationMethod.eventsRecent,
                params: ["limit": .int(limit)])
            else {
                usleep(sleepMicros)
                continue
            }
            do {
                for event in array(response.result).reversed() {
                    let item = object(event)
                    guard let id = item["id"]?.stringValue, !seen.contains(id) else { continue }
                    seen.insert(id)
                    try emit(event)
                }
            } catch {
                return
            }
            usleep(sleepMicros)
        }
    }

    private static func acceptWebSocket(_ request: HTTPRequest, fd: Int32) throws {
        guard let key = request.headers["sec-websocket-key"] else {
            throw CLIError("Missing Sec-WebSocket-Key")
        }
        let accept = websocketAccept(key)
        let response = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "Access-Control-Allow-Origin: *",
            "",
            "",
        ].joined(separator: "\r\n")
        try writeAll(Data(response.utf8), fd: fd)
    }

    private static func websocketAccept(_ key: String) -> String {
        let digest = Insecure.SHA1.hash(data: Data((key + websocketGUID).utf8))
        return Data(digest).base64EncodedString()
    }

    private static func proxyData(body: Data) -> Data {
        do {
            let request = try AutomationCodec.decodeRequest(body)
            let response = try SocketClient().requestRaw(request)
            return AutomationCodec.encode(response)
        } catch {
            return AutomationCodec.encode(AutomationResponse(
                id: nil,
                error: .badRequest("\(error)")))
        }
    }

    private static func proxyBatchData(body: Data) -> Data {
        guard let text = String(data: body, encoding: .utf8) else {
            return AutomationCodec.encode(AutomationResponse(
                id: nil,
                error: .badRequest("batch body must be UTF-8"))) + Data([0x0A])
        }
        var output = Data()
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let response: AutomationResponse
            do {
                let request = try AutomationCodec.decodeRequest(Data(line.utf8))
                response = try SocketClient().requestRaw(request)
            } catch {
                response = AutomationResponse(
                    id: nil,
                    error: .badRequest("batch line \(index + 1): \(error)"))
            }
            output.append(AutomationCodec.encode(response))
            output.append(0x0A)
        }
        return output
    }

    private static func healthData() -> Data {
        do {
            let status = try SocketClient().request(method: AutomationMethod.appStatus)
            var payload = object(status.result)
            payload["ok"] = .bool(true)
            payload["bridge"] = bridgeInfo()
            return jsonData(.object(payload))
        } catch {
            return jsonData(.object([
                "ok": .bool(false),
                "error": .string("\(error)"),
                "socket": .string(AutomationProtocol.defaultSocketURL.path),
                "bridge": bridgeInfo(),
            ]))
        }
    }

    private static func bridgeInfo() -> JSONValue {
        .object([
            "transport": .string("http-websocket"),
            "rpc": .string("/rpc"),
            "events": .string("/events"),
            "maxPayloadBytes": .int(maxPayloadBytes),
        ])
    }

    private static func docsData() -> Data {
        jsonData(.object([
            "app": .string("Conductor Bridge"),
            "endpoints": .object([
                "health": .string("GET /health"),
                "status": .string("GET /status"),
                "methods": .string("GET /methods"),
                "openapi": .string("GET /openapi.json"),
                "rpcHTTP": .string("POST /rpc"),
                "batchHTTP": .string("POST /batch"),
                "rpcWebSocket": .string("WS /rpc"),
                "eventsWebSocket": .string("WS /events"),
                "eventsSSE": .string("GET /events"),
            ]),
        ]))
    }

    private static func openAPIData() -> Data {
        jsonData(.object([
            "openapi": .string("3.1.0"),
            "info": .object([
                "title": .string("Conductor Bridge"),
                "version": .string("1.0.0"),
            ]),
            "paths": .object([
                "/health": .object([
                    "get": .object([
                        "summary": .string("Bridge and app health"),
                        "responses": okJSONResponse(),
                    ]),
                ]),
                "/status": .object([
                    "get": .object([
                        "summary": .string("Proxy app.status"),
                        "responses": automationResponseSpec(),
                    ]),
                ]),
                "/methods": .object([
                    "get": .object([
                        "summary": .string("Proxy app.methods"),
                        "responses": automationResponseSpec(),
                    ]),
                ]),
                "/rpc": .object([
                    "post": .object([
                        "summary": .string("Proxy one AutomationRequest"),
                        "requestBody": jsonRequestBody(description: "AutomationRequest JSON (max 4 MiB)"),
                        "responses": automationResponseSpec(),
                    ]),
                ]),
                "/batch": .object([
                    "post": .object([
                        "summary": .string("Proxy newline-delimited AutomationRequest messages"),
                        "requestBody": .object([
                            "required": .bool(true),
                            "description": .string("NDJSON AutomationRequest lines (max 4 MiB total)"),
                            "content": .object([
                                "application/x-ndjson": .object([
                                    "schema": .object(["type": .string("string")]),
                                ]),
                            ]),
                        ]),
                        "responses": .object([
                            "200": .object([
                                "description": .string("AutomationResponse NDJSON stream"),
                                "content": .object([
                                    "application/x-ndjson": .object([
                                        "schema": .object(["type": .string("string")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
                "/events": .object([
                    "get": .object([
                        "summary": .string("Server-Sent Events stream for events.recent"),
                        "parameters": .array([
                            queryParameter("limit", type: "integer"),
                            queryParameter("interval", type: "number"),
                        ]),
                        "responses": .object([
                            "200": .object([
                                "description": .string("SSE event stream"),
                                "content": .object([
                                    "text/event-stream": .object([
                                        "schema": .object(["type": .string("string")]),
                                    ]),
                                ]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]))
    }

    private static func automationResponseSpec() -> JSONValue {
        .object([
            "200": .object([
                "description": .string("AutomationResponse"),
                "content": .object([
                    "application/json": .object([
                        "schema": .object([
                            "type": .string("object"),
                            "required": .array([.string("ok")]),
                            "properties": .object([
                                "id": .object(["type": .array([.string("integer"), .string("null")])]),
                                "ok": .object(["type": .string("boolean")]),
                                "result": .object(["description": .string("Method result")]),
                                "error": .object(["description": .string("AutomationError")]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    }

    private static func okJSONResponse() -> JSONValue {
        .object([
            "200": .object([
                "description": .string("JSON response"),
                "content": .object([
                    "application/json": .object([
                        "schema": .object(["type": .string("object")]),
                    ]),
                ]),
            ]),
        ])
    }

    private static func jsonRequestBody(description: String) -> JSONValue {
        .object([
            "required": .bool(true),
            "description": .string(description),
            "content": .object([
                "application/json": .object([
                    "schema": .object(["type": .string("object")]),
                ]),
            ]),
        ])
    }

    private static func queryParameter(_ name: String, type: String) -> JSONValue {
        .object([
            "name": .string(name),
            "in": .string("query"),
            "required": .bool(false),
            "schema": .object(["type": .string(type)]),
        ])
    }

    private static func jsonData(_ value: JSONValue) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
    }

    private static func writeHTTP(
        fd: Int32,
        status: String,
        contentType: String = "application/json",
        body: Data
    ) throws {
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Private-Network: true",
            "",
            "",
        ].joined(separator: "\r\n")
        try writeAll(Data(header.utf8) + body, fd: fd)
    }

    private static func writeSSEHeader(fd: Int32) throws {
        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/event-stream",
            "Cache-Control: no-cache",
            "Connection: keep-alive",
            "Access-Control-Allow-Origin: *",
            "",
            "",
        ].joined(separator: "\r\n")
        try writeAll(Data(header.utf8), fd: fd)
    }

    private static func readFrame(fd: Int32) throws -> WebSocketFrame {
        let head = try readExactly(fd: fd, count: 2)
        let first = head[0]
        let second = head[1]
        let opcode = first & 0x0F
        let masked = (second & 0x80) != 0
        var length = UInt64(second & 0x7F)
        if length == 126 {
            let data = try readExactly(fd: fd, count: 2)
            length = UInt64(UInt16(data[0]) << 8 | UInt16(data[1]))
        } else if length == 127 {
            let data = try readExactly(fd: fd, count: 8)
            length = data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }
        if case .failure = PayloadLimit.validateFrameLength(length) {
            throw CLIError("WebSocket frame too large", httpStatus: "413 Payload Too Large")
        }
        let mask = masked ? try readExactly(fd: fd, count: 4) : []
        var payload = try readExactly(fd: fd, count: Int(length))
        if masked {
            for index in payload.indices {
                payload[index] ^= mask[index % 4]
            }
        }
        return WebSocketFrame(opcode: opcode, payload: Data(payload))
    }

    private static func sendFrame(fd: Int32, opcode: UInt8, payload: Data) throws {
        var header = Data()
        header.append(0x80 | opcode)
        if payload.count < 126 {
            header.append(UInt8(payload.count))
        } else if payload.count <= UInt16.max {
            header.append(126)
            header.append(UInt8((payload.count >> 8) & 0xFF))
            header.append(UInt8(payload.count & 0xFF))
        } else {
            header.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                header.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }
        try writeAll(header + payload, fd: fd)
    }

    private static func readExactly(fd: Int32, count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let readCount = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(fd, base.advanced(by: offset), count - offset)
            }
            guard readCount > 0 else { throw CLIError("connection closed") }
            offset += readCount
        }
        return buffer
    }

    private static func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                guard written > 0 else { throw CLIError("write() failed: \(errnoText())") }
                pointer += written
                remaining -= written
            }
        }
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}

enum UsageHTTPServer {
    private static let usageFetchGate = UsageHTTPAsyncGate()
    private static let defaultRefreshInterval: TimeInterval = 60
    private static let defaultRequestTimeout: TimeInterval = 30
    private static let configMutationBodyLimitBytes = 16_384

    static func run(
        host: String,
        port: Int,
        refreshInterval: TimeInterval = Self.defaultRefreshInterval,
        requestTimeout: TimeInterval = Self.defaultRequestTimeout
    ) throws {
        ignoreSIGPIPE()
        let terminationMonitor = UsageHTTPServerTerminationSignalMonitor()
        defer { terminationMonitor.cancel() }

        let server = socket(AF_INET, SOCK_STREAM, 0)
        guard server >= 0 else { throw CLIError("socket() failed: \(errnoText())") }
        var reuse: Int32 = 1
        setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        let cache = UsageHTTPResponseCache()

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            close(server)
            throw CLIError("Invalid serve host: \(host)")
        }

        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            close(server)
            throw CLIError("bind(\(host):\(port)) failed: \(errnoText())")
        }
        guard listen(server, 32) == 0 else {
            close(server)
            throw CLIError("listen() failed: \(errnoText())")
        }

        print("Conductor usage server listening on http://\(host):\(port)")
        print("  health: http://\(host):\(port)/health")
        print("  usage:  http://\(host):\(port)/usage?provider=codex")
        print("  cost:   http://\(host):\(port)/cost?provider=codex&days=7")
        print("  store:  http://\(host):\(port)/storage?provider=codex")
        print("  status: http://\(host):\(port)/provider-status?provider=both")
        print("  diag:   http://\(host):\(port)/diagnose?provider=codex")
        print("  config: http://\(host):\(port)/config/providers?provider=codex")
        print("  api:    http://\(host):\(port)/openapi.json")
        print("  cache:  refresh-interval=\(formatSeconds(refreshInterval)) request-timeout=\(formatSeconds(requestTimeout))")

        while true {
            let client = accept(server, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                throw CLIError("accept() failed: \(errnoText())")
            }
            DispatchQueue.global(qos: .userInitiated).async {
                handle(
                    client: client,
                    cache: cache,
                    refreshInterval: refreshInterval,
                    requestTimeout: requestTimeout)
            }
        }
    }

    private static func handle(
        client fd: Int32,
        cache: UsageHTTPResponseCache,
        refreshInterval: TimeInterval,
        requestTimeout: TimeInterval
    ) {
        defer { close(fd) }
        do {
            let request: HTTPRequest
            do {
                request = try HTTPRequest.readUsageServerRequest(from: fd)
            } catch {
                try writeJSON(fd: fd, status: "400 Bad Request", payload: ErrorPayload(error: "invalid request"))
                return
            }
            if let error = HTTPRequest.loopbackHostValidationError(request.hostHeaders) {
                let status: String
                let message: String
                switch error {
                case .missing, .duplicate:
                    status = "400 Bad Request"
                    message = "invalid request"
                case .invalid, .disallowed:
                    status = "403 Forbidden"
                    message = "forbidden host"
                }
                try writeJSON(fd: fd, status: status, payload: ErrorPayload(error: message))
                return
            }
            if request.method == "OPTIONS" {
                try writeHTTP(fd: fd, status: "204 No Content", body: Data())
                return
            }
            let isConfigMutation = request.method == "POST" && [
                "/config/account",
                "/config/provider",
                "/config/order",
                "/cache/clear",
            ].contains(request.path)
            guard request.method == "GET" || isConfigMutation else {
                try writeJSON(fd: fd, status: "405 Method Not Allowed", payload: ErrorPayload(error: "method not allowed"))
                return
            }

            switch request.path {
            case "/health":
                try writeJSON(fd: fd, status: "200 OK", payload: HealthPayload(status: "ok", service: "usage"))
            case "/openapi.json":
                try writeResponse(fd: fd, response: jsonHTTPResponse(payload: usageOpenAPI()))
            case "/usage":
                let provider = request.query["provider"]
                let source = try querySource(request.query["source"])
                let includeStatus = try queryBoolFlag(request.query["status"], name: "status")
                let configStore = CLIConfigStore()
                let config = try configStore.load()
                let entries = try UsageProviderCatalog.entries(for: provider, config: config)
                let accountSelection = try queryAccountSelection(request.query)
                let cacheKey = try serveCacheKey(
                    kind: "usage",
                    query: [
                        "provider": provider ?? "",
                        "source": source,
                        "status": includeStatus ? "1" : "0",
                        "account": accountSelection.label ?? "",
                        "account-index": accountSelection.index.map(String.init) ?? "",
                        "all-accounts": accountSelection.allAccounts ? "1" : "0",
                    ],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        await usageFetchGate.run {
                            do {
                                let reports = try await fetchUsageReports(
                                    entries: entries,
                                    source: source,
                                    config: config,
                                    configStore: configStore,
                                    accountSelection: accountSelection,
                                    includeStatus: includeStatus)
                                return jsonHTTPResponse(
                                    payload: reports,
                                    usageCacheKeys: reports.map(\.cacheAccountKey))
                            } catch is CancellationError {
                                return errorHTTPResponse(status: "499 Client Closed Request", message: "request cancelled")
                            } catch let error as CLIError {
                                return errorHTTPResponse(status: "400 Bad Request", message: error.description)
                            } catch {
                                return errorHTTPResponse(status: "500 Internal Server Error", message: "\(error)")
                            }
                        }
                    }
                }
                try writeResponse(fd: fd, response: response)
            case "/cost":
                let days = try queryDays(request.query["days"])
                let sources = try costSources(request.query["provider"])
                let config = try CLIConfigStore().load()
                let cacheKey = try serveCacheKey(
                    kind: "cost",
                    query: [
                        "provider": request.query["provider"] ?? "",
                        "days": String(days),
                    ],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        do {
                            let report = try await UsageCostCLIReporter.scanAsyncUnlessCancelled(
                                daysBack: days,
                                sources: sources)
                            return jsonHTTPResponse(payload: report)
                        } catch is CancellationError {
                            return errorHTTPResponse(status: "499 Client Closed Request", message: "request cancelled")
                        } catch {
                            return errorHTTPResponse(
                                status: "500 Internal Server Error",
                                message: commandErrorDescription(error))
                        }
                    }
                }
                try writeResponse(fd: fd, response: response)
            case "/storage":
                let provider = request.query["provider"] ?? "all"
                let config = try CLIConfigStore().load()
                let entries = try UsageProviderCatalog.entries(for: provider, config: config)
                let cacheKey = try serveCacheKey(
                    kind: "storage",
                    query: [
                        "provider": provider,
                    ],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        jsonHTTPResponse(payload: storageReports(entries: entries, config: config))
                    }
                }
                try writeResponse(fd: fd, response: response)
            case "/provider-status":
                let config = try CLIConfigStore().load()
                let entries = try UsageProviderCatalog.entries(for: request.query["provider"], config: config)
                let cacheKey = try serveCacheKey(
                    kind: "provider-status",
                    query: [
                        "provider": request.query["provider"] ?? "",
                    ],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        do {
                            let statuses = try await UsageProviderStatusReporter.fetchUnlessCancelled(entries: entries)
                            return jsonHTTPResponse(payload: statuses)
                        } catch is CancellationError {
                            return errorHTTPResponse(status: "499 Client Closed Request", message: "request cancelled")
                        } catch {
                            return errorHTTPResponse(status: "500 Internal Server Error", message: "\(error)")
                        }
                    }
                }
                try writeResponse(fd: fd, response: response)
            case "/diagnose":
                let provider = request.query["provider"]
                let source = try querySource(request.query["source"])
                let config = try CLIConfigStore().load()
                let entries = try UsageProviderCatalog.entries(for: provider, config: config)
                let accountSelection = try queryAccountSelection(request.query)
                let includeStorage = try queryBoolFlag(request.query["storage"], name: "storage")
                    || config.usage.providerStorageFootprintsEnabled
                let cacheKey = try serveCacheKey(
                    kind: "diagnose",
                    query: [
                        "provider": provider ?? "",
                        "source": source,
                        "account": accountSelection.label ?? "",
                        "account-index": accountSelection.index.map(String.init) ?? "",
                        "all-accounts": accountSelection.allAccounts ? "1" : "0",
                        "storage": includeStorage ? "1" : "0",
                    ],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        await usageFetchGate.run {
                            do {
                                let diagnostics = try await fetchUsageDiagnostics(
                                    entries: entries,
                                    source: source,
                                    config: config,
                                    accountSelection: accountSelection,
                                    includeStorage: includeStorage)
                                return jsonHTTPResponse(payload: diagnostics)
                            } catch is CancellationError {
                                return errorHTTPResponse(status: "499 Client Closed Request", message: "request cancelled")
                            } catch let error as CLIError {
                                return errorHTTPResponse(status: "400 Bad Request", message: error.description)
                            } catch {
                                return errorHTTPResponse(status: "500 Internal Server Error", message: "\(error)")
                            }
                        }
                    }
                }
                try writeResponse(fd: fd, response: response)
            case "/config/providers":
                let provider = request.query["provider"]
                let config = try CLIConfigStore().load()
                let cacheKey = try serveCacheKey(
                    kind: "config-providers",
                    query: [
                        "provider": provider ?? "",
                    ],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        do {
                            let statuses = try configProviderStatuses(config, providerSelection: provider)
                            return jsonHTTPResponse(payload: statuses)
                        } catch let error as CLIError {
                            return errorHTTPResponse(status: "400 Bad Request", message: error.description)
                        } catch let error as UsageProviderCatalogError {
                            return errorHTTPResponse(status: "400 Bad Request", message: error.description)
                        } catch {
                            return errorHTTPResponse(status: "500 Internal Server Error", message: "\(error)")
                        }
                    }
                }
                try writeResponse(fd: fd, response: response)
            case "/config/dump":
                let config = try CLIConfigStore().load()
                try writeResponse(fd: fd, response: jsonHTTPResponse(payload: config))
            case "/config/accounts":
                let provider = try configTokenAccountProvider(raw: request.query["provider"])
                let store = CLIConfigStore()
                let config = try store.load()
                let response = jsonHTTPResponse(payload: configTokenAccountsResult(
                    provider: provider,
                    config: config,
                    configPath: store.fileURL.path))
                try writeResponse(fd: fd, response: response)
            case "/config/account":
                guard request.method == "POST" else {
                    try writeJSON(fd: fd, status: "405 Method Not Allowed", payload: ErrorPayload(error: "method not allowed"))
                    return
                }
                do {
                    let body = try request.completeBody(from: fd, maxBytes: Self.configMutationBodyLimitBytes)
                    let response = try configAccountMutationResponse(body: body)
                    try writeResponse(fd: fd, response: response)
                } catch let error as CLIError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: error.description))
                } catch let error as DecodingError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: "Invalid JSON body: \(error)"))
                }
            case "/config/provider":
                guard request.method == "POST" else {
                    try writeJSON(fd: fd, status: "405 Method Not Allowed", payload: ErrorPayload(error: "method not allowed"))
                    return
                }
                do {
                    let body = try request.completeBody(from: fd, maxBytes: Self.configMutationBodyLimitBytes)
                    let response = try configProviderMutationResponse(body: body)
                    try writeResponse(fd: fd, response: response)
                } catch let error as CLIError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: error.description))
                } catch let error as DecodingError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: "Invalid JSON body: \(error)"))
                } catch let error as UsageProviderCatalogError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: error.description))
                }
            case "/config/order":
                guard request.method == "POST" else {
                    try writeJSON(fd: fd, status: "405 Method Not Allowed", payload: ErrorPayload(error: "method not allowed"))
                    return
                }
                do {
                    let body = try request.completeBody(from: fd, maxBytes: Self.configMutationBodyLimitBytes)
                    let response = try configOrderMutationResponse(body: body)
                    try writeResponse(fd: fd, response: response)
                } catch let error as CLIError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: error.description))
                } catch let error as DecodingError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: "Invalid JSON body: \(error)"))
                } catch let error as UsageProviderCatalogError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: error.description))
                }
            case "/cache/clear":
                guard request.method == "POST" else {
                    try writeJSON(fd: fd, status: "405 Method Not Allowed", payload: ErrorPayload(error: "method not allowed"))
                    return
                }
                do {
                    let body = try request.completeBody(from: fd, maxBytes: Self.configMutationBodyLimitBytes)
                    let response = try runAsync {
                        try await cacheClearMutationResponse(body: body)
                    }
                    try writeResponse(fd: fd, response: response)
                } catch let error as CLIError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: error.description))
                } catch let error as DecodingError {
                    try writeResponse(fd: fd, response: errorHTTPResponse(status: "400 Bad Request", message: "Invalid JSON body: \(error)"))
                }
            case "/config/validate":
                let config = try CLIConfigStore().load()
                let cacheKey = try serveCacheKey(
                    kind: "config-validate",
                    query: [:],
                    config: config)
                let response = try runAsync {
                    await cachedServeResponse(
                        key: cacheKey,
                        cache: cache,
                        refreshInterval: refreshInterval,
                        requestTimeout: requestTimeout)
                    {
                        jsonHTTPResponse(payload: validateConfig(config))
                    }
                }
                try writeResponse(fd: fd, response: response)
            default:
                try writeJSON(fd: fd, status: "404 Not Found", payload: ErrorPayload(error: "not found"))
            }
        } catch let error as UsageProviderCatalogError {
            try? writeJSON(fd: fd, status: "400 Bad Request", payload: ErrorPayload(error: error.description))
        } catch let error as CLIError {
            try? writeJSON(fd: fd, status: "400 Bad Request", payload: ErrorPayload(error: error.description))
        } catch {
            try? writeJSON(fd: fd, status: "500 Internal Server Error", payload: ErrorPayload(error: "\(error)"))
        }
    }

    private static func querySource(_ raw: String?) throws -> String {
        let source = (raw ?? "auto").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let supported = Set(["auto", "web", "cli", "oauth", "api"])
        guard supported.contains(source) else {
            throw CLIError("source must be auto, web, cli, oauth, or api")
        }
        return source
    }

    private static func queryDays(_ raw: String?) throws -> Int {
        guard let raw, !raw.isEmpty else { return 30 }
        guard let value = Int(raw), (1...365).contains(value) else {
            throw CLIError("days must be 1...365")
        }
        return value
    }

    private static func queryAccountSelection(_ query: [String: String]) throws -> UsageAccountSelection {
        let label = query["account"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let index: Int?
        if let rawIndex = query["account-index"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawIndex.isEmpty
        {
            guard let parsed = Int(rawIndex), parsed > 0 else {
                throw CLIError("account-index must be a positive integer")
            }
            index = parsed - 1
        } else {
            index = nil
        }
        let allAccounts = try queryBoolFlag(query["all-accounts"], name: "all-accounts")
        if allAccounts, (label?.isEmpty == false || index != nil) {
            throw CLIError("all-accounts cannot be combined with account or account-index")
        }
        return UsageAccountSelection(
            label: label?.isEmpty == false ? label : nil,
            index: index,
            allAccounts: allAccounts)
    }

    private static func queryBoolFlag(_ raw: String?, name: String) throws -> Bool {
        guard let raw else { return false }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "1" || normalized == "true" || normalized == "yes" {
            return true
        }
        if normalized == "0" || normalized == "false" || normalized == "no" {
            return false
        }
        throw CLIError("\(name) must be a boolean: true/false, 1/0, yes/no, or empty")
    }

    private static func configAccountMutationResponse(body: Data) throws -> UsageHTTPResponse {
        guard !body.isEmpty else {
            throw CLIError("Missing JSON body")
        }
        let request = try JSONDecoder().decode(ConfigAccountMutationRequest.self, from: body)
        let provider = try configTokenAccountProvider(raw: request.provider)
        let action = request.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result: ConfigTokenAccountMutationResult
        switch action {
        case "add", "create":
            guard let token = cleanConfigSecret(request.token) else {
                throw CLIError("Missing token account secret. Provide token in the JSON body.")
            }
            result = try addConfigTokenAccount(
                provider: provider,
                token: token,
                label: request.label,
                organizationID: request.organizationID,
                externalIdentifier: request.externalIdentifier,
                noSelect: request.noSelect,
                noEnable: request.noEnable)
        case "select", "use", "activate":
            result = try selectConfigTokenAccount(
                provider: provider,
                account: request.account,
                accountIndex: try request.positiveAccountIndex())
        case "update", "edit", "patch":
            result = try updateConfigTokenAccount(
                provider: provider,
                account: request.account,
                accountIndex: try request.positiveAccountIndex(),
                token: cleanConfigSecret(request.token),
                label: request.label,
                organizationID: request.organizationID,
                clearOrganizationID: request.clearOrganizationID,
                externalIdentifier: request.externalIdentifier,
                clearExternalIdentifier: request.clearExternalIdentifier,
                select: request.select)
        case "remove", "delete", "rm":
            result = try removeConfigTokenAccount(
                provider: provider,
                account: request.account,
                accountIndex: try request.positiveAccountIndex())
        default:
            throw CLIError("Unknown account action: \(request.action)")
        }
        return jsonHTTPResponse(payload: result)
    }

    private static func configProviderMutationResponse(body: Data) throws -> UsageHTTPResponse {
        guard !body.isEmpty else {
            throw CLIError("Missing JSON body")
        }
        let request = try JSONDecoder().decode(ConfigProviderMutationRequest.self, from: body)
        let provider = try configProviderEntry(raw: request.provider)
        let action = request.action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let result: ConfigProviderMutationResponse
        switch action {
        case "enable":
            let mutation = try setConfigProviderEnabled(provider: provider, enabled: true)
            result = ConfigProviderMutationResponse(
                action: "enable",
                provider: mutation.provider,
                displayName: mutation.displayName,
                enabled: mutation.enabled,
                cookieSource: nil,
                key: nil,
                present: nil,
                providerOrder: nil,
                configPath: mutation.configPath)
        case "disable":
            let mutation = try setConfigProviderEnabled(provider: provider, enabled: false)
            result = ConfigProviderMutationResponse(
                action: "disable",
                provider: mutation.provider,
                displayName: mutation.displayName,
                enabled: mutation.enabled,
                cookieSource: nil,
                key: nil,
                present: nil,
                providerOrder: nil,
                configPath: mutation.configPath)
        case "set-api-key", "set-key":
            guard UsageProviderConfigCapabilities.supportsAPIKey(provider.id) else {
                throw CLIError("\(provider.id) does not support config API keys.")
            }
            guard let apiKey = cleanConfigSecret(request.apiKey) else {
                throw CLIError("Missing API key. Provide apiKey in the JSON body.")
            }
            let mutation = try setConfigProviderAPIKey(
                provider: provider,
                apiKey: apiKey,
                noEnable: request.noEnable)
            result = ConfigProviderMutationResponse(
                action: "set-api-key",
                provider: mutation.provider,
                displayName: provider.name,
                enabled: mutation.enabled,
                cookieSource: nil,
                key: nil,
                present: nil,
                providerOrder: nil,
                configPath: mutation.configPath)
        case "set-cookie", "set-cookie-header", "set-session":
            guard UsageProviderConfigCapabilities.supportsCookieHeader(provider.id) else {
                throw CLIError("\(provider.id) does not support config cookies.")
            }
            guard let cookieHeader = cleanConfigSecret(request.cookie) else {
                throw CLIError("Missing Cookie header. Provide cookie in the JSON body.")
            }
            let mutation = try setConfigProviderCookie(
                provider: provider,
                cookieHeader: cookieHeader,
                noEnable: request.noEnable)
            result = ConfigProviderMutationResponse(
                action: "set-cookie",
                provider: mutation.provider,
                displayName: provider.name,
                enabled: mutation.enabled,
                cookieSource: mutation.cookieSource,
                key: nil,
                present: nil,
                providerOrder: nil,
                configPath: mutation.configPath)
        case "set", "set-field":
            guard let key = request.key else {
                throw CLIError("Missing config key. Provide key in the JSON body.")
            }
            guard let value = request.value else {
                throw CLIError("Missing config value. Provide value in the JSON body.")
            }
            let mutation = try setConfigProviderField(
                provider: provider,
                key: key,
                value: value,
                unset: false)
            result = ConfigProviderMutationResponse(
                action: "set-field",
                provider: mutation.provider,
                displayName: mutation.displayName,
                enabled: mutation.enabled,
                cookieSource: nil,
                key: mutation.key,
                present: mutation.present,
                providerOrder: nil,
                configPath: mutation.configPath)
        case "unset", "unset-field", "clear-field":
            guard let key = request.key else {
                throw CLIError("Missing config key. Provide key in the JSON body.")
            }
            let mutation = try setConfigProviderField(
                provider: provider,
                key: key,
                value: nil,
                unset: true)
            result = ConfigProviderMutationResponse(
                action: "unset-field",
                provider: mutation.provider,
                displayName: mutation.displayName,
                enabled: mutation.enabled,
                cookieSource: nil,
                key: mutation.key,
                present: mutation.present,
                providerOrder: nil,
                configPath: mutation.configPath)
        default:
            throw CLIError("Unknown provider action: \(request.action)")
        }
        return jsonHTTPResponse(payload: result)
    }

    private static func configOrderMutationResponse(body: Data) throws -> UsageHTTPResponse {
        guard !body.isEmpty else {
            throw CLIError("Missing JSON body")
        }
        let request = try JSONDecoder().decode(ConfigOrderMutationRequest.self, from: body)
        let selection = request.providerSelection
        guard !selection.isEmpty else {
            throw CLIError("Missing provider order. Provide providers in the JSON body.")
        }
        let mutation = try setConfigProviderOrder(providerSelection: selection)
        return jsonHTTPResponse(payload: ConfigProviderMutationResponse(
            action: "order",
            provider: nil,
            displayName: nil,
            enabled: nil,
            cookieSource: nil,
            key: nil,
            present: nil,
            providerOrder: mutation.providerOrder,
            configPath: mutation.configPath))
    }

    private static func cacheClearMutationResponse(body: Data) async throws -> UsageHTTPResponse {
        guard !body.isEmpty else {
            throw CLIError("Missing JSON body")
        }
        let request = try JSONDecoder().decode(CacheClearRequest.self, from: body)
        let result = try await clearUsageCaches(
            cookies: request.cookies,
            cost: request.cost,
            all: request.all,
            provider: request.provider,
            missingSelectionMessage: "Specify cookies, cost, or all.")
        return jsonHTTPResponse(payload: result)
    }

    private static func usageOpenAPI() -> JSONValue {
        .object([
            "openapi": .string("3.1.0"),
            "info": .object([
                "title": .string("Conductor Usage Server"),
                "version": .string("1.0.0"),
            ]),
            "paths": .object([
                "/health": usageOpenAPIGet(
                    summary: "Usage server health",
                    parameters: [],
                    responseSchema: usageHealthOpenAPISchema()),
                "/usage": usageOpenAPIGet(
                    summary: "Fetch provider usage snapshots",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "both, all, or comma-separated provider IDs/aliases"),
                        usageOpenAPIQuery("source", type: "string", description: "auto, web, cli, oauth, or api"),
                        usageOpenAPIQuery("account", type: "string", description: "Token account label"),
                        usageOpenAPIQuery("account-index", type: "integer", description: "1-based token account index"),
                        usageOpenAPIQuery("all-accounts", type: "boolean", description: "Fetch all configured accounts"),
                        usageOpenAPIQuery("status", type: "boolean", description: "Include provider status"),
                    ],
                    responseSchema: usageReportsOpenAPISchema()),
                "/cost": usageOpenAPIGet(
                    summary: "Fetch local cost history",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "all, both, codex, claude, vertexai, or bedrock"),
                        usageOpenAPIQuery("days", type: "integer", description: "History window, 1...365"),
                    ],
                    responseSchema: usageCostOpenAPISchema()),
                "/storage": usageOpenAPIGet(
                    summary: "Scan local provider storage without fetching account usage",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "all, both, or comma-separated provider IDs/aliases"),
                    ],
                    responseSchema: usageStorageReportsOpenAPISchema()),
                "/provider-status": usageOpenAPIGet(
                    summary: "Fetch provider service status",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "both, all, or comma-separated provider IDs/aliases"),
                    ],
                    responseSchema: usageProviderStatusReportsOpenAPISchema()),
                "/diagnose": usageOpenAPIGet(
                    summary: "Fetch provider diagnostics with redacted settings, errors, and repair actions",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "both, all, or comma-separated provider IDs/aliases"),
                        usageOpenAPIQuery("source", type: "string", description: "auto, web, cli, oauth, or api"),
                        usageOpenAPIQuery("account", type: "string", description: "Token account label"),
                        usageOpenAPIQuery("account-index", type: "integer", description: "1-based token account index"),
                        usageOpenAPIQuery("all-accounts", type: "boolean", description: "Diagnose all configured accounts"),
                        usageOpenAPIQuery("storage", type: "boolean", description: "Include local storage footprint summary"),
                    ],
                    responseSchema: usageDiagnosticsOpenAPISchema()),
                "/config/providers": usageOpenAPIGet(
                    summary: "List provider configuration capabilities",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "all, both, or comma-separated provider IDs/aliases"),
                    ],
                    responseSchema: usageConfigProvidersOpenAPISchema()),
                "/config/dump": usageOpenAPIGet(
                    summary: "Dump the effective Conductor config",
                    parameters: [],
                    responseSchema: usageOpenAPIAnyObject()),
                "/config/accounts": usageOpenAPIGet(
                    summary: "List configured token accounts for a provider",
                    parameters: [
                        usageOpenAPIQuery("provider", type: "string", description: "Provider ID or alias"),
                    ],
                    responseSchema: usageConfigAccountsOpenAPISchema()),
                "/config/account": usageOpenAPIPost(
                    summary: "Add, select, or remove a provider token account",
                    requestSchema: usageConfigAccountMutationRequestOpenAPISchema(),
                    responseSchema: usageConfigAccountMutationOpenAPISchema()),
                "/config/provider": usageOpenAPIPost(
                    summary: "Enable, disable, or store credentials for one provider",
                    requestSchema: usageConfigProviderMutationRequestOpenAPISchema(),
                    responseSchema: usageConfigProviderMutationOpenAPISchema()),
                "/config/order": usageOpenAPIPost(
                    summary: "Update configured provider order",
                    requestSchema: usageConfigOrderMutationRequestOpenAPISchema(),
                    responseSchema: usageConfigProviderMutationOpenAPISchema()),
                "/config/validate": usageOpenAPIGet(
                    summary: "Validate provider configuration",
                    parameters: [],
                    responseSchema: usageConfigValidationIssuesOpenAPISchema()),
                "/cache/clear": usageOpenAPIPost(
                    summary: "Clear local usage caches",
                    requestSchema: usageCacheClearRequestOpenAPISchema(),
                    responseSchema: usageCacheClearResultsOpenAPISchema()),
            ]),
        ])
    }

    private static func usageOpenAPIGet(
        summary: String,
        parameters: [JSONValue],
        responseSchema: JSONValue? = nil
    ) -> JSONValue {
        .object([
            "get": .object([
                "summary": .string(summary),
                "parameters": .array(parameters),
                "responses": .object([
                    "200": .object([
                        "description": .string("JSON response"),
                        "content": usageOpenAPIJSONContent(
                            schema: responseSchema ?? .object(["type": .string("object")])),
                    ]),
                    "400": .object([
                        "description": .string("Invalid query or provider selection"),
                        "content": usageOpenAPIJSONContent(schema: usageErrorPayloadOpenAPISchema()),
                    ]),
                    "499": .object([
                        "description": .string("Request cancelled or timed out"),
                        "content": usageOpenAPIJSONContent(schema: usageErrorPayloadOpenAPISchema()),
                    ]),
                    "500": .object([
                        "description": .string("Unexpected server error"),
                        "content": usageOpenAPIJSONContent(schema: usageErrorPayloadOpenAPISchema()),
                    ]),
                ]),
            ]),
        ])
    }

    private static func usageOpenAPIPost(
        summary: String,
        requestSchema: JSONValue,
        responseSchema: JSONValue
    ) -> JSONValue {
        .object([
            "post": .object([
                "summary": .string(summary),
                "requestBody": .object([
                    "required": .bool(true),
                    "content": usageOpenAPIJSONContent(schema: requestSchema),
                ]),
                "responses": .object([
                    "200": .object([
                        "description": .string("JSON response"),
                        "content": usageOpenAPIJSONContent(schema: responseSchema),
                    ]),
                    "400": .object([
                        "description": .string("Invalid JSON body, provider, or account selection"),
                        "content": usageOpenAPIJSONContent(schema: usageErrorPayloadOpenAPISchema()),
                    ]),
                    "405": .object([
                        "description": .string("Method not allowed"),
                        "content": usageOpenAPIJSONContent(schema: usageErrorPayloadOpenAPISchema()),
                    ]),
                    "500": .object([
                        "description": .string("Unexpected server error"),
                        "content": usageOpenAPIJSONContent(schema: usageErrorPayloadOpenAPISchema()),
                    ]),
                ]),
            ]),
        ])
    }

    private static func usageOpenAPIJSONContent(schema: JSONValue) -> JSONValue {
        .object([
            "application/json": .object([
                "schema": schema,
            ]),
        ])
    }

    private static func usageHealthOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "status": usageOpenAPIString(),
            "service": usageOpenAPIString(),
        ])
    }

    private static func usageReportsOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageReportOpenAPISchema())
    }

    private static func usageReportOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "name": usageOpenAPIString(),
            "configured": usageOpenAPIBoolean(),
            "source": usageOpenAPIString(),
            "fetchedAt": usageOpenAPIString(format: "date-time"),
            "account": usageOpenAPIString(),
            "cacheAccountKey": usageOpenAPIString(),
            "status": usageProviderStatusOpenAPISchema(),
            "usage": usageSnapshotOpenAPISchema(),
            "openaiDashboard": usageOpenAIDashboardOpenAPISchema(),
            "openaiCreditsHistory": usageOpenAICreditsHistoryOpenAPISchema(),
            "error": usageCLIErrorOpenAPISchema(),
            "repairActions": usageOpenAPIArray(usageRepairActionOpenAPISchema()),
        ])
    }

    private static func usageSnapshotOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "sourceLabel": usageOpenAPIString(),
            "planName": usageOpenAPIString(),
            "accountLabel": usageOpenAPIString(),
            "updatedAt": usageOpenAPIString(format: "date-time"),
            "windows": usageOpenAPIArray(usageWindowOpenAPISchema()),
            "providerCost": usageProviderCostOpenAPISchema(),
            "ampUsage": usageAmpUsageOpenAPISchema(),
            "claudeAdminAPIUsage": usageOpenAPIAnyObject(),
            "isEmpty": usageOpenAPIBoolean(),
        ], additionalProperties: true)
    }

    private static func usageWindowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "title": usageOpenAPIString(),
            "usedPercent": usageOpenAPINumber(),
            "remainingPercent": usageOpenAPINumber(),
            "windowMinutes": usageOpenAPIInteger(),
            "resetsAt": usageOpenAPIString(format: "date-time"),
            "resetDescription": usageOpenAPIString(),
            "pace": usagePaceOpenAPISchema(),
        ])
    }

    private static func usagePaceOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "stage": usageOpenAPIString(),
            "label": usageOpenAPIString(),
            "detail": usageOpenAPIString(),
            "expectedUsedPercent": usageOpenAPINumber(),
            "deltaPercent": usageOpenAPINumber(),
            "etaSeconds": usageOpenAPINumber(),
            "willLastToReset": usageOpenAPIBoolean(),
            "runOutProbability": usageOpenAPINumber(),
        ])
    }

    private static func usageProviderCostOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "used": usageOpenAPINumber(),
            "limit": usageOpenAPINumber(),
            "currencyCode": usageOpenAPIString(),
            "period": usageOpenAPIString(),
            "resetsAt": usageOpenAPIString(format: "date-time"),
            "usedPercent": usageOpenAPINumber(),
        ])
    }

    private static func usageAmpUsageOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "individualCredits": usageOpenAPINumber(),
            "workspaceBalances": usageOpenAPIArray(usageOpenAPIObject([
                "name": usageOpenAPIString(),
                "remaining": usageOpenAPINumber(),
            ])),
        ])
    }

    private static func usageOpenAIDashboardOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "signedInEmail": usageOpenAPIString(),
            "codeReviewRemainingPercent": usageOpenAPINumber(),
            "codeReviewLimit": usageRateWindowOpenAPISchema(),
            "creditEvents": usageOpenAPIArray(usageCreditEventOpenAPISchema()),
            "dailyBreakdown": usageOpenAPIArray(usageOpenAIDailyBreakdownOpenAPISchema()),
            "usageBreakdown": usageOpenAPIArray(usageOpenAIDailyBreakdownOpenAPISchema()),
            "creditsPurchaseURL": usageOpenAPIString(),
            "primaryLimit": usageRateWindowOpenAPISchema(),
            "secondaryLimit": usageRateWindowOpenAPISchema(),
            "extraRateWindows": usageOpenAPIArray(usageNamedRateWindowOpenAPISchema()),
            "creditsRemaining": usageOpenAPINumber(),
            "accountPlan": usageOpenAPIString(),
            "updatedAt": usageOpenAPIString(format: "date-time"),
        ], additionalProperties: true)
    }

    private static func usageRateWindowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "title": usageOpenAPIString(),
            "usedPercent": usageOpenAPINumber(),
            "windowMinutes": usageOpenAPIInteger(),
            "resetsAt": usageOpenAPIString(format: "date-time"),
            "resetDescription": usageOpenAPIString(),
        ])
    }

    private static func usageNamedRateWindowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "id": usageOpenAPIString(),
            "title": usageOpenAPIString(),
            "window": usageRateWindowOpenAPISchema(),
        ])
    }

    private static func usageCreditEventOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "id": usageOpenAPIString(),
            "date": usageOpenAPIString(format: "date-time"),
            "service": usageOpenAPIString(),
            "creditsUsed": usageOpenAPINumber(),
        ])
    }

    private static func usageOpenAIDailyBreakdownOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "day": usageOpenAPIString(format: "date"),
            "services": usageOpenAPIArray(usageOpenAIServiceUsageOpenAPISchema()),
            "totalCreditsUsed": usageOpenAPINumber(),
        ])
    }

    private static func usageOpenAIServiceUsageOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "service": usageOpenAPIString(),
            "creditsUsed": usageOpenAPINumber(),
        ])
    }

    private static func usageOpenAICreditsHistoryOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "accountEmail": usageOpenAPIString(),
            "updatedAt": usageOpenAPIString(format: "date-time"),
            "eventCount": usageOpenAPIInteger(),
            "recentEvents": usageOpenAPIArray(usageCreditEventOpenAPISchema()),
            "dailyBreakdown": usageOpenAPIArray(usageOpenAIDailyBreakdownOpenAPISchema()),
        ])
    }

    private static func usageCLIErrorOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "message": usageOpenAPIString(),
        ])
    }

    private static func usageErrorPayloadOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "error": usageOpenAPIString(),
        ])
    }

    private static func usageProviderStatusReportsOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageProviderStatusOpenAPISchema())
    }

    private static func usageProviderStatusOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "name": usageOpenAPIString(),
            "indicator": usageOpenAPIString(),
            "label": usageOpenAPIString(),
            "description": usageOpenAPIString(),
            "updatedAt": usageOpenAPIString(format: "date-time"),
            "statusPageURL": usageOpenAPIString(),
            "statusLinkURL": usageOpenAPIString(),
            "source": usageOpenAPIString(),
            "error": usageOpenAPIString(),
        ])
    }

    private static func usageRepairActionOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "id": usageOpenAPIString(),
            "kind": usageOpenAPIString(),
            "title": usageOpenAPIString(),
            "detail": usageOpenAPIString(),
            "command": usageOpenAPIString(),
            "url": usageOpenAPIString(),
        ])
    }

    private static func usageStorageReportsOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageStorageReportOpenAPISchema())
    }

    private static func usageStorageReportOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "displayName": usageOpenAPIString(),
            "scannedAt": usageOpenAPIString(format: "date-time"),
            "storage": usageDiagnosticStorageOpenAPISchema(),
        ])
    }

    private static func usageDiagnosticStorageOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "totalBytes": usageOpenAPIInteger(),
            "byteCountText": usageOpenAPIString(),
            "hasLocalData": usageOpenAPIBoolean(),
            "pathCount": usageOpenAPIInteger(),
            "missingPathCount": usageOpenAPIInteger(),
            "unreadablePathCount": usageOpenAPIInteger(),
            "componentCount": usageOpenAPIInteger(),
            "paths": usageOpenAPIArray(usageOpenAPIString()),
            "missingPaths": usageOpenAPIArray(usageOpenAPIString()),
            "unreadablePaths": usageOpenAPIArray(usageOpenAPIString()),
            "topComponents": usageOpenAPIArray(usageDiagnosticStorageComponentOpenAPISchema()),
            "cleanupRecommendations": usageOpenAPIArray(usageDiagnosticStorageRecommendationOpenAPISchema()),
            "updatedAt": usageOpenAPIString(format: "date-time"),
        ])
    }

    private static func usageDiagnosticStorageComponentOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "name": usageOpenAPIString(),
            "path": usageOpenAPIString(),
            "bytes": usageOpenAPIInteger(),
            "byteCountText": usageOpenAPIString(),
        ])
    }

    private static func usageDiagnosticStorageRecommendationOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "title": usageOpenAPIString(),
            "path": usageOpenAPIString(),
            "bytes": usageOpenAPIInteger(),
            "byteCountText": usageOpenAPIString(),
            "riskLevel": usageOpenAPIString(),
            "consequence": usageOpenAPIString(),
        ])
    }

    private static func usageDiagnosticsOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageDiagnosticOpenAPISchema())
    }

    private static func usageDiagnosticOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "schemaVersion": usageOpenAPIString(),
            "generatedAt": usageOpenAPIString(format: "date-time"),
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "displayName": usageOpenAPIString(),
            "source": usageOpenAPIString(),
            "sourceMode": usageOpenAPIString(),
            "configured": usageOpenAPIBoolean(),
            "auth": usageOpenAPIAnyObject(),
            "selectedAccount": usageOpenAPIAnyObject(),
            "settings": usageDiagnosticSettingsOpenAPISchema(),
            "usage": usageOpenAPIAnyObject(),
            "storage": usageDiagnosticStorageOpenAPISchema(),
            "fetchAttempts": usageOpenAPIArray(usageOpenAPIAnyObject()),
            "error": usageOpenAPIAnyObject(),
            "repairActions": usageOpenAPIArray(usageRepairActionOpenAPISchema()),
            "redaction": usageOpenAPIAnyObject(),
        ], additionalProperties: true)
    }

    private static func usageDiagnosticSettingsOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "configuredExplicitly": usageOpenAPIBoolean(),
            "enabled": usageOpenAPIBoolean(),
            "sourceModes": usageOpenAPIArray(usageOpenAPIString()),
            "sessionLabel": usageOpenAPIString(),
            "weeklyLabel": usageOpenAPIString(),
            "opusLabel": usageOpenAPIString(),
            "supportsOpus": usageOpenAPIBoolean(),
            "supportsCredits": usageOpenAPIBoolean(),
            "creditsHint": usageOpenAPIString(),
            "toggleTitle": usageOpenAPIString(),
            "cliName": usageOpenAPIString(),
            "isPrimaryProvider": usageOpenAPIBoolean(),
            "usesAccountFallback": usageOpenAPIBoolean(),
            "supportsAPIKey": usageOpenAPIBoolean(),
            "supportsTokenAccounts": usageOpenAPIBoolean(),
            "cliSessionPolicy": usageCLISessionPolicyOpenAPISchema(),
            "signInCommand": usageOpenAPIString(),
            "dashboardURL": usageOpenAPIString(),
            "subscriptionDashboardURL": usageOpenAPIString(),
            "changelogURL": usageOpenAPIString(),
            "environmentHints": usageEnvironmentHintsOpenAPISchema(),
            "sourceMode": usageOpenAPIString(),
            "cookieSource": usageOpenAPIString(),
            "hasAPIKey": usageOpenAPIBoolean(),
            "hasCookieHeader": usageOpenAPIBoolean(),
            "baseURLHost": usageOpenAPIString(),
            "projectIDPresent": usageOpenAPIBoolean(),
            "organizationIDPresent": usageOpenAPIBoolean(),
            "enabledFlags": usageOpenAPIArray(usageOpenAPIString()),
            "extraKeys": usageOpenAPIArray(usageOpenAPIString()),
            "tokenAccounts": usageOpenAPIAnyObject(),
        ], additionalProperties: true)
    }

    private static func usageCostOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "daysBack": usageOpenAPIInteger(),
            "generatedAt": usageOpenAPIString(format: "date-time"),
            "sourceInfo": usageCostSourceInfoOpenAPISchema(),
            "sessionsScanned": usageOpenAPIInteger(),
            "grand": usageTotalsOpenAPISchema(),
            "bySource": usageOpenAPIArray(usageCostSourceRowOpenAPISchema()),
            "byModel": usageOpenAPIArray(usageCostModelRowOpenAPISchema()),
            "byDay": usageOpenAPIArray(usageCostDayRowOpenAPISchema()),
            "byMonth": usageOpenAPIArray(usageCostMonthRowOpenAPISchema()),
            "bySession": usageOpenAPIArray(usageCostSessionRowOpenAPISchema()),
            "byProject": usageOpenAPIArray(usageCostProjectRowOpenAPISchema()),
        ])
    }

    private static func usageConfigProvidersOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageConfigProviderOpenAPISchema())
    }

    private static func usageConfigAccountsOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "displayName": usageOpenAPIString(),
            "enabled": usageOpenAPIBoolean(),
            "activeIndex": usageOpenAPIInteger(),
            "accounts": usageOpenAPIArray(usageConfigAccountOpenAPISchema()),
            "configPath": usageOpenAPIString(),
        ])
    }

    private static func usageConfigAccountMutationRequestOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "action": usageOpenAPIString(),
            "provider": usageOpenAPIString(description: "Provider ID or alias"),
            "token": usageOpenAPIString(),
            "apiKey": usageOpenAPIString(),
            "api-key": usageOpenAPIString(),
            "cookie": usageOpenAPIString(),
            "cookieHeader": usageOpenAPIString(),
            "cookie-header": usageOpenAPIString(),
            "session": usageOpenAPIString(),
            "label": usageOpenAPIString(),
            "organizationID": usageOpenAPIString(),
            "organizationId": usageOpenAPIString(),
            "organization": usageOpenAPIString(),
            "org": usageOpenAPIString(),
            "externalIdentifier": usageOpenAPIString(),
            "externalId": usageOpenAPIString(),
            "external-id": usageOpenAPIString(),
            "account": usageOpenAPIString(),
            "accountIndex": usageOpenAPIInteger(),
            "account-index": usageOpenAPIInteger(),
            "clearOrganizationID": usageOpenAPIBoolean(),
            "clearOrganizationId": usageOpenAPIBoolean(),
            "clearOrganization": usageOpenAPIBoolean(),
            "clear-organization": usageOpenAPIBoolean(),
            "clearOrg": usageOpenAPIBoolean(),
            "clear-org": usageOpenAPIBoolean(),
            "clearExternalIdentifier": usageOpenAPIBoolean(),
            "clearExternalId": usageOpenAPIBoolean(),
            "clearExternal": usageOpenAPIBoolean(),
            "clear-external-id": usageOpenAPIBoolean(),
            "select": usageOpenAPIBoolean(),
            "makeActive": usageOpenAPIBoolean(),
            "make-active": usageOpenAPIBoolean(),
            "noSelect": usageOpenAPIBoolean(),
            "no-select": usageOpenAPIBoolean(),
            "noEnable": usageOpenAPIBoolean(),
            "no-enable": usageOpenAPIBoolean(),
        ])
    }

    private static func usageConfigAccountMutationOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "displayName": usageOpenAPIString(),
            "action": usageOpenAPIString(),
            "enabled": usageOpenAPIBoolean(),
            "activeIndex": usageOpenAPIInteger(),
            "account": usageConfigAccountOpenAPISchema(),
            "accounts": usageOpenAPIArray(usageConfigAccountOpenAPISchema()),
            "configPath": usageOpenAPIString(),
        ])
    }

    private static func usageConfigAccountOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "index": usageOpenAPIInteger(),
            "id": usageOpenAPIString(format: "uuid"),
            "label": usageOpenAPIString(),
            "active": usageOpenAPIBoolean(),
            "organizationID": usageOpenAPIString(),
            "externalIdentifier": usageOpenAPIString(),
            "addedAt": usageOpenAPINumber(),
            "lastUsed": usageOpenAPINumber(),
            "hasToken": usageOpenAPIBoolean(),
        ])
    }

    private static func usageConfigProviderMutationRequestOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "action": usageOpenAPIString(),
            "provider": usageOpenAPIString(description: "Provider ID or alias"),
            "apiKey": usageOpenAPIString(),
            "api-key": usageOpenAPIString(),
            "token": usageOpenAPIString(),
            "cookie": usageOpenAPIString(),
            "cookieHeader": usageOpenAPIString(),
            "cookie-header": usageOpenAPIString(),
            "session": usageOpenAPIString(),
            "key": usageOpenAPIString(),
            "field": usageOpenAPIString(),
            "configKey": usageOpenAPIString(),
            "config-key": usageOpenAPIString(),
            "value": usageOpenAPIString(),
            "source": usageOpenAPIString(),
            "sourceMode": usageOpenAPIString(),
            "source-mode": usageOpenAPIString(),
            "baseURL": usageOpenAPIString(),
            "base-url": usageOpenAPIString(),
            "projectID": usageOpenAPIString(),
            "project": usageOpenAPIString(),
            "organizationID": usageOpenAPIString(),
            "organization": usageOpenAPIString(),
            "org": usageOpenAPIString(),
            "cookieSource": usageOpenAPIString(),
            "cookie-source": usageOpenAPIString(),
            "noEnable": usageOpenAPIBoolean(),
            "no-enable": usageOpenAPIBoolean(),
        ])
    }

    private static func usageConfigOrderMutationRequestOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "providers": usageOpenAPIStringOrStringArray(
                description: "Provider IDs/aliases as an array or comma-separated string"),
            "providerOrder": usageOpenAPIStringOrStringArray(
                description: "Provider IDs/aliases as an array or comma-separated string"),
            "provider-order": usageOpenAPIStringOrStringArray(
                description: "Provider IDs/aliases as an array or comma-separated string"),
        ])
    }

    private static func usageConfigProviderMutationOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "action": usageOpenAPIString(),
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "displayName": usageOpenAPIString(),
            "enabled": usageOpenAPIBoolean(),
            "cookieSource": usageOpenAPIString(),
            "key": usageOpenAPIString(),
            "present": usageOpenAPIBoolean(),
            "providerOrder": usageOpenAPIArray(usageOpenAPIString()),
            "configPath": usageOpenAPIString(),
        ])
    }

    private static func usageCacheClearRequestOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "cookies": usageOpenAPIBoolean(),
            "cost": usageOpenAPIBoolean(),
            "all": usageOpenAPIBoolean(),
            "provider": usageOpenAPIString(description: "Provider ID or alias"),
        ])
    }

    private static func usageCacheClearResultsOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageCacheClearResultOpenAPISchema())
    }

    private static func usageCacheClearResultOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "cache": usageOpenAPIString(),
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "cleared": usageOpenAPIInteger(),
            "error": usageOpenAPIString(),
        ])
    }

    private static func usageConfigValidationIssuesOpenAPISchema() -> JSONValue {
        usageOpenAPIArray(usageConfigValidationIssueOpenAPISchema())
    }

    private static func usageConfigValidationIssueOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "severity": usageOpenAPIString(),
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "field": usageOpenAPIString(),
            "code": usageOpenAPIString(),
            "message": usageOpenAPIString(),
        ])
    }

    private static func usageConfigProviderOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "order": usageOpenAPIInteger(),
            "provider": usageOpenAPIString(description: "Canonical provider ID"),
            "displayName": usageOpenAPIString(),
            "enabled": usageOpenAPIBoolean(),
            "defaultEnabled": usageOpenAPIBoolean(),
            "configuredExplicitly": usageOpenAPIBoolean(),
            "sourceModes": usageOpenAPIArray(usageOpenAPIString()),
            "sessionLabel": usageOpenAPIString(),
            "weeklyLabel": usageOpenAPIString(),
            "opusLabel": usageOpenAPIString(),
            "supportsOpus": usageOpenAPIBoolean(),
            "supportsCredits": usageOpenAPIBoolean(),
            "creditsHint": usageOpenAPIString(),
            "toggleTitle": usageOpenAPIString(),
            "cliName": usageOpenAPIString(),
            "isPrimaryProvider": usageOpenAPIBoolean(),
            "usesAccountFallback": usageOpenAPIBoolean(),
            "supportsAPIKey": usageOpenAPIBoolean(),
            "supportsTokenAccounts": usageOpenAPIBoolean(),
            "cliSessionPolicy": usageCLISessionPolicyOpenAPISchema(),
            "signInCommand": usageOpenAPIString(),
            "dashboardURL": usageOpenAPIString(),
            "subscriptionDashboardURL": usageOpenAPIString(),
            "changelogURL": usageOpenAPIString(),
            "environmentHints": usageEnvironmentHintsOpenAPISchema(),
            "statusPageURL": usageOpenAPIString(),
            "statusLinkURL": usageOpenAPIString(),
            "googleWorkspaceStatusProductID": usageOpenAPIString(),
        ])
    }

    private static func usageCLISessionPolicyOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "kind": usageOpenAPIString(),
            "persistsAcrossRequests": usageOpenAPIBoolean(),
            "idleWindowSeconds": usageOpenAPINumber(),
        ])
    }

    private static func usageEnvironmentHintsOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "apiKey": usageOpenAPIArray(usageOpenAPIString()),
            "cookieHeader": usageOpenAPIArray(usageOpenAPIString()),
            "baseURL": usageOpenAPIArray(usageOpenAPIString()),
            "project": usageOpenAPIArray(usageOpenAPIString()),
            "organization": usageOpenAPIArray(usageOpenAPIString()),
            "sourceMode": usageOpenAPIArray(usageOpenAPIString()),
            "cookieSource": usageOpenAPIArray(usageOpenAPIString()),
            "extra": usageOpenAPIStringArrayMap(),
        ])
    }

    private static func usageCostSourceInfoOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "source": usageOpenAPIString(),
            "loadedAt": usageOpenAPIString(format: "date-time"),
            "cacheAgeSeconds": usageOpenAPINumber(),
            "cachePath": usageOpenAPIString(),
            "reason": usageOpenAPIString(),
        ])
    }

    private static func usageTotalsOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "inputTokens": usageOpenAPIInteger(),
            "outputTokens": usageOpenAPIInteger(),
            "cacheCreationTokens": usageOpenAPIInteger(),
            "cacheReadTokens": usageOpenAPIInteger(),
            "costUSD": usageOpenAPINumber(),
            "requestCount": usageOpenAPIInteger(),
        ])
    }

    private static func usageCostSourceRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "source": usageOpenAPIString(),
            "name": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
            "sessions": usageOpenAPIInteger(),
        ])
    }

    private static func usageCostSourceTotalsRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "source": usageOpenAPIString(),
            "name": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
        ])
    }

    private static func usageCostModelRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "source": usageOpenAPIString(),
            "name": usageOpenAPIString(),
            "model": usageOpenAPIString(),
            "displayLabel": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
        ])
    }

    private static func usageCostDayRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "day": usageOpenAPIString(format: "date"),
            "totals": usageTotalsOpenAPISchema(),
            "bySource": usageOpenAPIArray(usageCostSourceTotalsRowOpenAPISchema()),
            "modelBreakdowns": usageOpenAPIArray(usageCostModelBreakdownOpenAPISchema()),
        ])
    }

    private static func usageCostMonthRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "month": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
            "bySource": usageOpenAPIArray(usageCostSourceTotalsRowOpenAPISchema()),
        ])
    }

    private static func usageCostSessionRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "session": usageOpenAPIString(),
            "source": usageOpenAPIString(),
            "name": usageOpenAPIString(),
            "project": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
            "lastActivity": usageOpenAPIString(format: "date-time"),
            "models": usageOpenAPIArray(usageOpenAPIString()),
        ])
    }

    private static func usageCostModelBreakdownOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "source": usageOpenAPIString(),
            "name": usageOpenAPIString(),
            "model": usageOpenAPIString(),
            "displayLabel": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
            "costUSD": usageOpenAPINumber(),
            "totalTokens": usageOpenAPIInteger(),
            "standardCostUSD": usageOpenAPINumber(),
            "priorityCostUSD": usageOpenAPINumber(),
            "standardTokens": usageOpenAPIInteger(),
            "priorityTokens": usageOpenAPIInteger(),
        ])
    }

    private static func usageCostProjectRowOpenAPISchema() -> JSONValue {
        usageOpenAPIObject([
            "path": usageOpenAPIString(),
            "totals": usageTotalsOpenAPISchema(),
            "bySource": usageOpenAPIArray(usageCostSourceTotalsRowOpenAPISchema()),
        ])
    }

    private static func usageOpenAPIObject(
        _ properties: [String: JSONValue],
        additionalProperties: Bool = false
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(additionalProperties),
            "properties": .object(properties),
        ])
    }

    private static func usageOpenAPIAnyObject() -> JSONValue {
        usageOpenAPIObject([:], additionalProperties: true)
    }

    private static func usageOpenAPIStringArrayMap() -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": usageOpenAPIArray(usageOpenAPIString()),
        ])
    }

    private static func usageOpenAPIArray(_ item: JSONValue) -> JSONValue {
        .object([
            "type": .string("array"),
            "items": item,
        ])
    }

    private static func usageOpenAPIStringOrStringArray(description: String) -> JSONValue {
        .object([
            "description": .string(description),
            "oneOf": .array([
                usageOpenAPIArray(usageOpenAPIString()),
                usageOpenAPIString(),
            ]),
        ])
    }

    private static func usageOpenAPIString(format: String? = nil, description: String? = nil) -> JSONValue {
        var schema: [String: JSONValue] = ["type": .string("string")]
        if let format {
            schema["format"] = .string(format)
        }
        if let description {
            schema["description"] = .string(description)
        }
        return .object(schema)
    }

    private static func usageOpenAPIInteger() -> JSONValue {
        .object(["type": .string("integer")])
    }

    private static func usageOpenAPINumber() -> JSONValue {
        .object(["type": .string("number")])
    }

    private static func usageOpenAPIBoolean() -> JSONValue {
        .object(["type": .string("boolean")])
    }

    private static func usageOpenAPIQuery(
        _ name: String,
        type: String,
        description: String)
        -> JSONValue
    {
        .object([
            "name": .string(name),
            "in": .string("query"),
            "required": .bool(false),
            "description": .string(description),
            "schema": .object(["type": .string(type)]),
        ])
    }

    private static func writeJSON<T: Encodable>(fd: Int32, status: String, payload: T) throws {
        try writeResponse(fd: fd, response: jsonHTTPResponse(payload: payload, status: status))
    }

    private static func writeResponse(fd: Int32, response: UsageHTTPResponse) throws {
        try writeHTTP(fd: fd, status: response.status, contentType: response.contentType, body: response.body)
    }

    private static func jsonHTTPResponse<T: Encodable>(
        payload: T,
        status: String = "200 OK",
        usageCacheKeys: [String?]? = nil
    ) -> UsageHTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            return UsageHTTPResponse(
                status: status,
                body: try encoder.encode(payload),
                usageCacheKeys: usageCacheKeys)
        } catch {
            return errorHTTPResponse(
                status: "500 Internal Server Error",
                message: "Could not encode JSON response: \(error)")
        }
    }

    private static func errorHTTPResponse(status: String, message: String) -> UsageHTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(ErrorPayload(error: message)) {
            return UsageHTTPResponse(status: status, body: data)
        }
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return UsageHTTPResponse(status: status, body: Data("{\"error\":\"\(escaped)\"}".utf8))
    }

    private static func writeHTTP(
        fd: Int32,
        status: String,
        contentType: String = "application/json",
        body: Data
    ) throws {
        let header = [
            "HTTP/1.1 \(status)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Private-Network: true",
            "",
            "",
        ].joined(separator: "\r\n")
        try writeAll(Data(header.utf8) + body, fd: fd)
    }

    private static func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                guard written > 0 else { throw CLIError("write() failed: \(errnoText())") }
                pointer += written
                remaining -= written
            }
        }
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }

    private static func ignoreSIGPIPE() {
        _ = Darwin.signal(SIGPIPE, SIG_IGN)
    }

    private static func cachedServeResponse(
        key: String,
        cache: UsageHTTPResponseCache,
        refreshInterval: TimeInterval,
        requestTimeout: TimeInterval,
        makeResponse: @escaping @Sendable () async -> UsageHTTPResponse
    ) async -> UsageHTTPResponse {
        switch await cache.responseOrStartFetch(for: key, now: Date()) {
        case let .response(response):
            return response
        case .miss:
            let response = await responseWithDeadline(seconds: requestTimeout, makeResponse: makeResponse)
            return await cache.completeFetch(
                response,
                for: key,
                policy: UsageHTTPResponseCache.CachePolicy(
                    ttl: refreshInterval,
                    staleTTL: serveStaleTTL(refreshInterval: refreshInterval)),
                now: Date(),
                shouldCache: shouldCacheServeResponse(response))
        }
    }

    private static func responseWithDeadline(
        seconds timeout: TimeInterval,
        makeResponse: @escaping @Sendable () async -> UsageHTTPResponse
    ) async -> UsageHTTPResponse {
        let clampedTimeout = min(max(timeout, 0), 86_400)
        guard clampedTimeout > 0 else {
            return await makeResponse()
        }
        let nanoseconds = max(1, UInt64((clampedTimeout * 1_000_000_000).rounded(.up)))
        return await withCheckedContinuation { continuation in
            let state = UsageHTTPDeadlineState(continuation: continuation)
            let workTask = Task {
                let response = await makeResponse()
                state.finish(response, cancelWork: false, cancelTimeout: true)
            }
            state.setWorkTask(workTask)

            let timeoutTask = Task {
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    return
                }
                state.finish(
                    errorHTTPResponse(status: "504 Gateway Timeout", message: "request timed out"),
                    cancelWork: true,
                    cancelTimeout: false)
            }
            state.setTimeoutTask(timeoutTask)
        }
    }

    private static func serveStaleTTL(refreshInterval: TimeInterval) -> TimeInterval {
        guard refreshInterval > 0 else { return 0 }
        guard refreshInterval.isFinite else { return UsageHTTPResponseCache.maximumStaleTTL }
        return min(max(refreshInterval * 10, 300), UsageHTTPResponseCache.maximumStaleTTL)
    }

    private static func shouldCacheServeResponse(_ response: UsageHTTPResponse) -> Bool {
        guard response.isOK else { return false }
        guard let payload = try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]] else {
            return true
        }
        return !payload.contains { item in
            guard let error = item["error"] else { return false }
            return !(error is NSNull)
        }
    }

    private static func serveCacheKey(
        kind: String,
        query: [String: String],
        config: AppConfig
    ) throws -> String {
        let payload = ServeCacheKeyPayload(
            kind: kind,
            query: query,
            configToken: try serveConfigCacheToken(for: config))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return "\(kind):\(sha256Hex(try encoder.encode(payload)))"
    }

    private static func serveConfigCacheToken(for config: AppConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256Hex(try encoder.encode(config.validated()))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))s"
        }
        return String(format: "%.2fs", seconds)
    }

    private struct ErrorPayload: Encodable {
        let error: String
    }

    private struct HealthPayload: Encodable {
        let status: String
        let service: String
    }

    private struct ConfigAccountMutationRequest: Decodable {
        let action: String
        let provider: String
        let token: String?
        let label: String?
        let organizationID: String?
        let externalIdentifier: String?
        let account: String?
        let accountIndex: Int?
        let clearOrganizationID: Bool
        let clearExternalIdentifier: Bool
        let select: Bool
        let noSelect: Bool
        let noEnable: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            guard let action = try Self.firstString(container, ["action"]) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing action"))
            }
            guard let provider = try Self.firstString(container, ["provider"]) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing provider"))
            }
            self.action = action
            self.provider = provider
            token = try Self.firstString(container, ["token", "apiKey", "api-key", "cookie", "cookieHeader", "cookie-header", "session"])
            label = try Self.firstString(container, ["label"])
            organizationID = try Self.firstString(container, ["organizationID", "organizationId", "organization", "org"])
            externalIdentifier = try Self.firstString(container, ["externalIdentifier", "externalId", "external-id"])
            account = try Self.firstString(container, ["account"])
            accountIndex = try Self.firstInt(container, ["accountIndex", "account-index"])
            clearOrganizationID = (try Self.firstBool(container, ["clearOrganizationID", "clearOrganizationId", "clearOrganization", "clear-organization", "clearOrg", "clear-org"])) ?? false
            clearExternalIdentifier = (try Self.firstBool(container, ["clearExternalIdentifier", "clearExternalId", "clearExternal", "clear-external-id"])) ?? false
            select = (try Self.firstBool(container, ["select", "makeActive", "make-active"])) ?? false
            noSelect = (try Self.firstBool(container, ["noSelect", "no-select"])) ?? false
            noEnable = (try Self.firstBool(container, ["noEnable", "no-enable"])) ?? false
        }

        func positiveAccountIndex() throws -> Int? {
            guard let accountIndex else { return nil }
            guard accountIndex > 0 else {
                throw CLIError("account-index must be a positive integer")
            }
            return accountIndex
        }

        private static func firstString(
            _ container: KeyedDecodingContainer<DynamicCodingKey>,
            _ keys: [String]
        ) throws -> String? {
            for key in keys {
                let codingKey = DynamicCodingKey(stringValue: key)
                if let value = try container.decodeIfPresent(String.self, forKey: codingKey) {
                    return value
                }
            }
            return nil
        }

        private static func firstInt(
            _ container: KeyedDecodingContainer<DynamicCodingKey>,
            _ keys: [String]
        ) throws -> Int? {
            for key in keys {
                let codingKey = DynamicCodingKey(stringValue: key)
                if let value = try container.decodeIfPresent(Int.self, forKey: codingKey) {
                    return value
                }
            }
            return nil
        }

        private static func firstBool(
            _ container: KeyedDecodingContainer<DynamicCodingKey>,
            _ keys: [String]
        ) throws -> Bool? {
            for key in keys {
                let codingKey = DynamicCodingKey(stringValue: key)
                if let value = try container.decodeIfPresent(Bool.self, forKey: codingKey) {
                    return value
                }
            }
            return nil
        }
    }

    private struct ConfigProviderMutationRequest: Decodable {
        let action: String
        let provider: String
        let apiKey: String?
        let cookie: String?
        let key: String?
        let value: String?
        let noEnable: Bool

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            func string(_ keys: [String]) throws -> String? {
                for key in keys {
                    if let value = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: key)) {
                        return value
                    }
                }
                return nil
            }
            func bool(_ keys: [String]) throws -> Bool? {
                for key in keys {
                    if let value = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey(stringValue: key)) {
                        return value
                    }
                }
                return nil
            }
            guard let action = try string(["action"]) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing action"))
            }
            guard let provider = try string(["provider"]) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing provider"))
            }
            self.action = action
            self.provider = provider
            apiKey = try string(["apiKey", "api-key", "key", "token"])
            cookie = try string(["cookie", "cookieHeader", "cookie-header", "session"])
            let explicitField = try string(["field", "configKey", "config-key"])
            let keyAsField = try string(["key"]).flatMap { candidate in
                ["set", "set-field", "unset", "unset-field", "clear-field"].contains(action.lowercased())
                    ? candidate
                    : nil
            }
            key = explicitField ?? keyAsField
            value = try string(["value", "source", "sourceMode", "source-mode", "baseURL", "base-url", "projectID", "project", "organizationID", "organization", "org", "cookieSource", "cookie-source"])
            noEnable = (try bool(["noEnable", "no-enable"])) ?? false
        }
    }

    private struct ConfigOrderMutationRequest: Decodable {
        let providers: [String]

        var providerSelection: String {
            providers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            for key in ["providers", "providerOrder", "provider-order"] {
                let codingKey = DynamicCodingKey(stringValue: key)
                if let list = try? container.decode([String].self, forKey: codingKey) {
                    providers = list
                    return
                }
                if let raw = try? container.decode(String.self, forKey: codingKey) {
                    providers = raw
                        .split(separator: ",")
                        .map(String.init)
                    return
                }
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Missing providers"))
        }
    }

    private struct ConfigProviderMutationResponse: Encodable {
        let action: String
        let provider: String?
        let displayName: String?
        let enabled: Bool?
        let cookieSource: String?
        let key: String?
        let present: Bool?
        let providerOrder: [String]?
        let configPath: String
    }

    private struct CacheClearRequest: Decodable {
        let cookies: Bool
        let cost: Bool
        let all: Bool
        let provider: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            func bool(_ keys: [String]) throws -> Bool? {
                for key in keys {
                    if let value = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey(stringValue: key)) {
                        return value
                    }
                }
                return nil
            }
            func string(_ keys: [String]) throws -> String? {
                for key in keys {
                    if let value = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: key)) {
                        return value
                    }
                }
                return nil
            }
            cookies = (try bool(["cookies"])) ?? false
            cost = (try bool(["cost"])) ?? false
            all = (try bool(["all"])) ?? false
            provider = try string(["provider"])
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    private struct ServeCacheKeyPayload: Encodable {
        let kind: String
        let query: [String: String]
        let configToken: String
    }
}

private struct UsageHTTPResponse: Sendable {
    let status: String
    let contentType: String
    let body: Data
    let usageCacheKeys: [String?]?

    init(
        status: String,
        contentType: String = "application/json",
        body: Data,
        usageCacheKeys: [String?]? = nil
    ) {
        self.status = status
        self.contentType = contentType
        self.body = body
        self.usageCacheKeys = usageCacheKeys
    }

    var isOK: Bool {
        status == "200 OK"
    }
}

private enum UsageHTTPCacheLookup: Sendable {
    case response(UsageHTTPResponse)
    case miss
}

private final class UsageHTTPServerTerminationSignalMonitor: @unchecked Sendable {
    private static let signalNumbers = [SIGINT, SIGTERM, SIGHUP]

    private let lock = NSLock()
    private let sources: [DispatchSourceSignal]
    private var isCancelled = false

    init() {
        sources = Self.signalNumbers.map { signalNumber in
            Self.installCaptureHandler(for: signalNumber)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global(qos: .utility))
            source.setEventHandler {
                TTYCommandRunner.terminateActiveProcessesForAppShutdown()
                Self.restoreDefaultHandler(for: signalNumber)
                _ = kill(getpid(), signalNumber)
            }
            source.resume()
            return source
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()

        for source in sources {
            source.cancel()
        }
        for signalNumber in Self.signalNumbers {
            Self.restoreDefaultHandler(for: signalNumber)
        }
    }

    deinit {
        cancel()
    }

    private static func installCaptureHandler(for signalNumber: Int32) {
        _ = Darwin.signal(signalNumber, handleUsageHTTPServerTerminationSignal)
    }

    private static func restoreDefaultHandler(for signalNumber: Int32) {
        _ = Darwin.signal(signalNumber, SIG_DFL)
    }
}

private final class UsageHTTPDeadlineState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UsageHTTPResponse, Never>?
    private var workTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<UsageHTTPResponse, Never>) {
        self.continuation = continuation
    }

    func setWorkTask(_ task: Task<Void, Never>) {
        var shouldCancel = false
        lock.lock()
        if continuation == nil {
            shouldCancel = true
        } else {
            workTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        var shouldCancel = false
        lock.lock()
        if continuation == nil {
            shouldCancel = true
        } else {
            timeoutTask = task
        }
        lock.unlock()

        if shouldCancel {
            task.cancel()
        }
    }

    func finish(_ response: UsageHTTPResponse, cancelWork: Bool, cancelTimeout: Bool) {
        let continuation: CheckedContinuation<UsageHTTPResponse, Never>?
        let workTask: Task<Void, Never>?
        let timeoutTask: Task<Void, Never>?

        lock.lock()
        continuation = self.continuation
        self.continuation = nil
        workTask = cancelWork ? self.workTask : nil
        timeoutTask = cancelTimeout ? self.timeoutTask : nil
        self.workTask = nil
        self.timeoutTask = nil
        lock.unlock()

        workTask?.cancel()
        timeoutTask?.cancel()
        continuation?.resume(returning: response)
    }
}

private actor UsageHTTPAsyncGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        await wait()
        let result = await operation()
        release()
        return result
    }

    private func wait() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private actor UsageHTTPResponseCache {
    static let maximumStaleTTL: TimeInterval = 3_600

    struct CachePolicy: Sendable {
        let ttl: TimeInterval
        let staleTTL: TimeInterval
    }

    private struct Entry: Sendable {
        let expiresAt: Date
        let response: UsageHTTPResponse
    }

    private struct LastGoodEntry: Sendable {
        let recordedAt: Date
        let response: UsageHTTPResponse
    }

    private struct UsageItemKey: Hashable, Sendable {
        let provider: String
        let accountID: String
    }

    private struct LastGoodUsageItem: Sendable {
        let recordedAt: Date
        let data: Data
    }

    private var entries: [String: Entry] = [:]
    private var lastGood: [String: LastGoodEntry] = [:]
    private var lastGoodUsageItems: [String: [UsageItemKey: LastGoodUsageItem]] = [:]
    private var inFlightKeys: Set<String> = []
    private var waiters: [String: [CheckedContinuation<UsageHTTPCacheLookup, Never>]] = [:]

    func responseOrStartFetch(for key: String, now: Date) async -> UsageHTTPCacheLookup {
        pruneExpiredEntries(now: now)
        if let response = response(for: key) {
            return .response(response)
        }

        if inFlightKeys.contains(key) {
            return await withCheckedContinuation { continuation in
                waiters[key, default: []].append(continuation)
            }
        }

        inFlightKeys.insert(key)
        return .miss
    }

    func completeFetch(
        _ response: UsageHTTPResponse,
        for key: String,
        policy: CachePolicy,
        now: Date,
        shouldCache: Bool
    ) -> UsageHTTPResponse {
        let delivered: UsageHTTPResponse
        let staleResponse = staleResponse(for: key, staleTTL: policy.staleTTL, now: now)
        let usageMerge = mergeLastGoodUsageItems(
            into: response,
            for: key,
            staleTTL: policy.staleTTL,
            now: now,
            replaceCachedItems: shouldCache)

        if shouldCache {
            store(response, for: key, ttl: policy.ttl, now: now)
            if key.hasPrefix("usage:") {
                lastGood[key] = nil
            } else {
                lastGood[key] = LastGoodEntry(recordedAt: now, response: response)
            }
            delivered = response
        } else if let usageMerge {
            delivered = usageMerge
            lastGood[key] = nil
        } else {
            delivered = staleResponse ?? response
        }

        inFlightKeys.remove(key)
        let continuations = waiters.removeValue(forKey: key) ?? []
        for continuation in continuations {
            continuation.resume(returning: .response(delivered))
        }
        return delivered
    }

    private func pruneExpiredEntries(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
        lastGood = lastGood.filter {
            now.timeIntervalSince($0.value.recordedAt) <= Self.maximumStaleTTL
        }
        lastGoodUsageItems = lastGoodUsageItems.compactMapValues { items in
            let retained = items.filter {
                now.timeIntervalSince($0.value.recordedAt) <= Self.maximumStaleTTL
            }
            return retained.isEmpty ? nil : retained
        }
    }

    private func response(for key: String) -> UsageHTTPResponse? {
        entries[key]?.response
    }

    private func staleResponse(
        for key: String,
        staleTTL: TimeInterval,
        now: Date
    ) -> UsageHTTPResponse? {
        guard staleTTL > 0 else { return nil }
        if key.hasPrefix("usage:") {
            return nil
        }
        if let entry = lastGood[key],
           now.timeIntervalSince(entry.recordedAt) <= staleTTL
        {
            return entry.response
        }
        if lastGood[key] != nil {
            lastGood[key] = nil
        }
        return nil
    }

    private func mergeLastGoodUsageItems(
        into response: UsageHTTPResponse,
        for key: String,
        staleTTL: TimeInterval,
        now: Date,
        replaceCachedItems: Bool
    ) -> UsageHTTPResponse? {
        guard key.hasPrefix("usage:"),
              response.isOK,
              staleTTL > 0,
              var items = try? JSONSerialization.jsonObject(with: response.body) as? [[String: Any]]
        else {
            return nil
        }

        var cachedItems = replaceCachedItems ? [:] : lastGoodUsageItems[key] ?? [:]
        if !replaceCachedItems {
            cachedItems = cachedItems.filter { now.timeIntervalSince($0.value.recordedAt) <= staleTTL }
        }
        let itemKeys = items.indices.compactMap { index in
            Self.usageItemKey(
                items[index],
                accountID: Self.cacheAccountKey(at: index, in: response.usageCacheKeys))
        }
        let duplicateKeys = Set(
            Dictionary(grouping: itemKeys, by: { $0 })
                .filter { $0.value.count > 1 }
                .map(\.key))
        for duplicateKey in duplicateKeys {
            cachedItems[duplicateKey] = nil
        }

        var replacedError = false
        for index in items.indices {
            let item = items[index]
            guard let itemKey = Self.usageItemKey(
                item,
                accountID: Self.cacheAccountKey(at: index, in: response.usageCacheKeys)),
                !duplicateKeys.contains(itemKey)
            else {
                continue
            }

            if Self.hasError(item) {
                if let cached = cachedItems[itemKey],
                   let cachedItem = try? JSONSerialization.jsonObject(with: cached.data) as? [String: Any]
                {
                    items[index] = cachedItem
                    replacedError = true
                }
            } else if let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]) {
                cachedItems[itemKey] = LastGoodUsageItem(recordedAt: now, data: data)
            }
        }
        lastGoodUsageItems[key] = cachedItems

        guard replacedError,
              let body = try? JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        else {
            return response
        }
        return UsageHTTPResponse(
            status: response.status,
            contentType: response.contentType,
            body: body,
            usageCacheKeys: response.usageCacheKeys)
    }

    private func store(_ response: UsageHTTPResponse, for key: String, ttl: TimeInterval, now: Date) {
        guard ttl > 0, response.isOK else { return }
        entries[key] = Entry(expiresAt: now.addingTimeInterval(ttl), response: response)
    }

    private static func usageItemKey(_ item: [String: Any], accountID: String?) -> UsageItemKey? {
        guard let provider = item["provider"] as? String,
              !provider.isEmpty,
              let accountID,
              !accountID.isEmpty
        else {
            return nil
        }
        return UsageItemKey(provider: provider, accountID: accountID)
    }

    private static func cacheAccountKey(at index: Int, in keys: [String?]?) -> String? {
        guard let keys, keys.indices.contains(index) else { return nil }
        return keys[index]
    }

    private static func hasError(_ item: [String: Any]) -> Bool {
        guard let error = item["error"] else { return false }
        return !(error is NSNull)
    }
}

private struct HTTPRequest {
    private static let readTimeoutMilliseconds: Int32 = 5_000
    private static let usageServerHeaderLimitBytes = 16_384

    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var hostHeaders: [String]
    var body: Data

    var isWebSocket: Bool {
        headers["upgrade"]?.lowercased() == "websocket"
    }

    func queryInt(_ key: String) -> Int? {
        query[key].flatMap(Int.init)
    }

    func queryDouble(_ key: String) -> Double? {
        query[key].flatMap(Double.init)
    }

    static func readUsageServerRequest(from fd: Int32) throws -> HTTPRequest {
        try read(
            from: fd,
            maxHeaderBytes: usageServerHeaderLimitBytes,
            readBody: false,
            strictHeaders: true)
    }

    static func read(
        from fd: Int32,
        maxHeaderBytes: Int = 1_048_576,
        readBody: Bool = true,
        strictHeaders: Bool = false
    ) throws -> HTTPRequest {
        var data = Data()
        var scratch = [UInt8](repeating: 0, count: 4096)
        while !data.containsHeaderTerminator {
            guard waitForReadable(fd, timeoutMilliseconds: readTimeoutMilliseconds) else {
                throw CLIError("HTTP request timed out")
            }
            let count = Darwin.read(fd, &scratch, scratch.count)
            if count == -1, errno == EINTR {
                continue
            }
            guard count > 0 else { throw CLIError("connection closed") }
            data.append(contentsOf: scratch[0..<count])
            guard data.count < maxHeaderBytes || data.containsHeaderTerminator else {
                throw CLIError("HTTP header too large")
            }
        }
        guard let split = data.headerTerminatorRange else {
            throw CLIError("Invalid HTTP request")
        }
        let headerData = data.subdata(in: data.startIndex..<split.lowerBound)
        var body = data.subdata(in: split.upperBound..<data.endIndex)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw CLIError("HTTP request is not UTF-8")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ").map(String.init) ?? []
        guard requestLine.count >= 2 else { throw CLIError("Invalid HTTP request line") }
        let (path, query) = parseTarget(requestLine[1])
        var headers: [String: String] = [:]
        var hostHeaders: [String] = []
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                if strictHeaders { throw CLIError("Invalid HTTP request") }
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if strictHeaders, key.isEmpty {
                throw CLIError("Invalid HTTP request")
            }
            if key == "host" {
                hostHeaders.append(value)
            }
            headers[key] = value
        }
        let contentLength: Int
        switch PayloadLimit.validateContentLength(headers["content-length"]) {
        case .success(let value):
            contentLength = value
        case .failure(.invalidContentLength(let raw)):
            throw CLIError("Invalid Content-Length: \(raw)", httpStatus: "400 Bad Request")
        case .failure(.tooLarge):
            throw CLIError("Payload too large", httpStatus: "413 Payload Too Large")
        }
        guard readBody else {
            return HTTPRequest(
                method: requestLine[0],
                path: path,
                query: query,
                headers: headers,
                hostHeaders: hostHeaders,
                body: body)
        }
        while body.count < contentLength {
            guard waitForReadable(fd, timeoutMilliseconds: readTimeoutMilliseconds) else {
                throw CLIError("HTTP request timed out")
            }
            let count = Darwin.read(fd, &scratch, min(scratch.count, contentLength - body.count))
            if count == -1, errno == EINTR {
                continue
            }
            guard count > 0 else { throw CLIError("connection closed") }
            body.append(contentsOf: scratch[0..<count])
        }
        if body.count > contentLength {
            body = body.subdata(in: 0..<contentLength)
        }
        guard body.count <= PayloadLimit.maxBytes else {
            throw CLIError("Payload too large", httpStatus: "413 Payload Too Large")
        }
        return HTTPRequest(
            method: requestLine[0],
            path: path,
            query: query,
            headers: headers,
            hostHeaders: hostHeaders,
            body: body)
    }

    func completeBody(from fd: Int32, maxBytes: Int) throws -> Data {
        let contentLength = try expectedBodyLength(maxBytes: maxBytes)
        if body.count >= contentLength {
            return body.prefix(contentLength)
        }
        var fullBody = body
        var scratch = [UInt8](repeating: 0, count: 4096)
        while fullBody.count < contentLength {
            guard Self.waitForReadable(fd, timeoutMilliseconds: Self.readTimeoutMilliseconds) else {
                throw CLIError("HTTP request timed out")
            }
            let count = Darwin.read(fd, &scratch, min(scratch.count, contentLength - fullBody.count))
            if count == -1, errno == EINTR {
                continue
            }
            guard count > 0 else { throw CLIError("connection closed") }
            fullBody.append(contentsOf: scratch[0..<count])
        }
        return fullBody
    }

    private func expectedBodyLength(maxBytes: Int) throws -> Int {
        guard let raw = headers["content-length"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return 0
        }
        guard let length = Int(raw), length >= 0 else {
            throw CLIError("Invalid Content-Length")
        }
        guard length <= maxBytes else {
            throw CLIError("HTTP body too large")
        }
        return length
    }

    enum HostValidationError {
        case missing
        case duplicate
        case invalid
        case disallowed
    }

    static func loopbackHostValidationError(_ hosts: [String]) -> HostValidationError? {
        guard let host = hosts.first else { return .missing }
        guard hosts.count == 1 else { return .duplicate }
        return isAllowedLoopbackHost(host) ? nil : .disallowed
    }

    private static func isAllowedLoopbackHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(",") else { return false }

        let hostWithoutPort: String
        if trimmed.hasPrefix("[") {
            guard let closingBracket = trimmed.firstIndex(of: "]") else { return false }
            hostWithoutPort = String(trimmed[...closingBracket])
            let remainder = trimmed[trimmed.index(after: closingBracket)...]
            guard remainder.isEmpty || isValidPortSuffix(String(remainder)) else { return false }
        } else {
            let segments = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            switch segments.count {
            case 1:
                hostWithoutPort = String(segments[0])
            case 2:
                guard isValidPort(String(segments[1])) else { return false }
                hostWithoutPort = String(segments[0])
            default:
                return false
            }
        }

        switch hostWithoutPort.lowercased() {
        case "127.0.0.1", "localhost", "localhost.", "[::1]":
            return true
        default:
            return false
        }
    }

    private static func isValidPortSuffix(_ raw: String) -> Bool {
        guard raw.hasPrefix(":") else { return false }
        return isValidPort(String(raw.dropFirst()))
    }

    private static func isValidPort(_ raw: String) -> Bool {
        guard let port = Int(raw), port > 0, port <= Int(UInt16.max) else { return false }
        return true
    }

    private static func waitForReadable(_ fd: Int32, timeoutMilliseconds: Int32) -> Bool {
        var pollFD = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        while true {
            let result = poll(&pollFD, 1, timeoutMilliseconds)
            if result > 0 {
                return (pollFD.revents & Int16(POLLIN)) != 0
            }
            if result == -1, errno == EINTR {
                continue
            }
            return false
        }
    }

    private static func parseTarget(_ target: String) -> (String, [String: String]) {
        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = pieces.first.map(String.init) ?? "/"
        guard pieces.count == 2 else { return (path, [:]) }
        var query: [String: String] = [:]
        for pair in pieces[1].split(separator: "&", omittingEmptySubsequences: true) {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = percentDecoded(String(kv[0]))
            let value = kv.count == 2 ? percentDecoded(String(kv[1])) : ""
            query[key] = value
        }
        return (path, query)
    }

    private static func percentDecoded(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}

private struct WebSocketFrame {
    var opcode: UInt8
    var payload: Data
}

private extension Data {
    var containsHeaderTerminator: Bool {
        headerTerminatorRange != nil
    }

    var headerTerminatorRange: Range<Data.Index>? {
        range(of: Data([13, 10, 13, 10]))
    }
}
