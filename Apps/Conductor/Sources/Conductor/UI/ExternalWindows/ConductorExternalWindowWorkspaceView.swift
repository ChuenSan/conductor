import AppKit
import ConductorCore
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorExternalWindowWorkspaceView: View {
    @ObservedObject var model: ConductorWindowModel
    let tab: WorkspaceExternalWindowTabState
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @State private var fitGeneration = 0
    @State private var trusted = ExternalWindowPortalService.isAccessibilityTrusted
    @State private var screenCaptureTrusted = ExternalWindowPortalService.isScreenCaptureTrusted
    @State private var windowAvailable = true
    @State private var previewImage: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            portalStage
        }
        .background(theme.terminalBackground)
        .onAppear {
            refreshPortalStatus()
            fitGeneration &+= 1
        }
        .onChange(of: tab) { _, _ in
            refreshPortalStatus()
            fitGeneration &+= 1
        }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refreshPortalStatus()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 9) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.9))
                .frame(width: 26, height: 26)
                .background(theme.floatingControlFill.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.displayTitle)
                    .font(.conductorSystem(size: 12.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.94))
                    .lineLimit(1)
                Text(tab.ownerName)
                    .font(.conductorSystem(size: 10.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.74))
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if !trusted {
                Button {
                    model.requestExternalWindowAccessibilityPermission()
                    refreshPortalStatus()
                } label: {
                    Label(L("允许控制", "Allow Control"), systemImage: "checkmark.shield")
                }
                .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme, emphasized: true))
                .macNativeTooltip(L("打开系统辅助功能授权", "Open Accessibility permission prompt"))
            } else if !screenCaptureTrusted && !tab.attached {
                Button {
                    model.requestExternalWindowScreenCapturePermission()
                    refreshPortalStatus()
                } label: {
                    Label(L("允许预览", "Allow Preview"), systemImage: "rectangle.dashed.badge.record")
                }
                .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme, emphasized: true))
                .macNativeTooltip(L("只在你点击时请求屏幕录制权限，用于显示窗口预览", "Ask for Screen Recording only when clicked, used for window previews"))
            } else {
                Button {
                    model.setWorkspaceExternalWindowTabAttached(tab.id, attached: true)
                    refreshPortalStatus()
                    fitGeneration &+= 1
                } label: {
                    Label(L("贴合", "Fit"), systemImage: "rectangle.arrowtriangle.2.inward")
                }
                .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme, emphasized: tab.attached))
                .macNativeTooltip(L("把窗口贴合到工作台内容区", "Fit the window into the workspace area"))

                Button {
                    model.focusWorkspaceExternalWindow(tab.id)
                    refreshPortalStatus()
                } label: {
                    Label(L("聚焦", "Focus"), systemImage: "scope")
                }
                .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme))
                .macNativeTooltip(L("把焦点交给这个应用窗口", "Focus this app window"))

                Button {
                    model.setWorkspaceExternalWindowTabAttached(tab.id, attached: false)
                    refreshPortalStatus()
                } label: {
                    Label(L("脱离", "Detach"), systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme))
                .macNativeTooltip(L("停止跟随工作台区域", "Stop fitting this window to the workspace"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.42 : 0.30))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.42 : 0.28))
                .frame(height: 1)
        }
    }

    private var portalStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.22 : 0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.32 : 0.22), lineWidth: 1)
                }
                .padding(10)

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .padding(24)
                    .opacity(tab.attached && trusted && windowAvailable ? 0.18 : 0.78)
                    .saturation(tab.attached && trusted && windowAvailable ? 0.65 : 1)
                    .allowsHitTesting(false)
            }

            if !trusted {
                permissionState
            } else if !windowAvailable {
                missingState
            } else if !screenCaptureTrusted && !tab.attached {
                screenCaptureState
            } else if !tab.attached {
                detachedState
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.connected.to.line.below")
                        .font(.system(size: 24, weight: .semibold))
                    Text(L("窗口已贴合", "Window Fitted"))
                        .font(.conductorSystem(size: 13, weight: .semibold, scale: fontScale))
                    Text(L("外部应用保持原生输入和菜单", "The external app keeps its native input and menus"))
                        .font(.conductorSystem(size: 11, weight: .medium, scale: fontScale))
                }
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.54))
                .allowsHitTesting(false)
            }

            ExternalWindowPortalFitView(tab: tab, attached: tab.attached && trusted, generation: fitGeneration)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.9))
            Text(L("需要辅助功能权限", "Accessibility Permission Needed"))
                .font(.conductorSystem(size: 15, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.9))
            Text(L("用于移动、缩放和聚焦你选择的应用窗口。", "Used to move, resize, and focus the app window you choose."))
                .font(.conductorSystem(size: 11.5, weight: .medium, scale: fontScale))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.76))
            Button(L("打开授权", "Open Permission")) {
                model.requestExternalWindowAccessibilityPermission()
                refreshPortalStatus()
            }
            .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme, emphasized: true))
        }
        .padding(24)
    }

    private var screenCaptureState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(theme.floatingEmphasis.opacity(0.88))
            Text(L("预览需要单独授权", "Preview Needs Permission"))
                .font(.conductorSystem(size: 15, weight: .semibold, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.9))
            Text(L("不影响贴合和聚焦；只用于显示这个窗口的静态预览。", "Fit and focus still work; this only enables the static window preview."))
                .font(.conductorSystem(size: 11.5, weight: .medium, scale: fontScale))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.76))
                .multilineTextAlignment(.center)
            Button(L("允许预览", "Allow Preview")) {
                model.requestExternalWindowScreenCapturePermission()
                refreshPortalStatus()
            }
            .buttonStyle(ExternalWindowPortalButtonStyle(theme: theme, emphasized: true))
        }
        .padding(24)
    }

    private var missingState: some View {
        portalMessage(
            icon: "macwindow.badge.plus",
            title: L("窗口不在当前桌面", "Window Not Available"),
            subtitle: L("它可能已关闭、最小化，或移动到了其他空间。", "It may be closed, minimized, or on another Space.")
        )
    }

    private var detachedState: some View {
        portalMessage(
            icon: "rectangle.portrait.and.arrow.right",
            title: L("窗口已脱离", "Window Detached"),
            subtitle: L("点击贴合，把它重新放回这个工作台区域。", "Fit it again to bring it back into this workspace area.")
        )
    }

    private func portalMessage(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .semibold))
            Text(title)
                .font(.conductorSystem(size: 14, weight: .semibold, scale: fontScale))
            Text(subtitle)
                .font(.conductorSystem(size: 11.5, weight: .medium, scale: fontScale))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.66))
        .padding(24)
    }

    private func refreshPortalStatus() {
        trusted = ExternalWindowPortalService.isAccessibilityTrusted
        screenCaptureTrusted = ExternalWindowPortalService.isScreenCaptureTrusted
        windowAvailable = ExternalWindowPortalService.isWindowAvailable(tab)
        guard screenCaptureTrusted else {
            previewImage = nil
            model.refreshWorkspaceExternalWindowTabs()
            return
        }
        let snapshotTab = tab
        Task { @MainActor in
            let image = await ExternalWindowPortalService.snapshot(for: snapshotTab)
            guard snapshotTab.id == tab.id else { return }
            previewImage = image
        }
        model.refreshWorkspaceExternalWindowTabs()
    }
}

