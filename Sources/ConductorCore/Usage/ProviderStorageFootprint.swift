import Foundation

public struct ProviderStorageFootprint: Sendable, Equatable {
    public struct Component: Sendable, Equatable, Identifiable {
        public let id: String
        public let path: String
        public let totalBytes: Int64

        public init(path: String, totalBytes: Int64) {
            self.id = path
            self.path = path
            self.totalBytes = totalBytes
        }

        public var name: String {
            let url = URL(fileURLWithPath: path)
            let last = url.lastPathComponent
            return last.isEmpty ? path : last
        }
    }

    public let providerID: String
    public let totalBytes: Int64
    public let paths: [String]
    public let missingPaths: [String]
    public let unreadablePaths: [String]
    public let components: [Component]
    public let updatedAt: Date

    public init(
        providerID: String,
        totalBytes: Int64,
        paths: [String],
        missingPaths: [String],
        unreadablePaths: [String],
        components: [Component] = [],
        updatedAt: Date)
    {
        self.providerID = providerID
        self.totalBytes = totalBytes
        self.paths = paths
        self.missingPaths = missingPaths
        self.unreadablePaths = unreadablePaths
        self.components = components
        self.updatedAt = updatedAt
    }

    public var hasLocalData: Bool { totalBytes > 0 }

    public var byteCountText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    public var cleanupRecommendations: [ProviderStorageRecommendation] {
        ProviderStorageRecommendation.recommendations(for: self)
    }

    public func hasSameContents(as other: ProviderStorageFootprint) -> Bool {
        providerID == other.providerID
            && totalBytes == other.totalBytes
            && paths == other.paths
            && missingPaths == other.missingPaths
            && unreadablePaths == other.unreadablePaths
            && components == other.components
    }

    public func replacingProviderID(_ providerID: String) -> ProviderStorageFootprint {
        ProviderStorageFootprint(
            providerID: providerID,
            totalBytes: totalBytes,
            paths: paths,
            missingPaths: missingPaths,
            unreadablePaths: unreadablePaths,
            components: components,
            updatedAt: updatedAt)
    }

    public static func applyingScanResults(
        _ footprints: [String: ProviderStorageFootprint],
        to current: [String: ProviderStorageFootprint],
        providerIDs: [String])
        -> [String: ProviderStorageFootprint]
    {
        let providerSet = Set(providerIDs)
        var updated = current.filter { !providerSet.contains($0.key) }
        for providerID in providerIDs {
            if let incoming = footprints[providerID],
               let existing = current[providerID],
               existing.hasSameContents(as: incoming)
            {
                updated[providerID] = existing
            } else {
                updated[providerID] = footprints[providerID]
            }
        }
        return updated
    }
}

public struct ProviderStorageRecommendation: Sendable, Equatable, Identifiable {
    public enum RiskLevel: String, Sendable {
        case informational
        case manualCleanup
    }

    public let id: String
    public let providerID: String
    public let path: String
    public let bytes: Int64
    public let title: String
    public let exportTitle: String
    public let riskLevel: RiskLevel
    public let consequence: String
    public let exportConsequence: String
    public let sortPriority: Int

    public init(
        providerID: String,
        path: String,
        bytes: Int64,
        title: String,
        exportTitle: String? = nil,
        riskLevel: RiskLevel,
        consequence: String,
        exportConsequence: String? = nil,
        sortPriority: Int)
    {
        self.id = path
        self.providerID = providerID
        self.path = path
        self.bytes = bytes
        self.title = title
        self.exportTitle = exportTitle ?? title
        self.riskLevel = riskLevel
        self.consequence = consequence
        self.exportConsequence = exportConsequence ?? consequence
        self.sortPriority = sortPriority
    }

