# Search Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Conductor's ad hoc search filtering with one shared, ranked search core while preserving the current contextual search entry points.

**Architecture:** Put pure search query, candidate, result, matcher, and selection helpers in `ConductorCore` so `ConductorModelCheck` can cover them. App UI surfaces convert commands, workspaces, file rows, and contextual search state into shared candidates/results, while terminal output search remains Ghostty-owned.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, `ConductorCore`, `ConductorModelCheck`.

---

## File Structure

- Create `Apps/Conductor/Sources/ConductorCore/Shared/SearchModel.swift`
  Pure search primitives: query normalization, candidates, ranked results, matcher, and selection movement.
- Modify `Apps/Conductor/Sources/ConductorModelCheck/main.swift`
  Add matcher and selection regression checks.
- Modify `Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift`
  Move Command Center and Workspace Overview filtering/selection to shared search primitives.
- Modify `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerDisplaySnapshot.swift`
  Replace file-row ad hoc `localizedCaseInsensitiveContains` filtering with `ConductorSearchMatcher`, while keeping current known-row-only behavior.
- Modify `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
  Normalize file search query usage and selection movement through shared query/selection helpers without changing WebView or detached text-search behavior.
- Modify `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
  Keep terminal search Ghostty-owned, but align next/previous routing and contextual search semantics with the shared behavior.

## Task 1: Add Pure Search Primitives

**Files:**
- Create: `Apps/Conductor/Sources/ConductorCore/Shared/SearchModel.swift`
- Modify: `Apps/Conductor/Sources/ConductorModelCheck/main.swift`

- [ ] **Step 1: Write failing model checks**

Add these checks near the other top-level check functions in `Apps/Conductor/Sources/ConductorModelCheck/main.swift`:

```swift
func checkSearchMatcherRanking() {
    let candidates = [
        ConductorSearchCandidate(id: "contains", title: "Open Current Directory", subtitle: "Finder", keywords: ["folder"]),
        ConductorSearchCandidate(id: "prefix", title: "Open File Manager", subtitle: "Files", keywords: ["browser"]),
        ConductorSearchCandidate(id: "exact", title: "Open", subtitle: "Exact command", keywords: []),
        ConductorSearchCandidate(id: "path", title: "README.md", subtitle: "/Users/me/project/Documentation/README.md", keywords: [])
    ]
    let results = ConductorSearchMatcher.results(for: "open", in: candidates)
    require(results.map(\.candidate.id).prefix(3) == ["exact", "prefix", "contains"], "search ranking should prefer exact then prefix then contains")

    let pathResults = ConductorSearchMatcher.results(for: "project readme", in: candidates)
    require(pathResults.first?.candidate.id == "path", "multi-token search should match across title and path fields")
}

func checkSearchSelection() {
    let enabled = ConductorSearchCandidate(id: "enabled", title: "Enabled", subtitle: "", keywords: [])
    let disabled = ConductorSearchCandidate(id: "disabled", title: "Disabled", subtitle: "", keywords: [], isEnabled: false, disabledReason: "Not available")
    let other = ConductorSearchCandidate(id: "other", title: "Other", subtitle: "", keywords: [])
    let results = ConductorSearchMatcher.results(for: "", in: [disabled, enabled, other])

    require(ConductorSearchSelection.resolvedSelection(currentID: nil, results: results) == "enabled", "selection should start at first enabled result")
    require(ConductorSearchSelection.move(currentID: "enabled", by: 1, results: results, wraps: true) == "other", "selection should move to next enabled result")
    require(ConductorSearchSelection.move(currentID: "other", by: 1, results: results, wraps: true) == "enabled", "selection should wrap over disabled results")
    require(ConductorSearchSelection.resolvedSelection(currentID: "other", results: results) == "other", "selection should preserve a still-visible enabled result")
}
```

Call both from the bottom check list:

```swift
checkSearchMatcherRanking()
checkSearchSelection()
```

- [ ] **Step 2: Run checks and verify they fail**

Run:

```bash
swift run --package-path Apps/Conductor ConductorModelCheck
```

Expected: compile failure because `ConductorSearchCandidate`, `ConductorSearchMatcher`, and `ConductorSearchSelection` are not defined.

- [ ] **Step 3: Implement pure search primitives**

Create `Apps/Conductor/Sources/ConductorCore/Shared/SearchModel.swift`:

```swift
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

    public static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
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
```

