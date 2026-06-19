import Foundation

#if os(macOS)
import SweetCookieKit

enum MiniMaxLocalStorageImporter {
    struct TokenInfo {
        let accessToken: String
        let groupID: String?
        let sourceLabel: String
    }

    private static let chromiumBrowsers: [Browser] = [
        .chrome,
        .chromeBeta,
        .chromeCanary,
        .edge,
        .edgeBeta,
        .edgeCanary,
        .brave,
        .braveBeta,
        .braveNightly,
        .vivaldi,
        .arc,
        .arcBeta,
        .arcCanary,
        .dia,
        .chatgptAtlas,
        .chromium,
        .helium,
    ]

    private static let origins = [
        "https://platform.minimax.io",
        "https://www.minimax.io",
        "https://minimax.io",
        "https://platform.minimaxi.com",
        "https://www.minimaxi.com",
        "https://minimaxi.com",
    ]

    static func importAccessTokens(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil
    ) -> [TokenInfo] {
        let log: (String) -> Void = { message in logger?("[minimax-storage] \(message)") }
        var tokens: [TokenInfo] = []

        for candidate in chromeLocalStorageCandidates(browserDetection: browserDetection) {
            let snapshot = readLocalStorage(from: candidate.url, logger: log)
            guard !snapshot.tokens.isEmpty else { continue }
            let groupID = snapshot.groupID ?? groupID(fromJWT: snapshot.tokens.first ?? "")
            for token in snapshot.tokens {
                tokens.append(TokenInfo(accessToken: token, groupID: groupID, sourceLabel: candidate.label))
            }
        }

        if tokens.isEmpty {
            for candidate in chromeSessionStorageCandidates(browserDetection: browserDetection) {
                for token in readSessionStorageTokens(from: candidate.url, logger: log) {
                    tokens.append(TokenInfo(
                        accessToken: token,
                        groupID: groupID(fromJWT: token),
                        sourceLabel: candidate.label))
                }
            }
        }

        if tokens.isEmpty {
            for candidate in chromeIndexedDBCandidates(browserDetection: browserDetection) {
                for token in readIndexedDBTokens(from: candidate.url, logger: log) {
                    tokens.append(TokenInfo(
                        accessToken: token,
                        groupID: groupID(fromJWT: token),
                        sourceLabel: candidate.label))
                }
            }
        }

        if tokens.isEmpty {
            log("No MiniMax access token found in browser storage")
        }
        return tokens
    }

    static func importGroupIDs(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil
    ) -> [String: String] {
        let log: (String) -> Void = { message in logger?("[minimax-storage] \(message)") }
        var results: [String: String] = [:]
        for candidate in chromeLocalStorageCandidates(browserDetection: browserDetection) {
            guard results[candidate.label] == nil else { continue }
            let snapshot = readLocalStorage(from: candidate.url, logger: log)
            if let groupID = snapshot.groupID {
                results[candidate.label] = groupID
            }
        }
        return results
    }

    private struct StorageCandidate {
        let label: String
        let url: URL
    }

    private static func profileBrowsers(using browserDetection: BrowserDetection) -> [Browser] {
        chromiumBrowsers.filter { browser in
            browser.usesChromiumProfileStore && browserDetection.hasUsableProfileData(browser)
        }
    }

    private static func profileDirs(root: URL) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else {
            return []
        }
        return entries.filter { url in
            guard let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory),
                  isDirectory
            else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func chromeLocalStorageCandidates(browserDetection: BrowserDetection) -> [StorageCandidate] {
        ChromiumProfileLocator.roots(
            for: profileBrowsers(using: browserDetection),
            homeDirectories: BrowserCookieClient.defaultHomeDirectories())
            .flatMap { root in
                profileDirs(root: root.url).compactMap { profile in
                    let url = profile.appendingPathComponent("Local Storage").appendingPathComponent("leveldb")
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return StorageCandidate(label: "\(root.labelPrefix) \(profile.lastPathComponent)", url: url)
                }
            }
    }

