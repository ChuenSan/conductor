import AppKit
import CodexBarCore
import SwiftUI

@MainActor
struct ConductorUsageWorkbenchPanel: View {
    let context: ConductorUsageSettingsContext
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedProvider: UsageProvider = .codex
    @State private var expandedSections: Set<ConductorUsageWorkbenchSection> = [.trends, .quick]
    @State private var isRefreshingSelection = false
    @State private var isRefreshingAll = false

    private var providerStates: [ConductorUsageWorkbenchProviderState] {
        var providers = context.store.enabledProvidersForDisplay()
        for provider in UsageProvider.allCases {
            let hasData = context.store.snapshot(for: provider) != nil ||
                context.store.tokenSnapshot(for: provider) != nil ||
                context.store.tokenError(for: provider) != nil ||
                context.store.storageFootprint(for: provider) != nil ||
                context.store.status(for: provider) != nil ||
                context.store.error(for: provider) != nil
            guard hasData, !providers.contains(provider) else { continue }
            providers.append(provider)
        }

        if providers.isEmpty {
            providers = [.codex]
        }

        return providers.prefix(24).map(makeState(for:))
    }

    private var currentState: ConductorUsageWorkbenchProviderState {
        providerStates.first { $0.provider == selectedProvider } ?? providerStates.first ?? makeState(for: .codex)
    }

    private var providerIDs: String {
        providerStates.map(\.provider.rawValue).joined(separator: "|")
    }

