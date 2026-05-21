# terminal input behavior settings

## Goal

Add practical terminal input settings for Conductor: Option/Alt behavior, paste safety, and the
default directory used by new terminals. These settings should improve daily terminal ergonomics
without moving terminal rendering, scrollback, or high-frequency input state into SwiftUI.

## What I already know

* Keyboard input is routed through `TerminalHostView` and `TerminalSurface`.
* Terminal text is sent to Ghostty via `TerminalSurface.sendText(_:)`.
* New terminal creation is centralized in `ConductorWindowModel.newTerminal()`.
* Settings already has a native sidebar/pane structure that can add a `终端输入` section.

## Requirements

* Persist terminal input behavior in appearance/preferences.
* Add a settings section for terminal input behavior.
* Support Option/Alt modes:
  * macOS special characters
  * Meta/Alt modifier
  * ESC prefix
* Support paste safety:
  * direct paste
  * confirm multiline/large paste
  * strip trailing newline
  * bracketed paste wrapping
* Support default new terminal directory:
  * home directory
  * focused terminal directory
* Apply input preferences to existing live terminal host views.
* Keep terminal output, transcript, scrollback, and render state out of SwiftUI.

## Acceptance Criteria

* [ ] Settings includes `终端输入`.
* [ ] Option/Alt behavior can be changed from settings.
* [ ] Multiline/large paste can prompt for confirmation.
* [ ] Paste can strip a trailing newline.
* [ ] Paste can be wrapped with bracketed paste sequences.
* [ ] New terminal default directory can be home or focused terminal directory.
* [ ] Existing surfaces receive updated input preferences.
* [ ] `swift build`, `ConductorModelCheck`, and `git diff --check` pass.

## Out of Scope

* Fully editable keybinding table.
* Left/right Option split behavior. macOS event data for normal key events does not reliably
  identify which Option key produced the character without a lower-level event tap.
* Runtime process detection for close confirmation.
