import Foundation
import CryptoKit
#if canImport(Security)
import Security
#endif

public enum CookieHeaderNormalizer {
    private static let headerPatterns: [String] = [
        #"(?i)-H\s*'Cookie:\s*([^']+)'"#,
        #"(?i)-H\s*\"Cookie:\s*([^\"]+)\""#,
        #"(?i)\bcookie:\s*'([^']+)'"#,
        #"(?i)\bcookie:\s*\"([^\"]+)\""#,
        #"(?i)\bcookie:\s*([^\r\n]+)"#,
        #"(?i)(?:^|\s)(?:--cookie|-b)\s*'([^']+)'"#,
        #"(?i)(?:^|\s)(?:--cookie|-b)\s*\"([^\"]+)\""#,
        #"(?i)(?:^|\s)-b([^\s=]+=[^\s]+)"#,
        #"(?i)(?:^|\s)(?:--cookie|-b)\s+([^\s]+)"#,
    ]

    public static func normalize(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let extracted = extractHeader(from: value) {
            value = extracted
        }
        value = stripCookiePrefix(value)
        value = stripWrappingQuotes(value)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func pairs(from raw: String) -> [(name: String, value: String)] {
        guard let normalized = normalize(raw) else { return [] }
        var results: [(name: String, value: String)] = []
        results.reserveCapacity(6)

        for part in normalized.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let equalsIndex = trimmed.firstIndex(of: "=")
            else {
                continue
            }
            let name = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = trimmed[trimmed.index(after: equalsIndex)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            results.append((name: String(name), value: String(value)))
        }
        return results
    }

    public static func filteredHeader(from raw: String?, allowedNames: Set<String>) -> String? {
        let filtered = pairs(from: raw ?? "").filter { allowedNames.contains($0.name) }
        guard !filtered.isEmpty else { return nil }
        return filtered.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func extractHeader(from raw: String) -> String? {
        for pattern in headerPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            guard let match = regex.firstMatch(in: raw, range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: raw)
            else {
                continue
            }
            let captured = raw[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty { return String(captured) }
        }
        return nil
    }

    private static func stripCookiePrefix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("cookie:") else { return trimmed }
        let index = trimmed.index(trimmed.startIndex, offsetBy: "cookie:".count)
        return String(trimmed[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripWrappingQuotes(_ raw: String) -> String {
        guard raw.count >= 2 else { return raw }
        if (raw.hasPrefix("\"") && raw.hasSuffix("\"")) ||
            (raw.hasPrefix("'") && raw.hasSuffix("'"))
        {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }
}

public struct OpenAIDashboardCookieSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let expiresDate: Date?

    public init?(_ cookie: HTTPCookie) {
        let name = cookie.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = cookie.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !domain.isEmpty else { return nil }
        self.name = name
        self.value = cookie.value
        self.domain = domain
        self.path = cookie.path.isEmpty ? "/" : cookie.path
        self.isSecure = cookie.isSecure
        self.isHTTPOnly = cookie.isHTTPOnly
        self.expiresDate = cookie.expiresDate
    }

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        isSecure: Bool = true,
        isHTTPOnly: Bool = false,
        expiresDate: Date? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path.isEmpty ? "/" : path
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.expiresDate = expiresDate
    }

    public static func snapshots(from cookies: [HTTPCookie]) -> [OpenAIDashboardCookieSnapshot] {
        cookies.compactMap(OpenAIDashboardCookieSnapshot.init)
    }

    public func makeHTTPCookie() -> HTTPCookie? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedDomain.isEmpty else { return nil }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: trimmedName,
            .value: value,
            .domain: trimmedDomain,
            .path: path.isEmpty ? "/" : path,
            .secure: isSecure,
        ]
        if isHTTPOnly {
            properties[.init("HttpOnly")] = "TRUE"
        }
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if let originURL = originURL(forDomain: trimmedDomain) {
            properties[.originURL] = originURL
        }
        return HTTPCookie(properties: properties)
    }

    private func originURL(forDomain domain: String) -> URL? {
        let host = domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty else { return nil }
        return URL(string: "\(isSecure ? "https" : "http")://\(host)")
    }
}

public enum CookieHeaderCache {
    public struct Scope: Equatable, Sendable {
        public let identifier: String

        public init?(_ raw: String?) {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else {
                return nil
            }
            self.identifier = raw
        }
    }

    public struct Entry: Codable, Equatable, Sendable {
        public let cookieHeader: String
        public let storedAt: Date
        public let sourceLabel: String

        public init(cookieHeader: String, storedAt: Date, sourceLabel: String) {
            self.cookieHeader = cookieHeader
            self.storedAt = storedAt
            self.sourceLabel = sourceLabel
        }
    }

    private static let service = "com.conductor.cookie-header-cache"

    public static func load(providerID: String, scope: Scope? = nil) -> Entry? {
        #if canImport(Security)
        var query = keychainQuery(providerID: providerID, scope: scope)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                clear(providerID: providerID, scope: scope)
            }
            return nil
        }
        guard let entry = try? JSONDecoder().decode(Entry.self, from: data),
              CookieHeaderNormalizer.normalize(entry.cookieHeader) != nil
        else {
            clear(providerID: providerID, scope: scope)
            return nil
        }
        return entry
        #else
        return nil
        #endif
    }

    @discardableResult
    public static func store(
        providerID: String,
        scope: Scope? = nil,
        cookieHeader: String,
        sourceLabel: String,
        now: Date = Date()
    ) -> Bool {
        guard let normalized = CookieHeaderNormalizer.normalize(cookieHeader),
              !normalized.isEmpty,
              let data = try? JSONEncoder().encode(Entry(
                  cookieHeader: normalized,
                  storedAt: now,
                  sourceLabel: sourceLabel))
        else {
            clear(providerID: providerID, scope: scope)
            return false
        }

        #if canImport(Security)
        var item = keychainQuery(providerID: providerID, scope: scope)
        SecItemDelete(item as CFDictionary)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        #else
        return false
        #endif
    }

    @discardableResult
    public static func clear(providerID: String, scope: Scope? = nil) -> Int {
        #if canImport(Security)
        if scope == nil {
            return clearAllScopes(providerID: providerID)
        }
        let status = SecItemDelete(keychainQuery(providerID: providerID, scope: scope) as CFDictionary)
        return status == errSecSuccess ? 1 : 0
        #else
        return 0
        #endif
    }

    #if canImport(Security)
    private static func clearAllScopes(providerID: String) -> Int {
        let provider = normalizedProviderID(providerID)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return 0
        }

        var cleared = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account == provider || account.hasPrefix("\(provider):")
            else {
                continue
            }
            query = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            if SecItemDelete(query as CFDictionary) == errSecSuccess {
                cleared += 1
            }
        }
        return cleared
    }
    #endif

    private static func keychainQuery(providerID: String, scope: Scope?) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key(providerID: providerID, scope: scope),
        ]
    }

    private static func key(providerID: String, scope: Scope?) -> String {
        let provider = normalizedProviderID(providerID)
        guard let scope else { return provider }
        let digest = SHA256.hash(data: Data(scope.identifier.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(provider):\(digest)"
    }

    private static func normalizedProviderID(_ providerID: String) -> String {
        providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
