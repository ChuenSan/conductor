# Architecture Notes

Conductor is split into a small core model and a macOS app shell.

## Boundaries

- `ConductorCore` owns testable workspace, pane, split, terminal-tab state, control protocol models, and attention event storage.
- `Conductor` owns SwiftUI/AppKit shell, GhosttyKit integration, web tabs, settings, notifications, updater UI, and the local control server.
- `ConductorCLI` owns the source-built command line entry point for the local control API.
- GhosttyKit/libghostty owns terminal character rendering, PTY behavior, selection, scrollback, IME, and Metal presentation.

## Important Rule

SwiftUI state must stay compact. It should not store terminal transcript, scrollback, cell grids, ANSI state, or raw output buffers.

## Current App Areas

- Shell root and window model
- Terminal panes and tab strip
- Native web workspace
- File manager and preview surfaces
- Usage workbench integration
- Settings and theming
- GitHub Release updater
- Local control socket and CLI routing
- Terminal sidecar snapshots
- In-app attention event store

## State And Runtime

Conductor separates durable state from runtime surfaces:

- `window-state.yaml`: compact persisted window/workspace state.
- `attention-events.json`: in-app notification and attention event store.
- `control.sock`: local socket while the app is running.

Runtime-only objects such as Ghostty surfaces, WKWebViews, and AppKit views should stay out of persisted SwiftUI state.

## Local Control Flow

```text
ConductorCLI
    │ newline-delimited JSON
    ▼
control.sock
    ▼
ConductorControlServer
    ▼
ConductorControlRouter
    ▼
ConductorWindowModel
```

The protocol and UI mutate the same model. There should not be a hidden automation-only state path.

## Documentation Map

- [Getting started](getting-started.md)
- [Local control API](api.md)
- [Notifications](notifications.md)
- [Updating](updating.md)
- [Security](security.md)
- [Troubleshooting](troubleshooting.md)
