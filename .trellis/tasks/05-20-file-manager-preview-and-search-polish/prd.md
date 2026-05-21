# File Manager Full Usability Design

## Goal

Upgrade the file workflow from a basic browser/editor into a fast daily-use workspace: the top toolbar search button should search the current context, files should support richer preview/open behavior, and file operations should reduce friction for repeated navigation and editing.

## What I already know

* The user clarified that "reuse search" means the top toolbar Search button, not separate ad hoc search fields.
* Current terminal search is driven by `ConductorShellCommand.showTerminalSearch` and the toolbar button in `ConductorRootView`.
* Markdown already has local search, but it is embedded in the Markdown toolbar rather than triggered by the global button.
* Text/code editors expose range selection through `ConductorCodeEditSourceEditor`.
* File manager has a tree view and keyboard focus, but no global-toolbar-triggered filtering.
* Image files currently tend to open via system apps rather than as workspace content.
* The user clarified that large files must be supported as part of the planned file workflow, not merely blocked by a protective message.
* Research from VS Code, CodeMirror, Zed, Monaco, and Sublime points to a dedicated large-file path: chunked buffers, viewport rendering, long-line guards, background indexing/search, and feature degradation by format.

## Requirements

* The toolbar Search button must route by context:
  * selected file tab -> search current file;
  * file manager visible without a selected file tab -> search/filter file tree;
  * otherwise -> terminal search.
* Markdown and plain text/code files must share the same top Search entry point.
* Search should support next/previous navigation and visible result counts.
* Image files should be viewable in the workspace with a lightweight image preview.
* File manager should support quick filtering from the global Search button.
* Large files must open in a dedicated high-performance mode as part of this plan.
* Large file mode must support opening, smooth scrolling, current-file search, Markdown outline, jump-to-line, copy, reveal in Finder, and controlled editing for safe bounded changes.

## Full Feature Design

The design rule for this task: every feature must define its entry point, happy path, failure path, state feedback, keyboard behavior where relevant, and explicit cutoff. Git-specific status/integration is intentionally deferred.

Global interaction rule: any icon-only button, menu trigger, or status badge must expose an immediate hover tooltip using the app's shared tooltip style. Native `.help` can remain as accessibility fallback, but the visible interaction must not rely on users guessing icon meaning.

### 1. Unified Context Search Entry
Entry: top toolbar Search button and `Cmd-F`.
Flow: inspect the active surface. If a workspace file tab is selected, open file search. If file manager is active and no file tab is selected, open file-tree filtering. Otherwise open terminal search.
Details: preserve existing query when reopening the same surface; focus the text field and select the previous query.
Cutoff: no whole-repository indexed search in this task.

### 2. Unified Search Style
Entry: any search surface.
Flow: all contexts use the same floating search control: search icon, scope chip, text field, result count, previous/next buttons, close button.
Details: same sizing, radius, shadow, focus behavior, keyboard handling.
Cutoff: no one-off search bars in child views.

### 3. File Tree Filtering
Entry: context search while file manager is active.
Flow: type query, visible rows filter by name/path/extension; arrows move through filtered rows; Enter opens.
Details: show match count; Esc closes and clears filter; selection remains valid when filter changes.
Cutoff: searches loaded tree nodes first; no background recursive indexing yet.

### 4. Current File Search
Entry: context search on text/code/Markdown file tab.
Flow: query selects current match; previous/next updates selection and scroll position.
Details: result count is shown; empty query clears match state.
Cutoff: binary and large protected files do not expose content search.

### 5. Search History
Entry: search field menu/future suggestion list.
Flow: successful queries are saved per workspace; user can reuse them.
Details: dedupe and keep last 10.
Cutoff: not synced across machines.

### 6. Recent Open Files
Entry: file manager header menu/section.
Flow: every workspace-opened file is pushed to recent; selecting recent reopens it.
Details: stale paths are skipped with a clear message.
Cutoff: keep last 20 local file URLs.

### 7. Favorite Directories
Entry: star/pin action on current directory or directory row.
Flow: pin directory, show it in quick access, click to navigate.
Details: stored locally; stale favorites are visually disabled or removed on use.
Cutoff: directories only, not individual files.

### 8. Path Breadcrumbs
Entry: file manager header.
Flow: current path displays clickable path segments; clicking a segment navigates there.
Details: long paths truncate middle segments; full path remains copyable via menu.
Cutoff: no editable path bar yet.

### 9. New File
Entry: toolbar plus button, directory context menu, `Cmd-N`.
Flow: create an available default name, select it, start inline rename.
Details: reject empty names, names containing `/`, and conflicts.
Cutoff: no template chooser yet.

