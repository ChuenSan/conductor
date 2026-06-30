import Foundation
import SweetCookieKit
#if os(macOS)
import Darwin
#endif

#if os(macOS)
struct BrowserCookieHelperCandidate: Codable, Equatable, Sendable {
    let sourceLabel: String
    let cookieHeader: String
    let cookies: [OpenAIDashboardCookieSnapshot]
}

struct BrowserCookieHelperClientResult: Sendable {
    let candidates: [BrowserCookieHelperCandidate]
    let timedOut: Bool
}

enum BrowserCookieHelperClient {
    static func cookieHeaderCandidates(
        browser: Browser,
        domains: [String],
        timeout: TimeInterval,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> BrowserCookieHelperClientResult {
        guard timeout > 0,
              let executableURL = helperExecutableURL(env: env)
        else {
            return BrowserCookieHelperClientResult(candidates: [], timedOut: false)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "__browser-cookie-helper",
            "--browser", browser.rawValue,
            "--domains", domains.joined(separator: ","),
        ]
        var childEnvironment = UsageProviderProcessEnvironment.scrubbedChildEnvironment(from: env)
        childEnvironment["CONDUCTOR_BROWSER_COOKIE_HELPER_CHILD"] = "1"
        process.environment = childEnvironment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        let output = PipeOutputBuffer()
        let outputDrained = DispatchGroup()
        outputDrained.enter()
        let outputDone = OneShotFlag()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                if outputDone.fire() { outputDrained.leave() }
            } else {
                output.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            if outputDone.fire() { outputDrained.leave() }
            return BrowserCookieHelperClientResult(candidates: [], timedOut: false)
        }

        let deadline = DispatchTime.now() + timeout
        if finished.wait(timeout: deadline) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.3)
            }
            stdout.fileHandleForReading.readabilityHandler = nil
            if outputDone.fire() { outputDrained.leave() }
            return BrowserCookieHelperClientResult(candidates: [], timedOut: true)
        }

        guard process.terminationStatus == 0 else {
            stdout.fileHandleForReading.readabilityHandler = nil
            if outputDone.fire() { outputDrained.leave() }
            return BrowserCookieHelperClientResult(candidates: [], timedOut: false)
        }

        if outputDrained.wait(timeout: .now() + 0.8) != .success {
            stdout.fileHandleForReading.readabilityHandler = nil
            if outputDone.fire() { outputDrained.leave() }
        }
        let data = output.drain()
        guard let payload = try? JSONDecoder().decode(BrowserCookieHelperPayload.self, from: data) else {
            return BrowserCookieHelperClientResult(candidates: [], timedOut: false)
        }
        return BrowserCookieHelperClientResult(candidates: payload.candidates, timedOut: false)
    }

    private static func helperExecutableURL(env: [String: String]) -> URL? {
        for key in ["CONDUCTOR_BROWSER_COOKIE_HELPER", "CONDUCTORCTL_PATH"] {
            if let url = executableURL(from: env[key]), FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        return helperExecutableCandidates(env: env)
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func helperExecutableCandidates(env: [String: String]) -> [URL] {
        var candidates: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL?) {
            guard let url else { return }
            let resolved = url.standardizedFileURL
            guard seen.insert(resolved.path).inserted else { return }
            candidates.append(resolved)
        }

        let current = CommandLine.arguments.first.flatMap(executableURL(from:))
        if current?.lastPathComponent == "conductorctl" {
            append(current)
        }
        append(current?.deletingLastPathComponent().appendingPathComponent("conductorctl"))

        let mainExecutable = Bundle.main.executableURL
        if mainExecutable?.lastPathComponent == "conductorctl" {
            append(mainExecutable)
        }
        append(mainExecutable?.deletingLastPathComponent().appendingPathComponent("conductorctl"))

        let bundleURL = Bundle.main.bundleURL
        append(bundleURL.appendingPathComponent("Contents/MacOS/conductorctl"))
        append(bundleURL.appendingPathComponent("Contents/Resources/conductorctl"))

        let pathEntries = (env["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in pathEntries {
            append(URL(fileURLWithPath: entry).appendingPathComponent("conductorctl"))
        }
        append(URL(fileURLWithPath: "/opt/homebrew/bin/conductorctl"))
        append(URL(fileURLWithPath: "/usr/local/bin/conductorctl"))

        return candidates
    }

    private static func executableURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(raw)
            .standardizedFileURL
    }
}

public enum BrowserCookieHelperCommand {
    public static func run(args: [String]) throws {
        let options = try BrowserCookieHelperOptions(args: args)
        BrowserCookieKeychainAccessGate.allowsSafeStoragePasswordRead = true

        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: options.domains)
        let sources = try client.records(matching: query, in: options.browser)
        let candidates = sources.compactMap { source -> BrowserCookieHelperCandidate? in
            let cookies = source.cookies(origin: query.origin)
            let header = cookies
                .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { "\($0.name)=\($0.value)" }
                .joined(separator: "; ")
            guard let normalized = CookieHeaderNormalizer.normalize(header), !normalized.isEmpty else {
                return nil
            }
            return BrowserCookieHelperCandidate(
                sourceLabel: source.label,
                cookieHeader: normalized,
                cookies: OpenAIDashboardCookieSnapshot.snapshots(from: cookies))
        }

        let payload = BrowserCookieHelperPayload(candidates: candidates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

private struct BrowserCookieHelperPayload: Codable {
    let candidates: [BrowserCookieHelperCandidate]
}

private final class PipeOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ other: Data) {
        lock.lock()
        data.append(other)
        lock.unlock()
    }

    func drain() -> Data {
        lock.lock()
        let result = data
        lock.unlock()
        return result
    }
}

private final class OneShotFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

private struct BrowserCookieHelperOptions {
    let browser: Browser
    let domains: [String]

    init(args: [String]) throws {
        var browser: Browser?
        var domains: [String] = []
        var index = 0
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--browser":
                index += 1
                guard index < args.count, let parsed = Browser(rawValue: args[index]) else {
                    throw BrowserCookieHelperError.invalidArgument("--browser")
                }
                browser = parsed
            case "--domains":
                index += 1
                guard index < args.count else {
                    throw BrowserCookieHelperError.invalidArgument("--domains")
                }
                domains = args[index]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            default:
                throw BrowserCookieHelperError.invalidArgument(arg)
            }
            index += 1
        }
        guard let browser else { throw BrowserCookieHelperError.invalidArgument("--browser") }
        guard !domains.isEmpty else { throw BrowserCookieHelperError.invalidArgument("--domains") }
        self.browser = browser
        self.domains = domains
    }
}

private enum BrowserCookieHelperError: LocalizedError, CustomStringConvertible {
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArgument(argument):
            "Invalid browser cookie helper argument: \(argument)"
        }
    }

    var description: String {
        self.errorDescription ?? "Browser cookie helper failed."
    }
}
#endif
