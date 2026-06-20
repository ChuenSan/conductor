import AppKit
import ConductorCore
import SwiftUI

/// 底部状态栏（自绘，跟主题）：当前 pane 的 cwd 全路径 + git 分支 + 实时时间。
struct StatusBarView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 12) {
            // 悬停链接时左侧切换成 URL 显示（浏览器式），移开还原 cwd/分支
            if let link = coordinator.hoveredLink {
                item("link", link, accent: true)
                    .transition(.opacity)
            } else {
                if let cwd = coordinator.activeCwd {
                    StatusCopyItem(icon: "folder", text: prettyPath(cwd),
                                   help: L("点击复制路径")) {
                        coordinator.copyToClipboard(cwd)
                        ToastHUD.shared.show(L("已复制路径"), icon: "doc.on.doc.fill",
                                             over: coordinator.window)
                    }
                }
                if let branch = coordinator.activeBranch {
                    StatusCopyItem(icon: "arrow.triangle.branch", text: branch, accent: true,
                                   help: L("点击复制分支名")) {
                        coordinator.copyToClipboard(branch)
                        ToastHUD.shared.show(L("已复制分支名"), icon: "doc.on.doc.fill",
                                             over: coordinator.window)
                    }
                }
            }
            Spacer(minLength: 8)
            // 右下角用量指示已移除（用户：功能不需要）。用量仍可在「渠道/用量」面板查看。
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(ctx.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 21)
        .frame(maxWidth: .infinity)
        .background(.clear)   // 透明：用根底统一磨砂
    }

    private func item(_ icon: String, _ text: String, accent: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(accent ? AppStyle.accent : AppStyle.textTertiary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .animation(.easeOut(duration: 0.12), value: text)
    }

    private func prettyPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// 状态栏的账号渠道聚合：不主动请求账号，仅展示已知/已手动刷新的 provider 摘要。
private struct ProviderUsageOverviewChip: View {
    let overview: StatusProviderUsageOverview
    let isPreparing: Bool
    let usageBarsShowUsed: Bool
    let onOpen: () -> Void
    let onRefresh: () -> Void

    private var signal: StatusProviderUsageSignal? { overview.headline }
    private var isLoading: Bool { isPreparing || overview.loadingCount > 0 }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 5) {
                leadingIcon
                Text(title)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(minWidth: 92, alignment: .leading)
            .frame(height: 17)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .contextMenu {
            Button(L("刷新已配置渠道")) { onRefresh() }
            Button(L("打开用量管理")) { onOpen() }
        }
        .accessibilityLabel(L("账号用量"))
        .accessibilityValue(title)
        .animation(Motion.hover, value: title)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if isLoading {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.accent)
        } else if overview.errorCount > 0, signal == nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.errorRed)
        } else if let signal {
            if let logo = CLIToolLogo.image(named: signal.logoName) {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: signal.fallbackSystemImage)
                    .font(.system(size: 9.5, weight: .bold))
            }
        } else {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppStyle.accent)
        }
    }

    private var title: String {
        if isLoading {
            return overview.loadingCount > 1 ? L("%ld 个刷新中", overview.loadingCount) : L("刷新中")
        }
        if overview.errorCount > 0, signal == nil {
            return L("%ld 个异常", overview.errorCount)
        }
        if let signal {
            if usageBarsShowUsed {
                return L("%1$@ 已用 %2$ld%%", signal.providerName, Int(signal.usedPercent.rounded()))
            }
            return L("%1$@ 剩 %2$ld%%", signal.providerName, Int(signal.remainingPercent.rounded()))
        }
        return L("%ld 个渠道", overview.configuredCount)
    }

    private var tint: Color {
        if isLoading { return AppStyle.accent }
        if overview.errorCount > 0, signal == nil { return AppStyle.errorRed }
        guard let signal else { return AppStyle.textSecondary }
        if signal.usedPercent >= 90 { return AppStyle.errorRed }
        if signal.usedPercent >= 70 { return AppStyle.waitAmber }
        return AppStyle.textSecondary
    }

    private var backgroundColor: Color {
        if isLoading { return AppStyle.accent.opacity(0.10) }
        if overview.errorCount > 0, signal == nil { return AppStyle.errorRed.opacity(0.12) }
        if let signal, signal.usedPercent >= 90 { return AppStyle.errorRed.opacity(0.12) }
        if let signal, signal.usedPercent >= 70 { return AppStyle.waitAmber.opacity(0.12) }
        return AppStyle.textTertiary.opacity(0.08)
    }

    private var tooltip: String {
        var lines = [L("账号用量")]
        if let signal {
            if usageBarsShowUsed {
                lines.append(L(
                    "%1$@ · %2$@ · 已用 %3$ld%% · 剩 %4$ld%%",
                    signal.providerName,
                    signal.windowTitle,
                    Int(signal.usedPercent.rounded()),
                    Int(signal.remainingPercent.rounded())))
            } else {
                lines.append(L(
                    "%1$@ · %2$@ · 剩 %3$ld%%",
                    signal.providerName,
                    signal.windowTitle,
                    Int(signal.remainingPercent.rounded())))
            }
            lines.append(L("最近更新 %@", UsageFormatting.agoText(signal.updatedAt)))
        }
        if overview.configuredCount > 0 {
            lines.append(L("%ld 个渠道", overview.configuredCount))
        }
        if overview.loadingCount > 0 {
            lines.append(L("%ld 个刷新中", overview.loadingCount))
        }
        if overview.errorCount > 0 {
            lines.append(L("%ld 个异常", overview.errorCount))
        }
        if let lastUpdatedAt = overview.lastUpdatedAt {
            lines.append(L("最近更新 %@", UsageFormatting.agoText(lastUpdatedAt)))
        }
        return lines.joined(separator: "\n")
    }
}

