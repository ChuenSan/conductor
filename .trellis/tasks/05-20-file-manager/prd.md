# File Manager Feature

## Goal

Add a native file-management surface to Conductor so users can inspect and act on files related to the focused terminal workspace without leaving the app.

## What I Already Know

* The user asked to open a dedicated worktree and start a file manager feature.
* The new worktree is `/Users/cses-38/workspace/conductor-file-manager` on branch `codex/file-manager`.
* Conductor is a Swift Package macOS app with a SwiftUI shell and AppKit integration points.
* The current shell has a terminal stage plus an optional right-side tool preview panel driven by `ConductorWindowModel.toolPreviewItem`.
* The model already tracks focused terminal working directories through `focusedWorkingDirectoryURL`.
* Existing commands include opening/copying the focused directory and creating a terminal at that directory.
* Local file URLs opened from terminal output already route into an in-app preview path for supported images/text and Finder for reveal behavior.

## Assumptions

* The first version should be an in-app browser for the focused terminal directory, not a full Finder replacement.
* The feature should preserve the core terminal performance rule: live terminal output, scrollback, and rendering stay out of SwiftUI state.
* File metadata can enter SwiftUI state because it is compact app metadata, but directory scans should be bounded and refreshed deliberately.
* Destructive and mutating file operations are out of scope until the interaction model is explicitly designed.

## Open Questions

* None.

## Requirements (Evolving)

* Provide file-management entry points from the main toolbar, command palette, and terminal right-click context menu.
* Anchor the initial file view to the focused terminal working directory when available.
* Present the MVP as a right-side file panel alongside the terminal stage, matching the existing optional tool-preview panel pattern.
* Keep the MVP read-only with an in-place disclosure navigation model: clicking a directory expands or collapses it inside the list, and clicking a file replaces the content with the file preview.
* Render Markdown/text files in an editor-style source preview with line numbers and a minimap, following Codux's text-file interaction pattern.
* Treat Markdown as a first-class document type, not just another source file.
* Markdown files should support source editing, rendered preview, and a document navigation model.
* Markdown rendering should handle headings, paragraphs, emphasis, lists, block quotes, fenced code blocks, inline code, links, images, tables where feasible, horizontal rules, and task-list checkboxes.
* Markdown editing should preserve source-first behavior: save writes the original `.md`, and preview is derived from the current editor text.
* Provide Markdown document outline from headings, with click-to-jump behavior.
* Provide in-document Markdown search with next/previous navigation. Search should work for the source text at minimum, and should keep preview/source position synchronized where feasible.
* Provide heading/anchor jump support for local links such as `#section-title` where feasible.
* Provide link handling:
  * External links open in the system browser.
  * Relative file links open in Conductor's file workspace when they resolve inside the current root.
  * Relative image links render in preview when they resolve safely.
  * Broken links/images show a restrained missing-state affordance rather than failing silently.
* Provide a clear Markdown toolbar mode surface: source, preview, and split/side-by-side when space allows.
* Default Markdown layout: use split source+preview on wide editor surfaces; use source mode on narrow surfaces, with explicit source/preview/split switching.
* File mutations that are exposed in the file manager must behave like a careful native file browser:
  * Rename should be inline, keep focus while editing, commit on Return, cancel on Escape, and preserve the selected/expanded item after success.
  * Delete must be a two-step move-to-Trash flow: first mark the item, then require an explicit confirmation before touching disk.
  * Copy, cut, paste, rename, and delete should refresh affected directories while preserving useful expanded/selected state.
  * Operation failures must show a visible error message; they should not fail with only a beep.
* Preserve the terminal performance boundary: Markdown parsing/rendering may use bounded document text from the open file, but must not interact with terminal scrollback or high-frequency terminal state.
* Allow inserting the selected file or folder path into the focused terminal.
* Support basic inspection of directory contents without disturbing terminal focus or high-frequency terminal rendering.
* Rewrite the current single-file `ToolPreviewPanel` into the new file-management surface instead of extending it as-is.
* Use Codux's file browser as pattern-level inspiration: a separate filesystem service, compact item/row/preview models, a right-side navigation panel, and deliberate preview/open-mode decisions.
* Avoid copying Codux source code verbatim; use it only as a reference for behavior and decomposition.

## Acceptance Criteria (Evolving)

* [ ] A user can open the file manager from the Conductor UI.
* [ ] A user can open the file manager from a terminal context menu when the terminal has a valid working directory.
* [ ] The file manager starts at the focused terminal's current directory when that directory exists.
* [ ] Directory entries render with stable layout and do not cause terminal surface re-creation.
* [ ] Selecting a supported file can preview it or route to the existing preview behavior.
* [ ] Markdown/text previews show line numbers and an editor-like source layout.
* [ ] Opening a Markdown file exposes Markdown-specific controls rather than only the generic text editor controls.
* [ ] Markdown preview renders common Markdown blocks and updates from current editor text.
* [ ] Markdown source mode remains fully editable and saveable.
* [ ] Markdown files expose a heading outline, and clicking an outline item jumps to the corresponding section.
* [ ] Markdown search can find matches and navigate next/previous inside the current document.
* [ ] Markdown local heading links and relative file links resolve to useful in-app navigation where possible.
* [ ] Markdown preview renders relative images that are inside or under the current root, with a clear fallback for missing/unsupported images.
* [ ] Large Markdown files degrade gracefully: avoid expensive live rendering, keep editing available when safe, and show preview limits explicitly.
* [ ] A user can expand and collapse subdirectories inline without a split tree layout.
* [ ] A user can rename an item inline, with keyboard commit/cancel behavior and visible errors.
* [ ] A user can mark one or more items for deletion and only move them to Trash after confirming.
* [ ] Copy/cut/paste/delete/rename refresh the changed directories without collapsing the whole browser unnecessarily.
* [ ] A user can reveal the current file or folder in Finder.
* [ ] A user can insert the selected file or folder path into the focused terminal.
* [ ] The old ad hoc `ToolPreviewPanel` path is replaced or absorbed so local file URLs and file-browser selections share one coherent preview experience.
* [ ] The implementation passes the Conductor check script or equivalent Swift package build checks.

