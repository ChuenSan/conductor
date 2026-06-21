import Foundation
import XCTest
@testable import ConductorCore

final class ConfigFileSecurityTests: XCTestCase {
    func testSecureConfigFileUsesOwnerOnlyPermissions() throws {
        #if os(macOS) || os(Linux)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-config-security-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("config.yaml")
        try "usage: {}\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([
            .posixPermissions: NSNumber(value: Int16(0o644)),
        ], ofItemAtPath: file.path)

        try ConfigFileSecurity.secureConfigFile(at: file)

        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        let mode = try XCTUnwrap(attrs[.posixPermissions] as? NSNumber).intValue & 0o777
        XCTAssertEqual(mode, 0o600)
        #endif
    }
}
