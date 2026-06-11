import AppKit
import ConductorCore
import SwiftUI

/// 一个被检测的 CLI 工具的展示模型。Sendable + Codable（用于磁盘缓存）。
struct CLIToolStatus: Identifiable, Sendable, Codable {
    let id: String
    let name: String
    /// 资源里的品牌 logo 名（Resources/Logos/<logo>.png）。
    let logo: String
    /// 加载不到 logo 时的 SF Symbol 兜底。
    let fallbackSystemImage: String
    let path: String?
    let version: String?

    var isInstalled: Bool { path != nil }
}

/// 加载并缓存品牌 logo（来自 SwiftPM 资源 bundle）。
enum CLIToolLogo {
    private static var cache: [String: NSImage?] = [:]

    /// 单色（深色）品牌标，需作为模板图按主题着色，否则在深色界面里看不见。
    static let monochrome: Set<String> = ["cursor", "copilot"]

    static func isMonochrome(_ name: String) -> Bool { monochrome.contains(name) }

    static func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let image = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Logos")
            .flatMap { NSImage(contentsOf: $0) }
        cache[name] = image
        return image
    }
}

/// 可一键启动的 Agent（已检测到安装）。`command` 即在终端里要执行的命令。
struct LaunchableAgent: Identifiable, Sendable {
    let id: String
    let title: String
    let command: String
    let logo: String
    let fallbackSystemImage: String
}

/// 一个受支持的 AI 编码 CLI 的静态描述 + 检测闭包。面板与右键菜单共用同一份定义，避免漂移。
struct AgentDescriptor: Sendable {
    let id: String
    let name: String
    let logo: String
    let fallbackSystemImage: String
    /// 在终端里启动它的命令（默认等于 id）。
    let command: String
    let resolveBinary: @Sendable () -> String?
    let readVersion: @Sendable () -> String?
}

enum AgentCatalog {
    static let all: [AgentDescriptor] = [
        AgentDescriptor(
            id: "codex", name: "Codex CLI", logo: "codex",
            fallbackSystemImage: "chevron.left.forwardslash.chevron.right", command: "codex",
            resolveBinary: { BinaryLocator.resolveCodexBinary() },
            readVersion: { ProviderVersionDetector.codexVersion() }),
        AgentDescriptor(
            id: "claude", name: "Claude Code", logo: "claude",
            fallbackSystemImage: "sparkles", command: "claude",
            resolveBinary: { BinaryLocator.resolveClaudeBinary() },
            readVersion: { ProviderVersionDetector.claudeVersion() }),
        AgentDescriptor(
            id: "gemini", name: "Gemini CLI", logo: "gemini",
            fallbackSystemImage: "diamond", command: "gemini",
            resolveBinary: { BinaryLocator.resolveGeminiBinary() },
            readVersion: { ProviderVersionDetector.geminiVersion() }),
        AgentDescriptor(
            id: "cursor", name: "Cursor Agent", logo: "cursor",
            fallbackSystemImage: "cursorarrow.rays", command: "cursor-agent",
            resolveBinary: { TTYCommandRunner.which("cursor-agent") },
            readVersion: { ProviderVersionDetector.genericVersion(command: "cursor-agent") }),
        AgentDescriptor(
            id: "copilot", name: "GitHub Copilot", logo: "copilot",
            fallbackSystemImage: "command", command: "copilot",
            resolveBinary: { TTYCommandRunner.which("copilot") },
            readVersion: { ProviderVersionDetector.genericVersion(command: "copilot") }),
        AgentDescriptor(
            id: "grok", name: "Grok CLI", logo: "grok",
            fallbackSystemImage: "bolt.fill", command: "grok",
            resolveBinary: { BinaryLocator.resolveGrokBinary() },
            readVersion: { ProviderVersionDetector.grokVersion() }),
    ]
}

/// 某个工具的用量展示状态。
enum ToolUsageState {
    /// 该工具不支持用量查询。
    case unsupported
    case loading
    case error(String)
    case loaded(CodexUsageSnapshot)
}

