# cmux-Level Delivery Contract

- **Date:** 2026-06-03
- **Purpose:** Define the exact product, engineering, QA, and docs contract required before Conductor can be called cmux-level useful.
- **Plan:** `docs/superpowers/plans/2026-06-03-cmux-level-workbench.md`
- **Design:** `docs/superpowers/specs/2026-06-03-cmux-level-workbench-design.md`
- **Matrix:** `docs/superpowers/specs/2026-06-03-cmux-level-capability-matrix.md`

This document is stricter than a roadmap. It is the delivery contract for the whole workbench. A row is not complete when it merely compiles. A row is complete when a human can use it, a script can verify it, diagnostics can explain failures, and public docs describe the current truth.

## How To Use This Contract

Every implementation slice must update four things:

1. Code path.
2. Verification command or manual acceptance note.
3. Plan/matrix status.
4. User-facing or developer-facing documentation, when the behavior is externally visible.

Do not mark a feature shipped if it only exists as a visual placeholder, a private helper, or a code path that cannot be reached from UI/protocol/tests.

## Completion Gate

Conductor is not considered cmux-level useful until all of these are true:

- Track A through Track J are at least L2 in the capability matrix.
- Session life, attention, browser automation, update flow, and diagnostics are L3.
- The whole-day acceptance story passes against a real app instance.
- A dogfood script can create workspaces, split terminals, open browser tabs, trigger notifications, inspect state, and export diagnostics without mouse automation.
- Public docs include real screenshots from the current app, installation notes, Gatekeeper/ad-hoc signing notes, update docs, notification troubleshooting, local control API docs, and known limitations.
- The app is still understandable when macOS notification permission is denied, update download fails, state restore is partial, browser automation fails, or a terminal process cannot be reattached.

Secondary AI-channel work does not count toward this completion gate. It may stay
in the repository as existing infrastructure, but it must not be used as evidence
that the workbench is closer to cmux-level usefulness unless it directly improves
one of the primary human loops above.

## Current Status Ledger

