# cmux-Level Workbench Full Build Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. This is intentionally **not** a priority roadmap. Every track is in scope. Track ordering below is for navigation only, not product priority. Use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise Conductor from a native terminal/workspace app with many features into a dependable agent workbench: users can run multiple CLI agents, browser sessions, files, notifications, and update flows all day without losing context, guessing state, or babysitting the UI.

**Human Standard:** A real user should be able to open Conductor in the morning, start several agents, browse docs, inspect files, leave the machine, come back, and immediately know: what is running, what finished, what needs attention, where each task lives, and whether the app itself is healthy. The app should feel like a quiet macOS tool, not a demo, dashboard, or AI control panel.

**Architecture:** Build a small set of durable primitives:

- A local command/control protocol so humans, agents, and tests can drive the app.
- A reliable session model so terminals, tabs, scrollback, notifications, and browser state survive ordinary failure.
- A notification and attention system that is visible inside the workspace and reliable outside it.
- Browser tabs that are useful surfaces, not only embedded web views.
- Workspace metadata that answers "where am I and what needs me?" at a glance.
- UI/animation/settings/release systems that behave like a native macOS product.

## User Value Ledger

This plan is not valuable because it adds more controls. It is valuable only when
users feel less friction in real work:

| Capability | What it gives the user |
| --- | --- |
| Local control protocol | Scripts and agents can prepare a workspace, split terminals, open pages, and report status without making the user click through setup every time. |
| Session life | A crash, update, or restart stops being scary because the shape of work returns or the app explains exactly what could not be restored. |
| Attention system | The user can leave long-running tasks alone and come back to a clear list of what finished, what failed, and where to jump. |
| Browser surfaces | Web tabs become inspectable work surfaces for docs, local apps, and agent checks, not passive mini browsers. |
| Workspace intelligence | The sidebar answers "which project needs me?" before the user opens panels or reads terminal output. |
| Command layer | Power users can move quickly, while newer users still see what each command will do before running it. |
| Native UX polish | The app feels calm and trustworthy during repeated use: no accidental drags, hidden shortcuts, unexplained icons, or oversized panels. |
| Updates and distribution | Users see a simple update path with progress and recovery, without raw release internals or manual replacement anxiety. |
| Observability and QA | Support becomes concrete: one diagnostics path can explain state, notifications, updates, restore, and protocol health. |
| Public docs | New users can install, operate, automate, and troubleshoot without needing private context from the builder. |

Every implementation note below should be judged against this ledger. If a feature
does not reduce user babysitting, uncertainty, or recovery cost, it is not done yet.

## Primary Capability Bar

The first goal is not a polish pass. Conductor must become a rich, dependable
workbench with strong daily-use capabilities before secondary AI-channel work
starts. The primary bar is complete only when these loops are useful and
verified:

- Multi-workspace terminal work: create, split, switch, restore, and script
  real workspaces without losing focus or context.
- Browser work surfaces: open docs/local apps, inspect pages, act on fixtures,
  capture screenshots, and explain automation failures.
- Attention management: every important event is stored, visible, jumpable,
  markable, and diagnosable even when macOS banners fail.
- Session life: relaunch, corrupt state, missing files, browser tabs, selected
  content, and update restarts restore or explain what could not be restored.
- Window/workbench integration: external windows and app surfaces can become
  part of a workspace with clear permissions, failure states, and recovery.
- Release quality: update, diagnostics, screenshots, performance gates, and
  public docs are verified against real app instances.

### Primary-First Execution Lock

AI channel management is frozen as secondary work until the primary capability
bar above is complete enough to pass the whole-day acceptance story. It must not
be selected as the next implementation slice, used as a headline progress item,
or expanded into new UI while these core loops still have open gaps:

- session restore and supported-agent continuation;
- browser surface reliability and no-surprise tab behavior;
- attention and notification visibility across denied/allowed macOS states;
- command/action consistency across toolbar, sidebar, rows, context menus, and
  shortcuts;
- native UX feel: scroll, hover help, drag thresholds, panel density, themes, and
  update progress;
- diagnostics, dogfood, screenshots, docs, and release gates against real app
  instances.

If AI channel code is touched before that bar is met, the change must be only a
regression fix required to keep existing workbench behavior compiling or passing
tests. It is not allowed to be counted as primary progress.

### Deferred AI Channel Ledger

The notes below are historical ledger entries only. They document existing
implementation, but they do not change the primary execution order.

**2026-06-04 AI channel foundation:** Started this only as a workbench primitive,
not as a standalone channel dashboard. `TerminalTabState` now persists an
optional terminal-level AI channel binding with channel ID, kind, model,
endpoint, launch args, and sanitized environment keys. New terminal surfaces
receive Conductor-scoped channel environment (`CONDUCTOR_AI_CHANNEL_ID`,
`CONDUCTOR_AI_CHANNEL_KIND`, optional model/endpoint) plus validated binding
environment, while already-running surfaces report that a new surface is needed
instead of mutating a live shell. The local protocol and CLI expose
`aiChannel.list`, `terminal.aiChannel`, and `terminal.setAIChannel` through
`conductor ai-channel list` and `conductor terminal channel get|set|clear`.
`surface.list`, `status`, and `diagnostics` expose redacted channel summaries.
Still open: priority ordering UI, auth/health probes, terminal badge UI,
conflict/fallback UX, real-agent dogfood, and settings integration.

**2026-06-04 global channel update:** Added durable global AI channel management
on top of the terminal binding foundation. `AIChannelState` merges built-in
presets with user overrides, persists the default channel in the window/session
snapshot, supports enable/disable, priority ordering, custom OpenAI-compatible
endpoints, launch args, validated environment keys, and lightweight health
messages. New terminal surfaces inherit the global default channel when the
terminal has no explicit override; `terminal channel clear` returns a pane to
that inherited default. The control API and CLI now expose
`aiChannel.configure`, `aiChannel.setDefault`, `conductor ai-channel configure`,
`set-default`, `enable`, `disable`, and `set-priority`, and diagnostics show the
default plus terminal effective binding without exposing environment values.
Still open: native settings/workbench UI, real provider auth probes, terminal
badges, conflict/fallback presentation, and multi-agent dogfood with actual CLIs.

**2026-06-04 primary-track correction:** AI channel work remains secondary until
the workbench loops above are useful. The next implemented primary primitive is
terminal runtime identity: each terminal tab can now persist an agent snapshot,
last command snapshot, and active search snapshot. Runtime events from agent
hooks, visible Codex polling, command-finished callbacks, and terminal search
callbacks update both in-memory display state and the durable workspace model.
Workspace metadata and the control protocol expose agent state, last command
exit/duration/time, and active search context so sidebar, restore, diagnostics,
and scripts can answer "what happened in this pane?" from the same source of
truth. Still open: real resume command extraction, process reattach limits,
agent-specific completion policies, and dogfood with real supported agents.

**2026-06-04 session-resume update:** Added a controlled batch resume path for
restored supported-agent terminals. The command palette now exposes "Resume
Workspace Agents", and the protocol/CLI expose `terminal.resumeAgents` through
`conductor terminal resume-agents --workspace current|all|<workspace-id>
[--dry-run]`. The batch scanner uses persisted agent snapshots instead of
focusing terminals to inspect visible text, so command availability checks do not
move the user's cursor. Dogfood now verifies the ordinary relaunch path can
dry-run both a single terminal resume and a current-workspace batch resume, then
execute the current-workspace batch resume against a local fake supported-agent
binary after relaunch. This is still explicit by design; automatic launch-time
resume and real external-agent conversation-continuation proof remain open.

**2026-06-04 restore-boundary update:** Restored terminals with useful runtime
context now carry an explicit process boundary in the recovery model. Settings >
Overview and `ConductorCLI session inspect` report `terminal_process_restarted`
and `process.status == fresh-after-restore` for restored Agent/command
terminals, making it clear that Conductor restored context and readable output
but did not reattach the original shell or agent process. The isolated dogfood
restore path asserts this field and issue after ordinary relaunch. True process
reattachment remains unfinished and is not claimed.

**Working directory for all commands:** `Apps/Conductor`

**Design spec:** `docs/superpowers/specs/2026-06-03-cmux-level-workbench-design.md`

**Capability matrix:** `docs/superpowers/specs/2026-06-03-cmux-level-capability-matrix.md`

**Delivery contract:** `docs/superpowers/specs/2026-06-03-cmux-level-delivery-contract.md`

---

## Track Map

