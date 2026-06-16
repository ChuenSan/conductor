import AppKit
import ConductorCore
import SwiftUI

@MainActor
final class AgentToolsConsoleStore: ObservableObject {
    @Published private(set) var cliTools: [CLIToolStatus] = []
    @Published private(set) var cliDetectedAt: Date?
    @Published private(set) var isScanningCLI = false
    @Published private(set) var providers: [UsageProviderEntry] = []
    @Published private(set) var providerStates: [String: ToolUsageState] = [:]
    @Published private(set) var usageReport: UsageReport?
    @Published private(set) var isScanningLocalUsage = false
    @Published private(set) var skillTools: [SkillToolInfo] = []
    @Published private(set) var managedSkills: [ManagedSkill] = []
    @Published private(set) var isLoadingAgentRegistry = false
    @Published private(set) var agentRegistryError: String?
    @Published private(set) var mcpServers: [AgentToolsMCPServerRecord] = []
    @Published private(set) var isScanningMCP = false
    @Published private(set) var mcpScanError: String?
    @Published private(set) var hookEntries: [HookEntry] = []
    @Published private(set) var hookRecipeStates: [String: Set<HookSource>] = [:]
    @Published private(set) var isLoadingHooks = false
    @Published private(set) var hookError: String?
    @Published private(set) var overviewRows: [AgentToolsOverviewRow] = []
    @Published var selectedOverviewRowID: String?
    @Published var selectedCLIToolID: String?
    @Published var selectedUsageProviderID: String?
    @Published var selectedAgentID: String?
    @Published var selectedMCPServerID: String?
    @Published var selectedHookEntryID: String?

    private var started = false

    var installedCLICount: Int { cliTools.filter(\.isInstalled).count }
    var missingCLICount: Int { cliTools.filter { !$0.isInstalled }.count }
    var configuredProviderCount: Int {
        providers.filter { provider in
            switch providerStates[provider.id] {
            case .manual, .loaded, .loading, .error: return true
            default: return false
            }
        }.count
    }
    var loadedProviderCount: Int {
        providers.filter {
            if case .loaded = providerStates[$0.id] { return true }
            return false
        }.count
    }
    var providerErrorCount: Int {
        providers.filter {
            if case .error = providerStates[$0.id] { return true }
            return false
        }.count
    }
    var coreMissingCount: Int {
        cliTools.filter { ["codex", "claude"].contains($0.id) && !$0.isInstalled }.count
    }
    var attentionCount: Int { providerErrorCount + coreMissingCount }
    var skillTargetCount: Int {
        skillTools.filter { $0.enabled && ($0.installed || $0.isCustom || $0.hasPathOverride) }.count
    }

    private func rebuildOverviewRows() {
        let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        let toolRows = AgentCatalog.all.map { descriptor -> AgentToolsOverviewRow in
            let tool = cliTools.first { $0.id == descriptor.id }
            let provider = providerMap[descriptor.id]
            return AgentToolsOverviewRow(
                id: descriptor.id,
                name: descriptor.name,
                command: descriptor.command,
                kind: L("Agent 工具"),
                logo: descriptor.logo,
                fallbackSystemImage: descriptor.fallbackSystemImage,
                tool: tool,
                provider: provider,
                providerState: providerStates[descriptor.id],
                capability: Self.capability(for: descriptor.id, hasUsageProvider: provider != nil))
        }

        let knownToolIDs = Set(AgentCatalog.all.map(\.id))
        let providerOnlyRows = providers
            .filter { !knownToolIDs.contains($0.id) }
            .filter { provider in
                switch providerStates[provider.id] {
                case .loaded, .manual, .loading, .error: return true
                default: return false
                }
            }
            .prefix(18)
            .map { provider in
                AgentToolsOverviewRow(
                    id: "provider:\(provider.id)",
                    name: provider.name,
                    command: provider.id,
                    kind: L("账号渠道"),
                    logo: provider.logoName,
                    fallbackSystemImage: provider.fallbackSystemImage,
                    tool: nil,
                    provider: provider,
                    providerState: providerStates[provider.id],
                    capability: Self.capability(for: provider.id, hasUsageProvider: true))
            }

        overviewRows = toolRows + providerOnlyRows
    }