/// 独立面板：检测本机已安装的 AI 编码 CLI（codex / claude / gemini）。
/// 入口在 Tab 栏右侧、设置按钮旁边。检测走登录 Shell 的 PATH + 常见安装路径，
/// 因为是阻塞型 shell 探测，统一放到后台任务，避免卡主线程。
struct CLIToolsView: View {
    let coordinator: AppCoordinator
    var onClose: () -> Void = {}
    /// 主题变 → 重渲染（AppStyle 跟随）。不观察的话切主题后停在旧配色。
    @ObservedObject private var configStore = ConfigStore.shared

    @State private var results: [CLIToolStatus] = []
    @State private var detecting = false
    /// 上次检测时间（来自磁盘缓存或刚跑完的检测）。
    @State private var lastDetectedAt: Date?
    /// 各工具的用量状态（目前仅 codex 支持）。
    @State private var usage: [String: ToolUsageState] = [:]
    /// 通知 hook 安装状态。
    @State private var hookStatus = HookInstaller.status()
    @State private var hookError: String?

    private var installedTools: [CLIToolStatus] { results.filter(\.isInstalled) }
    private var missingTools: [CLIToolStatus] { results.filter { !$0.isInstalled } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.md) {
                    embeddedToolbar
                    notificationCard
                    if results.isEmpty, detecting {
                        loadingPlaceholder
                    } else {
                        if !installedTools.isEmpty {
                            ToolsSectionLabel(L("已安装"))
                            ForEach(installedTools) { tool in
                                CLIToolRow(
                                    tool: tool,
                                    usageState: usage[tool.id] ?? .unsupported,
                                    onLaunch: {
                                        coordinator.launchAgent(command: tool.id)
                                        onClose()
                                    },
                                    onCopyPath: { coordinator.copyToClipboard($0) },
                                    onReveal: { coordinator.revealInFinder($0) }
                                )
                            }
                        }
                        if !missingTools.isEmpty {
                            ToolsSectionLabel(L("未检测到"))
                                .padding(.top, installedTools.isEmpty ? 0 : Space.xxs)
                            missingList
                        }
                    }
                }
                .padding(.top, Space.sm)
                .padding(.horizontal, Space.lg)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxHeight: .infinity)
        .background(AppStyle.windowBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AppStyle.separator)
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .onAppear { loadOrDetect() }
    }

    /// 未安装的工具收成一张紧凑卡片：一行一个，不再占满版面的空框。
    private var missingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(missingTools.enumerated()), id: \.element.id) { index, tool in
                HStack(spacing: 10) {
                    CLIToolLogoView(tool: tool)
                        .frame(width: 18, height: 18)
                        .opacity(0.45)
                        .saturation(0)
                    Text(tool.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppStyle.textSecondary)
                    Spacer()
                    Text(L("未检测到"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .padding(.horizontal, Space.sm)
                .frame(height: 36)
                if index < missingTools.count - 1 {
                    Divider().overlay(AppStyle.separator).padding(.leading, 40)
                }
            }
        }
        .padding(.vertical, 2)
        .toolsCard()
    }

    /// 打开面板：优先用磁盘缓存（不重新检测），仅在无缓存时才真正检测一次。
    private func loadOrDetect() {
        guard results.isEmpty else { return }
        if let cache = CLIDetectionStore.load() {
            results = cache.tools
            lastDetectedAt = cache.detectedAt
            pushLaunchableAgents(cache.tools)
            Task { await fetchUsage(for: cache.tools) }
        } else {
            detect()
        }
    }

    private func pushLaunchableAgents(_ tools: [CLIToolStatus]) {
        coordinator.setLaunchableAgents(tools.filter(\.isInstalled).map {
            LaunchableAgent(
                id: $0.id, title: $0.name, command: $0.id,
                logo: $0.logo, fallbackSystemImage: $0.fallbackSystemImage)
        })
    }

    /// 嵌入模式头：标题 + 上次检测时间 + 重新检测，一行收掉，不再单独一段说明文。
    private var embeddedToolbar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("AI 编码 CLI"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                if let lastDetectedAt {
                    Text(L("上次检测 %@", UsageFormatting.agoText(lastDetectedAt)))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                        .help(lastDetectedAt.formatted(date: .abbreviated, time: .standard))
                } else {
                    Text(L("从登录 Shell 的 PATH 与常见安装路径中查找"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
            Spacer()
            Button(action: detect) {
                HStack(spacing: 5) {
                    if detecting {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 10.5, weight: .bold))
                    }
                    Text(detecting ? L("检测中") : L("重新检测"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AppStyle.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(AppStyle.hoverFill))
                .contentShape(Capsule())
            }
            .buttonStyle(PressScaleStyle())
            .disabled(detecting)
        }
        .padding(.bottom, 2)
    }

    /// 「完成通知」卡片：安装 hook + 显示通知权限状态。
    private var notificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppStyle.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("完成通知"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(L("Agent 答完后发 macOS 通知，点击跳回对应 pane。"))
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                hookBadge(L("脚本"), hookStatus.scriptInstalled)
                hookBadge("Codex", hookStatus.codexConfigured)
                hookBadge("Claude", hookStatus.claudeConfigured)
                Spacer()
            }

            HStack(spacing: 8) {
                Button(action: installHooks) {
                    Text(hookStatus.allDone ? L("重新安装 hook") : L("安装通知 hook"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.theme.primarySolidText)
                        .padding(.horizontal, 12)
                        .frame(height: 27)
                        .background(Capsule().fill(AppStyle.theme.primarySolid))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())

                if !NotificationManager.shared.canDeliverRich {
                    Button { NotificationManager.shared.openSystemNotificationSettings() } label: {
                        Text(L("去系统设置授权"))
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(AppStyle.textSecondary)
                            .padding(.horizontal, 12)
                            .frame(height: 27)
                            .background(Capsule().fill(AppStyle.hoverFill))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressScaleStyle())
                    .help(L("ad-hoc 签名的 app 通知可能被系统默认拒绝；在此手动开启即可恢复点击跳转。"))
                }
                Spacer()
            }

            if !NotificationManager.shared.canDeliverRich {
                Text(L("当前无法发送可点击通知，已自动回退为普通横幅（看得到、点了不跳转）。"))
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let hookError {
                Text(hookError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolsCard()
    }

    private func hookBadge(_ label: String, _ on: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(on ? Color(red: 0.22, green: 0.62, blue: 0.40) : AppStyle.textTertiary)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(on ? AppStyle.textSecondary : AppStyle.textTertiary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(AppStyle.hoverFill.opacity(on ? 1 : 0.6)))
    }

    private func installHooks() {
        hookError = nil
        do {
            hookStatus = try HookInstaller.installAll()
        } catch {
            hookError = error.localizedDescription
            hookStatus = HookInstaller.status()
        }
        NotificationManager.shared.refreshAuthStatus()
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L("正在检测…"))
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textSecondary)
            Spacer()
        }
        .padding(.vertical, 18)
    }

    private func detect() {
        guard !detecting else { return }
        detecting = true
        Task {
            let detected = await Task.detached(priority: .userInitiated) { () -> [CLIToolStatus] in
                LoginShellPathCache.shared.captureOnce()
                _ = LoginShellPathCache.shared.currentOrCapture()
                return AgentCatalog.all.map { agent in
                    let path = agent.resolveBinary()
                    return CLIToolStatus(
                        id: agent.id, name: agent.name,
                        logo: agent.logo, fallbackSystemImage: agent.fallbackSystemImage,
                        path: path,
                        version: path != nil ? agent.readVersion() : nil)
                }
            }.value
            let cache = CLIDetectionStore.save(detected)
            await MainActor.run {
                results = detected
                lastDetectedAt = cache.detectedAt
                detecting = false
                pushLaunchableAgents(detected)
            }
            await fetchUsage(for: detected)
        }
    }

    /// 拉取支持用量查询的工具的额度（目前 codex）。
    private func fetchUsage(for tools: [CLIToolStatus]) async {
        guard tools.contains(where: { $0.id == "codex" && $0.isInstalled }) else { return }
        await MainActor.run { usage["codex"] = .loading }
        do {
            let snap = try await CodexUsageFetcher.fetch()
            await MainActor.run { usage["codex"] = .loaded(snap) }
        } catch {
            await MainActor.run { usage["codex"] = .error(error.localizedDescription) }
        }
    }
}

/// 品牌 logo（带 SF Symbol 兜底），CLI 行与「未检测到」列表共用。
struct CLIToolLogoView: View {
    let tool: CLIToolStatus
    /// 主题变 → 重渲染（字段不变时 SwiftUI 会跳过 body）。
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        if let logo = CLIToolLogo.image(named: tool.logo) {
            if CLIToolLogo.isMonochrome(tool.logo) {
                Image(nsImage: logo)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tool.isInstalled ? AppStyle.textPrimary : AppStyle.textTertiary)
            } else {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        } else {
            Image(systemName: tool.fallbackSystemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tool.isInstalled ? AppStyle.accent : AppStyle.textTertiary)
        }
    }
}

private struct CLIToolRow: View {
    let tool: CLIToolStatus
    let usageState: ToolUsageState
    let onLaunch: () -> Void
    let onCopyPath: (String) -> Void
    let onReveal: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            usageSection
        }
        .padding(Space.sm)
        .toolsCard()
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            // logo 放进小方片，撑住行的视觉锚点
            CLIToolLogoView(tool: tool)
                .frame(width: 20, height: 20)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppStyle.hoverFill))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    if let version = tool.version {
                        Text(version)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppStyle.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(AppStyle.hoverFill))
                    }
                }
                if let path = tool.path {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let path = tool.path {
                Button { onCopyPath(path) } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .buttonStyle(IconButtonStyle(size: 24))
                .help(L("复制路径"))
                Button { onReveal(path) } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .buttonStyle(IconButtonStyle(size: 24))
                .help(L("在 Finder 中显示"))
                Button(action: onLaunch) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5, weight: .bold))
                        Text(L("启动"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(AppStyle.theme.primarySolidText)
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .background(Capsule().fill(AppStyle.theme.primarySolid))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .help(L("在新标签页启动 %@", tool.name))
            }
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        switch usageState {
        case .unsupported:
            EmptyView()
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small).scaleEffect(0.7)
                Text(L("读取用量…"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
                Spacer()
            }
            .padding(.top, 8)
            .padding(.leading, 44)
        case let .error(message):
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(2)
                .padding(.top, 8)
                .padding(.leading, 44)
        case let .loaded(snap):
            VStack(alignment: .leading, spacing: 7) {
                if let session = snap.session {
                    UsageBar(title: L("会话"), window: session)
                }
                if let weekly = snap.weekly {
                    UsageBar(title: L("本周"), window: weekly)
                }
            }
            .padding(.top, 9)
            .padding(.leading, 44)
        }
    }
}

