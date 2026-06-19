import Foundation

public struct CopilotDeviceFlow: Sendable {
    public static let defaultHost = "github.com"

    private let clientID = "Iv1.b507a08c87ecfe98"
    private let scopes = "read:user"
    private let host: String

    public struct DeviceCodeResponse: Decodable, Sendable {
        public let deviceCode: String
        public let userCode: String
        public let verificationUri: String
        public let verificationUriComplete: String?
        public let expiresIn: Int
        public let interval: Int

        public var verificationURLToOpen: String {
            verificationUriComplete ?? verificationUri
        }

        private enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case verificationUriComplete = "verification_uri_complete"
            case expiresIn = "expires_in"
            case interval
        }
    }

    private struct AccessTokenResponse: Decodable {
        let accessToken: String

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
        }
    }

    public init(enterpriseHost: String? = nil) {
        host = Self.normalizedHost(enterpriseHost)
    }

    public static func normalizedHost(_ raw: String?) -> String {
        guard var host = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return defaultHost
        }
        let componentsValue = host.contains("://") ? host : "https://\(host)"
        if let components = URLComponents(string: componentsValue),
           let parsedHost = components.host,
           !parsedHost.isEmpty
        {
            host = parsedHost
            if let port = components.port {
                host += ":\(port)"
            }
        } else {
            if host.hasPrefix("https://") {
                host.removeFirst("https://".count)
            } else if host.hasPrefix("http://") {
                host.removeFirst("http://".count)
            }
            host = host.split(separator: "/", maxSplits: 1).first.map(String.init) ?? host
        }
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return normalized.isEmpty ? defaultHost : normalized
    }

    public func requestDeviceCode(session: URLSession = .shared) async throws -> DeviceCodeResponse {
        var request = try formRequest(path: "/login/device/code")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": clientID,
            "scope": scopes,
        ])
        let data = try await Self.perform(request, session: session)
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    public func pollForToken(
        deviceCode: String,
        interval: Int,
        session: URLSession = .shared) async throws -> String
    {
        var request = try formRequest(path: "/login/oauth/access_token")
        request.httpBody = Self.formURLEncodedBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        while true {
            try await Task.sleep(nanoseconds: UInt64(max(1, interval)) * 1_000_000_000)
            try Task.checkCancellation()

            let data = try await Self.perform(request, session: session, acceptsOAuthPending: true)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String
            {
                switch error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    continue
                case "expired_token":
                    throw URLError(.timedOut)
                default:
                    throw URLError(.userAuthenticationRequired)
                }
            }
            if let token = try? JSONDecoder().decode(AccessTokenResponse.self, from: data).accessToken,
               !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return token
            }
            throw URLError(.cannotParseResponse)
        }
    }

    private func formRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }

    private static func perform(
        _ request: URLRequest,
        session: URLSession,
        acceptsOAuthPending: Bool = false) async throws -> Data
    {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 200 { return data }
        if acceptsOAuthPending, (400...499).contains(http.statusCode) {
            return data
        }
        throw URLError(.badServerResponse)
    }

    private static func formURLEncodedBody(_ parameters: [String: String]) -> Data {
        let pairs = parameters
            .map { key, value in "\(formEncode(key))=\(formEncode(value))" }
            .joined(separator: "&")
        return Data(pairs.utf8)
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