| Track | Outcome |
| --- | --- |
| A. Control Protocol | `conductor` CLI + local socket API can create/select workspaces, send input, control tabs, query state, and emit notifications. |
| B. Session Life | Restarts, updates, crashes, and window reloads do not destroy task context. |
| C. Attention System | Notifications, badges, unread states, and jump-to-latest are coherent and debuggable. |
| D. Browser Surfaces | Web tabs expose navigation, snapshots, click/fill/find, screenshots, and session persistence. |
| E. Workspace Intelligence | Sidebars and tabs show project, ports, local services, agent, and pending work without clutter. |
| F. Command Layer | Command palette, shortcuts, context menus, and user-defined keybindings are complete and safe. |
| G. Native UX Polish | All panels, settings, motion, drag, scrolling, hover help, density, and themes feel consistent and non-AI. |
| H. Updates & Distribution | GitHub updater, progress UI, packaging, permissions, signing fallback, and release notes feel production-grade. |
| I. Observability & QA | Diagnostics, smoke tests, stress tests, performance gates, screenshots, and dogfood scripts cover the full system. |
| J. Documentation & Onboarding | README, install docs, privacy/security docs, API docs, and troubleshooting are external-user ready. |

---

## Non-Negotiable Experience Contracts

These contracts apply to every track. A feature is not complete if it works technically but violates one of these.

| Contract | Meaning | Failure example |
| --- | --- | --- |
| Orientation in 2 seconds | The user can tell which project/workspace/pane needs attention without opening three panels. | A notification exists but only inside a hidden modal. |
| Nothing quietly disappears | Terminals, browser tabs, notifications, and update state either restore or explain why not. | Relaunch opens a blank workspace after state corruption. |
| Every action explains itself | Icon-only controls have hover help; command palette items have outcome descriptions. | A circular arrow button appears with no tooltip or state. |
| Modals own input | Settings, command palette, notifications, and update panels block unrelated app shortcuts behind them. | Pressing a shortcut in settings changes a hidden terminal tab. |
| UI is calm, not dashboard-like | Metadata is compact, contextual, and readable. Avoid giant cards, decorative glow, or vague AI phrasing. | A usage page fills the window with oversized tiles that do not explain actions. |
| Protocol mirrors UI | Any major UI action has an equivalent command/protocol path where practical. | The user can split panes in UI but scripts/agents cannot. |
| Diagnostics are user-useful | Failures include a state, a cause, and the next action. | "Update unavailable" with a raw URL but no reason. |

---

## Whole-Day Acceptance Story

This is the benchmark scenario. The final system must pass it end to end.

- [ ] The user opens Conductor and sees three restored workspaces: one app repo, one backend repo, one release workspace.
- [ ] Each workspace shows project name, path, running port count, agent state, and unread count in compact chrome.
- [x] A script creates a new workspace through the CLI, splits two terminals, opens a browser tab, and sends commands to terminals.
- [ ] Two CLI agents finish while the app is not focused. macOS banners appear when allowed; in-app unread state appears regardless.
- [x] The user clicks "latest unread" and lands on the exact workspace and terminal that needs attention.
- [ ] The browser tab can be snapshotted, clicked, filled, and screenshotted from the protocol.
- [x] Settings can be opened while terminals are running; background shortcuts do not leak through.
- [x] The app is force-quit and relaunched. Workspaces, selected workspace, browser tabs, file tabs, and unread notification state restore in the normal path.
- [ ] Update state, no-reload browser interaction restore, agent resume, and process reattach behavior restore or explain limits after relaunch. Terminal title/cwd/readable output, supported-agent single/batch resume dry-run, fake-agent batch resume execution, restored-terminal fresh-process explanation, plus browser current URL, explicit back/forward fallback, and scroll position now have dogfood coverage.
- [ ] An update is detected from GitHub release assets. The user sees a simple update button, progress, ready-to-install state, and no manifest URL.
- [ ] A diagnostics bundle can explain notification permission, update state, session restore result, app version, and recent main-thread stalls.

---

## Track A: Control Protocol

**Human Problem:** Without a protocol, every workflow depends on clicking. Agents cannot reliably open panes, send text, query active work, or drive browser tabs. The user becomes the automation glue.

**Files:**
- Create: `Sources/Conductor/App/Protocol/ConductorControlServer.swift`
- Create: `Sources/Conductor/App/Protocol/ConductorControlRequest.swift`
- Create: `Sources/Conductor/App/Protocol/ConductorControlResponse.swift`
- Create: `Sources/Conductor/App/Protocol/ConductorControlRouter.swift`
- Create: `Sources/ConductorCLI/main.swift`
- Modify: `Package.swift`
- Modify: `Sources/Conductor/UI/ConductorWindowModel.swift`
- Create tests under `Tests/ConductorCoreTests/ControlProtocolTests.swift`

- [x] Add a SwiftPM executable product named `conductor` or `ConductorCLI`.
- [x] Add a local Unix domain socket server inside the app, scoped to the current user under `~/Library/Application Support/Conductor/control.sock`.
- [x] Use newline-delimited JSON requests and responses. Keep the protocol small, inspectable, and scriptable.
- [x] Add request IDs, typed errors, app version, workspace IDs, tab IDs, terminal IDs, and timestamps.
- [x] Implement `app.ping`, `app.version`, `app.status`.
- [x] Implement `workspace.list`, `workspace.create`, `workspace.select`, `workspace.rename`, `workspace.close`, `workspace.duplicate`.
- [x] Implement `surface.list`, `surface.focus`, `surface.split`, `surface.close`, `surface.zoom`, `surface.move`.
- [x] Implement `terminal.sendText`, `terminal.sendKey`, `terminal.visibleText`, `terminal.cwd`, `terminal.title`, `terminal.aiChannel`, and `terminal.setAIChannel`.
- [x] Implement `browser.open`, `browser.select`, `browser.navigate`, `browser.reload`, `browser.stop`, `browser.back`, `browser.forward`.
- [x] Expose `notification.create`, `notification.list`, `notification.clear`, `notification.focus` through the protocol. `notification.create` writes to the in-app attention store and requests app attention.
- [x] Implement `command.list` and `command.run` for existing `ConductorShellCommand` cases.
- [x] Add CLI examples:

```bash
conductor workspace create --title "Release"
conductor surface split --direction right
conductor terminal send --text "npm test\n"
conductor browser open "https://github.com"
conductor notify "Build finished" --body "npm test passed"
```

- [x] Add security guardrails: only current user socket, no remote network listener, clear error if app is not running.
- [x] Add smoke tests that start the app, call `app.ping`, create a workspace, send text into a terminal, and query state.

**2026-06-03 implementation note:** `ConductorCLI` is currently declared as a regular target with an executable product because this Command Line Tools SwiftPM build crashes during manifest execution when the same target is declared with `executableTarget(...)`. The product builds and runs, but SwiftPM emits a warning. Revisit when the local toolchain issue is isolated.

**2026-06-03 Track A status:** Implemented the local socket server, router, CLI, model control wrappers, `ControlProtocolTests`, and `Scripts/control-smoke.sh`. The socket path now supports `CONDUCTOR_CONTROL_SOCKET_PATH` for isolated app/CLI smoke runs, and the smoke script supports `CONDUCTOR_SMOKE_SKIP_CLI_BUILD=1` to reuse an already-built CLI binary. Verified with `swift build --product Conductor`, `swift build --product ConductorCLI`, `swift run ConductorModelCheck`, `./Scripts/swift-test.sh --filter ControlProtocolTests`, and isolated live socket smoke.

**2026-06-03 Track A/I diagnostics update:** Added `app.diagnosticsExport` and `conductor diagnostics export [--output path]`. Exports write a redacted directory bundle with `summary.redacted.json`, diagnostic logs when available, `manifest.json`, and `README.txt`. Diagnostics now include recent control protocol errors with request ID, method, code, message, timestamp, and details, plus a performance section with recent main-thread stalls, current user-feel budget targets, recent sampled budget results, and a coverage/over-budget report. `Scripts/control-smoke.sh` verifies the export path, manifest, summary, recent-error reporting, performance section, terminal tab-switch sample, scroll-frame sample, settings-open sample, command-palette-open sample, sampled-budget report counts, browser fixture actions, and file open/snapshot/save/reveal actions inside an isolated live app run. `Scripts/dogfood-workbench.sh` now starts an isolated app, creates three workspaces, splits terminals, opens fixture browser tabs, creates attention events, runs optional control smoke, and exports diagnostics without touching user state. `performance-gate.sh` now enforces dogfood UI budgets and update-fixture `update.check` budgets from exported diagnostics. Real agent dogfood and a full unskipped release gate remain open.

