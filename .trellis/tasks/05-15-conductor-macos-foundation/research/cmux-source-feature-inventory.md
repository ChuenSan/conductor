# cmux Source Feature Inventory for Conductor

Reviewed source: `/private/tmp/codex-cmux-reference`

Date: 2026-05-16

## Goal

Identify cmux product capabilities that Conductor has not carried over yet, with enough source-level detail to implement them without relying on chat memory. Conductor should reuse cmux's architecture ideas and behavioral contracts, but not copy its large AppDelegate/TerminalController coupling. Conductor's hard rule still applies: terminal scrollback/output/render state must stay out of SwiftUI state.

## Highest-Value Capabilities to Port

### 1. Agent-aware notifications

cmux has a real notification subsystem rather than a simple banner.

Relevant source:
- `Sources/TerminalNotificationStore.swift`
- `Sources/TerminalNotificationQueue.swift`
- `Sources/TerminalNotificationPolicy.swift`
- `Sources/TerminalNotificationCallerResolver.swift`
- `Sources/NotificationsPage.swift`
- `Sources/TmuxWorkspacePaneOverlayView.swift`
- `Sources/ContentView.swift`
- `CLI/cmux.swift`
- `cmuxTests/TerminalNotification*`
- `cmuxTests/NotificationAndMenuBarTests.swift`

Important behavior:
- Notification record fields: `id`, workspace/tab id, surface id, title, subtitle, body, creation time, read state, pane-flash flag.
- Store keeps derived indexes: total unread, unread by workspace/tab, unread by workspace+surface, latest unread, latest by tab.
- New notification replaces an older notification for the same workspace+surface, so one noisy agent does not flood the UI.
- Workspace-level unread indicators are separate from recorded notifications. cmux tracks manual unread, panel-derived unread, and restored unread separately.
- Native delivered/pending notification cleanup is dispatched off the main thread because `UNUserNotificationCenter` removal can block on usernoted XPC.
- `TerminalMutationBus` accepts socket-thread mutations and drains in small main-actor batches with coalescing. This is directly relevant to Conductor performance.
- Notification policies can rewrite or suppress effects: record, markUnread, reorderWorkspace, desktop, sound, command, paneFlash.
- There is a caller resolver that targets notifications by preferred workspace, preferred surface, caller TTY, or focused workspace.

Reusable design for Conductor:
- Put a pure notification state/index model in `ConductorCore`.
- Put app delivery effects and native notification cleanup in the app layer.
- Add a mutation bus for socket/CLI/agent hook events so background threads never publish SwiftUI state directly.
- Do not store long terminal transcript in notification bodies; truncate at ingestion.
- Keep unread badges/rings derived from indexes, not computed by scanning every render.

### 2. Agent hook lifecycle

cmux supports many agent hooks: Codex, Claude Code, OpenCode, Pi, Amp, Cursor CLI, Gemini, Rovo Dev, Copilot, CodeBuddy, Factory/Droid, Qoder, Hermes Agent.

Relevant source:
- `docs/agent-hooks.md`
- `CLI/CMUXCLI+AgentHookDefinitions.swift`
- `CLI/CMUXCLI+HermesAgentHooks.swift`
- `CLI/cmux.swift`
- `Sources/RestorableAgentSession.swift`
- `Sources/SessionIndexModels.swift`
- `Sources/SessionIndexStore.swift`
- `Packages/CMUXAgentLaunch`
- `Packages/CMUXAgentVault`
- `cmuxTests/*Hook*`
- `cmuxTests/*Agent*`

Important behavior:
- Agent definitions are data-driven: name, display name, status key, config dir/file, env override, disable env var, binary, hook format, lifecycle events, feed events.
- Hook command guards on `CMUX_SURFACE_ID`, checks disable env var, checks `cmux` on PATH, and returns `{}` outside cmux terminals.
- Common lifecycle actions: session start, prompt submit, stop/agent response, shell exec/done, session end.
- Hooks write session stores under `~/.cmuxterm/<agent>-hook-sessions.json`.
- Codex also has a transcript monitor: it watches transcript files for questions/failures and publishes notifications/status.
- Hook install supports uninstall/upgrade and avoids clobbering non-cmux user hooks.
- Config dir override support matters: `CODEX_HOME`, `OPENCODE_CONFIG_DIR`, `PI_CODING_AGENT_DIR`, `COPILOT_HOME`, `CODEBUDDY_CONFIG_DIR`, `QODER_CONFIG_DIR`, etc.

Reusable design for Conductor:
- Create a small `AgentIntegrationDefinition` table rather than hard-coding Codex only.
- Start with Codex and Claude, but model must already support multiple agents.
- Agent hooks should call a Conductor CLI/socket command, not mutate app files directly.
- Keep hook installation idempotent and reversible with owned markers.
- Track status as compact app metadata: running, waiting for input, error, complete, session id, cwd, surface id.

