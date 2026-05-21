# Swift Document Reading Performance Audit

Date: 2026-05-21

## Scope

This audit reviews Conductor's current file/document reading path against project specs and official Swift/Apple performance guidance. The focus areas are:

- Opening files from the workspace editor and file manager
- Markdown parsing, preview rendering, image blocks, and search
- Large text mode and native preview surfaces
- SwiftUI invalidation risks around document views
- Usability issues that make document reading feel slow or awkward

## Official Guidance Used

- Apple Developer: Understanding and Improving SwiftUI Performance
- Apple Developer: Improving app responsiveness
- Apple Developer: Analyzing hangs with Instruments
- Swift.org: The Swift Programming Language, Concurrency

## Findings

### P1: Workspace file open can block the main thread

`WorkspaceFileService.document(for:)` performs `Data(contentsOf:)` synchronously after metadata checks. It is called from `ConductorWorkspaceFileEditorView.init` and from `reload()`, both on the SwiftUI/main-actor interaction path.

Impact:

- Opening or reloading a file up to the current editable cap can freeze the app.
- Unknown text-like files can be read fully before the large-text path is chosen.
- This conflicts with the project rule that file/document IO must run off the main actor.

Recommendation:

- Replace synchronous init loading with a `@StateObject` loader and `.task(id:)`.
- Move resource checks and bounded reads into `Task.detached` or an actor.
- Show a loading state while preserving the previous editor surface until the new document is ready.

### P1: Markdown reparses synchronously on every text change

`ConductorMarkdownWorkspaceView` calls `ConductorMarkdownParser.parse(text)` directly inside `.onChange(of: text)`.

Impact:

- Typing in Markdown files near the 192 KB / 2,500 line limit can jank.
- Preview, outline, search, and source editing are coupled to the same synchronous parse.

Recommendation:

- Debounce parsing and run it off the main actor.
- Keep source typing independent from preview parse completion.
- Parse only for preview/split mode or when outline/search needs parsed blocks.

### P1: Markdown image blocks decode images in SwiftUI body

Markdown image rendering calls `NSImage(contentsOf:)` inside `markdownImage(...)`.

Impact:

- SwiftUI body recomputation can repeatedly decode local images on the main thread.
- A Markdown file with several images can stutter during scroll, edit, theme changes, or search updates.

Recommendation:

- Introduce an async image cache keyed by URL + file modification signature.
- Render placeholder/progress/error states from cached compact state.

### P1: External diff summary reads and compares disk content from body

When `externalDiffVisible` is true, the view builds `Text(externalDiffSummary())`. That function synchronously reads disk text and computes a line diff.

Impact:

- Any body invalidation can redo disk IO and diff work.
- The work is tied to rendering, not to the user's explicit “show diff” action.

Recommendation:

- Compute diff once when the user expands it.
- Store a cached diff state with loading/error/skipped states.
- Recompute only when file signature or text generation changes.

### P2: Plain text search runs synchronously on every edit while search is active

The editor refreshes all search matches on every text change and query change. The scan itself is synchronous and accumulates every match.

Impact:

- Large but still editable files can lag while typing with search open.
- Match arrays can grow large for common terms.

Recommendation:

- Debounce search while typing.
- Run search off-main for larger documents.
- Cap match count and surface a "showing first N" status.

### P2: File manager image preview decodes images inside body

The side file manager's `.image` preview path also calls `NSImage(contentsOf:)` directly in the SwiftUI body.

Impact:

- Selecting an image in the file manager can redo image decode during unrelated model updates.
- This is inconsistent with the workspace image viewer and should share one image loading path.

Recommendation:

- Reuse the async image cache for both Markdown and file manager previews.

### P2: Broad model observation can invalidate document readers

Document views and the file manager receive `@ObservedObject var model: ConductorWindowModel`.

Impact:

- Terminal metadata, workspace badge changes, or unrelated shell updates can invalidate heavy document views.
- This conflicts with the spec guidance to pass compact values/callbacks into leaf views.

Recommendation:

- Pass only callbacks and compact values into file/markdown preview leaves.
- Keep `ConductorWindowModel` observation near the shell/root layer.

### P2: Markdown opens source-only by default

`effectiveMode(for:)` defaults to `.source` even when opening `.md` from file navigation.

Impact:

- A "read document" action lands users in code-edit mode, not reading mode.
- The preview system exists but is hidden until the user discovers the segmented control.

Recommendation:

- Add an open intent: edit vs read.
- Default file-manager/terminal-opened Markdown to preview or split on wide windows.
- Remember the last Markdown mode per user preference.

### P3: Markdown table rendering is not tuned for wide tables

Markdown tables render every row/cell in nested SwiftUI stacks and stretch cells equally.

Impact:

- Wide tables become hard to read.
- Large tables can increase SwiftUI view count quickly.

Recommendation:

- Add horizontal scrolling and row limits.
- For bigger tables, route to large/structured preview with virtualization.

## Positive Notes

- Large text mode already uses an AppKit canvas, visible-rect invalidation, background indexing, capped drawn characters, and bounded search. This is the right direction for huge files.
- Native preview uses `QLPreviewView` and deduplicates `updateNSView` by URL, which fits the AppKit-stable-surface rule.
- File manager directory listing and text preview are already dispatched off the main actor; the main remaining issue is body-time image decode and computed row filtering at scale.

## Recommended Fix Order

1. Async workspace file loader and reload path.
2. Async/cached Markdown parse and search.
3. Shared async image cache for Markdown, file manager, and image workspace.
4. Cached external diff state.
5. Narrow `ConductorWindowModel` observation in document leaves.
6. Markdown read-mode defaults and table reading polish.
