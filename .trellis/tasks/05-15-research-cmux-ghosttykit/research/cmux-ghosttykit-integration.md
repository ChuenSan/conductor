# cmux GhosttyKit Integration Research

## Executive Summary

cmux does not embed the standalone Ghostty.app. It links `GhosttyKit.xcframework` and imports Ghostty's C API into Swift. cmux builds its own macOS product UI in SwiftUI/AppKit, then hands the live terminal character area to a custom `NSView` whose backing layer is a `CAMetalLayer` used by libghostty.

That means cmux's approach is:

```text
Custom cmux UI
-> SwiftUI/AppKit shell, tabs, sidebar, splits, notifications
-> custom AppKit terminal host views
-> GhosttyKit/libghostty owns PTY, ANSI, scrollback, glyph shaping, selection, Metal rendering
```

For our project, this confirms the first implementation route: do not embed Ghostty.app, build our own product UI, and host GhosttyKit/libghostty's macOS surface for the live terminal character area.

After checking Ghostty's source, there is also a deeper API family at `include/ghostty/vt.h`, especially `terminal.h`, `render.h`, and `screen.h`. Those headers expose terminal state and render-state/cell traversal for custom renderers. They are marked incomplete and unstable, so this path is deferred until the Ghostty surface route proves insufficient.

## Evidence From cmux

Important local reference files:

- `/tmp/codex-cmux-reference/cmux-Bridging-Header.h`
- `/tmp/codex-cmux-reference/ghostty.h`
- `/tmp/codex-cmux-reference/GhosttyTabs.xcodeproj/project.pbxproj`
- `/tmp/codex-cmux-reference/Sources/GhosttyTerminalView.swift`
- `/tmp/codex-cmux-reference/Sources/TerminalWindowPortal.swift`
- `/tmp/codex-cmux-reference/Sources/WorkspaceSurfaceConfig.swift`
- `/tmp/codex-cmux-reference/Sources/TerminalController.swift`

`cmux-Bridging-Header.h` imports `GhosttyKit`. `ghostty.h` includes Ghostty's canonical C API header from `ghostty/include/ghostty.h`. The Xcode project links `GhosttyKit.xcframework`.

The public C API pattern in cmux is centered on:

- `ghostty_init`
- `ghostty_config_new`
- `ghostty_config_load_default_files`
- `ghostty_config_load_recursive_files`
- `ghostty_app_new`
- `ghostty_app_tick`
- `ghostty_app_set_focus`
- `ghostty_surface_config_new`
- `ghostty_surface_new`
- `ghostty_surface_set_display_id`
- `ghostty_surface_set_content_scale`
- `ghostty_surface_set_size`
- `ghostty_surface_set_focus`
- `ghostty_surface_key`
- `ghostty_surface_text`
- `ghostty_surface_mouse_pos`
- `ghostty_surface_mouse_button`
- `ghostty_surface_mouse_scroll`
- `ghostty_surface_binding_action`
- `ghostty_surface_update_config`
- `ghostty_surface_free`

## Initialization Flow

cmux initializes one app-level Ghostty runtime:

1. Unsets `NO_COLOR` so TUI apps can use color.
2. Calls `ghostty_init(CommandLine.argc, CommandLine.unsafeArgv)`.
3. Creates a Ghostty config with `ghostty_config_new()`.
4. Loads default/user Ghostty config files.
5. Creates `ghostty_runtime_config_s`.
6. Wires callbacks for wakeups, actions, clipboard read/write, and surface close.
7. Calls `ghostty_app_new(&runtimeConfig, config)`.
8. On failure, falls back to a minimal config and tries `ghostty_app_new` again.
9. On app activation/resignation, calls `ghostty_app_set_focus`.

The wakeup callback does not immediately render in SwiftUI. It coalesces ticks and schedules `ghostty_app_tick(app)` on the main queue.

## Surface Creation Flow

cmux owns one `TerminalSurface` per terminal pane. A `TerminalSurface` owns:

- `ghostty_surface_t?`
- a custom `GhosttyNSView`
- a custom `GhosttySurfaceScrollView`
- workspace/surface IDs
- lifecycle state and portal binding generation
- desired focus state
- pending socket input queue

