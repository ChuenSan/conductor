import Foundation

struct ConductorAppVersion: Codable, Comparable, Equatable, Sendable {
    var version: String
    var build: String

    var displayText: String {
        "\(version) (\(build))"
    }

    static func current(bundle: Bundle = .main) -> ConductorAppVersion {
        let version = bundleValue("CFBundleShortVersionString", in: bundle) ?? "0.0.0"
        let build = bundleValue("CFBundleVersion", in: bundle) ?? "0"
        return ConductorAppVersion(version: version, build: build)
    }

    static func < (lhs: ConductorAppVersion, rhs: ConductorAppVersion) -> Bool {
        switch compareVersionString(lhs.version, rhs.version) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return compareBuildString(lhs.build, rhs.build) == .orderedAscending
        }
    }

    private static func bundleValue(_ key: String, in bundle: Bundle) -> String? {
        if let value = bundle.object(forInfoDictionaryKey: key) as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: key) as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func compareVersionString(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = numericVersionParts(lhs)
        let rhsParts = numericVersionParts(rhs)
        guard !lhsParts.isEmpty, !rhsParts.isEmpty else {
            return lhs.localizedStandardCompare(rhs)
        }

        let count = max(lhsParts.count, rhsParts.count)
        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : 0
            let right = index < rhsParts.count ? rhsParts[index] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func numericVersionParts(_ value: String) -> [Int] {
        value
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }

    private static func compareBuildString(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if let left = Int64(lhs), let right = Int64(rhs) {
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        }
        return lhs.localizedStandardCompare(rhs)
    }
}
