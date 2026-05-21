# Component Guidelines

> How native macOS UI components are built in this project.

---

## Overview

The UI shell is SwiftUI-first, with AppKit bridges for the parts where macOS control, responder-chain behavior, or high-frequency rendering matters. SwiftUI owns product-level composition. AppKit owns terminal host views, window integration, keyboard routing, drag/drop, focus, and resize-sensitive surfaces.

Always read `../guides/high-performance-terminal-roadmap.md` before adding UI that touches terminal panes, split panes, workspace switching, or agent notifications.

---

## Component Structure

Prefer small SwiftUI views that render stable metadata snapshots. A view should receive compact values such as title, cwd, branch, status, unread count, focus state, and notification summary. It should not receive terminal transcript text, raw output buffers, or scrollback models.

Use `NSViewRepresentable` only as a stable anchor or bridge. The underlying AppKit view identity should survive SwiftUI update cycles whenever it owns expensive runtime state such as a Ghostty surface, WebKit view, or long-lived overlay.

For terminal panes, follow this shape:

```text
TerminalPaneView (SwiftUI)
-> TerminalHostRepresentable (stable anchor)
-> AppKit host/portal view
-> Ghostty surface view with Metal-backed rendering
```

---

## Props Conventions

Props should be value-oriented and narrow. Pass IDs, booleans, and small display models. Avoid passing broad global stores into leaf views.

For repeated UI like sidebar rows and tab items, define a lightweight display model:

```swift
struct WorkspaceRowDisplayModel: Equatable, Identifiable {
    let id: WorkspaceID
    let title: String
    let directory: String?
    let gitBranch: String?
    let unreadCount: Int
    let isRunningAgent: Bool
    let lastNotificationSummary: String?
}
```

The model must be derived from throttled runtime snapshots, not from raw terminal output.

---

## Styling Patterns

Use native SwiftUI styling for ordinary app chrome. Use AppKit layer-backed views for overlays that must track terminal geometry precisely: notification rings, inactive-pane overlays, drag/drop highlights, and search affordances near the terminal surface.

Do not wrap terminal content in decorative SwiftUI cards. Terminal panes are working surfaces; chrome should be restrained, dense, and predictable.

For the main shell, the sidebar is a floating navigation panel, not a hard edge rail.
It should sit on the window background with rounded corners, a subtle stroke, and a
low shadow. The terminal canvas remains the dominant work surface; do not place the
terminal area inside a decorative card just to match the sidebar.

### Convention: Modern Shell Tokens

**What**: UI chrome should be driven by semantic tokens in `ConductorTokens`, then exposed through `ConductorDesign` compatibility aliases when existing views still use the older names.

**Why**: The shell is dense terminal software. Tokenized colors, radii, spacing, shadows, and typography keep sidebar, toolbar, workspace tabs, terminal tabs, split gutters, and status text visually consistent without letting decorative chrome compete with the terminal surface.

**Contract**:

- `ConductorTokens.Palette` owns semantic colors such as `window`, `canvas`, `selectedFill`, `hoverFill`, `splitGutter`, and text levels.
- `ConductorTokens.Radius` owns shared radii for sidebar, control groups, workspace tabs, terminal panes, terminal tabs, and rows.
- `ConductorTokens.Space` owns shell padding, sidebar width, toolbar height, terminal inset, split gutter width, and status bar height.
- `ConductorTokens.Typography` owns stable `Font` values for app title, rows, toolbar, workspace tabs, terminal tabs, and status text.
- `ConductorTokens.Shadow` owns reusable opacity/radius/y triples for floating panels, controls, and selected tabs.

**Correct**:

```swift
.clipShape(RoundedRectangle(cornerRadius: ConductorTokens.Radius.terminalPane))
.frame(height: ConductorTokens.Space.toolbarHeight)
.font(ConductorTokens.Typography.workspaceTabSelected)
```

**Wrong**:

```swift
.clipShape(RoundedRectangle(cornerRadius: 11))
.frame(height: 31)
.font(.system(size: 12.3, weight: .semibold))
```

Only introduce one-off numeric styling when the value is intrinsic to a specific asset or AppKit bridge. Otherwise add or reuse a token first.

### Convention: macOS 2026 Glass Direction

**What**: Conductor's modern shell should target the macOS 2026 / Liquid Glass visual
language for product chrome while keeping the terminal renderer itself owned by
GhosttyKit/AppKit.

**Why**: The product should feel like a native macOS 2026 workspace, not a web dashboard
wrapped around terminals. Glass surfaces, floating control groups, and fluid navigation
belong around the terminal: sidebar, toolbar groups, command center, notification feed,
workspace overview, and compact status modules.

**Contract**:

- Use `ConductorGlassSurface` for floating glass panels, command surfaces, cards, and
  control groups instead of ad hoc `.regularMaterial`, strokes, and shadows.
- Keep glass styling centralized in `ConductorGlassSurfaceStyle` and token enums so SDK
  feature detection, macOS 14/15 fallback, and macOS 26 Liquid Glass behavior stay in one
  place.
- Prefer system-first, lightweight controls: icon buttons, compact pills, searchable command
  surfaces, popovers, inspectors, and floating control groups.
- Do not make terminal content decorative. The terminal pane remains the dark working surface;
  glass belongs to navigation and metadata chrome.
- Treat visual themes as whole-shell presets, not terminal palettes only. A theme should own
  Ghostty colors, terminal chrome, the window backdrop, and the accent color together so the
  shell feels intentionally composed after switching themes.
- Whole-shell theme colors live on `TerminalTheme`. Shell surfaces should read theme-owned
  panel backgrounds, selected fills, hover fills, strokes, terminal chrome, terminal pane
  outlines, backdrop stops, and accent color instead of hard-coding fixed white/black opacity
  values in each component.
- `ConductorGlassSurface` resolves sidebar, palette, and panel tint/stroke from the current
  theme environment. Leaf sidebar/settings rows should use `\.conductorTheme` so theme changes
  update chrome consistently without manually passing theme through every view.
