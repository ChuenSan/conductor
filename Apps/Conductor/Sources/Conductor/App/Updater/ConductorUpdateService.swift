import AppKit
import CryptoKit
import Foundation

enum ConductorUpdateError: LocalizedError {
    case missingManifestURL
    case invalidHTTPStatus(Int)
    case invalidManifest(String)
    case noAppBundle
    case checksumMismatch(expected: String, actual: String)
    case missingDownloadedPackage
    case installerLaunchFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingManifestURL:
            "Update manifest URL is empty."
        case .invalidHTTPStatus(let status):
            "Update server returned HTTP \(status)."
        case .invalidManifest(let reason):
            "Update manifest is invalid: \(reason)"
        case .noAppBundle:
            "Conductor must be running from a .app bundle to install updates."
        case .checksumMismatch(let expected, let actual):
            "Downloaded update checksum does not match. Expected \(expected), got \(actual)."
        case .missingDownloadedPackage:
            "Downloaded update package was not found."
        case .installerLaunchFailed(let reason):
            "Could not start the updater: \(reason)"
        }
    }
}

actor ConductorUpdateService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fetchManifest(from manifestURL: URL) async throws -> ConductorUpdateManifest {
        let data = try await fetchData(from: manifestURL)
        do {
            return try JSONDecoder().decode(ConductorUpdateManifest.self, from: data)
        } catch {
            throw ConductorUpdateError.invalidManifest(error.localizedDescription)
        }
    }

    func downloadPackage(
        manifest: ConductorUpdateManifest,
        manifestURL: URL,
        kind: ConductorUpdatePackageKind,
        artifact: ConductorUpdateArtifact
    ) async throws -> ConductorDownloadedUpdate {
        let artifactURL = resolvedArtifactURL(artifact.filename, relativeTo: manifestURL)
        let destinationDirectory = try updateDirectory()
            .appendingPathComponent("\(manifest.version)-\(manifest.build)", isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destinationURL = destinationDirectory.appendingPathComponent(
            artifactURL.lastPathComponent.isEmpty ? artifact.filename : artifactURL.lastPathComponent
        )
        if fileManager.fileExists(atPath: destinationURL.path),
           try sha256Hex(for: destinationURL).caseInsensitiveCompare(artifact.sha256) == .orderedSame {
            return ConductorDownloadedUpdate(
                packageURL: destinationURL,
                artifactURL: artifactURL,
                kind: kind,
                manifest: manifest,
                artifact: artifact
            )
        }

        let temporaryURL = destinationDirectory.appendingPathComponent(".\(UUID().uuidString).download")
        try? fileManager.removeItem(at: temporaryURL)
        if artifactURL.isFileURL {
            try fileManager.copyItem(at: artifactURL, to: temporaryURL)
        } else {
            let (downloadedURL, response) = try await URLSession.shared.download(from: artifactURL)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw ConductorUpdateError.invalidHTTPStatus(httpResponse.statusCode)
            }
            try fileManager.moveItem(at: downloadedURL, to: temporaryURL)
        }

        let actualSHA = try sha256Hex(for: temporaryURL)
        guard actualSHA.caseInsensitiveCompare(artifact.sha256) == .orderedSame else {
            try? fileManager.removeItem(at: temporaryURL)
            throw ConductorUpdateError.checksumMismatch(expected: artifact.sha256, actual: actualSHA)
        }

        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        return ConductorDownloadedUpdate(
            packageURL: destinationURL,
            artifactURL: artifactURL,
            kind: kind,
            manifest: manifest,
            artifact: artifact
        )
    }

    func prepareInstaller(for downloadedUpdate: ConductorDownloadedUpdate) throws -> ConductorPreparedUpdate {
        guard fileManager.fileExists(atPath: downloadedUpdate.packageURL.path) else {
            throw ConductorUpdateError.missingDownloadedPackage
        }

        let currentAppURL = try currentApplicationBundleURL()
        let installerDirectory = try updateDirectory()
            .appendingPathComponent("install-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: installerDirectory, withIntermediateDirectories: true)

        let scriptURL = installerDirectory.appendingPathComponent("install-update.sh")
        let script = installerScript(
            currentAppURL: currentAppURL,
            packageURL: downloadedUpdate.packageURL,
            kind: downloadedUpdate.kind,
            workDirectory: installerDirectory,
            bundleIdentifier: Bundle.main.bundleIdentifier ?? downloadedUpdate.manifest.bundleIdentifier,
            processIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return ConductorPreparedUpdate(scriptURL: scriptURL)
    }

    @MainActor
    func launchInstallerAndTerminate(_ preparedUpdate: ConductorPreparedUpdate) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [preparedUpdate.scriptURL.path]
        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            throw ConductorUpdateError.installerLaunchFailed(error.localizedDescription)
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            return try Data(contentsOf: url)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw ConductorUpdateError.invalidHTTPStatus(httpResponse.statusCode)
        }
        return data
    }

    private func resolvedArtifactURL(_ filename: String, relativeTo manifestURL: URL) -> URL {
        if let url = URL(string: filename), url.scheme != nil {
            return url
        }
        return manifestURL
            .deletingLastPathComponent()
            .appendingPathComponent(filename)
    }

    private func updateDirectory() throws -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryURL = baseURL
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func currentApplicationBundleURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CONDUCTOR_UPDATE_CURRENT_APP"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        var candidate = Bundle.main.bundleURL.standardizedFileURL
        while !candidate.path.isEmpty, candidate.path != "/" {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw ConductorUpdateError.noAppBundle
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private func installerScript(
        currentAppURL: URL,
        packageURL: URL,
        kind: ConductorUpdatePackageKind,
        workDirectory: URL,
        bundleIdentifier: String,
        processIdentifier: Int32
    ) -> String {
        """
        #!/bin/bash
        set -euo pipefail

        CURRENT_APP=\(shellQuoted(currentAppURL.path))
        PACKAGE=\(shellQuoted(packageURL.path))
        KIND=\(shellQuoted(kind.rawValue))
        WORK_DIR=\(shellQuoted(workDirectory.path))
        EXPECTED_BUNDLE_IDENTIFIER=\(shellQuoted(bundleIdentifier))
        APP_PID=\(processIdentifier)
        LOG_FILE="$WORK_DIR/install.log"

        exec >>"$LOG_FILE" 2>&1
        echo "Conductor updater started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"

        for _ in $(/usr/bin/seq 1 160); do
          if ! /bin/kill -0 "$APP_PID" 2>/dev/null; then
            break
          fi
          /bin/sleep 0.25
        done

        STAGE="$WORK_DIR/stage"
        DELTA_ROOT="$WORK_DIR/delta"
        BACKUP_ROOT="$WORK_DIR/backup"
        BACKUP_APP="$BACKUP_ROOT/$(/usr/bin/basename "$CURRENT_APP")"

        /bin/rm -rf "$STAGE" "$DELTA_ROOT" "$BACKUP_ROOT"
        /bin/mkdir -p "$STAGE" "$BACKUP_ROOT"

        if [[ "$KIND" == "delta" ]]; then
          STAGED_APP="$STAGE/$(/usr/bin/basename "$CURRENT_APP")"
          /usr/bin/ditto "$CURRENT_APP" "$STAGED_APP"
          /bin/mkdir -p "$DELTA_ROOT"
          /usr/bin/ditto -x -k "$PACKAGE" "$DELTA_ROOT"
          /usr/bin/python3 - "$DELTA_ROOT/update-delta.json" "$STAGED_APP" <<'PY'
        import json
        import os
        import shutil
        import sys

        manifest_path, app_root = sys.argv[1], sys.argv[2]
        with open(manifest_path, "r", encoding="utf-8") as handle:
            manifest = json.load(handle)

        root = os.path.abspath(app_root)

        def safe_path(relative_path: str) -> str:
            normalized = relative_path.replace("\\\\", "/").lstrip("/")
            target = os.path.abspath(os.path.join(root, normalized))
            if target != root and not target.startswith(root + os.sep):
                raise SystemExit(f"Unsafe delta path: {relative_path}")
            return target

        for relative_path in manifest.get("removed", []):
            target = safe_path(relative_path)
            if os.path.isdir(target) and not os.path.islink(target):
                shutil.rmtree(target, ignore_errors=True)
            else:
                try:
                    os.remove(target)
                except FileNotFoundError:
                    pass
        PY
          if [[ -d "$DELTA_ROOT/payload/Conductor.app" ]]; then
            /usr/bin/ditto "$DELTA_ROOT/payload/Conductor.app" "$STAGED_APP"
          fi
        else
          /usr/bin/ditto -x -k "$PACKAGE" "$STAGE"
          STAGED_APP="$(/usr/bin/find "$STAGE" -maxdepth 2 -name '*.app' -type d | /usr/bin/head -n 1)"
        fi

        if [[ ! -d "$STAGED_APP" ]]; then
          echo "No staged app was produced."
          exit 20
        fi

        FOUND_BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)"
        if [[ -n "$EXPECTED_BUNDLE_IDENTIFIER" && "$FOUND_BUNDLE_IDENTIFIER" != "$EXPECTED_BUNDLE_IDENTIFIER" ]]; then
          echo "Bundle identifier mismatch: $FOUND_BUNDLE_IDENTIFIER"
          exit 21
        fi

        /usr/bin/codesign --verify --deep --strict "$STAGED_APP"
        /usr/bin/xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true

        if [[ -d "$CURRENT_APP" ]]; then
          /bin/mv "$CURRENT_APP" "$BACKUP_APP"
        fi

        if ! /usr/bin/ditto "$STAGED_APP" "$CURRENT_APP"; then
          /bin/rm -rf "$CURRENT_APP"
          if [[ -d "$BACKUP_APP" ]]; then
            /bin/mv "$BACKUP_APP" "$CURRENT_APP"
          fi
          exit 30
        fi

        /usr/bin/open "$CURRENT_APP"
        /bin/rm -rf "$BACKUP_ROOT" "$STAGE" "$DELTA_ROOT"
        echo "Conductor updater finished at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        """
    }
}