**2026-06-03 Track A file-control update:** Added `file.open`, `file.reveal`, `file.save`, and `file.snapshot` to the local control protocol and CLI. `file.open` opens a real file tab, `file.reveal` opens the in-app file manager on a path, `file.snapshot --text` returns bounded file metadata/text, and `file.save --text` writes a target file. The open editor now publishes a model-backed synchronized buffer, so no-text `file.save` writes the current open-editor text synchronously and returns `mode: buffered-editor-save` with a saved buffer revision; unavailable/non-editable buffers return typed `file_buffer_unavailable` instead of an ambiguous UI save request. Verified through isolated `dogfood-workbench.sh` with `control-smoke.sh`, including typed negative fixture coverage for missing files, directory-as-file operations, missing parent directories, and no-text saves against unopened targets. Remaining work: add richer file operation UI errors.

**2026-06-03 workspace activation update:** Workspace activation from the sidebar,
top tab strip, workspace panel, or control protocol now returns the main surface
to the terminal workbench instead of leaving the user stranded in a file or web
content tab. File and web tabs remain open and can still be selected directly.
Verified with the `CONDUCTOR_WORKSPACE_AUTORUN=1` scenario:
`workspaceNavigationRestoresTerminal=true`,
`sameWorkspaceActivationReturnsTerminal=true`, and
`crossWorkspaceActivationSucceeded=true`.

**2026-06-04 terminal channel update:** Added `AIChannelDefinition`,
`AIChannelCatalog`, and `TerminalAIChannelBinding` in `ConductorCore`; terminal
tabs persist an optional binding and preserve it when duplicating terminals or
workspaces. The terminal surface startup path injects only the selected tab's
channel environment, so different panes can prepare different agent launches
without sharing process-level env state. `ConductorCLI` now supports
`ai-channel list` and `terminal channel get|set|clear`, and the control API
returns `requiresNewSurface` when a live terminal would need to be recreated for
the binding to affect the process. Verified with `swift build --product
Conductor`, `swift build --product ConductorCLI`, `AIChannelModelTests`, and
`ControlProtocolTests`.

**Acceptance:**
- A shell script can create a workspace, open a browser tab, split a terminal, send a command, and create a notification without using mouse/keyboard UI.
- Failed commands explain whether the app is closed, target ID is gone, command is disabled, or permission is unavailable.

---

## Track B: Session Life

**Human Problem:** Users will not trust the app if a crash, update, or relaunch loses terminal context, browser history, or active task identity.

**Files:**
- Modify: `Sources/Conductor/Shared/WorkspacePersistence.swift`
- Modify: `Sources/Conductor/Terminal/TerminalSurface.swift`
- Modify: `Sources/Conductor/App/Coordinators/TerminalSurfaceCoordinator.swift`
- Modify: `Sources/Conductor/UI/Web/ConductorWebSurfaceStore.swift`
- Create: `Sources/Conductor/App/Session/ConductorSessionJournal.swift`
- Create: `Sources/Conductor/App/Session/ConductorSessionRecovery.swift`

- [x] Add a session journal that writes small append-only events for workspace changes, tab creation, terminal metadata, browser URLs, and file tab changes. Notification events move to the Track C in-app event store.
- [x] Keep current snapshot as the compact authoritative state, retain a previous valid snapshot, and expose restore health diagnostics when the newest snapshot fails.
- [ ] Persist terminal identity, title, cwd, last known agent, last command, last exit, search metadata, and scrollback snapshot. Identity/title/cwd and supported-agent resume metadata now restore through dogfood; real agent continuation remains open.
- [x] Store terminal scrollback using bounded, escape-safe snapshots. Avoid marker lines in restored history.
- [x] Add "session restore health" diagnostics for snapshot source, attempted paths, failed paths, original/restored/dropped workspace/web/file counts, and missing file paths.
- [x] Add browser interaction state restore for every web tab, including current URL, explicit back/forward fallback, and scroll position.
- [ ] Ensure update/install restart preserves the state file and journal.
- [x] Add an in-app attention event only when recovery uses the previous snapshot or fails; normal restores stay silent.
- [x] Add a startup recovery toast for fallback/failure with a direct path to the recovery event.
- [x] Add a "Restore Previous Session" command if the newest state is invalid but a previous snapshot is available.

**2026-06-03 Track B status:** Added `ConductorSessionJournal` in `ConductorCore`, semantic journal events for workspace/terminal/web/file mutations, snapshot-save journal events, rotation tests, and `app.diagnostics`/`conductor diagnostics` summary output. Journal IDs now write as plain strings while still reading older `{ rawValue: ... }` entries. The compact snapshot now keeps `window-state.previous.yaml`, falls back to that previous valid snapshot when the newest snapshot fails, exposes a restore-health report in diagnostics, and creates an in-app attention event only for fallback/failure cases. Fallback/failure now also shows a concise startup toast with restored workspace/web/file counts and a direct "view event" path into the notification panel. Restore reports include original/restored/dropped web and file tab counts plus missing file paths, so partial recovery can tell the user what disappeared. Opening a file tab now triggers session persistence when the workspace file-tab state changes, closing a gap where a normal relaunch could lose a just-opened file tab. Browser interaction state capture now archives non-`Data` WebKit state blobs when available, and `browser.select` lets scripts jump back to an existing restored web tab instead of only acting on whichever tab happens to be selected. `session.restorePrevious`, `ConductorCLI session restore-previous`, and the command-palette "Restore Previous Session" action now let a user intentionally replace the current workbench with the previous valid compact snapshot while preserving the current snapshot as the new previous one on save. `terminal.resumeAgent`, `terminal.resumeAgents`, `ConductorCLI terminal resume-agent`, `ConductorCLI terminal resume-agents`, the command-palette "Resume Workspace Agents" action, and the terminal tab context menu now let users explicitly send supported canonical resume commands, while `--dry-run` verifies the action without launching external agents. `dogfood-workbench.sh` now verifies both the ordinary relaunch path and the corrupt-current fallback path: it creates three workspaces with split terminals, browser tabs, file tabs, and unread attention events, submits terminal commands with an explicit Enter key, creates a local two-step browser page flow, relaunches against the same isolated state path, verifies `sessionRestore.state == restored`, selected workspace, web count, restored browser URL/page text after `browser.select`, restored terminal user title/cwd/readable output, restored supported-agent resume command/session ID plus single-terminal and current-workspace batch resume dry-runs, executes current-workspace batch resume against a local fake supported-agent binary, verifies restored-terminal process status `fresh-after-restore`, file count, unread count, and restored file surface, then switches to a different workspace, runs `session restore-previous`, verifies `restoredFromPrevious`, verifies the selected workspace returns to the previous release workspace, corrupts the current state file, injects a missing file tab into the previous snapshot, verifies `sessionRestore.state == restoredFromPrevious`, verifies the missing file path is reported, and confirms a `sessionRecovery` attention event. Terminal process reattach, real external-agent continuation dogfood, and no-reload WebKit restoration remain open.

**2026-06-04 journal replay update:** Added a pure session-journal replay engine that rebuilds a workbench skeleton from semantic events when compact snapshots are missing or invalid. It restores workspace titles/order/selection, split-created terminal placeholders with known terminal IDs/cwd, web tab open+navigate URLs, file tab paths, close events, and selected content where the journal contains enough information. `WorkspacePersistence.load()` now falls back to this path and reports `restoredFromJournal`; Settings > Overview, startup recovery toasts, in-app `sessionRecovery` events, `session inspect`, and recovery recommendations understand the new state. New `SessionJournalTests` cover replay and close-event behavior, and an isolated launch smoke verified no compact snapshot plus a temporary journal restores two workspaces, one web tab, and reports `restoredFromJournal` through `ConductorCLI session inspect --json`.

**2026-06-04 restore inspector productization:** Recovery issues now carry user-impact text plus a structured `primaryAction` with kind, title, detail, icon, and destructive flag. Settings > Overview uses the same model to show action-shaped recovery rows instead of generic jump arrows: browser load errors reload the selected tab, blank browser tabs focus the address field, and terminal/file issues jump to the exact affected surface with clearer impact copy. `session inspect` exposes the same `impact` and `primaryAction` fields, and `control-smoke.sh` verifies browser runtime-error recovery issues include both fields. This is primary workbench progress; AI-channel work remains deferred until the core recovery, browser, attention, command, native-UX, update, diagnostics, and dogfood bars are met.

**2026-06-03 verification:** `swift build --product Conductor`, `swift build --product ConductorCLI`, `swift run ConductorModelCheck`, `./Scripts/swift-test.sh --filter ControlProtocolTests --skip-build`, `./Scripts/swift-test.sh --filter SessionJournal`, and a live isolated `./Scripts/control-smoke.sh` run all passed.

**Acceptance:**
- Kill the app while four panes are running commands, restart, and see the same workspace, selected tabs, titles, browser tabs, and notifications.
- Corrupt the latest state file and confirm the app recovers from the previous good snapshot or journal without blanking the workspace.

---

## Track C: Attention System

**Human Problem:** A notification is not useful if the user hears a sound but cannot tell what finished, where it happened, or whether macOS blocked the banner.

