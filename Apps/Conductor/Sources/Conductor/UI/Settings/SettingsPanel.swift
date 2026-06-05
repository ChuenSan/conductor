import ConductorCore
import AppKit
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct AppearanceSettingsPanel: View {
    let model: ConductorWindowModel
    let commandShortcutRows: () -> [CommandShortcutGuideRowModel]
    @State private var selectedSection: SettingsSectionID = .overview
    @State private var renderedSection: SettingsSectionID? = .overview
    @State private var renderGeneration = 0
    @State var selectedTerminalSettingsSection: TerminalSettingsSection = .typography
    @State var recordingShortcutCommand: ConductorShellCommand?
    @State var shortcutRecordingMessage: String?
    @Namespace private var settingsSelectionNamespace
    @Environment(\.conductorTheme) var theme
    @Environment(\.conductorFontScale) var fontScale

    private var selectedSectionBinding: Binding<SettingsSectionID?> {
        Binding(
            get: { selectedSection },
            set: { section in
                guard let section else { return }
                selectSection(section)
            }
        )
    }

    var body: some View {
        let snapshot = SettingsSnapshot(
            selectedSection: selectedSection,
            theme: model.theme,
            appearance: model.appearance,
            agentHookSettingsMessage: model.agentHookSettingsMessage,
            notificationAuthorizationState: model.notificationAuthorizationState,
            notificationDeliveryTestMessage: model.notificationDeliveryTestMessage,
            agentCLIStatuses: model.agentCLIStatuses,
            terminalFontDownloadStates: model.terminalFontDownloadStates,
            updatePreferences: model.updatePreferences,
            updateState: model.updateState
        )
        return ZStack {
            VStack(spacing: 0) {
                settingsHeader(snapshot: snapshot)

                HStack(spacing: 0) {
                    sidebar(snapshot: snapshot)

                    contentPane(snapshot: snapshot)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.panel, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.panel, style: .continuous)
                    .fill(ConductorTokens.Settings.panelWash(dark: theme.usesDarkChrome))
            }
            .overlay {
                RoundedRectangle(cornerRadius: ConductorTokens.Radius.panel, style: .continuous)
                    .stroke(ConductorTokens.Settings.panelStroke(dark: theme.usesDarkChrome), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.panel, style: .continuous))
            .shadow(
                color: ConductorTokens.Settings.panelShadow(dark: theme.usesDarkChrome),
                radius: 28,
                y: 12
            )
            .frame(width: 860, height: 520)
            .onExitCommand {
                model.hideSettingsPanel()
            }
            .onAppear {
                applyRequestedSettingsSection(model.requestedSettingsSection)
            }
            .onChange(of: model.requestedSettingsSection) { _, section in
                applyRequestedSettingsSection(section)
            }
        }
    }

    private func settingsHeader(snapshot: SettingsSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("设置", "Settings"))
                        .font(.conductorSystem(size: 13.5, weight: .semibold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)
                    Text(snapshot.selectedSection.subtitle)
                        .font(.conductorSystem(size: 10.5, weight: .regular, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    model.hideSettingsPanel()
                } label: {
                    Label(L("关闭设置", "Close Settings"), systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(L("关闭设置", "Close Settings"))
                .help(L("关闭设置", "Close Settings"))
            }
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(height: 47)
        }
    }

    private func sidebar(snapshot: SettingsSnapshot) -> some View {
        List(selection: selectedSectionBinding) {
            Section(L("常用", "General")) {
                sidebarRows([.overview, .interface, .terminal])
            }

            Section(L("工作流", "Workflow")) {
                sidebarRows([.shell, .usage, .automation, .updates, .commands])
            }

            Section(L("外观", "Look")) {
                sidebarRows([.themes])
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .frame(width: 174)
    }

    @ViewBuilder
    private func sidebarRows(_ sections: [SettingsSectionID]) -> some View {
        ForEach(sections) { section in
            Label(section.title, systemImage: section.systemImage)
                .font(.conductorSystem(size: 12, weight: section == selectedSection ? .semibold : .medium, scale: fontScale))
                .foregroundStyle(section == selectedSection ? ConductorDesign.primaryText : ConductorDesign.secondaryText)
                .tag(section)
                .help(section.subtitle)
                .accessibilityLabel(section.title)
                .accessibilityHint(section.subtitle)
        }
    }

    @ViewBuilder
    private func contentPane(snapshot: SettingsSnapshot) -> some View {
        ZStack {
            Color.clear

            if selectedSection == .overview || selectedSection == .interface || selectedSection == .themes {
                VStack(alignment: .leading, spacing: 12) {
                    detailContent(snapshot: snapshot)
                }
                .frame(maxWidth: 600, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        detailContent(snapshot: snapshot)
                    }
                    .frame(maxWidth: selectedSection == .usage || selectedSection == .updates ? 620 : 600, alignment: .topLeading)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 18)
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailContent(snapshot: SettingsSnapshot) -> some View {
        SettingsPaneHeading(section: snapshot.selectedSection)
        if let renderedSection {
            let contentSnapshot = SettingsSnapshot(
                selectedSection: renderedSection,
                theme: snapshot.theme,
                appearance: snapshot.appearance,
                agentHookSettingsMessage: snapshot.agentHookSettingsMessage,
                notificationAuthorizationState: snapshot.notificationAuthorizationState,
                notificationDeliveryTestMessage: snapshot.notificationDeliveryTestMessage,
                agentCLIStatuses: snapshot.agentCLIStatuses,
                terminalFontDownloadStates: snapshot.terminalFontDownloadStates,
                updatePreferences: snapshot.updatePreferences,
                updateState: snapshot.updateState
            )
            selectedSectionBody(snapshot: contentSnapshot)
        } else {
            SettingsContentPlaceholder(section: snapshot.selectedSection)
        }
    }

    @ViewBuilder
    private func selectedSectionBody(snapshot: SettingsSnapshot) -> some View {
        switch snapshot.selectedSection {
        case .overview:
            overviewSettings(snapshot: snapshot)
        case .interface:
            interfaceSettings(snapshot: snapshot)
        case .terminal:
            terminalSettingsDashboard(snapshot: snapshot)
        case .shell:
            shellAndProxySettings(snapshot: snapshot)
        case .usage:
            usageSettings(snapshot: snapshot)
        case .automation:
            automationSettings(snapshot: snapshot)
        case .updates:
            updateSettings(snapshot: snapshot)
        case .commands:
            commandSettings()
        case .themes:
            themeSettings(snapshot: snapshot)
        }
    }

    func selectSection(_ section: SettingsSectionID) {
        guard selectedSection != section else { return }
        renderGeneration += 1
        let generation = renderGeneration
        ConductorMotion.withoutAnimation {
            selectedSection = section
            renderedSection = nil
        }
        Task { @MainActor in
            await Task.yield()
            guard generation == renderGeneration else { return }
            ConductorMotion.withoutAnimation {
                renderedSection = section
            }
        }
    }

    private func applyRequestedSettingsSection(_ section: SettingsSectionID?) {
        guard let section else { return }
        selectSection(section)
        model.requestedSettingsSection = nil
    }
}