- The main window backdrop should remain translucent material plus a light theme wash, not an
  opaque flat fill. Sidebar linework must stay quiet and intentional: use a soft rounded
  outline and short section separators, not stacked hard vertical dividers or selected-row
  strokes.
- The top workspace toolbar should feel like a translucent command shelf, not a compressed
  black strip. Give it enough vertical room, use material plus theme tint, separate workspace
  navigation from command groups, and make action clusters read as floating capsules.
- Terminal creation should have one primary user-facing entry. Do not expose separate "new
  terminal" and "new tab" controls when they perform the same focused-pane action.
- Command Center, Settings, Workspace Overview, Notification Center, and future floating shell
  panels should use theme-owned floating colors (`floatingPanelBase`, `floatingPanelWash`,
  `floatingControlFill`, `floatingControlStrongFill`, `floatingStroke`, selected/hover fills,
  and separators). Do not tint these panels directly with `shellPanelBackground` and do not
  create a separate settings-only color language; one app theme must produce one floating-panel
  language.
- Floating shell panels must not use the terminal/workspace `accent` as their default selected,
  hover, icon, unread, or focus color. Use neutral panel tokens such as `floatingEmphasis`,
  `floatingSelectedFill`, `floatingHoverFill`, and `floatingSelectedStroke` so Command Center,
  Settings, Workspace Overview, Notification Center, and file/tool previews match the sidebar's
  low-saturation glass language. The terminal `accent` remains appropriate for live terminal
  focus rings, terminal tabs, cursor/progress affordances, and explicit theme preview swatches.
- Floating shell panels should be translucent in material feel, not transparent in readability.
  `floatingPanelBase` must be strong enough that terminal text behind a modal panel does not
  visibly bleed through body controls or selected rows. Use soft black/white control layers for
  selected and hover states instead of colored translucent fills over live terminal content.
- Floating shell panels should share one outer skeleton: `ConductorGlassSurface`, one
  `FloatingPanelHeader`, one `FloatingPanelDivider`, then the panel's specialized content.
  Settings may include an internal category sidebar, but it should not add a second competing
  title bar inside the panel. In-window floating panels should share a common width/height
  unless the surface is a true small popover.
- Files opened from terminal file URLs are low-frequency tool UI beside the terminal, not
  terminal rendering. Route local files and directories into the app-owned right-side file
  manager surface instead of a one-off preview panel. Directory scans and text previews must
  do file IO off the main actor, cap initial reads, and expose only compact file metadata and
  bounded preview documents. They must not inspect terminal scrollback or make terminal
  transcript text observable. Formatted document parsing is intentionally not part of the
  current product surface.
- AppKit document/preview surfaces that own large text, native previews, or renderer state
  must deduplicate no-op `updateNSView` work. Theme, font, and geometry setters should return
  early when values are unchanged, and resize/selection/search updates should invalidate only
  the visible rect unless the whole backing document truly changed. Do not call
  `setNeedsDisplay(bounds)` from every SwiftUI update on a tall document view.
- Document reading surfaces must keep file loading, Markdown parsing, text search, image
  decoding, and inline diff generation outside SwiftUI `body` and view initializers. Use a
  cancellable task, generation token, background queue, actor, or AppKit surface, then publish
  a compact loading/ready/error snapshot back to the view. Shared image display must use the
  async image loader/cache path instead of calling `NSImage(contentsOf:)` from `body`.
- Workspace document tabs use a stable WebKit/AppKit renderer for formatted documents.
  Markdown, code, JSON, CSV/TSV, spreadsheet files, DOCX, image, PDF, HTML, and future rich
  formats should enter SwiftUI as compact file metadata plus a bounded payload only; do not
  rebuild Markdown or large text as thousands of SwiftUI rows. Community renderers such as
  markdown-it, DOMPurify, highlight.js, PapaParse, Mermaid, KaTeX, PDF.js, Mammoth, and SheetJS
  are bundled as app resources so previews work offline and do not depend on CDN availability.
  Binary document payloads must stay capped, and large files should show an explicit protected
  state or fall back to a cheap native surface rather than blocking the main actor.
  WebKit document surfaces must also avoid resizing the web view on every live-resize tick for
  large documents. Freeze the underlying `WKWebView` frame while AppKit reports live resize,
  then apply one final frame update when resizing ends; pair this with browser-side
  `content-visibility` for repeated Markdown blocks so offscreen document content does not
  repeatedly reflow during window drags.
- Formatted file views should share one document workbench skeleton: a theme-owned header with
  title/path/status badges, bounded metadata metrics, a typed reader body, and an optional
  outline column only when the format can provide useful headings. Markdown, log, TeX, and text
  files should not fall back to ad hoc SwiftUI rows or high-contrast zebra stripes in the file
  manager; route document-like previews through the same stable document renderer when possible.
  Large text files should show an explicit protected reading state and a calm source panel,
  not a broken-looking partial render.
- The workspace file/document area is a single replaceable file slot, not a many-file tab
  strip. Opening another file from terminal links, the file manager, or drag/drop replaces the
  existing file tab and prunes the previous file's dirty/external/save-token state. Terminal
  tabs remain multi-tab; document tabs do not accumulate.
- QuickLook and other native preview surfaces should follow the same live-resize contract as
  WebKit document views. Keep the expensive child AppKit view at its previous frame while the
  window is live-resizing, cover it with a theme-colored layer, and apply one final frame update
  when resizing ends. Split pane drag paths should also suspend terminal geometry sync and avoid
  no-op `needsDisplay` invalidations so resize does not fight Ghostty surface updates.
- When a shell panel is open, suspend terminal input focus so the live terminal host does not
  reclaim first responder from controls inside settings, command palette, or overview. The first
  click inside a panel must activate the clicked control, not only move focus away from terminal.
- Heavy floating panels such as Settings must not subscribe every row to
  `ConductorWindowModel`. The root shell may observe the model, but panel leaf views should
  receive the model as a plain reference, compact values, or callbacks unless they truly need an
  independent subscription. This prevents terminal metadata updates from invalidating dozens of
  settings rows while a panel is open.
