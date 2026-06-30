import Foundation

public enum UsageEndpointPolicy {
    public static func trustedHTTPSURL(
        from raw: String?,
        default defaultURL: URL,
        allowedHosts: Set<String>,
        allowedHostSuffixes: [String] = []
    ) -> URL {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              isTrustedHTTPSURL(url, allowedHosts: allowedHosts, allowedHostSuffixes: allowedHostSuffixes)
        else {
            return defaultURL
        }
        return url
    }

    public static func isTrustedHTTPSURL(
        _ url: URL,
        allowedHosts: Set<String>,
        allowedHostSuffixes: [String] = []
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased()
        else {
            return false
        }
        if allowedHosts.contains(host) { return true }
        return allowedHostSuffixes.contains { suffix in
            let normalized = suffix.lowercased()
            return host.hasSuffix(".\(normalized)")
        }
    }
}