- [ ] **Step 4: Run checks and verify they pass**

Run:

```bash
swift run --package-path Apps/Conductor ConductorModelCheck
```

Expected: `ConductorModelCheck passed`.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Shared/SearchModel.swift Apps/Conductor/Sources/ConductorModelCheck/main.swift
git commit -m "feat: add shared search matcher"
```

## Task 2: Move Command Center to Shared Search

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift`

- [ ] **Step 1: Write failing source check**

Run this source check before editing:

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("ConductorSearchMatcher.results"), "Command Center should use shared search matcher")
require(source.contains("ConductorSearchSelection.move"), "Command Center should use shared search selection movement")
require(!source.contains("guard normalizedQuery.isEmpty || command.searchText.contains(normalizedQuery) else { continue }"), "Command Center should not use ad hoc contains filtering")
print("command center source check passed")
SWIFT
```

Expected: fail because Command Center still uses ad hoc filtering.

- [ ] **Step 2: Replace Command Center filtering**

In `CommandPaletteFilterResult.init(commands:query:)`, build candidates and use shared results:

```swift
let candidates = commands.map { $0.searchCandidate }
let searchResults = ConductorSearchMatcher.results(for: query, in: candidates)
let commandByID = Dictionary(uniqueKeysWithValues: commands.map { ($0.id, $0) })
```

Then build rows from `searchResults`, preserving section-title logic from the ranked order:

```swift
for result in searchResults {
    guard let command = commandByID[result.candidate.id] else { continue }
    let showsSectionTitle = command.section != previousSection
    previousSection = command.section
    rows.append(CommandPaletteFilteredRow(
        command: command,
        showsSectionTitle: showsSectionTitle,
        presentationIndex: rows.count
    ))
    commandIDs.append(command.id)
    if !command.disabled {
        enabledCommands.append(command)
        enabledCommandIDs.insert(command.id)
    }
}
```

Add this computed property to `CommandPaletteItem`:

```swift
var searchCandidate: ConductorSearchCandidate {
    ConductorSearchCandidate(
        id: id,
        title: title,
        subtitle: shortcut,
        keywords: [keywords, section, shortcut],
        section: section,
        systemImage: systemImage,
        isEnabled: !disabled,
        disabledReason: disabledReason
    )
}
```

Update selection movement in `CommandPaletteView.moveSelection(by:)` and `ensureSelection(in:)` to use `ConductorSearchSelection` over `filteredResult.searchResults`, or expose enabled IDs from `CommandPaletteFilterResult` and use the shared helper.

- [ ] **Step 3: Run source check**

Run the same source check from Step 1.

Expected: `command center source check passed`.

- [ ] **Step 4: Run build**

```bash
swift build --package-path Apps/Conductor --product Conductor
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift
git commit -m "refactor: route command search through shared matcher"
```

## Task 3: Move Workspace Overview to Shared Search

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift`

- [ ] **Step 1: Write failing source check**

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("WorkspaceOverviewFilterResult(items: snapshot.items, query: query)"), "Workspace Overview should filter through a query-aware result type")
require(source.contains("ConductorSearchMatcher.results(for: query"), "Workspace Overview should use shared matcher")
require(!source.contains("item.searchText.contains(normalizedQuery)"), "Workspace Overview should not use ad hoc contains filtering")
print("workspace overview source check passed")
SWIFT
```

Expected: fail because Workspace Overview still filters locally.

- [ ] **Step 2: Add Workspace Overview candidates**

Replace `WorkspaceOverviewItemSnapshot.searchText` with this property:

```swift
var searchCandidate: ConductorSearchCandidate {
    ConductorSearchCandidate(
        id: workspace.id.description,
        title: workspace.title,
        subtitle: Self.subtitle(for: workspace),
        keywords: Self.keywords(for: workspace),
        section: L("工作区", "Workspaces"),
        systemImage: WorkspaceChromeGlyph.systemName(selected: false)
    )
}
```

Add helper methods:

```swift
private static func subtitle(for workspace: WorkspaceState) -> String {
    let terminalCount = workspace.panes.values.reduce(0) { $0 + $1.tabs.count }
    return L("\(workspace.panes.count) 个分屏 · \(terminalCount) 个终端", "\(workspace.panes.count) panes · \(terminalCount) terminals")
}

