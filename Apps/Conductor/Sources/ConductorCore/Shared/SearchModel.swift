import Foundation

public struct ConductorSearchQuery: Equatable, Sendable {
    public let rawValue: String
    public let normalized: String
    public let tokens: [String]

    public init(_ value: String) {
        self.rawValue = value
        let folded = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        self.normalized = folded
        self.tokens = folded
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    public var isEmpty: Bool {
        normalized.isEmpty
    }
}

public struct ConductorSearchCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let keywords: [String]
    public let section: String
    public let systemImage: String
    public let isEnabled: Bool
    public let disabledReason: String?

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        keywords: [String] = [],
        section: String = "",
        systemImage: String = "magnifyingglass",
        isEnabled: Bool = true,
        disabledReason: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.section = section
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

public enum ConductorSearchField: String, Equatable, Sendable {
    case title
    case subtitle
    case keyword
    case section
}

public struct ConductorSearchResult: Identifiable, Equatable, Sendable {
    public var id: String { candidate.id }
    public let candidate: ConductorSearchCandidate
    public let score: Int
    public let matchedFields: Set<ConductorSearchField>
    public let presentationIndex: Int

    public init(
        candidate: ConductorSearchCandidate,
        score: Int,
        matchedFields: Set<ConductorSearchField>,
        presentationIndex: Int
    ) {
        self.candidate = candidate
        self.score = score
        self.matchedFields = matchedFields
        self.presentationIndex = presentationIndex
    }
}

public enum ConductorSearchMatcher {
    public static func results(
        for query: String,
        in candidates: [ConductorSearchCandidate],
        limit: Int? = nil
    ) -> [ConductorSearchResult] {
        results(for: ConductorSearchQuery(query), in: candidates, limit: limit)
    }

    public static func results(
        for query: ConductorSearchQuery,
        in candidates: [ConductorSearchCandidate],
        limit: Int? = nil
    ) -> [ConductorSearchResult] {
        let ranked: [ConductorSearchResult]
        if query.isEmpty {
            ranked = candidates.enumerated().map { index, candidate in
                ConductorSearchResult(
                    candidate: candidate,
                    score: max(0, 10_000 - index),
                    matchedFields: [],
                    presentationIndex: index
                )
            }
        } else {
            ranked = candidates.enumerated().compactMap { index, candidate in
                guard let match = score(candidate, query: query) else { return nil }
                return ConductorSearchResult(
                    candidate: candidate,
                    score: match.score,
                    matchedFields: match.fields,
                    presentationIndex: index
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.presentationIndex < rhs.presentationIndex
            }
        }
        if let limit {
            return Array(ranked.prefix(limit))
        }
        return ranked
    }

    public static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func score(
        _ candidate: ConductorSearchCandidate,
        query: ConductorSearchQuery
    ) -> (score: Int, fields: Set<ConductorSearchField>)? {
        var total = 0
        var matchedFields = Set<ConductorSearchField>()
        for token in query.tokens {
            guard let tokenMatch = bestTokenScore(token, candidate: candidate) else {
                return nil
            }
            total += tokenMatch.score
            matchedFields.formUnion(tokenMatch.fields)
        }
        if normalized(candidate.title) == query.normalized {
            total += 2_000
            matchedFields.insert(.title)
        }
        return (total, matchedFields)
    }

    private static func bestTokenScore(
        _ token: String,
        candidate: ConductorSearchCandidate
    ) -> (score: Int, fields: Set<ConductorSearchField>)? {
        let fields: [(ConductorSearchField, String, Int)] = [
            (.title, candidate.title, 1_000),
            (.subtitle, candidate.subtitle, 620),
            (.section, candidate.section, 540)
        ] + candidate.keywords.map { (.keyword, $0, 700) }

        var best: (score: Int, fields: Set<ConductorSearchField>)?
        for (field, value, baseScore) in fields {
            let text = normalized(value)
            guard !text.isEmpty else { continue }
            let score: Int?
            if text == token {
                score = baseScore + 900
            } else if text.hasPrefix(token) {
                score = baseScore + 650
            } else if text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(token) }) {
                score = baseScore + 420
            } else if text.contains(token) {
                score = baseScore + 180
            } else {
                score = nil
            }
            guard let score else { continue }
            if best == nil || score > best!.score {
                best = (score, [field])
            } else if score == best!.score {
                best?.fields.insert(field)
            }
        }
        return best
    }
}

public enum ConductorSearchSelection {
    public static func resolvedSelection(
        currentID: String?,
        results: [ConductorSearchResult]
    ) -> String? {
        let enabledIDs = results.filter(\.candidate.isEnabled).map(\.candidate.id)
        guard !enabledIDs.isEmpty else { return nil }
        if let currentID, enabledIDs.contains(currentID) {
            return currentID
        }
        return enabledIDs.first
    }

    public static func move(
        currentID: String?,
        by offset: Int,
        results: [ConductorSearchResult],
        wraps: Bool
    ) -> String? {
        let enabledIDs = results.filter(\.candidate.isEnabled).map(\.candidate.id)
        guard !enabledIDs.isEmpty else { return nil }
        let currentIndex = currentID.flatMap { enabledIDs.firstIndex(of: $0) } ?? 0
        let rawIndex = currentIndex + offset
        let nextIndex: Int
        if wraps {
            nextIndex = (rawIndex % enabledIDs.count + enabledIDs.count) % enabledIDs.count
        } else {
            nextIndex = min(max(0, rawIndex), enabledIDs.count - 1)
        }
        return enabledIDs[nextIndex]
    }
}
