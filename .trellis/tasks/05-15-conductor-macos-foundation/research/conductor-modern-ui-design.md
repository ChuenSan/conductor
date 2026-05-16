# Conductor Modern UI Direction

## Product Posture

Conductor should feel like a modern native macOS production tool whose center of gravity is the live terminal, not the surrounding chrome.

The shell should borrow the quietness and material discipline of Craft/Codex-style macOS apps, but the density should be closer to a professional terminal workspace:

- Terminal surfaces occupy the dominant visual area.
- Navigation is present but lightweight, secondary, and collapsible.
- Every persistent control has a clear job and a stable location.
- Notifications, agent status, and unread state appear as compact edge signals instead of large panels.
- SwiftUI chrome remains metadata-only. GhosttyKit/AppKit owns terminal rendering.

## What Is Wrong In The Current UI

The current UI is functional but does not yet look like a mature product:

- The top chrome reads too wide and too heavy for a terminal-first app.
- Sidebar rows and action rows compete with the terminal instead of acting as a quiet workspace inspector.
- Workspace switching is split between a sidebar and dropdown-like controls; workspaces should be visible as compact top tabs.
- Pane tab chrome is inconsistent and visually noisy when many splits exist.
- Split gutters and pane boundaries do not always communicate layout hierarchy cleanly.
- Status, counts, current pane, and actions are scattered rather than expressed through one compact status language.
- Button labels/icons are sometimes unclear, and icon-only controls lack enough adjacent context.

## Target Layout

### Window Shell

- Window background: soft neutral translucent shell.
- Top toolbar: 30 px visual height maximum, including workspace tabs and global actions.
- Outer margin: 6 px on normal windows, 4 px in compact mode.
- Terminal stage starts immediately under the toolbar.
- No bottom command composer or oversized input area.

### Sidebar

The sidebar is a floating inspector card, not a full-height heavy navigation wall.

- Default width: 176 px.
- Compact width: 52 px icon rail.
- Top inset: 8 px.
- Corner radius: 14 px.
- Background: light material with subtle stroke.
- Content:
  - product identity
  - workspace list summary
  - compact metrics
  - command shortcuts
  - theme/status footer
- It can collapse without changing terminal surface identity.

### Workspace Tabs

Workspaces belong across the top, like browser tabs.

- Height: 26 px.
- Selected workspace pill: 22 px tall.
- Workspace row sits in the toolbar, left of global actions.
- Supports rename, close, reorder, unread badge, and agent state.
- Sidebar workspace list remains a secondary overview, not the primary switcher.

### Terminal Stage

The terminal stage should feel edge-to-edge.

- Stage background: near-black terminal plane.
- Inset from shell: 3 px.
- Pane radius: 5 px only at outer stage corners.
- Split gutter: 4 px neutral light gutter for AppKit/SwiftUI hit testing.
- Focus ring: 1 px accent line, drawn outside the Ghostty surface.
- No decorative card shadows around terminal panes.

### Pane Tabs

Pane tabs are compact surface labels, not large cards.

- Rail height: 24 px.
- Selected terminal tab: 20 px pill.
- Inactive terminal tab: text/icon only with hover fill.
- Close affordance appears on hover or selected state.
- Dirty/unread/agent state uses a tiny dot or 2-digit badge.
- The tab rail must not consume more vertical space than a single terminal text row.

### Right Utility Panel

Notifications, agent feed, browser tools, and future file previews should use one right-side utility drawer.

- Default width: 320 px.
- Overlay/docked hybrid: transient overlay by default, dockable later.
- It should never force terminal surfaces to recreate.
- It contains compact sections: Notifications, Agents, Feed, Tools.

## Design Tokens

### Color

