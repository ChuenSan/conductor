import ConductorCore
import Darwin
import Foundation

struct ConductorCLI {
    let arguments: [String]

    func run() -> Int32 {
        do {
            let request = try makeRequest()
            let response = try send(request)
            try printResponse(response)
            return response.ok ? 0 : 2
        } catch {
            FileHandle.standardError.write(Data("conductor: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    private func makeRequest() throws -> ConductorControlRequest {
        let args = Array(arguments.dropFirst())
        guard let command = args.first else {
            throw CLIError.usage(Self.usage)
        }

        switch command {
        case "ping":
            return request(.appPing)
        case "status":
            return request(.appStatus)
        case "diagnostics":
            return try diagnosticsRequest(Array(args.dropFirst()))
        case "version":
            return request(.appVersion)
        case "quit":
            return request(.appQuit)
        case "workspace":
            return try workspaceRequest(Array(args.dropFirst()))
        case "surface":
            return try surfaceRequest(Array(args.dropFirst()))
        case "terminal":
            return try terminalRequest(Array(args.dropFirst()))
        case "browser":
            return try browserRequest(Array(args.dropFirst()))
        case "notify":
            return try notifyRequest(Array(args.dropFirst()))
        case "update":
            return try updateRequest(Array(args.dropFirst()))
        case "file":
            return try fileRequest(Array(args.dropFirst()))
        case "command":
            return try commandRequest(Array(args.dropFirst()))
        default:
            throw CLIError.usage(Self.usage)
        }
    }

    private func diagnosticsRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            return request(.appDiagnostics)
        }
        switch subcommand {
        case "export":
            var params: [String: ConductorControlJSON] = [:]
            if let outputPath = optionValue("--output", in: args) ?? optionValue("--path", in: args) {
                params["outputPath"] = .string(outputPath)
            }
            return request(.appDiagnosticsExport, params: params)
        case "status", "inspect":
            return request(.appDiagnostics)
        default:
            throw CLIError.usage("Usage: conductor diagnostics [export --output path]")
        }
    }

    private func workspaceRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor workspace list|metadata|create|select|rename|duplicate|close")
        }
        switch subcommand {
        case "list":
            return request(.workspaceList)
        case "metadata":
            var params: [String: ConductorControlJSON] = [:]
            if let workspaceID = optionValue("--workspace", in: args) ?? optionValue("--workspace-id", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.workspaceMetadata, params: params)
        case "create":
            let title = optionValue("--title", in: args)
            return request(.workspaceCreate, params: title.map { ["title": .string($0)] } ?? [:])
        case "select":
            guard args.count >= 2 else {
                throw CLIError.usage("Usage: conductor workspace select <workspace-id>")
            }
            return request(.workspaceSelect, params: ["workspaceID": .string(args[1])])
        case "rename":
            let title = optionValue("--title", in: args) ?? positionalValues(in: args).joined(separator: " ")
            guard !title.isEmpty else {
                throw CLIError.usage("Usage: conductor workspace rename <title> [--workspace workspace-id]")
            }
            var params: [String: ConductorControlJSON] = ["title": .string(title)]
            if let workspaceID = optionValue("--workspace", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.workspaceRename, params: params)
        case "duplicate":
            var params: [String: ConductorControlJSON] = [:]
            if let workspaceID = optionValue("--workspace", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.workspaceDuplicate, params: params)
        case "close":
            var params: [String: ConductorControlJSON] = [:]
            if let workspaceID = optionValue("--workspace", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.workspaceClose, params: params)
        default:
            throw CLIError.usage("Usage: conductor workspace list|metadata|create|select|rename|duplicate|close")
        }
    }

    private func surfaceRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor surface list|focus|split|close|zoom|move")
        }
        switch subcommand {
        case "list":
            return request(.surfaceList)
        case "focus":
            var params: [String: ConductorControlJSON] = [:]
            if let type = optionValue("--type", in: args) {
                params["type"] = .string(type)
            }
            if let workspaceID = optionValue("--workspace", in: args) ?? optionValue("--workspace-id", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--web-tab-id", in: args) {
                params["webTabID"] = .string(webTabID)
            } else if let fileTabID = optionValue("--file-tab", in: args) ?? optionValue("--file-tab-id", in: args) {
                params["fileTabID"] = .string(fileTabID)
            } else if let target = optionValue("--target", in: args),
                      let type = params["type"]?.stringValue?.lowercased(),
                      type == "browser" || type == "web" {
                params["webTabID"] = .string(target)
            } else if let target = optionValue("--target", in: args),
                      params["type"]?.stringValue?.lowercased() == "file" {
                params["fileTabID"] = .string(target)
            } else if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.surfaceFocus, params: params)
        case "split":
            let direction = optionValue("--direction", in: args)
                ?? (args.indices.contains(1) && !args[1].hasPrefix("--") ? args[1] : "right")
            return request(.surfaceSplit, params: ["direction": .string(direction)])
        case "close":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.surfaceClose, params: params)
        case "zoom":
            return request(.surfaceZoom)
        case "move":
            guard args.count >= 2 else {
                throw CLIError.usage("Usage: conductor surface move left|right|nextPane|newRightSplit|newDownSplit")
            }
            return request(.surfaceMove, params: ["mode": .string(args[1])])
        default:
            throw CLIError.usage("Usage: conductor surface list|focus|split|close|zoom|move")
        }
    }

    private func terminalRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor terminal send|send-key|sample-scroll|visible-text|restored-content|cwd|title|rename|agent|resume-agent|resume-agents|channel")
        }
        switch subcommand {
        case "send":
            let text: String
            if let value = optionValue("--text", in: args) {
                text = value
            } else {
                let stdin = FileHandle.standardInput.readDataToEndOfFile()
                text = String(data: stdin, encoding: .utf8) ?? ""
            }
            var params: [String: ConductorControlJSON] = ["text": .string(text)]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalSendText, params: params)
        case "send-key":
            guard args.count >= 2 else {
                throw CLIError.usage("Usage: conductor terminal send-key <key> [--target focused|terminal-id]")
            }
            var params: [String: ConductorControlJSON] = ["key": .string(args[1])]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalSendKey, params: params)
        case "sample-scroll":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalSampleScroll, params: params)
        case "visible-text":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalVisibleText, params: params)
        case "restored-content":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalRestoredContent, params: params)
        case "cwd":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalCwd, params: params)
        case "title":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalTitle, params: params)
        case "rename":
            let title = optionValue("--title", in: args) ?? positionalValues(in: args).joined(separator: " ")
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Usage: conductor terminal rename <title> [--target focused|terminal-id]")
            }
            var params: [String: ConductorControlJSON] = ["title": .string(title)]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalRename, params: params)
        case "agent":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            return request(.terminalAgent, params: params)
        case "resume-agent":
            var params: [String: ConductorControlJSON] = [:]
            if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--target", in: args),
               terminalID != "focused" {
                params["terminalID"] = .string(terminalID)
            }
            if args.contains("--dry-run") {
                params["dryRun"] = .bool(true)
            }
            return request(.terminalResumeAgent, params: params)
        case "resume-agents":
            var params: [String: ConductorControlJSON] = [:]
            if let workspace = optionValue("--workspace", in: args) ?? optionValue("--workspace-id", in: args) {
                if workspace == "all" {
                    params["scope"] = .string("all")
                } else if workspace != "current" {
                    params["workspaceID"] = .string(workspace)
                }
            }
            if args.contains("--all") || args.contains("--all-workspaces") {
                params["scope"] = .string("all")
            }
            if args.contains("--dry-run") {
                params["dryRun"] = .bool(true)
            }
            return request(.terminalResumeAgents, params: params)
        default:
            throw CLIError.usage("Usage: conductor terminal send|send-key|sample-scroll|visible-text|restored-content|cwd|title|rename|agent|resume-agent|resume-agents")
        }
    }

    private func browserRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor browser open|select|navigate|reload|stop|back|forward|snapshot|screenshot|click|fill|press|wait|find|evaluate")
        }
        switch subcommand {
        case "open":
            let input = positionalValues(in: args).joined(separator: " ")
            guard !input.isEmpty else {
                throw CLIError.usage("Usage: conductor browser open <url-or-query>")
            }
            return request(.browserOpen, params: ["input": .string(input)])
        case "select":
            let webTabID = optionValue("--web-tab", in: args)
                ?? optionValue("--target", in: args)
                ?? positionalValues(in: args).first
            guard let webTabID, !webTabID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Usage: conductor browser select <web-tab-id> [--workspace workspace-id]")
            }
            var params: [String: ConductorControlJSON] = ["webTabID": .string(webTabID)]
            if let workspaceID = optionValue("--workspace", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.browserSelect, params: params)
        case "navigate":
            let input = positionalValues(in: args).joined(separator: " ")
            guard !input.isEmpty else {
                throw CLIError.usage("Usage: conductor browser navigate <url-or-query> [--web-tab web-tab-id]")
            }
            var params: [String: ConductorControlJSON] = ["input": .string(input)]
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserNavigate, params: params)
        case "reload", "stop", "back", "forward":
            var params: [String: ConductorControlJSON] = [:]
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            let method: String
            switch subcommand {
            case "reload":
                method = .browserReload
            case "stop":
                method = .browserStop
            case "back":
                method = .browserBack
            default:
                method = .browserForward
            }
            return request(method, params: params)
        case "snapshot", "screenshot":
            var params: [String: ConductorControlJSON] = [:]
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(subcommand == "snapshot" ? .browserSnapshot : .browserScreenshot, params: params)
        case "click":
            let values = positionalValues(in: args)
            guard let target = values.first else {
                throw CLIError.usage("Usage: conductor browser click <ref-or-selector> [--target selected|web-tab-id]")
            }
            var params: [String: ConductorControlJSON] = ["target": .string(target)]
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserClick, params: params)
        case "fill":
            let values = positionalValues(in: args)
            guard let target = values.first else {
                throw CLIError.usage("Usage: conductor browser fill <ref-or-selector> <value> [--target selected|web-tab-id]")
            }
            let value = optionValue("--value", in: args) ?? values.dropFirst().joined(separator: " ")
            var params: [String: ConductorControlJSON] = [
                "target": .string(target),
                "value": .string(value)
            ]
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserFill, params: params)
        case "press":
            let values = positionalValues(in: args)
            guard let key = values.first else {
                throw CLIError.usage("Usage: conductor browser press <key> [--element ref-or-selector] [--target selected|web-tab-id]")
            }
            var params: [String: ConductorControlJSON] = ["key": .string(key)]
            if let elementTarget = optionValue("--element", in: args) {
                params["target"] = .string(elementTarget)
            }
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserPress, params: params)
        case "wait":
            let values = positionalValues(in: args)
            let knownConditions = Set([
                "selector",
                "element",
                "visible",
                "text",
                "load",
                "ready",
                "idle",
                "networkidle",
                "url",
                "title",
                "hidden",
                "gone",
                "detached"
            ])
            let condition: String
            let target: String
            if let selector = optionValue("--selector", in: args) {
                condition = "selector"
                target = selector
            } else if let text = optionValue("--text", in: args) {
                condition = "text"
                target = text
            } else if let url = optionValue("--url", in: args) {
                condition = "url"
                target = url
            } else if let title = optionValue("--title", in: args) {
                condition = "title"
                target = title
            } else if let hidden = optionValue("--hidden", in: args) {
                condition = "hidden"
                target = hidden
            } else if let gone = optionValue("--gone", in: args) {
                condition = "gone"
                target = gone
            } else if let explicitCondition = optionValue("--for", in: args) ?? optionValue("--condition", in: args) {
                condition = explicitCondition.lowercased()
                target = values.joined(separator: " ")
            } else if let first = values.first?.lowercased(), knownConditions.contains(first) {
                condition = first
                target = values.dropFirst().joined(separator: " ")
            } else {
                condition = "selector"
                target = values.joined(separator: " ")
            }
            let targetlessConditions = Set(["load", "ready", "idle", "networkidle"])
            if !targetlessConditions.contains(condition),
               target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw CLIError.usage("Usage: conductor browser wait load|idle|url <text>|title <text>|hidden <selector>|gone <selector>|text <text>|<selector> [--timeout seconds] [--target selected|web-tab-id]")
            }
            var params: [String: ConductorControlJSON] = [
                "condition": .string(condition),
                "target": .string(target)
            ]
            if let timeout = optionValue("--timeout", in: args) {
                guard let timeoutSeconds = Double(timeout) else {
                    throw CLIError.usage("Usage: conductor browser wait ... [--timeout seconds]")
                }
                params["timeoutSeconds"] = .double(timeoutSeconds)
            }
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserWait, params: params)
        case "find":
            let query = optionValue("--query", in: args) ?? positionalValues(in: args).joined(separator: " ")
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Usage: conductor browser find <text> [--frame frame-id] [--target selected|web-tab-id]")
            }
            var params: [String: ConductorControlJSON] = ["query": .string(query)]
            if let frameID = optionValue("--frame", in: args) {
                params["frameID"] = .string(frameID)
            }
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserFind, params: params)
        case "evaluate":
            let script = optionValue("--script", in: args) ?? positionalValues(in: args).joined(separator: " ")
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Usage: conductor browser evaluate <javascript> [--frame frame-id] [--target selected|web-tab-id]")
            }
            var params: [String: ConductorControlJSON] = ["script": .string(script)]
            if let frameID = optionValue("--frame", in: args) {
                params["frameID"] = .string(frameID)
            }
            if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--target", in: args),
               webTabID != "selected" {
                params["webTabID"] = .string(webTabID)
            }
            return request(.browserEvaluate, params: params)
        default:
            throw CLIError.usage("Usage: conductor browser open|select|navigate|reload|stop|back|forward|snapshot|screenshot|click|fill|press|wait|find|evaluate")
        }
    }

    private func notifyRequest(_ args: [String]) throws -> ConductorControlRequest {
        if args.first == "list" {
            return request(.notificationList)
        }
        if args.first == "clear" {
            var params: [String: ConductorControlJSON] = [:]
            if args.count >= 2 {
                params["notificationID"] = .string(args[1])
            }
            return request(.notificationClear, params: params)
        }
        if args.first == "focus" {
            guard args.count >= 2 else {
                throw CLIError.usage("Usage: conductor notify focus <notification-id>")
            }
            return request(.notificationFocus, params: ["notificationID": .string(args[1])])
        }
        if args.first == "latest" || args.first == "focus-latest" {
            var params: [String: ConductorControlJSON] = [:]
            if let workspaceID = optionValue("--workspace", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.notificationFocusLatest, params: params)
        }
        if args.first == "mark-read" {
            var params: [String: ConductorControlJSON] = [:]
            if let workspaceID = optionValue("--workspace", in: args) {
                params["workspaceID"] = .string(workspaceID)
            }
            return request(.notificationMarkRead, params: params)
        }
        if args.first == "test" {
            var params: [String: ConductorControlJSON] = [
                "title": .string(optionValue("--title", in: args) ?? "Conductor Test Notification"),
                "body": .string(optionValue("--body", in: args) ?? "If you see this banner, system notification delivery is working.")
            ]
            if args.contains("--silent") {
                params["playSound"] = .bool(false)
            }
            return request(.notificationTest, params: params)
        }
        let title = args.first ?? ""
        guard !title.isEmpty else {
            throw CLIError.usage("Usage: conductor notify <title> [--body text] | list | clear | focus <notification-id> | latest | mark-read | test [--title title] [--body text] [--silent]")
        }
        var params: [String: ConductorControlJSON] = ["title": .string(title)]
        if let body = optionValue("--body", in: args) {
            params["body"] = .string(body)
        }
        if let workspaceID = optionValue("--workspace", in: args) ?? optionValue("--workspace-id", in: args) {
            params["workspaceID"] = .string(workspaceID)
        }
        if let terminalID = optionValue("--terminal", in: args) ?? optionValue("--terminal-id", in: args) ?? optionValue("--target", in: args),
           terminalID != "focused" {
            params["terminalID"] = .string(terminalID)
        }
        if let webTabID = optionValue("--web-tab", in: args) ?? optionValue("--web-tab-id", in: args),
           webTabID != "selected" {
            params["webTabID"] = .string(webTabID)
        }
        return request(.notificationCreate, params: params)
    }

    private func commandRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor command list|run")
        }
        switch subcommand {
        case "list":
            return request(.commandList)
        case "run":
            guard args.count >= 2 else {
                throw CLIError.usage("Usage: conductor command run <command-id>")
            }
            return request(.commandRun, params: ["command": .string(args[1])])
        default:
            throw CLIError.usage("Usage: conductor command list|run")
        }
    }

    private func updateRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor update status|check|download|cancel|install|rehearse-install")
        }
        switch subcommand {
        case "status":
            return request(.updateStatus)
        case "check":
            var params: [String: ConductorControlJSON] = [:]
            if let manifestURL = optionValue("--manifest", in: args)
                ?? optionValue("--url", in: args)
                ?? positionalValues(in: args).first {
                params["manifestURL"] = .string(manifestURL)
            }
            if let timeout = optionValue("--timeout", in: args) {
                guard let timeoutSeconds = Double(timeout) else {
                    throw CLIError.usage("Usage: conductor update check [--manifest url-or-path] [--timeout seconds]")
                }
                params["timeoutSeconds"] = .double(timeoutSeconds)
            }
            return request(.updateCheck, params: params)
        case "download":
            var params: [String: ConductorControlJSON] = [:]
            if let timeout = optionValue("--timeout", in: args) {
                guard let timeoutSeconds = Double(timeout) else {
                    throw CLIError.usage("Usage: conductor update download [--timeout seconds]")
                }
                params["timeoutSeconds"] = .double(timeoutSeconds)
            }
            return request(.updateDownload, params: params)
        case "cancel":
            return request(.updateCancel)
        case "install":
            return request(.updateInstall)
        case "rehearse-install", "rehearse":
            return request(.updateRehearseInstall)
        default:
            throw CLIError.usage("Usage: conductor update status|check|download|cancel|install|rehearse-install")
        }
    }

    private func fileRequest(_ args: [String]) throws -> ConductorControlRequest {
        guard let subcommand = args.first else {
            throw CLIError.usage("Usage: conductor file open|reveal|save|snapshot")
        }
        switch subcommand {
        case "open":
            let path = optionValue("--path", in: args) ?? positionalValues(in: args).first
            guard let path else {
                throw CLIError.usage("Usage: conductor file open <path> [--root path]")
            }
            var params: [String: ConductorControlJSON] = ["path": .string(path)]
            if let root = optionValue("--root", in: args) ?? optionValue("--root-path", in: args) {
                params["rootPath"] = .string(root)
            }
            return request(.fileOpen, params: params)
        case "reveal":
            var params: [String: ConductorControlJSON] = [:]
            if let path = optionValue("--path", in: args) ?? positionalValues(in: args).first {
                params["path"] = .string(path)
            }
            if let root = optionValue("--root", in: args) ?? optionValue("--root-path", in: args) {
                params["rootPath"] = .string(root)
            }
            return request(.fileReveal, params: params)
        case "save":
            var params: [String: ConductorControlJSON] = [:]
            let values = positionalValues(in: args)
            if let target = optionValue("--target", in: args) ?? optionValue("--path", in: args) ?? values.first {
                params["target"] = .string(target)
            }
            if let text = optionValue("--text", in: args) {
                params["text"] = .string(text)
            } else if args.contains("--stdin") {
                let stdin = FileHandle.standardInput.readDataToEndOfFile()
                params["text"] = .string(String(data: stdin, encoding: .utf8) ?? "")
            }
            return request(.fileSave, params: params)
        case "snapshot":
            var params: [String: ConductorControlJSON] = [:]
            if let target = optionValue("--target", in: args) ?? optionValue("--path", in: args) ?? positionalValues(in: args).first {
                params["target"] = .string(target)
            }
            if args.contains("--text") || args.contains("--include-text") {
                params["includeText"] = .bool(true)
            }
            if let maxTextBytes = optionValue("--max-text-bytes", in: args) {
                guard let parsed = Double(maxTextBytes) else {
                    throw CLIError.usage("Usage: conductor file snapshot [--target selected|path|file-tab-id] [--text] [--max-text-bytes bytes]")
                }
                params["maxTextBytes"] = .double(parsed)
            }
            return request(.fileSnapshot, params: params)
        default:
            throw CLIError.usage("Usage: conductor file open|reveal|save|snapshot")
        }
    }

    private func request(
        _ method: String,
        params: [String: ConductorControlJSON] = [:]
    ) -> ConductorControlRequest {
        ConductorControlRequest(
            method: method,
            params: params,
            client: ConductorControlClient(name: "conductor-cli", version: "0.0.1")
        )
    }

    private func send(_ request: ConductorControlRequest) throws -> ConductorControlResponse {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(fd) }

        let socketURL = ConductorControlSocket.socketURL()
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < pathCapacity else {
            throw CLIError.socketPathTooLong(path)
        }
        _ = withUnsafeMutablePointer(to: &address.sun_path.0) { pointer in
            path.withCString { source in
                strncpy(pointer, source, pathCapacity - 1)
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw CLIError.appNotRunning(socketURL.path)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var payload = try encoder.encode(request)
        payload.append(0x0A)
        try payload.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let written = Darwin.write(fd, baseAddress, payload.count)
            guard written == payload.count else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
            if data.contains(0x0A) { break }
        }
        guard let newlineIndex = data.firstIndex(of: 0x0A) else {
            throw CLIError.noResponse
        }
        let line = data[..<newlineIndex]
        return try JSONDecoder().decode(ConductorControlResponse.self, from: Data(line))
    }

    private func printResponse(_ response: ConductorControlResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(response)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private func optionValue(_ option: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: option),
              args.indices.contains(index + 1) else {
            return nil
        }
        return args[index + 1]
    }

    private func positionalValues(in args: [String], startingAt startIndex: Int = 1) -> [String] {
        var values: [String] = []
        var index = startIndex
        while index < args.count {
            let token = args[index]
            if token.hasPrefix("--") {
                index += 2
            } else {
                values.append(token)
                index += 1
            }
        }
        return values
    }

    private static let usage = """
    Usage:
      conductor ping
      conductor status
      conductor diagnostics
      conductor diagnostics export [--output path]
      conductor version
      conductor quit
      conductor workspace list
      conductor workspace metadata [--workspace workspace-id]
      conductor workspace create [--title title]
      conductor workspace select <workspace-id>
      conductor workspace rename <title> [--workspace workspace-id]
      conductor workspace duplicate [--workspace workspace-id]
      conductor workspace close [--workspace workspace-id]
      conductor surface list
      conductor surface focus [--target focused|terminal-id] [--web-tab web-tab-id] [--file-tab file-tab-id] [--workspace workspace-id]
      conductor surface split [left|right|up|down]
      conductor surface close [--target focused|terminal-id]
      conductor surface zoom
      conductor surface move left|right|nextPane|newRightSplit|newDownSplit
      conductor terminal send [--text text] [--target focused|terminal-id]
      conductor terminal send-key <key> [--target focused|terminal-id]
      conductor terminal sample-scroll [--target focused|terminal-id]
      conductor terminal visible-text [--target focused|terminal-id]
      conductor terminal restored-content [--target focused|terminal-id]
      conductor terminal cwd [--target focused|terminal-id]
      conductor terminal title [--target focused|terminal-id]
      conductor terminal rename <title> [--target focused|terminal-id]
      conductor terminal agent [--target focused|terminal-id]
      conductor terminal resume-agent [--target focused|terminal-id] [--dry-run]
      conductor terminal resume-agents [--workspace current|all|workspace-id] [--dry-run]
      conductor browser open <url-or-query>
      conductor browser select <web-tab-id> [--workspace workspace-id]
      conductor browser navigate <url-or-query> [--target selected|web-tab-id]
      conductor browser reload|stop|back|forward [--target selected|web-tab-id]
      conductor browser snapshot [--target selected|web-tab-id]
      conductor browser screenshot [--target selected|web-tab-id]
      conductor browser click <ref-or-selector> [--target selected|web-tab-id]
      conductor browser fill <ref-or-selector> <value> [--target selected|web-tab-id]
      conductor browser press <key> [--element ref-or-selector] [--target selected|web-tab-id]
      conductor browser wait load|idle|url <text>|title <text>|hidden <selector>|gone <selector>|text <text>|<selector> [--timeout seconds] [--target selected|web-tab-id]
      conductor browser find <text> [--frame frame-id] [--target selected|web-tab-id]
      conductor browser evaluate <javascript> [--frame frame-id] [--target selected|web-tab-id]
      conductor notify <title> [--body text] [--workspace workspace-id] [--terminal terminal-id] [--web-tab web-tab-id] | list | clear [notification-id] | focus <notification-id> | latest | mark-read [--workspace workspace-id] | test [--title title] [--body text] [--silent]
      conductor update status
      conductor update check [--manifest url-or-path] [--timeout seconds]
      conductor update download [--timeout seconds]
      conductor update cancel
      conductor update rehearse-install
      conductor update install
      conductor file open <path> [--root path]
      conductor file reveal [path] [--root path]
      conductor file save [target] [--text text|--stdin]
      conductor file snapshot [--target selected|path|file-tab-id] [--text] [--max-text-bytes bytes]
      conductor command list
      conductor command run <command-id>
    """
}