- Heavy floating panels should avoid blur-based insertion/removal transitions and full-content
  `.id(...)` transitions. Use cheap opacity or non-animated content swaps, and reserve matched
  geometry for small selection indicators.
- Bind fluid effects only to low-frequency product state such as selection, command palette
  visibility, notification badges, sidebar visibility, and workspace navigation.
- Do not bind glass effects, blur changes, or animated mesh/background effects to stdout,
  scrollback, cursor movement, or terminal redraws.
- Xcode live preview scenarios should use compact preview fixtures. Prefer `PreviewProvider`
  while SwiftPM command-line builds cannot resolve Xcode's `#Preview` macro plugin.

## Scenario: Right-Side File Manager Surface

### 1. Scope / Trigger

- Trigger: Adding or changing the shell file manager, terminal `file://` handling, or commands
  that open local files/directories beside the terminal.

### 2. Signatures

- `ConductorShellCommand.toggleFileManager`
- `ConductorWindowModel.fileManagerPanelRequest: FileManagerPanelRequest?`
- `ConductorWindowModel.showFileManagerForFocusedDirectory()`
- `ConductorWindowModel.showFileManager(for terminalID: TerminalID) -> Bool`
- `ConductorWindowModel.insertPathIntoFocusedTerminal(_ url: URL) -> Bool`
- `FileManagerPanelRequest(rootURL:selectedURL:)`

### 3. Contracts

- Toolbar, command palette, and terminal context-menu entry points must share the
  `toggleFileManager` / `showFileManager` model path.
- The panel root defaults to the focused terminal working directory. Terminal-originated file
  URLs open the panel at the file's parent directory with that file selected.
- Directory listing state may enter SwiftUI as compact metadata only: URL, display name,
  directory flag, symlink flag, and file size. Directory IO and text-preview IO run off the
  main actor.
- Text previews must be bounded. Large or binary files show an explicit state instead of
  loading complete contents into SwiftUI.
- Renderable local files that macOS can preview natively, such as HTML, webarchive, PDF, SVG,
  common media, and common office/iWork documents, should route to a stable AppKit native
  preview surface instead of CodeEdit or SwiftUI text rendering. Do not read the full file
  into SwiftUI just to decide how to display it; classify from `UTType` and extension metadata.
- Inserting a path into the focused terminal sends shell-escaped text plus a trailing space,
  and does not press Return.

### 4. Validation & Error Matrix

- No focused terminal cwd -> toolbar/command action is disabled unless the file panel is
  already visible and can be closed.
- Missing terminal-originated file -> handled by Conductor notification/error UI and the
  Ghostty fallback must not show a LaunchServices alert.
- Unreadable directory -> show a panel error state; do not crash or block the terminal host.
- Document, Markdown, and image preview work must use cancellable tasks tied to view/model
  lifetime. Do file bytes and parsing off the main actor, then publish compact UI state back on
  the main actor. Avoid creating or mutating AppKit image/view objects from detached background
  queues; rapid tab switching can otherwise turn preview races into app exits with little useful
  crash context.
- Unsupported or binary file -> show a preview message and keep Reveal/Copy/Insert actions
  available.

### 5. Good/Base/Bad Cases

- Good: `file://.../foo.swift` from terminal opens the file manager, selects `foo.swift`,
  and previews bounded text.
- Base: A folder row is clicked; the row expands or collapses its children inline without
  replacing the whole directory view or introducing a split tree.
- Bad: A directory scan runs synchronously inside `body`.
- Bad: A local file URL from Ghostty is passed directly to `NSWorkspace.open`.

### 6. Tests Required

- `swift build`
- `swift run ConductorModelCheck`
- Full gate: `./Scripts/check-conductor.sh`
- Manual smoke: open the file panel from toolbar, command palette, and terminal context menu;
  select text/image/binary files; insert a path into the focused terminal.

### 7. Wrong vs Correct

#### Wrong

```swift
if url.isFileURL {
    NSWorkspace.shared.open(url)
}
```

#### Correct

```swift
if isDirectory {
    showFileManager(rootURL: fileURL)
} else {
    showFileManager(rootURL: fileURL.deletingLastPathComponent(), selectedURL: fileURL)
}
```

### Convention: Shell Motion

**What**: Low-frequency product UI changes should use shared motion tokens such as
`ConductorMotion.micro`, `standard`, `layout`, and `emphasized`. Apply motion to
shell chrome: sidebar expansion, workspace and terminal tab selection, tab/list insertions
and removals, badges, notification rows, command palette entry, pane focus rings, and
button press/hover feedback.

**Why**: Motion should make the app feel native and responsive without turning terminal
rendering into SwiftUI work or making precision interactions lag behind the pointer.

**Contract**:

- Use `ConductorMotion.perform` around user-triggered metadata actions when the resulting
  SwiftUI chrome should animate.
- Do not bind animations to terminal output, scrollback, cursor movement, or runtime redraws.
- Do not animate the Ghostty/AppKit terminal surface itself with opacity, scale, or identity
  changes.
- Do not attach a layout animation to split fractions during divider drag. Animate split
  creation, close, move, or equalize, but drag updates must stay immediate.
- Do not attach broad implicit animations to ancestors of the live Ghostty host view for
  focus changes, split-tree changes, or selected-tab changes. Animate separate chrome
  overlays and controls, not the `NSViewRepresentable` that owns the terminal renderer.
- Do not use directional slide transitions for workspace or terminal tab insertion. Tab strips
  are navigation chrome, so adding or restoring many tabs should not look like the entire strip
  is sliding in. Prefer opacity plus a tiny scale change for tab insertion/removal.
- Keep workspace and terminal tab selection atomic. Do not attach implicit animations to
  selected foreground, icon, fill, stroke, or shadow styles, and do not wrap tab selection
  actions in a broad animated transaction. Animate scroll-to-visible, insertion/removal,
  hover/press, badges, and separate indicators instead.
