import ConductorCore
import Foundation

struct ConductorWorkspaceMetadataContext: Sendable {
    let workspaceID: WorkspaceID
    let title: String
    let selected: Bool
    let candidateRootPaths: [String]
    let counts: WorkspaceMetadataSnapshot.Counts
    let activeAgentCount: Int
    let unreadCount: Int
    let terminals: [WorkspaceMetadataSnapshot.TerminalSummary]
    let files: [WorkspaceMetadataSnapshot.FileSummary]
    let webTabs: [WorkspaceMetadataSnapshot.WebSummary]
}

enum ConductorWorkspaceMetadataService {
    private static let commandTimeout: TimeInterval = 0.9

    static func snapshots(for contexts: [ConductorWorkspaceMetadataContext]) async -> [WorkspaceMetadataSnapshot] {
        await withTaskGroup(of: (Int, WorkspaceMetadataSnapshot).self, returning: [WorkspaceMetadataSnapshot].self) { group in
            for (index, context) in contexts.enumerated() {
                group.addTask {
                    (index, await snapshot(for: context))
                }
            }

            var results: [(Int, WorkspaceMetadataSnapshot)] = []
            for await result in group {
                results.append(result)
            }
            return results
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }
    }

    private static func snapshot(
        for context: ConductorWorkspaceMetadataContext
    ) async -> WorkspaceMetadataSnapshot {
        let root = resolvedRoot(from: context.candidateRootPaths)
        let portRoots = portScanRoots(primaryRoot: root?.path, candidates: context.candidateRootPaths)
        let ports = await runningPorts(underAnyOf: portRoots)
        let devServers = deduplicatedServers(ports.servers + devServers(from: context.webTabs))
        let health: String
        if root == nil {
            health = "root_unknown"
        } else if ports.state == "timeout" {
            health = "metadata_partial"
        } else {
            health = "ok"
        }

        return WorkspaceMetadataSnapshot(
            workspaceID: context.workspaceID,
            title: context.title,
            selected: context.selected,
            rootPath: root?.path,
            rootSource: root?.source ?? "unknown",
            projectName: projectName(title: context.title, rootPath: root?.path),
            counts: context.counts,
            runningPorts: Set(ports.ports + devServers.map(\.port)).sorted(),
            devServers: devServers,
            portScanState: ports.state,
            activeAgentCount: context.activeAgentCount,
            unreadCount: context.unreadCount,
            terminals: context.terminals,
            files: context.files,
            webTabs: context.webTabs,
            health: health
        )
    }

    private static func resolvedRoot(from candidates: [String]) -> (path: String, source: String)? {
        for rawCandidate in candidates {
            let trimmed = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let expanded = (trimmed as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                return (
                    isDirectory.boolValue ? url.path : url.deletingLastPathComponent().path,
                    isDirectory.boolValue ? "terminal-cwd" : "file"
                )
            }
        }
        return nil
    }

    private static func portScanRoots(primaryRoot: String?, candidates: [String]) -> [String] {
        var roots: [String] = []
        if let primaryRoot {
            roots.append(primaryRoot)
        }
        for rawCandidate in candidates {
            let trimmed = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let expanded = (trimmed as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            roots.append(isDirectory.boolValue ? url.path : url.deletingLastPathComponent().path)
        }
        return scopedPortScanRoots(deduplicatedPaths(roots))
    }

    private static func deduplicatedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { path in
            let normalized = URL(fileURLWithPath: path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return seen.insert(normalized).inserted
        }
    }

    private static func scopedPortScanRoots(_ roots: [String]) -> [String] {
        guard roots.count > 1 else { return roots }
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let filtered = roots.filter { root in
            let normalized = URL(fileURLWithPath: root)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return normalized != home
        }
        return filtered.isEmpty ? roots : filtered
    }

    private static func projectName(title: String, rootPath: String?) -> String {
        guard let rootPath,
              !rootPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return title
        }
        let name = URL(fileURLWithPath: rootPath).lastPathComponent
        return name.isEmpty ? title : name
    }

