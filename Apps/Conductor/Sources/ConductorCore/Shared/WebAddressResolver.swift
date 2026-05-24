import Foundation

public enum WebAddressResolver {
    public static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           directURL.host != nil {
            return directURL
        }

        if isLocalHost(trimmed) {
            return URL(string: "http://\(trimmed)")
        }

        if looksLikeDomain(trimmed) {
            return URL(string: "https://\(trimmed)")
        }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    private static func isLocalHost(_ value: String) -> Bool {
        value == "localhost" ||
            value.hasPrefix("localhost:") ||
            value.hasPrefix("127.0.0.1:") ||
            value.hasPrefix("[::1]:")
    }

    private static func looksLikeDomain(_ value: String) -> Bool {
        guard !value.contains(" ") else { return false }
        guard value.contains(".") else { return false }
        return URL(string: "https://\(value)")?.host != nil
    }
}
