import AppKit
import ConductorCore
import SwiftUI

struct AgentToolsUsageView: View {
    @ObservedObject var store: AgentToolsConsoleStore
    let onApplyConfig: (AppConfig) -> Void
    let onOpenModule: (AgentToolsManagementModule) -> Void

    @ObservedObject private var configStore = ConfigStore.shared
    @State private var showingStatusBarOverviewPicker = false

    private var providers: [UsageProviderEntry] {
        UsageProviderCatalog.orderedEntries(config: configStore.config)
    }
    private var selectedProviderBinding: Binding<String?> {
        Binding(
            get: { store.selectedUsageProviderID },
            set: { store.selectedUsageProviderID = $0 })
    }

    private var enabledCount: Int {
        providers.filter { isEnabled($0) }.count
    }

    private var loadedCount: Int {
        UsageProviderCatalog.orderedEntries(config: configStore.config).filter {
            if case .loaded = store.usageState(for: $0) { return true }
            return false
        }.count
    }

    private var manualCount: Int {
        UsageProviderCatalog.orderedEntries(config: configStore.config).filter {
            if case .manual = store.usageState(for: $0) { return true }
            return false
        }.count
    }

    private var setupCount: Int {
        UsageProviderCatalog.orderedEntries(config: configStore.config).filter {
            if case .unconfigured = store.usageState(for: $0) { return true }
            return false
        }.count
    }

    private var errorCount: Int {
        UsageProviderCatalog.orderedEntries(config: configStore.config).filter {
            if case .error = store.usageState(for: $0) { return true }
            return false
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metricStrip
            refreshCadenceStrip
            usageDisplayStrip
            statusBarOverviewStrip
            workbench
        }
        .agentToolsPage()
        .onAppear {
            store.start()
            selectDefaultProviderIfNeeded()
        }
        .onChange(of: store.providerStates.count) { _, _ in
            selectDefaultProviderIfNeeded()
        }
    }

