# Conductor Motion Language

> Product motion contract for the native macOS terminal shell.

Conductor motion exists to make state changes legible without making the terminal feel
decorative, sluggish, or unstable. The terminal renderer remains owned by GhosttyKit/AppKit.
SwiftUI motion belongs to shell chrome, compact metadata, overlays, and interaction feedback.

## Global Rules

- Never animate `TerminalSurfaceRepresentable`, Ghostty surface opacity, terminal text,
  cursor, scrollback, selection, or high-frequency terminal redraws.
- Never attach broad implicit animations to ancestors of live terminal hosts.
- During pointer drag, layout must track the pointer without SwiftUI animation.
- Animate only low-frequency product state: selection, hover, press, panel visibility,
  sidebar visibility, notifications, badges, tooltip visibility, and drag previews.
- Prefer transform, opacity, fill, stroke, and shadow changes. Avoid layout changes unless the
  interaction is explicitly spatial, such as sidebar width or split creation.
- Text identity should be stable. Do not fade title text during normal workspace/tab selection.
- Every motion token must have a Reduced Motion behavior. Reduced Motion should remove scale,
  blur, bounce, and directional travel; use instant transitions or minimal opacity only.

## Motion Tokens

| Token | Use | Duration | Curve | Reduced Motion |
| --- | --- | ---: | --- | --- |
| `press` | Mouse down/up button response | 30-45ms down, 80-110ms release | ease out | instant |
| `hover` | Local icon/button hover feedback | 40-70ms | ease out | instant |
| `feedback` | Keyboard highlight, counters, tiny chrome-only state feedback | 40-60ms | ease out | instant |
| `selection` | Selected row/tab/category highlight migration | 110-150ms | smooth, very low bounce | instant selected state |
| `selectionGlide` | Local visual selected capsule that moves independently from model switching | 140-165ms | smooth, almost no bounce | instant selected state |
| `navigation` | Workspace/tab destination changes and scroll-to-visible | 120-170ms | smooth, no visible bounce | instant scroll |
| `panel` | Command/settings/overview reveal | 120-160ms | smooth, tiny bounce | opacity or instant |
| `search` | Terminal find bar reveal and result metadata | 90-130ms | smooth | instant |
| `list` | Filtered list row insert/remove | 90-130ms | smooth | opacity or instant |
| `layout` | Split create/close/equalize, sidebar width | 150-220ms | spatial smooth | instant layout |
| `attention` | Notification/badge/focus flash | 130-220ms | one-shot emphasized | opacity only |
| `dragPreview` | Drag hover preview overlays | 60-90ms in/out | ease out | instant |

## Interaction Matrix

### Sidebar Expanded / Collapsed

**Trigger**: `sidebarVisible` changes.

**Animate**:
- Sidebar width.
- Rail icon x-position through the width change.
- Expanded text/content opacity after the width starts moving.
- Collapsed rail action icons opacity after the width settles enough to avoid overlap.

**Do Not Animate**:
- Terminal stage frame through opacity/scale.
- Traffic-light positions independently from the sidebar container.
- Workspace title text during ordinary workspace selection.

**Motion**:
- Width: `layout`, 170-200ms.
- Text reveal: opacity 55-80ms with 35-50ms delay.
- Icon rail reveal: opacity 70ms, no vertical travel.

**Reduced Motion**:
- Width snaps.
- Text/icon content switches instantly.

**Acceptance**:
- No exposed titlebar/backdrop corners when the sidebar touches the top edge.
- Collapsed icons always show instant tooltip on hover.
- Expanding/collapsing does not recreate terminal hosts.

### Sidebar Rail Icon Tooltip

**Trigger**: pointer enters a pure icon-only control.

**Animate**:
- Tooltip opacity and scale from `0.98` to `1`.
- Pointer diamond opacity with the bubble.
- Control hover fill.

**Do Not Animate**:
- Controls with visible text.
- Close/destructive x buttons.
- Disabled controls.

**Motion**:
- Tooltip show: 45-70ms, no intentional delay.
- Tooltip hide: 35-55ms.
- Bubble travel: none, or at most 1px settle.

**Reduced Motion**:
- Tooltip appears/disappears with opacity only or instantly.

