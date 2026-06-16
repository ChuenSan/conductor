import Foundation

/// conductor 自动化协议：Unix socket 上的 NDJSON（一行一个 JSON）。
/// 请求 `{"id":1,"method":"workspace.list","params":{...}}`；
/// 响应 `{"id":1,"ok":true,"result":...}` 或 `{"id":1,"ok":false,"error":{"code":...,"message":...}}`。
/// CLI 与 app 内服务共用这套类型，确保两端永远同构。
public enum AutomationProtocol {
    /// 协议版本：破坏性改动时 +1，CLI 据此提示升级。
    public static let version = 1
    public static let socketPathEnvKey = "CONDUCTOR_SOCKET_PATH"

    /// Conductor app and CLI share one local automation socket.
    public static var defaultSocketURL: URL {
        if let override = ProcessInfo.processInfo.environment[socketPathEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
            .appendingPathComponent("automation.sock", isDirectory: false)
    }
}

public struct AutomationRequest: Codable, Sendable {
    public var id: Int?
    public var method: String
    public var params: [String: JSONValue]?

    public init(id: Int? = nil, method: String, params: [String: JSONValue]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    /// 参数访问（缺省空字典）。
    public var parameters: [String: JSONValue] { params ?? [:] }
}

public struct AutomationError: Codable, Sendable, Error {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public static func badRequest(_ message: String) -> AutomationError {
        AutomationError(code: "bad-request", message: message)
    }

    public static func notFound(_ message: String) -> AutomationError {
        AutomationError(code: "not-found", message: message)
    }

    public static func unknownMethod(_ method: String) -> AutomationError {
        AutomationError(code: "unknown-method", message: "未知方法：\(method)")
    }

    public static func internalError(_ message: String) -> AutomationError {
        AutomationError(code: "internal", message: message)
    }
}

public struct AutomationResponse: Codable, Sendable {
    public var id: Int?
    public var ok: Bool
    public var result: JSONValue?
    public var error: AutomationError?

    public init(id: Int?, result: JSONValue) {
        self.id = id
        self.ok = true
        self.result = result
        self.error = nil
    }

    public init(id: Int?, error: AutomationError) {
        self.id = id
        self.ok = false
        self.result = nil
        self.error = error
    }
}

public enum AutomationCodec {
    /// 单行请求 → 请求对象。
    public static func decodeRequest(_ line: Data) throws -> AutomationRequest {
        try JSONDecoder().decode(AutomationRequest.self, from: line)
    }

    public static func decodeResponse(_ line: Data) throws -> AutomationResponse {
        try JSONDecoder().decode(AutomationResponse.self, from: line)
    }

    public static func encode(_ response: AutomationResponse) -> Data {
        (try? JSONEncoder().encode(response)) ?? Data("{\"ok\":false}".utf8)
    }

    public static func encode(_ request: AutomationRequest) -> Data {
        (try? JSONEncoder().encode(request)) ?? Data("{}".utf8)
    }
}
