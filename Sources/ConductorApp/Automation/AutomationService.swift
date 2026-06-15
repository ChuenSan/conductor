import AppKit
import ConductorCore
import Foundation

/// 自动化方法分发：一行 JSON 请求 → 查表 → 调 coordinator → 一行 JSON 响应。
/// 全部在 MainActor 执行（与 UI 同一事实源，天然无竞态）。
@MainActor
final class AutomationService {
    private weak var coordinator: AppCoordinator?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    /// socket 服务器的行处理入口。
    nonisolated func handleLine(_ line: Data) async -> Data {
        let request: AutomationRequest
        do {
            request = try AutomationCodec.decodeRequest(line)
        } catch {
            return AutomationCodec.encode(AutomationResponse(
                id: nil, error: .badRequest("请求不是合法 JSON：\(error.localizedDescription)")))
        }
        let response = await dispatch(request)
        return AutomationCodec.encode(response)
    }

    private func dispatch(_ request: AutomationRequest) async -> AutomationResponse {
        guard let coordinator else {
            return AutomationResponse(id: request.id, error: .internalError("应用尚未就绪"))
        }
        do {
            let result = try handle(method: request.method, params: request.parameters,
                                    coordinator: coordinator)
            return AutomationResponse(id: request.id, result: result)
        } catch let error as AutomationError {
            return AutomationResponse(id: request.id, error: error)
        } catch {
            return AutomationResponse(id: request.id, error: .internalError("\(error)"))
        }
    }

    // MARK: - 方法表

