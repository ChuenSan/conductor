# Performance Quick Wins (Visibility-Scoped Polling + Occlusion) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop steady-state CPU/GPU from scaling with terminal count: shrink the agent-state poll to the visible selected tab(s) only, drop its forced `surface.refresh()`, and call `ghostty_surface_set_occlusion(true)` on every non-visible surface so libghostty pauses offscreen rendering.

**Architecture:** A new pure `WorkspaceVisibility.visibleTerminalIDs(workspaces:selectedWorkspaceID:)` in `ConductorCore` is the single source of truth for "which terminals can the user see right now." `TerminalSurface` gets a tiny `setOccluded(_:)` shim around the already-bundled `ghostty_surface_set_occlusion`. `ConductorWindowModel` consumes the pure function in two places: the 500 ms poll iterates the visible set instead of all terminals (and stops force-refreshing), and a new `applyOcclusion()` runs from the `workspaces` / `selectedWorkspaceID` setters and after each fresh surface attaches.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`import Testing`), AppKit/SwiftUI, vendored GhosttyKit (libghostty C API).

**Spec:** `docs/superpowers/specs/2026-05-31-perf-quick-wins-design.md`

**Working directory for all commands:** `Apps/Conductor`

> **Running tests on this machine:** Command Line Tools-only (no Xcode/XCTest). **Always run tests via `./Scripts/swift-test.sh`** — plain `swift test` cannot load Swift Testing at runtime here. `swift build` and `swift run ConductorModelCheck` work normally.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceVisibility.swift` | **new** — pure: compute the set of currently-visible terminal IDs from `[WorkspaceState]` + selected workspace ID |
| `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceVisibilityTests.swift` | **new** — TDD coverage for the visibility rule |
| `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift` | add `setOccluded(_:)` (last-value de-duped wrapper around `ghostty_surface_set_occlusion`) |
| `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift` | scope the poll to visible terminals; drop `surface.refresh()`; add `applyOcclusion()`; wire it from `workspaces` / `selectedWorkspaceID` setters and the surface-attach path |

---

## Task 1: `WorkspaceVisibility` — pure visible-set function

**Files:**
- Create: `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceVisibility.swift`
- Test: `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceVisibilityTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Apps/Conductor/Tests/ConductorCoreTests/WorkspaceVisibilityTests.swift`:

```swift
import Testing
@testable import ConductorCore

@Test func visibleTerminalsInSinglePaneSingleWorkspace() {
    let workspace = WorkspaceState()
    let expected = workspace.focusedPane?.selectedTabID
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([expected].compactMap { $0 }))
}

@Test func visibleTerminalsCoverEveryPaneInSelectedWorkspace() {
    var workspace = WorkspaceState()
    let firstPaneSelected = workspace.focusedPane!.selectedTabID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    let secondPaneSelected = workspace.panes[secondPaneID]!.selectedTabID
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([firstPaneSelected, secondPaneSelected]))
}

@Test func visibleTerminalsExcludeUnselectedTabsInPane() {
    var workspace = WorkspaceState()
    let paneID = workspace.focusedPaneID
    let firstTab = workspace.focusedPane!.selectedTabID
    let secondTab = workspace.newTerminal(title: "server")
    // Selecting the second tab should make ONLY the second tab visible.
    workspace.selectTab(secondTab, in: paneID)
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([secondTab]))
    #expect(!visible.contains(firstTab))
}

@Test func visibleTerminalsHonorZoom() {
    var workspace = WorkspaceState()
    let firstPaneSelected = workspace.focusedPane!.selectedTabID
    guard let secondPaneID = workspace.splitFocusedPane(.right, title: "agent") else {
        Issue.record("split should create second pane"); return
    }
    let secondPaneSelected = workspace.panes[secondPaneID]!.selectedTabID
    workspace.toggleZoom() // zoom the just-created (focused) second pane
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: workspace.id
    )
    #expect(visible == Set([secondPaneSelected]))
    #expect(!visible.contains(firstPaneSelected))
}

