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

    func existingWebView(for tabID: WebTabID) -> WKWebView? {
        webViews[tabID]
    }

    /// Restores a webView's back/forward history and scroll position from a
    /// persisted interactionState blob. Returns true when restoration was
    /// applied so callers can skip the initial URL load.
    @discardableResult
    func restoreInteractionState(_ data: Data?, for tabID: WebTabID) -> Bool {
        guard let data, !data.isEmpty else { return false }
        let webView = webView(for: tabID)
        webView.interactionState = Self.unarchivedInteractionState(from: data) ?? data
        pendingInteractionStates.removeValue(forKey: tabID)
        restoredFromInteractionState.insert(tabID)
        return true
    }

    func consumeRestoredFlag(for tabID: WebTabID) -> Bool {
        restoredFromInteractionState.remove(tabID) != nil
    }

    func interactionState(for tabID: WebTabID) -> Data? {
        guard let state = webViews[tabID]?.interactionState else { return nil }
        if let data = state as? Data {
            return data
        }
        return try? NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: false)
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

    private static func unarchivedInteractionState(from data: Data) -> Any? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        return unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
    }
}
