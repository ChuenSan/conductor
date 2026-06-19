#if os(macOS) && canImport(WebKit)
import AppKit
import Foundation
import WebKit

@MainActor
struct OpenAIDashboardWebViewLease {
    let webView: WKWebView
    let setPreserveLoadedPageOnRelease: @MainActor (Bool) -> Void
    let release: @MainActor () -> Void
}

@MainActor
final class OpenAIDashboardWebViewCache {
    static let shared = OpenAIDashboardWebViewCache()

    private final class ReleaseState {
        var preserveLoadedPageOnRelease: Bool

        init(preserveLoadedPageOnRelease: Bool) {
            self.preserveLoadedPageOnRelease = preserveLoadedPageOnRelease
        }
    }

    private final class Entry {
        let webView: WKWebView
        let host: OffscreenWebViewHost
        var isBusy: Bool
        var lastUsedAt: Date
        var preservedPageExpiresAt: Date?
        var preservedPageExpiryWorkItem: DispatchWorkItem?

        init(webView: WKWebView, host: OffscreenWebViewHost, isBusy: Bool, lastUsedAt: Date) {
            self.webView = webView
            self.host = host
            self.isBusy = isBusy
            self.lastUsedAt = lastUsedAt
        }

        func armPreservedPage(until expiry: Date) {
            preservedPageExpiresAt = expiry
        }

        func setPreservedPageExpiryWorkItem(_ workItem: DispatchWorkItem?) {
            preservedPageExpiryWorkItem?.cancel()
            preservedPageExpiryWorkItem = workItem
        }

        func clearPreservedPage() {
            preservedPageExpiresAt = nil
            preservedPageExpiryWorkItem?.cancel()
            preservedPageExpiryWorkItem = nil
        }

        func consumePreservedPageReuseIfAvailable(now: Date) -> Bool {
            guard let preservedPageExpiresAt else { return false }
            clearPreservedPage()
            return preservedPageExpiresAt > now
        }

        func hasExpiredPreservedPage(now: Date) -> Bool {
            guard let preservedPageExpiresAt else { return false }
            return preservedPageExpiresAt <= now
        }
    }

    private var entries: [String: Entry] = [:]
    private var idlePruneWorkItem: DispatchWorkItem?
    private let idleTimeout: TimeInterval
    private let preservedPageHandoffTimeout: TimeInterval = 5
    private let blankURL = URL(string: "about:blank")!
    private let idlePageClearScript = """
    (() => {
      try {
        document.documentElement.innerHTML = '';
        return true;
      } catch {
        return false;
      }
    })();
    """
    private let reusablePageResetScript = """
    (() => {
      try {
        delete window.__conductorDidScrollToCredits;
        delete window.__codexbarDidScrollToCredits;
        delete window.__codexbarUsageBreakdownJSON;
        delete window.__codexbarUsageBreakdownDebug;
        return true;
      } catch {
        return false;
      }
    })();
    """
    private let preferredLanguageScript = """
    (() => {
      const define = (target, name, value) => {
        try {
          Object.defineProperty(target, name, {
            get: () => value,
            configurable: true
          });
        } catch {}
      };
      define(Navigator.prototype, 'language', 'en-US');
      define(Navigator.prototype, 'languages', ['en-US', 'en']);
      define(navigator, 'language', 'en-US');
      define(navigator, 'languages', ['en-US', 'en']);
    })();
    """

    init(idleTimeout: TimeInterval = 60) {
        self.idleTimeout = idleTimeout
    }