    var selectedOverviewRow: AgentToolsOverviewRow? {
        guard let selectedOverviewRowID else { return nil }
        return overviewRows.first { $0.id == selectedOverviewRowID }
    }

    var selectedCLITool: CLIToolStatus? {
        guard let selectedCLIToolID else { return nil }
        return cliTools.first { $0.id == selectedCLIToolID }
    }

    var selectedUsageProvider: UsageProviderEntry? {
        guard let selectedUsageProviderID else { return nil }
        return UsageProviderCatalog.all.first { $0.id == selectedUsageProviderID }
    }

    var selectedMCPServer: AgentToolsMCPServerRecord? {
        guard let selectedMCPServerID else { return nil }
        return mcpServers.first { $0.id == selectedMCPServerID }
    }

    var selectedHookEntry: HookEntry? {
        guard let selectedHookEntryID else { return nil }
        return hookEntries.first { $0.id == selectedHookEntryID }
    }

    func overviewRow(for tool: CLIToolStatus) -> AgentToolsOverviewRow? {
        overviewRows.first { $0.id == tool.id }
    }

    func usageState(for provider: UsageProviderEntry) -> ToolUsageState? {
        providerStates[provider.id]
    }

    func start() {
        guard !started else { return }
        started = true
        if let cache = CLIDetectionStore.load() {
            cliTools = cache.tools
            cliDetectedAt = cache.detectedAt
        } else {
            cliTools = AgentCatalog.all.map {
                CLIToolStatus(
                    id: $0.id,
                    name: $0.name,
                    logo: $0.logo,
                    fallbackSystemImage: $0.fallbackSystemImage,
                    path: nil,
                    version: nil)
            }
            scanCLI()
        }
        rebuildOverviewRows()
        usageReport = UsageReportStore.load(daysBack: 30)
        Task { await prepareProviders() }
        refreshAgentRegistry()
    }

    func scanCLI() {
        guard !isScanningCLI else { return }
        isScanningCLI = true
        Task {
            let detected = await Task.detached(priority: .userInitiated) {
                AgentCatalog.detectStatuses()
            }.value
            let cache = CLIDetectionStore.save(detected)
            await MainActor.run {
                withAnimation(AgentToolsMotion.reveal) {
                    self.cliTools = detected
                    self.cliDetectedAt = cache.detectedAt
                    self.rebuildOverviewRows()
                    self.isScanningCLI = false
                }
            }
        }
    }

