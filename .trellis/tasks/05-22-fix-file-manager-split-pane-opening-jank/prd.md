# Fix File Manager Split Pane Opening Jank

## Goal

Opening the right-side file manager while a workspace has two or more terminal splits must stay smooth. The file manager should not trigger repeated expensive Ghostty surface geometry updates, rebuild split hosting roots during the panel reveal, or make the file manager's own list/header/status rendering do avoidable repeated work.

## What I Already Know

- The user reports severe stutter when opening the file manager with two split panes.
- The file manager's directory scan and preview loading already run off the main actor via detached tasks.
- The current right-side file manager tray animates its width from 0 to 468 points, which continuously shrinks the terminal workspace during the animation.
- `TerminalSurfaceRepresentable` currently calls `syncGeometry` immediately from hosted view frame synchronization.
- `SplitNodeView` refreshes both split hosting roots on every `updateNSView`.
- The user clarified that the file manager itself also feels stuck, so the fix must address file tree state/render work, not only terminal resizing.

## Requirements

- Opening and closing the file manager must avoid continuous terminal surface resize work.
- Terminal panes must keep stable AppKit/Ghostty host identity.
- File manager UI should still appear as a right-side tray and remain usable.
- File manager list rendering, status counts, selection, and search should avoid recomputing the visible tree repeatedly during a single SwiftUI update.
- The fix must preserve the existing file manager workflow and keyboard focus behavior.

## Acceptance Criteria

- [ ] With two terminal splits visible, toggling the file manager no longer drives per-frame Ghostty geometry sync during the reveal.
- [ ] Terminal geometry updates are coalesced after layout instead of called synchronously from SwiftUI/AppKit layout churn.
- [ ] Split hosting roots are not rebuilt unnecessarily when their inputs are unchanged.
- [ ] Opening the file manager does not repeatedly compute `displayedRows`/known rows for each visible row and toolbar/status view.
- [ ] File manager scrolling and search remain responsive for typical project directories.
- [ ] Project build/check command completes or any blocker is documented.

## Out of Scope

- Replacing the file manager UI.
- Reworking terminal rendering internals beyond geometry sync scheduling.
- Adding new file manager features.

## Technical Notes

- Relevant files:
  - `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
  - `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift`
  - `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurfaceRepresentable.swift`
  - `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`
- Relevant specs:
  - `.trellis/spec/guides/high-performance-terminal-roadmap.md`
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/state-management.md`
  - `.trellis/spec/backend/ghosttykit-integration.md`
  - `.trellis/spec/backend/quality-guidelines.md`