    private var header: some View {
        AgentToolsModuleHeader(
            title: L("用量"),
            subtitle: L("账号渠道、凭证来源、额度窗口和本机用量记录"),
            icon: "chart.bar.xaxis") {
            ToolActionButton(
                title: L("刷新已配置"),
                systemImage: "arrow.clockwise",
                height: 34,
                fontSize: 11.5,
                horizontalPadding: 12,
                help: L("手动刷新所有已配置渠道")) {
                    refreshConfiguredProviders()
                }
            ToolActionButton(
                title: store.isScanningLocalUsage ? L("读取中") : L("刷新本地用量"),
                systemImage: store.isScanningLocalUsage ? nil : "externaldrive",
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 18, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            AgentToolsStat(value: "\(providers.count)", title: L("全部渠道"))
            AgentToolsStat(value: "\(enabledCount)", title: L("启用"))
            AgentToolsStat(value: "\(loadedCount)", title: L("已取数"), valueColor: AppStyle.doneGreen)
            AgentToolsStat(value: "\(manualCount)", title: L("待刷新"))
            AgentToolsStat(value: "\(setupCount)", title: L("待配置"), valueColor: setupCount == 0 ? AppStyle.textPrimary : AppStyle.waitAmber)
            AgentToolsStat(value: "\(errorCount)", title: L("错误"), valueColor: errorCount == 0 ? AppStyle.textPrimary : AppStyle.errorRed)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 14)
        .agentToolsGlass()
    }

    private var statusBarOverviewStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(AppStyle.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("状态栏概览渠道"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(statusBarOverviewSummary)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button {
                showingStatusBarOverviewPicker = true
            } label: {
                HStack(spacing: 5) {
                    Text(L("%ld / %ld", statusBarOverviewIDs.count, UsageConfig.maxStatusBarOverviewProviders))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(AppStyle.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Capsule().fill(AppStyle.hoverFill.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .help(L("配置状态栏概览渠道"))
            .popover(isPresented: $showingStatusBarOverviewPicker, arrowEdge: .bottom) {
                StatusBarOverviewProviderPicker(
                    providers: statusBarOverviewCandidates,
                    selectedIDs: statusBarOverviewIDs,
                    maxCount: UsageConfig.maxStatusBarOverviewProviders,
                    onToggle: setStatusBarOverviewProvider(_:isSelected:),
                    onReset: resetStatusBarOverviewProviders)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .agentToolsGlass()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("状态栏概览渠道"))
        .accessibilityValue(statusBarOverviewSummary)
    }

    private var refreshCadenceStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(AppStyle.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("状态栏自动刷新"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                Text(L("只刷新已配置且不会触发浏览器提示的渠道"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Picker(L("状态栏自动刷新"), selection: providerRefreshIntervalBinding) {
                ForEach(UsageConfig.allowedProviderRefreshIntervalSeconds, id: \.self) { seconds in
                    Text(refreshCadenceLabel(seconds)).tag(seconds)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 128)
            .accessibilityLabel(L("状态栏自动刷新"))
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .agentToolsGlass()
    }

    private var usageDisplayStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(AppStyle.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("显示选项"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(L("对齐 CodexBar 菜单里的用量和重置时间显示口径。"))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 14, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                UsageDisplayToggleRow(
                    title: L("显示已使用用量"),
                    subtitle: L("进度条会随配额消耗填充；关闭后显示剩余额度。"),
                    isOn: usageBarsShowUsedBinding)
                UsageDisplayToggleRow(
                    title: L("将重置时间显示为时钟"),
                    subtitle: L("将重置时间显示为绝对时钟值，而不是倒计时。"),
                    isOn: resetTimesShowAbsoluteBinding)
                UsageDisplayToggleRow(
                    title: L("显示额度 + 额外用量"),
                    subtitle: L("在菜单中显示 Codex Credits 和 Claude 额外用量部分。"),
                    isOn: showOptionalCreditsAndExtraUsageBinding)
                UsageDisplayToggleRow(
                    title: L("隐藏个人信息"),
                    subtitle: L("在菜单栏和菜单界面中隐藏电子邮件地址。"),
                    isOn: hidePersonalInfoBinding)
                UsageDisplayToggleRow(
                    title: L("显示本地存储占用"),
                    subtitle: L("扫描 CLI 本地数据目录，并在渠道详情中显示占用大小。"),
                    isOn: providerStorageFootprintsEnabledBinding)
                UsageDisplayPickerRow(
                    title: L("工作日刻度线"),
                    subtitle: L("设置用于每周用量条刻度和进度计算的工作日。"),
                    selection: weeklyProgressWorkDaysBinding)
                UsageDisplayToggleRow(
                    title: L("显示提供商变更日志链接"),
                    subtitle: L("在菜单中为支持的 CLI 提供商添加发布说明链接。"),
                    isOn: providerChangelogLinksEnabledBinding)
            }
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 10)
        .agentToolsGlass()
    }

    private var workbench: some View {
        ScrollView {
            UsageProvidersSettingsView(
                providers: providers,
                tools: store.cliTools,
                states: store.providerStates,
                storageFootprints: store.providerStorageFootprints,
                isScanningStorage: store.isScanningProviderStorage,
                selectedID: selectedProviderBinding,
                onApplyConfig: onApplyConfig,
                onReload: { store.refreshProvider($0) })
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .agentToolsGlass()
        }
        .scrollIndicators(.visible)
    }

    private func refreshConfiguredProviders() {
        providers.forEach { provider in
            switch store.usageState(for: provider) {
            case .manual, .loaded, .error:
                store.refreshProvider(provider)
            default:
                break
            }
        }
    }

    private func selectDefaultProviderIfNeeded() {
        guard store.selectedUsageProviderID == nil else { return }
        let preferred = providers.first { provider in
            switch store.usageState(for: provider) {
            case .loaded, .manual, .error: return true
            default: return false
            }
        } ?? providers.first
        store.selectedUsageProviderID = preferred?.id
    }

    private func isEnabled(_ provider: UsageProviderEntry) -> Bool {
        provider.isEnabled(in: configStore.config)
    }

    private var statusBarOverviewCandidates: [UsageProviderEntry] {
        providers.filter { provider in
            provider.id != "codex" && isEnabled(provider)
        }
    }

    private var statusBarOverviewIDs: [String] {
        configStore.config.usage.effectiveStatusBarOverviewProviderIDs(
            activeProviderIDs: statusBarOverviewCandidates.map(\.id))
    }

    private var statusBarOverviewSummary: String {
        let selected = statusBarOverviewIDs
        guard !selected.isEmpty else { return L("未选择任何渠道") }
        let namesByID = Dictionary(uniqueKeysWithValues: statusBarOverviewCandidates.map { ($0.id, $0.name) })
        return selected.compactMap { namesByID[$0] }.joined(separator: ", ")
    }

    private func setStatusBarOverviewProvider(_ provider: UsageProviderEntry, isSelected: Bool) {
        let activeIDs = UsageConfig.normalizedProviderOrder(statusBarOverviewCandidates.map(\.id))
        var selectedSet = Set(statusBarOverviewIDs)
        if isSelected {
            guard selectedSet.contains(provider.id) || selectedSet.count < UsageConfig.maxStatusBarOverviewProviders else {
                return
            }
            selectedSet.insert(provider.id)
        } else {
            selectedSet.remove(provider.id)
        }
        let updated = Array(activeIDs.filter { selectedSet.contains($0) }.prefix(UsageConfig.maxStatusBarOverviewProviders))
        var config = configStore.config
        config.usage.statusBarOverviewProviderIDs = updated
        config.usage.statusBarOverviewSelectionBasisIDs = activeIDs
        onApplyConfig(config)
    }

    private func resetStatusBarOverviewProviders() {
        var config = configStore.config
        config.usage.statusBarOverviewProviderIDs = []
        config.usage.statusBarOverviewSelectionBasisIDs = []
        onApplyConfig(config)
    }

    private var providerRefreshIntervalBinding: Binding<Int> {
        Binding(
            get: { configStore.config.usage.providerRefreshIntervalSeconds },
            set: { seconds in
                var config = configStore.config
                config.usage.providerRefreshIntervalSeconds =
                    UsageConfig.normalizedProviderRefreshIntervalSeconds(seconds)
                onApplyConfig(config)
            })
    }

    private var usageBarsShowUsedBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.usageBarsShowUsed },
            set: { showUsed in
                var config = configStore.config
                config.usage.usageBarsShowUsed = showUsed
                onApplyConfig(config)
            })
    }

    private var resetTimesShowAbsoluteBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.resetTimesShowAbsolute },
            set: { showAbsolute in
                var config = configStore.config
                config.usage.resetTimesShowAbsolute = showAbsolute
                onApplyConfig(config)
            })
    }

    private var showOptionalCreditsAndExtraUsageBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.showOptionalCreditsAndExtraUsage },
            set: { showOptional in
                var config = configStore.config
                config.usage.showOptionalCreditsAndExtraUsage = showOptional
                onApplyConfig(config)
            })
    }