    func refreshLocalUsage(daysBack: Int = 30) {
        guard !isScanningLocalUsage else { return }
        isScanningLocalUsage = true
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                UsageScanner().scan(daysBack: daysBack)
            }.value
            UsageReportStore.save(report, daysBack: daysBack)
            await MainActor.run {
                withAnimation(AgentToolsMotion.reveal) {
                    self.usageReport = report
                    self.isScanningLocalUsage = false
                }
            }
        }
    }

    func refreshProvider(_ provider: UsageProviderEntry) {
        guard !isProviderLoading(provider.id) else { return }
        let cfg = ConfigStore.shared.config
        providerStates[provider.id] = .loading
        rebuildOverviewRows()
        Task {
            let configured = await Task.detached(priority: .utility) {
                UsageCredentials.apply(cfg)
                return provider.isConfigured()
            }.value
            guard configured else {
                await MainActor.run {
                    providerStates[provider.id] = .unconfigured
                    rebuildOverviewRows()
                }
                return
            }
            do {
                let snapshot = try await provider.fetch()
                await MainActor.run {
                    withAnimation(AgentToolsMotion.selection) {
                        providerStates[provider.id] = .loaded(snapshot)
                        rebuildOverviewRows()
                    }
                    UsageHistoryStore.shared.record(id: provider.id, snapshot: snapshot)
                    UsageHistoryStore.shared.persist()
                }
            } catch {
                await MainActor.run {
                    providerStates[provider.id] = .error(error.localizedDescription)
                    rebuildOverviewRows()
                }
            }
        }
    }

    func refreshAgentRegistry() {
        guard !isLoadingAgentRegistry else { return }
        isLoadingAgentRegistry = true
        agentRegistryError = nil
        Task {
            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    let engine = try SkillManagerEngine()
                    return (tools: engine.tools(), skills: engine.listSkills())
                }.value
                await MainActor.run {
                    withAnimation(AgentToolsMotion.reveal) {
                        self.skillTools = snapshot.tools
                        self.managedSkills = snapshot.skills
                        self.isLoadingAgentRegistry = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.agentRegistryError = error.localizedDescription
                    self.isLoadingAgentRegistry = false
                }
            }
        }
    }

    func setSkillToolEnabled(_ tool: SkillToolInfo, enabled: Bool) {
        Task {
            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    let engine = try SkillManagerEngine()
                    try engine.setToolEnabled(tool.key, enabled: enabled)
                    return (tools: engine.tools(), skills: engine.listSkills())
                }.value
                await MainActor.run {
                    withAnimation(AgentToolsMotion.reveal) {
                        self.skillTools = snapshot.tools
                        self.managedSkills = snapshot.skills
                    }
                }
            } catch {
                await MainActor.run { self.agentRegistryError = error.localizedDescription }
            }
        }
    }

    func refreshMCP() {
        guard !isScanningMCP else { return }
        isScanningMCP = true
        mcpScanError = nil
        Task {
            let snapshot = await Task.detached(priority: .utility) {
                AgentToolsMCPScanner.scan()
            }.value
            await MainActor.run {
                withAnimation(AgentToolsMotion.reveal) {
                    self.mcpServers = snapshot.servers
                    self.mcpScanError = snapshot.error
                    self.isScanningMCP = false
                    if let selected = self.selectedMCPServerID,
                       !snapshot.servers.contains(where: { $0.id == selected }) {
                        self.selectedMCPServerID = snapshot.servers.first?.id
                    } else if self.selectedMCPServerID == nil {
                        self.selectedMCPServerID = snapshot.servers.first?.id
                    }
                }
            }
        }
    }

    func installMCPTemplate(_ template: AgentToolsMCPTemplate, to clientIDs: Set<String>) {
        mcpScanError = nil
        do {
            try AgentToolsMCPScanner.installTemplate(template, to: clientIDs)
            refreshMCP()
        } catch {
            mcpScanError = L("写入 MCP 配置失败：%@", error.localizedDescription)
        }
    }

    func installCustomMCPServer(name: String,
                                transport: AgentToolsMCPTransport,
                                command: String?,
                                args: [String],
                                url: String?,
                                env: [String: String],
                                to clientIDs: Set<String>) {
        mcpScanError = nil
        do {
            try AgentToolsMCPScanner.installCustomServer(
                name: name,
                transport: transport,
                command: command,
                args: args,
                url: url,
                env: env,
                to: clientIDs)
            refreshMCP()
        } catch {
            mcpScanError = L("写入 MCP 配置失败：%@", error.localizedDescription)
        }
    }

    func removeMCPServer(_ server: AgentToolsMCPServerRecord) {
        mcpScanError = nil
        do {
            try AgentToolsMCPScanner.removeServer(server)
            refreshMCP()
        } catch {
            mcpScanError = L("移除 MCP server 失败：%@", error.localizedDescription)
        }
    }

    func refreshHooks() {
        guard !isLoadingHooks else { return }
        isLoadingHooks = true
        hookError = nil
        Task {
            let result = await Task.detached(priority: .utility) { () -> ([HookEntry], [String: Set<HookSource>]) in
                let entries = HookSource.allCases.flatMap { HookConfigDocument(source: $0).entries() }
                var states: [String: Set<HookSource>] = [:]
                for recipe in HookRecipes.all {
                    states[recipe.id] = HookRecipes.installedSources(recipe)
                }
                return (entries, states)
            }.value
            await MainActor.run {
                withAnimation(AgentToolsMotion.reveal) {
                    self.hookEntries = result.0
                    self.hookRecipeStates = result.1
                    self.isLoadingHooks = false
                    if let selected = self.selectedHookEntryID,
                       !result.0.contains(where: { $0.id == selected }) {
                        self.selectedHookEntryID = result.0.first?.id
                    } else if self.selectedHookEntryID == nil {
                        self.selectedHookEntryID = result.0.first?.id
                    }
                }
            }
        }
    }

    func installHookRecipe(_ recipe: HookRecipe) {
        installHookRecipe(recipe, to: Set(HookSource.allCases))
    }

    func installHookRecipe(_ recipe: HookRecipe, to sources: Set<HookSource>) {
        hookError = nil
        guard !sources.isEmpty else { return }
        do {
            try recipe.ensureScript?()
            for source in sources {
                try HookConfigDocument(source: source).addCommand(
                    event: HookEventName.stop,
                    command: recipe.command)
            }
            refreshHooks()
        } catch {
            hookError = L("安装失败：%@", error.localizedDescription)
        }
    }

    func uninstallHookRecipe(_ recipe: HookRecipe) {
        hookError = nil
        do {
            _ = try HookRecipes.uninstall(recipe)
            refreshHooks()
        } catch {
            hookError = L("移除失败：%@", error.localizedDescription)
        }
    }

    func removeHookEntry(_ entry: HookEntry) {
        hookError = nil
        do {
            try HookConfigDocument(source: entry.source).removeCommands(containing: entry.command)
            refreshHooks()
        } catch {
            hookError = L("移除失败：%@", error.localizedDescription)
        }
    }

    func installCustomHook(sources: Set<HookSource>, event: String, command: String, timeout: Int) {
        hookError = nil
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventName = event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sources.isEmpty, !trimmed.isEmpty, !eventName.isEmpty else { return }
        do {
            for source in sources {
                try HookConfigDocument(source: source).addCommand(
                    event: eventName,
                    command: trimmed,
                    timeout: timeout)
            }
            refreshHooks()
        } catch {
            hookError = L("写入 Hook 配置失败：%@", error.localizedDescription)
        }
    }

    func copyDiagnostics(for row: AgentToolsOverviewRow) {
        copyText(diagnostics(for: row))
    }

    func copyDiagnostics(for provider: UsageProviderEntry) {
        copyText(diagnostics(for: provider))
    }

    func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func prepareProviders() async {
        let cfg = ConfigStore.shared.config
        let resolved = await Task.detached(priority: .utility) { () -> [(UsageProviderEntry, Bool)] in
            UsageCredentials.apply(cfg)
            return UsageProviderCatalog.all
                .filter { UsageCredentials.isVisible($0, config: cfg) }
                .map { ($0, $0.isConfigured()) }
        }.value

        let visible = resolved.map(\.0)
        let configuredIDs = Set(resolved.filter(\.1).map { $0.0.id })
        await MainActor.run {
            providers = visible
            providerStates = providerStates.filter { id, _ in visible.contains { $0.id == id } }
            for provider in visible {
                guard providerStates[provider.id] == nil else { continue }
                providerStates[provider.id] = configuredIDs.contains(provider.id) ? .manual : .unconfigured
            }
            rebuildOverviewRows()
        }
    }

    private func isProviderLoading(_ id: String) -> Bool {
        if case .loading = providerStates[id] { return true }
        return false
    }

    private func diagnostics(for row: AgentToolsOverviewRow) -> String {
        var lines: [String] = []
        lines.append("Conductor Agent Tools Diagnostics")
        lines.append("name: \(row.name)")
        lines.append("id: \(row.id)")
        lines.append("kind: \(row.kind)")
        lines.append("command: \(row.command)")
        if let tool = row.tool {
            lines.append("cli.installed: \(tool.isInstalled)")
            lines.append("cli.version: \(tool.version ?? "-")")
            lines.append("cli.path: \(tool.path ?? "-")")
        } else {
            lines.append("cli.installed: false")
        }
        if let provider = row.provider {
            lines.append("provider.id: \(provider.id)")
            lines.append("provider.state: \(providerStateLabel(row.providerState))")
        } else {
            lines.append("provider.id: -")
        }
        lines.append("capability.usage: \(row.usageSignal.shortLabel)")
        lines.append("capability.skills: \(row.skillSignal.shortLabel)")
        lines.append("capability.hooks: \(row.hookSignal.shortLabel)")
        lines.append("capability.mcp: \(row.mcpSignal.shortLabel)")
        return lines.joined(separator: "\n")
    }

    private func diagnostics(for provider: UsageProviderEntry) -> String {
        var lines: [String] = []
        lines.append("Conductor Usage Provider Diagnostics")
        lines.append("name: \(provider.name)")
        lines.append("id: \(provider.id)")
        lines.append("state: \(providerStateLabel(providerStates[provider.id]))")
        if let tool = cliTools.first(where: { $0.id == provider.id }) {
            lines.append("cli.installed: \(tool.isInstalled)")
            lines.append("cli.version: \(tool.version ?? "-")")
            lines.append("cli.path: \(tool.path ?? "-")")
        } else {
            lines.append("cli.installed: false")
        }
        if case let .loaded(snapshot) = providerStates[provider.id] {
            lines.append("updated: \(snapshot.updatedAt)")
            lines.append("account: \(snapshot.accountLabel ?? "-")")
            lines.append("plan: \(snapshot.planName ?? "-")")
            lines.append("windows: \(snapshot.allWindows.count)")
            lines.append("cost: \(snapshot.providerCost == nil ? "false" : "true")")
        }
        return lines.joined(separator: "\n")
    }

    private func providerStateLabel(_ state: ToolUsageState?) -> String {
        switch state {
        case .unsupported: return "unsupported"
        case .loading: return "loading"
        case .manual: return "manual"
        case .unconfigured: return "unconfigured"
        case let .error(message): return "error: \(message)"
        case .loaded: return "loaded"
        case nil: return "unknown"
        }
    }

    private static let skillKeyByAgentID: [String: String] = [
        "codex": "codex",
        "claude": "claude_code",
        "gemini": "gemini_cli",
        "cursor": "cursor",
        "copilot": "github_copilot",
        "grok": "grok",
        "opencode": "opencode",
        "amp": "amp",
        "auggie": "augment",
        "augment": "augment",
        "qwen": "qwen_code",
        "windsurf": "windsurf",
    ]

    private static let usageProviderIDs = Set(UsageProviderCatalog.all.map(\.id))
    private static let skillToolKeys = Set(SkillToolCatalog.defaultAdapters.map(\.key))
    private static let hookAgentIDs: Set<String> = [
        "codex",
        "claude",
        "gemini",
        "cursor",
        "copilot",
        "grok",
        "opencode",
        "amp",
        "auggie",
        "augment",
        "qwen",
    ]
    private static let mcpAgentIDs: Set<String> = [
        "codex",
        "claude",
        "gemini",
        "cursor",
        "copilot",
        "grok",
        "opencode",
        "amp",
        "auggie",
        "augment",
        "qwen",
        "windsurf",
    ]

    private static func capability(for id: String, hasUsageProvider: Bool) -> AgentToolCapability {
        let skillKey = skillKeyByAgentID[id] ?? id
        return AgentToolCapability(
            usage: hasUsageProvider || usageProviderIDs.contains(id),
            skills: skillToolKeys.contains(skillKey),
            hooks: hookAgentIDs.contains(id),
            mcp: mcpAgentIDs.contains(id))
    }
}

