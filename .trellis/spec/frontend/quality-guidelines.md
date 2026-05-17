# Quality Guidelines

> Code quality standards for native macOS UI development.

---

## Overview

Frontend quality is judged by responsiveness under real terminal load. A UI change is not complete if it looks correct with short output but stalls with long agent transcripts or multiple active panes.

---

## Forbidden Patterns

Never:

- Render scrollback or long transcript text in SwiftUI.
- Bind raw terminal output to `@State`, `@Published`, `@Observable`, or `ObservableObject`.
- Do metadata parsing, git probing, port scanning, or transcript summarization inside SwiftUI `body`.
- Recreate Ghostty runtime surfaces for cosmetic UI changes.
- Force layout synchronization repeatedly during split resize unless the geometry actually changed.

---

## Required Patterns

Always:

- Keep terminal surface identity stable across SwiftUI updates.
- Deduplicate resize, focus, content-scale, and display-id updates.
- Use throttled display models for sidebar rows, notification badges, and agent status.
- Keep focus changes explicit and predictable.
- Prefer AppKit overlays for visuals that must track terminal geometry.

---

## Testing Requirements

Tests and verification should scale with risk:

- For ordinary UI chrome, verify layout, keyboard access, and state transitions.
- For terminal-adjacent UI, test workspace switch, split resize, pane move, notification arrival, focus restoration, and long-output responsiveness.
- Resize stress should include active terminal output, not only static split models. The Conductor gate runs a `resize-while-output` route that creates multiple panes, sends large output through Ghostty surfaces, repeatedly resizes/focuses/equalizes splits, and asserts compact workspace invariants without inspecting transcript text.
- For one-off high-volume output checks, run the long-output route with `CONDUCTOR_STRESS_CHARACTERS=<count>` to drive an exact stdout character count through one terminal surface while keeping transcript text out of SwiftUI state.
- For tab/split model changes, include invariant checks that the split tree leaves match the pane dictionary, focused/zoomed panes exist, every pane has a selected tab, and rapid tab switching does not reorder tabs.
- For performance-sensitive changes, capture Instruments or signpost evidence before release.

---

## Code Review Checklist

Review checklist:

- Does this change increase SwiftUI invalidation frequency?
- Does terminal output remain outside SwiftUI state?
- Are display models compact and `Equatable` where useful?
- Does the terminal NSView survive split/tab/workspace changes?
- Are background probes throttled, cancellable, and off the main thread?
- Is the active terminal focus preserved when UI metadata changes?
