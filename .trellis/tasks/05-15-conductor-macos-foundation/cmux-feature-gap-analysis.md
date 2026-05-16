# cmux Feature Gap Analysis

Source reviewed: `/tmp/codex-cmux-reference`

## What cmux Has That Conductor Does Not Yet Have

### 1. Agent-Aware Notifications

cmux has a full notification system, not just desktop banners.

- Sources: terminal OSC notifications, `cmux notify`, socket commands, and agent hooks.
- UI: pane ring, sidebar/tab unread badges, notifications panel, menu bar, dock/menu integration.
- Navigation: jump to latest unread and mark current as oldest unread then jump next.
- Policy: configurable notification hooks and custom commands can rewrite/suppress/deliver notifications.
- Safety/performance: `UNUserNotificationCenter` cleanup happens off-main to avoid blocking UI.

Important files:

- `Sources/TerminalNotificationStore.swift`
- `Sources/NotificationsPage.swift`
- `Sources/GhosttyTerminalView.swift`
- `Sources/TerminalController.swift`
- `CLI/cmux.swift`

### 2. Agent Hook Integrations

cmux installs hooks for many coding agents and maps their lifecycle into app state.

Supported agents observed:

- Claude Code
- Codex
- OpenCode
- Pi
- Amp
- Cursor CLI
- Gemini
- Rovo Dev
- Copilot
- CodeBuddy
- Factory
- Qoder
- Hermes Agent

Capabilities:

- running/idle state
- session start/stop
- prompt submit
- tool permission/feed events
- native session restore after app relaunch
- per-agent config directory overrides and disable env vars

Important files:

- `docs/agent-hooks.md`
- `CLI/CMUXCLI+AgentHookDefinitions.swift`
- `CLI/CMUXCLI+HermesAgentHooks.swift`
- `Sources/SessionIndexView.swift`
- `Sources/HermesAgentIndex.swift`

### 3. Feed / Approval Bridge

cmux has a "Feed" system for agent permission requests and approvals.

- Hooks can block while waiting for the user to approve/deny.
- Pending items expire when the agent process exits via kqueue process watchers.
- It can show native notifications with inline actions.
- It writes/audits workstream events.

Important files:

- `Sources/Feed/FeedCoordinator.swift`
- `Packages/CMUXWorkstream`
- `docs/agent-hooks.md`

### 4. Session Vault / Agent Session Restore

cmux indexes agent history and can resume sessions.

- Vault scans Claude/Codex/OpenCode/Rovo Dev and generic agent session stores.
- It previews transcripts without pushing all terminal output into UI state.
- It can resume an agent session in an existing pane when cwd matches, or create a workspace.
- It stores sanitized resume commands and strips secrets/prompts.

Important files:

- `Sources/SessionIndexView.swift`
- `Packages/CMUXAgentVault`
- `Sources/RovoDevIndex.swift`
- `docs/agent-hooks.md`

### 5. Right Sidebar Tool System

cmux has a second sidebar with modes:

- Files
- Find
- Sessions/Vault
- Feed
- Dock

Some of those tools can also open as panes.

Important files:

- `Sources/ContentView+RightSidebarCommandPalette.swift`
- `Sources/FileExplorerView.swift`
- `Sources/SessionIndexView.swift`
- `Sources/Feed`
- `Sources/DockPanelView.swift`

### 6. Built-In Browser Pane

cmux includes a WebKit browser pane with automation.

- Split browser right/down.
- Browser tabs/surfaces are peers of terminal surfaces.
- Agent-browser-style API: snapshot accessibility tree, click, type/fill, evaluate JS.
- Browser import: cookies/history/sessions from Chrome, Firefox, Arc, Safari, and others.
- Remote SSH browser routing so remote localhost works.

Important files:

- `Sources/Panels/BrowserPanel.swift`
- `Sources/Panels/BrowserPanelView.swift`
- `Sources/Panels/BrowserAutomation.swift`
- `Sources/Panels/CmuxWebView.swift`
- `docs/agent-browser-port-spec.md`

### 7. File Explorer / File Preview / Finder Drop

cmux supports file-focused panes and sidebar tooling.

- File explorer store and UI.
- File preview pane for markdown, PDF, images, etc.
- Finder file drops into panes/workspaces.
- Command-click file open routing from terminal output.