    func acquire(
        websiteDataStore: WKWebsiteDataStore,
        cacheKey: String?,
        usageURL: URL,
        navigationTimeout: TimeInterval,
        allowTimeoutRetry: Bool = true
    ) async throws -> OpenAIDashboardWebViewLease {
        _ = NSApplication.shared
        prune(now: Date())

        guard let cacheKey else {
            return try await makeTemporaryLease(
                websiteDataStore: websiteDataStore,
                usageURL: usageURL,
                navigationTimeout: navigationTimeout)
        }

        if let entry = entries[cacheKey] {
            guard !entry.isBusy else {
                return try await makeTemporaryLease(
                    websiteDataStore: websiteDataStore,
                    usageURL: usageURL,
                    navigationTimeout: navigationTimeout)
            }
            entry.isBusy = true
            entry.lastUsedAt = Date()
            let canReuseLoadedPage = entry.consumePreservedPageReuseIfAvailable(now: entry.lastUsedAt)
            let releaseState = ReleaseState(preserveLoadedPageOnRelease: false)
            entry.host.show()
            do {
                try await prepareWebView(
                    entry.webView,
                    usageURL: usageURL,
                    timeout: navigationTimeout,
                    canReuseLoadedPage: canReuseLoadedPage)
            } catch {
                entry.isBusy = false
                entry.clearPreservedPage()
                entry.host.close()
                entries.removeValue(forKey: cacheKey)
                if allowTimeoutRetry, Self.isNavigationTimeout(error) {
                    return try await acquire(
                        websiteDataStore: websiteDataStore,
                        cacheKey: cacheKey,
                        usageURL: usageURL,
                        navigationTimeout: navigationTimeout,
                        allowTimeoutRetry: false)
                }
                throw error
            }
            return OpenAIDashboardWebViewLease(
                webView: entry.webView,
                setPreserveLoadedPageOnRelease: { preserveLoadedPageOnRelease in
                    releaseState.preserveLoadedPageOnRelease = preserveLoadedPageOnRelease
                },
                release: { [weak self, weak entry] in
                    guard let self, let entry else { return }
                    self.releaseCachedEntry(
                        entry,
                        preserveLoadedPage: releaseState.preserveLoadedPageOnRelease)
                })
        }

        let (webView, host) = makeWebView(websiteDataStore: websiteDataStore)
        let entry = Entry(webView: webView, host: host, isBusy: true, lastUsedAt: Date())
        entries[cacheKey] = entry
        let releaseState = ReleaseState(preserveLoadedPageOnRelease: false)
        host.show()
        do {
            try await prepareWebView(
                webView,
                usageURL: usageURL,
                timeout: navigationTimeout,
                canReuseLoadedPage: false)
        } catch {
            entries.removeValue(forKey: cacheKey)
            host.close()
            if allowTimeoutRetry, Self.isNavigationTimeout(error) {
                return try await acquire(
                    websiteDataStore: websiteDataStore,
                    cacheKey: cacheKey,
                    usageURL: usageURL,
                    navigationTimeout: navigationTimeout,
                    allowTimeoutRetry: false)
            }
            throw error
        }
        return OpenAIDashboardWebViewLease(
            webView: webView,
            setPreserveLoadedPageOnRelease: { preserveLoadedPageOnRelease in
                releaseState.preserveLoadedPageOnRelease = preserveLoadedPageOnRelease
            },
            release: { [weak self, weak entry] in
                guard let self, let entry else { return }
                self.releaseCachedEntry(
                    entry,
                    preserveLoadedPage: releaseState.preserveLoadedPageOnRelease)
            })
    }

    func evict(accountEmail: String?) {
        guard let cacheKey = OpenAIDashboardWebsiteDataStore.cacheKey(forAccountEmail: accountEmail),
              let entry = entries.removeValue(forKey: cacheKey)
        else {
            return
        }
        entry.clearPreservedPage()
        entry.host.close()
        scheduleNextIdlePrune()
    }

    func evictAll() {
        idlePruneWorkItem?.cancel()
        idlePruneWorkItem = nil
        let existing = entries
        entries.removeAll()
        for entry in existing.values {
            entry.clearPreservedPage()
            entry.host.close()
        }
    }

