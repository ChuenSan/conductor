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
- Letting scrollable tab strips compress fixed toolbar commands. In the main toolbar, command
  groups keep their icon+label affordances and fixed horizontal size; the workspace tab strip is
  the flexible/scrollable region that absorbs narrow-window pressure.
- Allowing sidebar intrinsic height to vertically reposition the terminal workbench. The root
  shell row must be top-aligned, and the sidebar must own its own height/scroll behavior so
  adding workspaces, notifications, or actions cannot move the terminal canvas.
- Guessing at root shell spacing when the window titlebar is involved. First measure
  `NSWindow.contentLayoutRect`, `contentView.safeAreaInsets`, and the root hosted view frame,
  then keep `ConductorTokens.Space.shellTop` as the compact titlebar clearance rather than
  compensating with negative padding.
