# Project Performance And Interaction Audit

Date: 2026-05-22

Scope: every file under `Apps/Conductor/Sources` was included in the coverage matrix. Third-party document viewer assets are marked vendor bounded: reviewed for how Conductor loads and embeds them, not for internal library correctness.

## Executive Summary

The terminal rendering direction is sound: live terminal cells, scrollback, cursor movement, and Ghostty output do not enter SwiftUI state. Most remaining jank risk is in the shell around it:

- One large `ConductorWindowModel` publishes unrelated concerns through one `ObservableObject`, so small changes can invalidate the root shell, split panes, toolbars, tabs, settings, and file workspace together.
- File manager and workspace file flows still build full row/search snapshots in SwiftUI-visible state before rendering. `LazyVStack` delays view construction, but it does not prevent full tree flattening, filtering, or per-selection recomputation.
- Document preview recreates or reloads WebView content too aggressively, and every document HTML build inlines all vendor scripts, including large libraries not needed for the current file kind.
- Focus and cursor ownership is split across terminal host, hidden keyboard bridges, SwiftUI `FocusState`, AppKit text fields, and panel overlays. Recent fixes improved this, but there is still no central focus policy, which explains caret flicker and occasional surprise focus steals.
- Motion primitives exist, but transitions are not driven by a single compositor strategy. Some panels use AppKit/CALayer, some use SwiftUI transitions, some use selection scale/shadow. The result can feel like separate layers moving instead of one object.
- Several UI controls advertise actions only through hover tooltips or tiny icons. The app is powerful, but discoverability and confidence are uneven, especially for file operations, search scope, split resizing, protected readers, and external-change handling.

## Findings

### P1: Root ObservableObject Invalidation Is Too Broad

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- `ConductorWindowModel` exposes `@Published` for workspace, all workspaces, appearance, theme, terminal metadata, notifications, panel visibility, file tabs, search generations, drag/drop state, and file-manager focus/search tokens.
- `ConductorRootView`, `SplitNodeView`, settings, overview, command palette, file workspace, and terminal pane views all observe the whole model.
- Metadata publishing is coalesced, but it still publishes a full `[TerminalID: TerminalDisplayMetadata]` dictionary and can invalidate unrelated UI surfaces.

Impact:

- A terminal title, search count, unread badge, file dirty flag, settings tweak, or panel token can rebuild wide portions of the SwiftUI shell.
- Live resize and split dragging feel worse because SwiftUI body work competes with AppKit split layout and Ghostty geometry sync.

Fix direction:

- Split the model into smaller observable snapshots: `ShellChromeStore`, `WorkspaceLayoutStore`, `TerminalMetadataStore`, `FileWorkspaceStore`, `PanelStore`, `SettingsStore`.
- Pass value snapshots into rows/tab buttons/settings instead of the whole model.
- Keep `ConductorWindowModel` as command router/coordinator, but reduce `@ObservedObject` usage at leaf views.

### P1: File Manager Needs Real Virtualization, Not Just LazyVStack

Files:

- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- `displaySnapshot` recursively calls `knownRows` and `visibleRows`, filters all rows, and computes counts on every body pass.
- `displayedRows`, `displayedFileCount`, `displayedDirectoryCount`, and range selection also recompute flattened rows.
- The tree uses SwiftUI `ScrollView` + `LazyVStack`; that lazy-loads row views, but the data model still materializes the whole visible/known tree.
- Selection, hover, delete marking, rename, sort/filter/search, preview state, and loading state all live in one `FileManagerPanelStore` with many `@Published` fields.

Impact:

- Large directories or expanded trees can stutter on hover, selection, keyboard navigation, and search.
- Dragging split width while file manager is mounted still competes with row flattening and row diffing.

Fix direction:

- Introduce an AppKit-backed `NSOutlineView` or a fixed-row-height virtual list (`NSScrollView` + custom row host/reuse).
- Cache a `FileManagerDisplaySnapshot` and update it only when tree/search/filter/sort inputs change, not on every view body read.
- Split preview state from tree state so preview loading does not invalidate the row list.
- Keep row height stable and derive visible index range from scroll offset for SwiftUI fallback.