**Files:**
- Modify: `Sources/Conductor/App/AgentReplyNotificationService.swift`
- Modify: `Sources/Conductor/App/ConductorAgentHookBridge.swift`
- Modify: `Sources/Conductor/App/AgentNotificationHookInstaller.swift`
- Modify: `Sources/Conductor/UI/Shell/ShellRootView.swift`
- Modify: `Sources/Conductor/UI/Sidebar/ConductorSidebar.swift`
- Create: `Sources/Conductor/App/Notifications/ConductorNotificationCenter.swift`
- Create: `Sources/Conductor/App/Notifications/ConductorNotificationModel.swift`

- [x] Create an in-app notification store independent of macOS notification delivery.
- [x] Every agent-hook/control notification creates an in-app event with workspace ID, terminal ID or web tab ID when known, title, body, timestamp, read/unread state, source, and focus action.
- [x] Wire protocol `notification.create`, `notification.list`, `notification.focus`, and `notification.clear` to the in-app attention store.
- [x] Add unread badges to workspace/sidebar/tab states, not only the notification panel.
- [x] Add "jump to latest unread" and "mark current workspace read".
- [x] Make macOS permission status explicit in settings: allowed, denied, not requested, unavailable, and unknown.
- [x] Add a real test notification path that reports whether it was added to Notification Center, not merely whether sound played.
- [x] Support common terminal notification escapes where feasible: OSC 9, OSC 777, and task-finished signals from supported agent hooks.
- [x] Debounce duplicate notifications per terminal but never silently drop all diagnostics.
- [x] Add notification click behavior: focus workspace, select terminal, clear unread state.
- [x] Add a small, tasteful in-app toast for cases where macOS banners are denied or delivery fails.

**2026-06-03 Track C status:** Added `ConductorAttentionEvent` and `ConductorAttentionStore` in `ConductorCore`, model wrappers for create/list/focus/clear, agent reply hook persistence, protocol notification create/list/focus/clear/focusLatest/markRead/test, diagnostics attention summary, CLI clear-by-ID/focus/latest/mark-read/test paths, a top-toolbar notification panel with unread count, latest-unread jump, current-workspace mark-read, jump-to-target, clear-one, clear-all, and notification-permission check, plus compact unread indicators in workspace rows, collapsed sidebar workspace icons, and top workspace tabs. System notification permission/delivery failures now show a shell-level toast with a settings/check action while preserving the in-app attention event. Settings show explicit allowed/denied/not-requested/unavailable/unknown permission states and can send a test notification that reports whether Notification Center accepted it. The system-notification delivery policy now lives in `ConductorCore` and has unit coverage for allowed, denied, not-requested, unavailable, unknown, delivery success, and delivery failure outcomes. Duplicate agent-reply bursts from the same terminal/source now coalesce into one unread event with a visible merged-count badge and diagnostics. Ghostty desktop-notification actions from terminal escape sequences now create in-app terminal alert events with focus targets and attempt macOS banners. Agent-reply and terminal-attention macOS banners carry the in-app attention event ID; clicking a banner focuses the stored event, selects the target terminal when available, marks the event read, and falls back to terminal-target matching for older notifications. Background non-agent command completion now creates command-finished events for failed or long-running unattended commands, with control-smoke coverage for jumping back to the originating terminal. The panel participates in shell-panel mutual exclusion and blocks background terminal focus/shortcuts. End-to-end `.app` automation for denied/authorized macOS Notification Center states remains open.

**2026-06-03 Track C verification update:** `CONDUCTOR_NOTIFICATION_AUTORUN=1`
now uses an isolated state path, creates a terminal-targeted attention event,
opens the notification panel, focuses the event, verifies the panel stays open,
marks the event read, and confirms focus returns to the target terminal. This
turns notification testing from "did something launch" into the user-facing loop
that matters: store, show, jump, clear unread, and keep context stable.

**2026-06-03 modal containment update:** The shell-panel autorun now opens
settings and synthesizes Cmd-T, Cmd-W, Cmd-D, Cmd-N, and Cmd-K through the app
window. The run passes only when settings remains open, command/workspace/
notification panels stay closed, workspace counts and terminal counts do not
change, and the selected content remains stable. Verified with
`shortcut-blocked=true`.

**2026-06-04 shell-panel containment update:** The shortcut router now treats
the command palette, settings, workspace overview, notification panel, and
terminal search as shortcut-blocking shell panels. Unrelated global commands are
consumed before they can mutate background tabs, terminals, panes, web tabs, or
file tabs; only the visible panel's own close/toggle-style shortcut is allowed
through. The shell-panel autorun now directly opens settings, command palette,
workspace overview, notifications, and terminal search, sends Cmd-T/Cmd-W/Cmd-D/
Cmd-N/Cmd-K/Cmd-O/Cmd-F through the app window, and verifies
`shortcut-blocked=true`.

**Acceptance:**
- If macOS banners are blocked, the user still sees an in-app event and a clear settings message.
- Clicking a notification reliably opens the right workspace and terminal.
- A completed agent creates exactly one visible attention event unless duplicate suppression is clearly logged.

---

## Track D: Browser Surfaces

**Human Problem:** Embedded web tabs are only valuable if they behave like useful work surfaces. For agent workflows, browser tabs must be controllable, inspectable, and resilient.

**Files:**
- Modify: `Sources/Conductor/UI/Web/ConductorWebSurfaceStore.swift`
- Modify: `Sources/Conductor/UI/Web/ConductorWebSurfaceRepresentable.swift`
- Modify: `Sources/Conductor/UI/Web/ConductorWebWorkspaceView.swift`
- Create: `Sources/Conductor/UI/Web/ConductorWebAutomation.swift`
- Create: `Sources/Conductor/UI/Web/ConductorWebSnapshotExporter.swift`

- [ ] Add default DuckDuckGo/search behavior for address input while preserving direct URL detection.
- [ ] Add stable tab loading states: pending, loading, complete, failed, blocked.
- [x] Add `browser.snapshot` through the control protocol: title, URL, bounded visible text, links, form fields, buttons, and selected text.
- [x] Add `browser.screenshot` returning a PNG path.
- [x] Add `browser.click`, `browser.fill`, `browser.press`, `browser.evaluate`, and `browser.find`.
- [x] Add `browser.wait` for load, selector, visible element, and text conditions with bounded timeout.
- [ ] Use safe JS bridges, main-frame-only where possible, with visible failure messages for cross-origin or blocked operations.
- [ ] Add page crash/navigation error UI that is compact and actionable.
- [ ] Persist web interaction state and avoid accidental reload loops.
- [ ] Add per-tab favicon/title caching and graceful fallback.
- [ ] Add history menu and "copy markdown reference".
- [x] Add browser smoke tests using a local HTML fixture.

**2026-06-03 Track D status:** Added async control-router support for WebKit operations and implemented `browser.snapshot`, `browser.screenshot`, `browser.click`, `browser.fill`, `browser.press`, `browser.wait`, `browser.find`, and `browser.evaluate` through the local protocol and CLI. Snapshots read bounded visible page text, selected text, links, form fields, and buttons from the current page without dumping cookies, local storage, or password values. Screenshots capture the current visible WebKit viewport as a PNG in the temporary Conductor browser screenshot directory and return path, size, scale, title, URL, and web tab ID. Basic DOM automation targets snapshot refs or CSS selectors on the visible WebKit tab, and `browser.wait` covers load, selector, visible element, and text conditions with a bounded timeout. Common automation failures now return typed `automationError` details for missing selectors, invalid selectors, missing snapshot refs, non-editable fill targets, missing text, script errors, unsupported Promise results, and timeouts. `Scripts/control-smoke.sh` opens a local HTML fixture and verifies browser load, reload, selector wait, snapshot, fill, press, text wait, click, find, evaluate, screenshot, stop, and the negative typed-error cases above against an isolated live app. Dialog/download handling, safe-bridge hardening, advanced wait states, loading-state UI, richer user-facing error/state UI, frame coverage, and stress coverage remain open.

**2026-06-04 Track D primary update:** Browser surfaces now handle JavaScript
alert/confirm/prompt requests with native macOS sheets instead of silently
blocking or failing. WebKit downloads now write a persisted `downloadState` to
the web tab model with phase, filename, destination, failure message, and update
time. The browser toolbar shows a compact download status pill and finished
downloads can be revealed in Finder; `surface.list` exposes the same redacted
download state for scripts and diagnostics. `control-smoke.sh` now opens a
local binary fixture, waits for `download.phase == finished`, verifies the
downloaded destination exists, and removes the fixture result. Still open:
safe-bridge hardening, frame and cross-origin coverage, and broader stress
coverage. URL/title/idle/hidden/gone wait states were added in the later
browser wait-state update.