| Token | Value | Purpose |
| --- | --- | --- |
| `shell.bg` | `#F6F7F9` | main window shell |
| `shell.material` | `rgba(255,255,255,0.72)` | floating panels and toolbar groups |
| `shell.materialStrong` | `rgba(255,255,255,0.86)` | selected workspace/sidebar rows |
| `shell.stroke` | `rgba(31,35,43,0.09)` | low-contrast borders |
| `shell.strokeStrong` | `rgba(31,35,43,0.15)` | active outlines |
| `text.primary` | `#20242D` | primary chrome text |
| `text.secondary` | `#606776` | metadata |
| `text.tertiary` | `#8D95A3` | placeholder/inactive |
| `accent.blue` | `#1677FF` | current selection and workspace |
| `accent.violet` | `#735CFF` | focused pane and agent activity |
| `accent.amber` | `#D97706` | attention/waiting |
| `accent.green` | `#22A06B` | success/completed |
| `danger.red` | `#E5484D` | destructive/error |
| `terminal.bg` | `#090B0F` | terminal surface background |
| `terminal.chrome` | `#11141A` | pane tab rail |
| `terminal.chromeElevated` | `#1B2029` | selected terminal tab |
| `terminal.text` | `#D8DEE9` | terminal chrome labels only |
| `terminal.muted` | `#798196` | terminal metadata |
| `split.gutter` | `#E7E9EE` | split divider/hit target |

### Spacing

| Token | Value |
| --- | --- |
| `space.windowInset` | 6 |
| `space.stageInset` | 3 |
| `space.toolbarHeight` | 30 |
| `space.toolbarGap` | 6 |
| `space.sidebarWidth` | 176 |
| `space.sidebarCompactWidth` | 52 |
| `space.sidebarInset` | 10 |
| `space.workspaceTabHeight` | 22 |
| `space.paneTabRailHeight` | 24 |
| `space.paneTabHeight` | 20 |
| `space.splitGutter` | 4 |
| `space.statusHeight` | 14 |

### Radius

| Token | Value |
| --- | --- |
| `radius.window` | 18 |
| `radius.sidebar` | 14 |
| `radius.controlGroup` | 10 |
| `radius.control` | 8 |
| `radius.workspaceTab` | 9 |
| `radius.terminalStage` | 6 |
| `radius.paneTab` | 6 |
| `radius.badge` | 5 |

### Typography

| Token | Value |
| --- | --- |
| `type.brand` | 13 / semibold |
| `type.toolbar` | 11 / medium |
| `type.workspace` | 12 / medium |
| `type.workspaceSelected` | 12 / semibold |
| `type.sidebarSection` | 10 / semibold |
| `type.sidebarRow` | 11.5 / medium |
| `type.paneTab` | 10.5 / medium |
| `type.status` | 10 / regular |

### Motion

| Token | Value |
| --- | --- |
| `motion.fast` | 100 ms |
| `motion.normal` | 160 ms |
| `motion.slow` | 220 ms |
| `motion.curve` | ease-out |

Motion should be used for chrome, not terminal content.

## Component Rules

### Toolbar

- Left side: sidebar toggle, workspace tab strip.
- Right side: new terminal, new tab, split actions, command palette, notification drawer.
- Use compact labels for core actions (`New`, `Tab`, `Right`, `Down`, `Command`) when space allows.
- Collapse to icon-only only in narrow widths, with tooltips.

### Sidebar

- Treat as an inspector:
  - Workspace overview.
  - Counts: panes, terminals, unread, active agent.
  - Quick actions.
  - Theme/status footer.
- It should not push the stage around with a visually heavy wall.

### Workspace Tab

- Selected state: strong material fill, blue leading icon or blue underline.
- Hover: subtle fill only.
- Unread: small badge at trailing edge.
- Agent running: violet pulse dot.
- Rename: inline editor commits on Return, Escape cancel, blur commit.

### Terminal Pane

- Pane chrome is inside the stage but outside the Ghostty surface.
- Only pane metadata enters SwiftUI: title, cwd, unread count, agent state, focus.
- The Ghostty host view must remain stable across split, tab, rename, sidebar collapse, and utility panel toggles.

### Notifications

- Notification button shows unread count.
- Notification drawer rows show source workspace, terminal title, timestamp, and one-line message.
- Clicking a notification focuses workspace, pane, and terminal, then marks it read.
- Agent notifications use the same drawer and the same pane badge language.

## Implementation Order

1. Update `ConductorTokens` to the token names and values above.
2. Replace the current top workspace selector with a true compact workspace tab strip.
3. Rework the floating sidebar to be an inspector card with collapse behavior and quieter rows.
4. Redraw pane tabs and split gutters using fixed heights and stable hit targets.
5. Unify notification/agent state into badges and a right utility drawer.
6. Add visual regression screenshots for:
   - one pane
   - three vertical panes
   - mixed vertical/horizontal split
   - collapsed sidebar
   - notification drawer open

