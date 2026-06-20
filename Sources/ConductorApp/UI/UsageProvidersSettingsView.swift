import AppKit
import ConductorCore
import SwiftUI
import UniformTypeIdentifiers

struct UsageProvidersSettingsView: View {
    let providers: [UsageProviderEntry]
    let tools: [CLIToolStatus]
    let states: [String: ToolUsageState]
    let storageFootprints: [String: ProviderStorageFootprint]
    let isScanningStorage: Bool
    @Binding var selectedID: String?
    let onApplyConfig: (AppConfig) -> Void
    let onReload: (UsageProviderEntry) -> Void

    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var warningCenter = UsageQuotaWarningCenter.shared
    @State private var query = ""
    @State private var draggingProviderID: String?

    private var selectedProvider: UsageProviderEntry? {
        guard let selectedID else { return nil }
        return providers.first { $0.id == selectedID }
    }

    private var providersSortedAlphabetically: Bool {
        configStore.config.usage.providersSortedAlphabetically
    }

    private var canReorderProviders: Bool {
        !providersSortedAlphabetically
    }

    private var listProviders: [UsageProviderEntry] {
        guard providersSortedAlphabetically else { return providers }
        return providers.sorted { lhs, rhs in
            let lhsEnabled = lhs.isEnabled(in: configStore.config)
            let rhsEnabled = rhs.isEnabled(in: configStore.config)
            if lhsEnabled != rhsEnabled { return lhsEnabled }
            switch lhs.name.localizedCaseInsensitiveCompare(rhs.name) {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return lhs.id < rhs.id
            }
        }
    }

