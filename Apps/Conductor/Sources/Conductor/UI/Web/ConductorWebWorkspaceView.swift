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
    @State private var addressHovering = false
    @State private var powerMenuHovering = false
    @State private var findVisible = false
    @State private var findText = ""
    @State private var findGeneration = 0
    @State private var findBackwards = false
    @FocusState private var addressFocused: Bool
    @FocusState private var startAddressFocused: Bool
    @FocusState private var findFocused: Bool
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
        .onChange(of: snapshot.addressFocusGeneration) { _, _ in
            focusAddressField()
        }
        .onChange(of: snapshot.findFocusGeneration) { _, _ in
            showFind()
        }
        .onChange(of: snapshot.findNextGeneration) { _, _ in
            runFind(backwards: false)
        }
        .onChange(of: snapshot.findPreviousGeneration) { _, _ in
            runFind(backwards: true)
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                navigationCluster

                addressField

                if let tab = snapshot.tab, tab.url != nil {
                    pageStatusPill(tab)
                }

                ConductorPillGroup {
                    webIconButton("magnifyingglass", help: commandTooltip(L("查找页面", "Find in Page"), command: .showTerminalSearch, fallback: "Cmd-F"), enabled: snapshot.tab?.url != nil) {
                        showFind()
                    }

                    ConductorSegmentDivider()

                    webIconButton("link", help: L("复制链接", "Copy Link"), enabled: snapshot.tab?.url != nil) {
                        copyCurrentURL()
                    }

                    ConductorSegmentDivider()

                    webIconButton("arrow.up.right.square", help: L("在浏览器中打开", "Open in Browser"), enabled: snapshot.tab?.url != nil) {
                        if let tab = snapshot.tab {
                            model.openWorkspaceWebTabExternally(tab.id)
                        }
                    }
                }

                powerMenu
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.48 : 0.20))

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.30 : 0.16))
                    .frame(height: 1)

                if snapshot.tab?.isLoading == true {
                    loadingProgressLine
                }
            }
            .frame(height: 2)
        }
    }

    private var navigationCluster: some View {
        ConductorPillGroup {
            webIconButton("chevron.left", help: L("后退", "Back"), enabled: snapshot.tab?.canGoBack == true) {
                if let tab = snapshot.tab {
                    model.goBackWorkspaceWebTab(tab.id)
                }
            }

            ConductorSegmentDivider()

            webIconButton("chevron.right", help: L("前进", "Forward"), enabled: snapshot.tab?.canGoForward == true) {
                if let tab = snapshot.tab {
                    model.goForwardWorkspaceWebTab(tab.id)
                }
            }

            ConductorSegmentDivider()

            webIconButton(
                snapshot.tab?.isLoading == true ? "xmark" : "arrow.clockwise",
                help: commandTooltip(snapshot.tab?.isLoading == true ? L("停止载入", "Stop Loading") : L("重新加载", "Reload"), command: .reloadSelectedWebTab, fallback: "Cmd-R"),
                enabled: snapshot.tab?.url != nil
            ) {
                reloadOrStop()
            }
        }
    }

    private var addressField: some View {
        HStack(spacing: 7) {
            Image(systemName: addressSystemImage)
                .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(addressIconColor)
                .frame(width: 15)
                .accessibilityHidden(true)

            TextField(L("输入网址或搜索", "Search or enter address"), text: $addressText)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 12.2, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.94))
                .focused($addressFocused)
                .onSubmit(submitAddress)
                .disabled(snapshot.tab == nil)

            if addressFocused, !addressText.isEmpty {
                Button {
                    addressText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.62))
                }
                .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
                .accessibilityLabel(L("清空地址栏", "Clear address field"))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(addressFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(addressStroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            startAddressFocused = false
            addressFocused = true
        }
        .macNativeTooltip(commandTooltip(L("聚焦地址栏", "Focus Address Bar"), command: .focusWebAddress, fallback: "Cmd-L"))
        .conductorHover($addressHovering)
    }

    private var powerMenu: some View {
        Menu {
            Section(L("页面", "Page")) {
                Button(L("查找页面", "Find in Page"), systemImage: "magnifyingglass") {
                    showFind()
                }
                .disabled(snapshot.tab?.url == nil)

                Button(L("复制链接", "Copy Link"), systemImage: "link") {
                    copyCurrentURL()
                }
                .disabled(snapshot.tab?.url == nil)

                Button(L("复制引用", "Copy Reference"), systemImage: "doc.on.clipboard") {
                    copyPageReference()
                }
                .disabled(snapshot.tab?.url == nil)

                Button(L("在浏览器中打开", "Open in Browser"), systemImage: "arrow.up.right.square") {
                    if let tab = snapshot.tab {
                        model.openWorkspaceWebTabExternally(tab.id)
                    }
                }
                .disabled(snapshot.tab?.url == nil)

                Button(L("复制为新标签", "Duplicate Tab"), systemImage: "plus.rectangle.on.rectangle") {
                    duplicateCurrentTab()
                }
                .disabled(snapshot.tab == nil)
            }

            Section(L("本地", "Local")) {
                Button("localhost:3000", systemImage: "server.rack") {
                    openQuickAddress("3000")
                }
                Button("localhost:5173", systemImage: "bolt.horizontal") {
                    openQuickAddress("5173")
                }
                Button("localhost:8000", systemImage: "network") {
                    openQuickAddress("8000")
                }
                Button(L("从剪贴板打开", "Open Clipboard"), systemImage: "doc.on.clipboard") {
                    openClipboardAddress()
                }
                .disabled(clipboardAddressText() == nil)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(powerMenuHovering ? theme.floatingEmphasis : theme.shellChromeText.opacity(0.70))
                .frame(width: 28, height: 28)
                .background(powerMenuHovering ? theme.shellHoverFill.opacity(0.72) : theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.34 : 0.22))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.shellStroke.opacity(powerMenuHovering ? 0.38 : 0.20), lineWidth: 1)
                }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .macNativeTooltip(L("网页操作", "Web Actions"))
        .accessibilityLabel(L("网页操作", "Web Actions"))
        .conductorHover($powerMenuHovering)
    }

    private var loadingProgressLine: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.82 : 0.70))
                .frame(width: max(18, proxy.size.width * CGFloat(clampedProgress)))
                .frame(height: 2)
        }
        .frame(height: 2)
        .transition(.identity)
    }

    @ViewBuilder
    private var content: some View {
        if let tab = snapshot.tab {
            ZStack(alignment: .top) {
                if tab.url != nil {
                    ConductorWebSurfaceView(
                        tab: tab,
                        navigationGeneration: snapshot.navigationGeneration,
                        reloadGeneration: snapshot.reloadGeneration,
                        stopGeneration: snapshot.stopGeneration,
                        backGeneration: snapshot.backGeneration,
                        forwardGeneration: snapshot.forwardGeneration,
                        findQuery: findText,
                        findGeneration: findGeneration,
                        findBackwards: findBackwards,
                        model: model
                    )
                    .id(tab.id)
                    .background(theme.terminalBackground)
                } else {
                    blankState(tab: tab)
                }

                if let errorMessage = tab.errorMessage {
                    errorState(tab: tab, message: errorMessage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(ConductorMotion.panelTransition)
                }

                if findVisible {
                    findBar
                        .padding(.top, 10)
                        .padding(.trailing, 12)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .transition(ConductorMotion.searchTransition)
                }
            }
        } else {
            terminalFallback
        }
    }

    private func blankState(tab: WorkspaceWebTabState) -> some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    WebStartGlyph(systemImage: "globe", emphasis: theme.floatingEmphasis)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("网页", "Web"))
                            .font(.conductorSystem(size: 17, weight: .semibold, family: fontFamily, scale: fontScale))
                            .foregroundStyle(theme.shellChromeText.opacity(0.92))
                        Text(L("URL / 本机 / 搜索", "URL / Local / Search"))
                            .font(.conductorSystem(size: 10.8, weight: .medium, family: fontFamily, scale: fontScale))
                            .foregroundStyle(theme.shellChromeTextMuted.opacity(0.68))
                            .lineLimit(1)
                    }
                }

                startAddressField(tab: tab)

                HStack(alignment: .top, spacing: 12) {
                    launchSection(title: L("本机", "Local"), systemImage: "server.rack") {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            launchShortcut(title: "3000", subtitle: L("应用", "App"), systemImage: "rectangle.on.rectangle") {
                                openQuickAddress("3000")
                            }
                            launchShortcut(title: "5173", subtitle: "Vite", systemImage: "bolt.horizontal") {
                                openQuickAddress("5173")
                            }
                            launchShortcut(title: "8000", subtitle: L("服务", "Server"), systemImage: "network") {
                                openQuickAddress("8000")
                            }
                            launchShortcut(title: L("剪贴板", "Clipboard"), subtitle: clipboardPreviewText, systemImage: "doc.on.clipboard") {
                                openClipboardAddress(in: tab)
                            }
                            .disabled(clipboardAddressText() == nil)
                        }
                    }

                    launchSection(title: L("最近", "Recent"), systemImage: "clock") {
                        recentWebTabs(tab: tab)
                    }
                }
            }
            .frame(width: min(780, max(560, proxy.size.width - 120)), alignment: .leading)
            .padding(.top, max(52, min(112, proxy.size.height * 0.18)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            guard tab.url == nil else { return }
            DispatchQueue.main.async {
                startAddressFocused = true
            }
        }
    }

    private func startAddressField(tab: WorkspaceWebTabState) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 13, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.72))
                .accessibilityHidden(true)

            TextField(L("输入网址、端口或搜索", "Enter URL, port, or search"), text: $addressText)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 15, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.94))
                .focused($startAddressFocused)
                .onSubmit {
                    submitStartAddress(tab)
                }

            Button {
                submitStartAddress(tab)
            } label: {
                HStack(spacing: 5) {
                    Text(L("打开", "Open"))
                        .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                    Image(systemName: "arrow.right")
                        .font(.conductorSystem(size: 10.5, weight: .bold, family: fontFamily, scale: fontScale))
                }
                .foregroundStyle(theme.shellChromeText.opacity(addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.30 : 0.88))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.36 : 0.26))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
            .disabled(addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L("打开", "Open"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(height: 48)
        .background(theme.shellPanelStrong.opacity(theme.usesDarkChrome ? 0.52 : 0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(startAddressFocused ? theme.floatingEmphasis.opacity(0.50) : theme.shellStroke.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.10 : 0.04), radius: 10, y: 4)
    }

    private func recentWebTabs(tab: WorkspaceWebTabState) -> some View {
        VStack(spacing: 6) {
            if snapshot.otherTabs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.52))
                    Text(L("暂无网页标签", "No web tabs"))
                        .font(.conductorSystem(size: 11, weight: .medium, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.62))
                }
                .frame(maxWidth: .infinity, minHeight: 78)
            } else {
                ForEach(Array(snapshot.otherTabs.prefix(5))) { recent in
                    recentTabRow(recent)
                }
            }
        }
    }

    private func launchSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.68))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.76))
                    .textCase(.uppercase)
            }

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.shellPanelStrong.opacity(theme.usesDarkChrome ? 0.34 : 0.54))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.16 : 0.24), lineWidth: 1)
        }
    }

    private func launchShortcut(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 12.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.floatingEmphasis.opacity(0.86))
                    .frame(width: 22, height: 22)
                    .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.38 : 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.conductorSystem(size: 12.2, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.88))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.conductorSystem(size: 10.1, weight: .medium, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.24 : 0.16))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.forward")
                    .font(.conductorSystem(size: 8.5, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.42))
                    .padding(9)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.992, pressedOpacity: 0.96))
    }

    private func recentTabRow(_ recent: WorkspaceWebTabState) -> some View {
        Button {
            model.selectWorkspaceWebTab(recent.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: recent.errorMessage == nil ? "globe" : "exclamationmark.triangle")
                    .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.68))
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.displayTitle)
                        .font(.conductorSystem(size: 11.6, weight: .medium, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeText.opacity(0.84))
                        .lineLimit(1)

                    Text(recent.hostDisplay ?? "")
                        .font(.conductorSystem(size: 9.8, weight: .medium, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.shellChromeTextMuted.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.conductorSystem(size: 8.8, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.42))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.22 : 0.15))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.992, pressedOpacity: 0.96))
    }

    private var terminalFallback: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.terminalBackground)
    }

    private func errorState(tab: WorkspaceWebTabState, message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.conductorSystem(size: 26, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(Color(nsColor: .systemOrange).opacity(0.86))

            VStack(spacing: 4) {
                Text(L("页面没有打开", "Page Did Not Open"))
                    .font(.conductorSystem(size: 17, weight: .semibold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.92))

                Text(tab.url?.absoluteString ?? tab.pendingAddress)
                    .font(.conductorSystem(size: 11.2, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.74))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)

                Text(message)
                    .font(.conductorSystem(size: 11, weight: .medium, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeTextMuted.opacity(0.64))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            errorAddressField(tab)

            HStack(spacing: 8) {
                errorActionButton(L("重试", "Retry"), systemImage: "arrow.clockwise") {
                    model.reloadWorkspaceWebTab(tab.id)
                }
                errorActionButton(L("浏览器", "Browser"), systemImage: "arrow.up.right.square") {
                    model.openWorkspaceWebTabExternally(tab.id)
                }
                .disabled(tab.url == nil)
                errorActionButton(L("复制链接", "Copy Link"), systemImage: "link") {
                    copyCurrentURL()
                }
                .disabled(tab.url == nil)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(theme.shellPanelStrong.opacity(theme.usesDarkChrome ? 0.88 : 0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.shellStroke.opacity(0.16), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.08 : 0.035), radius: 8, y: 3)
    }

    private func errorAddressField(_ tab: WorkspaceWebTabState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.64))
                .accessibilityHidden(true)

            TextField(L("修改地址", "Edit address"), text: $addressText)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 11.6, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.90))
                .onSubmit {
                    navigate(tab, to: addressText)
                }

            Button {
                navigate(tab, to: addressText)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.conductorSystem(size: 9.5, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.74))
                    .frame(width: 22, height: 22)
                    .background(theme.shellHoverFill.opacity(theme.usesDarkChrome ? 0.32 : 0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
            .accessibilityLabel(L("打开地址", "Open Address"))
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: 420)
        .frame(height: 34)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.34 : 0.20))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.shellStroke.opacity(0.22), lineWidth: 1)
        }
    }

    private func errorActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
            }
            .foregroundStyle(theme.shellChromeText.opacity(0.82))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.24))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.shellStroke.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 10.2, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.48))
                .accessibilityHidden(true)

            TextField(L("查找页面", "Find in Page"), text: $findText)
                .textFieldStyle(.plain)
                .font(.conductorSystem(size: 11.5, weight: .medium, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.92))
                .focused($findFocused)
                .onSubmit {
                    runFind(backwards: false)
                }
                .frame(width: 180)

            webIconButton("chevron.up", help: commandTooltip(L("上一个", "Previous"), command: .findPrevious, fallback: "Cmd-Shift-G"), enabled: !findText.isEmpty) {
                runFind(backwards: true)
            }

            webIconButton("chevron.down", help: commandTooltip(L("下一个", "Next"), command: .findNext, fallback: "Cmd-G"), enabled: !findText.isEmpty) {
                runFind(backwards: false)
            }

            webIconButton("xmark", help: L("关闭查找", "Close Find")) {
                hideFind()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(theme.shellPanelStrong.opacity(theme.usesDarkChrome ? 0.90 : 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.shellStroke.opacity(0.18), lineWidth: 0.6)
        }
        .shadow(color: Color.black.opacity(theme.usesDarkChrome ? 0.06 : 0.025), radius: 4, y: 2)
    }

    private func quickAction(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.shellChromeText.opacity(0.76))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.24))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.shellStroke.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(ConductorPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.96))
    }

    private func webIconButton(
        _ systemImage: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        ConductorIconButton(
            state: ConductorControlState(
                id: "web-\(systemImage)-\(help)",
                systemImage: systemImage,
                isEnabled: enabled,
                tooltip: help,
                accessibilityLabel: help
            ),
            action: action)
    }

    private func commandTooltip(_ title: String, command: ConductorShellCommand, fallback: String) -> String {
        "\(title) \(model.shortcutTitle(for: command, fallback: fallback))"
    }

    private var clampedProgress: Double {
        min(max(snapshot.tab?.estimatedProgress ?? 0, 0), 1)
    }

    private var clipboardPreviewText: String {
        guard let text = clipboardAddressText() else {
            return L("无可用内容", "Nothing usable")
        }
        if text.count <= 24 {
            return text
        }
        return String(text.prefix(21)) + "..."
    }

    private var addressSystemImage: String {
        guard let tab = snapshot.tab else { return "magnifyingglass" }
        guard let url = tab.url else { return "magnifyingglass" }
        if isLocalURL(url) { return "server.rack" }
        if url.scheme?.lowercased() == "https" { return "lock" }
        return "globe"
    }

    private var addressIconColor: Color {
        guard let url = snapshot.tab?.url else {
            return theme.shellChromeText.opacity(0.42)
        }
        if isLocalURL(url) {
            return theme.floatingEmphasis.opacity(0.80)
        }
        if url.scheme?.lowercased() == "https" {
            return Color(nsColor: .systemGreen).opacity(theme.usesDarkChrome ? 0.84 : 0.74)
        }
        return theme.shellChromeText.opacity(0.52)
    }

    private var addressFieldBackground: Color {
        if addressFocused {
            return theme.shellPanelStrong.opacity(theme.usesDarkChrome ? 0.62 : 0.50)
        }
        if addressHovering {
            return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.52 : 0.30)
        }
        return theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.22)
    }

    private var addressStroke: Color {
        if addressFocused {
            return theme.floatingEmphasis.opacity(theme.usesDarkChrome ? 0.56 : 0.44)
        }
        return theme.shellStroke.opacity(addressHovering ? 0.34 : 0.20)
    }

    private func pageStatusPill(_ tab: WorkspaceWebTabState) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(for: tab))
                .frame(width: 6, height: 6)
            Text(statusText(for: tab))
                .font(.conductorSystem(size: 10.4, weight: .semibold, family: fontFamily, scale: fontScale))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(theme.shellChromeText.opacity(0.72))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.32 : 0.20))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(theme.shellStroke.opacity(0.20), lineWidth: 1)
        }
        .macNativeTooltip(tab.url?.absoluteString ?? "")
    }

    private func statusText(for tab: WorkspaceWebTabState) -> String {
        if tab.isLoading {
            return "\(Int((clampedProgress * 100).rounded()))%"
        }
        if let url = tab.url, isLocalURL(url) {
            return url.port.map { ":\($0)" } ?? "local"
        }
        return tab.hostDisplay ?? L("网页", "Web")
    }

    private func statusColor(for tab: WorkspaceWebTabState) -> Color {
        if tab.errorMessage != nil {
            return Color(nsColor: .systemOrange)
        }
        if tab.isLoading {
            return theme.floatingEmphasis
        }
        if let url = tab.url, isLocalURL(url) {
            return Color(nsColor: .systemBlue)
        }
        if tab.url?.scheme?.lowercased() == "https" {
            return Color(nsColor: .systemGreen)
        }
        return Color(nsColor: .systemGray)
    }

    private func isLocalURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else {
            return url.isFileURL
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func submitAddress() {
        guard let tab = snapshot.tab else { return }
        navigate(tab, to: addressText)
    }

    private func submitStartAddress(_ tab: WorkspaceWebTabState) {
        navigate(tab, to: addressText)
    }

    private func navigate(_ tab: WorkspaceWebTabState, to input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.navigateWorkspaceWebTab(tab.id, input: trimmed)
        addressText = trimmed
        addressFocused = false
        startAddressFocused = false
    }

    private func focusAddressField() {
        startAddressFocused = false
        addressFocused = true
    }

    private func showFind() {
        guard snapshot.tab?.url != nil else { return }
        findVisible = true
        DispatchQueue.main.async {
            findFocused = true
        }
    }

    private func hideFind() {
        findVisible = false
        findFocused = false
    }

    private func runFind(backwards: Bool) {
        guard !findText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFind()
            return
        }
        findVisible = true
        findBackwards = backwards
        findGeneration += 1
        DispatchQueue.main.async {
            findFocused = true
        }
    }

    private func reloadOrStop() {
        guard let tab = snapshot.tab, tab.url != nil else { return }
        if tab.isLoading {
            model.stopWorkspaceWebTab(tab.id)
        } else {
            model.reloadWorkspaceWebTab(tab.id)
        }
    }

    private func openQuickAddress(_ input: String) {
        guard let tab = snapshot.tab else {
            model.newWorkspaceWebTab(initialInput: input)
            return
        }
        navigate(tab, to: input)
    }

    private func openClipboardAddress(in tab: WorkspaceWebTabState? = nil) {
        guard let text = clipboardAddressText() else { return }
        if let tab, tab.url == nil {
            navigate(tab, to: text)
        } else {
            model.newWorkspaceWebTab(initialInput: text)
            addressText = text
            addressFocused = false
            startAddressFocused = false
        }
    }

    private func clipboardAddressText() -> String? {
        guard let rawText = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count == 1,
              let text = lines.first,
              text.count <= 300 else { return nil }
        return text
    }

    private func duplicateCurrentTab() {
        guard let tab = snapshot.tab else { return }
        let input = tab.url?.absoluteString ?? tab.pendingAddress
        model.newWorkspaceWebTab(initialInput: input)
    }

    private func copyCurrentURL() {
        guard let url = snapshot.tab?.url else { return }
        copyToPasteboard(url.absoluteString)
    }

    private func copyPageReference() {
        guard let tab = snapshot.tab, let url = tab.url else { return }
        let title = tab.displayTitle.replacingOccurrences(of: "]", with: "\\]")
        copyToPasteboard("[\(title)](\(url.absoluteString))")
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func synchronizeAddressText(focusBlank: Bool) {
        guard let tab = snapshot.tab else {
            addressText = ""
            return
        }
        addressText = tab.url?.absoluteString ?? tab.pendingAddress
        if focusBlank, tab.url == nil {
            DispatchQueue.main.async {
                startAddressFocused = true
            }
        }
    }
}

private struct WebStartGlyph: View {
    let systemImage: String
    let emphasis: Color
    @Environment(\.conductorFontScale) private var fontScale
    @Environment(\.conductorFontFamily) private var fontFamily
    @Environment(\.conductorTheme) private var theme

    var body: some View {
        Image(systemName: systemImage)
            .font(.conductorSystem(size: 15.5, weight: .semibold, family: fontFamily, scale: fontScale))
            .foregroundStyle(emphasis.opacity(0.88))
            .frame(width: 30, height: 30)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.42 : 0.26))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.shellStroke.opacity(theme.usesDarkChrome ? 0.16 : 0.22), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
