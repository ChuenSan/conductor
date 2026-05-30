import Testing
@testable import ConductorCore

@Test func searchMatcherRanking() {
    let candidates = [
        ConductorSearchCandidate(id: "contains", title: "Current Directory Open", subtitle: "Finder", keywords: ["folder"]),
        ConductorSearchCandidate(id: "prefix", title: "Open File Manager", subtitle: "Files", keywords: ["browser"]),
        ConductorSearchCandidate(id: "exact", title: "Open", subtitle: "Exact command", keywords: []),
        ConductorSearchCandidate(id: "path", title: "README.md", subtitle: "/Users/me/project/Documentation/README.md", keywords: [])
    ]
    let results = ConductorSearchMatcher.results(for: "open", in: candidates)
    #expect(results.map(\.candidate.id).prefix(3) == ["exact", "prefix", "contains"], "search ranking should prefer exact then prefix then contains")

    let pathResults = ConductorSearchMatcher.results(for: "project readme", in: candidates)
    #expect(pathResults.first?.candidate.id == "path", "multi-token search should match across title and path fields")
}

@Test func searchSelection() {
    let enabled = ConductorSearchCandidate(id: "enabled", title: "Enabled", subtitle: "", keywords: [])
    let disabled = ConductorSearchCandidate(id: "disabled", title: "Disabled", subtitle: "", keywords: [], isEnabled: false, disabledReason: "Not available")
    let other = ConductorSearchCandidate(id: "other", title: "Other", subtitle: "", keywords: [])
    let results = ConductorSearchMatcher.results(for: "", in: [disabled, enabled, other])

    #expect(ConductorSearchSelection.resolvedSelection(currentID: nil, results: results) == "enabled", "selection should start at first enabled result")
    #expect(ConductorSearchSelection.move(currentID: "enabled", by: 1, results: results, wraps: true) == "other", "selection should move to next enabled result")
    #expect(ConductorSearchSelection.move(currentID: "other", by: 1, results: results, wraps: true) == "enabled", "selection should wrap over disabled results")
    #expect(ConductorSearchSelection.resolvedSelection(currentID: "other", results: results) == "other", "selection should preserve a still-visible enabled result")
}
