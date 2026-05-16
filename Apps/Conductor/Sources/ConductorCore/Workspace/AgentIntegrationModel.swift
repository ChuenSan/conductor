import Foundation

public enum AgentHookFormat: Equatable, Codable, Sendable {
    case flat
    case nested(timeoutMilliseconds: Int)
    case yaml
}

public struct AgentHookEvent: Equatable, Codable, Sendable {
    public var agentEvent: String
    public var conductorAction: String

    public init(agentEvent: String, conductorAction: String) {
        self.agentEvent = agentEvent
        self.conductorAction = conductorAction
    }
}

public struct AgentIntegrationDefinition: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var displayName: String
    public var statusKey: String
    public var binaryName: String
    public var configDirectory: String
    public var configFile: String
    public var configDirectoryEnvironmentOverride: String?
    public var disableEnvironmentVariable: String
    public var hookFormat: AgentHookFormat
    public var lifecycleEvents: [AgentHookEvent]
    public var feedEvents: [String]
    public var aliases: [String]

    public init(
        id: String,
        displayName: String,
        statusKey: String,
        binaryName: String,
        configDirectory: String,
        configFile: String,
        configDirectoryEnvironmentOverride: String? = nil,
        disableEnvironmentVariable: String,
        hookFormat: AgentHookFormat,
        lifecycleEvents: [AgentHookEvent],
        feedEvents: [String] = [],
        aliases: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.statusKey = statusKey
        self.binaryName = binaryName
        self.configDirectory = configDirectory
        self.configFile = configFile
        self.configDirectoryEnvironmentOverride = configDirectoryEnvironmentOverride
        self.disableEnvironmentVariable = disableEnvironmentVariable
        self.hookFormat = hookFormat
        self.lifecycleEvents = lifecycleEvents
        self.feedEvents = feedEvents
        self.aliases = aliases
    }

    public func matches(_ rawName: String) -> Bool {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return id == normalized || aliases.contains(normalized)
    }
}

public enum AgentIntegrationCatalog {
    public static let builtIns: [AgentIntegrationDefinition] = [
        AgentIntegrationDefinition(
            id: "claude",
            displayName: "Claude Code",
            statusKey: "claude",
            binaryName: "claude",
            configDirectory: ".claude",
            configFile: "settings.json",
            configDirectoryEnvironmentOverride: "CLAUDE_CONFIG_DIR",
            disableEnvironmentVariable: "CONDUCTOR_CLAUDE_HOOKS_DISABLED",
            hookFormat: .nested(timeoutMilliseconds: 5_000),
            lifecycleEvents: [
                AgentHookEvent(agentEvent: "SessionStart", conductorAction: "session-start"),
                AgentHookEvent(agentEvent: "UserPromptSubmit", conductorAction: "prompt-submit"),
                AgentHookEvent(agentEvent: "Stop", conductorAction: "stop")
            ],
            feedEvents: ["PermissionRequest"],
            aliases: ["cc", "claude-code"]
        ),
        AgentIntegrationDefinition(
            id: "codex",
            displayName: "Codex",
            statusKey: "codex",
            binaryName: "codex",
            configDirectory: ".codex",
            configFile: "hooks.json",
            configDirectoryEnvironmentOverride: "CODEX_HOME",
            disableEnvironmentVariable: "CONDUCTOR_CODEX_HOOKS_DISABLED",
            hookFormat: .nested(timeoutMilliseconds: 5_000),
            lifecycleEvents: [
                AgentHookEvent(agentEvent: "SessionStart", conductorAction: "session-start"),
                AgentHookEvent(agentEvent: "UserPromptSubmit", conductorAction: "prompt-submit"),
                AgentHookEvent(agentEvent: "Stop", conductorAction: "stop")
            ],
            feedEvents: ["PreToolUse", "PermissionRequest"]
        ),
        AgentIntegrationDefinition(
            id: "opencode",
            displayName: "OpenCode",
            statusKey: "opencode",
            binaryName: "opencode",
            configDirectory: ".config/opencode",
            configFile: "plugins/conductor-session.js",
            configDirectoryEnvironmentOverride: "OPENCODE_CONFIG_DIR",
            disableEnvironmentVariable: "CONDUCTOR_OPENCODE_HOOKS_DISABLED",
            hookFormat: .flat,
            lifecycleEvents: []
        ),
        AgentIntegrationDefinition(
            id: "cursor",
            displayName: "Cursor CLI",
            statusKey: "cursor",
            binaryName: "cursor-agent",
            configDirectory: ".cursor",
            configFile: "hooks.json",
            disableEnvironmentVariable: "CONDUCTOR_CURSOR_HOOKS_DISABLED",
            hookFormat: .flat,
            lifecycleEvents: [
                AgentHookEvent(agentEvent: "beforeSubmitPrompt", conductorAction: "prompt-submit"),
                AgentHookEvent(agentEvent: "stop", conductorAction: "stop"),
                AgentHookEvent(agentEvent: "afterAgentResponse", conductorAction: "agent-response"),
                AgentHookEvent(agentEvent: "beforeShellExecution", conductorAction: "shell-exec"),
                AgentHookEvent(agentEvent: "afterShellExecution", conductorAction: "shell-done")
            ],
            feedEvents: ["beforeShellExecution"]
        ),
        AgentIntegrationDefinition(
            id: "gemini",
            displayName: "Gemini",
            statusKey: "gemini",
            binaryName: "gemini",
            configDirectory: ".gemini",
            configFile: "settings.json",
            disableEnvironmentVariable: "CONDUCTOR_GEMINI_HOOKS_DISABLED",
            hookFormat: .nested(timeoutMilliseconds: 10_000),
            lifecycleEvents: [
                AgentHookEvent(agentEvent: "SessionStart", conductorAction: "session-start"),
                AgentHookEvent(agentEvent: "BeforeAgent", conductorAction: "prompt-submit"),
                AgentHookEvent(agentEvent: "AfterAgent", conductorAction: "stop"),
                AgentHookEvent(agentEvent: "SessionEnd", conductorAction: "session-end")
            ],
            feedEvents: ["PreToolUse"]
        ),
        AgentIntegrationDefinition(
            id: "rovodev",
            displayName: "Rovo Dev",
            statusKey: "rovodev",
            binaryName: "acli",
            configDirectory: ".rovodev",
            configFile: "config.yml",
            disableEnvironmentVariable: "CONDUCTOR_ROVODEV_HOOKS_DISABLED",
            hookFormat: .yaml,
            lifecycleEvents: [
                AgentHookEvent(agentEvent: "on_complete", conductorAction: "stop"),
                AgentHookEvent(agentEvent: "on_error", conductorAction: "stop"),
                AgentHookEvent(agentEvent: "on_tool_permission", conductorAction: "prompt-submit")
            ],
            aliases: ["rovo"]
        )
    ]

    public static func definition(named rawName: String) -> AgentIntegrationDefinition? {
        builtIns.first { $0.matches(rawName) }
    }
}