    private var filteredProviders: [UsageProviderEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return listProviders }
        return listProviders.filter { provider in
            let profile = UsageProviderProfile.catalog(for: provider)
            return provider.name.lowercased().contains(trimmed)
                || provider.id.lowercased().contains(trimmed)
                || profile.category.lowercased().contains(trimmed)
                || profile.credentialKind.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        Group {
            if let provider = selectedProvider {
                ProviderSettingsDetailView(
                    provider: provider,
                    tool: tools.first { $0.id == provider.id },
                    state: states[provider.id],
                    storageFootprint: storageFootprints[provider.id],
                    isScanningStorage: isScanningStorage,
                    onBack: { withAnimation(Motion.panel) { selectedID = nil } },
                    onApplyConfig: onApplyConfig,
                    warningFlash: activeWarningFlash(for: provider.id),
                    onReload: { onReload(provider) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                providerList
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(Motion.panel, value: selectedID)
    }

    private var providerList: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            header
            searchAndSortControls
            ProviderStatusStrip(providers: providers, states: states)
            VStack(alignment: .leading, spacing: Space.xs) {
                if filteredProviders.isEmpty {
                    ProviderSettingsEmptyState(query: query)
                        .transition(.opacity)
                } else {
                    ForEach(filteredProviders) { provider in
                        ProviderSettingsListRow(
                            provider: provider,
                            tool: tools.first { $0.id == provider.id },
                            state: states[provider.id],
                            enabled: enabledBinding(for: provider),
                            warningFlash: activeWarningFlash(for: provider.id),
                            canReorder: canReorderProviders,
                            canMoveUp: canMoveProvider(provider, by: -1),
                            canMoveDown: canMoveProvider(provider, by: 1),
                            onOpen: { withAnimation(Motion.panel) { selectedID = provider.id } },
                            onReload: { onReload(provider) },
                            onDrag: {
                                draggingProviderID = provider.id
                                return NSItemProvider(object: provider.id as NSString)
                            },
                            onMoveTop: { moveProviderToTop(provider) },
                            onMoveUp: { moveProvider(provider, by: -1) },
                            onMoveDown: { moveProvider(provider, by: 1) })
                            .opacity(draggingProviderID == provider.id ? 0.55 : 1)
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: ProviderSettingsDropDelegate(
                                    itemID: provider.id,
                                    providerIDs: effectiveProviderOrder,
                                    draggingProviderID: $draggingProviderID,
                                    moveProviders: moveProviders(fromOffsets:toOffset:)))
                    }
                }
            }
            .animation(Motion.panel, value: filteredProviders.map(\.id))
            // 全局配额告警是配置项，沉到列表末尾、单独分隔，不再插在列表顶部 chrome 里。
            GlobalQuotaWarningSettingsCard(onApplyConfig: onApplyConfig)
                .padding(.top, Space.sm)
        }
        .onChange(of: providersSortedAlphabetically) { _, _ in
            draggingProviderID = nil
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppStyle.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("渠道配置"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(L("选择账号渠道，查看状态、来源和凭证。"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var searchAndSortControls: some View {
        HStack(spacing: 8) {
            searchField
            providerSortToggle
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            TextField(L("搜索渠道 / 来源 / 凭证"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppStyle.textPrimary)
            if !query.isEmpty {
                IconOnlyButton(
                    systemName: "xmark.circle.fill",
                    help: L("清空搜索"),
                    size: 20,
                    symbolSize: 10,
                    tint: AppStyle.textTertiary) {
                        withAnimation(Motion.snappy) { query = "" }
                    }
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(AppStyle.hoverFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("搜索渠道"))
    }

    private var providerSortToggle: some View {
        let isOn = providersSortedAlphabetically
        return Button {
            var config = configStore.config
            config.usage.providersSortedAlphabetically.toggle()
            draggingProviderID = nil
            withAnimation(Motion.snappy) {
                onApplyConfig(config)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(isOn ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isOn ? AppStyle.accent.opacity(0.16) : AppStyle.hoverFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(isOn ? AppStyle.accent.opacity(0.28) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(isOn
            ? L("已按字母排序（启用渠道优先）；点击切回自定义顺序")
            : L("按字母排序渠道（启用渠道优先）"))
        .accessibilityLabel(L("按字母排序渠道"))
        .accessibilityValue(isOn ? L("已启用") : L("已停用"))
    }

    private func enabledBinding(for provider: UsageProviderEntry) -> Binding<Bool> {
        Binding(
            get: { provider.isEnabled(in: configStore.config) },
            set: { enabled in
                var config = configStore.config
                var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
                providerConfig.enabled = enabled
                config.usage.providers[provider.id] = providerConfig
                onApplyConfig(config)
            })
    }

    private func activeWarningFlash(for providerID: String) -> UsageQuotaWarningFlash? {
        guard let flash = warningCenter.activeFlashes[providerID],
              flash.until > Date()
        else {
            return nil
        }
        return flash
    }

    private var effectiveProviderOrder: [String] {
        configStore.config.usage.effectiveProviderOrder(knownProviderIDs: providers.map(\.id))
    }

    private func canMoveProvider(_ provider: UsageProviderEntry, by offset: Int) -> Bool {
        guard canReorderProviders else { return false }
        let order = effectiveProviderOrder
        guard let index = order.firstIndex(of: provider.id) else { return false }
        return order.indices.contains(index + offset)
    }

    private func moveProvider(_ provider: UsageProviderEntry, by offset: Int) {
        guard canReorderProviders else { return }
        var order = effectiveProviderOrder
        guard let index = order.firstIndex(of: provider.id) else { return }
        let target = index + offset
        guard order.indices.contains(target) else { return }
        order.swapAt(index, target)
        applyProviderOrder(order)
    }

    private func moveProviderToTop(_ provider: UsageProviderEntry) {
        guard canReorderProviders else { return }
        var order = effectiveProviderOrder
        guard let index = order.firstIndex(of: provider.id), index > 0 else { return }
        let id = order.remove(at: index)
        order.insert(id, at: 0)
        applyProviderOrder(order)
    }

    private func moveProviders(fromOffsets: IndexSet, toOffset: Int) {
        guard canReorderProviders else { return }
        var order = effectiveProviderOrder
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        applyProviderOrder(order)
    }

    private func applyProviderOrder(_ order: [String]) {
        var config = configStore.config
        config.usage.providerOrder = UsageConfig.effectiveProviderOrder(
            raw: order,
            knownProviderIDs: providers.map(\.id))
        onApplyConfig(config)
    }
}

private struct ProviderSettingsEmptyState: View {
    let query: String

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppStyle.hoverFill.opacity(0.82)))
            Text(L("没有匹配的渠道"))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
            Text(emptyMessage)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.48)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppStyle.textTertiary.opacity(0.12), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var emptyMessage: String {
        if trimmedQuery.isEmpty {
            return L("当前没有可显示的渠道。")
        }
        return L("没有匹配「%@」的渠道。", trimmedQuery)
    }
}

private struct ProviderSettingsDropDelegate: DropDelegate {
    let itemID: String
    let providerIDs: [String]
    @Binding var draggingProviderID: String?
    let moveProviders: (IndexSet, Int) -> Void

    func dropEntered(info _: DropInfo) {
        guard let draggingProviderID, draggingProviderID != itemID else { return }
        guard let fromIndex = providerIDs.firstIndex(of: draggingProviderID),
              let toIndex = providerIDs.firstIndex(of: itemID)
        else { return }
        guard fromIndex != toIndex else { return }

        let adjustedIndex = toIndex > fromIndex ? toIndex + 1 : toIndex
        moveProviders(IndexSet(integer: fromIndex), adjustedIndex)
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        draggingProviderID = nil
        return true
    }
}

private struct ProviderStatusStrip: View {
    let providers: [UsageProviderEntry]
    let states: [String: ToolUsageState]
    @ObservedObject private var configStore = ConfigStore.shared

    private var enabledCount: Int {
        providers.filter { $0.isEnabled(in: configStore.config) }.count
    }

    private var readyCount: Int {
        providers.filter {
            if case .loaded = states[$0.id] { return true }
            return false
        }.count
    }

    private var errorCount: Int {
        providers.filter {
            if case .error = states[$0.id] { return true }
            return false
        }.count
    }

    private var setupCount: Int {
        providers.filter {
            if case .unconfigured = states[$0.id] { return true }
            return false
        }.count
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 86), spacing: 7, alignment: .leading)],
            alignment: .leading,
            spacing: 7
        ) {
            metric(L("启用"), "\(enabledCount)", icon: "power", color: AppStyle.accent)
            metric(L("已取数"), "\(readyCount)", icon: "chart.bar.fill", color: AppStyle.doneGreen)
            metric(L("待配置"), "\(setupCount)", icon: "key", color: AppStyle.waitAmber)
            if errorCount > 0 {
                metric(L("错误"), "\(errorCount)", icon: "exclamationmark.triangle.fill", color: AppStyle.errorRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, _ value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule()
                .fill(AppStyle.hoverFill.opacity(0.72)))
    }
}

private struct ProviderSettingsListRow: View {
    let provider: UsageProviderEntry
    let tool: CLIToolStatus?
    let state: ToolUsageState?
    @Binding var enabled: Bool
    let warningFlash: UsageQuotaWarningFlash?
    let canReorder: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onOpen: () -> Void
    let onReload: () -> Void
    let onDrag: () -> NSItemProvider
    let onMoveTop: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @ObservedObject private var configStore = ConfigStore.shared
    @State private var hovering = false

    private var profile: UsageProviderProfile { UsageProviderProfile.catalog(for: provider) }
    private var status: ProviderStatusPresentation { ProviderStatusPresentation(state: state, enabled: enabled) }
    private var hasWarning: Bool { warningFlash != nil }

    var body: some View {
        HStack(spacing: 8) {
            if canReorder {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(hovering ? AppStyle.textSecondary : AppStyle.textTertiary)
                    .frame(width: 14)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                    .help(L("拖拽排序"))
                    .accessibilityLabel(L("拖拽排序"))
                    .accessibilityHint(L("拖动此把手调整渠道顺序"))
                    .onDrag(onDrag)
            } else {
                Color.clear
                    .frame(width: 14)
                    .padding(.vertical, 7)
                    .accessibilityHidden(true)
            }
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    ProviderBrandIcon(provider: provider)
                        .frame(width: 22, height: 22)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(status.color.opacity(status.isStrong ? 0.17 : 0.10)))
                        .overlay(alignment: .topTrailing) {
                            ProviderQuotaWarningMarker(flash: warningFlash, compact: true)
                                .offset(x: 2, y: -2)
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(provider.name)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(AppStyle.textPrimary)
                                .lineLimit(1)
                            ProviderStatusPill(label: status.label, color: status.color)
                            if let warningFlash {
                                ProviderQuotaWarningPill(flash: warningFlash)
                            }
                        }
                        Text(rowSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(hasWarning ? AppStyle.errorRed : AppStyle.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    ProviderMiniUsage(state: state)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ThemedToggle(isOn: $enabled)
                .scaleEffect(0.78)
                .frame(width: 34)
                .help(enabled ? L("停用") : L("启用"))
                .accessibilityLabel(L("%@ 启用状态", provider.name))
                .accessibilityValue(enabled ? L("已启用") : L("已停用"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? AppStyle.hoverFill : AppStyle.theme.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(hovering ? AppStyle.accent.opacity(0.18) : Color.clear, lineWidth: 1))
        .onHover { inside in
            withAnimation(Motion.hover) { hovering = inside }
        }
        .contextMenu {
            Button(L("打开详情")) { onOpen() }
            Button(L("刷新用量")) { onReload() }
            Divider()
            Button(L("移到顶部")) { onMoveTop() }
                .disabled(!canReorder || !canMoveUp)
            Button(L("上移")) { onMoveUp() }
                .disabled(!canReorder || !canMoveUp)
            Button(L("下移")) { onMoveDown() }
                .disabled(!canReorder || !canMoveDown)
            Divider()
            Button(L("复制渠道 ID")) { copy(provider.id) }
            if let path = tool?.path {
                Button(L("复制路径")) { copy(path) }
                Button(L("在 Finder 中显示")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Divider()
            Button(enabled ? L("停用渠道") : L("启用渠道")) {
                enabled.toggle()
            }
        }
    }

    private var rowSubtitle: String {
        let kind = profile.credentialKind
        switch state {
        case let .loaded(snapshot):
            if let account = snapshot.accountLabel, !account.isEmpty { return displayAccount(account) }
            if let plan = snapshot.planName, !plan.isEmpty { return "\(kind) · \(plan)" }
            return "\(profile.category) · \(kind)"
        case let .error(message):
            return message
        case .loading:
            return L("刷新中")
        case .manual:
            return L("已配置，等待手动刷新")
        case .unconfigured:
            return profile.setupHint
        case .unsupported:
            return L("暂不支持用量")
        case .none:
            return profile.subtitle
        }
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func displayAccount(_ account: String) -> String {
        UsagePersonalInfoRedactor.redactEmails(
            in: account,
            isEnabled: configStore.config.usage.hidePersonalInfo) ?? account
    }
}

private struct ProviderQuotaWarningMarker: View {
    let flash: UsageQuotaWarningFlash?
    var compact = false
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        if let flash {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: compact ? 8.5 : 10, weight: .bold))
                .foregroundStyle(AppStyle.errorRed)
                .frame(width: compact ? 14 : 17, height: compact ? 14 : 17)
                .background(Circle().fill(AppStyle.windowBackground))
                .overlay(Circle().strokeBorder(AppStyle.errorRed.opacity(0.38), lineWidth: 1))
                .help(ProviderQuotaWarningText.tooltip(
                    flash,
                    hidePersonalInfo: configStore.config.usage.hidePersonalInfo))
                .transition(.opacity.combined(with: .scale(scale: 0.88)))
        }
    }
}

private struct ProviderQuotaWarningPill: View {
    let flash: UsageQuotaWarningFlash
    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        ToolBadge(
            text: L("告警"),
            icon: "bell.badge.fill",
            color: AppStyle.errorRed,
            height: 18)
            .help(ProviderQuotaWarningText.tooltip(
                flash,
                hidePersonalInfo: configStore.config.usage.hidePersonalInfo))
    }
}

private enum ProviderQuotaWarningText {
    static func tooltip(_ flash: UsageQuotaWarningFlash, hidePersonalInfo: Bool) -> String {
        let message = L(
            "%1$@ · %2$@ 剩余 %3$ld%%，已低于 %4$ld%% 阈值。",
            flash.providerName,
            flash.windowTitle,
            Int(flash.remainingPercent.rounded()),
            flash.threshold)
        guard let account = flash.accountLabel else { return message }
        let redacted = UsagePersonalInfoRedactor.redactEmails(
            in: account,
            isEnabled: hidePersonalInfo) ?? account
        return message + "\n" + redacted
    }
}

private struct ProviderStatusPill: View {
    let label: String
    let color: Color

    var body: some View {
        ToolBadge(text: label, color: color, height: 18)
    }
}

private struct ProviderMetaChip: View {
    let icon: String
    let text: String
    var monospaced = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
            Text(text)
                .font(.system(size: 9.5, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Capsule().fill(AppStyle.hoverFill.opacity(0.82)))
    }
}

private struct ProviderSettingsDetailView: View {
    let provider: UsageProviderEntry
    let tool: CLIToolStatus?
    let state: ToolUsageState?
    let storageFootprint: ProviderStorageFootprint?
    let isScanningStorage: Bool
    let onBack: () -> Void
    let onApplyConfig: (AppConfig) -> Void
    let warningFlash: UsageQuotaWarningFlash?
    let onReload: () -> Void

    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var history = UsageHistoryStore.shared
    @State private var serviceStatus: UsageProviderStatusSnapshot?
    @State private var isRefreshingServiceStatus = false
    @State private var isAddingTokenAccount = false
    @State private var newTokenAccountLabel = ""
    @State private var newTokenAccountToken = ""
    @State private var newTokenAccountOrganizationID = ""
    @State private var tokenAccountConfigStatus: ProviderTokenAccountConfigStatus?
    @State private var isRunningTokenAccountPrimaryAction = false
    @State private var openAIWebDebugLog = ""
    @State private var openAIWebDebugStatus: String?
    @State private var openAIWebArtifactPaths: [String] = []
    @State private var codexAccountRemovalCandidate: UsageProviderTokenAccount?
    @State private var codexManagedAccountAuthenticatingID: UUID?
    @State private var codexAccountPromotionCandidate: UsageProviderTokenAccount?
    @State private var codexManagedAccountPromotingID: UUID?

    private var profile: UsageProviderProfile { UsageProviderProfile.catalog(for: provider) }
    private var status: ProviderStatusPresentation {
        ProviderStatusPresentation(state: state, enabled: enabled.wrappedValue)
    }
    private var providerConfig: UsageProviderConfig {
        configStore.config.usage.providers[provider.id] ?? UsageProviderConfig()
    }
    private var tokenAccountSupport: UsageProviderTokenAccountSupport? {
        UsageProviderConfigCapabilities.tokenAccountSupportByProviderID[provider.id]
    }
    private var tokenAccountData: UsageProviderTokenAccountData {
        providerConfig.tokenAccounts ?? UsageProviderTokenAccountData()
    }
    private var tokenAccounts: [UsageProviderTokenAccount] {
        tokenAccountData.accounts
    }
    private var activeTokenAccountIndex: Int {
        tokenAccountData.clampedActiveIndex()
    }
    private var activeTokenAccount: UsageProviderTokenAccount? {
        let accounts = tokenAccounts
        guard !accounts.isEmpty else { return nil }
        return accounts[activeTokenAccountIndex]
    }
    private var codexDiscoveredTokenAccounts: [UsageProviderTokenAccount] {
        provider.id == "codex"
            ? CodexManagedAccountDiscovery.tokenAccounts(env: UsageCredentials.providerDiscoveryEnvironment())
            : []
    }
    private var codexDiscoveredAccountItems: [CodexDiscoveredAccountItem] {
        let authenticatingID = codexManagedAccountAuthenticatingID
        let promotingID = codexManagedAccountPromotingID
        let hasManagedOperation = authenticatingID != nil || promotingID != nil
        return codexDiscoveredTokenAccounts.map { account in
            let isManaged = isManagedCodexDiscoveredAccount(account)
            return CodexDiscoveredAccountItem(
                account: account,
                isConfigured: tokenAccounts.contains { tokenAccountsRepresentSameAccount($0, account) },
                isActive: activeTokenAccount.map { tokenAccountsRepresentSameAccount($0, account) } ?? false,
                isAuthenticating: authenticatingID == account.id,
                isPromoting: promotingID == account.id,
                canReauthenticate: isManaged && (!hasManagedOperation || authenticatingID == account.id),
                canPromote: isManaged && (!hasManagedOperation || promotingID == account.id),
                canRemove: isManaged && !hasManagedOperation)
        }
    }
    private var hasTokenAccountSurface: Bool {
        tokenAccountSupport != nil || !tokenAccounts.isEmpty || !codexDiscoveredTokenAccounts.isEmpty
    }
    private var repairActions: [UsageProviderRepairAction] {
        switch state {
        case .unconfigured:
            return UsageProviderRepairActions.actions(
                providerID: provider.id,
                providerName: provider.name,
                configured: false,
                errorMessage: nil,
                source: sourceMode,
                hasStatusPage: provider.statusURL != nil,
                statusURL: provider.statusURL)
        case let .error(message):
            return UsageProviderRepairActions.actions(
                providerID: provider.id,
                providerName: provider.name,
                configured: true,
                errorMessage: message,
                source: sourceMode,
                hasStatusPage: provider.statusURL != nil,
                statusURL: provider.statusURL)
        default:
            return []
        }
    }
    private var visibleRepairActions: [UsageProviderRepairAction] {
        let actions = repairActions
        guard actions.count > 1 else { return actions }
        return actions.filter { $0.kind != .retry }
    }
    private var enabled: Binding<Bool> {
        Binding(
            get: { provider.isEnabled(in: configStore.config) },
            set: { enabled in
                writeConfig { $0.enabled = enabled }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            compactDetailPanel
        }
        .task(id: provider.id) {
            await refreshServiceStatus()
        }
        .task(id: provider.id) {
            await pollProviderWebDebugLog()
        }
        .onChange(of: provider.id) {
            resetNewTokenAccountForm()
            codexAccountRemovalCandidate = nil
            codexAccountPromotionCandidate = nil
            refreshProviderWebDebugSnapshot()
        }
        .confirmationDialog(
            L("设为本机 Codex 账号？"),
            isPresented: codexAccountPromotionConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L("设为本机"), role: .destructive) {
                if let account = codexAccountPromotionCandidate {
                    promoteCodexDiscoveredAccount(account)
                }
                codexAccountPromotionCandidate = nil
            }
            Button(L("取消"), role: .cancel) {
                codexAccountPromotionCandidate = nil
            }
        } message: {
            Text(codexAccountPromotionMessage)
        }
        .confirmationDialog(
            L("移除 Codex 托管账号？"),
            isPresented: codexAccountRemovalConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button(L("移除托管账号"), role: .destructive) {
                if let account = codexAccountRemovalCandidate {
                    removeCodexDiscoveredAccount(account)
                }
                codexAccountRemovalCandidate = nil
            }
            Button(L("取消"), role: .cancel) {
                codexAccountRemovalCandidate = nil
            }
        } message: {
            Text(codexAccountRemovalMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconOnlyButton(
                    systemName: "chevron.left",
                    help: L("返回渠道列表"),
                    size: 28,
                    symbolSize: 11,
                    tint: AppStyle.textSecondary,
                    action: onBack)
                Spacer()
                IconOnlyButton(
                    systemName: "arrow.clockwise",
                    help: L("刷新用量"),
                    size: 28,
                    symbolSize: 11,
                    tint: AppStyle.textSecondary,
                    action: onReload)
                ThemedToggle(isOn: enabled)
                    .scaleEffect(0.86)
                    .frame(width: 38)
                    .help(enabled.wrappedValue ? L("停用渠道") : L("启用渠道"))
            }

            HStack(alignment: .center, spacing: 12) {
                ProviderBrandIcon(provider: provider)
                    .frame(width: 31, height: 31)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppStyle.accent.opacity(0.12)))
                    .overlay(alignment: .bottomTrailing) {
                        serviceStatusOverlay
                    }
                    .overlay(alignment: .topTrailing) {
                        ProviderQuotaWarningMarker(flash: warningFlash)
                            .offset(x: 3, y: -3)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(provider.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        statusPill
                        if let warningFlash {
                            ProviderQuotaWarningPill(flash: warningFlash)
                        }
                    }
                    Text(profile.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    detailMetaChips
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var detailMetaChips: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ProviderMetaChip(icon: "point.3.connected.trianglepath.dotted", text: sourceLabel)
                ProviderMetaChip(icon: "key", text: profile.credentialKind)
            }
            HStack(spacing: 5) {
                ProviderMetaChip(icon: "terminal", text: tool?.version ?? L("CLI 未检测到"), monospaced: tool?.version != nil)
                ProviderMetaChip(icon: "clock", text: updatedLabel)
            }
        }
        .padding(.top, 4)
    }

    private var statusPill: some View {
        let status = ProviderStatusPresentation(state: state, enabled: enabled.wrappedValue)
        return ProviderStatusPill(label: status.label, color: status.color)
    }

    @ViewBuilder
    private var serviceStatusOverlay: some View {
        if let serviceStatus,
           serviceStatus.indicator.hasIssue,
           serviceStatus.source != "link",
           serviceStatus.source != "none"
        {
            Circle()
                .fill(serviceStatusColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(AppStyle.windowBackground, lineWidth: 1.6))
                .offset(x: 2, y: 2)
                .help(serviceStatusLabel)
        }
    }

    private var compactDetailPanel: some View {
        VStack(spacing: 0) {
            // 用量：打开渠道最想看的，放最前。
            ProviderDetailSubsection(title: L("用量"), icon: "chart.bar.xaxis", collapsible: true) {
                usageSummary
            }

            // 未配置 / 出错时的修复动作，紧跟用量。
            if shouldShowSetupHint {
                ProviderPanelDivider()
                ProviderDetailSubsection(title: L("处理"), icon: "exclamationmark.triangle", collapsible: true) {
                    ProviderRepairActionsList(actions: visibleRepairActions, color: status.color)
                }
            }

            // 配置：Key / 来源 / 各种控件。
            ProviderPanelDivider()
            ProviderDetailSubsection(title: L("配置"), icon: "slider.horizontal.3", collapsible: true) {
                VStack(alignment: .leading, spacing: 12) {
                    ProviderKeyValueRow(label: L("说明"), value: profile.credentialHint)
                    configurationControls
                }
            }

            // 概览：只留 header 的 meta chips 没覆盖的几项（来源/凭证/更新/CLI版本 已在 header，不再重复）。
            ProviderPanelDivider()
            ProviderDetailSubsection(title: L("概览"), icon: "info.circle", collapsible: true, defaultExpanded: false) {
                VStack(spacing: 0) {
                    ProviderKeyValueRow(label: L("认证"), value: authLabel, valueColor: status.color)
                    if provider.statusURL != nil {
                        ProviderKeyValueRow(label: L("服务状态"), value: serviceStatusLabel, valueColor: serviceStatusColor)
                    }
                    if let account = loadedSnapshot?.accountLabel, !account.isEmpty {
                        ProviderKeyValueRow(
                            label: L("账号"),
                            value: UsagePersonalInfoRedactor.redactEmails(
                                in: account,
                                isEnabled: configStore.config.usage.hidePersonalInfo) ?? account)
                    }
                    if let plan = loadedSnapshot?.planName, !plan.isEmpty {
                        ProviderKeyValueRow(label: L("套餐"), value: plan)
                    }
                    ProviderKeyValueRow(label: L("渠道 ID"), value: provider.id, monospaced: true)
                    ProviderKeyValueRow(label: L("CLI 路径"), value: tool?.path ?? L("未检测到位置"), monospaced: tool?.path != nil)
                }
            }

            ProviderPanelDivider()
            ProviderDetailSubsection(title: L("配额告警"), icon: "bell.badge", collapsible: true, defaultExpanded: false) {
                ProviderQuotaWarningSettings(providerID: provider.id, onApplyConfig: onApplyConfig)
            }

            if configStore.config.usage.providerStorageFootprintsEnabled {
                ProviderPanelDivider()
                ProviderDetailSubsection(title: L("本地存储"), icon: "externaldrive", collapsible: true, defaultExpanded: false) {
                    ProviderStorageFootprintBlock(
                        footprint: storageFootprint,
                        providerName: provider.name,
                        isScanning: isScanningStorage)
                }
            }

            if hasProviderWebDebugPanel {
                ProviderPanelDivider()
                ProviderDetailSubsection(title: providerWebDebugTitle, icon: "globe", collapsible: true, defaultExpanded: false) {
                    openAIWebDebugPanel
                }
            }

            if !profile.toggles.isEmpty {
                ProviderPanelDivider()
                ProviderDetailSubsection(title: L("选项"), icon: "switch.2", collapsible: true, defaultExpanded: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(profile.toggles) { toggle in
                            ProviderToggleRow(
                                toggle: toggle,
                                isOn: toggle.key == "budgetExtras" && provider.id == "copilot"
                                    ? copilotBudgetExtrasBinding
                                    : toggle.key == "requireProviderEndpointOverrides" && ["minimax", "qwen"].contains(provider.id)
                                    ? extraFlagBinding(toggle.key, defaultValue: toggle.defaultValue)
                                    : flagBinding(toggle.key, defaultValue: toggle.defaultValue))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolsCard(cornerRadius: 10)
    }

    @ViewBuilder
    private var usageSummary: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("正在刷新用量…"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .manual:
            ProviderInlineNotice(
                icon: "hand.tap",
                text: L("不会自动请求账号；点击右上角刷新获取用量。"),
                color: AppStyle.accent)
        case .unconfigured:
            ProviderInlineNotice(icon: "key.fill", text: profile.setupHint, color: AppStyle.waitAmber)
        case let .error(message):
            VStack(alignment: .leading, spacing: 8) {
                ProviderInlineNotice(icon: "exclamationmark.triangle.fill", text: message, color: AppStyle.errorRed)
                ToolActionButton(
                    title: L("重试"),
                    systemImage: "arrow.clockwise",
                    role: .secondary,
                    height: 26,
                    fontSize: 11,
                    horizontalPadding: 10,
                    action: onReload)
            }
        case let .loaded(snapshot):
            ProviderUsageCompactDetail(
                providerID: provider.id,
                snapshot: snapshot,
                samples: history.samples(for: provider.id, snapshot: snapshot, config: configStore.config))
        case .unsupported, .none:
            ProviderInlineNotice(icon: "chart.bar.xaxis", text: L("暂无用量数据"), color: AppStyle.textTertiary)
        }
    }

    @ViewBuilder
    private var configurationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProviderCredentialSummaryStrip(items: credentialSummaryItems)
            if !providerConfigValidationIssues.isEmpty {
                ProviderConfigValidationBlock(issues: providerConfigValidationIssues)
            }
            ProviderEnvironmentHintsBlock(
                signInCommand: provider.signInCommand,
                hints: UsageProviderConfigCapabilities.environmentHints(providerID: provider.id),
                includeCookieHints: shouldShowCookieEnvironmentHints)
            if hasTokenAccountSurface {
                ProviderTokenAccountsSettingsBlock(
                    support: tokenAccountSupport,
                    accounts: tokenAccounts,
                    activeIndex: tokenAccountActiveIndexBinding,
                    isAdding: $isAddingTokenAccount,
                    newLabel: $newTokenAccountLabel,
                    newToken: $newTokenAccountToken,
                    newOrganizationID: $newTokenAccountOrganizationID,
                    placeholder: tokenAccountPlaceholder,
                    showsOrganizationField: provider.id == "claude",
                    configStatus: tokenAccountConfigStatus,
                    primaryActionTitle: tokenAccountPrimaryActionTitle,
                    primaryActionSystemImage: tokenAccountPrimaryActionSystemImage,
                    isPrimaryActionRunning: isRunningTokenAccountPrimaryAction,
                    onAdd: addTokenAccount,
                    onRemove: removeTokenAccount,
                    onPrimaryAction: tokenAccountPrimaryAction,
                    onOpenConfigFile: openProviderConfigFile,
                    onReloadFromDisk: reloadProviderConfigFromDisk)
            }
            if provider.id == "codex" {
                CodexDiscoveredAccountsBlock(
                    items: codexDiscoveredAccountItems,
                    onUse: useCodexDiscoveredAccount,
                    onReauthenticate: reauthenticateCodexDiscoveredAccount,
                    onPromote: requestCodexDiscoveredAccountPromotion,
                    onRemove: requestCodexDiscoveredAccountRemoval,
                    onImportAll: importCodexDiscoveredAccounts)
            }
            if !profile.sourceOptions.isEmpty {
                ProviderPickerRow(
                    title: L("来源"),
                    subtitle: profile.sourceSubtitle,
                    selection: stringBinding(.sourceMode, fallback: profile.sourceOptions.first?.id ?? "auto"),
                    options: profile.sourceOptions)
            }
            if !profile.cookieOptions.isEmpty {
                ProviderPickerRow(
                    title: "Cookie",
                    subtitle: profile.cookieSubtitle,
                    selection: stringBinding(.cookieSource, fallback: profile.cookieOptions.first?.id ?? "auto"),
                    options: profile.cookieOptions)
            }
            if provider.id == "qwen" {
                ProviderPickerRow(
                    title: L("区域"),
                    subtitle: L("选择 Alibaba Coding Plan 网关区域。"),
                    selection: stringBinding(.extra("region"), fallback: "intl"),
                    options: qwenRegionOptions)
            }
            if provider.id == "moonshot" {
                ProviderPickerRow(
                    title: L("区域"),
                    subtitle: L("选择国际或中国大陆 Moonshot/Kimi API 主机。"),
                    selection: stringBinding(.extra("region"), fallback: "international"),
                    options: moonshotRegionOptions)
            }
            if provider.id == "minimax" {
                ProviderPickerRow(
                    title: L("区域"),
                    subtitle: L("选择 MiniMax API 区域。"),
                    selection: stringBinding(.extra("region"), fallback: "global"),
                    options: minimaxRegionOptions)
            }
            if provider.id == "glm" {
                ProviderPickerRow(
                    title: L("区域"),
                    subtitle: L("选择 z.ai API 区域。"),
                    selection: stringBinding(.extra("region"), fallback: "global"),
                    options: glmRegionOptions)
            }
            if provider.id == "copilot", providerConfig.flags["budgetExtras"] == true {
                ProviderPickerRow(
                    title: L("副指标"),
                    subtitle: copilotSecondaryMetricSubtitle,
                    selection: stringBinding(.extra("iconSecondaryWindowID"), fallback: "chat"),
                    options: copilotSecondaryMetricOptions)
            }
            ForEach(profile.fields) { field in
                ProviderTextFieldRow(
                    field: field,
                    text: stringBinding(field.key, fallback: ""),
                    onSubmit: onReload)
            }
            if profile.fields.isEmpty, profile.sourceOptions.isEmpty, profile.cookieOptions.isEmpty {
                Text(profile.credentialHint)
                    .font(.system(size: 11))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !profile.actions.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8)
                {
                    ForEach(profile.actions) { action in
                        ToolActionButton(
                            title: action.title,
                            systemImage: action.systemImage,
                            role: .secondary,
                            height: 26,
                            fontSize: 11,
                            horizontalPadding: 10,
                            help: action.help,
                            action: action.perform)
                    }
                }
            }
            if provider.dashboardURL != nil
                || provider.subscriptionDashboardURL != nil
                || provider.statusURL != nil
                || shouldShowChangelogLink
            {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .leading)],
                    alignment: .leading,
                    spacing: 8)
                {
                    if provider.dashboardURL != nil {
                        ToolActionButton(
                            title: L("用量后台"),
                            systemImage: "chart.bar.doc.horizontal",
                            role: .secondary,
                            height: 26,
                            fontSize: 11,
                            horizontalPadding: 10,
                            help: provider.dashboardURL,
                            action: openDashboard)
                    }
                    if provider.subscriptionDashboardURL != nil {
                        ToolActionButton(
                            title: L("订阅后台"),
                            systemImage: "creditcard",
                            role: .secondary,
                            height: 26,
                            fontSize: 11,
                            horizontalPadding: 10,
                            help: provider.subscriptionDashboardURL,
                            action: openSubscriptionDashboard)
                    }
                    if provider.statusURL != nil {
                        ToolActionButton(
                            title: L("状态页"),
                            systemImage: "waveform.path.ecg",
                            role: .secondary,
                            height: 26,
                            fontSize: 11,
                            horizontalPadding: 10,
                            help: provider.statusURL,
                            action: openStatusPage)
                    }
                    if shouldShowChangelogLink {
                        ToolActionButton(
                            title: L("发布说明"),
                            systemImage: "list.bullet.rectangle",
                            role: .secondary,
                            height: 26,
                            fontSize: 11,
                            horizontalPadding: 10,
                            help: provider.changelogURL,
                            action: openChangelog)
                    }
                    if provider.statusPageURL != nil {
                        ToolActionButton(
                            title: L("检查状态"),
                            systemImage: "arrow.clockwise",
                            role: .secondary,
                            height: 26,
                            fontSize: 11,
                            horizontalPadding: 10,
                            action: {
                                Task { await refreshServiceStatus() }
                            })
                    }
                }
            }
        }
    }

    private var openAIWebDebugPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProviderInlineNotice(
                icon: isProviderWebSourceActive ? "checkmark.seal" : "arrow.triangle.2.circlepath",
                text: openAIWebSourceHint,
                color: isProviderWebSourceActive ? AppStyle.doneGreen : AppStyle.waitAmber)

            ProviderInlineNotice(
                icon: openAIWebDebugStatus == nil ? "clock" : "info.circle",
                text: openAIWebDebugStatus ?? L("还没有 %@ Web 刷新状态。", provider.name),
                color: openAIWebDebugStatus == nil ? AppStyle.textTertiary : AppStyle.accent)

            if provider.id == "codex" {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("省电模式"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                        Text(L("后台刷新复用缓存；手动刷新仍会立即抓取 chatgpt.com。"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppStyle.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    ThemedToggle(isOn: openAIWebBatterySaverBinding)
                        .scaleEffect(0.82)
                        .frame(width: 36)
                        .accessibilityLabel(L("省电模式"))
                }

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("失败时写 HTML"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                        Text(L("登录态失效、Cloudflare 或空页面时写入本地 dump。"))
                            .font(.system(size: 10))
                            .foregroundStyle(AppStyle.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    ThemedToggle(isOn: openAIWebDebugDumpBinding)
                        .scaleEffect(0.82)
                        .frame(width: 36)
                        .accessibilityLabel(L("失败时写 HTML"))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    openAIWebDebugButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    openAIWebDebugButtons
                }
            }

            ScrollView {
                Text(openAIWebDebugLogText)
                    .font(.system(size: 9.8, design: .monospaced))
                    .foregroundStyle(openAIWebDebugLog.isEmpty ? AppStyle.textTertiary : AppStyle.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
            }
            .frame(minHeight: 118, maxHeight: 176)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppStyle.hoverFill.opacity(0.68)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppStyle.separator.opacity(0.55), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var openAIWebDebugButtons: some View {
        ToolActionButton(
            title: L("切 Web 并刷新"),
            systemImage: "globe",
            role: isProviderWebSourceActive ? .secondary : .primary,
            height: 26,
            fontSize: 10.8,
            horizontalPadding: 9,
            action: switchProviderToWebAndReload)
        ToolActionButton(
            title: L("刷新"),
            systemImage: "arrow.clockwise",
            role: .secondary,
            height: 26,
            fontSize: 10.8,
            horizontalPadding: 9,
            action: onReload)
        ToolActionButton(
            title: L("复制"),
            systemImage: "doc.on.doc",
            role: .secondary,
            height: 26,
            fontSize: 10.8,
            horizontalPadding: 9,
            action: copyOpenAIWebDebugLog)
            .disabled(openAIWebDebugLog.isEmpty)
        if provider.id == "codex" {
            ToolActionButton(
                title: L("显示 Dump"),
                systemImage: "folder",
                role: .secondary,
                height: 26,
                fontSize: 10.8,
                horizontalPadding: 9,
                action: revealLatestOpenAIWebArtifact)
                .disabled(openAIWebArtifactPaths.isEmpty)
        }
        ToolActionButton(
            title: L("清空"),
            systemImage: "trash",
            role: .destructive,
            height: 26,
            fontSize: 10.8,
            horizontalPadding: 9,
            action: clearOpenAIWebDebugLog)
            .disabled(openAIWebDebugLog.isEmpty)
    }

    private var credentialSummaryItems: [ProviderCredentialSummaryItem] {
        var items: [ProviderCredentialSummaryItem] = [
            ProviderCredentialSummaryItem(
                id: "source",
                title: L("来源"),
                value: sourceLabel,
                icon: "point.3.connected.trianglepath.dotted"),
        ]
        if !profile.cookieOptions.isEmpty || normalized(providerConfig.cookieSource) != nil || normalized(providerConfig.cookieHeader) != nil {
            let cookieSource = profile.cookieOptions.first { $0.id == (providerConfig.cookieSource ?? "auto") }?.title
                ?? providerConfig.cookieSource
                ?? L("自动")
            let cookieValue = normalized(providerConfig.cookieHeader) == nil
                ? cookieSource
                : L("%@ · 已填写", cookieSource)
            items.append(ProviderCredentialSummaryItem(
                id: "cookie",
                title: "Cookie",
                value: cookieValue,
                icon: "globe"))
        }
        if normalized(providerConfig.apiKey) != nil || UsageProviderConfigCapabilities.supportsAPIKey(provider.id) {
            items.append(ProviderCredentialSummaryItem(
                id: "api-key",
                title: L("API 密钥"),
                value: normalized(providerConfig.apiKey) == nil ? L("未填写") : L("已填写"),
                icon: "key.fill"))
        }
        if hasTokenAccountSurface {
            items.append(ProviderCredentialSummaryItem(
                id: "token-accounts",
                title: L("账号"),
                value: tokenAccountsSummary,
                icon: "person.2"))
        }
        if let projectID = normalized(providerConfig.projectID) {
            items.append(ProviderCredentialSummaryItem(
                id: "project",
                title: L("项目"),
                value: projectID,
                icon: "folder.badge.gearshape",
                monospaced: true))
        }
        if let organizationID = normalized(providerConfig.organizationID) {
            items.append(ProviderCredentialSummaryItem(
                id: "organization",
                title: L("组织"),
                value: organizationID,
                icon: "building.2",
                monospaced: true))
        }
        if let baseURL = normalized(providerConfig.baseURL) {
            items.append(ProviderCredentialSummaryItem(
                id: "base-url",
                title: L("基础 URL"),
                value: baseURL,
                icon: "link",
                monospaced: true))
        }
        return items
    }

    private var providerConfigValidationIssues: [ConfigValidationIssue] {
        UsageProviderConfigValidator.issues(for: provider.id, in: configStore.config)
    }

    private var shouldShowCookieEnvironmentHints: Bool {
        !profile.cookieOptions.isEmpty ||
            normalized(providerConfig.cookieSource) != nil ||
            normalized(providerConfig.cookieHeader) != nil ||
            ["codex", "claude", "augment", "cursor", "grok", "perplexity"].contains(provider.id)
    }

    private var tokenAccountsSummary: String {
        if tokenAccounts.isEmpty, !codexDiscoveredTokenAccounts.isEmpty {
            return L("%ld 个发现账号", codexDiscoveredTokenAccounts.count)
        }
        guard !tokenAccounts.isEmpty else { return L("未配置账号") }
        guard let activeTokenAccount else { return L("%ld 个账号", tokenAccounts.count) }
        // 占位符必须全用位置号：混用 %1$ld 和裸 %@ 会让 NSString 格式解析错位，
        // 把 Int 当对象指针 respondsToSelector → 野指针崩（点 codex 渠道详情即崩的真凶）。
        return L("%1$ld 个账号 · 当前 %2$@",
                 tokenAccounts.count,
                 activeTokenAccount.displayName)
    }

    private var tokenAccountActiveIndexBinding: Binding<Int> {
        Binding(
            get: { activeTokenAccountIndex },
            set: { index in
                tokenAccountConfigStatus = nil
                writeConfig { config in
                    var data = config.tokenAccounts ?? UsageProviderTokenAccountData()
                    guard !data.accounts.isEmpty else { return }
                    data.activeIndex = min(max(index, 0), data.accounts.count - 1)
                    config.tokenAccounts = validatedTokenAccountData(data)
                }
                onReload()
            })
    }

    private var tokenAccountPlaceholder: String {
        guard let support = tokenAccountSupport else { return L("Token 或 Cookie") }
        if provider.id == "claude" {
            return "sk-ant-oat / sk-ant-admin / sessionKey=... / CLAUDE_CONFIG_DIR"
        }
        switch support.injection {
        case let .environment(keys, _):
            if provider.id == "codex" { return "CODEX_HOME" }
            if provider.id == "copilot" { return CopilotUsageFetcher.tokenEnvironmentKey }
            return keys.first ?? L("Token 或 Cookie")
        case let .cookieHeader(cookieName):
            if let cookieName { return "\(cookieName)=..." }
            return "Cookie: ..."
        }
    }

    private var tokenAccountPrimaryActionTitle: String? {
        provider.id == "copilot" ? L("GitHub 登录") : nil
    }

    private var tokenAccountPrimaryActionSystemImage: String? {
        provider.id == "copilot" ? "person.crop.circle.badge.plus" : nil
    }

    private var tokenAccountPrimaryAction: (() -> Void)? {
        provider.id == "copilot" ? startCopilotLoginFlow : nil
    }

    private func addTokenAccount() {
        let token = normalized(newTokenAccountToken)
        guard let token else { return }
        tokenAccountConfigStatus = nil
        let label = normalized(newTokenAccountLabel) ?? L("账号 %ld", tokenAccounts.count + 1)
        let organizationID = provider.id == "claude" ? normalized(newTokenAccountOrganizationID) : nil
        writeConfig { config in
            var data = config.tokenAccounts ?? UsageProviderTokenAccountData()
            data.accounts.append(UsageProviderTokenAccount(
                label: label,
                token: token,
                organizationID: organizationID))
            data.activeIndex = data.accounts.count - 1
            config.tokenAccounts = validatedTokenAccountData(data)
            if tokenAccountSupport?.requiresManualCookieSource == true {
                config.cookieSource = "manual"
            }
        }
        resetNewTokenAccountForm()
        onReload()
    }

    private func removeTokenAccount(_ accountID: UUID) {
        tokenAccountConfigStatus = nil
        writeConfig { config in
            guard var data = config.tokenAccounts else { return }
            data.accounts.removeAll { $0.id == accountID }
            data.activeIndex = data.clampedActiveIndex()
            config.tokenAccounts = validatedTokenAccountData(data)
        }
        onReload()
    }

    private func useCodexDiscoveredAccount(_ account: UsageProviderTokenAccount) {
        persistCodexDiscoveredAccounts(selecting: account)
    }

    private func importCodexDiscoveredAccounts() {
        persistCodexDiscoveredAccounts(selecting: nil)
    }

    private func reauthenticateCodexDiscoveredAccount(_ account: UsageProviderTokenAccount) {
        guard provider.id == "codex",
              isManagedCodexDiscoveredAccount(account),
              codexManagedAccountAuthenticatingID == nil,
              codexManagedAccountPromotingID == nil
        else {
            return
        }

        codexManagedAccountAuthenticatingID = account.id
        tokenAccountConfigStatus = .success(L("正在重登 Codex 账号：%@", account.displayName))
        Task { @MainActor in
            defer { codexManagedAccountAuthenticatingID = nil }
            do {
                let managedAccount = try await CodexManagedAccountAuthenticator()
                    .authenticateManagedAccount(existingAccountID: account.id)
                let refreshedAccount = codexTokenAccount(from: managedAccount, markUsed: true)
                persistCodexAccounts([refreshedAccount], selecting: refreshedAccount)
                tokenAccountConfigStatus = .success(L("已重登 Codex 账号：%@", refreshedAccount.displayName))
                onReload()
            } catch {
                tokenAccountConfigStatus = .failure(L("重登 Codex 账号失败：%@", error.localizedDescription))
            }
        }
    }

    private func requestCodexDiscoveredAccountPromotion(_ account: UsageProviderTokenAccount) {
        guard isManagedCodexDiscoveredAccount(account),
              codexManagedAccountAuthenticatingID == nil,
              codexManagedAccountPromotingID == nil
        else {
            return
        }
        codexAccountPromotionCandidate = account
    }

    private var codexAccountPromotionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { codexAccountPromotionCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    codexAccountPromotionCandidate = nil
                }
            })
    }

    private var codexAccountPromotionMessage: String {
        guard let account = codexAccountPromotionCandidate else { return "" }
        return L("会把 %@ 写入本机 Codex CODEX_HOME；当前本机账号会先保存为托管账号，无法安全识别时会拒绝覆盖。", account.displayName)
    }

    private func promoteCodexDiscoveredAccount(_ account: UsageProviderTokenAccount) {
        guard provider.id == "codex",
              isManagedCodexDiscoveredAccount(account),
              codexManagedAccountAuthenticatingID == nil,
              codexManagedAccountPromotingID == nil
        else {
            return
        }

        codexManagedAccountPromotingID = account.id
        tokenAccountConfigStatus = .success(L("正在设为本机 Codex 账号：%@", account.displayName))
        Task { @MainActor in
            defer { codexManagedAccountPromotingID = nil }
            do {
                let result = try CodexManagedAccountPromoter().promoteManagedAccount(id: account.id)
                let discoveredAccounts = CodexManagedAccountDiscovery.tokenAccounts(
                    env: UsageCredentials.providerDiscoveryEnvironment())
                let liveAccount = discoveredAccounts.first {
                    $0.externalIdentifier == "live-system" && $0.id == account.id
                } ?? discoveredAccounts.first {
                    $0.externalIdentifier == "live-system"
                }
                let selectedDisplayName = persistCodexAccounts(
                    discoveredAccounts.isEmpty ? [account] : discoveredAccounts,
                    selecting: liveAccount ?? account)
                tokenAccountConfigStatus = .success(codexPromotionStatusMessage(
                    result: result,
                    displayName: selectedDisplayName ?? liveAccount?.displayName ?? account.displayName))
                onReload()
            } catch {
                tokenAccountConfigStatus = .failure(L("设为本机 Codex 账号失败：%@", error.localizedDescription))
            }
        }
    }

    private func codexPromotionStatusMessage(
        result: CodexManagedAccountPromotionResult,
        displayName: String
    ) -> String {
        switch result.outcome {
        case .convergedNoOp:
            return L("该账号已经是本机 Codex 账号：%@", displayName)
        case .promoted:
            switch result.displacedLiveDisposition {
            case .none:
                return L("已设为本机 Codex 账号：%@", displayName)
            case .alreadyManaged:
                return L("已设为本机 Codex 账号：%@；原本机账号已同步到已有托管账号。", displayName)
            case .imported:
                return L("已设为本机 Codex 账号：%@；原本机账号已保存为托管账号。", displayName)
            }
        }
    }

    private func requestCodexDiscoveredAccountRemoval(_ account: UsageProviderTokenAccount) {
        guard isManagedCodexDiscoveredAccount(account),
              codexManagedAccountAuthenticatingID == nil,
              codexManagedAccountPromotingID == nil
        else { return }
        codexAccountRemovalCandidate = account
    }

    private var codexAccountRemovalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { codexAccountRemovalCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    codexAccountRemovalCandidate = nil
                }
            })
    }

    private var codexAccountRemovalMessage: String {
        guard let account = codexAccountRemovalCandidate else { return "" }
        return L("从 CodexBar 托管账号列表移除 %@；仅删除安全托管目录内的 CODEX_HOME，不会删除本机 ~/.codex。", account.displayName)
    }

    private func removeCodexDiscoveredAccount(_ account: UsageProviderTokenAccount) {
        guard isManagedCodexDiscoveredAccount(account) else { return }
        do {
            let removed = try FileCodexManagedAccountStore().removeManagedAccount(id: account.id)
            guard removed else {
                tokenAccountConfigStatus = .failure(L("未找到 Codex 托管账号：%@", account.displayName))
                return
            }
            writeConfig { config in
                guard var data = config.tokenAccounts else { return }
                data.accounts.removeAll { tokenAccountsRepresentSameAccount($0, account) }
                data.activeIndex = data.clampedActiveIndex()
                config.tokenAccounts = validatedTokenAccountData(data)
            }
            tokenAccountConfigStatus = .success(L("已移除 Codex 托管账号：%@", account.displayName))
            onReload()
        } catch {
            tokenAccountConfigStatus = .failure(L("移除 Codex 托管账号失败：%@", error.localizedDescription))
        }
    }

    private func persistCodexDiscoveredAccounts(selecting selectedAccount: UsageProviderTokenAccount?) {
        let discoveredAccounts = codexDiscoveredTokenAccounts
        guard !discoveredAccounts.isEmpty else {
            tokenAccountConfigStatus = .failure(L("没有发现 Codex 账号"))
            return
        }

        let selectedDisplayName = persistCodexAccounts(discoveredAccounts, selecting: selectedAccount)

        if let selectedDisplayName {
            tokenAccountConfigStatus = .success(L("当前 Codex 账号：%@", selectedDisplayName))
        } else {
            tokenAccountConfigStatus = .success(L("已导入 %ld 个 Codex 账号", discoveredAccounts.count))
        }
        onReload()
    }

    @discardableResult
    private func persistCodexAccounts(
        _ accounts: [UsageProviderTokenAccount],
        selecting selectedAccount: UsageProviderTokenAccount?
    ) -> String? {
        var selectedDisplayName: String?
        writeConfig { config in
            var data = config.tokenAccounts ?? UsageProviderTokenAccountData()
            for account in accounts {
                let isSelected = selectedAccount.map { tokenAccountsRepresentSameAccount($0, account) } ?? false
                let importedAccount = codexImportedAccount(from: account, markUsed: isSelected)
                if let index = data.accounts.firstIndex(where: { tokenAccountsRepresentSameAccount($0, importedAccount) }) {
                    let existing = data.accounts[index]
                    data.accounts[index] = UsageProviderTokenAccount(
                        id: existing.id,
                        label: importedAccount.label,
                        token: importedAccount.token,
                        addedAt: existing.addedAt,
                        lastUsed: importedAccount.lastUsed ?? existing.lastUsed,
                        externalIdentifier: importedAccount.externalIdentifier,
                        organizationID: importedAccount.organizationID)
                    if isSelected {
                        data.activeIndex = index
                        selectedDisplayName = importedAccount.displayName
                    }
                } else {
                    data.accounts.append(importedAccount)
                    if isSelected {
                        data.activeIndex = data.accounts.count - 1
                        selectedDisplayName = importedAccount.displayName
                    }
                }
            }
            if selectedAccount == nil {
                data.activeIndex = data.clampedActiveIndex()
            }
            config.enabled = true
            config.tokenAccounts = validatedTokenAccountData(data)
        }
        return selectedDisplayName
    }

    private func codexTokenAccount(from account: CodexManagedAccount, markUsed: Bool) -> UsageProviderTokenAccount {
        let label: String
        if let workspaceLabel = normalized(account.workspaceLabel),
           workspaceLabel.compare("Personal", options: [.caseInsensitive]) != .orderedSame
        {
            label = "\(account.email) - \(workspaceLabel)"
        } else {
            label = account.email
        }
        return UsageProviderTokenAccount(
            id: account.id,
            label: label,
            token: account.managedHomePath,
            lastUsed: markUsed ? Date().timeIntervalSince1970 : account.lastAuthenticatedAt,
            externalIdentifier: normalized(account.providerAccountID) ?? "managed:\(account.id.uuidString.lowercased())",
            organizationID: normalized(account.workspaceAccountID))
    }

    private func codexImportedAccount(
        from account: UsageProviderTokenAccount,
        markUsed: Bool
    ) -> UsageProviderTokenAccount {
        UsageProviderTokenAccount(
            id: account.id,
            label: normalized(account.label) ?? account.displayName,
            token: normalized(account.token) ?? account.token,
            addedAt: account.addedAt,
            lastUsed: markUsed ? Date().timeIntervalSince1970 : account.lastUsed,
            externalIdentifier: normalized(account.externalIdentifier),
            organizationID: normalized(account.organizationID))
    }

    private func tokenAccountsRepresentSameAccount(
        _ lhs: UsageProviderTokenAccount,
        _ rhs: UsageProviderTokenAccount
    ) -> Bool {
        CodexActiveAccountResolver.representsSameAccount(lhs, rhs)
    }

    private func isManagedCodexDiscoveredAccount(_ account: UsageProviderTokenAccount) -> Bool {
        !CodexActiveAccountResolver.isLiveSystemAccount(account)
    }

    private func startCopilotLoginFlow() {
        guard provider.id == "copilot", !isRunningTokenAccountPrimaryAction else { return }
        isRunningTokenAccountPrimaryAction = true
        tokenAccountConfigStatus = nil
        Task { @MainActor in
            defer { isRunningTokenAccountPrimaryAction = false }
            let result = await CopilotLoginFlow.run(
                enterpriseHost: normalized(providerConfig.extra["enterpriseHost"]),
                existingAccounts: tokenAccounts)
            guard let result else { return }
            let wasRefresh = applyCopilotLoginResult(result)
            tokenAccountConfigStatus = .success(
                wasRefresh
                    ? L("Token 已刷新：%@", result.label)
                    : L("账号已添加：%@", result.label))
            onReload()
        }
    }

    @discardableResult
    private func applyCopilotLoginResult(_ result: CopilotLoginFlow.AccountResult) -> Bool {
        var wasRefresh = false
        writeConfig { config in
            var data = config.tokenAccounts ?? UsageProviderTokenAccountData()
            if let matchedAccountID = result.matchedAccountID,
               let index = data.accounts.firstIndex(where: { $0.id == matchedAccountID })
            {
                let existing = data.accounts[index]
                data.accounts[index] = UsageProviderTokenAccount(
                    id: existing.id,
                    label: result.label,
                    token: result.token,
                    addedAt: existing.addedAt,
                    lastUsed: Date().timeIntervalSince1970,
                    externalIdentifier: result.externalIdentifier,
                    organizationID: existing.organizationID)
                data.activeIndex = index
                wasRefresh = true
            } else {
                data.accounts.append(UsageProviderTokenAccount(
                    label: result.label,
                    token: result.token,
                    lastUsed: Date().timeIntervalSince1970,
                    externalIdentifier: result.externalIdentifier))
                data.activeIndex = data.accounts.count - 1
            }
            config.tokenAccounts = validatedTokenAccountData(data)
            config.enabled = true
            config.sourceMode = "api"
        }
        return wasRefresh
    }

    private func openProviderConfigFile() {
        let url = ConfigLoader.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            configStore.persist()
        }
        if NSWorkspace.shared.open(url) {
            tokenAccountConfigStatus = .success(L("已打开配置文件"))
        } else {
            tokenAccountConfigStatus = .failure(L("无法打开配置文件"))
        }
    }

    private func reloadProviderConfigFromDisk() {
        do {
            try configStore.reloadFromDisk()
            resetNewTokenAccountForm()
            tokenAccountConfigStatus = .success(L("已从磁盘重新读取配置"))
            onReload()
        } catch {
            tokenAccountConfigStatus = .failure(L("重载配置失败：%@", error.localizedDescription))
        }
    }

    private func resetNewTokenAccountForm() {
        isAddingTokenAccount = false
        newTokenAccountLabel = ""
        newTokenAccountToken = ""
        newTokenAccountOrganizationID = ""
    }

    private func validatedTokenAccountData(_ data: UsageProviderTokenAccountData) -> UsageProviderTokenAccountData? {
        let accounts = data.accounts.compactMap { account -> UsageProviderTokenAccount? in
            guard let label = normalized(account.label),
                  let token = normalized(account.token)
            else { return nil }
            return UsageProviderTokenAccount(
                id: account.id,
                label: label,
                token: token,
                addedAt: account.addedAt,
                lastUsed: account.lastUsed,
                externalIdentifier: normalized(account.externalIdentifier),
                organizationID: normalized(account.organizationID))
        }
        guard !accounts.isEmpty else { return nil }
        return UsageProviderTokenAccountData(
            version: max(1, data.version),
            accounts: accounts,
            activeIndex: min(max(data.activeIndex, 0), accounts.count - 1))
    }

    private var loadedSnapshot: UsageSnapshot? {
        if case let .loaded(snapshot) = state { return snapshot }
        return nil
    }

    private var sourceLabel: String {
        profile.sourceOptions.first { $0.id == sourceMode }?.title ?? sourceMode
    }

    private var sourceMode: String {
        providerConfig.sourceMode ?? profile.sourceOptions.first?.id ?? "auto"
    }

    private var hasProviderWebDebugPanel: Bool {
        providerWebDebugLog != nil
    }

    private var providerWebDebugTitle: String {
        switch provider.id {
        case "claude": L("Claude Web 调试")
        default: L("OpenAI Web 调试")
        }
    }

    private var providerWebDebugLog: UsageWebDebugLog? {
        switch provider.id {
        case "codex": OpenAIWebDebugLog.shared
        case "claude": ClaudeWebDebugLog.shared
        default: nil
        }
    }

    private var isProviderWebSourceActive: Bool {
        switch provider.id {
        case "codex":
            ["web", "browser", "dashboard"].contains(sourceMode.lowercased())
        case "claude":
            ["web", "browser"].contains(sourceMode.lowercased())
        default:
            false
        }
    }

    private var openAIWebSourceHint: String {
        if isProviderWebSourceActive {
            if provider.id == "claude" {
                return L("当前来源会读取 Claude Web API；日志会随刷新实时更新。")
            }
            return L("当前来源会读取 OpenAI Web dashboard；日志会随刷新实时更新。")
        }
        return L("当前来源是 %@；切到 Web 后再刷新可查看 %@ 抓取过程。", sourceLabel, provider.name)
    }

    private var openAIWebDebugLogText: String {
        let trimmed = openAIWebDebugLog.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L("暂无 %@ Web 日志。", provider.name) }
        return trimmed
    }

    private var openAIWebBatterySaverBinding: Binding<Bool> {
        Binding(
            get: {
                switch normalized(providerConfig.extra["webBatterySaver"])?.lowercased() {
                case "1", "true", "yes", "y", "on":
                    return true
                default:
                    return false
                }
            },
            set: { enabled in
                writeConfig { config in
                    if enabled {
                        config.extra["webBatterySaver"] = "1"
                    } else {
                        config.extra.removeValue(forKey: "webBatterySaver")
                    }
                }
            })
    }

    private var openAIWebDebugDumpBinding: Binding<Bool> {
        Binding(
            get: {
                switch normalized(providerConfig.extra["webDebugDumpHTML"])?.lowercased() {
                case "1", "true", "yes", "y", "on":
                    return true
                default:
                    return false
                }
            },
            set: { enabled in
                writeConfig { config in
                    if enabled {
                        config.extra["webDebugDumpHTML"] = "1"
                    } else {
                        config.extra.removeValue(forKey: "webDebugDumpHTML")
                    }
                }
            })
    }

    private var authLabel: String {
        guard enabled.wrappedValue else { return L("已停用") }
        switch state {
        case .loaded: return L("就绪")
        case .loading: return L("检查中")
        case .manual: return L("待刷新")
        case .unconfigured: return L("待配置")
        case .error: return L("错误")
        case .unsupported: return L("不支持")
        case .none: return L("未知")
        }
    }

    private var updatedLabel: String {
        guard let snapshot = loadedSnapshot else {
            if case .manual = state { return L("待刷新") }
            if case .loading = state { return L("刷新中") }
            return L("未获取")
        }
        return UsageFormatting.agoText(snapshot.updatedAt)
    }

    private var shouldShowSetupHint: Bool {
        !visibleRepairActions.isEmpty
    }

    private var serviceStatusLabel: String {
        if isRefreshingServiceStatus, serviceStatus == nil {
            return L("检查中")
        }
        guard let serviceStatus else {
            return provider.statusPageURL == nil ? L("仅状态页链接") : L("待检查")
        }
        if serviceStatus.source == "link" {
            return L("仅状态页链接")
        }
        if serviceStatus.source == "none" {
            return L("未配置状态页")
        }
        var value = serviceStatus.label
        if let description = serviceStatus.description, !description.isEmpty {
            value += " · \(description)"
        }
        return value
    }

    private var serviceStatusColor: Color {
        guard let serviceStatus else {
            return provider.statusPageURL == nil ? AppStyle.textTertiary : AppStyle.accent
        }
        if serviceStatus.source == "link" || serviceStatus.source == "none" {
            return AppStyle.textTertiary
        }
        switch serviceStatus.indicator {
        case .none:
            return AppStyle.doneGreen
        case .minor, .maintenance:
            return AppStyle.waitAmber
        case .major, .critical:
            return AppStyle.errorRed
        case .unknown:
            return serviceStatus.error == nil ? AppStyle.textTertiary : AppStyle.waitAmber
        }
    }

    private var shouldShowChangelogLink: Bool {
        configStore.config.usage.providerChangelogLinksEnabled
            && provider.changelogURL?.isEmpty == false
    }

    @MainActor
    private func refreshServiceStatus() async {
        guard provider.statusURL != nil else {
            serviceStatus = nil
            isRefreshingServiceStatus = false
            return
        }
        let previousStatus = serviceStatus?.provider == provider.id ? serviceStatus : nil
        if previousStatus == nil {
            serviceStatus = nil
        }
        isRefreshingServiceStatus = true
        let entry = provider
        let snapshot: UsageProviderStatusSnapshot
        do {
            snapshot = try await UsageProviderStatusFetcher.fetch(entry: entry)
        } catch {
            if let previousStatus {
                guard entry.id == provider.id else { return }
                serviceStatus = previousStatus
                isRefreshingServiceStatus = false
                return
            }
            snapshot = UsageProviderStatusFetcher.errorSnapshot(entry: entry, error: error)
        }
        guard entry.id == provider.id else { return }
        serviceStatus = snapshot
        isRefreshingServiceStatus = false
    }

    private func openStatusPage() {
        guard let raw = provider.statusURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openDashboard() {
        guard let raw = provider.dashboardURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openSubscriptionDashboard() {
        guard let raw = provider.subscriptionDashboardURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openChangelog() {
        guard let raw = provider.changelogURL, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func pollProviderWebDebugLog() async {
        guard hasProviderWebDebugPanel else {
            openAIWebDebugLog = ""
            openAIWebDebugStatus = nil
            openAIWebArtifactPaths = []
            return
        }
        refreshProviderWebDebugSnapshot()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { break }
            refreshProviderWebDebugSnapshot()
        }
    }

    @MainActor
    private func refreshProviderWebDebugSnapshot() {
        guard let log = providerWebDebugLog else {
            openAIWebDebugLog = ""
            openAIWebDebugStatus = nil
            openAIWebArtifactPaths = []
            return
        }
        let snapshot = log.snapshot()
        openAIWebDebugLog = snapshot.text
        openAIWebDebugStatus = snapshot.status
        openAIWebArtifactPaths = snapshot.artifactPaths
    }

    private func switchProviderToWebAndReload() {
        guard hasProviderWebDebugPanel else { return }
        writeConfig { config in
            config.enabled = true
            config.sourceMode = "web"
            if normalized(config.cookieSource) == nil {
                config.cookieSource = "auto"
            }
        }
        refreshProviderWebDebugSnapshot()
        onReload()
    }

    private func copyOpenAIWebDebugLog() {
        let text = openAIWebDebugLog.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func revealLatestOpenAIWebArtifact() {
        let fileManager = FileManager.default
        let selectedPath = openAIWebArtifactPaths.reversed().first { fileManager.fileExists(atPath: $0) }
            ?? openAIWebArtifactPaths.last
        guard let selectedPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selectedPath)])
    }

    private func clearOpenAIWebDebugLog() {
        providerWebDebugLog?.clear()
        refreshProviderWebDebugSnapshot()
    }

    private func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func stringBinding(_ key: ProviderStringConfigKey, fallback: String) -> Binding<String> {
        Binding(
            get: { stringValue(for: key) ?? fallback },
            set: { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                writeConfig { config in
                    setString(trimmed.isEmpty ? nil : trimmed, for: key, in: &config)
                }
            })
    }

    private func flagBinding(_ key: String, defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { providerConfig.flags[key] ?? defaultValue },
            set: { value in
                writeConfig { config in
                    config.flags[key] = value
                }
            })
    }

    private var copilotBudgetExtrasBinding: Binding<Bool> {
        Binding(
            get: { providerConfig.flags["budgetExtras"] ?? false },
            set: { value in
                writeConfig { config in
                    config.flags["budgetExtras"] = value
                    if value, normalized(config.cookieSource) == nil {
                        config.cookieSource = "auto"
                    }
                }
                onReload()
            })
    }

    private func extraFlagBinding(_ key: String, defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: {
                guard let raw = normalized(providerConfig.extra[key])?.lowercased() else { return defaultValue }
                if ["1", "true", "yes", "on"].contains(raw) { return true }
                if ["0", "false", "no", "off"].contains(raw) { return false }
                return defaultValue
            },
            set: { value in
                writeConfig { config in
                    if value == defaultValue {
                        config.extra.removeValue(forKey: key)
                    } else {
                        config.extra[key] = value ? "true" : "false"
                    }
                }
            })
    }

    private var copilotSecondaryMetricOptions: [ProviderOption] {
        var options = [ProviderOption(id: "chat", title: L("聊天"))]
        let extras = loadedSnapshot?.extraRateWindows ?? []
        options.append(contentsOf: extras.map { ProviderOption(id: $0.id, title: $0.title) })
        let selected = normalized(providerConfig.extra["iconSecondaryWindowID"])
        if let selected,
           selected != "chat",
           !options.contains(where: { $0.id == selected })
        {
            options.append(ProviderOption(id: selected, title: L("已选择：%@", selected)))
        }
        return options
    }

    private var moonshotRegionOptions: [ProviderOption] {
        [
            ProviderOption(id: "international", title: L("国际")),
            ProviderOption(id: "china", title: L("中国大陆")),
        ]
    }

    private var minimaxRegionOptions: [ProviderOption] {
        [
            ProviderOption(id: "global", title: L("全球")),
            ProviderOption(id: "cn", title: L("中国大陆")),
        ]
    }

    private var qwenRegionOptions: [ProviderOption] {
        [
            ProviderOption(id: "intl", title: L("国际（modelstudio.console.alibabacloud.com）")),
            ProviderOption(id: "cn", title: L("中国大陆（bailian.console.aliyun.com）")),
        ]
    }

    private var glmRegionOptions: [ProviderOption] {
        [
            ProviderOption(id: "global", title: L("全球（api.z.ai）")),
            ProviderOption(id: "bigmodel-cn", title: L("BigModel 中国大陆（open.bigmodel.cn）")),
        ]
    }

    private var copilotSecondaryMetricSubtitle: String {
        if loadedSnapshot?.extraRateWindows.isEmpty == false {
            return L("选择状态栏渠道详情里的第二个 Copilot 指标。")
        }
        return L("刷新 Copilot 后，GitHub budgets 会出现在这里。")
    }

    private func stringValue(for key: ProviderStringConfigKey) -> String? {
        switch key {
        case .apiKey: return providerConfig.apiKey
        case .sourceMode: return providerConfig.sourceMode
        case .cookieSource: return providerConfig.cookieSource
        case .cookieHeader: return providerConfig.cookieHeader
        case .projectID: return providerConfig.projectID
        case .baseURL: return providerConfig.baseURL
        case .organizationID: return providerConfig.organizationID
        case let .extra(extraKey): return providerConfig.extra[extraKey]
        }
    }

    private func setString(_ value: String?, for key: ProviderStringConfigKey, in config: inout UsageProviderConfig) {
        switch key {
        case .apiKey: config.apiKey = value
        case .sourceMode: config.sourceMode = value
        case .cookieSource: config.cookieSource = value
        case .cookieHeader: config.cookieHeader = value
        case .projectID: config.projectID = value
        case .baseURL: config.baseURL = value
        case .organizationID: config.organizationID = value
        case let .extra(extraKey):
            if let value { config.extra[extraKey] = value } else { config.extra.removeValue(forKey: extraKey) }
        }
    }

    private func writeConfig(_ mutate: (inout UsageProviderConfig) -> Void) {
        var config = configStore.config
        var providerConfig = config.usage.providers[provider.id] ?? UsageProviderConfig()
        mutate(&providerConfig)
        config.usage.providers[provider.id] = providerConfig
        onApplyConfig(config)
    }
}

private struct GlobalQuotaWarningSettingsCard: View {
    let onApplyConfig: (AppConfig) -> Void

    @ObservedObject private var configStore = ConfigStore.shared

    private var warningConfig: Binding<QuotaWarningConfig> {
        Binding(
            get: { configStore.config.usage.quotaWarnings },
            set: { next in
                var config = configStore.config
                config.usage.quotaWarnings = next.validated()
                onApplyConfig(config)
            })
    }

    private var markersVisible: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.quotaWarningMarkersVisible },
            set: { value in
                var config = configStore.config
                config.usage.quotaWarningMarkersVisible = value
                onApplyConfig(config)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(AppStyle.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("配额告警"))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(L("全局阈值，单个渠道可覆盖。"))
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            QuotaWarningConfigEditor(config: warningConfig, enabledFallback: false)
            Divider().opacity(0.42)
            QuotaWarningSwitchRow(
                title: L("显示阈值标记"),
                subtitle: L("在额度条上显示告警阈值线。"),
                isOn: markersVisible)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolsCard(cornerRadius: 10)
    }
}

private struct ProviderQuotaWarningSettings: View {
    let providerID: String
    let onApplyConfig: (AppConfig) -> Void