| Track | Current state | Evidence | Next required completion work |
| --- | --- | --- | --- |
| A. Control Protocol | L2 foundation live. | `ConductorControlServer`, `ConductorControlRouter`, `ConductorCLI`, `control-smoke.sh`, `dogfood-workbench.sh`, filtered protocol tests, browser select/snapshot/screenshot/click/fill/press/wait/find/evaluate methods, file open/reveal/save/snapshot methods with negative fixture coverage, synchronized editor-buffer state for `file.save` without `--text`, terminal/browser/file `surface.focus`, update status/check/download/cancel/rehearse-install/install methods, diagnostics export. | Broaden typed automation/state errors and continue hardening operation-specific UI feedback. |
| B. Session Life | L2 normal and fallback paths live. | `ConductorSessionJournal`, journal tests, journal replay fallback, `app.diagnostics` journal summary, `window-state.previous.yaml`, `session.inspect`, `session.restorePrevious`/CLI/command-palette recovery action, restore-health report with missing file paths, startup recovery toast, in-app `sessionRecovery` event, dogfood normal relaunch verification for selected workspace/web/file/unread state, exact restored browser URL/page text after `browser.select`, restored browser scroll, restored explicit back/forward fallback, restored terminal title/cwd/readable output, restored-terminal `fresh-after-restore` process explanation, supported-agent resume metadata capture/exposure, explicit `terminal.resumeAgent` and `terminal.resumeAgents` dry-run coverage, non-dry-run batch resume dogfood through a local fake supported-agent binary, active restore-previous verification, and corrupt-current-state fallback verification. | Deeper terminal/browser restore UI, no-reload browser restoration, actual process reattach implementation, and real external-agent continuation dogfood. |
| C. Attention System | L2 foundation live. | `ConductorAttentionEvent`, `ConductorAttentionStore`, protocol create/list/focus/focusLatest/markRead/clear/test, toolbar notification panel, workspace/sidebar/tab unread indicators, banner failure toast, settings permission-state row plus test action, duplicate coalescing test, terminal desktop-notification escape ingestion, background non-agent command-finished events, system-banner attempts for terminal attention events, agent-reply banner click-through to stored events, pure delivery-policy tests for every abstract permission outcome, and notification/control-smoke coverage for store/show/jump/read/focus/test plus background failed-command focus. | Add end-to-end `.app` automation for every real macOS authorization state. |
| D. Browser Surfaces | L2 positive and negative fixture coverage plus explicit restore. | Protocol open/select/navigate/reload/stop/back/forward plus bounded `browser.snapshot`, visible-viewport PNG `browser.screenshot`, basic `browser.click/fill/press/wait/find/evaluate` against the visible WebKit tab, local HTML fixture coverage in `control-smoke.sh`, typed `automationError` details for common selector/text/script/timeout/frame failures, wait conditions for load/ready, selector/visible, text, URL, title, idle/network-idle, hidden, and gone/detached states, safe frame summaries with same-origin text/counts and explicit inaccessible-frame reasons, same-origin frame target routing via `frame-N >> selector` for click/fill/press/wait, frame-aware `browser.find`, `browser.evaluate --frame frame-N`, JS alert/confirm/prompt sheets, persisted browser download state with toolbar/reveal UI and surface-list diagnostics, recent console/error/unhandled-rejection runtime events persisted on web tabs, cleared on navigation/reload/history movement, and exposed through snapshot/surface/session-inspect diagnostics plus a compact toolbar error menu, local `.bin` download fixture coverage, runtime-error fixture coverage including clean-navigation reset, browser protocol stress for 10 tabs with same-origin frame automation on each tab, and dogfood verification that a restored browser tab can be selected, inspected, scrolled, and moved through explicit restored history. | Add safe-bridge hardening, cross-origin action routing, long-running/browser-scale stress, richer per-event source mapping, broader history/scroll coverage, and true no-reload restoration. |
| E. Workspace Intelligence | L2 foundation live. | `WorkspaceMetadataSnapshot`, `WorkspaceMetadataService`, `workspace.metadata`, `ConductorCLI workspace metadata`, selected and non-selected workspace smoke coverage for counts/health plus terminal/file/web arrays and live localhost dev-server summaries, sidebar and top-tab consumption of cached root/port/health/unread metadata with native hover details, top-tab root/port context actions, model-backed synchronized editor buffers for file tabs, and a workspace panel inspector with terminal summaries, workspace-owned file/web lists, local service quick-open, cross-workspace tab jump, switch/port/Finder actions. | Add richer per-tab actions, capture real-agent context, and prove scoped refresh does not hurt scroll/switch budgets. |
| F. Command Layer | L2 foundation live. | `ConductorShellCommand` canonical metadata registry, registry-generated command palette, command outcome descriptions, browser back/forward commands, file external-open/reveal commands, workspace rename/duplicate/close-other/close-right/close-current/open-root/open-service commands, high-frequency toolbar/sidebar/web/file/workspace/search actions routed through `performCommand`, top file/web/workspace tab context actions selecting their target before command execution, workspace overview/inspector root and first-service actions routed through commands, macOS menu entries for web back/forward, current-file open/reveal, workspace rename/close/root/service actions with eleven-item selector-to-command autorun coverage, recent-command memory, current-context ranking, ranking badges/tooltips, `command.list` metadata/disabled reasons/ranking, `command.run` disabled-reason errors, shortcut preferences, shortcut profile import/export UI plus autorun coverage, control smoke metadata/ranking/web/file/workspace-command coverage including `rename-workspace`, and shell-panel shortcut-containment autorun coverage for settings, command palette, workspace overview, notifications, and terminal search. | Remaining row-specific toolbar/sidebar/context action audit and broader native menu coverage. |
| G. Native UX Polish | L1 visual passes exist. | Shared design files and recent polish work. | Token audit, scroll/drag/hover audit, panel consistency, theme screenshot matrix. |
| H. Updates | L2 safety fixture live. | GitHub updater and package scripts, hourly automatic checks with repeated-failure diagnostics, control update commands, transient manifest override, temporary update directory override, and `update-fixture.sh` available/download/progress/cancel/install-rehearsal/tamper coverage. | Top chrome progress UX, speed/retry UX, release notes UI, and destructive replacement/relaunch rehearsal. |
| I. Observability & QA | L1/L2 partial. | Model check, filtered tests, `check-conductor.sh`, `dogfood-workbench.sh`, `stress-conductor.sh`, `update-fixture.sh`, control smoke, diagnostics method, redacted diagnostics bundle export, recent errors, main-thread stalls, UI/control/update/scroll budget samples, performance coverage report, dogfood and update-check performance threshold gates, release-gate screenshot capture, and fake-agent non-dry-run resume execution. | Full unskipped gate run and real external-agent dogfood. |
| J. Documentation | L1/L2 documentation foundation. | Plan, design, matrix, contract, README update, getting started, API, notifications, session restore, updating, security, troubleshooting, and current-build release screenshots. | Fresh-user rehearsal, video/GIF, final public copy pass. |

## Track A Contract: Control Protocol

### Human Behavior

The user can drive the workbench from a shell without relying on AppleScript or screen scraping. UI and CLI actions mutate the same model, so automation never creates a hidden parallel state.

### Required Surface

- App: ping, version, status, diagnostics, graceful quit.
- Workspace: list, create, select, rename, duplicate, close.
- Surface: list, focus, split, close, zoom, move.
- Terminal: send text, send key, visible text, cwd, title, rename.
- Browser: open, select, navigate, reload, stop, back, forward, snapshot, screenshot, click, fill, press, wait, find, evaluate.
- Notification: create, list, mark read, clear, focus latest, focus by ID.
- Update: check, status, download, cancel, rehearse-install, install.
- Command: list, run.
- File: open, reveal, save, snapshot.

