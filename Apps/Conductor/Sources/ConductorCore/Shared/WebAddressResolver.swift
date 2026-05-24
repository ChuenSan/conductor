import Foundation

public struct WebAddressResolver: Sendable {
    public var searchBaseURL: URL

    public init(searchBaseURL: URL = URL(string: "https://duckduckgo.com/")!) {
        self.searchBaseURL = searchBaseURL
    }

    public func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "file" {
            return url
        }

        if isLocalHost(trimmed), let url = URL(string: "http://\(trimmed)") {
            return url
        }

        if looksLikeDomain(trimmed), let url = URL(string: "https://\(trimmed)") {
            return url
        }

        var components = URLComponents(url: searchBaseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components?.url
    }

    private func isLocalHost(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased == "localhost" ||
            lowercased.hasPrefix("localhost:") ||
            lowercased == "127.0.0.1" ||
            lowercased.hasPrefix("127.0.0.1:") ||
            lowercased == "::1" ||
            lowercased.hasPrefix("[::1]:")
    }

    private func looksLikeDomain(_ value: String) -> Bool {
        guard !value.contains(" ") else { return false }
        guard let hostCandidate = value.split(separator: "/").first else { return false }
        return hostCandidate.contains(".") && !hostCandidate.hasPrefix(".") && !hostCandidate.hasSuffix(".")
    }
}
