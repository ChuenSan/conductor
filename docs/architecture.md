# Architecture Notes

Conductor is split into a small core model and a macOS app shell.

## Boundaries

- `ConductorCore` owns testable workspace, pane, split, and terminal-tab state.
- `Conductor` owns SwiftUI/AppKit shell, GhosttyKit integration, web tabs, settings, and updater UI.
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
