import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ModelsDevPricingInfo: Codable, Equatable, Sendable {
    public var providerID: String
    public var providerName: String?
    public var modelID: String
    public var modelName: String?
    public var inputCostPerM: Double
    public var outputCostPerM: Double
    public var cacheReadInputCostPerM: Double?
    public var cacheCreationInputCostPerM: Double?
    public var contextWindow: Int?
    public var thresholdTokens: Int?
    public var inputCostPerMAboveThreshold: Double?
    public var outputCostPerMAboveThreshold: Double?
    public var cacheReadInputCostPerMAboveThreshold: Double?
    public var cacheCreationInputCostPerMAboveThreshold: Double?
}

public struct ModelsDevPricingLookup: Equatable, Sendable {
    public var pricing: ModelsDevPricingInfo
    public var normalizedModelID: String
}

public struct ModelsDevCatalog: Codable, Equatable, Sendable {
    public var providers: [String: ModelsDevProvider]

    public init(providers: [String: ModelsDevProvider]) {
        self.providers = providers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ModelsDevAnyCodingKey.self)
        if let providersKey = ModelsDevAnyCodingKey(stringValue: "providers"),
           let decoded = try? container.decode([String: ModelsDevProvider].self, forKey: providersKey)
        {
            self.providers = decoded.reduce(into: [:]) { result, item in
                var provider = item.value
                provider.mapKey = provider.mapKey ?? item.key
                let providerID = ModelsDevProvider.normalizeProviderID(provider.id ?? item.key)
                result[providerID] = provider
            }
            return
        }

        var providers: [String: ModelsDevProvider] = [:]
        for key in container.allKeys {
            guard var provider = try? container.decode(ModelsDevProvider.self, forKey: key) else { continue }
            provider.mapKey = key.stringValue
            let providerID = ModelsDevProvider.normalizeProviderID(provider.id ?? key.stringValue)
            providers[providerID] = provider
        }
        self.providers = providers
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ModelsDevAnyCodingKey.self)
        try container.encode(self.providers, forKey: ModelsDevAnyCodingKey(stringValue: "providers")!)
    }

    public func pricing(providerID rawProviderID: String, modelID rawModelID: String) -> ModelsDevPricingLookup? {
        let providerID = ModelsDevProvider.normalizeProviderID(rawProviderID)
        return providers[providerID]?.pricing(modelID: rawModelID)
    }

    public func isPlausibleRefresh() -> Bool {
        ["anthropic", "openai"].allSatisfy { providerID in
            providers[providerID]?.models.values.contains(where: \.isPriceable) == true
        }
    }

    public func mergingFallbackPricing(from cachedCatalog: ModelsDevCatalog) -> ModelsDevCatalog {
        var merged = self
        for (providerID, cachedProvider) in cachedCatalog.providers {
            let normalizedProviderID = ModelsDevProvider.normalizeProviderID(providerID)
            guard var provider = merged.providers[normalizedProviderID] else {
                merged.providers[normalizedProviderID] = cachedProvider
                continue
            }
            for (modelKey, cachedModel) in cachedProvider.models
                where cachedModel.isPriceable && !provider.containsPricedModel(
                    withStableIdentity: cachedModel.stableIdentity)
            {
                let fallbackKey = provider.models[modelKey] == nil
                    ? modelKey
                    : "conductor-fallback:\(modelKey):\(cachedModel.normalizedID)"
                provider.models[fallbackKey] = cachedModel
            }
            merged.providers[normalizedProviderID] = provider
        }
        return merged
    }
}

public struct ModelsDevAnyCodingKey: CodingKey, Sendable {
    public var intValue: Int?
    public var stringValue: String

    public init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = String(intValue)
    }

    public init?(stringValue: String) {
        self.intValue = nil
        self.stringValue = stringValue
    }
}