### Data And Protocol

- Unix domain socket only. No remote listener.
- Newline-delimited JSON with request ID and typed errors.
- Socket path defaults to Application Support and supports `CONDUCTOR_CONTROL_SOCKET_PATH` for isolated testing.
- CLI prints JSON by default so scripts can parse it.
- Invalid targets return typed errors, never crashes.

### Failure States

- App not running.
- Stale socket.
- Target not found.
- Disabled command.
- Invalid params.
- Permission unavailable.
- Operation timed out.

### Verification

- Unit: control request/response round trip, method catalog, default and override socket path.
- Smoke: isolated app + CLI creates workspace, splits panes, sends terminal input, opens/navigates browser, creates/lists/focuses/clears notification.
- Negative: bogus IDs return `target_not_found` with details.

## Track B Contract: Session Life

### Human Behavior

The user can quit, crash, update, and relaunch without losing orientation. If something cannot be restored, the app explains exactly what survived and what did not.

### Required Surface

- Restore workspaces, selected workspace, selected content tab, terminal panes, browser tabs, file tabs, notification unread state, update state, and user settings.
- Preserve terminal identity and useful scrollback snapshot.
- Preserve browser URL/title/favicon/history/scroll when feasible.
- Provide "Restore Previous Session" from command palette, CLI, and local protocol when a previous snapshot exists.
- Show recovery toast/event only when something actually failed or the previous snapshot was used.

### Data Model

- `WorkspaceMetadataSnapshot` is the canonical compact workspace metadata model.
- `WorkspaceMetadataService` resolves project/root, counts, running
  ports, active agents, unread attention count, health, and refresh time for the
  control protocol.
- `ConductorWindowModel.controlWorkspaceMetadataContexts()` feeds selected and
  non-selected workspace context without making the UI parse scattered state.
- `workspace.metadata` and `ConductorCLI workspace metadata [--workspace
  workspace-id]` expose this data plus terminal/file/web arrays for dogfood,
  sidebar rows, inspectors, and future automation.
- `WorkspaceChromeSnapshot` reads the cached snapshots so sidebar rows can show
  project root, first running port, health state, active agents, and unread work
  without running port scans in SwiftUI body evaluation.
- The workspace panel uses the same cached model for a list-plus-inspector
  surface: root, health, refresh time, terminal summaries, workspace-owned
  file/web tab lists, unread attention, active agents, workspace switch,
  cross-workspace tab jump, first detected port open, and Finder root open.
- Top workspace tabs use the cached snapshot for first-port pills on
  selected/hovered tabs, a compact health warning when metadata is
  partial, native hover detail, and context-menu actions for root/port opening.

### Verification

- `control-smoke.sh` checks selected-workspace metadata returns one workspace,
  at least one terminal, a health value, and terminal/file/web summaries that
  match the live smoke fixture. It also creates a second workspace, opens a file
  and web tab there, switches away, and verifies that non-selected workspace
  metadata still exposes its own file/web summaries.
- `CONDUCTOR_WORKSPACE_AUTORUN=1` verifies user-facing workspace activation
  from the same-workspace path and cross-workspace path returns to the terminal
  workbench after a file tab has been selected, while preserving the opened file
  tab for direct selection.

- Compact snapshot remains the stable state file.
- Append-only session journal records semantic workspace, terminal, browser, file, snapshot, and restore events.
- File-tab mutations trigger persistence so a just-opened file is not lost on ordinary relaunch.
- Terminal title/cwd and bounded VT/plain scrollback snapshots are restored through the ordinary relaunch dogfood path; snapshots replay after the fresh Ghostty surface is attached and never through the shell input path.
- `session.restorePrevious`, `ConductorCLI session restore-previous`, and the command palette action replace the current in-memory workbench with the previous valid compact snapshot, then preserve the pre-restore current snapshot as the new previous snapshot during save.
- When compact snapshots are missing or invalid, journal replay can rebuild a
  workspace skeleton from semantic events and reports `restoredFromJournal`.
- Supported-agent resume metadata can be used explicitly through the terminal
  context menu, `terminal.resumeAgent`, command-palette "Resume Workspace
  Agents", and `terminal.resumeAgents`; batch availability checks use persisted
  snapshots rather than focusing terminals to scrape visible text.
- Restored Agent/command terminals expose `process.status ==
  fresh-after-restore`, `process.reattached == false`, and the
  `terminal_process_restarted` recovery issue so users understand that the
  context returned but the original process did not.
- Previous valid compact snapshot is retained for fallback.
- Restore summary records snapshot source, attempted paths, failed paths, original/restored/dropped workspace/web/file counts, missing file paths, and fallback source.
- Fallback/failure creates a user-visible startup toast plus an in-app `sessionRecovery` event with restored/dropped counts, missing file paths, and failed-path details.

### Failure States