    public static func recommendations(for footprint: ProviderStorageFootprint) -> [ProviderStorageRecommendation] {
        let provider = footprint.providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates: [ProviderStorageRecommendation] = footprint.components.compactMap { component in
            switch provider {
            case "claude":
                claudeRecommendation(for: component)
            case "codex":
                codexRecommendation(for: component, roots: footprint.paths)
            default:
                nil
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.sortPriority == rhs.sortPriority {
                if lhs.bytes == rhs.bytes {
                    return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
                }
                return lhs.bytes > rhs.bytes
            }
            return lhs.sortPriority < rhs.sortPriority
        }
    }

    private static func claudeRecommendation(
        for component: ProviderStorageFootprint.Component)
        -> ProviderStorageRecommendation?
    {
        return switch component.name {
        case "projects":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：历史会话",
                exportTitle: "Manual cleanup: past sessions",
                consequence: "清理后会移除过去的 resume、continue 和 rewind 历史。",
                exportConsequence: "Clearing removes past resume, continue, and rewind history.",
                priority: 10)
        case "file-history":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：文件检查点",
                exportTitle: "Manual cleanup: file checkpoints",
                consequence: "清理后会移除旧编辑的检查点恢复数据。",
                exportConsequence: "Clearing removes checkpoint restore data for previous edits.",
                priority: 20)
        case "plans":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：已保存计划",
                exportTitle: "Manual cleanup: saved plans",
                consequence: "清理后会移除旧的 plan-mode 文件。",
                exportConsequence: "Clearing removes old plan-mode files.",
                priority: 30)
        case "debug":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：调试日志",
                exportTitle: "Manual cleanup: debug logs",
                consequence: "清理后会移除历史调试日志。",
                exportConsequence: "Clearing removes past debug logs.",
                priority: 40)
        case "paste-cache", "image-cache":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：附件缓存",
                exportTitle: "Manual cleanup: attachment cache",
                consequence: "清理后会移除大型粘贴内容或图片附件缓存。",
                exportConsequence: "Clearing removes cached large pastes or attached images.",
                priority: 50)
        case "session-env":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：会话元数据",
                exportTitle: "Manual cleanup: session metadata",
                consequence: "清理后会移除每个会话的环境元数据。",
                exportConsequence: "Clearing removes per-session environment metadata.",
                priority: 60)
        case "shell-snapshots":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：Shell 快照",
                exportTitle: "Manual cleanup: shell snapshots",
                consequence: "清理后会移除残留的运行时 Shell 快照文件。",
                exportConsequence: "Clearing removes leftover runtime shell snapshot files.",
                priority: 70)
        case "todos":
            make(
                providerID: "claude",
                component: component,
                title: "手动清理：旧版待办",
                exportTitle: "Manual cleanup: legacy todos",
                consequence: "清理后会移除旧版的每会话任务列表。",
                exportConsequence: "Clearing removes legacy per-session task lists.",
                priority: 80)
        default:
            nil
        }
    }

    private static func codexRecommendation(
        for component: ProviderStorageFootprint.Component,
        roots: [String])
        -> ProviderStorageRecommendation?
    {
        guard path(component.path, isContainedIn: roots) else { return nil }

        return switch component.name {
        case "sessions":
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：会话",
                exportTitle: "Manual cleanup: sessions",
                consequence: "清理后会移除过去的 Codex 会话历史。",
                exportConsequence: "Clearing removes past Codex session history.",
                priority: 10)
        case "archived_sessions":
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：归档会话",
                exportTitle: "Manual cleanup: archived sessions",
                consequence: "清理后会移除已归档的 Codex 会话历史。",
                exportConsequence: "Clearing removes archived Codex session history.",
                priority: 20)
        case "cache", "caches", "Cache", "Caches":
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：缓存",
                exportTitle: "Manual cleanup: cache",
                consequence: "清理后会移除 provider 自有缓存数据。",
                exportConsequence: "Clearing removes provider-owned cached data.",
                priority: 30)
        case "log", "logs", "debug":
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：日志",
                exportTitle: "Manual cleanup: logs",
                consequence: "清理后会移除本地诊断日志。",
                exportConsequence: "Clearing removes local diagnostic logs.",
                priority: 40)
        case let name where name.hasPrefix("logs_") && name.hasSuffix(".sqlite"):
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：日志",
                exportTitle: "Manual cleanup: logs",
                consequence: "清理后会移除本地诊断日志。",
                exportConsequence: "Clearing removes local diagnostic logs.",
                priority: 40)
        case "file-history":
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：文件历史",
                exportTitle: "Manual cleanup: file history",
                consequence: "清理后会移除本地编辑检查点历史。",
                exportConsequence: "Clearing removes local edit checkpoint history.",
                priority: 50)
        case "paste-cache", "image-cache", "session-env", "shell-snapshots", "shell_snapshots", "tmp", "temp", ".tmp":
            make(
                providerID: "codex",
                component: component,
                title: "手动清理：临时数据",
                exportTitle: "Manual cleanup: temporary data",
                consequence: "清理后会移除本地 provider 临时数据。",
                exportConsequence: "Clearing removes local temporary provider data.",
                priority: 60)
        default:
            nil
        }
    }

    private static func make(
        providerID: String,
        component: ProviderStorageFootprint.Component,
        title: String,
        exportTitle: String,
        consequence: String,
        exportConsequence: String,
        priority: Int)
        -> ProviderStorageRecommendation
    {
        ProviderStorageRecommendation(
            providerID: providerID,
            path: component.path,
            bytes: component.totalBytes,
            title: title,
            exportTitle: exportTitle,
            riskLevel: .manualCleanup,
            consequence: consequence,
            exportConsequence: exportConsequence,
            sortPriority: priority)
    }

    private static func path(_ path: String, isContainedIn roots: [String]) -> Bool {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return roots.contains { root in
            let standardizedRoot = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.path
            return standardizedPath == standardizedRoot || standardizedPath.hasPrefix(standardizedRoot + "/")
        }
    }
}

