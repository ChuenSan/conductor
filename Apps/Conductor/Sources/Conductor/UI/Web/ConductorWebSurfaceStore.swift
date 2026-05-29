import ConductorCore
import WebKit

@MainActor
final class ConductorWebKitSurfaceStore {
    static let shared = ConductorWebKitSurfaceStore()

    private var webViews: [WebTabID: WKWebView] = [:]
    /// Tab IDs whose webView was seeded from a persisted interactionState, so
    /// the coordinator knows to skip the initial URL load.
    private var restoredFromInteractionState: Set<WebTabID> = []
    /// Interaction-state blobs restored from disk, awaiting the tab's first
    /// display. Held here (not in the tab model) so frequent debounced saves
    /// don't re-encode the large blob.
    private var pendingInteractionStates: [WebTabID: Data] = [:]

    private init() {}

    /// Seeds restored interaction-state blobs at launch. Consumed lazily when
    /// each web tab first appears.
    func seedPendingInteractionStates(_ states: [WebTabID: Data]) {
        for (id, data) in states where !data.isEmpty {
            pendingInteractionStates[id] = data
        }
    }

    func pendingInteractionState(for tabID: WebTabID) -> Data? {
        pendingInteractionStates[tabID]
    }

    func webView(for tabID: WebTabID) -> WKWebView {
        if let existing = webViews[tabID] {
            return existing
        }

        let webView = Self.makeWebView()
        webViews[tabID] = webView
        return webView
    }

    /// Restores a webView's back/forward history and scroll position from a
    /// persisted interactionState blob. Returns true when restoration was
    /// applied so callers can skip the initial URL load.
    @discardableResult
    func restoreInteractionState(_ data: Data?, for tabID: WebTabID) -> Bool {
        guard let data, !data.isEmpty else { return false }
        let webView = webView(for: tabID)
        webView.interactionState = data
        pendingInteractionStates.removeValue(forKey: tabID)
        restoredFromInteractionState.insert(tabID)
        return true
    }

    func consumeRestoredFlag(for tabID: WebTabID) -> Bool {
        restoredFromInteractionState.remove(tabID) != nil
    }

    func interactionState(for tabID: WebTabID) -> Data? {
        guard let webView = webViews[tabID] else { return nil }
        return webView.interactionState as? Data
    }

    func remove(_ tabID: WebTabID) {
        restoredFromInteractionState.remove(tabID)
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