**Acceptance**:
- Tooltip is drawn above the full shell and cannot be clipped by the sidebar shape.
- Tooltip text uses localized `L(...)` strings through the caller.
- Hovering a text-labeled button does not show a custom bubble.

### Workspace Sidebar List

**Trigger**: workspace selection, creation, close, rename, unread-count change.

**Animate**:
- Selected row background migration.
- Row insertion/removal opacity plus compact vertical size transition.
- Unread badge one-shot attention when it appears.
- Rename field focus ring, not the row position.

**Do Not Animate**:
- Workspace title text opacity during selection.
- Whole list opacity during workspace switch.
- Row layout on hover.

**Motion**:
- Selection capsule: `selectionGlide`, 140-165ms.
- Insert/remove: `list`, 90-120ms.
- Badge appear: `attention`, 140ms, scale `0.92 -> 1.04 -> 1`.

**Reduced Motion**:
- Selection and badge states switch instantly.

**Acceptance**:
- Fast switching from the sidebar does not make old/new workspace titles flash.
- Double-click rename stays in the same row geometry.
- Closing workspaces never resurrects the old first item.

### Workspace Tab Strip

**Trigger**: selected workspace, tab creation/close/reorder, scroll-to-visible.

**Animate**:
- A stable selected capsule/fill moving between tab bounds.
- Scroll-to-visible toward center with `navigation`.
- New tab opacity/scale `0.988 -> 1`.
- Tab close width collapse only after model removal is resolved.

**Do Not Animate**:
- Title text fade on selection.
- Tab height.
- Command button groups to the right.
- Terminal stage or terminal hosts.

**Motion**:
- Selection capsule: `selectionGlide`, 140-165ms.
- Scroll-to-visible: 130-170ms, no rubber-band.
- Insert/remove: 100-130ms.

**Reduced Motion**:
- Selection/scroll are instant.

**Acceptance**:
- Repeated tab switching never clips a title or leaves a lone close button at the edge.
- Toolbar command groups do not compress when workspace tabs overflow.
- Text remains readable in light and dark themes during selection.

### Terminal Tab Rail

**Trigger**: selected terminal tab, hover, close, new tab, rename, unread badge.

**Animate**:
- Tab hover fill/stroke.
- A local selected capsule/fill that glides between tab bounds.
- New tab opacity/scale.
- Close removal width collapse.
- Badge appear/update one-shot attention.

**Do Not Animate**:
- Terminal title text opacity during tab selection.
- Live terminal surface.
- Close button insertion/removal on hover; close slot must stay stable.

**Motion**:
- Hover: `hover`, 45-70ms.
- Selection capsule: `selectionGlide`, 140-165ms.
- New/close: `list`, 90-130ms.

**Reduced Motion**:
- All tab states switch instantly except optional opacity for insertion.

**Acceptance**:
- Selecting a terminal tab does not create duplicate cursors.
- Closing a tab does not move the pointer target mid-click.
- Rename field shares the exact tab geometry.

### Terminal Tab Drag / Reorder / Split Drop

**Trigger**: internal terminal tab drag starts, moves, hovers, drops, or cancels.

**Animate**:
- Drag ghost lift: opacity plus shadow when drag starts.
- Insertion indicator fade.
- Edge split preview fade.
- Drop settle after release.

**Do Not Animate**:
- Real split layout while pointer is moving.
- Finder/file drags as split previews.
- Ghostty surface identity or opacity.

**Motion**:
- Drag preview in/out: `dragPreview`, 60-90ms.
- Drop settle: `layout`, 90-130ms after mouse-up/drop.
- Reorder indicator follows pointer without animation.

**Reduced Motion**:
- Preview appears instantly, drop layout snaps.

**Acceptance**:
- Internal tab drags show split placeholders only for private in-process tab drags.
- File drags paste/drop path affordance only, never split placeholder.
- Dragging across pane edges offers top/right/bottom/left zones with stable hit areas.

### Split Creation

**Trigger**: split right/down command, drag-to-split drop, workspace-edge split.

**Animate**:
- New pane expands from the target edge.
- Existing pane yields space.
- New pane chrome fades in after geometry starts.

**Do Not Animate**:
- Terminal surface opacity/scale.
- Split fraction during live divider drag.
- Whole workbench opacity.