### 10. New Folder
Entry: toolbar folder-plus button, directory context menu, `Cmd-Shift-N`.
Flow: create available folder name, select it, start inline rename, and expand parent.
Details: same validation and conflict handling as new file.
Cutoff: no nested path creation from a single typed string.

### 11. Copy File/Folder
Entry: context menu and `Cmd-C`.
Flow: write file URLs to pasteboard; paste copies into selected target directory.
Details: supports files and folders; future multi-select shares same path.
Cutoff: no cross-process metadata beyond file URLs and cut marker.

### 12. Cut/Move File/Folder
Entry: context menu and `Cmd-X`.
Flow: write cut marker; paste moves.
Details: prevent moving a folder into itself or a descendant.
Cutoff: no queued long-running transfer UI yet.

### 13. Paste Conflict Handling
Entry: context menu and `Cmd-V`.
Flow: on conflict, generate `name copy`, `name copy 2`, etc.
Details: never silently overwrite.
Cutoff: no interactive conflict resolution dialog in first pass.

### 14. Duplicate
Entry: context menu.
Flow: copy selected item into same directory using conflict-safe copy name.
Details: select duplicated result after refresh.
Cutoff: no batch duplicate until multi-select lands.

### 15. Safe Delete
Entry: context menu and `Cmd-Backspace`.
Flow: mark items, show confirmation bar, move to Trash after confirm.
Details: opened tabs for deleted paths close after success.
Cutoff: no permanent delete command.

### 16. Delete Undo
Entry: post-delete message/action.
Flow: after trash success, offer undo when system returns restoreable target.
Details: if restore fails, show error and keep tree accurate.
Cutoff: can be deferred if macOS trash restore metadata is unavailable.

### 17. Rename Linked Tabs
Entry: inline rename.
Flow: after rename success, update file tree and any opened workspace tab URLs.
Details: directory rename updates descendant tabs.
Cutoff: external rename handled by external-change detection.

### 18. Multi-format Text Preview
Entry: select text-like file.
Flow: preview text with line numbers, minimap, truncation warning.
Details: UTF-8/UTF-16 fallback; binary guard.
Cutoff: default inline preview reads up to 1 MB.

### 19. Markdown Enhancements
Entry: open `.md`/`.markdown`.
Flow: source/preview/split modes, outline, search, local image/link handling, code-copy action.
Details: no forced split by default; user controls mode.
Cutoff: no full browser-grade Markdown extensions.

### 20. Image Preview
Entry: open image.
Flow: workspace image tab with fit-to-window, actual-size, zoom, reveal/copy path.
Details: preserve aspect ratio and avoid dark cropped previews.
Cutoff: no image editing.

### 21. JSON/YAML/TOML View
Entry: open config file.
Flow: parse; show formatted tree/pretty view; errors show line/column.
Details: offer format-on-save only by explicit action.
Cutoff: no schema validation.

### 22. CSV/TSV Preview
Entry: open `.csv`/`.tsv`.
Flow: parse first rows into table with horizontal scroll and copy cell/row.
Details: detect delimiter by extension and content sniffing.
Cutoff: no spreadsheet editing.

### 23. plist/env/conf View
Entry: open config-like file.
Flow: show key/value-oriented view when parseable; fallback to text.
Details: copy key, value, or line.
Cutoff: no chmod or system preference editing.

### 24. External File Change Detection
Entry: opened file tab watches mtime/hash.
Flow: external change marks tab; user can reload, keep current, or compare.
Details: avoid overwriting unseen external changes on save.
Cutoff: first compare can be lightweight text diff.

### 25. Open With Menu
Entry: row context menu and tab menu.
Flow: choose workspace editor, system app, Finder, copy path, insert path into terminal.
Details: defaults by type but user can override.
Cutoff: no third-party editor registry.

### 26. Drag and Drop
Entry: drag rows.
Flow: drag to terminal inserts escaped path; drag to folder moves; Option-drag copies.
Details: show valid drop target and protect move-into-self.
Cutoff: first pass can be in-app only.

### 27. Keyboard Complete Operation
Entry: file tree focus.
Flow: arrows navigate/expand/collapse, Enter opens, Space previews, Cmd-R refreshes, Cmd-Backspace deletes, Cmd-Shift-N creates folder.
Details: do not steal text-editing shortcuts while rename/search fields are focused.
Cutoff: keyboard remapping is not included.

### 28. Batch Multi-select
Entry: Shift/Cmd click rows.
Flow: select multiple rows and run delete/copy/move/copy paths/open.
Details: batch open has a confirmation threshold.
Cutoff: no range operation across unloaded children.

