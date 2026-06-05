import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct ConductorUsageCenterPanel: View {
    let context: ConductorUsageSettingsContext
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?

    @State private var expandedProvider: UsageProvider?
    @State private var isRefreshingAll = false
    @State private var hoveredRoute: ConductorUsageCenterRoute?

    private let tokenRecordProviders: [UsageProvider] = [.codex, .claude, .vertexai, .bedrock]

    private var states: [ConductorUsageProviderCenterState] {
        _ = context.settings.menuObservationToken
        _ = context.store.menuObservationToken

        let enabled = context.store.enabledProvidersForDisplay()
        let tokenProviders = tokenRecordProviders.filter { provider in
            context.store.tokenSnapshot(for: provider) != nil ||
                context.store.tokenError(for: provider) != nil ||
                context.store.isTokenRefreshInFlight(for: provider) ||
                context.store.isEnabled(provider)
        }
        let providers = enabled + tokenProviders.filter { !enabled.contains($0) }
        let displayProviders = providers.isEmpty ? [.codex] : providers
        return displayProviders.prefix(8).map { state(for: $0) }
    }

    private var focusedState: ConductorUsageProviderCenterState? {
        guard let expandedProvider else { return nil }
        return states.first { $0.provider == expandedProvider } ?? state(for: expandedProvider)
    }

    private var attentionCount: Int {
        states.filter { $0.status == .needsAttention }.count
    }

    private var connectedCount: Int {
        states.filter { $0.status == .ready }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 166), spacing: 9, alignment: .top)],
                alignment: .leading,
                spacing: 9)
            {
                ConductorUsageCenterRouteTile(
                    title: accountTitle,
                    subtitle: accountSubtitle,
                    systemImage: "person.crop.circle.badge.checkmark",
                    style: style,
                    isHovered: hoveredRoute == .account,
                    action: { runCodexAccountAction() })
                    .onHover { hoveredRoute = $0 ? .account : nil }

                ConductorUsageCenterRouteTile(
                    title: t("Token 记录", "Token Records"),
                    subtitle: tokenRecordsSubtitle,
                    systemImage: "chart.bar.doc.horizontal",
                    style: style,
                    isHovered: hoveredRoute == .records,
                    action: { openTokenRecords() })
                    .onHover { hoveredRoute = $0 ? .records : nil }

                ConductorUsageCenterRouteTile(
                    title: t("本地数据", "Local Data"),
                    subtitle: storageSubtitle,
                    systemImage: "internaldrive",
                    style: style,
                    isHovered: hoveredRoute == .storage,
                    action: { focusStorage() })
                    .onHover { hoveredRoute = $0 ? .storage : nil }
            }

            ConductorUsageProviderRail(
                states: states,
                expandedProvider: expandedProvider,
                style: style,
                languageIdentifier: languageIdentifier)
            { provider in
                ConductorUsageMotion.perform {
                    expandedProvider = expandedProvider == provider ? nil : provider
                }
            }

            if let focusedState {
                ConductorUsageProviderFocusCard(
                    state: focusedState,
                    style: style,
                    languageIdentifier: languageIdentifier,
                    refresh: { refresh(provider: focusedState.provider) },
                    connect: { runLoginFlow(provider: focusedState.provider) },
                    openDashboard: { openURL(focusedState.dashboardURL) },
                    openStatus: { openURL(focusedState.statusURL) })
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.panelBase.opacity(style.usesDarkChrome ? 0.30 : 0.56))
                .overlay(
                    style.panelWash.opacity(style.usesDarkChrome ? 0.08 : 0.16)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.stroke.opacity(0.28), lineWidth: 0.8)
        }
        .onAppear {
            prime()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.emphasis)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(t("用量状态", "Usage Status"))
                    .font(.system(size: 12.8, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)

                Text(t(
                    "账户、记录和服务连接",
                    "Accounts, records, and service connections"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ConductorUsageCenterStatusPill(
                title: overallStatusText,
                status: attentionCount > 0 ? .needsAttention : connectedCount > 0 ? .ready : .waiting,
                style: style)

            Button {
                refreshAll()
            } label: {
                Label(t("刷新全部用量", "Refresh all usage"), systemImage: refreshSystemImage)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isRefreshingAll || context.store.isRefreshing)
            .help(t("刷新全部用量", "Refresh all usage"))
            .accessibilityLabel(t("刷新全部用量", "Refresh all usage"))
        }
    }

    private var overallStatusText: String {
        if attentionCount > 0 {
            return t("\(attentionCount) 项需处理", "\(attentionCount) need attention")
        }
        if connectedCount > 0 {
            return t("\(connectedCount) 个服务可用", "\(connectedCount) services ready")
        }
        return t("等待首次同步", "Waiting to sync")
    }

    private var refreshSystemImage: String {
        isRefreshingAll || context.store.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
    }

    private var accountTitle: String {
        if let account = context.settings.activeManagedCodexAccount {
            return PersonalInfoRedactor.redactEmail(
                account.email,
                isEnabled: context.settings.hidePersonalInfo)
        }
        if let email = context.store.snapshot(for: .codex)?.identity?.accountEmail,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return PersonalInfoRedactor.redactEmail(
                email,
                isEnabled: context.settings.hidePersonalInfo)
        }
        return t("本机会话", "Local Session")
    }

    private var accountSubtitle: String {
        if let account = context.settings.activeManagedCodexAccount {
            if let workspace = account.workspaceLabel, !workspace.isEmpty {
                return t("托管账户 · \(workspace)", "Managed account · \(workspace)")
            }
            return t("托管账户，可继续添加或切换", "Managed account, ready to add or switch")
        }
        return t("使用本机凭据；可接入独立账户", "Using local credentials; add a managed account")
    }

    private var tokenRecordsSubtitle: String {
        let availableCount = tokenRecordProviders.filter {
            context.store.tokenSnapshot(for: $0) != nil
        }.count
        let attentionCount = tokenRecordProviders.filter {
            context.store.tokenError(for: $0) != nil
        }.count
        if availableCount > 0 {
            return t("\(availableCount) 个来源已有记录", "\(availableCount) sources have records")
        }
        if attentionCount > 0 {
            return t("\(attentionCount) 个来源需要重新读取", "\(attentionCount) sources need a reread")
        }
        if states.contains(where: { $0.isRefreshing }) {
            return t("正在收集最近记录", "Collecting recent records")
        }
        return t("查看会话、模型和成本轨迹", "Inspect sessions, models, and cost trails")
    }

    private var storageSubtitle: String {
        let footprints = states.compactMap { state in
            context.store.storageFootprint(for: state.provider)
        }
        let totalBytes = footprints.reduce(Int64(0)) { $0 + $1.totalBytes }
        let recommendations = footprints.reduce(0) { $0 + $1.cleanupRecommendations.count }

        if totalBytes > 0 {
            let size = UsageFormatter.byteCountString(totalBytes)
            if recommendations > 0 {
                return t("\(size) · \(recommendations) 条整理建议", "\(size) · \(recommendations) cleanup ideas")
            }
            return t("\(size) 已索引", "\(size) indexed")
        }
        if context.store.isStorageRefreshInFlight {
            return t("正在扫描本地痕迹", "Scanning local traces")
        }
        return t("按服务展开查看缓存与日志", "Expand a service to inspect cache and logs")
    }

    private func state(for provider: UsageProvider) -> ConductorUsageProviderCenterState {
        let metadata = context.store.metadata(for: provider)
        let snapshot = context.store.snapshot(for: provider)
        let tokenSnapshot = context.store.tokenSnapshot(for: provider)
        let storage = context.store.storageFootprint(for: provider)
        let providerError = context.store.errors[provider]
        let tokenError = context.store.tokenError(for: provider)
        let error = providerError ?? tokenError
        let isRefreshing = context.store.refreshingProviders.contains(provider) ||
            context.store.isTokenRefreshInFlight(for: provider)
        let status: ConductorUsageProviderCenterStatus = if isRefreshing {
            .refreshing
        } else if error != nil {
            .needsAttention
        } else if snapshot != nil || tokenSnapshot != nil || storage?.hasLocalData == true {
            .ready
        } else {
            .waiting
        }
        let primaryWindow = snapshot?.primary ?? snapshot?.secondary ?? snapshot?.tertiary
        let remaining = primaryWindow?.remainingPercent
        let detail = detailText(
            status: status,
            snapshot: snapshot,
            tokenSnapshot: tokenSnapshot,
            storage: storage,
            error: error,
            remaining: remaining)
        let dashboardURL = metadata.subscriptionDashboardURL ?? metadata.dashboardURL
        let statusURL = metadata.statusLinkURL ?? metadata.statusPageURL

        return ConductorUsageProviderCenterState(
            provider: provider,
            name: metadata.displayName,
            status: status,
            detail: detail,
            remainingPercent: remaining,
            hasTokenRecords: tokenSnapshot != nil || tokenError != nil,
            hasStorage: storage?.hasLocalData == true,
            storageText: storage.map { UsageFormatter.byteCountString($0.totalBytes) },
            cleanupCount: storage?.cleanupRecommendations.count ?? 0,
            dashboardURL: dashboardURL,
            statusURL: statusURL)
    }

    private func detailText(
        status: ConductorUsageProviderCenterStatus,
        snapshot: UsageSnapshot?,
        tokenSnapshot: CostUsageTokenSnapshot?,
        storage: ProviderStorageFootprint?,
        error: String?,
        remaining: Double?) -> String
    {
        switch status {
        case .refreshing:
            return t("正在刷新服务、状态和本地记录", "Refreshing service, status, and local records")
        case .needsAttention:
            let fallback = t("需要重新连接或检查来源", "Reconnect or inspect this source")
            let redacted = PersonalInfoRedactor.redactEmails(
                in: error?.trimmingCharacters(in: .whitespacesAndNewlines),
                isEnabled: context.settings.hidePersonalInfo)
            return redacted?.nilIfEmpty ?? fallback
        case .ready:
            if let remaining {
                let percent = Int(remaining.rounded())
                return t(
                    "主窗口约 \(percent)% 余量",
                    "Primary window has about \(percent)% left")
            }
            if let tokenSnapshot {
                let updated = tokenSnapshot.updatedAt.formatted(date: .omitted, time: .shortened)
                return t(
                    "Token 记录更新于 \(updated)",
                    "Token records updated at \(updated)")
            }
            if let storage, storage.hasLocalData {
                let size = UsageFormatter.byteCountString(storage.totalBytes)
                return t("本地数据 \(size)", "\(size) local data")
            }
            if let snapshot {
                let updated = snapshot.updatedAt.formatted(date: .omitted, time: .shortened)
                return t("用量更新于 \(updated)", "Usage updated at \(updated)")
            }
            return t("已接入，可继续刷新", "Connected and ready to refresh")
        case .waiting:
            return t(
                "还没有拿到数据，刷新后会在这里展开",
                "No data yet; refresh to unfold details here")
        }
    }

    private func prime() {
        context.store.scheduleStorageFootprintRefreshForOverview(force: false)
        Task { @MainActor in
            await context.store.refreshLocalTokenUsageNow(for: tokenRecordProviders, force: false)
        }
    }

    private func refreshAll() {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        Task { @MainActor in
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await context.store.refresh(forceTokenUsage: true)
            }
            context.store.scheduleStorageFootprintRefreshForOverview(force: true)
            isRefreshingAll = false
        }
    }

    private func refresh(provider: UsageProvider) {
        Task { @MainActor in
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                if provider == .codex {
                    await context.store.refreshCodexAccountScopedState(allowDisabled: true)
                } else {
                    await context.store.refreshProvider(provider, allowDisabled: true)
                }
                await context.store.refreshLocalTokenUsageNow(for: [provider], force: true)
                await context.store.refreshStorageFootprintsNow(for: [provider])
            }
        }
    }

    private func runCodexAccountAction() {
        runLoginFlow(provider: .codex)
    }

    private func runLoginFlow(provider: UsageProvider) {
        Task { @MainActor in
            await context.runProviderLoginFlow(provider)
        }
    }

    private func openTokenRecords() {
        ConductorUsageFeature.openTokenRecords(
            style: style,
            languageIdentifier: languageIdentifier)
    }

    private func focusStorage() {
        let provider = states.first { $0.hasStorage || $0.cleanupCount > 0 }?.provider ?? .codex
        ConductorUsageMotion.perform {
            expandedProvider = provider
        }
        context.store.scheduleStorageFootprintRefresh(for: [provider], force: true)
    }

    private func openURL(_ string: String?) {
        guard let string, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func t(_ zh: String, _ en: String) -> String {
        conductorTokenRecordsText(zh, en, languageIdentifier: languageIdentifier)
    }
}