**Acceptance:**
- A script can open a local fixture page, click a button, fill an input, read the resulting DOM text, and screenshot the page.
- Closing and reopening the app restores web tabs without surprise refresh loops.

---

## Track E: Workspace Intelligence

**Human Problem:** The UI must answer orientation questions quickly: which project, what is running, what needs attention, and what changed.

**Files:**
- Modify: `Sources/Conductor/UI/Sidebar/ConductorSidebar.swift`
- Modify: `Sources/Conductor/UI/WorkspaceTabs/WorkspaceTabStrip.swift`
- Modify: `Sources/Conductor/UI/ConductorWindowModel.swift`
- Create: `Sources/Conductor/App/WorkspaceMetadata/WorkspaceMetadataService.swift`
- Create: `Sources/Conductor/App/WorkspaceMetadata/PortScanner.swift`

- [x] Track workspace root/cwd separately from focused terminal cwd.
- [x] Show project name, shortened path, running port count, agent state, unread count.
- [x] Add compact sidebar rows that do not feel like dashboards.
- [x] Add hover/detail popovers for paths, local services, ports, and active tasks.
- [x] Add a "workspace inspector" panel with terminals, web tabs, files, notifications, and metadata.
- [x] Feed workspace tabs from metadata without turning them into dashboards.
- [x] Detect common dev servers from process/web-tab context and expose quick open links.
- [ ] Add workspace color/icon only as subtle identity, not large decorative branding.
- [ ] Make metadata polling visibility-scoped and debounced.

**2026-06-03 Track E status:** Added the first workspace intelligence data
plane through `WorkspaceMetadataSnapshot`, `WorkspaceMetadataService`, and the
`workspace.metadata` control method. `ConductorCLI workspace metadata
[--workspace workspace-id]` now returns selected workspace context, title,
project/root, terminal/browser/file counts, terminal summaries, workspace-owned
file/web tab summaries, running ports and local dev-server summaries, active agent count, unread
attention count, health, and refresh time. `control-smoke.sh` checks the
selected workspace metadata path plus a non-selected workspace file/web
ownership path, including terminal/file/web arrays and a live localhost fixture
server, so this is no longer only a UI ambition. The sidebar now consumes cached workspace metadata, preferring detected project root
for the subtitle, adding compact port/health signals, and using native hover
help for full path, ports, active agents, and unread
work. The workspace panel now uses a list-plus-inspector layout: selecting a
workspace shows root, health, refresh time, terminal summaries, workspace-owned
file tabs, workspace-owned web tabs, local service links, unread work, running agents, and concrete
actions to switch, open the first detected service, jump to an open file/web tab
across workspaces, or open the project root in Finder. Top workspace tabs now consume the same cached
metadata: selected/hovered tabs show first-port pills when there is room, show a
health warning icon when metadata is partial, expose full root/port details
through native hover help, and offer context-menu actions
to open the project root or first detected port. The most recent fast release
gate passed with build, dogfood, control smoke, stress, update fixture, and
performance checks enabled except tests, autorun, bundle, and screenshot
capture. Open work remains richer per-tab actions, synchronous editor buffer
state, real-agent context, and explicit visibility-scoped metadata refresh proof.

**Acceptance:**
- Looking at the sidebar for two seconds tells the user which workspaces are alive, idle, errored, or waiting.
- Metadata never causes terminal scroll or tab switching to feel slower.

---

## Track F: Command Layer

**Human Problem:** Power users should not hunt through buttons. New users should still understand what commands do.

**Files:**
- Modify: `Sources/Conductor/UI/ConductorShellCommand.swift`
- Modify: `Sources/Conductor/UI/Shell/ShellRootView.swift`
- Modify: `Sources/Conductor/UI/ConductorKeyboardShortcutPreferences.swift`
- Modify: `Sources/Conductor/UI/Settings/SettingsSections.swift`
- Modify: `Sources/Conductor/UI/Settings/SettingsControls.swift`

- [x] Make the command palette read from the canonical shell-command registry instead of a separate hardcoded list.
- [x] Add command categories for create, navigation, organize, web, context, search, and view actions.
- [x] Add command descriptions that explain outcome, not marketing copy, and show them in the command palette and `command.list`.
- [x] Add recent commands and context-weighted ranking.
- [x] Ensure settings/modals block unrelated global shortcuts except allowed close/toggle commands.
- [x] Finish user-defined shortcuts: record, clear, restore default, conflict detection, reserved system shortcut warnings.
- [x] Add import/export shortcut profile.
- [ ] Add tooltips back to every icon-only button with shortcut hints.
- [ ] Add menu bar/native menu entries for key commands where macOS users expect them.

**Acceptance:**
- Every toolbar/sidebar/panel action is discoverable from the command palette.
- Opening settings prevents background terminal/tab shortcuts from firing through the panel.

**2026-06-03 Track F status:** Added canonical metadata to `ConductorShellCommand`: catalog ID, category, title, outcome description, keywords, fallback shortcut, icon, and protocol method. The command palette now generates rows from `ConductorShellCommand.paletteOrder`, so the visible command list, shortcut guide, and command execution path share one registry. Command rows now show a plain outcome line, while disabled rows show the reason. `command.list` exposes the same metadata and includes the disabled reason in `command.run` errors; `control-smoke.sh` verifies the command metadata contract. Settings shortcut containment is also covered through the shell-panel autorun regression.

**2026-06-04 attention command update:** Added command-palette actions for "Jump
to Latest Unread" and "Mark Current Workspace Read", both backed by the same
attention store and protocol methods as the notification panel. CLI `notify`
can now create targetable events with `--workspace`, `--terminal`, or
`--web-tab`, so scripts can create attention events that jump to the exact
surface. `control-smoke.sh` creates targeted attention events in two
workspaces, verifies jump-latest prefers the selected workspace even when a
newer event exists elsewhere, verifies the second invocation falls back to the
latest global unread event, and verifies mark-current-workspace-read clears the
current workspace event without moving focus. Remaining work: full toolbar/
sidebar/context-menu action audit.

**2026-06-04 command ranking update:** Command execution now records a bounded
recent-command list, and the command palette sorts with a shared ranking model
that combines executable state, recent use, and current context such as web tab,
file tab, terminal/current directory, unread attention, session recovery, and
resumable agents. Palette rows show a small ranking badge and tooltip when a row
is recent or context-relevant. `command.list` exposes the same `ranking` object
for scripts, including score, recent flag, recent rank, context reasons, and
badge. The isolated `control-smoke.sh` path now runs a command, then verifies
`command list` returns that command with `ranking.recentRank == 0` and a recent
badge. Remaining work: full toolbar/sidebar/context-menu action audit.

**2026-06-04 shell-panel shortcut update:** `routeAppShortcut` now blocks
background command execution while command palette, settings, workspace
overview, notifications, or terminal search are visible. The shell-panel autorun
expanded from settings-only coverage to settings + command palette + workspace
overview + notifications + terminal search, proving Cmd-T/Cmd-W/Cmd-D/Cmd-N/
Cmd-K/Cmd-O/Cmd-F cannot change hidden workspaces, panes, tabs, web tabs, or
file tabs under those panels. Remaining work: full toolbar/sidebar/context-menu
action audit.

**2026-06-04 browser command update:** Browser back/forward are now canonical
shell commands with catalog IDs `web-back` and `web-forward`, disabled reasons,
command-palette metadata, protocol exposure through `command.run`, and current
web-tab context ranking. High-frequency toolbar/sidebar/web actions now route
through `performCommand` instead of separate direct model calls, including the
toolbar notification button, sidebar Token records entry, web navigation,
reload, copy link/reference, external-open, and web find navigation. The control
smoke now verifies the new browser commands remain present in `command.list`.
Remaining work: full toolbar/sidebar/context-menu action audit.

**2026-06-04 action-audit follow-up:** The Web power menu's duplicate action now
uses `duplicateSelectedTab` instead of a private duplicate helper, and the
terminal-search submit/previous/next controls now use `findNext`/`findPrevious`
instead of directly calling terminal search navigation. `duplicateSelectedTab`
also now has a real disabled reason for the no-target edge case. Remaining
work: row-specific toolbar/sidebar/context-menu action audit.

**2026-06-04 shortcut profile update:** The settings command page now has
compact import/export actions for shortcut profiles. Profiles are versioned JSON
files with command IDs and shortcut definitions, rather than raw app state.
Import replaces the current custom profile, ignores commands that no longer
exist, rejects reserved shortcuts such as Cmd-Q, and resolves conflicts with the
same "new shortcut wins" rule as the recorder. The
`CONDUCTOR_SHORTCUT_PROFILE_AUTORUN=1` gate verifies import/export, unknown
command handling, reserved-shortcut rejection, conflict resolution, and the
final exported custom-shortcut count. Remaining work: full toolbar/sidebar/
context-menu action audit.

