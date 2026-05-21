import Foundation

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
        for executable in provider.executableCandidates {
            if let path = commandPath(for: executable) {
                return AgentCLIStatus(provider: provider, state: .installed(path: path), checkedAt: Date())
            }
        }
        return AgentCLIStatus(provider: provider, state: .missing, checkedAt: Date())
    }

    private static func commandPath(for executable: String) -> String? {
        let script = """
        PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        command -v \(shellQuote(executable))
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", script]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
