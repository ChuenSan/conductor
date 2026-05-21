# AI Agent Configuration Center

## Goal

Add a functional AI settings center for configuring and launching terminal-based coding agents from Conductor. This should consolidate existing agent notification hooks and add default agent, command, availability, and launch controls.

## What I Already Know

- The user wants the next feature to be AI-related, not keyboard shortcuts, paste safety, file opening, or workspace templates.
- Existing code has `AgentIntegrationCatalog` for known agents and `AgentHookProvider` / notification hook installation for Codex and Claude Code.
- Terminal startup can send text into Ghostty surfaces through existing `TerminalSurface.sendText(_:)` and pending text queues.
- SwiftUI must only own compact product metadata; terminal output and scrollback must stay in Ghostty/AppKit.

## Requirements

- Add `Settings -> AI`.
- Let users choose a default agent from known providers and custom command.
- Persist per-agent launch commands, custom command text, and launch behavior in `AppearancePreferences`.
- Detect local CLI availability for known agents without blocking the main thread.
- Show installed / missing state in AI settings.
- Provide one-click actions to launch the selected agent in the current pane or a new terminal.
- Keep the existing Agent notification hook toggles, but present them under the AI settings center.
- Do not add a chat UI or store AI conversation content in SwiftUI state.

## Acceptance Criteria

- [ ] AI appears as a settings sidebar item.
- [ ] Default agent and command settings persist.
- [ ] Availability rows show whether known CLIs are found in common PATH locations.
- [ ] Launch in current pane sends the resolved command into the focused terminal.
- [ ] Launch in new terminal creates a new terminal and sends the resolved command.
- [ ] Existing Codex / Claude notification hook toggles remain available under AI.
- [ ] `swift build`, `swift run ConductorModelCheck`, and `git diff --check` pass.

## Out of Scope

- Embedded AI chat UI.
- API-key management.
- Reading or summarizing terminal scrollback.
- Auto-installing third-party CLIs.

## Technical Notes

- Likely files: `AppearancePreferences.swift`, `ConductorWindowModel.swift`, `ConductorRootView.swift`, and `AgentIntegrationModel.swift` if catalog metadata is needed.
- CLI detection should be bounded and off the main thread.