### 3. Feed approval bridge

cmux has a Feed system for permission prompts, questions, and plan feedback. This is not just notification; hooks can block until the user answers.

Relevant source:
- `Sources/Feed/FeedCoordinator.swift`
- `Sources/Feed/FeedPanelViewModel.swift`
- `Sources/Feed/FeedPanelView.swift`
- `Sources/Feed/FeedPermissionActionPolicy.swift`
- `Packages/CMUXWorkstream`
- `CLI/cmux.swift` feed sections
- `docs/agent-hooks.md`

Important behavior:
- `feed.push` creates a workstream item and optionally blocks the socket worker on a semaphore until reply or timeout.
- Replies resolve a pending item and wake the waiting hook inline.
- Pending items are tied to the agent process lifetime with kqueue `DispatchSourceProcess`; no polling loop.
- If the app is not focused, cmux can post a native notification with inline action buttons.
- Feed supports permission request, exit-plan feedback, questions, and tool context.

Reusable design for Conductor:
- This should become a separate `Workstream/Feed` domain, not part of notification store.
- Use kqueue process watchers for agent prompt lifetime.
- UI should live in a right sidebar/panel, with compact badge in workspace/sidebar.
- Do not block the main actor; only the hook/socket worker waits.

### 4. Session vault and resume

cmux indexes previous agent sessions and can resume them in panes.

Relevant source:
- `Sources/SessionIndexModels.swift`
- `Sources/SessionIndexStore.swift`
- `Sources/SessionIndexView.swift`
- `Sources/RestorableAgentSession.swift`
- `Sources/SessionRestoredTerminalCommandStore.swift`
- `Packages/CMUXAgentVault`
- `Packages/CMUXAgentLaunch`
- `Sources/RovoDevIndex.swift`
- `Sources/HermesAgentIndex.swift`

Important behavior:
- Supports session agents and custom registered agents.
- Entries include session id, title, cwd, git branch, linked PR, modified date, source file, and agent-specific resume options.
- Resume commands are sanitized. Prompts/secrets/old session selectors/noninteractive commands are dropped.
- Parsed metadata is cached with mtime and LRU to avoid repeatedly parsing large JSONL/SQLite histories.
- UI can group by directory or agent and preserves user ordering.

Reusable design for Conductor:
- We need a session vault, but it should be right-sidebar-first after notification/feed foundations.
- Use snapshots and bounded caches. Do not make transcript previews live SwiftUI state.
- Resume command builder should be pure/testable and conservative about secrets.

### 5. Local socket, CLI, and event stream

cmux is highly scriptable.

Relevant source:
- `Sources/TerminalController.swift`
- `Sources/CmuxEventBus.swift`
- `Sources/CmuxEventStream.swift`
- `Sources/CmuxEventLogWriter.swift`
- `Sources/CmuxSocketEventMapper.swift`
- `CLI/cmux.swift`
- `CLI/CMUXCLI+Events.swift`
- `cmuxTests/TerminalController*`
- `cmuxTests/CmuxEventBusTests.swift`

Important behavior:
- Commands include workspace/window/pane/surface focus, split, send keys/text, notify, right-sidebar control, feed replies, browser API, metadata updates.
- V2 uses typed method names like `notification.jump_to_unread`, `feed.push`, `surface.focus`, etc.
- Event bus retains a bounded replay buffer, has subscriptions with filters, sends heartbeats, enforces max event size, and writes a bounded JSONL audit log.
- Socket commands can declare focus intent so background commands do not accidentally steal focus.

Reusable design for Conductor:
- Add a small V2 socket API early. Hooks and future automation should use it.
- Event stream should come before many agent features so UI/tooling can observe without bespoke callbacks.
- Keep backpressure limits and encoded byte caps from day one.

### 6. Right sidebar tool system

cmux has a second sidebar, separate from the primary workspace list.

Relevant source:
- `Sources/ContentView+RightSidebarCommandPalette.swift`
- `Sources/RightSidebarPanelView.swift`
- `Sources/RightSidebarToolPanel.swift`
- `Sources/RightSidebarMode+Availability.swift`
- `Sources/RightSidebarChromeStyle.swift`
- `Sources/FileExplorerView.swift`
- `Sources/SessionIndexView.swift`
- `Sources/Feed`
- `Sources/DockPanelView.swift`

Important behavior:
- Modes: files, find, vault/sessions, feed, dock.
- Some tools can also open as pane surfaces.
- Command palette controls right sidebar visibility/mode/focus.

Reusable design for Conductor:
- Add a right sidebar shell after notifications/feed model exist.
- Keep terminal area dominant; sidebar must be collapsible and not change terminal output model.
- Modes should be lazy-loaded to avoid heavy file/session scans at app launch.

### 7. Browser pane and automation

cmux treats browser panels as peers of terminal surfaces.