    @ObservedObject private var configStore = ConfigStore.shared

    private var usesGlobal: Binding<Bool> {
        Binding(
            get: {
                let override = configStore.config.usage.providers[providerID]?.quotaWarnings
                return override?.isEmpty != false
            },
            set: { value in
                var config = configStore.config
                var provider = config.usage.providers[providerID] ?? UsageProviderConfig()
                if value {
                    provider.quotaWarnings = nil
                } else if provider.quotaWarnings?.isEmpty != false {
                    var seed = config.usage.quotaWarnings.validated()
                    seed.enabled = seed.enabled ?? true
                    seed.soundEnabled = seed.soundEnabled ?? true
                    provider.quotaWarnings = seed
                }
                config.usage.providers[providerID] = provider
                onApplyConfig(config)
            })
    }

    private var warningConfig: Binding<QuotaWarningConfig> {
        Binding(
            get: {
                configStore.config.usage.providers[providerID]?.quotaWarnings
                    ?? QuotaWarningConfig(enabled: true, soundEnabled: configStore.config.usage.quotaWarnings.soundEnabled ?? true)
            },
            set: { next in
                var config = configStore.config
                var provider = config.usage.providers[providerID] ?? UsageProviderConfig()
                let clean = next.validated()
                provider.quotaWarnings = clean.isEmpty ? nil : clean
                config.usage.providers[providerID] = provider
                onApplyConfig(config)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuotaWarningSwitchRow(
                title: L("使用全局设置"),
                subtitle: L("关闭后，此渠道使用独立阈值。"),
                isOn: usesGlobal)

            if !usesGlobal.wrappedValue {
                Divider().opacity(0.42)
                QuotaWarningConfigEditor(config: warningConfig, enabledFallback: true)
            }
        }
    }
}

private struct QuotaWarningConfigEditor: View {
    @Binding var config: QuotaWarningConfig
    let enabledFallback: Bool

