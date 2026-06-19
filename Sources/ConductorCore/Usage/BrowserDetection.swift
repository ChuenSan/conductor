import Foundation
import SweetCookieKit

#if os(macOS)
public final class BrowserDetection: @unchecked Sendable {
    public static let defaultCacheTTL: TimeInterval = 60 * 10

    private let lock = NSLock()
    private var cache: [CacheKey: CachedResult] = [:]
    private let homeDirectory: String
    private let cacheTTL: TimeInterval
    private let now: @Sendable () -> Date
    private let fileExists: @Sendable (String) -> Bool
    private let directoryContents: @Sendable (String) -> [String]?

    private struct CachedResult {
        let value: Bool
        let timestamp: Date
    }

    private enum ProbeKind: Int, Hashable {
        case appInstalled
        case usableProfileData
        case usableCookieStore
    }

    private struct CacheKey: Hashable {
        let browser: Browser
        let kind: ProbeKind
    }

    public init(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        cacheTTL: TimeInterval = BrowserDetection.defaultCacheTTL,
        now: @escaping @Sendable () -> Date = Date.init,
        fileExists: @escaping @Sendable (String) -> Bool = { path in FileManager.default.fileExists(atPath: path) },
        directoryContents: @escaping @Sendable (String) -> [String]? = { path in
            try? FileManager.default.contentsOfDirectory(atPath: path)
        })
    {
        self.homeDirectory = homeDirectory
        self.cacheTTL = cacheTTL
        self.now = now
        self.fileExists = fileExists
        self.directoryContents = directoryContents
    }

    public func isAppInstalled(_ browser: Browser) -> Bool {
        if browser == .safari {
            return true
        }
        return self.cachedBool(browser: browser, kind: .appInstalled) {
            self.detectAppInstalled(for: browser)
        }
    }

    public func isCookieSourceAvailable(_ browser: Browser) -> Bool {
        let homeURL = URL(fileURLWithPath: self.homeDirectory, isDirectory: true)
        guard BrowserCookieAccessGate.cookieStoreAccessDecision(homeDirectories: [homeURL]) == .allowed else {
            return false
        }

        if browser == .safari {
            return true
        }
        if self.requiresProfileValidation(browser) {
            return self.hasUsableCookieStore(browser)
        }
        return self.hasUsableProfileData(browser)
    }

    public func hasUsableProfileData(_ browser: Browser) -> Bool {
        self.cachedBool(browser: browser, kind: .usableProfileData) {
            self.detectUsableProfileData(for: browser)
        }
    }

    public func clearCache() {
        self.lock.lock()
        self.cache.removeAll()
        self.lock.unlock()
    }

    private func hasUsableCookieStore(_ browser: Browser) -> Bool {
        self.cachedBool(browser: browser, kind: .usableCookieStore) {
            self.detectUsableCookieStore(for: browser)
        }
    }

    private func cachedBool(browser: Browser, kind: ProbeKind, compute: () -> Bool) -> Bool {
        let now = self.now()
        let key = CacheKey(browser: browser, kind: kind)
        self.lock.lock()
        let cached = self.cache[key]
        self.lock.unlock()
        if let cached, now.timeIntervalSince(cached.timestamp) < self.cacheTTL {
            return cached.value
        }

        let result = compute()
        self.lock.lock()
        self.cache[key] = CachedResult(value: result, timestamp: now)
        self.lock.unlock()
        return result
    }

    private func detectAppInstalled(for browser: Browser) -> Bool {
        self.applicationPaths(for: browser).contains { self.fileExists($0) }
    }

    private func detectUsableProfileData(for browser: Browser) -> Bool {
        guard let profilePath = self.profilePath(for: browser),
              self.fileExists(profilePath)
        else {
            return false
        }

        if self.requiresProfileValidation(browser) {
            return self.hasValidProfileDirectory(for: browser, at: profilePath)
        }
        return true
    }

    private func detectUsableCookieStore(for browser: Browser) -> Bool {
        guard let profilePath = self.profilePath(for: browser),
              self.fileExists(profilePath)
        else {
            return false
        }
        return self.hasValidCookieStore(for: browser, at: profilePath)
    }

    private func applicationPaths(for browser: Browser) -> [String] {
        let appName = browser.appBundleName
        return [
            "/Applications/\(appName).app",
            "\(self.homeDirectory)/Applications/\(appName).app",
        ]
    }

    private func profilePath(for browser: Browser) -> String? {
        if browser == .safari {
            return "\(self.homeDirectory)/Library/Cookies/Cookies.binarycookies"
        }
        if let relativePath = browser.chromiumProfileRelativePath {
            return "\(self.homeDirectory)/Library/Application Support/\(relativePath)"
        }
        if let geckoFolder = browser.geckoProfilesFolder {
            return "\(self.homeDirectory)/Library/Application Support/\(geckoFolder)/Profiles"
        }
        return nil
    }

    private func requiresProfileValidation(_ browser: Browser) -> Bool {
        if browser == .safari || browser == .helium {
            return false
        }
        return browser.usesGeckoProfileStore || browser.usesChromiumProfileStore
    }

    private func hasValidProfileDirectory(for browser: Browser, at profilePath: String) -> Bool {
        guard let contents = self.directoryContents(profilePath) else { return false }
        if browser.usesGeckoProfileStore {
            return contents.contains { $0.range(of: ".default", options: [.caseInsensitive]) != nil }
        }
        return contents.contains { $0 == "Default" || $0.hasPrefix("Profile ") || $0.hasPrefix("user-") }
    }

    private func hasValidCookieStore(for browser: Browser, at profilePath: String) -> Bool {
        guard let contents = self.directoryContents(profilePath) else { return false }

        if browser.usesGeckoProfileStore {
            for name in contents where name.range(of: ".default", options: [.caseInsensitive]) != nil {
                if self.fileExists("\(profilePath)/\(name)/cookies.sqlite") {
                    return true
                }
            }
            return false
        }

        for name in contents where name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-") {
            if self.fileExists("\(profilePath)/\(name)/Cookies") ||
                self.fileExists("\(profilePath)/\(name)/Network/Cookies")
            {
                return true
            }
        }
        return false
    }
}

extension [Browser] {
    func cookieImportCandidates(using detection: BrowserDetection) -> [Browser] {
        let candidates = self.filter { browser in
            if BrowserCookieKeychainAccessGate.isDisabled, browser.usesKeychainForCookieDecryption {
                return false
            }
            return detection.isCookieSourceAvailable(browser)
        }
        return candidates.filter { BrowserCookieAccessGate.shouldAttempt($0) }
    }
}
#endif