private static func keywords(for workspace: WorkspaceState) -> [String] {
    var parts: [String] = []
    for pane in workspace.panes.values {
        for tab in pane.tabs {
            parts.append(tab.title)
            if let workingDirectory = tab.workingDirectory {
                parts.append(workingDirectory)
            }
        }
    }
    return parts
}
```

- [ ] **Step 3: Replace Workspace Overview filter result**

Change `WorkspaceOverviewFilterResult` to:

```swift
private struct WorkspaceOverviewFilterResult: Equatable {
    let items: [WorkspaceOverviewItemSnapshot]
    let ids: [WorkspaceID]

    init(items: [WorkspaceOverviewItemSnapshot], query: String = "") {
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id.description, $0) })
        let results = ConductorSearchMatcher.results(for: query, in: items.map(\.searchCandidate))
        self.items = results.compactMap { itemByID[$0.candidate.id] }
        self.ids = self.items.map(\.id)
    }
}
```

Change the `filteredResult` computed property to:

```swift
private var filteredResult: WorkspaceOverviewFilterResult {
    WorkspaceOverviewFilterResult(items: snapshot.items, query: query)
}
```

Use `ConductorSearchSelection.move(... wraps: false)` in `moveHighlight(by:)` by converting IDs to string and back via the result list.

- [ ] **Step 4: Run source check and build**

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("WorkspaceOverviewFilterResult(items: snapshot.items, query: query)"), "Workspace Overview should filter through a query-aware result type")
require(source.contains("ConductorSearchMatcher.results(for: query"), "Workspace Overview should use shared matcher")
require(!source.contains("item.searchText.contains(normalizedQuery)"), "Workspace Overview should not use ad hoc contains filtering")
print("workspace overview source check passed")
SWIFT
swift build --package-path Apps/Conductor --product Conductor
```

Expected: source check passes and build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/Shell/ShellRootView.swift
git commit -m "refactor: unify workspace overview search"
```

## Task 4: Move File Manager Filtering to Shared Search

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerDisplaySnapshot.swift`

- [ ] **Step 1: Write failing source check**

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerDisplaySnapshot.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("ConductorSearchMatcher.results(for: query"), "File Manager should use shared matcher")
require(!source.contains("localizedCaseInsensitiveContains(query)"), "File Manager should not use ad hoc contains filtering")
print("file manager search source check passed")
SWIFT
```

Expected: fail because File Manager still uses localized contains.

- [ ] **Step 2: Import ConductorCore**

Add to the top of `FileManagerDisplaySnapshot.swift`:

```swift
import ConductorCore
```

- [ ] **Step 3: Replace known-row matching**

In `appendKnownMatchingRows(...)`, replace the direct name/path contains condition with:

```swift
let candidate = ConductorSearchCandidate(
    id: item.url.path,
    title: item.name,
    subtitle: item.url.path,
    keywords: [item.url.pathExtension, item.url.deletingLastPathComponent().path],
    section: item.isDirectory ? fileManagerL("文件夹", "Folders") : fileManagerL("文件", "Files"),
    systemImage: item.isDirectory ? "folder" : "doc"
)
let matchesSearch = !ConductorSearchMatcher.results(for: query, in: [candidate]).isEmpty
if matchesKindFilter(item, kindFilter: kindFilter) && matchesSearch {
    rows.append(FileManagerVisibleRow(item: item, depth: depth))
}
```

This preserves the current known-row-only traversal and does not recursively load unloaded directories.

- [ ] **Step 4: Run source check and build**

```bash
swift - <<'SWIFT'
import Foundation
let source = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerDisplaySnapshot.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(source.contains("ConductorSearchMatcher.results(for: query"), "File Manager should use shared matcher")
require(!source.contains("localizedCaseInsensitiveContains(query)"), "File Manager should not use ad hoc contains filtering")
print("file manager search source check passed")
SWIFT
swift build --package-path Apps/Conductor --product Conductor
```

Expected: source check passes and build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/FileManager/FileManagerDisplaySnapshot.swift
git commit -m "refactor: unify file manager search matching"
```

## Task 5: Normalize Contextual File and Terminal Search Behavior

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

- [ ] **Step 1: Write failing source check**

```bash
swift - <<'SWIFT'
import Foundation
let fileSearch = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift", encoding: .utf8)
let model = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(fileSearch.contains("ConductorSearchQuery(searchQuery)"), "File search should normalize query through shared query model")
require(fileSearch.contains("ConductorSearchSelection.move"), "File search next/previous should use shared selection movement")
require(model.contains("routeContextualSearchNavigation(previous:"), "Terminal/file search navigation should share routing helper")
print("contextual search source check passed")
SWIFT
```

