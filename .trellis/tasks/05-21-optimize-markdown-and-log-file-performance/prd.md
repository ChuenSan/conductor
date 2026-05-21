# Optimize markdown and log file performance

## Goal

Opening or previewing Markdown, log, structured text, and other large text-like files should not make the whole Conductor UI feel stuck. Small files should remain editable and pleasant; larger files should automatically use bounded preview/indexing paths.

## What I Already Know

- The user reports that Markdown, log, and other formats can make the overall app very laggy.
- The app already has an AppKit-backed large text viewer, but several paths still read and render sizable text in SwiftUI.
- Terminal output and scrollback must never enter SwiftUI state.

## Requirements

- Lower high-cost Markdown/log/structured-text thresholds so expensive editors and previews are bypassed sooner.
- File manager preview must cap bytes and rendered rows per format.
- Workspace file search must not recompute full-text matches on every body render.
- Large text view must preserve indexed outline/search behavior for Markdown and log-like files.
- Keep small files editable.

## Acceptance Criteria

- Markdown and log files above bounded thresholds open in large text mode instead of high-cost SwiftUI/CodeEdit editing surfaces.
- File manager preview reads less data and renders a capped number of rows/lines/nodes for text, table, key-value, and structured views.
- Search result computation in normal file editors is cached by query/text version rather than recomputed through a computed property during every render.
- Project check script passes.

## Out Of Scope

- Replacing the Markdown renderer/editor architecture wholesale.
- Adding a new third-party virtualized editor dependency.
- Inspecting terminal scrollback text.
