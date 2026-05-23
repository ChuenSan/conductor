# Conductor

Formal macOS app foundation for the native multi-terminal manager.

This source tree is separate from `Prototypes/GhosttySurfaceValidation`. The prototype
proved the GhosttyKit surface route; this app owns the production module boundaries and
should not import prototype code.

## Build

```bash
./Scripts/prepare-ghosttykit.sh
swift build
swift run ConductorModelCheck
```

For manual validation:

```bash
./Scripts/run-conductor.sh
```

To create a clickable development app bundle:

```bash
./Scripts/build-app-bundle.sh
open .build/Conductor.app
```

Full local gate:

```bash
./Scripts/check-conductor.sh
```

Expected smoke output from the full gate:

```text
status=ok
panes=2
terminals=2
zoomed=false
```

The full gate also runs a long-output stress route. To run just that path:

```bash
./Scripts/stress-conductor.sh
```

Expected stress output:

```text
status=ok
stress=long-output
panes=3
terminals=4
zoomed=false
status=ok
stress=resize-while-output
resized=true
panes=3
terminals=4
surfaces=4
zoomed=false
```

`Vendor/GhosttyKit.xcframework/` is prepared locally and ignored by Git.

## Release Gate

Before expanding beyond the terminal foundation, run the full local gate and then complete
the manual pass in:

```text
.trellis/tasks/05-15-conductor-macos-foundation/validation-checklist.md
```

The automated gate must pass without modifying the user's persisted window state or leaving
behind a running `Conductor` process. Manual release blockers include hidden terminals
receiving input, unrelated Ghostty surfaces being recreated by tab/split operations, or any
terminal transcript/scrollback entering SwiftUI state.

## Boundaries

- `ConductorCore` owns testable workspace, pane, split, and terminal-tab state.
- `Conductor` owns the SwiftUI/AppKit app shell and GhosttyKit integration.
- SwiftUI state must stay compact. It must not store terminal transcript, scrollback,
  cell grids, ANSI state, or raw output buffers.
- Terminal character rendering, PTY behavior, selection, scrollback, IME, and Metal
  presentation are handled through GhosttyKit/libghostty surfaces.
- Workspace layout and theme persist to
  `~/Library/Application Support/Conductor/window-state.json`.
- Launch with `CONDUCTOR_RESET_STATE=1` to discard saved layout and start clean.
- Launch with `CONDUCTOR_DISABLE_PERSISTENCE=1` for validation sessions that must not
  read or write saved user state.

## Current Checks

The local Swift toolchain does not expose `Testing` or `XCTest`, so model assertions live
in `ConductorModelCheck` for now. The check covers tab/pane correctness, close/move
edge cases, rapid tab switching, and complex workspace invariant stress.

```bash
swift run ConductorModelCheck
```

## Smoke Automation

```bash
CONDUCTOR_SMOKE_AUTORUN=1 \
CONDUCTOR_SMOKE_OUTPUT=/tmp/conductor-smoke-ok.txt \
swift run Conductor
cat /tmp/conductor-smoke-ok.txt
```

Smoke automation disables normal persistence by default so test runs do not overwrite
`~/Library/Application Support/Conductor/window-state.json`.

Stress automation uses the same persistence isolation and sends long-output shell commands
through Ghostty surfaces instead of mirroring transcript into SwiftUI.

## Current Shortcuts

- Native menu bar commands mirror the core tab, pane, layout, and recovery actions.
  Invalid commands are disabled from the same model-level availability checks used by
  the toolbar and command palette.
- Ghostty-owned bindings for new tab/window, move tab, goto tab, split, focus split,
  resize split, equalize, zoom, close tab modes, and command palette are bridged back into
  the Conductor workspace model.
- Ghostty compact metadata actions for working directory, desktop notification, progress,
  command finished, search state, readonly state, and open URL are handled without storing
  terminal transcript in SwiftUI.
- Startup-sensitive actions such as cell size, color/config change, and bell are currently
  left to Ghostty until they have a dedicated lifecycle test; claiming them during startup
  can crash the Ghostty surface runtime.
- `Cmd-T`: new terminal tab in the focused pane.
- `Cmd-Shift-T`: new tab in the focused pane.
- `Cmd-K`: command palette.
- `Cmd-W`: close the selected terminal tab.
- `Cmd-Shift-W`: close focused pane.
- `Cmd-D`: split right.
- `Cmd-Shift-D`: split down.
- `Cmd-[` / `Cmd-]`: previous / next tab.
- `Cmd-Z`: toggle focused pane zoom.
- `Cmd-Shift-=`: equalize splits.
- `Cmd-Option-Arrow`: focus adjacent pane.
- `Cmd-Shift-Arrow`: resize focused split.
- `Cmd-Shift-,` / `Cmd-Shift-.`: move selected tab left / right.
- `Cmd-Option-M`: move selected tab to the next pane.
- `Cmd-Option-Shift-M`: move selected tab to a new right split.
- Command palette includes reset workspace for recovering from bad saved layouts.

## Tab and Pane Behavior

- Tabs can be reordered within a pane by drag/drop.
- Tabs can be dragged across panes; dropping on another tab inserts before it, and
  dropping on the strip appends to the end.
- Moving the only tab out of a pane collapses the empty pane instead of leaving a blank
  region.
- Closing the last terminal in the whole workspace creates a replacement shell.