- Use tiny transform-only feedback for hover/press; never insert or remove controls on hover.
- Workspace tabs should read as restrained floating capsules, not generic square buttons:
  use a compact dark fill, subtle stroke, stable grid glyph, and quiet terminal-count badge.
  Avoid stacking a selected-tab underline with the pane rail separator below it; selected
  state should come from fill, stroke, text weight, and glyph emphasis instead. Keep inactive
  workspace tabs visible but low-contrast so the terminal surface remains dominant.
- Workspace and terminal tab selected fills should stay neutral and theme-owned. Reserve
  saturated accent colors for live terminal focus affordances, unread/progress signals, and
  explicit theme previews; using the accent as the tab body makes the shell feel fragmented
  and competes with the terminal surface.
- Keep motion tokens intent-specific. Use `ConductorMotion.search` for the context-search
  chip, `ConductorMotion.panel` / `panelTransition` for floating panels, `ConductorMotion.list`
  / `rowTransition` for filtered command, overview, and notification rows, and
  `ConductorMotion.scroll` for scroll-to-visible behavior in tab strips. Do not reuse
  selection motion for scroll positioning; it makes tab navigation feel sticky and hides
  whether the state changed immediately.
- Use `ConductorMotion.feedback` for keyboard-driven row or card highlights that can move
  many times per second. Reserve `selection` / `navigation` for lower-frequency destination
  changes; otherwise command palettes and overview grids feel sticky under arrow keys.
- Defer search-field focus until the floating surface has entered the view tree. Command
  Center, Workspace Overview, and terminal context search should set their `FocusState` from
  the next main-actor turn so the first responder does not race panel insertion animation.

**Correct**:

```swift
ConductorMotion.perform(ConductorMotion.layout) {
    model.closePane(pane.id)
}

.animation(ConductorMotion.standard, value: isFocused)
```

**Wrong**:

```swift
.animation(ConductorMotion.layout, value: model.workspace.root) // also animates drag fraction
.opacity(isFocused ? 1 : 0.9) // applied to the live terminal surface
```

### Convention: Terminal Pane Chrome

**What**: Pane tab rails, terminal tabs, split gutters, and active-pane focus rings are
working chrome. They must use stable tokenized dimensions and may only reflect compact
product state such as selected tab, focused pane, unread state, hover, and drag state.

**Why**: Terminal panes are the primary work surface. Focus needs to be unmistakable, but
visual polish must not resize tab strips, add shadows over terminal text, or couple SwiftUI
styling to terminal output.

**Contract**:

- Keep pane tab rail height, tab height, tab width, and split gutter width in
  `ConductorTokens.Space`.
- Keep split fraction clamping in `SplitNode.minimumFraction` /
  `SplitNode.maximumFraction` and reuse `SplitNode.clampedFraction(_:)` from SwiftUI/AppKit
  split chrome. Do not add a second wider UI-only clamp such as `0.15...0.85`; divider drag
  should feel free until the real pixel minimum of the nested pane tree is reached.
- AppKit split minimum lengths are only a safety rail, not a layout preference. Keep leaf
  minimums tiny so nested split groups do not accumulate into a large invisible drag clamp.
  Visual readability can be handled by empty-state/chrome behavior; divider movement must not
  stop at 15-20% just because the pane is nested.
- Do not add or remove tab controls on hover. Reserve stable close/new-tab slots and change
  opacity, fill, or stroke only.
- Show the active pane with a full pane border or rail accent. Do not rely on a small dot,
  transient badge, shadow, or text label as the only focus signal.
- Do not draw a strong pane top border directly under the workspace toolbar. That creates a
  redundant middle hairline between workspace tabs and terminal tabs; prefer side/bottom pane
  borders plus tab emphasis in that region.
- Inactive panes may still show their selected tab, but with a quieter selected style than the
  focused pane. The focused pane owns the strongest accent treatment.
- Terminal tab selection should come from fill, stroke, icon/text weight, and compact metadata
  such as cwd/unread/readonly. Avoid bottom underlines in pane tabs; they create extra horizontal
  seams against the workspace toolbar and pane rail.
- Split gutters should have a stable hit target. Hover/drag may brighten the center handle,
  but dragging must keep split fraction updates animation-free.
- Split resize geometry should be AppKit-owned, not SwiftUI-frame-owned. Use a stable
  `NSSplitView` bridge for live divider dragging so AppKit adjusts the two hosted panes
  directly, terminal host views keep their identity, and `WorkspaceState.root` receives only
  the final divider fraction after mouse-up.
- Split gutter cursor overrides must be released explicitly on mouse exit, drag end outside
  the divider, and view teardown; a resize cursor must not remain stuck after divider drag.
- While a divider is being dragged, quiet adjacent pane border overlays so the gutter remains
  the only strong shared edge. Do not let both pane borders plus the divider draw competing
  hairlines during resize.
- Do not apply opacity/scale animations to the live `TerminalSurfaceRepresentable`; animate
  separate chrome overlays only.

**Correct**:

```swift
.frame(height: ConductorTokens.Space.paneTabRailHeight)

Rectangle()
    .stroke(isFocused ? theme.accent.opacity(0.82) : Color.white.opacity(0.075), lineWidth: isFocused ? 1.5 : 1)
    .allowsHitTesting(false)
```

#### Wrong

```swift
GeometryReader { proxy in
    HStack(spacing: 0) {
        first.frame(width: dragPreviewWidth)
        divider.onDrag { dragPreviewWidth = $0 }
        second.frame(width: proxy.size.width - dragPreviewWidth)
    }
}
```

#### Correct

```swift
NSViewRepresentableSplitView(
    first: firstHostedView,
    second: secondHostedView,
    onMouseUp: { model.setSplitFraction(path: path, fraction: finalFraction) }
)
```

### Convention: Terminal Drag And Drop

**What**: Internal terminal-tab dragging and external Finder/file dragging must use different
drop types and different visual feedback.

