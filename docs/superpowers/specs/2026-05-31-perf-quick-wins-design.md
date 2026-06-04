# Performance Quick Wins: Visibility-Scoped Polling + Surface Occlusion — Design

- **Date:** 2026-05-31
- **Status:** Approved (design); pending implementation plan
- **Scope:** Sub-project B of the Conductor-vs-cmux improvement roadmap
- **Branch:** `perf-quick-wins`

## 1. Context & Motivation

The 2026-05-30 cmux comparison turned up two precise, independent regressions
in Conductor's steady-state cost vs. cmux:

1. **2 Hz force-refresh of every surface.** `ConductorWindowModel.refreshVisibleAgentRuntimeStates`
   (`Sources/Conductor/UI/ConductorWindowModel.swift:3442-3467`) iterates
   `allTerminalIDs()` across **all** workspaces every 500 ms and unconditionally
   calls `surface.refresh()` (`= ghostty_surface_refresh`) on every existing
   surface — actively waking idle/offscreen surfaces twice a second. The poll's
   only legitimate work is `visibleText()` for Codex state detection; the
   forced refresh is defensive over-fetching.
2. **Offscreen surfaces never marked occluded.** `ghostty_surface_set_occlusion`
   is declared in the vendored header
   (`Vendor/GhosttyKit.xcframework/.../Headers/ghostty.h:1130`) but has zero
   call sites in Conductor. Hidden tabs / non-selected splits / background
   workspaces keep rendering at libghostty's `CVDisplayLink` rate.

cmux pauses unfocused/offscreen surfaces via the same `set_occlusion` API
(`Sources/GhosttyTerminalView.swift:12724-12731`) and limits status work to
visible panels. We adopt the same shape.

## 2. Decisions

- **D1 — Polling scope: visible selected tabs only.** Only iterate the set of
  terminals the user can currently see (one per pane in the selected workspace,
  honoring zoom). Other terminals are skipped entirely.
- **D2 — Drop the per-poll `surface.refresh()`.** The poll only needs to read
  `visibleText()` (a cheap viewport read) to drive the Codex active/inactive
  heuristic. Forcing a redraw on every tick is unrelated to that need; render
  cadence belongs to ghostty / `CVDisplayLink`.
- **D3 — Mark every non-visible surface occluded.** Call
  `ghostty_surface_set_occlusion(true)` for surfaces outside the visible set,
  `(false)` for surfaces inside it, on every visibility-changing state event.
- **D4 — "Visible" is selected-tab-only; window/NSWindow state ignored this round.**
  The simplest definition that captures all major savings (background tabs,
  background workspaces, hidden splits via zoom). Window/key/occlusion checks
  can layer on later in a separate sub-project.
- **D5 — Visibility logic lives in `ConductorCore` as a pure function.** Keeps
  `WorkspaceState`'s value-type discipline intact and makes the rule
  unit-testable and separate from libghostty-bound shims.

## 3. Goals & Success Criteria

1. Steady-state CPU/GPU does not scale with terminal count. A workspace with
   10 idle terminals must not noticeably exceed a workspace with 1.
2. Switching tab / pane / workspace flips occlusion within the same event
   (no "first frame after wake" lag for the newly visible surface).
3. Background terminals running a CPU-heavy program (e.g. `yes`) drop to near
   zero process cost when the user navigates away — verified by Activity
   Monitor or `top -pid`.
4. The Codex active/inactive indicator continues to update on the visible
   pane within ~500 ms (no regression).
5. `swift test` and `swift run ConductorModelCheck` stay green.

## 4. Architecture

```
ConductorCore (pure value types, unit-tested)
└── WorkspaceVisibility (new)
      visibleTerminalIDs(workspaces:selectedWorkspaceID:) -> Set<TerminalID>
      └─ honors WorkspaceState.visibleRoot (zoomed pane wins)

Conductor app (libghostty boundary, integration-verified)
├── TerminalSurface
│     setOccluded(_ occluded: Bool)        # new — forwards to
│                                          # ghostty_surface_set_occlusion,
│                                          # de-duplicates against last value
└── ConductorWindowModel
      refreshVisibleAgentRuntimeStates()   # changed — iterates the visible
                                           # set, no surface.refresh()
      applyOcclusion()                     # new — marks every surface
                                           # occluded ⇔ not in visible set
      hooks: selectedWorkspaceID didSet,
             workspaces didSet,
             surface attach (one-shot apply)
```

## 5. Components

### 5.1 `WorkspaceVisibility` (new — `ConductorCore`, pure, TDD)

```swift
public enum WorkspaceVisibility {
    /// The terminals the user can currently see: in the selected workspace,
    /// the currently-selected tab of every pane shown by `visibleRoot`.
    /// (`visibleRoot` already collapses to a single leaf when a pane is
    /// zoomed, so zoom is honored automatically.)
    /// Tolerates a `selectedWorkspaceID` that does not match any workspace
    /// by returning the empty set.
    public static func visibleTerminalIDs(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID
    ) -> Set<TerminalID>
}
```

