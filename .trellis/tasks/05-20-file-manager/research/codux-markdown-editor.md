# Codux Markdown/File Editor Review

## Scope

Reviewed the Codux file and Markdown editing path in `/tmp/codux-research` after repeated selection issues in Conductor's Markdown source editor.

## Files Reviewed

- `Sources/DmuxWorkspace/Services/ProjectFileBrowserService.swift`
- `Sources/DmuxWorkspace/UI/FileBrowser/FileBrowserPanelView.swift`
- `Sources/DmuxWorkspace/UI/Workspace/WorkspaceFileEditorView.swift`
- `Sources/DmuxWorkspace/UI/Workspace/NativeSourceEditorTextPreview.swift`
- `Sources/DmuxWorkspace/UI/FileBrowser/ProjectFileEditorTheme.swift`
- `Sources/DmuxWorkspace/Models/ProjectFileModels.swift`
- `Tests/DmuxWorkspaceTests/ProjectFileBrowserServiceTests.swift`
- `Packages/CodeEditTextView/Sources/CodeEditTextView/TextSelectionManager/TextSelectionManager+FillRects.swift`
- `Packages/CodeEditTextView/Sources/CodeEditTextView/TextLayoutManager/TextLayoutManager+Public.swift`

## Findings

- Codux does not implement a dedicated Markdown file editor. `.md` files are read as text by `ProjectFileBrowserService.preview(...)` and edited through the same source editor path as other text/code files.
- Codux uses `NativeSourceEditorTextPreview` as the stable source editor wrapper. It keeps a persistent `SourceEditorState`, a coordinator object, and explicit tokens for focus/render/copy/paste/undo/redo/find/snapshot/save.
- Codux's `CodeEditTextView` package is unmodified in the selection files compared with the vendored source in Conductor before local patches. The repeated selection fixes in Conductor were drifting away from Codux instead of matching it.
- Codux's file browser service has tests for `.md` text saving and file operation safety. Markdown is treated as editable source text; Markdown rendering is not part of Codux's file editor surface.
- The correct Conductor direction is to keep vendored CodeEdit packages aligned with Codux/CodeEdit behavior and put Conductor-specific Markdown features around a stable source editor wrapper, not inside the package's low-level selection rendering.

## Applied Direction

- Reverted Conductor's local `CodeEditTextView` selection hit-test/fill-rect patches so the vendored CodeEditTextView selection behavior matches Codux again.
- Changed Conductor's source editor wrapper to keep a persistent `SourceEditorState` instead of passing `.constant(SourceEditorState())`, matching Codux's stability pattern.

## Follow-Up

- If Markdown source editing still diverges, the next change should extract a Conductor-native equivalent of Codux's `NativeSourceEditorTextPreview` wrapper and use it for both normal text files and the Markdown source pane.
- Keep Conductor's Markdown preview/outline/search as additive UI around the shared source editor, not as a replacement for the editor surface.