@Test func visibleTerminalsExcludeOtherWorkspaces() {
    let workspaceA = WorkspaceState(title: "A")
    let workspaceB = WorkspaceState(title: "B")
    let aSelected = workspaceA.focusedPane!.selectedTabID
    let bSelected = workspaceB.focusedPane!.selectedTabID
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspaceA, workspaceB],
        selectedWorkspaceID: workspaceA.id
    )
    #expect(visible == Set([aSelected]))
    #expect(!visible.contains(bSelected))
}

@Test func visibleTerminalsForUnknownSelectedIDIsEmpty() {
    let workspace = WorkspaceState()
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [workspace],
        selectedWorkspaceID: WorkspaceID()
    )
    #expect(visible.isEmpty)
}

@Test func visibleTerminalsForEmptyWorkspaceListIsEmpty() {
    let visible = WorkspaceVisibility.visibleTerminalIDs(
        workspaces: [],
        selectedWorkspaceID: WorkspaceID()
    )
    #expect(visible.isEmpty)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter WorkspaceVisibilityTests`
Expected: FAIL — `WorkspaceVisibility` is undefined.

- [ ] **Step 3: Implement the function**

Create `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceVisibility.swift`:

```swift
import Foundation

/// Pure rule for "which terminals can the user currently see?". Used to
/// scope per-tick work (agent state polling) and to mark every other
/// surface occluded so libghostty can pause its rendering.
///
/// Visibility rule: in the selected workspace, the currently-selected tab
/// of every pane shown by `WorkspaceState.visibleRoot`. `visibleRoot`
/// already collapses to a single leaf when a pane is zoomed, so zoom is
/// honored automatically. A `selectedWorkspaceID` that does not match any
/// workspace yields the empty set (no crash).
public enum WorkspaceVisibility {
    public static func visibleTerminalIDs(
        workspaces: [WorkspaceState],
        selectedWorkspaceID: WorkspaceID
    ) -> Set<TerminalID> {
        guard let selected = workspaces.first(where: { $0.id == selectedWorkspaceID }) else {
            return []
        }
        var ids = Set<TerminalID>()
        for paneID in selected.visibleRoot.leaves {
            if let pane = selected.panes[paneID] {
                ids.insert(pane.selectedTabID)
            }
        }
        return ids
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh --filter WorkspaceVisibilityTests`
Expected: PASS — 7 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceVisibility.swift Apps/Conductor/Tests/ConductorCoreTests/WorkspaceVisibilityTests.swift
git commit -m "feat: pure WorkspaceVisibility — visible terminal set

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `TerminalSurface.setOccluded(_:)` — thin libghostty shim

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`

This is a libghostty-bound shim with no unit test (verified at the integration step in Task 5). It mirrors the `setFocused` pattern that already lives in this file (`:280-286`).

- [ ] **Step 1: Read the existing `setFocused` block to match its style**

Run: `cd Apps/Conductor && sed -n '280,290p' Sources/Conductor/Terminal/TerminalSurface.swift`
Expected output (style reference, do NOT modify it):

```swift
    func setFocused(_ focused: Bool, force: Bool = false) {
        guard force || focused != isFocused else { return }
        isFocused = focused
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
        ghostty_surface_refresh(surface)
    }
```

- [ ] **Step 2: Add the de-duped occlusion field next to `isFocused`**

Find the line:

```swift
    private var isFocused = false
```

(currently at `:42`). Add directly after it:

```swift
    private var lastSetOccluded: Bool?
```

The `Optional` lets the first `setOccluded(false)` after attach actually fire (it never equals the initial `nil`). Subsequent calls only fire on a real flip.

- [ ] **Step 3: Add `setOccluded(_:)` next to `setFocused`**

Insert this method immediately after the closing `}` of `setFocused(_:force:)` (currently at `:286`):

```swift
    /// Tells libghostty whether the surface is hidden so it can pause its
    /// CVDisplayLink renderer. Idempotent: redundant calls with the same
    /// value are dropped. Safe to call before the surface is attached —
    /// the value will be re-applied by the next `applyOcclusion()` after
    /// attach.
    func setOccluded(_ occluded: Bool) {
        guard let surface else { return }
        guard occluded != lastSetOccluded else { return }
        lastSetOccluded = occluded
        ghostty_surface_set_occlusion(surface, occluded)
    }