private struct ProviderUsageSwitcherPopover: View {
    @Environment(\.dismiss) private var dismiss
    let items: [StatusProviderSwitcherItem]
    let isPreparing: Bool
    let isScanningStorage: Bool
    let usageBarsShowUsed: Bool
    let onRefresh: () -> Void
    let onOpenUsage: () -> Void

    @State private var selectedID: String?
    @State private var frozenItems: [StatusProviderSwitcherItem] = []
    @State private var hasFrozenItems = false
    @FocusState private var keyboardFocused: Bool

    private var displayItems: [StatusProviderSwitcherItem] {
        guard hasFrozenItems else { return items }
        let liveItemsByProvider = items.reduce(into: [String: StatusProviderSwitcherItem]()) { result, item in
            result[item.providerID] = item
        }
        return frozenItems.map { frozenItem in
            liveItemsByProvider[frozenItem.providerID] ?? frozenItem
        }
    }

    private var selectedItem: StatusProviderSwitcherItem? {
        selectedItem(in: displayItems)
    }

    private func selectedItem(in list: [StatusProviderSwitcherItem]) -> StatusProviderSwitcherItem? {
        if let selectedID, let match = list.first(where: { $0.providerID == selectedID }) {
            return match
        }
        return list.first { $0.signal != nil || $0.errorMessage != nil || $0.isConfigured } ?? list.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if displayItems.isEmpty {
                emptyState
            } else {
                HStack(alignment: .top, spacing: 10) {
                    switcherList
                    if let selectedItem {
                        ProviderUsageSwitcherDetail(
                            item: selectedItem,
                            isScanningStorage: isScanningStorage,
                            usageBarsShowUsed: usageBarsShowUsed)
                    }
                }
                .frame(height: ProviderUsageSwitcherLayout.contentHeight, alignment: .top)
            }
        }
        .padding(12)
        .frame(width: ProviderUsageSwitcherLayout.popoverWidth)
        .background(AppStyle.windowBackground)
        .focusable()
        .focused($keyboardFocused)
        .onKeyPress(.downArrow) {
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onAppear {
            freezeItemsIfReady(items)
            normalizeSelection(using: displayItems)
            keyboardFocused = true
        }
        .onChange(of: items) { _, newItems in
            if !hasFrozenItems {
                freezeItemsIfReady(newItems)
                normalizeSelection(using: displayItems)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AppStyle.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(L("渠道切换"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text("\(displayItems.count)")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textTertiary)
            }
            Spacer(minLength: 0)
            Button(action: onRefresh) {
                Image(systemName: isPreparing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(L("刷新已配置渠道"))
            Button(action: onOpenUsage) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(L("打开用量管理"))
        }
    }

    private var switcherList: some View {
        ScrollView {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(displayItems) { item in
                        ProviderUsageSwitcherRow(
                            item: item,
                            isSelected: item.providerID == selectedItem?.providerID,
                            usageBarsShowUsed: usageBarsShowUsed,
                            onSelect: {
                                selectedID = item.providerID
                                keyboardFocused = true
                            })
                        .id(item.providerID)
                    }
                }
                .padding(.vertical, 1)
                .onChange(of: selectedID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(width: ProviderUsageSwitcherLayout.listWidth)
        .frame(height: ProviderUsageSwitcherLayout.contentHeight, alignment: .top)
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(L("暂无渠道"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppStyle.hoverFill.opacity(0.65)))
    }

    private func normalizeSelection(using list: [StatusProviderSwitcherItem]) {
        if let selectedID, list.contains(where: { $0.providerID == selectedID }) {
            return
        }
        selectedID = selectedItem(in: list)?.providerID
    }

    private func freezeItemsIfReady(_ candidateItems: [StatusProviderSwitcherItem]) {
        guard !hasFrozenItems, !candidateItems.isEmpty else { return }
        // Freeze order while the popover is open, but let matching provider rows keep receiving live updates.
        frozenItems = candidateItems
        hasFrozenItems = true
    }

    private func moveSelection(_ offset: Int) {
        guard !displayItems.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            displayItems.firstIndex { $0.providerID == id }
        } ?? -1
        let nextIndex: Int
        if currentIndex < 0 {
            nextIndex = offset >= 0 ? 0 : displayItems.count - 1
        } else {
            nextIndex = (currentIndex + offset + displayItems.count) % displayItems.count
        }
        selectedID = displayItems[nextIndex].providerID
    }
}

private enum ProviderUsageSwitcherLayout {
    static let popoverWidth: CGFloat = 456
    static let listWidth: CGFloat = 188
    static let detailWidth: CGFloat = 234
    static let contentHeight: CGFloat = 286
    static let detailBodyHeight: CGFloat = 232
    static let rowHeight: CGFloat = 42
}

private struct ProviderUsageSwitcherRow: View {
    let item: StatusProviderSwitcherItem
    let isSelected: Bool
    let usageBarsShowUsed: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ProviderUsageSwitcherLogo(item: item)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.providerName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(statusText)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(statusColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppStyle.accent)
                    }
                }
                quotaIndicator
            }
            .padding(.horizontal, 8)
            .frame(height: ProviderUsageSwitcherLayout.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? AppStyle.accent.opacity(0.12) : AppStyle.hoverFill.opacity(0.58)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? AppStyle.accent.opacity(0.24) : Color.clear, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.providerName)
        .accessibilityValue(statusText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var quotaIndicator: some View {
        if let signal = item.signal {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppStyle.textTertiary.opacity(0.18))
                    Capsule()
                        .fill(quotaIndicatorColor(signal))
                        .frame(width: max(2, proxy.size.width * remainingFraction(signal)))
                }
            }
            .frame(height: 3)
            .opacity(isSelected ? 0 : 1)
            .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(height: 3)
                .accessibilityHidden(true)
        }
    }

    private var statusText: String {
        if item.isLoading { return L("刷新中") }
        if item.errorMessage != nil { return L("异常") }
        if let signal = item.signal {
            if usageBarsShowUsed {
                return L("已用 %ld%%", Int(signal.usedPercent.rounded()))
            }
            return L("剩 %ld%%", Int(signal.remainingPercent.rounded()))
        }
        return item.isConfigured ? L("已配置") : L("未配置")
    }

    private var statusColor: Color {
        if item.isLoading { return AppStyle.accent }
        if item.errorMessage != nil { return AppStyle.errorRed }
        if let signal = item.signal {
            if signal.usedPercent >= 90 { return AppStyle.errorRed }
            if signal.usedPercent >= 70 { return AppStyle.waitAmber }
        }
        return AppStyle.textTertiary
    }

    private func remainingFraction(_ signal: StatusProviderUsageSignal) -> CGFloat {
        CGFloat(max(0, min(1, signal.remainingPercent / 100)))
    }

    private func quotaIndicatorColor(_ signal: StatusProviderUsageSignal) -> Color {
        if signal.usedPercent >= 90 { return AppStyle.errorRed }
        if signal.usedPercent >= 70 { return AppStyle.waitAmber }
        return AppStyle.accent
    }
}