    @discardableResult
    func evictIdle() -> Int {
        let idleEntries = entries.filter { _, entry in
            !entry.isBusy
        }
        guard !idleEntries.isEmpty else { return 0 }

        for (key, entry) in idleEntries {
            entry.clearPreservedPage()
            entry.host.close()
            entries.removeValue(forKey: key)
        }
        scheduleNextIdlePrune()
        return idleEntries.count
    }

    private func makeTemporaryLease(
        websiteDataStore: WKWebsiteDataStore,
        usageURL: URL,
        navigationTimeout: TimeInterval
    ) async throws -> OpenAIDashboardWebViewLease {
        let (webView, host) = makeWebView(websiteDataStore: websiteDataStore)
        host.show()
        do {
            try await prepareWebView(
                webView,
                usageURL: usageURL,
                timeout: navigationTimeout,
                canReuseLoadedPage: false)
        } catch {
            host.close()
            throw error
        }
        return OpenAIDashboardWebViewLease(
            webView: webView,
            setPreserveLoadedPageOnRelease: { _ in },
            release: {
                webView.stopLoading()
                webView.navigationDelegate = nil
                host.close()
            })
    }

    private func releaseCachedEntry(_ entry: Entry, preserveLoadedPage: Bool) {
        entry.isBusy = false
        entry.lastUsedAt = Date()
        prepareForIdle(entry, preserveLoadedPage: preserveLoadedPage)
        prune(now: Date())
        scheduleNextIdlePrune()
    }

    private func prepareForIdle(_ entry: Entry, preserveLoadedPage: Bool) {
        entry.webView.navigationDelegate = nil
        if preserveLoadedPage {
            let expiresAt = Date().addingTimeInterval(preservedPageHandoffTimeout)
            entry.armPreservedPage(until: expiresAt)
            if let key = entries.first(where: { $0.value === entry })?.key {
                schedulePreservedPageExpiry(for: key, entry: entry, expiresAt: expiresAt)
            }
            entry.host.hide()
            return
        }

        entry.clearPreservedPage()
        entry.webView.stopLoading()
        entry.webView.evaluateJavaScript(idlePageClearScript, completionHandler: nil)
        _ = entry.webView.load(URLRequest(url: blankURL))
        entry.host.hide()
    }

    private func makeWebView(websiteDataStore: WKWebsiteDataStore) -> (WKWebView, OffscreenWebViewHost) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let userContentController = WKUserContentController()
        userContentController.addUserScript(WKUserScript(
            source: preferredLanguageScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false))
        configuration.userContentController = userContentController