    private func handle(method: String, params: [String: JSONValue],
                        coordinator c: AppCoordinator) throws -> JSONValue {
        func str(_ key: String) -> String? { params[key]?.stringValue }
        func requireStr(_ key: String) throws -> String {
            guard let value = str(key), !value.isEmpty else {
                throw AutomationError.badRequest("缺少参数：\(key)")
            }
            return value
        }

        switch method {
        // —— 系统 ——
        case "ping":
            return .object([
                "pong": .bool(true),
                "protocol": .int(AutomationProtocol.version),
                "app": .string("Conductor"),
            ])
        case "open-agent-tools", "open-agent-tools-management":
            let rawModule = str("module") ?? AgentToolsManagementModule.overview.rawValue
            guard let module = AgentToolsManagementModule(rawValue: rawModule) else {
                let supported = AgentToolsManagementModule.railModules.map(\.rawValue).joined(separator: ", ")
                throw AutomationError.badRequest("module 只支持：\(supported)")
            }
            c.openAgentToolsManagement(module)
            return .object([
                "module": .string(module.rawValue),
                "window": .string("agent-tools"),
            ])
        #if DEBUG
        case "debug-agent-tools-smoke-test":
            return try debugAgentToolsSmokeTest()
        #endif

        // —— 工作区 ——
        case "list-workspaces":
            return .array(c.store.workspaces.map { c.automationDescribe(workspace: $0) })
        case "current-workspace":
            return c.automationDescribe(workspace: try c.automationFindWorkspace(nil))
        case "select-workspace":
            try c.automationSelectWorkspace(try requireStr("workspace"))
            return .bool(true)
        case "new-workspace":
            let workspace = try c.automationNewWorkspace(path: try requireStr("path"),
                                                         name: str("name"))
            return c.automationDescribe(workspace: workspace)
        case "rename-workspace":
            let workspace = try c.automationFindWorkspace(try requireStr("workspace"))
            c.renameWorkspace(workspace.id, to: try requireStr("name"))
            return .bool(true)
        case "close-workspace":
            let workspace = try c.automationFindWorkspace(try requireStr("workspace"))
            c.removeWorkspace(workspace.id)
            return .bool(true)

        // —— 标签 ——
        case "list-tabs":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            return .array(workspace.tabs.map { c.automationDescribe(tab: $0, in: workspace) })
        case "new-tab":
            let (tab, pane) = try c.automationNewTab(workspaceRef: str("workspace"),
                                                     cwd: str("cwd"))
            return .object(["tab": .string(tab.value), "pane": .string(pane.value)])
        case "select-tab":
            try c.automationSelectTab(try requireStr("tab"), workspaceRef: str("workspace"))
            return .bool(true)
        case "rename-tab":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            let tab = try c.automationFindTab(try requireStr("tab"), in: workspace)
            c.renameTab(tab.id, to: try requireStr("title"))
            return .bool(true)
        case "close-tab":
            try c.automationCloseTab(try requireStr("tab"), workspaceRef: str("workspace"))
            return .bool(true)

        // —— pane ——
        case "list-panes":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            let tab = try c.automationFindTab(str("tab"), in: workspace)
            return .array(tab.rootSplit.leaves().map { c.automationDescribe(pane: $0, in: tab) })
        case "split":
            let direction = str("direction") ?? "right"
            let axis: SplitAxis
            switch direction {
            case "right", "vertical": axis = .vertical
            case "down", "horizontal": axis = .horizontal
            default: throw AutomationError.badRequest("direction 只支持 right / down")
            }
            let pane = try c.automationSplit(paneRef: str("pane"), axis: axis, cwd: str("cwd"))
            return .object(["pane": .string(pane.value)])
        case "focus-pane":
            try c.automationFocusPane(try requireStr("pane"))
            return .bool(true)
        case "close-pane":
            try c.automationClosePane(str("pane"))
            return .bool(true)
        case "tree":
            return try c.automationTree(workspaceRef: str("workspace"))

        // —— 终端 I/O ——
        case "send-text":
            try c.automationSendText(paneRef: str("pane"),
                                     text: try requireStr("text"),
                                     submit: params["submit"]?.boolValue ?? true)
            return .bool(true)
        case "send-keys":
            let keys = (params["keys"]?.arrayValue ?? []).compactMap(\.stringValue)
            guard !keys.isEmpty else { throw AutomationError.badRequest("缺少参数：keys") }
            try c.automationSendKeys(paneRef: str("pane"), keys: keys)
            return .bool(true)
        case "read-screen", "capture-pane":
            let text = try c.automationReadScreen(paneRef: str("pane"),
                                                  scrollback: params["scrollback"]?.boolValue ?? false)
            return .object(["text": .string(text)])
        case "surface-resume-set", "resume-set":
            let binding = try c.automationSetSurfaceResume(
                paneRef: str("pane"),
                kind: str("kind") ?? "shell",
                checkpoint: str("checkpoint"),
                command: try requireStr("command"),
                autoResume: params["autoResume"]?.boolValue ?? false,
                trusted: params["trusted"]?.boolValue ?? false)
            return c.automationDescribe(binding: binding)
        case "surface-resume-show", "resume-show":
            guard let binding = try c.automationShowSurfaceResume(paneRef: str("pane")) else {
                return .null
            }
            return c.automationDescribe(binding: binding)
        case "surface-resume-clear", "resume-clear":
            let removed = try c.automationClearSurfaceResume(paneRef: str("pane"))
            return removed.map { c.automationDescribe(binding: $0) } ?? .null

        // —— 通知 ——
        case "notify":
            c.automationNotify(paneRef: str("pane"),
                               title: str("title") ?? "",
                               body: try requireStr("message"))
            return .bool(true)

        // —— 侧栏元数据（状态 / 进度 / 日志）——
        case "set-status":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.setStatus(workspace: workspace.id,
                                          key: try requireStr("key"),
                                          text: try requireStr("text"),
                                          color: str("color"),
                                          icon: str("icon"))
            return .bool(true)
        case "clear-status":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.clearStatus(workspace: workspace.id, key: str("key"))
            return .bool(true)
        case "list-status":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            return .array(c.workspaceMetadata.statuses(for: workspace.id).map { status in
                .object([
                    "key": .string(status.key),
                    "text": .string(status.text),
                    "color": status.color.map(JSONValue.string) ?? .null,
                    "icon": status.icon.map(JSONValue.string) ?? .null,
                ])
            })
        case "set-progress":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            guard let value = params["value"]?.doubleValue, (0...1).contains(value) else {
                throw AutomationError.badRequest("value 需在 0–1 之间")
            }
            c.workspaceMetadata.setProgress(workspace: workspace.id, value: value,
                                            label: str("label"))
            return .bool(true)
        case "clear-progress":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.clearProgress(workspace: workspace.id)
            return .bool(true)
        case "log":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.appendLog(workspace: workspace.id,
                                          text: try requireStr("text"),
                                          level: str("level") ?? "info",
                                          source: str("source"))
            return .bool(true)
        case "list-log":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            let limit = params["limit"]?.intValue ?? 50
            return .array(c.workspaceMetadata.logs(for: workspace.id, limit: limit).map { entry in
                .object([
                    "time": .double(entry.time.timeIntervalSince1970),
                    "level": .string(entry.level),
                    "source": entry.source.map(JSONValue.string) ?? .null,
                    "text": .string(entry.text),
                ])
            })
        case "clear-log":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.clearLog(workspace: workspace.id)
            return .bool(true)

        default:
            throw AutomationError.unknownMethod(method)
        }
    }

    #if DEBUG
    private func debugAgentToolsSmokeTest() throws -> JSONValue {
        func fail(_ message: String) throws -> Never {
            throw AutomationError.internalError(message)
        }

        let mcpSteps = try AgentToolsMCPScanner.debugSmokeTest()

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("conductor-hooks-smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("settings.json")
        let doc = HookConfigDocument(url: url, source: .claude)
        let command = "printf smoke #conductor:smoke"
        try doc.addCommand(event: HookEventName.stop, command: command, timeout: 3210)

        var entries = doc.entries()
        guard entries.count == 1,
              entries[0].event == HookEventName.stop,
              entries[0].command == command,
              entries[0].timeout == 3210,
              entries[0].managedByConductor else {
            try fail("hook command was not written correctly")
        }

        try doc.addCommand(event: HookEventName.stop, command: command, timeout: 3210)
        entries = doc.entries()
        guard entries.count == 1 else {
            try fail("duplicate hook command was written")
        }

        let removed = try doc.removeCommands(containing: "#conductor:smoke")
        guard removed == 1, doc.entries().isEmpty else {
            try fail("hook command was not removed")
        }

        return .object([
            "mcp": .array(mcpSteps.map(JSONValue.string)),
            "hooks": .array([
                .string("wrote command hook"),
                .string("deduplicated command hook"),
                .string("removed command hook"),
            ]),
        ])
    }
    #endif
}