private enum ConductorUsageCenterRoute: Hashable {
    case account
    case records
    case storage
}

private struct ConductorUsageProviderCenterState: Identifiable {
    let provider: UsageProvider
    let name: String
    let status: ConductorUsageProviderCenterStatus
    let detail: String
    let remainingPercent: Double?
    let hasTokenRecords: Bool
    let hasStorage: Bool
    let storageText: String?
    let cleanupCount: Int
    let dashboardURL: String?
    let statusURL: String?

    var id: UsageProvider { provider }

    var isRefreshing: Bool {
        status == .refreshing
    }
}

private enum ConductorUsageProviderCenterStatus {
    case ready
    case refreshing
    case needsAttention
    case waiting

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .refreshing:
            "arrow.triangle.2.circlepath"
        case .needsAttention:
            "exclamationmark.triangle.fill"
        case .waiting:
            "clock"
        }
    }

    func color(style: ConductorUsagePanelStyle) -> Color {
        switch self {
        case .ready:
            style.emphasis
        case .refreshing:
            style.secondaryText
        case .needsAttention:
            Color.orange
        case .waiting:
            style.tertiaryText
        }
    }

    func label(languageIdentifier: String?) -> String {
        switch self {
        case .ready:
            conductorTokenRecordsText("数据正常", "Healthy", languageIdentifier: languageIdentifier)
        case .refreshing:
            conductorTokenRecordsText("同步中", "Syncing", languageIdentifier: languageIdentifier)
        case .needsAttention:
            conductorTokenRecordsText("需要处理", "Needs attention", languageIdentifier: languageIdentifier)
        case .waiting:
            conductorTokenRecordsText("等待数据", "Waiting", languageIdentifier: languageIdentifier)
        }
    }
}

private struct ConductorUsageCenterRouteTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let style: ConductorUsagePanelStyle
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.emphasis)
                    .frame(width: 28, height: 28)
                    .background(style.controlFill.opacity(0.86))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(style.tertiaryText.opacity(isHovered ? 0.95 : 0.62))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(style.controlStrongFill.opacity(isHovered ? 0.70 : 0.46))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(style.stroke.opacity(isHovered ? 0.58 : 0.34), lineWidth: 0.7)
            }
            .scaleEffect(isHovered ? 1.01 : 1)
            .animation(ConductorUsageMotion.hover, value: isHovered)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct ConductorUsageProviderRail: View {
    let states: [ConductorUsageProviderCenterState]
    let expandedProvider: UsageProvider?
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let select: (UsageProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(conductorTokenRecordsText("服务", "Services", languageIdentifier: languageIdentifier))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)

                Rectangle()
                    .fill(style.separator.opacity(0.56))
                    .frame(height: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(states) { state in
                        ConductorUsageProviderPill(
                            state: state,
                            selected: expandedProvider == state.provider,
                            style: style,
                            languageIdentifier: languageIdentifier)
                        {
                            select(state.provider)
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }
}

private struct ConductorUsageProviderPill: View {
    let state: ConductorUsageProviderCenterState
    let selected: Bool
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                ConductorUsageProviderGlyph(provider: state.provider, style: style, size: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(state.name)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(style.primaryText)
                        .lineLimit(1)
                    Text(state.status.label(languageIdentifier: languageIdentifier))
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(state.status.color(style: style))
                        .lineLimit(1)
                }

                Image(systemName: selected ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(style.tertiaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(
                selected
                    ? style.controlStrongFill.opacity(style.usesDarkChrome ? 0.42 : 0.62)
                    : style.controlFill.opacity(isHovered ? 0.70 : 0.46))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(style.emphasis.opacity(style.usesDarkChrome ? 0.56 : 0.42))
                        .frame(width: 3, height: 18)
                        .padding(.leading, 3)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        selected
                            ? style.emphasis.opacity(style.usesDarkChrome ? 0.34 : 0.24)
                            : style.stroke.opacity(0.24),
                        lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(state.name), \(state.status.label(languageIdentifier: languageIdentifier))")
    }
}

private struct ConductorUsageProviderFocusCard: View {
    let state: ConductorUsageProviderCenterState
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let refresh: () -> Void
    let connect: () -> Void
    let openDashboard: () -> Void
    let openStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ConductorUsageProviderGlyph(provider: state.provider, style: style, size: 32)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(state.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(style.primaryText)
                            .lineLimit(1)

                        ConductorUsageCenterStatusPill(
                            title: state.status.label(languageIdentifier: languageIdentifier),
                            status: state.status,
                            style: style)
                    }

                    Text(state.detail)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }

            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    if let remainingPercent = state.remainingPercent {
                        ConductorUsageMiniBadge(
                            text: conductorTokenRecordsText(
                                "\(Int(remainingPercent.rounded()))% 用量余量",
                                "\(Int(remainingPercent.rounded()))% usage left",
                                languageIdentifier: languageIdentifier),
                            systemImage: "gauge.medium",
                            style: style)
                    }

                    if state.hasTokenRecords {
                        ConductorUsageMiniBadge(
                            text: conductorTokenRecordsText(
                                "Token 记录可用",
                                "Token records ready",
                                languageIdentifier: languageIdentifier),
                            systemImage: "doc.text.magnifyingglass",
                            style: style)
                    }

                    if let storageText = state.storageText {
                        ConductorUsageMiniBadge(
                            text: conductorTokenRecordsText(
                                "本地 \(storageText)",
                                "\(storageText) local",
                                languageIdentifier: languageIdentifier),
                            systemImage: "internaldrive",
                            style: style)
                    }

                    if state.cleanupCount > 0 {
                        ConductorUsageMiniBadge(
                            text: conductorTokenRecordsText(
                                "\(state.cleanupCount) 条清理建议",
                                "\(state.cleanupCount) cleanup ideas",
                                languageIdentifier: languageIdentifier),
                            systemImage: "magnifyingglass",
                            style: style)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    ConductorUsageFocusButton(
                        systemImage: "arrow.clockwise",
                        title: conductorTokenRecordsText("刷新数据", "Refresh Data", languageIdentifier: languageIdentifier),
                        subtitle: conductorTokenRecordsText(
                            "重新读取当前服务状态",
                            "Reread this provider state",
                            languageIdentifier: languageIdentifier),
                        style: style,
                        action: refresh)

                    ConductorUsageFocusButton(
                        systemImage: "person.crop.circle.badge.plus",
                        title: conductorTokenRecordsText("连接账户", "Connect Account", languageIdentifier: languageIdentifier),
                        subtitle: conductorTokenRecordsText(
                            "切换账户或补登录",
                            "Switch account or sign in",
                            languageIdentifier: languageIdentifier),
                        style: style,
                        action: connect)

                    if state.dashboardURL != nil {
                        ConductorUsageFocusButton(
                            systemImage: "safari",
                            title: conductorTokenRecordsText("用量网页", "Usage Page", languageIdentifier: languageIdentifier),
                            subtitle: conductorTokenRecordsText(
                                "打开服务网页",
                                "Open provider page",
                                languageIdentifier: languageIdentifier),
                            style: style,
                            action: openDashboard)
                    }

                    if state.statusURL != nil {
                        ConductorUsageFocusButton(
                            systemImage: "waveform.path.ecg",
                            title: conductorTokenRecordsText("服务状态", "Service Status", languageIdentifier: languageIdentifier),
                            subtitle: conductorTokenRecordsText(
                                "查看故障信息",
                                "View incidents",
                                languageIdentifier: languageIdentifier),
                            style: style,
                            action: openStatus)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(style.controlStrongFill.opacity(style.usesDarkChrome ? 0.22 : 0.36))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(style.stroke.opacity(0.28), lineWidth: 0.7)
        }
    }
}

private struct ConductorUsageCenterStatusPill: View {
    let title: String
    let status: ConductorUsageProviderCenterStatus
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.systemImage)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(status.color(style: style))
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(style.controlStrongFill.opacity(0.62))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(status.color(style: style).opacity(0.28), lineWidth: 0.8)
        }
    }
}

private struct ConductorUsageMiniBadge: View {
    let text: String
    let systemImage: String
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8.5, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(style.secondaryText)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(style.controlFill.opacity(0.72))
        .clipShape(Capsule())
    }
}

private struct ConductorUsageFocusButton: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let style: ConductorUsagePanelStyle
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(style.emphasis)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(style.controlFill.opacity(isHovered ? 0.78 : 0.42))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(style.stroke.opacity(isHovered ? 0.48 : 0.22), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(title): \(subtitle)")
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

private struct ConductorUsageProviderGlyph: View {
    let provider: UsageProvider
    let style: ConductorUsagePanelStyle
    let size: CGFloat

    var body: some View {
        Group {
            if let image = ProviderBrandIcon.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.48, weight: .semibold))
            }
        }
        .foregroundStyle(style.secondaryText)
        .frame(width: size * 0.58, height: size * 0.58)
        .frame(width: size, height: size)
        .background(style.controlFill.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: min(8, size * 0.28), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: min(8, size * 0.28), style: .continuous)
                .stroke(style.stroke.opacity(0.28), lineWidth: 0.7)
        }
        .accessibilityHidden(true)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
