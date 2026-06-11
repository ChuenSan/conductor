import Foundation
import os

// MARK: - Logging shim
//
// 这套 CLI 检测代码原样来自 CodexBar（MIT）。它内部用 `CodexBarLog.logger(...)`
// 打日志；conductor 不想引入 CodexBar 的整套日志子系统，这里用 os.Logger 做一个
// 等价的最小实现，保持调用点不变（debug/info/warning/error + metadata）。

public struct CodexBarLogger: Sendable {
    private let logger: Logger

    init(category: String) {
        self.logger = Logger(subsystem: "com.conductor.cli-detection", category: category)
    }

    private func render(_ message: String, _ metadata: [String: String]?) -> String {
        guard let metadata, !metadata.isEmpty else { return message }
        let pairs = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(message) {\(pairs)}"
    }

    public func debug(_ message: @autoclosure () -> String, metadata: [String: String]? = nil) {
        let line = self.render(message(), metadata)
        self.logger.debug("\(line, privacy: .public)")
    }

    public func info(_ message: @autoclosure () -> String, metadata: [String: String]? = nil) {
        let line = self.render(message(), metadata)
        self.logger.info("\(line, privacy: .public)")
    }

    public func warning(_ message: @autoclosure () -> String, metadata: [String: String]? = nil) {
        let line = self.render(message(), metadata)
        self.logger.warning("\(line, privacy: .public)")
    }

    public func error(_ message: @autoclosure () -> String, metadata: [String: String]? = nil) {
        let line = self.render(message(), metadata)
        self.logger.error("\(line, privacy: .public)")
    }
}

public enum CodexBarLog {
    public static func logger(_ category: String) -> CodexBarLogger {
        CodexBarLogger(category: category)
    }
}

public enum LogCategories {
    public static let ttyRunner = "tty-runner"
}

// MARK: - Claude probe working directory shim
//
// 原版用 ClaudeStatusProbe 准备一个隔离的工作目录（带 .claude/settings.local.json），
// 让 `claude --version` 之类的探测不读取项目级配置。CLI 检测只需要一个干净的临时目录，
// 这里给一个最小实现。

public enum ClaudeStatusProbe {
    public static func preparedProbeWorkingDirectoryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("conductor-cli-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
