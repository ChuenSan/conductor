import CodexBarCore
import SwiftUI

@MainActor
struct ConductorUsageSettingsContext {
    let settings: SettingsStore
    let store: UsageStore
    let managedCodexAccountCoordinator: ManagedCodexAccountCoordinator
    let codexAccountPromotionCoordinator: CodexAccountPromotionCoordinator
    let runProviderLoginFlow: @MainActor (UsageProvider) async -> Void
}

public struct ConductorUsageSettingsContent: View {
    private let style: ConductorUsagePanelStyle
    private let languageIdentifier: String?

    public init(
        style: ConductorUsagePanelStyle = .fallback,
        languageIdentifier: String? = nil)
    {
        self.style = style
        self.languageIdentifier = languageIdentifier
    }

    public var body: some View {
        let resolvedLanguageIdentifier = languageIdentifier ?? ConductorUsageFeature.currentHostLanguageIdentifier
        if let context = CodexBarEmbeddedRuntime.shared.conductorUsageSettingsContext() {
            ConductorUsageSettingsLoadedContent(
                context: context,
                style: style,
                languageIdentifier: resolvedLanguageIdentifier)
        } else {
            ConductorUsageSettingsUnavailableView(style: style, languageIdentifier: resolvedLanguageIdentifier)
        }
    }
}

@MainActor
private struct ConductorUsageSettingsLoadedContent: View {
    private static let hiddenProviderSettingIDs: Set<String> = [
        "codex-openai-web-battery-saver",
    ]

    let context: ConductorUsageSettingsContext
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    @State private var selection: ConductorUsageSettingsTab = .providers
    @State private var detailsReady = false

    private var availableTabs: [ConductorUsageSettingsTab] {
        var tabs: [ConductorUsageSettingsTab] = [.providers, .workbench, .general, .display, .advanced]
        if context.settings.debugMenuEnabled {
            tabs.append(.debug)
        }
        return tabs
    }

    private var languageSyncKey: String {
        languageIdentifier ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConductorUsageSettingsSummaryStrip(
                context: context,
                style: style,
                languageIdentifier: languageIdentifier,
                openWorkbench: {
                    selection = .workbench
                })

            tabBar

            Rectangle()
                .fill(style.separator.opacity(0.72))
                .frame(height: 1)

            content
                .id(languageSyncKey)
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .background(style.panelBase.opacity(style.usesDarkChrome ? 0.18 : 0.38))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(style.stroke.opacity(0.26), lineWidth: 0.8)
                }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, style.colorScheme)
        .preferredColorScheme(style.colorScheme)
        .tint(style.emphasis)
        .accentColor(style.emphasis)
        .onAppear {
            syncLanguage()
            normalizeSelection()
        }
        .task(id: languageSyncKey) {
            detailsReady = false
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            detailsReady = true
        }
        .onChange(of: languageSyncKey) { _, _ in
            syncLanguage()
        }
        .onChange(of: context.settings.debugMenuEnabled) { _, _ in
            normalizeSelection()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(availableTabs) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10.5, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(tab.title(languageIdentifier: languageIdentifier))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == tab ? style.primaryText : style.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(selection == tab ? style.controlStrongFill.opacity(0.64) : style.controlFill.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selection == tab ? style.emphasis.opacity(0.20) : Color.clear, lineWidth: 0.8)
                    }
                    .overlay(alignment: .leading) {
                        if selection == tab {
                            Capsule()
                                .fill(style.emphasis.opacity(0.42))
                                .frame(width: 3, height: 14)
                                .padding(.leading, 3)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !detailsReady {
            ConductorUsageSettingsContentPlaceholder(style: style)
        } else {
            switch selection {
            case .providers:
                ProvidersPane(
                    settings: context.settings,
                    store: context.store,
                    managedCodexAccountCoordinator: context.managedCodexAccountCoordinator,
                    codexAccountPromotionCoordinator: context.codexAccountPromotionCoordinator,
                    showsMenuBarMetricPicker: false,
                    hiddenProviderSettingIDs: Self.hiddenProviderSettingIDs,
                    allowsNestedScrolling: false,
                    runProviderLoginFlow: context.runProviderLoginFlow)
                    .padding(10)
            case .workbench:
                ConductorUsageWorkbenchPanel(
                    context: context,
                    style: style,
                    languageIdentifier: languageIdentifier)
                    .padding(10)
            case .general:
                GeneralPane(
                    settings: context.settings,
                    store: context.store,
                    showsLanguageControls: false,
                    showsStartupControls: false,
                    showsAppLifecycleControls: false)
            case .display:
                DisplayPane(
                    settings: context.settings,
                    store: context.store,
                    showsMenuBarControls: false)
            case .advanced:
                AdvancedPane(
                    settings: context.settings,
                    showsKeyboardShortcutControls: false,
                    showsMenuEffectControls: false)
            case .debug:
                DebugPane(settings: context.settings, store: context.store)
            }
        }
    }

    private func syncLanguage() {
        if context.settings.appLanguage != languageSyncKey {
            context.settings.appLanguage = languageSyncKey
        }
    }

    private func normalizeSelection() {
        guard !availableTabs.contains(selection) else { return }
        selection = availableTabs.first ?? .providers
    }
}