Unit tests cover:
- single workspace, single pane → that pane's selected tab.
- single workspace, multiple panes → each pane's selected tab (not the others).
- single workspace, zoomed pane → only the zoomed pane's selected tab.
- multiple workspaces, only the selected workspace's terminals are returned.
- `selectedWorkspaceID` not in `workspaces` → empty set, no crash.
- pane with multiple tabs → only the *selected* tab.

### 5.2 `TerminalSurface` (changed — app layer, thin binding)

Add:

```swift
private var lastSetOccluded: Bool?  // de-dupe redundant calls

func setOccluded(_ occluded: Bool) {
    guard let surface else { return }
    guard occluded != lastSetOccluded else { return }
    lastSetOccluded = occluded
    ghostty_surface_set_occlusion(surface, occluded)
}
```

No other behavior changes. The flag tracks the last-applied value (rather
than mirroring app-level focus) so we never re-issue the same call.

### 5.3 `ConductorWindowModel` (changed — `Sources/Conductor/UI/ConductorWindowModel.swift`)

**`refreshVisibleAgentRuntimeStates` (current `:3442-3467`)** — replace the
`for terminalID in allTerminalIDs()` loop with iteration over
`WorkspaceVisibility.visibleTerminalIDs(workspaces:, selectedWorkspaceID:)`.
Remove the `surface.refresh()` call; keep `surface.visibleText()` and the
existing Codex state branching unchanged.

**New `applyOcclusion()`**:

```swift
private func applyOcclusion() {
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: workspaces,
        selectedWorkspaceID: selectedWorkspaceID
    )
    for entry in surfaceCoordinator.allSurfaces {
        entry.surface.setOccluded(!visible.contains(entry.id))
    }
}
```

**Hooks** — call `applyOcclusion()`:
- in `selectedWorkspaceID` `didSet` (workspace switch).
- in `workspaces` `didSet` (covers tab selection / pane focus / zoom toggle —
  all of those mutate a `WorkspaceState` inside the array, which already
  re-publishes `workspaces`).
- once on first attach of each surface, before returning the surface from
  `surface(for:)` in `ConductorWindowModel`.

### 5.4 Out of scope

- `NSWindow.occlusionState` / window-key gating (D4).
- Slow heartbeat polling for non-visible surfaces (YAGNI — agent stop/start
  events flow through the existing hook bridge, not scrollback fingerprinting).
- Background workspace priming, idle agent hibernation, per-process CPU/RSS
  diagnostics — separate roadmap items.
- `RenderCounter`, `RenderBudget`, `ConductorMainThreadWatchdog` — orthogonal.

## 6. Data Flow

```
User switches tab / pane / workspace / toggles zoom
      │
      ▼
WorkspaceState mutation re-publishes `workspaces` (and/or selectedWorkspaceID)
      │
      ▼
applyOcclusion()
      │
      ├── WorkspaceVisibility.visibleTerminalIDs(...)
      └── surface.setOccluded(...) on every surface
              │
              ▼
        ghostty_surface_set_occlusion → ghostty pauses/resumes
        offscreen rendering on its own
      │
      ▼
Next 500 ms tick of refreshVisibleAgentRuntimeStates only
reads visibleText() for terminals in the visible set; no
forced surface.refresh().
```

## 7. Error Handling & Edge Cases

- Surface not yet attached (`surface == nil` inside `setOccluded`) → early
  return; the first `applyOcclusion()` after attach will set the correct
  value.
- Visible set empty (no workspaces, transient state) → every surface gets
  `setOccluded(true)`. Safe — ghostty resumes when next set to `false`.
- App-level `setApplicationActive(false)` continues to stop polling
  (existing logic untouched). Occlusion is independent.
- `selectedWorkspaceID` referencing a non-existent workspace → empty visible
  set; no crash.

## 8. Verification

- `./Scripts/swift-test.sh` green (existing 71 + new ~6 visibility tests).
- `swift run ConductorModelCheck` still passes (smoke gate).
- Manual end-to-end on a real screen: launch the rebuilt app; in workspace A
  start `yes > /dev/null` in pane 1; switch to a different tab in the same
  pane (or to workspace B); confirm CPU for the Conductor process drops
  noticeably (Activity Monitor / `top -pid`); switch back, confirm it
  resumes. Confirm the Codex active/inactive indicator still updates on the
  visible pane.

## 9. Files Touched

| File | Change |
| --- | --- |
| `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceVisibility.swift` | new — pure visible-set function |
| `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceVisibilityTests.swift` | new — TDD coverage |
| `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift` | new `setOccluded(_:)` with last-value de-dupe |
| `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | scope-shrink the poll, drop `surface.refresh()`, add `applyOcclusion()` and its three call sites |
