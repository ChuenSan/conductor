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
            UpdateStatusCard(state: state)

            SettingsPreferenceGroup(title: L("更新源", "Update Source")) {
                SettingsFormSurface {
                    SettingsTextFieldRow(
                        title: L("清单地址", "Manifest URL"),
                        subtitle: L("支持 https 和本地 file 路径；发布脚本生成的 JSON 可直接使用", "Supports https and local file paths from the release script"),
                        text: Binding(
                            get: { preferences.manifestURLString },
                            set: { value in setManifestURL(value) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsToggleRow(
                        title: L("自动检查", "Automatic Checks"),
                        subtitle: L("启动后静默检查；没有更新时不打扰", "Checks quietly after launch and stays silent when current"),
                        isOn: Binding(
                            get: { preferences.automaticChecksEnabled },
                            set: { value in setAutomaticChecksEnabled(value) }
                        )
                    )

                    SettingsControlDivider()

                    SettingsToggleRow(
                        title: L("优先增量包", "Prefer Delta"),
                        subtitle: L("清单包含 delta 时先下载小包；缺失时自动回退全量包", "Uses delta packages when present, otherwise falls back to full packages"),
                        isOn: Binding(
                            get: { preferences.prefersDeltaUpdates },
                            set: { value in setPrefersDeltaUpdates(value) }
                        )
                    )
                }
            }

            SettingsPreferenceGroup(title: L("运行时更新", "Runtime Update")) {
                SettingsFormSurface {
                    UpdateActionRow(
                        state: state,
                        hasManifestURL: preferences.manifestURL != nil,
                        checkForUpdates: checkForUpdates,
                        downloadUpdate: downloadUpdate,
                        installUpdate: installUpdate
                    )
                }
            }
        }
    }
}

private struct UpdateStatusCard: View {
    let state: ConductorUpdateState
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state.phase.systemImage)
                    .font(.conductorSystem(size: 16, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis)
                    .frame(width: 38, height: 38)
                    .background(theme.floatingControlStrongFill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(state.phase.statusTitle)
                            .font(.conductorSystem(size: 15, weight: .bold, scale: fontScale))
                            .foregroundStyle(ConductorDesign.primaryText)
                            .lineLimit(1)

                        SettingsStatusPill(
                            title: packageTitle,
                            systemImage: state.selectedPackageKind == .delta ? "shippingbox.and.arrow.backward" : "shippingbox"
                        )
                    }

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

            HStack(spacing: 8) {
                UpdateMetricTile(
                    title: L("当前", "Current"),
                    value: state.currentVersion.displayText,
                    systemImage: "app.badge"
                )
                UpdateMetricTile(
                    title: L("可用", "Available"),
                    value: state.availableVersion?.displayText ?? L("暂无", "None"),
                    systemImage: "sparkle.magnifyingglass"
                )
                UpdateMetricTile(
                    title: L("包大小", "Package"),
                    value: packageSizeText,
                    systemImage: "arrow.down.to.line.compact"
                )
            }
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

    private var packageTitle: String {
        switch state.selectedPackageKind {
        case .delta:
            L("增量", "Delta")
        case .full:
            L("全量", "Full")
        case .none:
            L("运行时", "Runtime")
        }
    }

    private var packageSizeText: String {
        guard let size = state.selectedArtifact?.size else { return L("待检查", "Pending") }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var statusDetail: String {
        switch state.phase {
        case .idle:
            return L("填写清单地址后即可检查。下载包会先做 SHA-256 校验，再进入替换流程。", "Enter a manifest URL to check. Packages are verified before replacement.")
        case .checking:
            return L("正在读取发布清单并和当前版本比较。", "Reading the release manifest and comparing versions.")
        case .upToDate:
            return L("当前版本不低于清单中的版本。", "Current build is not older than the manifest build.")
        case .available:
            return L("可以下载更新；安装时会退出 App，替换完成后自动重新打开。", "Download is available. Installing quits the app, replaces it, then reopens it.")
        case .downloading:
            return L("正在下载并准备校验更新包。", "Downloading and preparing to verify the package.")
        case .downloaded:
            return L("更新包已校验完成，可以安装并重启。", "The package has been verified and is ready to install.")
        case .installing:
            return L("安装器已准备接管，当前 App 会退出。", "The installer is taking over and the app will quit.")
        case .failed(let message):
            return message
        }
    }
}

private struct UpdateMetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 10, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.90))
                .frame(width: 22, height: 22)
                .background(theme.floatingControlStrongFill.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.conductorSystem(size: 9.2, weight: .semibold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.tertiaryText)
                    .lineLimit(1)
                Text(value)
                    .font(.conductorSystem(size: 10.4, weight: .bold, scale: fontScale))
                    .foregroundStyle(ConductorDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(theme.floatingControlFill.opacity(theme.usesDarkChrome ? 0.16 : 0.25))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                title: L("检查", "Check"),
                systemImage: "arrow.clockwise",
                tooltip: L("读取清单并比较版本", "Read the manifest and compare versions"),
                disabled: !hasManifestURL || !state.canCheck,
                action: checkForUpdates
            )

            UpdateActionButton(
                title: L("下载", "Download"),
                systemImage: "arrow.down.circle",
                tooltip: L("下载所选更新包并校验 SHA-256", "Download the selected package and verify SHA-256"),
                disabled: !state.canDownload,
                action: downloadUpdate
            )

            UpdateActionButton(
                title: L("安装并重启", "Install and Relaunch"),
                systemImage: "arrow.triangle.2.circlepath.circle",
                tooltip: L("退出 App，替换运行时，然后重新打开", "Quit, replace the runtime, then reopen"),
                disabled: !state.canInstall,
                action: installUpdate
            )
        }
        .padding(.horizontal, 9)
        .frame(height: 48)
    }
}

private struct UpdateActionButton: View {
    let title: String
    let systemImage: String
    let tooltip: String
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
                .frame(height: 30)
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
        return hovering ? theme.floatingHoverFill.opacity(0.32) : theme.floatingControlStrongFill.opacity(0.92)
    }
}