```

- [ ] **Step 4: Verify it builds**

Run: `cd Apps/Conductor && swift build`
Expected: `Build complete!` (the pre-existing `_ImFontConfig` / `_ImGuiStyle` linker warnings from libghostty are harmless).

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift
git commit -m "feat: TerminalSurface.setOccluded — thin set_occlusion wrapper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Scope the agent poll to the visible set; drop forced refresh

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

The poll currently iterates `allTerminalIDs()` and force-calls `surface.refresh()` on every surface (`:3442-3467`). After this task, it iterates only the visible set and reads `visibleText()` only — no forced refresh, no work for off-screen terminals.

- [ ] **Step 1: Read the current method to confirm shape**

Run: `cd Apps/Conductor && sed -n '3442,3467p' Sources/Conductor/UI/ConductorWindowModel.swift`
Expected: a `private func refreshVisibleAgentRuntimeStates()` that opens with `for terminalID in allTerminalIDs() {` and contains `surface.refresh()` before `surface.visibleText()`. If the line numbers have shifted, search by symbol name; otherwise stop and report.

- [ ] **Step 2: Replace the method body**

Replace the existing `refreshVisibleAgentRuntimeStates()` with:

```swift
    private func refreshVisibleAgentRuntimeStates() {
        let visible = WorkspaceVisibility.visibleTerminalIDs(
            workspaces: workspaces,
            selectedWorkspaceID: selectedWorkspaceID
        )
        for terminalID in visible {
            guard let surface = surfaceCoordinator.existingSurface(for: terminalID) else {
                continue
            }
            // Intentionally NO surface.refresh() here. visibleText() is a cheap
            // viewport read; render cadence is libghostty's responsibility.
            guard let state = Self.visibleAgentRuntimeState(in: surface.visibleText()) else {
                continue
            }
            let current = metadata(for: terminalID)
            switch state {
            case .active(let title):
                guard current.activeAgentTitle != title else { continue }
                updateMetadata(for: terminalID) { metadata in
                    metadata.activeAgentTitle = title
                    metadata.activeAgentStartedAt = Date()
                }
            case .inactive(let title):
                guard current.activeAgentTitle == title else { continue }
                updateMetadata(for: terminalID) { metadata in
                    metadata.activeAgentTitle = nil
                    metadata.activeAgentStartedAt = nil
                }
            }
        }
    }
```

Leave `allTerminalIDs()` (currently at `:3469`) in place — other call sites use it.

- [ ] **Step 3: Confirm `ConductorCore` is imported (no new import needed)**

Run: `cd Apps/Conductor && head -20 Sources/Conductor/UI/ConductorWindowModel.swift | grep -n '^import'`
Expected output includes `import ConductorCore`. If absent, stop and report — the symbol `WorkspaceVisibility` will not resolve otherwise.

- [ ] **Step 4: Verify it builds**

Run: `cd Apps/Conductor && swift build`
Expected: `Build complete!` (only the pre-existing libghostty linker warnings).

- [ ] **Step 5: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "perf: scope agent poll to visible terminals; drop forced refresh

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `applyOcclusion()` and its three call sites

**Files:**
- Modify: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`

Three things wired up in one task because they only make sense together: the helper, the two property setters that drive most visibility changes, and the surface-attach hook.

- [ ] **Step 1: Add `applyOcclusion()` next to the poll**

Insert this method **immediately after** the `refreshVisibleAgentRuntimeStates()` method (the one updated in Task 3):

```swift
    /// Marks every existing surface occluded ⇔ not in the currently-visible
    /// terminal set, so libghostty pauses renderers for hidden tabs, hidden
    /// splits, and background workspaces. Cheap: iterates only attached
    /// surfaces, and each `setOccluded` call is a no-op when the value is
    /// unchanged.
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

- [ ] **Step 2: Add `didSet` to `workspaces`**

Find this declaration (currently at `:180`):

```swift
    @Published private(set) var workspaces: [WorkspaceState]
```

Replace it with:

```swift
    @Published private(set) var workspaces: [WorkspaceState] {
        didSet { applyOcclusion() }
    }
```

- [ ] **Step 3: Add `didSet` to `selectedWorkspaceID`**

Find this declaration (currently at `:308`):

```swift
    private var selectedWorkspaceID: WorkspaceID
```

Replace it with:

```swift
    private var selectedWorkspaceID: WorkspaceID {
        didSet { applyOcclusion() }
    }
```

- [ ] **Step 4: Hook the surface-attach path**

Find `surface(for:)` and apply occlusion before returning the surface to the
caller:

```swift
        applyOcclusion()
        return surface
    }