    private var hidePersonalInfoBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.hidePersonalInfo },
            set: { hidePersonalInfo in
                var config = configStore.config
                config.usage.hidePersonalInfo = hidePersonalInfo
                onApplyConfig(config)
            })
    }

    private var weeklyProgressWorkDaysBinding: Binding<Int> {
        Binding(
            get: { configStore.config.usage.weeklyProgressWorkDays ?? 0 },
            set: { days in
                var config = configStore.config
                config.usage.weeklyProgressWorkDays =
                    UsageConfig.normalizedWeeklyProgressWorkDays(days == 0 ? nil : days)
                onApplyConfig(config)
            })
    }

    private var providerStorageFootprintsEnabledBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.providerStorageFootprintsEnabled },
            set: { isEnabled in
                var config = configStore.config
                config.usage.providerStorageFootprintsEnabled = isEnabled
                onApplyConfig(config)
                if isEnabled {
                    store.refreshProviderStorageFootprints(force: true)
                } else {
                    store.clearProviderStorageFootprints()
                }
            })
    }

    private var providerChangelogLinksEnabledBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.usage.providerChangelogLinksEnabled },
            set: { isEnabled in
                var config = configStore.config
                config.usage.providerChangelogLinksEnabled = isEnabled
                onApplyConfig(config)
            })
    }

    private func refreshCadenceLabel(_ seconds: Int) -> String {
        switch seconds {
        case UsageConfig.manualProviderRefreshIntervalSeconds:
            return L("手动")
        case 60:
            return L("1 分钟")
        case 120:
            return L("2 分钟")
        case 300:
            return L("5 分钟")
        case 900:
            return L("15 分钟")
        case 1800:
            return L("30 分钟")
        default:
            return L("5 分钟")
        }
    }
}

