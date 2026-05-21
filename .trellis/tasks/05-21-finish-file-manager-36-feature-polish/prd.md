# Finish File Manager 36 Feature Polish

## Goal

Bring the file manager and file workspace from "usable and merged" to a true 36/36 completion bar. The user explicitly wants every listed feature to be full-score; partial implementations should be closed, not described away.

## What I already know

* The file manager work is already merged to `main`.
* The app currently supports file manager entry, inline tree navigation, workspace file tabs, Markdown/source/image/large text views, search history, batch selection, safe delete, delete undo, sorting, favorites, recent files, hidden-file toggle, and many file operations.
* Remaining weak spots identified by direct PRD-to-code review:
  * JSON/YAML/TOML support is not yet a proper structured tree experience.
  * External file change detection exists, but compare/keep/reload conflict handling is thin.
  * Drag/drop supports file rows and folder drops, but terminal path insertion by drop needs explicit support.
  * Keyboard operations cover basics, but need a more complete file-tree command matrix.
  * File status markers exist for some states, but not all states promised in the 36-item design.
  * Terminal collaboration has insert path; `cd` and safe command insertion are missing.
  * Large file mode is high-performance and searchable, but controlled bounded editing is not implemented.
  * Get Info and Copy As exist; they need to be checked and filled out to match the spec.

## Requirements

* Complete the remaining gaps against the original 36-feature design without regressing terminal performance.
* Keep high-frequency terminal output out of SwiftUI state.
* Keep destructive file actions explicit and reversible where possible.
* Use AppKit-backed views for large/complex text operations where SwiftUI would be too slow.
* Preserve the current UI direction: compact, native-feeling, no bulky card shell.

## Acceptance Criteria

* [ ] Structured `.json`, `.jsonl`, `.yaml`, `.yml`, `.toml`, and `.plist` files show a tree/key-path oriented view when parseable, with copy key/path/value actions and parse errors when invalid.
* [ ] External file changes show visible conflict choices: reload from disk, keep current buffer, and view a lightweight diff/summary before saving over disk changes.
* [ ] Dragging a file/folder row onto the terminal inserts a shell-escaped path; terminal context actions include insert path, `cd` to directory, and safe command insertion without blind execution.
* [ ] File-tree keyboard commands cover arrows expand/collapse, Enter open, Space preview/open, Cmd-R refresh, Cmd-Backspace delete, Cmd-N new file, Cmd-Shift-N new folder, Cmd-C/X/V copy/cut/paste, and do not steal editor/search/rename shortcuts.
* [ ] File status badges cover dirty tab, deleted/missing, external changed, read-only/no-read, large/protected, binary/unsupported, symlink, and have tooltips.
* [ ] Get Info exposes type, kind, size, created/modified dates, permissions, full path, parent path, and copy actions.
* [ ] Quick Copy exposes name, absolute path, relative path, parent path, shell-escaped path, and terminal-ready quoted path.
* [ ] Large file mode supports bounded small-region editing or explicitly available safe append/replace-current-line flows, with no unsafe whole-file rewrite of unindexed regions.
* [ ] `swift build`, `swift run ConductorModelCheck`, and the Conductor check script pass from the main worktree.

## Out of Scope

* Whole-repository indexed search.
* Git status integration.
* Full arbitrary rope/piece-table large-file editor.
* Sudo/chmod escalation UI.
* Executing destructive terminal commands automatically.

## Technical Notes

* Main files likely involved:
  * `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorLargeTextWorkspaceView.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
  * `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
* Existing task references:
  * `.trellis/tasks/05-20-file-manager/prd.md`
  * `.trellis/tasks/05-20-file-manager-preview-and-search-polish/prd.md`
