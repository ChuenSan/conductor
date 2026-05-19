# Ghostty/libghostty Integration

> Rules for using Ghostty/libghostty in this project.

## Positioning

Do not embed the standalone Ghostty app. For the first validation and MVP, do use GhosttyKit/libghostty's macOS surface renderer for the live terminal character area. The product UI around it remains ours.

The intended split is:

```text
Our UI: SwiftUI + AppKit workspaces, tabs, splits, notifications, command palette, automation
Our host layer: stable AppKit terminal host views, focus routing, resize routing, overlays
GhosttyKit/libghostty: PTY, VT parsing, terminal state, scrollback, cursor, selection, glyph shaping, Metal terminal rendering
```

## cmux Reference

Study `/tmp/codex-cmux-reference` when implementing this layer. The most relevant files are:

- `cmux-Bridging-Header.h`
- `ghostty.h`
- `Sources/GhosttyTerminalView.swift`
- `Sources/TerminalWindowPortal.swift`
- `Sources/WorkspaceSurfaceConfig.swift`
- `Sources/TerminalController.swift`

Use cmux as an integration reference, not as a UI template. cmux uses Ghostty's macOS surface renderer, and that rendering approach is the first route to validate.

Also keep the Ghostty VT API checkout available for the deferred custom-renderer path:

- `/tmp/codex-ghostty-reference/include/ghostty/vt.h`
- `/tmp/codex-ghostty-reference/include/ghostty/vt/terminal.h`
- `/tmp/codex-ghostty-reference/include/ghostty/vt/render.h`
- `/tmp/codex-ghostty-reference/include/ghostty/vt/screen.h`

## App Runtime

Using the cmux surface API route, create one app-level Ghostty runtime:

- Call `ghostty_init` once.
- Load Ghostty config through `ghostty_config_new` and default/recursive config loaders.
- Create `ghostty_runtime_config_s`.
- Provide callbacks for wakeups, actions, clipboard, and close requests.
- Create the app with `ghostty_app_new`.
- Coalesce wakeups before calling `ghostty_app_tick`.
- Mirror macOS app active/inactive state into `ghostty_app_set_focus`.

Fallback config is required for the surface route. A broken user Ghostty config should not prevent this app from launching terminals.

For the deferred custom renderer path, study `libghostty-vt`:

- `ghostty_terminal_new` creates terminal state.
- `ghostty_terminal_vt_write` feeds raw PTY bytes into the terminal parser/state machine.
- `ghostty_terminal_resize` updates cell and pixel dimensions.
- `ghostty_render_state_new` creates render state for our renderer.
- `ghostty_render_state_update` pulls dirty render data from the terminal.
- `ghostty_render_state_row_iterator_*` and `ghostty_render_state_row_cells_*` expose rows/cells.
- `ghostty_cell_get`, `ghostty_row_get`, and style/color APIs expose per-cell data.

The VT headers warn that the API is incomplete and unstable. Treat this as a managed dependency risk.

## Surface Runtime

For the MVP surface path, create one `ghostty_surface_t` per terminal pane. Only create `ghostty_surface_t` after the AppKit view is attached to a real `NSWindow`.

The owner should hold:

- Workspace ID
- Terminal ID
- Pane ID
- `ghostty_surface_t?`
- Stable AppKit terminal host view
- Lifecycle state
- Last cell dimensions and pixel dimensions
- Pending input queue for automation before the surface is ready

For macOS surfaces:

- Set `platform_tag = GHOSTTY_PLATFORM_MACOS`.
- Set the platform `nsview` pointer to the real terminal `NSView`.
- Set retained callback userdata that can resolve back to the surface owner.
- Set display id, content scale, and pixel size immediately after creation.
- Force an initial refresh after creation.

## Target Rendering

The terminal character area should initially be GhosttyKit/libghostty's surface renderer hosted in our stable AppKit view. It must not be a per-cell SwiftUI hierarchy.

The deferred custom-renderer path may use `GhosttyRenderState` to obtain dirty rows, cells, colors, cursor state, graphemes, wide-cell state, and style IDs. That path is research material until the surface route is proven insufficient.

Important render-state APIs:

- `ghostty_render_state_update`
- `ghostty_render_state_get`
- `ghostty_render_state_get_multi`
- `ghostty_render_state_colors_get`
- `ghostty_render_state_row_iterator_new`
- `ghostty_render_state_row_iterator_next`
- `ghostty_render_state_row_get`
- `ghostty_render_state_row_cells_new`
- `ghostty_render_state_row_cells_next`
- `ghostty_render_state_row_cells_get`
- `ghostty_cell_get`
- `ghostty_row_get`

cmux's `GhosttyNSView`/`CAMetalLayer` surface path is the first implementation pattern to validate.

Custom overlays are allowed and expected:

- Notification ring
- Inactive-pane overlay
- Search UI
- Drop target overlay
- Flash/attention overlay
- Keyboard/copy mode badges

Overlays that must track terminal geometry should live in the same renderer/host coordinate system, not in a separate SwiftUI hierarchy that can drift during resize.

Ghostty open-url actions are a shell integration boundary. Remote URLs may fall through to
`NSWorkspace.open`, but local `file://` URLs must first be routed through app-owned preview,
reveal, or error UI. Do not pass arbitrary local file URLs directly to LaunchServices from the
terminal action callback; it can produce system alerts such as `-50` and breaks the intended
right-side preview workflow.

Current implementation contract:

- `GhosttyAppRuntime.openURL(_:terminalID:)` asks `GhosttyAppRuntimeActionDelegate` first.
- `ConductorWindowModel.ghosttyRuntimeDidRequestOpenURL(terminalID:url:)` must return `true`
  for every local file URL, including missing files, so the runtime fallback never shows a
  system alert for terminal-originated file paths.
- Existing directories open in Finder; existing files become `ToolPreviewItem`s in the
  app-owned right-side preview panel; missing files surface as compact Conductor
  notifications when a terminal can be resolved.
- Right-side file previews are product metadata/tool UI. They must not inspect terminal
  scrollback or make terminal transcript text observable by SwiftUI.

## SwiftUI Bridge

SwiftUI should see a stable terminal host component, not the terminal transcript or per-cell model.

Start with a simple `NSViewRepresentable` only if it keeps AppKit identity stable across split and tab operations. If SwiftUI reparenting causes renderer recreation, black frames, lost focus, or geometry drift, move to a cmux-style portal:

```text
SwiftUI placeholder anchor
-> window-level AppKit portal
-> real custom terminal renderer view
```

Do not free terminal state or renderer resources during transient SwiftUI dismantle. Free only on actual pane close or app teardown.

## Scenario: Surface Geometry And Navigation Refresh

### 1. Scope / Trigger

- Trigger: Any change that affects a live Ghostty surface's AppKit host view frame, backing scale, display, focus, selected tab, selected pane, workspace switch, split drag, or notification jump.
- Scope: Keep Ghostty's Metal drawable geometry aligned with the real `NSView` without letting SwiftUI animation or repeated representable updates fight the renderer.

### 2. Signatures

- `TerminalHostView.setFrameSize(_:)`
- `TerminalHostView.setBoundsSize(_:)`
- `TerminalHostView.layout()`
- `TerminalSurfaceContainerView.setSurface(_:theme:focused:)`
- `TerminalSurface.syncGeometry(force:)`
- `TerminalSurface.setFocused(_:force:)`
- `ConductorWindowModel.focusTerminal(_:)`

### 3. Contracts

- The AppKit host view bounds are the source of truth for Ghostty pixel size.
- Host/container layers used for Ghostty surfaces must disable implicit CoreAnimation `bounds`, `frame`, `position`, `contentsScale`, and `backgroundColor` animations.
- `syncGeometry(force:)` must set content scale, display id, and backing pixel size only when changed or forced, then refresh the surface when geometry changed.
- Focus changes must call Ghostty focus and refresh the surface.
- SwiftUI `updateNSView` may schedule one coalesced post-layout sync, but must not force repeated layout/refresh loops on every SwiftUI update.
- A pure split-fraction drag is not a terminal surface identity, theme, or focus change.
  Existing `NSView` layout callbacks should drive deduplicated geometry sync for those frames;
  `updateNSView` must not call immediate `layoutSubtreeIfNeeded` just because SwiftUI rebuilt
  the representable during divider movement.
