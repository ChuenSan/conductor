# Make Agent Status Badges Visible

## Goal

Fix the Agent status feature so users can clearly see that it is working. The current status icon is too subtle and can look like nothing changed.

## Requirements

- Make terminal tab Agent status badges textual and obvious, not icon-only.
- Keep status metadata compact and driven by launch/hook events only.
- Add a small AI settings action to mark the focused terminal as running for smoke testing.
- Keep the existing show/hide status badge toggle.
- Do not read terminal output, transcript, or scrollback.

## Acceptance Criteria

- [ ] Launching an Agent from AI settings visibly changes the target terminal tab.
- [ ] The badge includes short state text: running/waiting/done/failed.
- [ ] Settings -> AI includes a way to test the focused terminal status.
- [ ] `swift build`, `swift run ConductorModelCheck`, and `git diff --check` pass.