private struct ProviderUsageSwitcherDetail: View {
    let item: StatusProviderSwitcherItem
    let isScanningStorage: Bool
    let usageBarsShowUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderUsageSwitcherLogo(item: item)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.providerName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(item.providerID)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                statusPill
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    detailBody
                    storageBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 1)
            }
            .scrollIndicators(.hidden)
            .frame(height: ProviderUsageSwitcherLayout.detailBodyHeight, alignment: .top)
        }
        .padding(10)
        .frame(width: ProviderUsageSwitcherLayout.detailWidth, alignment: .topLeading)
        .frame(height: ProviderUsageSwitcherLayout.contentHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppStyle.hoverFill.opacity(0.66)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppStyle.textTertiary.opacity(0.10), lineWidth: 1))
    }

    @ViewBuilder
    private var detailBody: some View {
        if item.isLoading {
            ProviderUsageSwitcherMessage(icon: "arrow.triangle.2.circlepath", text: L("刷新中"), color: AppStyle.accent)
        } else if let error = item.errorMessage {
            ProviderUsageSwitcherMessage(icon: "exclamationmark.triangle.fill", text: error, color: AppStyle.errorRed)
        } else if let signal = item.signal {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(signal.windowTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(percentText(used: signal.usedPercent, remaining: signal.remainingPercent))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(signalColor(signal))
                }
                ProgressView(value: progressValue(used: signal.usedPercent, remaining: signal.remainingPercent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(signalColor(signal))
                if let secondary = signal.secondaryMetric {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L("副指标"))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(AppStyle.textTertiary)
                            Spacer(minLength: 0)
                            Text("\(secondary.title) · \(percentText(used: secondary.usedPercent, remaining: secondary.remainingPercent))")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(metricColor(secondary))
                                .lineLimit(1)
                        }
                        ProgressView(value: progressValue(used: secondary.usedPercent, remaining: secondary.remainingPercent), total: 100)
                            .progressViewStyle(.linear)
                            .tint(metricColor(secondary))
                    }
                }
                Text(L("最近更新 %@", UsageFormatting.agoText(signal.updatedAt)))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
        } else if item.isConfigured {
            ProviderUsageSwitcherMessage(icon: "checkmark.circle.fill", text: L("已配置"), color: AppStyle.doneGreen)
        } else {
            ProviderUsageSwitcherMessage(icon: "key", text: L("未配置"), color: AppStyle.textTertiary)
        }
    }

    @ViewBuilder
    private var storageBody: some View {
        if let footprint = item.storageFootprint {
            Divider().opacity(0.45)
            StatusProviderStorageSummary(footprint: footprint)
        } else if isScanningStorage {
            Divider().opacity(0.45)
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(L("正在扫描 %@ 的本地存储…", item.providerName))
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statusPill: some View {
        Text(statusTitle)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(statusColor.opacity(0.13)))
    }

    private var statusTitle: String {
        if item.isLoading { return L("刷新中") }
        if item.errorMessage != nil { return L("异常") }
        if item.signal != nil { return L("已取数") }
        return item.isConfigured ? L("已配置") : L("未配置")
    }

    private var statusColor: Color {
        if item.isLoading { return AppStyle.accent }
        if item.errorMessage != nil { return AppStyle.errorRed }
        if let signal = item.signal { return signalColor(signal) }
        return item.isConfigured ? AppStyle.doneGreen : AppStyle.textTertiary
    }

    private func signalColor(_ signal: StatusProviderUsageSignal) -> Color {
        if signal.usedPercent >= 90 { return AppStyle.errorRed }
        if signal.usedPercent >= 70 { return AppStyle.waitAmber }
        return AppStyle.doneGreen
    }

    private func metricColor(_ metric: StatusProviderUsageSignal.Metric) -> Color {
        if metric.usedPercent >= 90 { return AppStyle.errorRed }
        if metric.usedPercent >= 70 { return AppStyle.waitAmber }
        return AppStyle.doneGreen
    }

    private func percentText(used: Double, remaining: Double) -> String {
        if usageBarsShowUsed {
            return L("已用 %ld%%", Int(used.rounded()))
        }
        return L("剩 %ld%%", Int(remaining.rounded()))
    }

    private func progressValue(used: Double, remaining: Double) -> Double {
        min(max(usageBarsShowUsed ? used : remaining, 0), 100)
    }
}

