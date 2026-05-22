# SwiftUI Skill Re-Audit

Date: 2026-05-22

## Why This Re-Audit Exists

This is a fresh audit after the theme propagation regression in Settings. The failure mode was not a simple color bug: performance-isolated chrome views stopped observing the broad `ConductorWindowModel`, but some of them still read theme and appearance through an unobserved model reference. The result was delayed sidebar and workspace-tab restyling until an unrelated workspace/tab change happened.

That lesson changes the audit standard:

- Performance is the first product requirement.
- Narrow observation is required, but narrow observation must carry all display inputs explicitly.
- A control in Settings is a cross-surface command. Its validation path must include the settings row, root environment, sidebar, toolbar, workspace tabs, terminal pane chrome, terminal surfaces, and persistence when relevant.
- Optimizations such as `.equatable()` are only acceptable when their equality inputs include every environment or prop that affects visible output.

## Skill And Project References Loaded

- SwiftUI Expert: latest APIs, state management, view structure, performance patterns, list patterns, animation basics.
- SwiftUI Pro: performance guidance for body cost, dedicated view extraction, avoiding repeated filtering/sorting, lazy rendering, and avoiding unnecessary `AnyView`.
- Project specs: high-performance terminal roadmap, frontend component guidelines, frontend state management, backend quality guidelines.

## Current Architecture Snapshot

Good patterns already in place:

- Terminal output, scrollback, cursor state, and live character rendering are still owned by Ghostty/AppKit, not SwiftUI.
- `TerminalSurfaceRepresentable` keeps a stable AppKit container and deduplicates frame/bounds/theme/focus work before touching the Ghostty surface.
- Settings, sidebar/top tabs, toolbar, notification panel, file manager display, and workspace overview now have several compact snapshot patterns.

Current code-size pressure:

- `ConductorRootView.swift`: 7,083 lines.
- `FileManagerPanel.swift`: 4,806 lines.
- `ConductorWindowModel.swift`: 2,672 lines.
- `ConductorDocumentWorkspaceView.swift`: 2,016 lines.
- `SplitNodeView.swift`: 1,690 lines.
- `ConductorFileWorkspaceView.swift`: 1,517 lines.

The size is not only aesthetic debt. Large files make it easy to miss data-flow coupling between Settings, root chrome, split panes, file tools, and terminal surfaces.

## P0 Findings

### 1. Split pane and terminal tab chrome still observe the whole window model

Files:

- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:13`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:45`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:71`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:787`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1070`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1353`

Evidence:

- `TerminalPaneView`, `StableTerminalTabStrip`, and `TerminalTabButton` use `@ObservedObject var model: ConductorWindowModel`.
- The tab strip reads terminal metadata, unread counts, drag state, workspace split capability, active pane state, density, theme, appearance, and command callbacks from the same model.
- `TerminalTabButtonContent` is `.equatable()` while reading `\.conductorTheme` and `\.conductorFontScale`; that is the same class of risk as the delayed theme propagation bug unless the parent passes visible theme/font identities or the equality wrapper is removed.

Impact:

- Metadata, notifications, panel visibility, drag/drop state, theme changes, file tabs, or settings tokens can invalidate terminal-adjacent tab chrome.
- During split resize or active output, SwiftUI tab chrome can compete with AppKit layout and Ghostty geometry sync.
- Future fixes can easily over-correct by removing observation and then accidentally reading stale model appearance values.

Required direction:

- Introduce `TerminalPaneChromeSnapshot` and `TerminalTabDisplayModel`.
- Pass theme, appearance, font scale, pane focus, drop target, tab rows, unread state, metadata summary, split capability, and drag identity as explicit values.
- Keep the model only as a command coordinator for actions such as select, close, rename, split, duplicate, and drag/drop.
- Preserve stable `TerminalSurfaceRepresentable` identity and never use `.id(theme)` or appearance identity on terminal host views.

### 2. Command Center still observes the whole model and filters commands in body

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift:473`
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift:588`
- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift:607`

Evidence:

- `CommandPaletteView` has `@ObservedObject var model: ConductorWindowModel`.
- `commands` calls `ConductorCommandCatalog.items(model:run:)` from a computed property.
- `filteredCommands` lowercases and filters command title, shortcut, section, and keywords from a computed property.
- The row list animates by `filteredCommandIDs`, and the panel subtitle reads `model.workspace.title`.

Impact:

- The palette is a keyboard-first hot path. While it is open, unrelated model changes can rebuild the command list and selection state surface.
- Typing in search repeatedly recomputes command catalog/filter work in `body`.

Required direction:

- Add `CommandPaletteSnapshot` with title/subtitle, current command rows, disabled state, shortcuts, and section grouping.
- Cache or prebuild command search text once per command row.
- Keep command execution routed through model closures, but keep display rows as immutable values.
- Scope animations to selection feedback only; avoid list insertion animation for ordinary query filtering.

## P1 Findings

### 3. Workspace file editor is still a large SwiftUI state hub

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift:214`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift:249`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift:355`
- `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift:497`

Evidence:

- The selected file editor still carries full `text`, `savedText`, metrics, autosave task, external watch task, search task, diff state, search state, source selection state, markdown preview text, and preview update task in one SwiftUI view.
- Phase 7 improved AppKit live-buffer ownership, but the SwiftUI view remains the coordinator for many unrelated editor concerns.

Impact:

- Editing, search, autosave, external-change watching, Markdown preview, and dirty-state publishing are tightly coupled.
- This is harder to reason about than it needs to be, and future file features can accidentally reintroduce full-text SwiftUI churn.

