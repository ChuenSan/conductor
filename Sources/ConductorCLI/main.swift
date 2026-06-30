import ConductorCore
import Darwin
import Foundation
import Yams

struct CLIError: Error, CustomStringConvertible, LocalizedError, Sendable {
    let description: String
    var httpStatus: String

    init(_ description: String, httpStatus: String = "500 Internal Server Error") {
        self.description = description
        self.httpStatus = httpStatus
    }

    var errorDescription: String? { description }
}

struct CLISilentExit: Error, Sendable {
    let status: Int32
}

struct Options: Sendable {
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    func value(_ key: String) -> String? { values[key] }
    func has(_ key: String) -> Bool { flags.contains(key) || values[key] != nil }
}

func wantsHelp(_ args: [String]) -> Bool {
    args.contains("--help") || args.contains("-h") || args.contains("help")
}

func effectiveCLIArguments(_ args: [String]) -> [String] {
    guard let first = args.first else { return ["usage"] }
    if first.hasPrefix("-") { return ["usage"] + args }
    return args
}

func parseOptions(_ args: [String]) throws -> Options {
    let valueOptions: Set<String> = [
        "agent",
        "api-key",
        "base-url",
        "account",
        "account-index",
        "command",
        "cookie",
        "cookie-header",
        "cwd",
        "color",
        "days",
        "direction",
        "external-id",
        "format",
        "field",
        "host",
        "icon",
        "interval",
        "job",
        "jobId",
        "key",
        "label",
        "level",
        "log-level",
        "limit",
        "name",
        "org",
        "organization",
        "pane",
        "path",
        "poll",
        "port",
        "prompt",
        "project",
        "provider",
        "refresh-interval",
        "request-timeout",
        "source",
        "session",
        "tab",
        "text",
        "title",
        "timeout",
        "token",
        "value",
        "web-timeout",
        "workspace",
    ]
    var options = Options()
    var index = 0
    while index < args.count {
        let arg = args[index]
        if arg == "--" {
            options.positional.append(contentsOf: args.dropFirst(index + 1))
            break
        }
        if arg.hasPrefix("--") {
            let raw = String(arg.dropFirst(2))
            if let equal = raw.firstIndex(of: "=") {
                let key = String(raw[..<equal])
                let value = String(raw[raw.index(after: equal)...])
                options.values[key] = value
            } else if valueOptions.contains(raw), index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                options.values[raw] = args[index + 1]
                index += 1
            } else if valueOptions.contains(raw) {
                throw CLIError("--\(raw) requires a value")
            } else {
                options.flags.insert(raw)
            }
        } else if arg.hasPrefix("-"), arg.count > 1 {
            switch arg {
            case "-v":
                options.flags.insert("verbose")
            case "-h":
                options.flags.insert("help")
            case "-V":
                options.flags.insert("version")
            default:
                options.positional.append(arg)
            }
        } else {
            options.positional.append(arg)
        }
        index += 1
    }
    return options
}

final class SocketClient {
    private let socketURL: URL
    private var nextID = 1

    init(socketURL: URL = AutomationProtocol.defaultSocketURL) {
        self.socketURL = socketURL
    }

    func request(method: String, params: [String: JSONValue] = [:]) throws -> AutomationResponse {
        let automationRequest = AutomationRequest(id: nextID, method: method, params: params.isEmpty ? nil : params)
        nextID += 1
        return try request(automationRequest)
    }

    func request(_ request: AutomationRequest) throws -> AutomationResponse {
        try performRequest(request, throwOnRPCError: true)
    }

    func requestRaw(_ request: AutomationRequest) throws -> AutomationResponse {
        try performRequest(request, throwOnRPCError: false)
    }

    private func performRequest(_ request: AutomationRequest, throwOnRPCError: Bool) throws -> AutomationResponse {
        let response: AutomationResponse
        do {
            response = try send(request)
        } catch {
            AppLauncher.wake()
            let deadline = Date().addingTimeInterval(3)
            var lastError = error
            while Date() < deadline {
                usleep(150_000)
                let retryResponse: AutomationResponse
                do {
                    retryResponse = try send(request)
                } catch {
                    lastError = error
                    continue
                }
                if throwOnRPCError, let error = retryResponse.error {
                    throw CLIError("\(error.code): \(error.message)")
                }
                return retryResponse
            }
            throw CLIError("Could not connect to Conductor socket at \(socketURL.path): \(lastError)")
        }
        if throwOnRPCError, let error = response.error {
            throw CLIError("\(error.code): \(error.message)")
        }
        return response
    }

    private func send(_ request: AutomationRequest) throws -> AutomationResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw CLIError("socket() failed: \(String(cString: strerror(errno)))") }
        defer { close(fd) }

        var noSigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigpipe, socklen_t(MemoryLayout<Int32>.size))

        let path = socketURL.path
        guard path.utf8.count < 100 else { throw CLIError("Socket path is too long: \(path)") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buffer in
            path.utf8CString.withUnsafeBytes { source in
                buffer.copyBytes(from: source.prefix(buffer.count - 1))
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, size)
            }
        }
        guard connected == 0 else {
            throw CLIError(String(cString: strerror(errno)))
        }

        var payload = AutomationCodec.encode(request)
        payload.append(0x0A)
        try writeAll(payload, fd: fd)
        let reply = try readLine(fd: fd)
        return try AutomationCodec.decodeResponse(reply)
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = write(fd, pointer, remaining)
                guard written > 0 else {
                    throw CLIError("write() failed: \(String(cString: strerror(errno)))")
                }
                pointer += written
                remaining -= written
            }
        }
    }

    private func readLine(fd: Int32) throws -> Data {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let count = read(fd, &byte, 1)
            guard count > 0 else {
                throw CLIError("Socket closed before a response was received")
            }
            if byte == 0x0A { return data }
            data.append(byte)
        }
    }
}

enum AppLauncher {
    static func wake() {
        if let path = ProcessInfo.processInfo.environment["CONDUCTOR_APP_PATH"], !path.isEmpty {
            runOpen(["-g", path])
        } else {
            runOpen(["-g", "-a", "Conductor"])
        }
    }

    private static func runOpen(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

func pretty(_ value: JSONValue?) -> String {
    guard let value else { return "null" }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        return text
    }
    return "\(value)"
}

func jsonLine(_ value: JSONValue) -> String {
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        return text
    }
    return "null"
}

final class AsyncResultBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}

