#if os(macOS) && canImport(WebKit)
import AppKit
import CryptoKit
import Foundation
import WebKit

@MainActor
public enum OpenAIDashboardWebsiteDataStore {
    private static var cachedStores: [String: WKWebsiteDataStore] = [:]
    private static let clearTimeout: TimeInterval = 2

    public static func store(forAccountEmail email: String?) -> WKWebsiteDataStore {
        guard let normalized = cacheKey(forAccountEmail: email) else { return .nonPersistent() }
        if let cached = cachedStores[normalized] {
            return cached
        }
        let store = WKWebsiteDataStore(forIdentifier: identifier(forNormalizedEmail: normalized))
        cachedStores[normalized] = store
        return store
    }

    public static func installCookieHeader(
        _ cookieHeader: String,
        forAccountEmail email: String?,
        replacingExistingCookies: Bool
    ) async {
        let store = store(forAccountEmail: email)
        await installCookieHeader(
            cookieHeader,
            in: store,
            forAccountEmail: email,
            replacingExistingCookies: replacingExistingCookies)
    }

    public static func installCookies(
        _ cookieSnapshots: [OpenAIDashboardCookieSnapshot],
        fallbackCookieHeader: String,
        in store: WKWebsiteDataStore,
        forAccountEmail email: String?,
        replacingExistingCookies: Bool
    ) async {
        if cookieSnapshots.isEmpty {
            await installCookieHeader(
                fallbackCookieHeader,
                in: store,
                forAccountEmail: email,
                replacingExistingCookies: replacingExistingCookies)
            return
        }
        if replacingExistingCookies {
            OpenAIDashboardWebViewCache.shared.evict(accountEmail: email)
            await clearChatGPTData(in: store)
        }
        for snapshot in cookieSnapshots {
            guard let cookie = snapshot.makeHTTPCookie() else { continue }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    public static func installCookieHeader(
        _ cookieHeader: String,
        in store: WKWebsiteDataStore,
        forAccountEmail email: String?,
        replacingExistingCookies: Bool
    ) async {
        if replacingExistingCookies {
            OpenAIDashboardWebViewCache.shared.evict(accountEmail: email)
            await clearChatGPTData(in: store)
        }
        for cookie in cookies(from: cookieHeader) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    @discardableResult
    public static func clearStores(forAccountEmails emails: [String]) async -> Int {
        var cleared = 0
        var seen = Set<String>()
        for email in emails {
            guard let normalized = cacheKey(forAccountEmail: email), seen.insert(normalized).inserted else { continue }
            let store = store(forAccountEmail: normalized)
            OpenAIDashboardWebViewCache.shared.evict(accountEmail: normalized)
            await clearChatGPTData(in: store)
            cachedStores.removeValue(forKey: normalized)
            cleared += 1
        }
        return cleared
    }

    static func cacheKey(forAccountEmail email: String?) -> String? {
        normalizeEmail(email)
    }

    #if DEBUG
    static func normalizedEmailForTesting(_ email: String?) -> String? {
        normalizeEmail(email)
    }

    static func identifierForTesting(normalizedEmail email: String) -> UUID {
        identifier(forNormalizedEmail: cacheKey(forAccountEmail: email) ?? email)
    }

    static func clearCacheForTesting() {
        OpenAIDashboardWebViewCache.shared.evictAll()
        cachedStores.removeAll()
    }
    #endif

    private static func clearChatGPTData(in store: WKWebsiteDataStore) async {
        _ = NSApplication.shared
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let state = OneShotContinuation(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + clearTimeout) {
                state.resume()
            }
            store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
                let filtered = records.filter { record in
                    let name = record.displayName.lowercased()
                    return name.contains("chatgpt.com") || name.contains("openai.com")
                }
                guard !filtered.isEmpty else {
                    state.resume()
                    return
                }
                store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: filtered) {
                    state.resume()
                }
            }
        }
    }

    private static func cookies(from header: String) -> [HTTPCookie] {
        CookieHeaderNormalizer.pairs(from: header).flatMap { pair in
            cookieDomains.compactMap { domain in
                cookie(name: pair.name, value: pair.value, domain: domain)
            }
        }
    }

    private static let cookieDomains = ["chatgpt.com", "openai.com"]

    private static func cookie(name: String, value: String, domain: String) -> HTTPCookie? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .path: "/",
            .secure: "TRUE",
            .originURL: "https://\(domain)",
        ]
        if !name.hasPrefix("__Host-") {
            properties[.domain] = ".\(domain)"
        }
        return HTTPCookie(properties: properties)
    }

    private static func normalizeEmail(_ email: String?) -> String? {
        guard let raw = email?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.lowercased()
    }

    private static func identifier(forNormalizedEmail email: String) -> UUID {
        let digest = SHA256.hash(data: Data(email.utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let uuidBytes: uuid_t = (
            bytes[0],
            bytes[1],
            bytes[2],
            bytes[3],
            bytes[4],
            bytes[5],
            bytes[6],
            bytes[7],
            bytes[8],
            bytes[9],
            bytes[10],
            bytes[11],
            bytes[12],
            bytes[13],
            bytes[14],
            bytes[15])
        return UUID(uuid: uuidBytes)
    }

    private final class OneShotContinuation: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume()
        }
    }
}
#endif
