import Foundation

enum ValidationLogger {
    static func info(_ message: String) {
        print("[ghostty-validation] \(message)")
    }

    static func warn(_ message: String) {
        print("[ghostty-validation] warn: \(message)")
    }

    static func error(_ message: String) {
        print("[ghostty-validation] error: \(message)")
    }
}