Important files:

- `Sources/FileExplorerStore.swift`
- `Sources/FileExplorerView.swift`
- `Sources/FileDropOverlayView.swift`
- `Sources/Panels/FilePreviewPanel.swift`
- `Sources/Panels/MarkdownPanel.swift`
- `Sources/CommandClickFileOpenRouter.swift`

### 8. Local Socket / CLI / Event Stream

cmux is scriptable through a socket and CLI.

- Create workspaces, split panes, send text/keys, open browser URLs, notify, list panels.
- Event stream with reconnect, replay, heartbeats, bounded queues, and JSONL audit log.
- Categories: window, workspace, pane, surface, notification, feed, agent, browser.
- Socket security and password store exist.

Important files:

- `docs/events.md`
- `Sources/TerminalController.swift`
- `Sources/CmuxEventBus.swift`
- `Sources/CmuxEventStream.swift`
- `Sources/CmuxEventLogWriter.swift`
- `CLI/cmux.swift`

### 9. Workspace Metadata

cmux sidebar rows show far more than title/count:

- git branch
- linked PR status/number
- working directory
- listening ports
- latest notification text
- custom metadata blocks
- remote/SSH status
- pinned workspaces and colors

Important files:

- `Sources/Sidebar`
- `Sources/TabManager.swift`
- `Sources/CmuxTopSnapshot.swift`
- `Sources/PortScanner.swift`

### 10. Remote / SSH Workspaces

cmux has remote workspaces.

- `cmux ssh user@remote`
- remote browser panes route through the remote network
- image/file drag into remote session uploads through scp
- remote auth/status is shown in sidebar

Important files:

- `CLI/CMUXCLI+SSHCommandSupport.swift`
- `Sources/CmuxSSHURLRequest.swift`
- `Sources/Workspace.swift`
- `daemon/remote`

### 11. Project Configuration

cmux has `cmux.json`.

- custom commands
- custom actions
- notification hooks
- UI settings
- surface tab bar buttons
- vault config
- named workspace definitions
- new workspace command

Important files:

- `Sources/CmuxConfig.swift`
- `Sources/CmuxConfigExecutor.swift`
- `Sources/CmuxWorkspaceDefinition.swift`
- `Sources/CmuxConfigUI.swift`

### 12. Shortcut System

cmux has customizable shortcuts with conflicts/unbinding/settings migration.

Important files:

- `Sources/KeyboardShortcutSettings.swift`
- `Sources/KeyboardShortcutRecorder.swift`
- `Sources/KeyboardShortcutSettingsFileStore.swift`
- `Sources/CommandPalette/CommandPaletteSettingsToggle.swift`

## What We Should Take First

### P0: Agent Notification Backbone

Build this before Feed/Browser/Vault.

- `NotificationStore`
- per terminal/pane unread state
- pane focus ring and sidebar badge
- `jumpToLatestUnread`
- clear/read actions
- `conductor notify` or socket-like local command
- Ghostty OSC notification ingestion if exposed by current integration

### P1: Agent Hook Integration For Codex And Claude Code

Start with Codex and Claude Code only.

- install/uninstall hooks
- lifecycle state: running, waiting, stopped
- notification bridge
- persist session IDs for future restore
- avoid raw transcript in SwiftUI

### P2: Feed / Permission Requests

After notifications work, add blocking approval cards.

- request model
- pending/approved/denied/expired states
- process-exit expiry
- CLI/hook response contract

### P3: Session Vault

Add read-only session index and resume.

- Codex and Claude first
- transcript preview with hard truncation
- sanitized resume commands

### P4: Right Sidebar Tools

Add as a product shell system.

- Notifications
- Feed
- Sessions
- Files
- Find

### P5: Browser Pane

Large feature; valuable but should wait until terminal core plus notifications are solid.

### P6: CLI / Event Stream

Implement a smaller socket API before full event replay.

- notify
- send text/key
- split/new tab/new workspace
- list workspaces/panes
- then event stream

## Product Direction

Do not copy cmux wholesale. The valuable pieces are its composable primitives:

- terminal surfaces
- workspaces/splits/tabs
- notifications
- agent hooks
- feed approvals
- browser/tools
- socket automation

Conductor should keep the terminal work surface visually cleaner than cmux, but adopt the agent-aware workflow machinery.