Surface creation is delayed until the host view is attached to a real window. This is critical because Ghostty needs the macOS view pointer, backing scale, pixel size, and display id.

The creation flow:

1. Create a custom `GhosttyNSView` with a non-zero initial frame.
2. Create `ghostty_surface_config_s` with `ghostty_surface_config_new()`.
3. Set `font_size`, `wait_after_command`, `context`.
4. Set `platform_tag = GHOSTTY_PLATFORM_MACOS`.
5. Set `platform.macos.nsview` to `Unmanaged.passUnretained(view).toOpaque()`.
6. Set retained callback userdata pointing back to the Swift `TerminalSurface`/view context.
7. Add environment variables such as surface ID, workspace ID, socket path, port range, and shell integration flags.
8. Set optional command, working directory, and initial input.
9. Call `ghostty_surface_new(app, &surfaceConfig)`.
10. Register the native surface pointer to guard against stale freed pointers.
11. Set display id.
12. Set content scale.
13. Set pixel size.
14. Re-apply desired focus.
15. Flush queued socket input.
16. Force an initial refresh with `ghostty_surface_refresh`.

## Rendering Ownership

cmux's terminal character area is not SwiftUI-rendered. `GhosttyNSView` is an `NSView` whose `makeBackingLayer()` returns a `CAMetalLayer`. Ghostty receives the `NSView` pointer in the surface config and renders into that view/layer.

This is now the MVP validation target. It gives us Ghostty's mature terminal rendering while keeping the product shell, panes, overlays, metadata, automation, and workflow UI under our control.

cmux customizes the surrounding and overlay UI:

- background host view
- scroll view wrapper
- notification ring overlay
- inactive pane overlay
- flash overlay
- drop zone overlay
- search overlay
- keyboard copy mode badge
- image transfer indicator

Those overlays are AppKit/SwiftUI-owned, but in cmux the terminal glyph grid, scrollback, cursor, selection, ANSI styling, and Metal presentation remain Ghostty-owned. In our MVP architecture, Ghostty should own those terminal-character responsibilities too.

## Input Ownership

cmux translates AppKit events into Ghostty input APIs:

- Key down/up -> `ghostty_input_key_s` -> `ghostty_surface_key`
- Text paste/automation text -> `ghostty_surface_text`
- Mouse position -> `ghostty_surface_mouse_pos`
- Mouse buttons -> `ghostty_surface_mouse_button`
- Scroll wheel -> `ghostty_surface_mouse_scroll`
- Menu/binding actions -> `ghostty_surface_binding_action`

Important detail: for bulk text insertion and drops, cmux prefers `ghostty_surface_text` so bracketed paste mode works and insertion is instant. For special/control keys, it sends key events.

## Action Callback Ownership

Ghostty sends actions back through `runtimeConfig.action_cb`. cmux handles app-level and surface-level actions:

- Reload config
- Config/color changes
- Desktop notifications
- Ring bell
- New split
- Focus split
- Resize split
- Equalize splits
- Toggle split zoom
- Scrollbar updates
- Cell size updates
- Search start/navigation
- Child process exit

This is where Ghostty keybindings can drive custom UI. For example, Ghostty can request `new_split`, but cmux implements the actual split in its own workspace/split model.

## Portal Pattern

cmux discovered that a plain SwiftUI `NSViewRepresentable` is not stable enough during split/tab reparenting. Its solution:

```text
SwiftUI TerminalPanelView
-> GhosttyTerminalView NSViewRepresentable placeholder
-> HostContainerView anchor
-> TerminalWindowPortalRegistry
-> window-level AppKit host view
-> real GhosttySurfaceScrollView / GhosttyNSView
```

The real terminal view lives in a window-level portal and is synchronized to the SwiftUI anchor's geometry. SwiftUI can rebuild the placeholder without destroying the Ghostty surface.

We do not need to start with the full cmux portal if our split/tree implementation keeps AppKit identity stable. But if SwiftUI layout churn causes black frames, stale surfaces, lost focus, or surface recreation, we should adopt the portal pattern early.

## What We Can Customize

Safe to fully customize:

- Workspace model and vertical tabs
- Split layout system
- Sidebar metadata and badges
- Command palette
- Notification center and rings
- Agent status UI
- Browser/tool panes
- Settings
- Automation/socket API
- Shell hooks and metadata pipeline
- Overlay visuals around/above terminal panes