Relevant source:
- `Sources/Panels/BrowserPanel.swift`
- `Sources/Panels/BrowserPanelView.swift`
- `Sources/Panels/BrowserAutomation.swift`
- `Sources/Panels/CmuxWebView*.swift`
- `docs/agent-browser-port-spec.md`
- `cmuxTests/Browser*`

Important behavior:
- Split browser right/down.
- Browser surfaces participate in pane/tab movement.
- Automation API supports snapshot, click/type/fill, JS eval, dialogs, downloads, and unsupported network events.
- Remote workspace browser can proxy remote localhost.

Reusable design for Conductor:
- Not MVP, but our pane model should not assume every surface is terminal forever.
- Introduce `SurfaceKind` before adding browser/file preview.

### 8. File explorer, preview, and drops

Relevant source:
- `Sources/FileExplorerStore.swift`
- `Sources/FileExplorerView.swift`
- `Sources/FileDropOverlayView.swift`
- `Sources/FileExplorerTerminalPathInsertion.swift`
- `Sources/Panels/FilePreviewPanel.swift`
- `Sources/Panels/MarkdownPanel.swift`
- `Sources/CommandClickFileOpenRouter.swift`

Important behavior:
- File explorer can insert paths into terminal.
- Finder drops route to panes/workspaces.
- Terminal command-click can open files.
- Preview supports markdown/PDF/images/text with native AppKit views where needed.

Reusable design for Conductor:
- Add only after core terminal/workspace interaction stabilizes.
- Preserve separation: file indexing/store can be observable, terminal output cannot.

### 9. Workspace metadata and operations polish

Relevant source:
- `Sources/Sidebar/*`
- `Sources/TabManager.swift`
- `Sources/Workspace.swift`
- `Sources/WorkspaceActionDispatcher.swift`
- `Sources/WorkspacePromptSubmit.swift`
- `Sources/SidebarPortDisplayText.swift`
- `Sources/PortScanner.swift`
- `Sources/CmuxTopSnapshot.swift`
- `Sources/CmuxTopProcessCPUTracker.swift`

Important behavior:
- Workspace rows expose git branch, PR, cwd, ports, latest notification, custom metadata, SSH/remote state, pinned/color state.
- Workspaces can be moved, duplicated, pinned, colorized, renamed, marked unread/read, and dropped/reordered.
- CPU/top process snapshots are exposed to UI and CLI.

Reusable design for Conductor:
- Add metadata as compact snapshots keyed by workspace/surface.
- Keep expensive scans throttled/backgrounded.
- Add workspace tab menus and inline rename before more side features.

### 10. Remote/SSH workspaces and tmux compatibility

Relevant source:
- `CLI/CMUXCLI+SSHCommandSupport.swift`
- `Sources/CmuxSSHURLRequest.swift`
- `Sources/WorkspaceRemoteConfiguration.swift`
- `Sources/WorkspaceRemoteSSHBatchCommandBuilder.swift`
- `daemon/remote`
- `CLI/cmux.swift` tmux compatibility sections
- `cmuxTests/*SSH*`
- `cmuxTests/test_tmux_compat_*`

Important behavior:
- `cmux ssh` creates remote workspaces.
- Remote browser panes route through remote network.
- Remote file/image drops upload through scp.
- tmux compatibility injects fake `TMUX`/`TMUX_PANE` and command shims for agent/team workflows.

Reusable design for Conductor:
- Not near-term, but environment injection must leave space for `CONDUCTOR_WORKSPACE_ID`, `CONDUCTOR_SURFACE_ID`, and future tmux-compatible shims.

## Migration Priority

P0:
- Notification store/indexes with derived unread state.
- Mutation bus for socket/hook notifications.
- Notification panel, sidebar/workspace badges, pane unread ring.
- Jump latest unread, mark read/unread, clear all/clear surface.
- Minimal V2 socket/CLI notify endpoint.

P1:
- Agent integration definition table for Codex/Claude first.
- Hook install/uninstall with owned markers and disable env vars.
- Agent status metadata on workspace/surface.
- Codex transcript monitor for questions/failures.
- Event bus with bounded replay and heartbeat.

P2:
- Feed approval bridge and right sidebar Feed panel.
- Session vault/resume for Codex/Claude.
- Right sidebar shell with files/find/sessions/feed modes.

P3:
- Browser surfaces, file preview/explorer, remote/SSH, tmux compatibility.

## Implementation Warnings

- Do not copy cmux's global `AppDelegate` and huge `TerminalController` shape. Reuse data contracts and behavior, split Conductor into small stores/services.
- Do not publish one SwiftUI update per terminal/agent event. Batch and coalesce like `TerminalMutationBus`.
- Do not compute unread counts by scanning all notifications in views. Precompute indexes in store/model.
- Do not block main actor for native notification cleanup, file parsing, hook policy execution, socket reads, or agent transcript monitoring.
- Do not assume all panes are terminals. cmux's browser/file panels show why Conductor needs a future `SurfaceKind`.