Expected: fail because contextual search still uses local query trimming and manual modulo movement.

- [ ] **Step 2: Normalize file query**

In `refreshSearchMatches(resetSelection:)`, replace local trimming with:

```swift
let searchQueryModel = ConductorSearchQuery(searchQuery)
guard !searchQueryModel.isEmpty else {
    searchTask?.cancel()
    searchPending = false
    cachedSearchMatches = []
    selectedSearchIndex = 0
    sourceSelectionRange = nil
    return
}
```

Pass `searchQueryModel.normalized` into `searchMatches`:

```swift
let needle = searchQueryModel.normalized
```

Update `searchMatches(in:query:maxMatches:)` to create `ConductorSearchQuery(query)` and use its normalized value before `NSString.range`.

- [ ] **Step 3: Normalize file search selection**

In `moveSearchSelection(_:)`, replace manual modulo with shared selection over synthetic candidates:

```swift
let results = matches.indices.map { index in
    ConductorSearchResult(
        candidate: ConductorSearchCandidate(id: String(index), title: String(index)),
        score: matches.count - index,
        matchedFields: [],
        presentationIndex: index
    )
}
let nextID = ConductorSearchSelection.move(
    currentID: String(selectedSearchIndex),
    by: delta,
    results: results,
    wraps: true
)
selectedSearchIndex = nextID.flatMap(Int.init) ?? 0
selectCurrentSearchMatch()
```

- [ ] **Step 4: Extract navigation routing helper**

In `ConductorWindowModel`, extract the top of `navigateTerminalSearch(previous:)` into:

```swift
@discardableResult
private func routeContextualSearchNavigation(previous: Bool) -> Bool {
    if selectedWorkspaceFileTab != nil {
        if previous {
            workspaceFileSearchPreviousGeneration &+= 1
        } else {
            workspaceFileSearchNextGeneration &+= 1
        }
        return true
    }
    if fileManagerPanelRequest != nil {
        if previous {
            fileManagerSearchPreviousGeneration &+= 1
        } else {
            fileManagerSearchNextGeneration &+= 1
        }
        return true
    }
    return false
}
```

Then call it at the start of `navigateTerminalSearch(previous:)`:

```swift
if routeContextualSearchNavigation(previous: previous) {
    return
}
```

- [ ] **Step 5: Run source check and build**

```bash
swift - <<'SWIFT'
import Foundation
let fileSearch = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift", encoding: .utf8)
let model = try String(contentsOfFile: "Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift", encoding: .utf8)
func require(_ condition: Bool, _ message: String) {
    if !condition {
        FileHandle.standardError.write(("FAIL: " + message + "\n").data(using: .utf8)!)
        exit(1)
    }
}
require(fileSearch.contains("ConductorSearchQuery(searchQuery)"), "File search should normalize query through shared query model")
require(fileSearch.contains("ConductorSearchSelection.move"), "File search next/previous should use shared selection movement")
require(model.contains("routeContextualSearchNavigation(previous:"), "Terminal/file search navigation should share routing helper")
print("contextual search source check passed")
SWIFT
swift build --package-path Apps/Conductor --product Conductor
```

Expected: source check passes and build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "refactor: normalize contextual search navigation"
```

## Task 6: Final Verification and App Restart

**Files:**
- No source edits expected.

- [ ] **Step 1: Run full model check**

```bash
swift run --package-path Apps/Conductor ConductorModelCheck
```

Expected: `ConductorModelCheck passed`.

- [ ] **Step 2: Run app build**

```bash
swift build --package-path Apps/Conductor --product Conductor
```

Expected: build completes successfully. Existing GhosttyKit symbol warnings may appear during linking.

- [ ] **Step 3: Restart app**

```bash
pgrep -fl Conductor
kill <existing-conductor-pid> || true
Apps/Conductor/Scripts/run-conductor.sh
pgrep -fl Conductor
```

Expected: one fresh `Conductor.app/Contents/MacOS/Conductor` process is running.

- [ ] **Step 4: Commit any final verification-only documentation updates**

Only commit if files changed:

```bash
git status --short
```

Expected: no uncommitted changes except unrelated existing `.trellis/.agents/.codex` deletions.