public struct ModelsDevProvider: Codable, Equatable, Sendable {
    public var id: String?
    public var name: String?
    public var models: [String: ModelsDevModel]
    public var mapKey: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case models
    }

    public init(id: String?, name: String?, models: [String: ModelsDevModel], mapKey: String? = nil) {
        self.id = id
        self.name = name
        self.models = models
        self.mapKey = mapKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        let modelContainer = try container.nestedContainer(keyedBy: ModelsDevAnyCodingKey.self, forKey: .models)
        var models: [String: ModelsDevModel] = [:]
        for key in modelContainer.allKeys {
            guard let model = try? modelContainer.decode(ModelsDevModel.self, forKey: key) else { continue }
            models[key.stringValue] = model
        }
        self.models = models
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(models, forKey: .models)
    }

    public static func normalizeProviderID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func pricing(modelID rawModelID: String) -> ModelsDevPricingLookup? {
        for candidate in ModelsDevModelIDNormalizer.candidates(rawModelID) {
            if let model = models[candidate],
               let pricing = model.pricing(providerID: id ?? mapKey ?? "", providerName: name)
            {
                return ModelsDevPricingLookup(pricing: pricing, normalizedModelID: candidate)
            }
            for match in models.values where match.normalizedID == candidate {
                if let pricing = match.pricing(providerID: id ?? mapKey ?? "", providerName: name) {
                    return ModelsDevPricingLookup(pricing: pricing, normalizedModelID: match.normalizedID)
                }
            }
        }
        return nil
    }

    public func containsPricedModel(withStableIdentity modelID: String) -> Bool {
        models.values.contains { model in
            model.isPriceable && model.stableIdentity == modelID
        }
    }
}

public struct ModelsDevModel: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var cost: ModelsDevCost?
    public var limit: ModelsDevLimit?

    public var normalizedID: String { ModelsDevModelIDNormalizer.normalize(id) }
    public var stableIdentity: String { ModelsDevModelIDNormalizer.stableIdentity(id) }
    public var isPriceable: Bool { cost?.input != nil && cost?.output != nil }

    public func pricing(providerID: String, providerName: String?) -> ModelsDevPricingInfo? {
        guard let input = cost?.input, let output = cost?.output else { return nil }
        let over200K = cost?.contextOver200K
        return ModelsDevPricingInfo(
            providerID: ModelsDevProvider.normalizeProviderID(providerID),
            providerName: providerName,
            modelID: id,
            modelName: name,
            inputCostPerM: input,
            outputCostPerM: output,
            cacheReadInputCostPerM: cost?.cacheRead,
            cacheCreationInputCostPerM: cost?.cacheWrite,
            contextWindow: limit?.context,
            thresholdTokens: over200K == nil ? nil : 200_000,
            inputCostPerMAboveThreshold: over200K?.input,
            outputCostPerMAboveThreshold: over200K?.output,
            cacheReadInputCostPerMAboveThreshold: over200K?.cacheRead,
            cacheCreationInputCostPerMAboveThreshold: over200K?.cacheWrite)
    }
}

public struct ModelsDevCost: Codable, Equatable, Sendable {
    public var input: Double?
    public var output: Double?
    public var cacheRead: Double?
    public var cacheWrite: Double?
    public var contextOver200K: ModelsDevContextOver200KCost?

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case contextOver200K = "context_over_200k"
    }
}

public struct ModelsDevContextOver200KCost: Codable, Equatable, Sendable {
    public var input: Double?
    public var output: Double?
    public var cacheRead: Double?
    public var cacheWrite: Double?

    private enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }
}

public struct ModelsDevLimit: Codable, Equatable, Sendable {
    public var context: Int?
}