private struct UsageDisplayToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.4, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ThemedToggle(isOn: $isOn)
                .accessibilityLabel(title)
                .accessibilityValue(isOn ? L("开启") : L("关闭"))
        }
        .frame(minHeight: 34, alignment: .center)
    }
}

private struct UsageDisplayPickerRow: View {
    let title: String
    let subtitle: String
    @Binding var selection: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.4, weight: .semibold))
                    .foregroundStyle(AppStyle.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9.8, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                Text(L("关闭")).tag(0)
                ForEach(UsageConfig.allowedWeeklyProgressWorkDays, id: \.self) { days in
                    Text(L("%ld 天", days)).tag(days)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 92)
            .accessibilityLabel(title)
        }
        .frame(minHeight: 34, alignment: .center)
    }
}

private struct AgentToolsWorkDayMarkers: View {
    let workDays: Int?
    let windowMinutes: Int?
    let width: CGFloat
    let height: CGFloat

    private var markerPercents: [Double] {
        UsagePace.workDayMarkerPercents(workDays: workDays, windowMinutes: windowMinutes)
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

private struct StatusBarOverviewProviderPicker: View {
    let providers: [UsageProviderEntry]
    let selectedIDs: [String]
    let maxCount: Int
    let onToggle: (UsageProviderEntry, Bool) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("状态栏概览渠道"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                    Text(L("最多选择 %ld 个，顺序跟随渠道排序。", maxCount))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppStyle.textTertiary)
                }
                Spacer(minLength: 0)
                Button(L("恢复默认")) { onReset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
            }

            if providers.isEmpty {
                Text(L("没有可用于状态栏概览的渠道。"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppStyle.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(providers) { provider in
                            row(provider)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(AppStyle.windowBackground)
    }

    private func row(_ provider: UsageProviderEntry) -> some View {
        let isSelected = selectedIDs.contains(provider.id)
        let isDisabled = !isSelected && selectedIDs.count >= maxCount
        return Toggle(
            isOn: Binding(
                get: { selectedIDs.contains(provider.id) },
                set: { onToggle(provider, $0) }))
        {
            HStack(spacing: 8) {
                AgentToolsUsageProviderLogo(provider: provider)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(provider.id)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .help(isDisabled ? L("最多选择 %ld 个渠道", maxCount) : provider.name)
    }
}

struct AgentToolsUsageInspector: View {
    @ObservedObject var store: AgentToolsConsoleStore
    @ObservedObject private var configStore = ConfigStore.shared
    @ObservedObject private var history = UsageHistoryStore.shared

    var body: some View {
        AgentToolsInspectorShell {
            if let provider = store.selectedUsageProvider {
                selectedProvider(provider)
            } else {
                defaultState
            }
        }
    }

    private var defaultState: some View {
        VStack(alignment: .leading, spacing: 12) {
            AgentToolsSection(L("用量概览")) {
                AgentToolsInfoRow(label: L("全部渠道"), value: "\(UsageProviderCatalog.all.count)")
                AgentToolsInfoRow(label: L("已取数"), value: "\(loadedCount)")
                AgentToolsInfoRow(label: L("待刷新"), value: "\(manualCount)")
                AgentToolsInfoRow(label: L("本地用量"), value: store.usageReport.map { UsageFormatting.agoText($0.generatedAt) } ?? L("未扫描"))
            }

            Text(L("选择一个渠道查看账号、套餐、刷新状态和诊断信息。"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineSpacing(3)
        }
    }

    private func selectedProvider(_ provider: UsageProviderEntry) -> some View {
        let state = store.usageState(for: provider)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentToolsUsageProviderLogo(provider: provider)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.name)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(AppStyle.textPrimary)
                        .lineLimit(1)
                    Text(provider.id)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppStyle.textTertiary)
                        .lineLimit(1)
                }
            }

            AgentToolsSection(L("基础信息")) {
                AgentToolsInfoRow(label: L("状态"), value: statusLabel(state))
                AgentToolsInfoRow(label: L("凭证"), value: credentialLabel(state))
                AgentToolsInfoRow(label: L("本地 CLI"), value: cliLabel(provider))
                AgentToolsInfoRow(label: L("更新"), value: updatedLabel(state))
            }

            if case let .loaded(snapshot) = state {
                let windows = visibleUsageWindows(snapshot, provider: provider)
                AgentToolsSection(L("账号")) {
                    AgentToolsInfoRow(label: L("账号"), value: displayAccount(snapshot.accountLabel))
                    AgentToolsInfoRow(label: L("套餐"), value: snapshot.planName ?? "-")
                    AgentToolsInfoRow(label: L("窗口"), value: L("%ld 个", windows.count))
                    if optionalCreditsAndExtraUsageVisible, let cost = snapshot.providerCost {
                        AgentToolsInfoRow(label: L("成本"), value: AgentToolsUsageFormatting.costText(cost))
                    }
                    if optionalCreditsAndExtraUsageVisible, let ampUsage = snapshot.ampUsage, !ampUsage.isEmpty {
                        AgentToolsInfoRow(label: L("余额明细"), value: ampUsageSummary(ampUsage))
                    }
                    if provider.id == "codex", optionalCreditsAndExtraUsageVisible {
                        AgentToolsInfoRow(
                            label: L("重置券"),
                            value: CodexResetCreditsDisplay.countText(snapshot.codexResetCredits))
                    }
                }
                if optionalCreditsAndExtraUsageVisible, let ampUsage = snapshot.ampUsage, !ampUsage.isEmpty {
                    AgentToolsSection(L("余额明细")) {
                        if let individualCredits = ampUsage.individualCredits {
                            AgentToolsInfoRow(label: L("个人 Credits"), value: CostLine.money(individualCredits, "USD"))
                        }
                        ForEach(Array(ampUsage.workspaceBalances.enumerated()), id: \.offset) { _, workspace in
                            AgentToolsInfoRow(
                                label: "\(L("工作区")) \(workspace.name)",
                                value: CostLine.money(workspace.remaining, "USD"))
                        }
                    }
                }
                if !windows.isEmpty {
                    AgentToolsSection(L("额度窗口")) {
                        ForEach(windows.prefix(4), id: \.title) { item in
                            usageWindowRow(item.title, item.window, providerID: provider.id, snapshot: snapshot)
                        }
                    }
                }
                if provider.id == "codex",
                   optionalCreditsAndExtraUsageVisible,
                   let resetCredits = snapshot.codexResetCredits
                {
                    AgentToolsSection(L("限额重置券")) {
                        CodexResetCreditsInlineView(snapshot: resetCredits, compact: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ToolActionButton(
                    title: L("刷新这个渠道用量"),
                    systemImage: "arrow.clockwise",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        store.refreshProvider(provider)
                    }

                ToolActionButton(
                    title: L("复制渠道 ID"),
                    systemImage: "doc.on.doc",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        store.copyText(provider.id)
                    }

                ToolActionButton(
                    title: L("复制诊断信息"),
                    systemImage: "doc.text",
                    height: 28,
                    fontSize: 11,
                    horizontalPadding: 10) {
                        store.copyDiagnostics(for: provider)
                    }
            }
        }
    }

    private func ampUsageSummary(_ usage: AmpUsageDetails) -> String {
        var parts: [String] = []
        if let individualCredits = usage.individualCredits {
            parts.append(CostLine.money(individualCredits, "USD"))
        }
        if !usage.workspaceBalances.isEmpty {
            parts.append(L("%ld 个工作区", usage.workspaceBalances.count))
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " · ")
    }

    private var loadedCount: Int {
        UsageProviderCatalog.orderedEntries(config: configStore.config).filter {
            if case .loaded = store.usageState(for: $0) { return true }
            return false
        }.count
    }

    private var manualCount: Int {
        UsageProviderCatalog.orderedEntries(config: configStore.config).filter {
            if case .manual = store.usageState(for: $0) { return true }
            return false
        }.count
    }

    private func usageWindowRow(
        _ title: String,
        _ window: RateWindow,
        providerID: String,
        snapshot: UsageSnapshot)
        -> some View
    {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(AppStyle.textSecondary)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(statusColor(forPercent: window.usedPercent))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppStyle.hoverFill)
                    Capsule()
                        .fill(statusColor(forPercent: window.usedPercent))
                        .frame(width: max(4, proxy.size.width * CGFloat(window.usedPercent / 100)))
                    AgentToolsWorkDayMarkers(
                        workDays: configStore.config.usage.weeklyProgressWorkDays,
                        windowMinutes: window.windowMinutes,
                        width: proxy.size.width,
                        height: 8)
                }
            }
            .frame(height: 6)
            Text(resetLabel(window))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(AppStyle.textTertiary)
                .lineLimit(1)
            if let pace = history.paceSummary(
                providerID: providerID,
                window: window,
                snapshot: snapshot,
                config: configStore.config) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(paceColor(pace))
                    Text(pace.detail)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(paceColor(pace))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("用量节奏"))
                .accessibilityValue(pace.detail)
            }
        }
    }