    var body: some View {
        let state = currentState

        VStack(alignment: .leading, spacing: 10) {
            header(state: state)
            serviceRail(states: providerStates)

            VStack(alignment: .leading, spacing: 8) {
                ConductorUsageWorkbenchCard(
                    section: .trends,
                    isExpanded: expandedSections.contains(.trends),
                    style: style,
                    languageIdentifier: languageIdentifier,
                    toggle: { toggle(.trends) })
                {
                    trendSummary(state: state)
                } detail: {
                    trendDetail(state: state)
                }

                ConductorUsageWorkbenchCard(
                    section: .storage,
                    isExpanded: expandedSections.contains(.storage),
                    style: style,
                    languageIdentifier: languageIdentifier,
                    toggle: { toggle(.storage) })
                {
                    storageSummary(state: state)
                } detail: {
                    storageDetail(state: state)
                }

                ConductorUsageWorkbenchCard(
                    section: .status,
                    isExpanded: expandedSections.contains(.status),
                    style: style,
                    languageIdentifier: languageIdentifier,
                    toggle: { toggle(.status) })
                {
                    statusSummary(state: state)
                } detail: {
                    statusDetail(state: state)
                }

                ConductorUsageWorkbenchCard(
                    section: .costs,
                    isExpanded: expandedSections.contains(.costs),
                    style: style,
                    languageIdentifier: languageIdentifier,
                    toggle: { toggle(.costs) })
                {
                    costSummary(state: state)
                } detail: {
                    costDetail(state: state)
                }

                ConductorUsageWorkbenchCard(
                    section: .quick,
                    isExpanded: expandedSections.contains(.quick),
                    style: style,
                    languageIdentifier: languageIdentifier,
                    toggle: { toggle(.quick) })
                {
                    quickSummary(state: state)
                } detail: {
                    quickDetail(state: state)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.panelBase.opacity(style.usesDarkChrome ? 0.24 : 0.50))
                .overlay(
                    LinearGradient(
                        colors: [
                            style.panelWash.opacity(style.usesDarkChrome ? 0.10 : 0.20),
                            style.controlFill.opacity(style.usesDarkChrome ? 0.08 : 0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.stroke.opacity(0.24), lineWidth: 0.8)
        }
        .onAppear {
            normalizeSelection()
            prime()
        }
        .onChange(of: providerIDs) { _, _ in
            normalizeSelection()
        }
        .onChange(of: selectedProvider) { _, provider in
            Task { @MainActor in
                await context.store.refreshLocalTokenUsageNow(for: [provider], force: false)
            }
        }
    }

    private func header(state: ConductorUsageWorkbenchProviderState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(style.emphasis)
                .frame(width: 26, height: 26)
                .background(style.emphasis.opacity(style.usesDarkChrome ? 0.14 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(t("用量工作台", "Usage Workbench"))
                    .font(.system(size: 13.2, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)

                Text(headerSubtitle(state: state))
                    .font(.system(size: 10.4, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ConductorUsageWorkbenchStatusCapsule(
                text: state.statusText,
                indicator: state.statusIndicator,
                style: style)

            Button {
                refreshAll()
            } label: {
                Label(
                    t("刷新全部用量", "Refresh all usage"),
                    systemImage: isRefreshingAll || context.store.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(isRefreshingAll || context.store.isRefreshing)
            .help(t("刷新服务状态、用量记录和本地数据", "Refresh service status, usage records, and local data"))
            .accessibilityLabel(t("刷新全部用量", "Refresh all usage"))
        }
    }

    private func serviceRail(states: [ConductorUsageWorkbenchProviderState]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(states) { state in
                    ConductorUsageWorkbenchServiceChip(
                        state: state,
                        isSelected: state.provider == currentState.provider,
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

    private func trendSummary(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ConductorUsageWorkbenchMetricPair(
                primary: trendPrimaryText(state: state),
                secondary: trendSecondaryText(state: state),
                style: style)

            ConductorUsageWorkbenchSparkline(
                values: trendValues(state: state),
                tint: style.emphasis,
                muted: style.separator)
                .frame(height: 42)
                .accessibilityHidden(true)
        }
    }

    private func trendDetail(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ConductorUsageWorkbenchBars(
                values: trendValues(state: state),
                tint: style.emphasis,
                muted: style.separator)
                .frame(height: 46)
                .accessibilityHidden(true)

            let rows = trendRows(state: state)
            if rows.isEmpty {
                emptyLine(t("暂无日线记录", "No daily records yet"), systemImage: "chart.xyaxis.line")
            } else {
                ForEach(rows) { row in
                    ConductorUsageWorkbenchDataRow(
                        icon: row.icon,
                        title: row.title,
                        value: row.value,
                        detail: row.detail,
                        style: style)
                }
            }
        }
    }

    private func storageSummary(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ConductorUsageWorkbenchMetricPair(
                primary: state.storageText,
                secondary: storageSecondaryText(state: state),
                style: style)

            HStack(spacing: 6) {
                ConductorUsageWorkbenchTinyPill(
                    text: t("\(state.storageComponentCount) 项", "\(state.storageComponentCount) items"),
                    systemImage: "square.stack.3d.up",
                    style: style)
                ConductorUsageWorkbenchTinyPill(
                    text: t("\(state.cleanupCount) 条建议", "\(state.cleanupCount) ideas"),
                    systemImage: "sparkle.magnifyingglass",
                    style: style)
                Spacer(minLength: 0)
            }
        }
    }

    private func storageDetail(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let storage = state.storage {
                let recommendations = storage.cleanupRecommendations.prefix(4)
                if !recommendations.isEmpty {
                    ForEach(Array(recommendations)) { recommendation in
                        ConductorUsageWorkbenchPathRow(
                            icon: "folder.badge.gearshape",
                            title: localizedStorageTitle(recommendation.title),
                            subtitle: localizedStorageConsequence(recommendation.consequence),
                            value: UsageFormatter.byteCountString(recommendation.bytes),
                            path: recommendation.path,
                            style: style,
                            languageIdentifier: languageIdentifier,
                            copyPath: { copyToPasteboard(recommendation.path) },
                            revealPath: { revealPath(recommendation.path) })
                    }
                } else {
                    ForEach(storage.components.prefix(4)) { component in
                        ConductorUsageWorkbenchPathRow(
                            icon: "folder",
                            title: component.name,
                            subtitle: component.path,
                            value: UsageFormatter.byteCountString(component.totalBytes),
                            path: component.path,
                            style: style,
                            languageIdentifier: languageIdentifier,
                            copyPath: { copyToPasteboard(component.path) },
                            revealPath: { revealPath(component.path) })
                    }
                }

                if storage.components.isEmpty && !storage.hasLocalData {
                    emptyLine(t("没有发现本地缓存或日志", "No local cache or logs found"), systemImage: "checkmark.circle")
                }
            } else if context.store.isStorageRefreshInFlight {
                emptyLine(t("正在扫描本地数据", "Scanning local data"), systemImage: "hourglass")
            } else {
                emptyLine(t("刷新后显示缓存、日志和整理建议", "Refresh to show cache, logs, and cleanup ideas"), systemImage: "internaldrive")
            }

            HStack(spacing: 7) {
                ConductorUsageWorkbenchActionButton(
                    title: t("重新扫描", "Rescan"),
                    systemImage: "arrow.clockwise",
                    style: style,
                    action: { refreshStorage(for: state.provider) })
                if let path = state.storage?.paths.first {
                    ConductorUsageWorkbenchActionButton(
                        title: t("定位根目录", "Reveal Root"),
                        systemImage: "arrow.up.forward.square",
                        style: style,
                        action: { revealPath(path) })
                }
            }
        }
    }

    private func statusSummary(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ConductorUsageWorkbenchMetricPair(
                primary: state.statusText,
                secondary: statusSecondaryText(state: state),
                style: style)

            HStack(spacing: 6) {
                ForEach(statusMiniProviders().prefix(4)) { item in
                    ConductorUsageWorkbenchDotLabel(
                        text: item.name,
                        indicator: item.statusIndicator,
                        style: style)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func statusDetail(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let description = state.statusDescription?.workbenchNilIfEmpty {
                Text(description)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(statusMiniProviders().prefix(6)) { item in
                ConductorUsageWorkbenchDataRow(
                    icon: "waveform.path.ecg",
                    title: item.name,
                    value: item.statusText,
                    detail: item.statusDetail,
                    style: style)
            }

            HStack(spacing: 7) {
                if state.statusURL != nil {
                    ConductorUsageWorkbenchActionButton(
                        title: t("状态页", "Status"),
                        systemImage: "waveform.path.ecg",
                        style: style,
                        action: { openURL(state.statusURL) })
                }
                if state.changelogURL != nil {
                    ConductorUsageWorkbenchActionButton(
                        title: t("更新记录", "Changes"),
                        systemImage: "doc.text.magnifyingglass",
                        style: style,
                        action: { openURL(state.changelogURL) })
                }
                ConductorUsageWorkbenchActionButton(
                    title: t("同步状态", "Sync"),
                    systemImage: "arrow.triangle.2.circlepath",
                    style: style,
                    action: { refreshAll() })
            }
        }
    }

    private func costSummary(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ConductorUsageWorkbenchMetricPair(
                primary: costPrimaryText(state: state),
                secondary: costSecondaryText(state: state),
                style: style)

            HStack(spacing: 6) {
                ConductorUsageWorkbenchTinyPill(
                    text: tokenTotalText(state: state),
                    systemImage: "number",
                    style: style)
                if state.supportsCredits || state.provider == .codex {
                    ConductorUsageWorkbenchTinyPill(
                        text: creditsShortText(state: state),
                        systemImage: "creditcard",
                        style: style)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func costDetail(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ConductorUsageWorkbenchDataRow(
                icon: "calendar",
                title: t("近 30 天", "Last 30 days"),
                value: costPrimaryText(state: state),
                detail: tokenTotalText(state: state),
                style: style)

            ConductorUsageWorkbenchDataRow(
                icon: "clock",
                title: t("当前会话", "Session"),
                value: state.tokenSnapshot?.sessionCostUSD.map(UsageFormatter.usdString) ?? t("暂无成本", "No cost"),
                detail: state.tokenSnapshot?.sessionTokens.map(UsageFormatter.tokenCountString) ?? t("等待记录", "Waiting for records"),
                style: style)

            if let providerCost = state.snapshot?.providerCost {
                let used = providerCost.used.formatted(.number.precision(.fractionLength(0...2)))
                let limit = providerCost.limit.formatted(.number.precision(.fractionLength(0...2)))
                ConductorUsageWorkbenchDataRow(
                    icon: "wallet.pass",
                    title: providerCost.period ?? t("周期额度", "Period budget"),
                    value: "\(used)/\(limit) \(providerCost.currencyCode)",
                    detail: providerCost.resetsAt
                        .flatMap { date in
                            UsageFormatter.resetLine(
                                for: RateWindow(
                                    usedPercent: providerCost.limit > 0 ? providerCost.used / providerCost.limit * 100 : 0,
                                    windowMinutes: nil,
                                    resetsAt: date,
                                    resetDescription: nil),
                                style: .countdown,
                                now: Date())
                        } ?? "",
                    style: style)
            }

            if state.provider == .codex, let credits = context.store.credits {
                let latest = credits.events.first
                ConductorUsageWorkbenchDataRow(
                    icon: "creditcard",
                    title: t("余额", "Balance"),
                    value: UsageFormatter.creditsString(from: credits.remaining),
                    detail: latest.map { UsageFormatter.creditEventSummary($0) } ?? t("暂无最近扣减", "No recent spend"),
                    style: style)
            } else if let hint = creditsHintText(state: state).workbenchNilIfEmpty {
                ConductorUsageWorkbenchDataRow(
                    icon: "creditcard",
                    title: t("余额线索", "Balance hint"),
                    value: state.supportsCredits ? t("可读取", "Readable") : t("服务页面", "Service page"),
                    detail: hint,
                    style: style)
            }

            HStack(spacing: 7) {
                if state.dashboardURL != nil {
                    ConductorUsageWorkbenchActionButton(
                        title: t("服务页面", "Service Page"),
                        systemImage: "safari",
                        style: style,
                        action: { openURL(state.dashboardURL) })
                }
                if state.provider == .codex,
                   let purchaseURL = context.store.openAIDashboard?.creditsPurchaseURL
                {
                    ConductorUsageWorkbenchActionButton(
                        title: t("购买额度", "Buy Credits"),
                        systemImage: "plus.circle",
                        style: style,
                        action: { openURL(purchaseURL) })
                }
            }
        }
    }

    private func quickSummary(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ConductorUsageWorkbenchMetricPair(
                primary: t("当前：\(state.name)", "Current: \(state.name)"),
                secondary: quickSecondaryText(state: state),
                style: style)

            HStack(spacing: 7) {
                quickIcon("arrow.clockwise", t("刷新当前", "Refresh current")) { refreshSelection() }
                quickIcon("chart.bar.doc.horizontal", t("记录窗口", "Records window")) { openTokenRecords() }
                quickIcon("doc.on.clipboard", t("复制摘要", "Copy summary")) { copySummary(state: state) }
                quickIcon("person.badge.key", t("连接服务", "Connect provider")) { runLoginFlow(provider: state.provider) }
            }
        }
    }

    private func quickDetail(state: ConductorUsageWorkbenchProviderState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ConductorUsageWorkbenchDataRow(
                icon: "arrow.clockwise",
                title: t("刷新当前服务", "Refresh current provider"),
                value: state.isRefreshing || isRefreshingSelection ? t("进行中", "Running") : t("立即执行", "Run now"),
                detail: t("同步余量、Token 记录和本地扫描", "Sync quota, token records, and local scan"),
                style: style)

            ConductorUsageWorkbenchDataRow(
                icon: "doc.on.clipboard",
                title: t("复制摘要", "Copy summary"),
                value: t("剪贴板", "Clipboard"),
                detail: t("包含服务、余量、成本、本地数据和状态", "Provider, quota, cost, local data, and status"),
                style: style)

            HStack(spacing: 7) {
                ConductorUsageWorkbenchActionButton(
                    title: t("刷新当前", "Refresh"),
                    systemImage: "arrow.clockwise",
                    style: style,
                    action: { refreshSelection() })
                ConductorUsageWorkbenchActionButton(
                    title: t("Token 记录", "Token Records"),
                    systemImage: "chart.bar.doc.horizontal",
                    style: style,
                    action: { openTokenRecords() })
                ConductorUsageWorkbenchActionButton(
                    title: t("复制摘要", "Copy"),
                    systemImage: "doc.on.clipboard",
                    style: style,
                    action: { copySummary(state: state) })
                ConductorUsageWorkbenchActionButton(
                    title: t("连接", "Connect"),
                    systemImage: "person.badge.key",
                    style: style,
                    action: { runLoginFlow(provider: state.provider) })
            }
        }
    }

    private func emptyLine(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.tertiaryText)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(style.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func quickIcon(_ systemImage: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(help, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
    }

    private func makeState(for provider: UsageProvider) -> ConductorUsageWorkbenchProviderState {
        let metadata = context.store.metadata(for: provider)
        let snapshot = context.store.snapshot(for: provider)
        let tokenSnapshot = context.store.tokenSnapshot(for: provider)
        let storage = context.store.storageFootprint(for: provider)
        let status = context.store.status(for: provider)
        let indicator = context.store.statusIndicator(for: provider)
        let providerError = context.store.error(for: provider)
        let tokenError = context.store.tokenError(for: provider)
        let error = providerError ?? tokenError
        let isRefreshing = context.store.refreshingProviders.contains(provider) ||
            context.store.isTokenRefreshInFlight(for: provider)
        let window = snapshot?.primary ?? snapshot?.secondary ?? snapshot?.tertiary
        let statusText = statusText(indicator: indicator, hasStatus: status != nil, error: error, isRefreshing: isRefreshing)

        return ConductorUsageWorkbenchProviderState(
            provider: provider,
            name: metadata.displayName,
            snapshot: snapshot,
            tokenSnapshot: tokenSnapshot,
            storage: storage,
            statusIndicator: indicator,
            statusText: statusText,
            statusDescription: status?.description,
            isEnabled: context.store.enabledProvidersForDisplay().contains(provider),
            isRefreshing: isRefreshing,
            error: error,
            tokenError: tokenError,
            primaryRemaining: window?.remainingPercent,
            primaryLabel: windowLabel(window: window, metadata: metadata),
            storageText: storage.map { UsageFormatter.byteCountString($0.totalBytes) } ?? t("未扫描", "Not scanned"),
            storageComponentCount: storage?.components.count ?? 0,
            cleanupCount: storage?.cleanupRecommendations.count ?? 0,
            dashboardURL: metadata.subscriptionDashboardURL ?? metadata.dashboardURL,
            statusURL: metadata.statusLinkURL ?? metadata.statusPageURL,
            changelogURL: metadata.changelogURL,
            supportsCredits: metadata.supportsCredits,
            creditsHint: metadata.creditsHint)
    }

    private func headerSubtitle(state: ConductorUsageWorkbenchProviderState) -> String {
        let readyCount = providerStates.filter {
            $0.snapshot != nil || $0.tokenSnapshot != nil || $0.storage?.hasLocalData == true
        }.count
        let issueCount = providerStates.filter {
            $0.error != nil || $0.statusIndicator.hasIssue
        }.count
        if issueCount > 0 {
            return t("\(readyCount) 个服务有数据，\(issueCount) 项需处理", "\(readyCount) services with data, \(issueCount) need attention")
        }
        return t("\(readyCount) 个服务有数据 · 当前 \(state.name)", "\(readyCount) services with data · \(state.name)")
    }

    private func trendPrimaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        if let cost = state.tokenSnapshot?.last30DaysCostUSD {
            return UsageFormatter.usdString(cost)
        }
        if let tokens = state.tokenSnapshot?.last30DaysTokens {
            return UsageFormatter.tokenCountString(tokens)
        }
        if let remaining = state.primaryRemaining {
            return t("\(Int(remaining.rounded()))% 余量", "\(Int(remaining.rounded()))% left")
        }
        return t("等待记录", "Waiting")
    }

    private func trendSecondaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        guard let snapshot = state.tokenSnapshot, !snapshot.daily.isEmpty else {
            if let updatedAt = state.snapshot?.updatedAt {
                return t("用量更新于 \(shortTime(updatedAt))", "Usage updated \(shortTime(updatedAt))")
            }
            return t("刷新后生成趋势", "Refresh to build trend")
        }

        let average = rollingAverageCost(snapshot: snapshot)
        if average > 0 {
            return t("7 日均值 \(UsageFormatter.usdString(average))/天", "7d avg \(UsageFormatter.usdString(average))/day")
        }
        let tokenAverage = rollingAverageTokens(snapshot: snapshot)
        if tokenAverage > 0 {
            return t("7 日均值 \(UsageFormatter.tokenCountString(tokenAverage))/天", "7d avg \(UsageFormatter.tokenCountString(tokenAverage))/day")
        }
        return t("\(snapshot.daily.count) 天记录", "\(snapshot.daily.count) days recorded")
    }

    private func trendRows(state: ConductorUsageWorkbenchProviderState) -> [ConductorUsageWorkbenchRow] {
        guard let snapshot = state.tokenSnapshot else { return [] }
        let daily = snapshot.daily.sorted { $0.date < $1.date }
        let latest = daily.last
        var rows: [ConductorUsageWorkbenchRow] = []

        if let latest {
            rows.append(ConductorUsageWorkbenchRow(
                icon: "calendar.badge.clock",
                title: t("最近一天", "Latest day"),
                value: latest.costUSD.map(UsageFormatter.usdString) ??
                    latest.totalTokens.map(UsageFormatter.tokenCountString) ?? "--",
                detail: latest.date))
        }

        let model = topModelText(from: daily)
        if !model.value.isEmpty {
            rows.append(ConductorUsageWorkbenchRow(
                icon: "cpu",
                title: t("主要模型", "Top model"),
                value: model.value,
                detail: model.detail))
        }

        let projectedCost = rollingAverageCost(snapshot: snapshot) * 30
        if projectedCost > 0 {
            rows.append(ConductorUsageWorkbenchRow(
                icon: "arrow.up.right",
                title: t("按 7 日均值估算", "Projected from 7d avg"),
                value: UsageFormatter.usdString(projectedCost),
                detail: t("仅按本地记录估算", "Estimated from local records")))
        }

        return rows
    }

    private func trendValues(state: ConductorUsageWorkbenchProviderState) -> [Double] {
        guard let snapshot = state.tokenSnapshot else {
            if let remaining = state.primaryRemaining {
                return [remaining, remaining]
            }
            return []
        }

        return snapshot.daily
            .sorted { $0.date < $1.date }
            .suffix(max(1, min(snapshot.historyDays, 30)))
            .map { entry in
                if let cost = entry.costUSD, cost > 0 {
                    return cost
                }
                return Double(entry.totalTokens ?? 0)
            }
    }

    private func storageSecondaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        if context.store.isStorageRefreshInFlight {
            return t("正在扫描", "Scanning")
        }
        if state.cleanupCount > 0 {
            return t("\(state.cleanupCount) 条可整理项", "\(state.cleanupCount) cleanup ideas")
        }
        if state.storage?.hasLocalData == true {
            return t("缓存和日志已索引", "Cache and logs indexed")
        }
        return t("暂无本地痕迹", "No local traces")
    }

    private func statusSecondaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        if !context.store.statusChecksEnabled {
            return t("状态检查已关闭", "Status checks disabled")
        }
        if let updatedAt = context.store.status(for: state.provider)?.updatedAt {
            return t("更新于 \(shortTime(updatedAt))", "Updated \(shortTime(updatedAt))")
        }
        if state.statusURL != nil {
            return t("可打开服务状态页", "Status page available")
        }
        return t("该服务暂无状态源", "No status source")
    }

    private func costPrimaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        if let cost = state.tokenSnapshot?.last30DaysCostUSD {
            return UsageFormatter.usdString(cost)
        }
        if let providerCost = state.snapshot?.providerCost {
            let used = providerCost.used.formatted(.number.precision(.fractionLength(0...2)))
            return "\(used) \(providerCost.currencyCode)"
        }
        if state.provider == .codex, let credits = context.store.credits {
            return UsageFormatter.creditsString(from: credits.remaining)
        }
        return t("暂无成本", "No cost")
    }

    private func costSecondaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        if let updatedAt = state.tokenSnapshot?.updatedAt {
            return t("Token 成本更新于 \(shortTime(updatedAt))", "Token cost updated \(shortTime(updatedAt))")
        }
        if state.supportsCredits {
            return creditsHintText(state: state).workbenchNilIfEmpty ?? t("可读取余额", "Balance readable")
        }
        return t("可跳转服务页面核对", "Open service page to verify")
    }

    private func tokenTotalText(state: ConductorUsageWorkbenchProviderState) -> String {
        state.tokenSnapshot?.last30DaysTokens.map(UsageFormatter.tokenCountString) ?? t("无 Token", "No tokens")
    }

    private func creditsShortText(state: ConductorUsageWorkbenchProviderState) -> String {
        if state.provider == .codex, let credits = context.store.credits {
            return UsageFormatter.creditsString(from: credits.remaining)
        }
        if state.supportsCredits {
            return t("余额", "Balance")
        }
        return t("页面", "Page")
    }

    private func quickSecondaryText(state: ConductorUsageWorkbenchProviderState) -> String {
        if state.error != nil {
            return t("建议先重新连接或刷新", "Reconnect or refresh first")
        }
        if state.isRefreshing || isRefreshingSelection {
            return t("正在同步当前服务", "Syncing current provider")
        }
        return t("刷新、记录、复制、连接", "Refresh, records, copy, connect")
    }

    private func creditsHintText(state: ConductorUsageWorkbenchProviderState) -> String {
        if state.provider == .codex,
           let error = context.store.userFacingLastCreditsError?.workbenchNilIfEmpty
        {
            return PersonalInfoRedactor.redactEmails(in: error, isEnabled: context.settings.hidePersonalInfo) ?? error
        }
        return state.creditsHint
    }

    private func statusMiniProviders() -> [ConductorUsageWorkbenchProviderState] {
        let candidates = providerStates.filter { state in
            state.statusURL != nil || context.store.status(for: state.provider) != nil || state.statusIndicator.hasIssue
        }
        if candidates.isEmpty {
            return Array(providerStates.prefix(4))
        }
        return Array(candidates.prefix(8))
    }

    private func statusText(
        indicator: ProviderStatusIndicator,
        hasStatus: Bool,
        error: String?,
        isRefreshing: Bool) -> String
    {
        if isRefreshing {
            return t("同步中", "Syncing")
        }
        if error != nil {
            return t("需处理", "Needs attention")
        }
        switch indicator {
        case .none:
            return hasStatus ? t("服务正常", "Operational") : t("待观察", "Watching")
        case .minor:
            return t("部分异常", "Partial outage")
        case .major:
            return t("主要异常", "Major outage")
        case .critical:
            return t("严重异常", "Critical")
        case .maintenance:
            return t("维护中", "Maintenance")
        case .unknown:
            return t("未知", "Unknown")
        }
    }

    private func windowLabel(window: RateWindow?, metadata: ProviderMetadata) -> String {
        guard let window else { return t("无窗口", "No window") }
        if window.windowMinutes.map({ $0 <= 6 * 60 }) ?? false {
            return metadata.sessionLabel
        }
        return metadata.weeklyLabel
    }

    private func rollingAverageCost(snapshot: CostUsageTokenSnapshot) -> Double {
        let values = snapshot.daily
            .sorted { $0.date < $1.date }
            .suffix(7)
            .compactMap(\.costUSD)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func rollingAverageTokens(snapshot: CostUsageTokenSnapshot) -> Int {
        let values = snapshot.daily
            .sorted { $0.date < $1.date }
            .suffix(7)
            .compactMap(\.totalTokens)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    private func topModelText(from entries: [CostUsageDailyReport.Entry]) -> (value: String, detail: String) {
        var totals: [String: (cost: Double, tokens: Int)] = [:]
        for breakdown in entries.flatMap({ $0.modelBreakdowns ?? [] }) {
            var total = totals[breakdown.modelName, default: (0, 0)]
            total.cost += breakdown.costUSD ?? 0
            total.tokens += breakdown.totalTokens ?? 0
            totals[breakdown.modelName] = total
        }

        guard let top = totals.max(by: { lhs, rhs in
            if lhs.value.cost == rhs.value.cost {
                return lhs.value.tokens < rhs.value.tokens
            }
            return lhs.value.cost < rhs.value.cost
        }) else {
            let models = entries.flatMap { $0.modelsUsed ?? [] }
            guard let first = models.first else { return ("", "") }
            return (first, t("来自本地 Token 记录", "From local token records"))
        }

        let detail = top.value.cost > 0
            ? UsageFormatter.usdString(top.value.cost)
            : UsageFormatter.tokenCountString(top.value.tokens)
        return (top.key, detail)
    }

    private func shortTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func localizedStorageTitle(_ title: String) -> String {
        guard isChineseLanguage else { return title }
        if title.localizedCaseInsensitiveContains("sessions") { return "会话历史" }
        if title.localizedCaseInsensitiveContains("archived") { return "归档会话" }
        if title.localizedCaseInsensitiveContains("cache") { return "缓存" }
        if title.localizedCaseInsensitiveContains("logs") { return "日志" }
        if title.localizedCaseInsensitiveContains("temporary") { return "临时数据" }
        if title.localizedCaseInsensitiveContains("file history") { return "文件历史" }
        if title.localizedCaseInsensitiveContains("attachment") { return "附件缓存" }
        return title.replacingOccurrences(of: "Manual cleanup: ", with: "")
    }

    private func localizedStorageConsequence(_ text: String) -> String {
        guard isChineseLanguage else { return text }
        if text.localizedCaseInsensitiveContains("session history") { return "清理会移除历史会话记录。" }
        if text.localizedCaseInsensitiveContains("cached data") { return "清理会移除服务生成的缓存。" }
        if text.localizedCaseInsensitiveContains("diagnostic logs") { return "清理会移除本地诊断日志。" }
        if text.localizedCaseInsensitiveContains("temporary") { return "清理会移除临时运行数据。" }
        if text.localizedCaseInsensitiveContains("checkpoint") { return "清理会移除旧的编辑检查点。" }
        return text
    }

    private func normalizeSelection() {
        guard !providerStates.contains(where: { $0.provider == selectedProvider }) else { return }
        selectedProvider = providerStates.first?.provider ?? .codex
    }

    private func prime() {
        context.store.scheduleStorageFootprintRefreshForOverview(force: false)
        Task { @MainActor in
            await context.store.refreshLocalTokenUsageNow(for: [currentState.provider], force: false)
        }
    }

    private func select(_ provider: UsageProvider) {
        guard selectedProvider != provider else { return }
        let update = { selectedProvider = provider }
        if reduceMotion {
            update()
        } else {
            ConductorUsageMotion.perform(ConductorUsageMotion.selection, update)
        }
    }

    private func toggle(_ section: ConductorUsageWorkbenchSection) {
        let update = {
            if expandedSections.contains(section) {
                expandedSections.remove(section)
            } else {
                expandedSections.insert(section)
            }
        }
        if reduceMotion {
            update()
        } else {
            ConductorUsageMotion.perform(ConductorUsageMotion.selection, update)
        }
    }

    private func refreshSelection() {
        guard !isRefreshingSelection else { return }
        isRefreshingSelection = true
        let provider = currentState.provider
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
            isRefreshingSelection = false
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

    private func refreshStorage(for provider: UsageProvider) {
        Task { @MainActor in
            await context.store.refreshStorageFootprintsNow(for: [provider])
        }
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

    private func openURL(_ string: String?) {
        guard let string, let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copySummary(state: ConductorUsageWorkbenchProviderState) {
        let lines = [
            "\(state.name)",
            "\(t("状态", "Status")): \(state.statusText)",
            "\(t("余量", "Quota")): \(state.primaryRemaining.map { "\(Int($0.rounded()))%" } ?? "--")",
            "\(t("成本", "Cost")): \(costPrimaryText(state: state))",
            "\(t("Token", "Tokens")): \(tokenTotalText(state: state))",
            "\(t("本地数据", "Local data")): \(state.storageText)",
        ]
        copyToPasteboard(lines.joined(separator: "\n"))
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func revealPath(_ path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func t(_ zh: String, _ en: String) -> String {
        conductorTokenRecordsText(zh, en, languageIdentifier: languageIdentifier)
    }

    private var isChineseLanguage: Bool {
        conductorTokenRecordsText("zh", "en", languageIdentifier: languageIdentifier) == "zh"
    }
}

private enum ConductorUsageWorkbenchSection: String, CaseIterable, Identifiable {
    case trends
    case storage
    case status
    case costs
    case quick

    var id: String { rawValue }

    func title(languageIdentifier: String?) -> String {
        switch self {
        case .trends:
            conductorTokenRecordsText("趋势", "Trends", languageIdentifier: languageIdentifier)
        case .storage:
            conductorTokenRecordsText("本地整理", "Local Care", languageIdentifier: languageIdentifier)
        case .status:
            conductorTokenRecordsText("服务状态", "Service Health", languageIdentifier: languageIdentifier)
        case .costs:
            conductorTokenRecordsText("成本与余额", "Cost & Balance", languageIdentifier: languageIdentifier)
        case .quick:
            conductorTokenRecordsText("快捷操作", "Quick Actions", languageIdentifier: languageIdentifier)
        }
    }

    func subtitle(languageIdentifier: String?) -> String {
        switch self {
        case .trends:
            conductorTokenRecordsText("日线、均值和估算", "Daily lines, averages, forecast", languageIdentifier: languageIdentifier)
        case .storage:
            conductorTokenRecordsText("缓存、日志和路径", "Cache, logs, and paths", languageIdentifier: languageIdentifier)
        case .status:
            conductorTokenRecordsText("服务页和异常", "Status pages and incidents", languageIdentifier: languageIdentifier)
        case .costs:
            conductorTokenRecordsText("Token、花费、余额", "Tokens, spend, balance", languageIdentifier: languageIdentifier)
        case .quick:
            conductorTokenRecordsText("常用动作集中处理", "Common actions in one place", languageIdentifier: languageIdentifier)
        }
    }

    var systemImage: String {
        switch self {
        case .trends:
            "chart.line.uptrend.xyaxis"
        case .storage:
            "internaldrive"
        case .status:
            "waveform.path.ecg"
        case .costs:
            "creditcard"
        case .quick:
            "bolt"
        }
    }
}

private struct ConductorUsageWorkbenchProviderState: Identifiable {
    let provider: UsageProvider
    let name: String
    let snapshot: UsageSnapshot?
    let tokenSnapshot: CostUsageTokenSnapshot?
    let storage: ProviderStorageFootprint?
    let statusIndicator: ProviderStatusIndicator
    let statusText: String
    let statusDescription: String?
    let isEnabled: Bool
    let isRefreshing: Bool
    let error: String?
    let tokenError: String?
    let primaryRemaining: Double?
    let primaryLabel: String
    let storageText: String
    let storageComponentCount: Int
    let cleanupCount: Int
    let dashboardURL: String?
    let statusURL: String?
    let changelogURL: String?
    let supportsCredits: Bool
    let creditsHint: String

    var id: UsageProvider { provider }

    var statusDetail: String {
        if let statusDescription, !statusDescription.isEmpty { return statusDescription }
        if let error, !error.isEmpty { return error }
        return primaryRemaining.map { "\(Int($0.rounded()))%" } ?? ""
    }
}

private struct ConductorUsageWorkbenchRow: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let detail: String
}

private struct ConductorUsageWorkbenchCard<Summary: View, Detail: View>: View {
    let section: ConductorUsageWorkbenchSection
    let isExpanded: Bool
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let toggle: () -> Void
    @ViewBuilder let summary: () -> Summary
    @ViewBuilder let detail: () -> Detail

    private var expansion: Binding<Bool> {
        Binding {
            isExpanded
        } set: { newValue in
            guard newValue != isExpanded else { return }
            toggle()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: expansion) {
                Rectangle()
                    .fill(style.separator.opacity(0.44))
                    .frame(height: 1)
                detail()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(style.emphasis)
                            .frame(width: 22, height: 22)
                            .background(style.emphasis.opacity(style.usesDarkChrome ? 0.14 : 0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.title(languageIdentifier: languageIdentifier))
                                .font(.system(size: 11.8, weight: .semibold))
                                .foregroundStyle(style.primaryText)
                                .lineLimit(1)
                            Text(section.subtitle(languageIdentifier: languageIdentifier))
                                .font(.system(size: 9.4, weight: .medium))
                                .foregroundStyle(style.tertiaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)
                    }

                    summary()
                }
            }
            .tint(style.tertiaryText)
            .accessibilityLabel(section.title(languageIdentifier: languageIdentifier))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(style.controlFill.opacity(style.usesDarkChrome ? 0.34 : 0.52))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style.stroke.opacity(isExpanded ? 0.34 : 0.22), lineWidth: 0.8)
        }
    }
}

private struct ConductorUsageWorkbenchServiceChip: View {
    let state: ConductorUsageWorkbenchProviderState
    let isSelected: Bool
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: symbol(for: state.provider))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? style.primaryText : style.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(iconBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)

                    Circle()
                        .fill(indicatorColor(state.statusIndicator, error: state.error))
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(style.panelBase.opacity(0.86), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.name)
                        .font(.system(size: 10.8, weight: .semibold))
                        .foregroundStyle(isSelected ? style.primaryText : style.secondaryText)
                        .lineLimit(1)

                    Text(detailText)
                        .font(.system(size: 9.2, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .background(isSelected ? style.controlStrongFill.opacity(0.72) : style.controlFill.opacity(0.38))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? style.emphasis.opacity(0.28) : style.stroke.opacity(0.16), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .help(state.name)
        .accessibilityLabel(state.name)
    }

    private var iconBackground: Color {
        isSelected ? style.emphasis.opacity(style.usesDarkChrome ? 0.18 : 0.12) : style.controlStrongFill.opacity(0.52)
    }

    private var detailText: String {
        if let remaining = state.primaryRemaining {
            return conductorTokenRecordsText("\(Int(remaining.rounded()))% · \(state.primaryLabel)", "\(Int(remaining.rounded()))% · \(state.primaryLabel)", languageIdentifier: languageIdentifier)
        }
        if state.tokenSnapshot != nil {
            return conductorTokenRecordsText("有记录", "Records", languageIdentifier: languageIdentifier)
        }
        if state.storage?.hasLocalData == true {
            return state.storageText
        }
        return state.statusText
    }

    private func symbol(for provider: UsageProvider) -> String {
        switch provider {
        case .codex, .openai, .azureopenai:
            "sparkles"
        case .claude:
            "asterisk"
        case .gemini, .vertexai:
            "diamond"
        case .grok, .groq:
            "bolt.horizontal"
        case .cursor, .jetbrains, .windsurf, .kiro:
            "cursorarrow.motionlines"
        case .bedrock:
            "cube"
        case .ollama:
            "server.rack"
        default:
            "hexagon"
        }
    }

    private func indicatorColor(_ indicator: ProviderStatusIndicator, error: String?) -> Color {
        if error != nil { return Color(nsColor: .systemOrange) }
        switch indicator {
        case .none:
            return Color(nsColor: .systemGreen)
        case .minor:
            return Color(nsColor: .systemYellow)
        case .major:
            return Color(nsColor: .systemOrange)
        case .critical:
            return Color(nsColor: .systemRed)
        case .maintenance, .unknown:
            return Color(nsColor: .systemGray)
        }
    }
}

private struct ConductorUsageWorkbenchMetricPair: View {
    let primary: String
    let secondary: String
    let style: ConductorUsagePanelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(primary)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()

            Text(secondary)
                .font(.system(size: 10.3, weight: .medium))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConductorUsageWorkbenchDataRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.tertiaryText)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9.4, weight: .medium))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 10.4, weight: .semibold))
                .foregroundStyle(style.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .padding(.vertical, 1)
    }
}

private struct ConductorUsageWorkbenchPathRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let value: String
    let path: String
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let copyPath: () -> Void
    let revealPath: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.tertiaryText)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 9.6, weight: .semibold))
                        .foregroundStyle(style.tertiaryText)
                        .lineLimit(1)
                }

                Text(subtitle.isEmpty ? path : subtitle)
                    .font(.system(size: 9.2, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                iconButton("doc.on.doc", conductorTokenRecordsText("复制路径", "Copy Path", languageIdentifier: languageIdentifier), action: copyPath)
                iconButton("arrow.up.forward.square", conductorTokenRecordsText("在 Finder 中显示", "Reveal in Finder", languageIdentifier: languageIdentifier), action: revealPath)
            }
        }
        .padding(.vertical, 1)
    }