**Why**: Finder file drags often advertise text-compatible payloads in addition to file URLs.
If split-pane/tab-reorder drops accept broad text types, dragging a file over a terminal can
show the split placeholder even though the user intent is to paste the file path into the
terminal.

**Contract**:

- Internal tab drag/reorder/split operations must advertise a private app UTType as the
  primary payload. `UTType.text` may only be used as a compatibility fallback for macOS
  drag/drop plumbing.
- Internal tab drag/reorder/split operations must also require an in-process drag-session
  marker set by the terminal-tab `onDrag` source. Do not trust UTType matching alone; external
  providers can match surprisingly broad data representations.
- Split placeholders and tab insertion highlights may only appear for private internal tab
  drags: the private type or a text fallback must be paired with the active in-process
  drag-session marker and a valid terminal-tab ID payload.
- Terminal-tab drop edge zones should scale with the target pane and stay below half the pane
  size. Avoid fixed large minimum edge widths such as 80px because small panes then feel like
  they only have a few legal drop positions.
- When a live `NSViewRepresentable` terminal surface covers the pane, terminal-tab split drops
  must be handled by the stable AppKit host, not by a competing SwiftUI `.onDrop` around the
  live terminal surface: register the private tab type on `TerminalHostView`, publish deduped
  hover target changes back through `ConductorWindowModel`, draw the split placeholder at the
  full pane level so it covers the tab rail and terminal surface together, and route the final
  drop back through `ConductorWindowModel`.
- If a SwiftUI `NSItemProvider` payload is consumed by the AppKit host's `NSDraggingPasteboard`,
  the private tab type must be visible to the pasteboard reader. Keep the type private and gate
  acceptance through the active in-process drag-session marker rather than relying on provider
  visibility alone.
- Internal tab drags may also provide a text-compatible fallback payload for macOS drag/drop
  compatibility, but SwiftUI and AppKit drop handlers must only accept that fallback while the
  active in-process tab-drag marker is set and the payload parses as a terminal-tab ID.
- SwiftUI tab-strip `.onDrop` handlers should register only the private terminal-tab UTType.
  Do not include `UTType.text` on the tab strip itself; text fallback belongs in the AppKit
  terminal host path where pasteboard types can be inspected before deciding whether the drag
  is internal or an external file/URL drop.
- External `.fileURL`/`.URL`/legacy filename drops on a live terminal surface should be
  handled by the stable AppKit `TerminalHostView`, focus the target terminal, and insert
  shell-escaped file paths as terminal input without pressing Return. Decode file URLs first,
  then fall back to URL payloads, matching Ghostty/cmux drag-destination behavior where it
  does not conflict with app tab dragging.
- If the AppKit host sees external file/URL pasteboard types, it must not parse the generic
  `.string` payload as a terminal-tab fallback. This prevents Finder drags that also expose
  string data from producing split placeholders instead of inserting paths.
- Do not accept broad `.string` drag types on `TerminalHostView` as ordinary terminal-tab
  drops. If `.string` is registered as a compatibility fallback, the host must first verify
  the active in-process tab-drag marker and parse the payload as a terminal-tab ID before
  returning `.move`; otherwise it must reject the string path so external drags do not show
  split placeholders.
- Terminal host file/text drop handling must reject the private internal terminal-tab drag
  pasteboard type so dragging tabs cannot be inserted into the shell as text.
- Do not route dropped file contents or path lists through observable SwiftUI transcript state.

**Correct**:

```swift
final class TerminalHostView: NSView {
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard surface?.canAcceptTerminalTabDrop() == true else { return [] }
        surface?.updateTerminalTabDropTarget(target)
        return .move
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let draggedTerminalID = terminalTabID(from: sender.draggingPasteboard) {
            return surface?.performTerminalTabDrop(draggedTerminalID: draggedTerminalID, target: target) ?? false
        }
        surface?.sendText(shellQuotedPaths + " ")
        return true
    }
}

final class ConductorWindowModel: ObservableObject {
    func setTerminalTabDropTarget(for terminalID: TerminalID, target: TerminalTabDropTarget?) {
        guard terminalTabDropTargetByPaneID[paneID] != target else { return }
        terminalTabDropTargetByPaneID[paneID] = target
    }
}
```

**Wrong**:

```swift
.onDrop(of: [UTType.text], delegate: TerminalDetachDropDelegate(...))
.onDrop(of: [terminalTabDragType], delegate: TerminalDetachDropDelegate(...)) // around TerminalSurfaceRepresentable
.onDrop(of: [.fileURL], delegate: TerminalFileDropDelegate(...)) // wrapped around NSViewRepresentable
```

### Convention: Dense Tab Strip Scrolling

**What**: Dense workspace and terminal tab strips should use complete-item scrolling with
SwiftUI scroll targets when the deployment target supports it.

**Why**: Trackpad and wheel scrolling should feel native, but the strip must not rest with
half a title or only a close button visible at the edge. Programmatic selection should move
the selected tab toward the center without animating the terminal surface or changing toolbar
height.

**Contract**:

- Put tab IDs on the tab views and mark the stack with `.scrollTargetLayout()`.
- Use `.scrollTargetBehavior(.viewAligned)` plus `.scrollPosition(id:anchor:)` for selected
  tab centering instead of ad hoc `ScrollViewReader.scrollTo` when possible.
- Keep scroll-position state local to the tab strip. Do not promote scroll offset or geometry
  into the window model.
- Animate only the scroll target update and insertion/removal chrome. Keep selected tab color,
  icon, fill, and stroke changes atomic.
- Keep native horizontal indicators hidden inside 21-25px tab rails; use fixed-height viewports
  and edge fades or external affordances instead.
- Keep close buttons outside the parent tab selection tap region. Tapping a close button must
  not also select the tab/workspace; selection belongs to the title/glyph content region, while
  close is a separate instant action.
- Close-tab and close-workspace actions should use a non-animated transaction. Animated layout
  closes can briefly select/recenter the closing item, make neighboring tabs look like they are
  cycling into the first slot, or animate live terminal surfaces during removal.

**Correct**:

