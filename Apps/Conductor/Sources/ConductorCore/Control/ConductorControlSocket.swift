import Foundation

public enum ConductorControlSocket {
    public static let fileName = "control.sock"
    public static let overrideEnvironmentKey = "CONDUCTOR_CONTROL_SOCKET_PATH"

    public static func socketURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let overridePath = environment[overrideEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("Conductor", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