Required direction:

- Move editor state into a `WorkspaceFileEditorStore` or AppKit coordinator-owned buffer.
- Let SwiftUI receive compact editor snapshots: dirty state, metrics, search summary, external-change state, save status, and preview mode.
- Keep full text snapshots explicit and bounded: save, close, preview refresh, search refresh, and autosave checkpoints.

### 4. File manager store is improved but still mixes tree, preview, selection, search, and operations

Files:

- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift:1121`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift:1133`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift:1135`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift:1142`

Evidence:

- `FileManagerPanelStore` has many `@Published` fields for tree data, selection, preview, operation messages, delete state, rename state, search, filters, recents, favorites, focus tokens, and undo records.
- `FileManagerDisplaySnapshot` is a good pattern, but unrelated preview/operation mutations can still invalidate the panel store observer.

Impact:

- The panel can still feel heavy in large directories, especially when selection and preview work happen near row-list updates.

Required direction:

- Split tree/search display state from preview and operation banner state.
- Consider an AppKit `NSOutlineView` or fixed-row virtualized list for very large trees.
- Keep SwiftUI rows only for bounded counts or known-small directories.

### 5. Root and settings code remain too monolithic for safe cross-module work

Files:

- `Apps/Conductor/Sources/Conductor/UI/ConductorRootView.swift:1`
- `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift:1`

Evidence:

- `ConductorRootView.swift` still contains root shell, command center, settings, workspace overview, sidebar, toolbar, rows, preview mockups, and snapshots.
- Settings has improved snapshots and a clearer terminal category structure, but large global preference controls still live in the same file as unrelated root shell chrome.

Impact:

- The previous theme propagation issue is exactly the kind of bug large mixed files invite: a performance change in chrome changed Settings behavior through an indirect data-flow path.

Required direction:

- Extract by product surface, not by random helper type:
  - `CommandCenter/`
  - `Settings/`
  - `WorkspaceOverview/`
  - `Sidebar/`
  - `Toolbar/`
  - `SplitPane/`
- Keep snapshots close to the surface they feed.
- Each extracted feature should expose a narrow display snapshot plus action closures or a coordinator reference.

### 6. Motion is mostly improved but terminal tab rows still stack several animations

Files:

- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1519`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1520`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1521`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1522`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:1523`

Evidence:

- Terminal tab buttons animate hover, drop target, editing, unread, and drag state separately.

Impact:

- This is acceptable for a few tabs, but it becomes suspect with many tabs and active terminal metadata changes.

Required direction:

- Keep hover and selection cheap.
- Disable or coalesce row animations during split resize, drag, or high tab counts.
- Avoid layout-affecting animations in terminal-adjacent chrome.

## P2 Findings

### 7. `AnyView` is currently mostly bridge-hosting, but should stay contained

Files:

- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:121`
- `Apps/Conductor/Sources/Conductor/UI/SplitNodeView.swift:191`

Evidence:

- `AnyView` is used to swap SwiftUI roots inside `NSHostingView` for the AppKit split pair.

Impact:

- This is less concerning than `AnyView` inside rows/lists, but it should not spread into repeated terminal tab, sidebar, command, settings, or file rows.

Required direction:

- Treat this as an AppKit bridge exception.
- Do not introduce `AnyView` as a general solution for conditional SwiftUI rows.

## Recommended Next Sequence

1. **Command Center snapshot phase**: smaller blast radius than split panes, high user-visible payoff, and it exercises the same rule as Settings: value display state plus command callbacks.
2. **Terminal pane chrome snapshot phase**: highest performance risk. Add `TerminalPaneChromeSnapshot` and `TerminalTabDisplayModel`, then remove broad observation from tab strip/buttons without touching terminal surface identity.
3. **Settings extraction phase**: move Settings into its own folder/files after the snapshot contracts are stable. Extraction should make global preference linkage easier to inspect.
4. **File editor store phase**: move file editor scheduling/search/autosave/diff coordination out of the SwiftUI view while preserving AppKit live buffer ownership.
5. **File manager store segmentation / virtualization phase**: separate tree rows from preview/operations, then choose AppKit virtualization for large trees if needed.

## Guardrails For Future Patches

- Do not remove `@ObservedObject` from a container unless every visual value it used to read is passed as an explicit value input or snapshot field.
- Do not wrap a view in `.equatable()` if it reads theme, font scale, locale, density, or any other environment value not represented in equality inputs.
- Do not fix stale theme updates with `.id(theme)` on expensive host views; that can recreate AppKit/Ghostty/WebKit surfaces.
- Do not route terminal transcript, scrollback, cursor movement, raw output, or render counters into SwiftUI state.
- Do not animate large row collections or terminal-adjacent layout during split resize, drag, or heavy output.
- Do not accept a refactor as complete just because code is cleaner. The interaction must be smooth.

## Verification Expectations

For small snapshot-only changes:

- `swiftc -parse` over `Sources/Conductor` and `Sources/ConductorCore`.
- Manual smoke for the affected surface.

For split pane, terminal chrome, file editor, or model/store changes:

- `swift build`.
- `swift run ConductorModelCheck`.
- Manual smoke: theme switch with Settings open; workspace/tab switching; split resize; terminal focus; command palette; file manager tray.

For large or cross-layer changes:

- Full `./Scripts/check-conductor.sh`.
- Instruments trace for the interaction being optimized when subjective jank remains.