    private func iconButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(help, systemImage: systemName)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ConductorUsageWorkbenchTinyPill: View {
    let text: String
    let systemImage: String
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 8.8, weight: .bold))
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 9.4, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(style.secondaryText)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(style.controlStrongFill.opacity(0.54))
        .clipShape(Capsule())
    }
}

private struct ConductorUsageWorkbenchDotLabel: View {
    let text: String
    let indicator: ProviderStatusIndicator
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9.2, weight: .semibold))
                .foregroundStyle(style.tertiaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: 21)
        .background(style.controlStrongFill.opacity(0.44))
        .clipShape(Capsule())
    }

    private var color: Color {
        switch indicator {
        case .none:
            Color(nsColor: .systemGreen)
        case .minor:
            Color(nsColor: .systemYellow)
        case .major:
            Color(nsColor: .systemOrange)
        case .critical:
            Color(nsColor: .systemRed)
        case .maintenance, .unknown:
            Color(nsColor: .systemGray)
        }
    }
}

private struct ConductorUsageWorkbenchStatusCapsule: View {
    let text: String
    let indicator: ProviderStatusIndicator
    let style: ConductorUsagePanelStyle

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10.2, weight: .semibold))
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(style.controlStrongFill.opacity(0.62))
        .clipShape(Capsule())
    }

    private var color: Color {
        switch indicator {
        case .none:
            Color(nsColor: .systemGreen)
        case .minor:
            Color(nsColor: .systemYellow)
        case .major:
            Color(nsColor: .systemOrange)
        case .critical:
            Color(nsColor: .systemRed)
        case .maintenance, .unknown:
            Color(nsColor: .systemGray)
        }
    }
}