### 29. Sorting
Entry: header sort menu.
Flow: sort by name, modified time, size, type; keep folders first toggle.
Details: choice persists locally.
Cutoff: no per-directory sort persistence in first pass.

### 30. Hidden Files Toggle
Entry: header eye/dotfiles button.
Flow: show/hide dotfiles and refresh current directory.
Details: `.DS_Store` remains hidden by default unless explicit debug mode exists.
Cutoff: no gitignore-based hiding in this task.

### 31. File Status Markers
Entry: rows and tabs.
Flow: badges show dirty, deleted, external changed, read-only, large, binary.
Details: tooltip explains the marker.
Cutoff: Git status not included.

### 32. Terminal Collaboration
Entry: row context menu.
Flow: insert path, cd to directory, run safe generated command in focused terminal.
Details: commands are inserted or confirmed, not blindly executed.
Cutoff: no destructive auto-run commands.

### 33. File Info Panel
Entry: context menu “Get Info”.
Flow: show metadata: type, size, dates, permissions, full path.
Details: path values are copyable.
Cutoff: no permission editor in first pass.

### 34. Quick Copy
Entry: Copy As submenu.
Flow: copy name, absolute path, relative path, parent directory, shell-escaped path.
Details: relative path uses workspace/current root.
Cutoff: no custom copy templates yet.

### 35. Large File Mode
Entry: open text-like files above the interactive threshold, including Markdown, source, logs, structured config, CSV/TSV, and plain text.
Flow: route to a dedicated large-file workspace tab backed by an AppKit viewport renderer and chunked file buffer. Open the first screen quickly, build sparse line indexes in the background, render only visible rows plus overscan, and keep SwiftUI limited to toolbar/state chrome.
Details: support current-file search, result navigation, jump-to-line, copy selection/path, reveal in Finder, system app open, line numbers, long-line truncation, and format labels. Markdown large-file mode must preserve a lightweight outline generated by scanning heading lines instead of full Markdown parsing.
Controlled editing: support bounded in-place edits only when the changed region is loaded and small enough to save safely. If an edit would require rewriting an unsafe/unindexed region, show a clear message and keep the file unmodified.
Cutoff: no full rope/piece-tree arbitrary large-file editing in this task; no full JSON tree or CSV spreadsheet parser for huge files.

### 36. Permission and Read-only Handling
Entry: open/save/rename/create/delete failures.
Flow: show clear operation message and read-only tab state.
Details: preserve user edits if save fails.
Cutoff: no sudo escalation UI.

## Acceptance Criteria

* [ ] Cmd-F / toolbar Search focuses search for the selected text/Markdown file.
* [ ] Cmd-F / toolbar Search focuses file-tree filtering when the file manager is the active file surface.
* [ ] Terminal search behavior still works when terminal is the active surface.
* [ ] Text/code search selects matches in the editor.
* [ ] Markdown search still jumps both source and preview.
* [ ] Image files can open in the workspace instead of only the system app.
* [ ] A large Markdown/text/log/config/CSV file opens without freezing the UI.
* [ ] Large file mode renders by viewport, not by creating SwiftUI views for every loaded line.
* [ ] Large Markdown mode keeps a usable outline and allows clicking headings to jump.
* [ ] Large file search runs in the background, can be cancelled by a new query, and shows progress/results without blocking scrolling.
* [ ] Long lines are truncated or virtually rendered so one generated line cannot freeze layout.
* [ ] Large file controlled edits either save safely or refuse with a clear non-destructive message.
* [ ] `swift build` and `swift run ConductorModelCheck` pass.

## Out of Scope

* Full binary/office/PDF rendering.
* Whole-repository indexed search.
* Replacing CodeEditSourceEditor internals.
* Full arbitrary large-file editing with rope/piece-tree undo/redo.
* Full-file parsing/formatting of huge JSON/YAML/TOML/XML/CSV.

## Technical Notes

* Relevant files: `ConductorShellCommand.swift`, `ConductorWindowModel.swift`, `ConductorRootView.swift`, `ConductorFileWorkspaceView.swift`, `ConductorMarkdownWorkspaceView.swift`, `FileManagerPanel.swift`.
* Large-file implementation should add a separate path, likely `LargeFileWorkspaceView.swift`, `LargeFileTextHostView.swift`, `LargeFileBuffer.swift`, `LargeFileIndexWorker.swift`, and `LargeFileFormatProfile.swift`.
* Use AppKit for the document content layer; SwiftUI remains the shell/toolbar layer.
