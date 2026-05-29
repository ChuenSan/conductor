import ConductorCore
import SwiftUI
import WebKit

private func L(_ zh: String, _ en: String) -> String {
    ConductorLocalization.text(zh: zh, en: en)
}

struct ConductorWebKitSurfaceRepresentable: NSViewRepresentable {
    let tab: WorkspaceWebTabState
    let navigationGeneration: Int
    let reloadGeneration: Int
    let stopGeneration: Int
    let backGeneration: Int
    let forwardGeneration: Int
    let findQuery: String
    let findGeneration: Int
    let findBackwards: Bool
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
            forwardGeneration: forwardGeneration,
            findQuery: findQuery,
            findGeneration: findGeneration,
            findBackwards: findBackwards
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
        private var lastFindGeneration = -1
        private var lastRequestedURL: URL?

        init(model: ConductorWindowModel, tabID: WebTabID) {
            self.model = model
            self.tabID = tabID
            self.webView = ConductorWebKitSurfaceStore.shared.webView(for: tabID)

            super.init()

            webView.navigationDelegate = self
            webView.uiDelegate = self
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
            forwardGeneration: Int,
            findQuery: String,
            findGeneration: Int,
            findBackwards: Bool
        ) {
            tabID = tab.id

            if navigationGeneration != lastNavigationGeneration {
                let firstUpdate = lastNavigationGeneration == -1
                lastNavigationGeneration = navigationGeneration
                // On the first update, try restoring the persisted back/forward
                // history. If it takes, skip the fresh URL load so the user lands
                // exactly where they left off.
                let pendingState = ConductorWebKitSurfaceStore.shared.pendingInteractionState(for: tab.id)
                if firstUpdate,
                   ConductorWebKitSurfaceStore.shared.restoreInteractionState(pendingState, for: tab.id) {
                    lastRequestedURL = webView.url
                    publishState()
                } else {
                    load(tab.url, force: !firstUpdate)
                }
            }

            if lastReloadGeneration == -1 {
                lastReloadGeneration = reloadGeneration
            } else if reloadGeneration != lastReloadGeneration {
                lastReloadGeneration = reloadGeneration
                reload(tab.url)
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
            if lastFindGeneration == -1 {
                lastFindGeneration = findGeneration
            } else if findGeneration != lastFindGeneration {
                lastFindGeneration = findGeneration
                find(findQuery, backwards: findBackwards)
            }
        }

        private func load(_ url: URL?, force: Bool) {
            guard let url else { return }
            guard force || webView.url?.absoluteString != url.absoluteString else { return }
            lastRequestedURL = url
            webView.load(URLRequest(url: url))
        }

        private func reload(_ fallbackURL: URL?) {
            if webView.url != nil {
                webView.reload()
            } else {
                load(fallbackURL, force: true)
            }
        }

        private func find(_ query: String, backwards: Bool) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let configuration = WKFindConfiguration()
            configuration.backwards = backwards
            configuration.wraps = true
            webView.find(trimmed, configuration: configuration) { _ in }
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
            lastRequestedURL = webView.url
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
            guard nsError.domain != WKError.errorDomain || nsError.code != WKError.webContentProcessTerminated.rawValue else {
                model?.reloadWorkspaceWebTab(tabID)
                return
            }
            model?.failWorkspaceWebTab(tabID, url: lastRequestedURL ?? webView.url, message: error.localizedDescription)
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
