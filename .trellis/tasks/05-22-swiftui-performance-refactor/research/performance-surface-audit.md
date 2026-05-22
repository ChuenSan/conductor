# Performance Surface Audit

## Scope

First-pass scan of Conductor's SwiftUI/AppKit/WebKit/Ghostty surfaces using the locally loaded SwiftUI Expert and SwiftUI Pro skills plus project Trellis specs.

This is an audit, not an implementation patch. It identifies refactor surfaces where better structure and better performance should be addressed together.

## Quantitative Snapshot

- Swift files under `Apps/Conductor/Sources/Conductor`: 33
- Total Swift lines under app target: about 29.9k
- Largest files:
  - `UI/ConductorRootView.swift`: about 7.2k lines
  - `UI/FileManagerPanel.swift`: about 3.7k lines
  - `UI/ConductorWindowModel.swift`: about 2.7k lines
  - `UI/ConductorDocumentWorkspaceView.swift`: about 2.0k lines
  - `UI/SplitNodeView.swift`: about 1.7k lines
  - `App/ConductorApp.swift`: about 1.7k lines
- `@Published` occurrences in app target: 64
- Direct `@ObservedObject var model: ConductorWindowModel` subscriptions: 16
- `some View` computed properties/functions: 117
- `.animation(...)` occurrences: 54
- `.transition(...)` occurrences: 18
- `matchedGeometryEffect` occurrences: 5
- `AnyView` occurrences: 4

## Positive Existing Patterns To Preserve

### Stable terminal host bridge

`TerminalSurfaceRepresentable` uses a stable `NSViewRepresentable` container, stores the current `TerminalSurface`, deduplicates frame/bounds writes, and schedules geometry sync rather than doing unconditional expensive work in every SwiftUI update.

Keep this pattern. It matches the project rule that terminal rendering, scrollback, cursor state, and high-frequency output stay outside SwiftUI.

### AppKit/Core Animation tray reveal

`FileManagerCompositorSlideHost` uses an AppKit host and layer transform for the file manager tray instead of changing terminal split layout width. This follows the project spec direction for right-side tool trays.

Keep this approach, but narrow the SwiftUI data passed into the tray content.

### WebKit document renderer signature

`ConductorDocumentWebView.updateNSView` computes a signature and only calls `loadHTMLString` when payload/theme/chrome identity changes. Search updates are bridged separately.

Keep this "signature-gated AppKit/WebKit update" pattern and apply it more broadly.

## P0 Findings

### 1. `ConductorWindowModel` is a broad invalidation hub

Evidence:

- `ConductorWindowModel` publishes workspace, workspaces, theme, appearance, metadata, notifications, panel visibility, search tokens, file tabs, drag/drop state, and more from one `ObservableObject`.
- Many views observe the whole object directly, including root, notification panels, sidebars, toolbars, split nodes, file workspace views, and file manager adjacent views.

Why it matters:

With `ObservableObject`, any `@Published` change can invalidate every observing view. This is dangerous for a terminal shell because metadata, panel state, drag state, file tab state, notifications, and workspace layout should not all redraw the same large trees.

Recommended structure:

- Introduce compact, `Equatable` display snapshots for hot UI surfaces:
  - `RootShellSnapshot`
  - `WorkspaceChromeSnapshot`
  - `SidebarSnapshot`
  - `NotificationPanelSnapshot`
  - `TerminalPaneChromeSnapshot`
  - `WorkspaceFileChromeSnapshot`
- Leaf views should receive snapshots and callbacks, not the whole `ConductorWindowModel`.
- Keep `ConductorWindowModel` as the command coordinator initially; do not split it into many objects in the first patch.
- Longer term: split model ownership into feature stores/coordinators only after snapshots reduce fan-out.

Best first patch:

Create a small snapshot for one hot surface, likely workspace/sidebar chrome, and convert the row/list views to `Equatable` value inputs.

### 2. `ConductorRootView.swift` combines too many product surfaces

Evidence:

- The file contains root shell, file tray host, command palette, settings, workspace overview, notification panel, sidebar, workspace toolbar, preview mockups, and many row/control types.
- It has many computed `some View` properties and functions. SwiftUI Expert and SwiftUI Pro both prefer extracting complex sections into dedicated `View` structs because computed subviews re-execute with parent body updates.

Why it matters:

This makes review hard and increases the chance that root-level state changes re-enter large panel/list builders. It also obscures ownership: shell, panels, navigation, settings, notifications, and workspace chrome should not evolve in one file.

Recommended structure:

- Move by feature, preserving behavior:
  - `Root/ConductorRootView.swift`
  - `Root/FileManagerTrayHost.swift`
  - `CommandCenter/CommandPaletteView.swift`
  - `Settings/AppearanceSettingsPanel.swift`
  - `Settings/SettingsRows.swift`
  - `WorkspaceOverview/WorkspaceOverviewPanel.swift`
  - `Notifications/NotificationPanelView.swift`
  - `Sidebar/ConductorSidebar.swift`
  - `Toolbar/ConductorToolbar.swift`
- During extraction, replace computed subviews that have state, loops, or branching with dedicated structs.

Best first patch:

Extract one self-contained surface, not the whole file. The best candidates are Notification Panel or Workspace Overview because they have clear inputs and limited behavior.

### 3. File manager display snapshot is still main-actor recursive work

Evidence:

- `FileManagerPanelStore.displaySnapshot` recursively computes known/visible rows, filters search, counts files/directories, and caches the result.
- The cache is useful, but it is owned by the `ObservableObject` and accessed directly from `FileManagerPanel.body`.
- Many unrelated `@Published` properties in the same store can still invalidate the whole panel.

Why it matters:

Large directory trees can make body-triggered snapshot access expensive. The current shape is better than recomputing in every subview, but still mixes model mutation, snapshot derivation, selection, preview loading, operation messages, search, and rendering state.

Recommended structure:

- Extract a pure `FileManagerDisplaySnapshotBuilder`.
- Publish a single `@Published private(set) var displaySnapshot` from the store after invalidating inputs, instead of computing it from `body`.
- Consider building snapshots off the main actor for large trees, then publish one immutable result.
- Split store state into:
  - tree inputs
  - selection/search inputs
  - operation/banner state
  - preview state
- Leaf row views should receive `FileManagerRowDisplayModel` values, not the store.

Best first patch:

Move snapshot building into a standalone pure type and make `FileManagerPanel.body` read a stored snapshot value.

## P1 Findings

### 4. File preview bulk rendering still uses SwiftUI rows/cells

Evidence:

- `FileManagerSourcePreview` renders lines with `LazyVStack` and `ForEach(Array(document.lines.enumerated()), id: \.offset)`.
- `FileManagerTablePreview` renders rows and then each column with nested `ForEach`.
- Key/value and structured previews also render repeated SwiftUI rows.

Why it matters:

`LazyVStack` helps initial creation, but SwiftUI still owns thousands of `Text` nodes and row modifiers when previews are large. The project spec says large text, formatted documents, and table-like documents should use stable AppKit/WebKit renderers where possible.

Recommended structure:

- Route document-like file manager previews through the existing stable `ConductorDocumentWorkspaceView` or a smaller shared `DocumentPreviewSurface`.
- For source/log/table previews, prefer AppKit-backed text/table surfaces when the row count or cell count exceeds a threshold.
- Keep SwiftUI preview rows only for small bounded previews.
- Add explicit thresholds:
  - small source preview: SwiftUI okay
  - medium/large source preview: AppKit text view
  - CSV/TSV table above row/column threshold: WebKit table or AppKit table

Best first patch:

Introduce a preview routing strategy type that classifies preview payloads and centralizes thresholds, before replacing renderers.

### 5. Workspace file editor keeps full text in SwiftUI state

Evidence:

- `ConductorFileWorkspaceView` owns `text`, `savedText`, `textMetrics`, search matches, markdown preview text, diff state, and multiple task handles in `@State`.
- It uses an AppKit-backed source text view, which is good, but the source text still binds through SwiftUI state.
- `onChange(of: text)` updates metrics, schedules autosave, refreshes search, and schedules markdown preview refresh.

Why it matters:

For editable source files, especially markdown or large text, every edit can re-enter the SwiftUI view tree. The project spec already forbids `TextEditor(text: $fullFileText)` for large loaded contents; the same risk exists if AppKit text edits bounce the full text through SwiftUI state too frequently.

Recommended structure:

- Let the AppKit source editor own the live text buffer.
- Publish compact editor snapshots to SwiftUI:
  - dirty flag
  - metrics
  - search status
  - external change status
  - save status
- Use explicit snapshot requests for save/search/preview rather than binding every keystroke to the full text.
- Move autosave/search/markdown preview scheduling into a `WorkspaceFileEditorStore` or coordinator.

Best first patch:

Audit `ConductorWorkspaceSourceTextView` update frequency, then introduce a coordinator-owned text buffer path for the selected file tab.

### 6. Motion policy is too uniform for heavy surfaces

Evidence:

- `ConductorMotion.panelTransition` uses opacity + scale + offset + blur.
- Many lists and rows apply transitions and animations by default.
- Workspace/sidebar rows, notification rows, command rows, workspace tabs, and panel states all have animations.

