# Agent Status Recognition and Badges

## Goal

Show lightweight AI agent status in the terminal UI so users can see which pane is running an agent, waiting for input, or recently completed. This should use explicit launch/hook events and compact metadata only.

## What I Already Know

- The user approved the AI-related next feature after the AI Agent configuration center.
- Existing Agent hooks deliver compact events to `ConductorWindowModel.receiveAgentHookNotification`.
- Existing terminal metadata already stores unread, progress, bell, cwd, and notification summaries.
- Terminal output, transcript, scrollback, cursor, and rendered cells must not enter SwiftUI state.

## Requirements

- Track per-terminal agent status from explicit app events:
  - Starting an agent from the AI settings marks that terminal as running.
  - `session-start` / `prompt-submit` hook events mark running.
  - `notification` hook events mark waiting and create an agent notification.
  - `stop` / `agent-response` / `subagent-stop` hook events mark completed and create an agent notification.
- Show an Agent badge on terminal tabs when status badges are enabled.
- Add an AI setting to show/hide agent status badges.
- Do not read terminal scrollback or raw AI conversation content.
- Keep state compact and keyed by terminal ID.

## Acceptance Criteria

- [ ] Launching an agent from AI settings marks the target terminal as running.
- [ ] Agent hook notifications update terminal metadata with agent name/status.
- [ ] Terminal tab shows a compact Agent status badge.
- [ ] Settings -> AI includes a status badge toggle.
- [ ] `swift build`, `swift run ConductorModelCheck`, and `git diff --check` pass.

## Out of Scope

- Embedded chat UI.
- Transcript summarization.
- Process-level detection when hooks are not installed.
- Agent status persistence across app restarts.

## Technical Notes

- Likely files: `AppearancePreferences.swift`, `ConductorWindowModel.swift`, `SplitNodeView.swift`, `ConductorRootView.swift`.
- Use `TerminalDisplayMetadata`, not SwiftUI state derived from terminal output.
