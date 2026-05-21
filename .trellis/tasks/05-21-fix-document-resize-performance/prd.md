# Fix Document Resize Performance

## Goal

Opening a log or other protected large-text document must not make window resizing feel frozen. A 305 KB / ~3,000 line log should resize smoothly while the file manager and terminal chrome remain responsive.

## What I Already Know

- User reproduced severe resize jank with `java_error_in_idea_17655.log`.
- The file is routed to `ConductorLargeTextWorkspaceView` because `.log` files use protected large-text mode.
- `ConductorLargeTextViewport.updateNSView` calls `ConductorLargeTextHostView.configure(...)` on SwiftUI updates.
- `configure(...)` currently calls `canvas.apply(theme:fontSize:)` every update.
- `ConductorLargeTextCanvasView.apply(...)` currently rebuilds fonts and calls `setNeedsDisplay(bounds)` unconditionally.
- `setNeedsDisplay(bounds)` marks the full document canvas, not just the visible viewport. During window resizing this can be repeated many times.

## Assumptions

- The main culprit is repeated full-canvas invalidation during resize, not the background line indexer.
- The correct fix is to make large text rendering incremental: only redraw visible regions and only apply theme/font changes when the values actually changed.

## Requirements

- Avoid full-document redraws during ordinary window resize.
- Keep line indexing, search, jump-to-line, copy selected lines, and protected read-only preview behavior working.
- Do not move file content into SwiftUI state.
- Keep large text rendering in AppKit.

## Acceptance Criteria

- [ ] Opening a 300 KB / 3,000 line `.log` file does not make window resize visibly freeze.
- [ ] `ConductorLargeTextCanvasView` does not call full `setNeedsDisplay(bounds)` for no-op theme/font updates.
- [ ] Visible-only redraws are used for selection, search highlight, message, and cache-fill updates where possible.
- [ ] `cd Apps/Conductor && ./Scripts/check-conductor.sh` passes.

## Definition Of Done

- Build and model checks pass.
- Full Conductor gate passes, including shell panel and long-output stress routes.
- Any new large-text rendering convention is documented if it prevents this bug class.

## Out Of Scope

- Replacing the large-text renderer with CodeEdit or a new virtual table.
- Redesigning document tabs or file manager UI.
- Changing terminal renderer or Ghostty behavior.

## Technical Notes

- Relevant file: `Apps/Conductor/Sources/Conductor/UI/ConductorLargeTextWorkspaceView.swift`.
- Relevant specs: `.trellis/spec/frontend/component-guidelines.md`, `.trellis/spec/frontend/state-management.md`, `.trellis/spec/frontend/quality-guidelines.md`, `.trellis/spec/guides/high-performance-terminal-roadmap.md`.