Why it matters:

Micro motion is fine for small controls, but blur/scale/list transitions over heavy panels can cause expensive invalidation, especially while terminals, WebKit, file manager, or document previews are active.

Recommended structure:

- Create a motion cost policy:
  - cheap: opacity, small local transforms
  - expensive: blur, scale over large panel, matched geometry over dynamic lists
  - disabled under load: large list updates, live resize, terminal streaming, large preview mounted
- Use AppKit/Core Animation host layer transforms for large panel reveal.
- Disable row transitions above a count threshold.
- Avoid blur in panel transitions; use opacity or layer transform.

Best first patch:

Replace blur-bearing panel transitions with cheap opacity/transform variants for heavy panels, guarded by the existing reduced motion policy.

## P2 Findings

### 7. `AnyView` exists mostly in bridge-hosting code

Evidence:

- `SplitNodeView` stores `NSHostingView(rootView: AnyView(...))` for AppKit split children.
- It already uses a `HostingRootSignature` to avoid resetting roots unnecessarily.

Why it matters:

`AnyView` is normally a SwiftUI performance smell, but here it is localized to an AppKit bridge that needs type erasure. This is lower priority than broad model invalidation and bulk preview rendering.

Recommended structure:

- Keep for now.
- Revisit only if profiling shows split root refresh is hot.

### 8. Existing verification is strong and should become the refactor gate

Evidence:

- `Apps/Conductor/Scripts/check-conductor.sh` runs `swift build`, `swift run ConductorModelCheck`, multiple app smoke routes, stress, and resize-while-output.
- `Apps/Conductor/Scripts/stress-conductor.sh` has focused stress routes.

Recommended structure:

- For every refactor patch: at least `swift build` and `swift run ConductorModelCheck`.
- For terminal/split/resize/panel changes: run `Apps/Conductor/Scripts/check-conductor.sh`.
- For motion or surface identity changes: add focused signpost or manual Instruments capture when possible.

## Recommended Refactor Sequence

### Phase A: Snapshot boundaries before big movement

Goal: reduce invalidation fan-out while preserving behavior.

1. Introduce one or two `Equatable` snapshots for workspace/sidebar/toolbar or notification panel.
2. Convert leaf rows to value inputs + callbacks.
3. Keep `ConductorWindowModel` as command owner for now.

### Phase B: Extract one feature surface per patch

Goal: make the code elegant and reviewable without a huge rewrite.

Start with one of:

- Notification panel
- Workspace overview
- Command palette
- Sidebar/workspace chrome

Each extracted surface should get:

- one owning file
- one display snapshot where useful
- narrow props
- callback closures for actions
- no direct model observation in leaf rows

### Phase C: File manager snapshot/store refactor

Goal: make large file trees cheap and the code easier to reason about.

1. Extract `FileManagerDisplaySnapshotBuilder`.
2. Publish stored snapshots instead of computing from `body`.
3. Build large snapshots off-main if needed.
4. Introduce row display models.

### Phase D: Bulk preview routing

Goal: stop large previews from becoming SwiftUI row/cell workloads.

1. Create a `FilePreviewRenderingStrategy`.
2. Route large source/table/key-value/structured previews to AppKit/WebKit surfaces.
3. Keep SwiftUI previews for small bounded payloads only.

### Phase E: Motion cost policy

Goal: keep the app feeling alive without making heavy surfaces expensive.

1. Remove blur from heavy panel transitions.
2. Disable list transitions above thresholds.
3. Use Core Animation transforms for large mounted panels/trays.
4. Respect reduced motion and add a "high load" internal condition if needed.

## First Patch Recommendation

Start with **Notification Panel extraction + snapshot boundary**, then move to **Sidebar/workspace chrome snapshot boundary**.

Why:

- Small enough to review.
- Directly attacks broad `ConductorWindowModel` fan-out.
- Establishes the pattern that later refactors can copy.
- Lower risk than changing file editor text ownership or document renderers first.
- Notification Panel is especially contained: its current hot issues are direct whole-model observation, repeated title lookup through all workspaces/panes per notification row, list animation keyed by full record IDs, and row transitions. A `NotificationPanelSnapshot` can precompute rows and button enabled state once.
- Sidebar/workspace chrome is more important but wider: it computes workspace display rows in both sidebar and top tab strip, reads metadata/notification/workspace/model state directly, and animates list changes. It should copy the notification snapshot pattern after the first extraction lands.

After that, move to File Manager snapshot builder, because it is likely the highest ROI bulk-rendering target.