- State file unreadable.
- Journal partially corrupt.
- Previous snapshot missing.
- Terminal process cannot be reattached.
- Browser interaction state rejected by WebKit.
- File tab target disappeared.

### Verification

- Corrupt latest state file; relaunch must recover or explain.
- Gracefully quit during multiple terminals, browser tabs, file tabs, and unread attention events; relaunch restores the selected workspace, visible work surface, terminal title/cwd, and readable terminal output.
- Unit tests for journal append, rotation, legacy ID decode, and replay.
- Isolated launch smoke verifies a temporary journal with no compact snapshot
  restores two workspaces, one web tab, and reports `restoredFromJournal` through
  `ConductorCLI session inspect --json`.
- Diagnostics include journal path/count/latest event and restore summary.
- `session.inspect` and `ConductorCLI session inspect` return a human-readable recovery model with current object counts, restore health, recent journal events, terminal/browser/file surface checks, structured surface issues, severity counts, affected target IDs, restored-terminal process status, and recommended next actions.
- `dogfood-workbench.sh` must first verify normal relaunch with `sessionRestore.state == restored`, selected workspace, restored web/file/unread counts, exact restored browser URL, browser page text after `browser.select`, restored scroll position, explicit browser back/forward fallback, restored terminal title/cwd/readable output, restored supported-agent resume command/session ID, `terminal resume-agent --dry-run`, `terminal resume-agents --workspace current --dry-run`, non-dry-run `terminal resume-agents --workspace current` against a local fake supported-agent binary, `process.status == fresh-after-restore`, `terminal_process_restarted`, and restored file surface. It must also read terminal/browser/file IDs from `session inspect` after relaunch and prove each restored surface can be focused through `surface focus`. It must then mutate the current workspace, run `session restore-previous`, verify `restoredFromPrevious` and the previous selected workspace, then verify `sessionRestore.state == restoredFromPrevious`, a reported missing file path, and a matching `sessionRecovery` event after corrupting the current snapshot.

## Track C Contract: Attention System

### Human Behavior

A notification is a navigable event, not just a sound. The user can tell what happened, where it happened, whether it is unread, and how to jump to it.

### Required Surface

- In-app event store independent of macOS banners.
- Notification panel with unread/read groups.
- Top-toolbar unread entry point for the notification panel.
- Workspace/sidebar/tab unread indicators.
- Jump latest unread.
- Mark current workspace read.
- Clear one, clear read, clear all.
- Small in-app toast when banners are denied or unavailable.
- Settings state for allowed, denied, not requested, unavailable outside app bundle.

### Data Model

`ConductorAttentionEvent` stores ID, timestamp, kind, severity, title, body, workspace ID, terminal ID, web tab ID, source, read state, and details.

### Failure States

- macOS banners denied.
- macOS banners not requested.
- App launched in a context where banners cannot be registered reliably.
- Notification target no longer exists.
- Duplicate burst suppressed.
- Store write failed.

### Verification

- Unit: attention store persists, lists newest first, marks read, clears, limits old events, and coalesces unread duplicate terminal events.
- Protocol: create/list/focus/clear returns stable JSON.
- Smoke: create notification, parse ID, list, focus by ID, clear by ID, clear all.
- Autorun: create a terminal-targeted in-app event in an isolated state path,
  open the notification panel, focus the event, verify unread state clears, keep
  the panel open, and return focus to the target terminal.
- Permission matrix: authorized, denied, not determined, `.app`, debug launch.

## Track D Contract: Browser Surfaces

### Human Behavior

Browser tabs are real work surfaces for humans and agents. A user can browse normally; a script can inspect and act on the visible page without inventing hidden browser state.

### Required Surface

- Address/search with DuckDuckGo query fallback.
- Loading, complete, failed, blocked, and crashed states.
- Title and favicon cache.
- Back/forward/reload/stop.
- Find in page.
- Snapshot, screenshot, click, fill, press, find, evaluate, wait.
- Copy markdown reference.
- Browser history menu.
- Native JS alert/confirm/prompt handling.
- Download state with destination, completion/failure feedback, and Finder reveal.

### Data And Safety

- Snapshots are bounded and redacted.
- Snapshot includes visible text, links, buttons, fields, selected text, URL, title, and safe frame summaries.
- Automation uses stable refs from latest snapshot when possible.
- Cookies, passwords, and storage are never dumped in normal snapshots.
- JavaScript evaluation is explicit and documented.

### Failure States

- Selector/ref missing.
- Cross-origin script failure.
- Page load timeout.
- Dialog blocks automation.
- Download starts.
- Web content process crashes.
- Permission or content blocker prevents access.

### Verification

- Local fixture opens, fills an input, clicks a button, waits for text, snapshots DOM, screenshots page.
- Negative fixture returns typed errors.
- Download state persists with web tab state and appears in `surface.list`; `control-smoke.sh` opens a local binary fixture, waits for `download.phase == finished`, verifies the destination exists, and removes the downloaded file.
- Relaunch restores browser tabs without surprise reload loops; current-page restore is verified by selecting the restored tab and waiting for known page text. The dogfood fixture also verifies restored scroll position and explicit back/forward fallback after relaunch. True no-reload WebKit session restoration still needs a separate passing gate.

