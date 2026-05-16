# State Management

> How state is managed in this project.

---

## Overview

State is split by frequency and ownership. SwiftUI state may represent user-visible product metadata. Ghostty/AppKit runtime state owns terminal output, scrollback, selection, focus mechanics, and rendering invalidation.

The main rule: terminal output must not drive SwiftUI diffing.

---

## State Categories

Use these categories:

- Product state: workspaces, selected workspace, split tree, sidebar visibility, settings, command palette state.
- Display metadata: title, cwd, git branch, listening ports, agent status, unread count, latest notification summary.
- Runtime state: Ghostty surface pointer, PTY output, scrollback, cursor, selection, Metal layer, WebKit instances.
- Background derived state: git probes, port scans, hook parsing, transcript summaries, health/performance counters.

Only product state and compact display metadata should be observable by SwiftUI.

---

## When to Use Global State

Promote state only when multiple independent UI regions need the same compact value. A sidebar row does not need the terminal transcript; it needs a small display model.

Global state should be segmented by workspace and surface ID so one terminal update does not invalidate the entire app shell.

Persisted product state should be debounced. Split dragging, tab reordering, focus changes,
and theme changes may update observable workspace state rapidly; they must not synchronously
write to disk on every intermediate frame. Flush the latest snapshot during app termination.

---

## Server State

This project may have local automation, browser, or future cloud features, but terminal runtime remains local-first. Treat external data as snapshots that update UI at controlled boundaries.

For runtime metadata extraction:

- Parse output and hooks off the main thread when possible.
- Coalesce frequent events into snapshots.
- Publish snapshots at a bounded cadence, normally 10-30 Hz for visible UI.
- Prefer explicit terminal escape sequences or hooks over scanning complete scrollback.

---

## Common Mistakes

Forbidden patterns:

- Storing complete agent conversations in observable UI state.
- Publishing on every stdout chunk.
- Updating global app state on every cursor movement or terminal redraw.
- Scanning full scrollback to compute sidebar metadata.
- Making SwiftUI view identity depend on runtime counters, transcript length, or output hashes.