@MainActor
private struct ConductorUsageSettingsSummaryStrip: View {
    private static let tokenRecordProviders: [UsageProvider] = [.codex, .claude, .vertexai, .bedrock]

    let context: ConductorUsageSettingsContext
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?
    let openWorkbench: () -> Void
    @State private var refreshInFlight = false

    private var summary: Summary {
        _ = context.settings.menuObservationToken
        _ = context.store.menuObservationToken

        let providers = context.store.enabledProvidersForDisplay()
        let tokenCount = Self.tokenRecordProviders.filter { provider in
            context.store.tokenSnapshot(for: provider) != nil
        }.count
        let issueCount = UsageProvider.allCases.filter { provider in
            context.store.error(for: provider) != nil || context.store.tokenError(for: provider) != nil
        }.count
        let storageBytes = providers.compactMap { provider in
            context.store.storageFootprint(for: provider)?.totalBytes
        }.reduce(Int64(0), +)
        let isRefreshing = context.store.isRefreshing ||
            Self.tokenRecordProviders.contains { context.store.isTokenRefreshInFlight(for: $0) }

        return Summary(
            providerCount: providers.count,
            tokenCount: tokenCount,
            issueCount: issueCount,
            storageBytes: storageBytes,
            isRefreshing: isRefreshing)
    }