- Split-divider drags must update split fractions inside a non-animated transaction.
- Notification jumps or programmatic terminal navigation must focus the owning pane, select the tab, then force a current-run-loop and next-run-loop geometry refresh for the target surface if it already exists.
- Terminal close must detach the AppKit host view from its superview, clear pending input
  buffers and app callback closures, nil the host view's weak surface link, free the
  `ghostty_surface_t`, release retained Ghostty userdata exactly once, and leave the method
  idempotent for pane close, tab close, workspace close, app quit, and failed initialization.

### 4. Validation & Error Matrix

- Surface receives stale pixel size after split drag -> text can clip, disappear, or draw into old rows.
- SwiftUI layout animation wraps the live terminal host -> split resize can lag behind the pointer or show ghost frames.
- Repeated forced refreshes from `updateNSView` -> tab switching and resize feel sticky under many panes/tabs.
- Navigation selects a tab without focusing its pane -> first responder and Ghostty focus can disagree after notification jump.
- Close leaves host view installed in an AppKit container -> Instruments can show short-lived
  view retention after terminal close, and a stale terminal frame can remain visible until the
  next SwiftUI update.

### 5. Good/Base/Bad Cases

- Good: Dragging a divider changes AppKit bounds immediately; Ghostty receives deduped pixel sizes and refreshes only on actual geometry changes.
- Base: Selecting a terminal tab swaps one stable host view and schedules a single post-layout sync.
- Bad: `updateNSView` calls `layoutSubtreeIfNeeded`, `syncGeometry(force: true)`, and `refresh()` several times for every unrelated SwiftUI metadata update.
- Bad: `TerminalSurface.close()` frees Ghostty but waits for SwiftUI teardown to detach the
  host view and callbacks.

### 6. Tests Required

- `swift build`
- `ConductorModelCheck`
- Focus automation must verify first-responder routing across tabs and panes.
- Layout automation must verify split resize clamps/equalizes while keeping workspace invariants.
- Manual smoke: jump from a notification into a terminal with existing output; text should remain visible, and divider dragging should not animate or flicker.

### 7. Wrong vs Correct

#### Wrong

```swift
func updateNSView(_ view: TerminalSurfaceContainerView, context: Context) {
    view.layoutSubtreeIfNeeded()
    surface.syncGeometry(force: true)
    surface.refresh()
    DispatchQueue.main.async { surface.refresh() }
}
```

#### Correct

```swift
override func layout() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    super.layout()
    CATransaction.commit()
    surface?.syncGeometry()
}
```

## Input

For the MVP surface path, use Ghostty surface input APIs:

- `ghostty_surface_key` for key press/release and control keys.
- `ghostty_surface_text` for bulk text, paste, drops, and automation text.
- `ghostty_surface_preedit` for IME marked/preedit text from AppKit.
- `ghostty_surface_ime_point` for the input-method candidate window position.
- `ghostty_surface_mouse_pos` for pointer movement.
- `ghostty_surface_mouse_button` for mouse buttons.
- `ghostty_surface_mouse_scroll` for wheel events.
- `ghostty_surface_key_is_binding` to distinguish Ghostty-owned bindings from app/menu shortcuts before forwarding command-modified events.
- `ghostty_surface_binding_action` for built-in terminal actions such as copy, paste, search, and scroll commands.

For automation, split input into text chunks and control-key events. Newline, tab, escape, and delete should be sent as key events when terminal semantics require it.

The terminal host view must participate in AppKit text input. Use `NSTextInputClient`/`interpretKeyEvents` for IME and dead-key composition, then forward committed text through Ghostty key/text APIs. Do not replace terminal line editing in Swift. Chinese/Japanese/Korean preedit belongs in AppKit plus Ghostty preedit, while shell editing remains inside Ghostty/PTY.

## Action Callbacks / Events

For cmux-style surface hosting, route Ghostty actions into our product model:

- New tab / new window -> focused-pane terminal tab creation in our tab model
- Move tab / goto tab -> our tab ordering and selection model
- New split -> our split system
- Focus split -> our focus model
- Resize split -> our layout model
- Toggle command palette -> our command palette state
- Desktop notification -> our notification store
- Bell -> our attention system
- Config/color changes -> our theme/runtime config layer
- Child process exit -> our panel lifecycle
- Scrollbar/cell-size/search updates -> our terminal host metadata

For the deferred custom VT path, implement equivalent app events from terminal callbacks/options and our input/control layer: title changes, bell, write-pty responses, size reports, device attributes, focus, mouse, and notifications/OSC parsing.

Callbacks can arrive during teardown. They must resolve by IDs and lifecycle state before touching UI, terminal handles, or renderer resources. Do not carry native owner objects across asynchronous callback boundaries: copy stable values such as `TerminalID`, strings, counts, booleans, and directions synchronously, then resolve current model state on `MainActor`.

## Scenario: Ghostty Action Bridge Contract

### 1. Scope / Trigger

- Trigger: Any `ghostty_action_s` emitted by `ghostty_runtime_config_s.action_cb`.
- Scope: Translate Ghostty-owned keybindings into Conductor-owned workspace state without
  letting terminal bindings mutate SwiftUI views directly.

### 2. Signatures

- Runtime delegate:
  - `ghosttyRuntimeDidRequestNewTab(terminalID:) -> Bool`
  - `ghosttyRuntimeDidRequestMoveTab(terminalID:amount:) -> Bool`
  - `ghosttyRuntimeDidRequestSelectTab(terminalID:offset:last:) -> Bool`
  - `ghosttyRuntimeDidRequestSplit(terminalID:direction:) -> Bool`
  - `ghosttyRuntimeDidRequestFocus(terminalID:direction:) -> Bool`
  - `ghosttyRuntimeDidRequestResize(terminalID:direction:amount:) -> Bool`
  - `ghosttyRuntimeDidRequestEqualize(terminalID:) -> Bool`
  - `ghosttyRuntimeDidRequestToggleZoom(terminalID:) -> Bool`
  - `ghosttyRuntimeDidSetTitle(terminalID:title:) -> Bool`
  - `ghosttyRuntimeDidSetWorkingDirectory(terminalID:workingDirectory:) -> Bool`
  - `ghosttyRuntimeDidReceiveNotification(terminalID:title:body:) -> Bool`
  - `ghosttyRuntimeDidRingBell(terminalID:) -> Bool`
  - `ghosttyRuntimeDidUpdateProgress(terminalID:kind:progress:) -> Bool`
  - `ghosttyRuntimeDidFinishCommand(terminalID:exitCode:durationNanoseconds:) -> Bool`
  - `ghosttyRuntimeDidUpdateCellSize(terminalID:width:height:) -> Bool`
  - `ghosttyRuntimeDidUpdateSearch(terminalID:active:needle:total:selected:) -> Bool`
  - `ghosttyRuntimeDidSetReadonly(terminalID:readonly:) -> Bool`
  - `ghosttyRuntimeDidRequestClose(terminalID:) -> Bool`
  - `ghosttyRuntimeDidRequestCloseTabs(terminalID:scope:) -> Bool`
  - `ghosttyRuntimeDidRequestCommandPalette(terminalID:) -> Bool`

### 3. Contracts

- Request identity: resolve `ghostty_target_s.target.surface` to `TerminalSurface`, then
  use only `TerminalID` across the SwiftUI boundary.
- Model lookup: the delegate must resolve `TerminalID -> PaneID` before mutating layout.
- UI mutation: route through `WorkspaceState` and `ConductorWindowModel`; do not mutate
  SwiftUI view structs or AppKit host subviews from the callback.
- Hook identity: every Ghostty surface should expose a stable `CONDUCTOR_TERMINAL_ID`
  environment variable to its child shell. Agent hooks such as Codex Stop hooks use this ID
  to report compact lifecycle notifications back to Conductor without scanning terminal
  output or depending on the focused pane at delivery time.
- Threading: callback may be non-main; schedule model work onto `MainActor`.
- Async payloads: do not capture `TerminalSurface`, `GhosttyAppRuntime`, or native callback
  userdata into `Task` closures. Resolve the target synchronously and pass value payloads.