**2026-06-04 file/tab command audit update:** File-tab actions now have
canonical commands for "Open Current File in System App" and "Reveal Current
File in Finder", with command metadata, disabled reasons, context ranking,
diagnostic events, and command-list smoke assertions for catalog IDs
`file-open-external` and `file-reveal-finder`. The file workspace toolbar, large
file fallback buttons, and top file-tab context menu now route through those
commands. Top file/web tab close and web external-open actions select their
target and then use the same command path as shortcuts and the command palette.
`duplicateSelectedTab` now truly handles file tabs by reopening the selected
file tab instead of accidentally duplicating a background terminal. Remaining
work: deeper workspace-row close-other/close-right command coverage and the
rest of the row-specific context-menu audit.

**2026-06-04 native menu update:** The macOS View menu now exposes the same
canonical web/file context commands used by the toolbar, command palette, and
context menus: web back, web forward, open current file in the system app, and
reveal current file in Finder. `validateMenuItem` uses the shared command
mapping, so menu enabled states match the selected surface. Added
`CONDUCTOR_MENU_AUTORUN=1` and wired it into `check-conductor.sh`; the autorun
verifies these menu selectors exist and map back to the expected shell commands.
Remaining work: finish native menu coverage for the rest of the high-frequency
command registry.

**2026-06-04 workspace command update:** Workspace-level close actions now live
in the canonical shell command registry: duplicate workspace, close other
workspaces, close workspaces to the right, and close current workspace. The
sidebar and top workspace-tab context menus activate the target workspace first,
then execute the same command path used by the command palette, protocol, and
native File menu. Close-to-right menu items now disable correctly for the
rightmost workspace instead of merely checking whether multiple workspaces
exist. `CONDUCTOR_MENU_AUTORUN=1` now checks eight menu mappings, and
`control-smoke.sh` verifies the workspace command catalog IDs and
`command.run` protocol methods. Remaining work: rename workspace command
coverage and deeper workspace inspector action audit.

**2026-06-04 workspace context command update:** Project-root and local-service
workspace actions now also live in the canonical command registry. "Open Current
Workspace Root" opens the cached project root in Finder, and "Open Current
Workspace Local Service" opens the first detected dev server or localhost port
as a workspace web tab. The top workspace tab menu, sidebar row menu, workspace
overview row menu, and workspace inspector quick actions activate the target
workspace first, then run the shared command. These commands expose disabled
reasons when metadata has no root or service, record diagnostics with the
resolved path/URL, appear in the native File menu, are included in the
`CONDUCTOR_MENU_AUTORUN=1` ten-item menu check, and are asserted in
`control-smoke.sh` through catalog IDs `workspace-open-root` and
`workspace-open-service`.

**2026-06-04 workspace rename command update:** "Rename Current Workspace" is now
a first-class shell command instead of a toolbar-only behavior. The command lives
in the canonical registry with palette metadata, File menu routing, protocol
`command.run` support, command-list smoke assertions for catalog ID
`rename-workspace`, and the eleven-item selector-to-command menu autorun. It
triggers the existing top-tab inline rename flow through `WorkspaceRenameRequest`
so users edit the workspace title in place instead of getting another modal.
Remaining work: exact multi-service command variants and the remaining
row-specific context action audit.

---

## Track G: Native UX Polish

**Human Problem:** The app must stop feeling assembled. Every motion, hover, drag, empty state, and panel should feel like the same product.

**Files:**
- Modify: `Sources/Conductor/UI/ConductorDesign.swift`
- Modify: `Sources/Conductor/Shared/AppearancePreferences.swift`
- Modify: `Sources/Conductor/UI/Controls/ConductorIconButton.swift`
- Modify: `Sources/Conductor/UI/Controls/ConductorCommandButton.swift`
- Modify: `Sources/Conductor/UI/Settings/SettingsPanel.swift`
- Modify: `Sources/Conductor/UI/Shell/ShellRootView.swift`
- Modify: `Sources/Conductor/UI/Toolbar/ConductorToolbar.swift`

- [ ] Define a single token table for radius, elevation, opacity, hover, pressed, disabled, focus ring, and animation timing.
- [ ] Remove stray selected indicator bars unless the theme explicitly uses them.
- [ ] Audit every panel for scrolling, drag-to-move, resize, keyboard close, and focus restoration.
- [ ] Reduce "AI dashboard" visual language: fewer giant cards, fewer badges, less decorative glow, more native grouping.
- [ ] Add at least ten themes, but implement them through tokens, not one-off color hacks.
- [ ] Make dark/light/glass/gradient themes readable, restrained, and consistent.
- [ ] Add compact density and comfortable density that affect tabs, sidebars, and toolbars coherently.
- [ ] Fix tab click/drag thresholds so clicking does not accidentally become dragging.
- [x] Smooth the first terminal scroll path by coalescing precise wheel input and scrollbar updates to short frame windows, while keeping mouse-wheel scrolling immediate.
- [ ] Add hover hints to all icon buttons and delayed help tags.
- [ ] Make settings smaller, calmer, and more mac-native: fewer huge panels, stronger grouping, better scrolling.

**Acceptance:**
- A screenshot of any panel should look like the same app.
- Basic actions have visible feedback but do not animate theatrically.
- No visible text overlaps, clipped labels, mystery icons, or panels without scrolling.

---

## Track H: Updates & Distribution

**Human Problem:** Users do not care about manifests, asset URLs, or GitHub release internals. They care that update is visible, fast, safe, and understandable.

**Files:**
- Modify: `Sources/Conductor/App/Updater/ConductorUpdateService.swift`
- Modify: `Sources/Conductor/App/Updater/ConductorUpdateState.swift`
- Modify: `Sources/Conductor/UI/Toolbar/ConductorToolbar.swift`
- Modify: `Sources/Conductor/UI/Settings/SettingsUpdateSection.swift`
- Modify: `Scripts/package-release.sh`
- Modify: `Scripts/publish-github-release.sh`
- Create: `Scripts/update-fixture.sh`

- [x] Add a top toolbar update pill/button when an update exists.
- [x] Add an hourly automatic update check loop that respects the user preference and stops when the manifest is unavailable.
- [x] Add backoff and richer diagnostics for repeated background update-check failures.
- [ ] Hide raw URL/manifest/internal availability text from normal users.
- [ ] Show clean states: checking, up to date, update available, downloading, ready to install, failed.
- [ ] Show progress bar, downloaded size, speed if reliable, and cancel/retry.
- [x] Add a settings-panel cancel action during downloads and keep the top toolbar update pill tooltip explicit about progress/cancel.
- [x] Add control commands for update status, check, download, cancel, rehearse-install, and install.
- [x] Allow isolated tests to use a transient manifest URL and temporary update download directory without persisting user settings.
- [x] Verify SHA-256, bundle ID, and codesign before replacing.
- [x] Add an update fixture that proves a local available update downloads and a tampered asset fails before install.
- [x] Add slow local-copy update fixture coverage that proves `downloadProgress` changes during an in-flight download.
- [x] Add in-flight cancel fixture coverage that proves the update returns to an available, retryable state before a later download.
- [x] Add non-destructive installer rehearsal coverage that stages a signed fixture `.app`, checks bundle ID, and verifies strict codesign before replacement.
- [ ] Handle ad-hoc signing gracefully with clear first-launch docs.
- [ ] Publish arm64 and x86_64 assets consistently.
- [ ] Add release script validation that expected files exist before uploading.
- [ ] Add release notes and changelog rendering inside the update panel.

**Acceptance:**
- A user can update without seeing a manifest URL.
- A failed update explains in human terms what happened and offers retry/open releases.

---

## Track I: Observability & QA

**Human Problem:** If the app is meant to be trusted, we need to know when it is slow, broken, or quietly dropping state.

**Files:**
- Modify: `Scripts/check-conductor.sh`
- Modify: `Scripts/stress-conductor.sh`
- Modify: `Sources/Conductor/Shared/ConductorDiagnostics.swift`
- Modify: `Sources/Conductor/Shared/ConductorMainThreadWatchdog.swift`
- Create: `Scripts/dogfood-workbench.sh`
- Create: `Scripts/capture-release-screenshots.sh`