/// 单个用量窗口的展示：标题 + 进度条 + 剩余百分比 + 重置倒计时。
private struct UsageBar: View {
    let title: String
    let window: CodexUsageSnapshot.Window
    /// 主题变 → 重渲染（字段不变时 SwiftUI 会跳过 body）。
    @ObservedObject private var configStore = ConfigStore.shared

    private var fraction: Double { Double(window.usedPercent) / 100.0 }

    /// 用量越高越警示：<70 绿、70-90 橙、>90 红。
    private var barColor: Color {
        switch window.usedPercent {
        case ..<70: AppStyle.accent
        case 70..<90: Color(red: 0.95, green: 0.62, blue: 0.20)
        default: Color(red: 0.92, green: 0.34, blue: 0.34)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .frame(width: 28, alignment: .leading)
                Text(L("剩 %ld%%", window.remainingPercent))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer(minLength: 6)
                Text(UsageFormatting.resetText(window.resetAt))
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppStyle.theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.07))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
    }
}

enum UsageFormatting {
    /// 把过去时间格式化成「刚刚」「8 分钟前」「3 小时前」「2 天前」。
    static func agoText(_ date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        guard seconds > 0 else { return L("刚刚") }
        if seconds < 60 { return L("刚刚") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("%ld 分钟前", minutes) }
        let hours = minutes / 60
        if hours < 24 { return L("%ld 小时前", hours) }
        let days = hours / 24
        if days < 30 { return L("%ld 天前", days) }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// 把重置时间格式化成「4 小时后重置」「2 天后重置」「8 分钟后重置」。
    static func resetText(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return L("已重置") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return L("%ld 分钟后重置", max(1, minutes)) }
        let hours = minutes / 60
        if hours < 24 {
            let remMin = minutes % 60
            return remMin > 0 ? L("%1$ld 小时 %2$ld 分后重置", hours, remMin) : L("%ld 小时后重置", hours)
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? L("%1$ld 天 %2$ld 小时后重置", days, remHours) : L("%ld 天后重置", days)
    }
}