struct AgentToolCapability {
    var usage: Bool
    var skills: Bool
    var hooks: Bool
    var mcp: Bool

    static let providerOnly = AgentToolCapability(usage: true, skills: false, hooks: false, mcp: false)
}

struct AgentToolsOverviewRow: Identifiable {
    let id: String
    let name: String
    let command: String
    let kind: String
    let logo: String
    let fallbackSystemImage: String
    let tool: CLIToolStatus?
    let provider: UsageProviderEntry?
    let providerState: ToolUsageState?
    let capability: AgentToolCapability

    var cliSignal: AgentToolsSignal {
        guard let tool else { return .unavailable(L("非 CLI")) }
        if tool.isInstalled {
            return .ready(tool.version ?? L("已安装"))
        }
        return .warning(L("未检测"))
    }

    var credentialSignal: AgentToolsSignal {
        guard provider != nil else { return .unavailable(L("无账号渠道")) }
        return Self.providerSignal(providerState)
    }

    var usageSignal: AgentToolsSignal {
        guard capability.usage, provider != nil else { return .unavailable(L("暂不支持")) }
        return Self.providerSignal(providerState)
    }

    var skillSignal: AgentToolsSignal { capability.skills ? .ready(L("支持")) : .unavailable("-") }
    var hookSignal: AgentToolsSignal { capability.hooks ? .ready(L("支持")) : .unavailable("-") }
    var mcpSignal: AgentToolsSignal { capability.mcp ? .ready(L("支持")) : .unavailable("-") }

