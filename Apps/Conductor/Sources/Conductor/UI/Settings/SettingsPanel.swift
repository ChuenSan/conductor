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
    @State var selectedTerminalSettingsSection: TerminalSettingsSection = .typography
    @State var recordingShortcutCommand: ConductorShellCommand?
    @State private var settingsContentEdge: Edge = .trailing
    @State var terminalContentEdge: Edge = .trailing
    @Namespace private var settingsSelectionNamespace
    @Environment(\.conductorTheme) var theme
    @Environment(\.conductorFontScale) var fontScale

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
            ConductorGlassSurface(style: .settings, clarity: snapshot.appearance.chromeClarity, interactive: true) {
                VStack(spacing: 0) {
                    FloatingPanelHeader(
                        systemImage: snapshot.selectedSection.systemImage,
                        title: L("设置", "Settings"),
                        subtitle: snapshot.selectedSection.title,
                        closeHelp: L("关闭设置", "Close Settings"),
                        onClose: {
                            model.hideSettingsPanel()
                        })
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)

                    FloatingPanelDivider()
                        .padding(.horizontal, 10)

                    HStack(spacing: 0) {
                        sidebar(snapshot: snapshot)

                        Rectangle()
                            .fill(theme.floatingSeparator)
                            .frame(width: 1)
                            .padding(.vertical, 14)

                        contentPane(snapshot: snapshot)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous)
                    .fill(theme.floatingPanelWash.opacity(theme.usesDarkChrome ? 0.04 : 0.10))
            }
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

    private func sidebar(snapshot: SettingsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(width: 168)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background {
            theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.14 : 0.18)
        }
    }

    private func sidebarGroup(title: String, sections: [SettingsSectionID]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SidebarSectionTitle(title)

            VStack(spacing: 1) {
                ForEach(sections) { section in
                    SettingsSidebarItem(
                        section: section,
                        selected: selectedSection == section,
                        selectionNamespace: settingsSelectionNamespace
                    ) {
                        selectSection(section)
                    }
                }
            }
        }
    }

    private func contentPane(snapshot: SettingsSnapshot) -> some View {
        ZStack {
            theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.055 : 0.075)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    detailContent(snapshot: snapshot)
                        .id(selectedSection)
                        .transition(ConductorMotion.contentSwapTransition(edge: settingsContentEdge))
                }
                .frame(maxWidth: selectedSection == .usage || selectedSection == .updates ? 600 : 580, alignment: .topLeading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .animation(ConductorMotion.contentSwap, value: selectedSection)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailContent(snapshot: SettingsSnapshot) -> some View {
        SettingsPaneHeading(section: snapshot.selectedSection)
        selectedSectionBody(snapshot: snapshot)
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
        settingsContentEdge = contentSwapEdge(
            from: selectedSection,
            to: section,
            in: SettingsSectionID.allCases
        )
        ConductorMotion.perform(ConductorMotion.contentSwap) {
            selectedSection = section
        }
    }

    private func applyRequestedSettingsSection(_ section: SettingsSectionID?) {
        guard let section else { return }
        selectSection(section)
        model.requestedSettingsSection = nil
    }
}
