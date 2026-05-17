# Conductor Foundation Execution Plan

This plan orders the work so the product becomes stable from the inside outward. Do not
skip ahead to higher-level agent features until the terminal workspace feels dependable.

## Stage 1: Correctness Before Features

1. [done] Fix tab host swapping.
2. [done] Add tab close model operation.
3. [done] Add pane close and split collapse model operation.
4. [done] Add model checks for tab close, pane close, and invalid focus prevention.
5. [done] Add UI close affordances for tabs and panes.
6. [done] Add lifecycle logs around visible host changes and close/free.

**Exit Criteria**:

- Tabs can switch and close without showing stale terminal contents.
- Panes can close without leaving invalid layout state.
- `swift build` and `swift run ConductorModelCheck` pass.

## Stage 2: Usable Split Layout

1. [done] Add minimum pane size policy.
2. [done] Add split command availability checks.
3. [done] Disable split controls when a pane cannot remain usable.
4. [done] Store split fractions in the model.
5. [done] Implement draggable split dividers.
6. [done] Add equalize splits.
7. [done] Add split zoom.

**Exit Criteria**:

- Repeated split commands cannot create unusable narrow panes.
- Users can resize and recover a complex layout.

## Stage 3: Focus and Keyboard Reliability

1. [done] Define focus transition flow from model to AppKit first responder to Ghostty focus.
2. [done] Add click-to-focus without stealing focus during passive updates.
3. [done] Add next/previous tab shortcuts.
4. [done] Add adjacent pane focus shortcuts.
5. [done] Add close tab and close pane shortcuts.
6. [manual validation] Verify hidden terminals cannot receive accidental keyboard input.

**Exit Criteria**:

- Visual focus, model focus, and keyboard destination agree after tab switch, split, close,
  and shortcut operations.

## Stage 4: cmux/Ghostty Action Bridge

1. [done] Re-read cmux action handling for split/focus/resize/equalize/zoom.
2. [done] Add an internal action dispatcher in ConductorCore.
3. [done] Map Ghostty new split action to Conductor split operations.
4. [done] Map Ghostty focus split action to Conductor focus operations.
5. [done] Map resize/equalize/zoom actions.
6. [done] Add logging and checks for unsupported actions.
7. [done] Bridge Ghostty tab actions: new tab/window, move tab, goto tab, close this/other/right, and command palette toggle.
8. [done] Bridge stable compact Ghostty metadata: pwd, desktop notification, progress, command finished, search, readonly, and open URL.
9. [deferred] Handle startup-sensitive actions such as cell size, color/config change, and bell only after a dedicated lifecycle test; returning handled for these during startup can crash Ghostty.

**Exit Criteria**:

- Ghostty-owned keybindings can drive Conductor-owned layout behavior.

## Stage 5: Tab Strip Product Quality

1. [done] Add close and stable tab sizing.
2. [done] Add overflow behavior for many tabs.
3. [done] Add move selected tab left/right by shortcut.
4. [done] Add drag reorder.
5. [done] Add move tab to another pane.
6. [done] Add move tab to new split.
7. [done] Add title metadata updates without storing transcript.
8. [done] Add cross-pane tab drag/drop and drop-to-end behavior.

## Stage 5.5: Recovery / Validation UX

1. [done] Add command palette.
2. [done] Add reset workspace command.
3. [done] Add `.app` bundle build script.
4. [done] Add full local gate script.
5. [done] Prevent smoke automation from mutating persisted user state.

**Exit Criteria**:

- The tab strip remains fast and understandable with many terminal sessions.

## Stage 6: Performance and Stress Verification

1. [done] Add performance signposts for tab switch, split, resize, close, host swap, and attach.
2. [done] Add long-output stress scenario with several active panes.
3. [done] Add rapid tab switching and complex workspace invariant stress through model checks and smoke automation.
4. [done] Add resize-while-output stress.
5. [pending] Inspect main-thread behavior and SwiftUI invalidation with Instruments.
6. [pending] Document thresholds and findings.

**Exit Criteria**:

- UI chrome remains responsive while terminals produce large output.

## Stage 7: Persistence and Recovery

1. [done] Persist workspace model structure.
2. [done] Persist theme and layout preferences.
3. [done] Restore tabs as fresh shells with original working directories.
4. [done] Add crash-safe writes.
5. [done] Add user-facing recovery path for invalid saved layouts.
6. [done] Keep smoke automation from mutating persisted user state.
7. [done] Debounce workspace persistence so split dragging does not write on every frame.

**Exit Criteria**:

- Conductor can restart into the same workspace structure safely.

## Stage 8: Release Readiness

1. [done] Add smoke launch checks.
2. [done] Add manual QA checklist for terminal basics and IME.
3. [done] Add documentation for GhosttyKit preparation and app launch.
4. [partial] Add release gate checklist.
5. Only then expand into agent/workflow features.

**Exit Criteria**:

- The app is boringly reliable for terminal workspace basics.