- [x] Expand smoke tests for control protocol, notifications, browser automation, update states, and session restore fallback.
- [x] Expand smoke tests for shortcut-driven workspace mutations.
- [ ] Expand smoke tests for full session replay/agent restore.
- [x] Add stress tests for long output, resize while output, 20 terminals idle, 10 web tabs, and rapid workspace switching.
- [x] Add main-thread stall diagnostics with readable event names.
- [ ] Add render counter budget checks for settings and usage panels.
- [x] Add a diagnostics bundle command that exports redacted logs, state summary, update state, notification state, and control environment.
- [x] Add recent protocol error history to diagnostics export.
- [x] Add main-thread stall/performance budget sections to diagnostics export.
- [x] Add full sampled performance budget reports with sampled/missing budget counts, over-budget samples, and slowest recent sample.
- [x] Add dogfood release gate threshold enforcement for workspace switch, terminal tab switch, terminal scroll-frame, browser restore, settings open, and command palette open budgets.
- [x] Add update-fixture threshold enforcement for `update.check` budget behavior.
- [x] Record sampled budget results for control-driven workspace switch, terminal tab switch, and browser open/navigate paths.
- [x] Record sampled budget results for settings open, command palette open, and update check completion paths.
- [x] Record terminal scroll-frame budget samples from real wheel events and a control-driven `terminal sample-scroll` smoke path.
- [x] Add screenshot capture for README and release notes from real app windows.
- [x] Add isolated dogfood script that creates a realistic multi-workspace protocol run without touching user state.
- [x] Add isolated update fixture for available/download/checksum-failure coverage without touching user settings or update cache.
- [ ] Extend dogfood script to launch supported real agent completion/resume flows instead of harmless terminal markers.
- [ ] Add performance acceptance notes: cold launch time, settings open time, tab switch latency, scroll feel, update check latency.

**Acceptance:**
- Before release, one command can run build, model checks, smoke checks, stress checks, and screenshot capture.
- Diagnostics answer "why did notification/update/session restore fail?" without guessing.

**2026-06-03 Track H/I status:** Reworked `Scripts/check-conductor.sh` into an isolated release-gate entry point. It builds `Conductor` and `ConductorCLI`, runs `ConductorModelCheck`, optionally runs the full Swift test suite, runs the isolated dogfood/control-smoke flow, keeps the older autorun regression scenarios in the default path, runs protocol stress, runs the update fixture, can build the app bundle, and verifies release screenshot capture unless `CONDUCTOR_CHECK_SKIP_SCREENSHOTS=1` is set. `Scripts/stress-conductor.sh` covers the older long-output and resize-while-output autoruns plus an isolated protocol stress pass for 20 idle terminal tabs, 10 browser tabs, and 24 rapid workspace switches. `Scripts/update-fixture.sh` starts an isolated app with a temporary home, control socket, state file, manifest, current-app override, and update download directory; `CONDUCTOR_UPDATE_FIXTURE_SKIP_BUILD=1 ./Scripts/update-fixture.sh` passed available update, slow in-flight progress polling, in-flight cancel back to a retryable state, verified signed `.app` download, non-destructive installer staging/codesign rehearsal, tampered checksum failure coverage, and `update.check` performance-gate coverage. The settings update panel now exposes a cancel action while downloading, the top toolbar update pill tooltip names the progress/cancel path, and automatic update checks now continue about once per hour while enabled, back off repeated background failures, and expose `automaticChecks` diagnostics through update status/export. Terminal wheel scrolling now records throttled `terminal.scroll-frame` budget samples, `control-smoke.sh` verifies a control-driven `terminal sample-scroll` path appears in diagnostics, and `performance.report` now summarizes sampled/missing budgets, recent over-budget samples, and the slowest recent sample. `Scripts/performance-gate.sh` now reads diagnostics exports and enforces required sampled budgets plus over-budget thresholds for dogfood UI budgets and update-fixture `update.check` samples. The quick gate `CONDUCTOR_CHECK_SKIP_TESTS=1 CONDUCTOR_CHECK_SKIP_AUTORUN=1 CONDUCTOR_CHECK_SKIP_BUNDLE=1 CONDUCTOR_CHECK_SKIP_SCREENSHOTS=1 ./Scripts/check-conductor.sh` passed with dogfood/control-smoke, `performance_gate=ok`, protocol stress, and update fixture progress/performance samples. `Scripts/capture-release-screenshots.sh` starts an isolated Conductor instance, drives it through `ConductorCLI`, captures only Conductor-owned windows by PID/title, masks sensitive account/path areas, and writes a release screenshot manifest for workbench, token records, notifications, browser, command palette, and settings. Full Swift test gate, bundle gate, destructive replacement/relaunch rehearsal, speed/retry update UX, and real-agent dogfood remain open.

**2026-06-04 terminal scroll feel update:** `TerminalSurface` now coalesces precise trackpad wheel deltas into short frame windows before sending them to Ghostty, flushes immediately for non-precise mouse wheels and ended/cancelled momentum phases, and coalesces Ghostty scrollbar updates by the same short delay. Coalesced batches record `terminal-scroll-coalesced` diagnostics and still feed `terminal.scroll-frame` budget samples through the existing performance diagnostics. `swift build --product Conductor`, isolated `control-smoke.sh`, `terminal sample-scroll`, and the normal `dogfood-workbench.sh` restore path passed after the change. This is the first concrete fix for blocky terminal scrolling; broader manual validation on different trackpads/mice and long-output sessions still remains before claiming the entire scroll-feel problem is solved.

**2026-06-03 verification tightening:** The shortcut autorun now fails unless the workspace model stays valid and the final shortcut-driven shape is exactly `panes=3`, `terminals=3`, and `zoomed=true`. The long-output stress autorun no longer allows a zero-output success: by default it writes 65,536 characters into each visible split terminal, sends a real Return key through the terminal host view, waits for one marker per target, and the check/stress scripts require `target_terminals=3`, `total_characters=196608`, and `completed_terminals=3`.

**2026-06-03 tightened core gate:** `CONDUCTOR_CHECK_SKIP_BUILD=1 CONDUCTOR_CHECK_SKIP_TESTS=1 CONDUCTOR_CHECK_SKIP_BUNDLE=1 CONDUCTOR_CHECK_SKIP_SCREENSHOTS=1 ./Scripts/check-conductor.sh` passed after the tightened shortcut, notification, workspace, shell-panel, and long-output stress assertions. This is still a core gate, not a complete cmux-level finish line: full unskipped tests, bundle/screenshots, real-agent dogfood, deeper replay, and the remaining feature work are still open.

**2026-06-03 normal restore gate:** The same core gate passed after adding ordinary relaunch verification to `dogfood-workbench.sh`. The dogfood path now catches file-tab persistence regressions before release by opening a real file, waiting for it to land in `window-state.yaml`, relaunching, and checking the restored file surface alongside the exact restored browser URL, selected workspace, and unread attention count. It also now submits terminal commands with `terminal send-key enter`, so terminal dogfood steps are real command execution rather than text typed into a prompt.

**2026-06-03 restore surface gate:** `CONDUCTOR_CHECK_SKIP_BUILD=1 CONDUCTOR_CHECK_SKIP_TESTS=1 CONDUCTOR_CHECK_SKIP_BUNDLE=1 CONDUCTOR_CHECK_SKIP_SCREENSHOTS=1 ./Scripts/check-conductor.sh` passed after the dogfood gate began asserting exact browser URL restoration and real terminal command submission.

**2026-06-04 browser restore update:** Added `browser.select` to the control protocol and CLI so restored web tabs can be reactivated by ID and workspace. The local browser fixture now exposes a history marker from the URL query and enough vertical content to test scroll restoration. Web tabs now persist explicit navigation entries, the current navigation index, and scroll position in addition to WebKit's opaque interaction state. On relaunch, dogfood selects the restored tab, verifies the `release-2` page text, waits for the restored scroll position, then drives `browser back` to `release-1` and `browser forward` back to `release-2`. This gives users a practical restored browser context even when WebKit's own back/forward state is inconsistent. True no-reload WebKit session restoration still remains a higher bar, not a completed claim.

**2026-06-04 browser runtime diagnostics update:** Browser tabs now capture recent
main-frame `console.log/info/warn/error`, `window.onerror`, and
`unhandledrejection` events through a lightweight WebKit user script. The events
are stored on the web tab model, bounded to the latest 40 entries, persisted with
the tab, recorded in diagnostics, surfaced through `surface list`, included in
`browser snapshot`, and reported as a `web_runtime_error` warning in
`session inspect`/restore-health when page errors or console errors are present.
The browser toolbar now shows a compact "Page Error" menu pill only when an
actionable runtime event exists, with recent events and a copy action for the
latest error. Runtime events now clear on explicit navigation, reload, and
history movement so stale errors do not survive into an unrelated page.
`control-smoke.sh` verifies the local browser fixture emits a console error,
that the snapshot plus surface metadata expose it, and that navigating the same
tab to a clean local page resets the runtime-event count. This closes a
practical "browser is a black box" gap: when a tab or automation flow behaves
strangely, the user and scripts can inspect what the page itself reported
without carrying old failures forward. Remaining work: frame/cross-origin
runtime diagnostics, richer per-event source mapping, stress coverage, and
broader non-fixture browser coverage.

