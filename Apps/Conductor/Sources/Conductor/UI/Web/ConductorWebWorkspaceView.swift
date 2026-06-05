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
                    pageStatusLabel(tab)
                    if let downloadState = tab.downloadState {
                        downloadStatusMenu(tab: tab, state: downloadState)
                    }
                    if let runtimeEvent = latestActionableRuntimeEvent(in: tab) {
                        runtimeEventMenu(tab: tab, event: runtimeEvent)
                    }
                }

                ControlGroup {
                    webIconButton("magnifyingglass", help: commandTooltip(L("查找页面", "Find in Page"), command: .showTerminalSearch, fallback: "Cmd-F"), enabled: model.canPerformCommand(.showTerminalSearch)) {
                        model.performCommand(.showTerminalSearch)
                    }

                    webIconButton("link", help: commandTooltip(L("复制链接", "Copy Link"), command: .copySelectedWebTabURL, fallback: "Copy"), enabled: model.canPerformCommand(.copySelectedWebTabURL)) {
                        model.performCommand(.copySelectedWebTabURL)
                    }

                    webIconButton("arrow.up.right.square", help: commandTooltip(L("在浏览器中打开", "Open in Browser"), command: .openSelectedWebTabExternally, fallback: "Browser"), enabled: model.canPerformCommand(.openSelectedWebTabExternally)) {
                        model.performCommand(.openSelectedWebTabExternally)
                    }
                }
                .controlGroupStyle(.automatic)
                .fixedSize(horizontal: true, vertical: false)

                powerMenu
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .overlay(alignment: .bottomLeading) {
                if snapshot.tab?.isLoading == true {
                    loadingProgressLine
                }
            }
        }
        .background(.regularMaterial)
    }

    private var navigationCluster: some View {
        ControlGroup {
            webIconButton("chevron.left", help: commandTooltip(L("后退", "Back"), command: .goBackSelectedWebTab, fallback: "Back"), enabled: model.canPerformCommand(.goBackSelectedWebTab)) {
                model.performCommand(.goBackSelectedWebTab)
            }

            webIconButton("chevron.right", help: commandTooltip(L("前进", "Forward"), command: .goForwardSelectedWebTab, fallback: "Forward"), enabled: model.canPerformCommand(.goForwardSelectedWebTab)) {
                model.performCommand(.goForwardSelectedWebTab)
            }

            webIconButton(
                snapshot.tab?.isLoading == true ? "xmark" : "arrow.clockwise",
                help: commandTooltip(snapshot.tab?.isLoading == true ? L("停止载入", "Stop Loading") : L("重新加载", "Reload"), command: .reloadSelectedWebTab, fallback: "Cmd-R"),
                enabled: model.canPerformCommand(.reloadSelectedWebTab)
            ) {
                model.performCommand(.reloadSelectedWebTab)
            }
        }
        .controlGroupStyle(.automatic)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var addressField: some View {
        HStack(spacing: 7) {
            Image(systemName: addressSystemImage)
                .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(addressIconColor)
                .frame(width: 15)
                .accessibilityHidden(true)

            TextField(L("输入网址或搜索", "Search or enter address"), text: $addressText)
                .textFieldStyle(.roundedBorder)
                .font(.conductorSystem(size: 12.2, weight: .medium, family: fontFamily, scale: fontScale))
                .focused($addressFocused)
                .onSubmit(submitAddress)
                .disabled(snapshot.tab == nil)

            if addressFocused, !addressText.isEmpty {
                Button {
                    addressText = ""
                } label: {
                    Label(L("清空地址栏", "Clear address field"), systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel(L("清空地址栏", "Clear address field"))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture {
            startAddressFocused = false
            addressFocused = true
        }
        .help(commandTooltip(L("聚焦地址栏", "Focus Address Bar"), command: .focusWebAddress, fallback: "Cmd-L"))
    }

    private var powerMenu: some View {
        Menu {
            Section(L("页面", "Page")) {
                Button(L("查找页面", "Find in Page"), systemImage: "magnifyingglass") {
                    model.performCommand(.showTerminalSearch)
                }
                .disabled(!model.canPerformCommand(.showTerminalSearch))

                Button(L("复制链接", "Copy Link"), systemImage: "link") {
                    model.performCommand(.copySelectedWebTabURL)
                }
                .disabled(!model.canPerformCommand(.copySelectedWebTabURL))

                Button(L("复制引用", "Copy Reference"), systemImage: "doc.on.clipboard") {
                    model.performCommand(.copySelectedWebTabReference)
                }
                .disabled(!model.canPerformCommand(.copySelectedWebTabReference))

                Button(L("在浏览器中打开", "Open in Browser"), systemImage: "arrow.up.right.square") {
                    model.performCommand(.openSelectedWebTabExternally)
                }
                .disabled(!model.canPerformCommand(.openSelectedWebTabExternally))

                Button(L("复制为新标签", "Duplicate Tab"), systemImage: "plus.rectangle.on.rectangle") {
                    model.performCommand(.duplicateSelectedTab)
                }
                .disabled(!model.canPerformCommand(.duplicateSelectedTab))
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
            Label(L("网页操作", "Web Actions"), systemImage: "ellipsis")
                .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(L("网页操作", "Web Actions"))
        .accessibilityLabel(L("网页操作", "Web Actions"))
    }

    private var loadingProgressLine: some View {
        GeometryReader { proxy in
            Rectangle()
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
                    Image(systemName: "globe")
                        .font(.conductorSystem(size: 21, weight: .semibold, family: fontFamily, scale: fontScale))
                        .foregroundStyle(theme.floatingEmphasis.opacity(0.86))
                        .frame(width: 30, height: 30)
                        .accessibilityHidden(true)
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
                .textFieldStyle(.roundedBorder)
                .font(.conductorSystem(size: 15, weight: .medium, family: fontFamily, scale: fontScale))
                .focused($startAddressFocused)
                .onSubmit {
                    submitStartAddress(tab)
                }

            Button {
                submitStartAddress(tab)
            } label: {
                Label(L("打开", "Open"), systemImage: "arrow.right")
                    .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(addressText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(L("打开", "Open"))
        }
        .padding(.leading, 4)
        .padding(.trailing, 0)
        .frame(height: 48)
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
        GroupBox {
            content()
                .padding(.top, 2)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.78))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .groupBoxStyle(.automatic)
    }

    private func launchShortcut(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.conductorSystem(size: 12.2, weight: .semibold, family: fontFamily, scale: fontScale))
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.conductorSystem(size: 10.1, weight: .medium, family: fontFamily, scale: fontScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: systemImage)
                        .font(.conductorSystem(size: 12.5, weight: .semibold, family: fontFamily, scale: fontScale))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.conductorSystem(size: 8.5, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private func recentTabRow(_ recent: WorkspaceWebTabState) -> some View {
        Button {
            model.selectWorkspaceWebTab(recent.id)
        } label: {
            HStack(spacing: 9) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recent.displayTitle)
                            .font(.conductorSystem(size: 11.6, weight: .medium, family: fontFamily, scale: fontScale))
                            .lineLimit(1)

                        Text(recent.hostDisplay ?? "")
                            .font(.conductorSystem(size: 9.8, weight: .medium, family: fontFamily, scale: fontScale))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: recent.errorMessage == nil ? "globe" : "exclamationmark.triangle")
                        .font(.conductorSystem(size: 10.8, weight: .semibold, family: fontFamily, scale: fontScale))
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.conductorSystem(size: 8.8, weight: .bold, family: fontFamily, scale: fontScale))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 9)
            .frame(height: 38)
        }
        .buttonStyle(.borderless)
    }

    private var terminalFallback: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.terminalBackground)
    }

    private func errorState(tab: WorkspaceWebTabState, message: String) -> some View {
        VStack(spacing: 14) {
            ContentUnavailableView {
                Label(L("页面没有打开", "Page Did Not Open"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(tab.url?.absoluteString ?? tab.pendingAddress)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(message)
                    .lineLimit(2)
            }
            .font(.conductorSystem(size: 12, weight: .medium, family: fontFamily, scale: fontScale))
            .foregroundStyle(theme.shellChromeText.opacity(0.86))
            .frame(maxWidth: 420)

            errorAddressField(tab)

            ControlGroup {
                errorActionButton(L("重试", "Retry"), systemImage: "arrow.clockwise") {
                    model.performCommand(.reloadSelectedWebTab)
                }
                errorActionButton(L("浏览器", "Browser"), systemImage: "arrow.up.right.square") {
                    model.performCommand(.openSelectedWebTabExternally)
                }
                .disabled(!model.canPerformCommand(.openSelectedWebTabExternally))
                errorActionButton(L("复制链接", "Copy Link"), systemImage: "link") {
                    model.performCommand(.copySelectedWebTabURL)
                }
                .disabled(!model.canPerformCommand(.copySelectedWebTabURL))
            }
            .controlSize(.small)
        }
        .padding(22)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConductorTokens.Radius.panel, style: .continuous))
    }

    private func errorAddressField(_ tab: WorkspaceWebTabState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.conductorSystem(size: 10.5, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeTextMuted.opacity(0.64))
                .accessibilityHidden(true)

            TextField(L("修改地址", "Edit address"), text: $addressText)
                .textFieldStyle(.roundedBorder)
                .font(.conductorSystem(size: 11.6, weight: .medium, family: fontFamily, scale: fontScale))
                .onSubmit {
                    navigate(tab, to: addressText)
                }

            Button {
                navigate(tab, to: addressText)
            } label: {
                Image(systemName: "arrow.right")
                    .font(.conductorSystem(size: 9.5, weight: .bold, family: fontFamily, scale: fontScale))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L("打开地址", "Open Address"))
        }
        .frame(maxWidth: 420)
        .frame(height: 34)
    }

    private func errorActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.conductorSystem(size: 11, weight: .semibold, family: fontFamily, scale: fontScale))
        }
    }

    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.conductorSystem(size: 10.2, weight: .semibold, family: fontFamily, scale: fontScale))
                .foregroundStyle(theme.shellChromeText.opacity(0.48))
                .accessibilityHidden(true)

            TextField(L("查找页面", "Find in Page"), text: $findText)
                .textFieldStyle(.roundedBorder)
                .font(.conductorSystem(size: 11.5, weight: .medium, family: fontFamily, scale: fontScale))
                .focused($findFocused)
                .onSubmit {
                    runFind(backwards: false)
                }
                .frame(width: 180)

            ControlGroup {
                webIconButton("chevron.up", help: commandTooltip(L("上一个", "Previous"), command: .findPrevious, fallback: "Cmd-Shift-G"), enabled: !findText.isEmpty) {
                    model.performCommand(.findPrevious)
                }

                webIconButton("chevron.down", help: commandTooltip(L("下一个", "Next"), command: .findNext, fallback: "Cmd-G"), enabled: !findText.isEmpty) {
                    model.performCommand(.findNext)
                }

                webIconButton("xmark", help: L("关闭查找", "Close Find")) {
                    hideFind()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ConductorTokens.Radius.controlGroup, style: .continuous))
    }

    private func webIconButton(
        _ systemImage: String,
        help: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(help, systemImage: systemImage)
        }
        .labelStyle(.iconOnly)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
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

    private func pageStatusLabel(_ tab: WorkspaceWebTabState) -> some View {
        Label {
            Text(statusText(for: tab))
                .font(.conductorSystem(size: 10.4, weight: .semibold, family: fontFamily, scale: fontScale))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        } icon: {
            Image(systemName: "circle.fill")
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(statusColor(for: tab))
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(theme.shellChromeText.opacity(0.72))
        .frame(height: 28)
        .help(tab.url?.absoluteString ?? "")
    }

    private func downloadStatusMenu(tab: WorkspaceWebTabState, state: WorkspaceWebDownloadState) -> some View {
        Menu {
            Section(downloadMenuTitle(state)) {
                if let path = state.destinationPath {
                    Button(L("在 Finder 中显示", "Reveal in Finder"), systemImage: "folder") {
                        model.revealWorkspaceWebTabDownload(tab.id)
                    }
                    .disabled(state.phase != .finished)

                    Button(L("复制路径", "Copy Path"), systemImage: "doc.on.clipboard") {
                        copyToPasteboard(path)
                    }
                }

                if let message = state.errorMessage, !message.isEmpty {
                    Text(message)
                }
            }
        } label: {
            Label {
                Text(downloadStatusText(state))
                    .font(.conductorSystem(size: 10.4, weight: .semibold, family: fontFamily, scale: fontScale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } icon: {
                Image(systemName: downloadSystemImage(for: state.phase))
                    .font(.conductorSystem(size: 9.8, weight: .semibold, family: fontFamily, scale: fontScale))
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(downloadColor(for: state.phase).opacity(0.88))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(downloadTooltip(state))
        .accessibilityLabel(downloadTooltip(state))
    }

    private func runtimeEventMenu(tab: WorkspaceWebTabState, event: WorkspaceWebRuntimeEvent) -> some View {
        Menu {
            Section(runtimeEventTitle(event)) {
                Button(L("复制最近错误", "Copy Latest Error"), systemImage: "doc.on.clipboard") {
                    copyToPasteboard(runtimeEventCopyText(event))
                }
                if let location = runtimeEventLocation(event) {
                    Text(location)
                }
            }

            Section(L("最近事件", "Recent Events")) {
                ForEach(Array(tab.runtimeEvents.suffix(5).indices).reversed(), id: \.self) { index in
                    let event = tab.runtimeEvents[index]
                    Text(runtimeEventMenuLine(event))
                }
            }
        } label: {
            Label {
                Text(L("页面错误", "Page Error"))
                    .font(.conductorSystem(size: 10.4, weight: .semibold, family: fontFamily, scale: fontScale))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.conductorSystem(size: 9.8, weight: .semibold, family: fontFamily, scale: fontScale))
                    .accessibilityHidden(true)
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color(nsColor: .systemOrange).opacity(0.92))
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(runtimeEventTooltip(event))
        .accessibilityLabel(runtimeEventTooltip(event))
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

    private func downloadStatusText(_ state: WorkspaceWebDownloadState) -> String {
        switch state.phase {
        case .requested:
            return L("准备下载", "Download")
        case .downloading:
            return L("下载中", "Downloading")
        case .finished:
            return L("已下载", "Downloaded")
        case .failed:
            return L("下载失败", "Failed")
        }
    }

    private func downloadTooltip(_ state: WorkspaceWebDownloadState) -> String {
        var parts = [downloadMenuTitle(state)]
        if let message = state.errorMessage, !message.isEmpty {
            parts.append(message)
        }
        return parts.joined(separator: "\n")
    }

    private func downloadMenuTitle(_ state: WorkspaceWebDownloadState) -> String {
        let filename = state.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return filename.isEmpty ? downloadStatusText(state) : "\(downloadStatusText(state)) · \(filename)"
    }

    private func downloadSystemImage(for phase: WorkspaceWebDownloadPhase) -> String {
        switch phase {
        case .requested:
            return "arrow.down.circle"
        case .downloading:
            return "arrow.down.circle.fill"
        case .finished:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private func downloadColor(for phase: WorkspaceWebDownloadPhase) -> Color {
        switch phase {
        case .requested, .downloading:
            return theme.floatingEmphasis
        case .finished:
            return Color(nsColor: .systemGreen)
        case .failed:
            return Color(nsColor: .systemOrange)
        }
    }

    private func latestActionableRuntimeEvent(in tab: WorkspaceWebTabState) -> WorkspaceWebRuntimeEvent? {
        tab.runtimeEvents.last { event in
            event.kind == .pageError ||
                event.kind == .unhandledRejection ||
                event.level.lowercased() == "error"
        }
    }

    private func runtimeEventTitle(_ event: WorkspaceWebRuntimeEvent) -> String {
        switch event.kind {
        case .console:
            return event.level.isEmpty ? L("页面控制台", "Page Console") : "console.\(event.level)"
        case .pageError:
            return L("页面脚本错误", "Page Script Error")
        case .unhandledRejection:
            return L("未处理的 Promise", "Unhandled Promise")
        }
    }

    private func runtimeEventMenuLine(_ event: WorkspaceWebRuntimeEvent) -> String {
        let message = event.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(runtimeEventTitle(event)): \(message.isEmpty ? "..." : message)"
    }

    private func runtimeEventTooltip(_ event: WorkspaceWebRuntimeEvent) -> String {
        [runtimeEventTitle(event), event.message]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func runtimeEventCopyText(_ event: WorkspaceWebRuntimeEvent) -> String {
        var parts = [runtimeEventTitle(event), event.message]
        if let location = runtimeEventLocation(event) {
            parts.append(location)
        }
        return parts
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func runtimeEventLocation(_ event: WorkspaceWebRuntimeEvent) -> String? {
        guard let sourceURL = event.sourceURL, !sourceURL.isEmpty else { return nil }
        var location = sourceURL
        if let lineNumber = event.lineNumber {
            location += ":\(lineNumber)"
            if let columnNumber = event.columnNumber {
                location += ":\(columnNumber)"
            }
        }
        return location
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