## Definition of Done

* Tests or model checks are added/updated where appropriate.
* Lint/type-check/build checks pass.
* UI follows existing Conductor design and localization patterns.
* New file-system behavior handles missing directories and permission errors gracefully.
* Scope and out-of-scope behavior are documented in this PRD before implementation starts.

## Out of Scope (Initial)

* Recursive project search or indexed file search.
* Bulk operations.
* New file or folder creation.
* Permanent delete, chmod, overwrite/replace, and bulk operations beyond the two-step move-to-Trash flow.
* Watching the whole filesystem continuously.
* Terminal transcript parsing or any terminal-renderer changes.
* Copying GPL-licensed Codux implementation code into Conductor.
* Full Markdown authoring suite features such as PDF export, WYSIWYG editing, collaborative comments, or Mermaid/diagram execution unless explicitly added later.

## Technical Notes

* Likely UI files:
  * `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorShellCommand.swift`
* Existing supporting concepts:
  * `ToolPreviewItem` determines image/text/unsupported preview kind.
  * `ConductorWindowModel.focusedWorkingDirectoryURL` validates focused terminal directories.
  * `ConductorShellCommand` centralizes command availability and dispatch.
* Relevant specs to load before implementation:
  * `.trellis/spec/frontend/index.md`
  * `.trellis/spec/frontend/component-guidelines.md`
  * `.trellis/spec/frontend/state-management.md`
  * `.trellis/spec/backend/index.md`
  * `.trellis/spec/backend/directory-structure.md`
  * `.trellis/spec/backend/quality-guidelines.md`
  * `.trellis/spec/guides/high-performance-terminal-roadmap.md`
* Research references:
  * `research/codux-file-browser.md` — Codux uses a file service + tree panel + separate file preview/editor state; Conductor should borrow the decomposition but keep the MVP read-only.
* Follow-up Codux review:
  * Codux currently treats `.md` as an editable text/source file through `CodeEditSourceEditor`; it does not provide a dedicated Markdown preview, outline, heading navigation, or document-aware Markdown tooling in the file editor.
  * Codux's `MarkdownUI` dependency is used around agent/message rendering rather than workspace file editing.
  * Conductor should intentionally exceed that baseline for Markdown files instead of merely matching it.

## Decision (ADR-lite)

**Context**: The file manager needs to be available during terminal work without destabilizing the terminal renderer or forcing a major shell redesign.

**Decision**: Build the MVP as a right-side file panel that can sit alongside the terminal stage, reusing the existing shell pattern used by the optional tool-preview panel.

**Consequences**: This keeps the first implementation contained and makes it easy to anchor the panel to the focused terminal directory. The trade-off is limited horizontal space, so the MVP should favor compact list/detail interactions over a multi-column Finder replacement.

## Scope Decision

**Context**: File management can quickly expand into mutation, conflict handling, confirmation flows, and permission edge cases.

**Decision**: The first version is read-only browse and preview: directory listing, folder navigation, parent navigation, supported file preview, and Reveal in Finder.

**Consequences**: This makes the MVP safer and faster to ship while still proving the core “files beside terminal” workflow. Creation, rename, delete, move, and bulk operations remain future work.

## Terminal Path Insertion Decision

**Context**: The file manager is meant to support AI coding and terminal workflows, where accurately passing file paths to the focused shell is common.

**Decision**: Include a read-only action to insert the selected file or folder path into the focused terminal.

**Consequences**: This makes the file panel more useful without introducing filesystem mutation. The implementation should quote or escape paths safely for shell input and should no-op or disable the action when no focused terminal is available.

## Preview Rewrite Decision

**Context**: The existing `ToolPreviewPanel` is a narrow single-file preview surfaced from terminal file URLs. It is useful as prior art but not a strong foundation for a file manager. The user asked to rewrite it and pointed to Codux's file management as a reference.

**Decision**: Replace/absorb the current preview panel into a new right-side file-management surface. The new implementation should separate filesystem service logic from SwiftUI presentation, maintain compact browser state, and provide an integrated preview area for selected files.

**Consequences**: This avoids preserving awkward preview-panel behavior and gives terminal file URLs, toolbar entry, command palette entry, and context-menu entry one coherent destination. The trade-off is a larger implementation than simply bolting a file list onto the old preview panel.

## Entry Point Decision

**Context**: The file manager should be discoverable from the shell while also feeling natural when the user is acting on a specific terminal's working directory.

**Decision**: Add both primary shell entry points and contextual terminal entry points: a toolbar button, a command palette item, and a terminal right-click menu action.

**Consequences**: The toolbar and command palette make the feature easy to discover, while the context menu keeps directory-specific workflows close to the terminal. The implementation must share one command path so these entry points stay consistent.
