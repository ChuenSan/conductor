# Search Rewrite Design

Date: 2026-05-24
Status: Proposed

## Goal

Rewrite Conductor's existing search behavior into one consistent search system while preserving the current contextual entry points. The user should feel that every search box in the app ranks, navigates, and behaves the same way, without turning terminal output or large file contents into SwiftUI state.

This design covers:

- Command Center search.
- Workspace Overview search.
- File Manager search.
- Workspace file and Markdown search.
- Terminal search panel behavior.

This design does not add project profiles, runbooks, Git panels, or terminal transcript indexing.

## Current Problem

Search is currently implemented independently in several views:

- Command Center filters commands with direct lowercased `contains`.
- Workspace Overview performs a separate text filter.
- File Manager filters known rows with direct localized contains checks.
- File editor computes matches and selection state locally.
- Terminal search has its own panel state and delegates matching to Ghostty surfaces.

The result is inconsistent ranking, inconsistent keyboard behavior, duplicated state handling, and brittle future changes. It also makes performance policy harder to enforce because every search surface makes its own choices.

## Product Principles

1. Search must be fast enough to type into continuously.
2. Search must never force large, hidden, or terminal-owned content into SwiftUI state.
3. Search should preserve user context: command search remains command-oriented, file text search remains in-file, terminal search remains terminal-native.
4. Search ranking should reward useful intent: exact match, prefix match, title match, path/subtitle match, then weaker fuzzy/contains matches.
5. Keyboard interaction should be predictable everywhere: arrows move selection, Return executes, Escape closes, next/previous actions navigate matches.

## Architecture

Add a new `UI/Search` area under the Conductor app target:

- `ConductorSearchQuery`
  Normalized query representation. It trims whitespace, lowercases for matching, tokenizes by whitespace, and keeps the original display string.

- `ConductorSearchCandidate`
  A lightweight searchable item with `id`, `title`, `subtitle`, `keywords`, `section`, `systemImage`, `isEnabled`, and optional disabled reason.

- `ConductorSearchResult`
  A ranked candidate plus score, matched fields, and presentation index.

- `ConductorSearchMatcher`
  Pure, nonisolated matching and ranking logic. It should be testable without SwiftUI.

- `ConductorSearchSelection`
  Small helper for selection movement, preserving current selection when possible and clamping/wrapping consistently.

- `ConductorSearchDebouncer`
  Main-actor helper for delayed refresh when a search surface has expensive backing data. It should be optional: small command/workspace lists can filter synchronously.

The shared layer is app-local first. If later needed by model checks, the pure matcher can move into `ConductorCore`.

## Data Flow

Each search surface converts its existing domain objects into `ConductorSearchCandidate` values.

Command Center:

- Source: `ConductorCommandCatalog.items(model:)`.
- Candidate title: command title.
- Subtitle: section and shortcut.
- Keywords: existing keywords plus shortcut.
- Action: existing command execution.

Workspace Overview:

- Source: `WorkspaceOverviewSnapshot.items`.
- Candidate title: workspace title.
- Subtitle: terminal count, split count, unread count summary.
- Keywords: terminal titles and visible workspace metadata.
- Action: activate workspace and close overview.

File Manager:

- Source: already known visible and expanded rows from `FileManagerPanelStore`.
- Candidate title: file or folder name.
- Subtitle: path.
- Keywords: extension and path components.
- Action: select/open current item according to existing panel behavior.
- Performance boundary: only rank known rows. Do not recursively scan unloaded directories during interactive typing.

Workspace File Search:

- Source: currently loaded editable text or document preview search bridge.
- Query normalization and next/previous state use the shared search helpers.
- Matching over editable source text remains detached and debounced.
- Markdown/document preview still delegates DOM highlighting to the existing WebView bridge.

Terminal Search:

- Source: Ghostty native search.
- Shared behavior applies to panel focus, query state, target selection, next/previous shortcuts, and status display.
- Matching stays inside Ghostty. No transcript, scrollback, cell grid, or output buffer enters SwiftUI state.

## UI Behavior

Command Center and Workspace Overview keep their current panel shapes, but both display results through the same row semantics:

- Section header.
- Icon.
- Title.
- Subtitle.
- Right-side shortcut or status.
- Disabled reason when applicable.

File Manager keeps its panel layout, but search results use the same ranking policy. The status bar should make filtered counts clear.

File and terminal search keep compact contextual bars because they search within active content rather than navigate app objects.

## Keyboard Behavior

All search surfaces should share these rules:

- Up/Down moves selection through enabled results.
- Return executes the selected result.
- Escape closes the active search surface or clears the query when that is the established local behavior.
- Cmd-F opens contextual search for the current content.
- Cmd-G moves to next match.
- Shift-Cmd-G moves to previous match.

Where a surface uses grid navigation, left/right/up/down can still map to grid movement, but selection preservation must use the shared helper.

## Performance Policy

Search must not add large rendering or indexing work on the main actor.

- Command and workspace lists can rank synchronously.
- File Manager ranks only loaded/known rows and uses virtualized display windows.
- File text matching stays detached and debounced, capped to existing match limits.
- Terminal search remains Ghostty-owned.
- No new global file content index in this phase.

## Error Handling

Disabled results remain visible when useful and include a reason.

If a search source is unavailable, the surface should show a short empty state rather than silently dropping the section.

If detached matching is cancelled by new input, it should not show stale results.

## Testing

Add model-level checks where possible:

- `ConductorSearchMatcher` ranks exact, prefix, title, subtitle, keyword, and path matches in the expected order.
- Multi-token queries require every token to match at least one indexed field.
- Disabled candidates can be included but are skipped by selection movement.
- Selection is preserved across result updates when the selected ID remains present.
- File search does not require recursive directory reads for unloaded directories.

Run the existing gates after implementation:

- Source-level matcher checks or `ConductorModelCheck` coverage for pure search logic.
- `swift build --package-path Apps/Conductor --product Conductor`.
- `swift run --package-path Apps/Conductor ConductorModelCheck`.

## Implementation Slices

1. Add pure search primitives and tests/checks.
2. Move Command Center to the shared matcher and selection helper.
3. Move Workspace Overview to the shared matcher and selection helper.
4. Move File Manager filtering to the shared matcher without changing directory loading behavior.
5. Normalize file and terminal search keyboard behavior through shared selection/navigation helpers.
6. Run build, model checks, and manual app verification.

## Acceptance Criteria

- Existing search entry points still exist.
- Command Center and Workspace Overview no longer use ad hoc `contains` filtering.
- File Manager search uses the shared matcher and does not scan unloaded directories.
- File search remains responsive while typing in loaded text.
- Terminal search still uses Ghostty native search.
- Arrow, Return, Escape, next, and previous behavior are consistent across search surfaces.
- Build and model checks pass.
