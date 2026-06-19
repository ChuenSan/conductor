#if os(macOS) && canImport(WebKit)
import Foundation
import WebKit

@MainActor
final class OpenAIDashboardNavigationDelegate: NSObject, WKNavigationDelegate {
    private let completion: (Result<Void, Error>) -> Void
    private var completed = false
    private var timeoutWorkItem: DispatchWorkItem?
    private var postCommitWorkItem: DispatchWorkItem?
    nonisolated static let postCommitSuccessDelay: TimeInterval = 0.75

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func armTimeout(seconds: TimeInterval) {
        timeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.completeOnce(.failure(URLError(.timedOut)))
            }
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(seconds, 0.1), execute: workItem)
    }

    func cancel() {
        completeOnce(.failure(CancellationError()))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        completeOnce(.success(()))
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard !completed else { return }
        postCommitWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.completeOnce(.success(()))
            }
        }
        postCommitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.postCommitSuccessDelay, execute: workItem)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if Self.shouldIgnoreNavigationError(error) { return }
        completeOnce(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if Self.shouldIgnoreNavigationError(error) { return }
        completeOnce(.failure(error))
    }

    nonisolated static func shouldIgnoreNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            return true
        }
        return false
    }

    private func completeOnce(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        postCommitWorkItem?.cancel()
        postCommitWorkItem = nil
        completion(result)
    }
}
#endif