public enum ProviderStoragePathCatalog {
    public static func candidatePaths(
        for providerID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        additionalCodexHomePaths: [String] = [],
        fileManager: FileManager = .default)
        -> [String]
    {
        let home = normalized(environment["HOME"])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.homeDirectoryForCurrentUser

        func homePath(_ relativePath: String) -> String {
            home.appendingPathComponent(relativePath, isDirectory: true).path
        }

        let provider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidates: [String]
        switch provider {
        case "codex":
            candidates = [CodexManagedAccountDiscovery.codexHomeURL(env: environment, fileManager: fileManager).path]
                + managedCodexHomePaths(environment: environment, fileManager: fileManager)
                + additionalCodexHomePaths
        case "claude":
            candidates = [
                homePath(".claude"),
                homePath(".config/claude"),
                fileManager.temporaryDirectory
                    .appendingPathComponent("conductor-cli-probe", isDirectory: true)
                    .path,
            ]
        case "gemini":
            candidates = [
                homePath(".gemini"),
                homePath(".config/gemini"),
            ]
        case "opencode", "opencodego":
            candidates = [homePath(".config/opencode")]
        case "copilot":
            candidates = [homePath(".config/github-copilot")]
        case "cursor":
            candidates = [
                homePath("Library/Application Support/Cursor"),
                homePath("Library/Application Support/Caches/cursor-updater"),
                homePath(".cursor"),
                homePath("Library/Caches/Cursor"),
                homePath("Library/Caches/com.todesktop.230313mzl4w4u92"),
                homePath("Library/Caches/com.todesktop.230313mzl4w4u92.ShipIt"),
                homePath("Library/Caches/cursor-compile-cache"),
                homePath("Library/HTTPStorages/com.todesktop.230313mzl4w4u92"),
            ]
        default:
            candidates = []
        }

        return uniqueStandardizedPaths(candidates)
    }

    private static func managedCodexHomePaths(
        environment: [String: String],
        fileManager: FileManager)
        -> [String]
    {
        let storeURL = CodexManagedAccountDiscovery.storeURL(env: environment, fileManager: fileManager)
        let store = FileCodexManagedAccountStore(fileURL: storeURL, fileManager: fileManager)
        return ((try? store.loadAccounts())?.accounts ?? []).map(\.managedHomePath)
    }

    private static func uniqueStandardizedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let standardized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
            guard seen.insert(standardized).inserted else { continue }
            result.append(standardized)
        }
        return result
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

public enum ProviderStorageFootprintLoader {
    public static func scanProviders(
        _ providers: [UsageProviderEntry],
        config: AppConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default)
        -> [String: ProviderStorageFootprint]
    {
        let scanner = ProviderStorageScanner(fileManager: fileManager)
        let additionalCodexHomes = additionalCodexHomePaths(config: config, fileManager: fileManager)
        var footprints: [String: ProviderStorageFootprint] = [:]
        var pathCache: [String: ProviderStorageFootprint] = [:]

        for provider in providers {
            if Task.isCancelled { return footprints }
            let paths = ProviderStoragePathCatalog.candidatePaths(
                for: provider.id,
                environment: environment,
                additionalCodexHomePaths: provider.id == "codex" ? additionalCodexHomes : [],
                fileManager: fileManager)
            guard !paths.isEmpty else { continue }
            let pathKey = paths.joined(separator: "\u{1f}")
            if let cached = pathCache[pathKey] {
                footprints[provider.id] = cached.replacingProviderID(provider.id)
                continue
            }
            let footprint = scanner.scan(providerID: provider.id, candidatePaths: paths)
            pathCache[pathKey] = footprint
            footprints[provider.id] = footprint
        }
        return footprints
    }