    private func statusLabel(_ state: ToolUsageState?) -> String {
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

    private func credentialLabel(_ state: ToolUsageState?) -> String {
        switch state {
        case .loaded, .manual, .loading: return L("已配置")
        case .unconfigured: return L("未配置")
        case .error: return L("异常")
        case .unsupported: return L("不支持")
        case .none: return L("未知")
        }
    }

    private func cliLabel(_ provider: UsageProviderEntry) -> String {
        guard let tool = store.cliTools.first(where: { $0.id == provider.id }) else { return "-" }
        return tool.version ?? (tool.isInstalled ? L("已安装") : L("未安装"))
    }

    private func updatedLabel(_ state: ToolUsageState?) -> String {
        if case let .loaded(snapshot) = state { return UsageFormatting.agoText(snapshot.updatedAt) }
        if case .manual = state { return L("待刷新") }
        if case .loading = state { return L("刷新中") }
        return L("未获取")
    }

    private func statusColor(forPercent percent: Double) -> Color {
        if percent >= 90 { return AppStyle.errorRed }
        if percent >= 70 { return AppStyle.waitAmber }
        return AppStyle.doneGreen
    }

    private func resetLabel(_ window: RateWindow) -> String {
        if let description = window.resetDescription, !description.isEmpty { return description }
        if let resetsAt = window.resetsAt {
            return UsageFormatting.resetText(
                resetsAt,
                showAbsolute: configStore.config.usage.resetTimesShowAbsolute)
        }
        if let minutes = window.windowMinutes { return L("%ld 分钟窗口", minutes) }
        return L("无固定周期")
    }

    private var optionalCreditsAndExtraUsageVisible: Bool {
        configStore.config.usage.showOptionalCreditsAndExtraUsage
    }

    private func displayAccount(_ account: String?) -> String {
        let redacted = UsagePersonalInfoRedactor.redactEmails(
            in: account,
            isEnabled: configStore.config.usage.hidePersonalInfo)
        return redacted?.isEmpty == false ? redacted! : "-"
    }

    private func visibleUsageWindows(
        _ snapshot: UsageSnapshot,
        provider: UsageProviderEntry)
        -> [(title: String, window: RateWindow)]
    {
        let metadata = provider.displayMetadata
        var windows: [(title: String, window: RateWindow)] = []
        if let primary = snapshot.primary { windows.append((primary.title ?? metadata.sessionLabel, primary)) }
        if let secondary = snapshot.secondary { windows.append((secondary.title ?? metadata.weeklyLabel, secondary)) }
        if let tertiary = snapshot.tertiary { windows.append((tertiary.title ?? metadata.opusLabel ?? L("其它"), tertiary)) }
        if optionalCreditsAndExtraUsageVisible {
            windows.append(contentsOf: snapshot.extraRateWindows.map { ($0.title, $0.window) })
        }
        return windows
    }

    private func paceColor(_ pace: UsagePaceSummary) -> Color {
        if pace.isDeficit {
            return abs(pace.deltaPercent) >= 12 ? AppStyle.errorRed : AppStyle.waitAmber
        }
        if pace.isReserve { return AppStyle.doneGreen }
        return AppStyle.textTertiary
    }
}

private struct AgentToolsUsageProviderLogo: View {
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

private enum AgentToolsUsageFormatting {
    static func costText(_ cost: ProviderCostSnapshot) -> String {
        if cost.hasLimit {
            return "\(money(cost.used, cost.currencyCode)) / \(money(cost.limit, cost.currencyCode))"
        }
        return money(cost.used, cost.currencyCode)
    }

    private static func money(_ value: Double, _ currencyCode: String) -> String {
        let symbol: String
        switch currencyCode.uppercased() {
        case "USD": symbol = "$"
        case "CNY", "RMB": symbol = "¥"
        case "EUR": symbol = "€"
        case "GBP": symbol = "£"
        default: symbol = currencyCode + " "
        }
        return "\(symbol)\(String(format: "%.2f", value))"
    }
}