## Track E Contract: Workspace Intelligence

### Human Behavior

The user can glance at the sidebar/top chrome and understand project, path, ports, active agents, terminal/web/file counts, and unread work without opening a dashboard.

### Required Surface

- Compact workspace rows.
- Project title and shortened path.
- Running port/local service indicator and quick open.
- Agent state indicator.
- Unread badge.
- Hover detail for full path, ports, agents, and latest attention event.
- Workspace inspector for deeper state.

### Data Model

`WorkspaceMetadataSnapshot` includes workspace ID, root URL, project name, running ports, local dev-server summaries, active agents, unread count, last activity, health state, and compact terminal/file/web summaries.

### Failure States

- Port scan unavailable.
- Workspace root deleted.
- Agent state unknown.

### Verification

- Metadata readers run off main thread with timeout.
- Smoke fixtures prove local service summaries can be discovered and opened from workspace context.
- Terminal scroll and workspace switch stay inside budgets while metadata updates.
- Screenshot audit proves rows are compact and understandable.

## Track F Contract: Command And Shortcuts

### Human Behavior

Power users can drive everything from keyboard; new users can discover what every action does.

### Required Surface

- Canonical command registry with catalog ID, category, title, outcome description, icon, shortcut fallback, protocol method, and keywords.
- Command palette with categories, descriptions, shortcuts, disabled reasons, keyboard flow, recents, and context ranking.
- User shortcut recorder.
- Clear, restore default, import/export shortcut profile.
- Conflict detection and reserved shortcut warnings.
- Modal shortcut containment.

### Failure States

- Command disabled in current context.
- Shortcut conflicts with existing command.
- Shortcut reserved by macOS.
- Shortcut recorder loses focus.
- Panel shortcuts leak into background.

### Verification

- `command.list` exposes title, category, description, protocol method, shortcut, icon, enabled state, disabled reason, and the ranking model used by the command palette.
- After a command runs, `control-smoke.sh` verifies that `command.list` reports that command with `ranking.recentRank == 0` and a recent badge.
- Browser back/forward are canonical commands (`web-back` and `web-forward`), and `control-smoke.sh` verifies both remain exposed through `command.list`.
- Shortcut profiles can be imported/exported as versioned JSON. The shortcut-profile autorun verifies unknown commands are ignored, Cmd-Q is rejected, conflicts are resolved, and the exported profile contains only valid custom shortcuts.
- Every toolbar/sidebar/context action maps to a command.
- Opening settings, command palette, workspace overview, notifications, and terminal search prevents unrelated global shortcuts from changing hidden tabs or terminals; the shell-panel autorun synthesizes Cmd-T, Cmd-W, Cmd-D, Cmd-N, Cmd-K, Cmd-O, and Cmd-F and requires `shortcut-blocked=true`.
- Recorder tests conflict and restore default paths.

## Track G Contract: Native UX Polish

### Human Behavior

The app feels like one macOS product. No giant AI-dashboard panels, mystery icons, clipped text, accidental drags, or blocky interactions.

### Required Surface

- Shared tokens for radius, spacing, color, elevation, focus, disabled, selected, hover, and motion.
- At least ten readable themes implemented as token sets.
- Compact and comfortable density.
- Internal scrolling for every large panel.
- Movable/modeless panels where expected.
- Tooltip/help tag for every icon-only control.
- Stable tab click vs drag thresholds.
- Reduced motion support.

### Failure States

- Text clipping.
- Overlapping controls.
- Unreachable panel content.
- Hover help missing.
- Selection indicator inconsistent with theme.
- Accidental drag on click.
- Terminal scroll redraw should not feel blocky; precise trackpad wheel events and scrollbar updates are coalesced into short frame windows, while mouse-wheel scrolling remains immediate.

### Verification

- Screenshot matrix for settings, usage, notifications, command palette, toolbar, browser, sidebar.
- Hover audit.
- Motion/token audit.
- Manual click/drag and scroll pass on light/dark/glass themes.

## Track H Contract: Updates And Distribution

### Human Behavior

The user sees a quiet update button when useful, a believable progress state while downloading, and a safe install path. Normal UI hides GitHub/release internals.

### Required Surface

- Top chrome update pill/button.
- Hourly background check with repeated-failure backoff and diagnostics.
- States: checking, up to date, available, downloading, downloaded, installing, failed.
- Progress bar, downloaded bytes, speed when reliable, cancel, retry.
- Release notes.
- SHA-256 and bundle verification.
- arm64 and x86_64 assets.
- Honest ad-hoc signing/Gatekeeper docs if there is no Developer ID.

### Failure States