    public static func additionalCodexHomePaths(
        config: AppConfig,
        fileManager: FileManager = .default)
        -> [String]
    {
        let accounts = config.usage.providers["codex"]?.tokenAccounts?.accounts ?? []
        return accounts
            .map(\.token)
            .filter { token in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: token, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
    }
}

public struct ProviderStorageScanner: @unchecked Sendable {
    private struct DirectoryScanResult {
        var bytes: Int64 = 0
        var unreadablePaths: [String] = []
        var componentBytes: [String: Int64] = [:]
    }

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(
        providerID: String,
        candidatePaths: [String],
        now: Date = Date())
        -> ProviderStorageFootprint
    {
        var totalBytes: Int64 = 0
        var existingPaths: [String] = []
        var missingPaths: [String] = []
        var unreadablePaths: [String] = []
        var components: [ProviderStorageFootprint.Component] = []

        for path in candidatePaths {
            if Task.isCancelled { break }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
                missingPaths.append(path)
                continue
            }

            existingPaths.append(path)
            let url = URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
            if isSymbolicLink(at: url) { continue }

            if isDirectory.boolValue {
                let result = scanDirectory(at: url)
                if Task.isCancelled { break }
                totalBytes += result.bytes
                unreadablePaths.append(contentsOf: result.unreadablePaths)
                components.append(contentsOf: result.componentBytes.map {
                    ProviderStorageFootprint.Component(path: $0.key, totalBytes: $0.value)
                })
            } else {
                let result = sizeOfFile(at: url)
                totalBytes += result.bytes
                unreadablePaths.append(contentsOf: result.unreadablePaths)
                if result.bytes > 0 {
                    components.append(.init(path: url.path, totalBytes: result.bytes))
                }
            }
        }

        return ProviderStorageFootprint(
            providerID: providerID,
            totalBytes: totalBytes,
            paths: existingPaths,
            missingPaths: missingPaths,
            unreadablePaths: unreadablePaths,
            components: components.sorted { lhs, rhs in
                if lhs.totalBytes == rhs.totalBytes {
                    return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
                }
                return lhs.totalBytes > rhs.totalBytes
            },
            updatedAt: now)
    }

    private func isSymbolicLink(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private func sizeOfFile(at url: URL) -> (bytes: Int64, unreadablePaths: [String]) {
        if Task.isCancelled { return (0, []) }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return (0, [url.path])
        }
        if values.isSymbolicLink == true { return (0, []) }
        if values.isRegularFile == true {
            return (Int64(values.fileSize ?? 0), [])
        }
        return (0, [])
    }

    private func scanDirectory(at url: URL) -> DirectoryScanResult {
        if Task.isCancelled { return DirectoryScanResult() }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ]

        let unreadableCollector = ProviderStorageUnreadablePathCollector()
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { url, _ in
                unreadableCollector.append(url.path)
                return true
            })
        else {
            return DirectoryScanResult(unreadablePaths: [url.path])
        }

        var result = DirectoryScanResult()
        let rootPath = url.standardizedFileURL.path
        for case let itemURL as URL in enumerator {
            if Task.isCancelled {
                enumerator.skipDescendants()
                break
            }
            guard let itemValues = try? itemURL.resourceValues(forKeys: keys) else {
                unreadableCollector.append(itemURL.path)
                continue
            }
            if itemValues.isSymbolicLink == true {
                if itemValues.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if itemValues.isRegularFile == true {
                let bytes = Int64(itemValues.fileSize ?? 0)
                result.bytes += bytes
                if bytes > 0, let componentPath = topLevelComponentPath(for: itemURL, rootPath: rootPath) {
                    result.componentBytes[componentPath, default: 0] += bytes
                }
            }
        }
        result.unreadablePaths = unreadableCollector.paths
        return result
    }

    private func topLevelComponentPath(for url: URL, rootPath: String) -> String? {
        let itemPath = url.standardizedFileURL.path
        let pathPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        guard itemPath.hasPrefix(pathPrefix) else { return nil }
        let suffix = itemPath.dropFirst(pathPrefix.count)
        let relative = suffix.drop { $0 == "/" }
        guard let first = relative.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first else {
            return nil
        }
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(String(first))
            .path
    }
}

private final class ProviderStorageUnreadablePathCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(path)
    }
}
