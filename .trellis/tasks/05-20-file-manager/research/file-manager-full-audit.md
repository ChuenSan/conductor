# File Manager Full Audit

## Scope

Audited Conductor's file manager/editor against Codux after repeated bugs around Markdown selection and file content persistence.

## Codux Files Read

- `Sources/DmuxWorkspace/Services/ProjectFileBrowserService.swift`
- `Sources/DmuxWorkspace/UI/FileBrowser/FileBrowserPanelView.swift`
- `Sources/DmuxWorkspace/UI/Workspace/WorkspaceFileEditorView.swift`
- `Sources/DmuxWorkspace/UI/Workspace/NativeSourceEditorTextPreview.swift`
- `Sources/DmuxWorkspace/App/AppModel+WorkspaceFiles.swift`
- `Sources/DmuxWorkspace/Models/ProjectFileModels.swift`
- `Tests/DmuxWorkspaceTests/ProjectFileBrowserServiceTests.swift`

## Codux Behavior Contracts

- Directory rows are flattened from a root item plus `childrenByPath`, with inline expand/collapse.
- Hidden directories are kept; rows sort folders first with localized standard compare.
- Rename validates non-empty names, rejects `/`, rejects existing destination, and reloads parent state after success.
- Copy/move share one transfer path with conflict resolution and move-into-self protection.
- Delete is staged first, then moved to Trash via `NSWorkspace.recycle` callback, and UI refreshes only after the callback succeeds.
- Workspace file save uses a snapshot token: toolbar/model asks the editor for current `TextViewController` text, then saves that exact snapshot.
- Saving validates the file is inside the project root and rejects directories.
- Large/binary text handling is explicit: binary files are not edited; large files get a read-only virtual preview.

## Conductor Gaps Found

- Save previously used only the SwiftUI text binding. If the editor binding and AppKit text view diverged, the UI could show deleted content while saving the old content.
- Save did not validate that the target file belonged to the workspace root.
- Save ran synchronously on the main actor.
- The workspace editor has no dirty-tab model or close-confirm flow yet, unlike Codux.
- The file panel has unused preview UI paths; current behavior opens files in workspace tabs rather than showing the preview pane.
- File-manager keyboard shortcuts and drag/drop payload handling are thinner than Codux.
- File deletion does not close already-open file tabs for deleted files.

## Fixes Applied In This Pass

- Added a snapshot-token save path to `ConductorCodeEditSourceEditor`.
- Threaded snapshot save through `ConductorMarkdownWorkspaceView` so Markdown source saves from the live editor text.
- Changed workspace save to validate root containment and reject directories.
- Moved save IO to a detached task for normal save/autosave.
- Kept the previous autosave behavior, but it now snapshots from the live editor instead of using only stale view state.

## Remaining Follow-Up

- Add dirty-file tracking to `ConductorWindowModel` so file tabs show unsaved state and close can save/discard/cancel.
- Add file-manager keyboard handler for copy/cut/paste/rename/delete parity with Codux.
- Decide whether the right-side file manager should keep only the tree or revive inline preview; currently preview code is mostly unused.
- Close or invalidate workspace file tabs when their underlying file is moved to Trash or renamed.
