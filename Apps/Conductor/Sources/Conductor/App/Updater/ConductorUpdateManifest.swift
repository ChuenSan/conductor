import Foundation

enum ConductorUpdatePackageKind: String, Codable, Equatable, Sendable {
    case full
    case delta
}

struct ConductorUpdateArtifact: Codable, Equatable, Sendable {
    var filename: String
    var sha256: String
    var size: Int64
    var changedFiles: Int?
    var removedFiles: Int?
}

struct ConductorUpdateManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var app: String
    var bundleIdentifier: String
    var platform: String
    var arch: String
    var channel: String
    var version: String
    var build: String
    var createdAt: String
    var gitRevision: String?
    var minimumSystemVersion: String?
    var full: ConductorUpdateArtifact
    var delta: ConductorUpdateArtifact?

    var targetVersion: ConductorAppVersion {
        ConductorAppVersion(version: version, build: build)
    }

    func selectedArtifact(prefersDeltaUpdates: Bool) -> (kind: ConductorUpdatePackageKind, artifact: ConductorUpdateArtifact) {
        if prefersDeltaUpdates, let delta {
            return (.delta, delta)
        }
        return (.full, full)
    }
}
