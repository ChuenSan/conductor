# Conductor Foundation Bug Backlog

This backlog captures bugs and quality debt found during the first hands-on run of the
formal Conductor app. These are not polish requests. They are product-foundation issues
that must be fixed before building higher-level agent workflows.

## Quality Bar

- A bug is not done when the UI "looks better once." It is done when the behavior has a
  repeatable check, clear acceptance criteria, and no obvious regression path.
- Terminal panes must stay directly usable. Fixes must not add chat-style input boxes or
  replace shell behavior in Swift.
- Fixes must keep terminal transcript, scrollback, ANSI state, and cell grids out of
  SwiftUI state.
- When a problem touches Ghostty integration, inspect cmux before inventing a new pattern.

## Critical Bugs

### BUG-001: Same-pane tab switching selects chrome but does not swap the visible terminal surface

**Status**: Fixed and covered by model/smoke validation. `TerminalSurfaceContainerView`
now swaps the hosted `TerminalHostView` when the selected `TerminalID` changes while
keeping each `TerminalSurface` alive until real close.

**Observed**: Clicking another tab in the same pane changes the selected tab style, but the
visible Ghostty terminal can remain the previous tab.

**Likely Cause**: `NSViewRepresentable` is initialized with one `TerminalSurface`, but on
SwiftUI update the underlying `NSView` remains the old surface's `TerminalHostView`.

**Required Fix Direction**:

- Make tab selection change the actual hosted AppKit view identity.
- Ensure each `TerminalID` maps to exactly one long-lived `TerminalSurface`.
- Ensure the selected terminal's host view is attached and the previous selected host view
  is no longer visible.
- Avoid destroying the old surface merely because it became inactive.

**Acceptance Criteria**:

- Create five tabs in one pane; each tab can run a distinct command and preserve its own
  output while switching.
- Switching tabs changes both the tab selection and the visible terminal contents.
- Switching tabs does not create duplicate Ghostty surfaces for the same `TerminalID`.
- Switching tabs does not free inactive terminal surfaces.

### BUG-002: Tab clicks feel slow and can trigger too much view/runtime work

**Status**: Partially fixed. Surface host swapping, attach, resize, split, close, and tab
selection now emit point-of-interest signposts. The full gate also runs a long-output
Ghostty surface stress path. Further Instruments validation is still needed before this
is closed.

**Observed**: Clicking tabs feels laggy after several tabs/splits exist.

**Likely Cause**: Pane chrome, split tree, representable updates, focus changes, and
surface attach checks all run through broad SwiftUI invalidation.

**Required Fix Direction**:

- Narrow observable updates so one tab selection does not refresh unrelated panes.
- Add lifecycle logs around tab click -> model update -> visible host swap.
- Avoid repeated `attachIfPossible`, theme config updates, and focus calls when values are unchanged.

**Acceptance Criteria**:

- With at least eight tabs and four panes, switching a tab feels immediate.
- Logs show no new surface allocation for existing tabs.
- Logs show no repeated size/theme/focus calls when state is unchanged.

### BUG-003: Tabs cannot be closed

**Status**: Fixed. Tabs have close affordances, context menu close actions, `Cmd-W`, native
menu commands, and model checks for active, inactive, first/middle/last, only-tab, and
last-tab-in-pane close paths.

**Observed**: The tab strip has no close affordance and no close behavior.

**Required Fix Direction**:

- Add close button or hover close affordance per tab.
- Add model operation for closing a tab.
- If the selected tab closes, focus the nearest surviving tab.
- If the last tab in a pane closes and other panes exist, close the pane and collapse the split tree.
- If it is the last terminal in the workspace, create a replacement shell instead of leaving a blank workspace.
- Free the closed tab's `TerminalSurface` exactly once.

**Acceptance Criteria**:

- Closing inactive, active, first, middle, and last tab behaves predictably.
- Closing a tab frees only that tab's surface.
- Closing the last tab never crashes and never leaves invalid focus IDs.

### BUG-004: Panes cannot be closed

**Status**: Fixed. Panes have UI, menu, and shortcut close paths with split-tree collapse
and surface cleanup through `WorkspaceCloseResult`.

**Observed**: Split panes accumulate and cannot be removed from UI.

**Required Fix Direction**:

- Add pane close command and UI affordance.
- Collapse parent split when a pane closes.
- Close all terminal surfaces owned by the pane.
- Move focus to a neighboring surviving pane.

