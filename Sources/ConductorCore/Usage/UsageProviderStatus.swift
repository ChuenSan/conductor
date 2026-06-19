import Foundation

public enum UsageProviderStatusIndicator: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case minor
    case major
    case critical
    case maintenance
    case unknown

    public var hasIssue: Bool {
        switch self {
        case .none: false
        default: true
        }
    }

    public var label: String {
        switch self {
        case .none: L("运行正常")
        case .minor: L("部分中断")
        case .major: L("大面积中断")
        case .critical: L("严重故障")
        case .maintenance: L("维护中")
        case .unknown: L("状态未知")
        }
    }
}

public struct UsageProviderStatusSnapshot: Codable, Sendable, Equatable {
    public let provider: String
    public let name: String
    public let indicator: UsageProviderStatusIndicator
    public let label: String
    public let description: String?
    public let updatedAt: Date?
    public let statusPageURL: String?
    public let statusLinkURL: String?
    public let source: String
    public let error: String?

    public var url: String? { self.statusPageURL ?? self.statusLinkURL }

    public init(
        provider: String,
        name: String,
        indicator: UsageProviderStatusIndicator,
        description: String? = nil,
        updatedAt: Date? = nil,
        statusPageURL: String? = nil,
        statusLinkURL: String? = nil,
        source: String,
        error: String? = nil
    ) {
        self.provider = provider
        self.name = name
        self.indicator = indicator
        self.label = indicator.label
        self.description = description
        self.updatedAt = updatedAt
        self.statusPageURL = statusPageURL
        self.statusLinkURL = statusLinkURL
        self.source = source
        self.error = error
    }
}

private final class UsageProviderStatusISO8601FormatterBox: @unchecked Sendable {
    let lock = NSLock()
    let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private enum UsageProviderStatusDateParser {
    static let box = UsageProviderStatusISO8601FormatterBox()

    static func parse(_ text: String) -> Date? {
        self.box.lock.lock()
        defer { self.box.lock.unlock() }
        return self.box.withFractional.date(from: text) ?? self.box.plain.date(from: text)
    }

    static func decodingStrategy() -> JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = Self.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO8601 date")
            }
            return date
        }
    }
}