- No release found.
- Wrong architecture asset missing.
- Download interrupted.
- Checksum mismatch.
- Bundle ID mismatch.
- Codesign/ad-hoc verification issue.
- Replacement failed because app path is not writable.

### Verification

- Mock manifest checks core available/download/failed states through the control protocol.
- `Scripts/update-fixture.sh` slow local-copy simulation proves `downloadProgress.fraction` changes while the download is in flight.
- `Scripts/update-fixture.sh` proves a valid fixture downloads and a tampered asset fails safely.
- Release script validates required assets and checksums before upload.

## Track I Contract: Observability And QA

### Human Behavior

When something is wrong, one diagnostics path should explain it without guesswork.

### Required Surface

- `conductor diagnostics` returns app version, launch mode, socket path, workspace counts, surface counts, session journal summary, attention summary, update state and automatic-check diagnostics, notification permission state, recent control protocol errors, recent main-thread stalls, performance budget targets, recent budget samples, and a performance report summarizing sampled/missing budgets plus recent over-budget samples.
- `conductor diagnostics export` writes a redacted directory bundle with summary JSON, diagnostic logs when available, manifest, and privacy note.
- Release gate script runs build, model check, filtered tests, smoke, session restore, browser fixture, update fixture, and screenshot capture.
- Stress scripts cover long terminal output, resizing, many idle terminals, many web tabs, rapid workspace switching.
- Performance budgets for settings open, palette open, tab switch, scroll, update check, browser restore; terminal wheel events, precise-scroll flushes, and `terminal sample-scroll` feed scroll-frame samples into diagnostics.
- `performance-gate.sh` reads an exported diagnostics summary and enforces required sampled budgets plus over-budget thresholds for dogfood/control-smoke surfaces.

### Failure States

- Diagnostics export path unavailable.
- Log files missing.
- Redaction failed.
- Performance budget exceeded.
- Smoke script cannot start isolated app.

### Verification

- Release gate command exits non-zero on any missing section.
- Dogfood script uses `CONDUCTOR_STATE_PATH` and `CONDUCTOR_CONTROL_SOCKET_PATH` so it never touches user state.
- Shortcut autorun exits non-zero unless shortcut-driven commands leave a valid workspace with three panes, three terminal surfaces, and a zoomed terminal.
- Long-output stress exits non-zero unless three visible split terminals each complete their marker after receiving real terminal input; the default gate requires 196,608 total characters.
- Captured screenshots are current and masked; the standalone screenshot script covers workbench, token records, notifications, browser, command palette, and settings, and `check-conductor.sh` now validates that manifest during the release gate unless screenshot checks are explicitly skipped.

## Track J Contract: Documentation And Onboarding

### Human Behavior

A stranger can install, understand, operate, script, update, and troubleshoot the app without asking the owner.

### Required Docs

- README for external users.
- Getting started.
- Workbench concepts.
- Local control API.
- Browser automation.
- Notifications.
- Session restore.
- Updates.
- Security/privacy.
- Troubleshooting.
- Contributor notes.

### Required Media

- Real screenshots from current app.
- Workbench screenshot.
- Token/usage records screenshot.
- Settings screenshot.
- Notification panel screenshot.
- Browser tab snapshot/screenshot.
- Command palette screenshot.
- Optional short video/gif for workspace creation.
- GitHub activity/trend chart.

### Honesty Rules

- Do not claim L1 features as shipped.
- Do not hide ad-hoc signing limitations.
- Do not show raw internal package names in product-facing docs unless discussing developer internals.
- Do not use fake screenshots.
- Mask emails, local user paths, tokens, and private repo names.

### Verification

- Fresh install rehearsal from README.
- API examples run against debug app.
- Troubleshooting entries map to real diagnostics fields.
- Screenshots are regenerated from current build before release with `Apps/Conductor/Scripts/capture-release-screenshots.sh`.

## Evidence Log

### 2026-06-03

Completed evidence:

