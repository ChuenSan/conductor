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
        case "app.ping":
            return .object([
                "pong": .bool(true),
                "protocol": .int(AutomationProtocol.version),
                "app": .string("Conductor"),
                "socket": .string(AutomationProtocol.defaultSocketURL.path),
            ])
        case "app.status":
            return c.automationStatus(methods: Self.methodNames)
        case "app.methods":
            return .array(Self.methodNames.map(JSONValue.string))
        case "tools.open":
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
        case "debug.agentToolsSmokeTest":
            return try debugAgentToolsSmokeTest()
        #endif

        // —— 工作区 ——
        case "workspace.list":
            return .array(c.store.workspaces.map { c.automationDescribe(workspace: $0) })
        case "workspace.current":
            return c.automationDescribe(workspace: try c.automationFindWorkspace(nil))
        case "workspace.select":
            try c.automationSelectWorkspace(try requireStr("workspace"))
            return .bool(true)
        case "workspace.create":
            let workspace = try c.automationNewWorkspace(path: try requireStr("path"),
                                                         name: str("name"))
            return c.automationDescribe(workspace: workspace)
        case "workspace.rename":
            let workspace = try c.automationFindWorkspace(try requireStr("workspace"))
            c.renameWorkspace(workspace.id, to: try requireStr("name"))
            return .bool(true)
        case "workspace.close":
            let workspace = try c.automationFindWorkspace(try requireStr("workspace"))
            c.removeWorkspace(workspace.id)
            return .bool(true)

        // —— 标签 ——
        case "tab.list":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            return .array(workspace.tabs.map { c.automationDescribe(tab: $0, in: workspace) })
        case "pane.create":
            let (tab, pane) = try c.automationNewTab(workspaceRef: str("workspace"),
                                                     cwd: str("cwd"))
            return .object(["tab": .string(tab.value), "pane": .string(pane.value)])
        case "tab.select":
            try c.automationSelectTab(try requireStr("tab"), workspaceRef: str("workspace"))
            return .bool(true)
        case "tab.rename":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            let tab = try c.automationFindTab(try requireStr("tab"), in: workspace)
            c.renameTab(tab.id, to: try requireStr("title"))
            return .bool(true)
        case "tab.close":
            try c.automationCloseTab(try requireStr("tab"), workspaceRef: str("workspace"))
            return .bool(true)

        // —— pane ——
        case "pane.list":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            let tab = try c.automationFindTab(str("tab"), in: workspace)
            return .array(tab.rootSplit.leaves().map { c.automationDescribe(pane: $0, in: tab) })
        case "pane.split":
            let direction = str("direction") ?? "right"
            let axis: SplitAxis
            switch direction {
            case "right", "vertical": axis = .vertical
            case "down", "horizontal": axis = .horizontal
            default: throw AutomationError.badRequest("direction 只支持 right / down")
            }
            let pane = try c.automationSplit(paneRef: str("pane"), axis: axis, cwd: str("cwd"))
            return .object(["pane": .string(pane.value)])
        case "pane.focus":
            try c.automationFocusPane(try requireStr("pane"))
            return .bool(true)
        case "pane.close":
            try c.automationClosePane(str("pane"))
            return .bool(true)
        case "workspace.tree":
            return try c.automationTree(workspaceRef: str("workspace"))

        // —— 终端 I/O ——
        case "agent.run":
            let requestedAgent = str("agent") ?? str("command")
            guard let requestedAgent, !requestedAgent.isEmpty else {
                throw AutomationError.badRequest("缺少参数：agent")
            }
            let descriptor = AgentCatalog.all.first {
                $0.id == requestedAgent || $0.command == requestedAgent
            }
            let command = str("command") ?? descriptor?.command ?? requestedAgent
            let agentID = str("agent").flatMap { raw in
                descriptor?.id ?? AgentCatalog.all.first(where: { $0.id == raw || $0.command == raw })?.id
            } ?? descriptor?.id
            let cwd = str("cwd").map { ($0 as NSString).expandingTildeInPath }
            let pane = c.launchAutomationAgent(
                command: command,
                agentID: agentID,
                cwd: cwd,
                prompt: str("prompt"),
                submit: params["submit"]?.boolValue ?? true)
            let located = c.automationLocate(pane)
            return .object([
                "pane": .string(pane.value),
                "jobId": .string(pane.value),
                "tab": located.map { .string($0.1.id.value) } ?? .null,
                "workspace": located.map { .string($0.0.id.value) } ?? .null,
                "agent": agentID.map(JSONValue.string) ?? .null,
                "command": .string(command),
                "promptSent": .bool(str("prompt")?.isEmpty == false),
            ])
        case "agent.status":
            return try c.automationAgentStatus(jobRef: str("job") ?? str("jobId") ?? str("pane"))
        case "agent.result":
            return try c.automationAgentResult(jobRef: str("job") ?? str("jobId") ?? str("pane"))
        case "agent.send":
            try c.automationSendText(paneRef: str("pane"),
                                     text: try requireStr("text"),
                                     submit: params["submit"]?.boolValue ?? true)
            return .bool(true)
        case "terminal.keys":
            let keys = (params["keys"]?.arrayValue ?? []).compactMap(\.stringValue)
            guard !keys.isEmpty else { throw AutomationError.badRequest("缺少参数：keys") }
            try c.automationSendKeys(paneRef: str("pane"), keys: keys)
            return .bool(true)
        case "pane.read":
            let text = try c.automationReadScreen(paneRef: str("pane"),
                                                  scrollback: params["scrollback"]?.boolValue ?? false)
            return .object(["text": .string(text)])
        // —— 通知 ——
        case "notification.send":
            c.automationNotify(paneRef: str("pane"),
                               title: str("title") ?? "",
                               body: try requireStr("message"))
            return .bool(true)
        case "activity.list":
            return c.automationListActivity(limit: params["limit"]?.intValue ?? 20)
        case "events.recent":
            return c.automationRecentEvents(limit: params["limit"]?.intValue ?? 20)

        // —— 侧栏元数据（状态 / 进度 / 日志）——
        case "workspace.status.set":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.setStatus(workspace: workspace.id,
                                          key: try requireStr("key"),
                                          text: try requireStr("text"),
                                          color: str("color"),
                                          icon: str("icon"))
            return .bool(true)
        case "workspace.status.clear":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.clearStatus(workspace: workspace.id, key: str("key"))
            return .bool(true)
        case "workspace.status.list":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            return .array(c.workspaceMetadata.statuses(for: workspace.id).map { status in
                .object([
                    "key": .string(status.key),
                    "text": .string(status.text),
                    "color": status.color.map(JSONValue.string) ?? .null,
                    "icon": status.icon.map(JSONValue.string) ?? .null,
                ])
            })
        case "workspace.progress.set":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            guard let value = params["value"]?.doubleValue, (0...1).contains(value) else {
                throw AutomationError.badRequest("value 需在 0–1 之间")
            }
            c.workspaceMetadata.setProgress(workspace: workspace.id, value: value,
                                            label: str("label"))
            return .bool(true)
        case "workspace.progress.clear":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.clearProgress(workspace: workspace.id)
            return .bool(true)
        case "workspace.log.append":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.appendLog(workspace: workspace.id,
                                          text: try requireStr("text"),
                                          level: str("level") ?? "info",
                                          source: str("source"))
            return .bool(true)
        case "workspace.log.list":
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
        case "workspace.log.clear":
            let workspace = try c.automationFindWorkspace(str("workspace"))
            c.workspaceMetadata.clearLog(workspace: workspace.id)
            return .bool(true)

        default:
            throw AutomationError.unknownMethod(method)
        }
    }

    private static let methodNames: [String] = [
        "app.ping",
        "app.status",
        "app.methods",
        "tools.open",
        "workspace.list",
        "workspace.current",
        "workspace.select",
        "workspace.create",
        "workspace.rename",
        "workspace.close",
        "workspace.tree",
        "tab.list",
        "tab.select",
        "tab.rename",
        "tab.close",
        "pane.list",
        "pane.create",
        "pane.split",
        "pane.focus",
        "pane.close",
        "pane.read",
        "agent.run",
        "agent.status",
        "agent.result",
        "agent.send",
        "activity.list",
        "events.recent",
        "terminal.keys",
        "notification.send",
        "workspace.status.set",
        "workspace.status.clear",
        "workspace.status.list",
        "workspace.progress.set",
        "workspace.progress.clear",
        "workspace.log.append",
        "workspace.log.list",
        "workspace.log.clear",
    ]

    #if DEBUG
    private func debugAgentToolsSmokeTest() throws -> JSONValue {
        return .object([
            "modules": .array([
                .string("overview"),
                .string("cli"),
                .string("usage"),
                .string("agents"),
                .string("skills"),
            ]),
        ])
    }
    #endif
}