**Motion**:
- Layout expansion: `layout`, 170-210ms.
- New pane chrome: opacity 70-100ms, delayed 30ms.

**Reduced Motion**:
- Layout snaps; chrome appears instantly.

**Acceptance**:
- Existing terminal does not redraw as a new surface.
- New split direction matches the command/drop direction exactly.
- Two vertical panes plus a later down split remains two stacked on one side and one large on the other when requested.

### Split Close

**Trigger**: close pane command or terminal menu close pane.

**Animate**:
- Surviving sibling expands into the removed pane's space.
- Removed pane chrome fades out quickly.

**Do Not Animate**:
- Re-show surviving pane with fade-in.
- Recreate terminal hosts.
- Re-sort split topology automatically.

**Motion**:
- Removed chrome: opacity 55-80ms.
- Sibling expansion: `layout`, 150-190ms.

**Reduced Motion**:
- Snap.

**Acceptance**:
- Closing one pane never triggers a "new pane appearing" animation in the survivor.
- Cursor count remains correct.
- Terminal content remains stable.

### Split Divider Resize

**Trigger**: divider hover, pointer down, drag, pointer up.

**Animate**:
- Hover line opacity/width.
- Drag active line emphasis.
- Optional 60-90ms settle after mouse-up only.

**Do Not Animate**:
- Divider position while dragging.
- Split fraction updates while dragging.
- Adjacent terminal hosts.

**Motion**:
- Hover: `hover`, 45-70ms.
- Drag: no animation.
- Release settle: optional `micro`, 60-90ms max.

**Reduced Motion**:
- Hover can still change color; no settle.

**Acceptance**:
- Divider never jumps back and forth while dragging.
- Divider color matches theme, not fixed blue in dark themes unless theme says so.
- Drag remains free until real minimum pane sizes.

### Pane Focus

**Trigger**: click pane, keyboard focus navigation, notification jump, terminal activity.

**Animate**:
- Focus border strength.
- Pane tab rail selected intensity.
- Optional one-shot focus flash.

**Do Not Animate**:
- Terminal content.
- Pane opacity.
- Layout.

**Motion**:
- Focus ring: `attention`, 150-190ms one-shot then stable.
- Normal focus style transition: `selection`, 110-140ms.

**Reduced Motion**:
- Direct style change.

**Acceptance**:
- Focus is obvious even with multiple panes.
- Focus flash never loops.
- Focus change marks relevant notifications read only on real user activation.

### Command Center

**Trigger**: command palette visible, search query changes, keyboard selection changes.

**Animate**:
- Panel reveal from toolbar zone: opacity, `y: -4 -> 0`, scale `0.988 -> 1`.
- Filtered rows with compact opacity/scale.
- Selected row highlight movement.

**Do Not Animate**:
- Background dim hit-testing layer.
- Search input focus.
- Terminal host.

**Motion**:
- Panel: `panel`, 120-150ms.
- Row filter: `list`, 90-115ms.
- Keyboard highlight: `feedback`, 40-60ms.

**Reduced Motion**:
- Panel appears instantly or opacity-only.

**Acceptance**:
- Search field is focused immediately after insertion.
- Arrow keys feel immediate.
- Opening the panel never requires a second click to interact.

### Settings Panel

**Trigger**: settings visible, category selected, controls changed.

**Animate**:
- Panel reveal.
- Category selected fill movement.
- Detail pane content opacity/short crossfade per category.
- Toggle/slider press feedback.

**Do Not Animate**:
- Panel identity when theme/language/font changes.
- Settings category sidebar size.
- Whole app layout when editing a setting.

**Motion**:
- Panel: `panel`, 120-150ms.
- Category: `selection`, 110-140ms.
- Detail transition: opacity 70-100ms, no large travel.

**Reduced Motion**:
- Category/detail changes snap.

**Acceptance**:
- Theme change does not reset selected settings category.
- Language change localizes labels without panel re-entry animation.
- Text remains readable in both light and dark themes.

### Workspace Overview

**Trigger**: overview visible, search/filter, workspace hover/select.

**Animate**:
- Panel reveal.
- Workspace cards opacity/scale stagger with very small delay.
- Hover lift/shadow.
- Selection close transition if jumping to a workspace.

**Do Not Animate**:
- Mini terminal content as real output.
- Full shell layout.