### P1: Document WebView Reloads And Vendor Inlining Are Too Expensive

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorDocumentWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/*.js`
- `Apps/Conductor/Sources/Conductor/Resources/DocumentViewer/vendor/katex.min.css`

Evidence:

- `ConductorDocumentWorkspaceView` applies `.id("\(payload.renderID)|\(layoutRevision)|\(theme.rawValue)|\(fontSize)")`, which can recreate the representable and WKWebView for layout/theme/font changes.
- HTML generation inlines every vendor script for every document kind: markdown, sanitizer, highlight, PapaParse, Mermaid, KaTeX, PDF.js, Mammoth, XLSX.
- `vendorScriptBase64("pdf.worker.min")` is rebuilt from the script string when generating HTML.
- `readBinaryBase64` embeds up to 80 MB into the WebView payload for PDF/Word/spreadsheet.

Impact:

- Markdown preview and file preview feel heavy even for small documents.
- Split resizing or layout revision can reload WebView content when the desired behavior is only relayout/search.
- Large documents duplicate memory across Swift payload, base64 string, HTML string, and WebKit process.

Fix direction:

- Remove `layoutRevision` from `.id`; keep WKWebView stable and call JavaScript relayout/search APIs.
- Cache vendor script/style strings once per process.
- Build document-kind-specific HTML bundles so markdown does not load XLSX/Mammoth/PDF/Mermaid unless needed.
- For large binary documents, prefer file URL/native QuickLook or streaming PDF viewer rather than base64 embedding.

### P1: Workspace File Editor Keeps Hidden Editors Mounted

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`

Evidence:

- `ForEach(model.workspaceFileTabs)` creates a `ConductorWorkspaceFileEditorView` for every opened file and hides inactive ones with `opacity`.
- Each editor can own text state, autosave task, search task, external watch task, Markdown preview task, and WebView preview state.
- Hidden editors still observe model token changes and can keep periodic external-change polling alive.

Impact:

- Opening several files multiplies memory and background tasks.
- A large hidden file can still affect app responsiveness while the user is interacting with terminal or another file.

Fix direction:

- Mount only the selected editor view. Keep inactive file tab state in a lightweight document cache/service.
- Suspend external watchers and preview WebViews for inactive tabs.
- Use explicit save/dirty state objects per file instead of hidden full view trees.

### P1: Search Focus Has Multiple Owners

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorContextSearchControls.swift`
- `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurfaceRepresentable.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorKeyboardShortcutBridge.swift`

Evidence:

- Search fields focus through AppKit `makeFirstResponder` and delayed dispatch.
- Command palette/workspace overview use SwiftUI `FocusState`.
- Terminal container also restores focus after geometry sync and view movement.
- Hidden keyboard bridges can request first responder when autofocus is true.

Impact:

- Caret can flash then disappear when a terminal or hidden bridge restores first responder.
- Search feel changes depending on whether the current surface is terminal, file workspace, document preview, or file manager.

Fix direction:

- Add a central `FocusCoordinator` with explicit focus domains: terminal, terminal search, file search, file manager tree, rename field, palette, settings, native preview.
- Terminal focus restoration should ask the coordinator whether the terminal domain owns focus before calling `makeFirstResponder`.
- Replace token-only focus with domain + generation + owner.

### P1: Motion Is Not A Single Presentation Layer

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorDesign.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- File manager tray uses CALayer transform animation.
- Command/settings/overview use SwiftUI transitions.
- Rows and tabs use hover scale/shadow/matched geometry.
- Split panes disable animation in some transactions while descendants still have hover/selection animations.

Impact:

- A panel can visually slide independently while its internal content, shadow, and terminal underneath update on different schedules.
- Motion may feel like two surfaces moving rather than one coherent sheet.

Fix direction:

- Create a compositor policy: all large overlay panels should be hosted in AppKit/CALayer with stable SwiftUI content snapshots during enter/exit.
- Freeze or snapshot expensive descendants during panel reveal and live resize.
- Reserve SwiftUI animations for local feedback only, not broad layout or large panel presentation.

### P1: Settings Panel Still Has Heavy Subtree Cost

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- `Apps/Conductor/Sources/Conductor/Shared/TerminalGhosttyConfigCatalog.swift`
- `Apps/Conductor/Sources/Conductor/Shared/TerminalFontLibrary.swift`
- `Apps/Conductor/Sources/Conductor/Shared/TerminalFontAvailability.swift`

Evidence:

- Settings is improved with snapshot/equatable and lazy stacks, but `AppearanceSettingsPanel` still receives the whole model and many rows read `model.appearance`.
- Ghostty config search filters product groups from the catalog during body reads.
- Font choices can query installed candidate names through `TerminalFontLibrary.choices`.

Impact:

- Settings scroll and search can still hitch, especially when typing in config search or toggling terminal renderer options.
- The panel can invalidate on unrelated model changes because it holds the coordinator model directly.

Fix direction:

- Move settings into a dedicated `SettingsViewModel` snapshot with row-level bindings/actions.
- Cache Ghostty filtered groups by normalized query.
- Precompute font availability and update it only after explicit refresh/download/import.

### P2: Terminal Geometry Sync Has Redundant Paths

Files:

- `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurfaceRepresentable.swift`
- `Apps/Conductor/Sources/Conductor/Terminal/TerminalHostView.swift`
- `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift`

Evidence:

- Container syncs frame in `layout`, `setFrameSize`, `setBoundsSize`, post-layout task, and window attach.
- Host view also syncs geometry in `layout`, `setFrameSize`, `setBoundsSize`, backing changes, and move-to-window.
- Split coordinator calls `layoutSubtreeIfNeeded()` while programmatically syncing divider position.

Impact:

- During live resize, the same surface can receive several geometry checks in one visual frame.
- Even if idempotent, repeated AppKit/Ghostty calls can reduce frame budget.

Fix direction:

- Make one owner responsible for terminal geometry sync.
- Coalesce geometry into display-link/next-runloop batches keyed by terminal ID.
- Add counters/signposts for sync calls per second during split drag and window resize.

### P2: Terminal Input Retained CString Buffer Can Grow Large

Files:

- `Apps/Conductor/Sources/Conductor/Terminal/TerminalSurface.swift`

Evidence:

- Text/key/binding strings are retained until pruned.
- Limit is 4096 retained strings or 8 MB retained input bytes.

Impact:

- Large paste or many command/search binding actions can temporarily retain more memory than expected.

Fix direction:

- Verify Ghostty ownership semantics and free immediately when safe.
- Lower retained byte limits for normal text input; use separate short-lived path for binding actions.

### P2: Image Loading Caches Full NSImage Without Cost Limit

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorAsyncImage.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorImageWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- `NSCache` has no count/cost limit.
- Full file data is read before `NSImage(data:)`.
- File manager image preview and image workspace share this cache.

Impact:

- Previewing several large images can increase memory sharply.
- A large image decode can still affect responsiveness after the disk read completes.

Fix direction:

- Set `NSCache.totalCostLimit` and cost by pixel count/byte count.
- Add maximum preview pixel area or downsample for file-manager previews.
- Keep full-resolution image workspace separate from thumbnail/preview cache.

### P2: Command Palette And Overview Recompute Full Search Inputs

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`

Evidence:

- Command palette rebuilds command arrays and filters strings in computed properties.
- Workspace overview filters workspaces by joining titles/directories from all panes on each body/search update.

Impact:

- Typing in palette/overview can hitch as workspace count and metadata grow.

Fix direction:

- Cache searchable strings and command catalog snapshots.
- Use debounced search for large workspace sets.
- Keep hover highlight updates local instead of invalidating the whole grid.

### P2: Notification State Rebuilds Full Snapshot On Each Change

Files:

- `Apps/Conductor/Sources/ConductorCore/Workspace/TerminalNotificationModel.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`

Evidence:

- Notification state stores records plus derived maps/snapshot.
- Mark/clear/add operations refresh the whole snapshot.

Impact:

- Fine for small counts, but command-finish/bell-heavy workflows can make notification updates expensive and broad because `notifications` is one published value.

Fix direction:

- Bound notification records.
- Incrementally maintain counts and latest maps.
- Publish separate unread badge snapshot from visible notification list.

### P2: File And Document Search Duplicate Work

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorDocumentWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- Source editor search scans Swift strings in detached tasks.
- Markdown/document preview search runs in WebView JavaScript.
- File manager search filters flattened rows.

Impact:

- Same visible action, different performance/selection behavior per mode.
- Large Markdown/log files fall back to document search status in some branches but source selection is disabled, making feedback inconsistent.

Fix direction:

- Define one search contract: query, scope, match count, selected match, navigation, highlight.
- Provide per-surface implementations but identical toolbar behavior and status lifecycle.

### P2: Hidden Keyboard Shortcut Bridges Can Steal First Responder

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorKeyboardShortcutBridge.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorImageWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorNativePreviewWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- The bridge is an invisible NSView and may autofocus.
- Multiple surfaces mount their own bridge.

Impact:

- Shortcuts work, but invisible first-responder views make cursor/caret behavior harder to reason about.

Fix direction:

- Route workspace-level shortcuts through the window and focus coordinator.
- Use invisible bridge only for isolated AppKit surfaces that cannot otherwise expose key handling.

### P2: App Startup And Test Automation Are Mixed In One Delegate

Files:

- `Apps/Conductor/Sources/Conductor/App/ConductorApp.swift`

Evidence:

- `ConductorAppDelegate` owns launch, menus, window, notifications, focus, hook observers, many smoke/stress automation paths, and test output writers.

Impact:

- Runtime code is harder to audit and optimize because test-only timers and command paths live alongside real UI setup.

Fix direction:

- Extract automation runners behind debug/test-only types.
- Keep app delegate focused on lifecycle/window/menu/focus.

### P2: Persistence Runs On Main Actor

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorWindowModel.swift`
- `Apps/Conductor/Sources/Conductor/Shared/WorkspacePersistence.swift`

Evidence:

- Persistence is debounced in the model, but JSON encoding and atomic write happen through `WorkspacePersistence.save`.
- Persistence load is synchronous during model init.

Impact:

- State writes are likely small today, but more workspaces/tabs/metadata can make save/load visible at launch or after rapid workspace edits.

Fix direction:

- Move encode/write to a utility actor or background task with immutable snapshot input.
- Keep launch load small and validate/correct state off the critical first-render path when possible.

### P2: QuickLook And WebView Resize Freezing Helps But Needs Unified Live-Resize Policy

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorNativePreviewWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorDocumentWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`

Evidence:

- Native preview freezes resizing with cover layers.
- WebView applies deferred frame/reload commits.
- Source text scroll view changes redraw policy during live resize.

Impact:

- Good local mitigations, but each surface implements its own behavior, so mixed document/source/terminal layouts can still feel inconsistent.

Fix direction:

- Introduce a shared `LiveResizeCoordinator` environment flag and per-surface freeze/resume protocol.
- During active split/window resize, freeze expensive preview surfaces and keep terminal geometry coalesced.

### P3: Cursor Affordance Is Better But Still Incomplete

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorDesign.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`

Evidence:

- Source read-only/protected text now uses arrow cursor.
- Split divider sets resize cursors.
- Many SwiftUI buttons rely on default cursor and custom tooltip overlays.

Impact:

- Clickable regions do not always communicate clickability. Some plain icon buttons look like static chrome until hover.

Fix direction:

- Add a reusable AppKit cursor modifier for clickable SwiftUI controls.
- Use pointing-hand cursor for buttons, resize cursor only on split handles, I-beam only on editable text.

### P3: Discoverability Needs More Persistent State Cues

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`

Evidence:

- File manager has many icon-only actions.
- Protected reader state is expressed in status/message but not consistently in tab/chrome.
- Search scope changes across terminal/file/Markdown/file-manager.

Impact:

- Users can do the work, but they need to remember modes and icon meanings.

Fix direction:

- Add compact persistent labels for mode/scope when ambiguous.
- Prefer segmented controls for source/preview/split and scope chips for every search.
- Keep destructive actions visually separated from navigation/actions.

## Recommended Fix Batches

1. State isolation and virtualization:
   - Split `ConductorWindowModel` observation surfaces.
   - Introduce virtualized file tree rows.
   - Mount only selected file editor.

2. Document and preview performance:
   - Stabilize WKWebView identity.
   - Cache and conditionally load vendor assets.
   - Avoid base64 embedding large documents by default.

3. Focus and cursor policy:
   - Add `FocusCoordinator`.
   - Move search focus, terminal focus restore, rename focus, and hidden shortcut bridges under one owner.
   - Add cursor roles for editable, selectable, clickable, resize, inert.

4. Motion and live resize:
   - Standardize large-panel compositor hosting.
   - Freeze expensive descendants during panel reveal/live resize.
   - Coalesce terminal geometry sync by frame.

5. Instrumentation:
   - Add signposts/counters for SwiftUI body hotspots, file snapshot computation, WebView reloads, geometry syncs, and focus owner changes.
   - Keep `ConductorMainThreadWatchdog`, but add workflow-level labels so stalls point to the responsible surface.

## Verification Plan

- Static checks: `swift build`, `swift run ConductorModelCheck`.
- Profiling workflows:
  - Two split terminals, open/close file manager 20 times.
  - Expand a directory with 5k+ known rows, search/filter, multi-select, rename.
  - Open Markdown in source/preview/split, resize horizontally while typing.
  - Open log > 1.5 MB and resize app window.
  - Open settings, search Ghostty config, switch sections rapidly.
  - Open command palette and workspace overview with 20+ workspaces.
  - Drag split divider with terminal + WebView/native preview/file manager visible.
- Human feel checks:
  - Pointer shape matches target role.
  - Search caret remains visible after focus.
  - Tooltip disappears on mouse leave/scroll/click.
  - Large overlays move as one layer.
  - No terminal focus refresh when interacting with search or file panels.