Needs Ghostty APIs or renderer cooperation:

- Terminal glyph rendering
- ANSI parsing
- Scrollback
- Selection
- Cursor
- Font shaping
- IME coordinates
- Mouse reporting to terminal applications
- Bracketed paste behavior
- Alternate screen behavior

## What "Custom Terminal UI" Means

There are two different meanings:

1. Custom product UI around terminal panes: yes, this is the intended route.
2. Custom rendering of terminal cells/glyphs/scrollback using SwiftUI: no, this conflicts with the performance goal.

With the public GhosttyKit surface approach shown by cmux, the terminal content area is effectively Ghostty's renderer. That is the current MVP route. Ghostty also has a separate `libghostty-vt` API that exposes terminal/render-state data for custom renderers; that remains a later research path.

## Recommended Route

MVP architecture:

```text
SwiftUI custom shell
-> AppKit stable Ghostty terminal host
-> GhosttyKit/libghostty surface
-> Ghostty-owned terminal character rendering
```

Avoid copying cmux's whole UI. Borrow these integration mechanisms:

- Terminal owner object per pane.
- Stable AppKit view identity.
- Input translation and PTY write/read discipline.
- Action callback bridge into our split/notification/command systems.
- Deduplicated resize/focus/surface updates.
- Optional portal if SwiftUI reparenting creates renderer/view instability.

## Decision

We should not attempt SwiftUI-rendered terminal scrollback. The high-performance route is custom SwiftUI/AppKit product UI plus GhosttyKit/libghostty's terminal surface for the character area. If that path blocks required UI or performance behavior, revisit the Ghostty VT/render-state custom renderer path.

## Large Text / Lag Lessons

cmux's Ghostty path is careful about high-volume terminal output, but the surrounding app still shows the class of risks we must avoid.

Ghostty surface rendering itself should stay outside SwiftUI. cmux keeps the live `ghostty_surface_t` and terminal view state in AppKit/Ghostty, not in a SwiftUI transcript. `TerminalSurface` exposes small observable pieces such as search state and keyboard copy mode, not the scrollback text.

The strongest anti-lag patterns to preserve:

- Coalesce Ghostty wakeups. cmux's wakeup callback schedules one pending `ghostty_app_tick` instead of ticking directly for every I/O wakeup.
- Coalesce high-frequency UI metadata. cmux's scrollbar callback stores only the newest scrollbar value under a lock and schedules one main-thread flush, because callbacks can fire thousands of times per second during commands like `seq 1 100000`.
- Keep automation input bounded. cmux queues pending socket input before surface creation but caps queued bytes around `1_048_576`.
- Send terminal automation through Ghostty APIs, not SwiftUI text views. Bulk text goes through text/key paths and control characters become key events.
- Do not parse or render full agent transcripts in the active terminal shell. cmux has transcript preview parsers elsewhere, and those must stay bounded/off the hot path. One example caps JSON preview loads at 8 MB. Our product should avoid even that work on the visible terminal render path.

For this project, the rule is stricter: long agent conversations must not become observable SwiftUI state. The sidebar may receive compact snapshots such as unread counts, status, latest notification, title, cwd, or progress. It must never receive the full transcript or a value derived by rescanning full scrollback on every output chunk.

## Theme / Color Lessons

cmux does not change terminal colors by embedding Ghostty.app. It feeds Ghostty config into GhosttyKit:

- `ghostty_config_load_string` for inline config such as `macos-background-from-layer`, keybind overrides, and fallback/default appearance.
- theme files under `Resources/ghostty/themes/` with `palette`, `background`, `foreground`, `cursor-color`, `cursor-text`, `selection-background`, and `selection-foreground`.
- `ghostty_app_update_config` and refresh scheduling when app-level config changes.
- `ghostty_surface_set_color_scheme` and color-change callbacks for surface/window background coordination.

The validation prototype follows this direction: the SwiftUI shell owns product colors, while Ghostty receives a terminal palette config string. Runtime theme changes use `ghostty_surface_update_config` on the live surface and then refresh the surface. This proves terminal colors are configurable without custom terminal rendering and without embedding Ghostty.app.