    private var enabled: Binding<Bool> {
        Binding(
            get: { config.enabled ?? enabledFallback },
            set: { value in
                config.enabled = value
                config = config.validated()
            })
    }

    private var soundEnabled: Binding<Bool> {
        Binding(
            get: { config.soundEnabled ?? true },
            set: { value in
                config.soundEnabled = value
                config = config.validated()
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuotaWarningSwitchRow(
                title: L("启用告警"),
                subtitle: L("额度低于阈值时显示系统通知。"),
                isOn: enabled)
            QuotaWarningSwitchRow(
                title: L("提示音"),
                subtitle: L("触发告警时播放通知声音。"),
                isOn: soundEnabled)

            Divider().opacity(0.42)

            QuotaWarningWindowEditor(
                window: .session,
                config: $config,
                enabledFallback: enabled.wrappedValue)
            Divider().opacity(0.30)
            QuotaWarningWindowEditor(
                window: .weekly,
                config: $config,
                enabledFallback: enabled.wrappedValue)
        }
    }
}

private struct QuotaWarningWindowEditor: View {
    let window: QuotaWarningWindow
    @Binding var config: QuotaWarningConfig
    let enabledFallback: Bool

    private var title: String {
        switch window {
        case .session: return L("会话额度")
        case .weekly: return L("本周额度")
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { currentWindowConfig.enabled ?? enabledFallback },
            set: { value in
                updateWindow { $0.enabled = value }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 11.3, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer(minLength: 8)
                ThemedToggle(isOn: enabled)
                    .scaleEffect(0.76)
                    .frame(width: 32)
                    .accessibilityLabel(title)
                    .accessibilityValue(enabled.wrappedValue ? L("开") : L("关"))
            }

            HStack(spacing: 10) {
                thresholdControl(title: L("提醒"), index: 0)
                thresholdControl(title: L("紧急"), index: 1)
            }
        }
    }

    private var currentWindowConfig: QuotaWarningWindowConfig {
        config.windowConfig(for: window) ?? QuotaWarningWindowConfig()
    }

