import Foundation

public struct MiniMaxCookieOverride: Sendable {
    public let cookieHeader: String
    public let authorizationToken: String?
    public let groupID: String?

    public init(cookieHeader: String, authorizationToken: String?, groupID: String?) {
        self.cookieHeader = cookieHeader
        self.authorizationToken = authorizationToken
        self.groupID = groupID
    }
}

public enum MiniMaxCookieHeader {
    private static let authorizationPattern = #"(?i)\bauthorization:\s*bearer\s+([A-Za-z0-9._\-+=/]+)"#
    private static let groupIDPatterns = [
        #"(?i)\bx-group-id:\s*([0-9]{4,})"#,
        #"(?i)\bminimax_group_id_v2=([0-9]{4,})"#,
        #"(?i)\bgroup[_]?id=([0-9]{4,})"#,
    ]

    public static func override(from raw: String?) -> MiniMaxCookieOverride? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let cookie = CookieHeaderNormalizer.normalize(raw)
        else {
            return nil
        }
        return MiniMaxCookieOverride(
            cookieHeader: cookie,
            authorizationToken: extractFirst(pattern: authorizationPattern, text: raw),
            groupID: extractFirst(patterns: groupIDPatterns, text: raw))
    }

    private static func extractFirst(patterns: [String], text: String) -> String? {
        for pattern in patterns {
            if let value = extractFirst(pattern: pattern, text: text) {
                return value
            }
        }
        return nil
    }

    private static func extractFirst(pattern: String, text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        let value = text[valueRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value)
    }
}
