import ConductorCore
import Foundation

/// 一次 git 调用的结果。移植自 SourceGit `Command.Result`。
public struct GitResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { self.exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum GitError: Swift.Error, LocalizedError, Sendable {
    /// 找不到 git 可执行文件。
    case gitNotFound
    /// 进程启动失败（权限/路径等）。
    case launchFailed(String)
    /// git 退出码非 0。`stderr` 已去掉进度噪声。
    case failed(exitCode: Int32, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound:
            "找不到 git。请确认已安装 git 并在 PATH 中。"
        case let .launchFailed(msg):
            "启动 git 失败：\(msg)"
        case let .failed(code, stderr):
            stderr.isEmpty ? "git 退出码 \(code)" : stderr
        }
    }
}

/// 一次 git 命令调用。对应 SourceGit 的 `Command` 基类：
/// 拼 `git --no-pager -c core.quotepath=off <args>`，设工作目录，跑进程，抓 stdout/stderr/exit。
///
/// 与 SourceGit 的差异：args 用 `[String]` 而非单字符串，省掉手动加引号/转义。
public struct GitProcess: Sendable {
    /// 工作目录（仓库路径）。nil 表示用当前进程目录。
    public let repository: String?
    /// 命令参数，不含 `git` 本身与全局开关。例：`["status", "--porcelain"]`。
    public let args: [String]

    public init(repository: String?, _ args: [String]) {
        self.repository = repository
        self.args = args
    }

    public init(repository: String?, args: [String]) {
        self.repository = repository
        self.args = args
    }

    /// 跑命令并返回结果。`allowFailure == false`（默认）时非 0 退出码抛 `GitError.failed`。
    /// 只读查询命令通常传 `allowFailure: true` 自行判断。
    @discardableResult
    public func run(allowFailure: Bool = false) async throws -> GitResult {
        guard let git = GitExecutable.resolve() else { throw GitError.gitNotFound }
        let full = Self.globalArgs + self.args
        let repo = self.repository
        let env = GitExecutable.environment()

        let result = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<GitResult, Swift.Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try Self.runSync(git: git, repository: repo, args: full, env: env)
                    cont.resume(returning: r)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }

        if !allowFailure, !result.isSuccess {
            throw GitError.failed(exitCode: result.exitCode, stderr: Self.cleanError(result.stderr))
        }
        return result
    }

    /// 跑命令，成功时返回 stdout 按行拆分（去掉行尾空行）；失败抛错。
    public func runLines(allowFailure: Bool = false) async throws -> [String] {
        let result = try await self.run(allowFailure: allowFailure)
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    // MARK: - 全局开关

    /// 与 SourceGit `CreateGitStartInfo` 对齐的全局开关：
    /// - `--no-pager`：永不进 pager（否则会挂起等输入）。
    /// - `core.quotepath=off`：非 ASCII 文件名不转义成 `\xxx`，原样输出。
    /// - `core.editor=true` / `GIT_TERMINAL_PROMPT=0`（见 environment）：禁止任何交互编辑/提示。
    static let globalArgs = ["--no-pager", "-c", "core.quotepath=off", "-c", "core.editor=true"]

    // MARK: - 同步执行（在后台队列上跑）

    /// 持有从管道读出的字节，跨并发读闭包安全传递（`DispatchGroup.wait()` 保证读完后才访问）。
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    private static func runSync(
        git: String,
        repository: String?,
        args: [String],
        env: [String: String]) throws -> GitResult
    {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: git)
        proc.arguments = args
        proc.environment = env
        if let repository {
            proc.currentDirectoryURL = URL(fileURLWithPath: repository)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // 从 /dev/null 喂 stdin，避免命令意外等待输入而挂起。
        proc.standardInput = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        // 并发读两个管道：git log 等输出可能很大，单线程顺序读会因管道缓冲满而死锁。
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "conductor.git.read", attributes: .concurrent)
        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        queue.async(group: group) { outBox.data = outHandle.readDataToEndOfFile() }
        queue.async(group: group) { errBox.data = errHandle.readDataToEndOfFile() }
        group.wait()
        proc.waitUntilExit()

        return GitResult(
            exitCode: proc.terminationStatus,
            stdout: String(decoding: outBox.data, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self))
    }

    /// 去掉 stderr 里的进度/提示噪声，只留真正的错误。移植自 SourceGit `Command.HandleOutput`。
    static func cleanError(_ stderr: String) -> String {
        let dropped = [
            "remote: Enumerating objects:",
            "remote: Counting objects:",
            "remote: Compressing objects:",
            "Filtering content:",
            "hint:",
        ]
        let lines = stderr
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                if dropped.contains(where: { line.hasPrefix($0) }) { return false }
                // 形如 "Receiving objects:  42% (...)" 的百分比进度行。
                if line.range(of: #"\d+%"#, options: .regularExpression) != nil { return false }
                return true
            }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
