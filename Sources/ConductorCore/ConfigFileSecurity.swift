import Foundation

public enum ConfigFileSecurity {
    public static func secureConfigFile(at url: URL) throws {
        #if os(macOS) || os(Linux)
        try FileManager.default.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o600)),
        ], ofItemAtPath: url.path)
        #endif
    }

    public static func secureConfigDirectory(at url: URL) throws {
        #if os(macOS) || os(Linux)
        try FileManager.default.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o700)),
        ], ofItemAtPath: url.path)
        #endif
    }
}
