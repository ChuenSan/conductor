import ConductorCore
import QuartzCore
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
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
        let webView: WKWebView
        private weak var model: ConductorWindowModel?
        private var tabID: WebTabID
        private var observations: [NSKeyValueObservation] = []
        private let scrollMessageName: String
        private var scrollMessageHandler: WeakWebScriptMessageHandler?
        private let runtimeMessageName: String
        private var runtimeMessageHandler: WeakWebScriptMessageHandler?
        private var lastNavigationGeneration = -1
        private var lastReloadGeneration = -1
        private var lastStopGeneration = -1
        private var lastBackGeneration = -1
        private var lastForwardGeneration = -1
        private var lastFindGeneration = -1
        private var lastRequestedURL: URL?
        private var lastScrollY: Double?
        private var lastScrollPublishTime: CFTimeInterval = 0
        private var downloadsByID: [ObjectIdentifier: WorkspaceWebDownloadState] = [:]

        init(model: ConductorWindowModel, tabID: WebTabID) {
            self.model = model
            self.tabID = tabID
            self.webView = ConductorWebKitSurfaceStore.shared.webView(for: tabID)
            let stableID = tabID.rawValue.uuidString.replacingOccurrences(of: "-", with: "")
            self.scrollMessageName = "conductorScroll_\(stableID)"
            self.runtimeMessageName = "conductorRuntime_\(stableID)"

            super.init()

            webView.navigationDelegate = self
            webView.uiDelegate = self
            installScrollObserver()
            installRuntimeObserver()
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
                load(tab.url, force: !firstUpdate)
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
                } else {
                    navigateExplicitHistory(from: tab, delta: -1)
                }
            }
            if lastForwardGeneration == -1 {
                lastForwardGeneration = forwardGeneration
            } else if forwardGeneration != lastForwardGeneration {
                lastForwardGeneration = forwardGeneration
                if webView.canGoForward {
                    webView.goForward()
                } else {
                    navigateExplicitHistory(from: tab, delta: 1)
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

        private func installScrollObserver() {
            let handler = WeakWebScriptMessageHandler(delegate: self)
            scrollMessageHandler = handler
            let controller = webView.configuration.userContentController
            controller.removeScriptMessageHandler(forName: scrollMessageName)
            controller.add(handler, name: scrollMessageName)
            controller.addUserScript(WKUserScript(
                source: Self.scrollObserverScript(messageName: scrollMessageName),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
        }

        private func installRuntimeObserver() {
            let handler = WeakWebScriptMessageHandler(delegate: self)
            runtimeMessageHandler = handler
            let controller = webView.configuration.userContentController
            controller.removeScriptMessageHandler(forName: runtimeMessageName)
            controller.add(handler, name: runtimeMessageName)
            controller.addUserScript(WKUserScript(
                source: Self.runtimeObserverScript(messageName: runtimeMessageName),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
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
                let runtimeEntries = ConductorWebKitSurfaceStore.navigationEntries(for: webView)
                let runtimeIndex = ConductorWebKitSurfaceStore.currentNavigationIndex(for: webView)
                Self.mergeNavigationState(
                    currentURL: currentURL,
                    title: webView.title,
                    runtimeEntries: runtimeEntries,
                    runtimeIndex: runtimeIndex,
                    tab: &tab
                )
                let explicitIndex = tab.currentNavigationIndex
                tab.canGoBack = webView.canGoBack || (explicitIndex ?? 0) > 0
                tab.canGoForward = webView.canGoForward ||
                    explicitIndex.map { $0 < tab.navigationEntries.count - 1 } == true
                if webView.isLoading {
                    tab.errorMessage = nil
                }
            }
        }

        private func navigateExplicitHistory(from tab: WorkspaceWebTabState, delta: Int) {
            guard let index = tab.currentNavigationIndex else { return }
            let nextIndex = index + delta
            guard tab.navigationEntries.indices.contains(nextIndex) else { return }
            let entry = tab.navigationEntries[nextIndex]
            lastRequestedURL = entry.url
            model?.updateWorkspaceWebTab(tabID) { tab in
                tab.url = entry.url
                tab.pendingAddress = entry.url.absoluteString
                tab.title = entry.title ?? tab.title
                tab.currentNavigationIndex = nextIndex
                tab.canGoBack = nextIndex > 0
                tab.canGoForward = nextIndex < tab.navigationEntries.count - 1
                tab.isLoading = true
                tab.estimatedProgress = 0
                tab.errorMessage = nil
                tab.runtimeEvents.removeAll()
            }
            webView.load(URLRequest(url: entry.url))
        }

        private static func mergeNavigationState(
            currentURL: URL?,
            title: String?,
            runtimeEntries: [WorkspaceWebNavigationEntry],
            runtimeIndex: Int?,
            tab: inout WorkspaceWebTabState
        ) {
            if let currentURL,
               tab.navigationEntries.count > 1,
               let existingIndex = tab.navigationEntries.lastIndex(where: { $0.url.absoluteString == currentURL.absoluteString }) {
                tab.currentNavigationIndex = existingIndex
                tab.navigationEntries[existingIndex] = WorkspaceWebNavigationEntry(url: currentURL, title: title)
                return
            }

            if runtimeEntries.count > 1, let runtimeIndex {
                tab.navigationEntries = runtimeEntries
                tab.currentNavigationIndex = runtimeIndex
                return
            }

            guard let currentURL else { return }
            let currentEntry = WorkspaceWebNavigationEntry(url: currentURL, title: title)
            if tab.navigationEntries.isEmpty {
                tab.navigationEntries = [currentEntry]
                tab.currentNavigationIndex = 0
                return
            }

            let currentIndex = min(max(tab.currentNavigationIndex ?? (tab.navigationEntries.count - 1), 0), tab.navigationEntries.count - 1)
            tab.navigationEntries = Array(tab.navigationEntries.prefix(currentIndex + 1))
            tab.navigationEntries.append(currentEntry)
            tab.currentNavigationIndex = tab.navigationEntries.count - 1
        }

        private func restoreScrollIfNeeded(_ scrollY: Double?) {
            guard let scrollY, scrollY > 1 else { return }
            let script = Self.restoreScrollScript(y: scrollY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.webView.evaluateJavaScript(script) { _, _ in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                self?.webView.evaluateJavaScript(script) { _, _ in }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == runtimeMessageName {
                handleRuntimeMessage(message.body)
                return
            }
            guard message.name == scrollMessageName else { return }
            let rawY: Double?
            if let number = message.body as? NSNumber {
                rawY = number.doubleValue
            } else if let object = message.body as? [String: Any], let number = object["y"] as? NSNumber {
                rawY = number.doubleValue
            } else {
                rawY = nil
            }
            guard let scrollY = rawY, scrollY.isFinite else { return }
            let now = CACurrentMediaTime()
            if let lastScrollY, abs(lastScrollY - scrollY) < 8, now - lastScrollPublishTime < 0.35 {
                return
            }
            lastScrollY = scrollY
            lastScrollPublishTime = now
            model?.updateWorkspaceWebTab(tabID) { tab in
                tab.scrollY = max(0, scrollY)
            }
        }

        private func handleRuntimeMessage(_ body: Any) {
            guard let object = body as? [String: Any] else { return }
            let kindValue = Self.runtimeString(object["kind"])
            let kind: WorkspaceWebRuntimeEvent.Kind
            switch kindValue {
            case "pageError":
                kind = .pageError
            case "unhandledRejection":
                kind = .unhandledRejection
            default:
                kind = .console
            }
            let message = Self.runtimeString(object["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else { return }
            let event = WorkspaceWebRuntimeEvent(
                kind: kind,
                level: Self.runtimeString(object["level"], fallback: kind == .console ? "log" : "error"),
                message: message,
                sourceURL: Self.runtimeOptionalString(object["sourceURL"]),
                lineNumber: Self.runtimeInt(object["lineNumber"]),
                columnNumber: Self.runtimeInt(object["columnNumber"])
            )
            model?.recordWorkspaceWebRuntimeEvent(tabID, event: event)
        }

        private static func runtimeString(_ value: Any?, fallback: String = "") -> String {
            if let value = value as? String {
                return value
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            return fallback
        }

        private static func runtimeOptionalString(_ value: Any?) -> String? {
            let trimmed = runtimeString(value).trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private static func runtimeInt(_ value: Any?) -> Int? {
            if let value = value as? Int {
                return value
            }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let string = value as? String {
                return Int(string)
            }
            return nil
        }

        private static func scrollObserverScript(messageName: String) -> String {
            """
            (() => {
              if (window.__conductorScrollObserverInstalled) return;
              window.__conductorScrollObserverInstalled = true;
              const post = () => {
                try {
                  const scroller = document.scrollingElement || document.documentElement || document.body;
                  const y = window.pageYOffset || (scroller ? scroller.scrollTop : 0) || 0;
                  window.webkit.messageHandlers.\(messageName).postMessage({ y });
                } catch (_) {}
              };
              let scheduled = false;
              const schedule = () => {
                if (scheduled) return;
                scheduled = true;
                requestAnimationFrame(() => {
                  scheduled = false;
                  post();
                });
              };
              window.addEventListener("scroll", schedule, { passive: true });
              window.addEventListener("resize", schedule, { passive: true });
              setTimeout(post, 80);
            })();
            """
        }

        private static func runtimeObserverScript(messageName: String) -> String {
            """
            (() => {
              if (window.__conductorRuntimeObserverInstalled) return;
              window.__conductorRuntimeObserverInstalled = true;
              const clip = (value, limit = 1000) => String(value ?? "").replace(/\\s+/g, " ").trim().slice(0, limit);
              const serialize = (value) => {
                if (value instanceof Error) return value.stack || value.message || String(value);
                if (typeof value === "string") return value;
                try { return JSON.stringify(value); } catch (_) { return String(value); }
              };
              const post = (payload) => {
                try {
                  window.webkit.messageHandlers.\(messageName).postMessage({
                    kind: payload.kind || "console",
                    level: payload.level || "",
                    message: clip(payload.message),
                    sourceURL: payload.sourceURL || location.href,
                    lineNumber: Number.isFinite(payload.lineNumber) ? payload.lineNumber : null,
                    columnNumber: Number.isFinite(payload.columnNumber) ? payload.columnNumber : null
                  });
                } catch (_) {}
              };
              ["log", "info", "warn", "error"].forEach((level) => {
                const original = console[level];
                if (typeof original !== "function") return;
                console[level] = function(...args) {
                  post({
                    kind: "console",
                    level,
                    message: args.map(serialize).join(" ")
                  });
                  return original.apply(this, args);
                };
              });
              window.addEventListener("error", (event) => {
                post({
                  kind: "pageError",
                  level: "error",
                  message: event.message || serialize(event.error),
                  sourceURL: event.filename || location.href,
                  lineNumber: event.lineno,
                  columnNumber: event.colno
                });
              });
              window.addEventListener("unhandledrejection", (event) => {
                post({
                  kind: "unhandledRejection",
                  level: "error",
                  message: serialize(event.reason),
                  sourceURL: location.href
                });
              });
            })();
            """
        }

        private static func restoreScrollScript(y: Double) -> String {
            """
            (() => {
              const y = \(Int(max(0, y).rounded()));
              const scroller = document.scrollingElement || document.documentElement || document.body;
              try { window.scrollTo({ top: y, behavior: "instant" }); } catch (_) { window.scrollTo(0, y); }
              if (scroller) scroller.scrollTop = y;
              document.documentElement.scrollTop = y;
              if (document.body) document.body.scrollTop = y;
              return window.pageYOffset || (scroller ? scroller.scrollTop : 0) || 0;
            })();
            """
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
            model?.clearWorkspaceWebRuntimeEvents(tabID, reason: "navigation-start")
            publishState()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastRequestedURL = webView.url
            publishState()
            if let tab = model?.workspaceWebTabs.first(where: { $0.id == tabID }) {
                restoreScrollIfNeeded(tab.scrollY)
            }
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download, preferences)
            } else {
                decisionHandler(.allow, preferences)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            if shouldDownload(navigationResponse) {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable () -> Void
        ) {
            let alert = Self.makeJavaScriptDialog(
                title: L("网页提示", "Web Page Alert"),
                message: message,
                primaryButton: L("好", "OK")
            )
            runDialog(alert, webView: webView) { _ in
                completionHandler()
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
        ) {
            let alert = Self.makeJavaScriptDialog(
                title: L("网页确认", "Web Page Confirmation"),
                message: message,
                primaryButton: L("确认", "Confirm"),
                secondaryButton: L("取消", "Cancel")
            )
            runDialog(alert, webView: webView) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText: String?,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping @MainActor @Sendable (String?) -> Void
        ) {
            let input = NSTextField(string: defaultText ?? "")
            input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
            let alert = Self.makeJavaScriptDialog(
                title: L("网页输入", "Web Page Input"),
                message: prompt,
                primaryButton: L("确认", "Confirm"),
                secondaryButton: L("取消", "Cancel")
            )
            alert.accessoryView = input
            runDialog(alert, webView: webView) { response in
                completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
            }
        }

        private func runDialog(
            _ alert: NSAlert,
            webView: WKWebView,
            completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void
        ) {
            guard let window = webView.window else {
                completion(alert.runModal())
                return
            }
            alert.beginSheetModal(for: window) { response in
                Task { @MainActor in completion(response) }
            }
        }

        private static func makeJavaScriptDialog(
            title: String,
            message: String,
            primaryButton: String,
            secondaryButton: String? = nil
        ) -> NSAlert {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: primaryButton)
            if let secondaryButton {
                alert.addButton(withTitle: secondaryButton)
            }
            return alert
        }

        private func shouldDownload(_ navigationResponse: WKNavigationResponse) -> Bool {
            if !navigationResponse.canShowMIMEType {
                return true
            }
            guard let response = navigationResponse.response as? HTTPURLResponse,
                  let disposition = response.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() else {
                return false
            }
            return disposition.contains("attachment")
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            registerDownload(download, filenameHint: navigationAction.request.url?.lastPathComponent)
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            registerDownload(download, filenameHint: navigationResponse.response.suggestedFilename)
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
                let failed = WorkspaceWebDownloadState(
                    phase: .failed,
                    filename: filename,
                    errorMessage: L("无法定位下载目录", "Could not locate the Downloads folder")
                )
                recordDownload(download, state: failed)
                completionHandler(nil)
                return
            }
            let destination = uniqueDownloadDestination(in: downloadsURL, filename: filename)
            let state = WorkspaceWebDownloadState(
                phase: .downloading,
                filename: destination.lastPathComponent,
                destinationPath: destination.path
            )
            recordDownload(download, state: state)
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let identifier = ObjectIdentifier(download)
            let current = downloadsByID[identifier]
            let finished = WorkspaceWebDownloadState(
                phase: .finished,
                filename: current?.filename ?? L("下载", "Download"),
                destinationPath: current?.destinationPath
            )
            recordDownload(download, state: finished)
            downloadsByID.removeValue(forKey: identifier)
            publishState()
            model?.persistWorkspaceWebTabs()
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            let identifier = ObjectIdentifier(download)
            let current = downloadsByID[identifier]
            let failed = WorkspaceWebDownloadState(
                phase: .failed,
                filename: current?.filename ?? L("下载", "Download"),
                destinationPath: current?.destinationPath,
                errorMessage: error.localizedDescription
            )
            recordDownload(download, state: failed)
            downloadsByID.removeValue(forKey: identifier)
        }

        private func registerDownload(_ download: WKDownload, filenameHint: String?) {
            let filename = Self.cleanDownloadFilename(filenameHint) ?? L("下载", "Download")
            recordDownload(download, state: WorkspaceWebDownloadState(phase: .requested, filename: filename))
        }

        private func recordDownload(_ download: WKDownload, state: WorkspaceWebDownloadState) {
            downloadsByID[ObjectIdentifier(download)] = state
            model?.updateWorkspaceWebTabDownload(tabID, state: state)
            ConductorDiagnostics.record("browser-download-\(state.phase.rawValue)", fields: [
                "webTabID": tabID.rawValue.uuidString,
                "filename": state.filename,
                "hasDestination": state.destinationPath == nil ? "false" : "true"
            ])
        }

        private func uniqueDownloadDestination(in directory: URL, filename: String) -> URL {
            let sanitized = Self.cleanDownloadFilename(filename) ?? "download"
            let base = (sanitized as NSString).deletingPathExtension
            let ext = (sanitized as NSString).pathExtension
            var candidate = directory.appendingPathComponent(sanitized)
            var index = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                let suffix = ext.isEmpty ? "-\(index)" : "-\(index).\(ext)"
                candidate = directory.appendingPathComponent(base + suffix)
                index += 1
            }
            return candidate
        }

        private static func cleanDownloadFilename(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { return nil }
            let separators = CharacterSet(charactersIn: "/:")
            let parts = trimmed.components(separatedBy: separators).filter { !$0.isEmpty }
            return parts.last?.isEmpty == false ? parts.last : nil
        }
    }
}

private final class WeakWebScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
