import AppKit
import ConductorCore
import SwiftUI

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorWebWorkspaceView: View {
    @ObservedObject var model: ConductorWindowModel
    let snapshot: ConductorWebSnapshot

    @State private var addressText = ""
    @FocusState private var addressFocused: Bool
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .background(theme.terminalBackground)
        .onAppear {
            synchronizeAddressText(focusBlank: true)
        }
        .onChange(of: snapshot.tab?.id) { _, _ in
            synchronizeAddressText(focusBlank: true)
        }
        .onChange(of: snapshot.tab?.url) { _, _ in
            guard !addressFocused else { return }
            synchronizeAddressText(focusBlank: false)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            iconButton("chevron.left", help: L("后退", "Back"), enabled: snapshot.tab?.canGoBack == true) {
                if let tab = snapshot.tab {
                    model.goBackWorkspaceWebTab(tab.id)
                }
            }

            iconButton("chevron.right", help: L("前进", "Forward"), enabled: snapshot.tab?.canGoForward == true) {
                if let tab = snapshot.tab {
                    model.goForwardWorkspaceWebTab(tab.id)
                }
            }

            iconButton(snapshot.tab?.isLoading == true ? "xmark" : "arrow.clockwise", help: snapshot.tab?.isLoading == true ? L("停止", "Stop") : L("重新加载", "Reload"), enabled: snapshot.tab?.url != nil) {
                guard let tab = snapshot.tab else { return }
                if tab.isLoading {
                    model.stopWorkspaceWebTab(tab.id)
                } else {
                    model.reloadWorkspaceWebTab(tab.id)
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.42))
                TextField(L("输入网址或搜索", "Search or enter address"), text: $addressText)
                    .textFieldStyle(.plain)
                    .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.92))
                    .focused($addressFocused)
                    .onSubmit(submitAddress)
                    .disabled(snapshot.tab == nil)
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(theme.shellStroke.opacity(addressFocused ? 0.48 : 0.20), lineWidth: 1)
            }

            if let progress = snapshot.tab?.estimatedProgress, snapshot.tab?.isLoading == true {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(.linear)
                    .frame(width: 52)
            }

            iconButton("arrow.up.right.square", help: L("在浏览器中打开", "Open in Browser"), enabled: snapshot.tab?.url != nil) {
                if let tab = snapshot.tab {
                    model.openWorkspaceWebTabExternally(tab.id)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.48 : 0.20))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.30 : 0.16))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tab = snapshot.tab {
            ZStack(alignment: .top) {
                if tab.url != nil {
                    ConductorWebSurfaceRepresentable(
                        tab: tab,
                        navigationGeneration: snapshot.navigationGeneration,
                        reloadGeneration: snapshot.reloadGeneration,
                        stopGeneration: snapshot.stopGeneration,
                        backGeneration: snapshot.backGeneration,
                        forwardGeneration: snapshot.forwardGeneration,
                        model: model
                    )
                    .background(theme.terminalBackground)
                } else {
                    blankState(tab: tab)
                }

                if let errorMessage = tab.errorMessage {
                    errorBanner(errorMessage)
                        .padding(.top, 10)
                }
            }
        } else {
            terminalFallback
        }
    }

    private func blankState(tab: WorkspaceWebTabState) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.shellChromeText.opacity(0.30))
            Text(L("新建网页标签", "New Web Tab"))
                .font(.conductorSystem(size: 16, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.72))
            Text(L("输入本地预览地址、文档站点或搜索内容。", "Enter a local preview address, documentation site, or search."))
                .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard tab.url == nil else { return }
            DispatchQueue.main.async {
                addressFocused = true
            }
        }
    }

    private var terminalFallback: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.terminalBackground)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
            Text(message)
                .font(.conductorSystem(size: 11.5, weight: .medium, family: fontFamily, scale: fontScale))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(L("重新加载", "Reload")) {
                if let tab = snapshot.tab {
                    model.reloadWorkspaceWebTab(tab.id)
                }
            }
            .buttonStyle(.plain)
            .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.82))
        .padding(.horizontal, 10)
        .frame(maxWidth: 720)
        .frame(height: 30)
        .background(theme.shellPanelStrong.opacity(theme.usesDarkChrome ? 0.86 : 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(theme.shellStroke.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.18 : 0.10), radius: 10, y: 5)
    }

    private func iconButton(
        _ systemImage: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(enabled ? 0.72 : 0.30))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(!enabled)
        .macNativeTooltip(help)
    }

    private func submitAddress() {
        guard let tab = snapshot.tab else { return }
        model.navigateWorkspaceWebTab(tab.id, input: addressText)
        addressFocused = false
    }

    private func synchronizeAddressText(focusBlank: Bool) {
        guard let tab = snapshot.tab else {
            addressText = ""
            return
        }
        addressText = tab.url?.absoluteString ?? tab.pendingAddress
        if focusBlank, tab.url == nil {
            DispatchQueue.main.async {
                addressFocused = true
            }
        }
    }
}