**Motion**:
- Panel: `panel`, 130-160ms.
- Cards: `list`, 90-120ms; max stagger 60ms total.
- Hover: `hover`, 45-70ms.

**Reduced Motion**:
- No stagger; cards appear instantly.

**Acceptance**:
- Overview can show many workspaces without visible lag.
- Card hover does not shift neighboring cards.

### Notification Center

**Trigger**: notification arrives, unread changes, notification opened/cleared.

**Animate**:
- New row enters with opacity and small y travel.
- Unread badge one-shot attention.
- Row clear collapses height after opacity out.

**Do Not Animate**:
- Notification jump closing the panel automatically.
- Main window focus theft.
- Terminal content.

**Motion**:
- Row insert: `list`, 100-130ms.
- Badge: `attention`, 130-180ms one-shot.
- Clear: opacity 60ms plus height 90ms.

**Reduced Motion**:
- Row list updates instantly.

**Acceptance**:
- Jumping to a notification keeps notification panel open unless explicitly closed.
- Focusing a terminal marks its notifications read.
- Badge count never jitters layout.

### Terminal Search Bar

**Trigger**: Cmd-F, search target changes, query/result index changes.

**Animate**:
- Search bar reveal from pane tab rail area.
- Result count crossfade.
- Up/down result navigation with tiny directional emphasis.

**Do Not Animate**:
- Terminal scrollback/search match text through SwiftUI.
- Search input first responder.

**Motion**:
- Reveal: `search`, 90-120ms.
- Result counter: `feedback`, 40-60ms.

**Reduced Motion**:
- Bar appears instantly.

**Acceptance**:
- Cmd-A in input selects text.
- Up/down navigate matches while input remains focused.
- Closing search restores terminal focus.

### Toolbar Controls

**Trigger**: hover, press, active state.

**Animate**:
- Pure icon button hover/press.
- Active fill/stroke.
- Tooltip only when no title is visible.

**Do Not Animate**:
- Text-labeled button tooltip bubble.
- Toolbar height.
- Command groups moving due to hover.

**Motion**:
- Hover: `hover`, 45-70ms.
- Press: `press`, 30-45ms down.

**Reduced Motion**:
- Color changes only.

**Acceptance**:
- Toolbar buttons respond instantly.
- Text-labeled buttons never show custom tooltip bubbles.

### Theme / Appearance Changes

**Trigger**: theme, density, clarity, language, shell font, terminal font changes.

**Animate**:
- Shell chrome color crossfade.
- Density-driven shell chrome dimensions when low risk.
- Theme preview selection.

**Do Not Animate**:
- Terminal font size via scale transform.
- Terminal surface opacity.
- Language text replacement through layout travel.

**Motion**:
- Theme crossfade: 100-140ms.
- Density chrome: `layout`, 150-190ms if it does not disturb terminal hosts.

**Reduced Motion**:
- Direct color/density switch.

**Acceptance**:
- White theme makes terminal white and shell readable together.
- Theme switching does not reset settings panel state.
- Existing terminal hosts receive config updates without recreation.

### Context Menus

**Trigger**: right click in terminal, tab, workspace, toolbar menu.

**Animate**:
- Use system `NSMenu` behavior only.

**Do Not Animate**:
- Custom menu reveal.
- Menu item hover through SwiftUI.

**Motion**:
- Native macOS menu.

**Reduced Motion**:
- Native.

**Acceptance**:
- Every menu item operates on captured target, not whatever is focused after menu closes.
- No command is visually enabled if model says it cannot run.

## Implementation Checklist

For every motion implementation, document or verify:

- Event: what state transition triggers it.
- Animated objects: exact view layers that move/fade/scale.
- Non-animated objects: especially terminal hosts and text identities.
- Token: one of the motion tokens above.
- Reduced Motion behavior.
- Acceptance test: how to prove it did not create flicker, re-render, clipping, or lag.

## Anti-Patterns

- `.animation(..., value: model.workspace)` on a large parent.
- Animating selected tab text opacity.
- Animating split fractions during drag.
- Showing tooltip bubbles for text-labeled buttons or close buttons.
- Using fixed accent-blue split lines that ignore theme.
- Recreating terminal host views to achieve a visual transition.
- Adding continuous breathing/pulsing animations for focus or unread state.
