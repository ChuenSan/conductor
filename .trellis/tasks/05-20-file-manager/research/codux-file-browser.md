# Codux File Browser Research

Source: https://github.com/duxweb/codux

## Files Reviewed

* `Sources/DmuxWorkspace/Models/ProjectFileModels.swift`
* `Sources/DmuxWorkspace/Services/ProjectFileBrowserService.swift`
* `Sources/DmuxWorkspace/UI/FileBrowser/FileBrowserPanelView.swift`
* `Sources/DmuxWorkspace/App/AppModel+WorkspaceFiles.swift`
* `Sources/DmuxWorkspace/UI/Workspace/WorkspaceFileEditorView.swift`
* `Sources/DmuxWorkspace/UI/Workspace/WorkspaceView.swift`
* `Sources/DmuxWorkspace/UI/Workspace/NativeSourceEditorTextPreview.swift`
* `Sources/DmuxWorkspace/UI/Workspace/AgentMessageRendering.swift`
* `Sources/DmuxWorkspace/UI/RootSplitContainer.swift`
* `Sources/DmuxWorkspace/UI/RootTitlebarView.swift`

## What Codux Does

Codux has a native project file browser exposed from the title bar as a right panel. The panel displays a hierarchical file tree with expandable folders, row selection, context menus, drag/drop, pasteboard support, inline rename, delete confirmation, Finder reveal, copy path, and insertion of file paths into the terminal.

Opening a file does not keep all preview behavior inside the right panel. Instead, Codux opens files into a workspace file mode with file tabs. The file editor view handles preview/editing, toolbar actions, save state, reload, find, undo/redo, save-as, and Finder reveal. This separates file navigation from file reading/editing.

Markdown and other text files are shown as source text in Codux, not rendered Markdown. The editor uses CodeEditSourceEditor with line numbers, current-line styling, source-theme colors, and a minimap. The important interaction lesson for Conductor is the editor-like source reading layout; Conductor can recreate the behavior without copying Codux's GPL code.

Codux imports MarkdownUI, but the inspected usage is around agent/message rendering (`AgentMessageRendering.swift`, `WorkspaceAgentPaneView.swift`), not workspace file editing. Codux's workspace Markdown file path does not provide a rendered document preview, heading outline, local anchor navigation, relative-image rendering, or document-aware search beyond the source editor find panel.

## Architecture Patterns Worth Borrowing

* Separate compact file models from UI state:
  * `ProjectFileItem` stores URL, display name, relative path, directory flag, and symlink flag.
  * `ProjectFileRow` adds tree depth for rendering.
  * Preview state is modeled separately from tree state.
* Put filesystem access behind a service:
  * Directory reading, sorting, relative paths, preview classification, save validation, copy/move helpers, and open-mode decisions live in `ProjectFileBrowserService`.
  * UI calls the service through a store instead of mixing raw `FileManager` work into row views.
* Keep the right panel focused on navigation:
  * The panel owns tree expansion, selected path, loading paths, and refresh.
  * File opening routes into a separate workspace content surface.
* Use predictable tree behavior:
  * Direct children only per folder load.
  * Directories sort before files.
  * Names use localized standard comparison.
  * Packages are not treated as directories.
  * Folder rows toggle on click; file rows select on single click and open on double click.
* Treat unsupported/heavy files deliberately:
  * Use UTType/open-mode checks to decide whether a file should preview in-app or open in the system app.
  * Detect binary files rather than trying to render everything as text.
  * Use a large-file threshold and avoid loading huge files into a normal text preview.
* Keyboard and pasteboard behavior are centralized:
  * Codux uses a hidden AppKit key handler view for browser shortcuts.
  * Drag/drop payloads distinguish internal files from external file URLs.

## What Not To Copy Into Conductor MVP

* Codux supports mutation: paste, move, copy, rename, delete, save, save-as. Our current MVP is read-only, so these should stay out.
* Codux has a project/worktree model. Conductor's MVP should anchor to the focused terminal working directory instead.
* Codux opens source files into a primary workspace editor. Conductor should decide separately whether file preview belongs inside the right panel or in the terminal stage.
* Do not copy code verbatim. Codux is GPL-3.0; use it as a reference for behavior and decomposition only.

## Recommended Conductor Direction

Rewrite the current single-file `ToolPreviewPanel` into a more capable file-management feature:

* Introduce a `FileBrowserService`-style backend object for directory listing and preview metadata.
* Introduce compact models similar to `FileBrowserItem`, `FileBrowserRow`, and `FilePreviewState`.
* Replace the current ad hoc preview item panel with a right-side `FileManagerPanel` that can show:
  * a header with current directory and refresh/reveal controls,
  * a scrollable directory tree/list,
  * selected file details and preview for supported text/images,
  * empty/error states for invalid or inaccessible directories.
* Keep MVP read-only:
  * browse directories,
  * navigate by expanding/opening folders,
  * select files,
  * preview supported files,
  * copy path,
  * reveal in Finder,
  * optionally insert path into the focused terminal.
* Keep all terminal scrollback/rendering out of SwiftUI state; only file metadata and preview snippets enter SwiftUI.

## Markdown Opportunity Beyond Codux

Conductor should intentionally treat `.md` and `.markdown` as first-class documents:

* Keep a source mode backed by the CodeEditSourceEditor integration.
* Add a rendered preview mode that updates from the current editor text.
* Add a heading outline extracted from Markdown source and make headings clickable.
* Add document search with next/previous navigation. Source search is the MVP baseline; preview/source synchronization is the better version.
* Resolve Markdown local anchors (`#heading`) and relative links. External links should leave the app through the browser, while relative files should open in Conductor's file workspace when they are under the current root.
* Render safe relative images under the current root and show a missing image affordance for broken references.
* Degrade gracefully for large Markdown files by disabling expensive live preview or showing a bounded preview with explicit status.
