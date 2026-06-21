import Foundation

public enum ConductorPaths {
    public static let stateDirEnvKey = "CONDUCTOR_STATE_DIR"
    public static let configPathEnvKey = "CONDUCTOR_CONFIG_PATH"
    public static let socketPathEnvKey = "CONDUCTOR_SOCKET_PATH"

    public static func isStateDirectoryOverridden(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        normalized(environment[stateDirEnvKey]) != nil
    }

    public static func appSupportDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = normalized(environment[stateDirEnvKey]) {
            return fileURL(override, isDirectory: true)
        }
        return fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
    }

    public static func agentHomeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if normalized(environment[stateDirEnvKey]) != nil {
            return appSupportDirectory(environment: environment, fileManager: fileManager)
                .appendingPathComponent("home", isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
    }

    public static func configURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = normalized(environment[configPathEnvKey]) {
            return fileURL(override, isDirectory: false)
        }
        if normalized(environment[stateDirEnvKey]) != nil {
            return appSupportDirectory(environment: environment, fileManager: fileManager)
                .appendingPathComponent("config.yaml", isDirectory: false)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/conductor/config.yaml", isDirectory: false)
    }

    public static func automationSocketURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = normalized(environment[socketPathEnvKey]) {
            return fileURL(override, isDirectory: false)
        }
        return appSupportDirectory(environment: environment, fileManager: fileManager)
            .appendingPathComponent("automation.sock", isDirectory: false)
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func fileURL(_ path: String, isDirectory: Bool) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: isDirectory)
            .standardizedFileURL
    }
}