        if #available(macOS 14.0, *) {
            configuration.preferences.inactiveSchedulingPolicy = .suspend
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let host = OffscreenWebViewHost(webView: webView)
        return (webView, host)
    }

    private func prepareWebView(
        _ webView: WKWebView,
        usageURL: URL,
        timeout: TimeInterval,
        canReuseLoadedPage: Bool
    ) async throws {
        if canReuseLoadedPage,
           Self.isUsageRoute(webView.url?.absoluteString),
           await resetReusablePageState(webView)
        {
            return
        }

        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let state = NavigationState(webView: webView, continuation: continuation)
                let delegate = OpenAIDashboardNavigationDelegate { result in
                    state.complete(result)
                }
                state.delegate = delegate
                webView.navigationDelegate = delegate
                delegate.armTimeout(seconds: timeout)
                var request = URLRequest(url: usageURL)
                request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
                _ = webView.load(request)
                if Task.isCancelled {
                    state.cancel()
                }
            }
        } onCancel: {
            Task { @MainActor in
                webView.stopLoading()
                webView.navigationDelegate?.webView?(webView, didFail: nil, withError: CancellationError())
                webView.navigationDelegate = nil
            }
        }
    }

    private static func isNavigationTimeout(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
    }

    private static func isUsageRoute(_ raw: String?) -> Bool {
        guard let raw, !raw.isEmpty else { return false }
        let path = (URL(string: raw)?.path ?? raw).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.hasSuffix("codex/settings/usage")
            || path.hasSuffix("codex/cloud/settings/usage")
            || path.hasSuffix("codex/settings/analytics")
            || path.hasSuffix("codex/cloud/settings/analytics")
    }

    private func resetReusablePageState(_ webView: WKWebView) async -> Bool {
        do {
            let result = try await webView.evaluateJavaScript(reusablePageResetScript)
            return (result as? Bool) ?? true
        } catch {
            return false
        }
    }

    private func scheduleNextIdlePrune() {
        idlePruneWorkItem?.cancel()
        guard let nextExpiry = entries.values
            .filter({ !$0.isBusy })
            .map({ $0.lastUsedAt.addingTimeInterval(idleTimeout) })
            .min()
        else {
            idlePruneWorkItem = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.idlePruneWorkItem = nil
                self.prune(now: Date())
                self.scheduleNextIdlePrune()
            }
        }
        idlePruneWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.01, nextExpiry.timeIntervalSinceNow),
            execute: workItem)
    }

    private func prune(now: Date) {
        for entry in entries.values where !entry.isBusy && entry.hasExpiredPreservedPage(now: now) {
            prepareForIdle(entry, preserveLoadedPage: false)
        }

        let expired = entries.filter { _, entry in
            !entry.isBusy && now.timeIntervalSince(entry.lastUsedAt) >= idleTimeout
        }
        for (key, entry) in expired {
            entry.clearPreservedPage()
            entry.host.close()
            entries.removeValue(forKey: key)
        }
    }

    private func schedulePreservedPageExpiry(for key: String, entry: Entry, expiresAt: Date) {
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expirePreservedPageIfNeeded(for: key, expectedExpiry: expiresAt)
            }
        }
        entry.setPreservedPageExpiryWorkItem(workItem)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.01, expiresAt.timeIntervalSinceNow),
            execute: workItem)
    }

    private func expirePreservedPageIfNeeded(for key: String, expectedExpiry: Date) {
        guard let entry = entries[key],
              !entry.isBusy,
              let preservedPageExpiresAt = entry.preservedPageExpiresAt,
              preservedPageExpiresAt == expectedExpiry,
              preservedPageExpiresAt <= Date()
        else {
            return
        }

        prepareForIdle(entry, preserveLoadedPage: false)
        prune(now: Date())
    }
}

@MainActor
private final class NavigationState {
    weak var webView: WKWebView?
    var delegate: OpenAIDashboardNavigationDelegate?
    private var continuation: CheckedContinuation<Void, Error>?

    init(webView: WKWebView, continuation: CheckedContinuation<Void, Error>) {
        self.webView = webView
        self.continuation = continuation
    }

    func cancel() {
        webView?.stopLoading()
        delegate?.cancel()
        webView?.navigationDelegate = nil
        webView = nil
        delegate = nil
    }

    func complete(_ result: Result<Void, Error>) {
        webView?.navigationDelegate = nil
        let continuation = self.continuation
        self.continuation = nil
        webView = nil
        delegate = nil
        continuation?.resume(with: result)
    }
}

@MainActor
private final class OffscreenWebViewHost {
    private let window: NSWindow

    init(webView: WKWebView) {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 900)
        let frame = CGRect(
            x: visible.maxX - 1,
            y: visible.maxY - 1,
            width: min(1200, visible.width),
            height: min(1600, visible.height))
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.001
        window.ignoresMouseEvents = true
        window.level = .normal
        window.contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        webView.frame = window.contentView?.bounds ?? CGRect(x: 0, y: 0, width: 1200, height: 1600)
        webView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(webView)
        self.window = window
    }

    func show() {
        window.alphaValue = 0.001
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func close() {
        window.contentView?.subviews.forEach { $0.removeFromSuperview() }
        window.close()
    }
}

public enum OpenAIWebViewCacheMemoryPressureRelief {
    @MainActor
    @discardableResult
    public static func evictIdleDashboardWebViews() -> Int {
        OpenAIDashboardWebViewCache.shared.evictIdle()
    }
}
#endif