- Return value: return `true` only for actions Conductor intentionally owns or bridges.

### 4. Validation & Error Matrix

- Unknown target tag -> log debug and return `false`.
- Surface cannot resolve to `TerminalSurface` -> return `false`.
- Terminal ID no longer exists in workspace -> return `false`.
- Action would violate command availability -> return `false` or no-op through the model.
- Unsupported action tag -> log debug, return `false`, and do not mutate state.

### 5. Good/Base/Bad Cases

- Good: Ghostty `NEW_SPLIT` from focused terminal creates a Conductor split and focuses it.
- Good: Ghostty `NEW_TAB` or `NEW_WINDOW` creates a new terminal tab in the source pane.
- Good: Ghostty `MOVE_TAB` and `GOTO_TAB` operate on the source pane's tab model.
- Good: Ghostty `CLOSE_TAB` respects this/other/right close modes.
- Good: Ghostty `PWD`, notification, progress, command finished, search, and readonly
  actions update compact metadata only.
- Good: Ghostty `OPEN_URL` opens through the host OS and does not enter SwiftUI state.
- Startup-sensitive actions such as `CELL_SIZE`, `COLOR_CHANGE`, `CONFIG_CHANGE`, and
  `RING_BELL` require a dedicated lifecycle test before returning `true`; treating them as
  handled during surface startup can terminate the Ghostty runtime.
- Base: Ghostty `SET_TITLE` updates compact tab metadata only.
- Bad: reading `terminal.id` inside an async `Task` after resolving a
  `TerminalSurface` from `ghostty_surface_userdata`; the surface may be freed first.
- Bad: Handling a Ghostty binding by creating/destroying SwiftUI views directly.

### 6. Tests Required

- Model checks for tab move, tab select, cross-pane moves, split/focus/resize, close, and
  invalid command availability.
- Smoke automation for creating tabs/splits, moving tabs across panes, moving a tab into
  a new split, zooming, closing, and clean process exit.
- Shortcut automation for `NSWindow.performKeyEquivalent` covering app shortcuts and
  Ghostty-owned action callbacks without crashing or changing persisted user state.
- Manual QA for Ghostty-native keybindings because actual user config may decide which
  `ghostty_action_s` is emitted.

### 7. Wrong vs Correct

#### Wrong

Forward `Cmd-D` or `Cmd-T` exclusively through app-level shortcuts and ignore Ghostty's
action callback. This breaks user Ghostty keybindings when `ghostty_surface_key_is_binding`
correctly claims the event.

#### Correct

Let Ghostty-owned bindings reach Ghostty, then bridge resulting `ghostty_action_s` values
back into Conductor's workspace model by terminal ID.

#### Wrong

```swift
let terminal = TerminalSurface.fromGhosttySurface(target.target.surface)
Task { @MainActor in
    _ = actionDelegate?.ghosttyRuntimeDidRequestNewTab(terminalID: terminal.id)
}
```

#### Correct

```swift
guard let terminalID = TerminalSurface.fromGhosttySurface(target.target.surface)?.id else { return false }
Task { @MainActor in
    _ = actionDelegate?.ghosttyRuntimeDidRequestNewTab(terminalID: terminalID)
}
```

## Lifecycle Safety

Always:

- Deduplicate focus, size, scale, and display-id calls.
- Validate native handle ownership before dereferencing `ghostty_surface_t` or any future `GhosttyTerminal`/`GhosttyRenderState` handles.
- Clear the Swift pointer before async free paths can race with queued closures.
- Retain callback userdata until native surface free completes.
- Treat close/free as idempotent.

Never:

- Store raw terminal output in SwiftUI state.
- Recreate terminal state/render state for ordinary UI changes.
- Create Ghostty surfaces while the host view has no window.
- Block the main thread with metadata probes or output parsing.

## Product Decision

Our first implementation should target a custom SwiftUI/AppKit shell plus GhosttyKit/libghostty's macOS surface renderer for the terminal character area. The deeper custom terminal renderer driven by Ghostty's VT/render-state APIs remains a future option if the surface route is too constrained or too slow for production.