- `swift build --product Conductor` passed after Track C and socket override changes.
- `swift build --product ConductorCLI` passed.
- `swift run ConductorModelCheck` passed.
- `./Scripts/swift-test.sh --filter AttentionStore` passed with five tests, including duplicate coalescing.
- `./Scripts/swift-test.sh --filter ControlProtocolTests` passed with five tests.
- Manual isolated live smoke passed using `CONDUCTOR_STATE_PATH=/tmp/.../window-state.yaml` and `CONDUCTOR_CONTROL_SOCKET_PATH=/tmp/.../control.sock`.
- Manual smoke covered ping, status, diagnostics, diagnostics export, recent control error diagnostics, version, workspace list/create/rename, surface list/split/zoom/focus, terminal cwd/title/send/send-key/sample-scroll/visible-text, browser open/navigate/reload/stop, command list, notification create/list/focus/clear/test.
- `control-smoke.sh` supports `CONDUCTOR_SMOKE_SKIP_CLI_BUILD=1`, opens a local browser fixture, and an isolated live run passed browser load, reload, selector wait, snapshot, fill, press, text wait, click, find, evaluate, screenshot, stop, negative typed automation errors (`selector_not_found`, `invalid_selector`, `snapshot_ref_missing`, `not_editable`, `text_not_found`, `script_error`, `promise_unsupported`, `timeout`), plus notification create/list/focus/clear/test.
- `control-smoke.sh` also opens a temporary local file in the workspace, verifies `file.snapshot --text`, writes new text through `file.save --text`, reveals the file in the in-app file manager, snapshots the targeted path, checks typed file failures (`file_not_found`, `file_is_directory`, `file_parent_not_found`, `target_not_found`) with path details, and confirms `terminal sample-scroll` produces a `terminal.scroll-frame` diagnostics sample.
- `TerminalSurface` coalesces precise wheel deltas and scrollbar callbacks to reduce scroll redraw jitter, records `terminal-scroll-coalesced` diagnostics for real precise-scroll batches, and preserves immediate non-precise wheel handling.
- `performance-gate.sh` is wired into `check-conductor.sh` after dogfood diagnostics export. A focused run passed with `performance_gate=ok`, enforcing workspace switch, terminal tab switch, terminal scroll-frame, browser restore, settings open, and command palette open budgets while reporting non-enforced update-check noise separately.
- `update-fixture.sh` now exports diagnostics and runs `performance-gate.sh` with `update.check` as the required/enforced budget. `CONDUCTOR_UPDATE_FIXTURE_SKIP_BUILD=1 ./Scripts/update-fixture.sh` passed with `performance_gate=ok status=partial_coverage sampledBudgets=1 recentSamples=3 overBudget=0`.
- `CONDUCTOR_UPDATE_FIXTURE_SKIP_BUILD=1 ./Scripts/update-fixture.sh` passed against an isolated app, proving update status/check/download/cancel/rehearse-install control methods, transient local manifest use, verified signed local package download, temporary update directory routing, in-flight cancel recovery, dry-run installer staging/codesign verification, and checksum-mismatch failure reporting.
- The update fixture now builds 12 MB uncompressed local packages, including a signed fixture `Conductor.app`, applies `CONDUCTOR_UPDATE_LOCAL_COPY_DELAY_MS` to the isolated app, starts `update download` in the background, polls `update status`, requires at least one visible progress sample before cancelling, verifies the cancelled state remains `available` and `canDownload`, then requires at least two increasing progress samples before accepting the final download and runs an installer dry-run that stages the app, checks the bundle identifier, and verifies strict codesign without replacing the current app.
- Automatic update checks now use a cancellable background loop: after launch they wait briefly, check silently, continue about once per hour while the user preference is enabled and a manifest URL is available, and back off repeated background failures up to about six hours while exposing `automaticChecks` diagnostics through update status and diagnostics export.
- Shortcut autorun now asserts the resulting workspace is valid and exactly matches the intended shortcut-created split/zoom shape instead of trusting a loose success line.
- Long-output stress now targets visible split terminals, sends a real Return key through the terminal host, waits for per-terminal markers, and requires 65,536 characters per target in the default gate.
- The tightened core gate `CONDUCTOR_CHECK_SKIP_BUILD=1 CONDUCTOR_CHECK_SKIP_TESTS=1 CONDUCTOR_CHECK_SKIP_BUNDLE=1 CONDUCTOR_CHECK_SKIP_SCREENSHOTS=1 ./Scripts/check-conductor.sh` passed with dogfood/control-smoke, protocol stress, update fixture, workspace/shell-panel/notification autoruns, shortcut shape validation, and three-target long-output validation.
- The same core gate passed after adding normal relaunch verification to `dogfood-workbench.sh`; it now proves selected workspace, web tabs, exact browser URL, file tabs, unread attention, and restored file surface survive an ordinary restart before it exercises corrupt-state fallback.
- The restore-surface core gate passed with exact browser URL restoration and real terminal command submission wired into the dogfood path.
- `CONDUCTOR_CHECK_SKIP_TESTS=1 CONDUCTOR_CHECK_SKIP_AUTORUN=1 CONDUCTOR_CHECK_SKIP_BUNDLE=1 CONDUCTOR_CHECK_SKIP_SCREENSHOTS=1 ./Scripts/check-conductor.sh` passed with dogfood/control-smoke, terminal scroll-frame budget sampling, `performance_gate=ok`, protocol stress, and the update fixture progress samples wired into the gate.
- `CONDUCTOR_DOGFOOD_SKIP_BUILD=1 ./Scripts/dogfood-workbench.sh` passed after covering the three session-recovery paths: create three workspaces with split terminals, real submitted terminal commands, browser tabs, a file tab, and unread notifications; restart against the same isolated state path; verify `restored`, selected workspace, restored web/file/unread counts, exact browser URL, restored browser text/scroll, restored terminal title/cwd/readable output, and the restored file surface; switch away, run `session restore-previous`, verify `restoredFromPrevious` and the previous selected workspace; then corrupt current state, relaunch, verify previous-snapshot fallback, and confirm a `sessionRecovery` attention event exists.
- External docs were expanded: README, Getting Started, Local Control API, Notifications, Session Restore, Updating, Security, Troubleshooting, and Architecture.

