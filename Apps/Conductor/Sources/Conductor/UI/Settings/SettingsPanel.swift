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
    @Namespace private var settingsSelectionNamespace
    @Environment(\.conductorTheme) var theme
    @Environment(\.conductorFontScale) var fontScale

    private var panelCornerRadius: CGFloat { 12 }
    private var panelBase: Color { theme.floatingPanelBase }
    private var panelWash: Color { theme.floatingPanelWash.opacity(theme.usesDarkChrome ? 0.14 : 0.18) }
    private var sidebarBase: Color { theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.20 : 0.28) }
    private var separatorColor: Color { theme.floatingSeparator.opacity(theme.usesDarkChrome ? 0.66 : 0.48) }

    var body: some View {
        let snapshot = SettingsSnapshot(
            selectedSection: selectedSection,
            theme: model.theme,
            appearance: model.appearance,
            agentHookSettingsMessage: model.agentHookSettingsMessage,
            agentCLIStatuses: model.agentCLIStatuses,
            terminalFontDownloadStates: model.terminalFontDownloadStates,
            updatePreferences: model.updatePreferences,
            updateState: model.updateState
        )
        return ZStack {
            VStack(spacing: 0) {
                settingsHeader(snapshot: snapshot)

                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 1)

                HStack(spacing: 0) {
                    sidebar(snapshot: snapshot)

                    Rectangle()
                        .fill(separatorColor)
                        .frame(width: 1)

                    contentPane(snapshot: snapshot)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .fill(panelBase)
                    .overlay {
                        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                            .fill(panelWash)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                    .stroke(separatorColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.36 : 0.18), radius: 28, y: 18)
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
                Image(systemName: "xmark")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.secondaryText)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel(L("关闭设置", "Close Settings"))
            .macNativeTooltip(L("关闭设置", "Close Settings"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 48)
        .background(panelBase.opacity(theme.usesDarkChrome ? 0.94 : 0.88))
    }

    private func sidebar(snapshot: SettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sidebarGroup(
                title: L("常用", "General"),
                sections: [.overview, .interface, .terminal]
            )

            sidebarGroup(
                title: L("工作流", "Workflow"),
                sections: [.shell, .usage, .automation, .updates, .commands]
            )

            sidebarGroup(
                title: L("外观", "Look"),
                sections: [.themes]
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 174)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBase)
    }

    private func sidebarGroup(title: String, sections: [SettingsSectionID]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(ConductorDesign.tertiaryText)
                .padding(.horizontal, 8)
                .padding(.bottom, 1)

            VStack(spacing: 1) {
                ForEach(sections) { section in
                    SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section
                    ) {
                        selectSection(section)
                    }
                }
            }
        }
    }

    private func contentPane(snapshot: SettingsSnapshot) -> some View {
        ZStack {
            panelBase
                .overlay(panelWash.opacity(0.45))

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
