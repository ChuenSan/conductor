# Session Restore and Launch Behavior Settings

## Goal

Add a functional Settings section for startup/session behavior so users can choose how Conductor opens: restore previous workspaces, start clean, or keep only a lightweight workspace layout. This should build on existing `WorkspacePersistence` instead of adding a second persistence system.

## What I Already Know

- The user wants the next settings feature to be functional rather than more terminal appearance controls.
- `WorkspacePersistence` already saves and loads workspaces, selected workspace, theme, and `AppearancePreferences`.
- `ConductorWindowModel` currently restores persisted workspaces unconditionally when persisted state exists.
- Terminal live output, scrollback, and rendering must stay in Ghostty/AppKit and must not enter SwiftUI state.

## Requirements

- Add a new `Settings -> Session` section.
- Persist session startup preferences under `AppearancePreferences`.
- Let the user choose startup behavior:
  - Restore previous session.
  - Start with a clean terminal.
  - Restore layout only, replacing restored terminal tabs with fresh shell tabs while preserving workspace/pane shape where possible.
- Add toggles for whether restored metadata keeps terminal titles and working directories.
- Add a reset action that clears saved window/workspace state without losing appearance/settings preferences.
- Apply startup behavior on next app launch; do not restart or mutate existing terminal surfaces immediately.
- Keep implementation metadata-only: no terminal transcript, scrollback, or rendered cells in SwiftUI state.

## Acceptance Criteria

- [ ] `Settings -> Session` appears in the settings sidebar.
- [ ] Session preferences persist across app relaunches.
- [ ] "Clean terminal" startup ignores saved workspaces but keeps saved theme and app preferences.
- [ ] "Layout only" startup keeps workspace/pane layout but creates fresh terminal IDs/tabs and strips runtime-oriented terminal metadata according to toggles.
- [ ] Clear saved session state removes persisted workspace layout and future launch falls back to a fresh workspace.
- [ ] `swift build`, `swift run ConductorModelCheck`, and `git diff --check` pass.

## Out of Scope

- Restoring terminal scrollback or PTY process state.
- Prompting at app launch.
- Syncing preferences through iCloud or external profile files.

## Technical Notes

- Likely files: `AppearancePreferences.swift`, `WorkspacePersistence.swift`, `ConductorWindowModel.swift`, `ConductorRootView.swift`, and `ConductorModelCheck` if model invariants need coverage.
- The setting should use existing settings row components and localized text helpers.