private struct ConductorUsageWorkbenchActionButton: View {
    let title: String
    let systemImage: String
    let style: ConductorUsagePanelStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ConductorUsageWorkbenchSparkline: View {
    let values: [Double]
    let tint: Color
    let muted: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(muted.opacity(0.11))

                if values.count > 1 {
                    sparklinePath(in: proxy.size)
                        .stroke(
                            tint.opacity(0.90),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                    sparklinePath(in: proxy.size)
                        .stroke(
                            tint.opacity(0.18),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        .blur(radius: 5)
                } else {
                    Capsule()
                        .fill(muted.opacity(0.22))
                        .frame(height: 4)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private func sparklinePath(in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }

        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 1)
        let step = size.width / CGFloat(max(values.count - 1, 1))

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let ratio = (value - minValue) / range
            let y = size.height - CGFloat(ratio) * max(size.height - 8, 1) - 4
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct ConductorUsageWorkbenchBars: View {
    let values: [Double]
    let tint: Color
    let muted: Color

    var body: some View {
        let maxValue = max(values.max() ?? 0, 1)

        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(value > 0 ? tint.opacity(0.70) : muted.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, CGFloat(value / maxValue) * 42))
            }

            if values.isEmpty {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(muted.opacity(0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

private extension String {
    var workbenchNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
