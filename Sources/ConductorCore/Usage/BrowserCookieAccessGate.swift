import Foundation
import SweetCookieKit
#if os(macOS)
import Darwin
import LocalAuthentication
import Security
#endif

enum BrowserCookieStoreAccessDecision: Equatable {
    case allowed
    case suppressed
}

struct BrowserCookieStoreAccessSuppressedError: LocalizedError {
    var errorDescription: String? {
        "Browser cookie store access is suppressed for this process."
    }
}

public enum BrowserCookieAccessGate {
    private struct State {
        var loaded = false
        var deniedUntilByBrowser: [String: Date] = [:]
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var state = State()
    private static let defaultsKey = "conductor.browserCookieAccessDeniedUntil"
    private static let cooldownInterval: TimeInterval = 60 * 60 * 6
    static let allowTestCookieAccessEnvironmentKey = "CONDUCTOR_ALLOW_TEST_BROWSER_COOKIE_ACCESS"

    static func cookieStoreAccessDecision(
        homeDirectories: [URL],
        processName: String = ProcessInfo.processInfo.processName,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BrowserCookieStoreAccessDecision {
        guard isRunningUnderTests(processName: processName, environment: environment),
              environment[allowTestCookieAccessEnvironmentKey] != "1"
        else {
            return .allowed
        }

        let defaultHomes = Set(BrowserCookieClient.defaultHomeDirectories().map(normalizedPath))
        let usesDefaultHome = homeDirectories.contains { defaultHomes.contains(normalizedPath($0)) }
        return usesDefaultHome ? .suppressed : .allowed
    }

    public static func shouldAttempt(_ browser: Browser, now: Date = Date()) -> Bool {
        guard browser.usesKeychainForCookieDecryption else { return true }
        guard !BrowserCookieKeychainAccessGate.isDisabled else { return false }

        let canAttempt = withState { state in
            loadIfNeeded(&state)
            if let blockedUntil = state.deniedUntilByBrowser[browser.rawValue] {
                if blockedUntil > now {
                    return false
                }
                state.deniedUntilByBrowser.removeValue(forKey: browser.rawValue)
                persist(state)
            }
            return true
        }
        guard canAttempt else { return false }

        if chromiumKeychainRequiresInteraction(for: browser) {
            recordDenied(for: browser, now: now)
            return false
        }
        return true
    }

    public static func recordIfNeeded(_ error: Error, now: Date = Date()) {
        guard let cookieError = error as? BrowserCookieError,
              case .accessDenied = cookieError
        else {
            return
        }
        recordDenied(for: cookieError.browser, now: now)
    }

    public static func cookies(
        client: BrowserCookieClient,
        matching query: BrowserCookieQuery,
        in browser: Browser,
        now: Date = Date(),
        logger: ((String) -> Void)? = nil
    ) throws -> [HTTPCookie] {
        guard shouldAttempt(browser, now: now) else {
            throw BrowserCookieStoreAccessSuppressedError()
        }
        do {
            return try client.cookies(matching: query, in: browser, logger: logger)
        } catch {
            recordIfNeeded(error, now: now)
            throw error
        }
    }

    public static func recordDenied(for browser: Browser, now: Date = Date()) {
        guard browser.usesKeychainForCookieDecryption else { return }
        let blockedUntil = now.addingTimeInterval(cooldownInterval)
        withState { state in
            loadIfNeeded(&state)
            state.deniedUntilByBrowser[browser.rawValue] = blockedUntil
            persist(state)
        }
    }

    static func resetForTesting() {
        withState { state in
            state.loaded = true
            state.deniedUntilByBrowser.removeAll()
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private static func chromiumKeychainRequiresInteraction(for browser: Browser) -> Bool {
        #if os(macOS)
        let labels = browser.safeStorageLabels.isEmpty ? Browser.safeStorageLabels : browser.safeStorageLabels
        for label in labels {
            switch checkGenericPassword(service: label.service, account: label.account) {
            case .allowed:
                return false
            case .interactionRequired:
                return true
            case .notFound, .failure:
                continue
            }
        }
        #endif
        return false
    }

    private enum KeychainPreflightOutcome {
        case allowed
        case interactionRequired
        case notFound
        case failure
    }

    #if os(macOS)
    private static func checkGenericPassword(service: String, account: String?) -> KeychainPreflightOutcome {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        applyNoUIKeychainPolicy(to: &query)
        if let account {
            query[kSecAttrAccount as String] = account
        }

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            return .allowed
        case errSecItemNotFound:
            return .notFound
        case errSecInteractionNotAllowed:
            return .interactionRequired
        default:
            return .failure
        }
    }

    private static func applyNoUIKeychainPolicy(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = authenticationUIFailPolicy() as CFString
    }

    private static func authenticationUIFailPolicy() -> String {
        let securityPath = "/System/Library/Frameworks/Security.framework/Security"
        guard let handle = dlopen(securityPath, RTLD_NOW) else {
            return "u_AuthUIF"
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "kSecUseAuthenticationUIFail") else {
            return "u_AuthUIF"
        }
        let valuePointer = symbol.assumingMemoryBound(to: CFString?.self)
        return (valuePointer.pointee as String?) ?? "u_AuthUIF"
    }
    #endif

    private static func isRunningUnderTests(
        processName: String,
        environment: [String: String]
    ) -> Bool {
        processName == "swiftpm-testing-helper" ||
            processName.hasSuffix("PackageTests") ||
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["SWIFT_TESTING"] != nil
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func loadIfNeeded(_ state: inout State) {
        guard !state.loaded else { return }
        state.loaded = true
        guard let raw = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] else {
            return
        }
        state.deniedUntilByBrowser = raw.compactMapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func persist(_ state: State) {
        let raw = state.deniedUntilByBrowser.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(raw, forKey: defaultsKey)
    }

    @discardableResult
    private static func withState<T>(_ operation: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(&state)
    }
}

extension Browser {
    var usesKeychainForCookieDecryption: Bool {
        switch self {
        case .safari, .firefox, .zen:
            return false
        case .chrome, .chromeBeta, .chromeCanary,
             .arc, .arcBeta, .arcCanary,
             .chatgptAtlas,
             .chromium,
             .brave, .braveBeta, .braveNightly,
             .edge, .edgeBeta, .edgeCanary,
             .helium,
             .vivaldi,
             .dia,
             .yandex,
             .comet:
            return true
        @unknown default:
            return true
        }
    }
}
