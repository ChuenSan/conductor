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
            terminalFontDownloadStates: model.terminalFontDownloadStates
        )
        return ZStack {
            ConductorGlassSurface(style: .panel, clarity: snapshot.appearance.chromeClarity, interactive: true) {
                VStack(spacing: 0) {
                    FloatingPanelHeader(
                        systemImage: "gearshape",
                        title: L("设置", "Settings"),
                        subtitle: snapshot.theme.title,
                        closeHelp: L("关闭设置", "Close Settings")
                    ) {
                        model.hideSettingsPanel()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    FloatingPanelDivider()
                        .padding(.horizontal, 14)

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
            .overlay {
                RoundedRectangle(cornerRadius: ConductorDesign.sidebarCornerRadius, style: .continuous)
                    .stroke(theme.floatingStroke.opacity(0.82), lineWidth: 0.8)
                    .allowsHitTesting(false)
            }
            .frame(width: 1080, height: 650)
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
        VStack(alignment: .leading, spacing: 12) {
            SettingsSidebarSummary(theme: snapshot.theme, appearance: snapshot.appearance)

            sidebarGroup(
                title: L("常用", "General"),
                sections: [.overview, .interface, .terminal]
            )

            sidebarGroup(
                title: L("工作流", "Workflow"),
                sections: [.shell, .usage, .automation, .commands]
            )

            sidebarGroup(
                title: L("外观", "Look"),
                sections: [.themes]
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(theme.floatingControlFill.opacity(0.18))
    }

    private func sidebarGroup(title: String, sections: [SettingsSectionID]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SidebarSectionTitle(title)

            VStack(spacing: 3) {
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
            theme.floatingControlFill.opacity(0.06)

            if selectedSection == .usage {
                VStack(alignment: .leading, spacing: 18) {
                    detailContent(snapshot: snapshot)
                        .id(selectedSection)
                        .transition(ConductorMotion.contentSwapTransition(edge: settingsContentEdge))
                }
                .frame(maxWidth: 820, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .animation(ConductorMotion.contentSwap, value: selectedSection)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        detailContent(snapshot: snapshot)
                            .id(selectedSection)
                            .transition(ConductorMotion.contentSwapTransition(edge: settingsContentEdge))
                    }
                    .frame(maxWidth: 660, alignment: .topLeading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .animation(ConductorMotion.contentSwap, value: selectedSection)
                }
                .scrollIndicators(.visible)
            }
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