```swift
ScrollView(.horizontal, showsIndicators: false) {
    HStack {
        ForEach(workspaces) { workspace in
            WorkspaceTopTab(workspace: workspace)
                .id(workspace.id)
        }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.viewAligned)
.scrollPosition(id: $scrollTargetID, anchor: .center)

TabTitleContent(...)
    .contentShape(Rectangle())
    .onTapGesture { selectTab() }

Button {
    ConductorMotion.withoutAnimation { closeTab() }
} label: {
    Image(systemName: "xmark")
}
```

### Convention: Auxiliary Panel Focus

**What**: AppKit auxiliary panels such as the notification center must not leave the main
`ConductorWindow` without key focus after they are hidden or replaced by an in-window SwiftUI
surface.

**Why**: If an `NSPanel` is shown with `makeKeyAndOrderFront` and later hidden with only
`orderOut`, the app can remain active while the main window is no longer key. The next click
on toolbar/sidebar chrome may only refocus the main window instead of activating the control,
which feels like the app stopped accepting clicks.

**Contract**:

- Prefer `orderFront` or `orderFrontRegardless` for notification-style panels that do not need
  text input focus.
- Set `becomesKeyOnlyIfNeeded = true` for notification panels.
- When hiding an auxiliary panel, call a main-window focus restoration helper that makes the
  main `ConductorWindow` key again while the app is active.
- Opening an in-window modal surface such as Command Center, Appearance Center, or Workspace
  Overview must also dismiss any auxiliary notification panel.
- Do not use separate `NSPanel` windows for shell surfaces that can live safely inside the
  main SwiftUI window; prefer a single in-window overlay when possible.
- In-window dimming layers for Command Center, Appearance Center, and Workspace Overview are
  visual only unless the surface is intentionally modal. They must use
  `.allowsHitTesting(false)` so toolbar, sidebar, and tab clicks below the overlay are not
  swallowed by an invisible full-window hit target. Provide explicit close affordances such as
  the close button and Escape instead of making the dim layer a catch-all tap gesture.
- Escape-to-dismiss must be routed at the app/window event layer while one of these panels is
  visible so it works even when the terminal AppKit host is first responder. When no shell
  panel is visible, Escape remains terminal input.

**Correct**:

```swift
panel.becomesKeyOnlyIfNeeded = true
panel.orderFrontRegardless()

notificationWindow?.orderOut(nil)
restoreMainWindowFocus()

Color.black.opacity(0.12)
    .ignoresSafeArea()
    .allowsHitTesting(false)

if event.keyCode == 53, model.dismissVisibleShellPanel() {
    return nil
}
```

**Wrong**:

```swift
panel.makeKeyAndOrderFront(nil)
notificationWindow?.orderOut(nil)

Color.black.opacity(0.12)
    .ignoresSafeArea()
    .onTapGesture { model.hideSettingsPanel() }
```

### Scenario: Terminal Notification Read Acknowledgement

#### 1. Scope / Trigger

- Trigger: A terminal notification, bell, or agent event is shown in the notification center,
  sidebar, workspace tab, or terminal tab unread badge.
- Scope: User acknowledgement of terminal-scoped notifications across AppKit terminal hosts,
  SwiftUI tabs/sidebar, pane focus commands, and notification jumps.

#### 2. Signatures

- `TerminalSurface.onFocusRequest: (TerminalID) -> Void`
- `TerminalSurface.onUserActivity: (TerminalID) -> Void`
- `ConductorWindowModel.focusTerminal(_ terminalID: TerminalID)`
- `ConductorWindowModel.recordTerminalUserActivity(_ terminalID: TerminalID)`
- `ConductorWindowModel.markTerminalNotificationsRead(_ terminalID: TerminalID)`

#### 3. Contracts

- Notification records are unread when created by terminal notifications, bells, or agent hooks.
- Opening the notification panel only displays records; it must not mark records read.
- User activation of a terminal marks every unread record for that terminal read. Activation
  includes clicking the terminal host, right-clicking it, dropping text/files into it, selecting
  its tab, focusing its pane, typing into an already-focused host, scrolling it, or jumping from
  a notification row.
- Programmatic surface attachment, geometry refresh, theme refresh, metadata publishing, and
  terminal redraws must not mark notifications read.
- Notification jumps may update read state and focus the terminal, but must not close the
  notification panel unless the user explicitly closes it.

#### 4. Validation & Error Matrix

- Terminal ID no longer exists -> ignore the acknowledgement without mutating notifications.
- Terminal already focused -> still mark unread records for that terminal read.
- No unread records for terminal -> return before copying or publishing notification state.
- Notification panel visible during jump -> keep the panel visible and update row/badge state.

#### 5. Good/Base/Bad Cases

- Good: A notification arrives, the user clicks inside the already-focused terminal, and the
  sidebar/tab badges clear immediately.
- Good: A notification arrives while the terminal is already first responder, the next keypress
  or scroll event clears that terminal's unread state without re-focusing the whole workspace.
- Base: A notification row is clicked; the terminal is focused, its unread records are marked
  read, and the notification panel remains open.
- Bad: `focusTerminal(_:)` returns early for the current pane/tab before clearing unread state.
- Bad: A SwiftUI view refresh, Ghostty geometry sync, or surface reattachment clears unread
  records without direct user terminal activity.

#### 6. Tests Required

- `swift build`
- `swift run ConductorModelCheck`
- Model assertions for `TerminalNotificationState.markTerminalRead(_:)`: unread indexes clear,
  `latestUnread` updates, and repeated reads are idempotent.
- Manual smoke: create a test notification, click an already-focused terminal, type into it,
  scroll it, switch to it from a tab, and jump from the notification panel; each path clears the
  target terminal badge without closing the panel.

#### 7. Wrong vs Correct

##### Wrong

```swift
if workspace.focusedPaneID == paneID,
   workspace.panes[paneID]?.selectedTabID == terminalID {
    return
}
```

##### Correct

