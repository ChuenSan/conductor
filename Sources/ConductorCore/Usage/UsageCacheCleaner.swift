import Foundation

public enum UsageCacheCleaner {
    @discardableResult
    public static func clearProviderCaches(
        cacheRoot: URL? = nil,
        applicationSupportRoot: URL? = nil) -> [URL]
    {
        clearCookieDerivedCaches(cacheRoot: cacheRoot, applicationSupportRoot: applicationSupportRoot)
            + clearQuotaWarningState(applicationSupportRoot: applicationSupportRoot)
            + clearUsageSnapshotHydration(applicationSupportRoot: applicationSupportRoot)
    }

    @discardableResult
    public static func clearDashboardCaches(cacheRoot: URL? = nil) -> [URL] {
        removeCacheFileIfExists(OpenAIDashboardCacheStore.cacheURL(cacheRoot: cacheRoot))
            + OpenAIDashboardCreditHistoryStore.clearAll(cacheRoot: cacheRoot)
    }

    @discardableResult
    public static func clearCookieDerivedCaches(
        providerID: String? = nil,
        cacheRoot: URL? = nil,
        applicationSupportRoot _: URL? = nil) -> [URL]
    {
        guard let providerID = providerID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !providerID.isEmpty
        else {
            return clearOpenAICookieDerivedCaches(cacheRoot: cacheRoot)
                + clearCookieHeaderCaches(providerIDs: allCookieHeaderCacheProviderIDs)
        }

        switch providerID {
        case "codex", "openai":
            return clearOpenAICookieDerivedCaches(cacheRoot: cacheRoot)
        default:
            return clearCookieHeaderCaches(providerIDs: [providerID])
        }
    }

    @discardableResult
    public static func clearCookieDerivedCachesIncludingWebKit(
        providerID: String? = nil,
        cacheRoot: URL? = nil,
        applicationSupportRoot: URL? = nil) async -> [URL]
    {
        var removed = clearCookieDerivedCaches(
            providerID: providerID,
            cacheRoot: cacheRoot,
            applicationSupportRoot: applicationSupportRoot)

        #if os(macOS) && canImport(WebKit)
        if shouldClearOpenAIDashboardStores(providerID: providerID) {
            let emails = CodexManagedAccountDiscovery.accountEmails()
            if emails.isEmpty {
                await OpenAIDashboardWebViewCache.shared.evictAll()
            }
            let cleared = await OpenAIDashboardWebsiteDataStore.clearStores(forAccountEmails: emails)
            if cleared > 0 {
                removed.append(URL(fileURLWithPath: "/__conductor_openai_dashboard_webkit_stores__"))
            }
        }
        #endif

        return removed
    }

    @discardableResult
    public static func clearUIPanelUsageCaches(applicationSupportRoot: URL? = nil) -> [URL] {
        let root = applicationSupportRoot ?? defaultApplicationSupportRoot()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil)
        else { return [] }

        var removed: [URL] = []
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("usage-"), name.hasSuffix("d.json") else { continue }
            guard name.dropFirst("usage-".count).dropLast("d.json".count).allSatisfy(\.isNumber) else { continue }
            try? FileManager.default.removeItem(at: file)
            removed.append(file)
        }
        return removed
    }

    @discardableResult
    public static func clearQuotaWarningState(applicationSupportRoot: URL? = nil) -> [URL] {
        removeCacheFileIfExists(quotaWarningStateURL(applicationSupportRoot: applicationSupportRoot))
    }

    @discardableResult
    public static func clearUsageSnapshotHydration(applicationSupportRoot: URL? = nil) -> [URL] {
        UsageSnapshotHydrationStore.clear(applicationSupportRoot: applicationSupportRoot)
    }

    public static func quotaWarningStateURL(applicationSupportRoot: URL? = nil) -> URL {
        let root = applicationSupportRoot ?? defaultApplicationSupportRoot()
        return root.appendingPathComponent("usage-quota-warning-state.json", isDirectory: false)
    }

    public static func defaultApplicationSupportRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conductor", isDirectory: true)
    }

    @discardableResult
    public static func removeCacheFileIfExists(_ url: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try? FileManager.default.removeItem(at: url)
        return [url]
    }

    private static func shouldClearOpenAIDashboardStores(providerID: String?) -> Bool {
        guard let providerID = providerID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !providerID.isEmpty
        else {
            return true
        }
        return providerID == "codex" || providerID == "openai"
    }

    private static func clearOpenAICookieDerivedCaches(cacheRoot: URL?) -> [URL] {
        var removed = clearDashboardCaches(cacheRoot: cacheRoot)
        if CookieHeaderCache.clear(providerID: "codex") > 0 {
            removed.append(cookieHeaderCacheMarker(providerID: "codex"))
        }
        return removed
    }

    private static func clearCookieHeaderCaches(providerIDs: Set<String>) -> [URL] {
        providerIDs
            .filter { $0 != "codex" && $0 != "openai" }
            .sorted()
            .compactMap { providerID in
                CookieHeaderCache.clear(providerID: providerID) > 0
                    ? cookieHeaderCacheMarker(providerID: providerID)
                    : nil
            }
    }

    private static var allCookieHeaderCacheProviderIDs: Set<String> {
        var ids = Set(UsageProviderConfigCapabilities.cookieHeaderEnvironmentNames.keys)
        for (providerID, support) in UsageProviderConfigCapabilities.tokenAccountSupportByProviderID {
            if case .cookieHeader = support.injection {
                ids.insert(providerID)
            }
        }
        ids.insert("codex")
        return ids
    }

    private static func cookieHeaderCacheMarker(providerID: String) -> URL {
        let safe = providerID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .map { character -> Character in
                character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
            }
        return URL(fileURLWithPath: "/__conductor_\(String(safe))_cookie_header_cache__")
    }
}
