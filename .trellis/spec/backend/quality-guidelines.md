# Quality Guidelines

> Code quality standards for runtime/platform development.

---

## Overview

Runtime quality is measured by correctness under concurrency, low latency under terminal load, and predictable lifecycle ownership. The terminal manager must stay responsive when several agent sessions stream long output.

---

## Forbidden Patterns

Never:

- Access stale Ghostty surface pointers without lifecycle validation.
- Create Ghostty surfaces before the host view has a real window/backing context.
- Free or recreate terminal surfaces during transient SwiftUI teardown.
- Publish raw output to UI state.
- Do blocking process, git, port, or filesystem probes on the main thread.
- Let automation commands mutate view internals directly.

---

## Required Patterns

Always:

- Model runtime ownership explicitly: workspace ID, surface ID, pane ID, lifecycle state.
- Deduplicate content-scale, size, display-id, visibility, and focus updates.
- Gate main-thread calls to AppKit and Ghostty APIs that require it.
- Coalesce high-frequency events before crossing into UI.
- Keep cleanup idempotent. Close and free paths may be called during app quit, pane close, or failed initialization.

---

## Testing Requirements

Expected verification:

- Surface lifecycle: create, attach, detach, reattach, close, and app quit.
- Resize behavior: split dragging, window resize, display scale change, external monitor move.
- Focus behavior: workspace switch, pane switch, notification arrival, command palette open/close.
- Load behavior: long scrollback, fast stdout, multiple active panes.
- Automation: create workspace, split pane, send input, focus target, open browser/tool view.

Current local check commands:

```bash
cd Apps/Conductor
./Scripts/prepare-ghosttykit.sh
swift build
swift run ConductorModelCheck
```

The local Swift toolchain in this environment does not expose `Testing` or `XCTest`.
For model-level assertions, use a lightweight executable check target such as
`ConductorModelCheck` until a full Xcode/CI test runner is configured.

---

## Code Review Checklist

Review checklist:

- Is runtime state owned by one clear object?
- Are callbacks safe if they arrive after close begins?
- Are main-thread operations bounded?
- Are high-frequency signals throttled or coalesced?
- Is there enough diagnostic logging to debug freezes without logging private transcript content?
