# Conductor Product Foundation Roadmap

This roadmap is intentionally careful. The goal is not to quickly stack features. The
goal is to build a dependable terminal workspace that feels calm, direct, and fast after
hours of real use.

## Product Principles

- The terminal is the primary working surface and should occupy most of the window.
- Conductor is not a chat UI. There is no composer around terminal panes.
- Product chrome should be compact, predictable, and keyboard-friendly.
- GhosttyKit owns terminal behavior and rendering for the current product route.
- SwiftUI owns product structure and compact metadata only.
- Every foundation feature needs a model contract, UI behavior, lifecycle behavior, and
  regression check.

## Epic 1: Workspace / Pane / Tab Model

### Tasks

- Define complete value-model operations for tabs: create, select, close, move left,
  move right, move to pane, move to new pane.
- Define complete value-model operations for panes: split right, split down, close,
  focus adjacent, equalize, zoom, collapse.
- Add command availability APIs so UI can ask whether an operation is currently valid.
- Keep IDs stable and never allow dangling selected/focused IDs.
- Store enough split-tree metadata to support draggable dividers and persistence later.

### Acceptance

- Model checks cover every operation and edge case.
- UI code does not mutate split trees manually.
- Every UI command maps to one model operation.

## Epic 2: Stable Terminal Surface Hosting

### Tasks

- Fix selected-tab host swapping so selected tabs show the correct Ghostty surface.
- Keep one `TerminalSurface` per `TerminalID`.
- Free surfaces only on real tab/pane/workspace close.
- Separate visible attachment from lifecycle ownership.
- Add lifecycle logs for create, attach, become visible, become hidden, focus, resize,
  close, free.
- Evaluate whether SwiftUI representables remain stable enough; if not, implement a
  cmux-style portal host.

### Acceptance

- Tab switching preserves independent terminal sessions.
- Split changes do not recreate unrelated terminal surfaces.
- Focus and keyboard input always target the visible active terminal.

## Epic 3: Production Split Experience

### Tasks

- Implement draggable split dividers.
- Clamp pane sizes to a usable terminal minimum.
- Add split equalize.
- Add split zoom/unzoom.
- Add close-pane and collapse-parent behavior.
- Add adjacent-pane focus movement.
- Add visual focus treatment that is clear but not noisy.

### Acceptance

- Repeated split commands cannot destroy the workspace layout.
- Users can recover from complex layouts without restarting the app.
- Pane resize remains smooth while terminals are active.

## Epic 4: Terminal Tab Experience

### Tasks

- Add close affordance.
- Add keyboard shortcuts for new tab, close tab, next tab, previous tab.
- Add tab reorder by drag.
- Add tab overflow behavior when many tabs exist.
- Add stable tab sizing and text truncation.
- Add optional dirty/running/bell indicators later.

### Acceptance

- Tabs behave like a high-quality browser tab strip for terminal sessions.
- Large tab counts remain usable and do not make clicks feel heavy.

## Epic 5: Ghostty Action Bridge

### Tasks

- Study cmux action handling before implementing each action family.
- Bridge Ghostty `new split` actions into our split model.
- Bridge Ghostty `focus split` actions into our focus model.
- Bridge Ghostty `resize split`, `equalize splits`, and `toggle split zoom`.
- Bridge stable compact events such as desktop notification, progress, close request,
  and child process exit into product state.
- Defer bell and other startup-sensitive Ghostty actions until lifecycle validation proves
  Conductor can claim them without destabilizing surface startup.
- Keep Ghostty-owned bindings working without letting hidden terminals consume app commands.

### Acceptance

- Ghostty shortcuts that imply pane behavior operate on Conductor's layout model.
- App shortcuts and terminal shortcuts are routed intentionally and consistently.

## Epic 6: Input, IME, Mouse, and Clipboard Quality

### Tasks

- Verify typed input, paste, bracketed paste, Ctrl keys, Option keys, Command bindings,
  dead keys, and Chinese/Japanese/Korean IME.
- Verify mouse selection, right click, alternate screen mouse reporting, and scroll.
- Add focused regression scripts where possible and human QA notes where necessary.
- Ensure hidden tabs do not receive accidental keyboard/mouse input.

