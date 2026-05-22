# High Performance Terminal Roadmap

> Source of truth for the project's architecture route.

This project is a native macOS multi-terminal manager inspired by cmux, but with a stricter performance and UI ownership boundary around the product shell. It should support the same class of developer workflows: workspaces, vertical tabs, split panes, notifications, agent status, command palette, browser/tool surfaces, and scriptable automation. Performance is the primary product constraint.

## Core Architecture

Use this ownership model:

```text
SwiftUI Shell
- Workspaces, vertical tabs, sidebars, split layout chrome
- Command palette, settings, notifications, agent status
- Compact metadata: title, cwd, git branch, ports, unread count, last notification

AppKit Bridge
- NSWindow, NSResponder, focus routing, keyboard routing
- Drag/drop, split resize, menu commands, portal/host views
- Stable NSViewRepresentable anchors for SwiftUI integration

GhosttyKit / libghostty Surface
- PTY lifecycle, VT parsing, terminal state, scrollback, modes
- Terminal character rendering, cursor, selection, glyph shaping, Metal presentation
- Surface input APIs for keyboard, paste, mouse, scroll, and automation text

Future Custom Renderer Path
- Ghostty VT/render-state APIs feeding our own AppKit/Metal renderer if needed
- Deferred until the surface route proves insufficient for product or performance goals
```

## Non-Negotiable Boundary

SwiftUI may own the application shell. SwiftUI must not render terminal scrollback or transcript text.

For the first validation and MVP, terminal semantics and terminal character rendering belong to GhosttyKit/libghostty. The SwiftUI layer should embed or anchor a stable AppKit host view and observe only compressed metadata.

## cmux Reference Lessons

Use `/tmp/codex-cmux-reference` as a local reference checkout when studying Ghostty integration. Important files:

- `/tmp/codex-cmux-reference/Sources/GhosttyTerminalView.swift`
- `/tmp/codex-cmux-reference/Sources/TerminalWindowPortal.swift`
- `/tmp/codex-cmux-reference/Sources/Panels/TerminalPanel.swift`
- `/tmp/codex-cmux-reference/Sources/Panels/TerminalPanelView.swift`

Study, do not copy blindly. cmux uses Ghostty's macOS surface renderer, which is now the MVP validation route for terminal character rendering. The reusable lessons are:

- Initialize one Ghostty app runtime, then create one live surface per terminal pane.
- Create Ghostty surfaces only when the host AppKit view has a real window and backing scale.
- Keep terminal NSView identity stable across SwiftUI updates, split changes, tab moves, and workspace switches.
- Avoid tearing down the runtime surface during transient SwiftUI rebuilds.
- Update content scale, display id, and pixel size only when they actually change.
- Route real keyboard input through AppKit responder/text-input APIs, including `NSTextInputClient` for IME preedit and committed text.
- Keep notification rings, search overlays, and inactive pane overlays in AppKit-adjacent overlay views when they need to track terminal geometry.

For lower-level details, also read `.trellis/spec/backend/ghosttykit-integration.md`.

The deeper custom-renderer option should study `/tmp/codex-ghostty-reference/include/ghostty/vt.h` and `/tmp/codex-ghostty-reference/include/ghostty/vt/render.h`, but it is no longer the first implementation target.

## Performance Rules

Do not put long transcript text in `@State`, `@Published`, `@Observable`, `ObservableObject`, or SwiftUI view identity.

Do not trigger whole-window SwiftUI invalidation from stdout chunks, PTY reads, cursor movement, terminal redraws, or scrollback growth.

Treat module isolation and bounded rendering as T0 correctness requirements. Terminal panes,
file manager panels, document previews, workspace chrome, settings, and tab strips must not
drive each other's focus, search scope, renderer lifetime, or layout by accident. A feature
that makes another module re-render broadly, captures shortcuts while another module has
focus, or scales tab/file operations with the whole window is a release-blocking bug.

Throttle UI metadata updates. Sidebar rows and badges should update from snapshots at a controlled cadence, normally no faster than 10-30 Hz.

Run parsing, polling, git probes, port scans, agent hook processing, and transcript summarization off the main thread. The main thread receives small immutable snapshots.

Keep terminal surface creation, focus changes, and resize calls deduplicated. Repeated `set_focus`, `set_size`, or layout synchronization can cause visible stalls.

## Feature Targets

The product should include:

- Workspaces with vertical tabs and surface/pane metadata.
- Split panes with stable terminal surfaces during reparenting.
- Notification rings, unread badges, notification center, and jump-to-unread.
- Agent-friendly hooks and explicit notifications, including OSC-style terminal notifications where supported.
- Scriptable control surface for creating workspaces, splitting panes, sending input, focusing panes, and opening browser/tool views.
- Built-in browser/tool panes through WebKit where needed, isolated from terminal rendering.
- Keyboard-first command palette and configurable shortcuts.

## Verification Expectations

Every implementation touching terminal or shell performance should verify:

- Long output does not increase SwiftUI diff cost linearly with transcript length.
- Workspace switch does not recreate terminal runtime or renderer state unnecessarily.
- Split resize does not repeatedly allocate drawing resources when pixel size is unchanged.
- Several active agent sessions can produce output while sidebar metadata remains responsive.
- Main-thread work is bounded and observable with Instruments or signposts before release.

## Current Product Decision

The project is SwiftUI-first for product UI, AppKit-first for native macOS integration, and GhosttyKit/libghostty-surface-first for terminal character rendering. Any proposal that moves terminal scrollback or high-frequency rendering into per-cell SwiftUI conflicts with this route.

This does not mean embedding the standalone Ghostty app. It means hosting GhosttyKit/libghostty's macOS terminal surface inside our own SwiftUI/AppKit product UI, the same broad integration direction cmux proves. A custom terminal renderer using Ghostty's VT/render-state APIs remains a later option if the surface route cannot meet our product or performance requirements.
