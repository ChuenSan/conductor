import ConductorCore
import SwiftUI
import WebKit

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorWebSurfaceRepresentable: NSViewRepresentable {
    let tab: WorkspaceWebTabState
    let navigationGeneration: Int
    let reloadGeneration: Int
    let stopGeneration: Int
    let backGeneration: Int
    let forwardGeneration: Int
    let model: ConductorWindowModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, tabID: tab.id)
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(
            tab: tab,
            navigationGeneration: navigationGeneration,
            reloadGeneration: reloadGeneration,
            stopGeneration: stopGeneration,
            backGeneration: backGeneration,
            forwardGeneration: forwardGeneration
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let webView: WKWebView
        private weak var model: ConductorWindowModel?
        private var tabID: WebTabID
        private var observations: [NSKeyValueObservation] = []
        private var lastNavigationGeneration = -1
        private var lastReloadGeneration = -1
        private var lastStopGeneration = -1
        private var lastBackGeneration = -1
        private var lastForwardGeneration = -1

        init(model: ConductorWindowModel, tabID: WebTabID) {
            self.model = model
            self.tabID = tabID

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            self.webView = WKWebView(frame: .zero, configuration: configuration)

            super.init()

            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsBackForwardNavigationGestures = true
            installObservers()
        }

        deinit {
            observations.removeAll()
        }

        func update(
            tab: WorkspaceWebTabState,
            navigationGeneration: Int,
            reloadGeneration: Int,
            stopGeneration: Int,
            backGeneration: Int,
            forwardGeneration: Int
        ) {
            tabID = tab.id

            if navigationGeneration != lastNavigationGeneration {
                lastNavigationGeneration = navigationGeneration
                load(tab.url)
            } else if let url = tab.url, webView.url?.absoluteString != url.absoluteString {
                load(url)
            }

            if lastReloadGeneration == -1 {
                lastReloadGeneration = reloadGeneration
            } else if reloadGeneration != lastReloadGeneration {
                lastReloadGeneration = reloadGeneration
                webView.reload()
            }
            if lastStopGeneration == -1 {
                lastStopGeneration = stopGeneration
            } else if stopGeneration != lastStopGeneration {
                lastStopGeneration = stopGeneration
                webView.stopLoading()
                publishState()
            }
            if lastBackGeneration == -1 {
                lastBackGeneration = backGeneration
            } else if backGeneration != lastBackGeneration {
                lastBackGeneration = backGeneration
                if webView.canGoBack {
                    webView.goBack()
                }
            }
            if lastForwardGeneration == -1 {
                lastForwardGeneration = forwardGeneration
            } else if forwardGeneration != lastForwardGeneration {
                lastForwardGeneration = forwardGeneration
                if webView.canGoForward {
                    webView.goForward()
                }
            }
        }

        private func load(_ url: URL?) {
            guard let url else { return }
            webView.load(URLRequest(url: url))
        }

        private func installObservers() {
            observations = [
                webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.publishState() }
                },
                webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.publishState() }
                },
                webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.publishState() }
                },
                webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.publishState() }
                },
                webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.publishState() }
                },
                webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.publishState() }
                }
            ]
        }

        private func publishState() {
            let currentURL = webView.url
            model?.updateWorkspaceWebTab(tabID) { tab in
                if let currentURL {
                    tab.url = currentURL
                    tab.pendingAddress = currentURL.absoluteString
                    tab.faviconURL = Self.faviconURL(for: currentURL)
                }
                tab.title = webView.title
                tab.isLoading = webView.isLoading
                tab.estimatedProgress = webView.isLoading ? webView.estimatedProgress : 1
                tab.canGoBack = webView.canGoBack
                tab.canGoForward = webView.canGoForward
                if webView.isLoading {
                    tab.errorMessage = nil
                }
            }
        }

        private static func faviconURL(for url: URL) -> URL? {
            guard url.scheme == "http" || url.scheme == "https",
                  let host = url.host(percentEncoded: false),
                  !host.isEmpty,
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }
            components.path = "/favicon.ico"
            components.query = nil
            components.fragment = nil
            return components.url
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            publishState()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publishState()
            model?.persistWorkspaceWebTabs()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail(error)
        }

        private func fail(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            model?.failWorkspaceWebTab(tabID, url: webView.url, message: error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                model?.newWorkspaceWebTab(initialInput: url.absoluteString)
            } else {
                model?.failWorkspaceWebTab(
                    tabID,
                    url: webView.url,
                    message: L("无法打开没有地址的新窗口请求", "Cannot open a new-window request without an address")
                )
            }
            return nil
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
        ) {
            let filename = suggestedFilename.isEmpty ? "download" : suggestedFilename
            guard let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                model?.failWorkspaceWebTab(tabID, url: webView.url, message: L("无法定位下载目录", "Could not locate the Downloads folder"))
                completionHandler(nil)
                return
            }
            completionHandler(downloadsURL.appendingPathComponent(filename))
        }

        func downloadDidFinish(_ download: WKDownload) {
            publishState()
            model?.persistWorkspaceWebTabs()
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            fail(error)
        }
    }
}
