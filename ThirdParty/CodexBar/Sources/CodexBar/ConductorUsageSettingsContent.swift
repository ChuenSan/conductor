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

    private var availableTabs: [ConductorUsageSettingsTab] {
        var tabs: [ConductorUsageSettingsTab] = [.providers, .general, .display, .advanced]
        if context.settings.debugMenuEnabled {
            tabs.append(.debug)
        }
        return tabs
    }

    private var languageSyncKey: String {
        languageIdentifier ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabBar

            Rectangle()
                .fill(style.separator.opacity(0.72))
                .frame(height: 1)

            content
                .id(languageSyncKey)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(style.controlFill.opacity(style.usesDarkChrome ? 0.20 : 0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(style.stroke.opacity(0.42), lineWidth: 0.8)
                }
        }
        .frame(maxWidth: .infinity, minHeight: 468, alignment: .topLeading)
        .environment(\.colorScheme, style.colorScheme)
        .preferredColorScheme(style.colorScheme)
        .tint(style.emphasis)
        .accentColor(style.emphasis)
        .onAppear {
            syncLanguage()
            normalizeSelection()
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
                    .foregroundStyle(selection == tab ? style.emphasis : style.secondaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(selection == tab ? style.controlStrongFill : style.controlFill.opacity(0.42))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selection == tab ? style.stroke.opacity(0.58) : Color.clear, lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .providers:
            ProvidersPane(
                settings: context.settings,
                store: context.store,
                managedCodexAccountCoordinator: context.managedCodexAccountCoordinator,
                codexAccountPromotionCoordinator: context.codexAccountPromotionCoordinator,
                showsMenuBarMetricPicker: false,
                hiddenProviderSettingIDs: Self.hiddenProviderSettingIDs,
                runProviderLoginFlow: context.runProviderLoginFlow)
                .padding(12)
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
    case general
    case display
    case advanced
    case debug

    var id: String { rawValue }

    func title(languageIdentifier: String?) -> String {
        switch self {
        case .providers:
            conductorTokenRecordsText("服务", "Providers", languageIdentifier: languageIdentifier)
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