public enum ModelsDevModelIDNormalizer {
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func stableIdentity(_ raw: String) -> String {
        let normalized = normalize(raw)
        if let atSign = normalized.firstIndex(of: "@") {
            let base = String(normalized[..<atSign])
            let suffix = String(normalized[normalized.index(after: atSign)...])
            if suffix.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
                return "\(canonicalAliasIdentity(base))-\(suffix)"
            }
        }
        return canonicalAliasIdentity(normalized)
    }

    public static func candidates(_ raw: String, preserveDatedSnapshots: Bool = false) -> [String] {
        var candidates: [String] = []
        func append(_ value: String) {
            let normalized = normalize(value)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { return }
            candidates.append(normalized)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        append(trimmed)
        if trimmed.hasPrefix("openai/") {
            append(String(trimmed.dropFirst("openai/".count)))
        }
        if trimmed.hasPrefix("anthropic.") {
            append(String(trimmed.dropFirst("anthropic.".count)))
        }
        if let lastDot = trimmed.lastIndex(of: "."), trimmed.contains("claude-") {
            let tail = String(trimmed[trimmed.index(after: lastDot)...])
            if tail.hasPrefix("claude-") { append(tail) }
        }

        var index = 0
        while index < candidates.count {
            let candidate = candidates[index]
            if let atSign = candidate.firstIndex(of: "@") {
                let base = String(candidate[..<atSign])
                let suffix = String(candidate[candidate.index(after: atSign)...])
                if suffix.range(of: #"^\d{8}$"#, options: .regularExpression) != nil {
                    append("\(base)-\(suffix)")
                }
                append(base)
            } else if candidate.hasPrefix("claude-") {
                append("\(candidate)@default")
            }
            if !preserveDatedSnapshots {
                if let dated = candidate.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
                    append(String(candidate[..<dated.lowerBound]))
                }
                if let compactDate = candidate.range(of: #"-\d{8}$"#, options: .regularExpression) {
                    append(String(candidate[..<compactDate.lowerBound]))
                }
            }
            if let version = candidate.range(of: #"-v\d+:\d+$"#, options: .regularExpression) {
                var base = candidate
                base.removeSubrange(version)
                append(base)
            }
            index += 1
        }
        return candidates
    }

    private static func canonicalAliasIdentity(_ raw: String) -> String {
        candidates(raw, preserveDatedSnapshots: true).reversed().lazy
            .map { candidate in
                guard candidate.hasSuffix("@default") else { return candidate }
                return String(candidate.dropLast("@default".count))
            }
            .first { !$0.isEmpty } ?? normalize(raw)
    }
}

public struct ModelsDevCacheArtifact: Codable, Equatable, Sendable {
    public var version: Int
    public var fetchedAt: Date
    public var catalog: ModelsDevCatalog
}

public struct ModelsDevCacheLoadResult: Equatable, Sendable {
    public var artifact: ModelsDevCacheArtifact?
    public var isStale: Bool
    public var error: ModelsDevCache.Error?
}

private final class ModelsDevCacheMemo: @unchecked Sendable {
    enum Outcome {
        case decoded(ModelsDevCacheArtifact)
        case failure(ModelsDevCache.Error)
    }

    private struct Entry {
        let modificationDate: Date?
        let size: Int?
        let outcome: Outcome
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func outcome(path: String, modificationDate: Date?, size: Int?) -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path],
              entry.modificationDate == modificationDate,
              entry.size == size else { return nil }
        return entry.outcome
    }

    func store(path: String, modificationDate: Date?, size: Int?, outcome: Outcome) {
        lock.lock()
        defer { lock.unlock() }
        entries[path] = Entry(modificationDate: modificationDate, size: size, outcome: outcome)
    }

    func invalidate(path: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: path)
    }
}

public enum ModelsDevCache {
    public enum Error: Swift.Error, Equatable, Sendable {
        case unreadable
        case invalidVersion
        case invalidJSON
    }

    public static let artifactVersion = 1
    public static let ttlSeconds: TimeInterval = 24 * 60 * 60

    private static let memo = ModelsDevCacheMemo()