    private static func runningPorts(
        underAnyOf rootPaths: [String]
    ) async -> (state: String, ports: [Int], servers: [WorkspaceMetadataSnapshot.DevServerSummary]) {
        guard !rootPaths.isEmpty else {
            return ("root_unknown", [], [])
        }
        let output = await runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"],
            timeout: commandTimeout
        )
        switch output {
        case .success(let text):
            let listeners = parseLsofListeners(text)
            guard !listeners.isEmpty else {
                return ("no_listeners", [], [])
            }
            var matchedServers: [WorkspaceMetadataSnapshot.DevServerSummary] = []
            for listener in listeners {
                guard let cwd = await processCwd(pid: listener.pid),
                      rootPaths.contains(where: { path(cwd, isInside: $0) }) else {
                    continue
                }
                for port in listener.ports {
                    matchedServers.append(WorkspaceMetadataSnapshot.DevServerSummary(
                        port: port,
                        url: "http://localhost:\(port)",
                        label: devServerLabel(processName: listener.processName, port: port),
                        processID: listener.pid,
                        processName: listener.processName,
                        workingDirectory: cwd
                    ))
                }
            }
            let deduplicated = deduplicatedServers(matchedServers)
            return ("ok", deduplicated.map(\.port), deduplicated)
        case .timeout:
            return ("timeout", [], [])
        case .failure(let message):
            return (message.isEmpty ? "unavailable" : "unavailable:\(message)", [], [])
        }
    }

    private static func processCwd(pid: Int) async -> String? {
        let output = await runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-a", "-p", String(pid), "-d", "cwd", "-Fn"],
            timeout: commandTimeout
        )
        guard case .success(let text) = output else {
            return nil
        }
        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard line.first == "n" else { return nil }
                return String(line.dropFirst())
            }
            .first
    }

    private static func parseLsofListeners(_ text: String) -> [(pid: Int, processName: String?, ports: [Int])] {
        var results: [(pid: Int, processName: String?, ports: [Int])] = []
        var currentPID: Int?
        var currentProcessName: String?
        var ports = Set<Int>()

        func flush() {
            if let currentPID, !ports.isEmpty {
                results.append((currentPID, currentProcessName, ports.sorted()))
            }
            currentProcessName = nil
            ports.removeAll(keepingCapacity: true)
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("p") {
                flush()
                currentPID = Int(line.dropFirst())
            } else if line.hasPrefix("c") {
                currentProcessName = String(line.dropFirst())
            } else if line.hasPrefix("n") {
                ports.formUnion(portsInLsofName(String(line.dropFirst())))
            }
        }
        flush()
        return results
    }

    private static func deduplicatedServers(
        _ servers: [WorkspaceMetadataSnapshot.DevServerSummary]
    ) -> [WorkspaceMetadataSnapshot.DevServerSummary] {
        var byPort: [Int: WorkspaceMetadataSnapshot.DevServerSummary] = [:]
        for server in servers {
            if let existing = byPort[server.port] {
                let existingHasCwd = existing.workingDirectory?.isEmpty == false
                let nextHasCwd = server.workingDirectory?.isEmpty == false
                if !existingHasCwd && nextHasCwd {
                    byPort[server.port] = server
                }
            } else {
                byPort[server.port] = server
            }
        }
        return byPort.values.sorted { $0.port < $1.port }
    }

    private static func devServers(
        from webTabs: [WorkspaceMetadataSnapshot.WebSummary]
    ) -> [WorkspaceMetadataSnapshot.DevServerSummary] {
        webTabs.compactMap { tab in
            let rawURL = tab.url ?? (tab.pendingAddress.isEmpty ? nil : tab.pendingAddress)
            guard let rawURL,
                  let url = URL(string: rawURL),
                  let port = url.port,
                  isLocalhost(url.host(percentEncoded: false)) else {
                return nil
            }
            return WorkspaceMetadataSnapshot.DevServerSummary(
                port: port,
                url: "http://localhost:\(port)",
                label: tab.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? "\(tab.title ?? "localhost") :\(port)"
                    : "localhost:\(port)"
            )
        }
    }

    private static func isLocalhost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    private static func devServerLabel(processName: String?, port: Int) -> String {
        let cleanName = processName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleanName, !cleanName.isEmpty {
            return "\(cleanName) :\(port)"
        }
        return "localhost:\(port)"
    }

    private static func portsInLsofName(_ name: String) -> [Int] {
        let parts = name.split(separator: ":")
        guard let last = parts.last else { return [] }
        let numeric = last.prefix { $0.isNumber }
        guard let port = Int(numeric), port > 0 else { return [] }
        return [port]
    }

    private static func path(_ path: String, isInside rootPath: String) -> Bool {
        let pathURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let rootURL = URL(fileURLWithPath: rootPath).standardizedFileURL.resolvingSymlinksInPath()
        return pathURL.path == rootURL.path || pathURL.path.hasPrefix(rootURL.path + "/")
    }

    private enum CommandResult: Sendable {
        case success(String)
        case timeout
        case failure(String)
    }

    private static func runCommand(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(error.localizedDescription))
                    return
                }

                let deadline = DispatchTime.now() + .milliseconds(Int(timeout * 1000))
                let semaphore = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in
                    semaphore.signal()
                }

                if semaphore.wait(timeout: deadline) == .timedOut {
                    process.terminate()
                    continuation.resume(returning: .timeout)
                    return
                }

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(output))
                } else {
                    continuation.resume(returning: .failure(errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
        }
    }
}