    private static func chromeSessionStorageCandidates(browserDetection: BrowserDetection) -> [StorageCandidate] {
        ChromiumProfileLocator.roots(
            for: profileBrowsers(using: browserDetection),
            homeDirectories: BrowserCookieClient.defaultHomeDirectories())
            .flatMap { root in
                profileDirs(root: root.url).compactMap { profile in
                    let url = profile.appendingPathComponent("Session Storage")
                    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                    return StorageCandidate(
                        label: "\(root.labelPrefix) \(profile.lastPathComponent) (Session Storage)",
                        url: url)
                }
            }
    }

    private static func chromeIndexedDBCandidates(browserDetection: BrowserDetection) -> [StorageCandidate] {
        let targetPrefixes = [
            "https_platform.minimax.io_",
            "https_www.minimax.io_",
            "https_minimax.io_",
            "https_platform.minimaxi.com_",
            "https_www.minimaxi.com_",
            "https_minimaxi.com_",
        ]

        return ChromiumProfileLocator.roots(
            for: profileBrowsers(using: browserDetection),
            homeDirectories: BrowserCookieClient.defaultHomeDirectories())
            .flatMap { root in
                profileDirs(root: root.url).flatMap { profile -> [StorageCandidate] in
                    let indexedDBRoot = profile.appendingPathComponent("IndexedDB")
                    guard let entries = try? FileManager.default.contentsOfDirectory(
                        at: indexedDBRoot,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles])
                    else {
                        return []
                    }
                    return entries.compactMap { entry in
                        guard let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory),
                              isDirectory,
                              entry.lastPathComponent.hasSuffix(".indexeddb.leveldb"),
                              targetPrefixes.contains(where: { entry.lastPathComponent.hasPrefix($0) })
                        else {
                            return nil
                        }
                        return StorageCandidate(
                            label: "\(root.labelPrefix) \(profile.lastPathComponent) (IndexedDB)",
                            url: entry)
                    }
                }
            }
    }

    private struct LocalStorageSnapshot {
        let tokens: [String]
        let groupID: String?
    }

    private static func readLocalStorage(
        from levelDBURL: URL,
        logger: ((String) -> Void)? = nil
    ) -> LocalStorageSnapshot {
        var entries: [ChromiumLocalStorageEntry] = []
        for origin in origins {
            entries.append(contentsOf: ChromiumLocalStorageReader.readEntries(
                for: origin,
                in: levelDBURL,
                logger: logger))
        }

        var tokens: [String] = []
        var seen = Set<String>()
        var groupID: String?
        var hasMinimaxSignal = !entries.isEmpty

        func appendTokens(from value: String, requireMiniMaxJWT: Bool) {
            for token in extractAccessTokens(from: value) where !seen.contains(token) {
                if requireMiniMaxJWT, token.contains("."), !isMiniMaxJWT(token) {
                    continue
                }
                seen.insert(token)
                tokens.append(token)
            }
        }

        for entry in entries {
            appendTokens(from: entry.value, requireMiniMaxJWT: false)
            if groupID == nil, let match = extractGroupID(from: entry.value) {
                groupID = match
            }
        }

        if tokens.isEmpty {
            let textEntries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL, logger: logger)
            let candidates = textEntries.filter { entry in
                let key = entry.key.lowercased()
                let value = entry.value.lowercased()
                return key.contains("minimax.io") || value.contains("minimax.io") ||
                    key.contains("minimaxi.com") || value.contains("minimaxi.com")
            }
            hasMinimaxSignal = hasMinimaxSignal || !candidates.isEmpty
            for entry in candidates {
                appendTokens(from: entry.value, requireMiniMaxJWT: true)
                if groupID == nil, let match = extractGroupID(from: entry.value) {
                    groupID = match
                }
            }
        }

        if tokens.isEmpty, hasMinimaxSignal {
            for candidate in ChromiumLocalStorageReader.readTokenCandidates(
                in: levelDBURL,
                minimumLength: 60,
                logger: logger)
            where looksLikeToken(candidate) && isMiniMaxJWT(candidate) && !seen.contains(candidate)
            {
                seen.insert(candidate)
                tokens.append(candidate)
                if groupID == nil {
                    groupID = Self.groupID(fromJWT: candidate)
                }
            }
        }

        return LocalStorageSnapshot(tokens: tokens, groupID: groupID)
    }

    private static func readSessionStorageTokens(
        from levelDBURL: URL,
        logger: ((String) -> Void)? = nil
    ) -> [String] {
        let entries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL, logger: logger)
        let mapIDs = sessionStorageMapIDs(in: entries)
        guard !mapIDs.isEmpty else { return [] }

        var tokens: [String] = []
        var seen = Set<String>()
        for entry in entries {
            guard let mapID = sessionStorageMapID(fromKey: entry.key),
                  mapIDs.contains(mapID)
            else {
                continue
            }
            for token in extractAccessTokens(from: entry.value) where !seen.contains(token) {
                seen.insert(token)
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func readIndexedDBTokens(
        from levelDBURL: URL,
        logger: ((String) -> Void)? = nil
    ) -> [String] {
        let entries = ChromiumLocalStorageReader.readTextEntries(in: levelDBURL, logger: logger)
        var tokens: [String] = []
        var seen = Set<String>()
        for entry in entries {
            for token in extractAccessTokens(from: entry.value) where !seen.contains(token) {
                seen.insert(token)
                tokens.append(token)
            }
        }
        if tokens.isEmpty {
            for candidate in ChromiumLocalStorageReader.readTokenCandidates(
                in: levelDBURL,
                minimumLength: 60,
                logger: logger)
            where looksLikeToken(candidate) && !seen.contains(candidate)
            {
                seen.insert(candidate)
                tokens.append(candidate)
            }
        }
        return tokens
    }

    private static func sessionStorageMapIDs(in entries: [ChromiumLevelDBTextEntry]) -> Set<Int> {
        var mapIDs = Set<Int>()
        for entry in entries where entry.key.hasPrefix("namespace-") {
            guard origins.contains(where: { entry.key.localizedCaseInsensitiveContains($0) }),
                  let mapID = Int(entry.value.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                continue
            }
            mapIDs.insert(mapID)
        }
        return mapIDs
    }

    private static func sessionStorageMapID(fromKey key: String) -> Int? {
        guard key.hasPrefix("map-") else { return nil }
        let parts = key.split(separator: "-", maxSplits: 2)
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    private static func extractAccessTokens(from value: String) -> [String] {
        var tokens = Set<String>()
        let patterns = [
            #"access_token[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
            #"accessToken[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
            #"id_token[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
            #"idToken[^A-Za-z0-9._\-+=/]+([A-Za-z0-9._\-+=/]{20,})"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            for match in regex.matches(in: value, range: range) {
                guard match.numberOfRanges > 1,
                      let tokenRange = Range(match.range(at: 1), in: value)
                else {
                    continue
                }
                tokens.insert(String(value[tokenRange]))
            }
        }

        tokens.formUnion(extractTokensFromJSON(value) ?? [])
        tokens.formUnion(matchJWTs(in: value) ?? [])

        let preferred = tokens.filter { $0.count >= 60 }
        return Array(preferred.isEmpty ? tokens : preferred)
    }

    private static func extractTokensFromJSON(_ value: String) -> [String]? {
        guard let data = value.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }
        return collectTokens(from: json)
    }

    private static func collectTokens(from value: Any) -> [String] {
        switch value {
        case let dict as [String: Any]:
            return dict.flatMap { key, child in
                if tokenKeys.contains(key),
                   let string = child as? String,
                   looksLikeToken(string)
                {
                    return [string]
                }
                return collectTokens(from: child)
            }
        case let array as [Any]:
            return array.flatMap { collectTokens(from: $0) }
        case let string as String:
            if looksLikeToken(string) {
                return [string]
            }
            return extractTokensFromJSON(string) ?? []
        default:
            return []
        }
    }

    private static let tokenKeys: Set<String> = [
        "access_token",
        "accessToken",
        "id_token",
        "idToken",
        "token",
        "authToken",
        "authorization",
        "bearer",
    ]

    private static func looksLikeToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("."), trimmed.split(separator: ".").count >= 3 {
            return trimmed.count >= 60
        }
        return trimmed.count >= 60 &&
            trimmed.range(of: #"^[A-Za-z0-9._\-+=/]+$"#, options: .regularExpression) != nil
    }

    private static func matchJWTs(in value: String) -> [String]? {
        let pattern = #"[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty else { return nil }
        return matches.compactMap { match in
            guard let tokenRange = Range(match.range(at: 0), in: value) else { return nil }
            return String(value[tokenRange])
        }
    }

    private static func isMiniMaxJWT(_ token: String) -> Bool {
        guard let claims = decodeJWTClaims(token) else { return false }
        if let issuer = claims["iss"] as? String,
           issuer.localizedCaseInsensitiveContains("minimax")
        {
            return true
        }
        return ["GroupID", "GroupName", "UserName", "SubjectID", "Mail", "TokenType"]
            .contains { claims[$0] != nil }
    }

    private static func extractGroupID(from value: String) -> String? {
        if let data = value.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let match = extractGroupID(from: json)
        {
            return match
        }

        for marker in ["groups\":[", "groupId\":\"", "group_id\":\""] {
            guard let range = value.range(of: marker) else { continue }
            let tail = String(value[range.upperBound...].prefix(200))
            if let match = longestDigitSequence(in: tail) {
                return match
            }
        }
        return nil
    }

    private static func extractGroupID(from value: Any) -> String? {
        switch value {
        case let dict as [String: Any]:
            for (key, child) in dict {
                if key.lowercased().contains("group"),
                   let match = stringID(from: child)
                {
                    return match
                }
                if let nested = extractGroupID(from: child) {
                    return nested
                }
            }
        case let array as [Any]:
            for child in array {
                if let match = extractGroupID(from: child) {
                    return match
                }
            }
        default:
            break
        }
        return nil
    }

    private static func groupID(fromJWT token: String) -> String? {
        guard token.contains("."),
              let claims = decodeJWTClaims(token)
        else {
            return nil
        }

        for key in ["group_id", "groupId", "groupID", "gid", "tenant_id", "tenantId", "org_id", "orgId"] {
            if let match = stringID(from: claims[key]) {
                return match
            }
        }
        for (key, value) in claims where key.lowercased().contains("group") {
            if let match = stringID(from: value) {
                return match
            }
        }
        return nil
    }

    private static func decodeJWTClaims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2,
              let data = base64URLDecode(String(parts[1])),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: padding)
        }
        return Data(base64Encoded: base64)
    }

    private static func stringID(from value: Any?) -> String? {
        switch value {
        case let number as Int:
            return String(number)
        case let number as Int64:
            return String(number)
        case let number as NSNumber:
            return number.stringValue
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let match = longestDigitSequence(in: trimmed) {
                return match
            }
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }

    private static func longestDigitSequence(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"[0-9]{4,}"#) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let candidates = regex.matches(in: text, range: range).compactMap { match -> String? in
            guard let tokenRange = Range(match.range(at: 0), in: text) else { return nil }
            return String(text[tokenRange])
        }
        return candidates.max { $0.count < $1.count }
    }
}

extension MiniMaxLocalStorageImporter {
    static func _extractAccessTokensForTesting(_ value: String) -> [String] {
        extractAccessTokens(from: value)
    }

    static func _extractGroupIDForTesting(_ value: String) -> String? {
        extractGroupID(from: value)
    }

    static func _groupIDFromJWTForTesting(_ token: String) -> String? {
        groupID(fromJWT: token)
    }

    static func _isMiniMaxJWTForTesting(_ token: String) -> Bool {
        isMiniMaxJWT(token)
    }
}
#endif