    private static func providerSignal(_ state: ToolUsageState?) -> AgentToolsSignal {
        switch state {
        case .loaded: return .ready(L("已取数"))
        case .loading: return .loading(L("刷新中"))
        case .manual: return .warning(L("待刷新"))
        case .unconfigured: return .warning(L("待配置"))
        case let .error(message): return .error(message)
        case .unsupported: return .unavailable(L("暂不支持"))
        case nil: return .unknown(L("未知"))
        }
    }
}

enum AgentToolsSignal {
    case ready(String)
    case warning(String)
    case loading(String)
    case unavailable(String)
    case unknown(String)
    case error(String)

    var shortLabel: String {
        switch self {
        case let .ready(label), let .warning(label), let .loading(label),
             let .unavailable(label), let .unknown(label), let .error(label):
            return label
        }
    }

    var icon: String {
        switch self {
        case .ready: return "checkmark"
        case .warning: return "exclamationmark"
        case .loading: return "arrow.triangle.2.circlepath"
        case .unavailable: return "minus"
        case .unknown: return "questionmark"
        case .error: return "xmark"
        }
    }

    @MainActor var color: Color {
        switch self {
        case .ready: return AppStyle.doneGreen
        case .warning: return AppStyle.waitAmber
        case .loading: return AppStyle.accent
        case .unavailable: return AppStyle.textTertiary
        case .unknown: return AppStyle.textTertiary
        case .error: return AppStyle.errorRed
        }
    }

