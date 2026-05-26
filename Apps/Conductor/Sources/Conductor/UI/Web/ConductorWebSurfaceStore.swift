import ConductorCore
import WebKit

@MainActor
final class ConductorWebKitSurfaceStore {
    static let shared = ConductorWebKitSurfaceStore()

    private var webViews: [WebTabID: WKWebView] = [:]

    private init() {}

    func webView(for tabID: WebTabID) -> WKWebView {
        if let existing = webViews[tabID] {
            return existing
        }

        let webView = Self.makeWebView()
        webViews[tabID] = webView
        return webView
    }

    func remove(_ tabID: WebTabID) {
        guard let webView = webViews.removeValue(forKey: tabID) else { return }
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    func keepOnly(_ retainedIDs: Set<WebTabID>) {
        let staleIDs = webViews.keys.filter { !retainedIDs.contains($0) }
        for tabID in staleIDs {
            remove(tabID)
        }
    }

    private static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        return webView
    }
}
