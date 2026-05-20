# Fix split pane duplicate cursor

## Goal

After creating a split pane, the existing terminal pane must repaint with one prompt/cursor and accurate Ghostty surface geometry. Split creation should keep each terminal's AppKit host and Ghostty surface identity stable while forcing the resized pre-existing surface to synchronize with its new bounds.

## What I already know

- The user reported that after splitting a pane, the old pane shows two prompts/cursors.
- `WorkspaceState.splitWorkspaceEdge` creates a fresh `TerminalTabState` for the new pane and does not reuse the old terminal ID.
- `ConductorWindowModel.surface(for:)` owns one `TerminalSurface` per `TerminalID`.
- `TerminalSurfaceRepresentable` embeds a stable `TerminalSurfaceContainerView`; `TerminalSurface` owns a stable `TerminalHostView`.
- Project specs require Ghostty/AppKit to own terminal rendering, with SwiftUI limited to split chrome and compact metadata.

## Assumptions

- The duplicate prompt/cursor is a stale Ghostty frame or stale surface size after the old host view is reparented/resized during split creation, not a duplicated shell process.
- A focused split operation should refresh existing visible surfaces after the split tree changes, without forcing refresh loops on every SwiftUI update.

## Requirements

- Split creation must preserve one live surface per terminal ID.
- Split creation must force geometry and repaint for visible surfaces affected by the split tree change.
- The fix must not put terminal transcript, cursor data, or renderer state into SwiftUI state.
- The fix must keep refreshes bounded to split/topology changes, not divider drags or ordinary metadata updates.

## Acceptance Criteria

- [ ] Existing pane does not show duplicate prompts/cursors after `splitRight` or `splitDown`.
- [ ] Newly created pane gets its own terminal surface and focus.
- [ ] Existing visible surfaces receive a forced geometry sync after split creation.
- [ ] `swift build` passes for `Apps/Conductor`.
- [ ] `swift run ConductorModelCheck` passes if available in the local toolchain.

## Definition of Done

- Focused, minimal code change.
- Quality checks run and results reported.
- Specs updated only if a reusable new rule is learned.

## Out of Scope

- Replacing the Ghostty surface route with a custom renderer.
- Redesigning split layout behavior.
- Adding terminal transcript/cursor inspection to SwiftUI.

## Technical Notes

- Relevant specs: `.trellis/spec/guides/high-performance-terminal-roadmap.md`, `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/state-management.md`, `.trellis/spec/backend/directory-structure.md`, `.trellis/spec/backend/quality-guidelines.md`, `.trellis/spec/backend/ghosttykit-integration.md`.
- Likely files: `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`, `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurfaceRepresentable.swift`, `Apps/Conductor/Sources/Conductor/Terminal/TerminalHostView.swift`, `Apps/Conductor/Sources/ConductorCore/Workspace/WorkspaceModel.swift`.