```swift
guard let paneID = workspace.paneID(containing: terminalID) else { return }
markTerminalNotificationsRead(terminalID)
if workspace.focusedPaneID == paneID,
   workspace.panes[paneID]?.selectedTabID == terminalID {
    return
}
```

### Convention: Command Discovery Source

**What**: Command Center rows and settings-panel shortcut discovery must be generated from the
same command catalog.

**Why**: Users need the shortcut guide to match the real command surface. Duplicating labels,
sections, shortcut glyphs, disabled states, or command actions across views makes the guide drift
from Command Center and breaks keyboard-first workflows.

**Contract**:

- Keep app-level commands in a single MainActor command catalog near the command UI unless the
  catalog becomes large enough to deserve its own file.
- Command Center may include executable actions and state-aware disabled reasons; shortcut
  discovery should project the same command records into lightweight display rows.
- Exclude debug-only commands from user-facing shortcut discovery.
- Do not route terminal output, scrollback, cursor state, or per-cell rendering through the
  command catalog. It may read only compact shell/product state from the window model.

**Correct**:

```swift
private var commands: [CommandPaletteItem] {
    ConductorCommandCatalog.items(model: model, run: run)
}

private var shortcutRows: [CommandShortcutGuideItem] {
    ConductorCommandCatalog.shortcutGuideItems(model: model)
}
```

### Convention: Shell Command Routing

**What**: Menu items, keyboard shortcuts, toolbar buttons, terminal context menus, and future
touch/gesture affordances should route user actions through `ConductorShellCommand` and
`ConductorWindowModel.performCommand`.

**Why**: The same user intent should have one enablement check, one action implementation, and
one performance signpost. Splitting direct `ConductorWindowModel` method calls across menus,
toolbar buttons, and context menus creates drift: a command can appear enabled in one surface,
be disabled in another, or miss lifecycle cleanup and performance tracing.

**Contract**:

- Add shell-level actions to `ConductorShellCommand` first, with `canPerform(model:)` and
  `perform(model:window:)`.
- UI surfaces should ask `model.canPerformCommand(...)` for disabled state and call
  `model.performCommand(..., window:)` for execution.
- Commands may read compact product state such as selected workspace, focused pane, tab
  metadata, visible panels, notifications, and search visibility.
- Commands must not route terminal output, scrollback, cursor movement, or raw renderer state
  through SwiftUI-observed state.
- Keep command dispatch on the main actor. Heavy work triggered by a command must hop to the
  appropriate runtime/background layer after the shell state transition is recorded.
- Keep `ConductorSignpost` coverage at the command boundary so sluggish menu, shortcut,
  toolbar, and context-menu actions can be compared in Instruments.
- Native `NSMenu` context-menu controllers must be retained through the menu item's lifetime
  and released only after menu tracking has fully unwound. Use a dedicated controller/action
  registry, attach the controller to each item's `representedObject`, and delay final cleanup
  from `menuDidClose`; otherwise the menu can visually open but selectors may miss their target.

**Correct**:

```swift
guard model.canPerformCommand(.closeFocusedPane) else { return }
model.performCommand(.closeFocusedPane, window: window)
```

**Wrong**:

```swift
guard model.canCloseFocusedPane else { return }
model.closePane(model.workspace.focusedPaneID)
```

### Convention: Terminal Context Search

**What**: The floating terminal search surface is shell chrome for one live Ghostty terminal.
It may hold a compact query string and target terminal ID, but search execution and result
navigation belong to the terminal surface/runtime.

**Why**: Search must feel like a native terminal find bar without moving terminal scrollback or
match text into SwiftUI. Keyboard handling should be immediate and predictable while the live
terminal host is not first responder.

**Contract**:

- Opening search with `Cmd-F` should target the currently focused terminal and focus the search
  input after the surface enters the view tree.
- The search input must preserve normal macOS text editing commands such as `Cmd-A`.
- While the search input is focused, `Return` and Down navigate to the next result, Shift-Return
  and Up navigate to the previous result, and Escape closes search.
- Closing search must call the terminal runtime's end-search action and restore first responder
  to the searched terminal host when it still exists.
- Do not promote search matches, scrollback snippets, or result text into SwiftUI state. Store
  only compact metadata such as active state, query, total count, selected index, and target ID.

### Convention: Settings Panel Navigation

**What**: Settings surfaces with three or more product areas should use a compact sidebar
classifier and a single detail pane instead of stacking every section in one scroll column.

**Why**: The settings surface is a long-lived shell tool, not a landing page. A categorized
sidebar keeps the panel scannable as appearance, command, terminal, integration, and advanced
settings grow, while preserving a stable right-side detail area.

**Contract**:

- Keep the selected settings category as local SwiftUI state unless multiple shell regions need
  to observe it.
- Keep category changes low-frequency and route them through shared shell motion helpers when
  animation is appropriate.
- The sidebar should use compact rows with icons, labels, and restrained selected fills. Avoid
  high-contrast alternating blocks, heavy shadows, or large explanatory cards.
- Settings sidebars should reuse the main sidebar's surface language through the dedicated
  settings glass styling and theme-owned settings strokes/fills. Do not use accent-tinted
  outlines or large two-line rows for category navigation.
- When a settings panel floats over the dark terminal canvas, add a sidebar-background underlay
  inside the glass surface so the panel matches the main sidebar instead of becoming a gray,
  low-contrast blur over terminal content.
- The detail pane may scroll, but each category should own a focused set of controls. Do not
  reintroduce a single mixed list of unrelated settings inside the detail pane.
- Settings categories may read compact product state such as appearance preferences, command
  records, and theme metadata. They must not observe terminal output, scrollback, cursor state,
  or runtime renderer details.

**Correct**:

```swift
@State private var selectedSection: SettingsPanelSection = .interface

HStack(spacing: 0) {
    settingsSidebar
    settingsDetailPane(for: selectedSection)
}
```

---

## Accessibility

SwiftUI controls should expose labels, selected state, unread state, and keyboard navigation. AppKit terminal host placeholders should not confuse the accessibility tree; expose accessibility through the real interactive surface or explicit app chrome.

