import ConductorCore
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct SettingsUpdateSection: View {
    let preferences: ConductorUpdatePreferences
    let state: ConductorUpdateState
    let setManifestURL: @MainActor (String) -> Void
    let setAutomaticChecksEnabled: @MainActor (Bool) -> Void
    let setPrefersDeltaUpdates: @MainActor (Bool) -> Void
    let checkForUpdates: @MainActor () -> Void
    let downloadUpdate: @MainActor () -> Void
    let installUpdate: @MainActor () -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            UpdateStatusCard(
                preferences: preferences,
                state: state,
                checkForUpdates: checkForUpdates,
                downloadUpdate: downloadUpdate,
                installUpdate: installUpdate
            )

            SettingsPreferenceGroup(title: L("偏好", "Preferences")) {
                SettingsFormSurface {
                    SettingsToggleRow(
                        title: L("自动检查更新", "Automatically Check for Updates"),
                        subtitle: L("启动后在后台检查；没有更新时不打扰", "Checks quietly after launch and stays silent when current"),
                        isOn: Binding(
                            get: { preferences.automaticChecksEnabled },
                            set: { value in setAutomaticChecksEnabled(value) }
                        )
                    )
                }
            }
        }
    }
}

private struct UpdateStatusCard: View {
    let preferences: ConductorUpdatePreferences
    let state: ConductorUpdateState
    let checkForUpdates: @MainActor () -> Void
    let downloadUpdate: @MainActor () -> Void
    let installUpdate: @MainActor () -> Void
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: state.phase.systemImage)
                    .font(.conductorSystem(size: 16, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .frame(width: 38, height: 38)
                    .background(theme.floatingControlStrongFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.phase.statusTitle)
                        .font(.conductorSystem(size: 15, weight: .bold, scale: fontScale))
                        .foregroundStyle(ConductorDesign.primaryText)
                        .lineLimit(1)

                    Text(statusDetail)
                        .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if state.phase.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 24)
                }
            }

            HStack(spacing: 10) {
                Text(L("当前版本", "Current Version"))
                    .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)

                Text(state.currentVersion.displayText)
                    .font(.conductorSystem(size: 10.5, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)

                if let lastCheckedAt = state.lastCheckedAt {
                    Text("·")
                        .foregroundStyle(ConductorDesign.tertiaryText.opacity(0.7))
                    Text(lastCheckedAt, style: .relative)
                        .font(.conductorSystem(size: 10, weight: .medium, scale: fontScale))
                        .foregroundStyle(ConductorDesign.tertiaryText)
                }

                Spacer(minLength: 0)
            }

            UpdateActionRow(
                state: state,
                hasManifestURL: preferences.manifestURL != nil,
                checkForUpdates: checkForUpdates,
                downloadUpdate: downloadUpdate,
                installUpdate: installUpdate
            )
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.18 : 0.24))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.32), lineWidth: 0.8)
        }
    }

    private var statusDetail: String {
        switch state.phase {
        case .idle:
            return preferences.manifestURL == nil
                ? L("暂时无法连接更新服务。", "The update service is currently unavailable.")
                : L("可以手动检查新版本。", "You can check for a new version.")
        case .checking:
            return L("正在联系更新服务。", "Contacting the update service.")
        case .upToDate:
            return L("你正在使用最新版本。", "You are using the latest version.")
        case .available:
            return L("新版本已准备好，可以下载并安装。", "A new version is ready to download and install.")
        case .downloading:
            return L("正在下载更新。", "Downloading the update.")
        case .downloaded:
            return L("更新已下载，安装后会自动重新打开。", "The update is downloaded and will reopen after installation.")
        case .installing:
            return L("正在安装更新。", "Installing the update.")
        case .failed:
            return L("无法完成更新检查，请稍后再试。", "Could not complete the update check. Please try again later.")
        }
    }
}

private struct UpdateActionRow: View {
    let state: ConductorUpdateState
    let hasManifestURL: Bool
    let checkForUpdates: @MainActor () -> Void
    let downloadUpdate: @MainActor () -> Void
    let installUpdate: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 8) {
            UpdateActionButton(
                title: primaryTitle,
                systemImage: primarySystemImage,
                tooltip: primaryTooltip,
                prominent: state.phase == .available || state.phase == .downloaded,
                disabled: primaryDisabled,
                action: primaryAction
            )
        }
        .frame(height: 36)
    }

    private var primaryTitle: String {
        switch state.phase {
        case .available:
            L("下载更新", "Download Update")
        case .downloaded:
            L("安装并重新打开", "Install and Reopen")
        case .downloading:
            L("正在下载", "Downloading")
        case .installing:
            L("正在安装", "Installing")
        default:
            L("检查更新", "Check for Updates")
        }
    }

    private var primarySystemImage: String {
        switch state.phase {
        case .available:
            "arrow.down.circle"
        case .downloaded:
            "arrow.triangle.2.circlepath.circle"
        case .downloading:
            "icloud.and.arrow.down"
        case .installing:
            "arrow.clockwise.circle"
        default:
            "arrow.clockwise"
        }
    }

    private var primaryTooltip: String {
        switch state.phase {
        case .available:
            L("下载并准备新版本", "Download and prepare the new version")
        case .downloaded:
            L("安装更新并重新打开 App", "Install the update and reopen the app")
        default:
            L("检查是否有新版本", "Check whether a new version is available")
        }
    }

    private var primaryDisabled: Bool {
        if !hasManifestURL { return true }
        switch state.phase {
        case .available:
            return !state.canDownload
        case .downloaded:
            return !state.canInstall
        default:
            return !state.canCheck
        }
    }

    @MainActor
    private func primaryAction() {
        switch state.phase {
        case .available:
            downloadUpdate()
        case .downloaded:
            installUpdate()
        default:
            checkForUpdates()
        }
    }
}

private struct UpdateActionButton: View {
    let title: String
    let systemImage: String
    let tooltip: String
    var prominent = false
    let disabled: Bool
    let action: @MainActor () -> Void
    @State private var hovering = false
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.conductorSystem(size: 10.6, weight: .bold, scale: fontScale))
                .foregroundStyle(disabled ? ConductorDesign.tertiaryText : theme.floatingEmphasis)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(buttonFill)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(theme.floatingStroke.opacity(disabled ? 0.18 : 0.42), lineWidth: 0.8)
                }
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
        .disabled(disabled)
        .macNativeTooltip(tooltip, enabled: !disabled)
        .conductorHover($hovering)
        .animation(ConductorMotion.hover, value: hovering)
    }

    private var buttonFill: Color {
        guard !disabled else {
            return theme.floatingControlFill.opacity(0.18)
        }
        if prominent {
            return hovering ? theme.accent.opacity(0.88) : theme.accent.opacity(0.76)
        }
        return hovering ? theme.floatingHoverFill.opacity(0.32) : theme.floatingControlStrongFill.opacity(0.92)
    }
}
