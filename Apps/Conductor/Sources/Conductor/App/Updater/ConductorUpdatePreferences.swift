import Foundation

struct ConductorUpdatePreferences: Codable, Equatable, Sendable {
    var manifestURLString: String
    var automaticChecksEnabled: Bool
    var prefersDeltaUpdates: Bool

    static let publicManifestURLString = "https://github.com/zhengzizhe/conductor/releases/latest/download/latest-stable-macos-arm64.json"

    static func defaults(environment: [String: String] = ProcessInfo.processInfo.environment) -> ConductorUpdatePreferences {
        let bundledURL = Bundle.main.object(forInfoDictionaryKey: "ConductorUpdateManifestURL") as? String
        let manifestURLString = firstNonEmpty(
            environment["CONDUCTOR_UPDATE_MANIFEST_URL"],
            bundledURL,
            publicManifestURLString
        )
        return ConductorUpdatePreferences(
            manifestURLString: manifestURLString,
            automaticChecksEnabled: !manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            prefersDeltaUpdates: true
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    var normalizedManifestURLString: String {
        manifestURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var manifestURL: URL? {
        let value = normalizedManifestURLString
        guard !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
    }
}

final class ConductorUpdatePreferencesStore {
    private let userDefaults: UserDefaults
    private let manifestURLKey = "ConductorUpdateManifestURL"
    private let automaticChecksKey = "ConductorUpdateAutomaticChecksEnabled"
    private let prefersDeltaKey = "ConductorUpdatePrefersDeltaUpdates"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load() -> ConductorUpdatePreferences {
        var preferences = ConductorUpdatePreferences.defaults()
        if let value = userDefaults.string(forKey: manifestURLKey),
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            preferences.manifestURLString = value
        }
        if userDefaults.object(forKey: automaticChecksKey) != nil {
            preferences.automaticChecksEnabled = userDefaults.bool(forKey: automaticChecksKey)
        }
        if userDefaults.object(forKey: prefersDeltaKey) != nil {
            preferences.prefersDeltaUpdates = userDefaults.bool(forKey: prefersDeltaKey)
        }
        return preferences
    }

    func save(_ preferences: ConductorUpdatePreferences) {
        userDefaults.set(preferences.manifestURLString, forKey: manifestURLKey)
        userDefaults.set(preferences.automaticChecksEnabled, forKey: automaticChecksKey)
        userDefaults.set(preferences.prefersDeltaUpdates, forKey: prefersDeltaKey)
    }
}
