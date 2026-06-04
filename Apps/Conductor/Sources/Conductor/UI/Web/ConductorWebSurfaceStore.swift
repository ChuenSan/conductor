import ConductorCore
import WebKit

struct ConductorWebRuntimeState: Equatable {
    var entries: [WorkspaceWebNavigationEntry]
    var currentIndex: Int?
    var scrollY: Double?
}

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

    func existingWebView(for tabID: WebTabID) -> WKWebView? {
        webViews[tabID]
    }

    func runtimeState(for tabID: WebTabID) async -> ConductorWebRuntimeState? {
        guard let webView = webViews[tabID] else { return nil }
        let scrollY = try? await webView.evaluateJavaScript(Self.scrollYScript) as? Double
        return ConductorWebRuntimeState(
            entries: Self.navigationEntries(for: webView),
            currentIndex: Self.currentNavigationIndex(for: webView),
            scrollY: scrollY
        )
    }

    static func navigationEntries(for webView: WKWebView) -> [WorkspaceWebNavigationEntry] {
        let back = webView.backForwardList.backList.map(Self.navigationEntry)
        let current = webView.backForwardList.currentItem.map { [Self.navigationEntry($0)] } ?? []
        let forward = webView.backForwardList.forwardList.map(Self.navigationEntry)
        return back + current + forward
    }

    static func currentNavigationIndex(for webView: WKWebView) -> Int? {
        guard webView.backForwardList.currentItem != nil else { return nil }
        return webView.backForwardList.backList.count
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

    private static func navigationEntry(_ item: WKBackForwardListItem) -> WorkspaceWebNavigationEntry {
        WorkspaceWebNavigationEntry(url: item.url, title: item.title)
    }

    private static let scrollYScript = """
    (() => {
      const scroller = document.scrollingElement || document.documentElement || document.body;
      const y = window.pageYOffset || (scroller ? scroller.scrollTop : 0) || 0;
      return Number.isFinite(y) ? y : 0;
    })();
    """

}