    var body: some View {
        let summary = summary

        HStack(spacing: 8) {
            Image(systemName: summary.systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(summary.issueCount > 0 ? Color.orange : style.emphasis)
                .frame(width: 24, height: 24)
                .background(style.controlFill.opacity(0.48))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.title(languageIdentifier: languageIdentifier))
                    .font(.system(size: 12.4, weight: .semibold))
                    .foregroundStyle(style.primaryText)
                    .lineLimit(1)
                Text(summary.subtitle(languageIdentifier: languageIdentifier))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(style.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            metricPill(
                title: conductorTokenRecordsText("服务", "Services", languageIdentifier: languageIdentifier),
                value: "\(summary.providerCount)")

            metricPill(
                title: "Token",
                value: "\(summary.tokenCount)")

            Button {
                openWorkbench()
            } label: {
                Label(
                    conductorTokenRecordsText("工作台", "Workbench", languageIdentifier: languageIdentifier),
                    systemImage: "rectangle.stack")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.2, weight: .semibold))
            .foregroundStyle(style.secondaryText)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(style.controlFill.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Button {
                refreshAll()
            } label: {
                Image(systemName: refreshInFlight || summary.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 10.2, weight: .semibold))
                    .foregroundStyle(style.secondaryText)
                    .frame(width: 24, height: 24)
                    .background(style.controlFill.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(refreshInFlight || summary.isRefreshing)
            .help(conductorTokenRecordsText("刷新用量", "Refresh usage", languageIdentifier: languageIdentifier))
            .accessibilityLabel(conductorTokenRecordsText("刷新用量", "Refresh usage", languageIdentifier: languageIdentifier))
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(style.panelBase.opacity(style.usesDarkChrome ? 0.18 : 0.34))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(style.stroke.opacity(0.22), lineWidth: 0.8)
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(style.tertiaryText)
            Text(value)
                .foregroundStyle(style.secondaryText)
                .monospacedDigit()
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(style.controlFill.opacity(0.34))
        .clipShape(Capsule())
    }

    private func refreshAll() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        Task { @MainActor in
            await ProviderInteractionContext.$current.withValue(.userInitiated) {
                await context.store.refresh(forceTokenUsage: true)
            }
            context.store.scheduleStorageFootprintRefreshForOverview(force: true)
            refreshInFlight = false
        }
    }

    private struct Summary {
        let providerCount: Int
        let tokenCount: Int
        let issueCount: Int
        let storageBytes: Int64
        let isRefreshing: Bool

        var systemImage: String {
            if isRefreshing { return "arrow.triangle.2.circlepath" }
            if issueCount > 0 { return "exclamationmark.triangle" }
            return "chart.bar.doc.horizontal"
        }

        func title(languageIdentifier: String?) -> String {
            if isRefreshing {
                return conductorTokenRecordsText("正在同步用量", "Syncing usage", languageIdentifier: languageIdentifier)
            }
            if issueCount > 0 {
                return conductorTokenRecordsText("\(issueCount) 项需处理", "\(issueCount) need attention", languageIdentifier: languageIdentifier)
            }
            return conductorTokenRecordsText("用量已就绪", "Usage ready", languageIdentifier: languageIdentifier)
        }

        func subtitle(languageIdentifier: String?) -> String {
            let storage = storageBytes > 0 ? UsageFormatter.byteCountString(storageBytes) : nil
            if let storage {
                return conductorTokenRecordsText(
                    "\(providerCount) 个服务 · \(tokenCount) 个记录源 · 本地 \(storage)",
                    "\(providerCount) services · \(tokenCount) record sources · \(storage) local",
                    languageIdentifier: languageIdentifier)
            }
            return conductorTokenRecordsText(
                "\(providerCount) 个服务 · \(tokenCount) 个记录源",
                "\(providerCount) services · \(tokenCount) record sources",
                languageIdentifier: languageIdentifier)
        }
    }
}

private struct ConductorUsageSettingsContentPlaceholder: View {
    let style: ConductorUsagePanelStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(style.controlFill.opacity(index == 0 ? 0.38 : 0.24))
                    .frame(height: index == 0 ? 34 : 28)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
    }
}

private struct ConductorUsageSettingsUnavailableView: View {
    let style: ConductorUsagePanelStyle
    let languageIdentifier: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(style.emphasis)
            Text(conductorTokenRecordsText(
                "用量服务未启动",
                "Usage service is not running",
                languageIdentifier: languageIdentifier))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.primaryText)
            Text(conductorTokenRecordsText(
                "请稍后再试。",
                "Please try again shortly.",
                languageIdentifier: languageIdentifier))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(style.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(style.controlFill.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .environment(\.colorScheme, style.colorScheme)
        .preferredColorScheme(style.colorScheme)
        .tint(style.emphasis)
        .accentColor(style.emphasis)
    }
}

private enum ConductorUsageSettingsTab: String, CaseIterable, Identifiable {
    case providers
    case workbench
    case general
    case display
    case advanced
    case debug

    var id: String { rawValue }

    func title(languageIdentifier: String?) -> String {
        switch self {
        case .providers:
            conductorTokenRecordsText("服务", "Providers", languageIdentifier: languageIdentifier)
        case .workbench:
            conductorTokenRecordsText("工作台", "Workbench", languageIdentifier: languageIdentifier)
        case .general:
            conductorTokenRecordsText("常规", "General", languageIdentifier: languageIdentifier)
        case .display:
            conductorTokenRecordsText("显示", "Display", languageIdentifier: languageIdentifier)
        case .advanced:
            conductorTokenRecordsText("高级", "Advanced", languageIdentifier: languageIdentifier)
        case .debug:
            conductorTokenRecordsText("调试", "Debug", languageIdentifier: languageIdentifier)
        }
    }

    var systemImage: String {
        switch self {
        case .providers:
            "square.grid.2x2"
        case .workbench:
            "rectangle.stack"
        case .general:
            "gearshape"
        case .display:
            "eye"
        case .advanced:
            "slider.horizontal.3"
        case .debug:
            "ladybug"
        }
    }
}