**2026-06-04 browser wait-state update:** `browser.wait` now supports URL,
title, idle/network-idle, hidden, and gone/detached states in addition to
load/ready, selector/visible, and text waits. The CLI accepts direct forms such
as `browser wait url <text>`, `browser wait title <text>`, `browser wait idle`,
`browser wait hidden <selector>`, and `browser wait gone <selector>`, with the
same typed timeout/invalid-selector failure path as existing browser
automation. `control-smoke.sh` verifies those new waits against the local
browser fixture and also asserts that a wrong URL wait times out cleanly. This
makes scripted browser workflows less dependent on arbitrary sleeps when a local
service changes URL, title, DOM visibility, or reaches a quiet loaded state.
Remaining work: frame/cross-origin wait coverage, stress coverage, and stronger
safe-bridge hardening.

**2026-06-04 browser frame-summary update:** `browser.snapshot` now includes a
bounded `frames` array for iframe/frame elements. Same-origin frames expose
title/name/source URL, visible state, frame URL, clipped text, and link/field/
button counts; sandboxed or cross-origin frames stay privacy-safe and report an
explicit inaccessible-frame reason instead of silently disappearing. The local
browser fixture now contains both an accessible same-origin `srcdoc` frame and a
sandboxed frame, and `control-smoke.sh` verifies same-origin frame text plus the
inaccessible-frame explanation. This gives users and scripts a practical answer
to "the page has content, why can the workbench not see or act on it?" without
pretending Conductor can pierce cross-origin browser boundaries. Remaining work:
deep frame-targeted actions, cross-origin action routing, stress coverage, and
safe-bridge hardening.

**2026-06-04 browser frame-action update:** Browser automation targets now
support same-origin frame routing with `frame-N >> selector` syntax. The shared
target resolver routes `browser.click`, `browser.fill`, `browser.press`, and
selector/text waits into accessible frame documents, while missing or inaccessible
frames return typed `frame_not_found`/`frame_inaccessible` automation errors.
`control-smoke.sh` now fills an input inside `frame-0`, clicks the frame button,
waits for frame-local completion text, and verifies the sandboxed frame rejects
actions with `frame_inaccessible`. This turns frame support from passive
diagnostics into a practical scripting tool for local previews and embedded
work surfaces, while keeping cross-origin boundaries explicit. Remaining work:
cross-origin action handoff, deeper frame stress coverage, and safe-bridge
hardening.

**2026-06-04 browser frame-find/evaluate update:** Browser search and script
evaluation now understand same-origin frames. `browser.find` searches the main
document plus accessible frames and reports a frame match summary such as
`frame-0:1`, while `browser.find --frame frame-0 <text>` scopes the search to a
single frame. `browser.evaluate --frame frame-0 <script>` evaluates inside that
frame's document/window, and inaccessible frame evaluation returns the typed
`frame_inaccessible` automation error. `control-smoke.sh` verifies frame-local
find/evaluate after a real frame fill/click flow and verifies the sandboxed
frame failure path. This completes the same-origin frame automation loop for the
common "embedded preview/control surface" case without claiming cross-origin
access. Remaining work: cross-origin handoff, stress coverage, and safe-bridge
hardening.

**2026-06-04 browser automation stress update:** `Scripts/stress-conductor.sh`
now exercises browser automation while it opens 10 browser tabs, instead of only
counting that tabs exist. Each tab loads the local fixture, waits for title,
fills a same-origin frame input, clicks the frame button, waits for the
frame-local completion text, verifies `browser.find --frame frame-0`, and
verifies `browser.evaluate --frame frame-0`; the script now reports
`browserAutomationIterations=10`. A targeted isolated run with
`CONDUCTOR_STRESS_SKIP_BUILD=1 CONDUCTOR_STRESS_SKIP_AUTORUN=1` passed. This
turns the browser/frame work from single-fixture smoke into repeatable protocol
stress evidence. Remaining work: longer-duration browser stress, cross-origin
handoff, and safe-bridge hardening.

**2026-06-04 terminal restore update:** Added `terminal.rename` and a protocol-level `quit` command so automated relaunch tests can save terminal scrollback through the app's normal shutdown path instead of killing the process. Terminal snapshot replay now waits until the fresh Ghostty surface is attached before painting the bounded VT/plain history back through the program-output path. `terminal.resumeAgent` and the terminal tab context menu now send supported canonical resume commands explicitly, with dry-run automation for release gates. `dogfood-workbench.sh` verifies that after an ordinary relaunch the release terminal still has its user title, cwd, readable visible output, and resumable agent command. It also puts a local fake supported-agent binary first on `PATH`, runs non-dry-run `terminal resume-agents --workspace current`, and waits for the restored terminal to print the resumed session ID. This proves explicit command delivery after restore; live process reattach and real external-agent continuation remain separate unfinished capabilities.

---

## Track J: Documentation & Onboarding

**Human Problem:** A serious external user should understand what Conductor is, how to install it, what permissions mean, and how to recover when things go wrong.

**Files:**
- Modify: `README.md`
- Modify: `docs/getting-started.md`
- Modify: `docs/security.md`
- Modify: `docs/updating.md`
- Create: `docs/api.md`
- Create: `docs/notifications.md`
- Create: `docs/session-restore.md`
- Create: `docs/troubleshooting.md`

- [ ] Rewrite README for external users first, contributors second.
- [x] Include real screenshots only: workbench, token/usage panel, settings, notifications, browser tab, command palette.
- [ ] Add GitHub activity/trend chart and explain project status honestly.
- [ ] Add install instructions for ad-hoc builds and Gatekeeper workaround.
- [ ] Add notification permission troubleshooting.
- [ ] Add update troubleshooting.
- [x] Add local control API docs with examples.
- [x] Add privacy/security page: local socket, update verification, no remote listener, what is stored locally.
- [x] Add notification, session restore, update, and troubleshooting docs with current limitations.
- [ ] Add "known limitations" for no paid Developer ID if still true.

**Acceptance:**
- A stranger can install, run, update, and troubleshoot Conductor from docs without asking the owner.
- Docs never expose internal integration names in user-facing product language unless required for developer docs.

**2026-06-03 Track J status:** Reworked the README user value and docs table, removed raw update manifest URLs from the external entry point, rewrote Getting Started/Updating/Security, and added `docs/api.md`, `docs/notifications.md`, `docs/session-restore.md`, and `docs/troubleshooting.md`. README media now uses current-build screenshots generated from the isolated release screenshot script for workbench, token records, notifications, browser, command palette, and settings. Video/GIF, fresh-user rehearsal, and final public copy pass remain open.

---

## Integration Milestones

These are not priorities. They are whole-system checkpoints.

- [x] **M1: Scriptable workspace** — control protocol can create and drive a real workspace.
- [ ] **M2: Trustworthy attention** — notification path works with allowed, denied, and unavailable macOS states.
- [ ] **M3: Restorable day** — crash/relaunch/update preserves a multi-pane, multi-web-tab session.
- [x] **M4: Browser as surface** — agent can open, inspect, click, fill, and screenshot a web tab.
- [ ] **M5: Native feel pass** — settings, command palette, notification panel, usage panel, and toolbar share tokens and motion.
- [ ] **M6: Release candidate** — arm64/x86_64 builds, updater, docs, screenshots, and diagnostics all pass.

---

## Definition Of Done

- [ ] Every track A-J has shipped code, tests or diagnostics, and documentation.
- [ ] `swift build` passes.
- [ ] `swift run ConductorModelCheck` passes.
- [ ] `./Scripts/check-conductor.sh` passes.
- [x] `./Scripts/stress-conductor.sh` passes.
- [x] Manual dogfood script creates a useful workspace from the CLI.
- [ ] App can be restarted during active work and returns to an understandable state.
- [ ] User-facing update UI contains no raw manifest URLs or internal asset wording.
- [ ] All icon-only controls have hover help.
- [ ] Settings, command palette, notification panel, and usage panel are scrollable, draggable/movable where expected, and do not leak shortcuts through modal overlays.
- [x] README and docs use real screenshots from the current build.

---

## Notes For Implementation

- Keep feature names user-facing. Internal imported package names should not appear in product UI unless the user is explicitly configuring that provider.
- Do not build giant dashboards. The target is calm orientation, fast action, and reliable state.
- Prefer pure `ConductorCore` logic for protocol models, workspace state, search, visibility, and tests.
- Keep AppKit/WebKit/Ghostty boundaries thin and heavily diagnosed.
- When adding protocol commands, add the UI command and CLI command through the same command model where possible.
- Every new background poll needs an owner, interval, visibility rule, and diagnostic event.