### Acceptance

- A normal developer can use shells, editors, TUIs, SSH, and REPLs without surprises.
- IME candidate windows appear at the correct terminal cursor location.

## Epic 7: Performance Discipline

### Tasks

- Add signposts or structured logs for tab switch, split create, split resize, surface
  attach, and metadata publish.
- Measure long output with multiple active panes.
- Keep metadata publication bounded to compact snapshots.
- Avoid full-window SwiftUI invalidation for per-pane changes.
- Add stress scenarios: many tabs, many panes, long output, rapid switching, resize while output streams.

### Acceptance

- Long output does not make UI chrome slower as transcript length grows.
- SwiftUI state never contains transcript, scrollback, ANSI, or cell-grid data.

## Epic 8: Product Chrome and Command System

### Tasks

- Build command palette entries for every tab/pane action.
- Add menu bar commands and keyboard shortcuts.
- Add sidebar/workspace chrome only where it supports real workflow.
- Keep terminal canvas dominant.
- Add settings for theme, font size, shell command, working directory, keybindings route,
  and split defaults.

### Acceptance

- Common workflows are keyboard-first.
- Controls are discoverable without cluttering the terminal workspace.

## Epic 9: macOS 2026 Appearance System

### Tasks

- Build a compact Settings / Appearance Center that opens from the sidebar settings
  affordance.
- Treat themes as whole-shell presets: backdrop, terminal chrome, terminal background,
  accent color, and Ghostty config move together.
- Add refined live previews for each theme so switching feels inspectable, not blind.
- Add appearance controls for density, chrome clarity, font scale, and motion once the
  first theme center is stable.
- Keep decorative glass out of the live terminal character surface.

### Acceptance

- Theme changes are visibly composed across the full window, not just the terminal palette.
- The settings surface is polished, compact, and does not steal focus unless explicitly opened.
- Appearance state remains low-frequency SwiftUI product state.

## Epic 10: Workspace Overview and Navigation

### Tasks

- Add a Mission Control-style workspace overview for many workspaces.
- Show compact metadata for pane count, tab count, unread state, current cwd, and active agent status.
- Support keyboard search, direct jump, and jump-to-unread from the overview.
- Keep overview thumbnails abstract or metadata-driven until terminal surface snapshotting is
  explicitly designed.

### Acceptance

- Users with many workspaces can navigate quickly without relying only on a long sidebar.
- Overview does not recreate or snapshot live terminal renderers accidentally.

## Epic 11: Command Center and Shortcut System

### Tasks

- Evolve the command palette into a command center with grouped commands, recent actions,
  availability states, and lightweight context.
- Add shortcut discovery and eventually editable keybindings.
- Keep commands routed through stable model/service APIs.

### Acceptance

- Conductor remains keyboard-first as feature depth increases.
- Every command is discoverable without adding clutter around the terminal.

## Epic 12: Agent-Aware Chrome and Automation

### Tasks

- Add agent status modules for sessions that opt into compact lifecycle notifications.
- Add notification jump and follow-up affordances for long-running tasks.
- Add scriptable automation for workspace, tab, split, input, browser/tool panes, and focus.
- Keep terminal transcripts and full agent conversations out of SwiftUI state.

### Acceptance

- Agent activity is visible and actionable without turning the product into a chat UI.
- Automation uses stable service contracts and cannot mutate view internals directly.

## Epic 13: Persistence and Recovery

### Tasks

- Persist workspace layout, tabs, working directories, and theme.
- Decide what session restoration means for live processes versus new shells.
- Add crash-safe state writes.
- Add startup recovery behavior.

### Acceptance

- Restarting Conductor restores the workspace structure without corrupting terminal state.

## Epic 14: Release-Quality Verification

### Tasks

- Build a repeatable smoke suite for app launch, tab operations, split operations, and clean exit.
- Add manual QA checklist for terminal input and IME.
- Add performance capture checklist for long-output runs.
- Keep prototype validation archived separately from production verification.

### Acceptance

- A release candidate must pass build checks, model checks, smoke checks, and manual
  terminal-interaction QA before adding higher-level agent features.