    private func thresholdControl(title: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9.8, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
            HStack(spacing: 6) {
                ThemedStepper(value: thresholdBinding(index), range: thresholdRange(index))
                    .scaleEffect(0.82, anchor: .leading)
                Text("%")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thresholdBinding(_ index: Int) -> Binding<Int> {
        Binding(
            get: { thresholdPair[index] },
            set: { value in
                updateWindow { windowConfig in
                    var next = thresholdPair
                    if index == 0 {
                        next[0] = min(max(value, 1), 99)
                        next[1] = min(next[1], max(0, next[0] - 1))
                    } else {
                        next[1] = min(max(value, 0), 98)
                        next[0] = max(next[0], min(99, next[1] + 1))
                    }
                    windowConfig.thresholds = QuotaWarningThresholds.sanitized(next)
                }
            })
    }

    private func thresholdRange(_ index: Int) -> ClosedRange<Int> {
        let pair = thresholdPair
        if index == 0 {
            return min(99, pair[1] + 1)...99
        }
        return 0...max(0, pair[0] - 1)
    }

    private var thresholdPair: [Int] {
        var values = QuotaWarningThresholds.sanitized(currentWindowConfig.thresholds)
        let defaults = QuotaWarningThresholds.defaults
        for value in defaults where values.count < 2 && !values.contains(value) {
            values.append(value)
        }
        values = values.sorted(by: >)
        if values.count < 2 {
            let first = values.first ?? defaults[0]
            values.append(max(0, first - 1))
        }
        return Array(values.prefix(2))
    }

    private func updateWindow(_ mutate: (inout QuotaWarningWindowConfig) -> Void) {
        var next = config
        var windowConfig = next.windowConfig(for: window) ?? QuotaWarningWindowConfig()
        mutate(&windowConfig)
        switch window {
        case .session:
            next.session = windowConfig.validated()
        case .weekly:
            next.weekly = windowConfig.validated()
        }
        config = next.validated()
    }
}

private struct QuotaWarningSwitchRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.2, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(subtitle)
                    .font(.system(size: 9.8))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ThemedToggle(isOn: $isOn)
                .scaleEffect(0.78)
                .frame(width: 34)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? L("开") : L("关"))
        }
    }
}

private struct ProviderBrandIcon: View {
    let provider: UsageProviderEntry

    var body: some View {
        let logoName = provider.logoName
        if let image = CLIToolLogo.image(named: logoName) {
            if CLIToolLogo.isMonochrome(logoName) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(AppStyle.textPrimary)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        } else {
            Image(systemName: provider.fallbackSystemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
        }
    }
}

private struct ProviderMiniUsage: View {
    let state: ToolUsageState?

    @ObservedObject private var configStore = ConfigStore.shared

    var body: some View {
        switch state {
        case let .loaded(snapshot):
            if let text = compactSummary(snapshot) {
                ToolBadge(text: text, color: AppStyle.textSecondary, style: .muted, height: 20)
            }
        case .loading:
            ProgressView().controlSize(.small).scaleEffect(0.65)
        case .manual:
            ToolBadge(text: L("手动"), color: AppStyle.accent, height: 18)
        case .unconfigured:
            ToolBadge(text: L("配置"), color: AppStyle.waitAmber, height: 18)
        case .error:
            ToolBadge(text: L("失败"), color: AppStyle.errorRed, height: 18)
        case .unsupported, .none:
            EmptyView()
        }
    }

    private func compactSummary(_ snapshot: UsageSnapshot) -> String? {
        if let window = snapshot.primary ?? snapshot.secondary ?? snapshot.tertiary {
            return L("剩 %ld%%", Int(window.remainingPercent.rounded()))
        }
        if configStore.config.usage.showOptionalCreditsAndExtraUsage, let cost = snapshot.providerCost {
            return CostLine.shortText(cost)
        }
        return nil
    }
}

private struct ProviderDetailSubsection<Content: View>: View {
    let title: String
    let icon: String
    var collapsible = false
    @ViewBuilder var content: Content
    @State private var expanded: Bool