Do not steal focus from the active terminal when a notification arrives. Notification UI may indicate attention, but focus changes require explicit user action.

---

## Common Mistakes

Forbidden patterns:

- Rendering terminal output with SwiftUI `Text`, `List`, or `LazyVStack`.
- Using transcript length as SwiftUI state.
- Recreating terminal host views during tab selection, split resize, or workspace switching.
- Passing a whole app store into terminal pane leaf views.
- Rendering repeated tab/list title content directly from a broad observed model. Workspace
  rows, workspace tabs, and terminal tabs should feed title text, badges, and status glyphs
  through compact `Equatable` content views. Action wrappers may still hold closures or model
  references, but selected-tab and selected-workspace changes should only redraw the previous
  and next selected chrome, not every visible title label.
- Running expensive metadata probes from `body`.
- Routing terminal context-menu actions through whatever pane or tab is focused after the
  menu closes. A terminal context menu must capture the right-clicked terminal ID, re-resolve
  the current workspace/pane/tab target when an item is chosen, and execute target-specific
  model methods. Focus may be synchronized first, but it must not be the only source of truth
  for destructive actions such as close tab, close pane, close workspace, or duplicate tab.
- Adding or removing tab chrome on hover. Workspace and terminal tabs should reserve stable
  slots for close/status controls; hover may change color, stroke, or opacity, but must not
  insert new content, change padding, or shift titles.
- Letting tab editing state use a different layout contract from normal state. Rename fields
  inside workspace or terminal tabs must fill the same fixed tab content area as labels do;
  do not leave `NSTextField`/`TextField` at intrinsic or minimum width inside a fixed tab.
- Relying only on `controlTextDidEndEditing` for inline rename commit. SwiftUI buttons and
  row taps may not reliably resign an embedded `NSTextField`, so inline rename bridges must
  explicitly commit when the user clicks outside the field, while Escape still cancels and
  Return still commits. Parent navigation actions such as selecting another workspace,
  creating a workspace, closing a workspace, or running a toolbar/sidebar command must also
  finish any active workspace rename before they mutate selection or layout.
- Keeping close affordances active inside an inline terminal rename field. While a tab title is
  being edited, reserve the full tab content area for the rename field and avoid adjacent close
  controls that can be hit accidentally during text selection or IME composition.
- Letting dense workspace or terminal tab strips free-scroll to arbitrary pixel offsets.
  Overflow handling should use native scrolling with view-aligned tab targets or another
  complete-item mechanism so the strip keeps trackpad/mouse-wheel scrolling, never rests
  with a clipped title or a lone close button at the edge, and never changes the toolbar/pane
  height when item count changes.
- Hiding overflow affordances on scrollable navigation. Workspace, sidebar, and terminal tab
  scroll regions should expose scroll indicators when content can overflow, and selected items
  should be scrolled into view after creation, selection, or restoration.
- Putting native horizontal scrollbars inside dense 21-25px tab strips. On macOS, the scrollbar
  can participate in the tiny strip's layout and make tabs look vertically clipped or offset
  when many items exist. Workspace and terminal tab strips should keep a fixed-height scroll
  viewport, avoid native indicators inside that viewport, provide stable edge fades or external
  overflow controls, and scroll selected tabs toward the center instead of pinning them against
  fixed command buttons.
- Letting scrollable tab strips compress fixed toolbar commands. In the main toolbar, command
  groups keep their icon+label affordances and fixed horizontal size; the workspace tab strip is
  the flexible/scrollable region that absorbs narrow-window pressure.
- Allowing sidebar intrinsic height to vertically reposition the terminal workbench. The root
  shell row must be top-aligned, and the sidebar must own its own height/scroll behavior so
  adding workspaces, notifications, or actions cannot move the terminal canvas.
- Making the entire sidebar one scroll view. Workspace overflow should be isolated to the
  workspace list region; status summaries, quick actions, theme, and settings remain stable
  so a long workspace list does not drag a heavy scrollbar through unrelated controls.
- Collapsing the sidebar narrower than the macOS traffic-light cluster. In a full-size-content
  window, the standard close/minimize/zoom controls still occupy the top-left titlebar area;
  collapsed sidebar width and header clearance must keep those controls visually inside the
  sidebar instead of letting them float over the terminal canvas. Collapsed sidebar header
  controls should align to the same centered rail axis as workspace and action icons, not keep
  the expanded sidebar's trailing alignment. Avoid narrow decorative capsules behind traffic
  lights because native button geometry can drift from them; use a full-width titlebar wash
  clipped by the sidebar shape instead. If the sidebar must remain a floating card with outer
  margins, hide the standard `NSWindow` traffic lights and provide stable custom window-control
  buttons inside the sidebar rather than moving the whole panel to the window edge.
- Guessing at root shell spacing when the window titlebar is involved. First measure
  `NSWindow.contentLayoutRect`, `contentView.safeAreaInsets`, and the root hosted view frame,
  then keep `ConductorTokens.Space.shellTop` as the compact titlebar clearance rather than
  compensating with negative padding.
- Repeatedly forcing terminal host layout/refresh from `NSViewRepresentable.updateNSView`.
  SwiftUI can call this for unrelated metadata changes, so live terminal hosts should coalesce
  post-layout geometry syncs and let AppKit `layout`, `setFrameSize`, and `setBoundsSize`
  drive resize-sensitive Ghostty updates.
- Letting an auxiliary `NSPanel` steal key focus from the main window without restoring it
  after hide. Notification-style panels should not require a second click on the main window
  just to make toolbar/sidebar controls responsive again.
- Using a full-window hit-testing dim layer behind in-window shell panels. It makes the first
  click after opening settings, command center, or workspace overview dismiss the overlay
  instead of activating the control the user clicked, which feels like the app stopped
  accepting clicks.
- Relying only on SwiftUI `.onExitCommand` for shell panels while the terminal host can remain
  first responder. Escape may go to Ghostty/AppKit instead of the panel unless the app event
  layer consumes it only while a shell panel is visible.
