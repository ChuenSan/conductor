import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CodexLoginRunner {
    public struct Result: Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            case success
            case timedOut
            case failed(status: Int32)
            case missingBinary
            case launchFailed(String)
        }

        public let outcome: Outcome
        public let output: String

        public init(outcome: Outcome, output: String) {
            self.outcome = outcome
            self.output = output
        }
    }

    public static func run(
        homePath: String? = nil,
        timeout: TimeInterval = 120,
        outputDrainTimeout: TimeInterval = 3,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loginPATH: [String]? = LoginShellPathCache.shared.current
    ) async -> Result {
        await Task(priority: .userInitiated) {
            var env = environment
            env["PATH"] = PathBuilder.effectivePATH(
                purposes: [.rpc, .tty, .nodeTooling],
                env: env,
                loginPATH: loginPATH)
            if let homePath = normalized(homePath) {
                env["CODEX_HOME"] = homePath
            }

            guard let executable = BinaryLocator.resolveCodexBinary(
                env: env,
                loginPATH: loginPATH)
            else {
                return Result(outcome: .missingBinary, output: "")
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable, "login"]
            process.environment = env

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdoutCapture = PipeCapture(pipe: stdout)
            let stderrCapture = PipeCapture(pipe: stderr)

            let termination = ProcessTermination()
            process.terminationHandler = { _ in
                termination.resolve(timedOut: false)
            }

            var processGroup: pid_t?
            do {
                try process.run()
                processGroup = attachProcessGroup(process)
            } catch {
                return Result(outcome: .launchFailed(error.localizedDescription), output: "")
            }
            stdoutCapture.start()
            stderrCapture.start()

            let timedOut = await wait(timeout: timeout, termination: termination)
            if timedOut {
                terminate(process, processGroup: processGroup)
            }

            let output = await combinedOutput(
                stdout: stdoutCapture,
                stderr: stderrCapture,
                timeout: outputDrainTimeout)
            if timedOut {
                return Result(outcome: .timedOut, output: output)
            }

            let status = process.terminationStatus
            if status == 0 {
                return Result(outcome: .success, output: output)
            }
            return Result(outcome: .failed(status: status), output: output)
        }.value
    }

    private final class ProcessTermination: @unchecked Sendable {
        private let lock = NSLock()
        private var timedOut: Bool?
        private var continuation: CheckedContinuation<Bool, Never>?

        func resolve(timedOut: Bool) {
            let continuation: CheckedContinuation<Bool, Never>?
            lock.lock()
            guard self.timedOut == nil else {
                lock.unlock()
                return
            }
            self.timedOut = timedOut
            continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: timedOut)
        }

        func wait() async -> Bool {
            await withCheckedContinuation { continuation in
                let resolved: Bool?
                lock.lock()
                resolved = timedOut
                if resolved == nil {
                    self.continuation = continuation
                }
                lock.unlock()

                if let resolved {
                    continuation.resume(returning: resolved)
                }
            }
        }
    }

    private final class PipeCapture: @unchecked Sendable {
        private let pipe: Pipe
        private let lock = NSLock()
        private var data = Data()

        init(pipe: Pipe) {
            self.pipe = pipe
        }

        func start() {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                self?.append(chunk)
            }
        }

        func finish(timeout: TimeInterval) async -> Data {
            pipe.fileHandleForReading.readabilityHandler = nil
            await drainTail(timeout: timeout)
            return snapshot()
        }

        private func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }

        private func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        private func drainTail(timeout: TimeInterval) async {
            await withCheckedContinuation { continuation in
                let queue = DispatchQueue(label: "com.conductor.codex-login-pipe-drain")
                let finished = AtomicFlag()
                queue.async {
                    let tail = self.pipe.fileHandleForReading.readDataToEndOfFile()
                    if !tail.isEmpty {
                        self.append(tail)
                    }
                    if finished.setIfNeeded() {
                        continuation.resume()
                    }
                }
                queue.asyncAfter(deadline: .now() + max(0, timeout)) {
                    if finished.setIfNeeded() {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private final class AtomicFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func setIfNeeded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !value else { return false }
            value = true
            return true
        }
    }

    private static func wait(timeout: TimeInterval, termination: ProcessTermination) async -> Bool {
        let timeoutTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds(timeout))
            if !Task.isCancelled {
                termination.resolve(timedOut: true)
            }
        }
        let timedOut = await termination.wait()
        timeoutTask.cancel()
        return timedOut
    }

    private static func timeoutNanoseconds(_ timeout: TimeInterval) -> UInt64 {
        guard timeout.isFinite else { return UInt64.max }
        let seconds = max(0, min(timeout, Double(UInt64.max) / 1_000_000_000))
        return UInt64(seconds * 1_000_000_000)
    }

    private static func terminate(_ process: Process, processGroup: pid_t?) {
        if let processGroup {
            kill(-processGroup, SIGTERM)
        }
        if process.isRunning {
            process.terminate()
        }

        let deadline = Date().addingTimeInterval(2.0)
        while process.isRunning, Date() < deadline {
            usleep(100_000)
        }

        if process.isRunning {
            if let processGroup {
                kill(-processGroup, SIGKILL)
            }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func attachProcessGroup(_ process: Process) -> pid_t? {
        let pid = process.processIdentifier
        return setpgid(pid, pid) == 0 ? pid : nil
    }

    private static func combinedOutput(
        stdout: PipeCapture,
        stderr: PipeCapture,
        timeout: TimeInterval
    ) async -> String {
        async let outData = stdout.finish(timeout: timeout)
        async let errData = stderr.finish(timeout: timeout)
        let out = await decode(outData)
        let err = await decode(errData)

        let merged = if !out.isEmpty, !err.isEmpty {
            [out, err].joined(separator: "\n")
        } else {
            out + err
        }
        let trimmed = merged.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = trimmed.prefix(4000)
        return limited.isEmpty ? L("未捕获到输出。") : String(limited)
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