    init(title: String, icon: String, collapsible: Bool = false, defaultExpanded: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.collapsible = collapsible
        self.content = content()
        _expanded = State(initialValue: collapsible ? defaultExpanded : true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if collapsible {
                Button { withAnimation(Motion.snappy) { expanded.toggle() } } label: {
                    headerRow(showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                headerRow(showChevron: false)
            }
            if expanded { content }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerRow(showChevron: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
            Spacer(minLength: 0)
            if showChevron {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(AppStyle.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ProviderPanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppStyle.separator.opacity(0.55))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct ProviderKeyValueRow: View {
    let label: String
    let value: String
    var monospaced = false
    var valueColor: Color?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .frame(width: 76, alignment: .leading)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 11.2, weight: .semibold, design: monospaced ? .monospaced : .default))
                    .foregroundStyle(valueColor ?? AppStyle.textSecondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            Divider().opacity(0.42)
        }
    }
}

private struct ProviderInlineNotice: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 10.8))
                .foregroundStyle(AppStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderConfigValidationBlock: View {
    let issues: [ConfigValidationIssue]

    private var visibleIssues: [ConfigValidationIssue] {
        Array(issues.prefix(4))
    }

    private var title: String {
        issues.contains { $0.severity == "error" } ? L("配置错误") : L("配置警告")
    }

    private var color: Color {
        issues.contains { $0.severity == "error" } ? AppStyle.errorRed : AppStyle.waitAmber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: issues.contains { $0.severity == "error" } ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(visibleIssues.enumerated()), id: \.offset) { _, issue in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(issue.severity == "error" ? AppStyle.errorRed : AppStyle.waitAmber)
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.message)
                                .font(.system(size: 10.4))
                                .foregroundStyle(AppStyle.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let field = issue.field, !field.isEmpty {
                                Text(field)
                                    .font(.system(size: 9.2, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppStyle.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                if issues.count > visibleIssues.count {
                    Text(L("还有 %ld 个配置问题", issues.count - visibleIssues.count))
                        .font(.system(size: 9.8, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.10)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct ProviderStorageFootprintBlock: View {
    let footprint: ProviderStorageFootprint?
    let providerName: String
    let isScanning: Bool

    private var visibleComponents: [ProviderStorageFootprint.Component] {
        Array((footprint?.components ?? []).prefix(6))
    }

    private var cleanupRecommendations: [ProviderStorageRecommendation] {
        footprint?.cleanupRecommendations ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let footprint {
                VStack(spacing: 0) {
                    ProviderKeyValueRow(
                        label: L("占用"),
                        value: footprint.hasLocalData ? footprint.byteCountText : L("未发现本地数据"),
                        monospaced: footprint.hasLocalData)
                    ProviderKeyValueRow(label: L("已检查"), value: L("%ld 个路径", footprint.paths.count), monospaced: true)
                    if !footprint.missingPaths.isEmpty {
                        ProviderKeyValueRow(label: L("缺失"), value: L("%ld 个路径", footprint.missingPaths.count), monospaced: true)
                    }
                    if !footprint.unreadablePaths.isEmpty {
                        ProviderKeyValueRow(
                            label: L("不可读"),
                            value: L("%ld 个路径", footprint.unreadablePaths.count),
                            monospaced: true,
                            valueColor: AppStyle.waitAmber)
                    }
                    ProviderKeyValueRow(label: L("扫描"), value: UsageFormatting.agoText(footprint.updatedAt))
                }

                if !visibleComponents.isEmpty {
                    ProviderUsageGroupHeader(
                        title: L("占用明细"),
                        subtitle: L("最大的本地顶层目录"))
                    VStack(spacing: 6) {
                        ForEach(visibleComponents) { component in
                            ProviderStorageComponentRow(component: component)
                        }
                    }
                }

                if !cleanupRecommendations.isEmpty {
                    ProviderUsageGroupHeader(
                        title: L("清理建议"),
                        subtitle: L("需要手动确认的本地目录"))
                    VStack(spacing: 6) {
                        ForEach(cleanupRecommendations) { recommendation in
                            ProviderStorageRecommendationRow(recommendation: recommendation)
                        }
                    }
                }
            } else if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(L("正在扫描 %@ 的本地存储…", providerName))
                        .font(.system(size: 11))
                        .foregroundStyle(AppStyle.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProviderInlineNotice(
                    icon: "externaldrive",
                    text: L("这个渠道没有已知的本地存储路径，或尚未扫描。"),
                    color: AppStyle.textTertiary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("本地存储"))
    }
}

private struct ProviderStorageComponentRow: View {
    let component: ProviderStorageFootprint.Component

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(component.path)
                    .font(.system(size: 9.3, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: component.totalBytes, countStyle: .file))
                .font(.system(size: 10.3, weight: .bold, design: .monospaced))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.68)))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppStyle.separator.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(component.name), \(ByteCountFormatter.string(fromByteCount: component.totalBytes, countStyle: .file))")
    }
}

private struct ProviderStorageRecommendationRow: View {
    let recommendation: ProviderStorageRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppStyle.waitAmber)
                    .frame(width: 14)
                Text(L(recommendation.title))
                    .font(.system(size: 10.8, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(ByteCountFormatter.string(fromByteCount: recommendation.bytes, countStyle: .file))
                    .font(.system(size: 10.3, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Text(recommendation.path)
                    .font(.system(size: 9.3, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(recommendation.path)
                Spacer(minLength: 0)
                ProviderStoragePathCopyButton(path: recommendation.path)
            }

            Text(L(recommendation.consequence))
                .font(.system(size: 10.2))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(AppStyle.theme.isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.025)))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(AppStyle.separator.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L(recommendation.title)), \(ByteCountFormatter.string(fromByteCount: recommendation.bytes, countStyle: .file))")
        .accessibilityHint(L(recommendation.consequence))
    }
}

private struct ProviderStoragePathCopyButton: View {
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? L("已复制") : L("复制路径"))
        .accessibilityLabel(didCopy ? L("已复制") : L("复制路径"))
    }
}

private struct ProviderRepairActionsList: View {
    let actions: [UsageProviderRepairAction]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions) { action in
                ProviderRepairActionRow(action: action, color: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProviderRepairActionRow: View {
    let action: UsageProviderRepairAction
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(.system(size: 11.2, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(2)
                Text(action.detail)
                    .font(.system(size: 10.6))
                    .foregroundStyle(AppStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let command = action.command, !command.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(command)
                            .font(.system(size: 10.4, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppStyle.accent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        IconOnlyButton(
                            systemName: "doc.on.doc",
                            help: L("复制命令"),
                            size: 24,
                            symbolSize: 9.5,
                            tint: AppStyle.textTertiary,
                            action: copyCommand)
                            .accessibilityLabel(L("复制命令"))
                            .accessibilityValue(command)
                    }
                }
                if let url = action.url, !url.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(url)
                            .font(.system(size: 10.4, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppStyle.accent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        IconOnlyButton(
                            systemName: "arrow.up.right.square",
                            help: L("打开链接"),
                            size: 24,
                            symbolSize: 9.5,
                            tint: AppStyle.textTertiary,
                            action: openURL)
                            .accessibilityLabel(L("打开链接"))
                            .accessibilityValue(url)
                        IconOnlyButton(
                            systemName: "doc.on.doc",
                            help: L("复制链接"),
                            size: 24,
                            symbolSize: 9.5,
                            tint: AppStyle.textTertiary,
                            action: copyURL)
                            .accessibilityLabel(L("复制链接"))
                            .accessibilityValue(url)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func copyCommand() {
        guard let command = action.command, !command.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }

    private func openURL() {
        guard
            let rawURL = action.url,
            !rawURL.isEmpty,
            let url = URL(string: rawURL)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func copyURL() {
        guard let url = action.url, !url.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url, forType: .string)
    }

    private var icon: String {
        switch action.kind {
        case .configureCredential:
            return "key.fill"
        case .signIn:
            return "person.crop.circle.badge.checkmark"
        case .allowKeychain:
            return "lock.open.fill"
        case .solveCloudflare:
            return "safari.fill"
        case .checkNetwork:
            return "network"
        case .checkProviderStatus:
            return "waveform.path.ecg"
        case .adjustSource:
            return "slider.horizontal.3"
        case .inspectResponse, .copyDiagnostics:
            return "doc.text.magnifyingglass"
        case .waitOrRetry:
            return "clock.arrow.circlepath"
        case .retry:
            return "arrow.clockwise"
        }
    }
}

private struct ProviderUsageCompactDetail: View {
    let providerID: String
    let snapshot: UsageSnapshot
    let samples: [UsageSample]

    @ObservedObject private var configStore = ConfigStore.shared

    private var displayMetadata: UsageProviderDisplayMetadata {
        UsageProviderCatalog.displayMetadata(for: providerID, displayName: providerID)
    }

    private var baseWindows: [ProviderUsageDisplayWindow] {
        let metadata = displayMetadata
        var windows: [ProviderUsageDisplayWindow] = []
        if let primary = snapshot.primary {
            windows.append(ProviderUsageDisplayWindow(
                id: "primary",
                title: primary.title ?? metadata.sessionLabel,
                window: primary,
                markerWindow: .session))
        }
        if let secondary = snapshot.secondary {
            windows.append(ProviderUsageDisplayWindow(
                id: "secondary",
                title: secondary.title ?? metadata.weeklyLabel,
                window: secondary,
                markerWindow: .weekly))
        }
        if let tertiary = snapshot.tertiary {
            windows.append(ProviderUsageDisplayWindow(
                id: "tertiary",
                title: tertiary.title ?? metadata.opusLabel ?? L("其它"),
                window: tertiary,
                markerWindow: nil))
        }
        return windows
    }

    private var extraWindows: [ProviderUsageDisplayWindow] {
        guard optionalCreditsAndExtraUsageVisible else { return [] }
        return snapshot.extraRateWindows.map { extra in
            ProviderUsageDisplayWindow(
                id: extra.id,
                title: extra.title,
                window: extra.window,
                markerWindow: nil)
        }
    }

    private var codexCreditsHistory: OpenAIDashboardCreditHistory? {
        guard optionalCreditsAndExtraUsageVisible else { return nil }
        guard providerID == "codex" else { return nil }
        guard let accountEmail = CodexIdentityResolver.firstEmail(in: snapshot.accountLabel) else { return nil }
        return OpenAIDashboardCreditHistoryStore.load(accountEmail: accountEmail)
    }

    private var visibleProviderCost: ProviderCostSnapshot? {
        optionalCreditsAndExtraUsageVisible ? snapshot.providerCost : nil
    }

    private var visibleAmpUsage: AmpUsageDetails? {
        guard optionalCreditsAndExtraUsageVisible else { return nil }
        guard let ampUsage = snapshot.ampUsage, !ampUsage.isEmpty else { return nil }
        return ampUsage
    }

    private var visibleCodexResetCredits: CodexRateLimitResetCreditsSnapshot? {
        guard optionalCreditsAndExtraUsageVisible, providerID == "codex" else { return nil }
        return snapshot.codexResetCredits
    }

    private var hasVisibleUsage: Bool {
        !baseWindows.isEmpty || !extraWindows.isEmpty || visibleProviderCost != nil
            || visibleAmpUsage != nil || visibleCodexResetCredits != nil
    }

    private var optionalCreditsAndExtraUsageVisible: Bool {
        configStore.config.usage.showOptionalCreditsAndExtraUsage
    }

    var body: some View {
        if snapshot.isEmpty || !hasVisibleUsage {
            ProviderInlineNotice(
                icon: "chart.bar.xaxis",
                text: L("已连接，但当前没有可展示的额度窗口。"),
                color: AppStyle.textTertiary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    ProviderKeyValueRow(label: L("更新时间"), value: UsageFormatting.agoText(snapshot.updatedAt))
                    if let account = snapshot.accountLabel, !account.isEmpty {
                        ProviderKeyValueRow(
                            label: L("账号"),
                            value: UsagePersonalInfoRedactor.redactEmails(
                                in: account,
                                isEnabled: configStore.config.usage.hidePersonalInfo) ?? account)
                    }
                    if let plan = snapshot.planName, !plan.isEmpty {
                        ProviderKeyValueRow(label: L("套餐"), value: plan)
                    }
                    ProviderKeyValueRow(label: L("基础窗口"), value: "\(baseWindows.count)", monospaced: true)
                    ProviderKeyValueRow(label: L("额外窗口"), value: "\(extraWindows.count)", monospaced: true)
                    ProviderKeyValueRow(label: L("成本/余额"), value: visibleProviderCost == nil ? L("未提供") : L("已提供"))
                    ProviderKeyValueRow(label: L("余额明细"), value: visibleAmpUsage == nil ? L("未提供") : L("已提供"))
                    ProviderKeyValueRow(label: L("趋势样本"), value: "\(samples.count)", monospaced: true)
                }

                if !baseWindows.isEmpty {
                    ProviderUsageGroupHeader(
                        title: L("基础额度"),
                        subtitle: L("会话、本周或第三额度窗口"))
                    ForEach(baseWindows) { item in
                        ProviderUsageInlineBar(
                            providerID: providerID,
                            title: item.title,
                            window: item.window,
                            snapshot: snapshot,
                            warningThresholds: warningThresholds(for: item.markerWindow),
                            groupLabel: L("基础"))
                    }
                }

                if !extraWindows.isEmpty {
                    ProviderUsageGroupHeader(
                        title: L("额外额度"),
                        subtitle: L("Provider 返回的命名细分窗口"))
                    ForEach(extraWindows) { item in
                        ProviderUsageInlineBar(
                            providerID: providerID,
                            title: item.title,
                            window: item.window,
                            snapshot: snapshot,
                            warningThresholds: [],
                            groupLabel: L("额外"))
                    }
                }

                if let cost = visibleProviderCost {
                    ProviderUsageGroupHeader(
                        title: L("成本/余额"),
                        subtitle: cost.hasLimit ? L("已用、上限与周期") : L("无上限余额或已用金额"))
                    ProviderCostInlineRow(cost: cost)
                }

                if let ampUsage = visibleAmpUsage {
                    ProviderUsageGroupHeader(
                        title: L("余额明细"),
                        subtitle: L("Amp 个人与工作区 credits"))
                    VStack(spacing: 0) {
                        if let individualCredits = ampUsage.individualCredits {
                            ProviderKeyValueRow(
                                label: L("个人 Credits"),
                                value: CostLine.money(individualCredits, "USD"),
                                monospaced: true)
                        }
                        ForEach(Array(ampUsage.workspaceBalances.enumerated()), id: \.offset) { _, workspace in
                            ProviderKeyValueRow(
                                label: "\(L("工作区")) \(workspace.name)",
                                value: CostLine.money(workspace.remaining, "USD"),
                                monospaced: true)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(AppStyle.hoverFill.opacity(0.42)))
                }

                if let resetCredits = visibleCodexResetCredits {
                    ProviderUsageGroupHeader(
                        title: L("限额重置券"),
                        subtitle: L("Codex 手动恢复限额次数"))
                    CodexResetCreditsInlineView(snapshot: resetCredits)
                }

                if let codexCreditsHistory, !codexCreditsHistory.creditEvents.isEmpty {
                    ProviderUsageGroupHeader(
                        title: L("Credits 历史"),
                        subtitle: L("按当前 OpenAI Web 账号持久化"))
                    OpenAICreditsHistoryInlineView(history: codexCreditsHistory)
                }

                if samples.count >= 2 {
                    // 不要再套 .frame(height: 74)——compact:false 的图内部是 120pt + 脚注，
                    // 压成 74 会居中溢出、上面盖住上一条额度行（"重置于…"被图轴叠住）。让它用本来的高度。
                    UsageTrendChart(samples: samples, compact: false)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func warningThresholds(for window: QuotaWarningWindow?) -> [Int] {
        guard configStore.config.usage.quotaWarningMarkersVisible else { return [] }
        guard let window else { return [] }
        let policy = QuotaWarningPolicyResolver.resolve(
            global: configStore.config.usage.quotaWarnings,
            provider: configStore.config.usage.providers[providerID]?.quotaWarnings,
            window: window)
        return policy.enabled ? policy.thresholds : []
    }
}

private struct ProviderUsageDisplayWindow: Identifiable {
    let id: String
    let title: String
    let window: RateWindow
    let markerWindow: QuotaWarningWindow?
}

private struct OpenAICreditsHistoryInlineView: View {
    let history: OpenAIDashboardCreditHistory
    @State private var selectedRangeDays = 7
    @State private var selectedDayKey: String?
    @State private var hoveredDayKey: String?

    private var dailyBreakdown: [OpenAIDashboardDailyBreakdown] {
        OpenAIDashboardSnapshot.makeDailyBreakdown(from: history.creditEvents, maxDays: 30)
    }

    private var selectedDailyBreakdown: [OpenAIDashboardDailyBreakdown] {
        Array(dailyBreakdown.prefix(selectedRangeDays))
    }

    private var selectedTotalCredits: Double {
        selectedDailyBreakdown.reduce(0) { $0 + $1.totalCreditsUsed }
    }

    private var selectedDayBreakdown: OpenAIDashboardDailyBreakdown? {
        if let selectedDayKey,
           let day = selectedDailyBreakdown.first(where: { $0.day == selectedDayKey })
        {
            return day
        }
        return selectedDailyBreakdown.first
    }

    private var activeDayBreakdown: OpenAIDashboardDailyBreakdown? {
        if let hoveredDayKey,
           let day = selectedDailyBreakdown.first(where: { $0.day == hoveredDayKey })
        {
            return day
        }
        return selectedDayBreakdown
    }

    private var serviceTotals: [(service: String, credits: Double)] {
        guard let activeDayBreakdown else { return [] }
        return activeDayBreakdown.services
            .map { (service: $0.service, credits: $0.creditsUsed) }
            .sorted {
                if $0.credits == $1.credits { return $0.service < $1.service }
                return $0.credits > $1.credits
            }
            .prefix(4)
            .map { $0 }
    }

    private var recentEvents: [CreditEvent] {
        Array(history.creditEvents.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    creditsSummary
                    Spacer(minLength: 8)
                    updatedLabel
                }
                VStack(alignment: .leading, spacing: 3) {
                    creditsSummary
                    updatedLabel
                }
            }

            if !dailyBreakdown.isEmpty {
                creditsRangeHeader
                creditsDailyChart
                creditsServiceBreakdown
            }

            if !recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("最近事件"))
                        .font(.system(size: 9.8, weight: .semibold))
                        .foregroundStyle(AppStyle.textTertiary)
                    ForEach(recentEvents) { event in
                        creditEventRow(event)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.58)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Credits 历史"))
        .accessibilityValue(L("%ld 条事件，%@", history.creditEvents.count, creditAmountText(selectedTotalCredits)))
        .onAppear {
            normalizeSelectedDay()
        }
        .onChange(of: selectedRangeDays) {
            normalizeSelectedDay()
        }
    }

    private var creditsSummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 14)
            Text(L("%ld 条事件", history.creditEvents.count))
                .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
            Text(history.accountEmail)
                .font(.system(size: 9.8, weight: .medium, design: .monospaced))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var updatedLabel: some View {
        Text(L("更新 %@", UsageFormatting.agoText(history.updatedAt)))
            .font(.system(size: 9.8, weight: .medium))
            .foregroundStyle(AppStyle.textTertiary)
            .lineLimit(1)
    }

    private var creditsRangeHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                creditsRangeTitle
                Spacer(minLength: 8)
                rangePicker
            }
            VStack(alignment: .leading, spacing: 5) {
                creditsRangeTitle
                rangePicker
            }
        }
    }

    private var creditsRangeTitle: some View {
        HStack(spacing: 5) {
            Text(L("近 %ld 天", selectedRangeDays))
                .font(.system(size: 9.8, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
            Text(creditAmountText(selectedTotalCredits))
                .font(.system(size: 9.8, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var rangePicker: some View {
        Picker("", selection: $selectedRangeDays) {
            Text(L("7 天")).tag(7)
            Text(L("30 天")).tag(30)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(width: 108)
        .accessibilityLabel(L("Credits 历史范围"))
    }

    private var creditsDailyChart: some View {
        OpenAICreditsDailyChartView(
            days: selectedDailyBreakdown,
            selectedDayKey: selectedDayBreakdown?.day,
            hoveredDayKey: hoveredDayKey,
            onSelectDay: { selectedDayKey = $0 },
            onHoverDay: { day in hoveredDayKey = day })
    }

    @ViewBuilder
    private var creditsServiceBreakdown: some View {
        if !serviceTotals.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        serviceBreakdownTitle
                        Spacer(minLength: 8)
                        selectedDaySummary
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        serviceBreakdownTitle
                        selectedDaySummary
                    }
                }
                ForEach(serviceTotals, id: \.service) { item in
                    serviceBreakdownRow(item)
                }
            }
        }
    }

    private var serviceBreakdownTitle: some View {
        Text(L("服务占比"))
            .font(.system(size: 9.8, weight: .semibold))
            .foregroundStyle(AppStyle.textTertiary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        if let activeDayBreakdown {
            Text(L("%@ · %@", shortDayLabel(activeDayBreakdown.day), creditAmountText(activeDayBreakdown.totalCreditsUsed)))
                .font(.system(size: 9.6, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func serviceBreakdownRow(_ item: (service: String, credits: Double)) -> some View {
        let dayTotal = activeDayBreakdown?.totalCreditsUsed ?? 0
        let fraction = dayTotal > 0 ? max(0, min(1, item.credits / dayTotal)) : 0
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                Circle()
                    .fill(serviceColor(item.service))
                    .frame(width: 6, height: 6)
                Text(item.service)
                    .font(.system(size: 10.2, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppStyle.separator.opacity(0.42))
                        Capsule()
                            .fill(serviceColor(item.service).opacity(0.88))
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(width: 56, height: 5)
                Spacer(minLength: 8)
                Text(creditAmountText(item.credits))
                    .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(serviceColor(item.service))
                        .frame(width: 6, height: 6)
                    Text(item.service)
                        .font(.system(size: 10.2, weight: .medium))
                        .foregroundStyle(AppStyle.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(creditAmountText(item.credits))
                        .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppStyle.textPrimary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppStyle.separator.opacity(0.42))
                        Capsule()
                            .fill(serviceColor(item.service).opacity(0.88))
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.service)
        .accessibilityValue(creditAmountText(item.credits))
    }

    private func serviceColor(_ service: String) -> Color {
        let lower = service.lowercased()
        if lower == "cli" {
            return AppStyle.accent
        }
        if lower.contains("github") || lower.contains("review") {
            return Color(red: 0.94, green: 0.53, blue: 0.18)
        }
        let palette: [Color] = [
            Color(red: 0.46, green: 0.75, blue: 0.36),
            Color(red: 0.80, green: 0.45, blue: 0.92),
            Color(red: 0.26, green: 0.78, blue: 0.86),
            Color(red: 0.94, green: 0.74, blue: 0.26),
        ]
        let seed = service.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(seed) % palette.count]
    }

    private func normalizeSelectedDay() {
        guard let latest = selectedDailyBreakdown.first?.day else {
            selectedDayKey = nil
            hoveredDayKey = nil
            return
        }
        if let hoveredDayKey,
           !selectedDailyBreakdown.contains(where: { $0.day == hoveredDayKey })
        {
            self.hoveredDayKey = nil
        }
        guard let selectedDayKey,
              selectedDailyBreakdown.contains(where: { $0.day == selectedDayKey })
        else {
            selectedDayKey = latest
            return
        }
    }

    private func shortDayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    private func creditEventRow(_ event: CreditEvent) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(Self.eventDateFormatter.string(from: event.date))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                Text(event.service)
                    .font(.system(size: 10.2, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(creditAmountText(event.creditsUsed))
                    .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Self.eventDateFormatter.string(from: event.date))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                    Text(creditAmountText(event.creditsUsed))
                        .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppStyle.textPrimary)
                }
                Text(event.service)
                    .font(.system(size: 10.2, weight: .medium))
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func creditAmountText(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted: String
        if absValue >= 100 {
            formatted = String(format: "%.0f", value)
        } else if absValue >= 1 {
            formatted = String(format: "%.2f", value)
        } else {
            formatted = String(format: "%.3f", value)
        }
        return L("%@ credits", formatted)
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private struct OpenAICreditsDailyChartView: View {
    let days: [OpenAIDashboardDailyBreakdown]
    let selectedDayKey: String?
    let hoveredDayKey: String?
    let onSelectDay: (String) -> Void
    let onHoverDay: (String?) -> Void

    private var chartDays: [OpenAIDashboardDailyBreakdown] {
        Array(days.reversed())
    }

    private var maxCredits: Double {
        max(chartDays.map(\.totalCreditsUsed).max() ?? 0, 0.001)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: chartDays.count > 14 ? 2 : 4) {
            ForEach(Array(chartDays.enumerated()), id: \.element.day) { index, day in
                OpenAICreditsDailyBarView(
                    day: day,
                    index: index,
                    count: chartDays.count,
                    maxCredits: maxCredits,
                    isSelected: day.day == selectedDayKey,
                    isHovered: day.day == hoveredDayKey,
                    onSelect: { onSelectDay(day.day) },
                    onHover: { hovering in
                        onHoverDay(hovering ? day.day : nil)
                    })
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 1)
        .onHover { hovering in
            if !hovering {
                onHoverDay(nil)
            }
        }
        .accessibilityLabel(L("每日 Credits 图表"))
    }
}

private struct OpenAICreditsDailyBarView: View {
    let day: OpenAIDashboardDailyBreakdown
    let index: Int
    let count: Int
    let maxCredits: Double
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    private var barFraction: Double {
        guard maxCredits > 0 else { return 0 }
        return max(0, min(1, day.totalCreditsUsed / maxCredits))
    }

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isHighlighted ? AppStyle.accent : AppStyle.accent.opacity(0.62))
                            .frame(height: max(2, geo.size.height * CGFloat(barFraction)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .strokeBorder(isHighlighted ? AppStyle.textPrimary.opacity(0.72) : Color.clear, lineWidth: 1))
                    }
                }
                .frame(height: 42)
                Text(Self.axisLabel(for: index, count: count, day: day.day))
                    .font(.system(size: 7.5, weight: isHighlighted ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(isHighlighted ? AppStyle.textSecondary : AppStyle.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 9)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity)
        .onHover(perform: onHover)
        .help(Self.tooltip(for: day))
        .accessibilityLabel(day.day)
        .accessibilityValue(Self.creditAmountText(day.totalCreditsUsed))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static func axisLabel(for index: Int, count: Int, day: String) -> String {
        if count <= 7 { return shortDayLabel(day) }
        if index == 0 || index == count - 1 || index % 7 == 0 {
            return shortDayLabel(day)
        }
        return " "
    }

    private static func shortDayLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    private static func creditAmountText(_ value: Double) -> String {
        let absValue = abs(value)
        let formatted: String
        if absValue >= 100 {
            formatted = String(format: "%.0f", value)
        } else if absValue >= 1 {
            formatted = String(format: "%.2f", value)
        } else {
            formatted = String(format: "%.3f", value)
        }
        return L("%@ credits", formatted)
    }

    private static func tooltip(for day: OpenAIDashboardDailyBreakdown) -> String {
        let services = day.services
            .prefix(3)
            .map { "\($0.service): \(creditAmountText($0.creditsUsed))" }
        return ([day.day, creditAmountText(day.totalCreditsUsed)] + services)
            .joined(separator: "\n")
    }
}

private struct ProviderUsageGroupHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title)
                .font(.system(size: 10.8, weight: .bold))
                .foregroundStyle(AppStyle.textPrimary)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 9.8, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}

private struct ProviderUsageInlineBar: View {
    let providerID: String
    let title: String
    let window: RateWindow
    let snapshot: UsageSnapshot?
    var warningThresholds: [Int] = []
    var groupLabel: String?

    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var history = UsageHistoryStore.shared

    private var showUsed: Bool { configStore.config.usage.usageBarsShowUsed }
    private var displayPercent: Double { showUsed ? window.usedPercent : window.remainingPercent }
    private var fraction: Double { max(0.02, min(1, displayPercent / 100.0)) }

    private var barColor: Color {
        switch window.usedPercent {
        case ..<70: return AppStyle.accent
        case 70..<90: return AppStyle.waitAmber
        default: return AppStyle.errorRed
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶对齐（不用 firstTextBaseline——「基础」胶囊是框死高度的，没有文字基线，
            // 会把右侧百分比的垂直位置算歪导致叠字）。左块吃满宽度先截断，右侧百分比 fixedSize 钉住。
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                        if let groupLabel {
                            Text(groupLabel)
                                .font(.system(size: 8.8, weight: .bold))
                                .foregroundStyle(AppStyle.textTertiary)
                                .padding(.horizontal, 4)
                                .frame(height: 14)
                                .background(Capsule().fill(AppStyle.subtleFill))
                        }
                    }
                    Text(detailLine)
                        .font(.system(size: 9.8))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(percentText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppStyle.subtleFill)
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * fraction)
                        .animation(Motion.snappy, value: fraction)
                    QuotaWarningMarkers(
                        thresholds: warningThresholds,
                        showUsed: showUsed,
                        width: geo.size.width,
                        height: 7)
                    WorkDayMarkers(
                        workDays: configStore.config.usage.weeklyProgressWorkDays,
                        showUsed: showUsed,
                        windowMinutes: window.windowMinutes,
                        width: geo.size.width,
                        height: 7)
                }
            }
            .frame(height: 5)
            if let pace = history.paceSummary(
                providerID: providerID,
                window: window,
                snapshot: snapshot,
                config: configStore.config) {
                ProviderUsagePaceLine(pace: pace, compact: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var percentText: String {
        // 单个数即可——条形本身已表达占比，不再「剩X% · 已用Y%」挤成一长串。
        if showUsed { return L("已用 %ld%%", Int(window.usedPercent.rounded())) }
        return L("剩 %ld%%", Int(window.remainingPercent.rounded()))
    }

    private var accessibilityValue: String {
        "\(percentText)，\(detailLine)"
    }

    private var detailLine: String {
        var parts: [String] = []
        if let reset = window.resetsAt {
            parts.append(UsageFormatting.resetText(
                reset,
                showAbsolute: configStore.config.usage.resetTimesShowAbsolute))
        }
        else if let description = window.resetDescription, !description.isEmpty { parts.append(description) }
        else { parts.append(L("无固定重置")) }
        if let durationText { parts.append(durationText) }
        return parts.joined(separator: " · ")
    }

    private var durationText: String? {
        guard let minutes = window.windowMinutes, minutes > 0 else { return nil }
        if minutes % (60 * 24) == 0 { return L("窗口 %ld 天", minutes / (60 * 24)) }
        if minutes % 60 == 0 { return L("窗口 %ld 小时", minutes / 60) }
        return L("窗口 %ld 分钟", minutes)
    }
}

private struct ProviderCredentialSummaryItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let icon: String
    var monospaced = false
}

private struct ProviderCredentialSummaryStrip: View {
    let items: [ProviderCredentialSummaryItem]

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 116), spacing: 6, alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L("凭证摘要"))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(AppStyle.textSecondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppStyle.textTertiary)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 8.8, weight: .medium))
                                .foregroundStyle(AppStyle.textTertiary)
                                .lineLimit(1)
                            Text(item.value)
                                .font(.system(size: 10.2, weight: .semibold, design: item.monospaced ? .monospaced : .default))
                                .foregroundStyle(AppStyle.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppStyle.hoverFill.opacity(0.72)))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(item.value)
                }
            }
        }
    }
}

private struct ProviderEnvironmentHintItem: Identifiable {
    let id: String
    let title: String
    let icon: String
    let values: [String]
}

private struct ProviderEnvironmentHintsBlock: View {
    let signInCommand: String?
    let hints: UsageProviderConfigEnvironmentHints
    let includeCookieHints: Bool

    private var items: [ProviderEnvironmentHintItem] {
        var rows: [ProviderEnvironmentHintItem] = []
        if let signInCommand, !signInCommand.isEmpty {
            rows.append(.init(
                id: "sign-in",
                title: L("登录命令"),
                icon: "terminal",
                values: [signInCommand]))
        }
        append(values: hints.apiKey, id: "api-key", title: L("API 环境"), icon: "key.fill", to: &rows)
        if includeCookieHints {
            append(values: hints.cookieHeader, id: "cookie", title: "Cookie", icon: "globe", to: &rows)
            append(values: hints.cookieSource, id: "cookie-source", title: L("Cookie 来源"), icon: "slider.horizontal.3", to: &rows)
        }
        append(values: hints.baseURL, id: "base-url", title: L("地址"), icon: "link", to: &rows)
        append(values: hints.project, id: "project", title: L("项目"), icon: "folder.badge.gearshape", to: &rows)
        append(values: hints.organization, id: "organization", title: L("组织"), icon: "building.2", to: &rows)
        append(values: hints.sourceMode, id: "source", title: L("来源"), icon: "point.3.connected.trianglepath.dotted", to: &rows)
        for key in hints.extra.keys.sorted() {
            append(
                values: hints.extra[key] ?? [],
                id: "extra-\(key)",
                title: L("扩展 %@", key),
                icon: "gearshape.2",
                to: &rows)
        }
        return rows
    }

    var body: some View {
        let rows = items
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("配置环境"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(AppStyle.textSecondary)
                VStack(spacing: 0) {
                    ForEach(rows) { item in
                        ProviderEnvironmentHintRow(item: item)
                    }
                }
            }
        }
    }

    private func append(
        values: [String],
        id: String,
        title: String,
        icon: String,
        to rows: inout [ProviderEnvironmentHintItem])
    {
        guard !values.isEmpty else { return }
        rows.append(.init(id: id, title: title, icon: icon, values: values))
    }
}

private struct ProviderEnvironmentHintRow: View {
    let item: ProviderEnvironmentHintItem

    private var valueText: String {
        item.values.joined(separator: " / ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 13)
            Text(item.title)
                .font(.system(size: 10.2, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .frame(width: 72, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            Text(valueText)
                .font(.system(size: 10.3, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconOnlyButton(
                systemName: "doc.on.doc",
                help: L("复制配置值"),
                size: 24,
                symbolSize: 9.5,
                tint: AppStyle.textTertiary,
                action: copyValues)
                .accessibilityLabel(L("复制配置值"))
                .accessibilityValue(valueText)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(valueText)
        Divider().opacity(0.32)
    }

    private func copyValues() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(valueText, forType: .string)
    }
}

private struct ProviderTokenAccountConfigStatus {
    let message: String
    let isError: Bool

    var icon: String { isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill" }

    static func success(_ message: String) -> ProviderTokenAccountConfigStatus {
        ProviderTokenAccountConfigStatus(message: message, isError: false)
    }

    static func failure(_ message: String) -> ProviderTokenAccountConfigStatus {
        ProviderTokenAccountConfigStatus(message: message, isError: true)
    }
}

private struct ProviderTokenAccountsSettingsBlock: View {
    let support: UsageProviderTokenAccountSupport?
    let accounts: [UsageProviderTokenAccount]
    @Binding var activeIndex: Int
    @Binding var isAdding: Bool
    @Binding var newLabel: String
    @Binding var newToken: String
    @Binding var newOrganizationID: String
    let placeholder: String
    let showsOrganizationField: Bool
    let configStatus: ProviderTokenAccountConfigStatus?
    let primaryActionTitle: String?
    let primaryActionSystemImage: String?
    let isPrimaryActionRunning: Bool
    let onAdd: () -> Void
    let onRemove: (UUID) -> Void
    let onPrimaryAction: (() -> Void)?
    let onOpenConfigFile: () -> Void
    let onReloadFromDisk: () -> Void

    private var canAdd: Bool {
        !newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modeLabel: String {
        guard let support else { return L("已保存账号") }
        switch support.injection {
        case let .environment(keys, _):
            return keys.first ?? L("环境变量")
        case let .cookieHeader(cookieName):
            return cookieName.map { L("Cookie %@", $0) } ?? L("Cookie 头")
        }
    }

    private var subtitle: String {
        guard let support else { return L("已保存账号会用于刷新时切换凭证。") }
        if support.requiresManualCookieSource {
            return L("账号刷新时会作为 Cookie 注入，并使用手动 Cookie 来源。")
        }
        return L("账号刷新时会注入到对应环境变量。")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L("Token 账号"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                        ToolBadge(text: modeLabel, color: AppStyle.accent, height: 17)
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let onPrimaryAction {
                    ToolActionButton(
                        title: isPrimaryActionRunning ? L("登录中…") : (primaryActionTitle ?? L("添加账号")),
                        systemImage: isPrimaryActionRunning ? "hourglass" : primaryActionSystemImage,
                        role: .tinted(AppStyle.accent),
                        height: 24,
                        fontSize: 10.5,
                        horizontalPadding: 9,
                        action: onPrimaryAction)
                        .disabled(isPrimaryActionRunning)
                } else {
                    ToolActionButton(
                        title: isAdding ? L("取消添加") : L("添加账号"),
                        systemImage: isAdding ? "xmark" : "plus",
                        height: 24,
                        fontSize: 10.5,
                        horizontalPadding: 9) {
                            isAdding.toggle()
                        }
                }
            }

            if accounts.count > 1 {
                HStack(spacing: 8) {
                    Text(L("当前账号"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                        .frame(width: 68, alignment: .leading)
                    Picker("", selection: $activeIndex) {
                        ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                            Text(account.displayName).tag(index)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .accessibilityLabel(L("当前账号"))
                    .accessibilityValue(activeAccountLabel)
                    Spacer(minLength: 0)
                }
            }

            if accounts.isEmpty {
                ProviderInlineNotice(
                    icon: "person.badge.plus",
                    text: L("还没有保存账号。"),
                    color: AppStyle.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        ProviderTokenAccountRow(
                            account: account,
                            isActive: activeIndex == index,
                            onSelect: { activeIndex = index },
                            onRemove: { onRemove(account.id) })
                        if index < accounts.count - 1 {
                            Divider().opacity(0.42)
                        }
                    }
                }
            }

            if isAdding, onPrimaryAction == nil {
                ProviderTokenAccountAddForm(
                    newLabel: $newLabel,
                    newToken: $newToken,
                    newOrganizationID: $newOrganizationID,
                    placeholder: placeholder,
                    showsOrganizationField: showsOrganizationField,
                    canAdd: canAdd,
                    onAdd: onAdd)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                ToolActionButton(
                    title: L("打开配置文件"),
                    systemImage: "doc.text",
                    height: 24,
                    fontSize: 10.5,
                    horizontalPadding: 9,
                    action: onOpenConfigFile)
                ToolActionButton(
                    title: L("从磁盘重载"),
                    systemImage: "arrow.triangle.2.circlepath",
                    height: 24,
                    fontSize: 10.5,
                    horizontalPadding: 9,
                    action: onReloadFromDisk)
                Spacer(minLength: 0)
            }

            if let configStatus {
                ToolStatusLine(
                    icon: configStatus.icon,
                    text: configStatus.message,
                    color: configStatus.isError ? AppStyle.errorRed : AppStyle.accent)
                    .accessibilityLabel(configStatus.message)
            }
        }
    }

    private var activeAccountLabel: String {
        guard !accounts.isEmpty else { return L("未选择") }
        let index = min(max(activeIndex, 0), accounts.count - 1)
        return accounts[index].displayName
    }
}

private struct CodexDiscoveredAccountItem: Identifiable {
    let account: UsageProviderTokenAccount
    let isConfigured: Bool
    let isActive: Bool
    let isAuthenticating: Bool
    let isPromoting: Bool
    let canReauthenticate: Bool
    let canPromote: Bool
    let canRemove: Bool

    var id: UUID { account.id }
}

private struct CodexDiscoveredAccountsBlock: View {
    let items: [CodexDiscoveredAccountItem]
    let onUse: (UsageProviderTokenAccount) -> Void
    let onReauthenticate: (UsageProviderTokenAccount) -> Void
    let onPromote: (UsageProviderTokenAccount) -> Void
    let onRemove: (UsageProviderTokenAccount) -> Void
    let onImportAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("发现的 Codex 账号"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(L("从 CodexBar managed store 和本机 CODEX_HOME 读取，可导入后作为当前账号刷新。"))
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ToolActionButton(
                    title: L("导入全部"),
                    systemImage: "tray.and.arrow.down",
                    height: 24,
                    fontSize: 10.5,
                    horizontalPadding: 9,
                    action: onImportAll)
                    .disabled(items.isEmpty)
            }

            if items.isEmpty {
                ProviderInlineNotice(
                    icon: "person.crop.circle.badge.questionmark",
                    text: L("没有发现可导入的 Codex 账号。"),
                    color: AppStyle.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        CodexDiscoveredAccountRow(
                            item: item,
                            onUse: { onUse(item.account) },
                            onReauthenticate: { onReauthenticate(item.account) },
                            onPromote: { onPromote(item.account) },
                            onRemove: { onRemove(item.account) })
                        if index < items.count - 1 {
                            Divider().opacity(0.42)
                        }
                    }
                }
            }
        }
    }
}

private struct CodexDiscoveredAccountRow: View {
    let item: CodexDiscoveredAccountItem
    let onUse: () -> Void
    let onReauthenticate: () -> Void
    let onPromote: () -> Void
    let onRemove: () -> Void

    private var sourceBadge: String {
        item.account.externalIdentifier == "live-system" ? L("本机") : L("托管")
    }

    private var isBusy: Bool {
        item.isAuthenticating || item.isPromoting
    }

    private var hasSecondaryActions: Bool {
        item.canReauthenticate || item.canPromote || item.canRemove || isBusy
    }

    private var detail: String {
        var parts: [String] = [item.account.token]
        if let externalIdentifier = item.account.externalIdentifier, !externalIdentifier.isEmpty {
            parts.append(L("外部 ID %@", externalIdentifier))
        }
        if let organizationID = item.account.organizationID, !organizationID.isEmpty {
            parts.append(L("组织 %@", organizationID))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: item.isActive ? "checkmark.circle.fill" : "person.crop.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(item.isActive ? AppStyle.accent : AppStyle.textTertiary)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.account.displayName)
                        .font(.system(size: 11, weight: item.isActive ? .bold : .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    ToolBadge(text: sourceBadge, color: AppStyle.textTertiary, style: .muted, height: 16)
                    if item.isActive {
                        ToolBadge(text: L("当前"), color: AppStyle.accent, height: 16)
                    } else if item.isConfigured {
                        ToolBadge(text: L("已保存"), color: AppStyle.doneGreen, height: 16)
                    }
                }
                Text(detail)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            ToolActionButton(
                title: item.isActive ? L("当前") : L("使用"),
                systemImage: item.isActive ? "checkmark" : "person.crop.circle.badge.checkmark",
                role: item.isActive ? .secondary : .tinted(AppStyle.accent),
                height: 24,
                fontSize: 10.5,
                horizontalPadding: 9,
                action: onUse)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(item.isActive || isBusy)
            if hasSecondaryActions {
                Menu {
                    Button(action: onReauthenticate) {
                        Label(item.isAuthenticating ? L("登录中…") : L("重登"), systemImage: item.isAuthenticating ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(!item.canReauthenticate || item.isAuthenticating || item.isPromoting)
                    Button(action: onPromote) {
                        Label(item.isPromoting ? L("设置中…") : L("设为本机"), systemImage: item.isPromoting ? "hourglass" : "desktopcomputer")
                    }
                    .disabled(!item.canPromote || item.isPromoting || item.isAuthenticating)
                    if item.canRemove {
                        Divider()
                        Button(role: .destructive, action: onRemove) {
                            Label(L("移除托管账号"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppStyle.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Capsule().fill(AppStyle.hoverFill.opacity(0.82)))
                        .overlay(Capsule().strokeBorder(AppStyle.separator.opacity(0.45), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isBusy && !item.isAuthenticating && !item.isPromoting)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.account.displayName)
        .accessibilityValue(item.isActive ? L("当前账号") : detail)
    }
}

private struct ProviderTokenAccountRow: View {
    let account: UsageProviderTokenAccount
    let isActive: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    private var detail: String {
        var parts: [String] = []
        if let externalIdentifier = account.externalIdentifier, !externalIdentifier.isEmpty {
            parts.append(L("外部 ID %@", externalIdentifier))
        }
        if let organizationID = account.organizationID, !organizationID.isEmpty {
            parts.append(L("组织 %@", organizationID))
        }
        return parts.isEmpty ? L("本机配置账号") : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? AppStyle.accent : AppStyle.textTertiary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                            .foregroundStyle(AppStyle.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppStyle.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            IconOnlyButton(
                systemName: "trash",
                help: L("移除账号"),
                size: 24,
                symbolSize: 10,
                tint: AppStyle.errorRed,
                action: onRemove)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(account.displayName)
        .accessibilityValue(isActive ? L("当前账号") : detail)
    }
}

private struct ProviderTokenAccountAddForm: View {
    @Binding var newLabel: String
    @Binding var newToken: String
    @Binding var newOrganizationID: String
    let placeholder: String
    let showsOrganizationField: Bool
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                TextField(L("账号名称"), text: $newLabel)
                    .providerTokenAccountField()
                SecureField(placeholder, text: $newToken)
                    .providerTokenAccountField(monospaced: true)
                ToolActionButton(
                    title: L("保存账号"),
                    systemImage: "checkmark",
                    role: .tinted(AppStyle.accent),
                    height: 30,
                    fontSize: 10.5,
                    horizontalPadding: 10,
                    action: onAdd)
                    .disabled(!canAdd)
            }
            if showsOrganizationField {
                TextField(L("组织 ID（可选）"), text: $newOrganizationID)
                    .providerTokenAccountField(monospaced: true)
            }
        }
    }
}

private extension View {
    func providerTokenAccountField(monospaced: Bool = false) -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 11.2, design: monospaced ? .monospaced : .default))
            .foregroundStyle(AppStyle.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppStyle.hoverFill))
    }
}

private struct QuotaWarningMarkers: View {
    let thresholds: [Int]
    let showUsed: Bool
    let width: CGFloat
    let height: CGFloat

    private var markerPercents: [Double] {
        QuotaWarningThresholds.active(thresholds)
            .map { showUsed ? 100 - Double($0) : Double($0) }
            .filter { $0 > 0 && $0 < 100 }
    }

    var body: some View {
        ForEach(Array(markerPercents.enumerated()), id: \.offset) { _, percent in
            Rectangle()
                .fill(AppStyle.errorRed.opacity(0.78))
                .frame(width: 1, height: height)
                .offset(x: max(0, min(width - 1, width * CGFloat(percent / 100))))
        }
    }
}

private struct WorkDayMarkers: View {
    let workDays: Int?
    let showUsed: Bool
    let windowMinutes: Int?
    let width: CGFloat
    let height: CGFloat

    private var markerPercents: [Double] {
        UsagePace.workDayMarkerPercents(workDays: workDays, windowMinutes: windowMinutes)
            .map { showUsed ? $0 : 100 - $0 }
            .filter { $0 > 0 && $0 < 100 }
    }

    var body: some View {
        ForEach(Array(markerPercents.enumerated()), id: \.offset) { _, percent in
            Rectangle()
                .fill(AppStyle.textTertiary.opacity(0.5))
                .frame(width: 1, height: height)
                .offset(x: max(0, min(width - 1, width * CGFloat(percent / 100))))
        }
    }
}

private struct ProviderCostInlineRow: View {
    let cost: ProviderCostSnapshot

    @ObservedObject private var configStore = ConfigStore.shared

    private var showUsed: Bool { configStore.config.usage.usageBarsShowUsed }
    private var remainingPercent: Double { max(0, min(100, 100 - cost.usedPercent)) }
    private var displayPercent: Double { showUsed ? cost.usedPercent : remainingPercent }
    private var fraction: Double { max(0.02, min(1, displayPercent / 100)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppStyle.textTertiary)
                    .frame(width: 14)
                Text(text)
                    .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppStyle.textPrimary)
                if let period = cost.period, !period.isEmpty {
                    Text(period)
                        .font(.system(size: 10))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(detailText)
                .font(.system(size: 9.8))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if cost.hasLimit {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(AppStyle.subtleFill)
                        Capsule()
                            .fill(cost.usedPercent >= 90 ? AppStyle.errorRed : cost.usedPercent >= 70 ? AppStyle.waitAmber : AppStyle.accent)
                            .frame(width: geo.size.width * fraction)
                            .animation(Motion.snappy, value: displayPercent)
                    }
                }
                .frame(height: 5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("成本/余额"))
        .accessibilityValue("\(text), \(detailText)")
    }

    private var text: String {
        if cost.hasLimit {
            return "\(CostLine.money(cost.used, cost.currencyCode)) / \(CostLine.money(cost.limit, cost.currencyCode))"
        }
        return L("余额 %@", CostLine.money(cost.used, cost.currencyCode))
    }

    private var detailText: String {
        var parts: [String] = []
        if cost.hasLimit {
            if showUsed {
                parts.append(L("已用 %ld%% · 剩余 %ld%%",
                               Int(cost.usedPercent.rounded()),
                               Int(remainingPercent.rounded())))
            } else {
                parts.append(L("剩余 %ld%% · 已用 %ld%%",
                               Int(remainingPercent.rounded()),
                               Int(cost.usedPercent.rounded())))
            }
        } else {
            parts.append(L("无明确上限"))
        }
        if let period = cost.period, !period.isEmpty {
            parts.append(period)
        }
        if let resetsAt = cost.resetsAt {
            parts.append(UsageFormatting.resetText(
                resetsAt,
                showAbsolute: configStore.config.usage.resetTimesShowAbsolute))
        }
        return parts.joined(separator: " · ")
    }
}

private struct ProviderDetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(AppStyle.textPrimary)
                Spacer(minLength: 0)
            }
            content
        }
        .padding(Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolsCard(cornerRadius: 10)
    }
}

private struct ProviderInfoCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.hoverFill.opacity(0.7)))
    }
}

private struct ProviderSetupHintView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppStyle.waitAmber)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppStyle.waitAmber.opacity(0.10)))
    }
}

private struct ProviderErrorView: View {
    let message: String
    let onReload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(AppStyle.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            ToolActionButton(
                title: L("重试"),
                systemImage: "arrow.clockwise",
                role: .secondary,
                height: 26,
                fontSize: 11,
                horizontalPadding: 10,
                action: onReload)
        }
    }
}

private struct ProviderCalloutView: View {
    let icon: String
    let title: String
    let message: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(Circle().fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.opacity(0.08)))
    }
}

