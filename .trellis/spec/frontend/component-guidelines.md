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
- Settings and appearance panels should share the sidebar's glass language: one soft rounded
  shell, quiet internal dividers, sidebar-style category rows, and compact segmented controls.
  Avoid hard split lines, opaque content slabs, and large option cards inside these panels.
- Bind fluid effects only to low-frequency product state such as selection, command palette
  visibility, notification badges, sidebar visibility, and workspace navigation.
- Do not bind glass effects, blur changes, or animated mesh/background effects to stdout,
  scrollback, cursor movement, or terminal redraws.
- Xcode live preview scenarios should use compact preview fixtures. Prefer `PreviewProvider`
  while SwiftPM command-line builds cannot resolve Xcode's `#Preview` macro plugin.

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
- Settings sidebars should reuse the main sidebar's surface language: `ConductorGlassSurface`
  with sidebar styling, `ConductorDesign.selectedFill`, `ConductorDesign.hoverFill`, and
  `ConductorDesign.sidebarStroke`. Do not use accent-tinted outlines or large two-line rows
  for category navigation.
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
- Running expensive metadata probes from `body`.
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