func runAsync<T>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    let box = AsyncResultBox<T>()
    Task {
        do {
            box.result = .success(try await body())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    guard let result = box.result else {
        throw CLIError("Async operation did not return a result")
    }
    return try result.get()
}

func object(_ value: JSONValue?) -> [String: JSONValue] {
    value?.objectValue ?? [:]
}

func array(_ value: JSONValue?) -> [JSONValue] {
    value?.arrayValue ?? []
}

func printResult(_ response: AutomationResponse, json: Bool = false) {
    if json {
        print(pretty(response.result))
    } else if let result = response.result {
        print(pretty(result))
    }
}

func paramsFromJSONString(_ raw: String?) throws -> [String: JSONValue] {
    guard let raw, !raw.isEmpty else { return [:] }
    guard let data = raw.data(using: .utf8) else { throw CLIError("Invalid JSON text") }
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    guard let object = value.objectValue else { throw CLIError("Raw params must be a JSON object") }
    return object
}

func usage() -> String {
    """
    conductorctl: control Conductor over its local Unix socket

    Usage:
      conductorctl [usage options]
      conductorctl ping
      conductorctl status [--json]
      conductorctl usage [--provider both|all|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--source auto|web|cli|oauth|api] [--web] [--account LABEL|--account-index N|--all-accounts] [--status] [--no-credits] [--web-timeout SECONDS] [--web-debug-dump-html] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl diagnose [--provider both|all|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--source auto|web|cli|oauth|api] [--account LABEL|--account-index N|--all-accounts] [--storage] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl storage [--provider all|both|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl provider-status [--provider both|all|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl cost [--provider all|both|codex|claude|vertexai|bedrock] [--days 30] [--refresh] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config validate [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config dump [--format json] [--json-only] [--pretty]
      conductorctl config providers [--provider all|both|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--verbose] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config order [--provider ID_OR_ALIAS[,ID_OR_ALIAS...]] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config enable|disable --provider ID_OR_ALIAS [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config set-api-key --provider ID_OR_ALIAS (--api-key KEY|--stdin) [--no-enable] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config set-cookie --provider ID_OR_ALIAS (--cookie COOKIE|--stdin) [--no-enable] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config set --provider ID_OR_ALIAS --key sourceMode|baseURL|projectID|organizationID|cookieSource|extra.NAME --value VALUE [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config unset --provider ID_OR_ALIAS --key sourceMode|baseURL|projectID|organizationID|cookieSource|extra.NAME [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config accounts --provider ID_OR_ALIAS [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account add --provider ID_OR_ALIAS (--token TOKEN|--stdin) [--label LABEL] [--organization ORG] [--external-id ID] [--no-select] [--no-enable] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account update --provider ID_OR_ALIAS (--account LABEL|--account-index N) [--label LABEL] [--token TOKEN|--stdin] [--organization ORG|--clear-organization] [--external-id ID|--clear-external-id] [--select] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account select --provider ID_OR_ALIAS (--account LABEL|--account-index N) [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account remove --provider ID_OR_ALIAS (--account LABEL|--account-index N) [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl cache clear <--cookies|--cost|--all> [--provider ID_OR_ALIAS] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl serve [--port 8080] [--refresh-interval 60] [--request-timeout 30]
      conductorctl raw METHOD '{"key":"value"}'
      conductorctl batch < requests.ndjson
      conductorctl methods
      conductorctl workspace list|current|tree [--json]
      conductorctl workspace select WORKSPACE
      conductorctl workspace create PATH [--name NAME] [--json]
      conductorctl workspace rename WORKSPACE NAME
      conductorctl workspace close WORKSPACE
      conductorctl workspace status set KEY TEXT [--workspace WORKSPACE] [--color HEX] [--icon SF_SYMBOL]
      conductorctl workspace status list [--workspace WORKSPACE] [--json]
      conductorctl workspace status clear [KEY] [--workspace WORKSPACE]
      conductorctl workspace progress set VALUE [--workspace WORKSPACE] [--label TEXT]
      conductorctl workspace progress clear [--workspace WORKSPACE]
      conductorctl workspace log append TEXT [--workspace WORKSPACE] [--level LEVEL] [--source SOURCE]
      conductorctl workspace log list [--workspace WORKSPACE] [--limit N] [--json]
      conductorctl workspace log clear [--workspace WORKSPACE]
      conductorctl tab list [--workspace WORKSPACE] [--json]
      conductorctl tab select TAB [--workspace WORKSPACE]
      conductorctl tab rename TAB TITLE [--workspace WORKSPACE]
      conductorctl tab close TAB [--workspace WORKSPACE]
      conductorctl pane list [--json]
      conductorctl pane create [--cwd PATH] [--json]
      conductorctl pane split [--pane PANE] [--direction right|down] [--cwd PATH] [--json]
      conductorctl pane focus PANE
      conductorctl pane close [PANE]
      conductorctl screen [--pane PANE] [--scrollback]
      conductorctl send [--pane PANE] [--no-submit] [--stdin] TEXT
      conductorctl run AGENT [--cwd PATH] [--prompt TEXT|--stdin] [--command COMMAND] [--no-submit] [--wait] [--timeout SECONDS] [--poll SECONDS] [--json]
      conductorctl agent status [JOB] [--json]
      conductorctl agent wait [JOB] [--timeout SECONDS] [--poll SECONDS] [--json]
      conductorctl agent result [JOB] [--json]
      conductorctl activity [--limit N] [--json]
      conductorctl events [--limit N] [--interval SECONDS] [--jsonl]
      conductorctl watch [--interval SECONDS] [--jsonl]
      conductorctl bridge [--host 127.0.0.1] [--port 17373] [--interval SECONDS]

    Global flags:
      -h, --help
      -V, --version
      -v, --verbose
      --no-color
      --log-level trace|verbose|debug|info|warning|error|critical
      --json-output
      --json-only

    Environment:
      CONDUCTOR_APP_PATH=/path/to/Conductor.app  app to wake when socket is absent
      CONDUCTOR_SOCKET_PATH=/path/to/socket      override local socket path
    """
}

func usageCommandUsage() -> String {
    """
    Usage: conductorctl usage [--provider both|all|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--source auto|web|cli|oauth|api] [--web] [--account LABEL|--account-index N|--all-accounts] [--status] [--no-credits] [--web-timeout SECONDS] [--web-debug-dump-html] [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func diagnoseUsage() -> String {
    """
    Usage: conductorctl diagnose [--provider both|all|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--source auto|web|cli|oauth|api] [--account LABEL|--account-index N|--all-accounts] [--storage] [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func storageUsage() -> String {
    """
    Usage: conductorctl storage [--provider all|both|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func providerStatusUsage() -> String {
    """
    Usage: conductorctl provider-status [--provider both|all|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func costUsage() -> String {
    """
    Usage: conductorctl cost [--provider all|both|codex|claude|vertexai|bedrock] [--days 30] [--refresh] [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func serveUsage() -> String {
    """
    Usage: conductorctl serve [--port 8080] [--refresh-interval 60] [--request-timeout 30]

    Description:
      Start a foreground localhost-only HTTP server that exposes usage, cost,
      diagnostics, storage, provider status, config, and cache endpoints.
      The server binds to 127.0.0.1 only.

    Endpoints:
      GET  /health
      GET  /openapi.json
      GET  /usage
      GET  /usage?provider=all
      GET  /cost
      GET  /cost?provider=all
      GET  /storage
      GET  /provider-status
      GET  /diagnose
      GET  /config/providers
      GET  /config/validate
      GET  /config/dump
      GET  /config/accounts?provider=ID_OR_ALIAS
      POST /config/account
      POST /config/provider
      POST /config/order
      POST /cache/clear

    Examples:
      conductorctl serve
      conductorctl serve --port 8080 --refresh-interval 60 --request-timeout 30
      curl http://127.0.0.1:8080/usage?provider=all
    """
}

func printHelp(for command: String?) {
    switch command?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "usage":
        print(usageCommandUsage())
    case "diagnose", "diagnostic":
        print(diagnoseUsage())
    case "storage", "storage-footprint":
        print(storageUsage())
    case "provider-status", "status-page":
        print(providerStatusUsage())
    case "cost":
        print(costUsage())
    case "cache", "clear":
        print(cacheUsage())
    case "config", "validate", "dump", "providers", "enable", "disable", "set-api-key", "set-cookie", "set", "unset", "accounts", "account":
        print(configUsage())
    case "serve":
        print(serveUsage())
    default:
        print(usage())
    }
}

func printVersion() {
    if let version = currentCLIVersion() {
        print("Conductor \(version)")
    } else {
        print("Conductor")
    }
}

func currentCLIVersion() -> String? {
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
    }
    guard let executable = CommandLine.arguments.first, !executable.isEmpty else {
        return nil
    }
    let executableURL = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
    let candidates = [
        executableURL.deletingLastPathComponent().appendingPathComponent("VERSION"),
        executableURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("VERSION"),
    ]
    for candidate in candidates {
        guard let raw = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { continue }
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }
    return nil
}

func main() throws {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    if let helpIndex = rawArgs.firstIndex(where: { $0 == "--help" || $0 == "-h" }) {
        let command = helpIndex == 0 ? rawArgs.dropFirst().first : rawArgs.first
        printHelp(for: command)
        return
    }
    if rawArgs.contains("--version") || rawArgs.contains("-V") {
        printVersion()
        return
    }

    var args = effectiveCLIArguments(rawArgs)
    guard let command = args.first else {
        printHelp(for: nil)
        return
    }
    args.removeFirst()
    let client = SocketClient()

    switch command {
    case "help", "-h", "--help":
        print(usage())

    case "__browser-cookie-helper":
        try BrowserCookieHelperCommand.run(args: args)

    case "ping":
        let response = try client.request(method: AutomationMethod.appPing)
        let result = object(response.result)
        print("Conductor OK protocol=\(result["protocol"]?.intValue ?? 0) socket=\(result["socket"]?.stringValue ?? "")")

    case "status":
        let options = try parseOptions(args)
        let response = try client.request(method: AutomationMethod.appStatus)
        if options.has("json") {
            printResult(response, json: true)
        } else {
            printStatus(object(response.result))
        }

    case "usage":
        if wantsHelp(args) {
            print(usageCommandUsage())
            return
        }
        let options = try parseOptions(args)
        try runAsync {
            try await runUsage(options: options)
        }

    case "diagnose", "diagnostic":
        if wantsHelp(args) {
            print(diagnoseUsage())
            return
        }
        let options = try parseOptions(args)
        try runAsync {
            try await runDiagnose(options: options)
        }

    case "storage", "storage-footprint":
        if wantsHelp(args) {
            print(storageUsage())
            return
        }
        try runStorage(options: parseOptions(args))

    case "provider-status", "status-page":
        if wantsHelp(args) {
            print(providerStatusUsage())
            return
        }
        let options = try parseOptions(args)
        try runAsync {
            try await runProviderStatus(options: options)
        }

    case "cost":
        if wantsHelp(args) {
            print(costUsage())
            return
        }
        let options = try parseOptions(args)
        try runAsync {
            try await runCost(options: options)
        }

    case "cache":
        if wantsHelp(args) {
            print(cacheUsage())
            return
        }
        let cacheArgs = args
        try runAsync {
            try await runCache(args: cacheArgs)
        }

    case "config":
        if wantsHelp(args) {
            print(configUsage())
            return
        }
        try runConfig(args: args)

    case "serve":
        if wantsHelp(args) {
            print(serveUsage())
            return
        }
        let options = try parseOptions(args)
        let host = options.value("host") ?? "127.0.0.1"
        guard host == "127.0.0.1" else {
            throw CLIError("serve binds to 127.0.0.1 only")
        }
        let port = options.value("port").flatMap(Int.init) ?? 8080
        guard (1...65_535).contains(port) else {
            throw CLIError("--port must be 1...65535")
        }
        let refreshInterval = try doubleOption(options, "refresh-interval", default: 60)
        let requestTimeout = try doubleOption(options, "request-timeout", default: 30)
        try UsageHTTPServer.run(
            host: host,
            port: port,
            refreshInterval: refreshInterval,
            requestTimeout: requestTimeout)

    case "methods":
        let response = try client.request(method: AutomationMethod.appMethods)
        for item in array(response.result) {
            if let name = item.stringValue { print(name) }
        }

    case "raw":
        guard let method = args.first else { throw CLIError("raw requires METHOD") }
        let params = try paramsFromJSONString(args.dropFirst().first)
        printResult(try client.request(method: method, params: params), json: true)

    case "batch":
        try runBatch(client: client)

    case "workspace":
        guard let subcommand = args.first else { throw CLIError("workspace requires a subcommand") }
        let options = try parseOptions(Array(args.dropFirst()))
        switch subcommand {
        case "list", "ls":
            let response = try client.request(method: AutomationMethod.workspaceList)
            if options.has("json") {
                printResult(response, json: true)
            } else {
                printWorkspaces(array(response.result))
            }
        case "current":
            let response = try client.request(method: AutomationMethod.workspaceCurrent)
            if options.has("json") {
                printResult(response, json: true)
            } else {
                printWorkspaces([response.result ?? .null])
            }
        case "select":
            let workspace = try requiredValue(options, key: "workspace", positionalIndex: 0, label: "WORKSPACE")
            _ = try client.request(method: AutomationMethod.workspaceSelect, params: ["workspace": .string(workspace)])
        case "create", "new":
            let path = try requiredValue(options, key: "path", positionalIndex: 0, label: "PATH")
            var params: [String: JSONValue] = ["path": .string(path)]
            if let name = options.value("name") { params["name"] = .string(name) }
            let response = try client.request(method: AutomationMethod.workspaceCreate, params: params)
            if options.has("json") {
                printResult(response, json: true)
            } else {
                printWorkspaces([response.result ?? .null])
            }
        case "rename":
            let workspace = try requiredValue(options, key: "workspace", positionalIndex: 0, label: "WORKSPACE")
            let name = try requiredValue(options, key: "name", positionalIndex: 1, label: "NAME")
            _ = try client.request(method: AutomationMethod.workspaceRename, params: [
                "workspace": .string(workspace),
                "name": .string(name),
            ])
        case "close":
            let workspace = try requiredValue(options, key: "workspace", positionalIndex: 0, label: "WORKSPACE")
            _ = try client.request(method: AutomationMethod.workspaceClose, params: ["workspace": .string(workspace)])
        case "tree":
            var params: [String: JSONValue] = [:]
            if let workspace = options.value("workspace") ?? options.positional.first {
                params["workspace"] = .string(workspace)
            }
            printResult(try client.request(method: AutomationMethod.workspaceTree, params: params), json: true)
        case "status":
            let action = options.positional.first ?? "list"
            var params = workspaceScopedParams(options)
            switch action {
            case "set":
                params["key"] = .string(try requiredValue(options, key: "key", positionalIndex: 1, label: "KEY"))
                params["text"] = .string(try requiredJoinedText(options, key: "text", from: 2, label: "TEXT"))
                if let color = options.value("color") { params["color"] = .string(color) }
                if let icon = options.value("icon") { params["icon"] = .string(icon) }
                _ = try client.request(method: AutomationMethod.workspaceStatusSet, params: params)
            case "list", "ls":
                let response = try client.request(method: AutomationMethod.workspaceStatusList, params: params)
                if options.has("json") {
                    printResult(response, json: true)
                } else {
                    printStatusChips(array(response.result))
                }
            case "clear":
                if let key = options.value("key") ?? options.positional.dropFirst().first {
                    params["key"] = .string(key)
                }
                _ = try client.request(method: AutomationMethod.workspaceStatusClear, params: params)
            default:
                throw CLIError("Unknown workspace status subcommand: \(action)")
            }
        case "progress":
            let action = options.positional.first ?? "set"
            var params = workspaceScopedParams(options)
            switch action {
            case "set":
                let raw = try requiredValue(options, key: "value", positionalIndex: 1, label: "VALUE")
                guard let value = Double(raw) else { throw CLIError("Invalid VALUE: \(raw)") }
                params["value"] = .double(value)
                if let label = options.value("label") { params["label"] = .string(label) }
                _ = try client.request(method: AutomationMethod.workspaceProgressSet, params: params)
            case "clear":
                _ = try client.request(method: AutomationMethod.workspaceProgressClear, params: params)
            default:
                throw CLIError("Unknown workspace progress subcommand: \(action)")
            }
        case "log":
            let action = options.positional.first ?? "list"
            var params = workspaceScopedParams(options)
            switch action {
            case "append", "add":
                params["text"] = .string(try requiredJoinedText(options, key: "text", from: 1, label: "TEXT"))
                if let level = options.value("level") { params["level"] = .string(level) }
                if let source = options.value("source") { params["source"] = .string(source) }
                _ = try client.request(method: AutomationMethod.workspaceLogAppend, params: params)
            case "list", "ls":
                if let limit = options.value("limit").flatMap(Int.init) { params["limit"] = .int(limit) }
                let response = try client.request(method: AutomationMethod.workspaceLogList, params: params)
                if options.has("json") {
                    printResult(response, json: true)
                } else {
                    printWorkspaceLogs(array(response.result))
                }
            case "clear":
                _ = try client.request(method: AutomationMethod.workspaceLogClear, params: params)
            default:
                throw CLIError("Unknown workspace log subcommand: \(action)")
            }
        default:
            throw CLIError("Unknown workspace subcommand: \(subcommand)")
        }

    case "tab":
        guard let subcommand = args.first else { throw CLIError("tab requires a subcommand") }
        let options = try parseOptions(Array(args.dropFirst()))
        switch subcommand {
        case "list", "ls":
            var params: [String: JSONValue] = [:]
            if let workspace = options.value("workspace") { params["workspace"] = .string(workspace) }
            let response = try client.request(method: AutomationMethod.tabList, params: params)
            if options.has("json") {
                printResult(response, json: true)
            } else {
                printTabs(array(response.result))
            }
        case "select":
            let tab = try requiredValue(options, key: "tab", positionalIndex: 0, label: "TAB")
            var params: [String: JSONValue] = ["tab": .string(tab)]
            if let workspace = options.value("workspace") { params["workspace"] = .string(workspace) }
            _ = try client.request(method: AutomationMethod.tabSelect, params: params)
        case "rename":
            let tab = try requiredValue(options, key: "tab", positionalIndex: 0, label: "TAB")
            let title = try requiredValue(options, key: "title", positionalIndex: 1, label: "TITLE")
            var params: [String: JSONValue] = ["tab": .string(tab), "title": .string(title)]
            if let workspace = options.value("workspace") { params["workspace"] = .string(workspace) }
            _ = try client.request(method: AutomationMethod.tabRename, params: params)
        case "close":
            let tab = try requiredValue(options, key: "tab", positionalIndex: 0, label: "TAB")
            var params: [String: JSONValue] = ["tab": .string(tab)]
            if let workspace = options.value("workspace") { params["workspace"] = .string(workspace) }
            _ = try client.request(method: AutomationMethod.tabClose, params: params)
        default:
            throw CLIError("Unknown tab subcommand: \(subcommand)")
        }

    case "pane":
        guard let subcommand = args.first else { throw CLIError("pane requires a subcommand") }
        let options = try parseOptions(Array(args.dropFirst()))
        switch subcommand {
        case "list", "ls":
            let response = try client.request(method: AutomationMethod.paneList, params: [:])
            if options.has("json") {
                printResult(response, json: true)
            } else {
                for item in array(response.result) {
                    let pane = object(item)
                    let active = pane["active"]?.boolValue == true ? "*" : " "
                    let id = pane["id"]?.stringValue ?? "-"
                    let agent = pane["agent"]?.stringValue ?? "-"
                    let cwd = pane["cwd"]?.stringValue ?? ""
                    let title = pane["title"]?.stringValue ?? ""
                    print("\(active) \(id)  agent=\(agent)  \(title)  \(cwd)")
                }
            }
        case "create", "new":
            var params: [String: JSONValue] = [:]
            if let cwd = options.value("cwd") { params["cwd"] = .string(cwd) }
            printResult(try client.request(method: AutomationMethod.paneCreate, params: params), json: options.has("json"))
        case "split":
            var params: [String: JSONValue] = [:]
            if let pane = options.value("pane") ?? options.positional.first { params["pane"] = .string(pane) }
            if let direction = options.value("direction") { params["direction"] = .string(direction) }
            if let cwd = options.value("cwd") { params["cwd"] = .string(cwd) }
            printResult(try client.request(method: AutomationMethod.paneSplit, params: params), json: options.has("json"))
        case "focus":
            guard let pane = options.positional.first else { throw CLIError("pane focus requires PANE") }
            _ = try client.request(method: AutomationMethod.paneFocus, params: ["pane": .string(pane)])
        case "close":
            var params: [String: JSONValue] = [:]
            if let pane = options.value("pane") ?? options.positional.first { params["pane"] = .string(pane) }
            _ = try client.request(method: AutomationMethod.paneClose, params: params)
        default:
            throw CLIError("Unknown pane subcommand: \(subcommand)")
        }

    case "screen":
        let options = try parseOptions(args)
        var params: [String: JSONValue] = [:]
        if let pane = options.value("pane") ?? options.positional.first { params["pane"] = .string(pane) }
        if options.has("scrollback") { params["scrollback"] = .bool(true) }
        let response = try client.request(method: AutomationMethod.paneRead, params: params)
        print(object(response.result)["text"]?.stringValue ?? "")

    case "send":
        let options = try parseOptions(args)
        if options.has("stdin"), options.value("text") != nil || !options.positional.isEmpty {
            throw CLIError("send accepts either TEXT or --stdin, not both")
        }
        let text: String
        if options.has("stdin") {
            text = try readStdin()
        } else {
            text = options.value("text") ?? options.positional.joined(separator: " ")
        }
        guard !text.isEmpty else { throw CLIError("send requires TEXT") }
        var params: [String: JSONValue] = [
            "text": .string(text),
            "submit": .bool(!options.has("no-submit")),
        ]
        if let pane = options.value("pane") { params["pane"] = .string(pane) }
        _ = try client.request(method: AutomationMethod.agentSend, params: params)

    case "run":
        let options = try parseOptions(args)
        guard let agent = options.positional.first ?? options.value("agent") else {
            throw CLIError("run requires AGENT")
        }
        let timeout = try doubleOption(options, "timeout", default: 600)
        let poll = try doubleOption(options, "poll", default: 2)
        guard poll > 0 else { throw CLIError("--poll must be greater than 0") }
        if options.has("stdin"), options.value("prompt") != nil {
            throw CLIError("run accepts either --prompt or --stdin, not both")
        }
        var params: [String: JSONValue] = [
            "agent": .string(agent),
            "submit": .bool(!options.has("no-submit")),
        ]
        if let command = options.value("command") { params["command"] = .string(command) }
        if let cwd = options.value("cwd") { params["cwd"] = .string(cwd) }
        if options.has("stdin") {
            params["prompt"] = .string(try readStdin())
        } else if let prompt = options.value("prompt") {
            params["prompt"] = .string(prompt)
        }
        let response = try client.request(method: AutomationMethod.agentRun, params: params)
        let result = object(response.result)
        let job = result["jobId"]?.stringValue ?? result["pane"]?.stringValue
        if options.has("wait") {
            guard let job, !job.isEmpty else {
                throw CLIError("agent.run did not return a jobId")
            }
            let completed = try waitForAgentResult(client: client, job: job, timeout: timeout, poll: poll)
            if options.has("json") {
                printResult(completed, json: true)
            } else {
                printAgentResult(object(completed.result))
            }
            return
        }
        if options.has("json") {
            printResult(response, json: true)
        } else {
            print("pane=\(result["pane"]?.stringValue ?? "-") agent=\(result["agent"]?.stringValue ?? agent)")
        }

    case "agent":
        guard let subcommand = args.first else { throw CLIError("agent requires a subcommand") }
        let options = try parseOptions(Array(args.dropFirst()))
        let job = options.value("job") ?? options.value("jobId") ?? options.value("pane") ?? options.positional.first
        var params: [String: JSONValue] = [:]
        if let job { params["job"] = .string(job) }
        switch subcommand {
        case "status":
            let response = try client.request(method: AutomationMethod.agentStatus, params: params)
            if options.has("json") {
                printResult(response, json: true)
            } else {
                printAgentStatus(object(response.result))
            }
        case "wait":
            let timeout = try doubleOption(options, "timeout", default: 600)
            let poll = try doubleOption(options, "poll", default: 2)
            guard poll > 0 else { throw CLIError("--poll must be greater than 0") }
            let completed = try waitForAgentResult(client: client, job: job, timeout: timeout, poll: poll)
            if options.has("json") {
                printResult(completed, json: true)
            } else {
                printAgentResult(object(completed.result))
            }
        case "result":
            let response = try client.request(method: AutomationMethod.agentResult, params: params)
            if options.has("json") {
                printResult(response, json: true)
            } else {
                printAgentResult(object(response.result))
            }
        default:
            throw CLIError("Unknown agent subcommand: \(subcommand)")
        }

    case "activity":
        let options = try parseOptions(args)
        let limit = options.value("limit").flatMap(Int.init) ?? 20
        let response = try client.request(method: AutomationMethod.activityList, params: ["limit": .int(limit)])
        if options.has("json") {
            printResult(response, json: true)
        } else {
            printActivity(array(response.result))
        }

    case "events":
        let options = try parseOptions(args)
        let limit = options.value("limit").flatMap(Int.init) ?? 20
        let interval = max(0.5, options.value("interval").flatMap(Double.init) ?? 2.0)
        var seen = Set<String>()
        while true {
            let response = try client.request(method: AutomationMethod.eventsRecent, params: ["limit": .int(limit)])
            for event in array(response.result).reversed() {
                let item = object(event)
                guard let id = item["id"]?.stringValue, !seen.contains(id) else { continue }
                seen.insert(id)
                print(options.has("jsonl") ? jsonLine(event) : pretty(event))
                fflush(stdout)
            }
            Thread.sleep(forTimeInterval: interval)
        }

    case "watch":
        let options = try parseOptions(args)
        let interval = max(0.5, options.value("interval").flatMap(Double.init) ?? 2.0)
        var seen = Set<String>()
        while true {
            let response = try client.request(method: AutomationMethod.activityList, params: ["limit": .int(20)])
            let entries = array(response.result)
            for entry in entries.reversed() {
                let item = object(entry)
                guard let id = item["id"]?.stringValue, !seen.contains(id) else { continue }
                seen.insert(id)
                if options.has("jsonl") {
                    print(jsonLine(entry))
                } else {
                    printActivity([entry])
                }
                fflush(stdout)
            }
            Thread.sleep(forTimeInterval: interval)
        }

    case "bridge":
        let options = try parseOptions(args)
        let host = options.value("host") ?? "127.0.0.1"
        let port = options.value("port").flatMap(Int.init) ?? 17_373
        let interval = max(0.5, options.value("interval").flatMap(Double.init) ?? 1.0)
        try BridgeServer.run(host: host, port: port, interval: interval)

    default:
        throw CLIError("Unknown command: \(command)\n\n\(usage())")
    }
}

func doubleOption(_ options: Options, _ key: String, default defaultValue: Double) throws -> Double {
    guard let raw = options.value(key) else { return defaultValue }
    guard let value = Double(raw), value.isFinite, value >= 0 else {
        throw CLIError("Invalid --\(key): \(raw)")
    }
    return value
}

func optionalPositiveDoubleOption(_ options: Options, _ key: String) throws -> Double? {
    guard let raw = options.value(key) else { return nil }
    guard let value = Double(raw), value.isFinite, value > 0 else {
        throw CLIError("--\(key) must be greater than 0")
    }
    return value
}

func runUsage(options: Options) async throws {
    let selection = options.value("provider") ?? options.positional.first
    let store = CLIConfigStore()
    let config = try store.load()
    let entries = try UsageProviderCatalog.entries(for: selection, config: config)
    let source = try usageSource(options)
    let webTimeout = try optionalPositiveDoubleOption(options, "web-timeout")
    let webDebugDumpHTML = options.has("web-debug-dump-html")
    let accountSelection = try usageAccountSelection(options)
    let reports = try await fetchUsageReports(
        entries: entries,
        source: source,
        config: config,
        configStore: store,
        accountSelection: accountSelection,
        includeStatus: options.has("status"),
        webTimeout: webTimeout,
        webDebugDumpHTML: webDebugDumpHTML)
    switch try usageFormat(options) {
    case "text":
        print(UsageCLITextRenderer.render(
            reports,
            includeCredits: !options.has("no-credits"),
            hidePersonalInfo: config.usage.hidePersonalInfo))
    case "json":
        try printUsageJSON(reports, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runProviderStatus(options: Options) async throws {
    let selection = options.value("provider") ?? options.positional.first
    let config = try CLIConfigStore().load()
    let entries = try UsageProviderCatalog.entries(for: selection, config: config)
    let snapshots = try await UsageProviderStatusReporter.fetchUnlessCancelled(entries: entries)
    switch try usageFormat(options) {
    case "text":
        print(renderProviderStatuses(snapshots))
    case "json":
        try printEncodableJSON(snapshots, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runDiagnose(options: Options) async throws {
    let selection = options.value("provider") ?? options.positional.first
    let source = try usageSource(options)
    let config = try CLIConfigStore().load()
    let entries = try UsageProviderCatalog.entries(for: selection, config: config)
    let accountSelection = try usageAccountSelection(options)
    let includeStorage = options.has("storage") || config.usage.providerStorageFootprintsEnabled
    let diagnostics = try await fetchUsageDiagnostics(
        entries: entries,
        source: source,
        config: config,
        accountSelection: accountSelection,
        includeStorage: includeStorage)

    switch try usageFormat(options) {
    case "text":
        print(UsageDiagnosticRedactor.redact(UsageProviderDiagnosticTextRenderer.render(diagnostics)))
    case "json":
        try printDiagnosticJSON(diagnostics, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

struct UsageStorageCLIReport: Codable {
    let provider: String
    let displayName: String
    let scannedAt: Date
    let storage: UsageProviderDiagnosticStorageSummary?
}

func runStorage(options: Options) throws {
    let selection = options.value("provider") ?? options.positional.first ?? "all"
    let config = try CLIConfigStore().load()
    let entries = try UsageProviderCatalog.entries(for: selection, config: config)
    let reports = storageReports(entries: entries, config: config)

    switch try usageFormat(options) {
    case "text":
        print(renderStorageReports(reports))
    case "json":
        try printStorageJSON(reports, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func storageReports(entries: [UsageProviderEntry], config: AppConfig) -> [UsageStorageCLIReport] {
    let scannedAt = Date()
    let footprints = ProviderStorageFootprintLoader.scanProviders(entries, config: config)
    return entries.map { entry in
        UsageStorageCLIReport(
            provider: entry.id,
            displayName: entry.name,
            scannedAt: scannedAt,
            storage: footprints[entry.id].map { UsageProviderDiagnosticStorageSummary(footprint: $0) })
    }
}

func renderStorageReports(_ reports: [UsageStorageCLIReport]) -> String {
    reports.map(renderStorageReport(_:)).joined(separator: "\n\n")
}

func renderStorageReport(_ report: UsageStorageCLIReport) -> String {
    var lines = ["\(report.displayName) (\(report.provider))"]
    guard let storage = report.storage else {
        lines.append("  storage: not tracked")
        return lines.joined(separator: "\n")
    }
    lines.append("  storage: \(storage.hasLocalData ? storage.byteCountText : "no local data")")
    lines.append("  paths: \(storage.pathCount) existing, \(storage.missingPathCount) missing, \(storage.unreadablePathCount) unreadable")
    lines.append(contentsOf: storagePathLines(label: "path", paths: storage.paths, totalCount: storage.pathCount))
    lines.append(contentsOf: storagePathLines(label: "missing", paths: storage.missingPaths, totalCount: storage.missingPathCount))
    lines.append(contentsOf: storagePathLines(label: "unreadable", paths: storage.unreadablePaths, totalCount: storage.unreadablePathCount))
    for component in storage.topComponents.prefix(5) {
        lines.append("  component: \(component.name) \(component.byteCountText) - \(component.path)")
    }
    for recommendation in storage.cleanupRecommendations.prefix(3) {
        lines.append("  cleanup: \(recommendation.title) \(recommendation.byteCountText) - \(recommendation.path)")
        if !recommendation.consequence.isEmpty {
            lines.append("    consequence: \(recommendation.consequence)")
        }
    }
    return UsageDiagnosticRedactor.redact(lines.joined(separator: "\n"))
}

func storagePathLines(label: String, paths: [String], totalCount: Int, limit: Int = 3) -> [String] {
    guard totalCount > 0 else { return [] }
    var lines = paths.prefix(limit).map { "  \(label): \($0)" }
    if totalCount > limit {
        lines.append("  \(label): ... (+\(totalCount - limit) more)")
    }
    return lines
}

func renderProviderStatuses(_ snapshots: [UsageProviderStatusSnapshot]) -> String {
    snapshots.map { snapshot in
        var lines: [String] = []
        lines.append("\(snapshot.name) (\(snapshot.provider))")
        lines.append("  status: \(snapshot.label)\(providerStatusDescriptionSuffix(snapshot))")
        lines.append("  source: \(snapshot.source)")
        if let updatedAt = snapshot.updatedAt {
            lines.append("  updated: \(ISO8601DateFormatter().string(from: updatedAt))")
        }
        if let url = snapshot.url {
            lines.append("  url: \(url)")
        }
        if let error = snapshot.error, !error.isEmpty {
            lines.append("  error: \(error)")
        }
        return lines.joined(separator: "\n")
    }
    .joined(separator: "\n\n")
}

func providerStatusDescriptionSuffix(_ snapshot: UsageProviderStatusSnapshot) -> String {
    guard let description = snapshot.description, !description.isEmpty else { return "" }
    return " - \(description)"
}

struct UsageAccountSelection {
    let label: String?
    let index: Int?
    let allAccounts: Bool

    var usesOverride: Bool {
        label != nil || index != nil || allAccounts
    }
}

func usageAccountSelection(_ options: Options) throws -> UsageAccountSelection {
    let label = options.value("account")?.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawIndex = options.value("account-index")
    let index: Int?
    if let rawIndex {
        guard let parsed = Int(rawIndex), parsed > 0 else {
            throw CLIError("--account-index must be a positive integer")
        }
        index = parsed - 1
    } else {
        index = nil
    }
    let allAccounts = options.has("all-accounts")
    if allAccounts, (label?.isEmpty == false || index != nil) {
        throw CLIError("--all-accounts cannot be combined with --account or --account-index")
    }
    return UsageAccountSelection(
        label: label?.isEmpty == false ? label : nil,
        index: index,
        allAccounts: allAccounts)
}

func fetchUsageReports(
    entries: [UsageProviderEntry],
    source: String,
    config: AppConfig,
    configStore: CLIConfigStore? = nil,
    accountSelection: UsageAccountSelection,
    includeStatus: Bool = false,
    webTimeout: Double? = nil,
    webDebugDumpHTML: Bool = false) async throws -> [UsageCLIReport]
{
    try Task.checkCancellation()
    if accountSelection.usesOverride, entries.count != 1 {
        throw CLIError("account selection requires a single provider.")
    }
    let statusesByProvider: [String: UsageProviderStatusSnapshot]
    if includeStatus {
        let statuses = try await UsageProviderStatusReporter.fetchUnlessCancelled(entries: entries)
        try Task.checkCancellation()
        statusesByProvider = statuses.reduce(into: [:]) { result, status in
            result[status.provider] = status
        }
    } else {
        statusesByProvider = [:]
    }
    var reports: [UsageCLIReport] = []
    for entry in entries {
        try Task.checkCancellation()
        let accounts = try resolvedUsageAccounts(entry: entry, config: config, selection: accountSelection)
        for account in accounts {
            try Task.checkCancellation()
            if source != "auto", !entry.supportsSourceMode(source) {
                reports.append(unsupportedUsageSourceReport(
                    entry: entry,
                    source: source,
                    account: account,
                    status: statusesByProvider[entry.id]))
                continue
            }
            let patch = usageEnvironmentPatch(
                providerID: entry.id,
                config: config,
                account: account,
                source: source,
                webTimeout: webTimeout,
                webDebugDumpHTML: webDebugDumpHTML)
            var fetchPatch = patch
            let tokenUpdateSidecar = tokenAccountUpdateSidecar(providerID: entry.id, account: account)
            if let tokenUpdateSidecar {
                fetchPatch.set[AntigravityUsageFetcher.tokenAccountUpdatePathEnvironmentKey] =
                    tokenUpdateSidecar.url.path
            }
            let fetched: UsageCLIReport?
            do {
                fetched = try await withTemporaryEnvironmentThrowing(fetchPatch) {
                    let fetched = try await UsageProviderRuntimeContext.withForcedWebRefresh(for: entry.id) {
                        try await UsageCLIReporter.fetchUnlessCancelled(
                            entries: [entry],
                            source: source,
                            weeklyProgressWorkDays: config.usage.weeklyProgressWorkDays,
                            statusesByProvider: statusesByProvider).first
                    }
                    guard let fetched else { return nil }
                    let accountReport = reportWithAccount(fetched, providerID: entry.id, account: account)
                    let dashboardReport = reportWithCachedOpenAIDashboard(accountReport, providerID: entry.id)
                    return await reportWithCodexHistoricalPace(dashboardReport, providerID: entry.id)
                }
                try persistTokenAccountUpdateIfNeeded(
                    sidecar: tokenUpdateSidecar,
                    providerID: entry.id,
                    account: account,
                    configStore: configStore,
                    markUsed: fetched != nil)
                tokenUpdateSidecar?.cleanup()
            } catch {
                try? persistTokenAccountUpdateIfNeeded(
                    sidecar: tokenUpdateSidecar,
                    providerID: entry.id,
                    account: account,
                    configStore: configStore)
                tokenUpdateSidecar?.cleanup()
                throw error
            }
            try Task.checkCancellation()
            guard let fetched else { continue }
            reports.append(fetched)
        }
    }
    return reports
}

func unsupportedUsageSourceReport(
    entry: UsageProviderEntry,
    source: String,
    account: UsageProviderTokenAccount?,
    status: UsageProviderStatusSnapshot?) -> UsageCLIReport
{
    let error = unsupportedUsageSourceError(entry: entry, source: source)
    let configured = entry.isConfigured()
    let repairActions = UsageProviderRepairActions.actions(
        providerID: entry.id,
        providerName: entry.name,
        configured: configured,
        error: error,
        source: source,
        hasStatusPage: entry.statusURL != nil,
        statusURL: entry.statusURL)
    let cacheAccountKey = account.map {
        UsageAccountCacheKey.tokenAccountKey(
            providerID: entry.id,
            account: $0,
            usageAccountLabel: nil)
    }
    return UsageCLIReport(
        provider: entry.id,
        name: entry.name,
        configured: configured,
        source: source,
        account: account?.label,
        cacheAccountKey: cacheAccountKey,
        status: status,
        usage: nil,
        error: UsageCLIError(error),
        repairActions: repairActions)
}

func fetchUsageDiagnostics(
    entries: [UsageProviderEntry],
    source: String,
    config: AppConfig,
    accountSelection: UsageAccountSelection,
    includeStorage: Bool = false) async throws -> [UsageProviderDiagnosticExport]
{
    try Task.checkCancellation()
    if accountSelection.usesOverride, entries.count != 1 {
        throw CLIError("account selection requires a single provider.")
    }
    var diagnostics: [UsageProviderDiagnosticExport] = []
    for entry in entries {
        try Task.checkCancellation()
        if source != "auto", !entry.supportsSourceMode(source) {
            throw unsupportedUsageSourceError(entry: entry, source: source)
        }
        let accounts = try resolvedUsageAccounts(entry: entry, config: config, selection: accountSelection)
        for account in accounts {
            try Task.checkCancellation()
            let patch = usageEnvironmentPatch(providerID: entry.id, config: config, account: account, source: source)
            let diagnostic = try await withTemporaryEnvironmentThrowing(patch) {
                let storageFootprint = includeStorage
                    ? ProviderStorageFootprintLoader.scanProviders([entry], config: config)[entry.id]
                    : nil
                return try await UsageProviderDiagnostics.diagnoseUnlessCancelled(
                    entry: entry,
                    source: source,
                    config: config,
                    selectedAccount: account,
                    storageFootprint: storageFootprint,
                    environment: ProcessInfo.processInfo.environment)
            }
            try Task.checkCancellation()
            diagnostics.append(diagnostic)
        }
    }
    return diagnostics
}

func unsupportedUsageSourceError(entry: UsageProviderEntry, source: String) -> CLIError {
    CLIError("Source \(source) is not supported for \(entry.id). Expected one of: \(entry.sourceModes.joined(separator: ", ")).")
}

func resolvedUsageAccounts(
    entry: UsageProviderEntry,
    config: AppConfig,
    selection: UsageAccountSelection) throws -> [UsageProviderTokenAccount?]
{
    let support = UsageProviderConfigCapabilities.supportsTokenAccounts(entry.id)
    let data = config.usage.providers[entry.id]?.tokenAccounts
    let configuredAccounts = data?.accounts ?? []
    let discoveredAccounts = entry.id == "codex"
        ? CodexManagedAccountDiscovery.tokenAccounts()
        : []
    let accounts = entry.id == "codex"
        ? CodexActiveAccountResolver.mergedAccounts(configured: configuredAccounts, discovered: discoveredAccounts)
        : configuredAccounts

    if selection.usesOverride, !support {
        throw CLIError("\(entry.id) does not support token accounts.")
    }
    guard !accounts.isEmpty else {
        if selection.usesOverride {
            throw CLIError("No token accounts configured for \(entry.id).")
        }
        return [nil]
    }

    if selection.allAccounts {
        return accounts.map { Optional($0) }
    }
    if let label = selection.label {
        let normalized = label.lowercased()
        if let match = accounts.first(where: {
            $0.label.lowercased() == normalized ||
                $0.id.uuidString.lowercased() == normalized ||
                ($0.externalIdentifier?.lowercased() == normalized)
        }) {
            return [match]
        }
        throw CLIError("No token account labeled '\(label)' for \(entry.id).")
    }
    if let index = selection.index {
        guard index >= 0, index < accounts.count else {
            throw CLIError("Token account index \(index + 1) out of range for \(entry.id) (1-\(accounts.count)).")
        }
        return [accounts[index]]
    }
    if selection.usesOverride {
        return [nil]
    }
    if entry.id == "codex" {
        let resolution = CodexActiveAccountResolver.resolveDefaultAccount(
            configured: data,
            discoveredAccounts: discoveredAccounts)
        if let account = resolution.resolvedAccount {
            return [account]
        }
        if configuredAccounts.isEmpty {
            return [nil]
        }
    }
    return [accounts[data?.clampedActiveIndex() ?? 0]]
}

func usageEnvironmentPatch(
    providerID: String,
    config: AppConfig,
    account: UsageProviderTokenAccount?,
    source: String,
    webTimeout: Double? = nil,
    webDebugDumpHTML: Bool = false) -> UsageProviderEnvironmentPatch
{
    var patch = UsageProviderEnvironmentPatch()
    if let providerConfig = config.usage.providers[providerID] {
        patch.merge(UsageProviderConfigCapabilities.environmentPatch(providerID: providerID, config: providerConfig))
    }
    patch.merge(UsageProviderEnvironmentPatch(
        set: Dictionary(uniqueKeysWithValues: UsageProviderConfigCapabilities.conductorSourceEnvironmentNames(providerID).map { ($0, source) })))
    if providerID == "codex", let webTimeout {
        patch.set["CONDUCTOR_USAGE_CODEX_WEB_TIMEOUT"] = String(webTimeout)
    }
    if providerID == "codex", webDebugDumpHTML {
        patch.set["CONDUCTOR_USAGE_CODEX_WEB_DEBUG_DUMP_HTML"] = "1"
    }
    if let account {
        patch.merge(UsageProviderConfigCapabilities.environmentPatch(providerID: providerID, account: account))
    }
    return patch
}

struct TokenAccountUpdateSidecar {
    let url: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

func tokenAccountUpdateSidecar(
    providerID: String,
    account: UsageProviderTokenAccount?) -> TokenAccountUpdateSidecar?
{
    guard providerID == "antigravity", account != nil else { return nil }
    let filename = "conductor-\(providerID)-token-update-\(UUID().uuidString).json"
    return TokenAccountUpdateSidecar(url: FileManager.default.temporaryDirectory.appendingPathComponent(filename))
}

func persistTokenAccountUpdateIfNeeded(
    sidecar: TokenAccountUpdateSidecar?,
    providerID: String,
    account: UsageProviderTokenAccount?,
    configStore: CLIConfigStore?,
    markUsed: Bool = false) throws
{
    let updatedToken: String?
    if let sidecar, FileManager.default.fileExists(atPath: sidecar.url.path) {
        let token = try String(contentsOf: sidecar.url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        updatedToken = token.isEmpty ? nil : token
    } else {
        updatedToken = nil
    }

    guard markUsed || updatedToken != nil,
          let account,
          let configStore
    else { return }

    var config = try configStore.load()
    guard var providerConfig = config.usage.providers[providerID],
          var tokenAccounts = providerConfig.tokenAccounts,
          let index = tokenAccounts.accounts.firstIndex(where: { $0.id == account.id })
    else {
        return
    }

    var didChange = false
    if let updatedToken, tokenAccounts.accounts[index].token != updatedToken {
        tokenAccounts.accounts[index].token = updatedToken
        didChange = true
    }
    if markUsed {
        tokenAccounts.markAccountUsed(id: account.id)
        didChange = true
    }
    guard didChange else { return }
    providerConfig.tokenAccounts = tokenAccounts
    config.usage.providers[providerID] = providerConfig
    try configStore.save(config)
}

func reportWithAccount(
    _ report: UsageCLIReport,
    providerID: String,
    account: UsageProviderTokenAccount?) -> UsageCLIReport
{
    let cacheAccountKey = account.map {
        UsageAccountCacheKey.tokenAccountKey(
            providerID: providerID,
            account: $0,
            usageAccountLabel: report.usage?.accountLabel)
    } ?? UsageAccountCacheKey.snapshotDerivedKey(
        providerID: providerID,
        usageAccountLabel: report.usage?.accountLabel ?? report.account)

    if let usage = report.usage {
        UsageSnapshotHydrationStore.save(
            providerID: providerID,
            accountKey: cacheAccountKey,
            snapshot: usage.usageSnapshot,
            recordedAt: report.fetchedAt,
            source: "cli:\(report.source)")
    }

    return UsageCLIReport(
        provider: report.provider,
        name: report.name,
        configured: report.configured,
        source: report.source,
        fetchedAt: report.fetchedAt,
        account: account?.displayName,
        cacheAccountKey: cacheAccountKey,
        status: report.status,
        usage: report.usage,
        openaiDashboard: report.openaiDashboard,
        openaiCreditsHistory: report.openaiCreditsHistory
            ?? UsageCLIReporter.openAICreditsHistory(
                providerID: providerID,
                reportAccount: account?.displayName ?? report.account,
                usageAccountLabel: report.usage?.accountLabel,
                dashboard: report.openaiDashboard),
        error: report.error,
        repairActions: report.repairActions)
}

func reportWithCachedOpenAIDashboard(_ report: UsageCLIReport, providerID: String) -> UsageCLIReport {
    guard providerID == "codex", report.error == nil else { return report }
    let dashboard = OpenAIDashboardCacheStore.reusableSnapshotForCLI(
        reportAccount: report.account,
        usageAccountLabel: report.usage?.accountLabel,
        sourceLabel: report.source)
    guard dashboard != nil else { return report }
    return UsageCLIReport(
        provider: report.provider,
        name: report.name,
        configured: report.configured,
        source: report.source,
        fetchedAt: report.fetchedAt,
        account: report.account,
        cacheAccountKey: report.cacheAccountKey,
        status: report.status,
        usage: report.usage,
        openaiDashboard: dashboard,
        openaiCreditsHistory: report.openaiCreditsHistory
            ?? UsageCLIReporter.openAICreditsHistory(
                providerID: providerID,
                reportAccount: report.account,
                usageAccountLabel: report.usage?.accountLabel,
                dashboard: dashboard),
        error: report.error,
        repairActions: report.repairActions)
}

func reportWithCodexHistoricalPace(_ report: UsageCLIReport, providerID: String) async -> UsageCLIReport {
    guard providerID == "codex",
          report.error == nil,
          let usage = report.usage
    else {
        return report
    }

    let store = HistoricalUsageHistoryStore()
    var dataset: CodexHistoricalDataset?
    if let weekly = usage.codexWeeklyRateWindow {
        dataset = await store.recordCodexWeekly(
            window: weekly,
            sampledAt: usage.updatedAt,
            accountKey: report.cacheAccountKey)
        if let dashboard = report.openaiDashboard,
           let backfilled = await backfillCodexHistoricalFromDashboard(
               dashboard,
               store: store,
               fallbackWeekly: weekly,
               fallbackUpdatedAt: usage.updatedAt,
               accountKey: report.cacheAccountKey)
        {
            dataset = backfilled
        }
    }
    if dataset == nil {
        dataset = await store.loadCodexDataset(accountKey: report.cacheAccountKey)
    }
    guard let dataset else { return report }

    return UsageCLIReport(
        provider: report.provider,
        name: report.name,
        configured: report.configured,
        source: report.source,
        fetchedAt: report.fetchedAt,
        account: report.account,
        cacheAccountKey: report.cacheAccountKey,
        status: report.status,
        usage: usage.applyingCodexHistoricalPace(
            dataset: dataset,
            now: usage.updatedAt),
        openaiDashboard: report.openaiDashboard,
        openaiCreditsHistory: report.openaiCreditsHistory,
        error: report.error,
        repairActions: report.repairActions)
}

func backfillCodexHistoricalFromDashboard(
    _ dashboard: OpenAIDashboardSnapshot,
    store: HistoricalUsageHistoryStore,
    fallbackWeekly: RateWindow,
    fallbackUpdatedAt: Date,
    accountKey: String?)
    async -> CodexHistoricalDataset?
{
    guard !dashboard.usageBreakdown.isEmpty else { return nil }
    if let dashboardWeekly = dashboard.secondaryLimit,
       dashboardWeekly.resetsAt != nil,
       dashboardWeekly.windowMinutes != nil
    {
        return await store.backfillCodexWeeklyFromUsageBreakdown(
            dashboard.usageBreakdown,
            referenceWindow: dashboardWeekly,
            now: dashboard.updatedAt,
            accountKey: accountKey)
    }

    let fallbackTolerance: TimeInterval = 5 * 60
    guard abs(fallbackUpdatedAt.timeIntervalSince(dashboard.updatedAt)) <= fallbackTolerance else {
        return nil
    }
    return await store.backfillCodexWeeklyFromUsageBreakdown(
        dashboard.usageBreakdown,
        referenceWindow: fallbackWeekly,
        now: fallbackUpdatedAt,
        accountKey: accountKey)
}

func withTemporaryEnvironment<T>(
    _ patch: UsageProviderEnvironmentPatch,
    operation: () async -> T) async -> T
{
    await UsageEnvironmentMutationLock.shared.withAsyncLock {
        let restore = applyTemporaryEnvironment(patch)
        let result = await operation()
        restoreTemporaryEnvironment(restore)
        return result
    }
}

func withTemporaryEnvironmentThrowing<T>(
    _ patch: UsageProviderEnvironmentPatch,
    operation: () async throws -> T) async throws -> T
{
    try await UsageEnvironmentMutationLock.shared.withAsyncLock {
        let restore = applyTemporaryEnvironment(patch)
        do {
            let result = try await operation()
            restoreTemporaryEnvironment(restore)
            return result
        } catch {
            restoreTemporaryEnvironment(restore)
            throw error
        }
    }
}

struct TemporaryEnvironmentRestore {
    var values: [String: String] = [:]
    var missing: Set<String> = []

    var recordedNames: Set<String> {
        Set(values.keys).union(missing)
    }
}

func applyTemporaryEnvironment(_ patch: UsageProviderEnvironmentPatch) -> TemporaryEnvironmentRestore {
    var restore = TemporaryEnvironmentRestore()
    for name in patch.unset where !name.isEmpty {
        recordEnvironmentValue(name, into: &restore)
        unsetenv(name)
    }
    for (name, value) in patch.set where !name.isEmpty {
        recordEnvironmentValue(name, into: &restore)
        setenv(name, value, 1)
    }
    return restore
}

func recordEnvironmentValue(_ name: String, into restore: inout TemporaryEnvironmentRestore) {
    guard !restore.recordedNames.contains(name) else { return }
    if let value = getenv(name) {
        restore.values[name] = String(cString: value)
    } else {
        restore.missing.insert(name)
    }
}

func restoreTemporaryEnvironment(_ restore: TemporaryEnvironmentRestore) {
    for (name, value) in restore.values {
        setenv(name, value, 1)
    }
    for name in restore.missing {
        unsetenv(name)
    }
}

func usageFormat(_ options: Options) throws -> String {
    if options.has("json") || options.has("json-only") { return "json" }
    let format = options.value("format")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "text"
    guard format == "text" || format == "json" else {
        throw CLIError("--format must be text or json")
    }
    return format
}

func usageSource(_ options: Options) throws -> String {
    let source = (options.has("web") ? "web" : options.value("source") ?? "auto")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    let supported = Set(["auto", "web", "cli", "oauth", "api"])
    guard supported.contains(source) else {
        throw CLIError("--source must be auto, web, cli, oauth, or api")
    }
    return source
}

func printUsageJSON(_ reports: [UsageCLIReport], pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
    let data = try encoder.encode(reports)
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("Could not encode usage JSON")
    }
    print(text)
}

func printDiagnosticJSON(_ diagnostics: [UsageProviderDiagnosticExport], pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data: Data
    if diagnostics.count == 1, let diagnostic = diagnostics.first {
        data = try encoder.encode(diagnostic)
    } else {
        data = try encoder.encode(UsageProviderDiagnosticBatchExport(diagnostics: diagnostics))
    }
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("Could not encode diagnostic JSON")
    }
    print(UsageDiagnosticRedactor.redact(text))
}

func printStorageJSON(_ reports: [UsageStorageCLIReport], pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    let data: Data
    if reports.count == 1, let report = reports.first {
        data = try encoder.encode(report)
    } else {
        data = try encoder.encode(reports)
    }
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("Could not encode storage JSON")
    }
    print(UsageDiagnosticRedactor.redact(text))
}

func runCost(options: Options) async throws {
    let days = try intOption(options, "days", default: 30, range: 1...365)
    let selection = options.value("provider") ?? options.positional.first
    let sources = try costSources(selection)
    let forceRefresh = options.has("refresh")
    let report: UsageCostCLIReport
    do {
        report = try await UsageCostCLIReporter.scanAsyncUnlessCancelled(
            daysBack: days,
            sources: sources,
            forceRefresh: forceRefresh)
    } catch let error as CLIError {
        throw error
    } catch {
        throw CLIError(commandErrorDescription(error))
    }
    switch try usageFormat(options) {
    case "text":
        print(UsageCostCLITextRenderer.render(report))
    case "json":
        try printCostJSON(report, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runCache(args: [String]) async throws {
    let clearArgs: [String]
    if args.first == "clear" {
        clearArgs = Array(args.dropFirst())
    } else if args.isEmpty || args.first?.hasPrefix("-") == true {
        clearArgs = args
    } else {
        throw CLIError(cacheUsage())
    }
    let options = try parseOptions(clearArgs)
    let cookies = options.has("cookies")
    let cost = options.has("cost")
    let all = options.has("all")
    let results = try await clearUsageCaches(
        cookies: cookies,
        cost: cost,
        all: all,
        provider: options.value("provider"),
        missingSelectionMessage: "Specify --cookies, --cost, or --all.\n\n\(cacheUsage())")

    switch try usageFormat(options) {
    case "text":
        for result in results {
            let scope = result.provider ?? "all providers"
            if let error = result.error {
                print("\(result.cache): failed to clear (\(scope)) - \(error)")
            } else if result.cleared > 0 {
                print("\(result.cache): cleared (\(scope))")
            } else {
                print("\(result.cache): nothing to clear (\(scope))")
            }
        }
    case "json":
        try printEncodableJSON(results, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func cacheUsage() -> String {
    """
    Usage: conductorctl cache clear <--cookies|--cost|--all> [--provider ID_OR_ALIAS] [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func clearUsageCaches(
    cookies: Bool,
    cost: Bool,
    all: Bool,
    provider rawProvider: String?,
    missingSelectionMessage: String = "Specify cookies, cost, or all."
) async throws -> [CacheClearResult] {
    let clearCookies = cookies || all
    let clearCost = cost || all

    guard clearCookies || clearCost else {
        throw CLIError(missingSelectionMessage)
    }
    if rawProvider != nil, clearCost {
        throw CLIError("--provider only scopes cookie caches. Use --cookies --provider <name>, or omit --provider.")
    }

    let providerID: String?
    if let rawProvider {
        let normalized = normalizedConfigProviderID(rawProvider)
        guard UsageProviderCatalog.all.contains(where: { $0.id == normalized }) else {
            throw CLIError("Unknown provider: \(rawProvider)")
        }
        providerID = normalized
    } else {
        providerID = nil
    }

    var results: [CacheClearResult] = []
    if clearCookies {
        let removed = all && providerID == nil
            ? UsageCacheCleaner.clearCookieDerivedCaches()
                + UsageCacheCleaner.clearQuotaWarningState()
            : UsageCacheCleaner.clearCookieDerivedCaches(providerID: providerID)
        results.append(CacheClearResult(
            cache: "cookies",
            provider: providerID,
            cleared: removed.count,
            error: nil))
    }
    if clearCost {
        let removed = CostUsageFetcher.clearCache(includePricing: true)
        results.append(CacheClearResult(cache: "cost", provider: nil, cleared: removed.count, error: nil))
    }
    if all {
        let removed = UsageCacheCleaner.clearUsageSnapshotHydration()
        results.append(CacheClearResult(cache: "usage-snapshots", provider: nil, cleared: removed.count, error: nil))
    }
    return results
}

struct CacheClearResult: Encodable {
    let cache: String
    let provider: String?
    let cleared: Int
    let error: String?
}

struct CLIConfigStore {
    let fileURL: URL

    init(fileURL: URL = CLIConfigStore.defaultConfigURL()) {
        self.fileURL = fileURL
    }

    func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try save(.default)
            return .default
        }
        try? ConfigFileSecurity.secureConfigFile(at: fileURL)
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        return try YAMLDecoder().decode(AppConfig.self, from: text).validated()
    }

    func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? ConfigFileSecurity.secureConfigDirectory(at: fileURL.deletingLastPathComponent())
        let yaml = try YAMLEncoder().encode(config.validated())
        let header = "# conductor config managed by conductorctl\n\n"
        try (header + yaml).write(to: fileURL, atomically: true, encoding: .utf8)
        try ConfigFileSecurity.secureConfigFile(at: fileURL)
    }

    private static func defaultConfigURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CONDUCTOR_CONFIG_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/conductor/config.yaml")
    }
}

struct ConfigProviderStatus: Codable {
    let order: Int
    let provider: String
    let displayName: String
    let sessionLabel: String
    let weeklyLabel: String
    let opusLabel: String?
    let supportsOpus: Bool
    let supportsCredits: Bool
    let creditsHint: String
    let toggleTitle: String
    let cliName: String
    let isPrimaryProvider: Bool
    let usesAccountFallback: Bool
    let enabled: Bool
    let defaultEnabled: Bool
    let configuredExplicitly: Bool
    let sourceModes: [String]
    let supportsAPIKey: Bool
    let supportsTokenAccounts: Bool
    let cliSessionPolicy: UsageProviderCLISessionPolicy
    let signInCommand: String?
    let dashboardURL: String?
    let subscriptionDashboardURL: String?
    let changelogURL: String?
    let environmentHints: UsageProviderConfigEnvironmentHints
    let statusPageURL: String?
    let statusLinkURL: String?
    let googleWorkspaceStatusProductID: String?
}

struct ConfigProviderToggleResult: Codable {
    let provider: String
    let displayName: String
    let enabled: Bool
    let configPath: String
}

struct ConfigProviderOrderResult: Codable {
    let providerOrder: [String]
    let configPath: String
}

struct ConfigSetAPIKeyResult: Codable {
    let provider: String
    let enabled: Bool
    let configPath: String
}

struct ConfigSetCookieResult: Codable {
    let provider: String
    let enabled: Bool
    let cookieSource: String
    let configPath: String
}

struct ConfigProviderFieldResult: Codable {
    let provider: String
    let displayName: String
    let key: String
    let present: Bool
    let enabled: Bool
    let configPath: String
}

struct ConfigTokenAccountSummary: Codable {
    let index: Int
    let id: UUID
    let label: String
    let active: Bool
    let organizationID: String?
    let externalIdentifier: String?
    let addedAt: TimeInterval
    let lastUsed: TimeInterval?
    let hasToken: Bool
}

struct ConfigTokenAccountsResult: Codable {
    let provider: String
    let displayName: String
    let enabled: Bool
    let activeIndex: Int?
    let accounts: [ConfigTokenAccountSummary]
    let configPath: String
}

struct ConfigTokenAccountMutationResult: Codable {
    let provider: String
    let displayName: String
    let action: String
    let enabled: Bool
    let activeIndex: Int?
    let account: ConfigTokenAccountSummary?
    let accounts: [ConfigTokenAccountSummary]
    let configPath: String
}

func runConfig(args: [String]) throws {
    let subcommand: String
    let rest: [String]
    if let first = args.first, !first.hasPrefix("-") {
        subcommand = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        rest = Array(args.dropFirst())
    } else {
        subcommand = "validate"
        rest = args
    }
    switch subcommand {
    case "validate":
        try runConfigValidate(options: parseOptions(rest))
    case "dump":
        try runConfigDump(options: parseOptions(rest))
    case "providers", "list", "ls":
        try runConfigProviders(options: parseOptions(rest))
    case "order", "provider-order":
        try runConfigProviderOrder(options: parseOptions(rest))
    case "enable":
        try runConfigSetProviderEnabled(options: parseOptions(rest), enabled: true)
    case "disable":
        try runConfigSetProviderEnabled(options: parseOptions(rest), enabled: false)
    case "set-api-key", "set-key":
        try runConfigSetAPIKey(options: parseOptions(rest))
    case "set-cookie", "set-cookie-header", "set-session":
        try runConfigSetCookie(options: parseOptions(rest))
    case "set", "set-field":
        try runConfigSetField(options: parseOptions(rest), unset: false)
    case "unset", "unset-field", "clear-field":
        try runConfigSetField(options: parseOptions(rest), unset: true)
    case "accounts", "account-list", "list-accounts":
        try runConfigTokenAccounts(options: parseOptions(rest))
    case "account", "token-account":
        try runConfigTokenAccount(args: rest)
    case "help", "-h", "--help":
        print(configUsage())
    default:
        throw CLIError("Unknown config subcommand: \(subcommand)\n\n\(configUsage())")
    }
}

func configUsage() -> String {
    """
    Usage:
      conductorctl config [validate] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config validate [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config dump [--format json] [--json-only] [--pretty]
      conductorctl config providers [--provider all|both|ID_OR_ALIAS[,ID_OR_ALIAS...]] [--verbose] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config order [--provider ID_OR_ALIAS[,ID_OR_ALIAS...]] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config enable|disable --provider ID_OR_ALIAS [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config set-api-key --provider ID_OR_ALIAS (--api-key KEY|--stdin) [--no-enable] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config set-cookie --provider ID_OR_ALIAS (--cookie COOKIE|--stdin) [--no-enable] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config set --provider ID_OR_ALIAS --key sourceMode|baseURL|projectID|organizationID|cookieSource|extra.NAME --value VALUE [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config unset --provider ID_OR_ALIAS --key sourceMode|baseURL|projectID|organizationID|cookieSource|extra.NAME [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config accounts --provider ID_OR_ALIAS [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account add --provider ID_OR_ALIAS (--token TOKEN|--stdin) [--label LABEL] [--organization ORG] [--external-id ID] [--no-select] [--no-enable] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account update --provider ID_OR_ALIAS (--account LABEL|--account-index N) [--label LABEL] [--token TOKEN|--stdin] [--organization ORG|--clear-organization] [--external-id ID|--clear-external-id] [--select] [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account select --provider ID_OR_ALIAS (--account LABEL|--account-index N) [--format text|json] [--json] [--json-only] [--pretty]
      conductorctl config account remove --provider ID_OR_ALIAS (--account LABEL|--account-index N) [--format text|json] [--json] [--json-only] [--pretty]
    """
}

func runConfigValidate(options: Options) throws {
    let store = CLIConfigStore()
    let config = try store.load()
    let issues = validateConfig(config)
    switch try usageFormat(options) {
    case "text":
        if issues.isEmpty {
            print("Config: OK")
        } else {
            for issue in issues {
                let provider = issue.provider ?? "config"
                let field = issue.field.map { " (\($0))" } ?? ""
                print("[\(issue.severity.uppercased())] \(provider)\(field): \(issue.message)")
            }
        }
    case "json":
        try printEncodableJSON(issues, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
    if issues.contains(where: { $0.severity == "error" }) {
        if options.has("json-only") {
            throw CLISilentExit(status: 1)
        }
        throw CLIError("Config validation failed")
    }
}

func runConfigDump(options: Options) throws {
    let config = try CLIConfigStore().load()
    try printEncodableJSON(config, pretty: options.has("pretty"))
}

func runConfigProviders(options: Options) throws {
    let config = try CLIConfigStore().load()
    let providerSelection = options.value("provider") ?? options.positional.first
    let statuses = try configProviderStatuses(config, providerSelection: providerSelection)
    switch try usageFormat(options) {
    case "text":
        let verbose = options.has("verbose")
        for status in statuses {
            let state = status.enabled ? "enabled" : "disabled"
            let marker = status.defaultEnabled ? " default" : ""
            let key = status.supportsAPIKey ? " api-key" : ""
            let accounts = status.supportsTokenAccounts ? " accounts" : ""
            let cli = status.cliSessionPolicy.kind == "none" ? "" : " cli-\(status.cliSessionPolicy.kind)"
            let login = status.signInCommand == nil ? "" : " login"
            print("\(status.order). \(status.provider): \(state)\(marker)\(key)\(accounts)\(cli)\(login) (\(status.displayName))")
            if verbose {
                for line in configProviderVerboseLines(status) {
                    print("   \(line)")
                }
            }
        }
    case "json":
        try printEncodableJSON(statuses, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func configProviderVerboseLines(_ status: ConfigProviderStatus) -> [String] {
    var lines: [String] = []

    if let command = nonEmptyConfigProviderText(status.signInCommand) {
        lines.append("sign-in: \(command)")
    }
    if status.cliSessionPolicy.kind != "none" {
        let lifetime = status.cliSessionPolicy.persistsAcrossRequests ? "persistent" : "one-shot"
        lines.append("cli-session: \(status.cliSessionPolicy.kind) (\(lifetime))")
    }
    lines.append("cli-name: \(status.cliName)")
    let labels = [status.sessionLabel, status.weeklyLabel, status.opusLabel]
        .compactMap { nonEmptyConfigProviderText($0) }
        .joined(separator: " / ")
    if !labels.isEmpty {
        lines.append("window labels: \(labels)")
    }
    var traits: [String] = []
    if status.isPrimaryProvider { traits.append("primary") }
    if status.usesAccountFallback { traits.append("account-fallback") }
    if status.supportsCredits { traits.append("credits") }
    if status.supportsOpus { traits.append("tertiary-window") }
    if !traits.isEmpty {
        lines.append("traits: \(traits.joined(separator: ", "))")
    }
    if let hint = nonEmptyConfigProviderText(status.creditsHint) {
        lines.append("credits: \(hint)")
    }
    if !status.sourceModes.isEmpty {
        lines.append("source modes: \(status.sourceModes.joined(separator: ", "))")
    }
    if let url = nonEmptyConfigProviderText(status.statusPageURL ?? status.statusLinkURL) {
        lines.append("status: \(url)")
    }
    if let url = nonEmptyConfigProviderText(status.dashboardURL) {
        lines.append("dashboard: \(url)")
    }
    if let url = nonEmptyConfigProviderText(status.subscriptionDashboardURL) {
        lines.append("subscription: \(url)")
    }
    if let url = nonEmptyConfigProviderText(status.changelogURL) {
        lines.append("changelog: \(url)")
    }

    appendProviderHint("api-key env", values: status.environmentHints.apiKey, to: &lines)
    appendProviderHint("cookie env", values: status.environmentHints.cookieHeader, to: &lines)
    appendProviderHint("base-url env", values: status.environmentHints.baseURL, to: &lines)
    appendProviderHint("project env", values: status.environmentHints.project, to: &lines)
    appendProviderHint("organization env", values: status.environmentHints.organization, to: &lines)
    appendProviderHint("source env", values: status.environmentHints.sourceMode, to: &lines)
    appendProviderHint("cookie-source env", values: status.environmentHints.cookieSource, to: &lines)
    for key in status.environmentHints.extra.keys.sorted() {
        appendProviderHint("extra.\(key) env", values: status.environmentHints.extra[key] ?? [], to: &lines)
    }

    return lines
}

func appendProviderHint(_ label: String, values: [String], to lines: inout [String]) {
    guard !values.isEmpty else { return }
    lines.append("\(label): \(values.joined(separator: " / "))")
}

func nonEmptyConfigProviderText(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

func runConfigProviderOrder(options: Options) throws {
    let result = try setConfigProviderOrder(providerSelection: options.value("provider") ?? options.positional.first)
    switch try usageFormat(options) {
    case "text":
        for (index, provider) in result.providerOrder.enumerated() {
            print("\(index + 1). \(provider)")
        }
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runConfigSetProviderEnabled(options: Options, enabled: Bool) throws {
    let provider = try configProviderEntry(options)
    let result = try setConfigProviderEnabled(provider: provider, enabled: enabled)
    switch try usageFormat(options) {
    case "text":
        print("Config: \(enabled ? "enabled" : "disabled") \(provider.name)")
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runConfigSetAPIKey(options: Options) throws {
    let provider = try configProviderEntry(options)
    guard UsageProviderConfigCapabilities.supportsAPIKey(provider.id) else {
        throw CLIError("\(provider.id) does not support config API keys.")
    }
    let apiKey = try resolveConfigAPIKeyInput(
        apiKey: options.value("api-key") ?? options.value("key"),
        readFromStdin: options.has("stdin"))
    let result = try setConfigProviderAPIKey(
        provider: provider,
        apiKey: apiKey,
        noEnable: options.has("no-enable"))
    switch try usageFormat(options) {
    case "text":
        let suffix = result.enabled ? " and enabled" : ""
        print("Config: stored API key for \(provider.name)\(suffix)")
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runConfigSetCookie(options: Options) throws {
    let provider = try configProviderEntry(options)
    guard UsageProviderConfigCapabilities.supportsCookieHeader(provider.id) else {
        throw CLIError("\(provider.id) does not support config cookies.")
    }
    let cookieHeader = try resolveConfigCookieInput(
        cookie: options.value("cookie")
            ?? options.value("cookie-header")
            ?? options.value("session")
            ?? options.value("token"),
        readFromStdin: options.has("stdin"))
    let result = try setConfigProviderCookie(
        provider: provider,
        cookieHeader: cookieHeader,
        noEnable: options.has("no-enable"))
    switch try usageFormat(options) {
    case "text":
        let suffix = result.enabled ? " and enabled" : ""
        print("Config: stored Cookie header for \(provider.name)\(suffix)")
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runConfigSetField(options: Options, unset: Bool) throws {
    let provider = try configProviderEntry(options)
    let key = try configFieldKey(options)
    let value = unset ? nil : try configFieldValue(options)
    let result = try setConfigProviderField(
        provider: provider,
        key: key,
        value: value,
        unset: unset)
    switch try usageFormat(options) {
    case "text":
        print("Config: \(result.present ? "set" : "unset") \(result.key) for \(provider.name)")
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func setConfigProviderOrder(
    providerSelection raw: String?,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigProviderOrderResult {
    var config = try store.load()
    let known = UsageProviderCatalog.all.map(\.id)
    if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let requested = raw
            .split(separator: ",")
            .map { normalizedConfigProviderID(String($0)) }
            .filter { !$0.isEmpty }
        let knownSet = Set(known)
        if let unknown = requested.first(where: { !knownSet.contains($0) }) {
            throw UsageProviderCatalogError.unknownProvider(unknown, known: known)
        }
        config.usage.providerOrder = UsageConfig.effectiveProviderOrder(
            raw: requested,
            knownProviderIDs: known)
        try store.save(config)
    }
    let saved = try store.load()
    return ConfigProviderOrderResult(
        providerOrder: saved.usage.effectiveProviderOrder(knownProviderIDs: known),
        configPath: store.fileURL.path)
}

func setConfigProviderEnabled(
    provider: UsageProviderEntry,
    enabled: Bool,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigProviderToggleResult {
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    providerConfig.enabled = enabled
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    return ConfigProviderToggleResult(
        provider: provider.id,
        displayName: provider.name,
        enabled: enabled,
        configPath: store.fileURL.path)
}

func setConfigProviderAPIKey(
    provider: UsageProviderEntry,
    apiKey: String,
    noEnable: Bool,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigSetAPIKeyResult {
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    providerConfig.apiKey = apiKey
    if !noEnable {
        providerConfig.enabled = true
    }
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    let saved = try store.load()
    return ConfigSetAPIKeyResult(
        provider: provider.id,
        enabled: saved.usage.providers[provider.id]?.enabled ?? provider.defaultEnabled,
        configPath: store.fileURL.path)
}

func setConfigProviderCookie(
    provider: UsageProviderEntry,
    cookieHeader: String,
    noEnable: Bool,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigSetCookieResult {
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    providerConfig.cookieHeader = cookieHeader
    providerConfig.cookieSource = "manual"
    if !noEnable {
        providerConfig.enabled = true
    }
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    let saved = try store.load()
    return ConfigSetCookieResult(
        provider: provider.id,
        enabled: saved.usage.providers[provider.id]?.enabled ?? provider.defaultEnabled,
        cookieSource: saved.usage.providers[provider.id]?.cookieSource ?? "manual",
        configPath: store.fileURL.path)
}

func setConfigProviderField(
    provider: UsageProviderEntry,
    key rawKey: String,
    value rawValue: String?,
    unset: Bool,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigProviderFieldResult {
    let key = try canonicalConfigFieldKey(rawKey)
    let value = unset ? nil : try normalizedConfigFieldValue(rawValue, key: key, provider: provider)
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()

    switch key {
    case "sourceMode":
        providerConfig.sourceMode = value?.lowercased()
    case "cookieSource":
        providerConfig.cookieSource = value?.lowercased()
    case "baseURL":
        providerConfig.baseURL = value
    case "projectID":
        providerConfig.projectID = value
    case "organizationID":
        providerConfig.organizationID = value
    default:
        guard key.hasPrefix("extra.") else {
            throw CLIError("Unsupported config key: \(rawKey)")
        }
        let extraKey = String(key.dropFirst("extra.".count))
        if let value {
            providerConfig.extra[extraKey] = value
        } else {
            providerConfig.extra.removeValue(forKey: extraKey)
        }
    }

    config.usage.providers[provider.id] = providerConfig
    try store.save(config)
    let saved = try store.load()
    let savedConfig = saved.usage.providers[provider.id] ?? UsageProviderConfig()

    return ConfigProviderFieldResult(
        provider: provider.id,
        displayName: provider.name,
        key: key,
        present: configFieldIsPresent(key: key, config: savedConfig),
        enabled: savedConfig.enabled ?? provider.defaultEnabled,
        configPath: store.fileURL.path)
}

func runConfigTokenAccount(args: [String]) throws {
    guard let first = args.first, !first.hasPrefix("-") else {
        throw CLIError("Missing account action. Use add, update, select, remove, or list.\n\n\(configUsage())")
    }
    let action = first.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let rest = Array(args.dropFirst())
    switch action {
    case "list", "ls", "accounts":
        try runConfigTokenAccounts(options: parseOptions(rest))
    case "add", "create":
        try runConfigTokenAccountAdd(options: parseOptions(rest))
    case "update", "edit", "patch":
        try runConfigTokenAccountUpdate(options: parseOptions(rest))
    case "select", "use", "activate":
        try runConfigTokenAccountSelect(options: parseOptions(rest))
    case "remove", "delete", "rm":
        try runConfigTokenAccountRemove(options: parseOptions(rest))
    case "help", "-h", "--help":
        print(configUsage())
    default:
        throw CLIError("Unknown account action: \(action)\n\n\(configUsage())")
    }
}

func runConfigTokenAccounts(options: Options) throws {
    let provider = try configTokenAccountProvider(options)
    let store = CLIConfigStore()
    let config = try store.load()
    let result = configTokenAccountsResult(provider: provider, config: config, configPath: store.fileURL.path)
    switch try usageFormat(options) {
    case "text":
        printConfigTokenAccounts(result)
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func runConfigTokenAccountAdd(options: Options) throws {
    let provider = try configTokenAccountProvider(options)
    let token = try resolveConfigTokenAccountSecretInput(options: options)
    let result = try addConfigTokenAccount(
        provider: provider,
        token: token,
        label: options.value("label"),
        organizationID: options.value("organization") ?? options.value("org"),
        externalIdentifier: options.value("external-id"),
        noSelect: options.has("no-select"),
        noEnable: options.has("no-enable"))
    try printConfigTokenAccountMutation(result, options: options)
}

func runConfigTokenAccountUpdate(options: Options) throws {
    let provider = try configTokenAccountProvider(options)
    let token = try optionalConfigTokenAccountSecretInput(options: options)
    let result = try updateConfigTokenAccount(
        provider: provider,
        account: options.value("account"),
        accountIndex: try configAccountIndexOption(options.value("account-index")),
        token: token,
        label: options.value("label"),
        organizationID: options.value("organization") ?? options.value("org"),
        clearOrganizationID: options.has("clear-organization"),
        externalIdentifier: options.value("external-id"),
        clearExternalIdentifier: options.has("clear-external-id"),
        select: options.has("select"))
    try printConfigTokenAccountMutation(result, options: options)
}

func runConfigTokenAccountSelect(options: Options) throws {
    let provider = try configTokenAccountProvider(options)
    let result = try selectConfigTokenAccount(
        provider: provider,
        account: options.value("account"),
        accountIndex: try configAccountIndexOption(options.value("account-index")))
    try printConfigTokenAccountMutation(result, options: options)
}

func runConfigTokenAccountRemove(options: Options) throws {
    let provider = try configTokenAccountProvider(options)
    let result = try removeConfigTokenAccount(
        provider: provider,
        account: options.value("account"),
        accountIndex: try configAccountIndexOption(options.value("account-index")))
    try printConfigTokenAccountMutation(result, options: options)
}

func addConfigTokenAccount(
    provider: UsageProviderEntry,
    token: String,
    label: String?,
    organizationID: String?,
    externalIdentifier: String?,
    noSelect: Bool,
    noEnable: Bool,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigTokenAccountMutationResult {
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    var data = providerConfig.tokenAccounts ?? UsageProviderTokenAccountData()
    let label = normalizedConfigAccountText(label) ?? "Account \(data.accounts.count + 1)"
    let account = UsageProviderTokenAccount(
        label: label,
        token: token,
        externalIdentifier: normalizedConfigAccountText(externalIdentifier),
        organizationID: normalizedConfigAccountText(organizationID))
    data.accounts.append(account)
    if !noSelect || data.accounts.count == 1 {
        data.activeIndex = data.accounts.count - 1
    }
    providerConfig.tokenAccounts = data
    if UsageProviderConfigCapabilities.tokenAccountSupportByProviderID[provider.id]?.requiresManualCookieSource == true {
        providerConfig.cookieSource = "manual"
    }
    if !noEnable {
        providerConfig.enabled = true
    }
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    return configTokenAccountMutationResult(
        provider: provider,
        action: "add",
        accountID: account.id,
        config: try store.load(),
        configPath: store.fileURL.path)
}

func selectConfigTokenAccount(
    provider: UsageProviderEntry,
    account: String?,
    accountIndex: Int?,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigTokenAccountMutationResult {
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    guard var data = providerConfig.tokenAccounts, !data.accounts.isEmpty else {
        throw CLIError("No token accounts configured for \(provider.id).")
    }
    let index = try configTokenAccountIndex(
        account: account,
        accountIndex: accountIndex,
        data: data,
        providerID: provider.id)
    data.activeIndex = index
    providerConfig.tokenAccounts = data
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    return configTokenAccountMutationResult(
        provider: provider,
        action: "select",
        accountID: data.accounts[index].id,
        config: try store.load(),
        configPath: store.fileURL.path)
}

func updateConfigTokenAccount(
    provider: UsageProviderEntry,
    account: String?,
    accountIndex: Int?,
    token: String?,
    label: String?,
    organizationID: String?,
    clearOrganizationID: Bool,
    externalIdentifier: String?,
    clearExternalIdentifier: Bool,
    select: Bool,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigTokenAccountMutationResult {
    if clearOrganizationID, normalizedConfigAccountText(organizationID) != nil {
        throw CLIError("Use either --organization or --clear-organization, not both.")
    }
    if clearExternalIdentifier, normalizedConfigAccountText(externalIdentifier) != nil {
        throw CLIError("Use either --external-id or --clear-external-id, not both.")
    }
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    guard var data = providerConfig.tokenAccounts, !data.accounts.isEmpty else {
        throw CLIError("No token accounts configured for \(provider.id).")
    }
    let index = try configTokenAccountIndex(
        account: account,
        accountIndex: accountIndex,
        data: data,
        providerID: provider.id)

    var didChange = false
    if let label {
        guard let normalized = normalizedConfigAccountText(label) else {
            throw CLIError("Account label cannot be empty.")
        }
        data.accounts[index].label = normalized
        didChange = true
    }
    if let token {
        data.accounts[index].token = token
        didChange = true
    }
    if clearOrganizationID {
        data.accounts[index].organizationID = nil
        didChange = true
    } else if organizationID != nil {
        data.accounts[index].organizationID = normalizedConfigAccountText(organizationID)
        didChange = true
    }
    if clearExternalIdentifier {
        data.accounts[index].externalIdentifier = nil
        didChange = true
    } else if externalIdentifier != nil {
        data.accounts[index].externalIdentifier = normalizedConfigAccountText(externalIdentifier)
        didChange = true
    }
    if select {
        data.activeIndex = index
        didChange = true
    }
    guard didChange else {
        throw CLIError("No account updates specified.")
    }

    providerConfig.tokenAccounts = data
    if token != nil,
       UsageProviderConfigCapabilities.tokenAccountSupportByProviderID[provider.id]?.requiresManualCookieSource == true
    {
        providerConfig.cookieSource = "manual"
    }
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    return configTokenAccountMutationResult(
        provider: provider,
        action: "update",
        accountID: data.accounts[index].id,
        config: try store.load(),
        configPath: store.fileURL.path)
}

func removeConfigTokenAccount(
    provider: UsageProviderEntry,
    account: String?,
    accountIndex: Int?,
    store: CLIConfigStore = CLIConfigStore()
) throws -> ConfigTokenAccountMutationResult {
    var config = try store.load()
    var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
    guard var data = providerConfig.tokenAccounts, !data.accounts.isEmpty else {
        throw CLIError("No token accounts configured for \(provider.id).")
    }
    let index = try configTokenAccountIndex(
        account: account,
        accountIndex: accountIndex,
        data: data,
        providerID: provider.id)
    let removedAccount = data.accounts[index]
    let previousActiveIndex = data.clampedActiveIndex()
    data.accounts.remove(at: index)
    if data.accounts.isEmpty {
        providerConfig.tokenAccounts = nil
    } else {
        if index < previousActiveIndex {
            data.activeIndex = previousActiveIndex - 1
        } else if index == previousActiveIndex {
            data.activeIndex = min(index, data.accounts.count - 1)
        } else {
            data.activeIndex = previousActiveIndex
        }
        providerConfig.tokenAccounts = data
    }
    config.usage.providers[provider.id] = providerConfig
    try store.save(config)

    return configTokenAccountMutationResult(
        provider: provider,
        action: "remove",
        removedAccount: removedAccount,
        config: try store.load(),
        configPath: store.fileURL.path)
}

func validateConfig(_ config: AppConfig) -> [ConfigValidationIssue] {
    UsageProviderConfigValidator.validate(config)
}

func configProviderStatuses(
    _ config: AppConfig,
    providerSelection: String? = nil
) throws -> [ConfigProviderStatus] {
    let statuses = UsageProviderCatalog.orderedEntries(config: config).enumerated().map { index, entry in
        let providerConfig = config.usage.providers[entry.id]
        let defaultEnabled = entry.defaultEnabled
        let metadata = entry.displayMetadata
        return ConfigProviderStatus(
            order: index + 1,
            provider: entry.id,
            displayName: entry.name,
            sessionLabel: metadata.sessionLabel,
            weeklyLabel: metadata.weeklyLabel,
            opusLabel: metadata.opusLabel,
            supportsOpus: metadata.supportsOpus,
            supportsCredits: metadata.supportsCredits,
            creditsHint: metadata.creditsHint,
            toggleTitle: metadata.toggleTitle,
            cliName: metadata.cliName,
            isPrimaryProvider: metadata.isPrimaryProvider,
            usesAccountFallback: metadata.usesAccountFallback,
            enabled: providerConfig?.enabled ?? defaultEnabled,
            defaultEnabled: defaultEnabled,
            configuredExplicitly: providerConfig != nil,
            sourceModes: entry.sourceModes,
            supportsAPIKey: UsageProviderConfigCapabilities.supportsAPIKey(entry.id),
            supportsTokenAccounts: UsageProviderConfigCapabilities.supportsTokenAccounts(entry.id),
            cliSessionPolicy: entry.cliSessionPolicy,
            signInCommand: entry.signInCommand,
            dashboardURL: entry.dashboardURL,
            subscriptionDashboardURL: entry.subscriptionDashboardURL,
            changelogURL: entry.changelogURL,
            environmentHints: UsageProviderConfigCapabilities.environmentHints(providerID: entry.id),
            statusPageURL: entry.statusPageURL,
            statusLinkURL: entry.statusLinkURL,
            googleWorkspaceStatusProductID: entry.googleWorkspaceStatusProductID)
    }

    guard let selection = providerSelection?.trimmingCharacters(in: .whitespacesAndNewlines),
          !selection.isEmpty
    else {
        return statuses
    }

    let selected = try UsageProviderCatalog.entries(for: selection).map(\.id)
    let selectedIDs = Set(selected)
    return statuses.filter { selectedIDs.contains($0.provider) }
}

func configProviderEntry(_ options: Options) throws -> UsageProviderEntry {
    try configProviderEntry(raw: options.value("provider") ?? options.positional.first)
}

func configProviderEntry(raw: String?) throws -> UsageProviderEntry {
    guard let raw,
          !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        throw CLIError("Unknown or missing provider. Use --provider <name>.")
    }
    let id = normalizedConfigProviderID(raw)
    guard let entry = UsageProviderCatalog.all.first(where: { $0.id == id }) else {
        throw CLIError("Unknown or missing provider. Use --provider <name>.")
    }
    return entry
}

func configFieldKey(_ options: Options) throws -> String {
    let positionalIndex = options.value("provider") == nil ? 1 : 0
    let raw = options.value("key") ?? options.value("field") ?? options.positional.dropFirst(positionalIndex).first
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw CLIError("Missing config key. Pass --key <field>.")
    }
    return raw
}

func configFieldValue(_ options: Options) throws -> String {
    let keyPositionalIndex = options.value("provider") == nil ? 1 : 0
    let raw = options.value("value")
        ?? options.value("source")
        ?? options.value("base-url")
        ?? options.value("project")
        ?? options.value("organization")
        ?? options.positional.dropFirst(keyPositionalIndex + 1).first
    guard let value = normalizedConfigAccountText(raw) else {
        throw CLIError("Missing config value. Pass --value <value>.")
    }
    return value
}

func canonicalConfigFieldKey(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    switch lower {
    case "source", "source-mode", "sourcemode":
        return "sourceMode"
    case "cookie-source", "cookiesource":
        return "cookieSource"
    case "base-url", "baseurl", "url", "endpoint":
        return "baseURL"
    case "project", "project-id", "projectid", "workspace", "workspace-id":
        return "projectID"
    case "organization", "org", "org-id", "organization-id", "organizationid":
        return "organizationID"
    default:
        if lower.hasPrefix("extra."), trimmed.count > "extra.".count {
            let extraKey = String(trimmed.dropFirst("extra.".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !extraKey.isEmpty else {
                throw CLIError("Unsupported config key: \(raw)")
            }
            return "extra.\(extraKey)"
        }
        throw CLIError("Unsupported config key: \(raw). Expected sourceMode, cookieSource, baseURL, projectID, organizationID, or extra.NAME.")
    }
}

func normalizedConfigFieldValue(
    _ rawValue: String?,
    key: String,
    provider: UsageProviderEntry
) throws -> String {
    guard let value = normalizedConfigAccountText(rawValue) else {
        throw CLIError("Missing config value. Pass --value <value>.")
    }
    switch key {
    case "sourceMode":
        let source = value.lowercased()
        guard provider.supportsSourceMode(source) else {
            throw CLIError("Source \(source) is not supported for \(provider.id). Expected one of: \(provider.sourceModes.joined(separator: ", ")).")
        }
        return source
    case "cookieSource":
        let source = value.lowercased()
        let allowed = ["auto", "browser", "manual", "off"]
        guard allowed.contains(source) else {
            throw CLIError("cookieSource must be one of: \(allowed.joined(separator: ", ")).")
        }
        return source
    case "baseURL":
        guard isValidConfigBaseURL(value) else {
            throw CLIError("baseURL must be an http or https URL.")
        }
        return value
    default:
        return value
    }
}

func configFieldIsPresent(key: String, config: UsageProviderConfig) -> Bool {
    switch key {
    case "sourceMode":
        return normalizedConfigAccountText(config.sourceMode) != nil
    case "cookieSource":
        return normalizedConfigAccountText(config.cookieSource) != nil
    case "baseURL":
        return normalizedConfigAccountText(config.baseURL) != nil
    case "projectID":
        return normalizedConfigAccountText(config.projectID) != nil
    case "organizationID":
        return normalizedConfigAccountText(config.organizationID) != nil
    default:
        guard key.hasPrefix("extra.") else { return false }
        let extraKey = String(key.dropFirst("extra.".count))
        return normalizedConfigAccountText(config.extra[extraKey]) != nil
    }
}

func normalizedConfigProviderID(_ raw: String) -> String {
    UsageProviderCatalog.canonicalProviderID(raw)
}

func configTokenAccountProvider(_ options: Options) throws -> UsageProviderEntry {
    try configTokenAccountProvider(raw: options.value("provider") ?? options.positional.first)
}

func configTokenAccountProvider(raw: String?) throws -> UsageProviderEntry {
    let provider = try configProviderEntry(raw: raw)
    guard UsageProviderConfigCapabilities.supportsTokenAccounts(provider.id) else {
        throw CLIError("\(provider.id) does not support token accounts.")
    }
    return provider
}

func configTokenAccountIndex(
    options: Options,
    data: UsageProviderTokenAccountData,
    providerID: String
) throws -> Int {
    try configTokenAccountIndex(
        account: options.value("account"),
        accountIndex: configAccountIndexOption(options.value("account-index")),
        data: data,
        providerID: providerID)
}

func configTokenAccountIndex(
    account rawAccount: String?,
    accountIndex rawIndex: Int?,
    data: UsageProviderTokenAccountData,
    providerID: String
) throws -> Int {
    let account = normalizedConfigAccountText(rawAccount)
    if account != nil, rawIndex != nil {
        throw CLIError("Use either --account or --account-index, not both.")
    }
    if let account {
        let normalized = account.lowercased()
        if let index = data.accounts.firstIndex(where: {
            $0.label.lowercased() == normalized ||
                $0.id.uuidString.lowercased() == normalized ||
                ($0.externalIdentifier?.lowercased() == normalized)
        }) {
            return index
        }
        throw CLIError("No token account labeled '\(account)' for \(providerID).")
    }
    if let rawIndex {
        let index = rawIndex - 1
        guard index >= 0, index < data.accounts.count else {
            throw CLIError("Token account index \(rawIndex) out of range for \(providerID) (1-\(data.accounts.count)).")
        }
        return index
    }
    throw CLIError("Missing account selector. Pass --account <label> or --account-index <n>.")
}

func configAccountIndexOption(_ raw: String?) throws -> Int? {
    guard let value = normalizedConfigAccountText(raw) else { return nil }
    guard let parsed = Int(value), parsed > 0 else {
        throw CLIError("--account-index must be a positive integer")
    }
    return parsed
}

func configTokenAccountsResult(
    provider: UsageProviderEntry,
    config: AppConfig,
    configPath: String
) -> ConfigTokenAccountsResult {
    let providerConfig = config.usage.providers[provider.id]
    let data = providerConfig?.tokenAccounts
    let accounts = configTokenAccountSummaries(data)
    return ConfigTokenAccountsResult(
        provider: provider.id,
        displayName: provider.name,
        enabled: providerConfig?.enabled ?? provider.defaultEnabled,
        activeIndex: accounts.first { $0.active }?.index,
        accounts: accounts,
        configPath: configPath)
}

func configTokenAccountMutationResult(
    provider: UsageProviderEntry,
    action: String,
    accountID: UUID? = nil,
    removedAccount: UsageProviderTokenAccount? = nil,
    config: AppConfig,
    configPath: String
) -> ConfigTokenAccountMutationResult {
    let listResult = configTokenAccountsResult(provider: provider, config: config, configPath: configPath)
    let selected = accountID.flatMap { id in
        listResult.accounts.first { $0.id == id }
    } ?? removedAccount.map { account in
        ConfigTokenAccountSummary(
            index: 0,
            id: account.id,
            label: account.displayName,
            active: false,
            organizationID: normalizedConfigAccountText(account.organizationID),
            externalIdentifier: normalizedConfigAccountText(account.externalIdentifier),
            addedAt: account.addedAt,
            lastUsed: account.lastUsed,
            hasToken: cleanConfigSecret(account.token) != nil)
    }
    return ConfigTokenAccountMutationResult(
        provider: listResult.provider,
        displayName: listResult.displayName,
        action: action,
        enabled: listResult.enabled,
        activeIndex: listResult.activeIndex,
        account: selected,
        accounts: listResult.accounts,
        configPath: listResult.configPath)
}

func configTokenAccountSummaries(_ data: UsageProviderTokenAccountData?) -> [ConfigTokenAccountSummary] {
    guard let data, !data.accounts.isEmpty else { return [] }
    let activeIndex = data.clampedActiveIndex()
    return data.accounts.enumerated().map { index, account in
        ConfigTokenAccountSummary(
            index: index + 1,
            id: account.id,
            label: account.displayName,
            active: index == activeIndex,
            organizationID: normalizedConfigAccountText(account.organizationID),
            externalIdentifier: normalizedConfigAccountText(account.externalIdentifier),
            addedAt: account.addedAt,
            lastUsed: account.lastUsed,
            hasToken: cleanConfigSecret(account.token) != nil)
    }
}

func printConfigTokenAccounts(_ result: ConfigTokenAccountsResult) {
    guard !result.accounts.isEmpty else {
        print("Config: no token accounts for \(result.displayName)")
        return
    }
    for account in result.accounts {
        let marker = account.active ? "*" : " "
        var parts = ["\(marker) \(account.index). \(account.label)"]
        if let organizationID = account.organizationID {
            parts.append("org=\(organizationID)")
        }
        if let externalIdentifier = account.externalIdentifier {
            parts.append("external-id=\(externalIdentifier)")
        }
        if let lastUsed = account.lastUsed {
            parts.append("last-used=\(configAccountTimestamp(lastUsed))")
        }
        parts.append("token=\(account.hasToken ? "yes" : "no")")
        print(parts.joined(separator: " "))
    }
}

func configAccountTimestamp(_ timestamp: TimeInterval) -> String {
    ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
}

func printConfigTokenAccountMutation(
    _ result: ConfigTokenAccountMutationResult,
    options: Options
) throws {
    switch try usageFormat(options) {
    case "text":
        let label = result.account?.label ?? "token account"
        switch result.action {
        case "add":
            let suffix = result.enabled ? " and enabled" : ""
            print("Config: added \(label) for \(result.displayName)\(suffix)")
        case "update":
            print("Config: updated \(label) for \(result.displayName)")
        case "select":
            print("Config: selected \(label) for \(result.displayName)")
        case "remove":
            print("Config: removed \(label) for \(result.displayName)")
        default:
            print("Config: updated token accounts for \(result.displayName)")
        }
    case "json":
        try printEncodableJSON(result, pretty: options.has("pretty"))
    default:
        throw CLIError("--format must be text or json")
    }
}

func resolveConfigTokenAccountSecretInput(options: Options) throws -> String {
    let candidates = [
        ("token", options.value("token")),
        ("api-key", options.value("api-key")),
        ("key", options.value("key")),
        ("cookie", options.value("cookie")),
        ("cookie-header", options.value("cookie-header")),
        ("session", options.value("session")),
    ].compactMap { candidate -> (String, String)? in
        let key = candidate.0
        let value = candidate.1
        guard let value else { return nil }
        return (key, value)
    }
    if options.has("stdin"), !candidates.isEmpty {
        throw CLIError("Use either a token option or --stdin, not both.")
    }
    if candidates.count > 1 {
        let keys = candidates.map { "--\($0.0)" }.joined(separator: ", ")
        throw CLIError("Use only one token option, not \(keys).")
    }
    let raw = options.has("stdin") ? try readStdin() : candidates.first?.1
    guard let value = cleanConfigSecret(raw) else {
        throw CLIError("Missing token account secret. Pass --token <token> or pipe it with --stdin.")
    }
    return value
}

func optionalConfigTokenAccountSecretInput(options: Options) throws -> String? {
    let candidates = [
        ("token", options.value("token")),
        ("api-key", options.value("api-key")),
        ("key", options.value("key")),
        ("cookie", options.value("cookie")),
        ("cookie-header", options.value("cookie-header")),
        ("session", options.value("session")),
    ].compactMap { candidate -> (String, String)? in
        let key = candidate.0
        let value = candidate.1
        guard let value else { return nil }
        return (key, value)
    }
    if options.has("stdin"), !candidates.isEmpty {
        throw CLIError("Use either a token option or --stdin, not both.")
    }
    if candidates.count > 1 {
        let keys = candidates.map { "--\($0.0)" }.joined(separator: ", ")
        throw CLIError("Use only one token option, not \(keys).")
    }
    let raw = options.has("stdin") ? try readStdin() : candidates.first?.1
    guard raw != nil else { return nil }
    guard let value = cleanConfigSecret(raw) else {
        throw CLIError("Token account secret cannot be empty.")
    }
    return value
}

func normalizedConfigAccountText(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

func resolveConfigAPIKeyInput(apiKey: String?, readFromStdin: Bool) throws -> String {
    if apiKey != nil, readFromStdin {
        throw CLIError("Use either --api-key or --stdin, not both.")
    }
    let raw = readFromStdin ? try readStdin() : apiKey
    guard let value = cleanConfigSecret(raw) else {
        throw CLIError("Missing API key. Pass --api-key <key> or pipe it with --stdin.")
    }
    return value
}

func resolveConfigCookieInput(cookie: String?, readFromStdin: Bool) throws -> String {
    if cookie != nil, readFromStdin {
        throw CLIError("Use either --cookie or --stdin, not both.")
    }
    let raw = readFromStdin ? try readStdin() : cookie
    guard let value = cleanConfigSecret(raw) else {
        throw CLIError("Missing Cookie header. Pass --cookie <cookie> or pipe it with --stdin.")
    }
    return value
}

func cleanConfigSecret(_ raw: String?) -> String? {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
        (value.hasPrefix("'") && value.hasSuffix("'"))
    {
        value = String(value.dropFirst().dropLast())
    }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

func isValidConfigBaseURL(_ raw: String) -> Bool {
    guard let components = URLComponents(string: raw),
          let scheme = components.scheme?.lowercased(),
          ["http", "https"].contains(scheme),
          components.host?.isEmpty == false
    else { return false }
    return true
}

func intOption(_ options: Options, _ key: String, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
    guard let raw = options.value(key) else { return defaultValue }
    guard let value = Int(raw), range.contains(value) else {
        throw CLIError("--\(key) must be \(range.lowerBound)...\(range.upperBound)")
    }
    return value
}

func costSources(_ selection: String?) throws -> Set<UsageSource>? {
    guard let normalized = selection?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased(), !normalized.isEmpty else {
        return nil
    }
    switch normalized {
    case "", "both", "all":
        return nil
    case "codex":
        return [.codex]
    case "claude", "claude-code", "claudecode":
        return [.claude]
    case "vertexai", "vertex-ai", "vertex":
        return [.vertexai]
    case "bedrock", "aws-bedrock", "awsbedrock":
        return [.bedrock]
    default:
        throw CLIError("--provider must be all, both, codex, claude, vertexai, or bedrock")
    }
}

func commandErrorDescription(_ error: Error) -> String {
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription,
       !description.isEmpty
    {
        return description
    }
    let localized = error.localizedDescription
    if !localized.isEmpty, localized != "The operation couldn’t be completed." {
        return localized
    }
    return String(describing: error)
}

func printCostJSON(_ report: UsageCostCLIReport, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
    let data = try encoder.encode(report)
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("Could not encode cost JSON")
    }
    print(text)
}

func printCLIJSONOnlyError(_ error: Error) {
    let report = UsageCLIReport(
        provider: "cli",
        name: "conductorctl",
        configured: false,
        source: "cli",
        usage: nil,
        error: UsageCLIError(error))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if CommandLine.arguments.contains("--pretty") {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    guard let data = try? encoder.encode([report]),
          let text = String(data: data, encoding: .utf8)
    else {
        print("[{\"provider\":\"cli\",\"name\":\"conductorctl\",\"configured\":false,\"source\":\"cli\",\"usage\":null,\"error\":{\"message\":\"Could not encode CLI error\"},\"repairActions\":[]}]")
        return
    }
    print(text)
}

func shouldEmitJSONOnlyError() -> Bool {
    CommandLine.arguments.dropFirst().contains("--json-only")
}

func printEncodableJSON<T: Encodable>(_ value: T, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : []
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("Could not encode JSON")
    }
    print(text)
}

func requiredValue(_ options: Options, key: String, positionalIndex: Int, label: String) throws -> String {
    if let value = options.value(key), !value.isEmpty { return value }
    if positionalIndex < options.positional.count {
        let value = options.positional[positionalIndex]
        if !value.isEmpty { return value }
    }
    throw CLIError("Missing \(label)")
}

func requiredJoinedText(_ options: Options, key: String, from index: Int, label: String) throws -> String {
    if let value = options.value(key), !value.isEmpty { return value }
    if index < options.positional.count {
        let value = options.positional.dropFirst(index).joined(separator: " ")
        if !value.isEmpty { return value }
    }
    throw CLIError("Missing \(label)")
}

func workspaceScopedParams(_ options: Options) -> [String: JSONValue] {
    guard let workspace = options.value("workspace") else { return [:] }
    return ["workspace": .string(workspace)]
}

func readStdin() throws -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else {
        throw CLIError("stdin is not valid UTF-8")
    }
    return text
}

func runBatch(client: SocketClient) throws {
    let input = try readStdin()
    let encoder = JSONEncoder()
    for (index, rawLine) in input.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { continue }
        guard let data = line.data(using: .utf8) else {
            throw CLIError("batch line \(index + 1) is not valid UTF-8")
        }
        let request: AutomationRequest
        do {
            request = try JSONDecoder().decode(AutomationRequest.self, from: data)
        } catch {
            throw CLIError("batch line \(index + 1) is not an AutomationRequest: \(error.localizedDescription)")
        }
        let response = try client.requestRaw(request)
        guard let encoded = String(data: try encoder.encode(response), encoding: .utf8) else {
            throw CLIError("Could not encode batch response")
        }
        print(encoded)
        fflush(stdout)
    }
}

func waitForAgentResult(client: SocketClient, job: String?, timeout: Double, poll: Double) throws -> AutomationResponse {
    let started = Date()
    while true {
        let statusParams: [String: JSONValue] = job.map { ["job": .string($0)] } ?? [:]
        let statusResponse = try client.request(method: AutomationMethod.agentStatus, params: statusParams)
        let statusObject = object(statusResponse.result)
        let status = statusObject["status"]?.stringValue ?? "unknown"
        let resolvedJob = statusObject["jobId"]?.stringValue ?? job
        if status == "completed" {
            let resultParams: [String: JSONValue] = resolvedJob.map { ["job": .string($0)] } ?? [:]
            return try client.request(method: AutomationMethod.agentResult, params: resultParams)
        }
        if timeout > 0, Date().timeIntervalSince(started) >= timeout {
            let label = resolvedJob ?? "-"
            throw CLIError("Timed out waiting for job \(label) after \(Int(timeout))s (last status=\(status))")
        }
        Thread.sleep(forTimeInterval: max(0.25, poll))
    }
}

func printActivity(_ entries: [JSONValue]) {
    for entry in entries {
        let item = object(entry)
        let time = item["time"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date()
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: time)
        let title = item["title"]?.stringValue ?? "-"
        let agent = item["agent"]?.stringValue ?? "-"
        let pane = item["pane"]?.stringValue ?? "-"
        let message = item["message"]?.stringValue ?? ""
        print("[\(stamp)] \(title) agent=\(agent) pane=\(pane)")
        if !message.isEmpty {
            print("  \(message)")
        }
    }
}

func printWorkspaces(_ entries: [JSONValue]) {
    for entry in entries {
        let item = object(entry)
        let active = item["active"]?.boolValue == true ? "*" : " "
        let id = item["id"]?.stringValue ?? "-"
        let name = item["name"]?.stringValue ?? "-"
        let tabs = item["tabs"]?.intValue ?? 0
        let path = item["path"]?.stringValue ?? ""
        print("\(active) \(id)  tabs=\(tabs)  \(name)  \(path)")
    }
}

func printTabs(_ entries: [JSONValue]) {
    for entry in entries {
        let item = object(entry)
        let active = item["active"]?.boolValue == true ? "*" : " "
        let id = item["id"]?.stringValue ?? "-"
        let index = item["index"]?.intValue ?? 0
        let title = item["title"]?.stringValue ?? ""
        let panes = item["panes"]?.arrayValue?.count ?? 0
        print("\(active) \(id)  index=\(index)  panes=\(panes)  \(title)")
    }
}

func printStatusChips(_ entries: [JSONValue]) {
    for entry in entries {
        let item = object(entry)
        let key = item["key"]?.stringValue ?? "-"
        let text = item["text"]?.stringValue ?? ""
        let color = item["color"]?.stringValue ?? "-"
        let icon = item["icon"]?.stringValue ?? "-"
        print("\(key)  color=\(color) icon=\(icon)  \(text)")
    }
}

func printWorkspaceLogs(_ entries: [JSONValue]) {
    let formatter = ISO8601DateFormatter()
    for entry in entries {
        let item = object(entry)
        let time = item["time"]?.doubleValue.map { Date(timeIntervalSince1970: $0) } ?? Date()
        let stamp = formatter.string(from: time)
        let level = item["level"]?.stringValue ?? "info"
        let source = item["source"]?.stringValue ?? "-"
        let text = item["text"]?.stringValue ?? ""
        print("[\(stamp)] \(level) source=\(source) \(text)")
    }
}

func printStatus(_ status: [String: JSONValue]) {
    let active = object(status["active"])
    print("app=\(status["app"]?.stringValue ?? "Conductor") version=\(status["version"]?.stringValue ?? "") protocol=\(status["protocol"]?.intValue ?? 0)")
    print("active workspace=\(active["workspace"]?.stringValue ?? "-") tab=\(active["tab"]?.stringValue ?? "-") pane=\(active["pane"]?.stringValue ?? "-")")
}

func printAgentStatus(_ status: [String: JSONValue]) {
    print("job=\(status["jobId"]?.stringValue ?? "-") status=\(status["status"]?.stringValue ?? "-") agent=\(status["agent"]?.stringValue ?? "-") pane=\(status["pane"]?.stringValue ?? "-")")
}

func printAgentResult(_ result: [String: JSONValue]) {
    printAgentStatus(result)
    if let summary = result["summary"]?.stringValue, !summary.isEmpty {
        print("\nSummary:\n\(summary)")
    }
    if let markdown = result["markdown"]?.stringValue, !markdown.isEmpty {
        print("\nResult:\n\(markdown)")
    }
    if let path = result["transcriptPath"]?.stringValue, !path.isEmpty {
        print("\nTranscript: \(path)")
    }
}

do {
    try main()
} catch let exitSignal as CLISilentExit {
    Darwin.exit(exitSignal.status)
} catch let error as CLIError {
    if shouldEmitJSONOnlyError() {
        printCLIJSONOnlyError(error)
        exit(1)
    }
    fputs("conductorctl: \(error.description)\n", stderr)
    exit(1)
} catch {
    if shouldEmitJSONOnlyError() {
        printCLIJSONOnlyError(error)
        exit(1)
    }
    fputs("conductorctl: \(error)\n", stderr)
    exit(1)
}