**Acceptance Criteria**:

- Any pane in a nested split tree can be closed.
- Split tree remains valid and contains no dangling `PaneID`.
- Focus always points to an existing pane.

### BUG-005: Repeated split creates unusably narrow panes and large blank regions

**Status**: Fixed for the current foundation. Split count is capped, split controls are
disabled when unavailable, panes enforce minimum dimensions, and dividers clamp model
fractions.

**Observed**: After repeated splits, panes become extremely narrow vertical strips. Some
regions show large empty whitespace because the current layout has no usable size policy.

**Required Fix Direction**:

- Introduce minimum usable pane sizes.
- Stop creating a split when the focused pane cannot remain usable after splitting.
- Store and honor split fractions in the model.
- Add layout collapse/equalize behavior before allowing unlimited complex trees.

**Acceptance Criteria**:

- Repeated split commands cannot create panes below the minimum usable terminal size.
- The UI explains or disables split actions when a split is not currently possible.
- No large blank layout region appears during ordinary split operations.

### BUG-006: Split layout is not draggable or adjustable

**Status**: Fixed. Horizontal and vertical split dividers update persisted split fractions
with clamping and geometry deduplication at the terminal surface layer.

**Observed**: Split dividers are visual only. Users cannot resize panes.

**Required Fix Direction**:

- Make dividers draggable.
- Update split fractions in `WorkspaceState`.
- Clamp fractions by available size and minimum pane size.
- Avoid resize storms into Ghostty by deduplicating pixel size updates.

**Acceptance Criteria**:

- Users can drag horizontal and vertical split dividers.
- Pane sizes persist while interacting with tabs and focus.
- Ghostty receives size updates only when pixel dimensions actually change.

### BUG-007: Focus state can diverge from AppKit first responder

**Status**: Fixed for known tab/split/close paths. Focus flows from workspace selection to
the visible `TerminalHostView` first responder and then to Ghostty surface focus. Hidden
terminal input still requires human validation.

**Observed Risk**: SwiftUI selection/focus and AppKit first responder can disagree,
especially after tab switches, pane clicks, split creation, and close operations.

**Required Fix Direction**:

- Define one focus authority flow: product model selects pane/tab, AppKit host becomes
  first responder, Ghostty surface focus follows.
- Log focus transitions.
- Avoid focus changes caused by passive metadata updates.

**Acceptance Criteria**:

- Typing always goes to the visually active terminal.
- Closing or switching tabs never leaves keyboard input routed to a hidden terminal.

### BUG-008: Toolbar actions remain enabled when layout cannot safely perform them

**Status**: Fixed. Command availability lives in `WorkspaceState`; toolbar, command
palette, native menus, keyboard handlers, and tab context menus use the same model-level
availability checks.

**Observed**: Split buttons can be spammed until the workspace becomes unusable.

**Required Fix Direction**:

- Add command availability checks for split, close, move, and tab commands.
- Disable controls when the operation would violate model/layout constraints.
- Keep keyboard command availability consistent with toolbar state.

**Acceptance Criteria**:

- UI controls reflect whether an operation is valid.
- Invalid commands are ignored safely in the model layer.

## Required Regression Checks

Extend `ConductorModelCheck` with:

- [done] Close selected tab.
- [done] Close inactive tab.
- [done] Close last tab in pane with other panes present.
- [done] Close only terminal in workspace.
- [done] Close nested pane and collapse split tree.
- [done] Split availability with minimum pane constraints.
- [done] Select tab after close and after split.
- [done] Move/reorder tabs inside a pane.
- [done] Move tabs across panes by drag/drop model path.
- [done] Move the only tab out of a pane and collapse the empty pane.
- [done] Validate command availability for close, move, and split commands.
- [done] Rapid tab switching keeps tab order, focus, and split invariants stable.
- [done] Complex workspace stress keeps pane, tab, focus, zoom, and split-tree IDs valid.

Add a UI smoke check later that launches Conductor, creates tabs/splits, switches tabs,
closes them, and verifies the process exits cleanly.

**Status**: Done for local automation. The smoke route now creates tabs/splits, moves tabs
across panes, moves a tab to a new split, toggles zoom, closes a terminal/pane, verifies
the final smoke output, then the stress route streams long output through multiple
Ghostty surfaces. The full gate confirms no persisted user state was mutated.