private struct ProviderUsagePaceLine: View {
    let pace: UsagePaceSummary
    let compact: Bool

    private var color: Color {
        if pace.isDeficit {
            return abs(pace.deltaPercent) >= 12 ? AppStyle.errorRed : AppStyle.waitAmber
        }
        if pace.isReserve { return AppStyle.doneGreen }
        return AppStyle.textTertiary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "speedometer")
                .font(.system(size: compact ? 8.5 : 9.5, weight: .semibold))
                .foregroundStyle(color)
            Text(pace.detail)
                .font(.system(size: compact ? 9.2 : 9.8, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("用量节奏"))
        .accessibilityValue(pace.detail)
    }
}

private struct ProviderPickerRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: String
    let options: [ProviderOption]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .frame(width: 68, alignment: .leading)
                Picker("", selection: $selection) {
                    ForEach(options) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .accessibilityLabel(title)
                .accessibilityValue(selectedTitle)
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(AppStyle.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var selectedTitle: String {
        options.first { $0.id == selection }?.title ?? selection
    }
}

private struct ProviderTextFieldRow: View {
    let field: ProviderFieldDescriptor
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    if !field.subtitle.isEmpty {
                        Text(field.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(AppStyle.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Group {
                    switch field.kind {
                    case .plain:
                        TextField(field.placeholder, text: $text)
                    case .secure:
                        SecureField(field.placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: field.kind == .secure ? .monospaced : .default))
                .foregroundStyle(AppStyle.textPrimary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppStyle.hoverFill))
                .onSubmit(onSubmit)
                .accessibilityLabel(field.title)
                .accessibilityHint(field.subtitle)

                IconOnlyButton(
                    systemName: "doc.on.doc",
                    help: L("复制字段值"),
                    size: 30,
                    symbolSize: 11,
                    tint: AppStyle.textTertiary,
                    action: copyValue)
                    .disabled(text.isEmpty)

                IconOnlyButton(
                    systemName: "clipboard",
                    help: L("从剪贴板粘贴"),
                    size: 30,
                    symbolSize: 11,
                    tint: AppStyle.textTertiary,
                    action: pasteValue)
            }
            .contextMenu {
                Button(action: copyValue) {
                    Label(L("复制字段值"), systemImage: "doc.on.doc")
                }
                .disabled(text.isEmpty)

                Button(action: pasteValue) {
                    Label(L("从剪贴板粘贴"), systemImage: "clipboard")
                }
            }

            if let footer = field.footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyValue() {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func pasteValue() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        text = value
    }
}

private struct ProviderToggleRow: View {
    let toggle: ProviderToggleDescriptor
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(toggle.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(toggle.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ThemedToggle(isOn: $isOn)
                .scaleEffect(0.82)
                .frame(width: 36)
                .accessibilityLabel(toggle.title)
                .accessibilityValue(isOn ? L("开") : L("关"))
        }
    }
}

@MainActor
private struct ProviderStatusPresentation {
    let label: String
    let color: Color
    let isStrong: Bool

    init(state: ToolUsageState?, enabled: Bool) {
        guard enabled else {
            label = L("已停用")
            color = AppStyle.textTertiary
            isStrong = false
            return
        }
        switch state {
        case .loaded:
            label = L("就绪")
            color = AppStyle.doneGreen
            isStrong = true
        case .loading:
            label = L("检查中")
            color = AppStyle.accent
            isStrong = false
        case .manual:
            label = L("待刷新")
            color = AppStyle.accent
            isStrong = false
        case .unconfigured:
            label = L("待配置")
            color = AppStyle.waitAmber
            isStrong = true
        case .error:
            label = L("错误")
            color = AppStyle.errorRed
            isStrong = true
        case .unsupported:
            label = L("不支持")
            color = AppStyle.textTertiary
            isStrong = false
        case .none:
            label = L("未知")
            color = AppStyle.textTertiary
            isStrong = false
        }
    }
}

private struct UsageProviderProfile {
    let subtitle: String
    let category: String
    let credentialKind: String
    let credentialHint: String
    let setupHint: String
    let sourceSubtitle: String
    let cookieSubtitle: String
    let sourceOptions: [ProviderOption]
    let cookieOptions: [ProviderOption]
    let fields: [ProviderFieldDescriptor]
    let toggles: [ProviderToggleDescriptor]
    let actions: [ProviderActionDescriptor]

    static func catalog(for provider: UsageProviderEntry) -> UsageProviderProfile {
        let hints = UsageProviderConfigCapabilities.environmentHints(providerID: provider.id)
        let envVar = hints.apiKey.first
        let isCookie = UsageProviderConfigCapabilities.supportsCookieHeader(provider.id)
        let isLocal = localCredentialProviders.contains(provider.id)
        let sourceOptions: [ProviderOption] = {
            let options = Self.sourceOptions(for: provider)
            return options.count > 1 ? options : []
        }()

        var fields: [ProviderFieldDescriptor] = []
        if let envVar {
            let title: String = provider.id == "openai" ? L("管理 / API 密钥") : L("API 密钥")
            let subtitle: String = provider.id == "openai"
                ? L("需要带 billing 权限；project key 可能无法读取额度。")
                : L("保存到本机配置，刷新时作为 %@ 使用。", envVar)
            fields.append(.init(
                key: .apiKey,
                title: title,
                subtitle: subtitle,
                placeholder: envVar,
                kind: .secure,
                footer: hints.apiKey.joined(separator: " / ")))
        }

        if isCookie {
            fields.append(.init(
                key: .cookieHeader,
                title: L("手动 Cookie"),
                subtitle: L("浏览器读取失败时，可临时粘贴 Cookie。"),
                placeholder: "name=value; ...",
                kind: .secure,
                footer: nil))
        }

        if !hints.project.isEmpty {
            let title: String = switch provider.id {
            case "azureopenai": L("Deployment")
            case "deepgram": L("项目")
            case "opencode", "opencodego": "Workspace"
            default: L("项目")
            }
            let placeholder: String = switch provider.id {
            case "azureopenai": "deployment name"
            case "deepgram": "project id"
            case "opencode", "opencodego": "workspace id"
            default: "proj_..."
            }
            fields.append(.init(
                key: .projectID,
                title: title,
                subtitle: L("项目、deployment 或 workspace 标识。"),
                placeholder: placeholder,
                kind: .plain,
                footer: hints.project.joined(separator: " / ")))
        }

        if !hints.baseURL.isEmpty {
            fields.append(.init(
                key: .baseURL,
                title: L("基础 URL"),
                subtitle: L("自定义兼容端点。留空使用 provider 默认地址。"),
                placeholder: "https://...",
                kind: .plain,
                footer: hints.baseURL.joined(separator: " / ")))
        }

        if !hints.organization.isEmpty {
            fields.append(.init(
                key: .organizationID,
                title: L("组织"),
                subtitle: L("组织、workspace 或 account id。"),
                placeholder: "org / organization id",
                kind: .plain,
                footer: hints.organization.joined(separator: " / ")))
        }

        if provider.id == "azureopenai" {
            fields.append(.init(
                key: .extra("apiVersion"),
                title: L("API 版本"),
                subtitle: L("留空使用默认版本。"),
                placeholder: "2024-10-21",
                kind: .plain,
                footer: "AZURE_OPENAI_API_VERSION"))
        }

        if provider.id == "bedrock" {
            fields.append(contentsOf: [
                .init(
                    key: .extra("awsAccessKeyID"),
                    title: "Access Key",
                    subtitle: L("AWS_ACCESS_KEY_ID，用于 Cost Explorer 签名。"),
                    placeholder: "AKIA...",
                    kind: .plain,
                    footer: "AWS_ACCESS_KEY_ID"),
                .init(
                    key: .extra("awsSecretAccessKey"),
                    title: "Secret Key",
                    subtitle: L("AWS_SECRET_ACCESS_KEY。"),
                    placeholder: "secret",
                    kind: .secure,
                    footer: "AWS_SECRET_ACCESS_KEY"),
                .init(
                    key: .extra("awsSessionToken"),
                    title: "Session Token",
                    subtitle: L("临时凭证可选。"),
                    placeholder: "optional",
                    kind: .secure,
                    footer: "AWS_SESSION_TOKEN"),
                .init(
                    key: .extra("awsRegion"),
                    title: L("区域"),
                    subtitle: L("Cost Explorer 默认 us-east-1。"),
                    placeholder: "us-east-1",
                    kind: .plain,
                    footer: "AWS_REGION"),
                .init(
                    key: .extra("awsBudget"),
                    title: L("预算"),
                    subtitle: L("可选月度预算，用于计算百分比。"),
                    placeholder: "100",
                    kind: .plain,
                    footer: "CODEXBAR_BEDROCK_BUDGET"),
            ])
        }

        if provider.id == "stepfun" {
            fields.append(contentsOf: [
                .init(
                    key: .extra("username"),
                    title: L("用户名"),
                    subtitle: L("未填 token 时用于登录换取 Oasis-Token。"),
                    placeholder: "email / phone",
                    kind: .plain,
                    footer: "STEPFUN_USERNAME"),
                .init(
                    key: .extra("password"),
                    title: L("密码"),
                    subtitle: L("仅保存在本机配置中。"),
                    placeholder: "password",
                    kind: .secure,
                    footer: "STEPFUN_PASSWORD"),
            ])
        }

        if provider.id == "openrouter" {
            fields.append(contentsOf: [
                .init(
                    key: .extra("httpReferer"),
                    title: L("HTTP 来源"),
                    subtitle: L("OpenRouter 可选请求来源，用于路由和来源识别。"),
                    placeholder: "https://...",
                    kind: .plain,
                    footer: "OPENROUTER_HTTP_REFERER"),
                .init(
                    key: .extra("clientTitle"),
                    title: L("客户端标题"),
                    subtitle: L("OpenRouter X-Title 请求头；留空使用默认客户端名。"),
                    placeholder: "Conductor",
                    kind: .plain,
                    footer: "OPENROUTER_X_TITLE"),
            ])
        }

        if provider.id == "antigravity" {
            fields.append(contentsOf: [
                .init(
                    key: .extra("oauthCredentialsJSON"),
                    title: L("OAuth 凭证 JSON"),
                    subtitle: L("覆盖 Antigravity OAuth credentials JSON；留空读取共享凭证文件。"),
                    placeholder: "{...}",
                    kind: .secure,
                    footer: "ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"),
                .init(
                    key: .extra("oauthClientID"),
                    title: L("OAuth 客户端 ID"),
                    subtitle: L("覆盖 Antigravity OAuth client_id。"),
                    placeholder: "client id",
                    kind: .plain,
                    footer: "ANTIGRAVITY_OAUTH_CLIENT_ID"),
                .init(
                    key: .extra("oauthClientSecret"),
                    title: L("OAuth 客户端密钥"),
                    subtitle: L("覆盖 Antigravity OAuth client_secret。"),
                    placeholder: "client secret",
                    kind: .secure,
                    footer: "ANTIGRAVITY_OAUTH_CLIENT_SECRET"),
            ])
        }

        if provider.id == "claude" {
            fields.append(contentsOf: [
                .init(
                    key: .extra("sessionKey"),
                    title: L("会话密钥"),
                    subtitle: L("直接设置 Claude Web sessionKey；用于 Web source，优先于浏览器 Cookie。"),
                    placeholder: "sk-ant-sid...",
                    kind: .secure,
                    footer: "CONDUCTOR_USAGE_CLAUDE_SESSION_KEY"),
                .init(
                    key: .extra("oauthToken"),
                    title: L("OAuth 令牌"),
                    subtitle: L("直接设置 Claude OAuth access token；用于 OAuth source。"),
                    placeholder: "sk-ant-oat...",
                    kind: .secure,
                    footer: "CONDUCTOR_USAGE_CLAUDE_OAUTH_TOKEN"),
                .init(
                    key: .extra("subscriptionType"),
                    title: L("订阅类型"),
                    subtitle: L("OAuth 凭证缺少订阅信息时的可选提示。"),
                    placeholder: "pro / max / team",
                    kind: .plain,
                    footer: "CONDUCTOR_USAGE_CLAUDE_SUBSCRIPTION_TYPE"),
            ])
        }

        if provider.id == "copilot" {
            fields.append(.init(
                key: .extra("enterpriseHost"),
                title: L("企业主机"),
                subtitle: L("可选 GitHub Enterprise host。留空使用 github.com。"),
                placeholder: "github.com",
                kind: .plain,
                footer: "COPILOT_ENTERPRISE_HOST"))
        }

        if provider.id == "glm" || provider.id == "qwen" || provider.id == "alibabatokenplan" {
            let quotaURLFooter = switch provider.id {
            case "qwen": "ALIBABA_CODING_PLAN_QUOTA_URL"
            case "alibabatokenplan": "ALIBABA_TOKEN_PLAN_QUOTA_URL"
            default: "Z_AI_QUOTA_URL"
            }
            fields.append(.init(
                key: .extra("quotaURL"),
                title: L("Quota URL"),
                subtitle: L("高级覆盖；通常只填基础 URL 即可。"),
                placeholder: "https://...",
                kind: .plain,
                footer: quotaURLFooter))
        }

        if provider.id == "minimax" {
            fields.append(contentsOf: [
                .init(
                    key: .extra("remainsURL"),
                    title: L("剩余额度 URL"),
                    subtitle: L("覆盖 MiniMax remains 接口；留空跟随基础 URL 和区域。"),
                    placeholder: "https://...",
                    kind: .plain,
                    footer: "MINIMAX_REMAINS_URL"),
                .init(
                    key: .extra("codingPlanURL"),
                    title: L("编码套餐 URL"),
                    subtitle: L("覆盖 MiniMax 编码套餐页面地址，用于 Web source 的 Referer。"),
                    placeholder: "https://...",
                    kind: .plain,
                    footer: "MINIMAX_CODING_PLAN_URL"),
                .init(
                    key: .extra("billingHistoryURL"),
                    title: L("账单历史 URL"),
                    subtitle: L("覆盖 MiniMax 消费历史接口；留空使用当前区域默认地址。"),
                    placeholder: "https://...",
                    kind: .plain,
                    footer: "MINIMAX_BILLING_HISTORY_URL"),
            ])
        }

        let cookieOptions: [ProviderOption] = isCookie
            ? [
                .init(id: "auto", title: L("自动")),
                .init(id: "browser", title: L("浏览器")),
                .init(id: "manual", title: L("手动")),
                .init(id: "off", title: L("关闭")),
            ]
            : []

        var toggles: [ProviderToggleDescriptor] = [
            .init(
                key: "historyTracking",
                title: L("记录趋势"),
                subtitle: L("刷新成功后保留趋势样本。"),
                defaultValue: true),
        ]
        if provider.id == "claude" {
            toggles.append(.init(
                key: "avoidKeychainPrompts",
                title: L("减少授权弹窗"),
                subtitle: L("优先使用本机登录文件，减少重复授权。"),
                defaultValue: false))
        }
        if provider.id == "copilot" {
            toggles.append(.init(
                key: "budgetExtras",
                title: L("预算扩展"),
                subtitle: L("在 Copilot token 用量之外读取 GitHub budgets，并显示为额外额度窗口。"),
                defaultValue: false))
        }
        if provider.id == "minimax" || provider.id == "qwen" {
            toggles.append(.init(
                key: "requireProviderEndpointOverrides",
                title: L("限制端点覆盖"),
                subtitle: provider.id == "minimax"
                    ? L("要求 MiniMax 高级端点仍属于官方域名。关闭后仅校验 HTTPS。")
                    : L("要求 Alibaba 高级端点仍属于官方域名。关闭后仅校验 HTTPS。"),
                defaultValue: false))
        }

        return UsageProviderProfile(
            subtitle: subtitle(for: provider),
            category: category(for: provider),
            credentialKind: credentialKind(for: provider, envVar: envVar, isCookie: isCookie, isLocal: isLocal),
            credentialHint: credentialHint(for: provider, envVar: envVar, isCookie: isCookie, isLocal: isLocal),
            setupHint: setupHint(for: provider, envVar: envVar, isCookie: isCookie, isLocal: isLocal),
            sourceSubtitle: L("自动模式会优先使用已检测到的登录态或应用内凭证。"),
            cookieSubtitle: L("默认从浏览器读取；失败时再手动粘贴 Cookie。"),
            sourceOptions: sourceOptions,
            cookieOptions: cookieOptions,
            fields: fields,
            toggles: toggles,
            actions: actions(for: provider))
    }

    private static let localCredentialProviders: Set<String> = [
        "codex", "claude", "vertexai", "windsurf", "zed", "kiro", "jetbrains", "bedrock",
    ]

    private static func subtitle(for provider: UsageProviderEntry) -> String {
        switch provider.id {
        case "codex": return L("ChatGPT / Codex 订阅额度与窗口。")
        case "claude": return L("Claude Code 本机登录态与订阅用量。")
        case "openai": return L("OpenAI API credit grants 与 billing 额度。")
        case "amp": return L("Amp 账号登录态与 API 用量。")
        case "bedrock": return L("AWS Bedrock 账号预算与凭证。")
        case "vertexai": return L("Google Vertex AI 本地凭证。")
        case "zed": return L("Zed 本地登录态与 edit predictions 用量。")
        case "litellm": return L("LiteLLM 虚拟 key 的 spend/budget 与团队预算。")
        case "poe": return L("Poe API 点数余额与 30 天历史。")
        case "chutes": return L("Chutes 订阅用量、4 小时额度与月度额度。")
        default: return L("%@ 账号级用量与凭证。", provider.name)
        }
    }

    private static func sourceOptions(for provider: UsageProviderEntry) -> [ProviderOption] {
        provider.sourceModes.map { mode in
            ProviderOption(id: mode, title: sourceModeTitle(mode, providerID: provider.id))
        }
    }

    private static func sourceModeTitle(_ mode: String, providerID: String) -> String {
        switch mode {
        case "auto":
            return L("自动")
        case "api":
            if providerID == "claude" { return L("管理 API") }
            if providerID == "amp" { return L("API 令牌") }
            return L("API 密钥")
        case "web":
            return "Web"
        case "browser":
            return L("浏览器")
        case "dashboard":
            return L("用量后台")
        case "cli":
            return "CLI"
        case "oauth":
            return "OAuth"
        case "token":
            return L("OAuth 令牌")
        default:
            return mode
        }
    }

    private static func category(for provider: UsageProviderEntry) -> String {
        switch provider.id {
        case "codex", "claude", "gemini", "cursor", "amp", "opencode", "augment", "zed", "kiro":
            return L("AI 编码")
        case "openai", "azureopenai", "openrouter", "deepseek", "groq", "mistral", "moonshot", "llmproxy", "litellm", "poe", "chutes":
            return "API"
        case "bedrock", "vertexai":
            return L("云服务")
        default:
            return L("渠道")
        }
    }

    private static func credentialKind(
        for provider: UsageProviderEntry,
        envVar: String?,
        isCookie: Bool,
        isLocal: Bool) -> String
    {
        if provider.id == "claude" { return L("本机登录") }
        if provider.id == "codex" { return L("本机登录") }
        if envVar != nil, isCookie { return L("API 密钥 / Cookie") }
        if envVar != nil { return L("API 密钥") }
        if isCookie { return L("浏览器 Cookie") }
        if isLocal { return L("本地凭证") }
        return L("会话")
    }

    private static func credentialHint(
        for provider: UsageProviderEntry,
        envVar: String?,
        isCookie: Bool,
        isLocal: Bool) -> String
    {
        if let envVar { return L("可在这里填写 %@，刷新时优先使用这里的值。", envVar) }
        if provider.id == "codex" { return L("使用本机登录态自动检测。") }
        if provider.id == "claude" { return L("使用本机登录态自动检测。") }
        if isCookie { return L("默认从浏览器读取登录态。") }
        if isLocal { return L("使用本机 CLI 或云厂商登录态自动检测。") }
        return L("该渠道无需额外配置，检测到登录态即自动显示用量。")
    }

    private static func setupHint(
        for provider: UsageProviderEntry,
        envVar: String?,
        isCookie: Bool,
        isLocal: Bool) -> String
    {
        if let envVar { return L("填写 %@，或在本机 shell 配置后刷新。", envVar) }
        if provider.id == "codex" { return L("先完成 Codex CLI 登录，然后刷新。") }
        if provider.id == "claude" { return L("先完成 Claude Code 登录，然后刷新。") }
        if isCookie { return L("先在浏览器登录 %@，然后刷新。", provider.name) }
        if isLocal { return L("确认本机 CLI 或云厂商登录态可用。") }
        return L("该渠道通过本机登录态自动检测，无法自动获取时用量留空。")
    }

    private static func actions(for provider: UsageProviderEntry) -> [ProviderActionDescriptor] {
        switch provider.id {
        case "codex":
            return [
                .init(title: L("打开本机配置"), systemImage: "folder", help: L("打开 Codex 本机配置目录")) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
                },
            ]
        case "claude":
            return [
                .init(title: L("打开本机配置"), systemImage: "folder", help: L("打开 Claude 本机配置目录")) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))
                },
            ]
        case "openai":
            return [
                .init(title: L("账单"), systemImage: "safari", help: "OpenAI billing") {
                    openURL("https://platform.openai.com/settings/organization/billing/overview")
                },
                .init(title: L("项目"), systemImage: "safari", help: "OpenAI projects") {
                    openURL("https://platform.openai.com/settings/organization/projects")
                },
            ]
        case "amp":
            return [
                .init(title: L("Amp 设置"), systemImage: "safari", help: "ampcode.com") {
                    openURL("https://ampcode.com/settings")
                },
            ]
        case "zed":
            return [
                .init(title: L("打开 Zed 设置"), systemImage: "doc.text", help: L("打开 Zed 本机设置文件")) {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/zed/settings.json"))
                },
            ]
        case "poe":
            return [
                .init(title: L("Poe API 密钥"), systemImage: "safari", help: "poe.com/api/keys") {
                    openURL("https://poe.com/api/keys")
                },
            ]
        case "chutes":
            return [
                .init(title: "Chutes", systemImage: "safari", help: "chutes.ai") {
                    openURL("https://chutes.ai")
                },
            ]
        default:
            return []
        }
    }

    private static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProviderOption: Identifiable, Equatable {
    let id: String
    let title: String
}

private enum ProviderStringConfigKey: Hashable {
    case apiKey
    case sourceMode
    case cookieSource
    case cookieHeader
    case projectID
    case baseURL
    case organizationID
    case extra(String)
}

private struct ProviderFieldDescriptor: Identifiable {
    enum Kind {
        case plain
        case secure
    }

    let key: ProviderStringConfigKey
    let title: String
    let subtitle: String
    let placeholder: String
    let kind: Kind
    let footer: String?

    var id: String {
        switch key {
        case .apiKey: return "apiKey"
        case .sourceMode: return "sourceMode"
        case .cookieSource: return "cookieSource"
        case .cookieHeader: return "cookieHeader"
        case .projectID: return "projectID"
        case .baseURL: return "baseURL"
        case .organizationID: return "organizationID"
        case let .extra(key): return "extra.\(key)"
        }
    }
}

private struct ProviderToggleDescriptor: Identifiable {
    let key: String
    let title: String
    let subtitle: String
    let defaultValue: Bool

    var id: String { key }
}

private struct ProviderActionDescriptor: Identifiable {
    let title: String
    let systemImage: String
    let help: String
    let perform: () -> Void

    var id: String { "\(title)-\(systemImage)" }
}
