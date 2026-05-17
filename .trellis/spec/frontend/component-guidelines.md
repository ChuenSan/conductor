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
  clipped by the sidebar shape instead. The sidebar panel should start at the window origin in
  full-size-content windows so the default `NSWindow` traffic-light inset lands inside the
  panel rather than exactly on the panel's rounded edge.
- Guessing at root shell spacing when the window titlebar is involved. First measure
  `NSWindow.contentLayoutRect`, `contentView.safeAreaInsets`, and the root hosted view frame,
  then keep `ConductorTokens.Space.shellTop` as the compact titlebar clearance rather than
  compensating with negative padding.
- Repeatedly forcing terminal host layout/refresh from `NSViewRepresentable.updateNSView`.
  SwiftUI can call this for unrelated metadata changes, so live terminal hosts should coalesce
  post-layout geometry syncs and let AppKit `layout`, `setFrameSize`, and `setBoundsSize`
  drive resize-sensitive Ghostty updates.