public enum UsageProviderStatusFetcher {
    public static func fetch(entry: UsageProviderEntry) async throws -> UsageProviderStatusSnapshot {
        if let productID = entry.googleWorkspaceStatusProductID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !productID.isEmpty
        {
            return try await Self.fetchGoogleWorkspaceStatus(entry: entry, productID: productID)
        }

        guard let rawURL = entry.statusPageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              let baseURL = URL(string: rawURL)
        else {
            return Self.linkOnlySnapshot(entry: entry)
        }

        let apiURL = baseURL.appendingPathComponent("api/v2/status.json")
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode)
        {
            throw URLError(.badServerResponse)
        }
        return try Self.parseStatusPage(data: data, entry: entry)
    }

    public static func errorSnapshot(entry: UsageProviderEntry, error: Error) -> UsageProviderStatusSnapshot {
        UsageProviderStatusSnapshot(
            provider: entry.id,
            name: entry.name,
            indicator: .unknown,
            description: error.localizedDescription,
            statusPageURL: entry.statusPageURL,
            statusLinkURL: entry.statusLinkURL,
            source: "statuspage",
            error: error.localizedDescription)
    }

    public static func parseStatusPage(
        data: Data,
        entry: UsageProviderEntry
    ) throws -> UsageProviderStatusSnapshot {
        struct Response: Decodable {
            struct Status: Decodable {
                let indicator: String
                let description: String?
            }

            struct Page: Decodable {
                let updatedAt: Date?

                private enum CodingKeys: String, CodingKey {
                    case updatedAt = "updated_at"
                }
            }

            let page: Page?
            let status: Status
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = UsageProviderStatusDateParser.decodingStrategy()
        let response = try decoder.decode(Response.self, from: data)
        let indicator = UsageProviderStatusIndicator(rawValue: response.status.indicator) ?? .unknown
        return UsageProviderStatusSnapshot(
            provider: entry.id,
            name: entry.name,
            indicator: indicator,
            description: response.status.description,
            updatedAt: response.page?.updatedAt,
            statusPageURL: entry.statusPageURL,
            statusLinkURL: entry.statusLinkURL,
            source: "statuspage")
    }

    public static func fetchGoogleWorkspaceStatus(
        entry: UsageProviderEntry,
        productID: String
    ) async throws -> UsageProviderStatusSnapshot {
        guard let url = URL(string: "https://www.google.com/appsstatus/dashboard/incidents.json") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode)
        {
            throw URLError(.badServerResponse)
        }
        return try Self.parseGoogleWorkspaceStatus(data: data, entry: entry, productID: productID)
    }

    public static func parseGoogleWorkspaceStatus(
        data: Data,
        entry: UsageProviderEntry,
        productID: String
    ) throws -> UsageProviderStatusSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = UsageProviderStatusDateParser.decodingStrategy()

        let incidents = try decoder.decode([GoogleWorkspaceIncident].self, from: data)
        let active = incidents.filter { $0.isRelevant(productID: productID) && $0.isActive }
        guard !active.isEmpty else {
            return UsageProviderStatusSnapshot(
                provider: entry.id,
                name: entry.name,
                indicator: .none,
                statusPageURL: entry.statusPageURL,
                statusLinkURL: entry.statusLinkURL,
                source: "google-workspace")
        }

        var best: (
            indicator: UsageProviderStatusIndicator,
            incident: GoogleWorkspaceIncident,
            update: GoogleWorkspaceUpdate?)
        best = (indicator: .none, incident: active[0], update: active[0].mostRecentUpdate ?? active[0].updates?.last)

        for incident in active {
            let update = incident.mostRecentUpdate ?? incident.updates?.last
            let indicator = Self.workspaceIndicator(
                status: update?.status ?? incident.statusImpact,
                severity: incident.severity)
            if Self.indicatorRank(indicator) <= Self.indicatorRank(best.indicator) { continue }
            best = (indicator: indicator, incident: incident, update: update)
        }

        return UsageProviderStatusSnapshot(
            provider: entry.id,
            name: entry.name,
            indicator: best.indicator,
            description: Self.workspaceSummary(from: best.update?.text ?? best.incident.externalDesc),
            updatedAt: best.update?.when ?? best.incident.modified ?? best.incident.begin,
            statusPageURL: entry.statusPageURL,
            statusLinkURL: entry.statusLinkURL,
            source: "google-workspace")
    }

    private static func indicatorRank(_ indicator: UsageProviderStatusIndicator) -> Int {
        switch indicator {
        case .none: 0
        case .maintenance: 1
        case .minor: 2
        case .major: 3
        case .critical: 4
        case .unknown: 1
        }
    }

    private static func workspaceIndicator(status: String?, severity: String?) -> UsageProviderStatusIndicator {
        switch status?.uppercased() {
        case "AVAILABLE": return .none
        case "SERVICE_INFORMATION": return .minor
        case "SERVICE_DISRUPTION": return .major
        case "SERVICE_OUTAGE": return .critical
        case "SERVICE_MAINTENANCE", "SCHEDULED_MAINTENANCE": return .maintenance
        default: break
        }

        switch severity?.lowercased() {
        case "low": return .minor
        case "medium": return .major
        case "high": return .critical
        default: return .minor
        }
    }

    private static func workspaceSummary(from text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true)
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if lower.hasPrefix("**summary") || lower.hasPrefix("**description") || lower == "summary" {
                continue
            }
            var cleaned = trimmed.replacingOccurrences(of: "**", with: "")
            cleaned = cleaned.replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression)
            if cleaned.hasPrefix("- ") {
                cleaned.removeFirst(2)
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private static func linkOnlySnapshot(entry: UsageProviderEntry) -> UsageProviderStatusSnapshot {
        UsageProviderStatusSnapshot(
            provider: entry.id,
            name: entry.name,
            indicator: .unknown,
            description: entry.statusLinkURL == nil ? L("未配置状态页") : L("仅提供状态页链接"),
            statusPageURL: entry.statusPageURL,
            statusLinkURL: entry.statusLinkURL,
            source: entry.statusLinkURL == nil ? "none" : "link")
    }

    private struct GoogleWorkspaceIncident: Decodable {
        let begin: Date?
        let end: Date?
        let modified: Date?
        let externalDesc: String?
        let statusImpact: String?
        let severity: String?
        let affectedProducts: [GoogleWorkspaceProduct]?
        let currentlyAffectedProducts: [GoogleWorkspaceProduct]?
        let mostRecentUpdate: GoogleWorkspaceUpdate?
        let updates: [GoogleWorkspaceUpdate]?

        var isActive: Bool {
            self.end == nil
        }

        func isRelevant(productID: String) -> Bool {
            if let current = currentlyAffectedProducts {
                return current.contains { $0.id == productID }
            }
            return self.affectedProducts?.contains { $0.id == productID } ?? false
        }
    }

    private struct GoogleWorkspaceProduct: Decodable {
        let title: String?
        let id: String
    }

    private struct GoogleWorkspaceUpdate: Decodable {
        let when: Date?
        let status: String?
        let text: String?
    }
}

public enum UsageProviderStatusReporter {
    public static func fetchUnlessCancelled(entries: [UsageProviderEntry]) async throws -> [UsageProviderStatusSnapshot] {
        var snapshots: [UsageProviderStatusSnapshot] = []
        for entry in entries {
            try Task.checkCancellation()
            do {
                let snapshot = try await UsageProviderStatusFetcher.fetch(entry: entry)
                try Task.checkCancellation()
                snapshots.append(snapshot)
            } catch {
                try UsageProviderCancellation.rethrowIfCancelled(error)
                snapshots.append(UsageProviderStatusFetcher.errorSnapshot(entry: entry, error: error))
            }
        }
        return snapshots
    }

    public static func fetch(entries: [UsageProviderEntry]) async -> [UsageProviderStatusSnapshot] {
        var snapshots: [UsageProviderStatusSnapshot] = []
        for entry in entries {
            do {
                snapshots.append(try await UsageProviderStatusFetcher.fetch(entry: entry))
            } catch {
                snapshots.append(UsageProviderStatusFetcher.errorSnapshot(entry: entry, error: error))
            }
        }
        return snapshots
    }
}