private struct ExternalWindowPortalFitView: NSViewRepresentable {
    let tab: WorkspaceExternalWindowTabState
    let attached: Bool
    let generation: Int

    func makeNSView(context: Context) -> ExternalWindowPortalFitNSView {
        ExternalWindowPortalFitNSView()
    }

    func updateNSView(_ view: ExternalWindowPortalFitNSView, context: Context) {
        view.update(tab: tab, attached: attached, generation: generation)
    }
}

private final class ExternalWindowPortalFitNSView: NSView {
    private var tab: WorkspaceExternalWindowTabState?
    private var attached = false
    private var generation = 0
    private var pendingFit: DispatchWorkItem?

    override var isFlipped: Bool { true }

    func update(tab: WorkspaceExternalWindowTabState, attached: Bool, generation: Int) {
        self.tab = tab
        self.attached = attached
        self.generation = generation
        scheduleFit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleFit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleFit()
    }

    private func scheduleFit() {
        pendingFit?.cancel()
        guard attached, let tab else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.attached, let window = self.window else { return }
            let rectInWindow = self.convert(self.bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            ExternalWindowPortalService.fit(tab, to: rectOnScreen)
        }
        pendingFit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(45), execute: work)
    }
}

private struct ExternalWindowPortalButtonStyle: ButtonStyle {
    let theme: TerminalTheme
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(emphasized ? theme.shellChromeText.opacity(0.94) : theme.shellChromeTextMuted.opacity(0.82))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(emphasized ? theme.floatingEmphasis.opacity(0.18) : theme.floatingControlFill.opacity(0.72))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(emphasized ? theme.floatingEmphasis.opacity(0.32) : theme.floatingStroke.opacity(0.24), lineWidth: 0.8)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct ExternalWindowPickerPanel: View {
    @ObservedObject var model: ConductorWindowModel
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @State private var searchText = ""

    var body: some View {
        ZStack {
            Color.black.opacity(theme.usesDarkChrome ? 0.30 : 0.16)
                .ignoresSafeArea()
                .onTapGesture {
                    model.closeExternalWindowPicker()
                }

            VStack(spacing: 0) {
                header
                searchField
                Divider().opacity(0.18)
                windowList
            }
            .frame(width: 560, height: 520)
            .background(theme.floatingPanelBase.opacity(theme.usesDarkChrome ? 0.96 : 0.98))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.floatingStroke.opacity(theme.usesDarkChrome ? 0.42 : 0.30), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.34 : 0.12), radius: 28, y: 18)
        }
        .onAppear {
            model.refreshExternalWindowCandidates()
        }
    }

    private var filteredCandidates: [ExternalWindowCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.externalWindowCandidates }
        return model.externalWindowCandidates.filter { candidate in
            candidate.displayTitle.lowercased().contains(query) ||
                candidate.ownerName.lowercased().contains(query) ||
                (candidate.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.floatingEmphasis)
                .frame(width: 32, height: 32)
                .background(theme.floatingControlFill.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(L("接入应用窗口", "Attach App Window"))
                    .font(.conductorSystem(size: 16, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.94))
                Text(L("选择一个当前打开的窗口，放进工作台标签。", "Choose an open window and place it in a workspace tab."))
                    .font(.conductorSystem(size: 11.5, weight: .medium, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.72))
            }

            Spacer()

            Button {
                model.refreshExternalWindowCandidates()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.78))
            .background(theme.floatingControlFill.opacity(0.72))
            .clipShape(Circle())
            .macNativeTooltip(L("刷新窗口列表", "Refresh window list"))

            Button {
                model.closeExternalWindowPicker()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.78))
            .background(theme.floatingControlFill.opacity(0.72))
            .clipShape(Circle())
            .macNativeTooltip(L("关闭", "Close"))
        }
        .padding(18)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.70))
            TextField(L("搜索窗口或应用", "Search windows or apps"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 12.5, weight: .medium, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.90))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.55))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(theme.floatingControlFill.opacity(0.60))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.floatingStroke.opacity(0.20), lineWidth: 0.8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var windowList: some View {
        Group {
            if filteredCandidates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("没有可接入的窗口", "No Windows Available") : L("没有匹配窗口", "No Matching Windows"))
                        .font(.conductorSystem(size: 13.5, weight: .semibold, scale: fontScale))
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("打开一个应用窗口后刷新。", "Open an app window, then refresh.") : L("换个关键词试试。", "Try another keyword."))
                        .font(.conductorSystem(size: 11.5, weight: .medium, scale: fontScale))
                }
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.68))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCandidates) { candidate in
                            ExternalWindowCandidateRow(candidate: candidate) {
                                model.bindExternalWindow(candidate)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

private struct ExternalWindowCandidateRow: View {
    let candidate: ExternalWindowCandidate
    let action: () -> Void
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(nsImage: candidate.appIcon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.displayTitle)
                        .font(.conductorSystem(size: 13, weight: .semibold, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(candidate.subtitle)
                        .font(.conductorSystem(size: 11, weight: .medium, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.70))
                        .lineLimit(1)
                }

                Spacer()

                Text("\(Int(candidate.bounds.width)) x \(Int(candidate.bounds.height))")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.58))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(theme.floatingControlFill.opacity(0.62))
                    .clipShape(Capsule())

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(hovering ? 0.82 : 0.44))
            }
            .padding(.horizontal, 12)
            .frame(height: 58)
            .background(hovering ? theme.floatingHoverFill.opacity(0.78) : theme.floatingControlFill.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.floatingStroke.opacity(hovering ? 0.34 : 0.18), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .conductorHover($hovering)
    }
}