    public static func defaultCacheRoot() -> URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Conductor", isDirectory: true)
    }

    public static func cacheFileURL(cacheRoot: URL? = nil) -> URL {
        let root = cacheRoot ?? defaultCacheRoot()
        return root
            .appendingPathComponent("model-pricing", isDirectory: true)
            .appendingPathComponent("models-dev-v\(artifactVersion).json", isDirectory: false)
    }

    public static func load(now: Date = Date(), cacheRoot: URL? = nil) -> ModelsDevCacheLoadResult {
        let url = cacheFileURL(cacheRoot: cacheRoot)
        let metadata = fileMetadata(at: url)
        if let outcome = memo.outcome(path: url.path, modificationDate: metadata.modificationDate, size: metadata.size) {
            return result(for: outcome, now: now)
        }
        let outcome = readOutcome(at: url)
        memo.store(path: url.path, modificationDate: metadata.modificationDate, size: metadata.size, outcome: outcome)
        return result(for: outcome, now: now)
    }

    public static func save(catalog: ModelsDevCatalog, fetchedAt: Date = Date(), cacheRoot: URL? = nil) {
        save(artifact: ModelsDevCacheArtifact(version: artifactVersion, fetchedAt: fetchedAt, catalog: catalog), cacheRoot: cacheRoot)
    }

    public static func save(artifact: ModelsDevCacheArtifact, cacheRoot: URL? = nil) {
        let url = cacheFileURL(cacheRoot: cacheRoot)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(artifact) else { return }
        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString).json", isDirectory: false)
        do {
            try data.write(to: tmp, options: [.atomic])
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
            memo.invalidate(path: url.path)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private static func fileMetadata(at url: URL) -> (modificationDate: Date?, size: Int?) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return (nil, nil)
        }
        return (attributes[.modificationDate] as? Date, (attributes[.size] as? NSNumber)?.intValue)
    }

    private static func readOutcome(at url: URL) -> ModelsDevCacheMemo.Outcome {
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(ModelsDevCacheArtifact.self, from: data) else {
            return .failure(.invalidJSON)
        }
        guard decoded.version == artifactVersion else { return .failure(.invalidVersion) }
        return .decoded(decoded)
    }

    private static func result(for outcome: ModelsDevCacheMemo.Outcome, now: Date) -> ModelsDevCacheLoadResult {
        switch outcome {
        case let .decoded(artifact):
            return ModelsDevCacheLoadResult(
                artifact: artifact,
                isStale: now.timeIntervalSince(artifact.fetchedAt) > ttlSeconds,
                error: nil)
        case let .failure(error):
            return ModelsDevCacheLoadResult(artifact: nil, isStale: true, error: error)
        }
    }
}

public protocol ModelsDevHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionModelsDevTransport: ModelsDevHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public struct ModelsDevClient: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidResponse
        case httpStatus(Int)
        case invalidJSON
    }

    public var url: URL
    public var transport: any ModelsDevHTTPTransport

    public init(
        url: URL = URL(string: "https://models.dev/api.json")!,
        transport: any ModelsDevHTTPTransport = URLSessionModelsDevTransport())
    {
        self.url = url
        self.transport = transport
    }

    public func fetchCatalog() async throws -> ModelsDevCatalog {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw Error.httpStatus(http.statusCode) }
        do {
            return try JSONDecoder().decode(ModelsDevCatalog.self, from: data)
        } catch {
            throw Error.invalidJSON
        }
    }
}

public enum ModelsDevPricingPipeline {
    public static func lookup(
        providerID: String,
        modelID: String,
        now: Date = Date(),
        cacheRoot: URL? = nil) -> ModelsDevPricingLookup?
    {
        ModelsDevCache.load(now: now, cacheRoot: cacheRoot)
            .artifact?
            .catalog
            .pricing(providerID: providerID, modelID: modelID)
    }

    public static func refreshIfNeeded(
        now: Date = Date(),
        cacheRoot: URL? = nil,
        client: ModelsDevClient = ModelsDevClient()) async
    {
        let load = ModelsDevCache.load(now: now, cacheRoot: cacheRoot)
        guard load.isStale else { return }
        do {
            let catalog = try await client.fetchCatalog()
            guard catalog.isPlausibleRefresh() else { return }
            let refreshed = load.artifact.map { catalog.mergingFallbackPricing(from: $0.catalog) } ?? catalog
            ModelsDevCache.save(catalog: refreshed, fetchedAt: now, cacheRoot: cacheRoot)
        } catch {
            // Best effort: stale but valid cache remains usable.
        }
    }
}