### 2026-06-04

Completed evidence:

- `browser.select <web-tab-id> [--workspace workspace-id]` was added to the local protocol and CLI so scripts can activate an existing or restored web tab before inspecting it.
- The browser fixture now exposes a URL-query driven history marker, letting dogfood prove the restored tab is the exact latest page instead of only counting tabs.
- `dogfood-workbench.sh` now finds the restored browser tab by URL, selects it through the protocol after relaunch, and waits for `History marker: release-2` on the restored page.
- File-tab persistence was tightened so `file.open` publishes workspace content changes and persists immediately when it changes state.
- Browser interaction-state capture now archives non-`Data` WebKit state objects when available and attempts to unarchive them before restoring.
- Web tabs now persist explicit navigation entries, current navigation index, and scroll position. If WebKit's own restored back/forward list is inconsistent, `browser back`/`browser forward` fall back to the explicit history.
- `CONDUCTOR_DOGFOOD_SKIP_BUILD=1 ./Scripts/dogfood-workbench.sh` passed after adding the browser history and scroll restore gate: it scrolls the fixture, relaunches, verifies restored scroll, runs `browser back` to `History marker: release-1`, and runs `browser forward` back to `History marker: release-2`.
- The normal relaunch gate now uses `session inspect` to find restored terminal, browser, and file surfaces, verifies the structured surface issue counters are present, verifies restored Agent terminals report `fresh-after-restore` plus `terminal_process_restarted`, then verifies `surface focus` can activate each one in the restored workspace.
- Settings > Overview now includes a recovery check section that turns restored terminal/browser/file issues into severity-marked rows with a concrete next action and a jump target, while healthy restores show a compact passed check.
- `terminal.agent`, `terminal.resumeAgent`, and `AgentResumeDetector` now expose and act on persisted supported-agent resume metadata. Terminal tab hover/context menu and Settings > Overview surface captured resume commands with jump/copy actions, and the terminal tab context menu can explicitly resume supported agents. The dogfood restore path prints a Codex resume hint, verifies `terminal agent` captures it before relaunch, then verifies the same session ID, resume command, `terminal resume-agent --dry-run`, current-workspace batch dry-run, and current-workspace batch execution result after relaunch. The execution check uses a local fake supported-agent binary, so it proves terminal command delivery without network or token use.
- Non-agent background command completion now enters the in-app attention system: the Ghostty config enables command-finish reporting with app-layer filtering, so failed unattended commands and commands that run at least 30 seconds create `commandFinished` events with terminal target, exit code, duration, reason, coalescing, diagnostics, and user-attention requests. `control-smoke.sh` drives a real background terminal `sleep 0.4; false`, waits for the `terminal-command` notification, and focuses it back to the originating terminal.
- True no-reload WebKit session restoration is still not claimed; the shipped evidence is explicit, user-useful recovery of URL/history/scroll context.

Known evidence gaps:

- Full `swift test` remains expensive because the package rebuilds the imported usage module and macro targets. Release gates should use focused tests plus a separate nightly/full run until package boundaries are optimized.
- Full end-to-end macOS permission-state automation is not complete yet; the store, protocol, panel, workspace unread indicators, banner-failure toast, settings permission row plus test action, pure delivery-policy state coverage, duplicate coalescing, terminal desktop-notification escape ingestion, background command-finished events, system-banner attempts for terminal attention events, and agent-reply banner click-through are live.
- True no-reload browser restore and terminal process reattachment are not implemented yet. Session journal replay now restores a workbench skeleton when compact snapshots are missing or invalid, and the restore inspector exists as a structured Settings > Overview recovery check plus `session inspect` surface issue model that explicitly reports fresh restored terminal processes, but it still needs broader real-world failure coverage.
- Browser DOM automation and bounded waits are implemented for snapshot refs, CSS selectors, same-origin frame targets, load/ready, visible element, text, URL, title, idle/network-idle, hidden, and gone/detached conditions, with positive local fixture smoke coverage and negative typed `automationError` smoke coverage for common selector/text/script/timeout/frame failures. Browser snapshots include safe frame summaries for same-origin and inaccessible frames, `browser.find` searches same-origin frames, and `browser.evaluate --frame frame-N` evaluates inside accessible frame documents. `Scripts/stress-conductor.sh` now runs same-origin frame automation across 10 browser tabs. Typed product UI, cross-origin action routing, long-running/browser-scale stress, and safe-bridge hardening are not complete yet.
- Public media still needs optional video/GIF capture and a final external copy pass.