private enum CLIError: LocalizedError {
    case usage(String)
    case appNotRunning(String)
    case socketPathTooLong(String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        case .appNotRunning(let path):
            "Conductor is not running or the control socket is unavailable at \(path)."
        case .socketPathTooLong(let path):
            "Control socket path is too long: \(path)"
        case .noResponse:
            "Conductor did not return a control response."
        }
    }
}

extension String {
    fileprivate static let appPing = ConductorControlMethod.appPing
    fileprivate static let appStatus = ConductorControlMethod.appStatus
    fileprivate static let appDiagnostics = ConductorControlMethod.appDiagnostics
    fileprivate static let appDiagnosticsExport = ConductorControlMethod.appDiagnosticsExport
    fileprivate static let appQuit = ConductorControlMethod.appQuit
    fileprivate static let appVersion = ConductorControlMethod.appVersion
    fileprivate static let workspaceList = ConductorControlMethod.workspaceList
    fileprivate static let workspaceCreate = ConductorControlMethod.workspaceCreate
    fileprivate static let workspaceSelect = ConductorControlMethod.workspaceSelect
    fileprivate static let workspaceRename = ConductorControlMethod.workspaceRename
    fileprivate static let workspaceDuplicate = ConductorControlMethod.workspaceDuplicate
    fileprivate static let workspaceClose = ConductorControlMethod.workspaceClose
    fileprivate static let workspaceMetadata = ConductorControlMethod.workspaceMetadata
    fileprivate static let surfaceList = ConductorControlMethod.surfaceList
    fileprivate static let surfaceFocus = ConductorControlMethod.surfaceFocus
    fileprivate static let surfaceSplit = ConductorControlMethod.surfaceSplit
    fileprivate static let surfaceClose = ConductorControlMethod.surfaceClose
    fileprivate static let surfaceZoom = ConductorControlMethod.surfaceZoom
    fileprivate static let surfaceMove = ConductorControlMethod.surfaceMove
    fileprivate static let terminalSendText = ConductorControlMethod.terminalSendText
    fileprivate static let terminalSendKey = ConductorControlMethod.terminalSendKey
    fileprivate static let terminalVisibleText = ConductorControlMethod.terminalVisibleText
    fileprivate static let terminalRestoredContent = ConductorControlMethod.terminalRestoredContent
    fileprivate static let terminalCwd = ConductorControlMethod.terminalCwd
    fileprivate static let terminalTitle = ConductorControlMethod.terminalTitle
    fileprivate static let terminalRename = ConductorControlMethod.terminalRename
    fileprivate static let terminalSampleScroll = ConductorControlMethod.terminalSampleScroll
    fileprivate static let terminalAgent = ConductorControlMethod.terminalAgent
    fileprivate static let terminalResumeAgent = ConductorControlMethod.terminalResumeAgent
    fileprivate static let terminalResumeAgents = ConductorControlMethod.terminalResumeAgents
    fileprivate static let browserOpen = ConductorControlMethod.browserOpen
    fileprivate static let browserSelect = ConductorControlMethod.browserSelect
    fileprivate static let browserNavigate = ConductorControlMethod.browserNavigate
    fileprivate static let browserReload = ConductorControlMethod.browserReload
    fileprivate static let browserStop = ConductorControlMethod.browserStop
    fileprivate static let browserBack = ConductorControlMethod.browserBack
    fileprivate static let browserForward = ConductorControlMethod.browserForward
    fileprivate static let browserSnapshot = ConductorControlMethod.browserSnapshot
    fileprivate static let browserScreenshot = ConductorControlMethod.browserScreenshot
    fileprivate static let browserClick = ConductorControlMethod.browserClick
    fileprivate static let browserFill = ConductorControlMethod.browserFill
    fileprivate static let browserPress = ConductorControlMethod.browserPress
    fileprivate static let browserWait = ConductorControlMethod.browserWait
    fileprivate static let browserFind = ConductorControlMethod.browserFind
    fileprivate static let browserEvaluate = ConductorControlMethod.browserEvaluate
    fileprivate static let notificationCreate = ConductorControlMethod.notificationCreate
    fileprivate static let notificationList = ConductorControlMethod.notificationList
    fileprivate static let notificationClear = ConductorControlMethod.notificationClear
    fileprivate static let notificationFocus = ConductorControlMethod.notificationFocus
    fileprivate static let notificationFocusLatest = ConductorControlMethod.notificationFocusLatest
    fileprivate static let notificationMarkRead = ConductorControlMethod.notificationMarkRead
    fileprivate static let notificationTest = ConductorControlMethod.notificationTest
    fileprivate static let updateStatus = ConductorControlMethod.updateStatus
    fileprivate static let updateCheck = ConductorControlMethod.updateCheck
    fileprivate static let updateDownload = ConductorControlMethod.updateDownload
    fileprivate static let updateCancel = ConductorControlMethod.updateCancel
    fileprivate static let updateInstall = ConductorControlMethod.updateInstall
    fileprivate static let updateRehearseInstall = ConductorControlMethod.updateRehearseInstall
    fileprivate static let fileOpen = ConductorControlMethod.fileOpen
    fileprivate static let fileReveal = ConductorControlMethod.fileReveal
    fileprivate static let fileSave = ConductorControlMethod.fileSave
    fileprivate static let fileSnapshot = ConductorControlMethod.fileSnapshot
    fileprivate static let commandList = ConductorControlMethod.commandList
    fileprivate static let commandRun = ConductorControlMethod.commandRun
}

exit(ConductorCLI(arguments: CommandLine.arguments).run())