```

- [ ] **Step 5: Verify it builds**

Run: `cd Apps/Conductor && swift build`
Expected: `Build complete!` (only the pre-existing libghostty linker warnings).

- [ ] **Step 6: Verify the existing test suite still passes (no regression)**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh`
Expected: `Test run with N tests in 0 suites passed` — the count should match Task 1's run plus prior fixtures (≈78). No failures.

- [ ] **Step 7: Commit**

```bash
git add Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift
git commit -m "feat: applyOcclusion on visibility changes and surface attach

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Build the bundle, run smoke gate, and verify steady-state CPU drops

**Files:** none (verification only).

- [ ] **Step 1: Run the full unit suite**

Run: `cd Apps/Conductor && ./Scripts/swift-test.sh`
Expected: all tests pass; final line is `Test run with N tests in 0 suites passed`.

- [ ] **Step 2: Run the smoke gate**

Run: `cd Apps/Conductor && swift run ConductorModelCheck`
Expected: `ConductorModelCheck passed`.

- [ ] **Step 3: Build the app bundle**

Run: `cd Apps/Conductor && ./Scripts/build-app-bundle.sh`
Expected: trailing line `/Users/.../Apps/Conductor/.build/Conductor.app` and an ad-hoc-signed bundle.

- [ ] **Step 4: Manual end-to-end check**

This is GUI; the controller cannot drive it from a non-graphical shell. From a real Finder/Dock launch:

1. Open `/Users/uchihasasuke/Desktop/conductor/Apps/Conductor/.build/Conductor.app` in Finder.
2. In the visible terminal pane, run a CPU-burning command, e.g. `yes > /dev/null`.
3. Note the Conductor process CPU% in Activity Monitor (or `top -pid <pid> -l 2 | tail -2`).
4. Switch to a **different tab in the same pane**, OR a **different workspace**. The pane running `yes` is now offscreen.
5. Confirm the Conductor process CPU% drops noticeably (libghostty pauses the offscreen renderer once `setOccluded(true)` fires).
6. Switch back to the running pane; confirm CPU resumes and the output continues without visible artifacts (occlusion only affects rendering — the PTY keeps running, so output keeps accumulating in scrollback).
7. With Codex (or `codex --version` followed by an interactive Codex session) running in the visible pane, confirm the active/inactive indicator still updates within ~1 second (no regression from the dropped `surface.refresh()`).

- [ ] **Step 5: Commit any verification fixups (otherwise skip)**

If Step 4 surfaced a real issue (e.g. occlusion not flipping when expected), fix it with a follow-up commit referencing this plan; otherwise this step is a no-op.

---

## Self-Review

- **Spec coverage** — §5.1 `WorkspaceVisibility` → Task 1; §5.2 `TerminalSurface.setOccluded` → Task 2; §5.3 poll scope-shrink + drop refresh → Task 3; §5.3 `applyOcclusion()` + `workspaces`/`selectedWorkspaceID` `didSet` + surface-attach hook → Task 4; §8 verification → Task 5. All covered.
- **Type consistency** — `WorkspaceVisibility.visibleTerminalIDs(workspaces:selectedWorkspaceID:) -> Set<TerminalID>`, `TerminalSurface.setOccluded(_:)`, `ConductorWindowModel.applyOcclusion()` — names and signatures match across tasks.
- **Pre-existing-file caveat** — Tasks 3 and 4 cite line numbers (`:3442`, `:180`, `:308`, `:1364`); each step describes the surrounding code so the engineer can locate the symbol if line numbers have drifted.
- **Out-of-scope guardrails** — `NSWindow.occlusionState`, slow heartbeat polling for non-visible terminals, and main-thread watchdog touch-ups are explicitly NOT part of this plan (per spec §5.4).