    @MainActor var fill: Color {
        switch self {
        case .unavailable, .unknown:
            return AppStyle.hoverFill.opacity(0.62)
        default:
            return color.opacity(0.14)
        }
    }
}

struct AgentToolsOverviewView: View {
    @ObservedObject var store: AgentToolsConsoleStore
    @ObservedObject private var configStore = ConfigStore.shared
    let onOpenModule: (AgentToolsManagementModule) -> Void

    @State private var query = ""

    private var filteredRows: [AgentToolsOverviewRow] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return store.overviewRows }
        return store.overviewRows.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.command.lowercased().contains(trimmed)
                || $0.kind.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbar
            metricStrip
            capabilityMatrix
            quickActions
        }
        .agentToolsPage()
        .onAppear { store.start() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            AgentToolsSearchField(placeholder: L("搜索工具 / 渠道 / 能力"), text: $query)

            ToolActionButton(
                title: store.isScanningCLI ? L("扫描中") : L("重新扫描"),
                systemImage: store.isScanningCLI ? nil : "arrow.clockwise",
                height: 34,
                fontSize: 11.5,
                horizontalPadding: 12,
                help: L("重新扫描本机 CLI")) {
                    store.scanCLI()
                }
            .disabled(store.isScanningCLI)

            ToolActionButton(
                title: store.isScanningLocalUsage ? L("读取中") : L("刷新本地用量"),
                systemImage: store.isScanningLocalUsage ? nil : "chart.bar.xaxis",
                height: 34,
                fontSize: 11.5,
                horizontalPadding: 12,
                help: L("扫描本机会话记录，不请求账号接口")) {
                    store.refreshLocalUsage()
                }
            .disabled(store.isScanningLocalUsage)
        }
    }

    private var metricStrip: some View {
        HStack(alignment: .center, spacing: 0) {
            statBlock(
                value: "\(store.installedCLICount)",
                title: L("CLI 已安装"),
                sub: L("%ld 未检测", store.missingCLICount),
                valueColor: AppStyle.textPrimary,
                module: .cli)
            statDivider
            statBlock(
                value: "\(store.configuredProviderCount)",
                title: L("渠道已配置"),
                sub: L("%ld 个可见渠道", store.providers.count),
                valueColor: AppStyle.textPrimary,
                module: .usage)
            statDivider
            statBlock(
                value: "\(store.loadedProviderCount)",
                title: L("用量已取数"),
                sub: store.usageReport.map { L("本地 %@", UsageRelative.text($0.generatedAt)) } ?? L("本地未扫描"),
                valueColor: AppStyle.textPrimary,
                module: .usage)
            statDivider
            statBlock(
                value: "\(store.attentionCount)",
                title: L("待处理"),
                sub: store.attentionCount == 0 ? L("基础状态正常") : L("查看右侧详情"),
                valueColor: store.attentionCount == 0 ? AppStyle.textPrimary : AppStyle.waitAmber,
                module: .overview)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    /// 分隔数字块的呼吸：极淡竖向渐隐线（非硬线，两端淡出）。
    private var statDivider: some View {
        LinearGradient(
            colors: [.clear, AppStyle.separator.opacity(0.55), .clear],
            startPoint: .top, endPoint: .bottom)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 16)
    }

    /// 编辑化数字块：大号数值 + 小标签，坐在概览卡里（与 app 其他面板同款 toolsCard 表面）。
    private func statBlock(
        value: String,
        title: String,
        sub: String,
        valueColor: Color,
        module: AgentToolsManagementModule
    ) -> some View {
        Button {
            if module != .overview { onOpenModule(module) }
        } label: {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(sub)
        .disabled(module == .overview)
    }

    private var capabilityMatrix: some View {
        let visibleRows = filteredRows
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                ToolsSectionLabel(L("能力矩阵"))
                Spacer()
                Text(store.cliDetectedAt.map { L("CLI %@", UsageFormatting.agoText($0)) } ?? L("CLI 未扫描"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            VStack(spacing: 0) {
                matrixHeader
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(visibleRows) { row in
                            matrixRow(row)
                        }
                        if visibleRows.isEmpty {
                            Text(L("无匹配结果"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppStyle.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .agentToolsGlass()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var matrixHeader: some View {
        HStack(spacing: 6) {
            Text(L("工具 / 渠道"))
                .frame(maxWidth: .infinity, alignment: .leading)
            matrixHeaderCell("CLI")
            matrixHeaderCell(L("凭证"))
            matrixHeaderCell("Usage")
            matrixHeaderCell("Skills")
            matrixHeaderCell("Hooks")
            matrixHeaderCell("MCP")
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(AppStyle.textTertiary)
        .padding(.horizontal, 9)
        .frame(height: 28)
    }

    private func matrixHeaderCell(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 52)
    }

    private func matrixRow(_ row: AgentToolsOverviewRow) -> some View {
        let selected = store.selectedOverviewRowID == row.id
        return Button {
            withAnimation(AgentToolsMotion.selection) { store.selectedOverviewRowID = row.id }
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 9) {
                    AgentToolsOverviewLogo(row: row, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.system(size: 12.2, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        Text(row.kind + " · " + row.command)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AgentToolsSignalPill(signal: row.cliSignal)
                AgentToolsSignalPill(signal: row.credentialSignal)
                AgentToolsSignalPill(signal: row.usageSignal)
                AgentToolsSignalPill(signal: row.skillSignal)
                AgentToolsSignalPill(signal: row.hookSignal)
                AgentToolsSignalPill(signal: row.mcpSignal)
            }
            .padding(.horizontal, 9)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(selected ? AppStyle.accent.opacity(0.12) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .animation(AgentToolsMotion.selection, value: selected)
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button(L("打开 CLI 详情")) { onOpenModule(.cli) }
            Button(L("打开用量详情")) { onOpenModule(.usage) }
            Button(L("复制诊断信息")) { store.copyDiagnostics(for: row) }
            if let provider = row.provider {
                Button(L("刷新这个渠道用量")) { store.refreshProvider(provider) }
            }
            if row.tool != nil {
                Button(L("重新检测 CLI")) { store.scanCLI() }
            }
        }
    }

    private var quickActions: some View {
        HStack(spacing: 18) {
            Text(L("跳转"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            quickAction(L("CLI"), icon: "terminal", module: .cli)
            quickAction(L("用量"), icon: "chart.bar.xaxis", module: .usage)
            quickAction("Agents", icon: "cpu", module: .agents)
            quickAction("Skills", icon: "wand.and.stars", module: .skills)
            Spacer(minLength: 0)
        }
    }

    /// 轻量文字链接（无填充按钮），减少按钮汤、强调内容。
    private func quickAction(_ title: String, icon: String, module: AgentToolsManagementModule) -> some View {
        Button {
            onOpenModule(module)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(AppStyle.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .help(L("打开 %@", title))
    }
}

struct AgentToolsOverviewInspector: View {
    @ObservedObject var store: AgentToolsConsoleStore
    @ObservedObject private var configStore = ConfigStore.shared
    let onOpenModule: (AgentToolsManagementModule) -> Void

    var body: some View {
        AgentToolsInspectorShell {
            if let row = store.selectedOverviewRow {
                selectedRow(row)
            } else {
                defaultState
            }
        }
    }

    private var defaultState: some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorSection(L("数据状态")) {
                infoRow(L("CLI 缓存"), store.cliDetectedAt.map { UsageFormatting.agoText($0) } ?? L("无缓存"))
                infoRow(L("账号渠道"), L("%ld 个可见", store.providers.count))
                infoRow(L("已配置"), "\(store.configuredProviderCount)")
                infoRow(L("本地用量"), store.usageReport.map { UsageFormatting.agoText($0.generatedAt) } ?? L("未扫描"))
            }

            Text(L("打开管理台只读取本机缓存和凭证状态；账号额度不会自动请求，必须手动刷新。"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineSpacing(3)

            ToolActionButton(
                title: L("重新扫描 CLI"),
                systemImage: "arrow.clockwise",
                height: 28,
                fontSize: 11,
                horizontalPadding: 10,
                action: { store.scanCLI() })
        }
    }

    private func selectedRow(_ row: AgentToolsOverviewRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentToolsOverviewLogo(row: row, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(row.kind)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }

            inspectorSection(L("基础信息")) {
                infoRow(L("命令"), row.command)
                infoRow("CLI", row.cliSignal.shortLabel)
                if let version = row.tool?.version { infoRow(L("版本"), version) }
                if let provider = row.provider { infoRow(L("渠道"), provider.id) }
            }

            if let path = row.tool?.path {
                inspectorSection(L("路径")) {
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
            }

            inspectorSection(L("能力")) {
                signalRow("CLI", row.cliSignal)
                signalRow(L("凭证"), row.credentialSignal)
                signalRow("Usage", row.usageSignal)
                signalRow("Skills", row.skillSignal)
                signalRow("Hooks", row.hookSignal)
                signalRow("MCP", row.mcpSignal)
            }

            VStack(alignment: .leading, spacing: 8) {
                ToolActionButton(
                    title: L("打开 CLI 详情"),
                    systemImage: "terminal",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        onOpenModule(.cli)
                    }
                ToolActionButton(
                    title: L("打开用量详情"),
                    systemImage: "chart.bar.xaxis",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        onOpenModule(.usage)
                    }
                if let provider = row.provider {
                    ToolActionButton(
                        title: L("刷新这个渠道"),
                        systemImage: "arrow.clockwise",
                        height: 28,
                        fontSize: 11,
                        horizontalPadding: 10) {
                            store.refreshProvider(provider)
                        }
                }
                ToolActionButton(
                    title: L("复制诊断信息"),
                    systemImage: "doc.on.doc",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        store.copyDiagnostics(for: row)
                    }
            }
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AppStyle.textTertiary)
            content()
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func signalRow(_ label: String, _ signal: AgentToolsSignal) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: signal.icon)
                    .font(.system(size: 8.5, weight: .bold))
                Text(signal.shortLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(signal.color)
        }
    }
}

private struct AgentToolsSignalPill: View {
    let signal: AgentToolsSignal

    var body: some View {
        Image(systemName: signal.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(signal.color)
            .frame(width: 52)
            .help(signal.shortLabel)
            .rotationEffect(.degrees(isLoading ? 360 : 0))
            .animation(isLoading ? AgentToolsMotion.loading : AgentToolsMotion.selection, value: isLoading)
    }

    private var isLoading: Bool {
        if case .loading = signal { return true }
        return false
    }
}

private struct AgentToolsOverviewLogo: View {
    let row: AgentToolsOverviewRow
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = CLIToolLogo.image(named: row.logo) {
                if CLIToolLogo.isMonochrome(row.logo) {
                    Image(nsImage: logo)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .scaledToFit()
                        .foregroundStyle(AppStyle.textPrimary)
                } else {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            } else {
                Image(systemName: row.fallbackSystemImage)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
            }
        }
        .frame(width: size, height: size)
        .frame(width: size + 10, height: size + 10)
        .background(RoundedRectangle(cornerRadius: max(8, size * 0.28), style: .continuous).fill(AppStyle.hoverFill))
    }
}