## Static Mock

Prototype:

- V1: `Prototypes/ConductorModernUIDesign/index.html`
- V2: `Prototypes/ConductorModernUIDesign/v2.html`
- V3: `Prototypes/ConductorModernUIDesign/v3.html`

The mock is intentionally static. It defines the visual language before the SwiftUI implementation changes the live app.

## V2 Revision

The first mock was still too close to the current implementation. V2 intentionally changes the spatial model:

- The terminal stage fills the whole window underneath the chrome.
- Sidebar, toolbar, workspace tabs, utility drawer, and status line are floating overlays.
- The sidebar becomes a true inspector card rather than a layout column.
- The toolbar no longer owns a permanent horizontal band above the terminal.
- The pane tab rail becomes glassy in-pane chrome with a 23 px height.
- The terminal area visually begins at the outer window margin, making the app feel like a terminal product instead of a document product.

## V3 Revision

V2 made the chrome modern, but it overlaid the sidebar on top of the terminal, which weakened the spatial model. V3 keeps the modern density but separates the sidebar from the terminal stage:

- Sidebar is a standalone floating panel in its own left column.
- Terminal stage starts to the right of the sidebar, with a clear 10 px separation gap.
- Top workspace tabs and actions belong to the terminal area, not the whole window.
- The terminal stage still receives almost all remaining space.
- Utility drawer can overlay the terminal temporarily, but persistent navigation should not.

## V5 Revision

V5 explored a more distinct "terminal cockpit" structure:

- Replace the full sidebar with a narrow left rail.
- Move workspace tabs and global actions into a dark terminal-top cockpit bar.
- Use a floating workspace detail card for quick actions.
- Use a compact activity panel for notifications and agent events.

The direction is useful because it breaks away from the current sidebar-heavy layout, but it should not be used directly:

- It reads too much like a concept mock or AI-generated dashboard.
- The floating workspace card and activity panel add visual noise over the terminal.
- The top and outer margins are too large for a terminal-first app.
- Strong shadows, gradients, blue primary buttons, and oversized rounded controls make the UI feel less durable for daily use.

Keep from V5: narrow rail, cockpit-style workspace strip, terminal-first surface.
Discard from V5: decorative floating cards, large margins, strong glow/shadow treatment, and overtly "AI assistant" visual language.

## V6 Revision

V6 keeps the V5 structural idea but makes it more product-like and compact:

- Default state is a 46 px icon rail, preserving maximum terminal width.
- The rail can expand to a 214 px sidebar for workspace names, status, and quick actions.
- Outer margin drops to 6 px and the cockpit bar drops to 32 px.
- The decorative floating workspace card is removed.
- Shadows, gradients, and saturated primary buttons are reduced.
- The expanded sidebar should be a persistent layout mode, not a hover-only overlay, so the UI stays stable.
- Window traffic lights live inside the left rail/sidebar. This lets the right terminal
  workbench start at the top window margin instead of reserving a full titlebar-height
  strip above the terminal.

Prototype:

- `Prototypes/ConductorModernUIDesign/v6.html`

## V7 Revision

V7 is the current preferred direction for a product-grade terminal-first shell:

- Remove the product-logo/header treatment from the sidebar. Conductor should feel like a
  native terminal workspace, not a SaaS dashboard.
- Keep the traffic lights inside the left navigator so the terminal workbench can hug the
  top and bottom window bounds.
- Make the sidebar an explicit navigator/inspector that can collapse by user action. Do not
  reveal controls by hover or change row geometry on hover.
- Keep workspace tabs across the top of the terminal workbench, but make them compact and
  stable with reserved close/count slots.
- Group global actions into small control clusters so the right side does not read as a
  long button toolbar.
- Darken split gutters. Pane boundaries should be readable, but the terminal text should
  remain visually dominant.
- Replace the floating activity card with a narrow notification handle. Notifications can
  expand on demand, but should not cover the terminal by default.
- Rename overtly AI-flavored chrome to neutral product language such as automatic naming,
  notification center, and command palette.

Prototype:

- `Prototypes/ConductorModernUIDesign/v7.html`