private struct StatusProviderStorageSummary: View {
    let footprint: ProviderStorageFootprint

    @State private var expanded = false

    private var visibleComponents: [ProviderStorageFootprint.Component] {
        Array(footprint.components.prefix(expanded ? 6 : 0))
    }

    private var cleanupRecommendations: [ProviderStorageRecommendation] {
        Array(footprint.cleanupRecommendations.prefix(expanded ? 6 : 3))
    }

    private var visibleRootPaths: [String] {
        Array(footprint.paths.prefix(3))
    }

    private var visibleMissingPaths: [String] {
        Array(footprint.missingPaths.prefix(2))
    }

    private var visibleUnreadablePaths: [String] {
        Array(footprint.unreadablePaths.prefix(3))
    }

    private var maxComponentBytes: Int64 {
        max(visibleComponents.map(\.totalBytes).max() ?? 0, 1)
    }

    private var subtitle: String {
        var parts = [L("%ld 个路径", footprint.paths.count)]
        if !footprint.components.isEmpty {
            parts.append(L("%ld 项明细", footprint.components.count))
        }
        if !footprint.unreadablePaths.isEmpty {
            parts.append(L("%ld 个不可读", footprint.unreadablePaths.count))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(Motion.hover) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 9.8, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .frame(width: 14)
                    Text(L("本地存储"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                    Spacer(minLength: 0)
                    Text(footprint.hasLocalData ? footprint.byteCountText : L("未发现本地数据"))
                        .font(.system(size: 10.2, weight: .bold, design: .monospaced))
                        .foregroundStyle(footprint.hasLocalData ? AppStyle.textPrimary : AppStyle.textTertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.2, weight: .bold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .frame(width: 10)
                }
            }
            .buttonStyle(.plain)
            .help(expanded ? L("收起本地存储详情") : L("展开本地存储详情"))
            .accessibilityLabel(L("本地存储"))
            .accessibilityValue(expanded ? L("已展开") : L("已收起"))

            Text(subtitle)
                .font(.system(size: 9.4, weight: .medium, design: .rounded))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)

            if expanded {
                expandedDetails
            }

            if !cleanupRecommendations.isEmpty {
                storageSection(L("清理建议")) {
                    ForEach(cleanupRecommendations) { recommendation in
                        StatusProviderStorageRecommendationRow(recommendation: recommendation)
                    }
                    if footprint.cleanupRecommendations.count > cleanupRecommendations.count {
                        StatusProviderStorageMoreText(
                            text: L(
                                "还有 %ld 条建议",
                                footprint.cleanupRecommendations.count - cleanupRecommendations.count))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("本地存储"))
    }

    @ViewBuilder
    private var expandedDetails: some View {
        if !visibleComponents.isEmpty {
            storageSection(L("占用明细")) {
                ForEach(visibleComponents) { component in
                    StatusProviderStorageComponentRow(component: component, maxBytes: maxComponentBytes)
                }
                if footprint.components.count > visibleComponents.count {
                    StatusProviderStorageMoreText(
                        text: L(
                            "还有 %ld 项明细",
                            footprint.components.count - visibleComponents.count))
                }
            }
        } else if !footprint.hasLocalData {
            Text(L("没有发现可统计的本地数据"))
                .font(.system(size: 9.6, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(2)
        }

        if !visibleRootPaths.isEmpty {
            storageSection(L("扫描路径")) {
                ForEach(visibleRootPaths, id: \.self) { path in
                    StatusProviderStoragePathRow(
                        path: path,
                        systemImage: "folder",
                        tint: AppStyle.textTertiary)
                }
                if footprint.paths.count > visibleRootPaths.count {
                    StatusProviderStorageMoreText(
                        text: L(
                            "还有 %ld 个路径",
                            footprint.paths.count - visibleRootPaths.count))
                }
            }
        }

        if !visibleMissingPaths.isEmpty {
            storageSection(L("缺失路径")) {
                ForEach(visibleMissingPaths, id: \.self) { path in
                    StatusProviderStoragePathRow(
                        path: path,
                        systemImage: "questionmark.folder",
                        tint: AppStyle.textTertiary)
                }
                if footprint.missingPaths.count > visibleMissingPaths.count {
                    StatusProviderStorageMoreText(
                        text: L(
                            "还有 %ld 个路径",
                            footprint.missingPaths.count - visibleMissingPaths.count))
                }
            }
        }

        if !visibleUnreadablePaths.isEmpty {
            storageSection(L("不可读路径")) {
                ForEach(visibleUnreadablePaths, id: \.self) { path in
                    StatusProviderStoragePathRow(
                        path: path,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: AppStyle.waitAmber)
                }
                if footprint.unreadablePaths.count > visibleUnreadablePaths.count {
                    StatusProviderStorageMoreText(
                        text: L(
                            "还有 %ld 个路径",
                            footprint.unreadablePaths.count - visibleUnreadablePaths.count))
                }
            }
        }
    }

    private func storageSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9.8, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            content()
        }
    }
}

private struct StatusProviderStorageRecommendationRow: View {
    let recommendation: ProviderStorageRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L(recommendation.title))
                    .font(.system(size: 9.6, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(ByteCountFormatter.string(fromByteCount: recommendation.bytes, countStyle: .file))
                    .font(.system(size: 9.4, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            HStack(spacing: 4) {
                Text(recommendation.path)
                    .font(.system(size: 8.6, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(recommendation.path)
                Spacer(minLength: 0)
                StatusStoragePathCopyButton(path: recommendation.path)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppStyle.theme.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L(recommendation.title)), \(ByteCountFormatter.string(fromByteCount: recommendation.bytes, countStyle: .file))")
    }
}

private struct StatusProviderStorageComponentRow: View {
    let component: ProviderStorageFootprint.Component
    let maxBytes: Int64

    private var fraction: CGFloat {
        guard maxBytes > 0 else { return 0 }
        return CGFloat(max(0, min(1, Double(component.totalBytes) / Double(maxBytes))))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(component.name)
                    .font(.system(size: 9.6, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(ByteCountFormatter.string(fromByteCount: component.totalBytes, countStyle: .file))
                    .font(.system(size: 9.4, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppStyle.textTertiary.opacity(0.18))
                    Capsule()
                        .fill(AppStyle.accent.opacity(0.78))
                        .frame(width: max(2, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
            HStack(spacing: 4) {
                Text(component.path)
                    .font(.system(size: 8.6, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(component.path)
                Spacer(minLength: 0)
                StatusStoragePathCopyButton(path: component.path)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppStyle.theme.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.name), \(ByteCountFormatter.string(fromByteCount: component.totalBytes, countStyle: .file))")
    }
}

private struct StatusProviderStoragePathRow: View {
    let path: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 12)
            Text(path)
                .font(.system(size: 8.6, weight: .medium, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(path)
            Spacer(minLength: 0)
            StatusStoragePathCopyButton(path: path)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppStyle.theme.isDark ? Color.white.opacity(0.028) : Color.black.opacity(0.02)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(path)
    }
}

private struct StatusProviderStorageMoreText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(AppStyle.textTertiary)
            .lineLimit(1)
    }
}

private struct StatusStoragePathCopyButton: View {
    let path: String

    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            resetTask?.cancel()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(path, forType: .string)
            didCopy = true
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 8.8, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 17, height: 17)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? L("已复制") : L("复制路径"))
        .accessibilityLabel(didCopy ? L("已复制") : L("复制路径"))
    }
}

private struct ProviderUsageSwitcherMessage: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(4)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(text)
    }
}

private struct ProviderUsageSwitcherLogo: View {
    let item: StatusProviderSwitcherItem

    var body: some View {
        Group {
            if let logo = CLIToolLogo.image(named: item.logoName) {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: item.fallbackSystemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
            }
        }
    }
}

/// 任意 provider 的配额告警状态栏标记。Codex 有专属用量 chip，其他 provider 用这个短时 marker。
private struct QuotaWarningFlashChip: View {
    let flash: UsageQuotaWarningFlash
    let hidePersonalInfo: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(AppStyle.errorRed)
                Text(flash.providerName)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppStyle.errorRed)
                    .lineLimit(1)
                Text(L("剩 %ld%%", Int(flash.remainingPercent.rounded())))
                    .font(.system(size: 10.3, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(height: 17)
            .background(
                Capsule()
                    .fill(AppStyle.errorRed.opacity(0.13))
                    .overlay(Capsule().strokeBorder(AppStyle.errorRed.opacity(0.22), lineWidth: 1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
        .animation(Motion.hover, value: flash)
    }

    private var tooltip: String {
        var lines = [
            L("用量告警：%@", flash.providerName),
            L(
                "%1$@ · %2$@ 剩余 %3$ld%%，已低于 %4$ld%% 阈值。",
                flash.providerName,
                flash.windowTitle,
                Int(flash.remainingPercent.rounded()),
                flash.threshold)
        ]
        if let account = flash.accountLabel {
            lines.append(UsagePersonalInfoRedactor.redactEmails(
                in: account,
                isEnabled: hidePersonalInfo) ?? account)
        }
        return lines.joined(separator: "\n")
    }
}

/// 可点击复制的状态栏条目（cwd / git 分支）：hover 提亮 + 浮现复制小图标，点击进剪贴板。
private struct StatusCopyItem: View {
    let icon: String
    let text: String
    var accent = false
    let help: String
    let onCopy: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onCopy) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(accent ? AppStyle.accent : AppStyle.textTertiary)
                Text(text)
                    .font(.system(size: 10.5))
                    .foregroundStyle(hovering ? AppStyle.textPrimary : AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hovering {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .animation(.easeOut(duration: 0.12), value: text)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 状态栏里的 Codex 配额小条：logo + 最紧张窗口的剩余百分比，点击打开 CLI 面板。
private struct CodexUsageChip: View {
    let snapshot: CodexUsageSnapshot?
    let warningFlash: UsageQuotaWarningFlash?
    let usageBarsShowUsed: Bool
    let resetTimesShowAbsolute: Bool
    let onTap: () -> Void

    /// 取剩余最少（最紧张）的窗口作为头条。
    private var headline: (label: String, window: CodexUsageSnapshot.Window)? {
        guard let snapshot else { return nil }
        let candidates: [(String, CodexUsageSnapshot.Window)] =
            [(L("会话"), snapshot.session), (L("本周"), snapshot.weekly)].compactMap { label, win in
                win.map { (label, $0) }
            }
        return candidates.min { $0.1.remainingPercent < $1.1.remainingPercent }
    }

    private func color(_ used: Int) -> Color {
        if isWarningActive { return AppStyle.errorRed }
        switch used {
        case ..<70:
            return AppStyle.textSecondary
        case 70..<90:
            return AppStyle.waitAmber
        default:
            return AppStyle.errorRed
        }
    }

    private var isWarningActive: Bool {
        guard let warningFlash else { return false }
        return warningFlash.until > Date()
    }

    private var resetCredits: CodexRateLimitResetCreditsSnapshot? {
        guard let credits = snapshot?.codexResetCredits, credits.availableCount > 0 else { return nil }
        return credits
    }

    var body: some View {
        if let headline {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    if let logo = CLIToolLogo.image(named: "codex") {
                        Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 13, height: 13)
                    }
                    if isWarningActive {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(AppStyle.errorRed)
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }
                    Text(headlineText(headline))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(color(headline.window.usedPercent))
                    if let resetCredits {
                        resetCreditBadge(resetCredits)
                    }
                }
                .padding(.horizontal, isWarningActive ? 6 : 0)
                .frame(height: 17)
                .background {
                    if isWarningActive {
                        Capsule()
                            .fill(AppStyle.errorRed.opacity(0.13))
                            .overlay(Capsule().strokeBorder(AppStyle.errorRed.opacity(0.22), lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(tooltip)
            .animation(Motion.hover, value: isWarningActive)
        } else if let resetCredits {
            Button(action: onTap) {
                HStack(spacing: 5) {
                    if let logo = CLIToolLogo.image(named: "codex") {
                        Image(nsImage: logo).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 13, height: 13)
                    }
                    resetCreditBadge(resetCredits)
                }
                .frame(height: 17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(CodexResetCreditsDisplay.tooltip(resetCredits, showAbsolute: resetTimesShowAbsolute))
        }
    }

    private func resetCreditBadge(_ resetCredits: CodexRateLimitResetCreditsSnapshot) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 8.5, weight: .semibold))
            Text("\(resetCredits.availableCount)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(AppStyle.accent)
        .accessibilityLabel(L("限额重置券"))
        .accessibilityValue(CodexResetCreditsDisplay.countText(resetCredits))
    }

    private var tooltip: String {
        guard let snapshot else { return "" }
        var lines: [String] = []
        if isWarningActive, let warningFlash {
            lines.append(L(
                "告警：%1$@ 剩 %2$ld%%，低于 %3$ld%% 阈值",
                warningFlash.windowTitle,
                Int(warningFlash.remainingPercent.rounded()),
                warningFlash.threshold))
        }
        if let s = snapshot.session {
            lines.append(windowTooltip(label: L("会话"), window: s))
        }
        if let w = snapshot.weekly {
            lines.append(windowTooltip(label: L("本周"), window: w))
        }
        if let resetCredits {
            lines.append(CodexResetCreditsDisplay.detailText(
                resetCredits,
                showAbsolute: resetTimesShowAbsolute))
        }
        return L("Codex 用量") + "\n" + lines.joined(separator: "\n")
    }

    private func headlineText(_ headline: (label: String, window: CodexUsageSnapshot.Window)) -> String {
        if usageBarsShowUsed {
            return L("%1$@ 已用 %2$ld%%", headline.label, headline.window.usedPercent)
        }
        return L("%1$@ 剩 %2$ld%%", headline.label, headline.window.remainingPercent)
    }

    private func windowTooltip(label: String, window: CodexUsageSnapshot.Window) -> String {
        if usageBarsShowUsed {
            return L("%1$@：已用 %2$ld%% · 剩 %3$ld%% · %4$@",
                     label,
                     window.usedPercent,
                     window.remainingPercent,
                     UsageFormatting.resetText(window.resetAt, showAbsolute: resetTimesShowAbsolute))
        }
        return L("%1$@：剩 %2$ld%% · %3$@",
                 label,
                 window.remainingPercent,
                 UsageFormatting.resetText(window.resetAt, showAbsolute: resetTimesShowAbsolute))
    }
}
