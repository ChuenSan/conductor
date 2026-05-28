import Foundation
import CodexBarCore

enum AgentCLIInstallState: Equatable {
    case unknown
    case checking
    case installed(path: String)
    case missing

    var isInstalled: Bool {
        if case .installed = self {
            return true
        }
        return false
    }
}

struct AgentCLIStatus: Equatable {
    let provider: AgentHookProvider
    var state: AgentCLIInstallState
    var checkedAt: Date?

    static func unknown(provider: AgentHookProvider) -> AgentCLIStatus {
        AgentCLIStatus(provider: provider, state: .unknown, checkedAt: nil)
    }
}

enum AgentCLIStatusDetector {
    static func detectAll() -> [AgentHookProvider: AgentCLIStatus] {
        Dictionary(uniqueKeysWithValues: AgentHookProvider.allCases.map { provider in
            (provider, detect(provider))
        })
    }

    static func checkingStatuses() -> [AgentHookProvider: AgentCLIStatus] {
        Dictionary(uniqueKeysWithValues: AgentHookProvider.allCases.map { provider in
            (provider, AgentCLIStatus(provider: provider, state: .checking, checkedAt: Date()))
        })
    }

    private static func detect(_ provider: AgentHookProvider) -> AgentCLIStatus {
        if let path = providerPreferredPath(provider) {
            return AgentCLIStatus(provider: provider, state: .installed(path: path), checkedAt: Date())
        }

        for executable in provider.executableCandidates {
            if let path = commandPath(for: executable) {
                return AgentCLIStatus(provider: provider, state: .installed(path: path), checkedAt: Date())
            }
        }
        return AgentCLIStatus(provider: provider, state: .missing, checkedAt: Date())
    }

    private static func providerPreferredPath(_ provider: AgentHookProvider) -> String? {
        switch provider {
        case .codex:
            BinaryLocator.resolveCodexBinary()
        case .claudeCode:
            BinaryLocator.resolveClaudeBinary()
        }
    }

    private static func commandPath(for executable: String) -> String? {
        let fileManager = FileManager.default
        if let path = findExecutable(executable, in: searchDirectories(), fileManager: fileManager) {
            return path
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"]
        if let path = ShellCommandLocator.commandV(executable, shell, 2.0, fileManager) {
            return path
        }

        return ShellCommandLocator.resolveAlias(executable, shell, 2.0, fileManager, NSHomeDirectory())
    }

    private static func searchDirectories() -> [String] {
        var directories: [String] = []
        let environment = ProcessInfo.processInfo.environment

        append(LoginShellPathCache.shared.current ?? [], to: &directories)

        if let path = environment["PATH"] {
            append(path.split(separator: ":").map(String.init), to: &directories)
        }

        let home = NSHomeDirectory()
        append([
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.claude/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.yarn/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ], to: &directories)

        return directories
    }

    private static func append(_ candidates: [String], to directories: inout [String]) {
        for candidate in candidates {
            let path = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !directories.contains(path) else { continue }
            directories.append(path)
        }
    }

    private static func findExecutable(
        _ executable: String,
        in directories: [String],
        fileManager: FileManager) -> String?
    {
        for directory in directories where !directory.isEmpty {
            let path = "\(directory.hasSuffix("/") ? String(directory.dropLast()) : directory)/\(executable)"
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
