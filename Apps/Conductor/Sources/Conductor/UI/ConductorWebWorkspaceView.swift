import AppKit
import ConductorCore
import SwiftUI
import WebKit

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorWebWorkspaceView: View {
    let model: ConductorWindowModel
    let tab: ConductorWorkspaceWebTab

    @State private var addressText = ""
    @FocusState private var addressFocused: Bool
    @Environment(\.conductorTheme) private var theme
    @Environment(\.conductorFontScale) private var fontScale

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let url = tab.currentURL {
                ConductorWebView(
                    tabID: tab.id,
                    url: url,
                    model: model
                )
                .id(tab.id)
            } else {
                newTabSurface
            }
        }
        .background(theme.terminalBackground)
        .onAppear {
            addressText = tab.pendingInput.isEmpty ? (tab.currentURL?.absoluteString ?? "") : tab.pendingInput
            if tab.currentURL == nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    addressFocused = true
                }
            }
        }
        .onChange(of: tab.id) {
            addressText = tab.pendingInput.isEmpty ? (tab.currentURL?.absoluteString ?? "") : tab.pendingInput
        }
        .onChange(of: tab.currentURL) {
            guard !addressFocused else { return }
            addressText = tab.currentURL?.absoluteString ?? ""
        }
        .onChange(of: addressFocused) { _, focused in
            if !focused {
                addressText = tab.currentURL?.absoluteString ?? tab.pendingInput
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            webButton("chevron.left", help: L("后退", "Back"), disabled: !tab.canGoBack) {
                NotificationCenter.default.post(name: .conductorWebGoBack, object: tab.id)
            }
            webButton("chevron.right", help: L("前进", "Forward"), disabled: !tab.canGoForward) {
                NotificationCenter.default.post(name: .conductorWebGoForward, object: tab.id)
            }
            webButton(tab.isLoading ? "xmark" : "arrow.clockwise", help: tab.isLoading ? L("停止", "Stop") : L("重新载入", "Reload")) {
                NotificationCenter.default.post(name: tab.isLoading ? .conductorWebStop : .conductorWebReload, object: tab.id)
            }

            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.conductorSystem(size: 11, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.46))
                TextField(L("输入网址或搜索", "Search or enter website"), text: $addressText)
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .font(.conductorSystem(size: 12, weight: .medium, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.88))
                    .onSubmit { submitAddress() }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.36 : 0.24))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            webButton("arrow.up.right.square", help: L("在浏览器中打开", "Open Externally"), disabled: tab.currentURL == nil) {
                if let url = tab.currentURL {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(theme.terminalChrome.opacity(theme.usesDarkChrome ? 0.42 : 0.26))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.42 : 0.30))
                .frame(height: 1)
        }
    }

    private var newTabSurface: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            HStack {
                TextField(L("输入网址或搜索", "Search or enter website"), text: $addressText)
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .font(.conductorSystem(size: 20, weight: .semibold, scale: fontScale))
                    .foregroundStyle(theme.shellChromeText.opacity(0.92))
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 520)
                    .frame(height: 48)
                    .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.36 : 0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.terminalOuterStroke.opacity(theme.usesDarkChrome ? 0.36 : 0.24), lineWidth: 1)
                    }
                    .onSubmit { submitAddress() }
            }
            .padding(.horizontal, 24)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    quickOpen("localhost:3000")
                    quickOpen("localhost:5173")
                    quickOpen("github.com")
                }
                VStack(spacing: 8) {
                    quickOpen("localhost:3000")
                    quickOpen("localhost:5173")
                    quickOpen("github.com")
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickOpen(_ value: String) -> some View {
        Button(value) {
            addressText = value
            submitAddress()
        }
        .buttonStyle(ConductorPressButtonStyle())
        .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
        .foregroundStyle(theme.shellChromeText.opacity(0.72))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(theme.shellControlFill.opacity(theme.usesDarkChrome ? 0.24 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func webButton(_ systemImage: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.conductorSystem(size: 11.5, weight: .semibold, scale: fontScale))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(ConductorPressButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityLabel(help)
        .macNativeTooltip(help)
    }

    private func submitAddress() {
        guard let url = WebAddressResolver.resolve(addressText) else { return }
        model.updateWorkspaceWebTab(tab.id, pendingInput: addressText)
        model.navigateWorkspaceWebTab(tab.id, to: url)
    }
}

private extension Notification.Name {
    static let conductorWebGoBack = Notification.Name("conductor.web.goBack")
    static let conductorWebGoForward = Notification.Name("conductor.web.goForward")
    static let conductorWebReload = Notification.Name("conductor.web.reload")
    static let conductorWebStop = Notification.Name("conductor.web.stop")
}

private struct ConductorWebView: NSViewRepresentable {
    let tabID: String
    let url: URL
    let model: ConductorWindowModel

    func makeCoordinator() -> Coordinator {
        Coordinator(tabID: tabID, model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.bind(webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.tabID = tabID
        context.coordinator.model = model
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        coordinator.clearObservers()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var tabID: String
        weak var model: ConductorWindowModel?
        private let observers = WebNavigationObservers()

        init(tabID: String, model: ConductorWindowModel) {
            self.tabID = tabID
            self.model = model
        }

        func bind(_ webView: WKWebView) {
            let center = NotificationCenter.default
            observers.replace(with: [
                center.addObserver(forName: .conductorWebGoBack, object: nil, queue: .main) { [weak self, weak webView] note in
                    let requestedTabID = note.object as? String
                    Task { @MainActor [weak self, weak webView] in
                        guard self?.matches(requestedTabID) == true else { return }
                        webView?.goBack()
                    }
                },
                center.addObserver(forName: .conductorWebGoForward, object: nil, queue: .main) { [weak self, weak webView] note in
                    let requestedTabID = note.object as? String
                    Task { @MainActor [weak self, weak webView] in
                        guard self?.matches(requestedTabID) == true else { return }
                        webView?.goForward()
                    }
                },
                center.addObserver(forName: .conductorWebReload, object: nil, queue: .main) { [weak self, weak webView] note in
                    let requestedTabID = note.object as? String
                    Task { @MainActor [weak self, weak webView] in
                        guard self?.matches(requestedTabID) == true else { return }
                        webView?.reload()
                    }
                },
                center.addObserver(forName: .conductorWebStop, object: nil, queue: .main) { [weak self, weak webView] note in
                    let requestedTabID = note.object as? String
                    Task { @MainActor [weak self, weak webView] in
                        guard self?.matches(requestedTabID) == true else { return }
                        webView?.stopLoading()
                    }
                }
            ])
        }

        func clearObservers() {
            observers.removeAll()
        }

        private func matches(_ requestedTabID: String?) -> Bool {
            requestedTabID == tabID
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            publish(webView, isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publish(webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            publish(webView, isLoading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            publish(webView, isLoading: false)
        }

        private func publish(_ webView: WKWebView, isLoading: Bool) {
            model?.updateWorkspaceWebTab(
                tabID,
                title: webView.title ?? webView.url?.host,
                currentURL: webView.url,
                pendingInput: webView.url?.absoluteString,
                isLoading: isLoading,
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward
            )
        }
    }
}

private final class WebNavigationObservers: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    deinit {
        removeAll()
    }

    func replace(with tokens: [NSObjectProtocol]) {
        removeAll()
        self.tokens = tokens
    }

    func removeAll() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }
}
